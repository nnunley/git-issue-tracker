#!/bin/bash
# Debug the detection logic

cd standalone-test

echo "=== Git Detection Debug ==="
echo "PWD: $(pwd)"
echo "Contents: $(ls -la)"

echo ""
echo "Git directory checks:"
echo ".git directory exists: $([[ -d '.git' ]] && echo 'YES' || echo 'NO')"
echo ".git file exists: $([[ -f '.git' ]] && echo 'YES' || echo 'NO')"

echo ""
echo "Git commands:"
echo "git rev-parse --git-dir: $(git rev-parse --git-dir 2>&1 || echo 'FAILED')"
echo "git rev-parse --is-inside-work-tree: $(git rev-parse --is-inside-work-tree 2>&1 || echo 'FAILED')"

echo ""
echo "Detection logic test:"
if [[ -d ".git" ]] || [[ -f ".git" ]]; then
    echo "RESULT: Would use git mode"
else
    echo "RESULT: Would use XDG/standalone mode"
fi

echo ""
echo "OSTYPE: $OSTYPE"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Platform: macOS detected"
    echo "Default data home: $HOME/Library/Application Support"
else
    echo "Platform: Linux/Unix"
    echo "Default data home: $HOME/.local/share"
fi