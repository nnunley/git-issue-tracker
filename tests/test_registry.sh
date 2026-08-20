#!/usr/bin/env bash
# Multi-project registry tests — draft-ndn-multi-project-registry-02.
#
# The RFC's transcript corpus is the byte-exact contract (run it with
# rfc-run); this suite is the repo-local regression net for the same
# requirements, tagged with the requirement IDs it covers.
#
# HOME is redirected for the whole run: the registry lives in *global*
# git config, so an unisolated test would edit the developer's ~/.gitconfig.
set -e
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
GI="$REPO_DIR/bin/git-issue"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
eq()  { # eq <label> <want> <got>
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1"$'\n'"      want: $2"$'\n'"      got:  $3"; fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK" XDG_CONFIG_HOME="$WORK/.config" GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR
git config --global user.name registry-test
git config --global user.email registry-test@example.com
cd "$WORK"

reset_registry() { git config --global --remove-section-all 2>/dev/null || true
    while read -r k _; do
        [[ -n "$k" ]] || continue
        git config --global --remove-section "${k%.path}" >/dev/null 2>&1 || true
    done < <(git config --global --get-regexp '^issue\.repo\..*\.path$' 2>/dev/null || true)
}

echo "Testing registry storage [R-config-store]"
reset_registry; mkdir -p tracker
eq "repo add reports the registration" \
   "Registered 'tracker' -> $WORK/tracker" \
   "$("$GI" repo add tracker "$WORK/tracker" 2>&1)"
eq "registry is plain global git config, readable without git-issue" \
   "issue.repo.tracker.path $WORK/tracker" \
   "$(git config --global --get-regexp '^issue\.repo\.' 2>&1)"

echo "Testing name grammar [R-name-charset]"
reset_registry
for n in tracker api-v2 a_b; do
    if "$GI" repo add "$n" "$WORK" >/dev/null 2>&1; then ok "accepts '$n'"; else bad "rejected valid name '$n'"; fi
done
reset_registry
for n in Api a.b "a b" ""; do
    if "$GI" repo add "$n" "$WORK" >/dev/null 2>&1; then bad "accepted invalid name '$n'"; else ok "rejects '${n:-(empty)}'"; fi
done

echo "Testing duplicate and --force [R-reject-duplicate] [R-force-replace]"
reset_registry; mkdir -p a b
"$GI" repo add tracker "$WORK/a" >/dev/null
out=$("$GI" repo add tracker "$WORK/b" 2>&1) && rc=0 || rc=$?
eq "duplicate is refused, naming the incumbent path" \
   "Error: 'tracker' is already registered (-> $WORK/a); use --force to replace" "$out"
[[ "$rc" -ne 0 ]] && ok "duplicate exits nonzero" || bad "duplicate exited 0"
eq "--force replaces and reports old -> new" \
   "Registered 'tracker' -> $WORK/b (replaced $WORK/a)" \
   "$("$GI" repo add --force tracker "$WORK/b" 2>&1)"

echo "Testing path resolution [R-abs-path]"
reset_registry; mkdir -p sub/brain
( cd sub && "$GI" repo add brain ./brain >/dev/null )
eq "relative path is stored absolute, resolved against the cwd at add time" \
   "$WORK/sub/brain" "$(git config --global --get issue.repo.brain.path)"

echo "Testing worktree resolution [R-worktree-root]"
reset_registry
git init -q proj
( cd proj && git commit -q --allow-empty -m init && git worktree add --quiet ../fix-wt )
eq "a linked worktree registers as the main worktree, and says so" \
   "Registered 'fix' -> $WORK/proj (main worktree of the given path)" \
   "$("$GI" repo add fix ./fix-wt 2>&1)"
reset_registry
eq "the main worktree itself is registered as given" \
   "Registered 'proj' -> $WORK/proj" \
   "$("$GI" repo add proj ./proj 2>&1)"

echo "Testing repo list [R-list-missing]"
reset_registry; mkdir -p a gone
"$GI" repo add tracker "$WORK/a" >/dev/null
"$GI" repo add old "$WORK/gone" >/dev/null
rmdir gone
eq "missing entries are shown, marked, and never fatal" \
   "tracker $WORK/a
old $WORK/gone (missing)" \
   "$("$GI" repo list 2>&1)"

echo "Testing repo rm [R-repo-rm]"
reset_registry; mkdir -p a; touch a/keep
"$GI" repo add tracker "$WORK/a" >/dev/null
eq "rm forgets the entry" "Removed 'tracker' (repository contents untouched)" "$("$GI" repo rm tracker 2>&1)"
[[ -f a/keep ]] && ok "rm leaves repository contents untouched" || bad "rm deleted repository contents"
eq "registry is empty after rm" "" "$("$GI" repo list 2>&1)"
"$GI" repo rm nosuch >/dev/null 2>&1 && bad "rm of unknown name exited 0" || ok "rm of unknown name exits nonzero"

echo "Testing repo prune [R-prune]"
reset_registry; mkdir -p a gone
"$GI" repo add tracker "$WORK/a" >/dev/null
"$GI" repo add old "$WORK/gone" >/dev/null
rmdir gone
eq "prune reports each removal by name and path" "Pruned 'old' ($WORK/gone)" "$("$GI" repo prune 2>&1)"
eq "prune leaves entries whose path exists" "tracker $WORK/a" "$("$GI" repo list 2>&1)"

echo "Testing targeting [R-target-repo] [R-target-invalid]"
reset_registry
rm -rf t1 && git init -q t1
( cd t1 && git commit -q --allow-empty -m init && "$GI" create "target smoke" >/dev/null 2>&1 )
"$GI" repo add t1 "$WORK/t1" >/dev/null
eq "--repo before the subcommand" "1" "$("$GI" --repo t1 list 2>/dev/null | grep -c 'target smoke')"
eq "--repo after the subcommand"  "1" "$("$GI" list --repo t1 2>/dev/null | grep -c 'target smoke')"
eq "unknown name is named as such" \
   "Error: 'nosuch' is not a registered repository (see: git issue repo list)" \
   "$("$GI" --repo nosuch list 2>&1)"
"$GI" --repo nosuch list >/dev/null 2>&1 && bad "unknown --repo exited 0" || ok "unknown --repo exits nonzero"
mkdir -p gone2; "$GI" repo add old2 "$WORK/gone2" >/dev/null; rmdir gone2
eq "registered-but-missing path is named as such" \
   "Error: 'old2' points to $WORK/gone2, which does not exist" \
   "$("$GI" --repo old2 list 2>&1)"

echo "Testing aggregation [R-all-prefix] [R-all-continues]"
reset_registry
"$GI" repo add t1 "$WORK/t1" >/dev/null
eq "each swept line is prefixed with [<name>] " "1" "$("$GI" list --all 2>/dev/null | grep -c '^\[t1\] ')"
eq "ready --all is prefixed too" "1" "$("$GI" ready --all 2>/dev/null | grep -c '^\[t1\] ')"
mkdir -p gone3; "$GI" repo add old3 "$WORK/gone3" >/dev/null; rmdir gone3
eq "a failing entry does not abort the sweep" "1" "$("$GI" list --all 2>/dev/null | grep -c '^\[t1\] ')"
eq "failures are summarized on stderr" "1" "$("$GI" list --all 2>&1 >/dev/null | grep -c "skipped 'old3'")"
"$GI" list --all >/dev/null 2>&1 && bad "sweep with a failing entry exited 0" || ok "sweep with a failing entry exits nonzero"

echo "Testing compatibility"
reset_registry
eq "no registry entries: repo list is silent and succeeds" "" "$("$GI" repo list 2>&1)"
( cd t1 && "$GI" list 2>/dev/null | grep -q 'target smoke' ) \
    && ok "per-directory detection is unchanged with an empty registry" \
    || bad "per-directory detection regressed"
"$GI" create --all "x" >/dev/null 2>&1 && bad "--all accepted on a non-aggregating command" \
    || ok "--all is refused outside list/ready"

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
