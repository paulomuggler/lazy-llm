#!/usr/bin/env bash
# Test: Unit test for lazy_llm_setup_worktree + companion helpers.
# Uses disposable /tmp git repos, no tmux required.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="worktree-primitive-unit"

LIB_FILE="$TESTS_DIR/../llm-send-bin/.local/bin/lazy-llm-lib.sh"
if [ ! -f "$LIB_FILE" ]; then
    echo "ERROR: lazy-llm-lib.sh not found at $LIB_FILE" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_FILE"

# ──────────────────────────────────────────────────────────────────────────
# Test helpers
# ──────────────────────────────────────────────────────────────────────────
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
    rm -rf /tmp/lazy-llm-wt-test-*
}

trap cleanup_repos EXIT

# ──────────────────────────────────────────────────────────────────────────
# Test 1: New branch + new worktree under .worktrees default
# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: New branch creates worktree at .worktrees/<branch>..."
REPO=/tmp/lazy-llm-wt-test-1
mk_repo "$REPO"

unset LAZY_LLM_WORKTREE_DIR
out=$(cd "$REPO" && lazy_llm_setup_worktree feature-x 2>/dev/null)
rc=$?
assert_equals "$rc" "0" "setup_worktree exits 0 for new branch"
assert_equals "$out" "$REPO/.worktrees/feature-x" "returns expected path"
assert_dir_exists "$REPO/.worktrees/feature-x" "worktree directory created"

(cd "$REPO" && git rev-parse --verify refs/heads/feature-x >/dev/null 2>&1)
assert_equals "$?" "0" "branch feature-x exists in repo"

assert_file_exists "$REPO/.gitignore" ".gitignore created"
command grep -qxF ".worktrees/" "$REPO/.gitignore"
assert_equals "$?" "0" ".worktrees/ added to .gitignore"

# ──────────────────────────────────────────────────────────────────────────
# Test 2: Existing branch (not checked out) — worktree points at it
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 2: Pre-existing branch reused as worktree..."
REPO=/tmp/lazy-llm-wt-test-2
mk_repo "$REPO"
(cd "$REPO" && git branch existing-feature)

out=$(cd "$REPO" && lazy_llm_setup_worktree existing-feature 2>/dev/null)
rc=$?
assert_equals "$rc" "0" "setup_worktree exits 0 for existing branch"
assert_dir_exists "$REPO/.worktrees/existing-feature" "worktree dir created"

# Verify the worktree is on the existing branch
branch=$(cd "$REPO/.worktrees/existing-feature" && git branch --show-current)
assert_equals "$branch" "existing-feature" "worktree checked out to existing-feature"

# ──────────────────────────────────────────────────────────────────────────
# Test 3: Branch already checked out elsewhere → refuse
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: Branch checked out elsewhere → refusal..."
REPO=/tmp/lazy-llm-wt-test-3
mk_repo "$REPO"
(cd "$REPO" && git checkout -q -b in-use)
# Now the branch is checked out in the main worktree; trying to create
# another worktree for it should refuse.

set +e
out_err=$(cd "$REPO" && lazy_llm_setup_worktree in-use 2>&1 >/dev/null)
rc=$?
set -e
assert_pattern "$rc" "^[1-9]" "setup_worktree exits non-zero when branch already checked out"
assert_contains "$out_err" "already checked out" "error message mentions 'already checked out'"

# ──────────────────────────────────────────────────────────────────────────
# Test 4: Pre-existing worktree (registered) → return same path, no error
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: Pre-existing worktree returned idempotently..."
REPO=/tmp/lazy-llm-wt-test-4
mk_repo "$REPO"

out1=$(cd "$REPO" && lazy_llm_setup_worktree reuse-me 2>/dev/null)
out2=$(cd "$REPO" && lazy_llm_setup_worktree reuse-me 2>/dev/null)
assert_equals "$out1" "$out2" "second call returns same path"
assert_equals "$out2" "$REPO/.worktrees/reuse-me" "path matches expected"

