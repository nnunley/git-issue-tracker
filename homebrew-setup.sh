#!/bin/bash
# Setup script for Homebrew installation

set -e

echo "🍺 Setting up git-issue for Homebrew"
echo "===================================="

# Check if Homebrew is installed
if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Homebrew not found. Please install Homebrew first:"
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

echo "✅ Homebrew found: $(brew --version | head -n1)"

# Create a local tap (temporary for testing)
TAP_DIR="$(brew --repository)/Library/Taps/local/homebrew-git-issue"
echo "📁 Creating local tap at: $TAP_DIR"

if [[ -d "$TAP_DIR" ]]; then
    echo "⚠️  Tap already exists, removing old version..."
    rm -rf "$TAP_DIR"
fi

mkdir -p "$TAP_DIR"

# Copy formula to tap
echo "📋 Installing formula..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/Formula/git-issue.rb" "$TAP_DIR/"

# Install from local tap
echo "🔧 Installing git-issue via Homebrew..."
brew install --build-from-source local/git-issue/git-issue

echo ""
echo "✅ Installation complete!"
echo ""
echo "📝 You can now use:"
echo "   git issue create 'Fix the navbar bug'"
echo "   git issue list"
echo "   git issue-status"
echo ""
echo "🔄 To uninstall:"
echo "   brew uninstall git-issue"
echo "   rm -rf '$TAP_DIR'"