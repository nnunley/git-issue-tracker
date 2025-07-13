# Git Notes Workflow

This document explains how git-issue uses git notes to annotate commits with issue tracking information.

## Overview

Git notes allow adding metadata to commits without modifying the commits themselves. git-issue uses them to:

1. **Track Issues**: Link commits to issues
2. **Document Context**: Record implementation decisions  
3. **Add Notes**: Note remaining work or follow-ups
4. **Track Dependencies**: Link related commits or features

## Quick Start

### Using git-issue Commands

```bash
# Link a commit to an issue (automatically adds git note)
git issue link 102 HEAD

# View issue details (shows linked commits)
git issue show 102

# List all issues with commit links
git issue list
```

### Manual Git Notes Commands

```bash
# Add a note to the last commit
git notes add -m "Issue: #102
Thoughts: Implemented basic session tracking
TODO: Add timeout handling"

# View notes in git log
git log --notes

# Edit existing note
git notes edit HEAD

# Copy note from one commit to another
git notes copy abc123 def456
```

## Note Format

We use a structured format for consistency:

```
Issue: #<issue-number> [or 'Multiple: #102,#103' or 'None']
Thoughts: <implementation decisions and context>
TODO: <remaining work>
Dependencies: <related commits or features>
Date: <timestamp>
Author: <developer name>
```

## Best Practices

1. **Add notes during development**: Don't wait until PR time
2. **Be specific**: Include enough context for future reference
3. **Link issues**: Always reference the related GitHub issue(s)
4. **Document decisions**: Explain why, not just what
5. **Update notes**: Use append to add new information

## Examples

### Single Issue Link
```bash
git issue link 103 HEAD
git issue comment 103 "Implemented RBAC middleware with role hierarchy"
```

### Multiple Issues
```bash
git issue link 103 HEAD
git issue link 211 HEAD
git issue comment 103 "RBAC implementation affects user admin pages"
```

### Complex Note with Manual Edit
```bash
git notes add HEAD
# Then in editor:
Issue: #102 (Session Management)
Thoughts: 
- Implemented Redis-based session store
- Added activity tracking for idle timeout
- Integrated with existing Supabase auth
TODO:
- Add session analytics
- Implement concurrent session limits
Dependencies: Requires Redis service
```

## Viewing Notes

### In Git Log
```bash
# Show recent commits with notes
git log --oneline --notes -10

# Show only commits that have notes
git log --notes --grep="Issue:" --all
```

### In GitHub
Notes are pushed with: `git push origin refs/notes/commits`

However, GitHub doesn't display notes in the UI by default.

## Syncing Notes

### Fetch notes from remote
```bash
git fetch origin refs/notes/commits:refs/notes/commits
```

### Push notes to remote
```bash
git push origin refs/notes/commits
```

### Configure automatic note syncing
```bash
# Add to .git/config or global config
git config --add remote.origin.fetch +refs/notes/commits:refs/notes/commits
git config notes.displayRef refs/notes/commits
```

## Tips

1. **Notes persist through rebases**: Unlike commit messages, notes survive rebasing
2. **Notes are searchable**: Use `git log --notes --grep="pattern"`
3. **Notes can be scripted**: Useful for automation and reporting
4. **Multiple note refs**: Can have different categories (e.g., refs/notes/issues, refs/notes/reviews)

## Integration Ideas

- Generate release notes from issue annotations
- Create audit trails for compliance
- Track technical debt with TODO notes
- Link commits to documentation updates
- Record performance impact notes

Remember: Git notes are a powerful way to add context without cluttering commit messages!