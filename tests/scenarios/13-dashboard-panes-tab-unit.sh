#!/usr/bin/env bash
# Test: Structural unit checks for the dashboard Panes tab + Prefix+L retirement +
# llm-panes alias shrink. Live fzf flow isn't unit-testable (PTY-dependent);
# we verify the wiring is correct.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="dashboard-panes-tab-unit"

REPO_ROOT="$TESTS_DIR/.."
DASHBOARD="$REPO_ROOT/lazy-llm-bin/.local/bin/llm-dashboard"
LLM_PANES="$REPO_ROOT/lazy-llm-bin/.local/bin/llm-panes"
LAZY_LLM="$REPO_ROOT/lazy-llm-bin/.local/bin/lazy-llm"

# ──────────────────────────────────────────────────────────────────────────
# 1. llm-panes is now a thin alias
# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: llm-panes shrunk to alias..."
lines=$(wc -l < "$LLM_PANES")
if [ "$lines" -le 10 ]; then
    print_pass "llm-panes is $lines lines (≤ 10 expected for alias)"
else
    print_fail "llm-panes is $lines lines (expected ≤ 10 for alias)"
fi

if command grep -q 'exec.*llm-dashboard.*--tab panes' "$LLM_PANES"; then
    print_pass "llm-panes execs llm-dashboard --tab panes"
else
    print_fail "llm-panes does NOT exec llm-dashboard --tab panes"
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
# 3. Dashboard accepts --tab panes
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 4: --tab panes parsed correctly..."
# Use --help after --tab panes; should print usage and exit 0 (panes is valid)
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
# 4. Structural: render_panes_tab + action verbs present
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: render_panes_tab defined..."
if command grep -qE '^render_panes_tab\(\)' "$DASHBOARD"; then
    print_pass "render_panes_tab() defined"
else
    print_fail "render_panes_tab() NOT defined"
fi

echo ""
echo "Test 7: dispatch_action has pane verbs..."
for verb in pane-cycle pane-add pane-remove pane-next pane-prev; do
    if command grep -q "action:$verb" "$DASHBOARD"; then
        print_pass "dispatch handles action:$verb"
    else
        print_fail "dispatch does NOT handle action:$verb"
    fi
done

echo ""
echo "Test 8: main loop allowlist includes pane verbs..."
loop_arm=$(command grep -E 'action:switch:\*\|action:kill' "$DASHBOARD")
assert_contains "$loop_arm" "pane-cycle:" "loop arm includes pane-cycle"
assert_contains "$loop_arm" "pane-add" "loop arm includes pane-add"
assert_contains "$loop_arm" "pane-remove:" "loop arm includes pane-remove"
assert_contains "$loop_arm" "pane-next" "loop arm includes pane-next"
assert_contains "$loop_arm" "pane-prev" "loop arm includes pane-prev"

# ──────────────────────────────────────────────────────────────────────────
# 5. Canonical status detection (not duplicated)
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
# 6. Tab routing: 3 is handled in all tabs' key dispatch
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 10: 3 routes to panes from sessions/worktrees tabs..."
# Sessions tab: 3) echo "tab:panes" should be present
if command grep -A1 -E '3\)\s*echo "tab:panes"' "$DASHBOARD" >/dev/null; then
    print_pass "3 → tab:panes routing present"
else
    print_fail "3 → tab:panes routing missing"
fi

# ──────────────────────────────────────────────────────────────────────────
# 7. Help text mentions panes
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 11: help text documents Panes tab actions..."
help_out=$("$DASHBOARD" --help 2>&1)
assert_contains "$help_out" "Panes" "help mentions Panes"
assert_contains "$help_out" "panes" "help mentions panes (lowercase, in --tab list)"

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
