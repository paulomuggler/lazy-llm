#!/usr/bin/env bash
# Test: Unit test for manual dashboard tree reordering
# (dashboard-manual-list-reordering — Ctrl+Up/Ctrl+Down, scoped per tree
# level). Exercises the lib-level order helpers against an isolated tmux
# server (no live fzf flow tested — PTY-dependent, verified manually
# instead per the task's own acceptance criteria) plus structural checks
# that llm-dashboard wires the reorder keys the same way dashboard-reload-
# avoid-full-redraw wired 'z': transform(...) + an out-of-process CLI flag
# + reload-sync(...)+pos(N), never print(KEY)+accept or exit+relaunch.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="dashboard-manual-reorder-unit"

REPO_ROOT="$TESTS_DIR/.."
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"
DASHBOARD="$REPO_ROOT/lazy-llm-bin/.local/bin/llm-dashboard"

# ──────────────────────────────────────────────────────────────────────────
# 1. Library exposes the order helpers
# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: lazy-llm-lib.sh provides the manual-order helpers..."
for fn in lazy_llm_read_ws_order lazy_llm_apply_ws_order lazy_llm_move_ws_order lazy_llm_move_pane_order; do
    if command grep -qE "^${fn}\(\)" "$LIB_FILE"; then
        print_pass "$fn defined in lazy-llm-lib.sh"
    else
        print_fail "$fn NOT defined in lazy-llm-lib.sh"
    fi
done

# ──────────────────────────────────────────────────────────────────────────
# 2. Workspace order: read/apply against an isolated tmux server
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 2: lazy_llm_apply_ws_order is a no-op when no order is persisted..."
TMUX_TMPDIR=/tmp/lazy-llm-test-reorder1-$$
mkdir -p "$TMUX_TMPDIR"
export TMUX_TMPDIR

output=$(bash <<EOF
source "$LIB_FILE"
unset TMUX TMUX_PANE
tmux -f /dev/null new-session -d -s _reorder_a
tmux -f /dev/null set-option -t _reorder_a @lazy_llm 1
tmux -f /dev/null new-session -d -s _reorder_b
tmux -f /dev/null set-option -t _reorder_b @lazy_llm 1
data=\$(lazy_llm_gather_sessions)
lazy_llm_apply_ws_order "\$data" | cut -f1
tmux -f /dev/null kill-server 2>/dev/null
EOF
)
rm -rf "$TMUX_TMPDIR"

first_ws=$(echo "$output" | head -1)
assert_equals "$first_ws" "_reorder_a" "natural gather order preserved when no custom order is persisted"

echo ""
echo "Test 3: lazy_llm_move_ws_order persists a swap, scoped to workspace siblings only, appended-workspace never dropped..."
TMUX_TMPDIR=/tmp/lazy-llm-test-reorder2-$$
mkdir -p "$TMUX_TMPDIR"
export TMUX_TMPDIR

output=$(bash <<EOF
source "$LIB_FILE"
unset TMUX TMUX_PANE
tmux -f /dev/null new-session -d -s _reorder_a
tmux -f /dev/null set-option -t _reorder_a @lazy_llm 1
tmux -f /dev/null new-session -d -s _reorder_b
tmux -f /dev/null set-option -t _reorder_b @lazy_llm 1
# Move b up (should swap with a, since natural order is a, b)
lazy_llm_move_ws_order _reorder_b up
echo "ORDER1:\$(lazy_llm_read_ws_order)"
# b is now topmost (order: b, a) — moving it up again must be a no-op.
lazy_llm_move_ws_order _reorder_b up
echo "ORDER2:\$(lazy_llm_read_ws_order)"
# A third, never-moved workspace must still appear via apply_ws_order,
# appended (natural order), not silently dropped.
tmux -f /dev/null new-session -d -s _reorder_c
tmux -f /dev/null set-option -t _reorder_c @lazy_llm 1
data=\$(lazy_llm_gather_sessions)
echo "APPLIED:\$(lazy_llm_apply_ws_order "\$data" | cut -f1 | tr '\n' ',')"
tmux -f /dev/null kill-server 2>/dev/null
EOF
)
rm -rf "$TMUX_TMPDIR"

