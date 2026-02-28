#!/bin/bash
# Test dependency header fields in git-issue data model

# Source the test runner for assertion framework
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/test_runner.sh"

# Fix PATH to use absolute path (test_runner uses relative, breaks after cd)
export PATH="$SCRIPT_DIR/../bin:$PATH"

# Helper to read the edge index via plumbing (matches write_edge_index format)
read_edge_index_raw() {
    local ref="refs/notes/dep-graph"
    local tree_hash blob_hash
    tree_hash=$(git cat-file -p "$ref" 2>/dev/null | grep "^tree" | cut -d' ' -f2)
    [[ -z "$tree_hash" ]] && return 0
    blob_hash=$(git ls-tree "$tree_hash" 2>/dev/null | awk '$4 == "data" {print $3}')
    [[ -z "$blob_hash" ]] && blob_hash=$(git ls-tree "$tree_hash" 2>/dev/null | tail -1 | awk '{print $3}')
    [[ -z "$blob_hash" ]] && return 0
    git cat-file -p "$blob_hash" 2>/dev/null || true
}

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
    edges=$(read_edge_index_raw)
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
    edges=$(read_edge_index_raw)
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
    git update-ref -d refs/notes/dep-graph 2>/dev/null || true
    # Rebuild
    git issue dep rebuild 2>/dev/null
    local edges
    edges=$(read_edge_index_raw)
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

# ==========================================
# Auto-blocking state management tests (Task 5)
# ==========================================

# Test: dep add A blocks B => B's state becomes blocked
test_dep_add_blocks_sets_blocked() {
    local a=$(create_test_issue "Blocker")
    local b=$(create_test_issue "Blockee")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    local show_b
    show_b=$(git issue show "$b" 2>&1)
    assert_contains "blocked" "$show_b" "B should be blocked after dep add"
}

# Test: marking A done unblocks B
test_done_unblocks_dependents() {
    local a=$(create_test_issue "Will complete")
    local b=$(create_test_issue "Will unblock")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue update "$a" --state=done 2>/dev/null
    local show_b
    show_b=$(git issue show "$b" 2>&1)
    assert_contains "open" "$show_b" "B should be unblocked after A is done"
}

# Test: C blocked by A and B stays blocked when only A is done
test_multiple_blockers_partial_done() {
    local a=$(create_test_issue "Blocker 1")
    local b=$(create_test_issue "Blocker 2")
    local c=$(create_test_issue "Blocked by both")
    git issue dep add "$a" blocks "$c" 2>/dev/null
    git issue dep add "$b" blocks "$c" 2>/dev/null
    git issue update "$a" --state=done 2>/dev/null
    local show_c
    show_c=$(git issue show "$c" 2>&1)
    assert_contains "blocked" "$show_c" "C should stay blocked (B still open)"
    git issue update "$b" --state=done 2>/dev/null
    show_c=$(git issue show "$c" 2>&1)
    assert_contains "open" "$show_c" "C should unblock after both done"
}

# Test: removing last blocker unblocks the target
test_dep_rm_last_blocker_unblocks() {
    local a=$(create_test_issue "RM blocker")
    local b=$(create_test_issue "RM blocked")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue dep rm "$a" blocks "$b" 2>/dev/null
    local show_b
    show_b=$(git issue show "$b" 2>&1)
    assert_contains "open" "$show_b" "B should unblock after removing last blocker"
}

# ==========================================
# Incremental edge index rebuild tests (Task 6)
# ==========================================

