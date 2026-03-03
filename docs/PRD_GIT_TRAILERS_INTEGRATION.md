# Product Requirements Document: Git Trailers Integration for git-issue

**Version:** 1.0  
**Date:** January 29, 2025  
**Status:** Draft  

## Executive Summary

This PRD outlines the integration of `git-interpret-trailers` functionality into the git-issue system to provide standardized, discoverable issue tracking through RFC 822-style commit message trailers while maintaining the rich issue data storage capabilities of git notes.

## Problem Statement

### Current Issues
1. **Core Bug**: The `read_issue_data()` function is broken, causing most issues to be invisible in `git issue list`
2. **Poor Discoverability**: Issue-commit relationships are hidden in git notes, invisible to standard git workflows
3. **Non-Standard Format**: Custom git notes format requires specialized knowledge and tools
4. **Testing Gaps**: Test infrastructure uses incorrect git notes API, allowing critical bugs to persist
5. **Tool Integration**: Other git tools cannot understand or parse issue relationships

### Business Impact
- **Developer Frustration**: Issues disappear from lists due to broken functionality
- **Workflow Disruption**: Requires specialized commands to see issue relationships
- **Adoption Barriers**: Non-standard approach conflicts with git ecosystem expectations
- **Maintenance Burden**: Complex git notes implementation prone to bugs

## Solution Overview

### Hybrid Architecture
Implement a **dual-system approach** combining the strengths of both technologies:

1. **Git Notes for Rich Issue Storage** (Enhanced)
   - Fix broken `read_issue_data()` function
   - Store comprehensive issue metadata, comments, and history
   - Maintain existing git-issue functionality

2. **Git Trailers for Commit-Issue Linking** (New)
   - Use standardized RFC 822-style trailers in commit messages
   - Enable automatic issue-commit relationship discovery
   - Integrate with git's native trailer processing

## Requirements

### Functional Requirements

#### FR-1: Core Bug Fixes (Priority: Critical)
- **FR-1.1**: Fix `read_issue_data()` function to properly read git notes content
- **FR-1.2**: Ensure all existing issues become visible in `git issue list`
- **FR-1.3**: Fix integration tests to use correct git notes API
- **FR-1.4**: Add comprehensive test coverage for git notes read/write operations

#### FR-2: Trailer-Based Commit Linking (Priority: High)
- **FR-2.1**: Add support for standard issue trailers in commits:
  - `Issue: #a1b2c3d` - Links commit to issue
  - `Fixes: #b2c3d4e` - Marks issue as resolved by this commit  
  - `Closes: #c3d4e5f` - Closes issue when commit is merged
  - `Related-To: #d4e5f6g` - References related issue
- **FR-2.2**: Automatic trailer parsing using `git interpret-trailers --parse`
- **FR-2.3**: Bidirectional relationship discovery (commit → issue, issue → commit)

#### FR-3: Enhanced Git Issue Commands (Priority: High)
- **FR-3.1**: `git issue commit [--issue|--fixes|--closes] <id>` - Add trailers to commits
- **FR-3.2**: `git issue scan-commits [--since=date]` - Parse commit history for issue references
- **FR-3.3**: `git issue show <id> --with-commits` - Display related commits from trailers
- **FR-3.4**: `git issue link <id> <commit> --trailer` - Add trailers to existing commits

#### FR-4: Automatic Trailer Configuration (Priority: Medium)
- **FR-4.1**: Configure git trailers for issue tracking:
  ```bash
  git config trailer.issue.key "Issue: #"
  git config trailer.fixes.key "Fixes: #"  
  git config trailer.closes.key "Closes: #"
  ```
- **FR-4.2**: Integration with git hooks for automatic trailer addition
- **FR-4.3**: Template support for consistent trailer formatting

#### FR-5: Migration and Compatibility (Priority: Medium)
- **FR-5.1**: Maintain 100% backward compatibility with existing git-issue data
- **FR-5.2**: Optional migration tool to add trailers to existing commit-issue links
- **FR-5.3**: Graceful handling of mixed trailer/notes linking

### Non-Functional Requirements

#### NFR-1: Performance
- **NFR-1.1**: Issue listing must complete in <2 seconds for repositories with 1000+ issues
- **NFR-1.2**: Commit scanning should process 1000 commits in <5 seconds
- **NFR-1.3**: Trailer parsing should add <100ms overhead to git operations

