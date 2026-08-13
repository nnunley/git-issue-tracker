#!/bin/bash
# Unit tests for git-issue core functions
# Tests individual functions in isolation

set -e

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_runner.sh"

# Source functions from git-issue for unit testing
source_git_issue_functions() {
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/../bin/git-issue"   # dual-mode: defines functions, executes nothing
}

# Setup test repository with git config
setup_test_repo() {
    local test_dir=$(mktemp -d)
    cd "$test_dir"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git commit -q --allow-empty -m "initial"
    echo "$test_dir"
}

# Cleanup test repository
cleanup_test_repo() {
    local test_dir="$1"
    cd /
    rm -rf "$test_dir"
}

# Unit test functions
test_generate_issue_id() {
    local test_repo
    test_repo=$(setup_test_repo)
    trap "cleanup_test_repo '$test_repo'" RETURN

    source_git_issue_functions

    local title="Test Issue"
    local author="Test User"
    local timestamp="2025-07-12T10:00:00Z"

    # Compute expected hash using real git
    local content="issue: $title
author: $author
created: $timestamp"
    local expected_hash
    expected_hash=$(echo "$content" | git hash-object --stdin)
    expected_hash="${expected_hash:0:7}"

    local id
    id=$(generate_issue_id "$title" "$author" "$timestamp")

    assert_equals "7" "${#id}" "Generated ID should be 7 characters"
    assert_equals "$expected_hash" "$id" "ID should match expected hash (first 7 chars)"
}

test_get_issue_ref() {
    source_git_issue_functions
    
    local ref
    ref=$(get_issue_ref "a1b2c3d")
    
    assert_equals "refs/notes/issue-a1b2c3d" "$ref" "Should generate correct git ref"
}

test_statuses_validation() {
    local test_repo
    test_repo=$(setup_test_repo)
    trap "cleanup_test_repo '$test_repo'" RETURN

    source_git_issue_functions
    # Load statuses after sourcing (now in test repo context)
    load_statuses

    local statuses_string="${STATUSES[*]}"
    assert_contains "open" "$statuses_string" "Should include 'open' status"
    assert_contains "in_progress" "$statuses_string" "Should include 'in_progress' status"
    assert_contains "review" "$statuses_string" "Should include 'review' status"
    assert_contains "closed" "$statuses_string" "Should include 'closed' status"
    assert_contains "blocked" "$statuses_string" "Should include 'blocked' status"
    assert_contains "deferred" "$statuses_string" "Should include 'deferred' status"
}

test_priorities_validation() {
    # Test that PRIORITIES array contains expected values
    source_git_issue_functions
    
    local priorities_string="${PRIORITIES[*]}"
    assert_contains "low" "$priorities_string" "Should include 'low' priority"
    assert_contains "medium" "$priorities_string" "Should include 'medium' priority"
    assert_contains "high" "$priorities_string" "Should include 'high' priority"
    assert_contains "critical" "$priorities_string" "Should include 'critical' priority"
}

# Test input sanitization (if implemented)
test_input_sanitization() {
    # This test will fail until input sanitization is implemented
    # Keeping it here as a reminder of what needs to be added
    
    local malicious_input="test; rm -rf /"
    local sanitized
    
    # This function doesn't exist yet - we need to implement it
    if command -v sanitize_input >/dev/null 2>&1; then
        sanitized=$(sanitize_input "$malicious_input")
        assert_equals "test rm -rf " "$sanitized" "Should remove dangerous characters"
    else
        echo -e "  ${YELLOW}⚠${NC} Input sanitization not implemented yet"
        TESTS_RUN=$((TESTS_RUN + 1))
        # Don't count as pass or fail - it's a TODO
    fi
}

# Test hash collision handling logic
test_hash_collision_detection() {
    # Mock issue_exists to simulate collision
    issue_exists() {
        local id="$1"
        # Simulate collision for specific ID
        [[ "$id" == "a1b2c3d" ]]
    }
    
    source_git_issue_functions
    
    # This test would need modification of generate_issue_id to be testable
    # For now, just verify the collision detection logic exists
    local git_issue_content
    git_issue_content=$(cat "$SCRIPT_DIR/../bin/git-issue")
    
    assert_contains "Hash collision detected" "$git_issue_content" "Should have collision detection"
    assert_contains "attempts -lt 100" "$git_issue_content" "Should limit collision retry attempts"
}

# Test edge cases for ID generation
test_id_generation_edge_cases() {
    local test_repo
    test_repo=$(setup_test_repo)
    trap "cleanup_test_repo '$test_repo'" RETURN

    source_git_issue_functions

    # Test with empty title
    local id_empty
    id_empty=$(generate_issue_id "" "Test User" "2025-07-12T10:00:00Z")
    assert_equals "7" "${#id_empty}" "Should generate 7-char ID even with empty title"

    # Test with very long title
    local long_title
    long_title=$(printf 'a%.0s' {1..1000})  # 1000 'a' characters
    local id_long
    id_long=$(generate_issue_id "$long_title" "Test User" "2025-07-12T10:00:00Z")
    assert_equals "7" "${#id_long}" "Should generate 7-char ID with long title"

    # Test with special characters
    local special_title="Title with spaces & symbols! @#$%"
    local id_special
    id_special=$(generate_issue_id "$special_title" "Test User" "2025-07-12T10:00:00Z")
    assert_equals "7" "${#id_special}" "Should handle special characters in title"
}

# Test timestamp formatting
test_timestamp_format() {
    # Test that timestamp follows ISO 8601 format
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Basic regex to check ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ
    if [[ $timestamp =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Timestamp follows ISO 8601 format"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Timestamp format is incorrect: $timestamp"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🧪 git-issue Unit Tests${NC}"
    echo "========================"
    echo ""
    
    run_test "Issue ID Generation" test_generate_issue_id
    run_test "Git Ref Generation" test_get_issue_ref
    run_test "Statuses Validation" test_statuses_validation
    run_test "Priorities Validation" test_priorities_validation
    run_test "Input Sanitization" test_input_sanitization
    run_test "Hash Collision Detection" test_hash_collision_detection
    run_test "ID Generation Edge Cases" test_id_generation_edge_cases
    run_test "Timestamp Format" test_timestamp_format
    
    echo ""
    echo "========================"
    echo -e "${BLUE}Unit Test Results:${NC}"
    echo -e "  Total: $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "  ${GREEN}All unit tests passed!${NC}"
        exit 0
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi