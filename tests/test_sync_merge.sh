#!/usr/bin/env bash
# Multi-user sync and history (docs/plans/2026-10-11-multi-user-sync-design.md).
# Clones A and B of one bare remote R, as two people sharing issues.
# Usage: tests/test_sync_merge.sh [test_name...]   (default: every test)

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"
GI="$SCRIPT_DIR/bin/git-issue"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
TESTS_RUN=0
TESTS_PASSED=0

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/git-issue-sync-test.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global init.defaultBranch main

# check <name> <command...>: pass when the command exits 0
check() {
    local name="$1"; shift
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$@"; then
        echo -e "  ${GREEN}PASS${NC} $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}FAIL${NC} $name"
    fi
}

# A fresh bare remote R and clones A (Alice) and B (Bob), sync enabled in each
setup_pair() {
    local d="$ROOT/$1"
    rm -rf "$d"; mkdir -p "$d"
    R="$d/R.git"; A="$d/A"; B="$d/B"
    git init -q --bare "$R"
    git clone -q "$R" "$A" 2>/dev/null
    (cd "$A" && git config user.name Alice && git config user.email alice@example.com \
        && echo x > README && git add README && git commit -qm init && git push -q origin main 2>/dev/null)
    git clone -q "$R" "$B" 2>/dev/null
    (cd "$B" && git config user.name Bob && git config user.email bob@example.com)
    (cd "$A" && git issue setup-sync enable >/dev/null 2>&1)
    (cd "$B" && git issue setup-sync enable >/dev/null 2>&1)
}
in_A() { (cd "$A" && "$@"); }
in_B() { (cd "$B" && "$@"); }
new_issue() { GIT_ISSUE_PORCELAIN=1 git issue create "$@" 2>/dev/null | tail -1; }
ref_sha() { git rev-parse -q --verify "refs/notes/issue-$1" 2>/dev/null; }

# --- Task 1: compare-and-swap writes ---------------------------------------

test_concurrent_comments_all_kept() {
    setup_pair t1a
    cd "$A"
    local id i n=8
    id=$(new_issue "Race")
    for ((i = 1; i <= n; i++)); do git issue comment "$id" "c$i" >/dev/null 2>&1 & done
    wait
    local shown missing=0
    shown=$(git issue show "$id" 2>/dev/null)
    for ((i = 1; i <= n; i++)); do grep -q "c$i\$" <<< "$shown" || missing=$((missing + 1)); done
    check concurrent_comments_all_kept test "$missing" -eq 0
}

test_noop_edit_writes_nothing() {
    setup_pair t1b
    cd "$A"
    local id other before after
    id=$(new_issue "Relates")
    other=$(new_issue "Other")
    git issue dep add "$id" relates_to "$other" >/dev/null 2>&1
    before=$(git rev-list --count "refs/notes/issue-$id")
    git issue dep add "$id" relates_to "$other" >/dev/null 2>&1
    after=$(git rev-list --count "refs/notes/issue-$id")
    check noop_edit_writes_nothing test "$before" -eq "$after"
}

