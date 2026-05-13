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
