#!/usr/bin/env bash
# Test: Unit tests for the worktree bridge tab lib helpers + dashboard wiring.
# Uses disposable /tmp git repos; no live tmux.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="worktree-bridge-tab-unit"

LIB_FILE="$TESTS_DIR/../llm-send-bin/.local/bin/lazy-llm-lib.sh"
DASHBOARD="$TESTS_DIR/../lazy-llm-bin/.local/bin/llm-dashboard"
# shellcheck source=/dev/null
source "$LIB_FILE"

mk_repo() {
    local d="$1"
    rm -rf "$d"
    mkdir -p "$d"
    (
      cd "$d" || exit 1
      git init -q -b main >/dev/null
      git config user.email test@test
      git config user.name test
      printf 'init\n' > README.md
      git add README.md
      git commit -q -m init >/dev/null
    )
}

cleanup_repos() {
    rm -rf /tmp/lazy-llm-wbt-test-*
}
trap cleanup_repos EXIT

# ──────────────────────────────────────────────────────────────────────────
# 1. lazy_llm_default_branch
# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: lazy_llm_default_branch finds main..."
REPO=/tmp/lazy-llm-wbt-test-1
mk_repo "$REPO"
out=$(cd "$REPO" && lazy_llm_default_branch)
assert_equals "$out" "main" "fresh repo with main as init branch"

echo ""
echo "Test 2: lazy_llm_default_branch fallback to master..."
REPO=/tmp/lazy-llm-wbt-test-2
rm -rf "$REPO"
mkdir -p "$REPO"
(cd "$REPO" && git init -q -b master >/dev/null && git config user.email t@t && git config user.name t && printf x > a && git add a && git commit -q -m m)
out=$(cd "$REPO" && lazy_llm_default_branch)
assert_equals "$out" "master" "repo with only master returns master"

# ──────────────────────────────────────────────────────────────────────────
# 3. lazy_llm_gather_worktrees on repo with main + one extra worktree
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: gather_worktrees emits one row per worktree..."
REPO=/tmp/lazy-llm-wbt-test-3
mk_repo "$REPO"
# Add a second worktree
(cd "$REPO" && git worktree add /tmp/lazy-llm-wbt-test-3-wt -b feature-x >/dev/null 2>&1)

out=$(cd "$REPO" && lazy_llm_gather_worktrees)
row_count=$(echo "$out" | command grep -c .)
assert_equals "$row_count" "2" "two worktrees → two rows"

# Confirm columns: each row should be 7 tab-separated fields
first_cols=$(echo "$out" | head -1 | awk -F'\t' '{print NF}')
assert_equals "$first_cols" "7" "row has 7 columns"

# Branch column for the feature-x worktree
fx_branch=$(echo "$out" | command grep 'lazy-llm-wbt-test-3-wt' | awk -F'\t' '{print $2}')
assert_equals "$fx_branch" "feature-x" "feature-x worktree branch correct"

# ──────────────────────────────────────────────────────────────────────────
# 4. Dirty marker
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: dirty marker present for dirty worktree..."
# Touch a file in the secondary worktree to make it dirty
(cd /tmp/lazy-llm-wbt-test-3-wt && printf 'dirty\n' > new-file)
out=$(cd "$REPO" && lazy_llm_gather_worktrees)
fx_dirty=$(echo "$out" | command grep 'lazy-llm-wbt-test-3-wt' | awk -F'\t' '{print $3}')
assert_equals "$fx_dirty" "*" "dirty worktree shows '*'"

# Clean it up to keep test 5 reliable
rm -f /tmp/lazy-llm-wbt-test-3-wt/new-file

# ──────────────────────────────────────────────────────────────────────────
# 5. Skips detached-HEAD worktrees
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 5: detached-HEAD worktree skipped..."
HEAD_SHA=$(cd "$REPO" && git rev-parse HEAD)
(cd "$REPO" && git worktree add --detach /tmp/lazy-llm-wbt-test-3-detached "$HEAD_SHA" >/dev/null 2>&1)

out=$(cd "$REPO" && lazy_llm_gather_worktrees)
detached_present=$(echo "$out" | command grep -c 'detached' || true)
assert_equals "$detached_present" "0" "detached worktree NOT in output"

# ──────────────────────────────────────────────────────────────────────────
# 6. cleanup_worktree happy path (clean, no force)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: cleanup_worktree removes clean worktree + deletes branch..."
REPO=/tmp/lazy-llm-wbt-test-6
mk_repo "$REPO"
(cd "$REPO" && git worktree add /tmp/lazy-llm-wbt-test-6-wt -b feat-clean >/dev/null 2>&1)
assert_dir_exists "/tmp/lazy-llm-wbt-test-6-wt" "worktree dir present before cleanup"

