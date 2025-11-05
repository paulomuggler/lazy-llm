#!/usr/bin/env bash
# Test: Simple single-line prompt send

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

TEST_NAME="simple-send"

# Start lazy-llm with mock AI tool
echo "Starting lazy-llm session..."
if ! start_lazy_llm_session "$TEST_NAME"; then
    echo "Failed to start session"
    exit 1
fi

# Wait for initialization
sleep 2

# Send simple prompt to buffer
echo "Sending prompt to buffer..."
PROMPT="What is 2+2?"
send_to_prompt_buffer_simple "$PROMPT"

# Trigger send with <leader>llms
echo "Triggering LLM send..."
trigger_llm_send

# Wait for processing
sleep 1

# Capture AI pane output
echo "Capturing AI pane output..."
AI_OUTPUT=$(capture_pane "$AI_PANE")

# Assertions
echo ""
echo "Running assertions..."

assert_contains "$AI_OUTPUT" "### PROMPT" "Should contain PROMPT marker"
assert_contains "$AI_OUTPUT" "### END PROMPT" "Should contain END PROMPT marker"
assert_contains "$AI_OUTPUT" "$PROMPT" "Should contain the actual prompt text"
assert_contains "$AI_OUTPUT" "Mock AI Tool" "Should show mock AI tool started"

# Verify markers are properly placed (with date/time)
assert_pattern "$AI_OUTPUT" "### PROMPT [0-9]{4}-[0-9]{2}-[0-9]{2}" "PROMPT marker should have timestamp"

# Check that prompt appears between markers
if echo "$AI_OUTPUT" | grep -A 5 "### PROMPT" | grep -q "$PROMPT"; then
    assert_success "true" "Prompt appears after PROMPT marker"
else
    assert_fails "true" "Prompt should appear after PROMPT marker"
fi

# Exit with assertion results
print_assertion_summary
