#!/bin/bash
# Test that plumbing optimizations work correctly and maintain compatibility

# Add the git-issue script to PATH for testing (resolve before cd)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"

# Setup test environment
TEST_DIR="/tmp/git-issue-plumbing-test-$$"
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
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected: $expected_result"
        echo "  Got: $result (exit code: $exit_code)"
    fi
}

echo -e "${BLUE}Testing Plumbing Optimizations${NC}"
echo "=============================="
echo ""

# Test 1: Basic create still works
run_test "create issue" "git issue create 'Test plumbing optimization'" "success"

# Get the created issue ID
ISSUE_OUTPUT=$(git issue create "Test issue for plumbing" 2>&1)
ISSUE_ID=$(echo "$ISSUE_OUTPUT" | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
echo "Created test issue ID: $ISSUE_ID"

# Test 2: Show issue works (tests optimized read_issue_data)
run_test "show issue (read optimization)" "git issue show $ISSUE_ID" "success"

# Test 3: Update issue works (tests optimized write_issue_data)
run_test "update issue (write optimization)" "git issue update $ISSUE_ID --status=in_progress" "success"

# Test 4: List issues works
run_test "list issues" "git issue list" "success"

# Test 5: Comment works (tests write optimization)
run_test "add comment (write optimization)" "git issue comment $ISSUE_ID 'Testing optimizations'" "success"

# Test 6: Link works
echo "test file" > test.txt
git add test.txt
git commit -m "Test commit" >/dev/null 2>&1
run_test "link issue (write optimization)" "git issue link $ISSUE_ID HEAD" "success"

# Test 7: Verify git objects are created correctly
echo -n "Verifying git objects... "
ISSUE_REF="refs/notes/issue-$ISSUE_ID"
if git rev-parse --verify "$ISSUE_REF" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Issue ref $ISSUE_REF not found"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 8: Verify issue data is readable via git plumbing
echo -n "Verifying cat-file compatibility... "
TREE_HASH=$(git cat-file -p "$ISSUE_REF" 2>/dev/null | grep "^tree" | cut -d' ' -f2)
BLOB_HASH=$(git ls-tree "$TREE_HASH" 2>/dev/null | awk '{print $3}' | head -1)
ISSUE_DATA=$(git cat-file -p "$BLOB_HASH" 2>/dev/null)
if [[ -n "$ISSUE_DATA" ]] && echo "$ISSUE_DATA" | grep -q "title: Test issue for plumbing"; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Cannot read issue data via git cat-file"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 9: Multiple rapid operations (stress test optimizations)
echo -n "Stress testing rapid operations... "
for i in {1..10}; do
    git issue comment "$ISSUE_ID" "Rapid comment $i" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}FAIL${NC}"
        echo "  Failed on rapid operation $i"
        TESTS_RUN=$((TESTS_RUN + 1))
        break
    fi
done

if [[ $i -eq 10 ]]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 10: Verify cached user name works
echo -n "Testing cached user name... "
USER_ID1=$(git issue create "Test user caching 1" 2>&1 | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
USER_ID2=$(git issue create "Test user caching 2" 2>&1 | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
SHOW1=$(git issue show "$USER_ID1" 2>&1)
SHOW2=$(git issue show "$USER_ID2" 2>&1)
if echo "$SHOW1" | grep -q "Test User" && echo "$SHOW2" | grep -q "Test User"; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  User caching not working properly"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 11: Performance comparison (basic)
echo -n "Basic performance check... "
START_TIME=$(date +%s.%N)
for i in {1..5}; do
    git issue create "Performance test $i" >/dev/null 2>&1
done
END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | bc -l 2>/dev/null || echo "1")

# This should complete in reasonable time (less than 5 seconds for 5 operations)
if (( $(echo "$DURATION < 5.0" | bc -l 2>/dev/null || echo "1") )); then
    echo -e "${GREEN}PASS${NC} (${DURATION}s)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (${DURATION}s - too slow)"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 12: XDG directory mode (if not in git repo)
echo -n "Testing XDG directory mode... "
XDG_TEST_DIR="/tmp/git-issue-xdg-test-$$"
mkdir -p "$XDG_TEST_DIR"
cd "$XDG_TEST_DIR"

XDG_RESULT=$(git issue create "XDG test issue" 2>&1)
if echo "$XDG_RESULT" | grep -q "Created issue"; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  XDG mode failed: $XDG_RESULT"
fi
TESTS_RUN=$((TESTS_RUN + 1))

cd "$TEST_DIR"  # Return to original test dir

echo ""
echo -e "${BLUE}Test Results:${NC}"
echo "============="
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${NC}"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    echo "Plumbing optimizations are working correctly."
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi

# Cleanup
cd /
rm -rf "$TEST_DIR" "$XDG_TEST_DIR"