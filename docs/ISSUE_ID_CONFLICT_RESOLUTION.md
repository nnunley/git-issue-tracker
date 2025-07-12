# Issue ID Conflict Resolution

Comprehensive strategies for handling issue ID conflicts in distributed git-based issue tracking.

## 🔍 Problem Analysis

### Types of ID Conflicts

1. **Sequential ID Collisions**
   - Two people create issue #101 simultaneously
   - Offline work creates overlapping sequences
   - Merged repositories have duplicate IDs

2. **Cross-Repository Conflicts**
   - Same ID used in different project forks
   - Merging projects with existing issue histories
   - Submodule integration conflicts

3. **Temporal Conflicts**
   - Issues created during network partitions
   - Delayed synchronization creates duplicates
   - Import/export operations overlap

## 🎯 Solution Strategies

### Strategy 1: UUID-Based IDs (Recommended)

**Globally Unique Identifiers:**

```bash
#!/bin/bash
# Enhanced simple-issue-tracker.sh with UUID IDs

generate_issue_id() {
    # Generate UUID v4 (random)
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import uuid; print(uuid.uuid4())"
    else
        # Fallback: timestamp + random
        echo "$(date +%s)-$(openssl rand -hex 4)"
    fi
}

# Enhanced create function
create_issue() {
    local title="${@}"
    local id=$(generate_issue_id)
    
    echo -e "${BLUE}Creating issue with ID: $id${NC}"
    
    # Store with UUID
    local ref=$(get_issue_ref "$id")
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local author=$(git config user.name || echo "Unknown")
    
    cat <<EOF | git notes --ref="$ref" add -F -
id: $id
title: $title
state: open
priority: medium
created: $timestamp
updated: $timestamp
author: $author
assignee:
---
EOF
    
    # Also create human-readable alias
    create_issue_alias "$id" "$title"
    
    echo -e "${GREEN}✓ Created issue $id: $title${NC}"
    echo -e "${GRAY}   Alias: $(get_issue_alias "$id")${NC}"
}

create_issue_alias() {
    local uuid="$1"
    local title="$2"
    
    # Generate human-readable alias
    local slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    local short_uuid=$(echo "$uuid" | cut -d'-' -f1)
    local alias="${slug}-${short_uuid}"
    
    # Store alias mapping
    git config "issue.alias.$alias" "$uuid"
    git config "issue.uuid.$uuid" "$alias"
}

get_issue_alias() {
    local uuid="$1"
    git config "issue.uuid.$uuid" 2>/dev/null || echo "$uuid"
}

resolve_issue_id() {
    local input="$1"
    
    # Check if it's already a UUID
    if [[ $input =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        echo "$input"
        return 0
    fi
    
    # Check if it's an alias
    local uuid=$(git config "issue.alias.$input" 2>/dev/null)
    if [[ -n "$uuid" ]]; then
        echo "$uuid"
        return 0
    fi
    
    # Check if it's a short UUID
    local matches=$(git config --get-regexp "issue.uuid.*" | grep "$input" | wc -l)
    if [[ $matches -eq 1 ]]; then
        git config --get-regexp "issue.uuid.*" | grep "$input" | cut -d' ' -f1 | sed 's/issue.uuid.//'
        return 0
    elif [[ $matches -gt 1 ]]; then
        echo -e "${RED}Ambiguous ID: $input matches multiple issues${NC}" >&2
        echo -e "${YELLOW}Matches:${NC}" >&2
        git config --get-regexp "issue.uuid.*" | grep "$input" | while read key alias; do
            local uuid=${key#issue.uuid.}
            echo "  $alias -> $uuid" >&2
        done
        return 1
    fi
    
    echo -e "${RED}Issue not found: $input${NC}" >&2
    return 1
}
```

### Strategy 2: Hierarchical ID System

**Namespace-Based IDs:**

