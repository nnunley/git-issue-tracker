# draft-ndn-multi-project-registry-01: Multi-Project Registry for git-issue

**Status:** DRAFT
**Category:** Standards-Track
**Authors:** Norman Nunley, Jr <nnunley@gmail.com>, Claude (drafting agent)
**Date:** 2026-08-14

## Abstract

git-issue operates on one repository at a time, discovered from the working
directory. This RFC adds a global registry of named, git-issue-managed
repositories stored in global git config, three management commands
(`git issue repo add|list|rm`), a `--repo <name>` flag that targets any
registered repository from anywhere, and `--all` aggregation for `list` and
`ready` across every registered repository.

## Motivation

Working across several git-issue-managed projects today means `cd`-ing into
each and running commands separately; nothing records which repositories are
managed at all. For one or more humans collaborating with one or more
agents, that discovery gap is the sharper problem: an agent cannot answer
"what should I work on next, anywhere?" or "is this repository tracked?"
without a registry. The design follows the pattern of an explicit
`repo add <name> <path>` registration command, so the CLI and any agent can
see where git-issue is — or is not — set up.

## Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174)
when, and only when, they appear in all capitals, as shown here.

- **registry** — the set of `issue.repo.<name>.path` entries in global git
  config.
- **registered repository** — a directory named by a registry entry;
  either backend (git repository or XDG-managed directory) qualifies.
- **target repository** — the registered repository selected by `--repo`.

## Specification

### Storage

The registry lives in global git config under keys of the form
`issue.repo.<name>.path`. Registration MUST write through `git config
--global`; no other storage exists. [R-config-store] Agents and tooling read
the registry with stock git, with no git-issue binary involved.

```transcript @R-config-store
$ git issue repo add tracker /Users/ndn/development/git-issue-tracker
Registered 'tracker' -> /Users/ndn/development/git-issue-tracker
$ git config --global --get-regexp '^issue\.repo\.'
issue.repo.tracker.path /Users/ndn/development/git-issue-tracker
```

### Names

Registry names conform to `repo-name` in the Formal Grammar. `repo add`
MUST reject nonconforming names. [R-name-charset]

<!-- evidence: @R-name-charset -->
| input      | valid |
|------------|-------|
| tracker    | yes   |
| api-v2     | yes   |
| a_b        | yes   |
| Api        | no    |
| a.b        | no    |
| a b        | no    |
| (empty)    | no    |

### repo add

`repo add <name> <path>` MUST reject a name that is already registered.
[R-reject-duplicate] `repo add --force <name> <path>` MUST replace the
existing entry and MUST report both the old and new path, so a rebinding is
never silent. [R-force-replace] The stored path MUST be absolute; a
relative `<path>` argument is resolved against the current working
directory at registration time. [R-abs-path]

Issue refs belong to the repository, not to any particular checkout: when
`<path>` is a linked secondary working copy, registration MUST resolve and
store the primary working copy instead, and MUST report the substitution.
For git this means a linked worktree resolves to the main worktree (per
`git worktree list`); other multi-workspace systems layered on git (e.g.
jj workspaces) resolve through the same git-level rule. [R-worktree-root]

```transcript @R-worktree-root
$ git issue repo add fix /Users/ndn/development/proj/.worktrees/fix-123
Registered 'fix' -> /Users/ndn/development/proj (main worktree of the given path)
```

```transcript @R-reject-duplicate
$ git issue repo add tracker /elsewhere
Error: 'tracker' is already registered (-> /Users/ndn/development/git-issue-tracker); use --force to replace
```

```transcript @R-force-replace
$ git issue repo add --force tracker /elsewhere
Registered 'tracker' -> /elsewhere (replaced /Users/ndn/development/git-issue-tracker)
```

```transcript @R-abs-path
$ cd /Users/ndn/development && git issue repo add brain ./brain
Registered 'brain' -> /Users/ndn/development/brain
```

### repo list

`repo list` MUST print every registry entry with its path, and MUST mark
entries whose path no longer exists rather than omitting or failing on
them. [R-list-missing]

```transcript @R-list-missing
$ git issue repo list
tracker  /Users/ndn/development/git-issue-tracker
brain    /Users/ndn/development/brain
old      /Users/ndn/gone  (missing)
```

### repo rm

`repo rm <name>` MUST remove the entry and MUST leave the repository's
contents untouched — it forgets, never deletes. [R-repo-rm]

```transcript @R-repo-rm
$ git issue repo rm old
Removed 'old' (repository contents untouched)
$ git issue repo list
tracker  /Users/ndn/development/git-issue-tracker
brain    /Users/ndn/development/brain
```

### repo prune

`repo prune` MUST remove exactly the entries whose path does not exist,
MUST report each removal by name and path, and MUST NOT touch entries whose
path exists. [R-prune] Pruning is the only bulk registry mutation; no other
command removes entries as a side effect.

```transcript @R-prune
$ git issue repo prune
Pruned 'old' (/Users/ndn/gone)
$ git issue repo list
tracker  /Users/ndn/development/git-issue-tracker
brain    /Users/ndn/development/brain
```

### Targeting: --repo

`--repo <name>` MUST run the given command in the target repository exactly
as if invoked from that directory, with both storage backends supported by
the normal per-directory detection. [R-target-repo] An unknown name or a
registered-but-missing path MUST produce an error naming the problem, with
a nonzero exit. [R-target-invalid]

