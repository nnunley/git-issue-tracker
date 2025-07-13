# git-issue: Git-Native Issue Tracking

A lightweight, git notes-based issue tracking CLI that integrates seamlessly with existing git workflows using hash-based IDs.

## 🎯 Features

- ✅ **No external dependencies** (just git and bash)
- ✅ **Git-native hash IDs** (e.g., `a064d35` - looks like commit hashes)
- ✅ **Zero conflicts** - globally unique identifiers
- ✅ **Fully versioned** and auditable via git notes
- ✅ **Works offline** - no server required
- ✅ **Native git integration** - works as `git issue` subcommand
- ✅ **Commit linking** - bidirectional issue-commit relationships
- ✅ **XDG directory support** - works outside git repositories
- ✅ **Comprehensive testing** - unit, integration, and CI/CD tests

## 🚀 Quick Start

### Installation

**Dependencies:** `jq` (for GitHub integration)

```bash
# Install dependencies
brew install jq  # macOS
# apt-get install jq  # Ubuntu/Debian

# Install git-issue
./install-git-issue.sh

# Or manually copy to PATH
cp bin/git-issue /usr/local/bin/
cp bin/git-issue-status /usr/local/bin/
cp bin/gh-to-git-issue /usr/local/bin/  # GitHub integration
```

### Basic Usage

```bash
# Create issues (auto-generates hash IDs)
git issue create "Fix navbar responsive design" --description="Navbar overlaps content on mobile devices"
# ✓ Created issue #a064d35: Fix navbar responsive design

# List all issues
git issue list

# Update issue state and description
git issue update a064d35 --state=in-progress --description="Updated requirements after review"

# Add comments
git issue comment a064d35 "Started responsive breakpoint work"

# Link to commits
git commit -m "Fix navbar mobile layout"
git issue link a064d35 HEAD

# View issue details (shows description, state, etc.)
git issue show a064d35

# Setup automatic sync with remotes
git issue setup-sync enable

# Status overview
git issue-status
```

## 📋 Commands

| Command | Description |
|---------|-------------|
| `git issue create <title> [--description=<desc>]` | Create new issue (auto-generates hash ID) |
| `git issue list` | List all issues |
| `git issue show <id>` | Show issue details |
| `git issue update <id> [--state=<state>] [--priority=<priority>] [--assignee=<assignee>] [--description=<desc>]` | Update issue with git-style flags |
| `git issue comment <id> <text>` | Add comment to issue |
| `git issue link <id> <commit>` | Link issue to commit |
| `git issue setup-sync [enable\|disable\|status]` | Configure automatic git notes sync |
| `git issue-status` | Show status summary |

### States
- `open` - New issue
- `in-progress` - Being worked on
- `review` - Under review
- `done` - Completed
- `blocked` - Blocked by dependencies

### Priorities
- `low` - Nice to have
- `medium` - Standard priority
- `high` - Important
- `critical` - Urgent

## 🔗 Git Integration

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

## 🎯 Why Hash-Based IDs?

Traditional issue trackers use sequential numbers (`#47`, `#48`) which create conflicts in distributed environments. git-issue uses git-style hash IDs:

- **Familiar to developers** - looks like commit hashes (`a064d35`)
- **Zero conflicts** - globally unique via content hashing
- **Git-native** - leverages git's proven hash system
- **Optimal length** - 7 characters (shorter than UUIDs, longer than sequential)

## 🛠️ How It Works

git-issue stores issues as git notes with structured data:

```yaml
id: a064d35
title: Fix navbar responsive design
description: Navbar overlaps content on mobile devices below 768px
state: in-progress
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
- Uses git notes in current repository
- Fully integrated with git workflow
- Issues sync with git remotes
- Supports automatic sync via git hooks

**XDG Directory** (fallback when no git repo):
- Creates bare git repository in `$XDG_DATA_HOME/git-issue/$(project).git`
- Same git notes format and commands
- Isolated per-project issue tracking

## 🔄 Automatic Synchronization

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

**Manual sync (if auto-sync disabled):**
```bash
# Fetch issue notes from remote
git fetch origin 'refs/notes/*:refs/notes/*'

# Push issue notes to remote  
git push origin 'refs/notes/issue-*'
```

## 🔗 GitHub Integration

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
state: open
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
git issue update a064d35 --state=in-progress

# Export changes back to GitHub (manual process)
git issue export --github a064d35 | gh issue create --body-file -
```

## 📚 Documentation

- [Git Notes Workflow](docs/GIT_NOTES_WORKFLOW.md) - Understanding git notes integration
- [Issue-Commit Linking](docs/ISSUE_COMMIT_LINKING.md) - Bidirectional linking system
- [Demo](examples/hash-issue-demo.md) - Complete usage examples

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test
4. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details.

## 🙏 Acknowledgments

- Inspired by git's distributed philosophy
- Built for developers who live in the terminal
- Designed to feel like a native git feature

---

**git-issue: Because issue tracking should be as distributed as your code.** 🚀