#!/usr/bin/env bash
# Main test orchestrator for lazy-llm unit tests

set -e  # Exit on error (but we'll handle test failures gracefully)

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIOS_DIR="$TESTS_DIR/scenarios"
LIB_DIR="$TESTS_DIR/lib"

# lazy-llm saves a manifest of every workspace it launches (llm-persist). A
# test's throwaway workspaces must never land in the user's real one, where
# they'd show up as restorable once the test's tmux server is gone.
OWN_STATE_DIR=""
if [ -z "${LAZY_LLM_STATE_DIR:-}" ]; then
    LAZY_LLM_STATE_DIR=$(mktemp -d /tmp/lazy-llm-test-state-XXXXXX)
    OWN_STATE_DIR=$LAZY_LLM_STATE_DIR
    export LAZY_LLM_STATE_DIR
fi

# A private tmux server for the whole run. Tests create and kill sessions,
# which must never happen on the user's own server (run from inside tmux,
# they used to land next to the user's workspaces). Short /tmp path: tmux
# socket paths are limited to ~108 bytes.
TEST_TMUX_TMPDIR=$(mktemp -d /tmp/lazy-llm-test-tmux-XXXXXX)
export TMUX_TMPDIR="$TEST_TMUX_TMPDIR"
unset TMUX TMUX_PANE
# Keep that server up for the whole run, and give detached test sessions a
# roomy size: at tmux's default 80x24 the prompt pane is ~5 rows, too short
# to see what a test puts in it (e.g. a pulled multi-line response).
tmux new-session -d -s _test-runner
tmux set-option -g default-size 220x80
# Where tests' throwaway workspace dirs go; removed with the run.
LAZY_LLM_TEST_WORKROOT=$(mktemp -d /tmp/lazy-llm-test-work-XXXXXX)
export LAZY_LLM_TEST_WORKROOT
# State that tools keep under XDG_STATE_HOME (e.g. llm-wt's opt-in hook log)
# goes to the run's own dir, never the user's.
export XDG_STATE_HOME="$LAZY_LLM_TEST_WORKROOT/xdg-state"
mkdir -p "$XDG_STATE_HOME"

# Scenarios check for this (tests/lib/assertions.sh) and refuse to run
# without it: only a run isolated as above is safe for them.
export LAZY_LLM_TEST_RUNNER=$$

# Source helper libraries
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/tmux-helpers.sh"
source "$LIB_DIR/setup-teardown.sh"

# Every process under pid $1.
descendants() {
    local child
    for child in $(pgrep -P "$1"); do
        echo "$child"
        descendants "$child"
    done
}

# Kill our processes whose cwd is under $1, older than $2 seconds, that have
# been reparented to init or the user's service manager: whatever started
# them is gone. An nvim server blocked on a prompt when its pane dies is one
# (it would never exit, and grows for days). The age floor spares another
# run's processes that were started detached on purpose (`( ... &)`).
reap_orphans_in() {
    local prefix=$1 min_age=$2 pid cwd ppid age
    for pid in $(pgrep -u "$(id -u)"); do
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null) || continue
        [[ $cwd == "$prefix"* ]] || continue
        read -r ppid age <<<"$(ps -o ppid=,etimes= -p "$pid")" || continue
        [ "${age:-0}" -ge "$min_age" ] || continue
        [ "$ppid" = 1 ] || [ "$(ps -o comm= -p "$ppid")" = systemd ] || continue
        # It may have exited since pgrep listed it; that's fine, and under
        # set -e a failed kill would abort the run (or the EXIT trap).
        kill -9 "$pid" 2>/dev/null || true
    done
    return 0
}

# Leftovers of runs that were killed before their cleanup could run.
reap_orphans_in /tmp/lazy-llm-test- 600

