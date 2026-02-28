#!/bin/bash
# Test dependency header fields in git-issue data model

# Source the test runner for assertion framework
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/test_runner.sh"

# Fix PATH to use absolute path (test_runner uses relative, breaks after cd)
export PATH="$SCRIPT_DIR/../bin:$PATH"

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

# ==========================================
# dep add/rm/list tests (Task 2)
# ==========================================

# Test: dep add A blocks B => A shows Blocks: B, B shows Depends on: A
test_dep_add_blocks() {
    local id_a id_b
    id_a=$(create_test_issue "Issue A")
    id_b=$(create_test_issue "Issue B")

    git issue dep add "$id_a" blocks "$id_b" >/dev/null 2>&1

    local output_a output_b
    output_a=$(git issue show "$id_a" 2>&1)
    output_b=$(git issue show "$id_b" 2>&1)

    assert_contains "Blocks: $id_b" "$output_a" "A shows B in Blocks"
    assert_contains "Depends on: $id_a" "$output_b" "B shows A in Depends on"
}

# Test: dep add A relates_to B => A shows Relates to: B (unidirectional)
test_dep_add_relates_to() {
    local id_a id_b
    id_a=$(create_test_issue "Issue A")
    id_b=$(create_test_issue "Issue B")

    git issue dep add "$id_a" relates_to "$id_b" >/dev/null 2>&1

    local output_a output_b
    output_a=$(git issue show "$id_a" 2>&1)
    output_b=$(git issue show "$id_b" 2>&1)

    assert_contains "Relates to: $id_b" "$output_a" "A shows B in Relates to"
    # B should NOT show anything about A for relates_to (unidirectional)
    if [[ "$output_b" != *"Relates to:"* ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} B does not show relates_to (unidirectional)"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} B should not show relates_to for unidirectional link"
    fi
}

# Test: dep add epic parent_of task => epic shows Parent of: task (unidirectional)
test_dep_add_parent_of() {
    local id_epic id_task
    id_epic=$(create_test_issue "Epic issue")
    id_task=$(create_test_issue "Task issue")

    git issue dep add "$id_epic" parent_of "$id_task" >/dev/null 2>&1

    local output_epic
    output_epic=$(git issue show "$id_epic" 2>&1)

    assert_contains "Parent of: $id_task" "$output_epic" "epic shows task in Parent of"
}

# Test: dep rm removes blocks dep from both sides
test_dep_rm() {
    local id_a id_b
    id_a=$(create_test_issue "Issue A")
    id_b=$(create_test_issue "Issue B")

    git issue dep add "$id_a" blocks "$id_b" >/dev/null 2>&1

    # Verify it was added
    local output_a
    output_a=$(git issue show "$id_a" 2>&1)
    assert_contains "Blocks: $id_b" "$output_a" "blocks was added before removal"

    # Now remove it
    git issue dep rm "$id_a" blocks "$id_b" >/dev/null 2>&1

    output_a=$(git issue show "$id_a" 2>&1)
    local output_b
    output_b=$(git issue show "$id_b" 2>&1)

    # Neither should have the dep anymore
    if [[ "$output_a" != *"Blocks:"* ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} A no longer shows Blocks after removal"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} A still shows Blocks after removal"
    fi

    if [[ "$output_b" != *"Depends on:"* ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} B no longer shows Depends on after removal"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} B still shows Depends on after removal"
    fi
}

# Test: dep add self-dep is rejected
test_dep_add_self_rejected() {
    local id_a
    id_a=$(create_test_issue "Self-dep issue")

    if git issue dep add "$id_a" blocks "$id_a" >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} self-dependency should be rejected (got exit 0)"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} self-dependency rejected with non-zero exit"
    fi
}

# Test: dep add with nonexistent issue is rejected
test_dep_add_nonexistent_rejected() {
    local id_a
    id_a=$(create_test_issue "Real issue")

    if git issue dep add "$id_a" blocks zzzzzzz >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} nonexistent target should be rejected (got exit 0)"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} nonexistent target rejected with non-zero exit"
    fi

    if git issue dep add zzzzzzz blocks "$id_a" >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} nonexistent source should be rejected (got exit 0)"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} nonexistent source rejected with non-zero exit"
    fi
}

# Test: multiple deps — A blocks C, B blocks C => C depends_on A,B
test_dep_add_multiple() {
    local id_a id_b id_c
    id_a=$(create_test_issue "Issue A")
    id_b=$(create_test_issue "Issue B")
    id_c=$(create_test_issue "Issue C")

    git issue dep add "$id_a" blocks "$id_c" >/dev/null 2>&1
    git issue dep add "$id_b" blocks "$id_c" >/dev/null 2>&1

    local output_c
    output_c=$(git issue show "$id_c" 2>&1)

    assert_contains "$id_a" "$output_c" "C depends_on includes A"
    assert_contains "$id_b" "$output_c" "C depends_on includes B"
}

