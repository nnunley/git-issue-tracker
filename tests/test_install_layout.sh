#!/usr/bin/env bash
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

# Broken install must fail LOUDLY: missing awk dir => nonzero exit + clear
# error. Pin GIT_ISSUE_AWK_DIR so the /usr/local fallback in the resolution
# chain can't rescue the run on hosts that happen to have a system install.
mv "$TMP/usr/share/git-issue/awk" "$TMP/usr/share/git-issue/awk.hidden"
set +e
broken_out=$(GIT_ISSUE_AWK_DIR="$TMP/usr/share/git-issue/awk" "$TMP/usr/bin/git-issue" list 2>&1)
broken_exit=$?
set -e
mv "$TMP/usr/share/git-issue/awk.hidden" "$TMP/usr/share/git-issue/awk"
[[ $broken_exit -ne 0 ]] || { echo "FAIL: missing awk dir must be a hard error (got exit 0)"; exit 1; }
echo "$broken_out" | grep -q "awk program not found" || { echo "FAIL: missing awk dir must name the missing program"; exit 1; }

# install-git-issue.sh path: run the REAL installer into a temp dir and
# verify it completes and ships bin + awk + hooks (regression: quoted glob
# aborted it mid-way under set -e, leaving an empty awk dir)
INST=$(mktemp -d)
( cd "$REPO_DIR" && GIT_ISSUE_INSTALL_DIR="$INST/bin" ./install-git-issue.sh >/dev/null 2>&1 ) \
    || { echo "FAIL: install-git-issue.sh exited nonzero"; exit 1; }
[[ -f "$INST/bin/git-issue" ]] || { echo "FAIL: installer did not ship git-issue"; exit 1; }
[[ -f "$INST/share/git-issue/awk/extract_issues.awk" ]] || { echo "FAIL: installer did not ship awk programs"; exit 1; }
[[ -f "$INST/share/git-issue/hooks/pre-push" ]] || { echo "FAIL: installer did not ship hook templates"; exit 1; }
rm -rf "$INST"

echo "PASS: install layout (direct + symlink + status chain + hard-fail + installer surface)"
