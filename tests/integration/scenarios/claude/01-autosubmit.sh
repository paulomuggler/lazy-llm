#!/usr/bin/env bash
# Integration Test: Claude Code autosubmit reliability

INTEGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_DIR="$(cd "$INTEGRATION_DIR/.." && pwd)"

source "$INTEGRATION_DIR/lib/ai-tool-helpers.sh"
source "$INTEGRATION_DIR/lib/integration-assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

# Skip if Claude testing disabled
skip_if_disabled "claude"

# Load credentials
if ! load_dotenv "$INTEGRATION_DIR/.env"; then
    exit 1
fi

# Verify Claude is available
if ! require_tool "claude" "ANTHROPIC_API_KEY"; then
    exit 1
fi

TEST_NAME="claude-autosubmit"

echo "Starting lazy-llm with Claude..."
if ! start_lazy_llm_with_ai_tool "$TEST_NAME" "claude"; then
    echo "Failed to start session"
    exit 1
fi

# Wait for Claude to initialize
sleep 3

# Send simple prompt
echo "Sending prompt to Claude..."
PROMPT="What is 2+2? Answer with just the number."

send_prompt "$PROMPT"

# Wait for response
echo "Waiting for Claude response..."
START_TIME=$(date +%s)

if wait_for_response 30; then
    END_TIME=$(date +%s)
    echo "Response received!"
else
    END_TIME=$(date +%s)
    echo "WARNING: Response timeout"
fi

# Capture Claude's response
AI_OUTPUT=$(capture_pane "$AI_PANE")

# Run assertions
echo ""
echo "Running assertions..."

# Basic markers
assert_contains "$AI_OUTPUT" "### PROMPT" "Should have PROMPT marker"
assert_contains "$AI_OUTPUT" "### END PROMPT" "Should have END PROMPT marker"

# Check autosubmit
assert_autosubmit_success "$AI_OUTPUT" "Autosubmit should work with Claude"

# Extract and validate response
RESPONSE=$(extract_response "$AI_OUTPUT")
assert_valid_response "$RESPONSE" "Claude should provide valid response"
assert_contains "$RESPONSE" "4" "Claude should answer the math question"

# Check response time
assert_response_time "$START_TIME" "$END_TIME" 30 "Response should arrive within 30s"

# Check marker formatting
assert_markers_have_line_breaks "$AI_OUTPUT" "Markers should have proper formatting"

# Print summary
print_assertion_summary
