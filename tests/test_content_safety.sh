#!/bin/bash
# Content-safety tests: hostile or unlucky issue CONTENT must never hide,
# corrupt, or forge OTHER issues in any listing, and must not abort commands.

# Source the test runner for assertion framework
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/test_runner.sh"

# Fix PATH to use absolute path (test_runner uses relative, breaks after cd)
export PATH="$SCRIPT_DIR/../bin:$PATH"

# Write an issue blob verbatim via plumbing (bypasses create's sanitization,
# emulating imports and manual edits)
write_raw_issue() {
    local id="$1" blob tree commit
    blob=$(git hash-object -w --stdin)
    tree=$(printf "100644 blob %s\tissue\n" "$blob" | git mktree)
    commit=$(git commit-tree "$tree" -m "raw $id" </dev/null)
    git update-ref "refs/notes/issue-$id" "$commit"
}

# Helper to create an issue and return its ID
create_test_issue() {
    local title="$1"
    local output
    output=$(git issue create "$title" 2>/dev/null || true)
    echo "$output" | grep -o '#[a-f0-9]\{7\}' | head -1 | sed 's/#//'
}

# Helper to create an issue with a body
create_test_issue_with_body() {
    local title="$1"
    local body="$2"
    local id
    id=$(create_test_issue "$title")
    git issue update "$id" --description="$body" >/dev/null 2>&1 || true
    echo "$id"
}

# --- Quote characters (apostrophes are ordinary English!) ---

test_apostrophe_title_in_show() {
    local id
    id=$(create_test_issue "Don't crash on empty input")
    local output
    output=$(git issue show "$id" 2>&1)
    assert_contains "title: Don't crash on empty input" "$output" \
        "Apostrophe title should display in show (xargs would blank it)"
}

test_quote_in_dep_field_does_not_abort_listings() {
    local a
    a=$(create_test_issue "Innocent bystander")
    write_raw_issue quotedep <<'EOF'
id: quotedep
title: Quote in dep field
status: open
priority: medium
depends_on: don't
EOF

    local output
    output=$(git issue ready 2>&1)
    assert_exit_code 0 "git issue ready" "ready should survive a quote in depends_on"
    assert_contains "$a" "$output" "ready should still list other issues"

    output=$(git issue topo 2>&1)
    assert_exit_code 0 "git issue topo" "topo should survive a quote in depends_on"
    assert_contains "$a" "$output" "topo should still list other issues"

    assert_exit_code 0 "git issue dep rebuild" "dep rebuild should survive a quote in depends_on"
    assert_exit_code 0 "git issue deps" "deps should survive a quote in depends_on"
}

# --- Record forgery via body content ---

test_body_delimiter_line_cannot_forge_rows() {
    local a
    a=$(create_test_issue "Real issue A")
    write_raw_issue delimbmb <<'EOF'
id: delimbmb
title: Delimiter in body
status: open
priority: medium

Some body text
__ISSUE__
id: fakefak
status: done
title: PHANTOM ROW
EOF

    local output
    output=$(git issue list 2>&1)
    assert_contains "#delimbmb" "$output" "Issue with __ISSUE__ in body keeps its real id"
    assert_contains "#$a" "$output" "Other issues still listed"
    if echo "$output" | grep -q "#fakefak"; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Body content must not forge a phantom issue row"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Body content must not forge a phantom issue row"
    fi
}

test_midbody_header_lookalikes_do_not_shadow() {
    write_raw_issue shadowmb <<'EOF'
id: shadowmb
title: Shadow attempt
status: open
priority: medium

Steps to reproduce:
id: zzzzzz9
status: done
then more prose after, so these are body lines, not trailing headers
EOF

    local output
    output=$(git issue list 2>&1)
    assert_contains "#shadowmb [open]" "$output" \
        "Mid-body id:/status: lines must not change the displayed id/status"
}

