#!/usr/bin/env bash
# Tmux session management helpers for lazy-llm tests

# Global test session variables
TEST_SESSION=""
AI_PANE=""
EDITOR_PANE=""
PROMPT_PANE=""

# Start a lazy-llm session for testing
start_lazy_llm_session() {
    local session_name=$1
    local ai_tool=${2:-"tests/mock-ai-tool"}
    local working_dir=${3:-"$PWD"}

    # Export mock AI configuration
    export MOCK_AI_MODE=${MOCK_AI_MODE:-multiline}
    export MOCK_AI_LOG="/tmp/test-${session_name}-mock-ai.log"

    # Use absolute path for mock-ai-tool if it's relative
    if [[ "$ai_tool" == "tests/mock-ai-tool" ]]; then
        ai_tool="$PWD/tests/mock-ai-tool"
    fi

    # Kill any existing test session
    tmux kill-session -t "test-${session_name}" 2>/dev/null || true

    # Start lazy-llm with test session
    # Note: lazy-llm should be in PATH (installed via install.sh)
    if ! command -v lazy-llm &> /dev/null; then
        echo "ERROR: lazy-llm not found in PATH"
        echo "Please run install.sh first"
        return 1
    fi

    # Start lazy-llm in detached mode
    # Unset TMUX so lazy-llm creates a new session instead of adding a window
    env -u TMUX lazy-llm -s "test-${session_name}" -t "$ai_tool" -d "$working_dir" &
    local lazy_llm_pid=$!

    # Wait for session to be created (with timeout)
    local timeout=10
    local elapsed=0
    while ! tmux has-session -t "test-${session_name}" 2>/dev/null; do
        sleep 0.5
        elapsed=$((elapsed + 1))
        if [ $elapsed -gt $((timeout * 2)) ]; then
            echo "ERROR: Timeout waiting for lazy-llm session"
            return 1
        fi
    done

    # Store session name and pane IDs
    export TEST_SESSION="test-${session_name}"

    # Wait a bit more for panes to be fully initialized
    sleep 1

    # Get pane IDs from tmux window
    export AI_PANE=$(tmux list-panes -t "${TEST_SESSION}:0" -F '#{pane_index}:#{pane_id}' | grep '^0:' | cut -d: -f2)
    export EDITOR_PANE=$(tmux list-panes -t "${TEST_SESSION}:0" -F '#{pane_index}:#{pane_id}' | grep '^1:' | cut -d: -f2)
    export PROMPT_PANE=$(tmux list-panes -t "${TEST_SESSION}:0" -F '#{pane_index}:#{pane_id}' | grep '^2:' | cut -d: -f2)

    # Verify panes exist
    if [ -z "$AI_PANE" ] || [ -z "$EDITOR_PANE" ] || [ -z "$PROMPT_PANE" ]; then
        echo "ERROR: Failed to get pane IDs"
        echo "AI_PANE=$AI_PANE, EDITOR_PANE=$EDITOR_PANE, PROMPT_PANE=$PROMPT_PANE"
        return 1
    fi

    # Debug output
    if [ -n "$DEBUG" ]; then
        echo "Session created: $TEST_SESSION"
        echo "AI Pane: $AI_PANE"
        echo "Editor Pane: $EDITOR_PANE"
        echo "Prompt Pane: $PROMPT_PANE"
    fi

    return 0
}

# Capture pane content with history
capture_pane() {
    local pane_id=$1
    local history=${2:-2000}

    if [ -z "$pane_id" ]; then
        echo "ERROR: No pane ID provided to capture_pane"
        return 1
    fi

    tmux capture-pane -p -t "$pane_id" -S -"$history" -J
}

# Capture just visible pane content (no history)
capture_pane_visible() {
    local pane_id=$1

    if [ -z "$pane_id" ]; then
        echo "ERROR: No pane ID provided to capture_pane_visible"
        return 1
    fi

    tmux capture-pane -p -t "$pane_id"
}

# Send text to prompt buffer pane
send_to_prompt_buffer() {
    local content=$1

    if [ -z "$PROMPT_PANE" ]; then
        echo "ERROR: PROMPT_PANE not set"
        return 1
    fi

    # If content is a file, read it
    if [ -f "$content" ]; then
        content=$(cat "$content")
    fi

    # Clear prompt buffer first
    tmux send-keys -t "$PROMPT_PANE" Escape  # Exit insert mode if in it
    sleep 0.1
    tmux send-keys -t "$PROMPT_PANE" "ggdG"  # Delete all content
    sleep 0.1

    # Insert content via command mode
    # We'll send line by line to avoid issues with special characters
    while IFS= read -r line; do
        # Escape special characters for vim
        local escaped_line=$(echo "$line" | sed 's/"/\\"/g')
        tmux send-keys -t "$PROMPT_PANE" "i$line" Escape
        tmux send-keys -t "$PROMPT_PANE" "o" Escape  # Add newline
    done <<< "$content"

    # Return to normal mode
    tmux send-keys -t "$PROMPT_PANE" Escape

    sleep 0.2
    return 0
}

# Send text directly to prompt buffer (simple version)
send_to_prompt_buffer_simple() {
    local text=$1

    if [ -z "$PROMPT_PANE" ]; then
        echo "ERROR: PROMPT_PANE not set"
        return 1
    fi

    # Clear and insert text
    tmux send-keys -t "$PROMPT_PANE" Escape "ggdG" "i" "$text" Escape
    sleep 0.2
}

