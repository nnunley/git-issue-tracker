# Dependency Graph Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add dependency graph with four relationship types, edge index, tsort-based topological sort, auto-blocking, and text/DOT output to git-issue.

**Architecture:** Issues store deps as comma-separated header fields (source of truth). A derived edge index at `refs/notes/dep-graph` enables fast graph queries. POSIX `tsort` handles topological ordering and cycle detection. The index self-heals on reads by diffing modified notes.

**Tech Stack:** Bash, git notes, POSIX tsort, awk, grep

**Dogfooding:** Track progress with `git issue update <id> --state=done` using the IDs listed in AGENTS.md.

---

### Task 1: Add dep header fields to the data model

**Issue:** `27f03b1`

**Files:**
- Modify: `bin/git-issue` (lines 200-217: parse/get functions, lines 300-357: show_issue, lines 359-418: update_issue, lines 246-265: create_issue)
- Test: `tests/test_deps.sh` (create new)

**Step 1: Create test file with header field tests**

Create `tests/test_deps.sh`:

```bash
#!/bin/bash
# Tests for dependency graph features

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_runner.sh"

# Helper: create issue and return its ID
create_test_issue() {
    local title="$1"
    local output
    output=$(git issue create "$title" 2>/dev/null)
    echo "$output" | grep -o '#[a-f0-9]\{7\}' | head -1 | sed 's/#//'
}

# === DATA MODEL TESTS ===

test_dep_fields_in_show() {
    local id=$(create_test_issue "Issue with deps")

    # Verify show works (no dep fields yet, should not error)
    local output
    output=$(git issue show "$id")
    assert_contains "Issue with deps" "$output" "show should work without dep fields"
}

test_dep_fields_survive_update() {
    local id=$(create_test_issue "Issue for field test")

    # Manually write dep fields into the issue via update
    git issue update "$id" --blocks="aaaaaaa" 2>/dev/null

    local output
    output=$(git issue show "$id")
    assert_contains "blocks: aaaaaaa" "$output" "blocks field should appear in show"
}

test_multiple_dep_values() {
    local id=$(create_test_issue "Multi-dep issue")

    git issue update "$id" --blocks="aaaaaaa,bbbbbbb" 2>/dev/null

    local output
    output=$(git issue show "$id")
    assert_contains "blocks: aaaaaaa,bbbbbbb" "$output" "comma-separated blocks should round-trip"
}

# Main
main() {
    echo -e "${BLUE}Dependency Graph Tests${NC}"
    echo "=========================="

    run_test "Dep fields in show" test_dep_fields_in_show
    run_test "Dep fields survive update" test_dep_fields_survive_update
    run_test "Multiple dep values" test_multiple_dep_values

    echo ""
    echo "=========================="
    echo -e "Total: $TESTS_RUN  ${GREEN}Passed: $TESTS_PASSED${NC}  ${RED}Failed: $TESTS_FAILED${NC}"
    [[ $TESTS_FAILED -gt 0 ]] && exit 1
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

**Step 2: Run tests to verify they fail**

Run: `chmod +x tests/test_deps.sh && ./tests/test_deps.sh`
Expected: First test passes, second and third fail (blocks not in update allowlist)

**Step 3: Add dep fields to update_issue allowlist**

In `bin/git-issue`, modify the `update_issue()` function's case statement (around line 373) to accept the four new fields:

```bash
        blocks|depends_on|parent_of|relates_to)
            # Accept comma-separated issue IDs
            ;;
```

**Step 4: Add dep fields to show_issue output**

In `show_issue()` (around line 317), add extraction and display of the four dep fields after the assignee line:

```bash
    local blocks=$(get_field_value "$front_matter" "blocks")
    local depends_on=$(get_field_value "$front_matter" "depends_on")
    local parent_of=$(get_field_value "$front_matter" "parent_of")
    local relates_to=$(get_field_value "$front_matter" "relates_to")

    # ... after assignee display:
    [[ -n "$blocks" ]] && echo "Blocks: $blocks"
    [[ -n "$depends_on" ]] && echo "Depends on: $depends_on"
    [[ -n "$parent_of" ]] && echo "Parent of: $parent_of"
    [[ -n "$relates_to" ]] && echo "Relates to: $relates_to"
