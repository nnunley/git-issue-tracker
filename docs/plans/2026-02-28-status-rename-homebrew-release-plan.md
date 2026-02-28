# Status Rename, Homebrew & Release Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename `state` to `status` with Beads-aligned values, add a migration command, tag v1.0.0-rc1, and publish a Homebrew tap.

**Architecture:** Big-bang rename of field name and values across all code, tests, and docs. Read path accepts both `state:` and `status:` for backward compat. One-time migration command rewrites stored data. Then tag, release, and publish tap.

**Tech Stack:** Bash, git plumbing, gh CLI, Homebrew Ruby formula

---

### Task 1: Rename STATES array and values in bin/git-issue

**Files:**
- Modify: `bin/git-issue`

**Step 1: Rename the array and update values**

In `bin/git-issue`, make these changes:

Line 15-16, rename array and values:
```bash
# Issue statuses and priorities
STATUSES=("open" "in_progress" "review" "closed" "blocked" "deferred")
```

**Step 2: Update field extraction in list_issues()**

Line 308, change:
```bash
state=$(echo "$data" | grep "^state:" | cut -d' ' -f2)
```
to:
```bash
status=$(echo "$data" | grep -E "^(status|state):" | head -1 | cut -d' ' -f2)
```

Lines 312-319, update case statement variable and values:
```bash
case "$status" in
    closed) color=$GRAY ;;
    blocked) color=$RED ;;
    in_progress) color=$YELLOW ;;
    review) color=$BLUE ;;
    deferred) color=$YELLOW ;;
    *) color=$NC ;;
esac
```

Line 322, update display:
```bash
echo -ne "${color}#${id} [${status}] ${title} (P: ${priority})"
```

**Step 3: Update show_issue()**

Line 356, change field extraction:
```bash
local status=$(get_field_value "$front_matter" "status")
[[ -z "$status" ]] && status=$(get_field_value "$front_matter" "state")
```

Line 378, update display label:
```bash
echo "Status: $status"
```

**Step 4: Update create_issue() default value**

Line 282, change:
```bash
status: open
```

**Step 5: Update update_issue() field validation**

Lines 412-418, rename field case and array:
```bash
status)
    if [[ ! " ${STATUSES[*]} " =~ " ${value} " ]]; then
        echo -e "${RED}Invalid status: $value${NC}"
        echo "Valid statuses: ${STATUSES[*]}"
        return 1
    fi
    ;;
```

Also update the field name check at line 294 (the `case "$field"` switch) to accept `status` instead of `state`.

**Step 6: Update update_issue_with_flags()**

Line 474: `local status="" priority="" ...`

Lines 481-483: `--status=*) status="${1#*=}" ...`

Line 513: Update the flag list to use `--status`

Line 519: `--status) status="$2" ...`

Lines 531-532: Update error messages to reference `--status`

Lines 546-553: Update validation:
```bash
if [[ -n "$status" ]]; then
    case "$status" in
        "open"|"in_progress"|"review"|"closed"|"blocked"|"deferred") ;;
        *) echo -e "${RED}Error: Invalid status '$status'${NC}" >&2
           echo "Valid statuses: open, in_progress, review, closed, blocked, deferred" >&2
           return 1 ;;
    esac
fi
```

Lines 568-574: Update state update and cascade:
```bash
if [[ -n "$status" ]]; then
    update_issue "$id" "status" "$status"
    changes="status=$status "
    if [[ "$status" == "closed" ]]; then
        cascade_unblock "$id"
    fi
fi
```

**Step 7: Update usage() help text**

Line 110: `--status=<status>` instead of `--state=<state>`
Line 121: `topologically sorted ordering of non-closed issues`
Line 127: `--status=in_progress` instead of `--state=in-progress`

**Step 8: Update dependency management functions**

All occurrences of `grep "^state:"` should become `grep -E "^(status|state):"` for read compat.
All `update_issue "$id" "state"` should become `update_issue "$id" "status"`.
All comparisons to `"done"` should become `"closed"`.
All comparisons to `"in-progress"` should become `"in_progress"`.

