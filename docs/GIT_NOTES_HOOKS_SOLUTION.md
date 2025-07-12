# Git Notes Synchronization with Hooks

Solutions for automatically syncing git notes using git hooks to eliminate the manual push/pull problem.

## 🎯 Problem Summary

Git notes don't automatically sync with regular git operations. This creates issues:
- Notes exist locally but aren't shared with team
- Team members miss issue updates and commit annotations
- Manual `git push refs/notes/*` commands are easily forgotten
- Notes can become out of sync across repositories

## 🔧 Hook-Based Solutions

### Solution 1: Automatic Notes Push (Recommended)

**Pre-push Hook** - Automatically push notes whenever commits are pushed:

```bash
#!/bin/bash
# .git/hooks/pre-push

# Get the remote and URL being pushed to
remote="$1"
url="$2"

echo "🔄 Syncing git notes..."

# Push all notes refs to the same remote
git push "$remote" refs/notes/*:refs/notes/* 2>/dev/null || {
    echo "⚠️  Note: Some notes refs failed to push (this is normal for new repos)"
}

echo "✅ Notes sync complete"
```

**Post-receive Hook** (Server-side) - Auto-pull notes on server:

```bash
#!/bin/bash
# .git/hooks/post-receive (on server/remote)

# This runs on the server when notes are pushed
while read oldrev newrev refname; do
    if [[ $refname =~ ^refs/notes/ ]]; then
        echo "📝 Received notes update for $refname"
        # Could trigger notifications, CI builds, etc.
    fi
done
```

### Solution 2: Automatic Notes Pull

**Post-merge Hook** - Pull notes after merging:

```bash
#!/bin/bash
# .git/hooks/post-merge

echo "🔄 Pulling latest notes..."

# Fetch notes from all remotes
for remote in $(git remote); do
    git fetch "$remote" refs/notes/*:refs/notes/* 2>/dev/null || true
done

echo "✅ Notes updated"
```

**Post-checkout Hook** - Pull notes when switching branches:

```bash
#!/bin/bash
# .git/hooks/post-checkout

# Only run on branch checkouts (not file checkouts)
if [ "$3" = "1" ]; then
    echo "🔄 Syncing notes for branch $2..."
    
    # Fetch latest notes
    git fetch origin refs/notes/*:refs/notes/* 2>/dev/null || true
    
    echo "✅ Notes synchronized"
fi
```

### Solution 3: Comprehensive Sync Solution

**Universal Notes Hook** - Handles both push and pull:

```bash
#!/bin/bash
# scripts/git-notes-sync.sh - Shared sync script

sync_notes() {
    local operation="$1"
    local remote="${2:-origin}"
    
    case "$operation" in
        "push")
            echo "📤 Pushing notes to $remote..."
            git push "$remote" refs/notes/*:refs/notes/* 2>/dev/null && \
                echo "✅ Notes pushed successfully" || \
                echo "⚠️  Some notes may not have pushed (normal for new repos)"
            ;;
        "pull")
            echo "📥 Pulling notes from $remote..."
            git fetch "$remote" refs/notes/*:refs/notes/* 2>/dev/null && \
                echo "✅ Notes pulled successfully" || \
                echo "⚠️  No notes to pull or connection failed"
            ;;
        "sync")
            sync_notes "pull" "$remote"
            sync_notes "push" "$remote"
            ;;
    esac
}

# Allow script to be called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sync_notes "$@"
fi
```

**Pre-push Hook using shared script:**

```bash
#!/bin/bash
# .git/hooks/pre-push

# Source the sync script
source "$(git rev-parse --show-toplevel)/scripts/git-notes-sync.sh"

# Auto-sync notes on push
sync_notes "push" "$1"
```

**Post-merge Hook using shared script:**

```bash
#!/bin/bash
# .git/hooks/post-merge

# Source the sync script  
source "$(git rev-parse --show-toplevel)/scripts/git-notes-sync.sh"

# Auto-sync notes on merge
sync_notes "pull"
```

### Solution 4: Configuration-Based Auto-Sync

**Setup Script** - Configure git to always sync notes:

```bash
#!/bin/bash
# scripts/setup-notes-sync.sh

echo "🔧 Setting up automatic git notes synchronization..."

# Configure git to automatically fetch notes
git config --add remote.origin.fetch '+refs/notes/*:refs/notes/*'

# Set default notes ref for display
git config notes.displayRef 'refs/notes/*'

# Configure notes merging strategy
git config notes.mergeStrategy 'cat_sort_uniq'

# Install hooks
HOOKS_DIR=".git/hooks"
SCRIPT_DIR="$(dirname "$0")"

# Copy hook scripts
cp "$SCRIPT_DIR/../docs/hooks/pre-push" "$HOOKS_DIR/pre-push"
cp "$SCRIPT_DIR/../docs/hooks/post-merge" "$HOOKS_DIR/post-merge"

# Make hooks executable
chmod +x "$HOOKS_DIR/pre-push" "$HOOKS_DIR/post-merge"

echo "✅ Git notes sync setup complete!"
echo ""
echo "Notes will now automatically:"
echo "  📤 Push when you push commits"
echo "  📥 Pull when you merge/fetch"
echo "  🔍 Display in git log"
```

