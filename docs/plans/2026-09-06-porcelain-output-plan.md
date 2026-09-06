# Porcelain Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement draft-ndn-porcelain-output-00 in `bin/git-issue` so all fourteen requirement transcripts replay green.

**Architecture:** A `--porcelain[=v1]` flag parsed once in `_gi_dispatch` and relayed to every code path (including the `--repo` and `--all` re-execs) through the `GIT_ISSUE_PORCELAIN` environment variable. Read commands branch on that variable at their output step only; data gathering is shared with the human format. Storage moves to "format 2" (a `v: 2` marker, `description` as a header, leading-space continuation for multi-line values) through one upgrade wrapper in `write_issue_data` plus a fold helper used by the write paths, while the readers accept both formats by checking the marker.

**Tech Stack:** bash 3.2 compatible, POSIX awk (awk programs live in `share/git-issue/awk/`), the repo's shell test harness (`tests/*.sh`, `eq` helper), and the RFC conformance tooling (`rfc-run`, `rfc-check` from `~/.claude/skills/authoring-rfcs/`).

**Spec:** `docs/rfc/draft-ndn-porcelain-output-00.md`. Requirement IDs in this plan refer to it. Read the spec's transcripts before each task; they are the acceptance tests.

## Global Constraints

- Every read command MUST accept `--porcelain` before or after the subcommand, and `--porcelain=v1`; any other version is `Error: unsupported porcelain version '<v>' (supported: v1)` on stderr, exit 1. [R-flag-position] [R-version-frozen]
- In porcelain mode stdout carries records only; informational banners are suppressed on stderr too; empty result = empty stdout, exit 0. [R-plain-stdout]
- Issue line columns, in order: `repo id status priority assignee role updated blocks depends_on parent_of relates_to title`, tab-separated, twelve columns. [R-issue-line]
- Stored notes carry `v: 2` as line 2, immediately after `id:`. Every write emits format 2. [R-format-marker]
- Continuation line = exactly one leading space, both in `show --porcelain` output and in stored format-2 values. [R-show-block] [R-store-continuation]
- A note without `v: 2` is format 1: description is the body region; comments section lines not starting with `[` continue the previous comment verbatim. [R-legacy-read]
- Tab, CR, LF in single-line fields become one space on write and on porcelain read. [R-field-normalize]
- Human-format output without `--porcelain` MUST NOT change. The existing suites (`make test-all`) are the oracle for that.
- No new dependencies. No Claude attribution in commits (hook-enforced).
- Bash 3.2: no associative arrays, no `${var,,}`, no `mapfile`.
- Run every verification as `PATH="$PWD/bin:$PATH"` so `git issue` resolves to the checked-out script, not the Homebrew install.

### Corpus commands (used throughout)

```bash
# Single RFC, expect declared state (red until Task 11 flips it):
PATH="$PWD/bin:$PATH" ~/.claude/skills/authoring-rfcs/rfc-run --expect docs/rfc/draft-ndn-porcelain-output-00.md
# Same, but show which blocks pass right now (ignore the EXPECT verdict; count PASS lines):
PATH="$PWD/bin:$PATH" ~/.claude/skills/authoring-rfcs/rfc-run docs/rfc/draft-ndn-porcelain-output-00.md 2>&1 | grep -E '^(PASS|FAIL)'
# Whole gate:
PATH="$PWD/bin:$PATH" ~/.claude/skills/authoring-rfcs/rfc-check docs/rfc
# Existing suites:
make test-all
```

### Test file conventions

All new assertions go in `tests/test_porcelain.sh`, created in Task 1. It follows `tests/test_registry.sh`: `set -e`, `GI` resolved to the checked-out binary, `ok`/`bad`/`eq` helpers, a section `echo "Testing <topic> ..."` naming the requirement IDs it covers, and `[[ $FAIL -eq 0 ]]` as the last statement. Each test section starts from a fresh repository via the `fresh_repo` helper defined in Task 1.

---

## File map

| File | Responsibility in this plan |
|---|---|
| `bin/git-issue` | flag parsing, banner gating, porcelain output branches, format-2 write and read helpers |
| `share/git-issue/awk/extract_issues.awk` | batch issue stream: grows from 7 to 11 fields, tab normalization |
| `share/git-issue/awk/front_matter.awk` | header parsing with continuation lines |
| `share/git-issue/awk/body.awk` | unchanged; bypassed for format-2 notes |
| `share/git-issue/awk/upgrade_note.awk` (new) | format 1 → format 2 rewrite used by `write_issue_data` |
| `share/git-issue/awk/comments.awk` (new) | comments section → canonical folded records, both formats |
| `tests/test_porcelain.sh` (new) | assertions tagged by requirement ID |
| `Makefile`, `.github/workflows/test.yml` | wire the new suite |
| `README.md`, `man/man1/git-issue.1` | document the flag and format 2 |
| `docs/rfc/draft-ndn-porcelain-output-00.md` | corpus declaration flips red → green in Task 11 |

---

### Task 1: The flag, its relay, banner suppression, and the test file

**Files:**
- Modify: `bin/git-issue:3175-3224` (`_gi_dispatch`), `bin/git-issue:62,79,103` (banners in `detect_storage_backend`), `bin/git-issue:184` (status compiler call), `bin/git-issue:240-290` (usage text)
- Create: `tests/test_porcelain.sh`
- Modify: `Makefile:95-105`, `.github/workflows/test.yml:70-71`

**Interfaces:**
- Produces: environment variable `GIT_ISSUE_PORCELAIN=1` (exported before `main`, `_gi_target_repo`, `_gi_aggregate`). Every later task tests `[[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]`.
- Produces: helper `gi_info "<text>"` that echoes to stderr unless porcelain.
- Produces: test helpers `fresh_repo` and `porcelain_ids` in `tests/test_porcelain.sh`.

- [ ] **Step 1: Create the test file with helpers and the first failing assertions**

Create `tests/test_porcelain.sh`:

```bash
#!/usr/bin/env bash
# Porcelain output tests — draft-ndn-porcelain-output-00.
# Each section names the requirement IDs it covers. The RFC's transcripts
# are the conformance corpus; these assertions are the faster unit layer
# and cover edge cases the transcripts do not.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GI="$REPO_DIR/bin/git-issue"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
eq()  { # eq <label> <want> <got>
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1"$'\n'"      want: $2"$'\n'"      got:  $3"; fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK" XDG_CONFIG_HOME="$WORK/.config" GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_ISSUE_PORCELAIN
git config --global user.name conformance
git config --global user.email conformance@rfc

# fresh_repo <name>: create and enter an empty repository with one commit.
fresh_repo() {
    local d="$WORK/$1"
    rm -rf "$d"; mkdir -p "$d"; cd "$d"
    git init -q; git commit -q --allow-empty -m init
}
# porcelain_ids: ids of all issues, one per line, in list order.
porcelain_ids() { "$GI" list --porcelain | cut -f2; }

echo "Testing flag position and version [R-flag-position] [R-version-frozen]"
fresh_repo flag
"$GI" create "alpha task" >/dev/null 2>&1
eq "flag before subcommand" "alpha task" "$("$GI" --porcelain list | cut -f12)"
eq "flag after subcommand"  "alpha task" "$("$GI" list --porcelain | cut -f12)"
eq "explicit v1"            "alpha task" "$("$GI" list --porcelain=v1 | cut -f12)"
eq "v2 rejected" \
   "Error: unsupported porcelain version 'v2' (supported: v1)" \
   "$("$GI" list --porcelain=v2 2>&1 || true)"
set +e; "$GI" list --porcelain=v2 >/dev/null 2>&1; rc=$?; set -e
eq "v2 exit status" "1" "$rc"

echo "Testing plain stdout [R-plain-stdout]"
fresh_repo plain
eq "empty list is empty stdout" "0" "$("$GI" list --porcelain | wc -c | tr -d ' ')"
eq "empty list is silent on stderr" "" "$("$GI" list --porcelain 2>&1 >/dev/null)"
eq "no banner under --porcelain" "0" "$("$GI" list --porcelain 2>&1 | grep -c 'Using current' || true)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
```

Every later task appends its section before the final `echo ""` line.

- [ ] **Step 2: Run it to verify it fails**

Run: `chmod +x tests/test_porcelain.sh && ./tests/test_porcelain.sh`
Expected: the flag assertions fail (the current script treats `--porcelain` as an unknown argument or an issue id); the "empty list is empty stdout" assertion fails because the `Issues:` header is printed.