lazy_llm_cleanup_worktree /tmp/lazy-llm-wbt-test-6-wt yes no 2>/dev/null
rc=$?
assert_equals "$rc" "0" "cleanup returns 0 on success"

# Worktree dir gone
if [ ! -d /tmp/lazy-llm-wbt-test-6-wt ]; then
    print_pass "worktree dir removed"
else
    print_fail "worktree dir still present"
fi

# Branch deleted
if (cd "$REPO" && git rev-parse --verify --quiet refs/heads/feat-clean >/dev/null 2>&1); then
    print_fail "branch should have been deleted"
else
    print_pass "branch deleted"
fi

# ──────────────────────────────────────────────────────────────────────────
# 7. cleanup_worktree preserves branch when delete_branch=no
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 7: cleanup_worktree preserves branch when delete_branch=no..."
REPO=/tmp/lazy-llm-wbt-test-7
mk_repo "$REPO"
(cd "$REPO" && git worktree add /tmp/lazy-llm-wbt-test-7-wt -b feat-keep >/dev/null 2>&1)

lazy_llm_cleanup_worktree /tmp/lazy-llm-wbt-test-7-wt no no 2>/dev/null

if (cd "$REPO" && git rev-parse --verify --quiet refs/heads/feat-keep >/dev/null 2>&1); then
    print_pass "branch preserved when delete_branch=no"
else
    print_fail "branch was deleted unexpectedly"
fi

# ──────────────────────────────────────────────────────────────────────────
# 8. cleanup_worktree force mode handles dirty
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 8: cleanup_worktree force=yes against dirty worktree..."
REPO=/tmp/lazy-llm-wbt-test-8
mk_repo "$REPO"
(cd "$REPO" && git worktree add /tmp/lazy-llm-wbt-test-8-wt -b feat-dirty >/dev/null 2>&1)
(cd /tmp/lazy-llm-wbt-test-8-wt && printf 'dirty\n' > extra)

lazy_llm_cleanup_worktree /tmp/lazy-llm-wbt-test-8-wt yes yes 2>/dev/null
rc=$?
assert_equals "$rc" "0" "force cleanup succeeds against dirty worktree"

if [ ! -d /tmp/lazy-llm-wbt-test-8-wt ]; then
    print_pass "dirty worktree removed with --force"
else
    print_fail "dirty worktree still present"
fi

# ──────────────────────────────────────────────────────────────────────────
# 9. Dashboard structural: render_worktrees_tab no longer placeholder
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 9: render_worktrees_tab uses gather_worktrees..."
if command grep -q 'lazy_llm_gather_worktrees' "$DASHBOARD"; then
    print_pass "dashboard calls lazy_llm_gather_worktrees"
else
    print_fail "dashboard does NOT call lazy_llm_gather_worktrees"
fi

# Placeholder string should be gone
if command grep -q 'Worktrees tab — coming soon' "$DASHBOARD"; then
    print_fail "placeholder text still present"
else
    print_pass "placeholder text removed"
fi

# ──────────────────────────────────────────────────────────────────────────
# 10. Dispatch verbs + main-loop allowlist
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 10: dispatch_action has worktree verbs..."
for verb in worktree-open worktree-new worktree-lazygit worktree-cleanup; do
    if command grep -q "action:$verb" "$DASHBOARD"; then
        print_pass "dispatch handles action:$verb"
    else
        print_fail "dispatch does NOT handle action:$verb"
    fi
done

echo ""
echo "Test 11: main loop allowlist includes worktree verbs..."
loop_arm=$(command grep -E 'action:switch:\*\|action:kill' "$DASHBOARD")
assert_contains "$loop_arm" "worktree-open:" "loop arm includes worktree-open"
assert_contains "$loop_arm" "worktree-new" "loop arm includes worktree-new"
assert_contains "$loop_arm" "worktree-lazygit:" "loop arm includes worktree-lazygit"
assert_contains "$loop_arm" "worktree-cleanup:" "loop arm includes worktree-cleanup"

# ──────────────────────────────────────────────────────────────────────────
# 12. Help text mentions worktrees actions
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 12: help text documents Worktrees actions..."
help_out=$("$DASHBOARD" --help 2>&1)
assert_contains "$help_out" "Worktrees" "usage mentions Worktrees tab"
assert_contains "$help_out" "g" "usage documents g (lazygit) key"

# ──────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Passed: $ASSERTIONS_PASSED"
echo "Failed: $ASSERTIONS_FAILED"

if [ "$ASSERTIONS_FAILED" -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
