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

echo "Testing readers on both formats [R-legacy-read]"
fresh_repo readers
# A hand-built format-1 note (no marker, body region, raw multi-line comment).
blob=$(printf 'id: abc1234\ntitle: legacy\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\n\nold body\nsecond body line\n\n## Comments\n[2026-01-01T00:00:00Z] conformance: one\ntwo\n[2026-01-02T00:00:00Z] conformance: three\n' | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
git update-ref refs/notes/issue-abc1234 "$(git commit-tree "$tree" -m legacy </dev/null)"
# A hand-built format-2 note.
blob=$(printf 'id: def5678\nv: 2\ntitle: modern\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\ndescription: first\n ## Comments\n third\n\n## Comments\n[2026-01-01T00:00:00Z] conformance: one\n two\n' | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
git update-ref refs/notes/issue-def5678 "$(git commit-tree "$tree" -m modern </dev/null)"
src() { bash -c "source '$GI' 2>/dev/null; $*"; }
eq "format 1 detected" "1" "$(src 'note_format "$(read_issue_data abc1234)"')"
eq "format 2 detected" "2" "$(src 'note_format "$(read_issue_data def5678)"')"
eq "format 1 description from body" "old body"$'\n'"second body line" "$(src 'get_description "$(read_issue_data abc1234)"')"
eq "format 2 description from header, continuation unfolded" "first"$'\n'"## Comments"$'\n'"third" "$(src 'get_description "$(read_issue_data def5678)"')"
eq "format 1 comments folded canonically" "[2026-01-01T00:00:00Z] conformance: one"$'\n'" two"$'\n'"[2026-01-02T00:00:00Z] conformance: three" "$(src 'parse_comment_records "$(read_issue_data abc1234)"')"
eq "format 2 comments pass through" "[2026-01-01T00:00:00Z] conformance: one"$'\n'" two" "$(src 'parse_comment_records "$(read_issue_data def5678)"')"
eq "human show unfolds comments" "one"$'\n'"two" "$("$GI" show abc1234 2>/dev/null | sed -n '/^Comments:/,$p' | tail -n +3 | head -2 | sed -E 's/^\[[^]]+\] conformance: //')"
eq "human show of format 2 prints description" "1" "$("$GI" show def5678 2>/dev/null | grep -c '^first$')"
eq "stream reads format 2 title" "modern" "$("$GI" list --porcelain | awk -F'\t' '$2=="def5678"{print $12}')"

# A format-1 body whose last line looks like "description: ..." is prose:
# description is a format-2 top-block header only, so it must never anchor or
# extend a trailing header block.
blob=$(printf 'id: aaa1111\ntitle: legacy2\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\n\nold body\ndescription: how to reproduce\n' | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
git update-ref refs/notes/issue-aaa1111 "$(git commit-tree "$tree" -m legacy2 </dev/null)"
eq "format 1 body ending in description: stays in the body" "old body"$'\n'"description: how to reproduce" "$(src 'get_description "$(read_issue_data aaa1111)"')"
eq "format 1 description: line is not a trailing header" "" "$(src 'get_field_value "$(parse_front_matter "$(read_issue_data aaa1111)")" description')"
eq "human show keeps the description: body line" "1" "$("$GI" show aaa1111 2>/dev/null | grep -c '^description: how to reproduce$')"
# Same for a body ending in an "id:" line. front_matter.awk and
# extract_issues.awk have always refused to read one as a trailing header
# (every write path emits id first, so an id below the body is prose), but
# body.awk excluded only "description:" and so silently dropped the line
# from the body — the two parsers disagreed about the same note.
blob=$(printf 'id: ddd4444\ntitle: legacy5\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\n\nold body\nid: eee5555\n' | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
git update-ref refs/notes/issue-ddd4444 "$(git commit-tree "$tree" -m legacy5 </dev/null)"
eq "format 1 body ending in id: stays in the body" "old body"$'\n'"id: eee5555" \
   "$(src 'get_description "$(read_issue_data ddd4444)"')"
eq "format 1 id: line is not a trailing header" "ddd4444" \
   "$(src 'get_field_value "$(parse_front_matter "$(read_issue_data ddd4444)")" id')"
eq "the bogus id is not listed" "0" \
   "$("$GI" list --porcelain | awk -F'\t' '$2=="eee5555"' | grep -c . || true)"
eq "human show keeps the id: body line" "1" \
   "$("$GI" show ddd4444 2>/dev/null | grep -c '^id: eee5555$')"

# A prose line then "title: hijack" then "description: ...": the description
# line breaks trailing-block contiguity, so the bogus title cannot win.
blob=$(printf 'id: bbb2222\ntitle: legacy3\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\n\nold body\ntitle: hijack\ndescription: how to reproduce\n' | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
git update-ref refs/notes/issue-bbb2222 "$(git commit-tree "$tree" -m legacy3 </dev/null)"
eq "trailing description: does not extend a trailing block" "legacy3" "$("$GI" list --porcelain | awk -F'\t' '$2=="bbb2222"{print $12}')"

# Legacy comment continuations survive folding: a blank line and a line that
# itself begins with a space must both round-trip through fold + unfold.
blob=$(printf 'id: ccc3333\ntitle: legacy4\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\n\nbody\n\n## Comments\n[2026-01-01T00:00:00Z] conformance: first\n\nsecond\n  indented\n' | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
git update-ref refs/notes/issue-ccc3333 "$(git commit-tree "$tree" -m legacy4 </dev/null)"
eq "format 1 blank line folds to a lone-space continuation" \
   "[2026-01-01T00:00:00Z] conformance: first"$'\n'" "$'\n'" second"$'\n'"   indented" \
   "$(src 'parse_comment_records "$(read_issue_data ccc3333)"')"
eq "fold then unfold is the identity for legacy comments" \
   "[2026-01-01T00:00:00Z] conformance: first"$'\n'""$'\n'"second"$'\n'"  indented" \
   "$(src 'parse_comments "$(read_issue_data ccc3333)"')"

echo "Testing format-2 writes [R-format-marker] [R-store-continuation] [R-field-normalize]"
fresh_repo writes
"$GI" create "alpha task" --description="$(printf 'first line\n## Comments')" >/dev/null 2>&1
a=$(porcelain_ids)
note() { git cat-file -p "refs/notes/issue-$1:issue"; }
eq "marker on line 2" "v: 2" "$(note "$a" | sed -n 2p)"
eq "one id line" "1" "$(note "$a" | grep -c '^id:')"
eq "description folded in header block" "description: first line"$'\n'" ## Comments" "$(note "$a" | grep -A1 '^description:')"
eq "no body region" "0" "$(note "$a" | awk 'f && !/^## Comments$/ && $0!="" {c++} /^$/ {f=1} /^## Comments$/ {exit} END {print c+0}')"
"$GI" comment "$a" "$(printf 'one\ntwo')" >/dev/null 2>&1
eq "comment folded" "## Comments"$'\n'"[T] conformance: one"$'\n'" two" "$(note "$a" | sed -n '/^## Comments$/,$p' | sed -E 's/^\[[^]]+\]/[T]/')"
"$GI" update "$a" --description="$(printf 'changed\nagain')" >/dev/null 2>&1
eq "description update folded" "description: changed"$'\n'" again" "$(note "$a" | grep -A1 '^description:')"
eq "description update keeps comments" "1" "$(note "$a" | grep -c '^ two$')"
# Upgrade on write of a format-1 note
blob=$(printf 'id: abc1234\ntitle: legacy\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\n\nold body\n\n## Comments\n[2026-01-01T00:00:00Z] conformance: one\ntwo\n' | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
git update-ref refs/notes/issue-abc1234 "$(git commit-tree "$tree" -m legacy </dev/null)"
"$GI" update abc1234 --priority=high >/dev/null 2>&1
eq "upgraded note has marker" "v: 2" "$(note abc1234 | sed -n 2p)"
eq "upgraded note moved body to header" "1" "$(note abc1234 | grep -c '^description: old body$')"
eq "upgraded note folded legacy comment" "1" "$(note abc1234 | grep -c '^ two$')"
eq "upgraded note kept the update" "high" "$("$GI" list --porcelain | awk -F'\t' '$2=="abc1234"{print $4}')"
# Single-line normalization on write
"$GI" create "$(printf 'tab\there')" >/dev/null 2>&1
tabid=$("$GI" list --porcelain | awk -F'\t' '$12=="tab here"{print $2}')
eq "tab in title stored as space" "1" "$(note "$tabid" | grep -c '^title: tab here$')"
"$GI" update "$a" --assignee="$(printf 'two\nlines')" >/dev/null 2>&1
eq "newline in assignee stored as space" "two lines" "$("$GI" list --porcelain | awk -F'\t' -v a="$a" '$2==a{print $5}')"

echo "Testing continuation guards in the in-place rewriters [R-store-continuation]"
fresh_repo guards
# A description continuation line that looks exactly like a header. awk splits
# fields after leading whitespace, so an unguarded "$1 == field" rule in the
# rewrite programs would edit or delete this line instead of the real header.
"$GI" create "guard task" --description="$(printf 'see below\nstatus: unclear')" >/dev/null 2>&1
"$GI" create "other task" >/dev/null 2>&1
g=$("$GI" list --porcelain | awk -F'\t' '$12=="guard task"{print $2}')
o=$("$GI" list --porcelain | awk -F'\t' '$12=="other task"{print $2}')
gnote() { git cat-file -p "refs/notes/issue-$g:issue"; }
"$GI" update "$g" --status=closed >/dev/null 2>&1
eq "update keeps the lookalike continuation line" "1" "$(gnote | grep -c '^ status: unclear$')"
eq "update rewrote the real header" "1" "$(gnote | grep -c '^status: closed$')"
"$GI" dep add "$g" blocks "$o" >/dev/null 2>&1
eq "dep add keeps the lookalike continuation line" "1" "$(gnote | grep -c '^ status: unclear$')"
eq "dep add wrote the edge" "1" "$(gnote | grep -c "^blocks: $o\$")"
"$GI" dep rm "$g" blocks "$o" >/dev/null 2>&1
eq "dep rm keeps the lookalike continuation line" "1" "$(gnote | grep -c '^ status: unclear$')"
eq "dep rm dropped the edge" "0" "$(gnote | grep -c '^blocks: ')"
eq "description survives all three rewrites" "see below"$'\n'"status: unclear" \
   "$(src "get_description \"\$(read_issue_data $g)\"")"
eq "real status still readable" "closed" "$("$GI" list --porcelain | awk -F'\t' -v g="$g" '$2==g{print $3}')"

echo "Testing format-2 canonicalization is a fixed point [R-format-marker]"
# A second write that changes nothing material must reproduce the same blob,
# byte for byte. A user-level no-op flag ("--status=closed" on a closed issue)
# is skipped before it reaches the writer, so this drives write_issue_data
# directly with the note's own data: a real write (the ref gains a commit),
# with no fresh "updated:" stamp to mask a difference.
"$GI" comment "$g" "$(printf 'note\nwith continuation')" >/dev/null 2>&1
blob_before=$(git rev-parse "refs/notes/issue-$g:issue")
commits_before=$(git rev-list --count "refs/notes/issue-$g")
src "write_issue_data '$g' \"\$(read_issue_data '$g')\"" >/dev/null 2>&1
eq "rewriting a note with its own data is a real write" \
   "$((commits_before + 1))" "$(git rev-list --count "refs/notes/issue-$g")"
eq "rewriting a note with its own data leaves the blob identical" \
   "$blob_before" "$(git rev-parse "refs/notes/issue-$g:issue")"
eq "_gi_to_format_2 is idempotent" \
   "$(src "_gi_to_format_2 \"\$(read_issue_data '$g')\"")" \
   "$(src "_gi_to_format_2 \"\$(_gi_to_format_2 \"\$(read_issue_data '$g')\")\"")"
eq "marker is not duplicated by the second write" "1" "$(git cat-file -p "refs/notes/issue-$g:issue" | grep -c '^v: 2$')"
eq "updated: is still a single header" "1" "$(git cat-file -p "refs/notes/issue-$g:issue" | grep -c '^updated: ')"

echo "Testing show block [R-show-block]"
fresh_repo showp
"$GI" create "alpha task" --description="$(printf 'first line\nsecond line')" >/dev/null 2>&1
a=$(porcelain_ids)
"$GI" comment "$a" "$(printf 'one\ntwo')" >/dev/null 2>&1
"$GI" update "$a" --role=dev >/dev/null 2>&1
eq "canonical block" \
   "title: alpha task"$'\n'"status: open"$'\n'"priority: medium"$'\n'"author: conformance"$'\n'"assignee: conformance"$'\n'"role: dev"$'\n'"hash_source: content"$'\n'"description: first line"$'\n'" second line"$'\n'"comment: [T] conformance: one"$'\n'" two" \
   "$("$GI" show "$a" --porcelain | grep -vE '^(id|created|updated): ' | sed -E 's/^(comment: )\[[^]]+\]/\1[T]/')"
eq "id first" "id: $a" "$("$GI" show "$a" --porcelain | head -1)"
eq "marker not emitted" "0" "$("$GI" show "$a" --porcelain | grep -c '^v:' || true)"
eq "no blank lines" "0" "$("$GI" show "$a" --porcelain | grep -c '^$' || true)"
eq "unknown id is an error" "1" "$("$GI" show nosuch --porcelain >/dev/null 2>&1; echo $?)"

echo "Testing write_issue_data refuses a note without an id line [R-write-guard]"
fresh_repo noid
cd "$WORK/noid"
err=$(src "write_issue_data zzz9999 'title: nope'" 2>&1 1>/dev/null) && rc=0 || rc=$?
eq "refused write returns nonzero" "1" "$rc"
eq "refused write reports the error" "1" \
   "$(printf '%s' "$err" | grep -c 'Error: refusing to write issue zzz9999: note has no id line')"
eq "refused write does not create the ref" "1" \
   "$(git rev-parse --verify refs/notes/issue-zzz9999 >/dev/null 2>&1 && echo 0 || echo 1)"
"$GI" create "normal write still works" >/dev/null 2>&1
eq "a normal write still succeeds" "1" "$("$GI" list --porcelain | wc -l | tr -d ' ')"

echo "Testing scan-commits reports found references [R-scan-commits]"
fresh_repo scanhit
git commit -q --allow-empty -m "$(printf 'do the thing\n\nFixes: #abc1234')"
scan_out=$("$GI" scan-commits 2>&1)
eq "scan-commits: reference line present" "1" "$(printf '%s' "$scan_out" | grep -c 'fixes: #abc1234\|Fixes: #abc1234')"
eq "scan-commits: does not say none found" "0" "$(printf '%s' "$scan_out" | grep -c 'No issue references found')"

fresh_repo scanmiss
git commit -q --allow-empty -m "no refs here"
scan_out=$("$GI" scan-commits 2>&1)
eq "scan-commits: says none found when there are none" "1" "$(printf '%s' "$scan_out" | grep -c 'No issue references found')"

echo "Testing unknown id on deps and dep list is an error [R-error-porcelain]"
fresh_repo unknowndeps
err_file="$WORK/unknowndeps.err"
out=$("$GI" deps nosuch --porcelain 2>"$err_file") && rc=0 || rc=$?
err=$(cat "$err_file")
eq "deps nosuch: nonzero exit" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
eq "deps nosuch: error mentions the id" "1" "$(printf '%s' "$err" | grep -c 'nosuch')"
eq "deps nosuch: nothing on stdout" "0" "$(printf '%s' "$out" | wc -c | tr -d ' ')"

out=$("$GI" dep list nosuch --porcelain 2>"$err_file") && rc=0 || rc=$?
err=$(cat "$err_file")
eq "dep list nosuch: nonzero exit" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
eq "dep list nosuch: error mentions the id" "1" "$(printf '%s' "$err" | grep -c 'nosuch')"
eq "dep list nosuch: nothing on stdout" "0" "$(printf '%s' "$out" | wc -c | tr -d ' ')"

echo "Testing create --porcelain [R-create-porcelain]"
fresh_repo createp
out=$("$GI" create "alpha task" --porcelain 2>/dev/null)
eq "create prints the id alone" "1" "$(printf '%s\n' "$out" | grep -cE '^[0-9a-f]{7}$')"
eq "create prints one line" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
eq "created issue is listed" "alpha task" "$("$GI" list --porcelain | awk -F'\t' -v id="$out" '$2==id{print $12}')"
eq "create with description works in porcelain" "1" "$("$GI" create "beta" --description="$(printf 'l1\nl2')" --porcelain 2>/dev/null | grep -cE '^[0-9a-f]{7}$')"
eq "human create output unchanged" "1" "$("$GI" create "gamma" 2>/dev/null | grep -c 'Created issue #')"

echo "Testing write-path errors go to stderr [R-plain-stdout]"
# update, comment and link printed "Issue #<id> not found" on *stdout*, so a
# consumer reading stdout as data got a colourised error record.
fresh_repo writeerr
for spec in "update:--priority=high" "comment:some text" "link:HEAD"; do
    cmd="${spec%%:*}"; arg="${spec#*:}"
    err_file="$WORK/writeerr.$cmd.err"
    out=$("$GI" "$cmd" zzzzzzz "$arg" --porcelain 2>"$err_file") && rc=0 || rc=$?
    err=$(cat "$err_file")
    eq "$cmd on a bogus id: nonzero exit" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
    eq "$cmd on a bogus id: nothing on stdout" "0" \
       "$(printf '%s' "$out" | wc -c | tr -d ' ')"
    eq "$cmd on a bogus id: error on stderr" "1" \
       "$(printf '%s' "$err" | grep -c 'not found')"
done

echo "Testing empty results exit 0 with empty stdout [R-plain-stdout]"
# `ready' used to end its empty branch with a bare `[[ ... ]] && echo', whose
# false test became the function's exit status under --porcelain, so an empty
# result exited 1. Every read command must exit 0 and print nothing instead.
empty_ok() { # empty_ok <label> <args...>
    local label="$1"; shift
    local out rc err_file="$WORK/emptyexit.err"
    out=$("$GI" "$@" --porcelain 2>"$err_file") && rc=0 || rc=$?
    eq "$label: exits 0" "0" "$rc"
    eq "$label: nothing on stdout" "0" "$(printf '%s' "$out" | wc -c | tr -d ' ')"
    eq "$label: nothing on stderr" "0" "$(wc -c <"$err_file" | tr -d ' ')"
}

fresh_repo emptyexit
for cmd in list ready topo deps scan-commits; do
    empty_ok "$cmd in an empty repository" $cmd
done
empty_ok "dep list in an empty repository" dep list

fresh_repo closedexit
closed_id=$("$GI" create "alpha task" --porcelain 2>/dev/null)
"$GI" close "$closed_id" --porcelain >/dev/null 2>&1
for cmd in ready topo deps scan-commits; do
    empty_ok "$cmd with every issue closed" $cmd
done
# `list' still reports the closed issue, and still exits 0.
out=$("$GI" list --porcelain 2>/dev/null) && rc=0 || rc=$?
eq "list with every issue closed: exits 0" "0" "$rc"
eq "list with every issue closed: still lists it" "1" \
   "$(printf '%s\n' "$out" | grep -c "$closed_id")"

# A filter that matches nothing is an empty result, not a failure.
fresh_repo filterexit
"$GI" create "alpha task" --porcelain >/dev/null 2>&1
empty_ok "ready with a role nothing matches" ready --role=nobody-has-this-role

echo "Testing ids are unique across repositories"
# generate_issue_id hashed only (title, author, second-granularity timestamp),
# so the same title created in two fresh repositories inside one second got
# the same id — and the in-repo collision retry cannot see the other repo.
ids=""
for n in 1 2 3 4 5; do
    fresh_repo "iduniq$n" >/dev/null
    ids="$ids$("$GI" create "same title everywhere" --porcelain 2>/dev/null)"$'\n'
done
eq "five repos, five distinct ids" "5" \
   "$(printf '%s' "$ids" | sort -u | grep -c .)"
eq "ids are still 7 hex characters" "5" \
   "$(printf '%s' "$ids" | grep -cE '^[0-9a-f]{7}$')"

echo "Testing every diagnostic goes to stderr [R-plain-stdout]"
# A consumer reading stdout as data must never see a diagnostic there, in
# either mode: the human mode's banner and coloured errors used to land on
# stdout for validation failures (invalid status/priority/field/commit) as
# well as for not-found ids.
fresh_repo diagerr
real=$("$GI" create "alpha task" --porcelain 2>/dev/null)
diag_err() { # diag_err <label> <expected fragment> <args...>
    local label="$1" want="$2"; shift 2
    local mode out rc err_file="$WORK/diagerr.err"
    for mode in plain porcelain; do
        if [[ "$mode" == porcelain ]]; then
            out=$("$GI" "$@" --porcelain 2>"$err_file") && rc=0 || rc=$?
        else
            out=$("$GI" "$@" 2>"$err_file") && rc=0 || rc=$?
        fi
        eq "$label ($mode): nonzero exit" "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
        eq "$label ($mode): nothing on stdout" "0" "$(printf '%s' "$out" | wc -c | tr -d ' ')"
        eq "$label ($mode): diagnostic on stderr" "1" \
           "$(grep -c -- "$want" "$err_file" || true)"
    done
}
diag_err "show on a bogus id"    "not found"        show zzzzzzz
diag_err "update on a bogus id"  "not found"        update zzzzzzz --status=open
diag_err "link on a bogus id"    "not found"        link zzzzzzz HEAD
diag_err "dep add self"          "self-dependency"  dep add zzzzzzz blocks zzzzzzz
diag_err "update invalid status" "Invalid status"   update "$real" --status=not-a-status
diag_err "link invalid commit"   "Invalid commit"   link "$real" not-a-commit
# The unknown-command branch prints its usage as part of the error.
out=$("$GI" no-such-command 2>/dev/null) && rc=0 || rc=$?
eq "unknown command: nothing on stdout" "0" "$(printf '%s' "$out" | wc -c | tr -d ' ')"
eq "unknown command: usage on stderr" "1" \
   "$("$GI" no-such-command 2>&1 >/dev/null | grep -c '^Usage: git issue' || true)"

echo "Testing --version"
# The version query is answered in _gi_dispatch before storage detection, so
# it must work with no repository in sight and must never create a store.
fresh_repo versioncmd
want="git-issue $(cat "$REPO_DIR/VERSION")"
eq "--version prints the version" "$want" "$("$GI" --version)"
eq "-V prints the same line"      "$want" "$("$GI" -V)"
eq "version prints the same line" "$want" "$("$GI" version)"
set +e; "$GI" --version >/dev/null 2>&1; rc=$?; set -e
eq "--version exits 0" "0" "$rc"
eq "--version is silent on stderr" "" "$("$GI" --version 2>&1 >/dev/null)"
nogit="$WORK/not-a-repo"; rm -rf "$nogit"; mkdir -p "$nogit"; cd "$nogit"
eq "--version works outside a git repository" "$want" "$("$GI" --version)"
eq "--version created no store" "" "$(ls -A "$nogit")"
eq "man page .TH agrees with VERSION" "1" \
   "$(grep -c "\"$want\"" "$REPO_DIR/man/man1/git-issue.1" || true)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
