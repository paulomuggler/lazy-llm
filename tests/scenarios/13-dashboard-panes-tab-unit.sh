#!/usr/bin/env bash
# Test: Structural unit checks for the dashboard's Workspaces tree tab (AI panes
# nested under their workspace — dashboard-tree-view-consolidation folded the old
# separate Panes tab into this tree) + Prefix+L retirement + llm-panes alias
# shrink. Live fzf flow isn't unit-testable (PTY-dependent); we verify the wiring
# is correct.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="dashboard-panes-tab-unit"

REPO_ROOT="$TESTS_DIR/.."
DASHBOARD="$REPO_ROOT/lazy-llm-bin/.local/bin/llm-dashboard"
LLM_PANES="$REPO_ROOT/lazy-llm-bin/.local/bin/llm-panes"
LAZY_LLM="$REPO_ROOT/lazy-llm-bin/.local/bin/lazy-llm"

# ──────────────────────────────────────────────────────────────────────────
# 1. llm-panes is now a thin alias for --tab workspaces (panes live there now)
# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: llm-panes shrunk to alias..."
lines=$(wc -l < "$LLM_PANES")
if [ "$lines" -le 10 ]; then
    print_pass "llm-panes is $lines lines (≤ 10 expected for alias)"
else
    print_fail "llm-panes is $lines lines (expected ≤ 10 for alias)"
fi

if command grep -q 'exec.*llm-dashboard.*--tab workspaces' "$LLM_PANES"; then
    print_pass "llm-panes execs llm-dashboard --tab workspaces"
else
    print_fail "llm-panes does NOT exec llm-dashboard --tab workspaces"
fi

# ──────────────────────────────────────────────────────────────────────────
# 2. Prefix+L bind-key removed from lazy-llm
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 2: Prefix+L binding removed..."
if command grep -q 'bind-key -T prefix L' "$LAZY_LLM"; then
    print_fail "Prefix+L bind-key still present in lazy-llm"
else
    print_pass "Prefix+L bind-key removed from lazy-llm"
fi

echo ""
echo "Test 3: Prefix+S binding untouched..."
prefix_s=$(command grep -A2 'bind-key -T prefix S if-shell' "$LAZY_LLM" | tail -1)
assert_contains "$prefix_s" "llm-dashboard" "Prefix+S still launches llm-dashboard"

# ──────────────────────────────────────────────────────────────────────────
# 3. Dashboard accepts --tab panes as a compat alias for --tab workspaces
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: --tab panes still accepted (compat alias)..."
out=$("$DASHBOARD" --tab panes --help 2>&1)
rc=$?
assert_equals "$rc" "0" "--tab panes --help exits 0"
assert_contains "$out" "Usage: llm-dashboard" "still prints usage"

echo ""
echo "Test 5: --tab bogus rejected..."
set +e
bogus_out=$("$DASHBOARD" --tab bogus 2>&1)
bogus_rc=$?
set -e
assert_pattern "$bogus_rc" "^[1-9]" "rejected with non-zero exit"
assert_contains "$bogus_out" "Unknown tab" "error message mentions Unknown tab"

# ──────────────────────────────────────────────────────────────────────────
# 4. Structural: AI panes are rendered as nested rows under render_sessions_tab,
#    not a separate render_panes_tab (which no longer exists).
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: render_panes_tab no longer exists (folded into the tree)..."
if command grep -qE '^render_panes_tab\(\)' "$DASHBOARD"; then
    print_fail "render_panes_tab() still defined — should be folded into render_sessions_tab"
else
    print_pass "render_panes_tab() removed"
fi

echo ""
echo "Test 6b: tree row-id scheme present (ws:/pane: prefixes)..."
if command grep -q '"ws:\${name}"' "$DASHBOARD" && command grep -q 'pane:\${name}:\${i}:\${pid}' "$DASHBOARD"; then
    print_pass "workspace + pane row id construction present"
else
    print_fail "tree row-id construction (ws:/pane: prefixes) not found"
fi