test_create_never_overwrites() {
    setup_pair t1c
    cd "$A"
    local id before rc
    id=$(new_issue "Keep me")
    before=$(ref_sha "$id")
    rc=$(bash -c 'source "$1"; write_issue_data "$2" "id: $2
v: 2
title: clobber" "" >/dev/null 2>&1; echo $?' _ "$GI" "$id")
    check create_never_overwrites test "$rc" = 75 -a "$(ref_sha "$id")" = "$before"
}

# --- Task 2: the dependency index is local ---------------------------------

test_edge_index_ref_is_local() {
    setup_pair t2a
    cd "$A"
    local a b
    a=$(new_issue "Blocker"); b=$(new_issue "Blocked")
    git issue dep add "$a" blocks "$b" >/dev/null 2>&1
    check edge_index_ref_is_local \
        bash -c 'git rev-parse -q --verify refs/issue-local/dep-graph >/dev/null && ! git rev-parse -q --verify refs/notes/dep-graph >/dev/null'
}

test_legacy_edge_ref_ignored() {
    setup_pair t2b
    cd "$A"
    local a b blob tree commit
    a=$(new_issue "Real"); b=$(new_issue "Other")
    git issue dep add "$a" relates_to "$b" >/dev/null 2>&1
    # A legacy index that looks current (marker in the future), so only
    # reading it, not rescanning headers, could surface the bogus edge
    blob=$(printf '%s\n' "last_rebuilt_from: 2999-01-01T00:00:00Z" "$a blocks deadbee" | git hash-object -w --stdin)
    tree=$(printf '100644 blob %s\tedges\n' "$blob" | git mktree)
    commit=$(git commit-tree "$tree" -m legacy </dev/null)
    git update-ref refs/notes/dep-graph "$commit"
    check legacy_edge_ref_ignored bash -c "! git issue deps '$a' 2>&1 | grep -q deadbee"
}

# --- Task 3: the tracking namespace ----------------------------------------

# push_issue <id> [<remote>]: push one issue ref by hand, past the hooks
push_issue() { GIT_ISSUE_PUSHING_NOTES=1 git push -q "${2:-origin}" "refs/notes/issue-$1:refs/notes/issue-$1" 2>/dev/null; }

test_fetch_leaves_local_issue() {
    setup_pair t3a
    local id a_sha b_sha
    id=$(in_A new_issue "Shared")
    in_A push_issue "$id"
    in_B git fetch -q origin "refs/notes/issue-$id:refs/notes/issue-$id"
    in_B git issue comment "$id" "from Bob" >/dev/null 2>&1
    in_B push_issue "$id"
    b_sha=$(in_B ref_sha "$id")
    in_A git issue comment "$id" "from Alice, unpushed" >/dev/null 2>&1
    a_sha=$(in_A ref_sha "$id")
    in_A git fetch -q origin 2>/dev/null
    check fetch_leaves_local_issue test "$(in_A ref_sha "$id")" = "$a_sha" \
        -a "$(in_A git rev-parse -q --verify "refs/issue-remotes/origin/issue-$id")" = "$b_sha"
}

test_migration_replaces_forced_refspec() {
    setup_pair t3b
    cd "$A"
    git config --unset-all remote.origin.fetch 'refs/(notes|issue)' 2>/dev/null
    git config --add remote.origin.fetch '+refs/notes/*:refs/notes/*'
    local before after left
    before=$(GIT_ISSUE_PORCELAIN=1 git issue setup-sync status | awk -F'\t' '$1=="unsafe-fetch"{print $2}')
    git issue setup-sync enable >/dev/null 2>&1
    after=$(GIT_ISSUE_PORCELAIN=1 git issue setup-sync status | awk -F'\t' '$1=="unsafe-fetch"{print $2}')
    left=$(git config --get-all remote.origin.fetch | grep -c ':refs/notes/' || true)
    check migration_replaces_forced_refspec test "$before" = true -a "$after" = false -a "$left" = 0
}

test_non_origin_remote() {
    setup_pair t3c
    cd "$A"
    git remote rename origin forgejo
    git issue setup-sync enable >/dev/null 2>&1
    check non_origin_remote bash -c "git config --get-all remote.forgejo.fetch | grep -qxF '+refs/notes/issue-*:refs/issue-remotes/forgejo/issue-*'"
}

# ---------------------------------------------------------------------------

ALL_TESTS=$(declare -F | awk '$3 ~ /^test_/ {print $3}')
if [[ $# -gt 0 ]]; then ALL_TESTS=$(printf 'test_%s\n' "$@"); fi
echo "git-issue multi-user sync tests"
for t in $ALL_TESTS; do (set +e; "$t"); r=$?; done 2>&1 | tee "$ROOT/out"
TESTS_RUN=$(grep -c 'PASS\|FAIL' "$ROOT/out")
TESTS_PASSED=$(grep -c 'PASS' "$ROOT/out")
echo "$TESTS_PASSED/$TESTS_RUN passed"
[[ "$TESTS_PASSED" -eq "$TESTS_RUN" ]]