# The EXIT trap: it runs under set -e too, and a command failing in it ends
# the script with that command's status in place of main's exit code. Hence
# no `[ ... ] && cmd` here (a failing cmd counts) and `|| true` on anything
# that may fail harmlessly.
cleanup_run() {
    if [ -n "${DEBUG:-}" ]; then
        echo "Test tmux server kept (DEBUG): TMUX_TMPDIR=$TEST_TMUX_TMPDIR tmux attach"
    else
        local server_pid="" tree=""
        server_pid=$(tmux display -p '#{pid}' 2>/dev/null) || true
        if [ -n "$server_pid" ]; then
            tree=$(descendants "$server_pid") || true
        fi
        tmux kill-server 2>/dev/null || true
        # The killed nvims write their session snapshot on the way out (and
        # mkdir -p would recreate the dirs): let them finish first.
        sleep 1
        # Anything still up by now isn't exiting on its own. Usually all of
        # them have exited, and kill fails on the missing pids.
        if [ -n "$tree" ]; then
            kill -9 $tree 2>/dev/null || true
        fi
        reap_orphans_in "$LAZY_LLM_TEST_WORKROOT" 0
        rm -rf "$TEST_TMUX_TMPDIR" "$LAZY_LLM_TEST_WORKROOT"
    fi
    if [ -n "$OWN_STATE_DIR" ]; then
        rm -rf "$OWN_STATE_DIR"
    fi
    return 0
}
trap cleanup_run EXIT

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
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo ""
        print_fail "TEST FAILED: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
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
Usage: $0 [OPTIONS] [TEST_PATTERN...]

Run lazy-llm unit tests

OPTIONS:
  -h, --help          Show this help message
  -d, --debug         Enable debug mode (keep sessions, verbose output)
  -c, --cleanup       Cleanup all test artifacts and exit
  -v, --verify        Verify test environment and exit
  -l, --list          List all available tests
  -m MODE             Set MOCK_AI_MODE (echo, multiline, truncate, etc.)

ARGUMENTS:
  TEST_PATTERN...     Optional patterns to match test files (e.g., "send" or "01-*");
                      several run the union, each test once
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
TEST_PATTERNS=()

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
            TEST_PATTERNS+=("$1")
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

    if [ ${#TEST_PATTERNS[@]} -eq 0 ]; then
        # Run all tests
        if [ -d "$SCENARIOS_DIR" ]; then
            for test in "$SCENARIOS_DIR"/*.sh; do
                if [ -f "$test" ]; then
                    tests_to_run+=("$test")
                fi
            done
        fi
    else
        # Each pattern: an exact name first, else a substring match. A test
        # matched by several patterns runs once.
        local TEST_PATTERN t dup
        for TEST_PATTERN in "${TEST_PATTERNS[@]}"; do
            local matched=()
            if [ -f "$SCENARIOS_DIR/$TEST_PATTERN" ]; then
                matched=("$SCENARIOS_DIR/$TEST_PATTERN")
            elif [ -f "$SCENARIOS_DIR/${TEST_PATTERN}.sh" ]; then
                matched=("$SCENARIOS_DIR/${TEST_PATTERN}.sh")
            else
                for test in "$SCENARIOS_DIR"/*${TEST_PATTERN}*.sh; do
                    if [ -f "$test" ]; then
                        matched+=("$test")
                    fi
                done
            fi
            if [ ${#matched[@]} -eq 0 ]; then
                echo "No tests found matching: $TEST_PATTERN"
                echo ""
                list_tests
                exit 1
            fi
            for test in ${matched[@]+"${matched[@]}"}; do
                dup=false
                for t in ${tests_to_run[@]+"${tests_to_run[@]}"}; do
                    if [ "$t" = "$test" ]; then dup=true; fi
                done
                if ! $dup; then tests_to_run+=("$test"); fi
            done
        done
    fi

    # Check if we found any tests
    if [ ${#tests_to_run[@]} -eq 0 ]; then
        echo "No tests found matching: ${TEST_PATTERNS[*]}"
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
