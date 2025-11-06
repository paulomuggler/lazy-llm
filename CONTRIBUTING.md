# Contributing to lazy-llm

Thank you for your interest in contributing to lazy-llm! This document provides guidelines for contributing to the project.

## Getting Started

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/lazy-llm.git
   cd lazy-llm
   ```

2. **Install dependencies and run the installer**
   ```bash
   ./install.sh
   ```

3. **Test your installation**
   ```bash
   lazy-llm -t claude  # or your preferred AI tool
   ```

## Making Changes

### Before You Start

1. Check existing issues and PRs to avoid duplicate work
2. For major changes, open an issue first to discuss the approach
3. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

### Code Style

- **Shell scripts**: Follow Google Shell Style Guide basics
  - Use `#!/usr/bin/env bash` for portability
  - Quote variables: `"$variable"` not `$variable`
  - Use `[[` instead of `[` for conditionals
  - Add comments for non-obvious logic

- **Lua (Neovim config)**: Follow LazyVim conventions
  - Use 2-space indentation
  - Group related keymaps together
  - Add comments for custom functions

### Testing

**IMPORTANT**: lazy-llm includes a comprehensive test suite that should be run before submitting PRs.

#### Running Tests

```bash
# From repository root
cd tests

# Run all tests
./test-runner.sh

# Run specific test
./test-runner.sh 01-simple-send.sh

# Run tests matching a pattern
./test-runner.sh send

# Debug mode (keeps tmux sessions alive for inspection)
./test-runner.sh -d 02-multiline-send.sh

# Verify test environment
./test-runner.sh -v

# List available tests
./test-runner.sh -l
```

#### Test Requirements

- All tests must pass before PR submission
- For bug fixes: add a test case that reproduces the bug
- For new features: add test coverage for the new functionality
- Tests should be reliable and not flaky

#### Writing Tests

See [`tests/README.md`](tests/README.md) for comprehensive testing documentation, including:
- Test structure and templates
- Available assertion functions
- Tmux helper functions
- Mock AI tool usage
- Debug techniques

Quick template:
```bash
#!/usr/bin/env bash
# Test: Description of what this validates

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TESTS_DIR/lib/assertions.sh"
source "$TESTS_DIR/lib/tmux-helpers.sh"
source "$TESTS_DIR/lib/setup-teardown.sh"

TEST_NAME="my-new-test"

# Start lazy-llm session
echo "Starting lazy-llm session..."
if ! start_lazy_llm_session "$TEST_NAME"; then
    echo "Failed to start session"
    exit 1
fi

sleep 2

# Your test logic here
send_to_prompt_buffer_simple "Test prompt"
trigger_llm_send
sleep 1

AI_OUTPUT=$(capture_pane "$AI_PANE")

# Assertions
echo ""
echo "Running assertions..."
assert_contains "$AI_OUTPUT" "expected text" "Should contain expected text"

print_assertion_summary
```

#### Testing Limitations

**Note**: Integration tests for PTY-based applications have inherent timing sensitivities. See [`docs/HEADLESS_TESTING_RESEARCH.md`](docs/HEADLESS_TESTING_RESEARCH.md) for detailed research on this topic.

- Some tests may be timing-sensitive
- Tests create real tmux sessions with PTY
- CI automation is partially limited (some tests are manual-only)
- This is a known limitation shared by projects like tmux itself

When a test fails:
1. Run it 2-3 times to check for flakiness
2. Use debug mode: `./test-runner.sh -d <test-name>`
3. Attach to test session: `tmux attach -t test-<name>`
4. Check logs in `/tmp/test-*-mock-ai.log`

### Commit Messages

Follow conventional commits format:

```
type(scope): brief description

Longer explanation if needed

Fixes #123
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Test additions or changes
- `refactor`: Code refactoring
- `chore`: Maintenance tasks

Examples:
```
feat(keymaps): add visual mode support for llmr command

fix(tmux): handle session name collisions properly

test(send): add test for large prompt handling

docs(readme): clarify installation prerequisites
```

## Pull Request Process

### Before Submitting

1. **Run the test suite**
   ```bash
   cd tests && ./test-runner.sh
   ```

2. **Test manually with different AI tools**
   ```bash
   lazy-llm -t claude
   lazy-llm -t gemini
   # Test your changes in both
   ```

3. **Update documentation**
   - Update README.md if adding features
   - Update tests/README.md if adding test utilities
   - Add docstrings to new functions

4. **Clean up**
   ```bash
   # Remove debug code
   # Remove commented-out code
   # Check for TODOs
   ```

### PR Checklist

- [ ] Tests pass locally (`cd tests && ./test-runner.sh`)
- [ ] Code follows project style guidelines
- [ ] Commit messages follow conventional format
- [ ] Documentation updated (if applicable)
- [ ] New tests added (for bug fixes or features)
- [ ] Manual testing completed
- [ ] No breaking changes (or clearly documented)

### PR Description Template

```markdown
## Description
Brief description of changes