```bash
#!/bin/bash
# Hierarchical ID system

generate_hierarchical_id() {
    local namespace="$1"  # e.g., "user-repo" or "team-project"
    local timestamp=$(date +%s)
    local random=$(openssl rand -hex 2)
    
    echo "${namespace}-${timestamp}-${random}"
}

# Configure namespace
setup_namespace() {
    local namespace="$1"
    
    git config issue.namespace "$namespace"
    echo "✅ Issue namespace set to: $namespace"
}

get_namespace() {
    git config issue.namespace 2>/dev/null || {
        # Auto-generate from git remote
        local remote_url=$(git remote get-url origin 2>/dev/null || echo "local")
        local namespace=$(echo "$remote_url" | sed 's/.*[\/:]//g' | sed 's/\.git$//')
        
        # Fallback to user-repo
        if [[ -z "$namespace" || "$namespace" == "local" ]]; then
            local user=$(git config user.name | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
            local repo=$(basename "$(git rev-parse --show-toplevel)")
            namespace="${user}-${repo}"
        fi
        
        git config issue.namespace "$namespace"
        echo "$namespace"
    }
}

create_issue_hierarchical() {
    local title="${@}"
    local namespace=$(get_namespace)
    local id=$(generate_hierarchical_id "$namespace")
    
    echo -e "${BLUE}Creating issue with hierarchical ID: $id${NC}"
    
    # Rest of creation logic...
}
```

### Strategy 3: Conflict Detection & Resolution

**ID Collision Detection:**

```bash
#!/bin/bash
# Conflict detection and resolution

check_id_conflicts() {
    echo "🔍 Checking for ID conflicts..."
    
    local conflicts=0
    
    # Check for duplicate IDs across all notes refs
    for ref in $(git for-each-ref --format="%(refname)" refs/notes/issue-*); do
        local id=${ref#refs/notes/issue-}
        
        # Check if this ID exists in multiple refs
        local count=$(git for-each-ref --format="%(refname)" "refs/notes/issue-$id*" | wc -l)
        
        if [[ $count -gt 1 ]]; then
            echo -e "${RED}⚠️  Conflict detected for ID: $id${NC}"
            echo "   Conflicting refs:"
            git for-each-ref --format="   - %(refname)" "refs/notes/issue-$id*"
            ((conflicts++))
        fi
    done
    
    if [[ $conflicts -eq 0 ]]; then
        echo "✅ No ID conflicts found"
    else
        echo -e "${YELLOW}Found $conflicts ID conflicts${NC}"
        echo "Run: git-issue resolve-conflicts"
    fi
    
    return $conflicts
}

resolve_id_conflicts() {
    echo "🛠️  Resolving ID conflicts..."
    
    # Find all conflicted IDs
    local conflicted_ids=$(git for-each-ref --format="%(refname)" refs/notes/issue-* | \
                          sed 's/refs\/notes\/issue-//' | sort | uniq -d)
    
    for id in $conflicted_ids; do
        resolve_single_conflict "$id"
    done
}

resolve_single_conflict() {
    local conflicted_id="$1"
    
    echo -e "${YELLOW}Resolving conflict for ID: $conflicted_id${NC}"
    
    # Get all refs with this ID
    local refs=($(git for-each-ref --format="%(refname)" "refs/notes/issue-$conflicted_id*"))
    
    echo "Conflicted versions:"
    for i in "${!refs[@]}"; do
        local ref="${refs[$i]}"
        local title=$(git notes --ref="$ref" show 2>/dev/null | grep "^title:" | cut -d' ' -f2-)
        local created=$(git notes --ref="$ref" show 2>/dev/null | grep "^created:" | cut -d' ' -f2-)
        
        echo "  $((i+1)). $ref"
        echo "     Title: $title"
        echo "     Created: $created"
        echo ""
    done
    
    echo "Resolution options:"
    echo "  1. Keep earliest issue (by creation time)"
    echo "  2. Keep latest issue (by creation time)"
    echo "  3. Merge all issues into one"
    echo "  4. Rename conflicts with new UUIDs"
    echo "  5. Manual resolution"
    echo ""
    
    read -p "Choose option [1-5]: " -n 1 -r
    echo ""
    
    case $REPLY in
        1) keep_earliest_issue "$conflicted_id" "${refs[@]}" ;;
        2) keep_latest_issue "$conflicted_id" "${refs[@]}" ;;
        3) merge_conflicted_issues "$conflicted_id" "${refs[@]}" ;;
        4) rename_conflicts "$conflicted_id" "${refs[@]}" ;;
        5) manual_conflict_resolution "$conflicted_id" "${refs[@]}" ;;
        *) echo "❌ Invalid option" ;;
    esac
}

rename_conflicts() {
    local original_id="$1"
    shift
    local refs=("$@")
    
    echo "🔄 Renaming conflicted issues with new UUIDs..."
    
    for ref in "${refs[@]}"; do
        local new_id=$(generate_issue_id)
        local new_ref="refs/notes/issue-$new_id"
        
        # Copy note content to new ref
        local content=$(git notes --ref="$ref" show 2>/dev/null)
        
        # Update ID in content
        local updated_content=$(echo "$content" | sed "s/^id: $original_id$/id: $new_id/")
        
        # Create new note
        echo "$updated_content" | git notes --ref="$new_ref" add -F -
        
        # Remove old note
        git update-ref -d "$ref"
        
        echo "  ✅ Renamed $ref -> $new_ref"
        
        # Update any alias mappings
        local alias=$(get_issue_alias "$original_id")
        if [[ "$alias" != "$original_id" ]]; then
            git config --unset "issue.alias.$alias" 2>/dev/null || true
            git config --unset "issue.uuid.$original_id" 2>/dev/null || true
            
            # Create new alias
            git config "issue.alias.$alias" "$new_id"
            git config "issue.uuid.$new_id" "$alias"
        fi
    done
}
```

