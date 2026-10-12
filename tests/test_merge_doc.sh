#!/usr/bin/env bash
# Unit tests for the three-way issue document merge (gi_merge_docs,
# share/git-issue/awk/merge_doc.awk) and the document diff (gi_diff_docs).
# Usage: tests/test_merge_doc.sh [test_name...]   (default: every test)

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GI="$SCRIPT_DIR/bin/git-issue"
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/git-issue-merge-test.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT

check() {
    local name="$1"; shift
    if "$@"; then echo -e "  ${GREEN}PASS${NC} $name"; else echo -e "  ${RED}FAIL${NC} $name"; fi
}

# A canonical format-2 document. Extra header lines and comment records are
# passed as "h:<line>" and "c:<line>" arguments, in order.
doc() {
    local status="$1" priority="$2" updated="$3"; shift 3
    local headers="" comments="" a
    for a in "$@"; do
        case "$a" in
            h:*) headers="$headers"$'\n'"${a#h:}" ;;
            c:*) comments="$comments"$'\n'"${a#c:}" ;;
        esac
    done
    printf 'id: abc1234\nv: 2\ntitle: Merge me\nstatus: %s\npriority: %s\ncreated: 2026-10-01T00:00:00Z\nupdated: %s%s\n' \
        "$status" "$priority" "$updated" "$headers"
    if [[ -n "$comments" ]]; then printf '\n## Comments%s\n' "$comments"; fi
}

# merge <base> <local> <remote>: writes $ROOT/{base,local,remote}, runs
# gi_merge_docs, leaves the result in $OUT, the conflicts in $CONF, and the
# exit status in $RC
merge() {
    printf '%s\n' "$1" > "$ROOT/base"
    printf '%s\n' "$2" > "$ROOT/local"
    printf '%s\n' "$3" > "$ROOT/remote"
    CONF="$ROOT/conflicts"; : > "$CONF"
    OUT=$(bash -c 'source "$1"; gi_merge_docs "$2/base" "$2/local" "$2/remote" "$2/conflicts"' _ "$GI" "$ROOT" 2>"$ROOT/err")
    RC=$?
}
field() { printf '%s\n' "$OUT" | awk -v k="$1:" '$1 == k { sub(/^[^:]*: ?/, ""); print; exit }'; }
same() { [[ "$1" == "$2" ]] || { echo "      want: $1"; echo "      got:  $2"; return 1; }; }

T0=2026-10-01T00:00:00Z
T1=2026-10-02T00:00:00Z
T2=2026-10-03T00:00:00Z

test_one_side_field_wins() {
    merge "$(doc open medium $T0)" "$(doc open high $T1)" "$(doc open medium $T0)"
    check one_side_field_wins bash -c '[[ $0 == 0 && $1 == high ]]' "$RC" "$(field priority)"
}

test_both_same_value() {
    merge "$(doc open medium $T0)" "$(doc closed medium $T1)" "$(doc closed medium $T1)"
    check both_same_value bash -c '[[ $0 == 0 && $1 == closed && ! -s $2 ]]' "$RC" "$(field status)" "$CONF"
}

test_both_different_conflict() {
    merge "$(doc open medium $T0)" "$(doc closed medium $T1)" "$(doc blocked medium $T2)"
    check both_different_conflict same "1|closed|field: status
local: closed
remote: blocked" "$RC|$(field status)|$(cat "$CONF")"
}

test_updated_takes_later() {
    merge "$(doc open medium $T0)" "$(doc open high $T2)" "$(doc open medium $T1 h:role:\ dev)"
    check updated_takes_later bash -c '[[ $0 == 0 && $1 == "$2" ]]' "$RC" "$(field updated)" "$T2"
}

test_labels_set_merge() {
    merge "$(doc open medium $T0 h:labels:\ a,b)" "$(doc open medium $T1 h:labels:\ a,b,c)" "$(doc open medium $T1 h:labels:\ b,d)"
    check labels_set_merge same "0|b,c,d" "$RC|$(field labels)"
}

