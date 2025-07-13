#!/bin/bash
# Install git-issue as a native git subcommand

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔧 Installing git-issue as native git subcommand...${NC}"
echo ""

# Determine installation directory
if [[ -w "/usr/local/bin" ]]; then
    INSTALL_DIR="/usr/local/bin"
elif [[ -w "$HOME/.local/bin" ]]; then
    INSTALL_DIR="$HOME/.local/bin"
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.zshrc 2>/dev/null || true
        echo -e "${YELLOW}Added $HOME/.local/bin to PATH in ~/.bashrc and ~/.zshrc${NC}"
    fi
else
    echo "Creating $HOME/.local/bin directory..."
    mkdir -p "$HOME/.local/bin"
    INSTALL_DIR="$HOME/.local/bin"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.zshrc 2>/dev/null || true
    echo -e "${YELLOW}Added $HOME/.local/bin to PATH in ~/.bashrc and ~/.zshrc${NC}"
fi

echo "Installing to: $INSTALL_DIR"
echo ""

# Check dependencies
echo "Checking dependencies..."
if ! command -v jq >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Warning: jq not found. Install with: brew install jq (macOS) or apt-get install jq (Ubuntu)${NC}"
    echo "   jq is required for GitHub integration features"
fi

# Install main commands
cp "$(dirname "$0")/bin/git-issue" "$INSTALL_DIR/git-issue"
cp "$(dirname "$0")/bin/git-issue-status" "$INSTALL_DIR/git-issue-status"
cp "$(dirname "$0")/bin/gh-to-git-issue" "$INSTALL_DIR/gh-to-git-issue"

# Make executable
chmod +x "$INSTALL_DIR/git-issue"
chmod +x "$INSTALL_DIR/git-issue-status"
chmod +x "$INSTALL_DIR/gh-to-git-issue"

echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo "You can now use:"
echo -e "${BLUE}  git issue create 'Fix the navbar bug' --description='Button overlaps content'${NC}"
echo -e "${BLUE}  git issue list${NC}"
echo -e "${BLUE}  git issue update a1b2c3d --state=done --priority=high${NC}"
echo -e "${BLUE}  git issue-status${NC}"
echo ""
echo "GitHub integration:"
echo -e "${BLUE}  gh issue list --json number,title,body,state,author,assignees,labels,url,createdAt,updatedAt | gh-to-git-issue | git issue import${NC}"
echo ""

# Test installation
echo "Testing installation..."
if command -v git-issue >/dev/null 2>&1; then
    echo -e "${GREEN}✅ git-issue command found in PATH${NC}"
    
    # Test as git subcommand
    if git issue --help >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 'git issue' works as native git subcommand${NC}"
    else
        echo -e "${YELLOW}⚠️  'git issue' not working as subcommand (may need to restart shell)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  git-issue not found in PATH (may need to restart shell)${NC}"
fi

echo ""
echo -e "${BLUE}🎉 git-issue is now installed!${NC}"
echo ""
echo "If commands don't work immediately, restart your shell or run:"
echo "  source ~/.bashrc"