```transcript @R-target-repo
$ cd /tmp && git issue --repo tracker list
#43c456e [open] Multi-project registry: repo add/list/rm, --repo, --all (P: medium)
```

```transcript @R-target-invalid
$ git issue --repo nosuch list
Error: 'nosuch' is not a registered repository (see: git issue repo list)
$ git issue --repo old list
Error: 'old' points to /Users/ndn/gone, which does not exist
```

### Aggregation: --all

`list --all` and `ready --all` MUST run against every registry entry and
prefix each output line with `[<name>] `. [R-all-prefix] A failing entry
(missing path, broken repository) MUST NOT abort the sweep: remaining
entries are still processed, failures are summarized at the end, and the
exit status is nonzero if any entry failed. [R-all-continues]

```transcript @R-all-prefix
$ git issue ready --all
[tracker] #48137e7 [open]  Implement git issue export --beads  (P: medium)
[brain]   #a11ce55 [open]  Fix sync race  (P: high)
```

```transcript @R-all-continues
$ git issue list --all
[tracker] #43c456e [open] Multi-project registry: repo add/list/rm, --repo, --all (P: medium)
Warning: skipped 'old': /Users/ndn/gone does not exist
```

### Execution model (informative)

Each targeted or aggregated repository is served by its own subprocess
(`cd <path>` + exec): the script's state — `GIT_DIR`, caches, the compiled
status machine — is process-global, so one-process-per-repository is the
isolation seam. Aggregation is sequential; parallelism is out of scope.

## Formal Grammar

```abnf
registry-key = %s"issue.repo." repo-name %s".path"
repo-name    = 1*63( lower / DIGIT / "-" / "_" )
lower        = %x61-7A
```

Witnesses for `repo-name` are the evidence table under Names.

## Alternatives Considered

### XDG registry file

A `repos.conf` under XDG config. Rejected: introduces a parser and a sync
story that git config already provides, and agents would need git-issue
installed just to read the registry.

### Registry as a git repository

A bare repository whose contents are the registry, syncable by push/pull.
Rejected as the heaviest option; revisitable if registry sync across
machines becomes a requirement.

### Case-folding names instead of rejecting them

Accepting `Api` and registering it as `api` (case-insensitive input,
canonical lowercase storage). Names sit in git config's subsection
position, which is case-sensitive — `issue.repo.Api.path` and
`issue.repo.api.path` verifiably coexist as distinct keys — so unrestricted
case admits confusable twins, and folding papers over that at the cost of a
normalization rule whose behavior users must learn implicitly. Rejected in
favor of strict rejection: an explicit error is preferred over input that
"works" while silently associating a differently-spelled name with a
project. [R-name-charset] is therefore strict.

### Automatic registration

Registering any repository the tool touches. Rejected: surprise writes to
global config, and the registry stops being a statement of intent —
explicit `repo add` came out of the original design conversation.

## Security Considerations

Targeting executes with the working directory set to a path taken from
user-editable global config. That is a real trust boundary, bounded as
follows: `~/.gitconfig` is owner-writable, and an attacker who can edit it
already controls git itself (aliases, core.pager, hooks path), so this adds
surface only in kind, not in privilege. Two consequences still deserve
care. First, entering a repository executes that repository's git
configuration and, transitively, its hooks on git operations — registering
untrusted paths is the risk, and `repo add` is deliberately explicit for
that reason. Second, `--all` visits every entry in one sweep, so one
carelessly registered path exposes each sweep to that repository's
configuration; the failure-isolation requirement [R-all-continues] limits
blast radius to reporting, not execution. Registry contents (project names
and filesystem paths) are as readable as the user's global git config;
paths that are themselves sensitive do not belong in it.

## Compatibility

Absent any registry entries, behavior is unchanged — detection from the
working directory proceeds exactly as today, and no command writes registry
state without an explicit `repo` subcommand. Both storage backends are
registrable. Removing the feature later would strand only
`issue.repo.*` config entries, which are inert to git and to git-issue
alike.

## References

- Design record: `docs/plans/2026-08-13-modularization-refactor-design.md`
  (sub-project 2) and tracker issue `43c456e`.
- git-config(1) — storage substrate and access semantics.
- BCP 14 (RFC 2119, RFC 8174); RFC 5234/7405 (ABNF).

## Changelog

- 2026-08-13: Requirements interview conducted (storage, scope, mechanism,
  registration policy); design synthesis approved with the refactor spec.
- 2026-08-14: draft-00 created.
- 2026-08-14: name-case question raised in review; strict rejection
  confirmed over case-folding (recorded under Alternatives Considered).
- 2026-08-14 (rev -01): author-call interview concluded. Added
  `repo add --force` replacement [R-force-replace] (chosen over rm-then-add
  with the rebinding risk noted and accepted; mitigated by mandatory
  old->new reporting) and `repo prune` [R-prune] (explicit bulk cleanup of
  missing entries, keeping list/--repo semantics as drafted). `--all`
  failure behavior confirmed as drafted (continue + summarize + nonzero).
- 2026-08-14 (rev -01): worktree refinement — registering a linked working
  copy resolves to the primary [R-worktree-root]; issue refs are
  per-repository and worktree paths are transient.