### Strategy 4: Import/Export Conflict Prevention

**Safe Import with ID Mapping:**

```bash
#!/bin/bash
# Safe import with conflict prevention

import_issues_safe() {
    local source_file="$1"
    local id_mapping_file="${2:-id_mapping.json}"
    
    echo "📥 Importing issues with conflict prevention..."
    
    # Track ID mappings for reference updates
    echo "{}" > "$id_mapping_file"
    
    while IFS= read -r line; do
        if [[ $line =~ ^id:\ (.+)$ ]]; then
            local old_id="${BASH_REMATCH[1]}"
            
            # Check if ID already exists
            if issue_exists "$old_id"; then
                local new_id=$(generate_issue_id)
                echo "⚠️  ID conflict for $old_id, assigning new ID: $new_id"
                
                # Update mapping
                python3 -c "
import json
with open('$id_mapping_file', 'r') as f:
    mapping = json.load(f)
mapping['$old_id'] = '$new_id'
with open('$id_mapping_file', 'w') as f:
    json.dump(mapping, f, indent=2)
"
                # Replace ID in current issue
                line="id: $new_id"
            fi
        fi
        
        echo "$line"
    done < "$source_file" | import_issue_stream
    
    echo "✅ Import complete. ID mappings saved to $id_mapping_file"
}

update_references() {
    local id_mapping_file="$1"
    
    echo "🔗 Updating issue references..."
    
    # Update any commit notes that reference remapped IDs
    python3 -c "
import json, subprocess, re

with open('$id_mapping_file', 'r') as f:
    mapping = json.load(f)

if not mapping:
    print('No ID mappings to update')
    exit(0)

# Find all commit notes that might reference issues
commit_notes = subprocess.check_output(['git', 'notes', 'list'], text=True).strip().split('\n')

for note_commit in commit_notes:
    if not note_commit:
        continue
        
    try:
        content = subprocess.check_output(['git', 'notes', 'show', note_commit], text=True)
        updated_content = content
        
        # Replace old IDs with new IDs
        for old_id, new_id in mapping.items():
            updated_content = re.sub(rf'#?{re.escape(old_id)}\\b', f'#{new_id}', updated_content)
        
        if updated_content != content:
            # Update the note
            subprocess.run(['git', 'notes', 'add', '-f', '-m', updated_content, note_commit])
            print(f'Updated references in commit {note_commit}')
            
    except subprocess.CalledProcessError:
        continue
"
}
```

### Strategy 5: Distributed ID Coordination

**Reservation System:**

```bash
#!/bin/bash
# ID reservation system for coordinated allocation

reserve_id_block() {
    local block_size="${1:-100}"
    local namespace=$(get_namespace)
    
    # Use timestamp + random for block start
    local block_start=$(($(date +%s) * 1000 + RANDOM))
    local block_end=$((block_start + block_size - 1))
    
    # Store reservation
    git config "issue.reserved.start" "$block_start"
    git config "issue.reserved.end" "$block_end"
    git config "issue.reserved.namespace" "$namespace"
    
    echo "✅ Reserved ID block: $block_start - $block_end"
    echo "   Namespace: $namespace"
    echo "   $(git config --get issue.reserved.end) IDs remaining"
}

get_next_reserved_id() {
    local start=$(git config --get issue.reserved.start 2>/dev/null)
    local end=$(git config --get issue.reserved.end 2>/dev/null)
    local current=$(git config --get issue.reserved.current 2>/dev/null || echo "$start")
    
    if [[ -z "$start" || -z "$end" ]]; then
        echo "No ID block reserved. Run: git-issue reserve-block"
        return 1
    fi
    
    if [[ $current -gt $end ]]; then
        echo "ID block exhausted. Reserve new block with: git-issue reserve-block"
        return 1
    fi
    
    # Increment current
    git config "issue.reserved.current" $((current + 1))
    
    echo "$current"
}

create_issue_reserved() {
    local title="${@}"
    local namespace=$(git config --get issue.reserved.namespace)
    local id=$(get_next_reserved_id)
    
    if [[ $? -ne 0 ]]; then
        echo "❌ Could not allocate ID"
        return 1
    fi
    
    local full_id="${namespace}-${id}"
    
    echo -e "${BLUE}Creating issue with reserved ID: $full_id${NC}"
    
    # Create issue with reserved ID
    create_issue_with_id "$full_id" "$title"
}
```