order1=$(echo "$output" | command grep '^ORDER1:' | cut -d: -f2)
order2=$(echo "$output" | command grep '^ORDER2:' | cut -d: -f2)
applied=$(echo "$output" | command grep '^APPLIED:' | cut -d: -f2)

assert_equals "$order1" "_reorder_b _reorder_a" "moving b up swaps it with a in the persisted order"
assert_equals "$order2" "_reorder_b _reorder_a" "moving the already-topmost workspace up is a no-op"
assert_equals "$applied" "_reorder_b,_reorder_a,_reorder_c," "a workspace never explicitly moved is appended in natural order, not dropped"

# ──────────────────────────────────────────────────────────────────────────
# 3. Pane order: swap adjacent panes within ONE workspace, never crossing
#    into another workspace's panes
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: lazy_llm_move_pane_order swaps adjacent panes (AI_PANES/AI_TOOLS/AI_PANE_NAMES), bounds-checked, scoped to its own workspace..."
TMUX_TMPDIR=/tmp/lazy-llm-test-reorder3-$$
mkdir -p "$TMUX_TMPDIR"
export TMUX_TMPDIR

output=$(bash <<EOF
source "$LIB_FILE"
unset TMUX TMUX_PANE
tmux -f /dev/null new-session -d -s _reorder_panes
win=\$(tmux -f /dev/null list-windows -t _reorder_panes -F '#{window_index}' | head -1)
tmux -f /dev/null set-option -w -t "_reorder_panes:\$win" @AI_PANES "%100 %101"
tmux -f /dev/null set-option -w -t "_reorder_panes:\$win" @AI_TOOLS "claude gemini"
tmux -f /dev/null set-option -w -t "_reorder_panes:\$win" @AI_PANE_NAMES "_ custom"
tmux -f /dev/null set-option -w -t "_reorder_panes:\$win" @AI_PANE_IDX 0

# An unrelated second workspace's panes — must stay untouched by the swap below.
tmux -f /dev/null new-session -d -s _reorder_other
owin=\$(tmux -f /dev/null list-windows -t _reorder_other -F '#{window_index}' | head -1)
tmux -f /dev/null set-option -w -t "_reorder_other:\$owin" @AI_PANES "%200 %201"
tmux -f /dev/null set-option -w -t "_reorder_other:\$owin" @AI_TOOLS "claude claude"

lazy_llm_move_pane_order _reorder_panes "\$win" 0 down
echo "PANES1:\$(tmux -f /dev/null show-option -wv -t "_reorder_panes:\$win" @AI_PANES)"
echo "TOOLS1:\$(tmux -f /dev/null show-option -wv -t "_reorder_panes:\$win" @AI_TOOLS)"
echo "NAMES1:\$(tmux -f /dev/null show-option -wv -t "_reorder_panes:\$win" @AI_PANE_NAMES)"
echo "IDX1:\$(tmux -f /dev/null show-option -wv -t "_reorder_panes:\$win" @AI_PANE_IDX)"

# Swap idx0/idx1 again: sanity that the swap is a true, reversible swap
# (not a one-way move) — should land back at the original order.
lazy_llm_move_pane_order _reorder_panes "\$win" 0 down
echo "PANES2:\$(tmux -f /dev/null show-option -wv -t "_reorder_panes:\$win" @AI_PANES)"

echo "OTHER_PANES:\$(tmux -f /dev/null show-option -wv -t "_reorder_other:\$owin" @AI_PANES)"
tmux -f /dev/null kill-server 2>/dev/null
EOF
)
rm -rf "$TMUX_TMPDIR"