#### NFR-2: Reliability
- **NFR-2.1**: Fix must achieve 99.9% test success rate
- **NFR-2.2**: No data loss during trailer integration
- **NFR-2.3**: Graceful degradation when git-interpret-trailers unavailable

#### NFR-3: Usability
- **NFR-3.1**: All trailer commands must provide clear help text and examples
- **NFR-3.2**: Error messages must guide users to correct trailer syntax
- **NFR-3.3**: Integration should feel native to existing git workflows

#### NFR-4: Maintainability
- **NFR-4.1**: Code coverage must increase to >90% for core functions
- **NFR-4.2**: All trailer functionality must have comprehensive test coverage
- **NFR-4.3**: Documentation must include trailer configuration and usage examples

## Technical Specification

### Architecture Changes

#### 1. Core Function Fixes
```bash
# Fix broken read_issue_data() function
read_issue_data() {
    local id="$1"
    local ref=$(get_issue_ref "$id")
    # Get the tree hash from the notes commit
    local tree_hash=$(git cat-file -p "$ref" 2>/dev/null | grep "^tree" | cut -d' ' -f2) || return 1
    # Get the blob hash from the tree
    local blob_hash=$(git ls-tree "$tree_hash" | awk '{print $3}') || return 1
    # Read the actual issue content
    git cat-file -p "$blob_hash" 2>/dev/null || return 1
}
```

#### 2. New Trailer Functions
```bash
# Add trailer to commit
add_issue_trailer() {
    local commit="$1"
    local trailer_type="$2"  # issue, fixes, closes, related-to
    local issue_id="$3"
    
    git interpret-trailers --in-place \
        --trailer "${trailer_type}: #${issue_id}" \
        <(git show --format="%B" -s "$commit")
}

# Parse trailers from commit
parse_issue_trailers() {
    local commit="$1"
    git show --format="%B" -s "$commit" | \
        git interpret-trailers --parse | \
        grep -E "(Issue|Fixes|Closes|Related-To):"
}

# Scan commit history for issue references
scan_commits_for_issues() {
    local since="${1:-}"
    local git_log_args=("--oneline")
    [[ -n "$since" ]] && git_log_args+=("--since=$since")
    
    git log "${git_log_args[@]}" --format="%H" | while read commit; do
        parse_issue_trailers "$commit"
    done
}
```

#### 3. Enhanced Commands
```bash
# New command implementations
case "$1" in
    commit)
        # git issue commit --fixes a1b2c3d
        handle_commit_with_trailers "$@"
        ;;
    scan-commits)
        # git issue scan-commits --since="1 week ago"
        scan_commits_for_issues "${2:-}"
        ;;
    show)
        if [[ "$3" == "--with-commits" ]]; then
            show_issue_with_related_commits "$2"
        else
            show_issue "$2"
        fi
        ;;
esac
```

### Configuration

#### Trailer Configuration
```bash
# Automatic setup during git-issue installation
git config trailer.issue.key "Issue: #"
git config trailer.issue.where "end"
git config trailer.issue.ifExists "addIfDifferentNeighbor"
git config trailer.issue.ifMissing "add"

git config trailer.fixes.key "Fixes: #"
git config trailer.fixes.where "end"
git config trailer.fixes.ifExists "addIfDifferentNeighbor"
git config trailer.fixes.ifMissing "add"

git config trailer.closes.key "Closes: #"
git config trailer.closes.where "end"
git config trailer.closes.ifExists "addIfDifferentNeighbor"
git config trailer.closes.ifMissing "add"
```

## Implementation Plan

### Phase 1: Core Bug Fix (Week 1)
- **Task 1.1**: Fix `read_issue_data()` function
- **Task 1.2**: Update integration tests to use correct git notes API
- **Task 1.3**: Verify all existing issues become visible
- **Task 1.4**: Add comprehensive unit tests for git notes functions

### Phase 2: Basic Trailer Support (Week 2)
- **Task 2.1**: Implement trailer parsing functions
- **Task 2.2**: Add `git issue commit` command with trailer options
- **Task 2.3**: Add `git issue scan-commits` command
- **Task 2.4**: Update `git issue show` to display related commits

### Phase 3: Advanced Features (Week 3)
- **Task 3.1**: Implement automatic trailer configuration
- **Task 3.2**: Add git hook integration for automatic trailer addition
- **Task 3.3**: Create migration tool for existing commit-issue links
- **Task 3.4**: Enhanced error handling and validation