```

**Step 5: Add dep fields to update_issue_with_flags flag parsing**

In `update_issue_with_flags()` (around line 439), add flag parsing for `--blocks`, `--depends-on`, `--parent-of`, `--relates-to`:

```bash
            --blocks=*)
                blocks_val="${1#*=}"
                has_updates=true
                ;;
            --depends-on=*)
                depends_on_val="${1#*=}"
                has_updates=true
                ;;
            --parent-of=*)
                parent_of_val="${1#*=}"
                has_updates=true
                ;;
            --relates-to=*)
                relates_to_val="${1#*=}"
                has_updates=true
                ;;
```

And the corresponding update calls at the bottom of the function.

**Step 6: Run tests to verify they pass**

Run: `./tests/test_deps.sh`
Expected: All 3 tests pass

**Step 7: Commit**

```bash
git add tests/test_deps.sh bin/git-issue
git commit -m "feat: add dependency header fields to issue data model"
```

**Step 8: Update tracker**

```bash
git issue update 27f03b1 --state=done
```

---

### Task 2: Implement dep add/rm with bidirectional header sync

**Issue:** `9bc4207`

**Files:**
- Modify: `bin/git-issue` (add dep subcommand handler, add `handle_dep()`, `dep_add()`, `dep_rm()`, `dep_list()` functions, wire into main case statement)
- Modify: `tests/test_deps.sh` (add tests)

**Step 1: Add dep add/rm tests to test file**

Append to `tests/test_deps.sh`:

```bash
# === DEP ADD/RM TESTS ===

test_dep_add_blocks() {
    local a=$(create_test_issue "Parent task")
    local b=$(create_test_issue "Child task")

    local output
    output=$(git issue dep add "$a" blocks "$b" 2>&1)
    assert_contains "Added" "$output" "dep add should confirm"

    # Check A has blocks field
    local show_a
    show_a=$(git issue show "$a")
    assert_contains "$b" "$show_a" "A should list B in blocks"

    # Check B has depends_on field
    local show_b
    show_b=$(git issue show "$b")
    assert_contains "$a" "$show_b" "B should list A in depends_on"
}

test_dep_add_relates_to() {
    local a=$(create_test_issue "Related A")
    local b=$(create_test_issue "Related B")

    git issue dep add "$a" relates_to "$b" 2>/dev/null

    local show_a
    show_a=$(git issue show "$a")
    assert_contains "$b" "$show_a" "A should list B in relates_to"
}

test_dep_add_parent_of() {
    local epic=$(create_test_issue "Epic")
    local task=$(create_test_issue "Sub-task")

    git issue dep add "$epic" parent_of "$task" 2>/dev/null

    local show_epic
    show_epic=$(git issue show "$epic")
    assert_contains "$task" "$show_epic" "Epic should list task in parent_of"
}

test_dep_rm() {
    local a=$(create_test_issue "RM parent")
    local b=$(create_test_issue "RM child")

    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue dep rm "$a" blocks "$b" 2>/dev/null

    local show_a
    show_a=$(git issue show "$a")
    # blocks field should be empty or absent
    if echo "$show_a" | grep -q "Blocks:.*$b"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} A should not list B in blocks after rm"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} A does not list B in blocks after rm"
    fi
}

test_dep_add_self_rejected() {
    local a=$(create_test_issue "Self-dep issue")

    local output
    if git issue dep add "$a" blocks "$a" 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Self-dependency should be rejected"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Self-dependency rejected"
    fi
}

test_dep_add_nonexistent_rejected() {
    local a=$(create_test_issue "Real issue")

    if git issue dep add "$a" blocks "zzzzzzz" 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Dep on nonexistent issue should be rejected"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Dep on nonexistent issue rejected"
    fi
}

test_dep_add_multiple() {
    local a=$(create_test_issue "Blocker 1")
    local b=$(create_test_issue "Blocker 2")
    local c=$(create_test_issue "Blocked issue")

    git issue dep add "$a" blocks "$c" 2>/dev/null
    git issue dep add "$b" blocks "$c" 2>/dev/null

    local show_c
    show_c=$(git issue show "$c")
    assert_contains "$a" "$show_c" "C should depend on A"
    assert_contains "$b" "$show_c" "C should depend on B"
}