- [ ] **Step 3: Parse the flag in `_gi_dispatch`**

In `bin/git-issue`, in `_gi_dispatch` (line 3175), change the local declaration and the peel loop:

```bash
_gi_dispatch() {
    local -a rest=()
    local arg target="" all=0 want_target=0 porcelain=0 pv=""
    for arg in "$@"; do
        if [[ $want_target -eq 1 ]]; then
            target="$arg"; want_target=0; continue
        fi
        case "$arg" in
            --repo)   want_target=1 ;;
            --repo=*) target="${arg#--repo=}" ;;
            --all)    all=1 ;;
            --porcelain) porcelain=1 ;;
            --porcelain=*)
                pv="${arg#--porcelain=}"
                if [[ "$pv" != "v1" ]]; then
                    echo "Error: unsupported porcelain version '$pv' (supported: v1)" >&2
                    exit 1
                fi
                porcelain=1 ;;
            *)        rest+=("$arg") ;;
        esac
    done
    if [[ $porcelain -eq 1 ]]; then
        export GIT_ISSUE_PORCELAIN=1
    fi
```

The rest of `_gi_dispatch` is unchanged: the export happens before the `repo` routing, the `--all` aggregate, the `--repo` re-exec, and the plain `main` call, so all four paths inherit it (the two `exec` paths through the environment).

- [ ] **Step 4: Gate the informational banners**

Add this helper next to `get_git_user` (around line 119):

```bash
# Informational message to stderr; silent in porcelain mode (R-plain-stdout).
gi_info() {
    if [[ -z "${GIT_ISSUE_PORCELAIN:-}" ]]; then
        echo -e "$@" >&2
    fi
}
```

In `detect_storage_backend`, replace each of the three banner lines (62, 79, 103) of the form `echo -e "${BLUE}Using ...${NC}" >&2` with `gi_info "${BLUE}Using ...${NC}"`, keeping the text identical.

At line 184, replace `"$compiler" "$def_file" >&2` with:

```bash
            if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
                "$compiler" "$def_file" >/dev/null 2>&1
            else
                "$compiler" "$def_file" >&2
            fi
```

- [ ] **Step 5: Gate the `Issues:` header**

In `list_issues` (line 535), change the condition to cover both suppressors:

```bash
    if [[ -z "${GIT_ISSUE_NO_HEADER:-}" && -z "${GIT_ISSUE_PORCELAIN:-}" ]]; then
        echo -e "${BLUE}Issues:${NC}"
        echo ""
    fi
```

Do the same in `list_ready_issues` at lines 2559 and 2561: `[[ -z "${GIT_ISSUE_NO_HEADER:-}" && -z "${GIT_ISSUE_PORCELAIN:-}" ]] && ...`.

- [ ] **Step 6: Document the flag in usage**

In the usage text (the `Global options:` block near line 283), add after `--all`:

```bash
    echo "  --porcelain[=v1]                        Stable machine-readable output (see docs/rfc)"
```

- [ ] **Step 7: Run the test file and the existing suites**

Run: `./tests/test_porcelain.sh`
Expected: flag-position, version, and plain-stdout sections pass. (`list --porcelain` still prints the colored human line for a non-empty repo; that is Task 3.)

Run: `make test-all`
Expected: all existing suites pass; human output is unchanged.

- [ ] **Step 8: Wire the suite into Makefile and CI**

In `Makefile`, after the `test-registry` target (line 95-98) add:

```make
test-porcelain: ## Run porcelain output tests
	chmod +x tests/test_porcelain.sh
	./tests/test_porcelain.sh
```

and add `test-porcelain` to the `test-all` dependency list on line 105.

In `.github/workflows/test.yml`, after the registry step (lines 70-71) add:

```yaml
      - name: Run porcelain output tests
        run: ./tests/test_porcelain.sh
```

Match the indentation of the surrounding steps exactly.

- [ ] **Step 9: Commit**

```bash
git add bin/git-issue tests/test_porcelain.sh Makefile .github/workflows/test.yml
git commit -m "feat(porcelain): parse --porcelain[=v1] and silence banners

Adds the flag in _gi_dispatch so it works before or after the subcommand
and survives the --repo and --all re-execs through GIT_ISSUE_PORCELAIN.
Unsupported versions fail loudly. Informational banners are gated behind
gi_info so porcelain stdout and stderr both stay quiet.

Covers R-flag-position, R-version-frozen, and the banner half of
R-plain-stdout. Output records come in the next commits."
```

---

### Task 2: Widen the batch issue stream to eleven fields

**Files:**
- Modify: `share/git-issue/awk/extract_issues.awk`
- Modify: `bin/git-issue:541` (`list_issues` read), `bin/git-issue:2496-2513` (`list_ready_issues` reads), `bin/git-issue:2588` (`topo_sort_issues` read)
- Test: `tests/test_porcelain.sh` (a stream-shape section)

**Interfaces:**
- Produces: `_issue_tsv_stream` emits, US-separated (`\037`), in this order: `id status title priority assignee role depends_on updated blocks parent_of relates_to`. The first seven are unchanged so existing readers keep working; four are appended.
- Produces: tabs inside any field become a single space; other control characters are still stripped.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_porcelain.sh` before the final summary:

```bash
echo "Testing batch stream shape (internal) [R-issue-line] [R-field-normalize]"
fresh_repo stream
"$GI" create "$(printf 'tab\there')" >/dev/null 2>&1
# Sourcing the script exposes its functions without running the entry
# point (the guard at the bottom checks BASH_SOURCE[0] == $0).
stream=$(cd "$WORK/stream" && bash -c "source '$GI' 2>/dev/null; _issue_tsv_stream")
eq "stream has eleven fields" "11" "$(printf '%s' "$stream" | awk -F'\037' '{print NF}')"
eq "tab in title becomes a space" "tab here" "$(printf '%s' "$stream" | cut -d $'\037' -f3)"
eq "updated is the eighth field" "1" "$(printf '%s' "$stream" | cut -d $'\037' -f8 | grep -c 'T.*Z')"
```

If sourcing fails because the script calls `set -e` or `_gi_check_awk_files` at top level, read the guard at the bottom of `bin/git-issue` (around line 3515) and mirror what `tests/unit_tests.sh` does to load functions.

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/test_porcelain.sh`
Expected: "stream has eleven fields" fails with got `7`; "tab in title" fails with got `tabhere`.

- [ ] **Step 3: Extend the awk**

Edit `share/git-issue/awk/extract_issues.awk`. Change the header comment's output list, the `emit` print line, and the control-character line:

```awk
# Required: -v FIELDS=<pipe-separated known field names>. Input: __ISSUE__-delimited batch stream on stdin.
# Output: US(\037)-separated: id status title priority assignee role depends_on updated blocks parent_of relates_to
```

In `emit`, replace the `print` line with:

```awk
        print top["id"] OFS status OFS top["title"] OFS top["priority"] OFS top["assignee"] OFS top["role"] OFS top["depends_on"] OFS top["updated"] OFS top["blocks"] OFS top["parent_of"] OFS top["relates_to"]
```

Replace `{ gsub(/[[:cntrl:]]/, "") }` with:

```awk
{ gsub(/\t/, " "); gsub(/[[:cntrl:]]/, "") }
```

Continuation lines (a leading space) do not match `header_re`, so a format-2 `description:` header's continuation lines are skipped in the top block exactly as body prose is today. No change needed for them here.

- [ ] **Step 4: Update the three readers' variable lists**

The readers destructure with `IFS=$'\037' read -r ...`; they must name the new fields or the trailing catch-all absorbs them. Update:

`list_issues` line 541:
```bash
    _issue_tsv_stream | while IFS=$'\037' read -r id status_val title priority assignee role depends_on updated blocks parent_of relates_to; do
```

`list_ready_issues` line 2496 (status index loop) and line 2505 (filter loop):
```bash
    while IFS=$'\037' read -r id status_val _ _ _ _ _ _ _ _ _; do
```
```bash
    while IFS=$'\037' read -r id status_val title priority assignee role depends_on updated blocks parent_of relates_to; do
```

`topo_sort_issues` line 2588:
```bash
    while IFS=$'\037' read -r id status_val title priority _ _ depends_on _ _ _ _; do
```

- [ ] **Step 5: Run tests**

Run: `./tests/test_porcelain.sh && make test-all`
Expected: the stream section passes; every existing suite passes (human output unchanged).

- [ ] **Step 6: Commit**

