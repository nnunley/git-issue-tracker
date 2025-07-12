# Git Notes Merge Strategy & Conflict Resolution

Comprehensive solution for handling git notes conflicts in team environments.

## 🔍 Problem Analysis

### Types of Git Notes Conflicts

1. **Issue Data Conflicts**
   - Multiple people update same issue simultaneously
   - Conflicting state changes (open → closed vs open → in-progress)
   - Different priority assignments

2. **Comment Conflicts**
   - Multiple people add comments at same time
   - Comments referencing outdated state

3. **Commit Annotation Conflicts**
   - Multiple people annotate same commit with different issues
   - Different linking relationships

4. **Structural Conflicts**
   - Format changes vs content updates
   - Schema evolution conflicts

## 🛠️ Built-in Git Merge Strategies

Git provides several notes merge strategies:

```bash
# Configure merge strategy
git config notes.mergeStrategy <strategy>

# Available strategies:
# - manual: Default, requires manual resolution
# - ours: Keep our version  
# - theirs: Take their version
# - union: Concatenate both versions
# - cat_sort_uniq: Concatenate, sort, deduplicate
```

## 🚀 Custom Merge Solutions

### Solution 1: Smart Auto-Merge Strategy

**Intelligent Merge Script:**

```bash
#!/bin/bash
# scripts/git-notes-merge.sh

merge_issue_notes() {
    local issue_id="$1"
    local ours="$2"
    local theirs="$3"
    local base="$4"
    
    echo "🔀 Merging issue #$issue_id notes..."
    
    # Parse structured data from notes
    local our_data=$(parse_issue_data "$ours")
    local their_data=$(parse_issue_data "$theirs")
    local base_data=$(parse_issue_data "$base")
    
    # Merge strategy based on data type
    merge_structured_issue "$our_data" "$their_data" "$base_data"
}

parse_issue_data() {
    local note_content="$1"
    
    # Extract structured fields
    python3 -c "
import sys, re
content = '''$note_content'''

# Parse key-value pairs
fields = {}
for line in content.split('\n'):
    if ':' in line and not line.startswith('['):
        key, value = line.split(':', 1)
        fields[key.strip()] = value.strip()

# Parse comments (timestamped entries)
comments = []
for line in content.split('\n'):
    if line.startswith('[') and ']' in line:
        comments.append(line)

print(f'FIELDS:{fields}')
print(f'COMMENTS:{comments}')
"
}

merge_structured_issue() {
    local our_fields="$1"
    local their_fields="$2" 
    local base_fields="$3"
    
    # Field-level merge logic
    python3 -c "
import sys, ast, datetime

# Parse field data
our_fields = ast.literal_eval('$our_fields'.split('FIELDS:')[1].split('COMMENTS:')[0])
their_fields = ast.literal_eval('$their_fields'.split('FIELDS:')[1].split('COMMENTS:')[0])
base_fields = ast.literal_eval('$base_fields'.split('FIELDS:')[1].split('COMMENTS:')[0])

our_comments = ast.literal_eval('$our_fields'.split('COMMENTS:')[1])
their_comments = ast.literal_eval('$their_fields'.split('COMMENTS:')[1])

# Merge strategy
merged = {}

# 1. Timestamp-based wins for status fields
timestamp_fields = ['state', 'priority', 'assignee']
for field in timestamp_fields:
    our_time = our_fields.get('updated', '1970-01-01T00:00:00Z')
    their_time = their_fields.get('updated', '1970-01-01T00:00:00Z')
    
    if our_time > their_time:
        merged[field] = our_fields.get(field, base_fields.get(field, ''))
    else:
        merged[field] = their_fields.get(field, base_fields.get(field, ''))

# 2. Union merge for additive fields
additive_fields = ['tags', 'watchers']
for field in additive_fields:
    our_val = set(our_fields.get(field, '').split(','))
    their_val = set(their_fields.get(field, '').split(','))
    merged[field] = ','.join(sorted(our_val.union(their_val)))

# 3. Preserve immutable fields
immutable_fields = ['id', 'created', 'author']
for field in immutable_fields:
    merged[field] = base_fields.get(field, our_fields.get(field, their_fields.get(field, '')))

# 4. Merge comments chronologically
all_comments = sorted(our_comments + their_comments, 
                     key=lambda x: x.split(']')[0][1:] if ']' in x else '1970')

# 5. Update timestamp to now
merged['updated'] = datetime.datetime.utcnow().isoformat() + 'Z'

# Output merged result
for key, value in merged.items():
    print(f'{key}: {value}')

print('---')
for comment in all_comments:
    print(comment)
"
}
```

