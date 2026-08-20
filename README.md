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
- ✅ **Dependency graph** - blocking, cycle detection, topological sort, Graphviz export
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

# Update issue status and description
git issue update a064d35 --status=in_progress --description="Updated requirements after review"

# Add comments
git issue comment a064d35 "Started responsive breakpoint work"

# Link to commits
git commit -m "Fix navbar mobile layout"
git issue link a064d35 HEAD

# View issue details (shows description, status, etc.)
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
| `git issue update <id> [--status=<status>] [--priority=<priority>] [--assignee=<assignee>] [--description=<desc>]` | Update issue with git-style flags |
| `git issue statuses` | Show configured statuses and allowed transitions |
| `git issue comment <id> <text>` | Add comment to issue |
| `git issue link <id> <commit>` | Link issue to commit |
| `git issue setup-sync [enable\|disable\|status]` | Configure automatic git notes sync |
| `git issue dep add <from> <type> <to>` | Add dependency between issues |
| `git issue dep rm <from> <type> <to>` | Remove dependency |
| `git issue dep list [<id>]` | Show dependencies for an issue |
| `git issue dep rebuild` | Regenerate edge index |
| `git issue ready` | List issues with no open blockers |
| `git issue topo` | Topological ordering of issues |
| `git issue deps [<id>] [--dot]` | Dependency graph (text or Graphviz DOT) |
| `git issue repo add [--force] <name> <path>` | Register a repository in the global registry |
| `git issue repo list` | List registered repositories as `<name> <path>` |
| `git issue repo rm <name>` | Forget a repository (contents untouched) |
| `git issue repo prune` | Forget entries whose path no longer exists |
| `git issue-status` | Show status summary |

Two global options work with any command: `--repo <name>` runs it in a
registered repository, and `--all` sweeps `list` or `ready` across every
one. Both are accepted before or after the subcommand.

### Statuses
- `open` - New issue, not yet started
- `in_progress` - Actively being worked on
- `review` - Awaiting feedback or review
- `blocked` - Blocked by a dependency
- `deferred` - On hold, will revisit later
- `closed` - Completed or resolved

Statuses and their allowed transitions are configurable via `.git-issue/statuses`. Run `git issue statuses` to view the current configuration.

### Priorities
- `low` - Nice to have
- `medium` - Standard priority
- `high` - Important
- `critical` - Urgent

## Dependency Graph

Track relationships between issues with four dependency types:

| Type | Meaning | Blocking? |
|------|---------|-----------|
| `blocks` | Must complete before target can start | Yes |
| `depends_on` | Cannot start until dependency completes | Yes (inverse of blocks) |
| `parent_of` | Epic/parent containing sub-issues | No |
| `relates_to` | Informational link | No |

Dependencies are **bidirectional**: `dep add A blocks B` automatically sets `depends_on: A` on B.

```bash
# Add a dependency
git issue dep add a1b2c3d blocks d4e5f6a
# Auto-sets d4e5f6a to "blocked" status

# Remove a dependency
git issue dep rm a1b2c3d blocks d4e5f6a

# List dependencies for an issue
git issue dep list a1b2c3d

# Mark blocker closed — auto-unblocks dependents
git issue update a1b2c3d --status=closed

# List issues with no open blockers (ready to work on)
git issue ready

# Topological ordering of issues
git issue topo

# Dependency graph (text output)
git issue deps

# Subgraph from a specific issue
git issue deps a1b2c3d

# Graphviz DOT output (pipe to dot for visualization)
git issue deps --dot | dot -Tpng -o deps.png
```

**Key behaviors:**
- Blocked issues auto-transition to `blocked` status when a blocking dependency is added
- Marking a blocker `closed` cascades unblock to dependents
- Cycle detection via POSIX `tsort` prevents circular dependencies
- `dep rebuild` regenerates the edge index if it gets out of sync

## Multi-Project Registry

`git-issue` normally works on whatever repository you are standing in.
The registry names your repositories so you — or an agent — can reach any
of them from anywhere, and ask "what should I work on next, *anywhere*?"

