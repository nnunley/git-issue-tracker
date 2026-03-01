#!/bin/bash
# Test issue description functionality

# Add the git-issue script to PATH for testing (resolve before cd)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"

# Setup test environment
TEST_DIR="/tmp/git-issue-desc-test-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"

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
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected: $expected_result"
        echo "  Got: $result (exit code: $exit_code)"
        return 1
    fi
}

echo -e "${BLUE}Testing Issue Description Functionality${NC}"
echo "======================================="
echo ""

# Test 1: Create issue with description using equals syntax
run_test "create with description (equals)" "git issue create 'Test issue' --description='This is a test description'" "success"

# Get the created issue ID
ISSUE_OUTPUT=$(git issue create "Test issue for descriptions" --description="A detailed description of the issue" 2>&1)
ISSUE_ID=$(echo "$ISSUE_OUTPUT" | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
echo "Created test issue ID: $ISSUE_ID"

# Test 2: Create issue with description using space syntax
run_test "create with description (space)" "git issue create 'Another test' --description 'Space separated description'" "success"

# Test 3: Show issue displays description
SHOW_OUTPUT=$(git issue show "$ISSUE_ID" 2>&1)
if echo "$SHOW_OUTPUT" | grep -q "Description: A detailed description of the issue"; then
    echo -e "Show displays description... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Show displays description... ${RED}FAIL${NC}"
    echo "  Description not found in show output"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 4: Update issue description
run_test "update description" "git issue update $ISSUE_ID --description='Updated description text'" "success"

# Test 5: Verify description was updated
UPDATED_SHOW=$(git issue show "$ISSUE_ID" 2>&1)
if echo "$UPDATED_SHOW" | grep -q "Description: Updated description text"; then
    echo -e "Description update verification... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Description update verification... ${RED}FAIL${NC}"
    echo "  Updated description not found"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 6: Create issue without description (should work)
run_test "create without description" "git issue create 'No description issue'" "success"

# Test 7: Verify empty description doesn't break show
NO_DESC_OUTPUT=$(git issue create "No desc test" 2>&1)
NO_DESC_ID=$(echo "$NO_DESC_OUTPUT" | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
SHOW_NO_DESC=$(git issue show "$NO_DESC_ID" 2>&1)
if echo "$SHOW_NO_DESC" | grep -q "Title: No desc test" && ! echo "$SHOW_NO_DESC" | grep -q "Description:"; then
    echo -e "Show without description... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Show without description... ${RED}FAIL${NC}"
    echo "  Show output incorrect for issue without description"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 8: Multi-line description with equals
run_test "multiline description (equals)" "git issue create 'Multiline test' --description='Line 1\nLine 2\nLine 3'" "success"

# Test 9: Description with special characters
run_test "description with special chars" "git issue create 'Special chars' --description='Description with \"quotes\" and \$variables'" "success"

# Test 10: Empty description update
run_test "empty description update" "git issue update $ISSUE_ID --description=''" "success"

# Test 11: Multiple flags including description
run_test "multiple flags with description" "git issue update $ISSUE_ID --status=in_progress --priority=high --description='Multi-flag update test'" "success"

# Test 12: Verify multiple flag update
MULTI_SHOW=$(git issue show "$ISSUE_ID" 2>&1)
if echo "$MULTI_SHOW" | grep -qi "status:.*in_progress" && \
   echo "$MULTI_SHOW" | grep -qi "priority:.*high" && \
   echo "$MULTI_SHOW" | grep -q "Description: Multi-flag update test"; then
    echo -e "Multiple flag update verification... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Multiple flag update verification... ${RED}FAIL${NC}"
    echo "  Multiple flags not properly applied"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 13: Long description (stress test)
LONG_DESC="This is a very long description that contains multiple sentences and should test how well the system handles longer text content. It includes various punctuation marks, numbers like 123 and 456, and should still work correctly when stored and retrieved from the git notes system."
run_test "long description" "git issue create 'Long desc test' --description='$LONG_DESC'" "success"

# Test 14: Description with newlines in show output
NEWLINE_DESC="First line\nSecond line\nThird line"
NEWLINE_OUTPUT=$(git issue create "Newline test" --description="$NEWLINE_DESC" 2>&1)
NEWLINE_ID=$(echo "$NEWLINE_OUTPUT" | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
NEWLINE_SHOW=$(git issue show "$NEWLINE_ID" 2>&1)
if echo "$NEWLINE_SHOW" | grep -q "First line"; then
    echo -e "Newline description handling... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "Newline description handling... ${RED}FAIL${NC}"
    echo "  Newlines not properly handled"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 15: Invalid flag combination
run_test "invalid description flag" "git issue update $ISSUE_ID --invalid-desc='test'" "failure"

echo ""
echo -e "${BLUE}Test Results:${NC}"
echo "============="
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${NC}"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo -e "${GREEN}All description tests passed!${NC}"
    echo "Issue description functionality is working correctly."
    exit 0
else
    echo -e "${RED}Some description tests failed.${NC}"
    exit 1
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"