#!/usr/bin/env bash
# Test: Claude's worktrees shown by lazy-llm (claude-subagent-worktrees-ui,
# spec .agents/TODO/specs/claude-subagent-worktrees.md §10): the AI pane
# border's ⎇×N and the dashboard tree row's.
# The Worktrees tab (owners, I) is covered in 14-worktree-bridge-tab-unit.
# Claude worktrees come from `llm-wt claude-hook` payloads with TMUX_PANE set
# to a sandbox pane: no Claude needed.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="claude-worktrees-ui-unit"

REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"
LLMWT="$REPO_ROOT/llm-wt-bin/.local/bin/llm-wt"

# With $TMUX set, tmux ignores TMUX_TMPDIR and reaches the user's own server.
unset TMUX TMUX_PANE CLAUDE_PROJECT_DIR LAZY_LLM_WORKTREE_DIR

sandbox=$(mktemp -d /tmp/lazy-llm-test-claudeui-XXXXXX)
cleanup_sandbox() {
    env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$sandbox/tmux" tmux kill-server 2>/dev/null || true
    rm -rf "$sandbox"
}
trap cleanup_sandbox EXIT
# Work from inside the sandbox: an empty path given to `git -C` means the
# current directory, which must never be the lazy-llm checkout.
cd "$sandbox" || exit 1
export GIT_CEILING_DIRECTORIES=/tmp
export HOME="$sandbox/home" TMUX_TMPDIR="$sandbox/tmux" LAZY_LLM_STATE_DIR="$sandbox/state"
HOME_BIN="$HOME/.local/bin"
mkdir -p "$HOME_BIN" "$TMUX_TMPDIR"
unset XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE
git config --global user.email test@test
git config --global user.name test
git config --global init.defaultBranch main
for f in llm-send-bin/.local/bin/lazy-llm-lib.sh llm-wt-bin/.local/bin/llm-wt \
         lazy-llm-bin/.local/bin/llm-dashboard lazy-llm-bin/.local/bin/llm-pane-border; do
    ln -sf "$REPO_ROOT/$f" "$HOME_BIN/${f##*/}"
done
# shellcheck source=/dev/null
source "$LIB_FILE"