# Test: manual header edit is picked up by dep list via incremental rebuild
test_manual_header_edit_picked_up() {
    local a=$(create_test_issue "Manual A")
    local b=$(create_test_issue "Manual B")

    # First do a normal dep add to establish the index
    git issue dep add "$a" blocks "$b" 2>/dev/null

    # Now create a new issue and manually add depends_on to its header
    local c=$(create_test_issue "Manual C")
    local data
    data=$(git issue show "$c" --raw 2>/dev/null)
    # Read via plumbing since show --raw may not exist
    local ref="refs/notes/issue-$c"
    local tree_hash blob_hash
    tree_hash=$(git cat-file -p "$ref" 2>/dev/null | grep "^tree" | cut -d' ' -f2)
    blob_hash=$(git ls-tree "$tree_hash" 2>/dev/null | awk '$4 == "data" {print $3}')
    [[ -z "$blob_hash" ]] && blob_hash=$(git ls-tree "$tree_hash" 2>/dev/null | tail -1 | awk '{print $3}')
    data=$(git cat-file -p "$blob_hash" 2>/dev/null)
    # Insert depends_on before the --- separator
    local new_data
    new_data=$(echo "$data" | awk -v dep="$a" '
        /^---$/ { print "depends_on: " dep; print; next }
        { print }
    ')
    # Write back via plumbing
    local new_blob new_tree new_commit parent
    new_blob=$(echo "$new_data" | git hash-object -w --stdin)
    new_tree=$(printf "100644 blob %s\tdata\n" "$new_blob" | git mktree)
    parent=$(git rev-parse --verify "$ref" 2>/dev/null) || true
    if [[ -n "$parent" ]]; then
        new_commit=$(git commit-tree "$new_tree" -p "$parent" -m "Manual edit" </dev/null)
    else
        new_commit=$(git commit-tree "$new_tree" -m "Manual edit" </dev/null)
    fi
    git update-ref "$ref" "$new_commit"

    # dep list should pick it up after ensure_edge_index_current runs
    local output
    output=$(git issue dep list "$c" 2>&1)
    assert_contains "$a" "$output" "Manual header edit should be picked up via incremental rebuild"

    # Also verify the edge index was updated with the new edge
    local edges
    edges=$(read_edge_index_raw)
    assert_contains "$c depends_on $a" "$edges" "Edge index should contain the manually-added depends_on edge"
}

# ==========================================
# Ready command tests (Task 7)
# ==========================================

test_ready_excludes_blocked() {
    local a=$(create_test_issue "Ready blocker")
    local b=$(create_test_issue "Ready blocked")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    local output
    output=$(git issue ready 2>&1)
    assert_contains "$a" "$output" "Blocker should be ready"
    if echo "$output" | grep -q "$b"; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Blocked issue should not be in ready list"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Blocked issue excluded from ready list"
    fi
}

test_ready_excludes_done() {
    local a=$(create_test_issue "Done issue")
    git issue update "$a" --state=done 2>/dev/null
    local output
    output=$(git issue ready 2>&1)
    if echo "$output" | grep -q "$a"; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Done issue should not be in ready list"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Done issue excluded from ready list"
    fi
}

test_ready_sorted_by_priority() {
    local low=$(create_test_issue "Low pri")
    local high=$(create_test_issue "High pri")
    git issue update "$low" --priority=low 2>/dev/null
    git issue update "$high" --priority=critical 2>/dev/null
    local output
    output=$(git issue ready 2>&1)
    local high_line low_line
    high_line=$(echo "$output" | grep -n "$high" | head -1 | cut -d: -f1)
    low_line=$(echo "$output" | grep -n "$low" | head -1 | cut -d: -f1)
    if [[ -n "$high_line" && -n "$low_line" && "$high_line" -lt "$low_line" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Higher priority listed first"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Higher priority should be listed first"
    fi
}

# ==========================================
# Topo command tests (Task 8)
# ==========================================

test_topo_ordering() {
    local a=$(create_test_issue "Topo first")
    local b=$(create_test_issue "Topo second")
    local c=$(create_test_issue "Topo third")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue dep add "$b" blocks "$c" 2>/dev/null
    local output
    output=$(git issue topo 2>&1)
    local a_line b_line c_line
    a_line=$(echo "$output" | grep -n "$a" | head -1 | cut -d: -f1)
    b_line=$(echo "$output" | grep -n "$b" | head -1 | cut -d: -f1)
    c_line=$(echo "$output" | grep -n "$c" | head -1 | cut -d: -f1)
    if [[ -n "$a_line" && -n "$b_line" && -n "$c_line" && "$a_line" -lt "$b_line" && "$b_line" -lt "$c_line" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Topological order correct: A < B < C"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Topological order incorrect (A=$a_line B=$b_line C=$c_line)"
    fi
}

test_topo_excludes_done() {
    local a=$(create_test_issue "Topo done")
    git issue update "$a" --state=done 2>/dev/null
    local output
    output=$(git issue topo 2>&1)
    if echo "$output" | grep -q "$a"; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Done issues should be excluded from topo"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Done issues excluded from topo"
    fi
}

# ==========================================
# Deps command tests (Task 9)
# ==========================================

test_deps_text_output() {
    local a=$(create_test_issue "Deps text A")
    local b=$(create_test_issue "Deps text B")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    local output
    output=$(git issue deps 2>&1)
    assert_contains "$a" "$output" "Should show A"
    assert_contains "$b" "$output" "Should show B"
    assert_contains "blocks" "$output" "Should show relationship"
}

test_deps_dot_output() {
    local a=$(create_test_issue "DOT A")
    local b=$(create_test_issue "DOT B")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    local output
    output=$(git issue deps --dot 2>&1)
    assert_contains "digraph" "$output" "DOT output should start with digraph"
    assert_contains "->" "$output" "DOT output should contain edges"
    assert_contains "$a" "$output" "DOT should include source ID"
    assert_contains "$b" "$output" "DOT should include target ID"
}

test_deps_single_issue() {
    local a=$(create_test_issue "Sub A")
    local b=$(create_test_issue "Sub B")
    local c=$(create_test_issue "Sub C")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue dep add "$b" blocks "$c" 2>/dev/null
    # Show only subgraph from B
    local output
    output=$(git issue deps "$b" 2>&1)
    assert_contains "$c" "$output" "Should show C (blocked by B)"
}

# ==========================================
# Missing edge case tests (Task 10)
# ==========================================

# Test: dep add with invalid type is rejected
test_dep_add_invalid_type_rejected() {
    local a=$(create_test_issue "Invalid type A")
    local b=$(create_test_issue "Invalid type B")
    if git issue dep add "$a" foobar "$b" 2>/dev/null; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Invalid dep type should be rejected"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Invalid dep type rejected"
    fi
}

# Test: topo with no deps returns all issues sorted by priority
test_topo_no_deps_shows_all() {
    local a=$(create_test_issue "Standalone A")
    local b=$(create_test_issue "Standalone B")
    local output
    output=$(git issue topo 2>&1)
    assert_contains "$a" "$output" "A should appear in topo"
    assert_contains "$b" "$output" "B should appear in topo"
}

# Test: dep list with no deps shows clean output (no error)
test_dep_list_no_deps() {
    local a=$(create_test_issue "No deps issue")
    local output
    output=$(git issue dep list "$a" 2>&1)
    # Should not error, just show clean/empty output
    if [[ $? -eq 0 ]]; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} dep list with no deps returns clean output"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} dep list with no deps should not error"
    fi
}

# Test: dep rebuild from scratch matches incrementally-maintained index
test_dep_rebuild_matches_incremental() {
    local a=$(create_test_issue "Rebuild match A")
    local b=$(create_test_issue "Rebuild match B")
    local c=$(create_test_issue "Rebuild match C")
    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue dep add "$b" blocks "$c" 2>/dev/null
    git issue dep add "$a" relates_to "$c" 2>/dev/null

    # Capture incremental index (sorted for comparison)
    local incremental
    incremental=$(read_edge_index_raw | grep -v "^last_rebuilt_from:" | sort)

    # Full rebuild
    git issue dep rebuild 2>/dev/null

    # Capture rebuilt index (sorted)
    local rebuilt
    rebuilt=$(read_edge_index_raw | grep -v "^last_rebuilt_from:" | sort)

    if [[ "$incremental" == "$rebuilt" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Rebuilt index matches incremental index"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Rebuilt index does not match incremental index"
        echo "  Incremental: $incremental"
        echo "  Rebuilt: $rebuilt"
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
    echo -e "${BLUE}Testing Auto-Blocking State Management (Task 5)${NC}"
    echo "================================="
    echo ""

    run_test "dep add blocks sets target to blocked" test_dep_add_blocks_sets_blocked
    run_test "done unblocks dependents" test_done_unblocks_dependents
    run_test "multiple blockers partial done stays blocked" test_multiple_blockers_partial_done
    run_test "dep rm last blocker unblocks" test_dep_rm_last_blocker_unblocks

    echo ""
    echo -e "${BLUE}Testing Incremental Edge Index Rebuild (Task 6)${NC}"
    echo "================================="
    echo ""

    run_test "manual header edit picked up by dep list" test_manual_header_edit_picked_up

    echo ""
    echo -e "${BLUE}Testing Ready Command (Task 7)${NC}"
    echo "================================="
    echo ""

    run_test "ready excludes blocked issues" test_ready_excludes_blocked
    run_test "ready excludes done issues" test_ready_excludes_done
    run_test "ready sorted by priority" test_ready_sorted_by_priority

    echo ""
    echo -e "${BLUE}Testing Topo Command (Task 8)${NC}"
    echo "================================="
    echo ""

    run_test "topo ordering correct" test_topo_ordering
    run_test "topo excludes done issues" test_topo_excludes_done

    echo ""
    echo -e "${BLUE}Testing Deps Command (Task 9)${NC}"
    echo "================================="
    echo ""

    run_test "deps text output" test_deps_text_output
    run_test "deps DOT output" test_deps_dot_output
    run_test "deps single issue subgraph" test_deps_single_issue

    echo ""
    echo -e "${BLUE}Testing Edge Cases (Task 10)${NC}"
    echo "================================="
    echo ""

    run_test "dep add invalid type rejected" test_dep_add_invalid_type_rejected
    run_test "topo with no deps shows all issues" test_topo_no_deps_shows_all
    run_test "dep list with no deps shows clean output" test_dep_list_no_deps
    run_test "dep rebuild matches incremental index" test_dep_rebuild_matches_incremental

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
