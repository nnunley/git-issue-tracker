# Agentic Roles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `role` field to issues so agents can filter `ready` by role, with optional auto-assignment on status transitions.

**Architecture:** New `role` header field on issues (like `assignee`). Extend `update_issue_with_flags` to accept `--role=`. Extend `list_ready_issues` with `--role=` filter. Add `queue` command as alias. Extend status machine DSL and compiler with `(role=X)` on transitions. Apply transition roles in `check_transition` path.

**Tech Stack:** Bash (git-issue), bash status compiler (git-issue-compile-statuses)

---

### Task 1: Add `role` to `update_issue` field validation

**Files:**
- Modify: `bin/git-issue:548-577` (`update_issue()` case statement)

**Step 1: Write the failing test**

Add to `tests/test_git_style_flags.sh` before the cleanup section:

```bash
# Test: role flag
run_test "role flag with equals" "git issue update $ISSUE_ID --role=reviewer" "success"

# Verify role was stored
run_test "role stored in issue data" "git issue show $ISSUE_ID" "Role: reviewer"

# Test: clear role
run_test "clear role" "git issue update $ISSUE_ID --role=" "success"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_git_style_flags.sh`
Expected: FAIL on "role flag with equals" — `Unknown flag '--role'`

**Step 3: Add `role` to `update_issue()` field validation**

In `bin/git-issue`, in the `update_issue()` function's case statement (line ~548), add after the `assignee)` case:

```bash
        role)
            # Accept any value for role
            ;;
```

Also add `role` to the error message for invalid fields (line ~575):

```bash
            echo "Valid fields: status, priority, assignee, role, description, blocks, depends_on, parent_of, relates_to"
```

**Step 4: Run test to verify it still fails**

Run: `bash tests/test_git_style_flags.sh`
Expected: Still FAIL — `update_issue_with_flags` doesn't parse `--role=` yet.

**Step 5: Commit**

```bash
git add bin/git-issue
git commit -m "feat: add role to update_issue field validation"
```

---

### Task 2: Add `--role=` flag parsing to `update_issue_with_flags`

**Files:**
- Modify: `bin/git-issue:622-774` (`update_issue_with_flags()`)

**Step 1: Add `--role=` to flag parsing**

In the `while` loop at line ~641, add after the `--description=*` case:

```bash
            --role=*)
                role_val="${1#*=}"
                has_updates=true
                ;;
```

In the space-separated block at line ~675, add `--role` to the pattern and case:

```bash
            --status|--priority|--assignee|--role|--description|--blocks|--depends-on|--parent-of|--relates-to)
```

And in the inner case:

```bash
                    --role) role_val="$2"; has_updates=true ;;
```

Add the local declaration at line ~636:

```bash
    local role_val=""
```

Add the update call after the `assignee` block (line ~751):

```bash
    if [[ -n "$role_val" || "$role_val" == "" ]]; then
        # Only update if --role was explicitly passed (even if empty to clear)
        # We need a flag to distinguish "not passed" from "passed as empty"
        if [[ "$has_role_update" == "true" ]]; then
            update_issue "$id" "role" "$role_val"
            changes="${changes}role=$role_val "
        fi
    fi
```

Actually, the simpler approach: use a sentinel. Declare `local role_val="__unset__"` and check `[[ "$role_val" != "__unset__" ]]`. This lets `--role=` (empty) clear the field.

```bash
    local role_val="__unset__"
```

In the flag parsing, set `role_val` to the value (including empty string).

In the update section:

```bash
    if [[ "$role_val" != "__unset__" ]]; then
        update_issue "$id" "role" "$role_val"
        changes="${changes}role=$role_val "
    fi
```

Update the error messages listing valid flags (line ~694 and ~703) to include `--role`.

**Step 2: Run tests**

Run: `bash tests/test_git_style_flags.sh`
Expected: PASS on "role flag" tests, but FAIL on "role stored in issue data" because `show_issue` doesn't display it yet.

**Step 3: Commit**

```bash
git add bin/git-issue
git commit -m "feat: add --role flag to update_issue_with_flags"
```

---

### Task 3: Display `role` in `show_issue` and `list_issues`

**Files:**
- Modify: `bin/git-issue:460-533` (`show_issue()`)
- Modify: `bin/git-issue:426-458` (`list_issues()`)

