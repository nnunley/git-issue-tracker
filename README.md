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

## 🚀 Quick Start

### Installation

```bash
# Install git-issue
./install-git-issue.sh

# Or manually copy to PATH
cp bin/git-issue /usr/local/bin/
cp bin/git-issue-status /usr/local/bin/
```

### Basic Usage

```bash
# Create issues (auto-generates hash IDs)
git issue create "Fix navbar responsive design"
# ✓ Created issue #a064d35: Fix navbar responsive design

# List all issues
git issue list

# Update issue state
git issue update a064d35 state in-progress

# Add comments
git issue comment a064d35 "Started responsive breakpoint work"

# Link to commits
git commit -m "Fix navbar mobile layout"
git issue link a064d35 HEAD

# View issue details
git issue show a064d35

# Status overview
git issue-status
```

## 📋 Commands

| Command | Description |
|---------|-------------|
| `git issue create <title>` | Create new issue (auto-generates hash ID) |
| `git issue list` | List all issues |
| `git issue show <id>` | Show issue details |
| `git issue update <id> <field> <value>` | Update issue (state/priority/assignee) |
| `git issue comment <id> <text>` | Add comment to issue |
| `git issue link <id> <commit>` | Link issue to commit |
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
state: in-progress
priority: medium
created: 2025-07-12T16:57:31Z
updated: 2025-07-12T16:57:50Z
author: Norman Nunley, Jr
assignee: 
hash_source: content
---

[2025-07-12T16:57:56Z] Norman Nunley, Jr: Started responsive breakpoint work
```

## 📚 Documentation

- [Git Notes Workflow](docs/GIT_NOTES_WORKFLOW.md) - Understanding git notes
- [Issue-Commit Linking](docs/ISSUE_COMMIT_LINKING.md) - Bidirectional linking system
- [Merge Strategy](docs/GIT_NOTES_MERGE_STRATEGY.md) - Conflict resolution
- [Hash-Based IDs](docs/GIT_HASH_ISSUE_IDS.md) - ID generation and collision handling
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