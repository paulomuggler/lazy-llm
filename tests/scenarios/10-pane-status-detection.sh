#!/usr/bin/env bash
# Test: Unit test for lazy_llm_detect_status_from_content and
# lazy_llm_detect_pane_status (no tmux session required for the content
# helper; the wrapper test exercises the capture-failure path).

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="pane-status-detection"

# Source the library under test
LIB_FILE="$TESTS_DIR/../llm-send-bin/.local/bin/lazy-llm-lib.sh"
if [ ! -f "$LIB_FILE" ]; then
    echo "ERROR: lazy-llm-lib.sh not found at $LIB_FILE"
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB_FILE"

FIXTURE_DIR="$TESTS_DIR/fixtures/status"

echo "Testing lazy_llm_detect_status_from_content with fixtures..."

# Each entry: <fixture_suffix>:<expected_status>
cases=(
    "working:working"
    "idle:idle"
    "waiting-yn:waiting"
    "waiting-numbered:waiting"
    # Regression: waiting-numbered's pattern (Claude Code's real numbered
    # permission-prompt UI) is indistinguishable from an ordinary markdown
    # numbered list in Claude's own RESPONSE text. Confirmed live against a
    # real idle pane whose finished response ended in a 3-item numbered
    # list — misclassified as "waiting" purely from old scrollback, long
    # after the turn had actually finished. This fixture reproduces that
    # exact shape (numbered list well above the tail, genuine idle prompt
    # at the very end) and must detect idle, not waiting.
    "idle-with-old-numbered-list:idle"
    "unknown:unknown"
)

for entry in "${cases[@]}"; do
    fixture="${entry%%:*}"
    expected="${entry##*:}"
    fixture_path="$FIXTURE_DIR/claude-${fixture}.txt"

    if [ ! -f "$fixture_path" ]; then
        print_fail "Fixture missing: $fixture_path"
        continue
    fi

    actual=$(lazy_llm_detect_status_from_content claude < "$fixture_path")
    assert_equals "$actual" "$expected" "claude fixture '$fixture' should detect '$expected'"
done

echo ""
echo "Testing per-tool fallthrough (non-claude tools share defaults)..."

for tool in gemini codex grok aider; do
    actual=$(lazy_llm_detect_status_from_content "$tool" < "$FIXTURE_DIR/claude-working.txt")
    assert_equals "$actual" "working" "tool '$tool' should fall through to claude patterns (working)"

    actual=$(lazy_llm_detect_status_from_content "$tool" < "$FIXTURE_DIR/claude-idle.txt")
    assert_equals "$actual" "idle" "tool '$tool' should fall through to claude patterns (idle)"
done

echo ""
echo "Testing default tool (no argument) uses claude patterns..."
actual=$(lazy_llm_detect_status_from_content < "$FIXTURE_DIR/claude-working.txt")
assert_equals "$actual" "working" "default (no tool arg) treats content as claude"

echo ""
echo "Testing precedence: interrupt hint wins over choice prompt..."
mixed=$'❯ blah\nctrl+c to interrupt\n[y/n]'
actual=$(printf '%s' "$mixed" | lazy_llm_detect_status_from_content claude)
assert_equals "$actual" "working" "interrupt hint should take precedence over [y/n]"

echo ""
echo "Testing precedence: choice prompt wins over bare prompt glyph..."
mixed=$'❯ blah\n[y/n]'
actual=$(printf '%s' "$mixed" | lazy_llm_detect_status_from_content claude)
assert_equals "$actual" "waiting" "choice prompt should take precedence over bare ❯"

echo ""
echo "Testing jetski-cli status detection..."
jetski_working=$'▸ Thought for 1m 26s, 89 tokens\n● Bash(git status)\n⣯  Running command...\n─────────────────────────────────────────\n>\n─────────────────────────────────────────\nesc to cancel                                                                                 Gemini Next'
actual=$(printf '%s' "$jetski_working" | lazy_llm_detect_status_from_content jetski-cli)
assert_equals "$actual" "working" "jetski-cli active spinner + esc to cancel should detect 'working'"

jetski_idle_with_old_thought=$'▸ Thought for 1m 26s, 89 tokens\n  Done!\n─────────────────────────────────────────\n>\n─────────────────────────────────────────\n                                                                                              Gemini Next'
actual=$(printf '%s' "$jetski_idle_with_old_thought" | lazy_llm_detect_status_from_content jetski-cli)
assert_equals "$actual" "idle" "jetski-cli idle prompt should detect 'idle' even with old '1m 26s' thought in scrollback"

jetski_idle_bg_task=$'▸ Thought for 1m 26s, 89 tokens\n  Done!\n─────────────────────────────────────────\n>\n─────────────────────────────────────────\n  ● [13:20:10] python3 server.py running\n─────────────────────────────────────────\nesc to cancel                                                            Gemini Next · 1 task(s) · /tasks'
actual=$(printf '%s' "$jetski_idle_bg_task" | lazy_llm_detect_status_from_content jetski-cli)
assert_equals "$actual" "idle" "jetski-cli idle prompt with background task footer should detect 'idle'"

echo ""
echo "Testing lazy_llm_detect_pane_status with a nonexistent pane..."
actual=$(lazy_llm_detect_pane_status "%99999" claude 2>/dev/null)
assert_equals "$actual" "unknown" "missing pane id should return 'unknown' without erroring"

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