### Phase 4: Testing and Documentation (Week 4)
- **Task 4.1**: Comprehensive test suite for all trailer functionality
- **Task 4.2**: Update documentation with trailer examples and configuration
- **Task 4.3**: Performance testing and optimization
- **Task 4.4**: User acceptance testing

## Success Metrics

### Quantitative Metrics
- **Bug Resolution**: 100% of existing issues visible in `git issue list`
- **Test Coverage**: >90% code coverage for core functions
- **Performance**: <2s issue listing for 1000+ issues
- **Adoption**: >80% of new commits include relevant issue trailers

### Qualitative Metrics
- **Developer Experience**: Seamless integration with git workflows
- **Discoverability**: Issue relationships visible in standard git tools
- **Maintainability**: Reduced complexity and improved code quality
- **Ecosystem Integration**: Compatible with existing git tooling

## Risks and Mitigations

### Technical Risks
- **Risk**: Git-interpret-trailers not available on older git versions
  - **Mitigation**: Version detection and graceful degradation
- **Risk**: Performance impact of trailer parsing on large repositories
  - **Mitigation**: Lazy loading and caching mechanisms
- **Risk**: Conflicts with existing custom git trailers
  - **Mitigation**: Configurable trailer prefixes and conflict detection

### Business Risks
- **Risk**: User confusion during transition period
  - **Mitigation**: Clear documentation and gradual rollout
- **Risk**: Resistance to additional complexity
  - **Mitigation**: Emphasize discoverability benefits and optional usage

## Dependencies

### External Dependencies
- **Git >= 2.1.4**: Required for `git interpret-trailers` command
- **Bash >= 4.0**: For advanced array handling in trailer functions
- **Existing git-issue installation**: Base system must be functional

### Internal Dependencies
- **Fixed git notes functions**: Core bug must be resolved first
- **Updated test infrastructure**: Tests must validate trailer functionality
- **Documentation updates**: User guides must reflect new capabilities

## Acceptance Criteria

### Must Have
- ✅ All existing issues visible in `git issue list`
- ✅ Commit trailers automatically parsed and linked
- ✅ `git issue commit --fixes <id>` updates issue state and adds trailer
- ✅ `git log` shows issue relationships in commit messages
- ✅ 100% backward compatibility with existing git-issue data

### Should Have
- ✅ Automatic trailer configuration during installation
- ✅ Migration tool for existing commit-issue links
- ✅ Performance optimization for large repositories
- ✅ Comprehensive test coverage >90%

### Could Have
- ✅ Integration with GitHub/GitLab trailer conventions
- ✅ Visual indicators in git log output
- ✅ Bulk trailer addition tools
- ✅ Advanced trailer querying capabilities

## Appendix

### Example Workflows

#### Workflow 1: Bug Fix with Trailers
```bash
# Create issue
git issue create "Fix navbar responsive bug" --priority=high
# ✓ Created issue #a1b2c3d

# Make fix and commit with trailer
git commit -m "Fix navbar mobile layout

Updated breakpoints and responsive behavior for mobile devices.

Fixes: #a1b2c3d"

# Issue automatically marked as resolved
git issue show a1b2c3d  # Shows state: done
```

#### Workflow 2: Feature Development
```bash
# Create feature issue
git issue create "Add dark mode support" --priority=medium
# ✓ Created issue #b2c3d4e

# Multiple commits referencing the issue
git commit -m "Add dark mode CSS variables

Issue: #b2c3d4e"

git commit -m "Implement theme switcher component  

Issue: #b2c3d4e"

git commit -m "Complete dark mode implementation

Closes: #b2c3d4e"

# View all related commits
git issue show b2c3d4e --with-commits
```

#### Workflow 3: Historical Analysis
```bash
# Scan recent commits for issue references
git issue scan-commits --since="1 month ago"

# Output shows all discovered relationships
# Issue: #a1b2c3d linked to commits: abc123, def456
# Issue: #b2c3d4e linked to commits: ghi789, jkl012
```

### Related Documentation
- [Git Notes Workflow](GIT_NOTES_WORKFLOW.md)
- [Issue-Commit Linking](ISSUE_COMMIT_LINKING.md)  
- [Git Interpret Trailers Manual](https://git-scm.com/docs/git-interpret-trailers)