# Test: dep list shows dependencies
test_dep_list() {
    local id_a id_b
    id_a=$(create_test_issue "Issue A")
    id_b=$(create_test_issue "Issue B")

    git issue dep add "$id_a" blocks "$id_b" >/dev/null 2>&1

    local output
    output=$(git issue dep list 2>&1)

    assert_contains "$id_a" "$output" "dep list mentions A"
    assert_contains "$id_b" "$output" "dep list mentions B"
    assert_contains "blocks" "$output" "dep list shows relationship type"
}

# ==========================================
# Edge index tests (Task 3)
# ==========================================

# Test: edge index is written when dep add is called
test_edge_index_written_on_dep_add() {
    local a=$(create_test_issue "Edge A")
    local b=$(create_test_issue "Edge B")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    local edges
    edges=$(git notes --ref=refs/notes/dep-graph show 2>/dev/null || echo "")
    assert_contains "$a blocks $b" "$edges" "Edge index should contain blocks edge"
    assert_contains "$b depends_on $a" "$edges" "Edge index should contain depends_on edge"
}

# Test: edge index is cleaned when dep rm is called
test_edge_index_cleaned_on_dep_rm() {
    local a=$(create_test_issue "EdgeRM A")
    local b=$(create_test_issue "EdgeRM B")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue dep rm "$a" blocks "$b" 2>/dev/null
    local edges
    edges=$(git notes --ref=refs/notes/dep-graph show 2>/dev/null || echo "")
    # Use custom assertion since we need to check absence
    if echo "$edges" | grep -q "$a blocks $b"; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Edge should be removed from index"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Edge removed from index"
    fi
    if echo "$edges" | grep -q "$b depends_on $a"; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Inverse edge should be removed from index"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Inverse edge removed from index"
    fi
}

# Test: dep rebuild reconstructs edge index from headers
test_dep_rebuild() {
    local a=$(create_test_issue "Rebuild A")
    local b=$(create_test_issue "Rebuild B")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    # Wipe the edge index
    git notes --ref=refs/notes/dep-graph remove 2>/dev/null || true
    # Rebuild
    git issue dep rebuild 2>/dev/null
    local edges
    edges=$(git notes --ref=refs/notes/dep-graph show 2>/dev/null || echo "")
    assert_contains "$a blocks $b" "$edges" "Rebuild should restore blocks edge from headers"
    assert_contains "$b depends_on $a" "$edges" "Rebuild should restore depends_on edge from headers"
}

# ==========================================
# Cycle detection tests (Task 4)
# ==========================================

# Test: direct cycle A->B->A is rejected
test_direct_cycle_rejected() {
    local a=$(create_test_issue "Cycle A")
    local b=$(create_test_issue "Cycle B")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    if git issue dep add "$b" blocks "$a" 2>/dev/null; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Direct cycle should be rejected"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Direct cycle rejected"
    fi
}

# Test: transitive cycle A->B->C->A is rejected
test_transitive_cycle_rejected() {
    local a=$(create_test_issue "TCycle A")
    local b=$(create_test_issue "TCycle B")
    local c=$(create_test_issue "TCycle C")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue dep add "$b" blocks "$c" 2>/dev/null
    if git issue dep add "$c" blocks "$a" 2>/dev/null; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Transitive cycle should be rejected"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Transitive cycle rejected"
    fi
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
    echo -e "${BLUE}Testing dep add/rm/list Commands${NC}"
    echo "================================="
    echo ""

    run_test "dep add blocks (bidirectional)" test_dep_add_blocks
    run_test "dep add relates_to (unidirectional)" test_dep_add_relates_to
    run_test "dep add parent_of (unidirectional)" test_dep_add_parent_of
    run_test "dep rm removes from both sides" test_dep_rm
    run_test "dep add self-dependency rejected" test_dep_add_self_rejected
    run_test "dep add nonexistent issue rejected" test_dep_add_nonexistent_rejected
    run_test "dep add multiple deps accumulate" test_dep_add_multiple
    run_test "dep list shows dependencies" test_dep_list

    echo ""
    echo -e "${BLUE}Testing Edge Index (Task 3)${NC}"
    echo "================================="
    echo ""

    run_test "edge index written on dep add" test_edge_index_written_on_dep_add
    run_test "edge index cleaned on dep rm" test_edge_index_cleaned_on_dep_rm
    run_test "dep rebuild reconstructs index" test_dep_rebuild

    echo ""
    echo -e "${BLUE}Testing Cycle Detection (Task 4)${NC}"
    echo "================================="
    echo ""

    run_test "direct cycle rejected" test_direct_cycle_rejected
    run_test "transitive cycle rejected" test_transitive_cycle_rejected

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
