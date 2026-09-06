#!/usr/bin/env bash
# Porcelain output tests — draft-ndn-porcelain-output-00.
# Each section names the requirement IDs it covers. The RFC's transcripts
# are the conformance corpus; these assertions are the faster unit layer
# and cover edge cases the transcripts do not.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GI="$REPO_DIR/bin/git-issue"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
eq()  { # eq <label> <want> <got>
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1"$'\n'"      want: $2"$'\n'"      got:  $3"; fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK" XDG_CONFIG_HOME="$WORK/.config" GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_ISSUE_PORCELAIN
git config --global user.name conformance
git config --global user.email conformance@rfc

# fresh_repo <name>: create and enter an empty repository with one commit.
fresh_repo() {
    local d="$WORK/$1"
    rm -rf "$d"; mkdir -p "$d"; cd "$d"
    git init -q; git commit -q --allow-empty -m init
}
# porcelain_ids: ids of all issues, one per line, in list order.
porcelain_ids() { "$GI" list --porcelain | cut -f2; }

echo "Testing flag position and version [R-flag-position] [R-version-frozen]"
fresh_repo flag
"$GI" create "alpha task" >/dev/null 2>&1
eq "flag before subcommand" "alpha task" "$("$GI" --porcelain list | cut -f12)"
eq "flag after subcommand"  "alpha task" "$("$GI" list --porcelain | cut -f12)"
eq "explicit v1"            "alpha task" "$("$GI" list --porcelain=v1 | cut -f12)"
eq "v2 rejected" \
   "Error: unsupported porcelain version 'v2' (supported: v1)" \
   "$("$GI" list --porcelain=v2 2>&1 || true)"
set +e; "$GI" list --porcelain=v2 >/dev/null 2>&1; rc=$?; set -e
eq "v2 exit status" "1" "$rc"

echo "Testing plain stdout [R-plain-stdout]"
fresh_repo plain
eq "empty list is empty stdout" "0" "$("$GI" list --porcelain | wc -c | tr -d ' ')"
eq "empty list is silent on stderr" "" "$("$GI" list --porcelain 2>&1 >/dev/null)"
eq "no banner under --porcelain" "0" "$("$GI" list --porcelain 2>&1 | grep -c 'Using current' || true)"

echo "Testing batch stream shape (internal) [R-issue-line] [R-field-normalize]"
fresh_repo stream
"$GI" create "$(printf 'tab\there')" >/dev/null 2>&1
# Sourcing the script exposes its functions without running the entry
# point (the guard at the bottom checks BASH_SOURCE[0] == $0).
stream=$(cd "$WORK/stream" && bash -c "source '$GI' 2>/dev/null; _issue_tsv_stream")
eq "stream has eleven fields" "11" "$(printf '%s' "$stream" | awk -F'\037' '{print NF}')"
eq "tab in title becomes a space" "tab here" "$(printf '%s' "$stream" | cut -d $'\037' -f3)"
eq "updated is the eighth field" "1" "$(printf '%s' "$stream" | cut -d $'\037' -f8 | grep -c 'T.*Z')"

echo "Testing issue lines [R-issue-line] [R-issue-line-shared] [R-plain-stdout]"
fresh_repo lines
"$GI" create "alpha task" >/dev/null 2>&1
"$GI" create "beta task"  >/dev/null 2>&1
a=$("$GI" list --porcelain | awk -F'\t' '$12=="alpha task"{print $2}')
b=$("$GI" list --porcelain | awk -F'\t' '$12=="beta task"{print $2}')
"$GI" update "$b" --role=dev >/dev/null 2>&1
"$GI" dep add "$a" blocks "$b" >/dev/null 2>&1
eq "twelve columns" "12" "$("$GI" list --porcelain | head -1 | awk -F'\t' '{print NF}')"
eq "repo column empty, title last" "|open|medium|conformance||||alpha task" \
   "$("$GI" list --porcelain | awk -F'\t' -v a="$a" '$2==a' | cut -f1,3-6,10-12 | tr '\t' '|')"
eq "blocks and depends_on columns" "blocked  A beta task"$'\n'"open B  alpha task" \
   "$("$GI" list --porcelain | awk -F'\t' -v a="$a" -v b="$b" '{ gsub(a,"A"); gsub(b,"B"); print $3, $8, $9, $12 }' | sort)"
eq "no ANSI in porcelain list" "0" "$("$GI" list --porcelain | grep -c "$(printf '\033')" || true)"
eq "ready: only unblocked, twelve columns" "12 alpha task" "$("$GI" ready --porcelain | awk -F'\t' '{print NF, $12}')"
eq "ready: no header or (none) on stdout" "" "$(cd "$WORK/lines" && "$GI" ready --porcelain --role=nobody)"
eq "queue: filtered by role" "" "$("$GI" queue dev --porcelain)"
eq "topo: order without rank numbers" "12 alpha task"$'\n'"12 beta task" "$("$GI" topo --porcelain | awk -F'\t' '{print NF, $12}')"
eq "topo: empty repo is empty stdout" "0" "$(fresh_repo lines-empty >/dev/null; "$GI" topo --porcelain | wc -c | tr -d ' ')"

echo "Testing repo column under --all [R-all-column]"
fresh_repo agg-a
"$GI" create "alpha task" >/dev/null 2>&1
"$GI" repo add agg-a "$WORK/agg-a" >/dev/null 2>&1
cd "$WORK"
eq "--all fills column 1" "agg-a|open|alpha task" "$("$GI" list --all --porcelain 2>/dev/null | cut -f1,3,12 | tr '\t' '|')"
eq "--all has no bracket prefix" "0" "$("$GI" list --all --porcelain 2>/dev/null | grep -c '^\[' || true)"
eq "--repo leaves column 1 empty" "|open|alpha task" "$("$GI" --repo agg-a list --porcelain | cut -f1,3,12 | tr '\t' '|')"
eq "ready --all fills column 1" "agg-a" "$("$GI" ready --all --porcelain 2>/dev/null | cut -f1)"
"$GI" repo rm agg-a >/dev/null 2>&1

echo "Testing edge lines [R-edge-line]"
fresh_repo edges
"$GI" create "alpha task" >/dev/null 2>&1
"$GI" create "beta task"  >/dev/null 2>&1
a=$("$GI" list --porcelain | awk -F'\t' '$12=="alpha task"{print $2}')
b=$("$GI" list --porcelain | awk -F'\t' '$12=="beta task"{print $2}')
"$GI" dep add "$a" blocks "$b" >/dev/null 2>&1
norm() { awk -F'\t' -v a="$a" -v b="$b" '{ gsub(a,"A"); gsub(b,"B"); print }'; }
eq "deps: both directions, tab-separated" "A	blocks	B"$'\n'"B	depends_on	A" "$("$GI" deps --porcelain | norm | sort)"
eq "deps <id>: edges from that id" "A	blocks	B" "$("$GI" deps "$a" --porcelain | norm)"
eq "dep list <id>: same shape" "B	depends_on	A" "$("$GI" dep list "$b" --porcelain | norm)"
eq "dep list: all edges" "2" "$("$GI" dep list --porcelain | wc -l | tr -d ' ')"
eq "deps: no marker line leaks" "0" "$("$GI" deps --porcelain | grep -c last_rebuilt || true)"
eq "deps: empty graph is empty stdout" "0" "$(fresh_repo edges-empty >/dev/null; "$GI" deps --porcelain | wc -c | tr -d ' ')"

echo "Testing reference lines [R-ref-line]"
fresh_repo refs
"$GI" create "alpha task" >/dev/null 2>&1
a=$(porcelain_ids)
git commit -q --allow-empty -m "work" -m "Fixes: $a"
git commit -q --allow-empty -m "more" -m "Issue: #$a"
eq "full hash, lowercase key, id" "40 fixes 1"$'\n'"40 issue 1" \
   "$("$GI" scan-commits --porcelain | awk -F'\t' -v a="$a" '{print length($1), $2, ($3==a)}' | sort)"
eq "no banner or tip on stdout" "2" "$("$GI" scan-commits --porcelain | wc -l | tr -d ' ')"
eq "no references is empty stdout" "0" "$(fresh_repo refs-empty >/dev/null; "$GI" scan-commits --porcelain | wc -c | tr -d ' ')"

echo "Testing key-value lines [R-kv-line]"
fresh_repo kv
"$GI" create "alpha task" >/dev/null 2>&1
eq "sync status keys in order" \
   "enabled false"$'\n'"post-merge-hook false"$'\n'"pre-push-hook false"$'\n'"auto-fetch false"$'\n'"issue-notes 1" \
   "$("$GI" setup-sync status --porcelain | tr '\t' ' ')"
"$GI" setup-sync enable >/dev/null 2>&1 || true
eq "sync status reflects enable" "true" "$("$GI" setup-sync status --porcelain | awk -F'\t' '$1=="enabled"{print $2}')"
"$GI" repo add kv "$WORK/kv" >/dev/null 2>&1
eq "repo list unchanged under --porcelain" "$("$GI" repo list)" "$("$GI" repo list --porcelain)"
"$GI" repo rm kv >/dev/null 2>&1

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
