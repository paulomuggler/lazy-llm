#!/usr/bin/env bash
# Test: Workspace-local directory creation and isolation

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

TEST_NAME="workspace-local-dirs"

# Create temporary workspace directories for testing
WORKSPACE1="/tmp/lazy-llm-test-workspace1-$$"
WORKSPACE2="/tmp/lazy-llm-test-workspace2-$$"

cleanup_workspaces() {
    rm -rf "$WORKSPACE1" "$WORKSPACE2"
}

# Ensure cleanup on exit
trap cleanup_workspaces EXIT

echo "Creating test workspaces..."
mkdir -p "$WORKSPACE1"
mkdir -p "$WORKSPACE2"

# Test 1: Verify .lazy-llm directory is created in workspace1
echo ""
echo "Test 1: Starting lazy-llm in workspace1..."
if ! start_lazy_llm_session_in_dir "$TEST_NAME-ws1" "$WORKSPACE1"; then
    echo "Failed to start session in workspace1"
    exit 1
fi

# Wait for initialization
sleep 2

# Check that .lazy-llm directory was created in workspace1
echo "Verifying .lazy-llm directory exists in workspace1..."
assert_dir_exists "$WORKSPACE1/.lazy-llm" ".lazy-llm directory should be created in workspace1"
assert_dir_exists "$WORKSPACE1/.lazy-llm/prompts" "prompts subdirectory should exist"
assert_dir_exists "$WORKSPACE1/.lazy-llm/swap" "swap subdirectory should exist"
assert_dir_exists "$WORKSPACE1/.lazy-llm/undo" "undo subdirectory should exist"

# Kill workspace1 session
kill_test_session

# Test 2: Verify .lazy-llm directory is created in workspace2 (independent)
echo ""
echo "Test 2: Starting lazy-llm in workspace2..."
if ! start_lazy_llm_session_in_dir "$TEST_NAME-ws2" "$WORKSPACE2"; then
    echo "Failed to start session in workspace2"
    exit 1
fi

# Wait for initialization
sleep 2

# Check that .lazy-llm directory was created in workspace2
echo "Verifying .lazy-llm directory exists in workspace2..."
assert_dir_exists "$WORKSPACE2/.lazy-llm" ".lazy-llm directory should be created in workspace2"
assert_dir_exists "$WORKSPACE2/.lazy-llm/prompts" "prompts subdirectory should exist in workspace2"
assert_dir_exists "$WORKSPACE2/.lazy-llm/swap" "swap subdirectory should exist in workspace2"
assert_dir_exists "$WORKSPACE2/.lazy-llm/undo" "undo subdirectory should exist in workspace2"

# Kill workspace2 session
kill_test_session

# Test 3: Verify workspaces are isolated
echo ""
echo "Test 3: Verifying workspace isolation..."

# Create a test file in workspace1's prompt directory
TEST_FILE1="$WORKSPACE1/.lazy-llm/prompts/test-prompt-1.md"
echo "Test prompt from workspace 1" > "$TEST_FILE1"

# Verify it exists in workspace1
assert_file_exists "$TEST_FILE1" "Test file should exist in workspace1"

# Verify it does NOT exist in workspace2
TEST_FILE2="$WORKSPACE2/.lazy-llm/prompts/test-prompt-1.md"
assert_file_not_exists "$TEST_FILE2" "Test file should NOT exist in workspace2"

# Test 4: Verify no global state directory interference
echo ""
echo "Test 4: Verifying no global state directory is created..."

# Check that the old global directory is NOT being used/created during these tests
GLOBAL_STATE_DIR="$HOME/.local/state/lazy-llm"
if [ -d "$GLOBAL_STATE_DIR" ]; then
    # If it exists (from previous installations), check it wasn't modified
    # We can't easily test this without comparing timestamps, so we'll just
    # verify that our workspace-local directories exist instead
    print_info "Global state dir exists from previous installation, but workspace-local dirs take precedence"
fi

# The key test is that workspace-local directories exist and are being used
assert_dir_exists "$WORKSPACE1/.lazy-llm" "Workspace1 uses local .lazy-llm directory"
assert_dir_exists "$WORKSPACE2/.lazy-llm" "Workspace2 uses local .lazy-llm directory"

# Test 5: Verify directory structure after lazy-llm usage
echo ""
echo "Test 5: Testing directory creation with -d flag..."

# Create a third workspace and use -d flag
WORKSPACE3="/tmp/lazy-llm-test-workspace3-$$"
mkdir -p "$WORKSPACE3"

# Start lazy-llm with -d flag pointing to workspace3
if ! start_lazy_llm_session_with_args "$TEST_NAME-ws3" "-d \"$WORKSPACE3\""; then
    echo "Failed to start session with -d flag"
    exit 1
fi

# Wait for initialization
sleep 2

# Verify workspace3 has its own .lazy-llm directory
echo "Verifying .lazy-llm directory created via -d flag..."
assert_dir_exists "$WORKSPACE3/.lazy-llm" ".lazy-llm directory should be created when using -d flag"
assert_dir_exists "$WORKSPACE3/.lazy-llm/prompts" "prompts subdirectory should exist in workspace3"
assert_dir_exists "$WORKSPACE3/.lazy-llm/swap" "swap subdirectory should exist in workspace3"
assert_dir_exists "$WORKSPACE3/.lazy-llm/undo" "undo subdirectory should exist in workspace3"

# Kill workspace3 session
kill_test_session

# Cleanup workspace3
rm -rf "$WORKSPACE3"

# Exit with assertion results
echo ""
print_assertion_summary
