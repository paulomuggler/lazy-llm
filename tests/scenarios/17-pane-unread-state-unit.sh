#!/usr/bin/env bash
# Test: Unit test for the "unread" pane status (finished a turn, not looked
# at since) and the per-status cross-workspace summary.
# (status-unread-state-and-aggregate-counts). Runs against an isolated tmux
# server AND an isolated HOME, so neither the user's live sessions nor
# their real ~/.cache/lazy-llm markers are touched.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="pane-unread-state-unit"

REPO_ROOT="$TESTS_DIR/.."
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"

# Run a snippet against a fresh isolated tmux server + HOME; prints the
# snippet's stdout. The server is killed and both dirs removed afterwards.
# Pane helpers available to the snippet:
#   show_idle <pane>     repaint the pane with a bare ❯ prompt
#   show_working <pane>  repaint the pane with an "esc to interrupt" line
run_isolated() {
    local sandbox
    sandbox=$(mktemp -d /tmp/lazy-llm-test-unread-XXXXXX)
    mkdir -p "$sandbox/tmux" "$sandbox/home"
    TMUX_TMPDIR="$sandbox/tmux" HOME="$sandbox/home" bash <<EOF
unset TMUX TMUX_PANE
source "$LIB_FILE"
tmux -f /dev/null new-session -d -s _unread -x 120 -y 20 "exec sleep 600"
paint() { tmux clear-history -t "\$1"; tmux respawn-pane -k -t "\$1" "printf '\033[2J\033[H%s\n' '\$2'; exec sleep 600"; sleep 0.3; }
show_idle() { paint "\$1" '❯ '; }
show_working() { paint "\$1" 'Thinking… esc to interrupt'; }
P=\$(tmux display-message -t _unread -p '#{pane_id}')
$1
tmux kill-server 2>/dev/null
EOF
    rm -rf "$sandbox"
}

# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: glyph + color mapping covers every status..."
source "$LIB_FILE"
assert_equals "$(lazy_llm_status_glyph unread)" "◉" "unread glyph"
assert_equals "$(lazy_llm_status_glyph waiting)" "◐" "waiting glyph"
assert_equals "$(lazy_llm_status_glyph working)" "●" "working glyph"
assert_equals "$(lazy_llm_status_glyph idle)" "○" "idle glyph"
assert_equals "$(lazy_llm_status_glyph bogus)" "?" "unknown glyph"
assert_equals "$(lazy_llm_status_color unread)" "#5fff00" "unread is the green 'your turn' color"
assert_equals "$(lazy_llm_status_color idle)" "#bcbcbc" "idle is the calm gray"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 2: lazy_llm_render_summary — per-status counts, attention order, zeros omitted..."
actual=$(lazy_llm_render_summary "#fff" 3 1 2 0 4)
expected="3ws #[fg=#ff00af,bold]1◐#[fg=#fff,nobold] #[fg=#5fff00,bold]2◉#[fg=#fff,nobold] #[fg=#bcbcbc]4○#[fg=#fff,nobold]"
assert_equals "$actual" "$expected" "mixed counts render waiting, unread, idle (working=0 omitted)"
assert_equals "$(lazy_llm_render_summary "#fff" 2 0 0 0 0)" "2ws" "all-zero counts render as just the workspace count"
assert_equals "$(lazy_llm_render_summary "#fff" 0)" "0ws" "missing counts don't error"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: mark / clear / precedence on a real (detached, so unfocused) pane..."
output=$(run_isolated '
show_idle "$P"
echo "base=$(lazy_llm_detect_pane_status "$P" gemini)"
lazy_llm_pane_is_focused "$P" && echo "focused=yes" || echo "focused=no"
lazy_llm_mark_unread "$P"
echo "marked=$(lazy_llm_detect_pane_status "$P" gemini)"
lazy_llm_clear_unread "$P"
echo "cleared=$(lazy_llm_detect_pane_status "$P" gemini)"
')
assert_contains "$output" "base=idle" "idle pane with no marker is idle"
assert_contains "$output" "focused=no" "a pane in a detached session is not focused"
assert_contains "$output" "marked=unread" "marked idle pane reports unread"
assert_contains "$output" "cleared=idle" "clearing the marker returns it to idle"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: working outranks an unread marker; marker is kept, not consumed..."
output=$(run_isolated '
show_idle "$P"
lazy_llm_mark_unread "$P"
show_working "$P"
lazy_llm_mark_unread "$P"   # respawn changed pane_pid; re-key the marker to it
echo "while-working=$(lazy_llm_detect_pane_status "$P" claude)"
[ -f "$HOME/.cache/lazy-llm/unread/$P" ] && echo "marker=kept" || echo "marker=gone"
')
assert_contains "$output" "while-working=working" "working wins over an unread marker"
assert_contains "$output" "marker=kept" "detecting working does not clear the marker"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 5: a marker whose pid doesn't match the pane (reused %N id) is ignored and removed..."
output=$(run_isolated '
show_idle "$P"
mkdir -p "$HOME/.cache/lazy-llm/unread"
echo 999999 > "$HOME/.cache/lazy-llm/unread/$P"
echo "status=$(lazy_llm_detect_pane_status "$P" gemini)"
[ -f "$HOME/.cache/lazy-llm/unread/$P" ] && echo "marker=kept" || echo "marker=gone"
')
assert_contains "$output" "status=idle" "stale-pid marker does not make the pane unread"
assert_contains "$output" "marker=gone" "stale-pid marker is cleaned up"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: non-claude tools — scrape-observed working -> idle marks unread..."
output=$(run_isolated '
show_working "$P"
echo "first=$(lazy_llm_detect_pane_status "$P" gemini)"
show_idle "$P"
echo "second=$(lazy_llm_detect_pane_status "$P" gemini)"
echo "third=$(lazy_llm_detect_pane_status "$P" gemini)"
')
assert_contains "$output" "first=working" "working observed"
assert_contains "$output" "second=unread" "transition to idle marks unread"
assert_contains "$output" "third=unread" "stays unread on the next poll"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 7: claude — the scrape transition does NOT mark (the Stop hook owns that)..."
output=$(run_isolated '
show_working "$P"
lazy_llm_detect_pane_status "$P" claude >/dev/null
show_idle "$P"
echo "after=$(lazy_llm_detect_pane_status "$P" claude)"
')
assert_contains "$output" "after=idle" "claude pane goes working -> idle without a marker"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 8: lazy_llm_compute_summary counts panes per status across workspaces..."
output=$(run_isolated '
tmux set-option -t _unread @lazy_llm 1
tmux set-option -w -t _unread @AI_PANES "$P"
tmux set-option -w -t _unread @AI_TOOLS gemini
show_idle "$P"
lazy_llm_mark_unread "$P"
echo "summary=$(lazy_llm_compute_summary)"
')
assert_contains "$output" "summary=1 0 1 0 0" "one workspace, one unread pane"

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