```bash
git add share/git-issue/awk/extract_issues.awk bin/git-issue tests/test_porcelain.sh
git commit -m "refactor(stream): emit updated and all four dependency fields

The batch stream grows from seven to eleven fields, appended so existing
readers are unaffected, and tabs inside fields become spaces instead of
vanishing. Groundwork for the twelve-column porcelain issue line."
```

---

### Task 3: Issue lines for list, ready, queue, topo

**Files:**
- Modify: `bin/git-issue` — `list_issues` (532-561), `list_ready_issues` (2469-2571), `topo_sort_issues` (2574-2653)
- Test: `tests/test_porcelain.sh`

**Interfaces:**
- Produces: `_porcelain_issue_line <id> <status> <priority> <assignee> <role> <updated> <blocks> <depends_on> <parent_of> <relates_to> <title>` prints one twelve-column line with an empty first column. Task 4 relies on the first column being empty (the line starts with a tab).

- [ ] **Step 1: Write the failing test**

Append to `tests/test_porcelain.sh`:

```bash
echo "Testing issue lines [R-issue-line] [R-issue-line-shared] [R-plain-stdout]"
fresh_repo lines
"$GI" create "alpha task" >/dev/null 2>&1
"$GI" create "beta task"  >/dev/null 2>&1
a=$("$GI" list --porcelain | awk -F'\t' '$12=="alpha task"{print $2}')
b=$("$GI" list --porcelain | awk -F'\t' '$12=="beta task"{print $2}')
"$GI" update "$b" --role=dev >/dev/null 2>&1
"$GI" dep add "$a" blocks "$b" >/dev/null 2>&1
eq "twelve columns" "12" "$("$GI" list --porcelain | head -1 | awk -F'\t' '{print NF}')"
eq "repo column empty, title last" "|open|medium|conformance||||||alpha task" \
   "$("$GI" list --porcelain | awk -F'\t' -v a="$a" '$2==a' | cut -f1,3-6,8-12 | tr '\t' '|')"
eq "blocks and depends_on columns" "open A  alpha task"$'\n'"blocked  A beta task" \
   "$("$GI" list --porcelain | awk -F'\t' -v a="$a" -v b="$b" '{ gsub(a,"A"); gsub(b,"B"); print $3, $8, $9, $12 }')"
eq "no ANSI in porcelain list" "0" "$("$GI" list --porcelain | grep -c "$(printf '\033')" || true)"
eq "ready: only unblocked, twelve columns" "12 alpha task" "$("$GI" ready --porcelain | awk -F'\t' '{print NF, $12}')"
eq "ready: no header or (none) on stdout" "" "$(cd "$WORK/lines" && "$GI" ready --porcelain --role=nobody)"
eq "queue: filtered by role" "" "$("$GI" queue dev --porcelain)"
eq "topo: order without rank numbers" "12 alpha task"$'\n'"12 beta task" "$("$GI" topo --porcelain | awk -F'\t' '{print NF, $12}')"
eq "topo: empty repo is empty stdout" "0" "$(fresh_repo lines-empty >/dev/null; "$GI" topo --porcelain | wc -c | tr -d ' ')"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/test_porcelain.sh`
Expected: the issue-lines section fails (human-format lines are printed).

- [ ] **Step 3: Add the shared line printer**

Add near `list_issues` (before line 532):

```bash
# One porcelain issue line (R-issue-line). Column 1 (repo) is empty here;
# _gi_aggregate fills it under --all. Single-line fields are normalized
# by the stream (tabs -> space), so a plain printf is safe.
_porcelain_issue_line() {
    printf '\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}"
}
```

Argument order: id, status, priority, assignee, role, updated, blocks, depends_on, parent_of, relates_to, title.

- [ ] **Step 4: Branch in `list_issues`**

Inside the `while` loop in `list_issues`, before the `# Color based on status` comment, add:

```bash
        if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
            _porcelain_issue_line "$id" "$status_val" "$priority" "$assignee" "$role" "$updated" "$blocks" "$depends_on" "$parent_of" "$relates_to" "$title"
            continue
        fi
```

- [ ] **Step 5: Branch in `list_ready_issues`**

The function collects `results` as `<rank> <human line>` and sorts. Keep that structure; make the line porcelain when requested. Replace lines 2553-2556 (the `local line=...` through `results=...`) with:

```bash
        local line
        if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
            line=$(_porcelain_issue_line "$id" "$status_val" "$priority" "$assignee" "$role" "$updated" "$blocks" "$depends_on" "$parent_of" "$relates_to" "$title")
        else
            line="#${id} [${status_val}]  ${title}  (P: ${priority})"
            [[ -n "$role" ]] && line="${line} [${role}]"
            [[ -n "$assignee" ]] && line="${line} -> ${assignee}"
        fi
        results="${results}${rank} ${line}"$'\n'
```

The existing `sort -n | sed 's/^[0-9] //'` strips the rank and the one space after it, leaving the porcelain line intact (it begins with a tab, which `sed` leaves alone). The header and `(none)` lines were gated in Task 1.

- [ ] **Step 6: Branch in `topo_sort_issues`**

The function builds `issue_index` with only title, priority, depends_on. Widen it to carry every column. Replace the index loop (line 2588-2594) with:

```bash
    while IFS=$'\037' read -r id status_val title priority assignee role depends_on updated blocks parent_of relates_to; do
        [[ -z "$id" ]] && continue
        [[ "$status_val" == "closed" ]] && continue
        non_done_ids+=("$id")
        non_done_list="${non_done_list}${id}"$'\n'
        issue_index="${issue_index}${id}"$'\t'"${title}"$'\t'"${priority}"$'\t'"${depends_on}"$'\t'"${status_val}"$'\t'"${assignee}"$'\t'"${role}"$'\t'"${updated}"$'\t'"${blocks}"$'\t'"${parent_of}"$'\t'"${relates_to}"$'\n'
    done <<< "$all_tsv"
```

Change the empty case (line 2596-2599) so porcelain prints nothing:

```bash
    if [[ ${#non_done_ids[@]} -eq 0 ]]; then
        [[ -z "${GIT_ISSUE_PORCELAIN:-}" ]] && echo "No non-closed issues found."
        return 0
    fi
```

Gate the header (line 2627):

```bash
    [[ -z "${GIT_ISSUE_PORCELAIN:-}" ]] && echo -e "${BLUE}Topological order (do first → do last):${NC}"
```

Inside the output loop, after the three `cut` lines (2634-2636), add the porcelain branch:

```bash
        if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
            local status_val assignee role updated blocks parent_of relates_to
            status_val=$(echo "$idx_line" | cut -f5)
            assignee=$(echo "$idx_line" | cut -f6)
            role=$(echo "$idx_line" | cut -f7)
            updated=$(echo "$idx_line" | cut -f8)
            blocks=$(echo "$idx_line" | cut -f9)
            parent_of=$(echo "$idx_line" | cut -f10)
            relates_to=$(echo "$idx_line" | cut -f11)
            _porcelain_issue_line "$id" "$status_val" "$priority" "$assignee" "$role" "$updated" "$blocks" "$depends_on" "$parent_of" "$relates_to" "$title"
            continue
        fi
```

Note: the tsort failure path (`Error: tsort failed`) still goes to stderr with exit 1 in both modes.

- [ ] **Step 7: Run tests and the corpus**

Run: `./tests/test_porcelain.sh && make test-all`
Expected: all pass.

Run: `PATH="$PWD/bin:$PATH" ~/.claude/skills/authoring-rfcs/rfc-run docs/rfc/draft-ndn-porcelain-output-00.md 2>&1 | grep -E '^(PASS|FAIL)'`
Expected: `flag-position`, `version-frozen`, `plain-stdout`, `issue-line`, `issue-line-shared` PASS. Others still FAIL.

- [ ] **Step 8: Commit**

```bash
git add bin/git-issue tests/test_porcelain.sh
git commit -m "feat(porcelain): twelve-column issue lines for list, ready, queue, topo

One printer serves all four commands; ready keeps its priority sort and
topo its tsort order, so line position carries the rank. Covers
R-issue-line, R-issue-line-shared, and the record half of R-plain-stdout."
```

---

### Task 4: The repo column under --all

**Files:**
- Modify: `bin/git-issue:3149-3170` (`_gi_aggregate`)
- Test: `tests/test_porcelain.sh`

**Interfaces:**
- Consumes: the porcelain issue line begins with a tab (empty column 1).

- [ ] **Step 1: Write the failing test**

Append to `tests/test_porcelain.sh`:

```bash
echo "Testing repo column under --all [R-all-column]"
fresh_repo agg-a
"$GI" create "alpha task" >/dev/null 2>&1
"$GI" repo add agg-a "$WORK/agg-a" >/dev/null 2>&1
cd "$WORK"
eq "--all fills column 1" "agg-a|open|alpha task" "$("$GI" list --all --porcelain 2>/dev/null | cut -f1,3,12 | tr '\t' '|')"
eq "--all has no bracket prefix" "0" "$("$GI" list --all --porcelain 2>/dev/null | grep -c '^\[' || true)"
eq "--repo leaves column 1 empty" "|open|alpha task" "$("$GI" --repo agg-a list --porcelain | cut -f1,3,12 | tr '\t' '|')"
eq "ready --all fills column 1" "agg-a" "$("$GI" ready --all --porcelain 2>/dev/null | cut -f1)"
"$GI" repo rm agg-a >/dev/null 2>&1
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/test_porcelain.sh`
Expected: "--all fills column 1" fails with got `[agg-a] |open|alpha task` shaped output.

- [ ] **Step 3: Fill the column in the aggregate loop**

In `_gi_aggregate`, replace the inner `while` that prefixes lines:

```bash
        ( cd "$path" && unset GIT_DIR && GIT_ISSUE_NO_HEADER=1 exec "$_GI_SELF" "${argv[@]}" ) |
        while IFS= read -r line; do
            if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
                printf '%s%s\n' "$name" "$line"
            else
                printf '[%s] %s\n' "$name" "$line"
            fi
        done
```

The child inherits `GIT_ISSUE_PORCELAIN` through the environment (exported in Task 1), emits lines starting with a tab, and the parent prepends the registry name, producing `name<TAB>id...`.

- [ ] **Step 4: Run tests and the corpus**

Run: `./tests/test_porcelain.sh && ./tests/test_registry.sh`
Expected: pass; registry suite unchanged.

Run the corpus PASS/FAIL listing. Expected: `all-column` now PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/git-issue tests/test_porcelain.sh
git commit -m "feat(porcelain): registry name as the first column under --all

The child emits an empty first column; the sweep fills it with the
registry name instead of the human [name] prefix. Covers R-all-column."
```

---

### Task 5: Edge lines for deps and dep list

**Files:**
- Modify: `bin/git-issue` — `dep_list` (2335-2426), `show_deps` (2656-2719)
- Test: `tests/test_porcelain.sh`

**Interfaces:**
- Produces: `_porcelain_edges [<id>]` prints every edge from the edge index as `from<TAB>type<TAB>to`, filtered to `from == <id>` when given.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_porcelain.sh`:

```bash
echo "Testing edge lines [R-edge-line]"
fresh_repo edges
"$GI" create "alpha task" >/dev/null 2>&1
"$GI" create "beta task"  >/dev/null 2>&1
a=$("$GI" list --porcelain | awk -F'\t' '$12=="alpha task"{print $2}')
b=$("$GI" list --porcelain | awk -F'\t' '$12=="beta task"{print $2}')
"$GI" dep add "$a" blocks "$b" >/dev/null 2>&1
norm() { awk -F'\t' -v a="$a" -v b="$b" '{ gsub(a,"A"); gsub(b,"B"); print }'; }
eq "deps: both directions, tab-separated" "A	blocks	B"$'\n'"B	depends_on	A" "$("$GI" deps --porcelain | norm | sort)"
eq "deps <id>: edges from that id" "A	blocks	B" "$("$GI" deps "$a" --porcelain | norm)"
eq "dep list <id>: same shape" "B	depends_on	A" "$("$GI" dep list "$b" --porcelain | norm)"
eq "dep list: all edges" "2" "$("$GI" dep list --porcelain | wc -l | tr -d ' ')"
eq "deps: no marker line leaks" "0" "$("$GI" deps --porcelain | grep -c last_rebuilt || true)"
eq "deps: empty graph is empty stdout" "0" "$(fresh_repo edges-empty >/dev/null; "$GI" deps --porcelain | wc -c | tr -d ' ')"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/test_porcelain.sh`
Expected: edge section fails (human text).

- [ ] **Step 3: Add the edge printer and branch both commands**

Add before `dep_list` (line 2335):

```bash
# Porcelain edge lines (R-edge-line): from<TAB>type<TAB>to, one per edge in
# the edge index, optionally restricted to edges leaving <id>.
_porcelain_edges() {
    local only="${1:-}"
    ensure_edge_index_current
    read_edge_index | while read -r from type to; do
        [[ -z "$from" || "$from" == "last_rebuilt_from:" ]] && continue
        [[ -n "$only" && "$from" != "$only" ]] && continue
        printf '%s\t%s\t%s\n' "$from" "$type" "$to"
    done
}
```

At the top of `dep_list`, after `local target_id="$1"`, add:

```bash
    if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
        if [[ -n "$target_id" ]] && ! issue_exists "$target_id"; then
            echo -e "${RED}Error: Issue #$target_id not found${NC}" >&2
            return 1
        fi
        _porcelain_edges "$target_id"
        return 0
    fi
```

At the top of `show_deps`, after `local target_id="$1"`, add the identical block. `show_deps_dot` (`--dot`) is untouched.

- [ ] **Step 4: Run tests and the corpus**

Run: `./tests/test_porcelain.sh && ./tests/test_deps.sh`
Expected: pass.

Corpus listing: `edge-line` PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/git-issue tests/test_porcelain.sh
git commit -m "feat(porcelain): edge lines from the dependency index

deps and dep list share one printer over the edge index, so a synced
blocks/depends_on pair appears as two lines. Covers R-edge-line."
```

---

### Task 6: Reference lines for scan-commits

**Files:**
- Modify: `bin/git-issue:1552-1600` (`scan_commits_for_issues`)
- Test: `tests/test_porcelain.sh`

- [ ] **Step 1: Write the failing test**

```bash
echo "Testing reference lines [R-ref-line]"
fresh_repo refs
"$GI" create "alpha task" >/dev/null 2>&1
a=$(porcelain_ids)
git commit -q --allow-empty -m "work" -m "Fixes: $a"
git commit -q --allow-empty -m "more" -m "Issue: #$a"
eq "full hash, lowercase key, id" "40 fixes 1"$'\n'"40 issue 1" \
   "$("$GI" scan-commits --porcelain | awk -F'\t' -v a="$a" '{print length($1), $2, ($3==a)}' | sort)"
eq "no banner or tip on stdout" "2" "$("$GI" scan-commits --porcelain | wc -l | tr -d ' ')"
eq "no references is empty stdout" "0" "$(fresh_repo refs-empty >/dev/null; "$GI" scan-commits --porcelain | wc -c | tr -d ' ')"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/test_porcelain.sh`
Expected: reference section fails.

- [ ] **Step 3: Branch the scanner**

In `scan_commits_for_issues`, gate the banner (lines 1556-1557):

```bash
    if [[ -z "${GIT_ISSUE_PORCELAIN:-}" ]]; then
        echo -e "${BLUE}🔍 Scanning commits for issue references...${NC}"
        echo ""
    fi
```

Replace the summary-format inner loop (lines 1586-1591) with:

```bash
                echo "$trailers" | while IFS= read -r trailer; do
                    local issue_id trailer_type
                    issue_id=$(echo "$trailer" | grep -oE '#?[a-f0-9]{7}' | head -1 | sed 's/^#//')
                    trailer_type=$(echo "$trailer" | cut -d':' -f1)
                    if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
                        printf '%s\t%s\t%s\n' "$commit_hash" "$(echo "$trailer_type" | tr 'A-Z' 'a-z')" "$issue_id"
                    else
                        echo "${commit_hash:0:7} $trailer_type: #$issue_id"
                    fi
                done
```

The `#` becomes optional in the id match so a hand-written `Fixes: abc1234` trailer is found; the human line still prints `#` itself. Gate the trailing "No issue references" block (1597-1598):

```bash
    if [[ $issue_refs_found -eq 0 && -z "${GIT_ISSUE_PORCELAIN:-}" ]]; then
```

- [ ] **Step 4: Run tests and the corpus**

Run: `./tests/test_porcelain.sh && ./tests/integration_tests.sh`
Expected: pass. Corpus listing: `ref-line` PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/git-issue tests/test_porcelain.sh
git commit -m "feat(porcelain): reference lines from commit trailers

