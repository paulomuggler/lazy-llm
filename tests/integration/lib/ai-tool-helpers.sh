#!/usr/bin/env bash
# AI tool helpers for integration tests

# Load environment variables from .env file
load_dotenv() {
    local env_file="${1:-tests/integration/.env}"

    if [ ! -f "$env_file" ]; then
        echo "ERROR: .env file not found: $env_file"
        echo "Copy .env.example to .env and add your API keys:"
        echo "  cp tests/integration/.env.example tests/integration/.env"
        return 1
    fi

    # Load variables from .env
    set -a
    source "$env_file"
    set +a

    return 0
}

# Check if a tool is available and configured
require_tool() {
    local tool_name=$1
    local api_key_var=$2

    # Check if tool is installed
    if ! command -v "$tool_name" &> /dev/null; then
        echo "ERROR: $tool_name not found in PATH"
        echo "Please install it first"
        return 1
    fi

    # Check if API key is set (if required)
    if [ -n "$api_key_var" ]; then
        if [ -z "${!api_key_var}" ]; then
            echo "ERROR: $api_key_var not set"
            echo "Please add it to tests/integration/.env"
            return 1
        fi
    fi

    return 0
}

# Start lazy-llm session with specific AI tool
start_lazy_llm_with_ai_tool() {
    local session_name=$1
    local ai_tool=$2
    local working_dir=${3:-"$PWD"}

    # Ensure API keys are exported
    export ANTHROPIC_API_KEY
    export GEMINI_API_KEY

    # Kill any existing test session
    tmux kill-session -t "test-${session_name}" 2>/dev/null || true

    # Start lazy-llm
    if ! command -v lazy-llm &> /dev/null; then
        echo "ERROR: lazy-llm not found in PATH"
        return 1
    fi

    # Start in detached mode
    lazy-llm -s "test-${session_name}" -t "$ai_tool" -d "$working_dir" &
    local lazy_llm_pid=$!

    # Wait for session to be created
    local timeout=${INTEGRATION_TEST_TIMEOUT:-30}
    local elapsed=0
    while ! tmux has-session -t "test-${session_name}" 2>/dev/null; do
        sleep 0.5
        elapsed=$((elapsed + 1))
        if [ $elapsed -gt $((timeout * 2)) ]; then
            echo "ERROR: Timeout waiting for lazy-llm session"
            return 1
        fi
    done

    # Store session name
    export TEST_SESSION="test-${session_name}"

    # Wait for panes to initialize
    sleep 2

    # Get pane IDs
    export AI_PANE=$(tmux list-panes -t "${TEST_SESSION}:0" -F '#{pane_index}:#{pane_id}' | grep '^0:' | cut -d: -f2)
    export EDITOR_PANE=$(tmux list-panes -t "${TEST_SESSION}:0" -F '#{pane_index}:#{pane_id}' | grep '^1:' | cut -d: -f2)
    export PROMPT_PANE=$(tmux list-panes -t "${TEST_SESSION}:0" -F '#{pane_index}:#{pane_id}' | grep '^2:' | cut -d: -f2)

    # Verify panes exist
    if [ -z "$AI_PANE" ] || [ -z "$EDITOR_PANE" ] || [ -z "$PROMPT_PANE" ]; then
        echo "ERROR: Failed to get pane IDs"
        return 1
    fi

    if [ -n "$DEBUG" ]; then
        echo "Integration test session created: $TEST_SESSION"
        echo "AI Tool: $ai_tool"
        echo "AI Pane: $AI_PANE"
        echo "Editor Pane: $EDITOR_PANE"
        echo "Prompt Pane: $PROMPT_PANE"
    fi

    return 0
}

# Send prompt and wait for AI response
send_prompt() {
    local prompt=$1
    local timeout=${2:-30}

    # Clear prompt buffer
    tmux send-keys -t "$PROMPT_PANE" Escape "ggdG"
    sleep 0.3

    # Insert prompt
    tmux send-keys -t "$PROMPT_PANE" "i$prompt" Escape
    sleep 0.3

    # Trigger send
    tmux send-keys -t "$PROMPT_PANE" '\' 'llms'
    sleep 0.5

    return 0
}

# Wait for AI response to appear
wait_for_response() {
    local timeout=${1:-30}
    local marker="### END PROMPT"

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local content=$(tmux capture-pane -p -t "$AI_PANE" -S -2000)

        # Check if END PROMPT marker exists
        if echo "$content" | grep -q "$marker"; then
            # Check if there's content after the marker (the response)
            local after_marker=$(echo "$content" | sed -n '/### END PROMPT/,$p' | tail -n +2)

            if [ -n "$after_marker" ] && [ "${#after_marker}" -gt 10 ]; then
                # Found a response
                return 0
            fi
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "WARNING: Timeout waiting for AI response"
    return 1
}

# Check if autosubmit worked (no manual Enter needed)
check_autosubmit_success() {
    local ai_output=$1

    # If we see the response after END PROMPT marker, autosubmit worked
    local after_marker=$(echo "$ai_output" | sed -n '/### END PROMPT/,$p' | tail -n +2)

    if [ -n "$after_marker" ] && [ "${#after_marker}" -gt 10 ]; then
        return 0  # Success
    else
        return 1  # Failed - probably needs manual Enter
    fi
}

# Extract response content (everything after ### END PROMPT)
extract_response() {
    local ai_output=$1

    echo "$ai_output" | sed -n '/### END PROMPT/,$p' | tail -n +2
}

# Check if tool is enabled in config
is_tool_enabled() {
    local tool=$1

    case "$tool" in
        claude)
            [ "${TEST_CLAUDE:-true}" = "true" ]
            ;;
        gemini)
            [ "${TEST_GEMINI:-true}" = "true"  ]
            ;;
        codex)
            [ "${TEST_CODEX:-false}" = "true" ]
            ;;
        *)
            return 1
            ;;
    esac
}

# Skip test if tool not enabled
skip_if_disabled() {
    local tool=$1

    if ! is_tool_enabled "$tool"; then
        echo "SKIPPED: $tool testing is disabled in .env (TEST_${tool^^}=false)"
        exit 0
    fi
}
