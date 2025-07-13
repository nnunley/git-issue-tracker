#!/bin/bash
# Test git hooks automatic sync functionality

# Setup test environment
TEST_DIR="/tmp/git-issue-hooks-test-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

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
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected: $expected_result"
        echo "  Got: $result (exit code: $exit_code)"
        return 1
    fi
}

echo -e "${BLUE}Testing Git Hooks Sync Functionality${NC}"
echo "===================================="
echo ""

# Create test git repository
echo "Setting up test git repository..."
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"

# Create initial commit
echo "# Test Repo" > README.md
git add README.md
git commit -m "Initial commit" >/dev/null 2>&1

echo "Repository setup complete"
echo ""

# Test 1: setup-sync status (should show not configured)
run_test "initial sync status" "git issue setup-sync status" "not fully configured"

# Test 2: setup-sync enable
run_test "enable sync" "git issue setup-sync enable" "Automatic git notes sync is now enabled"

# Test 3: Verify hooks were installed
echo -n "Verifying hooks installation... "
if [[ -x ".git/hooks/post-merge" && -x ".git/hooks/pre-push" ]]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Hooks not properly installed"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 4: Verify git config was set
echo -n "Verifying git config... "
SYNC_ENABLED=$(git config --get git-issue.sync.enabled 2>/dev/null)
if [[ "$SYNC_ENABLED" == "true" ]]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Git config not set correctly: $SYNC_ENABLED"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 5: setup-sync status (should show configured)
run_test "sync status after enable" "git issue setup-sync status" "fully configured and enabled"

# Test 6: Create an issue to test sync
ISSUE_OUTPUT=$(git issue create "Test sync issue" --description="Testing sync functionality" 2>&1)
ISSUE_ID=$(echo "$ISSUE_OUTPUT" | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
echo "Created test issue: $ISSUE_ID"

# Test 7: Verify issue notes exist
echo -n "Verifying issue notes creation... "
if git rev-parse "refs/notes/issue-$ISSUE_ID" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Issue notes not created"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 8: Test hook content (basic check)
echo -n "Verifying hook content... "
if grep -q "git-issue" .git/hooks/post-merge && grep -q "refs/notes/issue" .git/hooks/pre-push; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Hook content not as expected"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 9: Test disable sync
run_test "disable sync" "git issue setup-sync disable" "Automatic git notes sync has been disabled"

# Test 10: Verify config was disabled
echo -n "Verifying sync disabled... "
SYNC_DISABLED=$(git config --get git-issue.sync.enabled 2>/dev/null)
if [[ "$SYNC_DISABLED" == "false" ]]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Sync not properly disabled: $SYNC_DISABLED"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 11: Test XDG mode rejection
echo -n "Testing XDG mode rejection... "
XDG_TEST_DIR="/tmp/git-issue-xdg-sync-test-$$"
mkdir -p "$XDG_TEST_DIR"
cd "$XDG_TEST_DIR"

XDG_RESULT=$(git issue setup-sync enable 2>&1)
if echo "$XDG_RESULT" | grep -q "only available in git repositories"; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  XDG mode should reject sync setup"
fi
TESTS_RUN=$((TESTS_RUN + 1))

cd "$TEST_DIR"  # Return to git repo

# Test 12: Re-enable and test backup functionality
git issue setup-sync enable >/dev/null 2>&1
echo "existing hook" > .git/hooks/post-merge
run_test "backup existing hooks" "git issue setup-sync enable" "backing up to post-merge.backup"

# Test 13: Verify backup was created
echo -n "Verifying hook backup... "
if [[ -f ".git/hooks/post-merge.backup" ]]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Hook backup not created"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 14: Test restore functionality
run_test "restore backed up hooks" "git issue setup-sync disable" "Restored original post-merge hook"

# Test 15: Verify hook was restored
echo -n "Verifying hook restoration... "
if [[ -f ".git/hooks/post-merge" ]] && grep -q "existing hook" .git/hooks/post-merge; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Hook not properly restored"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 16: Test invalid setup-sync argument
run_test "invalid setup-sync argument" "git issue setup-sync invalid" "Usage: git issue setup-sync"

echo ""
echo -e "${BLUE}Test Results:${NC}"
echo "============="
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${NC}"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo -e "${GREEN}All hooks sync tests passed!${NC}"
    echo "Git hooks automatic sync functionality is working correctly."
    exit 0
else
    echo -e "${RED}Some hooks sync tests failed.${NC}"
    exit 1
fi

# Cleanup
cd /
rm -rf "$TEST_DIR" "$XDG_TEST_DIR"