**Step 1: Add role extraction and display in `show_issue`**

After the `assignee` extraction (line ~494), add:

```bash
    local role=$(get_field_value "$front_matter" "role")
```

After the assignee display (line ~519), add:

```bash
    [[ -n "$role" ]] && echo "Role: $role"
```

**Step 2: Add role display in `list_issues`**

In `list_issues()`, after extracting assignee (line ~438), add:

```bash
            role=$(echo "$data" | grep "^role:" | head -1 | cut -d' ' -f2-)
```

In the format output (line ~453), modify to include role:

```bash
            echo -ne "${color}#${id} [${status_val}] ${title} (P: ${priority})"
            [ -n "$role" ] && echo -n " [$role]"
            [ -n "$assignee" ] && echo -n " -> $assignee"
            echo -e "${NC}"
```

Note: `list_issues` uses `->` (ASCII arrow) while the actual output shows `→` (Unicode). Match existing style.

**Step 3: Run tests**

Run: `bash tests/test_git_style_flags.sh`
Expected: All role tests PASS.

**Step 4: Commit**

```bash
git add bin/git-issue
git commit -m "feat: display role in show and list output"
```

---

### Task 4: Add `--role=` filter to `list_ready_issues`

**Files:**
- Modify: `bin/git-issue:2262-2329` (`list_ready_issues()`)
- Modify: `bin/git-issue` (command dispatch for `ready`)

**Step 1: Write the failing test**

Create `tests/test_roles.sh`:

```bash
#!/bin/bash
# Test role-based filtering

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"

TEST_DIR="/tmp/git-issue-role-test-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0

run_test() {
    local test_name="$1"
    local command="$2"
    local expected_result="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Testing $test_name... "

    local result
    result=$(eval "$command" 2>&1)
    local exit_code=$?

    if [[ "$result" == *"$expected_result"* ]]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected to contain: $expected_result"
        echo "  Got: $result (exit code: $exit_code)"
    fi
}

run_test_not_contains() {
    local test_name="$1"
    local command="$2"
    local unexpected="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Testing $test_name... "

    local result
    result=$(eval "$command" 2>&1)

    if [[ "$result" != *"$unexpected"* ]]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected NOT to contain: $unexpected"
        echo "  Got: $result"
    fi
}

echo -e "${BLUE}Testing Role-Based Filtering${NC}"
echo "============================"
echo ""

# Create issues with different roles
echo "Setting up test issues..."
ID1=$(git issue create "Coder task 1" 2>&1 | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
ID2=$(git issue create "Reviewer task" 2>&1 | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
ID3=$(git issue create "Coder task 2" 2>&1 | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
ID4=$(git issue create "No role task" 2>&1 | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)

git issue update "$ID1" --role=coder >/dev/null 2>&1
git issue update "$ID2" --role=reviewer >/dev/null 2>&1
git issue update "$ID3" --role=coder >/dev/null 2>&1
# ID4 has no role

echo "Created: $ID1 (coder), $ID2 (reviewer), $ID3 (coder), $ID4 (no role)"
echo ""

# Test ready --role filtering
run_test "ready --role=coder shows coder tasks" \
    "git issue ready --role=coder" "Coder task 1"

run_test "ready --role=coder shows second coder task" \
    "git issue ready --role=coder" "Coder task 2"

run_test_not_contains "ready --role=coder excludes reviewer task" \
    "git issue ready --role=coder" "Reviewer task"

run_test_not_contains "ready --role=coder excludes no-role task" \
    "git issue ready --role=coder" "No role task"

run_test "ready --role=reviewer shows reviewer task" \
    "git issue ready --role=reviewer" "Reviewer task"

run_test_not_contains "ready --role=reviewer excludes coder tasks" \
    "git issue ready --role=reviewer" "Coder task 1"

# Test ready without --role shows everything
run_test "ready (no filter) shows all" \
    "git issue ready" "Coder task 1"
run_test "ready (no filter) includes reviewer" \
    "git issue ready" "Reviewer task"
run_test "ready (no filter) includes no-role" \
    "git issue ready" "No role task"

# Test queue alias
run_test "queue alias works" \
    "git issue queue coder" "Coder task 1"

run_test_not_contains "queue alias filters correctly" \
    "git issue queue coder" "Reviewer task"

# Cleanup
echo ""
echo "Results: $TESTS_PASSED/$TESTS_RUN passed"
rm -rf "$TEST_DIR"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    exit 0
else
    exit 1
fi
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_roles.sh`
Expected: FAIL — `--role` is unknown flag to ready, `queue` is unknown command.

