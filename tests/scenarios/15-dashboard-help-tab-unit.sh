#!/usr/bin/env bash
# Test: Structural unit checks for the dashboard's Help tab (dashboard-help-tab) —
# converted from a transient tmux display-popup overlay into a proper tab, reachable
# from either other tab via '3' or '?'. Live fzf flow isn't unit-testable
# (PTY-dependent); we verify the wiring is correct.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="dashboard-help-tab-unit"

REPO_ROOT="$TESTS_DIR/.."
DASHBOARD="$REPO_ROOT/lazy-llm-bin/.local/bin/llm-dashboard"

# ──────────────────────────────────────────────────────────────────────────
# 1. The old transient overlay is gone; render_help_tab exists instead
# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: show_help_overlay retired, render_help_tab defined..."
if command grep -qE '^show_help_overlay\(\)' "$DASHBOARD"; then
    print_fail "show_help_overlay() still defined — should be replaced by render_help_tab"
else
    print_pass "show_help_overlay() removed"
fi
if command grep -qE '^render_help_tab\(\)' "$DASHBOARD"; then
    print_pass "render_help_tab() defined"
else
    print_fail "render_help_tab() NOT defined"
fi

echo ""
echo "Test 2: no stray tmux display-popup call inside render_help_tab (it's an fzf tab now, not a nested popup)..."
help_body=$(sed -n '/^render_help_tab()/,/^}/p' "$DASHBOARD")
if echo "$help_body" | command grep -q 'display-popup'; then
    print_fail "render_help_tab still spawns a nested display-popup"
else
    print_pass "render_help_tab uses the same fzf-tab pattern as the other tabs"
fi

# ──────────────────────────────────────────────────────────────────────────
# 2. '?' and '3' both route to the Help tab from Workspaces and Worktrees
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 3: '?' routes to tab:help (not the retired action:help) from both tabs..."
help_routes=$(command grep -c '"tab:help"' "$DASHBOARD")
if [ "$help_routes" -ge 2 ]; then
    print_pass "tab:help routed from at least 2 places ($help_routes found — Workspaces + Worktrees)"
else
    print_fail "tab:help routed from fewer than 2 places ($help_routes found)"
fi
if command grep -q 'action:help' "$DASHBOARD"; then
    print_fail "stale action:help reference still present"
else
    print_pass "action:help fully retired"
fi

echo ""
echo "Test 4: '3' is in the Workspaces and Worktrees tabs' --expect lists..."
ws_expect=$(command grep -oE -- '--expect="1,2,3,n,K,r,R,z,a,\],\[,\?"' "$DASHBOARD")
assert_contains "$ws_expect" "1,2,3" "Workspaces tab --expect includes 3"
wt_expect=$(command grep -oE -- '--expect="1,2,3,n,g,K,R,\?"' "$DASHBOARD")
assert_contains "$wt_expect" "1,2,3" "Worktrees tab --expect includes 3"

# ──────────────────────────────────────────────────────────────────────────
# 3. Main loop dispatches the help tab; --tab help is a valid CLI value
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 5: main loop's tab case includes help)..."
if command grep -qE '^\s*help\)\s+result=\$\(render_help_tab\)' "$DASHBOARD"; then
    print_pass "main loop dispatches help) to render_help_tab"
else
    print_fail "main loop does not dispatch a help) case"
fi

echo ""
echo "Test 6: --tab help accepted from the CLI..."
out=$("$DASHBOARD" --tab help --help 2>&1)
rc=$?
assert_equals "$rc" "0" "--tab help --help exits 0"
assert_contains "$out" "Usage: llm-dashboard" "still prints usage"

# ──────────────────────────────────────────────────────────────────────────
# 4. The q:abort fix (found while shortening headers) — 'q' actually closes,
#    not just Esc, matching the header text's long-standing 'q/esc: close' claim
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 7: 'q' is bound to abort in the two main tab fzf calls..."
q_binds=$(command grep -c -- "--bind='q:abort'" "$DASHBOARD")
if [ "$q_binds" -ge 2 ]; then
    print_pass "q:abort bound in at least 2 fzf calls ($q_binds found — Workspaces + Worktrees)"
else
    print_fail "q:abort bound in fewer than 2 fzf calls ($q_binds found)"
fi

# ──────────────────────────────────────────────────────────────────────────
# 5. Help content covers the actual current keybindings (sanity — not
#    exhaustive; catches gross staleness like a whole tab's section missing)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 8: help body covers Workspaces, Worktrees, and fold/pane-row behavior..."
assert_contains "$help_body" "WORKSPACES TAB" "help body covers the Workspaces tab"
assert_contains "$help_body" "WORKTREES TAB" "help body covers the Worktrees tab"
assert_contains "$help_body" "fold/unfold" "help body documents the fold key"
assert_contains "$help_body" "pane row" "help body documents pane-row-specific behavior"

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
