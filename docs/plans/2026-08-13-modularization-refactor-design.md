# Modularization Refactor — Design

**Date:** 2026-08-13
**Status:** Approved pending review
**Sequence:** Sub-project 1 of 2. Sub-project 2 (multi-project registry, summarized at the end) builds on this and is blocked by it.

## Goal

Behavior-preserving split of `bin/git-issue` (~3,250 lines) into sourced shell modules and external awk programs. No feature changes, no output changes. The full test suite passes after every commit.

Motivation: this script's size is now a measured maintenance cost — the 2026-08-13 hardening work required fixing three copy-pasted awk extractors, 21 replicated `xargs` call sites, and format parsing spread across four places that must agree.

## Layout

Repo layout equals installed layout, so dev and installed resolution are identical.

```
bin/git-issue              # dispatcher: env setup, arg parsing, command table (~200 lines)
libexec/git-issue/
  common.sh                # colors, trim_ws, get_git_user, error helpers
  storage.sh               # backend detection (git/XDG), plumbing read/write, refs, batch stream
  format.sh                # parse_front_matter/body/comments, KNOWN_HEADER_FIELDS, serialization
  statuses.sh              # status machine load/compile/transitions
  deps.sh                  # edge index, dep add/rm/list, cycles, ready/topo queries
  display.sh               # list/show/deps rendering
  sync.sh                  # import/export, gh conversion glue, trailers, setup-sync
  awk/
    extract_issues.awk     # batch-stream record state machine (US-separated output)
    front_matter.awk
    body.awk
```

Issue #606e606 (strict commit-object field format) is out of scope here but lands in `format.sh` afterward.

### Install paths (pinned)

| Installer | bin | modules |
|---|---|---|
| Makefile | `$(BINDIR)` | `$(PREFIX)/libexec/git-issue/` (awk under `.../awk/`) |
| Formula/git-issue.rb, git-issue-local.rb | `bin.install` | `libexec.install` |
| install-git-issue.sh | `$INSTALL_DIR` | `$INSTALL_DIR/../libexec/git-issue/` (e.g. `~/.local/libexec/git-issue`) |

### Lib resolution

In order: `$GIT_ISSUE_LIB` (override for tests/tooling) → `<physical path of bin, symlinks resolved>/../libexec/git-issue` → hard error naming both options ("reinstall, or set GIT_ISSUE_LIB"). `GIT_ISSUE_AWK_DIR` is derived from the resolved lib dir. A missing lib dir is a loud fatal error, never a silent partial load. Symlink resolution is a required behavior (Homebrew invokes through `/opt/homebrew/bin` symlinks); the current `GIT_ISSUE_BIN_DIR` line does not resolve symlinks, so this is a deliberate change guarded by the smoke test.

## Module policy

- **Include guards:** every module starts with `[[ -n "${_GI_<NAME>_SH:-}" ]] && return; _GI_<NAME>_SH=1`.
- **Dependencies:** each module sources its own dependencies via `$GIT_ISSUE_LIB` (guards make this idempotent, so there is no load order to maintain). Any consumer — dispatcher, `git-issue-status`, unit tests — sources only what it needs.
- **No top-level `readonly`:** module-level constants are plain assignments (re-sourcing must be safe; the `KNOWN_HEADER_FIELDS` readonly collision in unit tests is the precedent).
- **`set -e` in entrypoints only:** `bin/git-issue` and `bin/git-issue-status` declare it; modules must be correct under both settings.

## Awk contract

Each `.awk` file documents its required `-v` variables in a header comment. Data arrives on stdin, parameters via `-v`; awk programs never read the environment. Each is independently testable: `awk -f extract_issues.awk -v FIELDS=... < fixture`. Must run under BSD awk, gawk, and mawk (CI covers ubuntu + macos).

## Companion scripts

`git-issue-status` drops its duplicated `read_issue_data` and sources `storage.sh`. `gh-to-git-issue` and `git-issue-to-gh` stay standalone (small, jq-centric).

## Process

- All work on branch `refactor/modularize`; merge to main when complete (abandonable work never lands on main).
- One module per commit, mechanical, nothing moves twice. Full test suite + shellcheck green at every commit on the branch.
- Precondition (satisfied 2026-08-13): clean working tree — pre-push hook work committed as `6ff704b`, mode fix `a209701`.
- Tracker: refactor epic issue with one child issue per migration step; registry issue blocked by the epic.

## Migration order

1. **Install surface** — create `libexec/git-issue/` (with `common.sh` as the first occupant), lib resolution in `bin/git-issue`, update Makefile + both formulas + `install-git-issue.sh`, add the layout smoke test. Everything after lands on prepared ground; CI's compatibility job (which runs `install-git-issue.sh`) proves installers continuously.
2. `statuses.sh`
3. `format.sh` + `awk/` files
4. `storage.sh` (+ `git-issue-status` dedupe)
5. `deps.sh`
6. `display.sh`
7. `sync.sh`
8. Slim the dispatcher; update `tests/unit_tests.sh` to source modules directly instead of sed-extracting functions from `bin/git-issue`.

## Testing

- Existing suites run unchanged (they exercise the CLI) — they are the behavior-preservation oracle.
- **Layout smoke test** (new, in CI): `make install DESTDIR=$tmp`, then invoke through a symlinked bin dir imitating Homebrew's shape (`ln -s $tmp/usr/bin/git-issue $tmp/fakebrew/git-issue`) and assert a real command works. Runs on ubuntu + macos.
- **Release checklist addition:** run `brew test git-issue` after each tap bump — Homebrew's native formula test, exercising the linked install through the real symlink.
- `tests/unit_tests.sh` switches from sed-extraction to sourcing modules (step 8).

## Error handling

Missing/unresolvable lib dir: fatal, message names the resolved path it tried, suggests reinstall or `GIT_ISSUE_LIB`. Individually missing module or awk file: same treatment (fail fast at source/use time, no feature-degraded mode).

## Out of scope

Language change; behavior changes; strict-format enforcement (#606e606); registry (below); parallelizing anything.

---

## Sub-project 2: Multi-project registry (summary — detailed spec when reached)

Blocked by the refactor. Decisions already made:

- **Store:** global git config — `issue.repo.<name>.path`; readable by agents with stock `git config --get-regexp '^issue\.repo\.'`.
- **Commands:** `git issue repo add <name> <path>`, `repo list` (annotates missing paths), `repo rm <name>`.
- **Targeting:** `--repo <name>` on existing commands; **aggregation:** `list --all` / `ready --all` with `[name]`-prefixed lines.
- **Mechanism:** one subprocess per repo (`cd <path> && exec git-issue ...`) — remains the correct isolation seam post-refactor because sourced bash modules still share process-global state (GIT_DIR, caches, status machine). Works for both git and XDG backends since backend detection is per-directory.
- **Origin:** explicit `repo add` registration (per design conversation, 2026-08-13); no auto-registration, at most a hint.