panes1=$(echo "$output" | command grep '^PANES1:' | cut -d: -f2)
tools1=$(echo "$output" | command grep '^TOOLS1:' | cut -d: -f2)
names1=$(echo "$output" | command grep '^NAMES1:' | cut -d: -f2)
idx1=$(echo "$output" | command grep '^IDX1:' | cut -d: -f2)
panes2=$(echo "$output" | command grep '^PANES2:' | cut -d: -f2)
other_panes=$(echo "$output" | command grep '^OTHER_PANES:' | cut -d: -f2)

assert_equals "$panes1" "%101 %100" "moving idx0 down swaps @AI_PANES"
assert_equals "$tools1" "gemini claude" "@AI_TOOLS swapped in parallel with @AI_PANES"
assert_equals "$names1" "custom _" "@AI_PANE_NAMES swapped in parallel too"
assert_equals "$idx1" "1" "@AI_PANE_IDX follows the pane it pointed at across the swap"
assert_equals "$panes2" "%100 %101" "swapping idx0/idx1 again reverses the prior swap (true swap, not a one-way move)"
assert_equals "$other_panes" "%200 %201" "an unrelated workspace's panes are never touched by another workspace's pane reorder"

echo ""
echo "Test 5: lazy_llm_move_pane_order no-ops (not errors) at either end of the pane list..."
TMUX_TMPDIR=/tmp/lazy-llm-test-reorder4-$$
mkdir -p "$TMUX_TMPDIR"
export TMUX_TMPDIR

output=$(bash <<EOF
set -e
source "$LIB_FILE"
unset TMUX TMUX_PANE
tmux -f /dev/null new-session -d -s _reorder_bounds
win=\$(tmux -f /dev/null list-windows -t _reorder_bounds -F '#{window_index}' | head -1)
tmux -f /dev/null set-option -w -t "_reorder_bounds:\$win" @AI_PANES "%300 %301 %302"
tmux -f /dev/null set-option -w -t "_reorder_bounds:\$win" @AI_TOOLS "claude claude claude"

lazy_llm_move_pane_order _reorder_bounds "\$win" 0 up
echo "TOP_NOOP:\$(tmux -f /dev/null show-option -wv -t "_reorder_bounds:\$win" @AI_PANES)"
lazy_llm_move_pane_order _reorder_bounds "\$win" 2 down
echo "BOTTOM_NOOP:\$(tmux -f /dev/null show-option -wv -t "_reorder_bounds:\$win" @AI_PANES)"
tmux -f /dev/null kill-server 2>/dev/null
EOF
)
rm -rf "$TMUX_TMPDIR"

top_noop=$(echo "$output" | command grep '^TOP_NOOP:' | cut -d: -f2)
bottom_noop=$(echo "$output" | command grep '^BOTTOM_NOOP:' | cut -d: -f2)
assert_equals "$top_noop" "%300 %301 %302" "moving the first pane up is a no-op"
assert_equals "$bottom_noop" "%300 %301 %302" "moving the last pane down is a no-op"

# ──────────────────────────────────────────────────────────────────────────
# 4. Structural: llm-dashboard wires Ctrl-Up/Ctrl-Down the same way 'z' is
#    wired (transform + out-of-process CLI flag + reload-sync+pos(N)) —
#    NOT print(KEY)+accept, NOT execute-silent()+reload(), NOT --track.
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: Ctrl-Up/Ctrl-Down bound to transform(...--reorder-transform...), never print+accept..."
if command grep -qE "ctrl-up:transform\([^)]*--reorder-transform[^)]*\)" "$DASHBOARD" \
   && command grep -qE "ctrl-down:transform\([^)]*--reorder-transform[^)]*\)" "$DASHBOARD"; then
    print_pass "Ctrl-Up/Ctrl-Down bound to transform(...--reorder-transform...)"
else
    print_fail "Ctrl-Up/Ctrl-Down are not wired to transform(...--reorder-transform...)"