Specific locations in cascade_unblock(), dep_add(), dep_remove():
- `grep "^state:"` → `grep -E "^(status|state):"`
- `"state" "blocked"` → `"status" "blocked"`
- `"state" "open"` → `"status" "open"`
- `!= "done"` → `!= "closed"`

**Step 9: Update ready and topo commands**

- ready: `grep "^state:"` → `grep -E "^(status|state):"`, `"done"` → `"closed"`
- topo: same changes
- ready display: `[${state}]` → `[${status}]`

**Step 10: Update export function**

Line 1037-1044: change `state` extraction and mapping:
```bash
local status=$(get_field_value "$front_matter" "status")
[[ -z "$status" ]] && status=$(get_field_value "$front_matter" "state")

local gh_state="open"
case "$status" in
    closed) gh_state="closed" ;;
esac
```

**Step 11: Update commit trailer auto-close**

Lines 1318-1322: change `done` to `closed`:
```bash
if [[ "$trailer_type" == "fixes" || "$trailer_type" == "closes" ]]; then
    echo ""
    echo -e "${YELLOW}Updating issue status...${NC}"
    update_issue "$issue_id" status closed
```

**Step 12: Update manual issue creation (add/legacy)**

Line 2432: `status: open` instead of `state: open`

**Step 13: Update main case dispatch**

Line 2483: Update usage help for update command to reference `--status=`

**Step 14: Run shellcheck to verify no errors introduced**

Run: `shellcheck --severity=error --format=gcc bin/git-issue`
Expected: no errors

**Step 15: Commit**

```bash
git add bin/git-issue
git commit -m "refactor: rename state to status with Beads-aligned values

BREAKING: --state= flag renamed to --status=
Values changed: in-progress→in_progress, done→closed, added deferred
Read path accepts both state: and status: in stored data"
```

---

### Task 2: Update bin/git-issue-status

**Files:**
- Modify: `bin/git-issue-status`

**Step 1: Update field extraction and display**

Line 46: change `grep "^state:"` to `grep -E "^(status|state):"` with `head -1`

Lines 49-54: update case values:
```bash
case "$status" in
    open) open_count=$((open_count + 1)) ;;
    in_progress|in-progress) in_progress_count=$((in_progress_count + 1)) ;;
    closed|done) done_count=$((done_count + 1)) ;;
    blocked) blocked_count=$((blocked_count + 1)) ;;
esac
```

Rename variable from `state` to `status` throughout.

Line 70: Change `"By State:"` to `"By Status:"`

**Step 2: Commit**

```bash
git add bin/git-issue-status
git commit -m "refactor: rename state to status in git-issue-status"
```

---

### Task 3: Add migrate-status command

**Files:**
- Modify: `bin/git-issue`

**Step 1: Add migrate_status() function**

Add before the main case dispatch (around line 2400):

```bash
# Migrate issue data from state→status field and old values to new
migrate_status() {
    local migrated=0
    local skipped=0

    echo -e "${BLUE}Migrating issues from state→status...${NC}"

    for ref in $(list_all_issues); do
        local id=$(extract_issue_id "$ref")
        local data
        data=$(read_issue_data "$id" 2>/dev/null) || continue

        # Check if already migrated (has status: field)
        if echo "$data" | grep -q "^status:"; then
            skipped=$((skipped + 1))
            continue
        fi

        # Check if has old state: field
        if ! echo "$data" | grep -q "^state:"; then
            skipped=$((skipped + 1))
            continue
        fi

        # Replace field name and map values
        local new_data
        new_data=$(echo "$data" | sed \
            -e 's/^state: in-progress$/status: in_progress/' \
            -e 's/^state: done$/status: closed/' \
            -e 's/^state: /status: /')

        write_issue_data "$id" "$new_data"
        migrated=$((migrated + 1))
        echo -e "  Migrated #$id"
    done

    echo ""
    echo -e "${GREEN}Migration complete: $migrated migrated, $skipped skipped${NC}"
}
```

