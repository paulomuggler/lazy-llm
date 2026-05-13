#!/usr/bin/env bash
# Test: Unit test for the dashboard shell — exercises lazy_llm_gather_sessions
# (extracted from llm-sessions into the shared library) and the dashboard's
# argparse / help-text surface. No live fzf flow tested (PTY-dependent).

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="dashboard-shell-unit"

REPO_ROOT="$TESTS_DIR/.."
LIB_FILE="$REPO_ROOT/llm-send-bin/.local/bin/lazy-llm-lib.sh"
DASHBOARD="$REPO_ROOT/lazy-llm-bin/.local/bin/llm-dashboard"
SESSIONS="$REPO_ROOT/lazy-llm-bin/.local/bin/llm-sessions"
LAZY_LLM="$REPO_ROOT/lazy-llm-bin/.local/bin/lazy-llm"

# ──────────────────────────────────────────────────────────────────────────
# 1. The library exposes lazy_llm_gather_sessions
# ──────────────────────────────────────────────────────────────────────────
echo "Test 1: lazy_llm_gather_sessions exists in the library..."
if command grep -qE '^lazy_llm_gather_sessions\(\)' "$LIB_FILE"; then
    print_pass "lazy_llm_gather_sessions defined in lazy-llm-lib.sh"
else
    print_fail "lazy_llm_gather_sessions NOT defined in lazy-llm-lib.sh"
fi

echo ""
echo "Test 2: llm-sessions no longer has a local gather_sessions function..."
if command grep -qE '^gather_sessions\(\)' "$SESSIONS"; then
    print_fail "llm-sessions still has an inline gather_sessions"
else
    print_pass "llm-sessions correctly delegates to lazy_llm_gather_sessions"
fi

echo ""
echo "Test 3: llm-sessions calls lazy_llm_gather_sessions..."
if command grep -q 'lazy_llm_gather_sessions' "$SESSIONS"; then
    print_pass "llm-sessions invokes lazy_llm_gather_sessions"
else
    print_fail "llm-sessions does NOT invoke lazy_llm_gather_sessions"
fi

echo ""
echo "Test 4: llm-dashboard calls lazy_llm_gather_sessions..."
if command grep -q 'lazy_llm_gather_sessions' "$DASHBOARD"; then
    print_pass "llm-dashboard invokes lazy_llm_gather_sessions"
else
    print_fail "llm-dashboard does NOT invoke lazy_llm_gather_sessions"
fi

# ──────────────────────────────────────────────────────────────────────────
# 2. gather function output format with isolated tmux server
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 5: gather returns tab-separated rows for lazy-llm-marked sessions..."
TMUX_TMPDIR=/tmp/lazy-llm-test-dash-$$
mkdir -p "$TMUX_TMPDIR"
export TMUX_TMPDIR

# Source the lib in a clean subshell so we can call the function
output=$(bash <<EOF
source "$LIB_FILE"
unset TMUX TMUX_PANE
tmux -f /dev/null new-session -d -s _dash_test_session
tmux -f /dev/null set-option -t _dash_test_session @lazy_llm 1
tmux -f /dev/null set-option -wv -t _dash_test_session:0 @AI_TOOL claude
lazy_llm_gather_sessions
tmux -f /dev/null kill-server 2>/dev/null
EOF
)
rm -rf "$TMUX_TMPDIR"

# Expect one tab-separated line whose first column is the session name
field_count=$(echo "$output" | head -1 | awk -F'\t' '{print NF}')
first_col=$(echo "$output" | head -1 | awk -F'\t' '{print $1}')

assert_equals "$first_col" "_dash_test_session" "gather output first column should be session name"
assert_equals "$field_count" "5" "gather output should have 5 tab-separated columns"

# ──────────────────────────────────────────────────────────────────────────
# 3. Non-lazy-llm sessions are excluded
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 6: sessions without @lazy_llm marker are filtered out..."
TMUX_TMPDIR=/tmp/lazy-llm-test-dash2-$$
mkdir -p "$TMUX_TMPDIR"
export TMUX_TMPDIR

output=$(bash <<EOF
source "$LIB_FILE"
unset TMUX TMUX_PANE
tmux -f /dev/null new-session -d -s _plain_session
# Note: no @lazy_llm option set
lazy_llm_gather_sessions
tmux -f /dev/null kill-server 2>/dev/null
EOF
)
rm -rf "$TMUX_TMPDIR"

if [[ -z "$output" ]]; then
    print_pass "Plain (non-lazy-llm) sessions excluded from gather output"
else
    print_fail "Plain sessions leaked into gather output: $output"
fi

# ──────────────────────────────────────────────────────────────────────────
# 4. Dashboard argparse / help text surface
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 7: llm-dashboard --help prints usage..."
help_out=$("$DASHBOARD" --help 2>&1)
assert_contains "$help_out" "Usage: llm-dashboard" "help text starts with Usage"
assert_contains "$help_out" "Tabbed popup dashboard" "help mentions tabbed popup"
assert_contains "$help_out" "1, 2" "help documents tab keys"
assert_contains "$help_out" "Enter" "help documents primary action"
assert_contains "$help_out" "K" "help documents kill key"

echo ""
echo "Test 8: llm-dashboard --bogus exits non-zero with usage..."
set +e
bogus_out=$("$DASHBOARD" --bogus 2>&1)
bogus_rc=$?
set -e
assert_pattern "$bogus_rc" "^[1-9]" "exit code should be non-zero"
assert_contains "$bogus_out" "Unknown arg" "should report unknown arg"

# ──────────────────────────────────────────────────────────────────────────
# 5. Prefix+S binding now launches llm-dashboard
# Note: Prefix+L was retired in the dashboard-panes-tab task — the Panes tab
# now lives inside the dashboard, reachable from any tab via the '3' key.
# That assertion has moved to 13-dashboard-panes-tab-unit.sh.
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Test 9: Prefix+S launches llm-dashboard..."
prefix_s=$(command grep -A2 'bind-key -T prefix S if-shell' "$LAZY_LLM" | tail -1)

assert_contains "$prefix_s" "llm-dashboard" "Prefix+S should launch llm-dashboard"
assert_not_contains "$prefix_s" "llm-sessions" "Prefix+S should no longer reference llm-sessions"

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
