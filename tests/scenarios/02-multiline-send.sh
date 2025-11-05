#!/usr/bin/env bash
# Test: Multiline prompt send with proper formatting

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

TEST_NAME="multiline-send"
FIXTURE="$TESTS_DIR/fixtures/multiline-prompt.txt"

echo "Starting lazy-llm session..."
if ! start_lazy_llm_session "$TEST_NAME"; then
    echo "Failed to start session"
    exit 1
fi

sleep 2

# Load multiline prompt from fixture
echo "Loading multiline prompt from fixture..."
if [ ! -f "$FIXTURE" ]; then
    echo "ERROR: Fixture not found: $FIXTURE"
    exit 1
fi

PROMPT_CONTENT=$(cat "$FIXTURE")

# Send to buffer
echo "Sending multiline prompt to buffer..."
send_to_prompt_buffer_simple "$PROMPT_CONTENT"

# Trigger send
echo "Triggering LLM send..."
trigger_llm_send

# Wait for processing
sleep 1.5

# Capture AI pane output
echo "Capturing AI pane output..."
AI_OUTPUT=$(capture_pane "$AI_PANE")

# Assertions
echo ""
echo "Running assertions..."

assert_contains "$AI_OUTPUT" "### PROMPT" "Should contain PROMPT marker"
assert_contains "$AI_OUTPUT" "### END PROMPT" "Should contain END PROMPT marker"
assert_contains "$AI_OUTPUT" "Python function" "Should contain prompt content"

# Verify multiline content is preserved
assert_contains "$AI_OUTPUT" "Takes a list" "Should preserve line 1"
assert_contains "$AI_OUTPUT" "Filters out negative" "Should preserve line 2"
assert_contains "$AI_OUTPUT" "Returns the sum" "Should preserve line 3"

# Check line count (should be more than 10 lines total)
LINE_COUNT=$(echo "$AI_OUTPUT" | wc -l)
if [ "$LINE_COUNT" -gt 10 ]; then
    assert_success "true" "Output has >10 lines (actual: $LINE_COUNT)"
else
    assert_fails "true" "Output should have >10 lines (actual: $LINE_COUNT)"
fi

# Verify markers are on separate lines (critical for response parsing)
# Extract text around markers to check formatting
MARKER_CONTEXT=$(echo "$AI_OUTPUT" | grep -A 1 -B 1 "### PROMPT")

# The PROMPT marker should be on its own line (not in middle of text)
if echo "$AI_OUTPUT" | grep -E "^### PROMPT [0-9-:]+$" > /dev/null; then
    assert_success "true" "PROMPT marker is on its own line"
else
    assert_fails "true" "PROMPT marker should be on its own line"
fi

if echo "$AI_OUTPUT" | grep -E "^### END PROMPT$" > /dev/null; then
    assert_success "true" "END PROMPT marker is on its own line"
else
    assert_fails "true" "END PROMPT marker should be on its own line"
fi

print_assertion_summary
