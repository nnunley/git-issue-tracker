# Single-File Refactor (Dual-Mode + External Awk) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `bin/git-issue` sourceable with busybox-style `$0` dispatch (absorbing `git-issue-status` as a symlink), and externalize its three awk programs to `share/git-issue/awk/`, per `docs/plans/2026-08-13-modularization-refactor-design.md`. Zero behavior change.

**Architecture:** All top-level execution moves into `main()`; the file tail runs `_gi_entry "$@"` only when executed (`BASH_SOURCE == $0`), dispatching on `basename "$0"`. `bin/git-issue-status` becomes a symlink; its logic becomes `status_report()`. Awk programs load with `awk -f` from the existing `share/git-issue/` surface.

**Tech Stack:** bash 3.2+, git plumbing, awk (BSD awk + gawk + mawk), shellcheck, bash test framework in `tests/`.

## Global Constraints

- All work on branch `refactor/dispatch-and-awk`; merge to main only in the final task.
- After EVERY task: full suite green (`for t in tests/*.sh; do ./$t; done` — every script exit 0) AND `shellcheck -S error bin/git-issue` clean. A task is not done otherwise.
- No behavior/output changes. Only `tests/unit_tests.sh` may change to pass (Task 1's sourcing rework); any other test edit is a defect in the move.
- Moves are verbatim cut/paste; flag any non-move edit in the commit message.
- No top-level `readonly`; sourcing the file must be repeatable and side-effect-free (no output, no `set -e` leakage).
- Awk files: params only via `-v`, data on stdin, no environment access, no interval quantifiers `{n}` (mawk/BSD awk compat — the delimiter match already uses `substr`/`length` for this reason).
- Function references are to `bin/git-issue` at commit `3057f7b`; locate by name (`grep -n '^funcname()' bin/git-issue`), never by line number.

---

### Task 1: Dual-mode + multi-call dispatch; absorb `git-issue-status`; rework unit tests

**Files:**
- Modify: `bin/git-issue` (wrap tail in `main()`, add `_gi_entry()`/`status_report()`, move `set -e`)
- Delete + symlink: `bin/git-issue-status` → `git-issue`
- Create: `tests/test_dispatch.sh`
- Modify: `tests/unit_tests.sh` (source instead of sed-extract)
- Modify: `Makefile`, `Formula/git-issue.rb`, `git-issue-local.rb`, `install-git-issue.sh` (install symlink)

**Interfaces:**
- Produces: `main "$@"` (the current dispatch case, verbatim), `status_report "$@"` (current git-issue-status body, using `read_issue_data`/`extract_issue_id` instead of its deleted private `read_issue_data_by_ref`), `_gi_entry "$@"` (basename dispatch). Sourcing `bin/git-issue` defines all 70+ functions and executes nothing.

- [ ] **Step 1: Create the branch**

```bash
git checkout -b refactor/dispatch-and-awk
```

- [ ] **Step 2: Write the failing dispatch test**

Create `tests/test_dispatch.sh` (mode 755):

```bash
#!/bin/bash
# Dual-mode + multi-call dispatch tests
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }

# 1) Sourcing executes nothing and does not enable set -e in the caller
out=$(bash -c 'set +e; source "'"$REPO_DIR"'/bin/git-issue"; [[ $- == *e* ]] && echo "E_LEAK"; echo "SRC_OK"')
[[ "$out" == "SRC_OK" ]] && ok "sourcing is silent and set -e does not leak" \
                         || bad "sourcing produced output or leaked set -e: '$out'"

# 2) Sourcing defines the core functions
bash -c 'source "'"$REPO_DIR"'/bin/git-issue"; declare -f read_issue_data trim_ws status_report main >/dev/null' \
    && ok "core functions defined after sourcing" || bad "functions missing after sourcing"

# 3) A symlink named git-issue-status dispatches to the status report
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
cd "$WORK" && git init -q && git config user.name T && git config user.email t@t.co
git commit -q --allow-empty -m init
ln -s "$REPO_DIR/bin/git-issue" "$WORK/git-issue-status"
"$WORK/git-issue-status" 2>/dev/null | grep -q "Issue Status Report" \
    && ok "symlink dispatches to status report" || bad "symlink did not dispatch to status report"

# 4) Normal invocation still dispatches commands
"$REPO_DIR/bin/git-issue" create "dispatch smoke" >/dev/null 2>&1
"$REPO_DIR/bin/git-issue" list 2>/dev/null | grep -q "dispatch smoke" \
    && ok "direct invocation dispatches main" || bad "direct invocation broken"

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
```

Run: `./tests/test_dispatch.sh`
Expected: FAIL — sourcing currently executes the dispatch case (test 1 emits usage/errors), and there is no `status_report`.

- [ ] **Step 3: Restructure `bin/git-issue`**

1. Delete `set -e` from the top of the file.
2. Find the top-level execution tail (starts at `detect_storage_backend` followed by `load_statuses` and the dispatch `case` — currently the last ~200 lines). Wrap it verbatim in `main() { ... }` (the `cleanup_xdg_environment` calls at its end stay inside).
3. Append `status_report()` — the body of today's `bin/git-issue-status` from its first `echo` to the end, verbatim, with two edits (flagged): its private `read_issue_data_by_ref "$ref"` calls become `read_issue_data "$(extract_issue_id "$ref")"`, and its final `"$(dirname "$0")/git-issue" list` becomes `list_issues` (colors/helpers already in scope; delete its duplicated color block and `set -e`).
4. Append the entry gate as the last lines of the file:

```bash
_gi_entry() {
    case "$(basename "$0")" in
        git-issue-status) status_report "$@" ;;
        *)                main "$@" ;;
    esac
}

# Execute only when run, not when sourced — consumers may `source bin/git-issue`
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -e
    _gi_entry "$@"
fi
```

- [ ] **Step 4: Replace `bin/git-issue-status` with a symlink**

```bash
git rm bin/git-issue-status
ln -s git-issue bin/git-issue-status
git add bin/git-issue-status
```

- [ ] **Step 5: Update installers to ship the symlink**

- Makefile `install:`: replace `install -m 755 bin/git-issue-status $(BINDIR)/` with `ln -sf git-issue $(BINDIR)/git-issue-status`.
- `Formula/git-issue.rb` and `git-issue-local.rb`: replace `bin.install "bin/git-issue-status"` with `bin.install_symlink bin/"git-issue" => "git-issue-status"` (placed after the `bin.install "bin/git-issue"` line).
- `install-git-issue.sh`: replace the `cp .../git-issue-status ...` line with `ln -sf git-issue "$INSTALL_DIR/git-issue-status"`.

- [ ] **Step 6: Rework `tests/unit_tests.sh`**

Delete its sed/awk function-extraction into a temp file; replace with:

```bash
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../bin/git-issue"   # dual-mode: defines functions, executes nothing
```

Delete the temp-file cleanup for the extraction artifact.

- [ ] **Step 7: Run tests**

Run: `./tests/test_dispatch.sh` → `PASS=… FAIL=0`
Run: full suite + `shellcheck -S error bin/git-issue` → green/clean. (`git-issue-status` is now a symlink — drop it from any shellcheck invocation lists.)

- [ ] **Step 8: File tracker issues, commit**

```bash
git issue create "refactor: dual-mode dispatch + external awk (epic)"     # note id -> EPIC
git issue create "refactor: dual-mode + \$0 dispatch, absorb git-issue-status"   # -> C1
git issue create "refactor: externalize awk programs to share/git-issue/awk"     # -> C2
git issue create "refactor: merge gate + rc5 release"                            # -> C3
git issue dep add <EPIC> parent_of <C1>   # repeat for C2, C3
git issue close <C1>
git add bin/git-issue bin/git-issue-status tests/test_dispatch.sh tests/unit_tests.sh Makefile Formula/git-issue.rb git-issue-local.rb install-git-issue.sh
git commit -m "refactor: dual-mode script with \$0 dispatch, git-issue-status as symlink

Non-move edits: set -e relocated into the executed-only entry gate;
status_report uses read_issue_data/extract_issue_id instead of its
deleted private read_issue_data_by_ref; its trailing git-issue list
subprocess becomes a list_issues call."
```

---

### Task 2: Externalize awk programs to `share/git-issue/awk/`

**Files:**
- Create: `share/git-issue/awk/extract_issues.awk`, `share/git-issue/awk/front_matter.awk`, `share/git-issue/awk/body.awk`
- Modify: `bin/git-issue` (awk-dir resolution + three invocation swaps)
- Modify: `tests/test_content_safety.sh` (awk-direct test)
- Modify: `Makefile`, `Formula/git-issue.rb`, `git-issue-local.rb`, `install-git-issue.sh` (ship awk dir)
- Create: `tests/test_install_layout.sh`; Modify: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: the existing share lookup at `bin/git-issue:108` (`$GIT_ISSUE_BIN_DIR/../share/git-issue`).
- Produces: `GIT_ISSUE_AWK_DIR` (env-overridable), `require_awk_file(name)` (hard error on missing), three `.awk` files each documenting `-v FIELDS` in a header comment.

- [ ] **Step 1: Write the failing awk-direct test**

Append to `tests/test_content_safety.sh` (register in `main` as `run_test "front_matter.awk parses split front matter directly" test_front_matter_awk_direct`):

```bash
test_front_matter_awk_direct() {
    local awk_dir="$SCRIPT_DIR/../share/git-issue/awk"
    local fields='id|title|status|state|priority|created|updated|author|assignee|role|labels|hash_source|github_id|github_url|jira_id|jira_url|gitlab_id|gitlab_url|blocks|depends_on|parent_of|relates_to|issue_type|external_ref|waits_for'
    local out
    out=$(printf 'id: abc1234\ntitle: T\n\nbody line\nnote: prose stays\nstatus: closed\n' \
        | awk -f "$awk_dir/front_matter.awk" -v FIELDS="$fields")
    assert_contains "status: closed" "$out" "awk-direct: trailing known header honored"
    assert_contains "id: abc1234" "$out" "awk-direct: top id preserved"
    if echo "$out" | grep -q "note: prose"; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} awk-direct: prose must not be emitted as a header"
    else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} awk-direct: prose must not be emitted as a header"
    fi
}
```

Run: `./tests/test_content_safety.sh` → new test FAILS (file doesn't exist).

- [ ] **Step 2: Create the three awk files**

Each begins with a header comment naming its required `-v` vars, then the **verbatim** awk program currently inline in, respectively: `_issue_tsv_stream()` → `extract_issues.awk` (`# Required: -v FIELDS=<pipe-separated known field names>. Input: __ISSUE__-delimited batch stream on stdin. Output: US(\037)-separated: id status title priority assignee role depends_on`); `parse_front_matter()` → `front_matter.awk`; `parse_body()` → `body.awk`. The `BEGIN { known_re = "^(" FIELDS "):" }` / `header_re` lines are retained — only the surrounding shell quoting is removed.

- [ ] **Step 3: Add resolution + swap invocations in `bin/git-issue`**

After the existing share-dir lookup pattern (reuse it — see `load_statuses`), add near the top:

```bash
# Awk program directory: env override, else the share dir next to the binary.
# Unlike statuses (which have an in-script fallback), a missing awk file is fatal.
if [[ -z "${GIT_ISSUE_AWK_DIR:-}" ]]; then
    if [[ -d "$GIT_ISSUE_BIN_DIR/../share/git-issue/awk" ]]; then
        GIT_ISSUE_AWK_DIR="$GIT_ISSUE_BIN_DIR/../share/git-issue/awk"
    elif [[ -d "/usr/local/share/git-issue/awk" ]]; then
        GIT_ISSUE_AWK_DIR="/usr/local/share/git-issue/awk"
    fi
fi

require_awk_file() {
    local f="$GIT_ISSUE_AWK_DIR/$1"
    [[ -f "$f" ]] || { echo -e "${RED}Error: awk program not found: $f — reinstall git-issue or set GIT_ISSUE_AWK_DIR${NC}" >&2; exit 1; }
    printf '%s' "$f"
}
```

Swap the three inline programs for:

```bash
awk -f "$(require_awk_file front_matter.awk)" -v FIELDS="$KNOWN_HEADER_FIELDS"
awk -f "$(require_awk_file body.awk)" -v FIELDS="$KNOWN_HEADER_FIELDS"
_batch_issue_stream | awk -f "$(require_awk_file extract_issues.awk)" -v FIELDS="$KNOWN_HEADER_FIELDS"
```

- [ ] **Step 4: Ship the awk dir in every installer**

- Makefile `install:`: `install -d $(SHAREDIR)/awk` + `install -m 644 share/git-issue/awk/*.awk $(SHAREDIR)/awk/`; `uninstall:` already removes `$(SHAREDIR)` wholesale — verify.
- Both formulas: `(share/"git-issue/awk").install Dir["share/git-issue/awk/*.awk"]`.
- `install-git-issue.sh`: after the bin copies, `mkdir -p "$INSTALL_DIR/../share/git-issue/awk" && cp share/git-issue/awk/*.awk "$INSTALL_DIR/../share/git-issue/awk/"`.

- [ ] **Step 5: Write the layout smoke test + CI hook**

Create `tests/test_install_layout.sh` (755):

```bash
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
```

Note: if the current Makefile install paths lack `$(DESTDIR)`, add `$(DESTDIR)` to every install path as part of this step.

`.github/workflows/test.yml`, after "Run content safety tests":
```yaml
    - name: Run dispatch tests
      run: ./tests/test_dispatch.sh
    - name: Run install layout smoke test
      run: ./tests/test_install_layout.sh
```
Also add `test-layout` and `test-dispatch` targets to the Makefile and `test-all`.

- [ ] **Step 6: Gate + commit**

Full suite (incl. new tests) + shellcheck green, then:
```bash
git add share/git-issue/awk bin/git-issue tests/test_content_safety.sh tests/test_install_layout.sh Makefile Formula/git-issue.rb git-issue-local.rb install-git-issue.sh .github/workflows/test.yml
git commit -m "refactor: externalize awk programs to share/git-issue/awk"
git issue close <C2>
```

---

### Task 3: Merge gate + rc5 release

- [ ] **Step 1: Output-parity check** — in this repo, diff branch vs installed rc4: `diff <(git-issue list 2>/dev/null) <(./bin/git-issue list 2>/dev/null)` and same for `ready`, `git issue-status`. Expected: empty diffs.
- [ ] **Step 2: Merge** — `git checkout main && git merge --no-ff refactor/dispatch-and-awk -m "refactor: dual-mode dispatch and external awk programs" && git push`. Close `<C3>` and `<EPIC>`.
- [ ] **Step 3: Release rc5** — per the rc3/rc4 procedure: VERSION → `1.0.0-rc5`, commit, tag, push; tarball sha256; update `Formula/git-issue.rb` (repo) and mirror to tap `nnunley/homebrew-git-issue`; `brew upgrade git-issue`; **`brew test git-issue`** (new checklist step — exercises the linked symlink chain for real).
- [ ] **Step 4: Unblock registry** — the registry issue's `depends_on` on the epic auto-unblocks on close; verify with `git issue ready`.

---

## Self-Review Notes

- Spec coverage: dual-mode ✓ (T1), multi-call symlink + installers ✓ (T1), status dedupe ✓ (T1 S3), unit-test sourcing ✓ (T1 S6), awk externalization + contract + hard error ✓ (T2), awk-direct test ✓ (T2 S1), layout smoke incl. symlink chain ✓ (T2 S5), brew test on release ✓ (T3), branch + tracker issues ✓ (T1).
- Non-move edits are enumerated in T1 S8's commit message body; T2's only non-move edit is the three invocation swaps + resolution block, named in its message.
- Types/names: `status_report`, `_gi_entry`, `main`, `require_awk_file`, `GIT_ISSUE_AWK_DIR` used consistently across tasks.
