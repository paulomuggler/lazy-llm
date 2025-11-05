# Automated Testing Infrastructure for lazy-llm

**Priority:** High
**Complexity:** Medium
**Impact:** Critical - Enables rapid iteration and prevents regressions

---

## Problem Statement

Currently, testing lazy-llm requires manual interaction with AI TUI tools and human observation of behavior. This creates severe bottlenecks:

1. **Slow iteration cycles** - Each change requires manual testing across multiple AI tools
2. **Poor reproducibility** - Difficult to verify specific edge cases or regressions
3. **Limited parallelization** - Only one person can test at a time
4. **Autosubmit reliability issues** - Inconsistent behavior across Claude, Gemini, Codex without systematic testing
5. **Response parsing bugs** - Marker placement and line breaking issues discovered only through manual use

We need automated testing infrastructure that can:
- Verify core text piping mechanisms without AI tools
- Test integration with real AI tools programmatically
- Run in CI/CD pipelines
- Be easily executed by contributors

---

## Architecture Overview

### Two-Tier Testing Strategy

```
┌─────────────────────────────────────────────────┐
│            Integration Tests (Tier 2)           │
│   Real AI tools (claude, gemini-cli, codex)     │
│   Requires API keys, tests actual behavior      │
└─────────────────────────────────────────────────┘
                      ▲
                      │
┌─────────────────────────────────────────────────┐
│              Unit Tests (Tier 1)                │
│   Mock AI tool, tests piping infrastructure     │
│   No API keys, fast, deterministic              │
└─────────────────────────────────────────────────┘
```

---

## Tier 1: Unit Testing with Mock AI Tool

### Concept

Create a deterministic mock AI TUI that simulates receiving input and producing responses, allowing us to test the core infrastructure without real API calls.

### Directory Structure

```
tests/
├── README.md                    # How to run tests, contribution guide
├── mock-ai-tool                 # Executable mock AI TUI script
├── test-runner.sh               # Main test orchestrator
├── lib/
│   ├── assertions.sh            # Test assertion helpers
│   ├── tmux-helpers.sh          # Tmux session management
│   └── setup-teardown.sh        # Test environment lifecycle
├── scenarios/
│   ├── 01-simple-send.sh        # Single line prompt
│   ├── 02-multiline-send.sh     # Multi-paragraph prompt
│   ├── 03-large-paste.sh        # >1KB prompt (tests delays)
│   ├── 04-visual-selection.sh   # Visual mode send
│   ├── 05-response-pull.sh      # Extract AI response
│   ├── 06-marker-placement.sh   # Verify BEGIN/END markers
│   ├── 07-line-breaking.sh      # Newline handling around markers
│   ├── 08-filtered-send.sh      # Send only untagged lines
│   ├── 09-keypress-forward.sh   # llmk keypress forwarding
│   └── 10-context-append.sh     # llmr/llmR context insertion
├── fixtures/
│   ├── simple-prompt.txt
│   ├── multiline-prompt.txt
│   ├── large-prompt.txt
│   └── mock-responses/
│       ├── claude-style.txt
│       ├── gemini-style.txt
│       └── codex-style.txt
└── expected/
    ├── 01-simple-send.out
    ├── 02-multiline-send.out
    └── ...
```

### Mock AI Tool Specification

**File:** `tests/mock-ai-tool`

Bash script that simulates AI TUI behavior:

```bash
#!/usr/bin/env bash
# Mock AI TUI for testing lazy-llm infrastructure

LOG_FILE="${MOCK_AI_LOG:-/tmp/mock-ai-tool.log}"
MODE="${MOCK_AI_MODE:-echo}" # echo, delay, multiline, truncate

# Log everything received for debugging
log_input() {
    echo "[$(date +%T.%N)] INPUT: $1" >> "$LOG_FILE"
}

# Simulate different AI tool behaviors
case "$MODE" in
    echo)
        # Simple echo mode - just repeat back what was sent
        while IFS= read -r line; do
            log_input "$line"
            echo "$line"
        done
        ;;
    delay)
        # Simulate slow response
        while IFS= read -r line; do
            log_input "$line"
            sleep 0.1
            echo "$line"
        done
        ;;
    multiline)
        # Simulate response with markers
        while IFS= read -r line; do
            log_input "$line"
            if [[ "$line" == "### END PROMPT" ]]; then
                echo "$line"
                echo ""
                echo "Sure, I'll help with that!"
                echo ""
                echo "Here's my response with multiple lines."
                echo "This should be extractable via llm-pull."
            else
                echo "$line"
            fi
        done
        ;;
    truncate)
        # Simulate Gemini-style truncation bug (repeats prompt)
        buffer=""
        while IFS= read -r line; do
            log_input "$line"
            buffer+="$line"$'\n'
            # Simulate truncated repetition
            if [[ "$line" == "### END PROMPT" ]]; then
                for i in {1..3}; do
                    echo "$buffer"
                done
            fi
        done
        ;;
esac
```