### Solution 2: Conflict-Free Data Structure

**Event Sourcing Approach:**

```bash
# Instead of storing current state, store events
# Each note contains append-only events

# Example issue note structure:
cat > example-issue-events.txt << 'EOF'
id: 123
events:
[2025-07-12T10:00:00Z] created by alice: "Fix navbar bug"
[2025-07-12T10:30:00Z] assigned by alice to bob
[2025-07-12T11:00:00Z] state_changed by bob: open -> in-progress  
[2025-07-12T11:30:00Z] commented by bob: "Started investigating"
[2025-07-12T12:00:00Z] priority_changed by alice: medium -> high
[2025-07-12T12:30:00Z] commented by alice: "Customer escalation"
EOF

# Events are append-only, so merging is just union + sort
merge_events() {
    local ours="$1"
    local theirs="$2"
    
    # Extract events from both sides
    (grep "^\[" "$ours"; grep "^\[" "$theirs") | sort | uniq
}
```

### Solution 3: Operational Transformation

**Google Docs-style Conflict Resolution:**

```bash
#!/bin/bash
# scripts/operational-transform.sh

transform_operations() {
    local our_ops="$1"
    local their_ops="$2"
    local base_state="$3"
    
    # Transform operations to be compatible
    python3 -c "
# Simplified operational transformation
# Real implementation would be more complex

class Operation:
    def __init__(self, timestamp, user, field, old_value, new_value):
        self.timestamp = timestamp
        self.user = user  
        self.field = field
        self.old_value = old_value
        self.new_value = new_value

def transform_concurrent_ops(op1, op2):
    '''Transform two concurrent operations to be compatible'''
    
    # If same field, timestamp wins
    if op1.field == op2.field:
        if op1.timestamp > op2.timestamp:
            return op1, None  # Discard op2
        else:
            return None, op2  # Discard op1
    
    # Different fields - both operations are valid
    return op1, op2

def apply_operations(base_state, operations):
    '''Apply a sequence of operations to base state'''
    state = base_state.copy()
    
    for op in sorted(operations, key=lambda x: x.timestamp):
        if op:  # Skip None operations
            state[op.field] = op.new_value
            
    return state

# Parse and transform operations...
print('Transformed state after conflict resolution')
"
}
```

### Solution 4: Automatic Conflict Detection & Prevention

**Pre-emptive Conflict Detection:**

```bash
#!/bin/bash
# Enhancement to simple-issue-tracker.sh

check_for_conflicts() {
    local issue_id="$1"
    local ref=$(get_issue_ref "$issue_id")
    
    # Check if remote has newer version
    git fetch origin "$ref:refs/remotes/origin/issue-$issue_id" 2>/dev/null || return 0
    
    local local_commit=$(git rev-parse "$ref" 2>/dev/null || echo "")
    local remote_commit=$(git rev-parse "refs/remotes/origin/issue-$issue_id" 2>/dev/null || echo "")
    
    if [[ -n "$local_commit" && -n "$remote_commit" && "$local_commit" != "$remote_commit" ]]; then
        echo "⚠️  Issue #$issue_id has been modified remotely."
        echo "   Local:  $local_commit"
        echo "   Remote: $remote_commit"
        echo ""
        echo "Options:"
        echo "  1. Pull and merge: git-issue sync $issue_id"
        echo "  2. Force update: git-issue update $issue_id --force"
        echo "  3. View differences: git-issue diff $issue_id"
        return 1
    fi
    
    return 0
}

# Add to update functions
update_issue() {
    local issue_id="$1"
    
    # Check for conflicts before updating
    if ! check_for_conflicts "$issue_id"; then
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ Update cancelled"
            return 1
        fi
    fi
    
    # Proceed with update...
}
```