test_dep_list() {
    local a=$(create_test_issue "List A")
    local b=$(create_test_issue "List B")

    git issue dep add "$a" blocks "$b" 2>/dev/null

    local output
    output=$(git issue dep list "$a" 2>&1)
    assert_contains "blocks" "$output" "dep list should show blocks edge"
    assert_contains "$b" "$output" "dep list should show target ID"
}
```

Add these to the `main()` function's run_test calls.

**Step 2: Run tests to verify they fail**

Run: `./tests/test_deps.sh`
Expected: New dep add/rm tests fail (command not found)

**Step 3: Implement dep command infrastructure**

In `bin/git-issue`, add these functions before the main case statement:

- `append_to_field()` — adds a value to a comma-separated header field (or creates it)
- `remove_from_field()` — removes a value from a comma-separated header field
- `dep_add()` — validates both IDs exist, rejects self-dep, validates type, calls `append_to_field` on both issues for blocks/depends_on (bidirectional), calls `append_to_field` on source only for parent_of/relates_to
- `dep_rm()` — inverse of dep_add, calls `remove_from_field`
- `dep_list()` — reads dep fields from an issue's headers and prints them
- `handle_dep()` — routes `dep add|rm|list|rebuild` subcommands

Wire `dep)` into the main case statement (around line 1360).

**Key implementation detail for `append_to_field`:**

```bash
append_to_field() {
    local id="$1"
    local field="$2"
    local value="$3"

    local data
    data=$(read_issue_data "$id")
    local current
    current=$(echo "$data" | grep "^${field}:" | cut -d' ' -f2- | xargs)

    if [[ -z "$current" ]]; then
        local new_value="$value"
    else
        # Don't add duplicates
        if echo ",$current," | grep -q ",$value,"; then
            return 0
        fi
        local new_value="${current},${value}"
    fi

    # Use the awk updater pattern from update_issue
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local updated_data
    updated_data=$(echo "$data" | awk -v field="${field}:" -v value="$new_value" -v ts="$timestamp" '
        BEGIN { found=0; in_body=0 }
        /^---$/ { if (!found) { print field, value; found=1 }; in_body=1; print; next }
        in_body { print; next }
        $1 == field { print field, value; found=1; next }
        $1 == "updated:" { print "updated:", ts; next }
        { print }
    ')

    write_issue_data "$id" "$updated_data"
}
```

Similar pattern for `remove_from_field` but filtering the value out of the comma-separated list and removing the field entirely if empty.

**Step 4: Run tests to verify they pass**

Run: `./tests/test_deps.sh`
Expected: All dep add/rm tests pass

**Step 5: Commit**

```bash
git add bin/git-issue tests/test_deps.sh
git commit -m "feat: implement dep add/rm with bidirectional header sync"
```

**Step 6: Update tracker**

```bash
git issue update 9bc4207 --state=done
```

---

### Task 3: Implement edge index at refs/notes/dep-graph

**Issue:** `5f82085`

**Files:**
- Modify: `bin/git-issue` (add `read_edge_index()`, `write_edge_index()`, `add_edge()`, `remove_edge()`, `rebuild_edge_index()` functions; call from `dep_add`/`dep_rm`)
- Modify: `tests/test_deps.sh` (add edge index tests)

**Step 1: Add edge index tests**

```bash
test_edge_index_written_on_dep_add() {
    local a=$(create_test_issue "Edge A")
    local b=$(create_test_issue "Edge B")

    git issue dep add "$a" blocks "$b" 2>/dev/null

    # Read the edge index directly
    local edges
    edges=$(git notes --ref=refs/notes/dep-graph show 2>/dev/null || echo "")
    assert_contains "$a blocks $b" "$edges" "Edge index should contain blocks edge"
    assert_contains "$b depends_on $a" "$edges" "Edge index should contain depends_on edge"
}

test_edge_index_cleaned_on_dep_rm() {
    local a=$(create_test_issue "EdgeRM A")
    local b=$(create_test_issue "EdgeRM B")

    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue dep rm "$a" blocks "$b" 2>/dev/null

    local edges
    edges=$(git notes --ref=refs/notes/dep-graph show 2>/dev/null || echo "")
    if echo "$edges" | grep -q "$a blocks $b"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Edge should be removed from index"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Edge removed from index"
    fi
}

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
}
```

**Step 2: Run to verify failure, then implement**

The edge index functions:

- `read_edge_index()` — reads the dep-graph note, returns content (empty string if note doesn't exist)
- `write_edge_index()` — writes content to the dep-graph note
- `add_edge()` — appends `"from type to"` line to edge index (deduplicates)
- `remove_edge()` — filters out matching line from edge index
- `rebuild_edge_index()` — iterates all issues, parses dep fields from headers, writes complete edge index with `last_rebuilt_from:` marker set to current timestamp

Modify `dep_add()` to call `add_edge()` after header updates.
Modify `dep_rm()` to call `remove_edge()` after header updates.
Wire `rebuild)` in `handle_dep()` to call `rebuild_edge_index()`.

**Step 3: Run tests, verify pass, commit**

```bash
git add bin/git-issue tests/test_deps.sh
git commit -m "feat: implement edge index at refs/notes/dep-graph"
git issue update 5f82085 --state=done
```

---

### Task 4: Implement cycle detection via tsort

**Issue:** `9fea41d`

**Files:**
- Modify: `bin/git-issue` (add `check_for_cycles()`, call from `dep_add` before committing)
- Modify: `tests/test_deps.sh`

**Step 1: Add cycle detection tests**

```bash
test_direct_cycle_rejected() {
    local a=$(create_test_issue "Cycle A")
    local b=$(create_test_issue "Cycle B")

    git issue dep add "$a" blocks "$b" 2>/dev/null

    if git issue dep add "$b" blocks "$a" 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Direct cycle should be rejected"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Direct cycle rejected"
    fi
}

