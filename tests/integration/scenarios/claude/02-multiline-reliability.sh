#!/usr/bin/env bash
# Integration Test: Claude multiline prompt reliability

INTEGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_DIR="$(cd "$INTEGRATION_DIR/.." && pwd)"

source "$INTEGRATION_DIR/lib/ai-tool-helpers.sh"
source "$INTEGRATION_DIR/lib/integration-assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

skip_if_disabled "claude"

if ! load_dotenv "$INTEGRATION_DIR/.env"; then
    exit 1
fi

if ! require_tool "claude" "ANTHROPIC_API_KEY"; then
    exit 1
fi

TEST_NAME="claude-multiline"

echo "Starting lazy-llm with Claude..."
if ! start_lazy_llm_with_ai_tool "$TEST_NAME" "claude"; then
    exit 1
fi

sleep 3

# Load multiline prompt
PROMPT=$(cat "$INTEGRATION_DIR/prompts/multiline-task.txt")

echo "Sending multiline prompt to Claude..."
send_prompt "$PROMPT"

echo "Waiting for response..."
START_TIME=$(date +%s)
wait_for_response 30
END_TIME=$(date +%s)

# Capture output
AI_OUTPUT=$(capture_pane "$AI_PANE")

echo ""
echo "Running assertions..."

# Autosubmit check
assert_autosubmit_success "$AI_OUTPUT" "Autosubmit should work with multiline prompts"

# Extract response
RESPONSE=$(extract_response "$AI_OUTPUT")
assert_valid_response "$RESPONSE" "Should have valid response"

# Check that prompt content was preserved
assert_contains "$AI_OUTPUT" "Takes a string" "Should preserve prompt line 1"
assert_contains "$AI_OUTPUT" "Reverses the string" "Should preserve prompt line 2"
assert_contains "$AI_OUTPUT" "Returns the reversed" "Should preserve prompt line 3"

# Check for code in response
assert_contains_code_block "$RESPONSE" "python" "Should contain Python code block"

# Response time
assert_response_time "$START_TIME" "$END_TIME" 30 "Should respond within 30s"

print_assertion_summary
