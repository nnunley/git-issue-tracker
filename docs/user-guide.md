# git-issue User Guide

git-issue keeps your issues inside the git repository they belong to, as
git notes. There is no server, no database, and nothing to sync that git
does not already sync. This guide walks through the tool the way you will
use it: first issue, daily loop, linking work to commits, dependencies,
several repositories at once, machines and remotes, and automation.

For the Emacs and magit interface, see the [Emacs guide](emacs-guide.md).
For the exact contracts behind the machine-readable output and the
registry, see the RFCs under [`rfc/`](rfc/).

## Contents

1. [Install](#install)
2. [Your first issue](#your-first-issue)
3. [The daily loop](#the-daily-loop)
4. [Issue fields and statuses](#issue-fields-and-statuses)
5. [Linking issues to commits](#linking-issues-to-commits)
6. [Dependencies and the ready queue](#dependencies-and-the-ready-queue)
7. [Roles and queues](#roles-and-queues)
8. [Several repositories](#several-repositories)
9. [Syncing between machines](#syncing-between-machines)
10. [Importing and exporting](#importing-and-exporting)
11. [Scripting and agents](#scripting-and-agents)
12. [Where the data lives](#where-the-data-lives)
13. [Troubleshooting](#troubleshooting)

## Install

Requirements: git, bash 3.2 or later, POSIX awk, and `jq` for the
GitHub converters.

```bash
# Homebrew
brew install nnunley/git-issue/git-issue

# Or from a checkout
git clone https://github.com/nnunley/git-issue-tracker
cd git-issue-tracker
make install PREFIX=$HOME/.local        # puts git-issue in ~/.local/bin
```

`git issue` works as a git subcommand as soon as `git-issue` is on your
`PATH`. Check with:

```bash
git issue --help
```

The installer also places awk programs, hook templates, and the Emacs
files under `<prefix>/share/git-issue`. If you move the binary, keep that
directory beside it, or set `GIT_ISSUE_AWK_DIR`.

## Your first issue

Inside any git repository:

```bash
git issue create "Fix navbar on narrow screens" \
  --description="Overlaps content below 768px"
# ✓ Created issue #a064d35: Fix navbar on narrow screens

git issue list
git issue show a064d35
```

Ids are seven hex characters, hashed from the content, so two people
creating issues on different machines never collide. You will usually
read them off `list` and paste them; the Emacs interface completes them.

## The daily loop

```bash
git issue ready                  # what can I work on right now?
git issue start a064d35          # status -> in_progress
git issue comment a064d35 "Reproduced on Safari; breakpoint is the culprit"
# ... make commits ...
git issue close a064d35          # status -> closed
git issue reopen a064d35         # if it comes back
```

`ready` lists open issues with no open blockers, sorted by priority. It
is the view to start the day from; the Emacs status buffer shows the
same list.

Multi-line comments and descriptions are fine: pass them as one argument.

```bash
git issue comment a064d35 "$(printf 'Two things:\n- one\n- two')"
```

## Issue fields and statuses

Every issue has a title, status, priority, author, assignee, optional
role, description, comments, and dependency fields. Change fields with
`update`:

```bash
git issue update a064d35 --status=review --priority=high
git issue update a064d35 --assignee="Ada Lovelace" --role=frontend
git issue update a064d35 --description="Rewritten description"
git issue update a064d35 --title="Navbar overlaps content on mobile"   # the id stays
```

Priorities are `low`, `medium`, `high`, `critical`.

Statuses default to `open`, `in_progress`, `review`, `blocked`,
`deferred`, and `closed`. Two are set for you: `blocked` when a blocking
dependency is added, and back to `open` when the last blocker closes.
The vocabulary and the allowed transitions live in `.git-issue/statuses`
in the repository; `git issue statuses` prints the current machine. A
repository can adopt a different vocabulary, for example the Beads set
shipped in `share/git-issue/statuses.beads`, by copying it to that path.

## Linking issues to commits

Two mechanisms, and they compose.

**Trailers in the commit message** are the durable link. Write one by
hand, or let git-issue add it to `HEAD`:

```bash
git commit -m "Clamp navbar width" --trailer "Fixes: #a064d35"
git issue commit --fixes a064d35     # amends HEAD with the trailer
```

Recognized keys are `Issue`, `Fixes`, `Closes`, and `Related-To`. Find
them later with:

```bash
git issue scan-commits --since="2 weeks ago"
git issue show a064d35 --with-commits
```

**`link`** records a commit on the issue and a note on the commit, for
work that was committed before the issue existed:

```bash
git issue link a064d35 HEAD~2
```

## Dependencies and the ready queue

Four relationship types, added between ids:

| Type | Meaning | Blocks the target? |
|---|---|---|
| `blocks` | A must finish before B can start | yes |
| `depends_on` | inverse of blocks, kept in sync automatically | yes |
| `parent_of` | epic containing sub-issues | no |
| `relates_to` | informational | no |

```bash
git issue dep add a064d35 blocks d4e5f6a   # d4e5f6a becomes blocked
git issue dep list d4e5f6a
git issue dep rm a064d35 blocks d4e5f6a
git issue close a064d35                    # d4e5f6a returns to open
```

Views over the graph:

```bash
git issue ready            # unblocked, open, by priority
git issue topo             # every open issue in an order you could work them
git issue deps             # the whole graph as text
git issue deps a064d35     # the subgraph reachable from one issue
git issue deps --dot | dot -Tpng -o deps.png
```

Cycles are refused when you try to add them.

## Roles and queues

A role is a free-form label on an issue, such as `frontend` or `review`.
It lets a person, or an agent playing that role, ask for only their share
of the ready work:

```bash
git issue update d4e5f6a --role=frontend
git issue ready --role=frontend --limit=5
git issue queue frontend           # same thing, shorter
```

## Several repositories

The registry names repositories so you can reach any of them from
anywhere and ask what to do next across all of them. Nothing is
registered unless you say so.

```bash
git issue repo add tracker ~/src/git-issue-tracker
git issue repo add api ~/src/api
git issue repo list
# tracker /home/you/src/git-issue-tracker
# api /home/you/src/api

git issue --repo api list          # run any command in a registered repo
git issue ready --all              # sweep every registered repo
# [tracker] #a064d35 [open]  Fix navbar  (P: high)
# [api] #d4e5f6a [open]  Rate limiting  (P: medium)

git issue repo rm api              # forget; never deletes anything
git issue repo prune               # forget entries whose path is gone
```

The registry is plain git config, `issue.repo.<name>.path` in your
global config, so it travels with your dotfiles. A sweep reports and
skips a broken entry rather than stopping.

## Syncing between machines

Issues are git notes under `refs/notes/issue-*`. Git does not push or
fetch notes by default. Turn on automatic sync once per clone:

```bash
git issue setup-sync enable
git issue setup-sync status
```

This installs a pre-push hook that pushes the notes refs and a
post-merge hook that fetches them, and adds the refspec so `git fetch`
brings them down. On a second machine, clone, run `setup-sync enable`,
and `git fetch` once. To do it by hand instead:

```bash
git push origin 'refs/notes/issue-*'
git fetch origin 'refs/notes/issue-*:refs/notes/issue-*'
```

## Importing and exporting

**GitHub**, through the `gh` CLI and the converters shipped with
git-issue:

```bash
gh issue list --state=all \
  --json number,title,body,state,author,assignees,labels,url,createdAt,updatedAt \
  | gh-to-git-issue | git issue import

git issue export --github a064d35 | gh issue create --body-file -
```

Imported issues keep `github_id` and `github_url` fields, so the origin
is never lost.

**Files and bulk**: `git issue import --file issues.txt` reads one
issue document, `--bulk` reads several, `--stdin` reads from a pipe.
`git issue export` with no arguments prints every issue in git-issue's
own format, which `import` reads back.

## Scripting and agents

Every read command has a stable, tab-separated machine format behind
`--porcelain`, in the sense git gives that word: frozen columns, no
color, no decoration, exit 0 on an empty result.

```bash
git issue list --porcelain | cut -f2,3,12      # id, status, title
git issue ready --porcelain --all | cut -f1,2   # repo, id
git issue show a064d35 --porcelain             # key: value block
git issue create "Title" --porcelain           # prints only the new id
```

The twelve columns of an issue line are `repo`, `id`, `status`,
`priority`, `assignee`, `role`, `updated`, `blocks`, `depends_on`,
`parent_of`, `relates_to`, `title`. The `show` block is one `key: value`
line per field, with continuation lines beginning with one space, then
`description`, then one `comment` line per comment. The full contract is
[`rfc/draft-ndn-porcelain-output-00.md`](rfc/draft-ndn-porcelain-output-00.md);
never parse the colored output, it changes with the display.

The MCP server under `mcp/` exposes the same commands to AI assistants;
see its README.

## Where the data lives

- One git note per issue at `refs/notes/issue-<id>`, a small text
  document: headers, a `v: 2` format marker, the description as a header
  with continuation lines, and a `## Comments` section.
- A derived dependency index at `refs/notes/dep-graph`, rebuilt as
  needed; never edit it.
- `.git-issue/statuses` in the repository for the status machine,
  compiled on first use.
- Outside a git repository, git-issue falls back to a bare repository
  under `$XDG_DATA_HOME/git-issue/<project>.git` so a plain directory
  can still have issues.

Because everything is a git object, `git log refs/notes/issue-a064d35`
shows an issue's history, and a bad edit is one `git update-ref` away
from undone.

## Troubleshooting

**`git: 'issue' is not a git command`.** `git-issue` is not on `PATH`.
Check `which git-issue`; with a Homebrew install, `brew link git-issue`.

**`awk program not found`.** The binary cannot find
`share/git-issue/awk` beside its `bin` directory. Reinstall, or set
`GIT_ISSUE_AWK_DIR` to the directory.

**Issues missing after a clone.** Notes are not fetched by default; run
`git issue setup-sync enable` and `git fetch`.

**Two people created an issue with the same id.** Ids hash title,
author, and second-resolution time, so a collision needs the same three.
`create` retries on collision within one repository.

**`ready` shows nothing but `list` shows open issues.** They are all
blocked, or you filtered by a role no issue carries; `git issue deps`
shows why.

**Colored text where a script expected data.** Add `--porcelain`.
