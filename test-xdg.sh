#!/bin/bash
# Test XDG functionality by simulating non-git environment

echo "🧪 Testing XDG Directory Support"
echo "================================"

# Create isolated test environment
TEST_DIR="$HOME/tmp/git-issue-xdg-test"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Ensure no git repo exists
rm -rf .git

# Set custom XDG directory for testing
export XDG_DATA_HOME="$TEST_DIR/.local/share"

echo "Test directory: $TEST_DIR"
echo "XDG_DATA_HOME: $XDG_DATA_HOME"
echo ""

# Test 1: Check git detection fails
echo "🔍 Testing git detection..."
if git rev-parse --git-dir >/dev/null 2>&1; then
    echo "❌ Git repo found - test environment not isolated"
    echo "Git dir: $(git rev-parse --git-dir)"
    exit 1
else
    echo "✅ No git repository detected"
fi
echo ""

# Test 2: Create issue in non-git environment
echo "📝 Creating issue in non-git environment..."
output=$(git issue create "XDG test issue" 2>&1)
echo "$output"

# Check if XDG message appears
if echo "$output" | grep -q "XDG"; then
    echo "✅ XDG storage activated"
else
    echo "❌ XDG storage not activated"
fi
echo ""

# Test 3: Verify XDG directory structure
expected_repo="$XDG_DATA_HOME/git-issue/git-issue-xdg-test.git"
echo "🗂️  Checking XDG directory structure..."
echo "Expected location: $expected_repo"

if [[ -d "$expected_repo" ]]; then
    echo "✅ XDG bare repository created"
    ls -la "$expected_repo"
else
    echo "❌ XDG bare repository not found"
    echo "Contents of XDG directory:"
    find "$XDG_DATA_HOME" -type d 2>/dev/null || echo "XDG directory not created"
fi
echo ""

# Test 4: List issues
echo "📋 Testing issue listing..."
git issue list 2>&1
echo ""

# Test 5: Test status command
echo "📊 Testing status command..."
git issue-status 2>&1
echo ""

# Cleanup
echo "🧹 Cleaning up test environment..."
rm -rf "$TEST_DIR"
echo "✅ Test environment cleaned up"