echo ""
echo "Test 6c: per-workspace pane list uses lazy_llm_read_multi_state_for..."
if command grep -q 'lazy_llm_read_multi_state_for' "$DASHBOARD"; then
    print_pass "dashboard reads every workspace's full pane list (not just the first pane)"
else
    print_fail "dashboard does not use lazy_llm_read_multi_state_for — likely still first-pane-only"
fi

# ──────────────────────────────────────────────────────────────────────────
# 5. dispatch_action has the tree's action verbs (pane-cycle retired — Enter on
#    a pane row now emits switch-pane, composed with a workspace switch)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 7: dispatch_action has tree action verbs..."
for verb in switch-pane toggle pane-add pane-remove pane-remove-unsupported pane-next pane-prev; do
    if command grep -q "action:$verb" "$DASHBOARD"; then
        print_pass "dispatch handles action:$verb"
    else
        print_fail "dispatch does NOT handle action:$verb"
    fi
done

if command grep -q 'action:pane-cycle' "$DASHBOARD"; then
    print_fail "stale action:pane-cycle still referenced (should be action:switch-pane now)"
else
    print_pass "action:pane-cycle retired (superseded by action:switch-pane)"
fi

echo ""
echo "Test 8: main loop allowlist includes the tree's action verbs..."
loop_arm=$(command grep -E 'action:switch:\*\|action:switch-pane' "$DASHBOARD")
assert_contains "$loop_arm" "switch-pane:" "loop arm includes switch-pane"
assert_contains "$loop_arm" "toggle:" "loop arm includes toggle"
assert_contains "$loop_arm" "pane-add" "loop arm includes pane-add"
assert_contains "$loop_arm" "pane-remove:" "loop arm includes pane-remove"
assert_contains "$loop_arm" "pane-remove-unsupported" "loop arm includes pane-remove-unsupported"
assert_contains "$loop_arm" "pane-next" "loop arm includes pane-next"
assert_contains "$loop_arm" "pane-prev" "loop arm includes pane-prev"

# ──────────────────────────────────────────────────────────────────────────
# 6. Canonical status detection (not duplicated)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 9: dashboard uses canonical lazy_llm_detect_pane_status..."
if command grep -q 'lazy_llm_detect_pane_status' "$DASHBOARD"; then
    print_pass "dashboard calls lazy_llm_detect_pane_status"
else
    print_fail "dashboard does NOT call canonical detector"
fi

# Confirm dashboard doesn't define its own detect_pane_status helper
if command grep -qE '^detect_pane_status\(\)' "$DASHBOARD"; then
    print_fail "dashboard redefines detect_pane_status (should use lib helper)"
else
    print_pass "dashboard does not redefine status detection"
fi

# ──────────────────────────────────────────────────────────────────────────
# 7. Fold/unfold state: declared once at script scope, toggled by dispatch_action
#    (render_sessions_tab runs in a subshell and must only read it)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 10: fold state (_collapsed) declared once, mutated only in dispatch_action..."
if command grep -q 'declare -A _collapsed' "$DASHBOARD"; then
    print_pass "_collapsed associative array declared"
else
    print_fail "_collapsed associative array not found"
fi
if command grep -q '_collapsed\[\$name\]=1' "$DASHBOARD"; then
    print_pass "toggle action sets _collapsed"
else
    print_fail "toggle action does not set _collapsed"
fi

# ──────────────────────────────────────────────────────────────────────────
# 8. Help text documents the tree (fold key, pane-row Enter behavior) instead
#    of a separate Panes tab
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 11: help text documents the workspace tree, not a separate Panes tab..."
help_out=$("$DASHBOARD" --help 2>&1)
assert_contains "$help_out" "fold" "help mentions fold/unfold (z key)"
assert_contains "$help_out" "CURRENT workspace" "help clarifies a/]/[  scope to the current workspace"
if echo "$help_out" | command grep -qE '^\s*3\s'; then
    print_fail "help still documents a tab-3 keybinding (Panes tab should be gone)"
else
    print_pass "help no longer documents a separate tab-3 (Panes) keybinding"
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
