#!/bin/bash
# Benchmark harness for dependency graph performance
#
# Usage: ./tests/bench_deps.sh [COUNT]
#   COUNT: number of issues to create (default: 100)
#
# Performance targets (from design doc):
#   - ready: under 100ms for 500 issues
#   - topo:  under 200ms for 500 issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$SCRIPT_DIR/../bin:$PATH"

COUNT=${1:-100}
BENCH_REPO="/tmp/git-issue-bench-$$"

# Portable nanosecond timestamp.
# macOS date(1) may not support %N; prefer gdate (GNU coreutils) if available,
# fall back to python3.
_nano() {
    if command -v gdate >/dev/null 2>&1; then
        gdate +%s%N
    elif date +%s%N 2>/dev/null | grep -qv N; then
        date +%s%N
    else
        python3 -c 'import time; print(int(time.time()*1e9))'
    fi
}

# Time a command, print result in ms.
bench() {
    local label="$1"
    shift
    local start end elapsed
    start=$(_nano)
    "$@" >/dev/null 2>&1
    end=$(_nano)
    elapsed=$(( (end - start) / 1000000 ))
    printf "  %-20s %d ms\n" "$label" "$elapsed"
}

cleanup() {
    cd /tmp
    rm -rf "$BENCH_REPO"
}
trap cleanup EXIT

echo "Setting up benchmark with $COUNT issues..."

mkdir -p "$BENCH_REPO"
cd "$BENCH_REPO"
git init >/dev/null 2>&1
git config user.name "Bench User"
git config user.email "bench@example.com"
echo "# Bench" > README.md
git add README.md
git commit -m "init" >/dev/null 2>&1

# Create issues
ids=()
for i in $(seq 1 "$COUNT"); do
    id=$(git issue create "Bench issue $i" 2>/dev/null | grep -o '#[a-f0-9]\{7\}' | head -1 | sed 's/#//')
    ids+=("$id")
    if (( i % 50 == 0 )); then
        echo "  Created $i/$COUNT issues..."
    fi
done

echo "Creating random blocking dependencies..."

# Create random blocking deps (each issue blocks ~1-2 later issues)
dep_count=0
for i in $(seq 0 $((COUNT - 2))); do
    target=$((i + 1 + RANDOM % 3))
    [[ $target -ge $COUNT ]] && continue
    git issue dep add "${ids[$i]}" blocks "${ids[$target]}" 2>/dev/null || true
    dep_count=$((dep_count + 1))
done

echo "Created $dep_count dependencies."
echo ""
echo "Benchmarking $COUNT issues with $dep_count deps..."
echo "========================================="

bench "ready"       git issue ready
bench "topo"        git issue topo
bench "deps"        git issue deps
bench "deps --dot"  git issue deps --dot
bench "dep rebuild" git issue dep rebuild
bench "dep list"    git issue dep list

echo ""
echo "Done."
