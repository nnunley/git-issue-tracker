# Agent Instructions for git-issue-tracker

## Project Overview

`git-issue` is a lightweight, git-native issue tracking CLI that stores issues as git notes with hash-based IDs. Pure bash + git, zero external dependencies.

## Current Work: Dependency Graph Feature

We are adding a dependency graph system to close the biggest gap with [Beads](https://github.com/steveyegge/beads). The design is documented in `docs/plans/2026-02-28-dependency-graph-design.md`.

### Dogfooding

**All work on this feature is tracked using git-issue itself.** Use `git issue list` to see current tasks. Use `git issue show <id>` for details.

Epic: `ffdbfdb` — Add dependency graph and topological sort

Implementation tasks (in dependency order):

1. `2f1ab08` — dep: Write design doc
2. `27f03b1` — dep: Add dep header fields to issue data model
3. `9bc4207` — dep: Implement dep add/rm commands with bidirectional header sync
4. `5f82085` — dep: Implement edge index at refs/notes/dep-graph
5. `9fea41d` — dep: Implement cycle detection via tsort
6. `2b5a920` — dep: Implement auto-blocking state management
7. `0083ead` — dep: Implement incremental rebuild on read
8. `d5b50eb` — dep: Implement git issue ready command
9. `5d89481` — dep: Implement git issue topo command
10. `164b383` — dep: Implement git issue deps command with --dot output
11. `033d845` — dep: Write test suite for dependency features
12. `235ba00` — dep: Write benchmark harness for dependency performance

Run `git issue list` to see current state. Use `git issue show <id>` for full details.
When completing a task, run `git issue update <id> --state=done`.

### Design Decisions (settled)

- **Four relationship types:** blocks, depends_on, parent_of, relates_to
- **Storage:** Comma-separated values in issue front-matter headers (source of truth)
- **Edge index:** Derived graph at `refs/notes/dep-graph`, eagerly maintained on writes, incrementally rebuilt on reads by diffing modified notes since last rebuild
- **Topological sort:** POSIX `tsort` — no custom algorithm
- **Auto-blocking:** `dep add A blocks B` sets B to `blocked`; marking A `done` auto-unblocks B if no other blockers remain
- **Output:** Text tree + `ready` command + `topo` command + `--dot` flag for Graphviz DOT export
- **Cycle detection:** Via `tsort` stderr (free with POSIX tsort)

### Architecture Notes

- Main script: `bin/git-issue` (~1400 lines bash)
- Issue data: YAML-like front matter in git notes at `refs/notes/issue-<id>`
- Field parsing: `grep "^field:" | cut -d' ' -f2-` — no structured YAML parser
- `update_issue()` has an allowlist of valid fields — new dep fields must be added
- The `blocked` state already exists but is currently manual-only
- Tests: `tests/` directory, bash test framework in `tests/test_runner.sh`

### Commands

```bash
# View current issues
./bin/git-issue list

# Show issue details
./bin/git-issue show <id>

# Update issue state
./bin/git-issue update <id> --state=done

# Run tests
make test-unit
make test-integration
make test-all
```