fi
if command grep -qE "bind='ctrl-up:print" "$DASHBOARD" || command grep -qE "bind='ctrl-down:print" "$DASHBOARD"; then
    print_fail "Ctrl-Up/Ctrl-Down still use print(KEY)+accept (exit+relaunch) somewhere"
else
    print_pass "no print(KEY)+accept binding for Ctrl-Up/Ctrl-Down"
fi

echo ""
echo "Test 7: --reorder-transform CLI mode exists and reuses _dashboard_build_rows..."
if command grep -q -- '--reorder-transform)' "$DASHBOARD"; then
    print_pass "--reorder-transform CLI flag present"
else
    print_fail "--reorder-transform CLI flag missing"
fi

echo ""
echo "Test 8: --reorder-transform uses reload-sync (not plain reload) for the printed action chain..."
if command grep -A80 -- '--reorder-transform)' "$DASHBOARD" | command grep -qE "printf 'reload-sync\(%s --emit-rows\)\+pos\(%s\)"; then
    print_pass "--reorder-transform prints reload-sync(...)+pos(N)"
else
    print_fail "--reorder-transform does not print reload-sync(...)+pos(N)"
fi
if command grep -A80 -- '--reorder-transform)' "$DASHBOARD" | command grep -v '^\s*#' | command grep -qE "printf 'reload\(%s"; then
    print_fail "--reorder-transform uses plain (non-sync) reload(...) — same race --fold-transform's comment documents"
else
    print_pass "--reorder-transform does not use plain reload(...)"
fi

echo ""
echo "Test 9: no --track/--id-nth reintroduced on the Workspaces fzf call..."
if command grep -v '^\s*#' "$DASHBOARD" | command grep -q -- '--track' \
   || command grep -v '^\s*#' "$DASHBOARD" | command grep -qE -- "--id-nth[= ]"; then
    print_fail "--track/--id-nth present — reorder must use explicit pos(N) like --fold-transform, not --track"
else
    print_pass "--track/--id-nth not reintroduced"
fi

echo ""
echo "Test 10: _dashboard_build_rows applies the persisted workspace order (single source of truth for render_sessions_tab, --emit-rows, --fold-transform AND --reorder-transform)..."
build_rows_body=$(command grep -A20 '^_dashboard_build_rows()' "$DASHBOARD")
if echo "$build_rows_body" | command grep -q 'lazy_llm_apply_ws_order'; then
    print_pass "_dashboard_build_rows calls lazy_llm_apply_ws_order"
else
    print_fail "_dashboard_build_rows does not apply the persisted workspace order"
fi

echo ""
echo "Test 11: Ctrl-Up/Ctrl-Down added to the /-search unbind/rebind key lists (same precedent as 'z')..."
unbind_line=$(command grep -oE "unbind\([^)]*\)" "$DASHBOARD" | command grep 'ctrl-up' | head -1)
rebind_line=$(command grep -oE "rebind\([^)]*\)" "$DASHBOARD" | command grep 'ctrl-up' | head -1)
assert_contains "$unbind_line" "ctrl-down" "the '/' unbind list includes both ctrl-up and ctrl-down"
assert_contains "$rebind_line" "ctrl-down" "the 'tab' rebind list includes both ctrl-up and ctrl-down"

echo ""
echo "Test 12: Help tab documents the reorder key..."
help_src=$(command grep -A30 '^render_help_tab()' "$DASHBOARD")
if echo "$help_src" | command grep -qi 'reorder'; then
    print_pass "Help tab text mentions reorder"
else
    print_fail "Help tab text does not mention reorder"
fi

echo ""
echo "Test 13: workspace order state is server-scoped (tmux set-option -s), not session/window-scoped..."
if command grep -qE "set-option -s @lazy_llm_ws_order" "$LIB_FILE"; then
    print_pass "@lazy_llm_ws_order persisted via 'tmux set-option -s' (server-scoped)"
else
    print_fail "@lazy_llm_ws_order is not persisted server-scoped"
fi

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
