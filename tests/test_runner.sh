#!/bin/bash
# Test runner for git-issue - uses lightweight bash testing
# No external dependencies - pure bash assertions

set -e

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test state
CURRENT_TEST=""
TEST_REPO=""

# Test utilities
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $message"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $message"
        echo -e "    Expected: '$expected'"
        echo -e "    Actual:   '$actual'"
    fi
}

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local message="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $message"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $message"
        echo -e "    Looking for: '$needle'"
        echo -e "    In: '$haystack'"
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local command="$2"
    local message="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$command" >/dev/null 2>&1; then
        actual_code=0
    else
        actual_code=$?
    fi
    
    if [[ "$expected_code" == "$actual_code" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $message"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $message"
        echo -e "    Expected exit code: $expected_code"
        echo -e "    Actual exit code: $actual_code"
    fi
}

# Test setup/teardown
setup_test_repo() {
    TEST_REPO="/tmp/git-issue-test-$$"
    mkdir -p "$TEST_REPO"
    cd "$TEST_REPO"
    git init >/dev/null 2>&1
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "# Test Repo" > README.md
    git add README.md
    git commit -m "Initial commit" >/dev/null 2>&1
}

cleanup_test_repo() {
    if [[ -n "$TEST_REPO" && -d "$TEST_REPO" ]]; then
        cd /tmp
        rm -rf "$TEST_REPO"
    fi
}

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    CURRENT_TEST="$test_name"
    echo -e "${BLUE}Running: $test_name${NC}"
    
    setup_test_repo
    $test_function
    cleanup_test_repo
}

# Add git-issue to PATH for testing (use absolute path so cd doesn't break it)
SCRIPT_DIR_RUNNER="$(cd "$(dirname "$0")" && pwd)"
export PATH="$SCRIPT_DIR_RUNNER/../bin:$PATH"

# Test functions
test_issue_creation() {
    local output
    output=$(git issue create "Test issue creation")
    
    assert_contains "Created issue" "$output" "Should confirm issue creation"
    assert_contains "Test issue creation" "$output" "Should include issue title"
}

test_issue_listing() {
    # Create a test issue first
    git issue create "Test listing issue" >/dev/null 2>&1
    
    local output
    output=$(git issue list)
    
    assert_contains "Test listing issue" "$output" "Should list created issue"
    assert_contains "[open]" "$output" "Should show default state"
}

test_issue_update() {
    # Create and get ID
    local create_output
    create_output=$(git issue create "Test update issue")
    local issue_id
    issue_id=$(echo "$create_output" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    # Update state
    local update_output
    update_output=$(git issue update "$issue_id" --state=in-progress)

    assert_contains "Updated issue" "$update_output" "Should confirm update"

    # Verify update
    local show_output
    show_output=$(git issue show "$issue_id")
    assert_contains "State: in-progress" "$show_output" "Should show updated state"
}

test_issue_comments() {
    # Create and get ID
    local create_output
    create_output=$(git issue create "Test comment issue")
    local issue_id
    issue_id=$(echo "$create_output" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    # Add comment
    local comment_output
    comment_output=$(git issue comment "$issue_id" "This is a test comment")
    
    assert_contains "Added comment" "$comment_output" "Should confirm comment addition"
    
    # Verify comment in raw note data (show does not display comments)
    local notes_ref="refs/notes/issue-$issue_id"
    local raw_data=""
    local tree_hash
    tree_hash=$(git cat-file -p "$notes_ref" 2>/dev/null | grep "^tree" | cut -d' ' -f2)
    if [[ -n "$tree_hash" ]]; then
        local blob_hash
        blob_hash=$(git ls-tree "$tree_hash" 2>/dev/null | awk '{print $3}')
        if [[ -n "$blob_hash" ]]; then
            raw_data=$(git cat-file -p "$blob_hash" 2>/dev/null || echo "")
        fi
    fi
    assert_contains "This is a test comment" "$raw_data" "Should have comment in note data"
}

test_hash_id_generation() {
    # Test that IDs are 7 characters and look like git hashes
    local output
    output=$(git issue create "Hash ID test")
    local issue_id
    issue_id=$(echo "$output" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    assert_equals "7" "${#issue_id}" "Issue ID should be 7 characters"
    
    # Test that it only contains valid hex characters
    if [[ "$issue_id" =~ ^[a-f0-9]+$ ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Issue ID contains only valid hex characters"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Issue ID contains invalid characters: $issue_id"
    fi
}

test_status_command() {
    # Create issues with different states
    local id1 id2
    id1=$(git issue create "Open issue" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    id2=$(git issue create "Progress issue" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    git issue update "$id2" --state=in-progress >/dev/null 2>&1
    
    local status_output
    status_output=$(git issue-status)
    
    assert_contains "Issue Status Report" "$status_output" "Should show status header"
    assert_contains "Total Issues: 2" "$status_output" "Should count total issues"
    assert_contains "Open: 1" "$status_output" "Should count open issues"
    assert_contains "In Progress: 1" "$status_output" "Should count in-progress issues"
}

test_error_handling() {
    # Test invalid issue ID
    assert_exit_code 1 "git issue show nonexistent" "Should fail for nonexistent issue"
    
    # Test invalid state
    local id
    id=$(git issue create "Error test" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    assert_exit_code 1 "git issue update $id --state=invalid-state" "Should fail for invalid state"
    
    # Test missing arguments
    assert_exit_code 1 "git issue create" "Should fail when no title provided"
    assert_exit_code 1 "git issue update" "Should fail when no arguments provided"
}

# Main test execution
main() {
    echo -e "${BLUE}🧪 git-issue Test Suite${NC}"
    echo "=========================="
    echo ""
    
    # Check if git-issue is available
    if ! command -v git-issue >/dev/null 2>&1; then
        echo -e "${RED}Error: git-issue not found in PATH${NC}"
        echo "Please install git-issue first:"
        echo "  make install"
        exit 1
    fi
    
    # Run tests
    run_test "Issue Creation" test_issue_creation
    run_test "Issue Listing" test_issue_listing
    run_test "Issue Updates" test_issue_update
    run_test "Issue Comments" test_issue_comments
    run_test "Hash ID Generation" test_hash_id_generation
    run_test "Status Command" test_status_command
    run_test "Error Handling" test_error_handling
    
    echo ""
    echo "=========================="
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

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi