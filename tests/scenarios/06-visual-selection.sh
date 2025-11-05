#!/usr/bin/env bash
# Test: Visual selection send (partial buffer send)

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

TEST_NAME="visual-selection"

echo "Starting lazy-llm session..."
if ! start_lazy_llm_session "$TEST_NAME"; then
    echo "Failed to start session"
    exit 1
fi

sleep 2

# Create multi-line content in prompt buffer
echo "Setting up prompt buffer with multiple lines..."
CONTENT="Line 1: This should be selected
Line 2: This should also be selected
Line 3: This should NOT be selected
Line 4: This should NOT be selected"

send_to_prompt_buffer_simple "$CONTENT"
sleep 0.5

# Visually select first 2 lines and send
echo "Selecting first 2 lines visually..."

# Go to first line, enter visual line mode, select 2 lines, send
tmux send-keys -t "$PROMPT_PANE" Escape "gg" "V" "j" '\' 'llms'
sleep 1

# Capture AI pane output
AI_OUTPUT=$(capture_pane "$AI_PANE")

echo ""
echo "Running assertions..."

# Should contain markers
assert_contains "$AI_OUTPUT" "### PROMPT" "Should have PROMPT marker"
assert_contains "$AI_OUTPUT" "### END PROMPT" "Should have END PROMPT marker"

# Should contain selected lines
assert_contains "$AI_OUTPUT" "Line 1: This should be selected" "Should contain line 1"
assert_contains "$AI_OUTPUT" "Line 2: This should also be selected" "Should contain line 2"

# Should NOT contain unselected lines
assert_not_contains "$AI_OUTPUT" "Line 3: This should NOT" "Should not contain line 3"
assert_not_contains "$AI_OUTPUT" "Line 4: This should NOT" "Should not contain line 4"

# Verify only 2 content lines were sent (plus markers)
BETWEEN_MARKERS=$(echo "$AI_OUTPUT" | sed -n '/### PROMPT/,/### END PROMPT/p')
CONTENT_LINE_COUNT=$(echo "$BETWEEN_MARKERS" | grep -c "^Line [0-9]:")

assert_equals "$CONTENT_LINE_COUNT" "2" "Should have sent exactly 2 lines"

print_assertion_summary
