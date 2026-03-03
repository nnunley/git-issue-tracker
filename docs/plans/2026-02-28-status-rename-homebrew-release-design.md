# Status Rename, Homebrew, and Release Design

## Goal

Rename the `state` field to `status` with configurable status values driven by a state machine definition file, fix the Homebrew formula, tag a v1.0.0-rc1 release, and publish a Homebrew tap.

## Architecture

Four coordinated changes: (1) a state machine definition file with compiler, (2) field/value rename across the codebase to use the compiled definitions, (3) one-time data migration for existing issues, and (4) release packaging (GitHub release + Homebrew tap).

## State Machine File

**Location:** `.git-issue/statuses` (per-project, human-editable source of truth)

**Auto-created** on first `git issue` command if it doesn't exist.

**Format:**
```
mode: permissive

status: open        | default | New issue, not yet started
status: in_progress | yellow  | Actively being worked on
status: review      | blue    | Awaiting feedback or review
status: blocked     | red     | Blocked by a dependency
status: deferred    | yellow  | On hold, will revisit later
status: closed      | gray    | Completed or resolved

transition: open → in_progress
transition: open → blocked
transition: open → deferred
transition: open → closed
transition: in_progress → review
transition: in_progress → blocked
transition: in_progress → deferred
transition: in_progress → closed
transition: review → in_progress
transition: review → closed
transition: blocked → open
transition: blocked → in_progress
transition: deferred → open
transition: deferred → in_progress
transition: closed → open
```

**Compiled output:** `.git-issue/statuses.bash` (auto-generated, sourced at runtime)

Contains:
- `STATUSES` array
- `STATUS_MODE` variable
- `status_color()` — case statement mapping status → color name
- `status_description()` — case statement mapping status → human description
- `validate_transition()` — case statement returning 0 for valid, 1 for invalid

**Compilation trigger:** On startup, if `.git-issue/statuses.bash` is missing or older than `.git-issue/statuses`, recompile automatically.

**Presets:** Shipped in `share/git-issue/`:
- `statuses.default` — open, in_progress, review, blocked, deferred, closed
- `statuses.beads` — open, in_progress, blocked, deferred, closed (no review)

**Enforcement modes:**
- `strict` — invalid transitions are rejected with an error
- `permissive` — invalid transitions print a warning but proceed

## Field & Value Rename

**Field:** `state` → `status` in stored data, CLI flags, output, tests, and docs.

**Flag:** `--state=` → `--status=`. Hard break, no backward compatibility.

**Values (default preset):**

| Old | New |
|-----|-----|
| `open` | `open` |
| `in-progress` | `in_progress` |
| `review` | `review` |
| `done` | `closed` |
| `blocked` | `blocked` |
| _(new)_ | `deferred` |

**Read compatibility:** Field extraction accepts both `state:` and `status:` when reading stored data, so un-migrated issues still load. All writes use `status:`.

**Validation and color mapping:** Driven by the compiled statuses.bash instead of hardcoded arrays.

## Migration

A `git issue migrate-status` subcommand that:

1. Iterates all `refs/notes/issue-*`
2. Reads each issue's raw blob data
3. Replaces `state:` line with `status:`
4. Maps values: `in-progress` → `in_progress`, `done` → `closed`
5. Writes back via `write_issue_data`
6. Reports count of migrated issues

Run once on this repo after code changes land.

## Homebrew Formula

- Update version from `1.0.0-dev` to `1.0.0-rc1`
- After tagging, add `url` pointing to release tarball and `sha256` checksum
- Install preset files to `share/git-issue/`
- Formula already has correct install block and test block from earlier fixes

## GitHub Release

- Tag `v1.0.0-rc1` on main after all changes are committed and CI is green
- Create GitHub release via `gh release create v1.0.0-rc1`
- Download tarball, compute sha256, update formula

## Homebrew Tap

- Create `nnunley/homebrew-git-issue` repo on GitHub
- Copy validated formula there
- Verify `brew tap nnunley/git-issue && brew install git-issue` works end to end

## Ordering

1. Create state machine definition file and compiler
2. Create preset files (default, beads)
3. Integrate compiler into git-issue startup (replace hardcoded STATES array)
4. State→status rename (code, tests, docs)
5. Migration command implementation
6. Run migration on this repo's issues
7. Tag v1.0.0-rc1, create GitHub release
8. Update formula with release tarball URL + sha256
9. Create homebrew-tap repo, push formula
10. Verify brew install end to end
