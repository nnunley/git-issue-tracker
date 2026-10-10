# How git-issue works

The storage model and why ids are hashes.

## How It Works

git-issue stores each issue under its own ref, `refs/notes/issue-<id>`. The ref points at a commit whose tree holds one file, the issue document: a header of fields, then the description and comments. Each edit is a new commit, so an issue's history is the ref's log. (Despite the `refs/notes/` prefix these are not `git notes` entries; see #e2dfdaa for why sync needs to merge them.) A document looks like this:

```yaml
id: a064d35
title: Fix navbar responsive design
description: Navbar overlaps content on mobile devices below 768px
status: in_progress
priority: medium
created: 2025-07-12T16:57:31Z
updated: 2025-07-12T16:57:50Z
author: Norman Nunley, Jr
assignee: Norman Nunley, Jr
hash_source: content
---

[2025-07-12T16:57:56Z] Norman Nunley, Jr: Started responsive breakpoint work
```

### Storage Backends

**Git Repository** (default when in git repo):
- Uses issue refs (`refs/notes/issue-*`) in the current repository
- Fully integrated with git workflow
- Issues sync with git remotes
- Supports automatic sync via git hooks

**XDG Directory** (fallback when no git repo):
- Creates bare git repository in `$XDG_DATA_HOME/git-issue/$(project).git`
- Same git notes format and commands
- Isolated per-project issue tracking


## Why Hash-Based IDs?

Traditional issue trackers use sequential numbers (`#47`, `#48`) which create conflicts in distributed environments. git-issue uses git-style hash IDs:

- **Familiar to developers** - looks like commit hashes (`a064d35`)
- **Zero conflicts** - globally unique via content hashing
- **Git-native** - leverages git's proven hash system
- **Optimal length** - 7 characters (shorter than UUIDs, longer than sequential)
