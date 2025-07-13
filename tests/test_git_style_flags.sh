#!/bin/bash
# Test git-style flag functionality for git-issue update command

# Setup test environment
TEST_DIR="/tmp/git-issue-flag-test-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"

# Add the git-issue script to PATH for testing
SCRIPT_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
export PATH="$SCRIPT_DIR/bin:$PATH"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Test function
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_result="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Testing $test_name... "
    
    local result
    result=$(eval "$command" 2>&1)
    local exit_code=$?
    
    if [[ "$expected_result" == "success" && $exit_code -eq 0 ]] || \
       [[ "$expected_result" == "failure" && $exit_code -ne 0 ]] || \
       [[ "$result" == *"$expected_result"* ]]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected: $expected_result"
        echo "  Got: $result (exit code: $exit_code)"
    fi
}

echo -e "${BLUE}Testing Git-Style Flag Functionality${NC}"
echo "===================================="
echo ""

# Create test issue
echo "Setting up test issue..."
ISSUE_OUTPUT=$(git issue create "Test issue for flag testing" 2>&1)
ISSUE_ID=$(echo "$ISSUE_OUTPUT" | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
echo "Created issue ID: $ISSUE_ID"
echo ""

# Test 1: Basic flag syntax with equals
run_test "state flag with equals" "git issue update $ISSUE_ID --state=in-progress" "success"

# Test 2: Basic flag syntax with space
run_test "priority flag with space" "git issue update $ISSUE_ID --priority high" "success"

# Test 3: Multiple flags at once
run_test "multiple flags" "git issue update $ISSUE_ID --state=review --priority=critical" "success"

# Test 4: Assignee flag with quotes
run_test "assignee with quotes" "git issue update $ISSUE_ID --assignee='John Doe'" "success"

# Test 5: Invalid flag
run_test "invalid flag" "git issue update $ISSUE_ID --invalid=value" "failure"

# Test 6: Invalid state value
run_test "invalid state" "git issue update $ISSUE_ID --state=invalid" "failure"

# Test 7: Invalid priority value  
run_test "invalid priority" "git issue update $ISSUE_ID --priority=invalid" "failure"

# Test 8: Flag without value
run_test "flag without value" "git issue update $ISSUE_ID --state" "failure"

# Test 9: No flags provided
run_test "no flags" "git issue update $ISSUE_ID" "failure"

# Test 10: Nonexistent issue ID
run_test "nonexistent issue" "git issue update invalid123 --state=done" "failure"

# Test 11: Verify state was actually updated
SHOW_OUTPUT=$(git issue show "$ISSUE_ID" 2>&1)
if echo "$SHOW_OUTPUT" | grep -q "state: review"; then
    echo -e "Verifying state update... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Verifying state update... ${RED}FAIL${NC}"
    echo "  Issue state was not properly updated"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 12: Verify priority was actually updated
if echo "$SHOW_OUTPUT" | grep -q "priority: critical"; then
    echo -e "Verifying priority update... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Verifying priority update... ${RED}FAIL${NC}"
    echo "  Issue priority was not properly updated"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 13: Verify assignee was actually updated
if echo "$SHOW_OUTPUT" | grep -q "assignee: John Doe"; then
    echo -e "Verifying assignee update... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Verifying assignee update... ${RED}FAIL${NC}"
    echo "  Issue assignee was not properly updated"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 14: Test all valid states
for state in open in-progress review done blocked; do
    run_test "valid state: $state" "git issue update $ISSUE_ID --state=$state" "success"
done

# Test 15: Test all valid priorities
for priority in low medium high critical; do
    run_test "valid priority: $priority" "git issue update $ISSUE_ID --priority=$priority" "success"
done

# Test 16: Test backwards compatibility (if implemented)
# This tests the old syntax to ensure we don't break existing scripts
# run_test "legacy syntax" "git issue update $ISSUE_ID state open" "success"

echo ""
echo -e "${BLUE}Test Results:${NC}"
echo "============="
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${NC}"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"