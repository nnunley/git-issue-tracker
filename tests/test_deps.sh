#!/bin/bash
# Test dependency header fields in git-issue data model

# Source the test runner for assertion framework
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/test_runner.sh"

# Helper to create an issue and return its ID
create_test_issue() {
    local title="$1"
    local output
    output=$(git issue create "$title" 2>/dev/null)
    echo "$output" | grep -o '#[a-f0-9]\{7\}' | head -1 | sed 's/#//'
}

# Test: show works without dep fields present
test_dep_fields_in_show() {
    local id
    id=$(create_test_issue "Issue without deps")

    local output
    output=$(git issue show "$id" 2>&1)

    assert_contains "Title: Issue without deps" "$output" "show displays title"
    assert_contains "State: open" "$output" "show displays state"
    # Dep fields should NOT appear when empty
    if [[ "$output" != *"Blocks:"* ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} no Blocks line when field is empty"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Blocks line should not appear when field is empty"
    fi
}

# Test: update with --blocks and verify it survives round-trip
test_dep_fields_survive_update() {
    local id
    id=$(create_test_issue "Issue with blocks")

    git issue update "$id" --blocks=aaaaaaa >/dev/null 2>&1

    local output
    output=$(git issue show "$id" 2>&1)

    assert_contains "Blocks: aaaaaaa" "$output" "show displays blocks after update"
}

# Test: multiple comma-separated dep values round-trip
test_multiple_dep_values() {
    local id
    id=$(create_test_issue "Issue with multiple blocks")

    git issue update "$id" --blocks=aaaaaaa,bbbbbbb >/dev/null 2>&1

    local output
    output=$(git issue show "$id" 2>&1)

    assert_contains "Blocks: aaaaaaa,bbbbbbb" "$output" "show displays comma-separated blocks"
}

# Main
main() {
    echo -e "${BLUE}Testing Dependency Header Fields${NC}"
    echo "================================="
    echo ""

    run_test "dep fields not shown when empty" test_dep_fields_in_show
    run_test "dep fields survive update round-trip" test_dep_fields_survive_update
    run_test "multiple dep values round-trip" test_multiple_dep_values

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
