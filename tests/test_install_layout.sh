#!/bin/bash
# Installed-layout smoke test: DESTDIR install must work invoked directly
# AND through a brew-style symlinked bin dir, including the status symlink chain.
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TMP=$(mktemp -d); WORK=$(mktemp -d); trap 'rm -rf "$TMP" "$WORK"' EXIT

make -C "$REPO_DIR" install PREFIX=/usr DESTDIR="$TMP" >/dev/null
[[ -f "$TMP/usr/share/git-issue/awk/extract_issues.awk" ]] || { echo "FAIL: awk dir not installed"; exit 1; }
[[ -L "$TMP/usr/bin/git-issue-status" ]] || { echo "FAIL: status symlink not installed"; exit 1; }

cd "$WORK" && git init -q && git config user.name T && git config user.email t@t.co
git commit -q --allow-empty -m init

"$TMP/usr/bin/git-issue" create "layout smoke" >/dev/null 2>&1 || { echo "FAIL: direct invocation"; exit 1; }

mkdir "$TMP/fakebrew"
ln -s "$TMP/usr/bin/git-issue" "$TMP/fakebrew/git-issue"
ln -s "$TMP/usr/bin/git-issue-status" "$TMP/fakebrew/git-issue-status"
"$TMP/fakebrew/git-issue" list 2>/dev/null | grep -q "layout smoke" || { echo "FAIL: symlinked bin"; exit 1; }
"$TMP/fakebrew/git-issue-status" 2>/dev/null | grep -q "Issue Status Report" || { echo "FAIL: status symlink chain dispatch"; exit 1; }

echo "PASS: install layout (direct + symlink + status chain)"
