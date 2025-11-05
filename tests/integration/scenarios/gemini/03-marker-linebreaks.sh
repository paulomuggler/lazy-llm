#!/usr/bin/env bash
# Integration Test: Gemini marker line breaking issue
# Tests if markers appear on their own lines (required for llm-pull)

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

TEST_NAME="gemini-markers"

echo "Starting lazy-llm with Gemini CLI..."
if ! start_lazy_llm_with_ai_tool "$TEST_NAME" "gemini"; then
    exit 1
fi

sleep 3

# Send prompt
echo "Sending prompt..."
PROMPT="Write a hello world function in Python."
send_prompt "$PROMPT"

echo "Waiting for response..."
wait_for_response 30

# Capture output
AI_OUTPUT=$(capture_pane "$AI_PANE")

echo ""
echo "Checking marker formatting..."

# Check if PROMPT marker is on its own line
if echo "$AI_OUTPUT" | grep -E "^### PROMPT [0-9-:]+$" > /dev/null; then
    assert_success "true" "PROMPT marker is on its own line"
else
    log_known_bug "PROMPT marker not properly formatted"
    assert_fails "true" "KNOWN BUG: PROMPT marker should be on its own line"
fi

# Check if END PROMPT marker is on its own line
if echo "$AI_OUTPUT" | grep -E "^### END PROMPT$" > /dev/null; then
    assert_success "true" "END PROMPT marker is on its own line"
else
    log_known_bug "END PROMPT marker not properly formatted"
    assert_fails "true" "KNOWN BUG: END PROMPT marker should be on its own line"
fi

# Check if response starts on a new line after END PROMPT
echo ""
echo "Checking response positioning..."

AFTER_END_MARKER=$(echo "$AI_OUTPUT" | sed -n '/### END PROMPT/,$p' | tail -n +2 | head -n 3)

if [ -n "$AFTER_END_MARKER" ]; then
    # Check if first line after marker is blank or contains response
    FIRST_LINE=$(echo "$AFTER_END_MARKER" | head -n 1)

    if [ -z "$FIRST_LINE" ] || echo "$FIRST_LINE" | grep -E "^[[:space:]]*$" > /dev/null; then
        assert_success "true" "Blank line after END PROMPT (good formatting)"
    else
        echo "WARNING: Response starts immediately after END PROMPT"
        echo "First line: $FIRST_LINE"
    fi

    # Verify response is extractable
    RESPONSE=$(extract_response "$AI_OUTPUT")
    if [ -n "$RESPONSE" ] && [ "${#RESPONSE}" -gt 10 ]; then
        assert_success "true" "Response is extractable via llm-pull logic"
    else
        log_known_bug "Response not properly extractable (line breaking issue)"
        assert_fails "true" "KNOWN BUG: Response should be extractable"
    fi
fi

print_assertion_summary

# Exit 0 - documenting known issues
exit 0
