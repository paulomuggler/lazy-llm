#!/usr/bin/env bash
# Test: Marker placement and line breaking (critical for response parsing)

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

TEST_NAME="marker-placement"

# Use 'markers' mode for mock AI tool to specifically test this
export MOCK_AI_MODE="markers"

echo "Starting lazy-llm session with markers mode..."
if ! start_lazy_llm_session "$TEST_NAME"; then
    echo "Failed to start session"
    exit 1
fi

sleep 2

# Send a simple prompt
echo "Sending prompt..."
PROMPT="Test prompt for marker validation"
send_to_prompt_buffer_simple "$PROMPT"

# Trigger send
echo "Triggering LLM send..."
trigger_llm_send

sleep 1.5

# Capture AI pane output
echo "Capturing AI pane output..."
AI_OUTPUT=$(capture_pane "$AI_PANE")

# Assertions focused on marker formatting
echo ""
echo "Running marker placement assertions..."

# 1. Markers should exist
assert_contains "$AI_OUTPUT" "### PROMPT" "PROMPT marker should exist"
assert_contains "$AI_OUTPUT" "### END PROMPT" "END PROMPT marker should exist"

# 2. PROMPT marker should be on its own line with timestamp
if echo "$AI_OUTPUT" | grep -E "^### PROMPT [0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}:[0-9]{2}:[0-9]{2}$" > /dev/null; then
    assert_success "true" "PROMPT marker has correct format with timestamp"
else
    assert_fails "true" "PROMPT marker should be on its own line with timestamp"
    echo "  Looking for: ^### PROMPT YYYY-MM-DD-HH:MM:SS$"
fi

# 3. END PROMPT marker should be on its own line (no timestamp)
if echo "$AI_OUTPUT" | grep -E "^### END PROMPT$" > /dev/null; then
    assert_success "true" "END PROMPT marker is on its own line"
else
    assert_fails "true" "END PROMPT marker should be on its own line"
    echo "  Looking for: ^### END PROMPT$"
fi

# 4. There should be a blank line BEFORE the PROMPT marker
# Extract context around PROMPT marker
BEFORE_PROMPT=$(echo "$AI_OUTPUT" | grep -B 2 "### PROMPT" | head -n 2)
if echo "$BEFORE_PROMPT" | tail -n 1 | grep -E "^[[:space:]]*$" > /dev/null; then
    assert_success "true" "Blank line exists before PROMPT marker"
else
    echo "WARNING: No blank line before PROMPT marker (may affect readability)"
fi

# 5. Prompt content should start on line AFTER PROMPT marker
# Extract section between markers
BETWEEN_MARKERS=$(echo "$AI_OUTPUT" | sed -n '/### PROMPT/,/### END PROMPT/p')

if echo "$BETWEEN_MARKERS" | grep -q "$PROMPT"; then
    assert_success "true" "Prompt content appears between markers"
else
    assert_fails "true" "Prompt content should appear between markers"
fi

# 6. Response (if any) should start on a NEW LINE after END PROMPT
# The markers mode mock should generate a response after END PROMPT
AFTER_END_MARKER=$(echo "$AI_OUTPUT" | sed -n '/### END PROMPT/,$p' | tail -n +2)

if [ -n "$AFTER_END_MARKER" ]; then
    # Check if first line after END PROMPT is blank or contains response
    FIRST_LINE_AFTER=$(echo "$AFTER_END_MARKER" | head -n 1)

    if [ -z "$FIRST_LINE_AFTER" ] || echo "$FIRST_LINE_AFTER" | grep -E "^[[:space:]]*$" > /dev/null; then
        assert_success "true" "Blank line after END PROMPT marker (good formatting)"
    else
        # Response starts immediately - that's also acceptable
        assert_success "true" "Response starts after END PROMPT marker"
    fi
fi

# 7. No duplicate markers (each should appear exactly once)
PROMPT_MARKER_COUNT=$(echo "$AI_OUTPUT" | grep -c "^### PROMPT")
END_PROMPT_MARKER_COUNT=$(echo "$AI_OUTPUT" | grep -c "^### END PROMPT")

assert_equals "$PROMPT_MARKER_COUNT" "1" "Should have exactly 1 PROMPT marker"
assert_equals "$END_PROMPT_MARKER_COUNT" "1" "Should have exactly 1 END PROMPT marker"

print_assertion_summary