```bash
# Register repositories (explicit: nothing is ever registered for you)
git issue repo add tracker ~/src/git-issue-tracker
git issue repo add api ~/src/api
# Registered 'tracker' -> /home/you/src/git-issue-tracker

# See what is tracked. Entries whose path is gone are shown, not hidden.
git issue repo list
# tracker /home/you/src/git-issue-tracker
# api /home/you/src/api

# Run any command against a registered repository, from anywhere
git issue --repo api list
git issue create "New bug" --repo api      # either flag position works

# Sweep every registered repository; each line is prefixed with its name
git issue ready --all
# [tracker] #a064d35 [open]  Fix navbar  (P: high)
# [api] #d4e5f6a [open]  Rate limiting  (P: medium)

# Forget a repository (this never deletes anything on disk)
git issue repo rm api
git issue repo prune          # drop entries whose path no longer exists
```

The registry is stored in your global git config as
`issue.repo.<name>.path`, so anything that can read git config can read
it without git-issue installed:

```bash
git config --global --get-regexp '^issue\.repo\.'
```

Names are lowercase letters, digits, `-` and `_`. A path that is a linked
worktree registers as its main worktree, since issue refs belong to the
repository rather than to a checkout. A sweep never stops at a broken
entry: it reports the skip on stderr, keeps going, and exits nonzero.

With no registry entries, behavior is exactly as before.

The full specification is
[`docs/rfc/draft-ndn-multi-project-registry-02.md`](docs/rfc/draft-ndn-multi-project-registry-02.md).

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
status: open
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
git issue update a064d35 --status=in_progress

# Export changes back to GitHub (manual process)
git issue export --github a064d35 | gh issue create --body-file -
```

## 📚 Documentation

- [Git Notes Workflow](docs/GIT_NOTES_WORKFLOW.md) - Understanding git notes integration
- [Issue-Commit Linking](docs/ISSUE_COMMIT_LINKING.md) - Bidirectional linking system
- [Demo](examples/hash-issue-demo.md) - Complete usage examples

## 🤖 AI Integration (MCP Server)

**Optional AI-powered features** via Model Context Protocol (MCP) - requires Node.js.

### Installation

```bash
# Install MCP server (requires Node.js 18+)
make install-mcp

# Or build manually
cd mcp && npm install && npm run build
npm install --global
```

### Claude Desktop Integration

Add to your Claude Desktop configuration (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "git-issue": {
      "command": "git-issue-mcp-server"
    }
  }
}
```

### AI-Powered Features

Once configured, you can ask Claude to:

- **Analyze issue complexity**: "Analyze the complexity of issue abc123"
- **Suggest next tasks**: "What should I work on next based on my current issues?"
- **Create issues from descriptions**: "Create an issue for implementing user authentication"
- **Get project insights**: "Give me an overview of my project's current status"
- **Prioritize work**: "Help me prioritize these open issues"

### Available MCP Tools

| Tool | Description |
|------|-------------|
| `create_issue` | Create new issues with AI-guided structure |
| `list_issues` | List and filter issues |
| `show_issue` | Get detailed issue information |
| `update_issue` | Update issue properties |
| `get_project_status` | Project health and metrics |
| `get_issue_context` | Rich context for AI analysis |

### Example AI Workflow

```
You: "Analyze my current project and suggest what I should work on next"

Claude: I'll check your project status and analyze your issues.
[Uses get_project_status and list_issues tools]

Based on your project, I can see you have:
- 3 critical priority issues 
- 2 issues currently blocked
- 1 issue in review

I recommend focusing on issue abc123 "Fix authentication bug" because:
- It's marked critical priority
- It's blocking 2 other issues
- Based on the description, it appears to be a focused fix

Would you like me to create a detailed plan for tackling this issue?
```

### MCP Commands

```bash
# Test MCP server
make test-mcp

# Rebuild after changes
make build-mcp

# Remove MCP server
make uninstall-mcp
```

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