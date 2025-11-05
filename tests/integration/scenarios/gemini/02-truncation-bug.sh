#!/usr/bin/env bash
# Integration Test: Gemini truncation/repetition bug
# This test documents the known issue where Gemini repeats prompts 6-8 times

INTEGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_DIR="$(cd "$INTEGRATION_DIR/.." && pwd)"

source "$INTEGRATION_DIR/lib/ai-tool-helpers.sh"
source "$INTEGRATION_DIR/lib/integration-assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

skip_if_disabled "gemini"

if ! load_dotenv "$INTEGRATION_DIR/.env"; then
    exit 1
fi

if ! require_tool "gemini" "GEMINI_API_KEY"; then
    exit 1
fi

TEST_NAME="gemini-truncation"

echo "Starting lazy-llm with Gemini CLI..."
if ! start_lazy_llm_with_ai_tool "$TEST_NAME" "gemini"; then
    exit 1
fi

sleep 3

# Send multi-paragraph prompt (this triggers the bug)
echo "Sending multiline prompt to Gemini..."
PROMPT=$(cat "$INTEGRATION_DIR/prompts/multiline-task.txt")

send_prompt "$PROMPT"

echo "Waiting for response..."
wait_for_response 30

# Capture output
AI_OUTPUT=$(capture_pane "$AI_PANE")

echo ""
echo "Checking for truncation bug..."

# Count how many times the prompt appears
PROMPT_COUNT=$(echo "$AI_OUTPUT" | grep -c "^### PROMPT")
END_PROMPT_COUNT=$(echo "$AI_OUTPUT" | grep -c "^### END PROMPT")

echo "Found $PROMPT_COUNT PROMPT markers"
echo "Found $END_PROMPT_COUNT END PROMPT markers"

if [ "$PROMPT_COUNT" -gt 1 ]; then
    log_known_bug "Gemini truncation bug confirmed: prompt repeated ${PROMPT_COUNT} times"
    echo ""
    echo "This makes the response unusable because:"
    echo "1. Response is truncated and repeated"
    echo "2. llm-pull cannot extract the correct response"
    echo "3. Visual clutter makes it hard to read"
    echo ""
    echo "Expected: 1 PROMPT marker"
    echo "Actual:   $PROMPT_COUNT PROMPT markers"

    # This is expected to fail for now
    assert_equals "$PROMPT_COUNT" "1" "KNOWN BUG: Should have only 1 PROMPT marker"
else
    echo "✓ No truncation bug detected!"
    echo "Gemini appears to be working correctly"
    assert_equals "$PROMPT_COUNT" "1" "Should have 1 PROMPT marker"
fi

# Check marker line breaking (another known issue)
echo ""
echo "Checking marker line breaks..."
assert_markers_have_line_breaks "$AI_OUTPUT" "Markers should have proper line breaks"

print_assertion_summary

# Exit 0 even if assertions fail - this is documenting a known bug
exit 0