test_transitive_cycle_rejected() {
    local a=$(create_test_issue "TCycle A")
    local b=$(create_test_issue "TCycle B")
    local c=$(create_test_issue "TCycle C")

    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue dep add "$b" blocks "$c" 2>/dev/null

    if git issue dep add "$c" blocks "$a" 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Transitive cycle should be rejected"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Transitive cycle rejected"
    fi
}
```

**Step 2: Implement check_for_cycles**

```bash
check_for_cycles() {
    local from="$1"
    local to="$2"

    # Get current blocking edges from index + proposed new edge
    local edges
    edges=$(read_edge_index | grep ' blocks ' | awk '{print $1, $3}')
    edges="${edges}"$'\n'"${from} ${to}"

    # tsort returns non-zero and prints cycle info to stderr on cycles
    if ! echo "$edges" | tsort >/dev/null 2>&1; then
        return 1  # cycle detected
    fi
    return 0
}
```

Call `check_for_cycles` in `dep_add()` before writing anything, only for `blocks` type. If it returns 1, print error and exit without modifying headers or index.

**Step 3: Run tests, verify pass, commit**

```bash
git add bin/git-issue tests/test_deps.sh
git commit -m "feat: implement cycle detection via tsort"
git issue update 9fea41d --state=done
```

---

### Task 5: Implement auto-blocking state management

**Issue:** `2b5a920`

**Files:**
- Modify: `bin/git-issue` (modify `dep_add`, `dep_rm`, `update_issue_with_flags` to cascade state changes)
- Modify: `tests/test_deps.sh`

**Step 1: Add auto-blocking tests**

```bash
test_dep_add_blocks_sets_blocked() {
    local a=$(create_test_issue "Blocker")
    local b=$(create_test_issue "Blockee")

    git issue dep add "$a" blocks "$b" 2>/dev/null

    local show_b
    show_b=$(git issue show "$b")
    assert_contains "blocked" "$show_b" "B should be blocked after dep add"
}

test_done_unblocks_dependents() {
    local a=$(create_test_issue "Will complete")
    local b=$(create_test_issue "Will unblock")

    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue update "$a" --state=done 2>/dev/null

    local show_b
    show_b=$(git issue show "$b")
    assert_contains "open" "$show_b" "B should be unblocked after A is done"
}

test_multiple_blockers_partial_done() {
    local a=$(create_test_issue "Blocker 1")
    local b=$(create_test_issue "Blocker 2")
    local c=$(create_test_issue "Blocked by both")

    git issue dep add "$a" blocks "$c" 2>/dev/null
    git issue dep add "$b" blocks "$c" 2>/dev/null

    # Complete only A
    git issue update "$a" --state=done 2>/dev/null

    local show_c
    show_c=$(git issue show "$c")
    assert_contains "blocked" "$show_c" "C should stay blocked (B still open)"

    # Complete B
    git issue update "$b" --state=done 2>/dev/null

    show_c=$(git issue show "$c")
    assert_contains "open" "$show_c" "C should unblock after both done"
}

test_dep_rm_last_blocker_unblocks() {
    local a=$(create_test_issue "RM blocker")
    local b=$(create_test_issue "RM blocked")

    git issue dep add "$a" blocks "$b" 2>/dev/null
    git issue dep rm "$a" blocks "$b" 2>/dev/null

    local show_b
    show_b=$(git issue show "$b")
    assert_contains "open" "$show_b" "B should unblock after removing last blocker"
}
```

**Step 2: Implement auto-blocking**

In `dep_add()`, after writing headers and edge index for `blocks` type:
```bash
    if [[ "$type" == "blocks" ]]; then
        local target_state
        target_state=$(read_issue_data "$to" | grep "^state:" | cut -d' ' -f2)
        if [[ "$target_state" != "done" ]]; then
            update_issue "$to" "state" "blocked"
        fi
    fi
