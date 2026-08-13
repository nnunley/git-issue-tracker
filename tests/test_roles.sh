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
    "git issue show $ID5" "role: reviewer"

# Moving back to in_progress should auto-assign role=coder
git issue update "$ID5" --status=in_progress >/dev/null 2>&1
run_test "transition sets role to coder" \
    "git issue show $ID5" "role: coder"

# Moving to closed should clear role (role=)
git issue update "$ID5" --status=review >/dev/null 2>&1
git issue update "$ID5" --status=closed >/dev/null 2>&1
run_test_not_contains "transition clears role on close" \
    "git issue show $ID5" "role:"

# Cleanup
echo ""
echo "Results: $TESTS_PASSED/$TESTS_RUN passed"
rm -rf "$TEST_DIR"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    exit 0
else
    exit 1
fi