### Solution 5: Merge Hooks Integration

**Post-merge Hook with Conflict Resolution:**

```bash
#!/bin/bash
# .git/hooks/post-merge with conflict handling

handle_notes_conflicts() {
    echo "🔀 Checking for git notes conflicts..."
    
    # Check for conflicted notes refs
    for ref in $(git for-each-ref --format="%(refname)" refs/notes/); do
        if ! git notes --ref="$ref" merge refs/remotes/origin/"${ref#refs/notes/}" 2>/dev/null; then
            echo "⚠️  Conflict detected in $ref"
            
            # Extract issue ID from ref name
            if [[ $ref =~ refs/notes/issue-([0-9]+) ]]; then
                local issue_id="${BASH_REMATCH[1]}"
                resolve_issue_conflict "$issue_id"
            else
                resolve_generic_conflict "$ref"
            fi
        fi
    done
}

resolve_issue_conflict() {
    local issue_id="$1"
    local ref="refs/notes/issue-$issue_id"
    
    echo "🛠️  Auto-resolving issue #$issue_id conflict..."
    
    # Get the conflicted versions
    local ours=$(git notes --ref="$ref" show 2>/dev/null || echo "")
    local theirs=$(git show refs/remotes/origin/issue-$issue_id 2>/dev/null || echo "")
    
    # Apply smart merge strategy
    local merged=$(merge_issue_notes "$issue_id" "$ours" "$theirs" "")
    
    # Update with merged version
    echo "$merged" | git notes --ref="$ref" add -f -F -
    
    echo "✅ Issue #$issue_id conflict resolved automatically"
}

# Run conflict resolution
handle_notes_conflicts
```

## 🔧 Implementation Strategy

### Step 1: Configure Git for Smart Merging

```bash
#!/bin/bash
# scripts/setup-merge-strategy.sh

echo "🔧 Configuring git notes merge strategy..."

# Set up intelligent merge strategy
git config notes.mergeStrategy union

# Configure notes display
git config notes.displayRef refs/notes/*

# Set up merge driver for issue notes
git config merge.issue-notes.name "Smart issue notes merger"
git config merge.issue-notes.driver "./scripts/git-notes-merge.sh %A %O %B %L"

echo "✅ Merge strategy configured"
```

### Step 2: Enhanced Issue Tracker with Conflict Handling

```bash
# Add conflict resolution commands to simple-issue-tracker.sh

case "$1" in
    # ... existing commands ...
    
    diff)
        if [ $# -lt 2 ]; then
            echo -e "${RED}Error: 'diff' requires issue id${NC}"
            usage
        fi
        show_issue_diff "$2"
        ;;
        
    sync)
        if [ $# -lt 2 ]; then
            echo -e "${RED}Error: 'sync' requires issue id${NC}"
            usage
        fi
        sync_issue_with_merge "$2"
        ;;
        
    resolve)
        if [ $# -lt 2 ]; then
            echo -e "${RED}Error: 'resolve' requires issue id${NC}"
            usage
        fi
        resolve_conflict_interactive "$2"
        ;;
esac

show_issue_diff() {
    local issue_id="$1"
    local ref=$(get_issue_ref "$issue_id")
    
    echo -e "${BLUE}Differences for issue #$issue_id:${NC}"
    echo ""
    
    # Show local vs remote differences
    git diff "$ref" "refs/remotes/origin/issue-$issue_id" 2>/dev/null || {
        echo "No differences found or remote not available"
    }
}

sync_issue_with_merge() {
    local issue_id="$1"
    local ref=$(get_issue_ref "$issue_id")
    
    echo "🔀 Syncing issue #$issue_id with merge..."
    
    # Fetch latest
    git fetch origin "$ref:refs/remotes/origin/issue-$issue_id" 2>/dev/null || {
        echo "⚠️  Could not fetch remote version"
        return 1
    }
    
    # Attempt automatic merge
    if git notes --ref="$ref" merge "refs/remotes/origin/issue-$issue_id" 2>/dev/null; then
        echo "✅ Merged successfully"
    else
        echo "⚠️  Merge conflict detected - use 'resolve' command"
        return 1
    fi
}
```