**Step 3: Add `--role=` parameter to `list_ready_issues`**

Modify the function signature to accept arguments:

```bash
list_ready_issues() {
    local role_filter=""

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --role=*)
                role_filter="${1#*=}"
                ;;
            --role)
                role_filter="$2"
                shift
                ;;
            *)
                echo -e "${RED}Error: Unknown flag '$1'${NC}" >&2
                echo "Usage: git issue ready [--role=<role>]" >&2
                return 1
                ;;
        esac
        shift
    done

    ensure_edge_index_current
    # ... rest of function
```

Inside the loop, after extracting assignee (line ~2304), add role extraction:

```bash
        local role
        role=$(echo "$data" | grep "^role:" | head -1 | cut -d' ' -f2-)
```

After the assignee extraction, add the role filter check:

```bash
        # Filter by role if specified
        if [[ -n "$role_filter" && "$role" != "$role_filter" ]]; then
            continue
        fi
```

In the line formatting (line ~2316), add role display:

```bash
        local line="#${id} [${status_val}]  ${title}  (P: ${priority})"
        [[ -n "$role" ]] && line="${line} [${role}]"
        [[ -n "$assignee" ]] && line="${line} -> ${assignee}"
```

**Step 4: Update command dispatch for `ready` and add `queue`**

In the case statement, modify `ready)` to pass args:

```bash
    ready)
        shift
        list_ready_issues "$@"
        ;;
```

Add `queue)` command:

```bash
    queue)
        if [ $# -lt 2 ]; then
            echo -e "${RED}Error: 'queue' requires a role name${NC}"
            echo "Usage: git issue queue <role>"
            exit 1
        fi
        list_ready_issues "--role=$2"
        ;;
```

**Step 5: Run tests**

Run: `bash tests/test_roles.sh`
Expected: All PASS.

**Step 6: Commit**

```bash
git add bin/git-issue tests/test_roles.sh
git commit -m "feat: add --role filter to ready, add queue command"
```

---

### Task 5: Update usage text

**Files:**
- Modify: `bin/git-issue:214-247` (`usage()`)

**Step 1: Update usage**

Update the `ready` line:

```bash
    echo "  ready [--role=<role>]                   List issues ready to work on (sorted by priority)"
```

Add queue after ready:

```bash
    echo "  queue <role>                            List ready issues for a given role"
```

**Step 2: Run quick sanity check**

Run: `git issue --help 2>&1 | grep -E 'ready|queue'`
Expected: Both lines appear.

**Step 3: Commit**

```bash
git add bin/git-issue
git commit -m "docs: update usage for ready --role and queue"
```

---

### Task 6: Extend status machine DSL to parse `(role=X)` on transitions

**Files:**
- Modify: `bin/git-issue-compile-statuses`

**Step 1: Write a test definition file**

Create `tests/test_statuses_with_roles`:

```
mode: permissive

status: open        | default | New issue
status: in_progress | yellow  | Working
status: review      | blue    | Under review
status: closed      | gray    | Done

transition: open → in_progress
transition: in_progress → review (role=reviewer)
transition: review → in_progress (role=coder)
transition: review → closed (role=)
transition: closed → open
```

**Step 2: Run compiler on it to verify it fails**

Run: `bin/git-issue-compile-statuses tests/test_statuses_with_roles /tmp/test_statuses.bash && cat /tmp/test_statuses.bash`
Expected: The `(role=reviewer)` part is silently ignored because the regex doesn't match it, so the transition line is skipped entirely.

**Step 3: Update the compiler regex**

In `bin/git-issue-compile-statuses`, the transition regex (line ~33) is:

```bash
    elif [[ "$line" =~ ^transition:\ *([a-z_]+)\ *→\ *([a-z_]+)$ ]]; then
```

Change to capture optional `(role=X)`:

```bash
    elif [[ "$line" =~ ^transition:\ *([a-z_]+)\ *→\ *([a-z_]+)(\ *\(role=([a-z_]*)\))?$ ]]; then
        transitions+=("${BASH_REMATCH[1]}→${BASH_REMATCH[2]}")
        if [[ -n "${BASH_REMATCH[3]}" ]]; then
            transition_roles+=("${BASH_REMATCH[1]}→${BASH_REMATCH[2]}=${BASH_REMATCH[4]}")
        fi
```