# Claude's WorktreeCreate as the plugin runs it; $3 = the owning pane.
claude_wt() {
    printf '{"session_id":"s1","cwd":"%s","hook_event_name":"WorktreeCreate","name":"%s"}' "$1" "$2" \
        | TMUX_PANE="$3" "$LLMWT" claude-hook 2>/dev/null
}
untag() { sed 's/#\[[^]]*\]//g'; }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
# Literal substring checks (assert_contains matches a regex; these needles
# carry "×", "(" and paths).
assert_has() {
    if [[ "$1" == *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  Looking for: '$2'"; echo "  In text: '${1:0:300}...'"; fi
}
assert_lacks() {
    if [[ "$1" != *"$2"* ]]; then ((ASSERTIONS_PASSED++)); print_pass "$3"
    else print_fail "$3"; echo "  Unexpected: '$2'"; fi
}

R="$sandbox/repo"
mkdir -p "$R/src"
git -C "$R" init -q
printf 'l1\nl2\nl3\nl4\n' > "$R/src/x.lua"
git -C "$R" add -A && git -C "$R" commit -qm init

# A workspace with two AI panes, P and Q, both in the main directory.
tmux -f /dev/null new-session -d -s cws -c "$R" -x 200 -y 50 "exec sleep 300"
P=$(tmux display -t cws -p '#{pane_id}')
Q=$(tmux split-window -t "$P" -c "$R" -P -F '#{pane_id}' "exec sleep 300")
tmux set-option -t cws @lazy_llm 1
tmux set-option -t cws @lazy_llm_dir "$R"
tmux set-option -w -t cws @AI_PANE_ID "$P"
tmux set-option -w -t cws @AI_PANES "$P $Q"
tmux set-option -w -t cws @AI_TOOLS "claude claude"
tmux set-option -w -t cws @AI_PANE_IDX 0

# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: lazy_llm_claude_worktree_owners..."
assert_equals "$(lazy_llm_claude_worktree_owners "$R")" "" "none yet: nothing"
WA=$(claude_wt "$R" agent-a "$P")
WB=$(claude_wt "$R" agent-b "$P")
WC=$(claude_wt "$R" agent-c "$Q")
WN=$(claude_wt "$R" agent-n "")
WP=$("$LLMWT" create "$R" pw 2>/dev/null)
printf 'l1\nl2\nl3\nl4\nfrom-a\n' > "$WA/src/x.lua"
owners=$(lazy_llm_claude_worktree_owners "$R" | sort)
assert_equals "$owners" "$(printf '%s\t%s\n%s\t%s\n%s\t%s' "$P" "$WA" "$P" "$WB" "$Q" "$WC" | sort)" \
    "one row per Claude worktree with a pane: pane<TAB>path (none for agent-n or the pane worktree)"
assert_dir_exists "$WN" "setup: agent-n (made outside tmux) exists"
assert_equals "$(lazy_llm_claude_worktree_owners "$WP" | sort)" "$owners" "same answer from inside a worktree (shared config)"
assert_equals "$(lazy_llm_claude_worktree_owners "$sandbox")" "" "not a repo: nothing"
assert_equals "$(lazy_llm_claude_worktree_owners "")" "" "empty dir: nothing (never the current directory)"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 2: border git segment ends with ⎇×N for the owning pane..."
seg() { lazy_llm_git_segment "$1" T D "${2:-}" | untag; }
sha=$(git -C "$R" rev-parse --short=7 HEAD)
assert_equals "$(seg "$R" "$P")" "main $sha local ⎇×2" "pane P owns two"
assert_equals "$(seg "$R" "$Q")" "main $sha local ⎇×1" "pane Q owns one"
assert_equals "$(seg "$R" "%9999")" "main $sha local" "a pane that owns none: unchanged"
assert_equals "$(seg "$R")" "main $sha local" "no pane id: unchanged"
assert_equals "$(seg "$WP" "$P")" "⎇ pw→main $sha ⎇×2" "from a pane worktree too (the repo's config is shared)"
# Cost: one git config for the whole repo, plus one for-each-ref when some
# worktree records a pane. Never a git call per worktree.
mkdir -p "$sandbox/gitshim"
real_git=$(command -v git)
printf '#!/bin/sh\necho "$*" >> "%s/gitcalls"\nexec "%s" "$@"\n' "$sandbox" "$real_git" > "$sandbox/gitshim/git"
chmod +x "$sandbox/gitshim/git"
: > "$sandbox/gitcalls"; PATH="$sandbox/gitshim:$PATH" lazy_llm_git_segment "$R" T D "$P" >/dev/null
assert_equals "$(grep -c '' "$sandbox/gitcalls")" "4" "4 git calls with Claude worktrees (rev-parse, status, config, for-each-ref)"
assert_equals "$(grep -c -- '--get-regexp' "$sandbox/gitcalls")" "1" "...one of them a single config --get-regexp"
assert_has "$(cat "$sandbox/gitcalls")" "for-each-ref" "...and one for-each-ref for all of them"
R0="$sandbox/plain"; mkdir -p "$R0"; git -C "$R0" init -q; git -C "$R0" commit -q --allow-empty -m i
: > "$sandbox/gitcalls"; PATH="$sandbox/gitshim:$PATH" lazy_llm_git_segment "$R0" T D "$P" >/dev/null
assert_equals "$(grep -c '' "$sandbox/gitcalls")" "3" "3 git calls in a repo without any (no for-each-ref)"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: llm-pane-border and the dashboard tree row..."
border() { "$HOME_BIN/llm-pane-border" "$1" claude | untag; }
assert_has "$(border "$P")" "│ main $sha local ⎇×2 " "P's border ends with ⎇×2"
assert_has "$(border "$Q")" "│ main $sha local ⎇×1 " "Q's border ends with ⎇×1"
rows=$("$HOME_BIN/llm-dashboard" --emit-rows cws 2>/dev/null | strip)
assert_has "$(grep "pane:cws:0:$P" <<< "$rows" | cut -f2)" "⎇×2" "tree row for P carries ⎇×2"
assert_has "$(grep "pane:cws:1:$Q" <<< "$rows" | cut -f2)" "⎇×1" "tree row for Q carries ⎇×1"
# A worktree whose directory is gone no longer counts.
rm -rf "$WB"
assert_has "$(border "$P")" "│ main $sha local ⎇×1 " "a deleted directory stops counting"
"$LLMWT" remove "$WC" >/dev/null 2>&1
assert_lacks "$(border "$Q")" "⎇×" "removed through llm-wt: no ⎇× at all"
rows=$("$HOME_BIN/llm-dashboard" --emit-rows cws 2>/dev/null | strip)
assert_lacks "$(grep "pane:cws:1:$Q" <<< "$rows" | cut -f2)" "⎇×" "...on the tree row either"
tmux set-option -g @lazy_llm_border_git off
assert_lacks "$(border "$P")" "⎇×" "@lazy_llm_border_git off drops it with the git segment"
tmux set-option -g @lazy_llm_border_git on
git -C "$R" worktree prune

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
