# lazy-llm Test Suite

Automated testing infrastructure for lazy-llm using mock AI tools and real tmux sessions.

## Overview

This test suite provides:
- **Unit tests** using a mock AI tool (no API keys required)
- **Deterministic testing** of text piping mechanisms
- **Fast feedback** for core infrastructure changes
- **Regression prevention** through automated assertions

## Quick Start

```bash
# From repository root
cd tests

# Run all tests
./test-runner.sh

# Run specific test
./test-runner.sh 01-simple-send.sh

# Run tests matching pattern
./test-runner.sh send

# Run with debug mode (keeps sessions alive)
./test-runner.sh -d 02-multiline-send.sh
```

## Prerequisites

1. **lazy-llm installed**: Run `./install.sh` from repository root
2. **Dependencies**: tmux, nvim (LazyVim), bash, stow
3. **PATH configured**: `~/.local/bin` must be in your PATH

To verify environment:
```bash
./test-runner.sh -v
```

## Test Architecture

### Components

```
tests/
├── mock-ai-tool              # Simulated AI TUI with multiple modes
├── test-runner.sh            # Main test orchestrator
├── lib/
│   ├── assertions.sh         # Test assertion helpers
│   ├── tmux-helpers.sh       # Tmux session management
│   └── setup-teardown.sh     # Test lifecycle management
├── scenarios/
│   ├── 01-simple-send.sh     # Single line prompt test
│   ├── 02-multiline-send.sh  # Multi-paragraph prompt test
│   ├── 03-large-paste.sh     # >1KB prompt (delay test)
│   ├── 04-marker-placement.sh # Marker formatting validation
│   ├── 05-response-pull.sh   # llm-pull functionality
│   ├── 06-visual-selection.sh # Visual mode send test
│   └── 07-keypress-forward.sh # llmk keypress forwarding
├── fixtures/
│   ├── simple-prompt.txt     # Test fixtures
│   ├── multiline-prompt.txt
│   ├── large-prompt.txt
│   └── mock-responses/       # Expected response formats
└── expected/                 # Expected test outputs (optional)
```

### Mock AI Tool

The mock AI tool simulates different AI TUI behaviors for testing:

#### Available Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `echo` | Simple echo back | Basic piping test |
| `multiline` | Generate mock responses | Response pull testing (default) |
| `truncate` | Repeat prompt 3x | Simulate Gemini bug |
| `delay` | Slow responses (0.2s/line) | Timeout handling |
| `interactive` | Prompt for 1/2/3 choice | Keypress forwarding |
| `markers` | Test marker formatting | Line breaking validation |

#### Usage

```bash
# Set mode via environment variable
MOCK_AI_MODE=truncate ./test-runner.sh

# Use in test scripts
export MOCK_AI_MODE="interactive"
start_lazy_llm_session "test-name"
```

#### Manual Testing

```bash
# Run mock AI tool directly
tests/mock-ai-tool

# With specific mode
MOCK_AI_MODE=multiline tests/mock-ai-tool

# View logs
MOCK_AI_LOG=/tmp/debug.log tests/mock-ai-tool
tail -f /tmp/debug.log
```

## Writing Tests

### Test Template

```bash
#!/usr/bin/env bash
# Test: Description of what this test validates

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

TEST_NAME="my-test"

# Optional: Set mock AI mode
export MOCK_AI_MODE="multiline"

# Start lazy-llm session
echo "Starting lazy-llm session..."
if ! start_lazy_llm_session "$TEST_NAME"; then
    echo "Failed to start session"
    exit 1
fi

sleep 2  # Wait for initialization

# Send prompt
PROMPT="Test prompt"
send_to_prompt_buffer_simple "$PROMPT"

# Trigger send
trigger_llm_send
sleep 1

# Capture output
AI_OUTPUT=$(capture_pane "$AI_PANE")

# Run assertions
echo ""
echo "Running assertions..."

assert_contains "$AI_OUTPUT" "expected text" "Description"
assert_not_contains "$AI_OUTPUT" "unexpected text" "Description"
assert_line_count "$AI_OUTPUT" ">" "10" "Should have >10 lines"

# Print summary
print_assertion_summary
```