Add `transition_roles=()` to the declarations at line ~19.

**Step 4: Generate `transition_role()` function**

After the `validate_transition` generation, add:

```bash
# transition_role()
printf '\ntransition_role() {\n    local from="$1" to="$2"\n    case "${from}→${to}" in\n' >> "$output"
if [[ ${#transition_roles[@]} -gt 0 ]]; then
    for tr in "${transition_roles[@]}"; do
        local key="${tr%=*}"
        local val="${tr#*=}"
        printf '        %s) echo "%s" ;;\n' "$key" "$val" >> "$output"
    done
fi
printf '    esac\n}\n' >> "$output"
```

**Step 5: Run compiler and verify output**

Run: `bin/git-issue-compile-statuses tests/test_statuses_with_roles /tmp/test_statuses.bash && cat /tmp/test_statuses.bash`

Expected output includes:

```bash
transition_role() {
    local from="$1" to="$2"
    case "${from}→${to}" in
        in_progress→review) echo "reviewer" ;;
        review→in_progress) echo "coder" ;;
        review→closed) echo "" ;;
    esac
}
```

**Step 6: Clean up test file and commit**

```bash
rm tests/test_statuses_with_roles
git add bin/git-issue-compile-statuses
git commit -m "feat: extend status compiler to parse (role=X) on transitions"
```

---

### Task 7: Apply transition roles in `update_issue_with_flags`

**Files:**
- Modify: `bin/git-issue:732-743` (status update section in `update_issue_with_flags`)

**Step 1: Write a failing test**

Add to `tests/test_roles.sh`, before cleanup. This test requires a custom status machine:

```bash
# Test transition-based role assignment
echo ""
echo "Testing transition-based role assignment..."

# Write custom statuses with role rules
mkdir -p "$TEST_DIR/.git-issue"
cat > "$TEST_DIR/.git-issue/statuses" << 'STATEOF'
mode: permissive

status: open        | default | New issue
status: in_progress | yellow  | Working
status: review      | blue    | Under review
status: closed      | gray    | Done

transition: open → in_progress
transition: in_progress → review (role=reviewer)
transition: review → in_progress (role=coder)
transition: review → closed (role=)
transition: closed → open
STATEOF

# Compile statuses
git-issue-compile-statuses "$TEST_DIR/.git-issue/statuses" "$TEST_DIR/.git-issue/statuses.bash" >/dev/null 2>&1

ID5=$(git issue create "Transition role test" 2>&1 | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
git issue update "$ID5" --status=in_progress >/dev/null 2>&1

# Moving to review should auto-assign role=reviewer
git issue update "$ID5" --status=review >/dev/null 2>&1
run_test "transition sets role to reviewer" \
    "git issue show $ID5" "Role: reviewer"

# Moving back to in_progress should auto-assign role=coder
git issue update "$ID5" --status=in_progress >/dev/null 2>&1
run_test "transition sets role to coder" \
    "git issue show $ID5" "Role: coder"

# Moving to closed should clear role
git issue update "$ID5" --status=review >/dev/null 2>&1
git issue update "$ID5" --status=closed >/dev/null 2>&1
run_test_not_contains "transition clears role on close" \
    "git issue show $ID5" "Role:"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_roles.sh`
Expected: FAIL — transition doesn't change role.

**Step 3: Apply transition role in status update path**

In `update_issue_with_flags`, in the status update block (line ~732):

```bash
    if [[ -n "$status_val" ]]; then
        local current_status
        current_status=$(read_issue_data "$id" | grep -E "^(status|state):" | head -1 | cut -d' ' -f2)
        if [[ -n "$current_status" ]]; then
            check_transition "$current_status" "$status_val" || return 1

            # Apply transition role if configured and not explicitly overridden
            if [[ "$role_val" == "__unset__" ]]; then
                local trans_role
                trans_role=$(transition_role "$current_status" "$status_val" 2>/dev/null)
                if [[ -n "$trans_role" || ( -z "$trans_role" && $(type -t transition_role) == "function" ) ]]; then
                    # transition_role returned (possibly empty string = clear role)
                    # Only act if the function produced output (matched a case)
                    local trans_output
                    trans_output=$(transition_role "$current_status" "$status_val" 2>/dev/null; echo "X")
                    # If function echoed something before "X", it matched
                    if [[ "$trans_output" != "X" ]]; then
                        local new_role="${trans_output%X}"
                        new_role="${new_role%$'\n'}"
                        update_issue "$id" "role" "$new_role"
                        changes="${changes}role=$new_role "
                    fi
                fi
            fi
        fi
        update_issue "$id" "status" "$status_val"
        changes="status=$status_val "
        if [[ "$status_val" == "closed" ]]; then
            cascade_unblock "$id"
        fi
    fi
```