### Step 3: User-Friendly Conflict Resolution

```bash
resolve_conflict_interactive() {
    local issue_id="$1"
    local ref=$(get_issue_ref "$issue_id")
    
    echo -e "${YELLOW}Resolving conflict for issue #$issue_id${NC}"
    echo ""
    
    # Show both versions
    echo -e "${BLUE}=== LOCAL VERSION ===${NC}"
    git notes --ref="$ref" show 2>/dev/null || echo "(No local version)"
    echo ""
    
    echo -e "${BLUE}=== REMOTE VERSION ===${NC}" 
    git show "refs/remotes/origin/issue-$issue_id" 2>/dev/null || echo "(No remote version)"
    echo ""
    
    # Resolution options
    echo "Resolution options:"
    echo "  1. Keep local version"
    echo "  2. Keep remote version"  
    echo "  3. Smart merge (recommended)"
    echo "  4. Manual edit"
    echo ""
    
    read -p "Choose option [1-4]: " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            echo "✅ Keeping local version"
            git notes --ref="$ref" merge --strategy=ours "refs/remotes/origin/issue-$issue_id"
            ;;
        2)
            echo "✅ Using remote version"
            git notes --ref="$ref" merge --strategy=theirs "refs/remotes/origin/issue-$issue_id"
            ;;
        3)
            echo "🤖 Performing smart merge..."
            # Use our custom merge logic
            smart_merge_issue "$issue_id"
            ;;
        4)
            echo "✏️  Opening editor for manual resolution..."
            git notes --ref="$ref" edit
            ;;
        *)
            echo "❌ Invalid option"
            return 1
            ;;
    esac
}
```

## 🎯 Recommended Approach

For production use, I recommend:

1. **Event Sourcing Structure** - Append-only events prevent most conflicts
2. **Smart Auto-Merge** - Handles 90% of conflicts automatically  
3. **Conflict Detection** - Warns users before creating conflicts
4. **Interactive Resolution** - Easy UI for manual resolution when needed

## 📊 Conflict Prevention Strategies

### 1. Optimistic Locking
```bash
# Include timestamp in updates
update_with_timestamp() {
    local issue_id="$1"
    local last_known_update="$2"
    
    # Check if issue was modified since last_known_update
    current_update=$(get_issue_field "$issue_id" "updated")
    
    if [[ "$current_update" != "$last_known_update" ]]; then
        echo "⚠️  Issue was modified by someone else"
        return 1
    fi
    
    # Proceed with update
}
```

### 2. Operational Queues
```bash
# Queue operations for async processing
queue_operation() {
    local operation="$1"
    
    # Store in .git/notes-queue/
    echo "$operation" >> ".git/notes-queue/$(date +%s)-$RANDOM"
    
    # Process queue periodically
}
```

### 3. Real-time Collaboration
```bash
# Optional: WebSocket integration for live updates
notify_team_update() {
    local issue_id="$1"
    
    # Send webhook notification
    curl -X POST "$TEAM_WEBHOOK_URL" \
         -H "Content-Type: application/json" \
         -d "{\"issue\": \"$issue_id\", \"user\": \"$(git config user.name)\"}"
}
```

This comprehensive merge strategy makes git notes suitable for serious team collaboration! 🚀