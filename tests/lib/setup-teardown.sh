#!/usr/bin/env bash
# Setup and teardown helpers for lazy-llm tests

# Test environment directories
TEST_STATE_DIR="/tmp/lazy-llm-test-state"
TEST_LOG_DIR="/tmp/lazy-llm-test-logs"

# Setup test environment before running a test
setup_test_env() {
    local test_name=${1:-"test"}

    # Create test directories
    mkdir -p "$TEST_STATE_DIR"
    mkdir -p "$TEST_LOG_DIR"

    # Create test-specific log file
    export TEST_LOG_FILE="$TEST_LOG_DIR/${test_name}.log"
    echo "=== Test: $test_name ===" > "$TEST_LOG_FILE"
    echo "Started at: $(date)" >> "$TEST_LOG_FILE"
    echo "" >> "$TEST_LOG_FILE"

    # Reset assertion counters
    export ASSERTIONS_PASSED=0
    export ASSERTIONS_FAILED=0

    # Set default mock AI mode if not specified
    export MOCK_AI_MODE=${MOCK_AI_MODE:-multiline}

    # Debug mode
    if [ -n "$DEBUG" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Setting up test environment: $test_name"
        echo "State dir: $TEST_STATE_DIR"
        echo "Log dir: $TEST_LOG_DIR"
        echo "Mock AI mode: $MOCK_AI_MODE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi

    return 0
}

# Teardown test environment after running a test
teardown_test_env() {
    # Kill any test tmux sessions
    if [ -n "$TEST_SESSION" ]; then
        if [ -n "$DEBUG" ]; then
            echo ""
            echo "Keeping session $TEST_SESSION for debugging (DEBUG mode)"
            echo "To inspect: tmux attach -t $TEST_SESSION"
            echo "To kill: tmux kill-session -t $TEST_SESSION"
        else
            kill_test_session
        fi
    fi

    # Clean up temporary files unless in debug mode
    if [ -z "$DEBUG" ]; then
        rm -f /tmp/test-*-mock-ai.log
        rm -f /tmp/mock-ai-tool-*.log
    fi

    # Log test completion
    if [ -n "$TEST_LOG_FILE" ]; then
        echo "" >> "$TEST_LOG_FILE"
        echo "Completed at: $(date)" >> "$TEST_LOG_FILE"
    fi

    return 0
}

# Clean up all test artifacts
cleanup_all_test_artifacts() {
    echo "Cleaning up all test artifacts..."

    # Kill all test sessions
    for session in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^test-'); do
        echo "  Killing session: $session"
        tmux kill-session -t "$session" 2>/dev/null || true
    done

    # Remove test directories
    if [ -d "$TEST_STATE_DIR" ]; then
        echo "  Removing state directory: $TEST_STATE_DIR"
        rm -rf "$TEST_STATE_DIR"
    fi

    if [ -d "$TEST_LOG_DIR" ]; then
        echo "  Removing log directory: $TEST_LOG_DIR"
        rm -rf "$TEST_LOG_DIR"
    fi

    # Remove temporary mock AI logs
    rm -f /tmp/test-*-mock-ai.log 2>/dev/null
    rm -f /tmp/mock-ai-tool-*.log 2>/dev/null

    echo "Cleanup complete."
}

# Check if lazy-llm is installed
check_lazy_llm_installed() {
    if ! command -v lazy-llm &> /dev/null; then
        echo "ERROR: lazy-llm not found in PATH"
        echo "Please run install.sh first:"
        echo "  cd /home/user/lazy-llm && ./install.sh"
        return 1
    fi
    return 0
}

# Check if required tools are available
check_dependencies() {
    local missing_deps=()

    if ! command -v tmux &> /dev/null; then
        missing_deps+=("tmux")
    fi

    if ! command -v nvim &> /dev/null; then
        missing_deps+=("nvim")
    fi

    if ! command -v lazy-llm &> /dev/null; then
        missing_deps+=("lazy-llm (run install.sh)")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "ERROR: Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        return 1
    fi

    return 0
}

# Verify test environment is ready
verify_test_environment() {
    echo "Verifying test environment..."

    # Check dependencies
    if ! check_dependencies; then
        return 1
    fi

    # Check if we can create test directories
    if ! mkdir -p "$TEST_STATE_DIR" "$TEST_LOG_DIR"; then
        echo "ERROR: Cannot create test directories"
        return 1
    fi

    # Check if mock-ai-tool exists and is executable
    if [ ! -x "tests/mock-ai-tool" ]; then
        echo "ERROR: tests/mock-ai-tool not found or not executable"
        return 1
    fi

    echo "✓ Test environment ready"
    return 0
}

# Save test artifacts for debugging
save_test_artifacts() {
    local test_name=$1
    local artifact_dir="$TEST_STATE_DIR/${test_name}-artifacts"

    mkdir -p "$artifact_dir"

    # Capture all pane contents if session exists
    if [ -n "$TEST_SESSION" ] && tmux has-session -t "$TEST_SESSION" 2>/dev/null; then
        if [ -n "$AI_PANE" ]; then
            capture_pane "$AI_PANE" > "$artifact_dir/ai-pane.txt"
        fi

        if [ -n "$EDITOR_PANE" ]; then
            capture_pane "$EDITOR_PANE" > "$artifact_dir/editor-pane.txt"
        fi

        if [ -n "$PROMPT_PANE" ]; then
            capture_pane "$PROMPT_PANE" > "$artifact_dir/prompt-pane.txt"
        fi
    fi

    # Copy mock AI log
    if [ -f "$MOCK_AI_LOG" ]; then
        cp "$MOCK_AI_LOG" "$artifact_dir/mock-ai.log"
    fi

    # Copy test log
    if [ -f "$TEST_LOG_FILE" ]; then
        cp "$TEST_LOG_FILE" "$artifact_dir/test.log"
    fi

    echo "Test artifacts saved to: $artifact_dir"
}

# Trap to cleanup on exit
trap_cleanup() {
    if [ -z "$DEBUG" ]; then
        teardown_test_env
    fi
}

# Set trap for clean exit
setup_trap() {
    trap trap_cleanup EXIT INT TERM
}