Simpler approach — just check if `transition_role` is defined (it won't be if the compiled file doesn't have it):

```bash
            # Apply transition role if configured and not explicitly overridden
            if [[ "$role_val" == "__unset__" ]] && type -t transition_role &>/dev/null; then
                local trans_role
                trans_role=$(transition_role "$current_status" "$status_val")
                if [[ $? -eq 0 || -n "$trans_role" ]]; then
                    update_issue "$id" "role" "$trans_role"
                    changes="${changes}role=$trans_role "
                fi
            fi
```

Wait — the `transition_role` function as generated doesn't return a specific exit code for matches vs non-matches. We need the compiler to generate it with `return 0` for matches and the default case returning 1. Update Task 6's compiler output:

```bash
transition_role() {
    local from="$1" to="$2"
    case "${from}→${to}" in
        in_progress→review) echo "reviewer"; return 0 ;;
        review→in_progress) echo "coder"; return 0 ;;
        review→closed) echo ""; return 0 ;;
        *) return 1 ;;
    esac
}
```

Then in `update_issue_with_flags`:

```bash
            if [[ "$role_val" == "__unset__" ]] && type -t transition_role &>/dev/null; then
                local trans_role
                if trans_role=$(transition_role "$current_status" "$status_val"); then
                    update_issue "$id" "role" "$trans_role"
                    changes="${changes}role=$trans_role "
                fi
            fi
```

**Step 4: Run tests**

Run: `bash tests/test_roles.sh`
Expected: All PASS.

**Step 5: Commit**

```bash
git add bin/git-issue bin/git-issue-compile-statuses tests/test_roles.sh
git commit -m "feat: apply transition roles on status change"
```

---

### Task 8: Ensure existing presets and compiled files still work

**Files:**
- Check: `share/git-issue/statuses.default`
- Check: `share/git-issue/statuses.beads`

**Step 1: Recompile default preset**

Run: `bin/git-issue-compile-statuses share/git-issue/statuses.default /tmp/default_compiled.bash && cat /tmp/default_compiled.bash`
Expected: Valid output. `transition_role()` function generated with only the default `*) return 1` case (no role assignments).

**Step 2: Recompile beads preset**

Run: `bin/git-issue-compile-statuses share/git-issue/statuses.beads /tmp/beads_compiled.bash && cat /tmp/beads_compiled.bash`
Expected: Same — valid output, empty `transition_role()`.

**Step 3: Run existing test suites**

Run: `bash tests/test_git_style_flags.sh && bash tests/test_roles.sh`
Expected: All PASS.

**Step 4: Recompile project's own statuses**

Run: `bin/git-issue-compile-statuses .git-issue/statuses .git-issue/statuses.bash`
Expected: Success. The compiled file includes the new `transition_role()` function.

**Step 5: Commit the recompiled statuses.bash**

```bash
git add .git-issue/statuses.bash
git commit -m "chore: recompile statuses.bash with transition_role function"
```

---

### Task 9: Run full test suite and verify

**Step 1: Run all relevant tests**

```bash
bash tests/test_git_style_flags.sh
bash tests/test_roles.sh
bash tests/unit_tests.sh
bash tests/integration_tests.sh
```

Expected: All PASS.

**Step 2: Manual smoke test**

```bash
git issue create "Smoke test" --description="Testing role workflow"
# Get the ID from output
git issue update <id> --role=coder
git issue ready --role=coder
git issue queue coder
git issue update <id> --status=closed
git issue show <id>
```

**Step 3: Verify help output**

```bash
git issue --help
```

Expected: Shows `start`, `close`, `reopen`, `ready [--role=<role>]`, `queue <role>` commands.