```

Add `cascade_unblock()` function:
```bash
cascade_unblock() {
    local completed_id="$1"

    # Find all issues that depend on the completed issue
    local edges
    edges=$(read_edge_index)
    local dependents
    dependents=$(echo "$edges" | grep " depends_on " | while read -r dep_id _ blocker_id; do
        if [[ "$blocker_id" == "$completed_id" ]]; then
            echo "$dep_id"
        fi
    done)

    for dep_id in $dependents; do
        # Get all blockers for this dependent
        local dep_data
        dep_data=$(read_issue_data "$dep_id")
        local all_blockers
        all_blockers=$(echo "$dep_data" | grep "^depends_on:" | cut -d' ' -f2- | tr ',' '\n')

        local all_resolved=true
        for blocker in $all_blockers; do
            [[ -z "$blocker" ]] && continue
            blocker=$(echo "$blocker" | xargs)
            local blocker_state
            blocker_state=$(read_issue_data "$blocker" | grep "^state:" | cut -d' ' -f2)
            if [[ "$blocker_state" != "done" ]]; then
                all_resolved=false
                break
            fi
        done

        if [[ "$all_resolved" == "true" ]]; then
            local current_state
            current_state=$(echo "$dep_data" | grep "^state:" | cut -d' ' -f2)
            if [[ "$current_state" == "blocked" ]]; then
                update_issue "$dep_id" "state" "open"
                echo -e "${GREEN}Unblocked issue #$dep_id${NC}"
            fi
        fi
    done
}
```

Call `cascade_unblock "$id"` from `update_issue_with_flags` when state is set to `done`.

In `dep_rm()`, after removing the edge, check if target has any remaining blockers and unblock if not.

**Step 3: Run tests, verify pass, commit**

```bash
git add bin/git-issue tests/test_deps.sh
git commit -m "feat: implement auto-blocking state management"
git issue update 2b5a920 --state=done
```

---

### Task 6: Implement incremental rebuild on read

**Issue:** `0083ead`

**Files:**
- Modify: `bin/git-issue` (add `ensure_edge_index_current()`, call before graph queries)
- Modify: `tests/test_deps.sh`

**Step 1: Add incremental rebuild tests**

```bash
test_manual_header_edit_picked_up() {
    local a=$(create_test_issue "Manual A")
    local b=$(create_test_issue "Manual B")

    # Manually add depends_on to B's header (bypassing dep add)
    local data
    data=$(git notes --ref="refs/notes/issue-$b" show 2>/dev/null)
    local new_data
    new_data=$(echo "$data" | awk -v dep="$a" '
        /^---$/ { print "depends_on: " dep; print; next }
        { print }
    ')
    echo "$new_data" | git notes --ref="refs/notes/issue-$b" add -f -F - 2>/dev/null

    # Now dep list should pick it up after incremental rebuild
    local output
    output=$(git issue dep list "$b" 2>&1)
    assert_contains "$a" "$output" "Manual header edit should be picked up"
}
```

**Step 2: Implement ensure_edge_index_current**

```bash
ensure_edge_index_current() {
    local edge_data
    edge_data=$(read_edge_index)

    # Get the last rebuild timestamp from the index
    local last_rebuilt
    last_rebuilt=$(echo "$edge_data" | grep "^last_rebuilt_from:" | cut -d' ' -f2-)

    # Find issue notes modified since last rebuild
    # Compare committer dates of issue note refs against the marker
    local needs_rebuild=false
    local changed_ids=()

    for ref in $(git for-each-ref --format="%(refname)" 'refs/notes/issue-*' 2>/dev/null); do
        local ref_date
        ref_date=$(git for-each-ref --format="%(committerdate:iso-strict)" "$ref" 2>/dev/null)
        if [[ -z "$last_rebuilt" ]] || [[ "$ref_date" > "$last_rebuilt" ]]; then
            local id
            id=$(echo "$ref" | sed 's/refs\/notes\/issue-//')
            changed_ids+=("$id")
            needs_rebuild=true
        fi
    done

    if [[ "$needs_rebuild" == "true" ]]; then
        # Re-parse only changed issues and update edges
        for id in "${changed_ids[@]}"; do
            local data
            data=$(read_issue_data "$id" 2>/dev/null) || continue

            # Remove old edges for this issue
            edge_data=$(echo "$edge_data" | grep -v "^${id} " | grep -v " ${id}$")

            # Parse dep fields and add new edges
            for field in blocks depends_on parent_of relates_to; do
                local values
                values=$(echo "$data" | grep "^${field}:" | cut -d' ' -f2- | xargs)
                if [[ -n "$values" ]]; then
                    for target in $(echo "$values" | tr ',' '\n'); do
                        target=$(echo "$target" | xargs)
                        [[ -n "$target" ]] && edge_data="${edge_data}"$'\n'"${id} ${field} ${target}"
                    done
                fi
            done
        done

        # Update marker and write
        edge_data=$(echo "$edge_data" | grep -v "^last_rebuilt_from:" | grep -v "^$")
        edge_data="last_rebuilt_from: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"$'\n'"${edge_data}"
        write_edge_index "$edge_data"
    fi
}
```

Call `ensure_edge_index_current` at the start of `ready`, `topo`, `deps`, and `dep list`.

**Step 3: Run tests, verify pass, commit**

```bash
git add bin/git-issue tests/test_deps.sh
git commit -m "feat: implement incremental edge index rebuild on read"
git issue update 0083ead --state=done
```

---

### Task 7: Implement git issue ready

**Issue:** `d5b50eb`

**Files:**
- Modify: `bin/git-issue` (add `list_ready_issues()`, wire `ready)` in main case)
- Modify: `tests/test_deps.sh`

**Step 1: Add ready command tests**

```bash
test_ready_excludes_blocked() {
    local a=$(create_test_issue "Ready blocker")
    local b=$(create_test_issue "Ready blocked")

    git issue dep add "$a" blocks "$b" 2>/dev/null

    local output
    output=$(git issue ready 2>&1)
    assert_contains "$a" "$output" "Blocker should be ready"
    if echo "$output" | grep -q "$b"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Blocked issue should not be in ready list"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Blocked issue excluded from ready list"
    fi
}

