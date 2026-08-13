#!/bin/bash
# Dual-mode + multi-call dispatch tests
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }

# 1) Sourcing executes nothing and does not enable set -e in the caller
out=$(bash -c 'set +e; source "'"$REPO_DIR"'/bin/git-issue"; [[ $- == *e* ]] && echo "E_LEAK"; echo "SRC_OK"')
[[ "$out" == "SRC_OK" ]] && ok "sourcing is silent and set -e does not leak" \
                         || bad "sourcing produced output or leaked set -e: '$out'"

# 2) Sourcing defines the core functions
bash -c 'source "'"$REPO_DIR"'/bin/git-issue"; declare -f read_issue_data trim_ws status_report main >/dev/null' \
    && ok "core functions defined after sourcing" || bad "functions missing after sourcing"

# 3) A symlink named git-issue-status dispatches to the status report and renders listing
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
cd "$WORK" && git init -q && git config user.name T && git config user.email t@t.co
git commit -q --allow-empty -m init
ln -s "$REPO_DIR/bin/git-issue" "$WORK/git-issue-status"
"$REPO_DIR/bin/git-issue" create "status listing smoke" >/dev/null 2>&1
"$WORK/git-issue-status" 2>/dev/null | grep -q "Issue Status Report" \
    && ok "symlink dispatches to status report" || bad "symlink did not dispatch to status report"
"$WORK/git-issue-status" 2>/dev/null | grep -q "status listing smoke" \
    && ok "symlink rendering includes created issue" || bad "symlink listing did not render issue"

# 4) Normal invocation still dispatches commands
"$REPO_DIR/bin/git-issue" create "dispatch smoke" >/dev/null 2>&1
"$REPO_DIR/bin/git-issue" list 2>/dev/null | grep -q "dispatch smoke" \
    && ok "direct invocation dispatches main" || bad "direct invocation broken"

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
