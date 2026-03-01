#!/bin/bash
# Integration tests for git-issue with real git operations
# Tests full workflows and git notes integration

set -e

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_runner.sh"

# Add git-issue to PATH (ensure local version is used)
export PATH="$SCRIPT_DIR/../bin:$PATH"
echo "Using git-issue from: $(which git-issue)" >&2

# Integration test functions
test_full_issue_workflow() {
    # Test complete issue lifecycle
    echo "  Testing full issue workflow..."
    
    # Create issue
    local create_output
    create_output=$(git issue create "Full workflow test issue")
    local issue_id
    issue_id=$(echo "$create_output" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    # Update priority
    git issue update "$issue_id" --priority=high >/dev/null 2>&1

    # Update status
    git issue update "$issue_id" --status=in_progress >/dev/null 2>&1
    
    # Add comment
    git issue comment "$issue_id" "Working on implementation" >/dev/null 2>&1
    
    # Update assignee
    git issue update "$issue_id" --assignee="Test User" >/dev/null 2>&1
    
    # Add another comment
    git issue comment "$issue_id" "Almost done" >/dev/null 2>&1
    
    # Complete issue
    git issue update "$issue_id" --status=closed >/dev/null 2>&1
    
    # Verify final state via show output
    local final_output
    final_output=$(git issue show "$issue_id")

    assert_contains "Status: closed" "$final_output" "Issue should be marked as closed"
    assert_contains "Priority: high" "$final_output" "Issue should have high priority"
    assert_contains "Assignee: Test User" "$final_output" "Issue should be assigned"

    # Verify comments in raw note data (show does not display comments)
    local notes_ref="refs/notes/issue-$issue_id"
    local raw_data=""
    local tree_hash=$(git cat-file -p "$notes_ref" 2>/dev/null | grep "^tree" | cut -d' ' -f2)
    if [[ -n "$tree_hash" ]]; then
        local blob_hash=$(git ls-tree "$tree_hash" 2>/dev/null | awk '{print $3}')
        if [[ -n "$blob_hash" ]]; then
            raw_data=$(git cat-file -p "$blob_hash" 2>/dev/null || echo "")
        fi
    fi
    assert_contains "Working on implementation" "$raw_data" "Should contain first comment"
    assert_contains "Almost done" "$raw_data" "Should contain second comment"
}

test_git_notes_persistence() {
    # Test that issues are stored as git notes and persist
    echo "  Testing git notes persistence..."
    
    # Create issue
    local issue_id
    issue_id=$(git issue create "Persistence test" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    # Check that git notes exists
    local notes_ref="refs/notes/issue-$issue_id"
    
    if git show-ref --verify --quiet "$notes_ref"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Git notes created successfully"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Git notes not found"
    fi
    
    # Check that notes contain expected data using proper git notes reading
    local notes_content
    local tree_hash=$(git cat-file -p "$notes_ref" 2>/dev/null | grep "^tree" | cut -d' ' -f2)
    if [[ -n "$tree_hash" ]]; then
        local blob_hash=$(git ls-tree "$tree_hash" 2>/dev/null | awk '{print $3}')
        if [[ -n "$blob_hash" ]]; then
            notes_content=$(git cat-file -p "$blob_hash" 2>/dev/null || echo "")
        fi
    fi
    
    assert_contains "id: $issue_id" "$notes_content" "Notes should contain issue ID"
    assert_contains "title: Persistence test" "$notes_content" "Notes should contain title"
    assert_contains "status: open" "$notes_content" "Notes should contain default status"
}

test_issue_commit_linking() {
    # Test bidirectional linking between issues and commits
    echo "  Testing issue-commit linking..."
    
    # Create issue
    local issue_id
    issue_id=$(git issue create "Commit linking test" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    # Create a commit
    echo "Test change for linking" >> test_file.txt
    git add test_file.txt
    git commit -m "Test commit for issue linking" >/dev/null 2>&1
    
    # Link issue to commit
    local link_output
    link_output=$(git issue link "$issue_id" HEAD)
    
    assert_contains "Added comment" "$link_output" "Should confirm link creation"
    
    # Verify link in raw issue data (link is stored as a comment)
    local notes_ref="refs/notes/issue-$issue_id"
    local raw_data=""
    local tree_hash=$(git cat-file -p "$notes_ref" 2>/dev/null | grep "^tree" | cut -d' ' -f2)
    if [[ -n "$tree_hash" ]]; then
        local blob_hash=$(git ls-tree "$tree_hash" 2>/dev/null | awk '{print $3}')
        if [[ -n "$blob_hash" ]]; then
            raw_data=$(git cat-file -p "$blob_hash" 2>/dev/null || echo "")
        fi
    fi
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD)

    assert_contains "Linked to commit: $commit_hash" "$raw_data" "Issue should reference commit"
}

test_concurrent_issue_creation() {
    # Test multiple issues created simultaneously (hash collision avoidance)
    echo "  Testing concurrent issue creation..."
    
    local ids=()
    
    # Create multiple issues rapidly
    for i in {1..5}; do
        local output
        output=$(git issue create "Concurrent test issue $i")
        local id
        id=$(echo "$output" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
        ids+=("$id")
        sleep 0.1  # Small delay to ensure different timestamps
    done
    
    # Verify all IDs are unique
    local unique_count
    unique_count=$(printf '%s\n' "${ids[@]}" | sort -u | wc -l | tr -d ' ')
    local total_count=${#ids[@]}
    
    assert_equals "$total_count" "$unique_count" "All issue IDs should be unique"
    
    # Verify all issues can be listed
    local list_output
    list_output=$(git issue list)
    
    for id in "${ids[@]}"; do
        assert_contains "#$id" "$list_output" "Issue $id should appear in list"
    done
}

test_git_repository_integration() {
    # Test integration with git repository features
    echo "  Testing git repository integration..."
    
    # Test in clean repo
    local status_before
    status_before=$(git status --porcelain)
    
    # Create and modify issues
    local id1 id2
    id1=$(git issue create "Integration test 1" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    id2=$(git issue create "Integration test 2" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    git issue update "$id1" --status=in_progress >/dev/null 2>&1
    git issue comment "$id2" "Test comment" >/dev/null 2>&1
    
    # Verify git status is still clean (notes don't affect working tree)
    local status_after
    status_after=$(git status --porcelain)
    
    assert_equals "$status_before" "$status_after" "Working tree should remain clean"
    
    # Test that notes are part of git history
    if git for-each-ref refs/notes/issue-* >/dev/null 2>&1; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Issue notes are tracked by git"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Issue notes not found in git refs"
    fi
}

test_issue_data_format() {
    # Test that issue data follows expected YAML-like format
    echo "  Testing issue data format..."
    
    local issue_id
    issue_id=$(git issue create "Format test issue" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    # Add some data
    git issue update "$issue_id" --priority=critical >/dev/null 2>&1
    git issue update "$issue_id" --assignee="Test User" >/dev/null 2>&1
    git issue comment "$issue_id" "Test comment for format" >/dev/null 2>&1
    
    # Get raw issue data using proper git notes reading
    local notes_ref="refs/notes/issue-$issue_id"
    local raw_data
    local tree_hash=$(git cat-file -p "$notes_ref" 2>/dev/null | grep "^tree" | cut -d' ' -f2)
    if [[ -n "$tree_hash" ]]; then
        local blob_hash=$(git ls-tree "$tree_hash" 2>/dev/null | awk '{print $3}')
        if [[ -n "$blob_hash" ]]; then
            raw_data=$(git cat-file -p "$blob_hash" 2>/dev/null || echo "")
        fi
    fi
    
    # Test format structure
    assert_contains "id: $issue_id" "$raw_data" "Should have ID field"
    assert_contains "title: Format test issue" "$raw_data" "Should have title field"
    assert_contains "status: open" "$raw_data" "Should have status field"
    assert_contains "priority: critical" "$raw_data" "Should have priority field"
    assert_contains "assignee: Test User" "$raw_data" "Should have assignee field"
    assert_contains "---" "$raw_data" "Should have metadata separator"
    assert_contains "Test comment for format" "$raw_data" "Should have comment in body"
    
    # Test timestamp format
    if echo "$raw_data" | grep -q "created: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} Created timestamp follows ISO format"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Created timestamp format is incorrect"
    fi
}

test_status_reporting_accuracy() {
    # Test that status command provides accurate reporting
    echo "  Testing status reporting accuracy..."
    
    # Create issues in different states
    local id1 id2 id3 id4
    id1=$(git issue create "Open issue" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    id2=$(git issue create "In progress issue" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    id3=$(git issue create "Done issue" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    id4=$(git issue create "Blocked issue" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    # Set statuses
    git issue update "$id2" --status=in_progress >/dev/null 2>&1
    git issue update "$id3" --status=closed >/dev/null 2>&1
    git issue update "$id4" --status=blocked >/dev/null 2>&1

    # Set priorities
    git issue update "$id1" --priority=high >/dev/null 2>&1
    git issue update "$id2" --priority=medium >/dev/null 2>&1
    git issue update "$id3" --priority=low >/dev/null 2>&1
    git issue update "$id4" --priority=critical >/dev/null 2>&1
    
    # Get status report
    local status_output
    status_output=$(git issue-status)
    
    # Test counts
    assert_contains "Total Issues: 4" "$status_output" "Should count 4 total issues"
    assert_contains "Open: 1" "$status_output" "Should count 1 open issue"
    assert_contains "In Progress: 1" "$status_output" "Should count 1 in_progress issue"
    assert_contains "Closed: 1" "$status_output" "Should count 1 closed issue"
    assert_contains "Blocked: 1" "$status_output" "Should count 1 blocked issue"
    
    # Test priority counts (high/critical grouped together)
    assert_contains "High/Critical: 2" "$status_output" "Should count 2 high/critical issues"
    assert_contains "Medium: 1" "$status_output" "Should count 1 medium issue"
    assert_contains "Low: 1" "$status_output" "Should count 1 low issue"
}

test_error_recovery() {
    # Test system behavior with corrupted or missing data
    echo "  Testing error recovery..."
    
    # Test with non-existent issue
    local error_output
    error_output=$(git issue show "nonexist" 2>&1 || true)
    assert_contains "not found" "$error_output" "Should report non-existent issue"
    
    # Test with invalid commit for linking
    local issue_id
    issue_id=$(git issue create "Error recovery test" | grep -o '#[a-f0-9]\{7\}' | sed 's/#//')
    
    local link_error
    link_error=$(git issue link "$issue_id" "invalid-commit-hash" 2>&1 || true)
    assert_contains "Invalid commit" "$link_error" "Should reject invalid commit hash"
}

# Main execution
main() {
    echo -e "${BLUE}🧪 git-issue Integration Tests${NC}"
    echo "=============================="
    echo ""
    
    # Check prerequisites
    if ! command -v git-issue >/dev/null 2>&1; then
        echo -e "${RED}Error: git-issue not found in PATH${NC}"
        echo "Please install git-issue first"
        exit 1
    fi
    
    # Run integration tests
    run_test "Full Issue Workflow" test_full_issue_workflow
    run_test "Git Notes Persistence" test_git_notes_persistence
    run_test "Issue-Commit Linking" test_issue_commit_linking
    run_test "Concurrent Issue Creation" test_concurrent_issue_creation
    run_test "Git Repository Integration" test_git_repository_integration
    run_test "Issue Data Format" test_issue_data_format
    run_test "Status Reporting Accuracy" test_status_reporting_accuracy
    run_test "Error Recovery" test_error_recovery
    
    echo ""
    echo "=============================="
    echo -e "${BLUE}Integration Test Results:${NC}"
    echo -e "  Total: $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "  ${GREEN}All integration tests passed!${NC}"
        exit 0
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi