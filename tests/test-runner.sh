#!/usr/bin/env bash
# Main test orchestrator for lazy-llm unit tests

set -e  # Exit on error (but we'll handle test failures gracefully)

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIOS_DIR="$TESTS_DIR/scenarios"
LIB_DIR="$TESTS_DIR/lib"

# Source helper libraries
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/tmux-helpers.sh"
source "$LIB_DIR/setup-teardown.sh"

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

# Run a single test
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .sh)

    print_banner "Running: $test_name"

    # Setup test environment
    setup_test_env "$test_name"

    # Run test and capture result
    local test_result=0
    if bash "$test_file"; then
        test_result=0
    else
        test_result=$?
    fi

    # Print assertion summary if available
    if [ -n "$ASSERTIONS_PASSED" ] || [ -n "$ASSERTIONS_FAILED" ]; then
        print_assertion_summary
    fi

    # Handle test result
    if [ $test_result -eq 0 ]; then
        echo ""
        print_pass "TEST PASSED: $test_name"
        ((TESTS_PASSED++))
    else
        echo ""
        print_fail "TEST FAILED: $test_name"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")

        # Save artifacts on failure
        if [ -z "$DEBUG" ]; then
            save_test_artifacts "$test_name"
        fi
    fi

    # Cleanup
    teardown_test_env
    echo ""

    return $test_result
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [TEST_PATTERN]

Run lazy-llm unit tests

OPTIONS:
  -h, --help          Show this help message
  -d, --debug         Enable debug mode (keep sessions, verbose output)
  -c, --cleanup       Cleanup all test artifacts and exit
  -v, --verify        Verify test environment and exit
  -l, --list          List all available tests
  -m MODE             Set MOCK_AI_MODE (echo, multiline, truncate, etc.)

ARGUMENTS:
  TEST_PATTERN        Optional pattern to match test files (e.g., "send" or "01-*")
                      If not specified, runs all tests

EXAMPLES:
  $0                          # Run all tests
  $0 01-simple-send.sh        # Run specific test
  $0 send                     # Run all tests matching "send"
  $0 -d 02-multiline          # Run with debug mode
  $0 -m truncate              # Run with truncate mode

MOCK_AI_MODES:
  echo        - Simple echo mode
  multiline   - Generate mock responses (default)
  truncate    - Simulate Gemini repetition bug
  delay       - Slow responses
  interactive - Simulate user prompts (1/2/3)
  markers     - Test marker line breaking

EOF
}

# List available tests
list_tests() {
    echo "Available tests:"
    echo ""
    if [ -d "$SCENARIOS_DIR" ]; then
        for test in "$SCENARIOS_DIR"/*.sh; do
            if [ -f "$test" ]; then
                local test_name=$(basename "$test" .sh)
                local description=$(grep -m 1 "^# Test:" "$test" | sed 's/^# Test: //')
                if [ -n "$description" ]; then
                    echo "  $test_name - $description"
                else
                    echo "  $test_name"
                fi
            fi
        done
    else
        echo "  No tests found in $SCENARIOS_DIR"
    fi
    echo ""
}

# Parse command line options
DEBUG=""
MOCK_AI_MODE=""
TEST_PATTERN=""

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
        -c|--cleanup)
            cleanup_all_test_artifacts
            exit 0
            ;;
        -v|--verify)
            verify_test_environment
            exit $?
            ;;
        -l|--list)
            list_tests
            exit 0
            ;;
        -m)
            MOCK_AI_MODE="$2"
            export MOCK_AI_MODE="$2"
            shift 2
            ;;
        *)
            TEST_PATTERN="$1"
            shift
            ;;
    esac
done

# Main test execution
main() {
    print_banner "lazy-llm Unit Test Runner"

    # Verify environment
    if ! verify_test_environment; then
        echo "Please fix the issues above and try again."
        exit 1
    fi

    echo ""

    # Find tests to run
    local tests_to_run=()

    if [ -z "$TEST_PATTERN" ]; then
        # Run all tests
        if [ -d "$SCENARIOS_DIR" ]; then
            for test in "$SCENARIOS_DIR"/*.sh; do
                if [ -f "$test" ]; then
                    tests_to_run+=("$test")
                fi
            done
        fi
    else
        # Run tests matching pattern
        # First try exact match
        if [ -f "$SCENARIOS_DIR/$TEST_PATTERN" ]; then
            tests_to_run+=("$SCENARIOS_DIR/$TEST_PATTERN")
        elif [ -f "$SCENARIOS_DIR/${TEST_PATTERN}.sh" ]; then
            tests_to_run+=("$SCENARIOS_DIR/${TEST_PATTERN}.sh")
        else
            # Try pattern matching
            for test in "$SCENARIOS_DIR"/*${TEST_PATTERN}*.sh; do
                if [ -f "$test" ]; then
                    tests_to_run+=("$test")
                fi
            done
        fi
    fi

    # Check if we found any tests
    if [ ${#tests_to_run[@]} -eq 0 ]; then
        echo "No tests found matching pattern: $TEST_PATTERN"
        echo ""
        list_tests
        exit 1
    fi

    echo "Running ${#tests_to_run[@]} test(s)..."
    echo ""

    # Run each test
    for test in "${tests_to_run[@]}"; do
        # Don't exit on test failure, just track it
        run_test "$test" || true
    done

    # Print final summary
    print_banner "Test Summary"

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
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main