### Available Assertions

```bash
# Equality
assert_equals "$actual" "$expected" "message"

# String content
assert_contains "$text" "substring" "message"
assert_not_contains "$text" "substring" "message"
assert_pattern "$text" "regex" "message"

# Emptiness
assert_empty "$value" "message"
assert_not_empty "$value" "message"

# Line counting
assert_line_count "$text" "=" "10" "message"   # exactly 10
assert_line_count "$text" ">" "5" "message"    # more than 5
assert_line_count "$text" "<" "20" "message"   # less than 20
assert_line_count "$text" ">=" "3" "message"   # at least 3

# Files
assert_file_exists "/path/to/file" "message"
assert_file_not_exists "/path/to/file" "message"
assert_dir_exists "/path/to/dir" "message"

# Commands
assert_success "command" "message"
assert_fails "command" "message"
```

### Tmux Helpers

```bash
# Session management
start_lazy_llm_session "session-name" "ai-tool" "working-dir"
kill_test_session

# Pane interaction
send_to_prompt_buffer_simple "text"
send_to_prompt_buffer "file.txt"
capture_pane "$AI_PANE"
capture_pane_visible "$PROMPT_PANE"

# Trigger commands
trigger_llm_send              # <leader>llms
trigger_llm_pull              # <leader>llmp
trigger_llm_keypress "2"      # <leader>llmk + key

# Wait helpers
wait_for_text_in_pane "$AI_PANE" "expected text" 10  # 10s timeout

# Session info
session_alive "session-name"
get_pane_count
```

### Environment Variables

Global variables set by `start_lazy_llm_session`:

```bash
TEST_SESSION    # Tmux session name (e.g., "test-simple-send")
AI_PANE         # Pane ID for AI tool (e.g., "%0")
EDITOR_PANE     # Pane ID for Neovim editor (e.g., "%1")
PROMPT_PANE     # Pane ID for prompt buffer (e.g., "%2")
```

## Test Runner Options

```bash
./test-runner.sh [OPTIONS] [TEST_PATTERN]

OPTIONS:
  -h, --help          Show help message
  -d, --debug         Enable debug mode (keeps sessions, verbose output)
  -c, --cleanup       Cleanup all test artifacts and exit
  -v, --verify        Verify test environment and exit
  -l, --list          List all available tests
  -m MODE             Set MOCK_AI_MODE

EXAMPLES:
  ./test-runner.sh                    # Run all tests
  ./test-runner.sh 01-simple-send.sh  # Run specific test
  ./test-runner.sh send               # Pattern match
  ./test-runner.sh -d 02-multiline    # Debug mode
  ./test-runner.sh -m truncate        # With mode
```

## Debug Mode

Debug mode (`-d` flag) is useful for investigating failures:

```bash
./test-runner.sh -d 02-multiline-send.sh
```

**Debug features:**
- Test tmux sessions remain alive after test completion
- Verbose output enabled
- Test artifacts preserved in `/tmp/lazy-llm-test-state/`
- Mock AI logs saved

**Inspecting sessions:**
```bash
# List test sessions
tmux list-sessions | grep test-

# Attach to session
tmux attach -t test-multiline-send

# View panes
tmux list-panes -t test-multiline-send

# Kill session when done
tmux kill-session -t test-multiline-send
```

**Viewing logs:**
```bash
# Mock AI logs
cat /tmp/test-multiline-send-mock-ai.log

# Test logs
cat /tmp/lazy-llm-test-logs/multiline-send.log

# Saved artifacts (on failure)
ls /tmp/lazy-llm-test-state/multiline-send-artifacts/
```

## CI/CD Integration