### Solution 5: Smart Issue Tracker Integration

**Enhanced Issue Tracker with Auto-Sync:**

```bash
#!/bin/bash
# Enhancement to simple-issue-tracker.sh

# Add to the top of existing script
AUTO_SYNC=${GIT_ISSUE_AUTO_SYNC:-true}

auto_sync_notes() {
    if [[ "$AUTO_SYNC" == "true" ]]; then
        echo "🔄 Auto-syncing notes..."
        git push origin refs/notes/*:refs/notes/* 2>/dev/null || true
    fi
}

# Add after any operation that modifies notes
create_issue() {
    # ... existing code ...
    
    # Auto-sync after creating issue
    auto_sync_notes
}

update_issue() {
    # ... existing code ...
    
    # Auto-sync after updating issue  
    auto_sync_notes
}

# Add sync command
case "$1" in
    # ... existing commands ...
    sync)
        echo "🔄 Syncing all notes..."
        git fetch origin refs/notes/*:refs/notes/* 2>/dev/null || true
        git push origin refs/notes/*:refs/notes/* 2>/dev/null || true
        echo "✅ Sync complete"
        ;;
esac
```

## 🛠️ Implementation Plan

### Step 1: Create Hook Scripts

```bash
# Create hooks directory structure
mkdir -p docs/hooks

# Create the hook scripts (use examples above)
# Make them executable
chmod +x docs/hooks/*
```

### Step 2: Installation Script

```bash
#!/bin/bash
# scripts/install-git-notes-hooks.sh

echo "🔧 Installing git notes synchronization hooks..."

# Ensure hooks directory exists
mkdir -p .git/hooks

# Install hooks
cp docs/hooks/pre-push .git/hooks/pre-push
cp docs/hooks/post-merge .git/hooks/post-merge
cp docs/hooks/post-checkout .git/hooks/post-checkout

# Make executable
chmod +x .git/hooks/*

# Configure git for notes
git config --add remote.origin.fetch '+refs/notes/*:refs/notes/*'
git config notes.displayRef 'refs/notes/*'

echo "✅ Installation complete!"
```

### Step 3: Team Onboarding

```bash
#!/bin/bash
# scripts/setup-team-notes.sh

echo "👥 Setting up git notes for team collaboration..."

# Run installation
./scripts/install-git-notes-hooks.sh

# Initial sync
echo "📥 Performing initial notes sync..."
git fetch origin refs/notes/*:refs/notes/* 2>/dev/null || true

# Show current notes
echo "📝 Current notes in repository:"
git log --notes --oneline -5

echo "✅ Team setup complete!"
```

## 🎯 Recommended Approach

For your issue tracker, I recommend **Solution 1 + 5**:

1. **Pre-push hook** that auto-pushes notes
2. **Enhanced issue tracker** with auto-sync option
3. **Setup script** for easy team onboarding

This provides:
- ✅ **Automatic synchronization** 
- ✅ **Team collaboration** support
- ✅ **Backwards compatibility** (can be disabled)
- ✅ **Easy setup** for new repositories

## 🔄 Benefits of Hook-Based Solution

### ✅ **Advantages**
- **Invisible to users** - works automatically
- **No workflow changes** - keeps existing git habits
- **Team-friendly** - everyone stays in sync
- **Configurable** - can be enabled/disabled per repo
- **Reliable** - triggers on actual git operations

### ⚠️ **Considerations**
- **Hook management** - needs installation on each clone
- **Network dependencies** - push/pull operations require connection
- **Merge conflicts** - notes can still conflict (but hooks can handle this)
- **Performance** - slight delay on push/pull operations

## 📚 Additional Features

### Conflict Resolution
```bash
# In post-merge hook
if git notes merge refs/notes/commits 2>/dev/null; then
    echo "✅ Notes merged successfully"
else
    echo "⚠️  Notes merge conflicts detected"
    echo "Run: git notes merge --abort"
    echo "Or: git notes merge --strategy=theirs refs/notes/commits"
fi
```

### Selective Sync
```bash
# Only sync issue notes, not commit notes
git push origin refs/notes/issue-*:refs/notes/issue-*
```

### Notification Integration
```bash
# In post-receive hook (server-side)
if [[ $refname =~ ^refs/notes/issue- ]]; then
    # Extract issue ID and send notification
    issue_id="${refname#refs/notes/issue-}"
    echo "📬 Notifying team about issue #$issue_id update..."
    # Call Slack webhook, email, etc.
fi
```

With hooks, git notes become as seamless as regular git operations! 🚀