## 🎯 Recommended Implementation

### Production Strategy: Hybrid Approach

```bash
#!/bin/bash
# Combined strategy for maximum compatibility

create_issue_production() {
    local title="${@}"
    local id_strategy=$(git config issue.id-strategy 2>/dev/null || echo "uuid")
    
    case "$id_strategy" in
        "uuid")
            create_issue_uuid "$title"
            ;;
        "hierarchical")
            create_issue_hierarchical "$title"
            ;;
        "reserved")
            create_issue_reserved "$title"
            ;;
        "sequential")
            create_issue_sequential "$title"  # Legacy support
            ;;
        *)
            echo "❌ Unknown ID strategy: $id_strategy"
            echo "Valid strategies: uuid, hierarchical, reserved, sequential"
            return 1
            ;;
    esac
}

configure_id_strategy() {
    local strategy="$1"
    
    case "$strategy" in
        "uuid")
            git config issue.id-strategy "uuid"
            echo "✅ Using UUID-based IDs (recommended for distributed teams)"
            ;;
        "hierarchical")
            git config issue.id-strategy "hierarchical"
            setup_namespace "$(get_namespace)"
            echo "✅ Using hierarchical IDs with namespace: $(get_namespace)"
            ;;
        "reserved")
            git config issue.id-strategy "reserved"
            reserve_id_block 1000
            echo "✅ Using reserved ID blocks"
            ;;
        "sequential")
            git config issue.id-strategy "sequential"
            echo "⚠️  Using sequential IDs (conflicts possible in distributed setup)"
            ;;
        *)
            echo "❌ Invalid strategy. Choose: uuid, hierarchical, reserved, sequential"
            return 1
            ;;
    esac
}
```

## 📊 Strategy Comparison

| Strategy | Pros | Cons | Best For |
|----------|------|------|----------|
| **UUID** | No conflicts, globally unique | Long IDs, not human-friendly | Distributed teams |
| **Hierarchical** | Readable, namespace isolation | Setup required, medium length | Multi-project orgs |
| **Reserved Blocks** | Short IDs, coordination | Requires planning, can exhaust | Coordinated teams |
| **Sequential** | Short, familiar | High conflict risk | Single-user/centralized |

## 🛠️ Migration Tools

```bash
#!/bin/bash
# Migration from sequential to UUID

migrate_to_uuid() {
    echo "🔄 Migrating from sequential to UUID IDs..."
    
    local mapping_file="sequential_to_uuid_mapping.json"
    echo "{}" > "$mapping_file"
    
    # Find all sequential issues
    for ref in $(git for-each-ref --format="%(refname)" refs/notes/issue-*); do
        local old_id=${ref#refs/notes/issue-}
        
        # Skip if already UUID
        if [[ $old_id =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
            continue
        fi
        
        local new_id=$(generate_issue_id)
        local new_ref="refs/notes/issue-$new_id"
        
        # Copy and update content
        local content=$(git notes --ref="$ref" show)
        local updated_content=$(echo "$content" | sed "s/^id: $old_id$/id: $new_id/")
        
        # Create new note
        echo "$updated_content" | git notes --ref="$new_ref" add -F -
        
        # Remove old note
        git update-ref -d "$ref"
        
        # Track mapping
        python3 -c "
import json
with open('$mapping_file', 'r') as f:
    mapping = json.load(f)
mapping['$old_id'] = '$new_id'
with open('$mapping_file', 'w') as f:
    json.dump(mapping, f, indent=2)
"
        
        echo "  Migrated #$old_id -> #$new_id"
    done
    
    # Update all references
    update_references "$mapping_file"
    
    # Update configuration
    git config issue.id-strategy "uuid"
    
    echo "✅ Migration complete!"
}
```

This comprehensive solution eliminates ID conflicts entirely while providing multiple strategies for different team needs! 🚀