Full hash, lowercase trailer key, issue id. The id match now tolerates a
missing #, which the human format never needed. Covers R-ref-line."
```

---

### Task 7: Key-value lines for setup-sync status; repo list accepts the flag

**Files:**
- Modify: `bin/git-issue:1134-1178` (`setup_sync_status`), `bin/git-issue:3194-3201` (`repo` routing in `_gi_dispatch`)
- Test: `tests/test_porcelain.sh`

- [ ] **Step 1: Write the failing test**

```bash
echo "Testing key-value lines [R-kv-line]"
fresh_repo kv
"$GI" create "alpha task" >/dev/null 2>&1
eq "sync status keys in order" \
   "enabled false"$'\n'"post-merge-hook false"$'\n'"pre-push-hook false"$'\n'"auto-fetch false"$'\n'"issue-notes 1" \
   "$("$GI" setup-sync status --porcelain | tr '\t' ' ')"
"$GI" setup-sync enable >/dev/null 2>&1 || true
eq "sync status reflects enable" "true" "$("$GI" setup-sync status --porcelain | awk -F'\t' '$1=="enabled"{print $2}')"
"$GI" repo add kv "$WORK/kv" >/dev/null 2>&1
eq "repo list unchanged under --porcelain" "$("$GI" repo list)" "$("$GI" repo list --porcelain)"
"$GI" repo rm kv >/dev/null 2>&1
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/test_porcelain.sh`
Expected: kv section fails; `repo list --porcelain` may error because `repo` routing rejects unknown flags.

- [ ] **Step 3: Branch `setup_sync_status`**

Restructure the function so the facts are computed first and printed second. Replace the whole function body with:

```bash
setup_sync_status() {
    local git_dir=$(git rev-parse --git-dir)
    local hooks_dir="$git_dir/hooks"

    local sync_enabled=$(git config --get git-issue.sync.enabled 2>/dev/null || echo "false")
    local post_merge=false pre_push=false auto_fetch=false
    [[ -f "$hooks_dir/post-merge" && -x "$hooks_dir/post-merge" ]] && post_merge=true
    [[ -f "$hooks_dir/pre-push"   && -x "$hooks_dir/pre-push"   ]] && pre_push=true
    if git config --get-regexp "remote\..*\.fetch" 2>/dev/null | grep -q "refs/notes"; then
        auto_fetch=true
    fi
    local note_count=$(git for-each-ref --format="%(refname)" 'refs/notes/issue-*' 2>/dev/null | wc -l | tr -d ' ')

    if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
        printf 'enabled\t%s\n'         "$sync_enabled"
        printf 'post-merge-hook\t%s\n' "$post_merge"
        printf 'pre-push-hook\t%s\n'   "$pre_push"
        printf 'auto-fetch\t%s\n'      "$auto_fetch"
        printf 'issue-notes\t%s\n'     "$note_count"
        return 0
    fi

    local mark_pm="❌" mark_pp="❌" mark_af="❌"
    [[ "$post_merge" == true ]] && mark_pm="✅"
    [[ "$pre_push"   == true ]] && mark_pp="✅"
    [[ "$auto_fetch" == true ]] && mark_af="✅"

    echo -e "${BLUE}Git Notes Sync Status${NC}"
    echo "===================="
    echo "Config enabled: $sync_enabled"
    echo "Post-merge hook: $mark_pm"
    echo "Pre-push hook: $mark_pp"
    echo "Notes auto-fetch: $mark_af"
    echo "Issue notes: $note_count"
    echo ""
    if [[ "$sync_enabled" == "true" && "$post_merge" == true && "$pre_push" == true ]]; then
        echo -e "${GREEN}✓ Automatic sync is fully configured and enabled${NC}"
    else
        echo -e "${YELLOW}⚠️  Automatic sync is not fully configured${NC}"
        echo "Run: git issue setup-sync enable"
    fi
}
```

Check `tests/test_hooks_sync.sh` for any assertion on the exact `Issue notes:` spacing; the original printed `Issue notes: $note_count` where `wc -l` on macOS pads with spaces. The `tr -d ' '` above removes that padding, so if a hooks test matches the padded form, update that test to the unpadded value (the padding was never intentional).

- [ ] **Step 4: Accept the flag on `repo` commands**

`_gi_dispatch` already peeled `--porcelain` out of `rest` in Task 1, so `repo list --porcelain` reaches `gi_repo_command` with `list` alone. Verify with the test; no code change should be needed. If `repo` routing rejects it, the peel loop is wrong and must be fixed there, not in `gi_repo_command`.

- [ ] **Step 5: Run tests and the corpus**

Run: `./tests/test_porcelain.sh && ./tests/test_hooks_sync.sh && ./tests/test_registry.sh`
Expected: pass. Corpus listing: `kv-line` PASS.

- [ ] **Step 6: Commit**

```bash
git add bin/git-issue tests/test_porcelain.sh
git commit -m "feat(porcelain): key-value lines for setup-sync status