**Usage:**
```bash
MOCK_AI_MODE=echo tests/mock-ai-tool
MOCK_AI_MODE=multiline tests/mock-ai-tool
MOCK_AI_LOG=/tmp/debug.log tests/mock-ai-tool
```

### Test Runner

**File:** `tests/test-runner.sh`

```bash
#!/usr/bin/env bash
# Main test orchestrator

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIOS_DIR="$TESTS_DIR/scenarios"

# Source helpers
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

PASSED=0
FAILED=0
SKIPPED=0

run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .sh)

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: $test_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Setup test environment
    setup_test_env

    # Run test
    if bash "$test_file"; then
        echo "✓ PASSED: $test_name"
        ((PASSED++))
    else
        echo "✗ FAILED: $test_name"
        ((FAILED++))
    fi

    # Cleanup
    teardown_test_env
    echo ""
}

# Run all scenarios or specific test
if [ $# -eq 0 ]; then
    for test in "$SCENARIOS_DIR"/*.sh; do
        run_test "$test"
    done
else
    run_test "$SCENARIOS_DIR/$1"
fi

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Passed:  $PASSED"
echo "Failed:  $FAILED"
echo "Skipped: $SKIPPED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ $FAILED -eq 0 ] && exit 0 || exit 1
```

### Example Test Scenario

**File:** `tests/scenarios/02-multiline-send.sh`

```bash
#!/usr/bin/env bash
# Test: Multiline prompt send with markers

source "$(dirname "$0")/../lib/assertions.sh"
source "$(dirname "$0")/../lib/tmux-helpers.sh"

TEST_NAME="multiline-send"
FIXTURE="$TESTS_DIR/fixtures/multiline-prompt.txt"
EXPECTED="$TESTS_DIR/expected/02-multiline-send.out"

# Start lazy-llm with mock AI tool
start_lazy_llm_session "$TEST_NAME" "mock-ai-tool"

# Wait for session initialization
sleep 1

# Send multiline prompt
send_to_prompt_buffer "$FIXTURE"

# Trigger send with <leader>llms
tmux_send_keys_to_nvim "\\llms"

# Wait for processing
sleep 1

# Capture AI pane output
AI_PANE_OUTPUT=$(capture_pane "$AI_PANE")

# Assertions
assert_contains "$AI_PANE_OUTPUT" "### PROMPT"
assert_contains "$AI_PANE_OUTPUT" "### END PROMPT"
assert_line_count "$AI_PANE_OUTPUT" ">10" "Should have multiple lines"

# Verify markers are on separate lines
assert_pattern "$AI_PANE_OUTPUT" $'\n### PROMPT [0-9-: ]+\n'
assert_pattern "$AI_PANE_OUTPUT" $'\n### END PROMPT\n'

# Compare with expected output (optional, for strict verification)
if [ -f "$EXPECTED" ]; then
    assert_equals "$AI_PANE_OUTPUT" "$(cat "$EXPECTED")"
fi
```

### Helper Libraries

**File:** `tests/lib/assertions.sh`

