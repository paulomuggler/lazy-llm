# Integration Tests for lazy-llm

Integration tests using **real AI TUI tools** (Claude Code, Gemini CLI, Codex) to verify autosubmit reliability, response parsing, and tool-specific behavior.

## Quick Start

```bash
# 1. Set up credentials
cp tests/integration/.env.example tests/integration/.env
# Edit .env and add your API keys

# 2. Install AI tools
npm install -g @anthropic-ai/claude-code
npm install -g @google/gemini-cli

# 3. Run all tests
cd tests/integration
./runner.sh

# 4. Run specific tool tests
./runner.sh claude
./runner.sh gemini
```

## Requirements

### Prerequisites

1. **lazy-llm installed**: Run `./install.sh` from repository root
2. **Neovim/LazyVim**: Properly configured (`~/.config/nvim/`)
3. **Dependencies**: tmux, Node.js 18+, npm
4. **API Keys**: Active keys for the tools you want to test

### AI Tool Installation

**Claude Code:**
```bash
npm install -g @anthropic-ai/claude-code
```

**Gemini CLI:**
```bash
npm install -g @google/gemini-cli
```

**Codex** (unofficial):
```bash
# TBD - not yet supported in integration tests
```

## Configuration

### API Keys Setup

1. Copy the example file:
   ```bash
   cp tests/integration/.env.example tests/integration/.env
   ```

2. Edit `.env` and add your keys:
   ```bash
   # Get Claude key from: https://console.anthropic.com/settings/keys
   ANTHROPIC_API_KEY=sk-ant-...

   # Get Gemini key from: https://aistudio.google.com/app/apikey
   GEMINI_API_KEY=AIza...
   ```

3. **Important**: `.env` is gitignored - never commit it!

### Configuration Options

Edit `tests/integration/.env`:

```bash
# Timeout for AI responses (seconds)
INTEGRATION_TEST_TIMEOUT=30

# Cleanup sessions after tests
INTEGRATION_TEST_CLEANUP=true

# Keep sessions on failure (for debugging)
INTEGRATION_TEST_KEEP_ON_FAILURE=false

# Enable/disable specific tools
TEST_CLAUDE=true
TEST_GEMINI=true
TEST_CODEX=false
```

## Running Tests

### Basic Usage

```bash
# Run all enabled tests
./runner.sh

# Run specific tool
./runner.sh claude
./runner.sh gemini

# Run with debug mode (keeps sessions alive)
./runner.sh -d claude

# Keep sessions on failure
./runner.sh -k gemini

# List available tests
./runner.sh -l

# Verify environment and credentials
./runner.sh -v
```

### Environment Verification

Before running tests, verify your setup:

```bash
./runner.sh -v
```

This checks:
- ✓ .env file exists and is loaded
- ✓ lazy-llm is installed
- ✓ tmux and nvim are available
- ✓ AI CLI tools are installed
- ✓ API keys are set

## Test Scenarios

### Claude Tests

Located in `scenarios/claude/`:

| Test | Purpose | What It Validates |
|------|---------|-------------------|
| 01-autosubmit.sh | Basic autosubmit | Simple prompt, response timing, markers |
| 02-multiline-reliability.sh | Multiline prompts | Paragraph handling, code generation |

**Status**: Claude generally has the most reliable behavior with lazy-llm.

### Gemini Tests

Located in `scenarios/gemini/`:

| Test | Purpose | Known Issues |
|------|---------|--------------|
| 01-autosubmit.sh | Basic autosubmit | Sometimes fails |
| 02-truncation-bug.sh | Prompt repetition | Repeats prompt 6-8x on multiline |
| 03-marker-linebreaks.sh | Marker formatting | Breaks line formatting |

**Known Issues**:
- ⚠️ **Truncation bug**: Multiline prompts get repeated 6-8 times
- ⚠️ **Autosubmit**: Intermittent failures requiring manual Enter
- ⚠️ **Marker line breaks**: Improper newlines around BEGIN/END PROMPT markers
- ⚠️ **llm-pull unusable**: Due to above issues, response extraction fails