## Motivation
Why is this change needed?

## Changes
- Bullet point list of changes
- Include file paths for major changes

## Testing
How was this tested?
- [ ] Ran full test suite
- [ ] Tested manually with [AI tool names]
- [ ] Added new test: [test name]

## Screenshots (if applicable)
For UI/visual changes

## Breaking Changes
None / List any breaking changes

## Related Issues
Fixes #123
Related to #456
```

### Review Process

1. Maintainers will review your PR
2. Address feedback by pushing new commits
3. Once approved, maintainer will merge
4. Use squash merge for cleaner history (default)

## Reporting Issues

### Bug Reports

Use the issue template and include:

1. **Description**: Clear description of the bug
2. **Steps to reproduce**:
   ```
   1. Start lazy-llm with: lazy-llm -t claude
   2. Send prompt: [example prompt]
   3. Observe: [what happens]
   ```
3. **Expected behavior**: What should happen
4. **Actual behavior**: What actually happens
5. **Environment**:
   - OS: [e.g., Ubuntu 22.04, macOS 14.0]
   - tmux version: `tmux -V`
   - Neovim version: `nvim --version`
   - lazy-llm version: `git rev-parse HEAD`
6. **Logs**: Include relevant logs from `/tmp/lazy-llm-*`

### Feature Requests

1. Check if feature already requested
2. Describe use case and motivation
3. Provide examples of desired behavior
4. Consider implementation complexity

## Development Workflow

### Typical Development Session

```bash
# 1. Create feature branch
git checkout -b feature/new-keymap

# 2. Make changes
# Edit files in home/.config/nvim/lua/plugins/ or bin/

# 3. Test locally (reinstall if needed)
./install.sh

# 4. Start lazy-llm and test manually
lazy-llm -t tests/mock-ai-tool  # Use mock for quick testing

# 5. Run automated tests
cd tests && ./test-runner.sh

# 6. Debug if needed
./test-runner.sh -d my-test.sh
tmux attach -t test-my-test  # Inspect the session

# 7. Commit changes
git add .
git commit -m "feat(keymaps): add new keymap for X"

# 8. Push and create PR
git push origin feature/new-keymap
```

### Debug Techniques

**For lazy-llm script issues:**
```bash
# Add debug output
set -x  # At top of script for verbose output

# Check variables
echo "DEBUG: SESSION=$SESSION" >&2
```

**For Neovim plugin issues:**
```lua
-- Add to Neovim config
vim.notify("DEBUG: variable = " .. vim.inspect(variable))

-- Check keymaps
:verbose map <leader>llms
```

**For test issues:**
```bash
# Run in debug mode
./test-runner.sh -d test-name.sh

# Attach to test session
tmux attach -t test-name

# Check pane contents manually
tmux capture-pane -p -t %0  # Replace %0 with pane ID

# View logs
cat /tmp/test-name-mock-ai.log
```

## Project Structure

```
lazy-llm/
├── bin/
│   └── lazy-llm              # Main launcher script
├── home/
│   ├── .config/nvim/
│   │   └── lua/plugins/
│   │       └── lazy-llm.lua  # Neovim plugin config
│   └── .tmux.conf.lazy-llm   # Tmux configuration
├── tests/
│   ├── mock-ai-tool          # Mock AI for testing
│   ├── test-runner.sh        # Test orchestrator
│   ├── lib/                  # Test libraries
│   ├── scenarios/            # Test scenarios
│   └── README.md             # Test documentation
├── docs/
│   ├── AUTOMATED_TESTING.md  # Testing specification
│   └── HEADLESS_TESTING_RESEARCH.md  # PTY testing research
├── install.sh                # Installation script
└── README.md                 # Main documentation
```

## Key Files to Know

- `bin/lazy-llm` - Main entry point, tmux session creation
- `home/.config/nvim/lua/plugins/lazy-llm.lua` - All keymaps and Neovim functionality
- `tests/lib/tmux-helpers.sh` - Tmux session management for tests
- `tests/lib/assertions.sh` - Assertion functions for tests
- `tests/mock-ai-tool` - Simulates AI tools for testing

## Getting Help

- **Documentation**: Start with README.md and tests/README.md
- **Issues**: Check existing issues for similar problems
- **Testing**: See docs/HEADLESS_TESTING_RESEARCH.md for testing insights
- **Code questions**: Open a discussion or issue

## Code of Conduct

- Be respectful and constructive
- Focus on the problem, not the person
- Welcome newcomers and help them learn
- Follow the golden rule

## Resources

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [LazyVim Documentation](https://www.lazyvim.org/)
- [tmux Documentation](https://github.com/tmux/tmux/wiki)
- [Conventional Commits](https://www.conventionalcommits.org/)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to lazy-llm! 🚀