```bash
#!/usr/bin/env bash
# Assertion helpers for tests

assert_equals() {
    local actual=$1
    local expected=$2
    local message=${3:-"Values should be equal"}

    if [ "$actual" != "$expected" ]; then
        echo "ASSERTION FAILED: $message"
        echo "Expected: $expected"
        echo "Actual:   $actual"
        return 1
    fi
    return 0
}

assert_contains() {
    local haystack=$1
    local needle=$2
    local message=${3:-"Should contain '$needle'"}

    if [[ ! "$haystack" =~ $needle ]]; then
        echo "ASSERTION FAILED: $message"
        echo "Content: $haystack"
        return 1
    fi
    return 0
}

assert_not_contains() {
    local haystack=$1
    local needle=$2
    local message=${3:-"Should not contain '$needle'"}

    if [[ "$haystack" =~ $needle ]]; then
        echo "ASSERTION FAILED: $message"
        return 1
    fi
    return 0
}

assert_line_count() {
    local text=$1
    local operator=$2  # =, >, <, >=, <=
    local count=$3
    local message=${4:-"Line count mismatch"}

    local actual_count=$(echo "$text" | wc -l)

    case "$operator" in
        "=")  [ "$actual_count" -eq "$count" ] || { echo "FAILED: $message (expected $count, got $actual_count)"; return 1; } ;;
        ">")  [ "$actual_count" -gt "$count" ] || { echo "FAILED: $message (expected >$count, got $actual_count)"; return 1; } ;;
        "<")  [ "$actual_count" -lt "$count" ] || { echo "FAILED: $message (expected <$count, got $actual_count)"; return 1; } ;;
        ">=") [ "$actual_count" -ge "$count" ] || { echo "FAILED: $message (expected >=$count, got $actual_count)"; return 1; } ;;
        "<=") [ "$actual_count" -le "$count" ] || { echo "FAILED: $message (expected <=$count, got $actual_count)"; return 1; } ;;
    esac
    return 0
}

assert_pattern() {
    local text=$1
    local pattern=$2
    local message=${3:-"Should match pattern"}

    if [[ ! "$text" =~ $pattern ]]; then
        echo "ASSERTION FAILED: $message"
        echo "Pattern: $pattern"
        echo "Text: $text"
        return 1
    fi
    return 0
}

assert_file_exists() {
    local filepath=$1
    local message=${2:-"File should exist: $filepath"}

    if [ ! -f "$filepath" ]; then
        echo "ASSERTION FAILED: $message"
        return 1
    fi
    return 0
}
```

**File:** `tests/lib/tmux-helpers.sh`

```bash
#!/usr/bin/env bash
# Tmux session management for tests

start_lazy_llm_session() {
    local session_name=$1
    local ai_tool=${2:-"mock-ai-tool"}

    export MOCK_AI_MODE=${MOCK_AI_MODE:-multiline}
    export MOCK_AI_LOG="/tmp/test-${session_name}-mock-ai.log"

    # Start lazy-llm with test session
    lazy-llm -s "test-${session_name}" -t "$ai_tool" -d "$PWD"

    # Store pane IDs
    export TEST_SESSION="test-${session_name}"
    export AI_PANE=$(tmux display-message -p -t "${TEST_SESSION}:0.0" '#{pane_id}')
    export EDITOR_PANE=$(tmux display-message -p -t "${TEST_SESSION}:0.1" '#{pane_id}')
    export PROMPT_PANE=$(tmux display-message -p -t "${TEST_SESSION}:0.2" '#{pane_id}')
}

capture_pane() {
    local pane_id=$1
    local history=${2:-2000}

    tmux capture-pane -p -t "$pane_id" -S -"$history"
}

send_to_prompt_buffer() {
    local content_file=$1

    # Load content into prompt buffer
    tmux send-keys -t "$PROMPT_PANE" \
        ":r $content_file" Enter \
        "ggdd"  # Delete first empty line
}

tmux_send_keys_to_nvim() {
    local keys=$1

    tmux send-keys -t "$EDITOR_PANE" "$keys"
}

kill_test_session() {
    if [ -n "$TEST_SESSION" ]; then
        tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
    fi
}
```

---

## Tier 2: Integration Testing with Real AI Tools

### Concept

Test lazy-llm with actual AI TUI tools (Claude Code, gemini-cli, codex) to verify autosubmit behavior, response parsing, and tool-specific quirks.

### Prerequisites

1. AI tools installed globally:
   ```bash
   npm install -g claude-code
   npm install -g @gemini-cli/gemini-cli
   # codex TBD
   ```

2. Credentials configuration:
   ```bash
   tests/integration/.env.example  # Template
   tests/integration/.env          # User's actual keys (gitignored)
   ```

### Credential Management

**File:** `tests/integration/.env.example`

```bash
# API Keys for Integration Tests
# Copy to .env and fill in your credentials

# Claude Code (required for claude integration tests)
ANTHROPIC_API_KEY=sk-ant-...

# Gemini CLI (required for gemini integration tests)
GEMINI_API_KEY=...

# Codex (required for codex integration tests)
GROK_API_KEY=...

# Test configuration
INTEGRATION_TEST_TIMEOUT=30  # seconds
INTEGRATION_TEST_CLEANUP=true  # cleanup sessions after tests
```

