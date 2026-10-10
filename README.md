# git-issue

Issue tracking that lives in your git repository, beside the code. Each issue is a small document stored under its own ref (`refs/notes/issue-<id>`) and named by a short hash id such as `a064d35`, so issues work offline, travel with `git push` and `git fetch`, and never collide the way sequential numbers do. It runs as `git issue`, needs only git, bash and (for GitHub import and export) jq, and falls back to a per-project repository under `$XDG_DATA_HOME` when you are not in a git repository.

## Features

- **No external dependencies** (just git and bash)
- **Git-native hash IDs** (e.g., `a064d35` - looks like commit hashes)
- **Zero conflicts** - globally unique identifiers
- **Fully versioned** and auditable via git notes
- **Works offline** - no server required
- **Native git integration** - works as `git issue` subcommand
- **Commit linking** - bidirectional issue-commit relationships
- **XDG directory support** - works outside git repositories
- **Dependency graph** - blocking, cycle detection, topological sort, Graphviz export
- **Comprehensive testing** - unit, integration, and CI/CD tests

## Quick Start

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


## How it works

An issue is a header of fields (title, status, priority, assignee, role, dependencies) followed by a description and comments. Each edit is a commit on that issue's ref, so every issue has its full history in git. `git issue setup-sync enable` installs hooks that push and fetch the issue refs along with your branches. The details are in [How git-issue works](docs/design.md).

## Documentation

- [User Guide](docs/user-guide.md): a task-oriented walkthrough of the command line
- [Reference](docs/reference.md): every command, the statuses and priorities, the dependency graph, the multi-project registry, machine-readable output, sync, and GitHub import and export
- [How git-issue works](docs/design.md): the storage model and why ids are hashes
- [Emacs Guide](docs/emacs-guide.md): setup, keys and workflows for the magit integration
- [AI integration](docs/mcp.md): the MCP server
- [RFCs](docs/rfc/index.md): the contracts for the multi-project registry, porcelain output and the magit integration
- [Git Notes Workflow](docs/GIT_NOTES_WORKFLOW.md) and [Issue-Commit Linking](docs/ISSUE_COMMIT_LINKING.md): linking issues and commits
- [Demo](examples/hash-issue-demo.md): a complete usage example

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test
4. Submit a pull request


## License

MIT License - see LICENSE file for details.


## Acknowledgments

- Inspired by git's distributed philosophy
- Built for developers who live in the terminal
- Designed to feel like a native git feature

---

**git-issue: Because issue tracking should be as distributed as your code.**