test_trailing_id_line_does_not_reassign_issue() {
    write_raw_issue keepmyid <<'EOF'
id: keepmyid
title: Keeps its id
status: open
priority: medium

Pasted from another export:
id: stolenid
EOF

    local output
    output=$(git issue list 2>&1)
    assert_contains "#keepmyid" "$output" "Trailing id: line in body must not reassign the issue id"
}

# --- Display robustness ---

test_escape_sequences_not_interpreted() {
    write_raw_issue escbomb1 <<'EOF'
id: escbomb1
title: Vanish \033[8m now \c never seen
status: open
priority: medium
EOF

    local a
    a=$(create_test_issue "After the bomb")
    local output
    output=$(git issue list 2>&1)
    assert_contains 'Vanish \033[8m now \c never seen' "$output" \
        "Backslash escapes in titles must render literally, not as terminal codes"
    assert_contains "#$a" "$output" "Issues after an escape-laden title still render"
}

test_control_bytes_stripped_and_columns_stable() {
    # Real tab + empty title: neither may shift columns for the row or its neighbors
    printf 'id: tabtitle\ntitle: Tab\there\nstatus: open\npriority: high\nassignee: alice\n' \
        | write_raw_issue tabtitle
    printf 'id: notitle1\ntitle: \nstatus: open\npriority: high\n' \
        | write_raw_issue notitle1

    local output
    output=$(git issue list 2>&1)
    assert_contains "#tabtitle [open] Tabhere (P: high)" "$output" \
        "Tab in title is stripped instead of shifting columns"
    assert_contains "#notitle1 [open]  (P: high)" "$output" \
        "Empty title must not shift priority into the title column"
}

# --- Body-content parsing ---

test_trailing_prose_stays_in_body() {
    local id
    id=$(create_test_issue_with_body "Prose keeper" $'Fix the thing.\nnote: remember this line')
    local output
    output=$(git issue show "$id" 2>&1)
    assert_contains "note: remember this line" "$output" \
        "Trailing 'word:' prose must stay in the displayed body"
}

test_markdown_hrule_survives_roundtrip() {
    local a b exported
    a=$(create_test_issue_with_body "Markdown issue" $'Intro paragraph.\n\n---\n\nAfter the rule.')
    b=$(create_test_issue "Follower issue")

    exported=$(git issue export "$a" "$b" 2>/dev/null)
    git update-ref -d "refs/notes/issue-$a"
    git update-ref -d "refs/notes/issue-$b"

    local import_output
    import_output=$(echo "$exported" | git issue import 2>&1)
    assert_contains "Imported 2 issues" "$import_output" \
        "Both issues import despite --- inside a body"

    local output
    output=$(git issue show "$a" 2>&1)
    assert_contains "After the rule." "$output" \
        "Body content after a markdown --- rule survives export/import"
}

# Main
main() {
    echo -e "${BLUE}Content Safety Tests${NC}"
    echo "================================="
    echo ""

    run_test "apostrophe title displays in show" test_apostrophe_title_in_show
    run_test "quote in dep field cannot abort listings" test_quote_in_dep_field_does_not_abort_listings
    run_test "body __ISSUE__ line cannot forge rows" test_body_delimiter_line_cannot_forge_rows
    run_test "mid-body header lookalikes do not shadow" test_midbody_header_lookalikes_do_not_shadow
    run_test "trailing id line does not reassign issue" test_trailing_id_line_does_not_reassign_issue
    run_test "escape sequences render literally" test_escape_sequences_not_interpreted
    run_test "control bytes stripped, columns stable" test_control_bytes_stripped_and_columns_stable
    run_test "trailing prose stays in body" test_trailing_prose_stays_in_body
    run_test "markdown --- survives roundtrip" test_markdown_hrule_survives_roundtrip

    echo ""
    echo "================================="
    echo -e "${BLUE}Test Results:${NC}"
    echo -e "  Total: $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "  ${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
