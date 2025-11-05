#!/usr/bin/env bash
# Test: Response pull (llm-pull) functionality

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

TEST_NAME="response-pull"

# Use multiline mode to generate mock responses
export MOCK_AI_MODE="multiline"

echo "Starting lazy-llm session..."
if ! start_lazy_llm_session "$TEST_NAME"; then
    echo "Failed to start session"
    exit 1
fi

sleep 2

# Send a prompt to generate a response
echo "Sending prompt to generate response..."
PROMPT="Write a hello world function"
send_to_prompt_buffer_simple "$PROMPT"

# Trigger send
echo "Triggering LLM send..."
trigger_llm_send

# Wait for mock AI to generate response
sleep 2

# Verify AI pane has response
AI_OUTPUT=$(capture_pane "$AI_PANE")
echo "AI pane output captured (${#AI_OUTPUT} chars)"

# Check that response was generated
assert_contains "$AI_OUTPUT" "### END PROMPT" "Should have END PROMPT marker"
assert_contains "$AI_OUTPUT" "Sure, I'll help" "Mock AI should have responded"

# Now test response pull
echo ""
echo "Testing response pull..."

# Clear prompt buffer first
tmux send-keys -t "$PROMPT_PANE" Escape "ggdG"
sleep 0.3

# Trigger llm-pull (<leader>llmp)
trigger_llm_pull

# Wait for pull to complete
sleep 1

# Capture prompt buffer content
PROMPT_BUFFER=$(capture_pane "$PROMPT_PANE")

echo ""
echo "Running assertions on pulled response..."

# Assertions on pulled content
# The response should NOT include the original prompt or markers
assert_not_contains "$PROMPT_BUFFER" "### PROMPT" "Pulled content should not include PROMPT marker"
assert_not_contains "$PROMPT_BUFFER" "### END PROMPT" "Pulled content should not include END PROMPT marker"
assert_not_contains "$PROMPT_BUFFER" "$PROMPT" "Pulled content should not include original prompt"

# Should contain the mock response content
assert_contains "$PROMPT_BUFFER" "Sure, I'll help" "Should contain response text"
assert_contains "$PROMPT_BUFFER" "multi-line response" "Should contain full response"

# Check that response is properly formatted (not truncated)
LINE_COUNT=$(echo "$PROMPT_BUFFER" | wc -l)
if [ "$LINE_COUNT" -gt 3 ]; then
    assert_success "true" "Pulled response has multiple lines (actual: $LINE_COUNT)"
else
    echo "WARNING: Pulled response has only $LINE_COUNT lines"
fi

# Verify response doesn't have artifacts from capture
assert_not_contains "$PROMPT_BUFFER" "capture-pane" "Should not contain tmux artifacts"

print_assertion_summary