**File:** `tests/integration/.gitignore`

```
.env
*.log
test-sessions/
```

### Integration Test Structure

```
tests/integration/
├── .env.example
├── .env                      # gitignored
├── .gitignore
├── README.md
├── runner.sh                 # Integration test orchestrator
├── lib/
│   ├── ai-tool-helpers.sh   # Tool-specific setup
│   └── integration-assertions.sh
├── scenarios/
│   ├── claude/
│   │   ├── 01-autosubmit.sh
│   │   ├── 02-response-markers.sh
│   │   └── 03-multiline-reliability.sh
│   ├── gemini/
│   │   ├── 01-autosubmit.sh
│   │   ├── 02-truncation-bug.sh     # Known issue
│   │   └── 03-marker-linebreaks.sh  # Known issue
│   └── codex/
│       └── 01-autosubmit.sh
└── prompts/
    ├── simple-question.txt          # "What is 2+2?"
    ├── code-request.txt             # "Write hello world in Python"
    └── multiline-task.txt           # Multi-paragraph prompt
```

### Integration Test Example

**File:** `tests/integration/scenarios/claude/01-autosubmit.sh`

```bash
#!/usr/bin/env bash
# Integration Test: Claude Code autosubmit reliability

source "$(dirname "$0")/../../lib/ai-tool-helpers.sh"
source "$(dirname "$0")/../../lib/integration-assertions.sh"

# Load credentials
load_dotenv

# Verify Claude is available
require_tool "claude" "$ANTHROPIC_API_KEY"

TEST_NAME="claude-autosubmit"

# Start lazy-llm with real Claude
start_lazy_llm_session "$TEST_NAME" "claude"
sleep 2  # Wait for Claude to initialize

# Send simple prompt
PROMPT="What is 2+2? Answer with just the number."
send_prompt "$PROMPT"

# Wait for response (with timeout)
wait_for_response 30

# Capture Claude's response
RESPONSE=$(capture_pane "$AI_PANE")

# Assertions
assert_contains "$RESPONSE" "4" "Should receive answer"
assert_contains "$RESPONSE" "### PROMPT" "Should have prompt marker"
assert_contains "$RESPONSE" "### END PROMPT" "Should have end marker"

# Check if autosubmit worked (response should appear after marker)
RESPONSE_AFTER_MARKER=$(echo "$RESPONSE" | sed -n '/### END PROMPT/,$p')
assert_contains "$RESPONSE_AFTER_MARKER" "4" "Response should appear after END PROMPT marker"

# Log success
echo "✓ Claude autosubmit working correctly"
```

**File:** `tests/integration/scenarios/gemini/02-truncation-bug.sh`

```bash
#!/usr/bin/env bash
# Integration Test: Gemini truncation/repetition bug

source "$(dirname "$0")/../../lib/ai-tool-helpers.sh"
source "$(dirname "$0")/../../lib/integration-assertions.sh"

load_dotenv
require_tool "gemini-cli" "$GEMINI_API_KEY"

TEST_NAME="gemini-truncation"

start_lazy_llm_session "$TEST_NAME" "gemini-cli"
sleep 2

# Send multi-paragraph prompt (this triggers the bug)
PROMPT=$(cat "$TESTS_DIR/integration/prompts/multiline-task.txt")
send_prompt "$PROMPT"

wait_for_response 30

RESPONSE=$(capture_pane "$AI_PANE")

# Count how many times the prompt appears (Gemini bug: repeats 6-8 times)
PROMPT_COUNT=$(echo "$RESPONSE" | grep -c "### PROMPT")

if [ "$PROMPT_COUNT" -gt 1 ]; then
    echo "⚠ BUG CONFIRMED: Gemini repeated prompt ${PROMPT_COUNT} times"
    echo "This is a known issue. Response unusable."

    # This test is expected to fail until fixed
    exit 1
else
    echo "✓ Gemini truncation bug appears to be fixed!"
    exit 0
fi
```

### Integration Test Runner

**File:** `tests/integration/runner.sh`

