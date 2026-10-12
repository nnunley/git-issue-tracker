# Multi-User Sync and Issue History — Design

**Date:** 2026-10-11
**Status:** Draft for review
**Issue:** #e2dfdaa (this spec carries its design plus the gaps in its 2026-10-12 comment)

## Goal

Two people (or two agents) editing the same issues, locally or through a shared remote, never lose an edit, and every issue's history can be read. Today three things lose edits:

1. **Local writes race.** `write_issue_data` reads the ref's commit, builds a child commit, and calls `git update-ref "$ref" "$commit"` with no expected old value. Two writers on one issue keep only the last commit.
2. **Fetch overwrites.** `setup-sync enable` installs `+refs/notes/*:refs/notes/*`, so a fetch writes the remote's refs over local ones (the bug in #e2dfdaa). `post-merge` fetches onto local refs too, and swallows the error when git refuses.
3. **Push hides divergence.** `pre-push` exits 0 when the issue push fails. Its change detection also never matches: `git rev-parse` of a missing ref prints the ref's name, so every ref looks changed, and the fallback runs `ls-remote` once per ref.

Per-issue refs stay (#e2dfdaa explains why: no write contention across issues, batch reads, one sha comparison per ref). The document format (format 2) does not change.

Success: the acceptance list at the end passes in a new `tests/test_sync_merge.sh`, and `list`, `show` and `pre-push` stay O(changed refs) in git calls.

## Design

### 1. Compare-and-swap writes

`write_issue_data <id> <data> <expected>` passes `<expected>` as update-ref's old value: the commit the edit was computed from, or the zero oid on create. A mismatch returns status 75 without writing.

Edits go through one helper that retries:

```bash
gi_edit <id> <transform> [args...]
# loop up to 5 times: read data and its commit; new=$(<transform> "$data" args...);
# write_issue_data id "$new" "$commit"; return on success, retry on 75
```

Every caller of `write_issue_data` (create, update, comment, status, dep add/rm, link, import) becomes a transform: a function from the current document to the new one. A transform never reads the ref itself, so a retry re-applies the edit to the newer document. Create uses the zero oid, so two creates of one id cannot both succeed.

`write_edge_index` gets the same old-value check. The index is derived data (§5), so on a mismatch it rebuilds instead of retrying the edit.

### 2. Tracking namespace

A remote's issue refs are fetched into `refs/issue-remotes/<remote>/issue-*`, never onto `refs/notes/issue-*`:

- `setup-sync enable` writes `+refs/notes/issue-*:refs/issue-remotes/<remote>/issue-*` for each remote, and removes any `refs/notes/*` fetch refspec an older version installed. `setup-sync status` reports the old refspec as "unsafe: fetch overwrites local issues".
- A plain `git fetch` is now safe: it only moves tracking refs. Forcing (`+`) on tracking refs is correct, since they mirror the remote, like `refs/remotes/`.
- `refs/notes/dep-graph` is not fetched (§5).

### 3. `git issue sync [<remote>]`: integrate per issue

`sync` fetches (as in §2), then integrates every issue whose local and tracking refs differ. One `for-each-ref` over both namespaces finds them. For each:

| Local | Tracking | Action |
|---|---|---|
| missing | present | create the local ref at the tracking commit |
| ancestor of tracking | | fast-forward the local ref |
| descendant of tracking | | nothing (push sends it) |
| diverged, merge base exists | | three-way merge (below) |
| diverged, no merge base | | **id collision**: report it, change nothing |

Every ref update in `sync` uses the compare-and-swap write from §1.

**Three-way merge.** It works on the canonical format-2 documents of the base, local and remote commits (a format-1 side is canonicalized first with `_gi_to_format_2`). Rules per part:

- **Header fields**, each compared against the base: changed on one side, that side wins; changed on both sides to the same value, that value; changed on both sides to different values, a conflict.
- **`updated:`** is never a conflict: the later timestamp wins.
- **List fields** (`labels`, `blocks`, `depends_on`, `parent_of`, `relates_to`, `waits_for`): a set merge against the base: an element either side added is kept, an element either side removed is dropped, and the rest of the base's elements stay. In set terms, `(base ∩ local ∩ remote) ∪ (local − base) ∪ (remote − base)`. Order follows local, then the remote's additions.
- **`description`**: a field like the others. Both sides changing it is a conflict; there is no text merge.
- **Comments**: the set union of whole records (`[ts] author: text` plus continuation lines), sorted by timestamp and then by the original order on each side. Two records are the same comment only if timestamp, author and text all match, so the union is exact without stored comment ids.

With no conflict, `sync` writes a merge commit with both parents (local first). The message is `Merge issue <id> from <remote>`.

**Conflicts** are not stored. A diverged issue whose merge has conflicts is left as it is: local ref unchanged, tracking ref at the remote's commit. Pushing it is refused (§4), so it can't spread. The state is recomputed from the refs on each run:

- `sync` lists each conflicted issue with both values of each conflicting field.
- `show <id>` prints the conflict block above the issue.
- `list` marks the issue with `!`. It already reads every local ref, and the tracking refs are one more `for-each-ref`.
- `git issue resolve <id> <field>=<value>...` writes the merge commit. It applies the automatic rules plus the given values, and refuses unless every conflicting field has a value.

Nothing is dropped. Both values stay in the two parent commits, and `log` (§6) shows them.

**Id collision** (diverged with no merge base): two clients created different issues with the same 7-character id. `sync` reports it and leaves both refs alone. `create` makes this rare: before taking an id, it checks the tracking refs as well as local refs. Recovering a collision (re-id one side) is out of scope; the report names both titles.

### 4. Push without force

`pre-push`:

- **Change detection:** one `for-each-ref` over `refs/notes/issue-*` and `refs/issue-remotes/<remote>/issue-*`. A ref is pushed when its sha differs from its tracking ref or it has no tracking ref. No `ls-remote`, and no `rev-parse` of missing refs.
- **Refspec:** `refs/notes/issue-<id>:refs/notes/issue-<id>` with no `+`, under `--atomic`. A diverged issue is rejected like a diverged branch.
- **On rejection:** the hook prints the rejected ids and "run `git issue sync <remote>` first". Then it exits 1, failing the code push too. This is a behavior change: until now the hook warned and let the push proceed. Failing is what git does for a diverged branch. `GIT_ISSUE_PUSH_SOFT=1` restores warn-only for anyone who needs it.
- **After a successful push:** the hook updates the tracking refs to the pushed shas, so the next run's change detection is accurate without a fetch.

`post-merge` calls `git issue sync <remote>` in place of its own fetch.

### 5. The dependency index is local only

`refs/notes/dep-graph` is derived from issue headers, and it diverges whenever two clients edit dependencies, so it never syncs:
- It moves to `refs/issue-local/dep-graph`, outside both the push globs and the fetch globs.
- A `refs/notes/dep-graph` left over from an older version is ignored, and deleted by `setup-sync enable`.
- `sync` re-derives edges for every issue it changed. That fixes a current gap: `ensure_edge_index_current` selects issues by commit date, and an incoming commit can carry a date older than the last rebuild.

### 6. History: `git issue log <id>`

An issue's history is its ref's commit graph, and §§1–4 keep it intact. `git issue log <id> [--porcelain]` walks it newest first: `git log --format=...` over the ref, plus one `cat-file --batch` for every blob.

For each commit it prints the date, the committer name and email (from the commit object), and the change:
- header fields whose values differ from the first parent's, as `field: old → new`;
- comments added;
- `description changed`;
- for a merge commit, which side each conflicting field's value came from.

Commit messages name the change too, so plain `git log refs/notes/issue-<id>` is readable. `write_issue_data` builds the message with the same diff as `log` (`status: open → closed; comment`), in place of `Update issue <id>`. Older commits keep their generic messages; `log` computes their changes from the blobs, so it works over existing history.

## Out of scope

- Email in the `author:` field and in comment records: commits already carry the email, and `log` shows it. Changing the field affects every name filter.
- Re-iding one side of an id collision.
- `refs/notes/commits`, which is real git notes. git has `git notes merge` for it. Its hook fetch stays non-forced.
- Text merging inside `description`.

## Acceptance (tests/test_sync_merge.sh)

Two clones, A and B, of one bare remote, both with `setup-sync enable`:

1. **Concurrent local writes:** two `git issue comment` calls on one issue, started together in one clone, keep both comments.
2. **Different comments:** A and B comment on the same issue, both push and sync. Both clones end with both comments, and the issue's history has a merge commit with both parents.
3. **Fetch doesn't touch local work:** a plain `git fetch` in A, with an unpushed local comment, leaves `refs/notes/issue-<id>` unchanged.
4. **Conflict:** A sets status to `closed`, B sets it to `blocked`. `sync` reports the conflict with both values; `show` and `list` mark it; B's push of that issue is refused with the sync hint; `resolve <id> status=closed` merges it and the push succeeds.
5. **Different fields:** A changes priority, B adds a label. They merge with no conflict, and `updated:` is the later of the two.
6. **Id collision:** two refs with the same id and no common ancestor are reported, and neither changes.
7. **Change detection:** after a push and a sync with nothing new, `pre-push` pushes 0 refs, and it makes no `ls-remote` calls in any case.
8. **The dependency index doesn't sync:** dependency edits in both clones never push or fetch an index ref. After sync, `ready` and `deps` in each clone reflect the merged headers.
9. **`log`:** shows each change from tests 2 and 4 with committer, date and `field: old → new`, and shows the merge's resolved value.
10. **Migration:** a clone with the old `+refs/notes/*:refs/notes/*` refspec gets it replaced by `setup-sync enable`, and `setup-sync status` flags it before that.