# Send keys to editor pane (Neovim in middle pane)
tmux_send_keys_to_nvim() {
    local keys=$1

    if [ -z "$EDITOR_PANE" ]; then
        echo "ERROR: EDITOR_PANE not set"
        return 1
    fi

    # Convert \\ to actual backslash for leader key
    keys="${keys//\\\\/\\}"

    tmux send-keys -t "$EDITOR_PANE" "$keys"
    sleep 0.2
}

# Send keys to prompt pane
tmux_send_keys_to_prompt() {
    local keys=$1

    if [ -z "$PROMPT_PANE" ]; then
        echo "ERROR: PROMPT_PANE not set"
        return 1
    fi

    tmux send-keys -t "$PROMPT_PANE" "$keys"
    sleep 0.2
}

# Send llms command (main send command)
trigger_llm_send() {
    # Focus prompt pane first
    tmux select-pane -t "$PROMPT_PANE"
    sleep 0.2

    # Send the <leader>llms keymap
    # Assuming <leader> is \
    tmux send-keys -t "$PROMPT_PANE" '\' 'llms'
    sleep 0.5  # Wait for send to complete
}

# Send llmk command (keypress forwarding)
trigger_llm_keypress() {
    local key=$1

    tmux select-pane -t "$PROMPT_PANE"
    sleep 0.1

    # Send <leader>llmk followed by the key
    tmux send-keys -t "$PROMPT_PANE" '\' 'llmk' "$key"
    sleep 0.3
}

# Send llmp command (pull response)
trigger_llm_pull() {
    tmux select-pane -t "$PROMPT_PANE"
    sleep 0.1

    tmux send-keys -t "$PROMPT_PANE" '\' 'llmp'
    sleep 0.5  # Wait for pull to complete
}

# Wait for text to appear in a pane
wait_for_text_in_pane() {
    local pane_id=$1
    local text=$2
    local timeout=${3:-10}

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local content=$(capture_pane "$pane_id")
        if [[ "$content" =~ $text ]]; then
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    echo "ERROR: Timeout waiting for text '$text' in pane $pane_id"
    return 1
}

# Kill test session
kill_test_session() {
    if [ -n "$TEST_SESSION" ]; then
        tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
    fi

    # Clear variables
    TEST_SESSION=""
    AI_PANE=""
    EDITOR_PANE=""
    PROMPT_PANE=""
}

# Check if we're in a tmux session
is_in_tmux() {
    [ -n "$TMUX" ]
}

# Get number of panes in test session
get_pane_count() {
    if [ -z "$TEST_SESSION" ]; then
        echo "0"
        return
    fi

    tmux list-panes -t "$TEST_SESSION" | wc -l
}

# Check if session is alive
session_alive() {
    local session=$1
    tmux has-session -t "$session" 2>/dev/null
}

# Helper: Start lazy-llm in a specific directory (wrapper for clarity in tests)
start_lazy_llm_session_in_dir() {
    local session_name=$1
    local working_dir=$2
    local ai_tool=${3:-"tests/mock-ai-tool"}

    start_lazy_llm_session "$session_name" "$ai_tool" "$working_dir"
}

# Helper: Start lazy-llm with custom args
start_lazy_llm_session_with_args() {
    local session_name=$1
    local extra_args=$2

    # Export mock AI configuration
    export MOCK_AI_MODE=${MOCK_AI_MODE:-multiline}
    export MOCK_AI_LOG="/tmp/test-${session_name}-mock-ai.log"

    # Use absolute path for mock-ai-tool
    local ai_tool="$PWD/tests/mock-ai-tool"

    # Kill any existing test session
    tmux kill-session -t "test-${session_name}" 2>/dev/null || true

    # Start lazy-llm with custom args
    if ! command -v lazy-llm &> /dev/null; then
        echo "ERROR: lazy-llm not found in PATH"
        return 1
    fi

    # Start lazy-llm with extra args
    # Unset TMUX so lazy-llm creates a new session instead of adding a window
    eval "env -u TMUX lazy-llm -s \"test-${session_name}\" -t \"$ai_tool\" $extra_args" &
    local lazy_llm_pid=$!

    # Wait for session to be created
    local timeout=10
    local elapsed=0
    while ! tmux has-session -t "test-${session_name}" 2>/dev/null; do
        sleep 0.5
        elapsed=$((elapsed + 1))
        if [ $elapsed -gt $((timeout * 2)) ]; then
            echo "ERROR: Timeout waiting for lazy-llm session"
            return 1
        fi
    done

    # Store session name and pane IDs
    export TEST_SESSION="test-${session_name}"

    # Wait for panes to be initialized
    sleep 1

    # Get pane IDs
    export AI_PANE=$(tmux list-panes -t "${TEST_SESSION}:0" -F '#{pane_index}:#{pane_id}' | grep '^0:' | cut -d: -f2)
    export EDITOR_PANE=$(tmux list-panes -t "${TEST_SESSION}:0" -F '#{pane_index}:#{pane_id}' | grep '^1:' | cut -d: -f2)
    export PROMPT_PANE=$(tmux list-panes -t "${TEST_SESSION}:0" -F '#{pane_index}:#{pane_id}' | grep '^2:' | cut -d: -f2)

    # Verify panes exist
    if [ -z "$AI_PANE" ] || [ -z "$EDITOR_PANE" ] || [ -z "$PROMPT_PANE" ]; then
        echo "ERROR: Failed to get pane IDs"
        return 1
    fi

    return 0
}
