# Multi-User Sync and Issue History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** No edit to an issue is lost when several people or agents write the same issues, locally or through a shared remote, and every issue's history can be read with `git issue log`.

**Architecture:**
- Writes become compare-and-swap through one retrying edit helper.
- A fetch lands in a tracking namespace, and `git issue sync` integrates each issue: fast-forward, or a three-way document merge done by one new awk program.
- `pre-push` pushes without force and fails on divergence.
- The dependency index becomes local, derived data.
- `log` and the commit messages share one document diff.

**Tech Stack:** bash 3.2-compatible (no associative arrays: the codebase has none), git plumbing, awk helpers in `share/git-issue/awk/`, bash test scripts in `tests/`.

**Spec:** `docs/plans/2026-10-11-multi-user-sync-design.md`

## Global Constraints

- Per-issue refs `refs/notes/issue-<id>` stay; the format-2 document format does not change.
- Tracking refs: `refs/issue-remotes/<remote>/issue-<id>`; fetch refspec `+refs/notes/issue-*:refs/issue-remotes/<remote>/issue-*`.
- Dependency index ref: `refs/issue-local/dep-graph`; never pushed or fetched.
- Write conflict status: `write_issue_data` returns 75 on an old-value mismatch; `gi_edit` retries up to 5 times.
- Merge commit message: `Merge issue <id> from <remote>`; parents in order local, remote.
- `updated:` is never a conflict: later timestamp wins.
- List fields: `labels blocks depends_on parent_of relates_to waits_for`; merged as `(base ∩ local ∩ remote) ∪ (local − base) ∪ (remote − base)`, order local then remote's additions.
- `pre-push` refspecs carry no `+`, use `--atomic`, and exit 1 on rejection with the hint `run \`git issue sync <remote>\` first`; `GIT_ISSUE_PUSH_SOFT=1` restores warn-and-exit-0.
- `list`, `show` and `pre-push` stay O(changed refs) in git calls; no `ls-remote` in `pre-push`.
- Every new command gets a usage line in `show_help` and an entry in `docs/reference.md`, in the task that adds it.
- Commit messages: conventional prefix as in `git log` (`feat(sync):`, `fix(hooks):`, `test:`); no attribution lines.

## Review Focus