test_ready_excludes_done() {
    local a=$(create_test_issue "Done issue")
    git issue update "$a" --state=done 2>/dev/null

    local output
    output=$(git issue ready 2>&1)
    if echo "$output" | grep -q "$a"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Done issue should not be in ready list"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
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
    # High priority should appear before low
    local high_line low_line
    high_line=$(echo "$output" | grep -n "$high" | head -1 | cut -d: -f1)
    low_line=$(echo "$output" | grep -n "$low" | head -1 | cut -d: -f1)

    if [[ -n "$high_line" && -n "$low_line" && "$high_line" -lt "$low_line" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Higher priority listed first"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Higher priority should be listed first"
    fi
}
```

**Step 2: Implement list_ready_issues**

```bash
list_ready_issues() {
    ensure_edge_index_current

    echo -e "${BLUE}Ready to work on:${NC}"
    echo ""

    # Get all blocked issue IDs from the edge index
    local blocked_ids
    blocked_ids=$(read_edge_index | grep " depends_on " | awk '{print $1}' | sort -u)

    # Priority sort order
    local -A priority_rank=( [critical]=0 [high]=1 [medium]=2 [low]=3 )

    # Collect ready issues with sort keys
    local ready_lines=()
    for ref in $(list_all_issues); do
        local id
        id=$(extract_issue_id "$ref")
        local data
        data=$(read_issue_data "$id" 2>/dev/null) || continue

        local state
        state=$(echo "$data" | grep "^state:" | cut -d' ' -f2)

        # Skip done and blocked
        [[ "$state" == "done" || "$state" == "blocked" ]] && continue

        # Skip if has unresolved blockers
        local depends
        depends=$(echo "$data" | grep "^depends_on:" | cut -d' ' -f2- | xargs)
        if [[ -n "$depends" ]]; then
            local has_open_blocker=false
            for blocker in $(echo "$depends" | tr ',' '\n'); do
                blocker=$(echo "$blocker" | xargs)
                [[ -z "$blocker" ]] && continue
                local bstate
                bstate=$(read_issue_data "$blocker" 2>/dev/null | grep "^state:" | cut -d' ' -f2)
                if [[ "$bstate" != "done" ]]; then
                    has_open_blocker=true
                    break
                fi
            done
            [[ "$has_open_blocker" == "true" ]] && continue
        fi

        local title priority assignee
        title=$(echo "$data" | grep "^title:" | cut -d' ' -f2-)
        priority=$(echo "$data" | grep "^priority:" | cut -d' ' -f2)
        assignee=$(echo "$data" | grep "^assignee:" | cut -d' ' -f2-)

        local rank=${priority_rank[$priority]:-2}
        echo "${rank} #${id} [${state}] ${title} (P: ${priority}) -> ${assignee:-Unassigned}"
    done | sort -t' ' -k1,1n | cut -d' ' -f2-
}
```

Wire `ready)` into the main case statement.

**Step 3: Run tests, verify pass, commit**

```bash
git add bin/git-issue tests/test_deps.sh
git commit -m "feat: implement git issue ready command"
git issue update d5b50eb --state=done
```

---

### Task 8: Implement git issue topo

**Issue:** `5d89481`

**Files:**
- Modify: `bin/git-issue` (add `topo_sort_issues()`, wire `topo)` in main case)
- Modify: `tests/test_deps.sh`

**Step 1: Add topo tests**

```bash
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
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Topological order correct: A < B < C"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Topological order incorrect"
    fi
}

