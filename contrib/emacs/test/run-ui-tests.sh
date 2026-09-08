#!/usr/bin/env bash
# Run the magit UI ERT suite.
#
# Installs magit from NonGNU ELPA into a scratch `user-emacs-directory' so the
# developer's own Emacs configuration is never read or written.  Set
# GIT_ISSUE_EMACS_SCRATCH to a stable path to keep the download between runs
# (CI caches that directory); without it a throwaway directory is used and
# magit is fetched every time.
#
# HOME is redirected for the whole run: the multi-project registry lives in
# *global* git config, so an unisolated run would edit ~/.gitconfig.  This is
# the same guard tests/test_registry.sh uses.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# Resolve the package scratch directory against the *real* HOME, before the
# redirect below.
SCRATCH="${GIT_ISSUE_EMACS_SCRATCH:-$(mktemp -d)}"
mkdir -p "$SCRATCH"
SCRATCH="$(cd "$SCRATCH" && pwd)"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

export PATH="$ROOT/bin:$PATH"
export HOME="$WORK"
export XDG_CONFIG_HOME="$WORK/.config"
# The CLI puts a standalone (repository-less) tracker under XDG_DATA_HOME,
# defaulting to ~/Library/Application Support on macOS. Pin it so the test
# that asserts no such tracker was created knows where to look.
export XDG_DATA_HOME="$WORK/.local/share"
export GIT_CONFIG_NOSYSTEM=1
# Read by the suite: the registry tests refuse to run unless HOME is isolated.
export GIT_ISSUE_UI_TEST_ISOLATED=1
mkdir -p "$XDG_CONFIG_HOME"

git config --global user.name "git-issue ui tests"
git config --global user.email "ui@tests.invalid"
git config --global init.defaultBranch main

echo "magit scratch: $SCRATCH"
echo "isolated HOME: $HOME"
command -v git-issue >/dev/null || { echo "git-issue not on PATH" >&2; exit 1; }

exec emacs -Q --batch \
  --eval "(setq user-emacs-directory \"$SCRATCH/\")" \
  --eval "(require 'package)" \
  --eval "(setq package-user-dir (expand-file-name \"elpa\" user-emacs-directory))" \
  --eval "(add-to-list 'package-archives '(\"nongnu\" . \"https://elpa.nongnu.org/nongnu/\") t)" \
  --eval "(package-initialize)" \
  --eval "(unless (package-installed-p 'magit) (package-refresh-contents) (package-install 'magit))" \
  -L "$ROOT/share/git-issue/emacs" \
  -l ert \
  -l "$ROOT/contrib/emacs/test/magit-git-issue-test.el" \
  -f ert-run-tests-batch-and-exit