1. **A remote that isn't called `origin`** (this repo's remote is `forgejo`). `setup-sync`, `sync`, `post-merge` and `pre-push` must all use the remote they were given, never a hardcoded `origin`. Tested in Task 3 and Task 7.
2. **The first push to a remote with no tracking refs.** Every local issue gets pushed and the push succeeds; nothing is flagged as diverged. Tested in Task 7.
3. **A format-1 note on one side and format-2 on the other.** The merge canonicalizes both before comparing, so the format upgrade alone is never a conflict. Tested in Task 4.
4. **Multi-line comments** (continuation lines start with one space). Union compares whole folded records, so two comments sharing a first line are both kept. Tested in Task 4.
5. **An edit that changes nothing** (adding a label that's already there). `gi_edit` writes no commit, so history and push stay quiet. Tested in Task 1.

## File Structure

- `bin/git-issue`: the storage functions (CAS write, `gi_edit`), the `sync`, `resolve` and `log` commands, `setup-sync` migration, and the list/show conflict marks.
- `share/git-issue/awk/merge_doc.awk` (new): the three-way merge of format-2 documents; a pure function from three files to a merged document and a conflict file.
- `share/git-issue/awk/diff_doc.awk` (new): the field-level diff of two documents, used by commit messages and `log`.
- `hooks/pre-push`, `hooks/post-merge`: rewritten per spec §4.
- `tests/test_sync_merge.sh` (new): the spec's acceptance list, with clones A and B of one bare remote.
- `tests/test_merge_doc.sh` (new): unit tests for `merge_doc.awk` and `diff_doc.awk` on fixture documents.
- `Makefile`: targets `test-sync` and `test-merge-doc`, both added to `test-all`.
- `docs/reference.md`, `docs/design.md`: commands and storage model.

---

### Task 1: Compare-and-swap writes and `gi_edit`

**Files:**
- Modify: `bin/git-issue`:
  - `write_issue_data` (409);
  - the callers `create_issue` (617), `update_issue` (831), `import_single_issue` (1548), `add_comment` (1667), `append_to_field` (2228), `remove_from_field` (2280), `migrate_status` (3146), `migrate_format` (3187), and manual create in `main` (3617).
- Create: `tests/test_sync_merge.sh` (the harness, plus test 1).
- Modify: `Makefile` (`test-sync`, added to `test-all`).

**Interfaces:**
- Produces:
  - `gi_ref_commit <id>`: prints the issue ref's commit sha, or nothing if absent; exit 0.
  - `read_issue_at <commit>`: prints the document stored in that commit's `issue` blob (legacy fallback as in `read_issue_data`).
  - `write_issue_data <id> <data> <expected>`. `<expected>` is the parent sha, or empty for create, which uses the zero oid. Returns 0 on write, 75 on mismatch, 1 on the existing refusal.
  - `gi_edit <id> <transform> [args...]`. Calls `<transform> "$data" args...` with the document read at `gi_ref_commit`. The transform prints the new document; its nonzero exit aborts `gi_edit` with that status. A transform output equal to the canonical input writes nothing and returns 0. Retries on 75, up to 5 times, then prints `Error: issue <id> kept changing; edit not applied` to stderr and returns 75.
  - Harness functions in `tests/test_sync_merge.sh`: `setup_pair` (bare remote `R`, clones `A` and `B`, user names `Alice`/`Bob`, `setup-sync enable` in each), `in_A <cmd>`, `in_B <cmd>`, `check <name> <condition-command>`.

- [ ] **Step 1: Write the failing tests** in `tests/test_sync_merge.sh`:
  - `concurrent_comments_all_kept`: in `A`, create one issue, then start 8 `git issue comment "$id" "c$i"` in the background and `wait`. Assert `git issue show "$id"` contains each of `c1`…`c8`.
  - `noop_edit_writes_nothing`: add label `x` twice. Assert `git rev-list --count refs/notes/issue-$id` is the same after the second add as after the first.
  - `create_never_overwrites`: create an issue, then call `write_issue_data "$id" "<doc>" ""` (source `bin/git-issue`). Assert it returns 75 and the ref is unchanged.
- [ ] **Step 2: Run** `bash tests/test_sync_merge.sh`.
  Expected: `concurrent_comments_all_kept` FAILS, with fewer than 8 comments; if all 8 survive, raise the count to 16. The other two tests also fail.
- [ ] **Step 3: Implement the four interface functions.** `write_issue_data` passes `"$expected"` (or `0000000000000000000000000000000000000000`) as update-ref's third argument. Convert each caller into a transform plus one `gi_edit` call; the transform is the caller's existing "compute `updated_data` from `data`" code, moved into a function named `_tx_<caller>`. A caller's messages print after `gi_edit` returns 0. `create_issue` and the manual create call `write_issue_data … ""` directly.
- [ ] **Step 4: Run** `bash tests/test_sync_merge.sh && make test-all`. Expected: the three new tests PASS, and every existing suite passes.
- [ ] **Step 5: Commit** with message `feat(storage): compare-and-swap issue writes through gi_edit`.

### Task 2: The dependency index is local, with a checked write

**Files:**
- Modify: `bin/git-issue` (`read_edge_index`, `write_edge_index`, `remove_edge`, `rebuild_edge_index`, `ensure_edge_index_current`, 1986–2200).
- Test: `tests/test_sync_merge.sh`.

**Interfaces:**
- Consumes: the Task 1 harness.
- Produces: `GI_EDGE_REF=refs/issue-local/dep-graph`. `write_edge_index <data> <expected>` returns 75 on mismatch; `add_edge`/`remove_edge` retry by re-reading. `gi_reindex_issues <id>...` re-derives the edges of exactly those issues (the per-issue body of `ensure_edge_index_current`, extracted).

- [ ] **Step 1: Write the failing tests:**
  - `edge_index_ref_is_local`: after `git issue dep add`, assert `refs/issue-local/dep-graph` exists and `refs/notes/dep-graph` does not.
  - `legacy_edge_ref_ignored`: hand-write a `refs/notes/dep-graph` holding a bogus edge. Assert `git issue deps <id>` doesn't show it.
- [ ] **Step 2: Run** `bash tests/test_sync_merge.sh`. Expected: both FAIL.
- [ ] **Step 3: Implement.** Point every edge-index read and write at `$GI_EDGE_REF`, add the old-value check, and extract `gi_reindex_issues`. A missing local index is rebuilt from headers on first read, as an absent index is today.
- [ ] **Step 4: Run** `bash tests/test_sync_merge.sh && make test-deps`. Expected: PASS.
- [ ] **Step 5: Commit** with message `fix(deps): keep the edge index local at refs/issue-local/dep-graph`.

### Task 3: Tracking namespace and `setup-sync` migration

**Files:**
- Modify: `bin/git-issue` (`setup_sync_enable` 1248, `setup_sync_status` 1370, `setup_sync_disable` 1330).
- Test: `tests/test_sync_merge.sh`, `tests/test_hooks_sync.sh` (update its refspec expectation).

**Interfaces:**
- Consumes: `GI_EDGE_REF` (Task 2).
- Produces:
  - `gi_tracking_ref <remote> <id>`, which prints `refs/issue-remotes/<remote>/issue-<id>`.
  - `setup-sync enable [<remote>...]`: default every remote. Writes `+refs/notes/issue-*:refs/issue-remotes/<remote>/issue-*` once per remote, removes any `remote.<r>.fetch` value matching `refs/notes/`, and deletes `refs/notes/dep-graph`.
  - `setup-sync status` porcelain key `unsafe-fetch	true|false`.

- [ ] **Step 1: Write the failing tests:**
  - `fetch_leaves_local_issue`: B comments and pushes the issue notes. A adds an unpushed comment, then runs plain `git fetch`. Assert A's `refs/notes/issue-$id` sha is unchanged and `refs/issue-remotes/origin/issue-$id` equals B's sha.
  - `migration_replaces_forced_refspec`: add `+refs/notes/*:refs/notes/*` to `remote.origin.fetch`. Assert `setup-sync status --porcelain` prints `unsafe-fetch	true`. After `setup-sync enable`, assert `git config --get-all remote.origin.fetch` has no `refs/notes/` value and `status` prints `unsafe-fetch	false`.
  - `non_origin_remote`: rename A's remote to `forgejo` and run `setup-sync enable`. Assert `remote.forgejo.fetch` has the tracking refspec.
- [ ] **Step 2: Run** `bash tests/test_sync_merge.sh`. Expected: the three new tests FAIL.
- [ ] **Step 3: Implement** the interface. Disable removes the tracking refspecs it added.
- [ ] **Step 4: Run** `bash tests/test_sync_merge.sh && bash tests/test_hooks_sync.sh`. Expected: PASS.
- [ ] **Step 5: Commit** with message `fix(sync): fetch issue refs into refs/issue-remotes, never over local refs`.

### Task 4: `merge_doc.awk`, the three-way document merge

**Files:**
- Create: `share/git-issue/awk/merge_doc.awk`, `tests/test_merge_doc.sh`, fixtures under `tests/fixtures/merge/`.
- Modify: `Makefile` (`test-merge-doc`, in `test-all`); `Makefile`/`Formula` install lists, if they enumerate awk files.

**Interfaces:**
- Produces: `gi_merge_docs <base> <local> <remote> <conflicts>`, in `bin/git-issue`. Its arguments are file paths, and each document is canonicalized with `_gi_to_format_2` before the awk runs. It prints the merged canonical document to stdout. It exits 0 on a clean merge, or 1 when `<conflicts>` holds records.

  Each conflict record is three lines: `field: <name>`, then `local: <value>` and `remote: <value>`, with values folded by `gi_fold`. When conflicts exist, the document carries the local value for each conflicting field. The awk takes `-v LIST_FIELDS="labels blocks depends_on parent_of relates_to waits_for"`, plus `-v CONFLICTS=<path>`.

- [ ] **Step 1: Write the failing tests.** Each is a fixture triple plus an expected output, compared with `diff`:
  - `one_side_field_wins`: local changes `priority`; the result has local's priority.
  - `both_same_value`: both sides set `status: closed`; it's clean.
  - `both_different_conflict`: local `status: closed`, remote `status: blocked`. Exit 1; the conflict file holds `field: status`, `local: closed`, `remote: blocked`.
  - `updated_takes_later`: both sides change `updated:`. Clean, and the later value is kept.
  - `labels_set_merge`: base `a,b`, local `a,b,c`, remote `b,d`. The result is `b,c,d`.
  - `description_both_changed_conflict`.
  - `comments_union`: each side adds one comment. The result has both, sorted by timestamp.
  - `multiline_comments_kept` (Review Focus 4): two comments with the same first line and different continuation lines are both kept.
  - `format1_vs_format2` (Review Focus 3): the base and local are format 1, the remote is the same content upgraded to format 2. Clean, with no conflicts.
- [ ] **Step 2: Run** `bash tests/test_merge_doc.sh`. Expected: every test FAILS (`merge_doc.awk` not found).
- [ ] **Step 3: Implement `merge_doc.awk` and `gi_merge_docs`.**
  - The awk reads the three files via `ARGV`, splits each into its header block and the `## Comments` records (with continuation lines attached to their record), and merges per spec §3.
  - Header order follows local's, then fields only the remote has. Comments are keyed on the whole record text.
- [ ] **Step 4: Run** `bash tests/test_merge_doc.sh`. Expected: all PASS.
- [ ] **Step 5: Commit** with message `feat(sync): three-way merge of issue documents`.

### Task 5: `git issue sync`

**Files:**
- Modify: `bin/git-issue` (new `sync_issues`, the dispatch `case` in `main`, `show_help`), `docs/reference.md`.
- Test: `tests/test_sync_merge.sh`.

**Interfaces:**
- Consumes: `gi_tracking_ref` (Task 3), `gi_merge_docs` (Task 4), `gi_reindex_issues` (Task 2), and `write_issue_data` with expected (Task 1).
- Produces:
  - `git issue sync [<remote>]`. The default is every remote with a tracking refspec.
  - `gi_integrate <remote>`. It prints one line per issue it changed or flagged:
    - `fast-forward <id>`
    - `new <id>`
    - `merged <id>`
    - `conflict <id> <field>...`
    - `collision <id> "<local title>" "<remote title>"`

    It exits 0, or 1 if any line is a conflict or collision.
  - `gi_issue_conflicts <remote> <id> <conflicts-file>`, which recomputes an issue's conflicts from the refs. It exits 0 if the issue is clean and 1 if it is in conflict. Tasks 6 and 7 use it.

- [ ] **Step 1: Write the failing tests:**
  - `comments_merge_both_ways` (acceptance 2): A and B each comment on one issue; A pushes; B syncs and pushes; A syncs. Assert both clones show both comments, and the ref's head has 2 parents (`git rev-list --parents -n1`).
  - `different_fields_merge` (acceptance 5).
  - `remote_only_issue_created`: B creates an issue and pushes; A syncs. Assert A's `refs/notes/issue-<id>` equals the tracking ref.
  - `id_collision_reported` (acceptance 6): write unrelated root commits to the same id in A and in R. Assert `sync` prints `collision`, exits 1, and changes neither ref.
  - `deps_after_sync` (acceptance 8): B adds a dependency and pushes; A syncs. Assert A's `git issue deps` shows it, and `git ls-remote R` lists no `dep-graph` ref.
- [ ] **Step 2: Run** `bash tests/test_sync_merge.sh`. Expected: the five new tests FAIL (`sync`: unknown command).
- [ ] **Step 3: Implement.**
  - One `git for-each-ref --format='%(refname) %(objectname)'` over both namespaces, joined on the id, finds the issues that differ.
  - Per issue, `git merge-base --is-ancestor` both ways, then `git merge-base` to choose a row of the spec's table.
  - A clean merge writes its blob, tree and commit with `-p <local> -p <remote>`, then calls `write_issue_data`'s update-ref with the expected local sha. A 75 means a local write landed meanwhile, so redo that issue once.
  - Finish with `gi_reindex_issues` over every changed id.
- [ ] **Step 4: Run** `bash tests/test_sync_merge.sh && make test-all`. Expected: PASS.
- [ ] **Step 5: Commit** with message `feat(sync): git issue sync integrates each issue with its remote`.

### Task 6: Conflicts in `show` and `list`, and `git issue resolve`

**Files:**
- Modify: `bin/git-issue` (`show_issue` 750, `list_issues` 686, the porcelain list output, the new `resolve_issue`, dispatch, help), `docs/reference.md`.
- Test: `tests/test_sync_merge.sh`.

**Interfaces:**
- Consumes: `gi_issue_conflicts` (Task 5).
- Produces:
  - `git issue resolve <id> [--remote <r>] <field>=<value>...`. It exits 2 with `Error: unresolved fields: <names>` when a conflicting field lacks a value.
  - `show` prints a `Conflict with <remote>:` block before the issue, one `field: local | remote` line per field.
  - `list` prefixes a conflicted issue's id with `!`. Porcelain list adds the column `conflict` (`1`/`0`) at the end.

- [ ] **Step 1: Write the failing test** `status_conflict_resolved` (acceptance 4, up to the push):
  - A closes the issue and pushes; B sets `blocked`, then syncs.
  - Assert the `sync` output contains `conflict <id> status`; `show` contains `status: blocked | closed`; and `list` has `!<id>`.
  - Assert `resolve <id> priority=low` exits 2 (`status` is still unresolved). Then `resolve <id> status=closed` exits 0, the head has 2 parents, and `show` has `status: closed` and no conflict block.
- [ ] **Step 2: Run** the suite. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `list` gets the conflicted ids from one extra `for-each-ref` over the tracking refs, keeping the cost O(changed refs).
  - It calls `gi_issue_conflicts` only for diverged ids.
  - `resolve` re-runs the merge with the given values written into the conflicting fields, and commits with both parents.
- [ ] **Step 4: Run** `bash tests/test_sync_merge.sh && make test-porcelain`. Expected: PASS.
- [ ] **Step 5: Commit** with message `feat(sync): show conflicts and resolve them`.

### Task 7: The `pre-push` and `post-merge` hooks; `create` checks tracking ids

**Files:**
- Modify: `hooks/pre-push`, `hooks/post-merge`, `bin/git-issue` (`create_issue`'s id collision retry).
- Test: `tests/test_sync_merge.sh`, `tests/test_hooks_sync.sh`.

**Interfaces:**
- Consumes: `gi_tracking_ref` (Task 3), `sync` (Task 5).
- Produces: hook behavior per spec §4. After a successful push, the hook runs `git update-ref` for each pushed tracking ref.

- [ ] **Step 1: Write the failing tests:**
  - `diverged_push_refused`, the end of acceptance 4: B pushes before resolving. Assert `git push` exits nonzero, its stderr contains `run \`git issue sync origin\` first`, and R's ref is unchanged. With `GIT_ISSUE_PUSH_SOFT=1`, the push exits 0.
  - `push_after_resolve_succeeds`.
  - `no_change_pushes_nothing` (acceptance 7): after sync and push, a second `git push` prints `Pushing` 0 times. Run with `GIT_TRACE=1` and assert there's no `ls-remote` in the trace.
  - `first_push_without_tracking_refs` (Review Focus 2): a new bare remote `R2` with no tracking refs. Assert the push of 3 issues succeeds and `git ls-remote R2` lists all 3.
  - `post_merge_runs_sync`: `git pull` in A, after B's comment, shows B's comment in A.
  - `hooks_use_named_remote` (Review Focus 1): the same divergence test with the remote named `forgejo`.
- [ ] **Step 2: Run** the suite. Expected: the new tests FAIL.
- [ ] **Step 3: Implement** both hooks per spec §4. `post-merge` runs `git issue sync "$remote"` for the remote of the current branch's upstream (`git rev-parse --abbrev-ref @{u}`), falling back to every remote with a tracking refspec. In `create_issue`, the existing collision retry checks `refs/issue-remotes/*/issue-<id>` too.
- [ ] **Step 4: Run** `make test-all`. Expected: PASS.
- [ ] **Step 5: Commit** with message `fix(hooks): push issue refs without force and fail on divergence`.

### Task 8: Commit messages that name the change, and `git issue log`

**Files:**
- Create: `share/git-issue/awk/diff_doc.awk`.
- Modify: `bin/git-issue` (`write_issue_data`'s message, the new `log_issue`, dispatch, help), `docs/reference.md`, `docs/design.md` (storage model: tracking refs, local index, history).
- Test: `tests/test_merge_doc.sh` (diff units), `tests/test_sync_merge.sh` (acceptance 9).

**Interfaces:**
- Consumes: `read_issue_at` (Task 1).
- Produces:
  - `gi_diff_docs <old-file> <new-file>`, which prints one change per line: `field: <old> → <new>`, `field: + <new>` for an added field, `comment`, or `description changed`.
  - The commit message is the change lines joined with `; `, or `Create issue <id>` on create. A merge keeps `Merge issue <id> from <remote>`.
  - `git issue log <id> [--porcelain]`. For each commit, newest first, it prints a header line `<short sha> <ISO date> <committer name> <email>` followed by its change lines indented two spaces. For a merge, the change lines show `field: <value> (from local|remote|resolved)`. Porcelain output is one record per commit, separated by US (`\037`), in the order sha, date, name, email, changes joined by `\036`.

- [ ] **Step 1: Write the failing tests:**
  - In `test_merge_doc.sh`, these produce exact lines:
    - `diff_status_change`
    - `diff_added_comment`
    - `diff_description_changed`
  - In `test_sync_merge.sh`:
    - `commit_message_names_change`: close an issue. Assert `git log -1 --format=%s refs/notes/issue-$id` is `status: open → closed`.
    - `log_shows_history` (acceptance 9): after the conflict test's resolve, `log` shows Alice's and Bob's commits with their emails, `status: open → closed`, and the merge line `status: closed (from resolved)`.
    - `log_reads_old_generic_commits`: hand-write a commit whose message is `Update issue <id>`. Assert `log` still shows its field change, computed from the blobs.
- [ ] **Step 2: Run** both suites. Expected: the new tests FAIL.
- [ ] **Step 3: Implement.**
  - `write_issue_data` computes the message from the expected commit's document against the new one.
  - `log` reads `git log --format='%H %P %cI %cn %ce' <ref>` once, and every blob through one `cat-file --batch`.
- [ ] **Step 4: Run** `make test-all`. Expected: PASS.
- [ ] **Step 5: Commit** with message `feat(history): git issue log and commit messages that name the change`.
