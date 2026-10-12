# git-issue reference

Every command, field and integration, section by section. For a walkthrough, read the [User Guide](user-guide.md).

## Commands

| Command | Description |
|---------|-------------|
| `git issue create <title> [--description=<desc>]` | Create new issue (auto-generates hash ID) |
| `git issue list` | List all issues |
| `git issue show <id>` | Show issue details |
| `git issue update <id> [--status=<status>] [--priority=<priority>] [--assignee=<assignee>] [--title=<title>] [--description=<desc>]` | Update issue with git-style flags |
| `git issue statuses` | Show configured statuses and allowed transitions |
| `git issue comment <id> <text>` | Add comment to issue |
| `git issue link <id> <commit>` | Link issue to commit |
| `git issue setup-sync [enable [<remote>...]\|disable\|status]` | Configure automatic git notes sync |
| `git issue sync [<remote>]` | Fetch each remote's issues and merge them with yours |
| `git issue resolve <id> [--remote <r>] <field>=<value>...` | Merge an issue in conflict, choosing each conflicting field's value |
| `git issue dep add <from> <type> <to>` | Add dependency between issues |
| `git issue dep rm <from> <type> <to>` | Remove dependency |
| `git issue dep list [<id>]` | Show dependencies for an issue |
| `git issue dep rebuild` | Regenerate edge index |
| `git issue ready` | List issues with no open blockers |
| `git issue topo` | Topological ordering of issues |
| `git issue deps [<id>] [--dot]` | Dependency graph (text or Graphviz DOT) |
| `git issue repo add [--force] <name> <path>` | Register a repository in the global registry |
| `git issue repo list` | List registered repositories as `<name> <path>` |
| `git issue repo rm <name>` | Forget a repository (contents untouched) |
| `git issue repo prune` | Forget entries whose path no longer exists |
| `git issue-status` | Show status summary |

Two global options work with any command: `--repo <name>` runs it in a
registered repository, and `--all` sweeps `list` or `ready` across every
one. Both are accepted before or after the subcommand.

### Statuses
- `open` - New issue, not yet started
- `in_progress` - Actively being worked on
- `review` - Awaiting feedback or review
- `blocked` - Blocked by a dependency
- `deferred` - On hold, will revisit later
- `closed` - Completed or resolved

Statuses and their allowed transitions are configurable via `.git-issue/statuses`. Run `git issue statuses` to view the current configuration.

### Priorities
- `low` - Nice to have
- `medium` - Standard priority
- `high` - Important
- `critical` - Urgent


## Dependency Graph

Track relationships between issues with four dependency types:

| Type | Meaning | Blocking? |
|------|---------|-----------|
| `blocks` | Must complete before target can start | Yes |
| `depends_on` | Cannot start until dependency completes | Yes (inverse of blocks) |
| `parent_of` | Epic/parent containing sub-issues | No |
| `relates_to` | Informational link | No |

Dependencies are **bidirectional**: `dep add A blocks B` automatically sets `depends_on: A` on B.

```bash
# Add a dependency
git issue dep add a1b2c3d blocks d4e5f6a
# Auto-sets d4e5f6a to "blocked" status

# Remove a dependency
git issue dep rm a1b2c3d blocks d4e5f6a

# List dependencies for an issue
git issue dep list a1b2c3d

# Mark blocker closed — auto-unblocks dependents
git issue update a1b2c3d --status=closed

# List issues with no open blockers (ready to work on)
git issue ready

# Topological ordering of issues
git issue topo

# Dependency graph (text output)
git issue deps

# Subgraph from a specific issue
git issue deps a1b2c3d

# Graphviz DOT output (pipe to dot for visualization)
git issue deps --dot | dot -Tpng -o deps.png
```

**Key behaviors:**
- Blocked issues auto-transition to `blocked` status when a blocking dependency is added
- Marking a blocker `closed` cascades unblock to dependents
- Cycle detection via POSIX `tsort` prevents circular dependencies
- `dep rebuild` regenerates the edge index if it gets out of sync


## Multi-Project Registry

`git-issue` normally works on whatever repository you are standing in.
The registry names your repositories so you — or an agent — can reach any
of them from anywhere, and ask "what should I work on next, *anywhere*?"

```bash
# Register repositories (explicit: nothing is ever registered for you)
git issue repo add tracker ~/src/git-issue-tracker
git issue repo add api ~/src/api
# Registered 'tracker' -> /home/you/src/git-issue-tracker

# See what is tracked. Entries whose path is gone are shown, not hidden.
git issue repo list
# tracker /home/you/src/git-issue-tracker
# api /home/you/src/api

# Run any command against a registered repository, from anywhere
git issue --repo api list
git issue create "New bug" --repo api      # either flag position works

# Sweep every registered repository; each line is prefixed with its name
git issue ready --all
# [tracker] #a064d35 [open]  Fix navbar  (P: high)
# [api] #d4e5f6a [open]  Rate limiting  (P: medium)

# Forget a repository (this never deletes anything on disk)
git issue repo rm api
git issue repo prune          # drop entries whose path no longer exists
```

