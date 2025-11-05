#!/usr/bin/env bash
# Integration test runner for lazy-llm with real AI tools

set -e

INTEGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "$INTEGRATION_DIR/.." && pwd)"

# Source libraries
source "$INTEGRATION_DIR/lib/ai-tool-helpers.sh"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

# Test tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
FAILED_TESTS=()

# Colors
BOLD='\033[1m'
NC='\033[0m'

# Print banner
print_banner() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BOLD}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Run a single integration test
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .sh)
    local tool=$(basename $(dirname "$test_file"))

    print_banner "Running: $tool/$test_name"

    # Setup test environment
    setup_test_env "$test_name"

    # Run test and capture result
    local test_result=0
    if bash "$test_file"; then
        test_result=0
    else
        test_result=$?
    fi

    # Handle test result
    if [ $test_result -eq 0 ]; then
        echo ""
        print_pass "TEST PASSED: $tool/$test_name"
        ((TESTS_PASSED++))
    else
        echo ""
        print_fail "TEST FAILED: $tool/$test_name"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$tool/$test_name")

        # Save artifacts on failure
        if [ "${INTEGRATION_TEST_KEEP_ON_FAILURE:-false}" = "true" ] || [ -n "$DEBUG" ]; then
            save_test_artifacts "$test_name"
        fi
    fi

    # Cleanup
    if [ "${INTEGRATION_TEST_CLEANUP:-true}" = "true" ] && [ -z "$DEBUG" ]; then
        teardown_test_env
    fi

    echo ""
    return $test_result
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [TOOL]

Run lazy-llm integration tests with real AI tools

OPTIONS:
  -h, --help          Show this help message
  -d, --debug         Enable debug mode (keep sessions, verbose output)
  -v, --verify        Verify environment and credentials
  -l, --list          List all available tests
  -k, --keep          Keep test sessions on failure

ARGUMENTS:
  TOOL                Which AI tool to test (claude, gemini, codex, or all)
                      Default: all enabled tools

EXAMPLES:
  $0                  # Run all enabled integration tests
  $0 claude           # Run only Claude tests
  $0 gemini           # Run only Gemini tests
  $0 -d claude        # Run Claude tests in debug mode
  $0 -k gemini        # Keep sessions on failure

REQUIREMENTS:
  - .env file with API keys (see .env.example)
  - lazy-llm installed (run install.sh from repo root)
  - AI CLI tools installed (claude, gemini-cli)
  - Neovim/LazyVim configured

CONFIGURATION:
  Edit tests/integration/.env to:
  - Set API keys (ANTHROPIC_API_KEY, GEMINI_API_KEY)
  - Configure timeout (INTEGRATION_TEST_TIMEOUT)
  - Enable/disable tools (TEST_CLAUDE, TEST_GEMINI)

EOF
}

# List available tests
list_tests() {
    echo "Available integration tests:"
    echo ""

    for tool in claude gemini codex; do
        local tool_dir="$INTEGRATION_DIR/scenarios/$tool"
        if [ -d "$tool_dir" ]; then
            local enabled=$(is_tool_enabled "$tool" && echo "✓" || echo "✗")
            echo "[$enabled] $tool:"

            for test in "$tool_dir"/*.sh; do
                if [ -f "$test" ]; then
                    local test_name=$(basename "$test" .sh)
                    local description=$(grep -m 1 "^# Integration Test:" "$test" | sed 's/^# Integration Test: //')
                    if [ -n "$description" ]; then
                        echo "      $test_name - $description"
                    else
                        echo "      $test_name"
                    fi
                fi
            done
            echo ""
        fi
    done

    echo "Legend: [✓] enabled  [✗] disabled (set in .env)"
}

# Verify environment
verify_environment() {
    echo "Verifying integration test environment..."
    echo ""

    # Check .env file
    if [ -f "$INTEGRATION_DIR/.env" ]; then
        print_pass ".env file exists"
        load_dotenv "$INTEGRATION_DIR/.env"
    else
        print_fail ".env file missing"
        echo "  Copy .env.example to .env and add your API keys"
        return 1
    fi

    # Check lazy-llm
    if command -v lazy-llm &> /dev/null; then
        print_pass "lazy-llm is installed"
    else
        print_fail "lazy-llm not found in PATH"
        echo "  Run install.sh from repository root"
        return 1
    fi

    # Check tmux
    if command -v tmux &> /dev/null; then
        print_pass "tmux is installed"
    else
        print_fail "tmux not found"
        return 1
    fi

    # Check nvim
    if command -v nvim &> /dev/null; then
        print_pass "nvim is installed"
    else
        print_fail "nvim not found"
        return 1
    fi

    # Check AI tools
    echo ""
    echo "AI Tools:"

    if [ "${TEST_CLAUDE:-true}" = "true" ]; then
        if command -v claude &> /dev/null; then
            print_pass "claude CLI is installed"
            if [ -n "$ANTHROPIC_API_KEY" ]; then
                print_pass "ANTHROPIC_API_KEY is set"
            else
                print_fail "ANTHROPIC_API_KEY not set in .env"
            fi
        else
            print_fail "claude not found (npm install -g @anthropic-ai/claude-code)"
        fi
    fi

    if [ "${TEST_GEMINI:-true}" = "true" ]; then
        if command -v gemini &> /dev/null; then
            print_pass "gemini CLI is installed"
            if [ -n "$GEMINI_API_KEY" ]; then
                print_pass "GEMINI_API_KEY is set"
            else
                print_fail "GEMINI_API_KEY not set in .env"
            fi
        else
            print_fail "gemini not found (npm install -g @google/gemini-cli)"
        fi
    fi

    echo ""
    echo "✓ Environment verification complete"
    return 0
}

# Parse command line options
DEBUG=""
TOOL_FILTER="all"
VERIFY_ONLY=false
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -d|--debug)
            DEBUG=1
            export DEBUG=1
            shift
            ;;
        -v|--verify)
            VERIFY_ONLY=true
            shift
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -k|--keep)
            export INTEGRATION_TEST_KEEP_ON_FAILURE=true
            shift
            ;;
        claude|gemini|codex|all)
            TOOL_FILTER="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_banner "lazy-llm Integration Test Runner"

    # Load .env
    if ! load_dotenv "$INTEGRATION_DIR/.env"; then
        echo "Please create .env file with your API keys"
        exit 1
    fi

    # Handle special modes
    if [ "$VERIFY_ONLY" = true ]; then
        verify_environment
        exit $?
    fi

    if [ "$LIST_ONLY" = true ]; then
        list_tests
        exit 0
    fi

    # Verify environment
    if ! verify_environment; then
        echo ""
        echo "Please fix the issues above before running tests"
        exit 1
    fi

    echo ""

    # Find tests to run
    local tests_to_run=()

    if [ "$TOOL_FILTER" = "all" ]; then
        # Run all enabled tools
        for tool in claude gemini codex; do
            if is_tool_enabled "$tool"; then
                local tool_dir="$INTEGRATION_DIR/scenarios/$tool"
                if [ -d "$tool_dir" ]; then
                    for test in "$tool_dir"/*.sh; do
                        [ -f "$test" ] && tests_to_run+=("$test")
                    done
                fi
            fi
        done
    else
        # Run specific tool
        if is_tool_enabled "$TOOL_FILTER"; then
            local tool_dir="$INTEGRATION_DIR/scenarios/$TOOL_FILTER"
            if [ -d "$tool_dir" ]; then
                for test in "$tool_dir"/*.sh; do
                    [ -f "$test" ] && tests_to_run+=("$test")
                done
            else
                echo "No tests found for tool: $TOOL_FILTER"
                exit 1
            fi
        else
            echo "Tool '$TOOL_FILTER' is disabled in .env (TEST_${TOOL_FILTER^^}=false)"
            exit 0
        fi
    fi

    # Check if we found any tests
    if [ ${#tests_to_run[@]} -eq 0 ]; then
        echo "No tests to run"
        exit 1
    fi

    echo "Running ${#tests_to_run[@]} integration test(s)..."
    echo ""

    # Run each test
    for test in "${tests_to_run[@]}"; do
        run_test "$test" || true
    done

    # Print final summary
    print_banner "Integration Test Summary"

    echo "Total tests run: $((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))"
    print_pass "Passed: $TESTS_PASSED"

    if [ $TESTS_FAILED -gt 0 ]; then
        print_fail "Failed: $TESTS_FAILED"
        echo ""
        echo "Failed tests:"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo "  - $failed_test"
        done
    else
        echo -e "${GREEN}Failed: 0${NC}"
    fi

    if [ $TESTS_SKIPPED -gt 0 ]; then
        print_info "Skipped: $TESTS_SKIPPED"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Exit with appropriate code
    [ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
}

# Run main function
main