**Step 2: Add case dispatch entry**

In the main case statement, add:
```bash
    migrate-status)
        migrate_status
        ;;
```

**Step 3: Commit**

```bash
git add bin/git-issue
git commit -m "feat: add migrate-status command for state→status migration"
```

---

### Task 4: Update all test files

**Files:**
- Modify: `tests/test_runner.sh`
- Modify: `tests/integration_tests.sh`
- Modify: `tests/unit_tests.sh`
- Modify: `tests/test_deps.sh`
- Modify: `tests/test_git_style_flags.sh`
- Modify: `tests/test_descriptions.sh`
- Modify: `tests/test_plumbing_optimizations.sh`
- Modify: `tests/test_github_integration.sh`

**Step 1: Update tests/unit_tests.sh**

- Rename `test_states_validation` → `test_statuses_validation`
- Change `STATES` → `STATUSES`
- Update value assertions: `in-progress` → `in_progress`, `done` → `closed`, add `deferred`
- Update run_test call name

**Step 2: Update tests/test_runner.sh**

- `--state=in-progress` → `--status=in_progress`
- `--state=invalid-state` → `--status=invalid_status`
- `"State: in-progress"` → `"Status: in_progress"`
- `"[open]"` stays the same (display format unchanged)
- Update all comments referencing state

**Step 3: Update tests/integration_tests.sh**

- All `--state=` → `--status=`
- `--state=in-progress` → `--status=in_progress`
- `--state=done` → `--status=closed`
- `--state=blocked` → `--status=blocked`
- `"State: done"` → `"Status: closed"`
- `"state: open"` in raw data assertions → `"status: open"`

**Step 4: Update tests/test_deps.sh**

- `"State: open"` → `"Status: open"`
- `--state=done` → `--status=closed`
- Update all state management test comments

**Step 5: Update tests/test_git_style_flags.sh**

- `--state=in-progress` → `--status=in_progress`
- `--state=review` → `--status=review`
- `--state=invalid` → `--status=invalid`
- `--state=done` → `--status=closed`
- `--state` → `--status` (bare flag test)
- `"state: review"` → `"status: review"` in verification
- Loop: `for state in open in-progress review done blocked` → `for status in open in_progress review closed blocked deferred`
- `--state=$state` → `--status=$status`

**Step 6: Update tests/test_descriptions.sh**

- `--state=in-progress` → `--status=in_progress`
- `"state: in-progress"` → `"status: in_progress"` in verification

**Step 7: Update tests/test_plumbing_optimizations.sh**

- `--state=in-progress` → `--status=in_progress`

**Step 8: Update tests/test_github_integration.sh**

- `"state": "open"` stays (this is GitHub API format, not git-issue format)
- `"state":` in grep patterns stays (checking GitHub export format)

**Step 9: Run all tests**

```bash
./tests/unit_tests.sh
./tests/integration_tests.sh
./tests/test_runner.sh
./tests/test_deps.sh
./tests/test_git_style_flags.sh
```

Expected: all pass

**Step 10: Commit**

```bash
git add tests/
git commit -m "test: update all tests for state→status rename"
```

---

### Task 5: Update documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/ISSUE_COMMIT_LINKING.md`
- Modify: `examples/hash-issue-demo.md`

**Step 1: Update README.md**

- `--state=` → `--status=` in all examples and command table
- `in-progress` → `in_progress` in examples
- Rename "States" section to "Statuses", update values:
  ```
  ### Statuses
  - `open` - New issue
  - `in_progress` - Being worked on
  - `review` - Under review
  - `closed` - Completed
  - `blocked` - Blocked by dependencies
  - `deferred` - On hold
  ```
- `state: in-progress` → `status: in_progress` in YAML examples
- `--state=done` → `--status=closed` in dep examples

