# Agentic Roles Design

Use the issue tracker as a coordination bus between agents. Different agent
types (coders, reviewers) poll their queue for work, act on issues, then
transition status to hand off to the next agent.

## Role Field

A new `role` header field on issues, stored alongside `assignee`:

```
id: a1b2c3d
title: Fix navbar
status: review
priority: medium
role: reviewer
assignee: Alice
```

- Freeform string, no validation
- Empty by default on `create`
- Set via `git issue update <id> --role=<name>`
- Answers "what kind of agent should act on this?" (vs assignee = "which specific agent")

## Filtering: `ready --role` and `queue`

`git issue ready --role=<name>` filters the ready list to issues matching
the given role. Issues with no role are excluded when `--role` is specified.

`git issue queue <role>` is an alias for `ready --role=<role>`.

Both produce: unblocked, non-closed issues matching the role, sorted by
priority, then topologically within the same priority level.

`git issue ready` (no flag) remains unchanged -- shows all ready issues.

## Status Machine DSL Extension

Extend the transition syntax to optionally assign a role on transition:

```
# Existing syntax (unchanged)
transition: open -> in_progress

# New: assign role on transition
transition: in_progress -> review (role=reviewer)
transition: review -> in_progress (role=coder)
transition: review -> closed (role=)
```

`(role=)` clears the role. Omitting the parenthetical means "don't change
the role." Fully backward compatible.

The compiler generates a `transition_role()` function that returns the
target role for a given transition, or empty for "no change."

## Display

Role shown in listings as `[rolename]` before the assignee arrow:

```
#37f5aed [open]  Bootstrap Phase 2: Compiler Cutover  (P: high) [coder] -> Norman Nunley, Jr
```

When no role is set, output is unchanged from current format.

## Default and Beads Presets

Both presets remain unchanged -- no `(role=...)` on any transitions. Teams
opt into roles by customizing their `.git-issue/statuses` file and using
`--role=` on updates.

## Shortcut Commands

`start`, `close`, `reopen` set status only and do not directly touch the
role field. If the status machine has a transition rule with `(role=X)`,
the role is updated as a side effect of the transition.

## Summary

| Change                          | Description                                      |
|---------------------------------|--------------------------------------------------|
| New `role` header field         | Freeform string on issues, empty by default      |
| `update --role=<name>`          | Set/clear role on an issue                        |
| `ready --role=<name>`           | Filter ready list by role                         |
| `queue <role>`                  | Alias for `ready --role=<role>`                   |
| DSL: `(role=X)` on transitions  | Optional role assignment when status changes      |
| Compiler: `transition_role()`   | New compiled function for role lookup             |
| Display                         | Role shown as `[rolename]` before assignee arrow  |
| Default/Beads presets           | Unchanged -- no roles configured                  |
