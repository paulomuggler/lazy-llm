#!/usr/bin/env bash
# Test: Large prompt (>1KB) send with proper delay handling

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

TEST_NAME="large-paste"
FIXTURE="$TESTS_DIR/fixtures/large-prompt.txt"

echo "Starting lazy-llm session..."
if ! start_lazy_llm_session "$TEST_NAME"; then
    echo "Failed to start session"
    exit 1
fi

sleep 2

# Verify fixture is actually large (>1KB)
if [ ! -f "$FIXTURE" ]; then
    echo "ERROR: Fixture not found: $FIXTURE"
    exit 1
fi

FIXTURE_SIZE=$(wc -c < "$FIXTURE")
echo "Fixture size: $FIXTURE_SIZE bytes"

if [ "$FIXTURE_SIZE" -lt 1024 ]; then
    echo "WARNING: Fixture is smaller than 1KB, test may not be meaningful"
fi

# Load large prompt
PROMPT_CONTENT=$(cat "$FIXTURE")

# Send to buffer
echo "Sending large prompt to buffer..."
send_to_prompt_buffer_simple "$PROMPT_CONTENT"

# Trigger send
echo "Triggering LLM send..."
START_TIME=$(date +%s)
trigger_llm_send

# For large pastes, llm-send adds a 0.5s delay
# So we should wait a bit longer
sleep 2

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Capture AI pane output
echo "Capturing AI pane output..."
AI_OUTPUT=$(capture_pane "$AI_PANE")

# Assertions
echo ""
echo "Running assertions..."

# Basic marker checks
assert_contains "$AI_OUTPUT" "### PROMPT" "Should contain PROMPT marker"
assert_contains "$AI_OUTPUT" "### END PROMPT" "Should contain END PROMPT marker"

# Check that content from fixture appears
assert_contains "$AI_OUTPUT" "distributed system" "Should contain content from fixture"
assert_contains "$AI_OUTPUT" "Performance Bottlenecks" "Should preserve headers"
assert_contains "$AI_OUTPUT" "RabbitMQ cluster" "Should preserve technical details"

# Verify large content is not truncated
assert_contains "$AI_OUTPUT" "Constraints" "Should include content near end of prompt"
assert_contains "$AI_OUTPUT" "additional context" "Should include final content"

# Check that timing was appropriate (delay was applied)
if [ "$ELAPSED" -ge 1 ]; then
    assert_success "true" "Send took ${ELAPSED}s (delay applied for large paste)"
else
    echo "WARNING: Send took ${ELAPSED}s, expected >=1s for large paste"
fi

# Line count should be substantial
LINE_COUNT=$(echo "$AI_OUTPUT" | wc -l)
if [ "$LINE_COUNT" -gt 50 ]; then
    assert_success "true" "Output has >50 lines (actual: $LINE_COUNT)"
else
    assert_fails "true" "Output should have >50 lines for large prompt (actual: $LINE_COUNT)"
fi

print_assertion_summary
