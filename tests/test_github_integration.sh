#!/bin/bash
# Test GitHub integration with provider-specific fields

# Setup test environment
TEST_DIR="./test-github-integration-$$"
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

echo -e "${BLUE}Testing GitHub Integration with Provider-Specific Fields${NC}"
echo "==========================================================="
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

# Test 1: Create sample GitHub issue data
echo "Creating sample GitHub issue data..."
cat << 'EOF' > github_issues.json
[
  {
    "number": 42,
    "title": "Fix navigation bug",
    "body": "Navigation menu doesn't work on mobile devices",
    "state": "open",
    "author": {"login": "developer1"},
    "assignees": [{"login": "reviewer1"}],
    "labels": [{"name": "bug"}, {"name": "frontend"}],
    "url": "https://github.com/example/repo/issues/42",
    "createdAt": "2025-01-15T10:30:00Z",
    "updatedAt": "2025-01-15T14:20:00Z"
  },
  {
    "number": 43,
    "title": "Add dark mode",
    "body": "",
    "state": "closed",
    "author": {"login": "designer1"},
    "assignees": [],
    "labels": [{"name": "enhancement"}, {"name": "priority:high"}],
    "url": "https://github.com/example/repo/issues/43",
    "createdAt": "2025-01-10T09:15:00Z",
    "updatedAt": "2025-01-14T16:45:00Z"
  }
]
EOF

# Test 2: Import GitHub issues
echo -n "Testing GitHub import... "
IMPORT_RESULT=$(cat github_issues.json | gh-to-git-issue | git issue import)
if echo "$IMPORT_RESULT" | grep -q "Imported 2 issues"; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Import failed: $IMPORT_RESULT"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 3: Verify GitHub-specific fields were imported
echo -n "Testing GitHub field import... "
ISSUE_LIST=$(git issue list)
echo "DEBUG: Issue list output: $ISSUE_LIST" >&2
if echo "$ISSUE_LIST" | grep -q "Fix navigation bug" && echo "$ISSUE_LIST" | grep -q "Add dark mode"; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Issues not properly imported: $ISSUE_LIST"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 4: Verify provider-specific fields in issue details
FIRST_ISSUE_ID=$(git issue list | head -1 | grep -o '#[a-f0-9]\+' | head -1 | cut -c2-)
echo -n "Testing provider-specific field storage... "
if [[ -n "$FIRST_ISSUE_ID" ]]; then
    ISSUE_DETAILS=$(git issue show "$FIRST_ISSUE_ID")
    if echo "$ISSUE_DETAILS" | grep -q "GitHub: #" && echo "$ISSUE_DETAILS" | grep -q "github.com"; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  GitHub fields not found in issue details"
        echo "  Issue details: $ISSUE_DETAILS"
    fi
else
    echo -e "${RED}FAIL${NC}"
    echo "  Could not extract issue ID"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 5: Test GitHub export
echo -n "Testing GitHub export... "
if [[ -n "$FIRST_ISSUE_ID" ]]; then
    EXPORT_RESULT=$(git issue export --github "$FIRST_ISSUE_ID")
    if echo "$EXPORT_RESULT" | grep -q '"title":' && echo "$EXPORT_RESULT" | grep -q '"state":'; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  GitHub export failed: $EXPORT_RESULT"
    fi
else
    echo -e "${RED}FAIL${NC}"
    echo "  No issue ID available for export test"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 6: Verify empty fields are not stored
echo -n "Testing empty field optimization... "
# Get raw issue data to check for empty fields
RAW_DATA=$(git issue export "$FIRST_ISSUE_ID")
if ! echo "$RAW_DATA" | grep -q "jira_id:" && ! echo "$RAW_DATA" | grep -q "gitlab_id:"; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Empty provider fields found in storage"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 7: Test that issues with empty description don't store description field
SECOND_ISSUE_ID=$(git issue list | tail -1 | grep -o '#[a-f0-9]\+' | cut -c2-)
echo -n "Testing empty description optimization... "
RAW_DATA_2=$(git issue export "$SECOND_ISSUE_ID")
if ! echo "$RAW_DATA_2" | grep -q "description:"; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Empty description field found in storage"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 8: Test round-trip conversion (GitHub -> git-issue -> GitHub)
echo -n "Testing round-trip conversion... "
ORIGINAL_GITHUB=$(echo '[{"number": 99, "title": "Test issue", "body": "Test description", "state": "open", "author": {"login": "test"}, "assignees": [], "labels": [], "url": "https://github.com/test/repo/issues/99", "createdAt": "2025-01-15T12:00:00Z", "updatedAt": "2025-01-15T12:00:00Z"}]')
CONVERTED_ID=$(echo "$ORIGINAL_GITHUB" | gh-to-git-issue | git issue import 2>&1 | grep -o '#[a-f0-9]\+' | cut -c2-)
EXPORTED_BACK=$(git issue export --github "$CONVERTED_ID")
if echo "$EXPORTED_BACK" | grep -q '"title": "Test issue"' && echo "$EXPORTED_BACK" | grep -q '"body": "Test description"'; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    echo "  Round-trip conversion failed"
fi
TESTS_RUN=$((TESTS_RUN + 1))

echo ""
echo -e "${BLUE}Test Results:${NC}"
echo "============="
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${NC}"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo -e "${GREEN}All GitHub integration tests passed!${NC}"
    echo "Provider-specific fields and empty field optimization working correctly."
    exit 0
else
    echo -e "${RED}Some GitHub integration tests failed.${NC}"
    exit 1
fi

# Cleanup
cd ..
rm -rf "$TEST_DIR"