test_description_both_changed_conflict() {
    merge "$(doc open medium $T0 'h:description: first' 'h: line')" \
          "$(doc open medium $T1 'h:description: mine' 'h: line')" \
          "$(doc open medium $T1 'h:description: theirs')"
    check description_both_changed_conflict bash -c '[[ $0 == 1 ]] && grep -qx "field: description" "$1"' "$RC" "$CONF"
}

test_comments_union() {
    local c0='c:[2026-10-01T00:00:00Z] Alice: start'
    merge "$(doc open medium $T0 "$c0")" \
          "$(doc open medium $T2 "$c0" 'c:[2026-10-03T00:00:00Z] Alice: later')" \
          "$(doc open medium $T1 "$c0" 'c:[2026-10-02T00:00:00Z] Bob: earlier')"
    check comments_union same "0|[2026-10-01T00:00:00Z] Alice: start
[2026-10-02T00:00:00Z] Bob: earlier
[2026-10-03T00:00:00Z] Alice: later" "$RC|$(printf '%s\n' "$OUT" | sed -n '/^## Comments$/,$p' | tail -n +2)"
}

test_multiline_comments_kept() {
    merge "$(doc open medium $T0)" \
          "$(doc open medium $T1 'c:[2026-10-02T00:00:00Z] Alice: note' 'c: from Alice')" \
          "$(doc open medium $T1 'c:[2026-10-02T00:00:00Z] Alice: note' 'c: from Bob')"
    check multiline_comments_kept bash -c '[[ $0 == 0 ]] && grep -qx " from Alice" <<< "$1" && grep -qx " from Bob" <<< "$1"' "$RC" "$OUT"
}

test_format1_vs_format2() {
    local f1 f2
    f1=$(printf 'id: abc1234\ntitle: Legacy\nstatus: open\npriority: medium\ncreated: %s\nupdated: %s\nauthor: Alice\n\nold body\n\n## Comments\n[%s] Alice: one\n' $T0 $T0 $T0)
    f2=$(printf 'id: abc1234\nv: 2\ntitle: Legacy\nstatus: open\npriority: medium\ncreated: %s\nupdated: %s\nauthor: Alice\ndescription: old body\n\n## Comments\n[%s] Alice: one\n' $T0 $T0 $T0)
    merge "$f1" "$f1" "$f2"
    check format1_vs_format2 bash -c '[[ $0 == 0 && ! -s $1 ]] && grep -qx "description: old body" <<< "$2" && [[ $(grep -c "Alice: one" <<< "$2") == 1 ]]' "$RC" "$CONF" "$OUT"
}

# diff <old> <new>: gi_diff_docs of two documents, into $OUT
diff_of() {
    printf '%s\n' "$1" > "$ROOT/old"
    printf '%s\n' "$2" > "$ROOT/new"
    OUT=$(bash -c 'source "$1"; gi_diff_docs "$2/old" "$2/new"' _ "$GI" "$ROOT" 2>"$ROOT/err")
}

test_diff_status_change() {
    diff_of "$(doc open medium $T0)" "$(doc closed medium $T1)"
    check diff_status_change same "status: open → closed" "$OUT"
}

test_diff_added_comment() {
    diff_of "$(doc open medium $T0)" "$(doc open medium $T1 'c:[2026-10-02T00:00:00Z] Bob: hi' 'c: there')"
    check diff_added_comment same "comment" "$OUT"
}

test_diff_description_changed() {
    diff_of "$(doc open medium $T0 'h:description: one')" "$(doc open medium $T1 'h:description: two' 'h: lines' h:role:\ dev)"
    check diff_description_changed same "description changed
role: + dev" "$OUT"
}

ALL_TESTS=$(declare -F | awk '$3 ~ /^test_/ {print $3}')
if [[ $# -gt 0 ]]; then ALL_TESTS=$(printf 'test_%s\n' "$@"); fi
echo "git-issue document merge tests"
for t in $ALL_TESTS; do "$t"; done 2>&1 | tee "$ROOT/out"
run=$(grep -c 'PASS\|FAIL' "$ROOT/out"); passed=$(grep -c 'PASS' "$ROOT/out")
echo "$passed/$run passed"
[[ "$passed" -eq "$run" ]]
