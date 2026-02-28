# Status Rename, Homebrew, and Release Design

## Goal

Rename the `state` field to `status` with Beads-aligned values, fix the Homebrew formula, tag a v1.0.0-rc1 release, and publish a homebrew tap.

## Architecture

Three coordinated changes ship together: a field/value rename across the entire codebase, a one-time data migration for existing issues, and release packaging (GitHub release + Homebrew tap).

## Field & Value Rename

**Field:** `state` → `status` in stored data, CLI flags, output, tests, and docs.

**Flag:** `--state=` → `--status=`. Hard break, no backward compatibility.

**Values:**

| Old | New |
|-----|-----|
| `open` | `open` |
| `in-progress` | `in_progress` |
| `review` | `review` |
| `done` | `closed` |
| `blocked` | `blocked` |
| _(new)_ | `deferred` |

**Read compatibility:** Field extraction accepts both `state:` and `status:` when reading stored data, so un-migrated issues still load. All writes use `status:`.

**Color mapping:** `closed` → gray (was `done`), `deferred` → yellow.

**Scope:** ~200 occurrences across `bin/git-issue`, `bin/git-issue-status`, 7 test files, README, and docs.

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

1. State→status rename (code, tests, docs)
2. Migration command implementation
3. Run migration on this repo's issues
4. Tag v1.0.0-rc1, create GitHub release
5. Update formula with release tarball URL + sha256
6. Create homebrew-tap repo, push formula
7. Verify brew install end to end