test_topo_no_deps_shows_all() {
    local a=$(create_test_issue "Topo standalone A")
    local b=$(create_test_issue "Topo standalone B")

    local output
    output=$(git issue topo 2>&1)
    assert_contains "$a" "$output" "A should appear in topo"
    assert_contains "$b" "$output" "B should appear in topo"
}

test_topo_excludes_done() {
    local a=$(create_test_issue "Topo done")
    git issue update "$a" --state=done 2>/dev/null

    local output
    output=$(git issue topo 2>&1)
    if echo "$output" | grep -q "$a"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Done issues should be excluded from topo"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Done issues excluded from topo"
    fi
}
```

**Step 2: Implement topo_sort_issues**

```bash
topo_sort_issues() {
    ensure_edge_index_current

    echo -e "${BLUE}Topological order (do these in sequence):${NC}"
    echo ""

    # Get blocking edges for non-done issues
    local edges
    edges=$(read_edge_index | grep " blocks ")

    # Get all non-done issue IDs
    local all_ids=()
    for ref in $(list_all_issues); do
        local id
        id=$(extract_issue_id "$ref")
        local state
        state=$(read_issue_data "$id" 2>/dev/null | grep "^state:" | cut -d' ' -f2)
        [[ "$state" == "done" ]] && continue
        all_ids+=("$id")
    done

    # Build tsort input: blocking edges + standalone nodes (paired with themselves removed)
    local tsort_input=""
    for edge_line in $(echo "$edges" | awk '{print $1 " " $3}'); do
        tsort_input="${tsort_input}${edge_line}"$'\n'
    done
    # Add standalone nodes so tsort includes them
    for id in "${all_ids[@]}"; do
        tsort_input="${tsort_input}${id} ${id}"$'\n'
    done

    # Run tsort
    local ordered
    ordered=$(echo "$tsort_input" | tsort 2>/dev/null) || {
        echo -e "${RED}Cycle detected in dependency graph!${NC}" >&2
        return 1
    }

    # Annotate and display
    local n=0
    echo "$ordered" | while read -r id; do
        # Skip IDs not in our active set (could be stale)
        local data
        data=$(read_issue_data "$id" 2>/dev/null) || continue
        local state
        state=$(echo "$data" | grep "^state:" | cut -d' ' -f2)
        [[ "$state" == "done" ]] && continue

        n=$((n + 1))
        local title priority depends_on
        title=$(echo "$data" | grep "^title:" | cut -d' ' -f2-)
        priority=$(echo "$data" | grep "^priority:" | cut -d' ' -f2)
        depends_on=$(echo "$data" | grep "^depends_on:" | cut -d' ' -f2- | xargs)

        local annotation=""
        if [[ -n "$depends_on" ]]; then
            annotation=" <- blocked by #$(echo "$depends_on" | tr ',' ' #')"
        fi

        echo -e "${n}. #${id}  ${title}  (P: ${priority})${annotation}"
    done
}
```

**Step 3: Run tests, verify pass, commit**

```bash
git add bin/git-issue tests/test_deps.sh
git commit -m "feat: implement git issue topo command"
git issue update 5d89481 --state=done
```

---

### Task 9: Implement git issue deps with --dot output

**Issue:** `164b383`

**Files:**
- Modify: `bin/git-issue` (add `show_deps()`, `show_deps_dot()`, wire `deps)` in main case)
- Modify: `tests/test_deps.sh`

**Step 1: Add deps command tests**

```bash
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
    # A should not appear since we're rooted at B
}
```

**Step 2: Implement show_deps and show_deps_dot**

`show_deps()` — reads edge index, prints text tree grouped by source issue.
`show_deps_dot()` — reads edge index, outputs Graphviz DOT with edge styles:
- `blocks` — solid arrow
- `parent_of` — dashed arrow
- `relates_to` — dotted arrow
- `depends_on` — skip (inverse of blocks, would duplicate)

When an issue ID argument is provided, filter to only edges reachable from that node (BFS/DFS via a while loop over a queue).

**Step 3: Run tests, verify pass, commit**

```bash
git add bin/git-issue tests/test_deps.sh
git commit -m "feat: implement git issue deps with --dot output"
git issue update 164b383 --state=done
```

---

### Task 10: Write comprehensive test suite

**Issue:** `033d845`

**Files:**
- Modify: `tests/test_deps.sh` (consolidate, add missing edge cases)
- Modify: `Makefile` (add `test-deps` target)

**Step 1: Review test coverage against design doc checklist**

Ensure all tests from the design doc's Testing section are present. Add any missing:
- `dep add` invalid type rejected
- `dep list` with no deps shows clean output
- `import` with dep fields triggers rebuild
- `dep rebuild` from scratch matches incremental index

**Step 2: Add Makefile target**

```makefile
test-deps:
	@echo "Running dependency graph tests..."
	chmod +x tests/test_deps.sh
	./tests/test_deps.sh