# ──────────────────────────────────────────────────────────────────────────
# Test 5: Non-git directory → refuse
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 5: Non-git directory refused..."
NONGIT=/tmp/lazy-llm-wt-test-5-nongit
rm -rf "$NONGIT"
mkdir -p "$NONGIT"

set +e
out_err=$(cd "$NONGIT" && lazy_llm_setup_worktree anything 2>&1 >/dev/null)
rc=$?
set -e
assert_pattern "$rc" "^[1-9]" "setup_worktree exits non-zero outside git repo"
assert_contains "$out_err" "not inside a git repository" "error mentions not in git repo"

# ──────────────────────────────────────────────────────────────────────────
# Test 6: LAZY_LLM_WORKTREE_DIR override → no .gitignore touch
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: LAZY_LLM_WORKTREE_DIR override + no gitignore append..."
REPO=/tmp/lazy-llm-wt-test-6
EXTERNAL=/tmp/lazy-llm-wt-test-6-external
mk_repo "$REPO"
rm -rf "$EXTERNAL"

export LAZY_LLM_WORKTREE_DIR="$EXTERNAL"
out=$(cd "$REPO" && lazy_llm_setup_worktree off-tree 2>/dev/null)
rc=$?
unset LAZY_LLM_WORKTREE_DIR

assert_equals "$rc" "0" "override path works"
assert_equals "$out" "$EXTERNAL/off-tree" "worktree at override location"
assert_dir_exists "$EXTERNAL/off-tree" "external worktree created"

# No .gitignore should have been created since the in-repo default wasn't used
if [ -f "$REPO/.gitignore" ]; then
    command grep -qxF ".worktrees/" "$REPO/.gitignore" && \
        print_fail ".worktrees/ should NOT be in .gitignore when using override" || \
        print_pass ".gitignore left untouched with override"
else
    print_pass "no .gitignore created with override (correct)"
fi

# ──────────────────────────────────────────────────────────────────────────
# Test 7: Slashed branch name sanitized to dashes in path
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 7: Slashed branch names sanitized in path..."
REPO=/tmp/lazy-llm-wt-test-7
mk_repo "$REPO"

out=$(cd "$REPO" && lazy_llm_setup_worktree feature/with/slashes 2>/dev/null)
assert_equals "$out" "$REPO/.worktrees/feature-with-slashes" "slashes → dashes in path"

# But the actual branch name keeps the slashes
branch=$(cd "$REPO/.worktrees/feature-with-slashes" && git branch --show-current)
assert_equals "$branch" "feature/with/slashes" "branch name keeps slashes"

# ──────────────────────────────────────────────────────────────────────────
# Test 8: ensure_gitignore is idempotent
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 8: ensure_gitignore idempotent..."
REPO=/tmp/lazy-llm-wt-test-8
mk_repo "$REPO"

lazy_llm_ensure_gitignore "$REPO" "first/" 2>/dev/null
lazy_llm_ensure_gitignore "$REPO" "first/" 2>/dev/null  # idempotent
lazy_llm_ensure_gitignore "$REPO" "second/" 2>/dev/null

count_first=$(command grep -cxF "first/" "$REPO/.gitignore" 2>/dev/null)
count_second=$(command grep -cxF "second/" "$REPO/.gitignore" 2>/dev/null)
assert_equals "$count_first" "1" "first/ appears exactly once"
assert_equals "$count_second" "1" "second/ appears exactly once"

# ──────────────────────────────────────────────────────────────────────────
# Test 9: find_session_for_path returns empty when no match (no tmux required)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 9: find_session_for_path returns empty for non-matching path..."
# No tmux server → gather_sessions returns nothing → find returns empty
TMUX_TMPDIR=/tmp/lazy-llm-wt-test-9-tmux
mkdir -p "$TMUX_TMPDIR"
export TMUX_TMPDIR
unset TMUX TMUX_PANE

out=$(lazy_llm_find_session_for_path "/some/path/that/no/session/has")
assert_empty "$out" "empty result when no matching session"

rm -rf "$TMUX_TMPDIR"
unset TMUX_TMPDIR

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
