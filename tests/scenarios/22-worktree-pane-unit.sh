#!/usr/bin/env bash
# Test: per-pane worktree isolation (worktree-concurrency-mode).
# Covers the workspace-dir fix (spec §2). Isolated tmux server, throwaway
# git repos under /tmp.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="worktree-pane-unit"

REPO_ROOT="$TESTS_DIR/.."
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"

# When $TMUX is set, tmux uses ITS socket and ignores TMUX_TMPDIR: run from
# inside tmux, any bare `tmux` call here would hit the user's own server (a
# `kill-server` in the cleanup trap once killed it). Unset it for the whole
# script, and pin the sandbox socket explicitly as well.
unset TMUX TMUX_PANE

sandbox=$(mktemp -d /tmp/lazy-llm-test-wtpane-XXXXXX)
cleanup_sandbox() {
    env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$sandbox/tmux" tmux kill-server 2>/dev/null || true
    rm -rf "$sandbox"
}
trap cleanup_sandbox EXIT
mkdir -p "$sandbox/tmux" "$sandbox/home" "$sandbox/bin"

# ──────────────────────────────────────────────────────────────────────────
# 1. The workspace directory comes from @lazy_llm_dir, not the active pane
# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: workspace dir ignores a focused pane whose cwd is elsewhere..."
mkdir -p "$sandbox/ws" "$sandbox/elsewhere"
output=$(TMUX_TMPDIR="$sandbox/tmux" HOME="$sandbox/home" bash <<EOF
unset TMUX TMUX_PANE
source "$LIB_FILE"
tmux -f /dev/null new-session -d -s myws -c "$sandbox/ws" -x 120 -y 30 "exec sleep 60"
tmux set-option -t myws @lazy_llm 1
tmux set-option -t myws @lazy_llm_dir "$sandbox/ws"
# A second pane in another directory, focused (the active pane)
tmux split-window -t myws -c "$sandbox/elsewhere" "exec sleep 60"
echo "active-path=\$(tmux display -t myws -p '#{pane_current_path}')"
echo "gather-dir=\$(lazy_llm_gather_sessions | cut -f2)"
echo "find-elsewhere=<\$(lazy_llm_find_session_for_path "$sandbox/elsewhere")>"
echo "find-ws=<\$(lazy_llm_find_session_for_path "$sandbox/ws")>"
echo "wsdir=\$(lazy_llm_workspace_dir myws)"
# A session from before @lazy_llm_dir: falls back to the active pane's path
tmux -f /dev/null new-session -d -s oldws -c "$sandbox/ws" "exec sleep 60"
tmux set-option -t oldws @lazy_llm 1
echo "wsdir-legacy=\$(lazy_llm_workspace_dir oldws)"
EOF
)
assert_contains "$output" "active-path=$sandbox/elsewhere" "setup: the focused pane is in the other dir"
assert_contains "$output" "gather-dir=$sandbox/ws" "gather_sessions reports @lazy_llm_dir"
assert_contains "$output" "find-elsewhere=<>" "find_session_for_path doesn't bind the workspace to the pane's cwd"
assert_contains "$output" "find-ws=<myws>" "find_session_for_path still finds the workspace by its dir"
assert_contains "$output" "wsdir=$sandbox/ws" "lazy_llm_workspace_dir reads @lazy_llm_dir"
assert_contains "$output" "wsdir-legacy=$sandbox/ws" "lazy_llm_workspace_dir falls back to the pane path"

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