### GitHub Actions

Tests can run automatically on push/PR:

```yaml
name: Tests
on: [push, pull_request]

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
        run: ./install.sh
      - name: Run tests
        run: cd tests && ./test-runner.sh
```

## Troubleshooting

### Common Issues

**"lazy-llm not found in PATH"**
```bash
# Install lazy-llm first
cd /home/user/lazy-llm && ./install.sh

# Verify installation
which lazy-llm
lazy-llm --help
```

**"Failed to start session"**
```bash
# Check tmux is available
tmux -V

# Try starting manually
lazy-llm -s test-manual -t tests/mock-ai-tool

# Check logs
cat /tmp/test-*-mock-ai.log
```

**"Timeout waiting for lazy-llm session"**
- Increase timeout in `lib/tmux-helpers.sh` (`start_lazy_llm_session`)
- Check if lazy-llm can start successfully outside tests
- Verify Neovim/LazyVim is properly configured

**"Pane ID not found"**
```bash
# Check panes manually
tmux list-panes -t test-session-name -F '#{pane_index}:#{pane_id}'

# Verify 3-pane layout was created
tmux list-panes -t test-session-name | wc -l  # Should be 3
```

**Assertions failing unexpectedly**
```bash
# Run in debug mode to inspect
./test-runner.sh -d failing-test.sh

# Attach to session and check pane contents
tmux attach -t test-failing-test

# Manually capture pane to see what's there
tmux capture-pane -p -t %0  # Replace %0 with actual pane ID
```

**Tests passing locally but failing in CI**
- Check timing differences (CI may be slower)
- Increase sleep durations in tests
- Verify all dependencies are installed in CI
- Check tmux version compatibility

### Cleanup

```bash
# Kill all test sessions
for s in $(tmux list-sessions -F '#{session_name}' | grep test-); do
    tmux kill-session -t "$s"
done

# Remove test artifacts
./test-runner.sh -c

# Manual cleanup
rm -rf /tmp/lazy-llm-test-*
rm -f /tmp/test-*-mock-ai.log
rm -f /tmp/mock-ai-tool-*.log
```

## Test Coverage

Current test scenarios:

| Test | Focus | What it validates |
|------|-------|-------------------|
| 01-simple-send | Basic send | Single line prompt with markers |
| 02-multiline-send | Multiline | Paragraph prompts, line preservation |
| 03-large-paste | Large input | >1KB prompts, delay handling |
| 04-marker-placement | Formatting | Marker line breaks, timestamp format |
| 05-response-pull | llm-pull | Response extraction, filtering |
| 06-visual-selection | Visual mode | Partial buffer send |
| 07-keypress-forward | llmk | Interactive prompt responses |

### Adding New Tests

1. Create test file in `tests/scenarios/`
2. Follow naming convention: `NN-test-name.sh`
3. Include descriptive comment: `# Test: What this validates`
4. Use template above as starting point
5. Make executable: `chmod +x tests/scenarios/NN-test-name.sh`
6. Test it: `./test-runner.sh NN-test-name.sh`
7. Run in debug mode to verify: `./test-runner.sh -d NN-test-name.sh`

## Future Enhancements

See `docs/AUTOMATED_TESTING.md` for:
- Integration testing with real AI tools (Claude, Gemini, Codex)
- Credential management via `.env`
- Performance benchmarking
- Visual regression testing
- Coverage reporting

## Contributing

When contributing tests:
1. Write clear test descriptions
2. Use meaningful assertion messages
3. Add comments explaining non-obvious logic
4. Test both success and failure cases
5. Use fixtures for reusable test data
6. Clean up resources in test (if not using helpers)
7. Run full test suite before submitting PR

## Support

- **Issues**: Report bugs at https://github.com/paulomuggler/lazy-llm/issues
- **Questions**: See main README.md and docs/
- **Spec**: Full testing design at `docs/AUTOMATED_TESTING.md`