The registry is stored in your global git config as
`issue.repo.<name>.path`, so anything that can read git config can read
it without git-issue installed:

```bash
git config --global --get-regexp '^issue\.repo\.'
```

Names are lowercase letters, digits, `-` and `_`. A path that is a linked
worktree registers as its main worktree, since issue refs belong to the
repository rather than to a checkout. A sweep never stops at a broken
entry: it reports the skip on stderr, keeps going, and exits nonzero.

With no registry entries, behavior is exactly as before.

The full specification is
[`docs/rfc/draft-ndn-multi-project-registry-02.md`](rfc/draft-ndn-multi-project-registry-02.md).


## Machine-readable output

`--porcelain` (accepted before or after the subcommand; `--porcelain=v1`
is the same thing, and v1 is frozen — any other version is rejected; a
changed format would be a new version) switches read commands to stable,
tab-separated output: no color, no headings, no `(none)` placeholders,
empty stdout for an empty result.

`list`, `ready`, `queue`, and `topo` each emit one line per issue with
twelve tab-separated columns: `repo`, `id`, `status`, `priority`,
`assignee`, `role`, `updated`, `blocks`, `depends_on`, `parent_of`,
`relates_to`, `title` (`repo` is empty unless `--all` is given, and
`title` is last because it's the only free-text column).

```bash
$ git issue list --porcelain
	a1b2c3d	open	medium	conformance		2026-01-01T00:00:00Z					alpha task
```

Split on tabs, that line is `repo=""`, `id=a1b2c3d`, `status=open`,
`priority=medium`, `assignee=conformance`, `role=""`,
`updated=2026-01-01T00:00:00Z`, `blocks=""`, `depends_on=""`,
`parent_of=""`, `relates_to=""`, `title="alpha task"` — twelve fields,
`updated` at column 7 and `title` at column 12.

`deps` and `dep list` emit one edge per line as `from`, `type`, `to`.
`scan-commits` emits one line per trailer as the full commit hash, the
lowercase trailer key, and the issue id. `setup-sync status` emits
`key`, `value` pairs (`enabled`, `post-merge-hook`, `pre-push-hook`,
`auto-fetch`, `issue-notes`, in that order).

`show --porcelain` emits a `key: value` header block instead of columns:

```bash
$ git issue show a1b2c3d --porcelain
title: alpha task
status: open
priority: medium
author: conformance
description: first line
 second line
comment: [2026-01-01T00:00:00Z] conformance: one
```

A line beginning with one space continues the previous value — this is
how multi-line descriptions and comments stay on one logical field. The
same rule now governs the note as stored: on disk, a note carries `v: 2`
as its second header line, and `description` is a header in the top
block with continuation lines rather than free text in a body region.
Notes written before this format are read the same way as ever (`v: 2`
absent means format 1); every write upgrades a legacy note in place.

The full specification, including the edge and reference line shapes
and the storage grammar, is
[`docs/rfc/draft-ndn-porcelain-output-00.md`](rfc/draft-ndn-porcelain-output-00.md).


## Git Integration

git-issue creates bidirectional links between issues and commits:

```bash
# Create issue
git issue create "Fix login validation"
# ✓ Created issue #d4a2b89: Fix login validation

# Work on the fix
git checkout -b fix-login-validation
echo "// Better validation logic" >> login.js
git add login.js
git commit -m "Improve login validation logic"

# Link issue to commit  
git issue link d4a2b89 HEAD

# View in git log
git log --notes --oneline -1
# abc1234 Improve login validation logic
# Notes:
#     Issue: #d4a2b89
#     Thoughts: Linked to issue #d4a2b89
```


## Automatic Synchronization

Enable seamless team collaboration with automatic git notes sync:

```bash
# Enable automatic sync (installs git hooks)
git issue setup-sync enable

# Check sync status
git issue setup-sync status

# Disable automatic sync
git issue setup-sync disable
```

**What automatic sync does:**
- **Auto-fetch**: Issue notes sync when you `git pull` or `git merge`
- **Auto-push**: Issue notes sync when you `git push` commits
- **Zero friction**: Works transparently with normal git workflow
- **Team collaboration**: Everyone stays in sync automatically

**How sync merges.** A fetch writes a remote's issues to
`refs/issue-remotes/<remote>/issue-<id>`, never over your own
`refs/notes/issue-<id>`. `git issue sync [<remote>]` then integrates each
issue that differs, the way git merges a branch, and prints one line per issue:

- `new <id>`: an issue only the remote had;
- `fast-forward <id>`: only the remote changed it;
- `merged <id>`: both changed it, and the merge commit has both as parents.
  A field one side changed takes that side's value, `updated:` takes the
  later value, list fields (`labels`, `blocks`, `depends_on`, `parent_of`,
  `relates_to`, `waits_for`) merge as sets, and comments are the union of
  both sides;
- `conflict <id> <field>...`: both changed a field to different values. The
  issue is left as it is, and nothing is dropped;
- `collision <id> "<title>" "<title>"`: two different issues got the same id.
  Neither is changed.

`sync` exits 1 when any issue is in conflict or collides. A conflicted issue
shows a `Conflict with <remote>:` block in `git issue show`, with one
`field: yours | theirs` line per field, and `git issue list` marks it `!` in
place of `#`. `git issue resolve <id> <field>=<value>...` writes the merge,
taking your value for each conflicting field; it refuses (exit 2) until every
conflicting field has one.

**Manual sync (if auto-sync disabled):**
```bash
# Fetch each remote's issues and merge them
git issue sync origin

# Push issue notes to remote  
git push origin 'refs/notes/issue-*'
```


## GitHub Integration

git-issue provides seamless bidirectional integration with GitHub issues:

### Import from GitHub

```bash
# Import issues from GitHub using gh CLI
gh issue list --json number,title,body,state,author,assignees,labels,url,createdAt,updatedAt | gh-to-git-issue | git issue import

# Import specific issues
gh issue view 42 --json number,title,body,state,author,assignees,labels,url,createdAt,updatedAt | jq '[.]' | gh-to-git-issue | git issue import
```

### Export to GitHub

```bash
# Export all issues in GitHub format
git issue export --github

# Export specific issues
git issue export --github a064d35 b123c4d
```

### Provider-Specific Fields

Imported issues maintain links to their GitHub origins:

```yaml
id: a064d35
title: Fix navbar responsive design
description: Navigation overlaps content on mobile
status: open
priority: high
github_id: 42
github_url: https://github.com/example/repo/issues/42
created: 2025-01-15T10:30:00Z
author: developer1
assignee: reviewer1
```

### Workflow Examples

**One-time import:**
```bash
# Import existing GitHub issues
gh issue list --state=all --json number,title,body,state,author,assignees,labels,url,createdAt,updatedAt | gh-to-git-issue | git issue import
```

**Sync workflow:**
```bash
# Work with issues locally
git issue create "Add new feature" --description="Implement user dashboard"
git issue update a064d35 --status=in_progress

# Export changes back to GitHub (manual process)
git issue export --github a064d35 | gh issue create --body-file -
```


## Emacs and Magit

The installer ships two Elisp files to `<prefix>/share/git-issue/emacs`,
alongside the awk and hook directories. Add that directory to your
`load-path`:

```elisp
(add-to-list 'load-path "<prefix>/share/git-issue/emacs")
(require 'magit-git-issue)
```

`git-issue.el` is the magit-free core: it runs `git issue --porcelain`
and parses the result into Lisp structs, and loads in a plain Emacs with
no other packages. Any Elisp — not only magit — can `(require 'git-issue)`
alone to read and write issues.

`magit-git-issue.el` adds the rest, once magit and transient are
available:

- An issues section in the status buffer, whose contents are set by
  `magit-git-issue-status-section` (`ready`, the default, or `open`).
- `x` opens `magit-git-issue-dispatch`, a transient bound both in
  `magit-dispatch` and in the status buffer, with actions for every issue
  command — start, close, reopen, comment, set status/priority/assignee/role,
  add or remove a dependency, link to a commit, and open the list, ready,
  and show buffers.
- `magit-git-issue-list` and `magit-git-issue-ready` open a buffer of
  issues; a prefix argument (`C-u`) asks for `--all`, listing every
  registered repository with each line prefixed by its repo name.
- `RET` on an issue line opens a detail buffer; `g` refreshes it.
- The commit transient gains `-x`/`--fixes=`, `-X`/`--closes=`, and
  `-i`/`--issue=`, each completing over open issue ids and passed to
  `git commit --trailer`. `C-c C-x` in a commit message buffer runs
  `git-issue-insert-trailer` to add a trailer interactively.
- Composing a comment or a new issue's description happens in a small
  buffer finished with `C-c C-c` or aborted with `C-c C-k`, the same
  convention as magit's own commit buffer.
