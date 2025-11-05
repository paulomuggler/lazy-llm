#!/usr/bin/env bash
# Test: Keypress forwarding (llmk) for interactive prompts

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

TEST_NAME="keypress-forward"

# Use interactive mode which prompts for 1/2/3 choices
export MOCK_AI_MODE="interactive"

echo "Starting lazy-llm session with interactive mode..."
if ! start_lazy_llm_session "$TEST_NAME"; then
    echo "Failed to start session"
    exit 1
fi

sleep 2

# Send a prompt to trigger interactive response
echo "Sending prompt..."
PROMPT="What should I do?"
send_to_prompt_buffer_simple "$PROMPT"

# Trigger send
trigger_llm_send
sleep 2

# Verify AI is asking for choice
AI_OUTPUT=$(capture_pane "$AI_PANE")
echo "AI pane output captured"

assert_contains "$AI_OUTPUT" "choose:" "AI should be asking for choice"
assert_contains "$AI_OUTPUT" "1. Option A" "Should show option 1"
assert_contains "$AI_OUTPUT" "2. Option B" "Should show option 2"
assert_contains "$AI_OUTPUT" "3. Option C" "Should show option 3"

# Now use llmk to forward a keypress (choose option 2)
echo ""
echo "Forwarding keypress '2' to AI pane..."
trigger_llm_keypress "2"

# Wait for AI to process choice
sleep 1

# Capture updated AI output
AI_OUTPUT_AFTER=$(capture_pane "$AI_PANE")

# Assertions
echo ""
echo "Running assertions after keypress..."

# Should contain confirmation of choice
assert_contains "$AI_OUTPUT_AFTER" "selected option 2" "AI should confirm choice 2"
assert_contains "$AI_OUTPUT_AFTER" "Processing..." "AI should be processing choice"

# The number 2 should appear as input
assert_contains "$AI_OUTPUT_AFTER" "2" "Choice should be visible in output"

print_assertion_summary