Facts are computed once and rendered either as tab-separated pairs or
the existing human report. repo list already emits its contractual
format and now simply accepts the flag. Covers R-kv-line."
```

---

### Task 8: Readers that accept both note formats

**Files:**
- Modify: `share/git-issue/awk/front_matter.awk`
- Create: `share/git-issue/awk/comments.awk`
- Modify: `bin/git-issue` — `KNOWN_HEADER_FIELDS` (352), `parse_body` (451-454), `parse_comments` (457-460), `get_field_value` (473-479), `show_issue` (564-638), `_gi_check_awk_files` (the awk file list near line 3500)
- Test: `tests/test_porcelain.sh`

**Interfaces:**
- Produces: `note_format <data>` prints `1` or `2`.
- Produces: `get_field_value` joins continuation lines with a space for single-line fields (unchanged behavior for them) and `get_field_raw <front_matter> <field>` returns the value with embedded newlines for `description`.
- Produces: `get_description <data>` returns the description for either format, newlines preserved.
- Produces: `parse_comment_records <data>` prints comments in canonical folded form: each comment's first line `[ts] author: text`, continuation lines prefixed by one space, for either input format.
- `parse_front_matter` output now includes continuation lines verbatim after their header line.

- [ ] **Step 1: Write the failing test**

```bash
echo "Testing readers on both formats [R-legacy-read]"
fresh_repo readers
# A hand-built format-1 note (no marker, body region, raw multi-line comment).
blob=$(printf 'id: abc1234\ntitle: legacy\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\n\nold body\nsecond body line\n\n## Comments\n[2026-01-01T00:00:00Z] conformance: one\ntwo\n[2026-01-02T00:00:00Z] conformance: three\n' | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
git update-ref refs/notes/issue-abc1234 "$(git commit-tree "$tree" -m legacy </dev/null)"
# A hand-built format-2 note.
blob=$(printf 'id: def5678\nv: 2\ntitle: modern\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\ndescription: first\n ## Comments\n third\n\n## Comments\n[2026-01-01T00:00:00Z] conformance: one\n two\n' | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
git update-ref refs/notes/issue-def5678 "$(git commit-tree "$tree" -m modern </dev/null)"
src() { bash -c "source '$GI' 2>/dev/null; $*"; }
eq "format 1 detected" "1" "$(src 'note_format "$(read_issue_data abc1234)"')"
eq "format 2 detected" "2" "$(src 'note_format "$(read_issue_data def5678)"')"
eq "format 1 description from body" "old body"$'\n'"second body line" "$(src 'get_description "$(read_issue_data abc1234)"')"
eq "format 2 description from header, continuation unfolded" "first"$'\n'"## Comments"$'\n'"third" "$(src 'get_description "$(read_issue_data def5678)"')"
eq "format 1 comments folded canonically" "[2026-01-01T00:00:00Z] conformance: one"$'\n'" two"$'\n'"[2026-01-02T00:00:00Z] conformance: three" "$(src 'parse_comment_records "$(read_issue_data abc1234)"')"
eq "format 2 comments pass through" "[2026-01-01T00:00:00Z] conformance: one"$'\n'" two" "$(src 'parse_comment_records "$(read_issue_data def5678)"')"
eq "human show unfolds comments" "one"$'\n'"two" "$("$GI" show abc1234 2>/dev/null | sed -n '/^Comments:/,$p' | tail -2 | sed -E 's/^\[[^]]+\] conformance: //')"
eq "human show of format 2 prints description" "1" "$("$GI" show def5678 2>/dev/null | grep -c '^first$')"
eq "stream reads format 2 title" "modern" "$("$GI" list --porcelain | awk -F'\t' '$2=="def5678"{print $12}')"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/test_porcelain.sh`
Expected: "format 1 detected" fails with `note_format: command not found`.

- [ ] **Step 3: Continuation-aware front matter**

Edit `share/git-issue/awk/front_matter.awk`. The top-block loop (lines 11-21) collects `lines[i] ~ /^[a-z_]+:/`; make it also carry continuation lines with the header they extend. Replace that loop with:

```awk
    # Collect top headers (before first blank line); a line beginning with
    # one space continues the previous header's value (format 2).
    top_count = 0
    for (i = 1; i <= n; i++) {
        if (lines[i] == "") break
        if (lines[i] ~ /^[a-z_]+:/) {
            top_count++
            top_headers[top_count] = lines[i]
            split(lines[i], kv, ": *")
            top_keys[top_count] = kv[1]
        } else if (lines[i] ~ /^ / && top_count > 0) {
            top_headers[top_count] = top_headers[top_count] "\n" lines[i]
        }
    }
```

The trailing-header scan is unchanged: trailing headers exist only in format-1 notes, which have no continuation lines. Printing (`print top_headers[i]`) now emits the header line followed by its continuation lines, each still starting with a space.

- [ ] **Step 4: Add `description` to the known fields and the format probe**

Line 352: append `|description` to `KNOWN_HEADER_FIELDS`. (`v` is deliberately not added; it is the marker, not a field.)

Add after `read_issue_data`:

```bash
# Note format: 2 when line 2 is the marker "v: 2", else 1 (R-format-marker).
note_format() {
    local data="$1"
    if [[ "$(printf '%s\n' "$data" | sed -n '2p')" == "v: 2" ]]; then
        echo 2
    else
        echo 1
    fi
}
```

- [ ] **Step 5: Field accessors that understand continuation**

Replace `get_field_value` (473-479) with:

```bash
# Raw value of a header field with continuation lines unfolded (joined by
# newline, leading space stripped). Empty if absent.
get_field_raw() {
    local front_matter="$1"
    local field="$2"
    printf '%s\n' "$front_matter" | awk -v f="$field" '
        $0 ~ "^" f ":" { v = $0; sub("^" f ": ?", "", v); found = 1; next }
        found && /^ / { v = v "\n" substr($0, 2); next }
        found { exit }
        END { if (found) printf "%s", v }'
}

# Single-line view of a field: newlines become spaces (unchanged behavior
# for every field but description, which callers read with get_field_raw).
get_field_value() {
    local value
    value=$(get_field_raw "$1" "$2" | tr '\n' ' ')
    trim_ws "$value"
}
```

Note `get_field_raw` returns the last-wins semantics only for the first match; `parse_front_matter` already resolves trailing-over-top precedence before this point, so the first match is the resolved one.

- [ ] **Step 6: Description and comments accessors**

Replace `parse_comments` (457-460) with the pair below, and add `get_description` after `parse_body`:

```bash
# Description for either note format, newlines preserved.
get_description() {
    local data="$1"
    if [[ "$(note_format "$data")" == "2" ]]; then
        get_field_raw "$(parse_front_matter "$data")" "description"
    else
        parse_body "$data"
    fi
}

# Comments as canonical folded records (R-legacy-read, R-store-continuation):
# first line "[ts] author: text", continuation lines prefixed by one space.
parse_comment_records() {
    local data="$1"
    printf '%s\n' "$data" | awk -f "$(require_awk_file comments.awk)" -v FORMAT="$(note_format "$data")"
}

# Comments for human display: records with continuation unfolded.
parse_comments() {
    parse_comment_records "$1" | sed 's/^ //'
}
```

Create `share/git-issue/awk/comments.awk`:

```awk
# Required: -v FORMAT=1|2. Input: whole note on stdin.
# Output: comments after "## Comments" as folded records: a line beginning
# with "[" starts a record; in format 2 a line beginning with one space is a
# continuation and is passed through; in format 1 any other non-empty line
# is a legacy continuation and is emitted with one leading space added.
/^## Comments$/ { p = 1; next }
!p { next }
/^\[/ { print; started = 1; next }
started && /^ / { print; next }
started && FORMAT == 1 && $0 != "" { print " " $0; next }
```

Add `comments.awk` to the list checked by `_gi_check_awk_files` (near line 3500) and to the awk directory install lists in `install-git-issue.sh`, `homebrew-setup.sh`, `Formula/git-issue.rb`, and `git-issue-local.rb` wherever `extract_issues.awk` is named (grep for it; `tests/test_install_layout.sh` will catch a miss).

- [ ] **Step 7: Make `show_issue` use the accessors**

In `show_issue`, replace `local body=$(parse_body "$data")` and `local description="$body"` with `local description=$(get_description "$data")`. `parse_comments` keeps its name and now returns unfolded text, so the comments display block (632-637) is unchanged.

Also make `parse_body` return nothing for format 2, so any remaining caller cannot misread a format-2 note:

```bash
parse_body() {
    local data="$1"
    [[ "$(note_format "$data")" == "2" ]] && return 0
    echo "$data" | awk -f "$(require_awk_file body.awk)" -v FIELDS="$KNOWN_HEADER_FIELDS"
}
```

- [ ] **Step 8: Run tests**

Run: `./tests/test_porcelain.sh && make test-all`
Expected: readers section passes; every existing suite passes (all existing notes are format 1 and read exactly as before).

- [ ] **Step 9: Commit**

```bash
git add share/git-issue/awk/front_matter.awk share/git-issue/awk/comments.awk bin/git-issue tests/test_porcelain.sh install-git-issue.sh homebrew-setup.sh Formula/git-issue.rb git-issue-local.rb
git commit -m "feat(notes): read format-2 notes alongside format 1

A v: 2 marker on line 2 selects the new layout: description as a header
with leading-space continuation, comments continuation-encoded. Without
the marker the body region is the description and a comments-section
line not starting with [ continues the previous comment. Human output
is unchanged for every existing note. Covers R-legacy-read."
```

---

### Task 9: Writers that emit format 2 and normalize single-line fields

**Files:**
- Create: `share/git-issue/awk/upgrade_note.awk`
- Modify: `bin/git-issue` — `write_issue_data` (374-402), `create_issue` (482-529), the legacy `add` arm in `main` (3255-3270), `update_issue` description branch (691-714), `add_comment` (1434-1463), `update_issue_with_flags` field setters (767-770, 803, 893-900)
- Test: `tests/test_porcelain.sh`

**Interfaces:**
- Produces: `gi_fold <text>` prints text with every line after the first prefixed by one space.
- Produces: `gi_single_line <text>` replaces tab, CR, LF with one space.
- Produces: `write_issue_data` upgrades any format-1 text to format 2 before writing.

- [ ] **Step 1: Write the failing test**

```bash
echo "Testing format-2 writes [R-format-marker] [R-store-continuation] [R-field-normalize]"
fresh_repo writes
"$GI" create "alpha task" --description="$(printf 'first line\n## Comments')" >/dev/null 2>&1
a=$(porcelain_ids)
note() { git cat-file -p "refs/notes/issue-$1:issue"; }
eq "marker on line 2" "v: 2" "$(note "$a" | sed -n 2p)"
eq "one id line" "1" "$(note "$a" | grep -c '^id:')"
eq "description folded in header block" "description: first line"$'\n'" ## Comments" "$(note "$a" | grep -A1 '^description:')"
eq "no body region" "0" "$(note "$a" | awk 'f && !/^## Comments$/ && $0!="" {c++} /^$/ {f=1} /^## Comments$/ {exit} END {print c+0}')"
"$GI" comment "$a" "$(printf 'one\ntwo')" >/dev/null 2>&1
eq "comment folded" "## Comments"$'\n'"[T] conformance: one"$'\n'" two" "$(note "$a" | sed -n '/^## Comments$/,$p' | sed -E 's/^\[[^]]+\]/[T]/')"
"$GI" update "$a" --description="$(printf 'changed\nagain')" >/dev/null 2>&1
eq "description update folded" "description: changed"$'\n'" again" "$(note "$a" | grep -A1 '^description:')"
eq "description update keeps comments" "1" "$(note "$a" | grep -c '^ two$')"
# Upgrade on write of a format-1 note
blob=$(printf 'id: abc1234\ntitle: legacy\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\n\nold body\n\n## Comments\n[2026-01-01T00:00:00Z] conformance: one\ntwo\n' | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
git update-ref refs/notes/issue-abc1234 "$(git commit-tree "$tree" -m legacy </dev/null)"
"$GI" update abc1234 --priority=high >/dev/null 2>&1
eq "upgraded note has marker" "v: 2" "$(note abc1234 | sed -n 2p)"
eq "upgraded note moved body to header" "1" "$(note abc1234 | grep -c '^description: old body$')"
eq "upgraded note folded legacy comment" "1" "$(note abc1234 | grep -c '^ two$')"
eq "upgraded note kept the update" "high" "$("$GI" list --porcelain | awk -F'\t' '$2=="abc1234"{print $4}')"
# Single-line normalization on write
"$GI" create "$(printf 'tab\there')" >/dev/null 2>&1
eq "tab in title stored as space" "1" "$(note "$(porcelain_ids | tail -1)" | grep -c '^title: tab here$')"
"$GI" update "$a" --assignee="$(printf 'two\nlines')" >/dev/null 2>&1
eq "newline in assignee stored as space" "two lines" "$("$GI" list --porcelain | awk -F'\t' -v a="$a" '$2==a{print $5}')"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/test_porcelain.sh`
Expected: "marker on line 2" fails with got `title: alpha task`.

- [ ] **Step 3: Add the fold and normalize helpers**

Add after `trim_ws` (around line 470):

```bash
# Continuation-encode a multi-line value: every line after the first gets
# one leading space (R-store-continuation).
gi_fold() {
    printf '%s\n' "$1" | sed '2,$s/^/ /'
}

# Collapse tab, CR, LF to one space (R-field-normalize).
gi_single_line() {
    printf '%s' "$1" | tr '\t\r\n' '   '
}
```

- [ ] **Step 4: The upgrade wrapper**

Create `share/git-issue/awk/upgrade_note.awk`:

```awk
# Input: a whole note in format 1 or 2 on stdin. Output: the same note in
# format 2: "id:" first, "v: 2" second, remaining headers (top and trailing,
# trailing wins, continuation lines kept), description as a header with
# continuation, blank line, "## Comments" and folded comment records
# (format-1 legacy continuation lines gain one leading space).
BEGIN { n = 0 }
{ lines[++n] = $0 }
END {
    # Split into regions.
    ca = n + 1
    for (i = 1; i <= n; i++) if (lines[i] == "## Comments") { ca = i; break }
    fb = ca
    for (i = 1; i < ca; i++) if (lines[i] == "") { fb = i; break }
    fmt = (n >= 2 && lines[2] == "v: 2") ? 2 : 1

    # Top headers, in order, keyed for override; continuation lines attach.
    hk = 0
    for (i = 1; i < fb; i++) {
        if (lines[i] ~ /^[a-z_]+:/) {
            key = lines[i]; sub(/:.*/, "", key)
            if (key == "v") continue
            if (!(key in pos)) { pos[key] = ++hk; order[hk] = key }
            val[key] = lines[i]
        } else if (lines[i] ~ /^ / && hk > 0) {
            val[order[hk]] = val[order[hk]] "\n" lines[i]
        }
    }
    # Format 1: body region and trailing headers.
    body = ""
    if (fmt == 1) {
        e = ca - 1
        while (e > fb && lines[e] == "") e--
        s = e
        while (s > fb && lines[s] ~ /^[a-z_]+:/) s--
        # lines s+1..e are trailing headers (override), fb+1..s body
        for (i = s + 1; i <= e; i++) {
            key = lines[i]; sub(/:.*/, "", key)
            if (key == "id") continue
            if (!(key in pos)) { pos[key] = ++hk; order[hk] = key }
            val[key] = lines[i]
        }
        be = s
        while (be > fb && lines[be] == "") be--
        for (i = fb + 1; i <= be; i++) body = (i == fb + 1) ? lines[i] : body "\n" lines[i]
    }
    # Emit headers: id, marker, the rest in order, description last.
    print val["id"]
    print "v: 2"
    for (i = 1; i <= hk; i++) {
        key = order[i]
        if (key == "id" || key == "description") continue
        print val[key]
    }
    if ("description" in val) {
        print val["description"]
    } else if (body != "") {
        m = split(body, bl, "\n")
        printf "description: %s\n", bl[1]
        for (i = 2; i <= m; i++) print " " bl[i]
    }
    # Comments.
    if (ca <= n) {
        print ""
        print "## Comments"
        started = 0
        for (i = ca + 1; i <= n; i++) {
            if (lines[i] ~ /^\[/) { print lines[i]; started = 1 }
            else if (started && lines[i] ~ /^ /) print lines[i]
            else if (started && fmt == 1 && lines[i] != "") print " " lines[i]
        }
    }
}
```

In `write_issue_data` (line 374), upgrade before hashing. Replace:

```bash
    local blob_hash
    blob_hash=$(echo "$data" | git hash-object -w --stdin)
```

with:

```bash
    local blob_hash
    data=$(printf '%s\n' "$data" | awk -f "$(require_awk_file upgrade_note.awk)")
    blob_hash=$(printf '%s\n' "$data" | git hash-object -w --stdin)
```

Add `upgrade_note.awk` to `_gi_check_awk_files` and the installer lists as in Task 8.

- [ ] **Step 5: Write paths produce folded values and normalized fields**

`create_issue` (482-529): normalize the title and fold the description. Replace the `issue_data` construction:

```bash
    title=$(gi_single_line "$title")
    local issue_data="id: $id
v: 2
title: $title
status: open
priority: medium
created: $timestamp
updated: $timestamp
author: $author
assignee: $author
hash_source: content"
    if [[ -n "$description" ]]; then
        issue_data="$issue_data
description: $(gi_fold "$description")"
    fi
```

Note `gi_fold` output begins with the first line unprefixed, so `description: ` + fold gives `description: first` then ` second`.

Legacy `add` arm in `main` (3255-3270): apply the same two changes (`v: 2` after `id:`, title through `gi_single_line`).

`update_issue` description branch (691-714): after recomputing `headers` and `comments`, build the note as headers with the old `description:` header (and its continuation lines) removed, then the new folded description, then comments:

```bash
        local headers_wo_desc
        headers_wo_desc=$(printf '%s\n' "$front_matter" | awk '
            /^description:/ { skip = 1; next }
            skip && /^ / { next }
            { skip = 0; print }')
        updated_data="$headers_wo_desc
description: $(gi_fold "$value")"
        if [[ -n "$comments" ]]; then
            updated_data="$updated_data

## Comments
$comments"
        fi
```

Here `comments` must come from `parse_comment_records "$data"` (folded form), not the old `parse_comments`, so that it round-trips. Update the local assignment in that branch accordingly.

`add_comment` (1434-1463): fold the comment text. Replace both `[$timestamp] $author: $comment` interpolations with `[$timestamp] $author: $(gi_fold "$comment")`.

`update_issue_with_flags` setters for `--assignee`, `--role`, `--status`, `--priority` (767-770, 803, 893-900) and the non-description branch of `update_issue`: pass the value through `gi_single_line` before the awk rewrite. Find each `update_issue "$id" "<field>" "$value"` call for a single-line field and wrap: `update_issue "$id" assignee "$(gi_single_line "$value")"`. Equivalently, apply it once at the top of `update_issue` for every field except `description`:

```bash
    if [[ "$field" != "description" ]]; then
        value=$(gi_single_line "$value")
    fi
```

Prefer this single site.

- [ ] **Step 6: Run tests, all suites, and the corpus**

Run: `./tests/test_porcelain.sh && make test-all`
Expected: pass. Existing suites now write format-2 notes and read them through Task 8's readers; any assertion that inspected raw note text for a body region will fail and must be updated to the header form (check `tests/test_descriptions.sh` and `tests/test_content_safety.sh` first; update the expected text, not the behavior).

Corpus listing: `format-marker`, `store-continuation`, `legacy-read`, `field-normalize` PASS.

- [ ] **Step 7: Commit**

```bash
git add share/git-issue/awk/upgrade_note.awk bin/git-issue tests/ install-git-issue.sh homebrew-setup.sh Formula/git-issue.rb git-issue-local.rb
git commit -m "feat(notes): write format 2 and upgrade format-1 notes in place

write_issue_data now runs every note through upgrade_note.awk, so the
v: 2 marker, header-block description and folded comments come from one
place and a format-1 note is upgraded the first time it is written.
Write paths fold multi-line values and normalize tab, CR and LF out of
single-line fields. Covers R-format-marker, R-store-continuation and
R-field-normalize."
```

---

### Task 10: show --porcelain

**Files:**
- Modify: `bin/git-issue:564-638` (`show_issue`)
- Test: `tests/test_porcelain.sh`

- [ ] **Step 1: Write the failing test**

```bash
echo "Testing show block [R-show-block]"
fresh_repo showp
"$GI" create "alpha task" --description="$(printf 'first line\nsecond line')" >/dev/null 2>&1
a=$(porcelain_ids)
"$GI" comment "$a" "$(printf 'one\ntwo')" >/dev/null 2>&1
"$GI" update "$a" --role=dev >/dev/null 2>&1
eq "canonical block" \
   "title: alpha task"$'\n'"status: open"$'\n'"priority: medium"$'\n'"author: conformance"$'\n'"assignee: conformance"$'\n'"role: dev"$'\n'"hash_source: content"$'\n'"description: first line"$'\n'" second line"$'\n'"comment: [T] conformance: one"$'\n'" two" \
   "$("$GI" show "$a" --porcelain | grep -vE '^(id|created|updated): ' | sed -E 's/^(comment: )\[[^]]+\]/\1[T]/')"
eq "id first" "id: $a" "$("$GI" show "$a" --porcelain | head -1)"
eq "marker not emitted" "0" "$("$GI" show "$a" --porcelain | grep -c '^v:' || true)"
eq "no blank lines" "0" "$("$GI" show "$a" --porcelain | grep -c '^$' || true)"
eq "unknown id is an error" "1" "$("$GI" show nosuch --porcelain >/dev/null 2>&1; echo $?)"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/test_porcelain.sh`
Expected: "canonical block" fails (human layout).

- [ ] **Step 3: Add the porcelain branch**

In `show_issue`, after the `issue_exists` check and `local data=$(read_issue_data "$id")`, insert:

```bash
    if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
        _porcelain_show "$data"
        return 0
    fi
```

Add before `show_issue`:

```bash
# Canonical header order for show --porcelain (R-show-block); matches the
# hkey alternatives in the RFC grammar. description and comment follow.
_PORCELAIN_SHOW_FIELDS="id title status priority created updated author assignee role labels hash_source github_id github_url jira_id jira_url gitlab_id gitlab_url blocks depends_on parent_of relates_to issue_type external_ref waits_for"

_porcelain_show() {
    local data="$1"
    local front_matter
    front_matter=$(parse_front_matter "$data")
    local f v
    for f in $_PORCELAIN_SHOW_FIELDS; do
        if [[ "$f" == "status" ]]; then
            v=$(get_field_value "$front_matter" status)
            [[ -z "$v" ]] && v=$(get_field_value "$front_matter" state)
        else
            v=$(get_field_value "$front_matter" "$f")
        fi
        [[ -n "$v" ]] && printf '%s: %s\n' "$f" "$v"
    done
    local description
    description=$(get_description "$data")
    if [[ -n "$description" ]]; then
        printf 'description: %s\n' "$(gi_fold "$description")"
    fi
    parse_comment_records "$data" | sed -E '/^\[/s/^/comment: /'
}
```

`gi_fold` yields the first line then space-prefixed lines, so `description: ` + fold is the required form. Comment records are already folded; the `sed` prefixes only record-start lines.

- [ ] **Step 4: Run tests and the corpus**

Run: `./tests/test_porcelain.sh && make test-all`
Expected: pass.

Run: `PATH="$PWD/bin:$PATH" ~/.claude/skills/authoring-rfcs/rfc-run docs/rfc/draft-ndn-porcelain-output-00.md`
Expected: 14 PASS, 0 FAIL. (With `--expect` it now reports a mismatch against the red declaration; that is Task 11.)

- [ ] **Step 5: Commit**

```bash
git add bin/git-issue tests/test_porcelain.sh
git commit -m "feat(porcelain): show as one continuation-encoded header block

Fields in the grammar's canonical order, then description, then one
comment record per comment; multi-line values fold with a leading space.
Covers R-show-block. All fourteen RFC transcripts now replay."
```

---

### Task 11: Flip the corpus, document, and gate

**Files:**
- Modify: `docs/rfc/draft-ndn-porcelain-output-00.md` (masthead `Corpus:` and Changelog)
- Modify: `README.md`, `man/man1/git-issue.1`
- Modify: `AGENTS.md` (one line pointing agents at `--porcelain`)

- [ ] **Step 1: Flip the declaration**

Change `**Corpus:** red (spec-first — evidence is the acceptance criteria)` to `**Corpus:** green`. Append to the Changelog:

```markdown
- <today, via date>: implemented in `bin/git-issue`; corpus flipped red -> green
  (14/14 transcripts replay and the [R-field-normalize] table matches).
  Findings recorded during implementation: <list anything the executor had
  to decide that the spec did not say, e.g. scan-commits accepting a trailer
  id without '#'>.
```

Use `date +%Y-%m-%d` for the date.

- [ ] **Step 2: Run the full gate**

Run: `PATH="$PWD/bin:$PATH" ~/.claude/skills/authoring-rfcs/rfc-check docs/rfc`
Expected:

```
document | lint | corpus | declared | digest
draft-ndn-multi-project-registry-02 | ok | green | green | ok
draft-ndn-porcelain-output-00 | ok | green | green | ok
rfc-check: PASS (docs/rfc)
```

Run: `make test-all`
Expected: every suite passes.

Run three consecutive corpus replays to confirm determinism: `for i in 1 2 3; do PATH="$PWD/bin:$PATH" ~/.claude/skills/authoring-rfcs/rfc-run docs/rfc/draft-ndn-porcelain-output-00.md >/dev/null 2>&1 && echo ok || echo FLAKY; done`
Expected: `ok` three times.

- [ ] **Step 3: Document**

`README.md`: add a "Machine-readable output" subsection after the registry section, with the column list, the `show` block shape, one example of each, and a sentence that notes now carry `v: 2` and a header-block description. `man/man1/git-issue.1`: add `--porcelain[=v1]` under global options and a `PORCELAIN FORMAT` section with the same content in roff. `AGENTS.md`: under "Project Overview", add "Read state with `--porcelain` (tab-separated, stable; see docs/rfc/draft-ndn-porcelain-output-00.md), never by parsing the colored output."

- [ ] **Step 4: Commit**

```bash
git add docs/rfc/draft-ndn-porcelain-output-00.md README.md man/man1/git-issue.1 AGENTS.md
git commit -m "rfc: porcelain output corpus is green

All fourteen transcripts replay and the normalization table matches.
Documents --porcelain and the format-2 note layout in the README, the
man page, and the agent instructions."
```

- [ ] **Step 5: Ledger and handoff**

Run:

```bash
ledger set porcelain-output status=done --as git-issue-agent \
  --evidence "commit:$(git rev-parse --short HEAD)" \
  --evidence "run:rfc-check docs/rfc PASS, 14/14 blocks green" \
  --evidence "run:tests/test_porcelain.sh PASS" \
  -m "draft-ndn-porcelain-output-00 implemented on feat/porcelain-output; corpus green; not yet merged."
```

Then stop. Merging to main is a separate decision (see memory: feature branches merge with `--no-ff` once proven), and the commit that records it goes through the two-key read.

---

## Self-review notes

**Spec coverage.** R-flag-position, R-version-frozen (Task 1); R-plain-stdout (Tasks 1, 3, and each command's empty-case gating in 5, 6); R-issue-line, R-issue-line-shared (Task 3); R-all-column (Task 4); R-edge-line (Task 5); R-ref-line (Task 6); R-kv-line (Task 7); R-legacy-read (Task 8); R-format-marker, R-store-continuation, R-field-normalize (Task 9); R-show-block (Task 10). Fourteen IDs, fourteen covered. Check: `grep -o '\[R-[a-z-]*\]' docs/rfc/draft-ndn-porcelain-output-00.md | sort -u` and the same over this plan yield the same set.

**Ordering.** Readers (Task 8) land before writers (Task 9) so that no commit leaves the tool unable to read what it writes. Tasks 3 through 7 depend only on Tasks 1 and 2 and could be reordered among themselves.

**Known risks.**
- `upgrade_note.awk` is the densest piece. Its body-extraction logic mirrors `body.awk`; if the two disagree on a legacy note, the test in Task 9 ("upgraded note moved body to header") catches it. If it proves too fiddly, an acceptable fallback is to call the existing `parse_front_matter`, `parse_body`, and `parse_comment_records` from bash inside `write_issue_data` and assemble the format-2 text there, at the cost of three more awk invocations per write.
- The `setup-sync` human output loses `wc -l` padding; `tests/test_hooks_sync.sh` may need its expected string trimmed.
- Existing tests that inspect raw note blobs for a body region will need their expectations updated in Task 9; behavior, not tests, is the oracle for human output, but raw storage is legitimately changing.