### Test Structure

Each integration test follows this pattern:

```bash
#!/usr/bin/env bash
# Integration Test: Description

# Load libraries
source "$INTEGRATION_DIR/lib/ai-tool-helpers.sh"
source "$INTEGRATION_DIR/lib/integration-assertions.sh"

# Skip if tool disabled
skip_if_disabled "claude"

# Load credentials
load_dotenv "$INTEGRATION_DIR/.env"
require_tool "claude" "ANTHROPIC_API_KEY"

# Start lazy-llm with AI tool
start_lazy_llm_with_ai_tool "test-name" "claude"

# Send prompt and wait
send_prompt "What is 2+2?"
wait_for_response 30

# Capture and assert
AI_OUTPUT=$(capture_pane "$AI_PANE")
assert_autosubmit_success "$AI_OUTPUT"
assert_contains "$AI_OUTPUT" "4"

print_assertion_summary
```

## Helper Libraries

### ai-tool-helpers.sh

```bash
# Load environment
load_dotenv "$INTEGRATION_DIR/.env"

# Check tool availability
require_tool "claude" "ANTHROPIC_API_KEY"
skip_if_disabled "gemini"

# Session management
start_lazy_llm_with_ai_tool "session-name" "tool-name"

# Send and wait
send_prompt "prompt text"
wait_for_response 30

# Extract response
RESPONSE=$(extract_response "$AI_OUTPUT")

# Check autosubmit
check_autosubmit_success "$AI_OUTPUT"
```

### integration-assertions.sh

Extends base assertions with integration-specific checks:

```bash
# Autosubmit validation
assert_autosubmit_success "$output" "message"

# Response validation
assert_valid_response "$response"
assert_contains_code_block "$response" "python"

# Known bugs
assert_no_prompt_repetition "$output"
assert_markers_have_line_breaks "$output"

# Timing
assert_response_time $start $end 30

# Document issues
log_known_bug "Description of bug"
```

## Debugging Failed Tests

### Debug Mode

Run with `-d` flag to keep sessions alive:

```bash
./runner.sh -d claude
```

**What this does**:
- Sessions remain alive after tests
- Verbose output enabled
- Artifacts saved
- Can inspect tmux panes manually

**Inspecting sessions**:
```bash
# List test sessions
tmux list-sessions | grep test-

# Attach to session
tmux attach -t test-claude-autosubmit

# View specific pane
tmux select-pane -t %0  # AI pane
tmux select-pane -t %1  # Editor pane
tmux select-pane -t %2  # Prompt pane

# Kill session when done
tmux kill-session -t test-claude-autosubmit
```

### Keep Sessions on Failure

Use `-k` flag to only keep failed test sessions:

```bash
./runner.sh -k gemini
```

### View Artifacts

Failed tests save artifacts to `/tmp/lazy-llm-test-state/`:

```bash
ls /tmp/lazy-llm-test-state/claude-autosubmit-artifacts/

# View pane captures
cat /tmp/lazy-llm-test-state/claude-autosubmit-artifacts/ai-pane.txt
cat /tmp/lazy-llm-test-state/claude-autosubmit-artifacts/prompt-pane.txt

# View logs
cat /tmp/lazy-llm-test-state/claude-autosubmit-artifacts/test.log
```

## Common Issues

### "API key invalid" or 403 Forbidden

**Gemini:**
- Verify key is active at https://aistudio.google.com/app/apikey
- Check key has proper permissions
- Ensure billing is enabled if required

**Claude:**
- Verify key at https://console.anthropic.com/settings/keys
- Check API usage/billing
- Ensure key hasn't expired

### "Timeout waiting for response"

- Increase `INTEGRATION_TEST_TIMEOUT` in .env
- Check network connectivity
- Verify AI tool is actually running (attach to tmux session)
- Check API rate limits

### "lazy-llm not found"

```bash
# Install lazy-llm
cd /path/to/lazy-llm
./install.sh

# Verify installation
which lazy-llm
lazy-llm --help
```

### "nvim not found" or LazyVim issues

Integration tests require a working Neovim setup:

```bash
# Install neovim
# (varies by OS)

# Verify LazyVim config exists
ls ~/.config/nvim/

# Test nvim works
nvim --version
```

### Autosubmit consistently failing

This is a known issue being investigated. If you see failures:

1. **Document the behavior**: Check which tool and prompt type
2. **Try manually**: Attach to session and test manually
3. **Report**: Create GitHub issue with:
   - Tool name and version
   - Prompt that failed
   - AI pane output
   - Whether manual Enter fixes it

## Adding New Tests

### Create a Test File

```bash
# Create test in appropriate directory
touch tests/integration/scenarios/claude/03-new-test.sh
chmod +x tests/integration/scenarios/claude/03-new-test.sh
```

### Test Template

```bash
#!/usr/bin/env bash
# Integration Test: Description of what this tests

INTEGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_DIR="$(cd "$INTEGRATION_DIR/.." && pwd)"

source "$INTEGRATION_DIR/lib/ai-tool-helpers.sh"
source "$INTEGRATION_DIR/lib/integration-assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

# Skip if tool disabled
skip_if_disabled "claude"

# Load credentials
if ! load_dotenv "$INTEGRATION_DIR/.env"; then
    exit 1
fi

if ! require_tool "claude" "ANTHROPIC_API_KEY"; then
    exit 1
fi

TEST_NAME="claude-new-test"

echo "Starting lazy-llm with Claude..."
if ! start_lazy_llm_with_ai_tool "$TEST_NAME" "claude"; then
    exit 1
fi

sleep 3

# Your test logic here
send_prompt "Test prompt"
wait_for_response 30

AI_OUTPUT=$(capture_pane "$AI_PANE")

echo ""
echo "Running assertions..."

assert_autosubmit_success "$AI_OUTPUT"
assert_contains "$AI_OUTPUT" "expected text"

print_assertion_summary
```

### Run Your Test

```bash
./runner.sh claude
```

## Known Bugs Documentation

Integration tests document known issues:

### Gemini Issues

1. **Truncation/Repetition Bug**
   - **Symptom**: Multiline prompts repeated 6-8 times
   - **Impact**: Response unusable, llm-pull broken
   - **Test**: `scenarios/gemini/02-truncation-bug.sh`
   - **Status**: Reproducible, awaiting fix

2. **Marker Line Breaking**
   - **Symptom**: Markers not on own lines
   - **Impact**: Response extraction fails
   - **Test**: `scenarios/gemini/03-marker-linebreaks.sh`
   - **Status**: Reproducible

3. **Autosubmit Reliability**
   - **Symptom**: Sometimes requires manual Enter
   - **Impact**: Workflow interruption
   - **Test**: `scenarios/gemini/01-autosubmit.sh`
   - **Status**: Intermittent

### Claude Issues

1. **Intermittent Autosubmit**
   - **Symptom**: Occasionally fails to submit
   - **Impact**: Minor workflow interruption
   - **Test**: `scenarios/claude/01-autosubmit.sh`
   - **Status**: Rare, under investigation

## CI/CD Integration

### GitHub Actions

Example workflow for running integration tests in CI:

```yaml
name: Integration Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:  # Manual trigger

jobs:
  integration-tests:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y tmux stow neovim

      - name: Install AI CLI tools
        run: |
          npm install -g @anthropic-ai/claude-code
          npm install -g @google/gemini-cli

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
          echo "TEST_CLAUDE=true" >> .env
          echo "TEST_GEMINI=true" >> .env
          ./runner.sh

      - name: Upload artifacts on failure
        if: failure()
        uses: actions/upload-artifact@v3
        with:
          name: test-artifacts
          path: /tmp/lazy-llm-test-state/
```

**Setup secrets** in GitHub:
- Settings → Secrets → Actions
- Add `ANTHROPIC_API_KEY`
- Add `GEMINI_API_KEY`

## Support

- **Issues**: https://github.com/paulomuggler/lazy-llm/issues
- **Documentation**: See `docs/AUTOMATED_TESTING.md` for full spec
- **Unit Tests**: See `tests/README.md` for mock testing