```

Update `test-all` to include `test-deps`.

**Step 3: Run full suite, verify all pass, commit**

```bash
make test-all
git add tests/test_deps.sh Makefile
git commit -m "test: comprehensive dependency graph test suite"
git issue update 033d845 --state=done
```

---

### Task 11: Write benchmark harness

**Issue:** `235ba00`

**Files:**
- Create: `tests/bench_deps.sh`
- Modify: `Makefile` (add `bench-deps` target)

**Step 1: Create benchmark script**

```bash
#!/bin/bash
# Benchmark harness for dependency graph performance

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$SCRIPT_DIR/../bin:$PATH"

COUNT=${1:-500}
BENCH_REPO="/tmp/git-issue-bench-$$"

echo "Setting up benchmark with $COUNT issues..."

mkdir -p "$BENCH_REPO"
cd "$BENCH_REPO"
git init >/dev/null 2>&1
git config user.name "Bench User"
git config user.email "bench@example.com"
echo "# Bench" > README.md
git add README.md
git commit -m "init" >/dev/null 2>&1

# Create issues
ids=()
for i in $(seq 1 "$COUNT"); do
    id=$(git issue create "Bench issue $i" 2>/dev/null | grep -o '#[a-f0-9]\{7\}' | head -1 | sed 's/#//')
    ids+=("$id")
done

# Create random blocking deps (each issue blocks ~1-2 later issues)
for i in $(seq 0 $((COUNT - 2))); do
    target=$((i + 1 + RANDOM % 3))
    [[ $target -ge $COUNT ]] && continue
    git issue dep add "${ids[$i]}" blocks "${ids[$target]}" 2>/dev/null || true
done

echo ""
echo "Benchmarking $COUNT issues with deps..."
echo "========================================="

# Time ready
echo -n "ready:       "
time git issue ready >/dev/null 2>&1

# Time topo
echo -n "topo:        "
time git issue topo >/dev/null 2>&1

# Time deps
echo -n "deps:        "
time git issue deps >/dev/null 2>&1

# Time dep rebuild
echo -n "dep rebuild: "
time git issue dep rebuild >/dev/null 2>&1

echo ""
echo "Cleanup..."
cd /tmp
rm -rf "$BENCH_REPO"
echo "Done."
```

**Step 2: Add Makefile target**

```makefile
bench-deps:
	@echo "Running dependency benchmark..."
	chmod +x tests/bench_deps.sh
	./tests/bench_deps.sh $(COUNT)
```

**Step 3: Run benchmark, verify targets met, commit**

```bash
make bench-deps COUNT=500
git add tests/bench_deps.sh Makefile
git commit -m "perf: add dependency graph benchmark harness"
git issue update 235ba00 --state=done
```

---

### Task 12: Final integration and epic close

**Step 1: Run full test suite**

```bash
make test-all
```

**Step 2: Run benchmarks**

```bash
make bench-deps COUNT=500
```

**Step 3: Update epic issue**

```bash
git issue update ffdbfdb --state=done
```

**Step 4: Final commit with all changes**

Ensure everything is committed and clean.
