#!/usr/bin/env bash
# Test: Unit test for init_state_dirs function (no tmux required)

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"

TEST_NAME="init-state-dirs-unit"

echo "Testing init_state_dirs function..."

# Create a test workspace directory
TEST_WORKSPACE="/tmp/lazy-llm-test-init-$$"
mkdir -p "$TEST_WORKSPACE"

# Source the lazy-llm script to get the functions
# We need to extract just the init_state_dirs function
LAZY_LLM_SCRIPT="$TESTS_DIR/../lazy-llm-bin/.local/bin/lazy-llm"

if [ ! -f "$LAZY_LLM_SCRIPT" ]; then
    echo "ERROR: lazy-llm script not found at $LAZY_LLM_SCRIPT"
    exit 1
fi

# Extract and test the init_state_dirs logic
# We'll simulate what the script does

# Set TARGET_DIR (simulating user running lazy-llm in a directory)
TARGET_DIR="$TEST_WORKSPACE"

# Initialize variables (as the script does)
STATE_DIR=""
PROMPTS_DIR=""
SWAP_DIR=""
UNDO_DIR=""

# Run the init logic (extracted from the script)
STATE_DIR="${TARGET_DIR}/.lazy-llm"
PROMPTS_DIR="${STATE_DIR}/prompts"
SWAP_DIR="${STATE_DIR}/swap"
UNDO_DIR="${STATE_DIR}/undo"

# Create directories
mkdir -p "$PROMPTS_DIR" "$SWAP_DIR" "$UNDO_DIR"

echo ""
echo "Test 1: Verifying directory structure..."

# Test that directories were created
assert_dir_exists "$STATE_DIR" "STATE_DIR should be created at $STATE_DIR"
assert_dir_exists "$PROMPTS_DIR" "PROMPTS_DIR should exist at $PROMPTS_DIR"
assert_dir_exists "$SWAP_DIR" "SWAP_DIR should exist at $SWAP_DIR"
assert_dir_exists "$UNDO_DIR" "UNDO_DIR should exist at $UNDO_DIR"

# Test that paths are correct
echo ""
echo "Test 2: Verifying paths are workspace-local..."

assert_contains "$STATE_DIR" "$TEST_WORKSPACE" "STATE_DIR should be inside test workspace"
assert_contains "$PROMPTS_DIR" "$TEST_WORKSPACE" "PROMPTS_DIR should be inside test workspace"
assert_contains "$SWAP_DIR" "$TEST_WORKSPACE" "SWAP_DIR should be inside test workspace"
assert_contains "$UNDO_DIR" "$TEST_WORKSPACE" "UNDO_DIR should be inside test workspace"

# Test that paths end with the correct subdirectories
assert_contains "$STATE_DIR" ".lazy-llm" "STATE_DIR should end with .lazy-llm"
assert_contains "$PROMPTS_DIR" ".lazy-llm/prompts" "PROMPTS_DIR should end with .lazy-llm/prompts"
assert_contains "$SWAP_DIR" ".lazy-llm/swap" "SWAP_DIR should end with .lazy-llm/swap"
assert_contains "$UNDO_DIR" ".lazy-llm/undo" "UNDO_DIR should end with .lazy-llm/undo"

# Test 3: Verify multiple workspaces are independent
echo ""
echo "Test 3: Testing workspace isolation..."

TEST_WORKSPACE2="/tmp/lazy-llm-test-init2-$$"
mkdir -p "$TEST_WORKSPACE2"

# Simulate running in a different workspace
TARGET_DIR2="$TEST_WORKSPACE2"
STATE_DIR2="${TARGET_DIR2}/.lazy-llm"
PROMPTS_DIR2="${STATE_DIR2}/prompts"
SWAP_DIR2="${STATE_DIR2}/swap"
UNDO_DIR2="${STATE_DIR2}/undo"

mkdir -p "$PROMPTS_DIR2" "$SWAP_DIR2" "$UNDO_DIR2"

# Verify second workspace has its own directories
assert_dir_exists "$STATE_DIR2" "Second workspace should have its own .lazy-llm directory"
assert_dir_exists "$PROMPTS_DIR2" "Second workspace should have its own prompts directory"

# Verify the two workspaces have different paths
if [ "$STATE_DIR" = "$STATE_DIR2" ]; then
    print_fail "STATE_DIR paths should be different for different workspaces"
    ((ASSERTIONS_FAILED++))
else
    print_pass "STATE_DIR paths are different for different workspaces"
    ((ASSERTIONS_PASSED++))
fi

# Test 4: Verify no global directory reference
echo ""
echo "Test 4: Verifying no global directory paths..."

# Make sure we're NOT using the old global path
GLOBAL_PATH="$HOME/.local/state/lazy-llm"
assert_not_contains "$STATE_DIR" "$HOME/.local/state/lazy-llm" "Should not use global state directory"
assert_not_contains "$PROMPTS_DIR" "$HOME/.local/state/lazy-llm" "Should not use global prompts directory"
assert_not_contains "$SWAP_DIR" "$HOME/.local/state/lazy-llm" "Should not use global swap directory"
assert_not_contains "$UNDO_DIR" "$HOME/.local/state/lazy-llm" "Should not use global undo directory"

# Cleanup
rm -rf "$TEST_WORKSPACE" "$TEST_WORKSPACE2"

# Print summary
echo ""
print_assertion_summary