**Step 2: Update docs/ISSUE_COMMIT_LINKING.md**

- `state in-progress` → `--status=in_progress`
- `state done` → `--status=closed`

**Step 3: Update examples/hash-issue-demo.md**

- `state in-progress` → `--status=in_progress`
- `# Update issue state` → `# Update issue status`

**Step 4: Commit**

```bash
git add README.md docs/ examples/
git commit -m "docs: update all documentation for state→status rename"
```

---

### Task 6: Run migration on this repo

**Step 1: Check current issue data**

```bash
bin/git-issue list
```

Note which issues have old `state:` field.

**Step 2: Run migration**

```bash
bin/git-issue migrate-status
```

Expected: reports count of migrated issues.

**Step 3: Verify migration**

```bash
bin/git-issue list
bin/git-issue show <any-issue-id>
```

Verify output shows `Status:` not `State:`, and values are correct.

**Step 4: Run full test suite to ensure nothing is broken**

```bash
./tests/unit_tests.sh && ./tests/integration_tests.sh && ./tests/test_runner.sh && ./tests/test_deps.sh
```

**Step 5: Commit any migration-related changes (notes refs)**

Note: git notes changes are in refs, not in the working tree. No commit needed for the data itself — it lives in git refs. But push the notes:

```bash
git push origin 'refs/notes/issue-*'
```

---

### Task 7: Update Homebrew formula and create release

**Files:**
- Modify: `Formula/git-issue.rb`

**Step 1: Verify CI is green**

```bash
git push origin main
# Wait for CI to pass
gh run list --limit 1
```

**Step 2: Tag and create release**

```bash
git tag v1.0.0-rc1
git push origin v1.0.0-rc1
gh release create v1.0.0-rc1 --title "v1.0.0-rc1" --notes "First release candidate.

Changes:
- Renamed state field to status (Beads alignment)
- Status values: open, in_progress, review, closed, blocked, deferred
- Dependency graph with blocking, cycle detection, topological sort
- Homebrew formula
- Comprehensive test suite
- ShellCheck clean

BREAKING: --state= flag renamed to --status="
```

**Step 3: Get tarball SHA256**

```bash
curl -sL https://github.com/nnunley/git-issue-tracker/archive/refs/tags/v1.0.0-rc1.tar.gz | shasum -a 256
```

**Step 4: Update formula with release URL**

In `Formula/git-issue.rb`, add url and sha256 before `head`:
```ruby
url "https://github.com/nnunley/git-issue-tracker/archive/refs/tags/v1.0.0-rc1.tar.gz"
sha256 "<computed-hash>"
version "1.0.0-rc1"
```

**Step 5: Update formula test to use --status**

In the test block, update any `--state` references to `--status`.

**Step 6: Commit**

```bash
git add Formula/git-issue.rb
git commit -m "chore: update formula for v1.0.0-rc1 release"
git push origin main
```

---

### Task 8: Create Homebrew tap repo

**Step 1: Create the repo on GitHub**

```bash
gh repo create nnunley/homebrew-git-issue --public --description "Homebrew tap for git-issue"
```

**Step 2: Clone and add formula**

```bash
cd /tmp
git clone https://github.com/nnunley/homebrew-git-issue.git
cd homebrew-git-issue
cp /path/to/git-issue-tracker/Formula/git-issue.rb .
git add git-issue.rb
git commit -m "Add git-issue formula v1.0.0-rc1"
git push origin main
```

**Step 3: Verify end-to-end install**

```bash
brew untap nnunley/git-issue 2>/dev/null || true
brew tap nnunley/git-issue
brew install git-issue
git issue --help
```

Expected: installs and runs successfully.

**Step 4: Mark issues done**

```bash
bin/git-issue update cde30c7 --status=closed
bin/git-issue update a16c143 --status=closed
bin/git-issue update 1027c78 --status=closed
bin/git-issue update a1005ab --status=closed
```