```bash
#!/usr/bin/env bash
# Integration test runner with credential checking

INTEGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for .env file
if [ ! -f "$INTEGRATION_DIR/.env" ]; then
    echo "ERROR: Missing .env file"
    echo "Copy .env.example to .env and add your API keys:"
    echo "  cp tests/integration/.env.example tests/integration/.env"
    exit 1
fi

# Load credentials
source "$INTEGRATION_DIR/.env"

# Select which tools to test
TOOLS="${1:-all}"  # claude, gemini, codex, or all

run_tool_tests() {
    local tool=$1
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Testing: $tool"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for test in "$INTEGRATION_DIR/scenarios/$tool"/*.sh; do
        echo "Running: $(basename "$test")"
        if bash "$test"; then
            echo "✓ PASSED"
        else
            echo "✗ FAILED"
        fi
        echo ""
    done
}

if [ "$TOOLS" = "all" ]; then
    for tool in claude gemini codex; do
        if [ -d "$INTEGRATION_DIR/scenarios/$tool" ]; then
            run_tool_tests "$tool"
        fi
    done
else
    run_tool_tests "$TOOLS"
fi
```

---

## CI/CD Integration

### GitHub Actions Workflow

**File:** `.github/workflows/test.yml`

```yaml
name: Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  unit-tests:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3

    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y tmux stow

    - name: Install lazy-llm
      run: |
        ./install.sh

    - name: Run unit tests
      run: |
        cd tests
        ./test-runner.sh

  integration-tests:
    runs-on: ubuntu-latest
    # Only run on main branch (to protect API keys)
    if: github.ref == 'refs/heads/main'

    steps:
    - uses: actions/checkout@v3

    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y tmux stow nodejs npm

    - name: Install AI tools
      run: |
        npm install -g claude-code
        npm install -g @gemini-cli/gemini-cli

    - name: Install lazy-llm
      run: ./install.sh

    - name: Run integration tests
      env:
        ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
      run: |
        cd tests/integration
        echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" > .env
        echo "GEMINI_API_KEY=$GEMINI_API_KEY" >> .env
        ./runner.sh
```

---

## Usage

### Running Unit Tests

```bash
# Run all unit tests
cd tests
./test-runner.sh

# Run specific test
./test-runner.sh 02-multiline-send.sh

# Debug mode (verbose output)
DEBUG=1 ./test-runner.sh

# With custom mock AI behavior
MOCK_AI_MODE=truncate ./test-runner.sh
```

### Running Integration Tests

```bash
# Setup credentials (first time only)
cp tests/integration/.env.example tests/integration/.env
# Edit .env with your API keys

# Run all integration tests
cd tests/integration
./runner.sh

# Test specific tool
./runner.sh claude
./runner.sh gemini

# Debug mode with logs
DEBUG=1 INTEGRATION_KEEP_SESSIONS=true ./runner.sh claude
```

---

## Benefits

1. **Fast iteration** - Unit tests run in seconds, no API calls needed
2. **Reproducibility** - Same tests can be run by anyone, anywhere
3. **Regression prevention** - Catch bugs before they reach users
4. **Tool-specific debugging** - Isolate and document AI tool quirks
5. **Contributor-friendly** - Clear test structure for PRs
6. **CI/CD ready** - Automated testing on every commit

---

## Implementation Plan

### Phase 1: Mock Testing Infrastructure (Week 1)
- [ ] Create `tests/` directory structure
- [ ] Implement mock-ai-tool with different modes
- [ ] Write test-runner.sh with helpers
- [ ] Create 5-10 core unit test scenarios
- [ ] Add fixtures and expected outputs
- [ ] Document test writing guide

### Phase 2: Integration Testing (Week 2)
- [ ] Create `tests/integration/` structure
- [ ] Implement credential management (.env)
- [ ] Write AI tool helpers for Claude, Gemini, Codex
- [ ] Create integration test scenarios (3-5 per tool)
- [ ] Test and document known bugs (Gemini truncation, etc.)
- [ ] Add integration runner script

### Phase 3: CI/CD & Documentation (Week 3)
- [ ] Setup GitHub Actions workflow
- [ ] Configure secrets for integration tests
- [ ] Write comprehensive tests/README.md
- [ ] Create CONTRIBUTING.md with test guidelines
- [ ] Add test coverage reporting
- [ ] Document troubleshooting common test failures

---

## Future Enhancements

- **Visual regression testing** - Screenshot comparison for TUI layouts
- **Performance benchmarking** - Measure latency of send/receive operations
- **Stress testing** - Large prompts (10KB+), rapid sends, concurrent sessions
- **Fuzzing** - Random input generation to catch edge cases
- **Coverage reporting** - Track which code paths are tested
- **Test fixtures generator** - Tool to record real interactions for test cases
