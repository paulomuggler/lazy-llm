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
LIB="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"

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
# 'toggle' is deliberately NOT in this list — fold/unfold no longer
# round-trips through dispatch_action at all (see Test 10-14 below,
# dashboard-reload-avoid-full-redraw): 'z' is bound directly to fzf's
# execute-silent()+reload(), so action:toggle is dead and was removed.
for verb in switch-pane pane-add pane-remove pane-remove-unsupported pane-next pane-prev; do
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
# 7. Fold/unfold (dashboard-reload-avoid-full-redraw): 'z' no longer exits
#    and relaunches fzf. State moved from an in-process bash array to a
#    tmux option (a reload() subprocess has no access to this script's
#    memory), and 'z' is bound directly to execute-silent()+reload() so the
#    running fzf process is reused instead of restarted.
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 10: fold state externalized to a tmux option (not an in-process array)..."
if command grep -q 'declare -A _collapsed' "$DASHBOARD"; then
    print_fail "_collapsed associative array still declared — a reload() subprocess can't see in-process bash state, so fold state must live outside the process"
else
    print_pass "no in-process _collapsed array"
fi
if command grep -q 'lazy_llm_read_collapsed' "$LIB" && command grep -q 'lazy_llm_toggle_collapsed' "$LIB"; then
    print_pass "lazy-llm-lib.sh provides lazy_llm_read_collapsed/lazy_llm_toggle_collapsed"
else
    print_fail "fold-state read/toggle helpers not found in lazy-llm-lib.sh"
fi
if command grep -q '@lazy_llm_collapsed' "$LIB"; then
    print_pass "fold state stored as @lazy_llm_collapsed (session-scoped, parallel to @lazy_llm)"
else
    print_fail "@lazy_llm_collapsed tmux option not found in lazy-llm-lib.sh"
fi

echo ""
echo "Test 11: 'z' is bound to transform(...--fold-transform...), not print+accept..."
if command grep -qE "z:transform\([^)]*--fold-transform[^)]*\)" "$DASHBOARD"; then
    print_pass "'z' binds transform(...--fold-transform...) — never exits fzf"
else
    print_fail "'z' is not wired to transform(...)"
fi
if command grep -q "bind='z:print(z)+accept'" "$DASHBOARD"; then
    print_fail "old 'z' print(z)+accept binding (exit+relaunch) still present"
else
    print_pass "old 'z' print+accept binding removed"
fi
if command grep -qE "z:execute-silent\([^)]*--toggle-fold" "$DASHBOARD"; then
    print_fail "old 'z' execute-silent(...--toggle-fold...)+reload(...) binding still present — should be transform(...--fold-transform...) now (dashboard-reload-avoid-full-redraw rework: --track's cursor fallback resets to row 1 when a tracked pane row's own parent is folded)"
else
    print_pass "old execute-silent(...--toggle-fold...)+reload(...) binding removed"
fi
if command grep -qE '^\s*z\)\s' "$DASHBOARD"; then
    print_fail "dead 'z' case arm still present in the key-dispatch case (z never reaches accept/selection now)"
else
    print_pass "dead 'z' case arm removed from key dispatch"
fi

echo ""
echo "Test 12: cursor placement across a fold reload is computed explicitly (pos(N) in --fold-transform), not left to fzf's --track --id-nth (dashboard-reload-avoid-full-redraw rework: --track's own fallback empirically resets to row 1, not the parent row, when the tracked pane row's own parent gets folded and the tracked id vanishes from the reloaded list)..."
# Only non-comment lines count — the rationale comments above the fzf call
# and --fold-transform deliberately still mention --track/--id-nth in prose
# (explaining why they were dropped), which a plain grep would misread as
# the flags still being set.
if command grep -v '^\s*#' "$DASHBOARD" | command grep -q -- '--track' \
   || command grep -v '^\s*#' "$DASHBOARD" | command grep -qE -- "--id-nth[= ]"; then
    print_fail "--track/--id-nth still set on the Workspaces fzf call — should be removed now that --fold-transform positions the cursor explicitly"
else
    print_pass "--track/--id-nth removed from the Workspaces fzf call (code, not just comments, checked)"
fi
if command grep -qE "printf 'reload-sync\(%s --emit-rows\)\+pos\(%s\)" "$DASHBOARD"; then
    print_pass "--fold-transform prints reload-sync(...)+pos(N) — explicit cursor placement after the reload"
else
    print_fail "--fold-transform does not print reload-sync(...)+pos(N) — cursor placement after a fold reload is unaccounted for"
fi
if command grep -v '^\s*#' "$DASHBOARD" | command grep -qE "printf 'reload\(%s"; then
    print_fail "--fold-transform uses plain reload(...) (not reload-sync) — confirmed live (fzf 0.74.3) that a chained pos(N) after a plain async reload() races and gets discarded"
else
    print_pass "--fold-transform does not use plain (non-sync) reload(...) for the fold key"
fi

echo ""
echo "Test 13: --emit-rows / --fold-transform CLI modes exist (transform()'s out-of-process target, folding toggle+reposition into one call) and row-building is shared, not duplicated..."
if command grep -q -- '--emit-rows)' "$DASHBOARD" && command grep -q -- '--fold-transform)' "$DASHBOARD"; then
    print_pass "--emit-rows and --fold-transform CLI flags present"
else
    print_fail "--emit-rows/--fold-transform CLI flags missing"
fi
if command grep -q -- '--toggle-fold)' "$DASHBOARD"; then
    print_fail "old standalone --toggle-fold CLI mode still present — its logic should be folded into --fold-transform now"
else
    print_pass "old standalone --toggle-fold CLI mode retired"
fi
if command grep -q '_dashboard_build_rows' "$DASHBOARD"; then
    print_pass "row-building factored into _dashboard_build_rows (used by render_sessions_tab, --emit-rows, and --fold-transform)"
else
    print_fail "_dashboard_build_rows not found — row emission isn't factored out for reuse"
fi

echo ""
echo "Test 14: action:toggle fully retired (fold no longer round-trips through dispatch_action/the main loop)..."
if command grep -q 'action:toggle' "$DASHBOARD"; then
    print_fail "action:toggle still referenced somewhere"
else
    print_pass "action:toggle retired"
fi

# ──────────────────────────────────────────────────────────────────────────
# 8. Help text documents the tree (fold key, pane-row Enter behavior) instead
#    of a separate Panes tab — tab 3 is legitimately reused for the Help tab
#    (see dashboard-help-tab), not a leftover Panes reference.
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 15: help text documents the workspace tree, not a separate Panes tab..."
help_out=$("$DASHBOARD" --help 2>&1)
assert_contains "$help_out" "fold" "help mentions fold/unfold (z key)"
assert_contains "$help_out" "CURRENT workspace" "help clarifies a/]/[  scope to the current workspace"
if command grep -qE '^render_panes_tab\(\)|action:pane-cycle' "$DASHBOARD"; then
    print_fail "stale Panes-tab-3 machinery still present (render_panes_tab or action:pane-cycle)"
else
    print_pass "no stale Panes-tab-3 machinery — tab 3 is legitimately Help now"
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
