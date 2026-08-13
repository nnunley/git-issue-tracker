# Single-File Refactor: Dual-Mode Dispatch + External Awk — Design

**Date:** 2026-08-13 (revised same day; supersedes the libexec module split)
**Status:** Approved pending review
**Sequence:** Sub-project 1 of 2. Sub-project 2 (multi-project registry, summarized at the end) builds on this and is blocked by it.

## Goal

Remove the measured maintenance costs of `bin/git-issue` (3,240 lines) **without splitting it into module files**. The 2026-08-13 hardening showed the real costs were duplication (three copy-pasted awk extractors, 21 `xargs` sites, a duplicated `read_issue_data` in `git-issue-status`, sed-based function extraction in unit tests) — all addressable in one file. No behavior changes; the test suite is the oracle.

### Why not the module split (decision record)

An earlier revision of this spec proposed `libexec/git-issue/{storage,format,deps,...}.sh`. Review concluded the split's unique benefits ("file-sized review units", "boundaries for future work") were self-justifying — bash modules are process-global anyway, and every concrete pain point is fixable in-file. The split remains available later if file size becomes a demonstrated problem.

## Design

### 1. Dual-mode script

`bin/git-issue` becomes sourceable: all top-level execution (currently `detect_storage_backend; load_statuses;` + the dispatch `case` at the file tail) moves into `main()`, and the file ends with:

```bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -e
    _gi_entry "$@"
fi
```

`set -e` moves from the top of the file into this executed-only branch — sourcing must not mutate the caller's shell options. Consumers (`tests/unit_tests.sh`, future tooling) `source bin/git-issue` to get every function with zero extraction machinery. Top-level code outside functions is limited to variable defaults; no `readonly` (re-sourcing must be safe).

### 2. Multi-call dispatch (busybox-style)

```bash
_gi_entry() {
    case "$(basename "$0")" in
        git-issue-status) status_report "$@" ;;
        *)                main "$@" ;;
    esac
}
```

`bin/git-issue-status` becomes a **symlink** to `git-issue`. Its report logic moves into `bin/git-issue` as `status_report()`, deleting its duplicated `read_issue_data_by_ref` (uses the canonical `read_issue_data`/`extract_issue_id`). All installers install the symlink: Makefile (`ln -sf git-issue $(BINDIR)/git-issue-status`), both formulas (`bin.install_symlink`), `install-git-issue.sh` (`ln -sf`).

### 3. External awk programs

The three substantial awk programs move to files under the **existing** `share/git-issue/` install surface (already shipped by Makefile, both formulas, and resolvable via the script's existing `../share/git-issue` lookup at `bin/git-issue:108`):

```
share/git-issue/awk/
  extract_issues.awk   # batch-stream record state machine (US-separated output)
  front_matter.awk
  body.awk
```

Resolution: `$GIT_ISSUE_AWK_DIR` env override → `<share_dir>/awk` via the existing share lookup. Missing awk file is a **hard error** (unlike statuses, which has an in-script fallback) — never a silent degraded mode. Contract: each `.awk` documents its `-v` variables in a header comment; data on stdin, parameters via `-v`, no environment access; must run under BSD awk, gawk, and mawk. Each is independently testable: `awk -f extract_issues.awk -v FIELDS=... < fixture`.

`install-git-issue.sh` currently ships no share files (statuses fall back in-script); it now must install `share/git-issue/awk/`.

## Process

- All work on branch `refactor/dispatch-and-awk`; merge to main when complete (abandonable work never lands on main).
- Small mechanical commits; full test suite + `shellcheck -S error` green at every commit.
- Moves are verbatim; any non-move edit is flagged in the commit message.
- Tracker: one epic with a child per task; registry issue blocked by the epic.

## Testing

- Existing suites unchanged except `tests/unit_tests.sh`, which switches from sed-extraction to `source bin/git-issue` (fixes the extraction fragility that caused the earlier `readonly` collision).
- New assertions: (a) sourcing `bin/git-issue` executes nothing and leaves `set -e` untouched; (b) the `git-issue-status` symlink dispatches to the status report; (c) awk-direct fixture test for `front_matter.awk`.
- **Layout smoke test** (new, in CI): `make install DESTDIR=$tmp`, invoke directly AND through a brew-style symlinked bin dir, including the `git-issue-status` symlink chain (symlink → symlink → script must still dispatch as status).
- **Release checklist addition:** run `brew test git-issue` after each tap bump.

## Out of scope

Module file split; language change; behavior changes; strict-format enforcement (#606e606); registry (below).

---

## Sub-project 2: Multi-project registry (summary — detailed spec when reached)

Blocked by this refactor. Decisions already made:

- **Store:** global git config — `issue.repo.<name>.path`; readable by agents with stock `git config --get-regexp '^issue\.repo\.'`.
- **Commands:** `git issue repo add <name> <path>`, `repo list` (annotates missing paths), `repo rm <name>`.
- **Targeting:** `--repo <name>` on existing commands; **aggregation:** `list --all` / `ready --all` with `[name]`-prefixed lines.
- **Mechanism:** one subprocess per repo (`cd <path> && exec git-issue ...`) — the correct isolation seam since the script's state (GIT_DIR, caches, status machine) is process-global. Works for both git and XDG backends since backend detection is per-directory.
- **Origin:** explicit `repo add` registration (per design conversation, 2026-08-13); no auto-registration, at most a hint.
