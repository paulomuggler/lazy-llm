# Headless PTY Testing Research
## Automated Integration Testing for Terminal Applications

**Date:** 2025-11-06
**Status:** Research Complete
**Context:** Investigating how to run automated integration tests for lazy-llm in headless CI environments

---

## Executive Summary

Automated testing of PTY-based terminal applications in headless environments is a **well-known challenge** with several solutions, though each has trade-offs. The good news: **lazy-llm already has excellent test infrastructure** using tmux for PTY testing, which mirrors the approach used by major terminal projects.

### Key Finding from tmux Project

When someone attempted to add CI automation to tmux's regress tests ([PR #3962](https://github.com/tmux/tmux/pull/3962)), the maintainer declined, stating:

> "Thanks but I don't think I want these tests run on every commit, they are not 100% reliable, it is better if they are run manually."

**This is the exact challenge we face.** PTY-based integration tests have inherent timing and environment sensitivities that make them challenging for fully automated CI.

---

## Current State: lazy-llm Test Infrastructure

### What We Have ✓

lazy-llm has a **sophisticated test infrastructure** already in place:

- **Test Runner:** `/tests/test-runner.sh` with debug mode, pattern matching, and cleanup
- **Mock AI Tool:** Simulates AI responses in multiple modes (echo, multiline, truncate, delay, interactive, markers)
- **Test Scenarios:** 7 comprehensive test cases covering:
  - Simple send operations
  - Multiline prompts
  - Large paste handling
  - Marker placement
  - Response pulling
  - Visual selection
  - Keypress forwarding
- **Library Support:**
  - `assertions.sh` - 15+ assertion functions
  - `tmux-helpers.sh` - PTY session management
  - `setup-teardown.sh` - Test lifecycle
- **Documentation:** Comprehensive `tests/README.md` with usage guide

### Architecture

```
┌─────────────────────────────────────────┐
│         test-runner.sh                  │
│   (Orchestrates all test execution)    │
└──────────────┬──────────────────────────┘
               │
               ├──► Mock AI Tool (simulates AI responses)
               │
               ├──► tmux Sessions (real PTY)
               │    ├─ Pane 0: AI Tool
               │    ├─ Pane 1: Neovim Editor
               │    └─ Pane 2: Prompt Buffer
               │
               └──► Assertions (validate outputs)
```

### How It Works

1. **Start tmux session** with 3 panes (AI tool, editor, prompt buffer)
2. **Send test prompts** to the prompt buffer via tmux commands
3. **Trigger lazy-llm commands** (`<leader>llms`, `<leader>llmp`, etc.)
4. **Capture pane output** using `tmux capture-pane`
5. **Run assertions** against captured text
6. **Cleanup** sessions between tests

---

## Research Findings: Industry Approaches

### 1. tmux Project Testing

**Location:** `regress/` directory
**Method:** Bash scripts that test tmux functionality
**CI Status:** Intentionally manual-only due to reliability concerns
**Key Files:**
- `copy-mode-test-emacs.sh`
- `copy-mode-test-vi.sh`
- `format-strings.sh`
- `input-keys.sh`
- `tty-keys.sh`

**Lesson:** Even tmux itself doesn't fully automate PTY tests in CI.

### 2. Terminal Emulator Projects

#### Alacritty
- **Testing:** Uses `vtebench` for performance benchmarks
- **Focus:** PTY read speed, not interactive behavior
- **Library:** Rust-based `alacritty_terminal` crate with unit tests

#### WezTerm
- **Testing:** Unit tests with `TestTerm` wrapper
- **Approach:** Test terminal emulation layer directly, not full PTY
- **Benefit:** Faster, more reliable than full integration tests

#### Zellij
- **Testing:** Performance benchmarks with `hyperfine`
- **Method:** Cat large files, measure throughput
- **PTY Tests:** Limited information available

### 3. Testing Tools & Frameworks

#### A. Python: pexpect
**Best for:** Scripting interactive programs
**Pros:**
- Pure Python, widely used
- Good for ssh, ftp, passwd automation
- Regex pattern matching
- Cross-platform (Unix-only for PTY features)

**Cons:**
- Can be brittle (timing issues)
- Hard to debug flaky tests
- Headless reliability issues (see pyinvoke/invoke#37)

**Example:**
```python
import pexpect
child = pexpect.spawn('lazy-llm')
child.expect('PROMPT')
child.sendline('test prompt')
child.expect('Mock AI Tool')
```

#### B. Bash: expect + DejaGnu
**Best for:** Traditional UNIX testing
**Pros:**
- Battle-tested (used for GCC testing)
- Tcl-based scripting
- Good terminal mode control (cooked, raw, echo)

**Cons:**
- Tcl learning curve
- Older technology
- Verbose syntax

**Example (Expect):**
```tcl
spawn lazy-llm
expect "PROMPT"
send "test prompt\r"
expect "Mock AI Tool"
```

#### C. Python: pytest-tmux
**Best for:** Python projects testing CLIs
**Pros:**
- Integrates with pytest ecosystem
- Uses tmux for PTY management
- Screen capture and assertion helpers
- Modern, actively maintained

**Cons:**
- Python-only
- Still subject to timing issues
- Requires Python test runner

**Example:**
```python
def test_send(tmux):
    tmux.send_keys('printf "Hello"')
    assert "Hello" in tmux.screen()
```

#### D. Bash: tmux-test
**Best for:** Testing tmux plugins
**Pros:**
- Designed specifically for tmux
- Isolated test environments
- Can use Vagrant for consistency

**Cons:**
- Plugin-focused, not general purpose
- Heavyweight (Vagrant)
- Limited adoption

#### E. Bash Testing Frameworks
Several frameworks for bash script testing:
- **ShellSpec** - BDD-style, POSIX-compliant
- **BATS** (bats-core) - TAP-compliant, actively maintained
- **Bach** - Assertion-based
- **bash_unit** - Enterprise-focused with mocking

**Note:** These test bash scripts themselves, not PTY interactions.

#### F. Terminal Emulation Testing

**VTTEST:**
- Tests VT100/VT102 terminal features
- Manual inspection required
- Not automated

**esctest:**
- Automated unit tests for terminal emulation
- Uses DECRCRA control sequences
- Cannot test interactive features
- Good for regression testing

---

## The Fundamental Challenges

### 1. Timing Sensitivity
PTY operations are inherently asynchronous:
- Process startup time varies
- Screen rendering has delays
- Key events may race with output
- Terminal state transitions take time

**Impact:** Tests may pass 80% of the time but fail intermittently.

### 2. Environment Dependencies
Tests depend on:
- Terminal dimensions
- TTY availability
- Shell configuration
- Process scheduling
- System load

**Impact:** Works locally, fails in CI.

### 3. Text vs. Visual Testing
Terminal apps are visual, but tests capture text:
- Cursor positions matter
- Colors and formatting affect behavior
- Screen updates may be partial
- Scrollback complicates capture

**Impact:** Hard to verify visual correctness.

---

## Solutions & Recommendations

### Tier 1: What We Already Have (Keep & Enhance)

**Current Approach:** Manual testing with excellent tooling ✓

**Recommended Enhancements:**

1. **Add Test Environment Validation**
   ```bash
   # In test-runner.sh -v
   - Check tmux version compatibility
   - Verify terminal dimensions
   - Test PTY availability
   - Validate lazy-llm installation
   ```

2. **Improve Timing Robustness**
   ```bash
   # Instead of: sleep 2
   # Use: wait_for_text_in_pane with timeout
   wait_for_text_in_pane "$PROMPT_PANE" ">" 10
   ```

3. **Add Retry Logic for Flaky Tests**
   ```bash
   run_test_with_retry() {
       local max_attempts=3
       for i in $(seq 1 $max_attempts); do
           if run_test "$1"; then
               return 0
           fi
           echo "Retry $i/$max_attempts..."
       done
       return 1
   }
   ```

4. **Enhanced Debug Artifacts**
   ```bash
   - Screenshot capture (tmux screen dump)
   - Timing logs (operation durations)
   - Pane content snapshots at each step
   - Mock AI interaction logs
   ```

### Tier 2: Selective CI Automation (Medium Effort)

**Goal:** Run stable tests in CI, keep flaky ones manual

**Approach:**

1. **Categorize Tests by Stability**
   ```bash
   tests/
   ├── scenarios/
   │   ├── stable/          # CI-safe tests
   │   │   ├── 01-simple-send.sh
   │   │   └── 04-marker-placement.sh
   │   └── interactive/     # Manual-only tests
   │       ├── 06-visual-selection.sh
   │       └── 07-keypress-forward.sh
   ```

2. **GitHub Actions Workflow**
   ```yaml
   name: Integration Tests (Stable)
   on: [push, pull_request]

   jobs:
     test:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v3
         - name: Install dependencies
           run: |
             sudo apt-get update
             sudo apt-get install -y tmux neovim stow
         - name: Install lazy-llm
           run: ./install.sh
         - name: Run stable tests
           run: cd tests && ./test-runner.sh stable/
           timeout-minutes: 10
         - name: Upload artifacts on failure
           if: failure()
           uses: actions/upload-artifact@v3
           with:
             name: test-artifacts
             path: /tmp/lazy-llm-test-state/
   ```

3. **Add Test Metadata**
   ```bash
   # In test files:
   # Test: Simple single-line prompt send
   # Stability: stable
   # CI: enabled
   # Timing: fast (<5s)
   ```

### Tier 3: Advanced Testing (High Effort)

#### Option A: VT100 Emulation Library

**Approach:** Test terminal parsing without PTY

**Example with Python `pyte`:**
```python
import pyte

screen = pyte.Screen(80, 24)
stream = pyte.Stream(screen)

# Send ANSI sequences
stream.feed("### PROMPT 2025-11-06\r\n")
stream.feed("Test prompt\r\n")
stream.feed("### END PROMPT\r\n")

# Assert screen contents
assert "### PROMPT" in screen.display[0]
assert "Test prompt" in screen.display[1]
```

**Pros:**
- Fast, deterministic
- No PTY needed
- Easy to debug

**Cons:**
- Doesn't test actual tmux integration
- Misses timing issues
- Requires rewriting tests

#### Option B: Video Recording & Analysis

**Approach:** Record terminal session, analyze frames

**Tools:**
- `asciinema` - Record terminal sessions
- `vhs` - Generate terminal GIFs/videos
- Custom frame analysis scripts

**Example:**
```bash
# Record test session
asciinema rec test-session.cast -c "cd tests && ./test-runner.sh 01-simple-send.sh"

# Analyze recording
asciinema cat test-session.cast | grep "### PROMPT"
```

**Pros:**
- Visual verification
- Captures real behavior
- Useful for documentation

**Cons:**
- Slow
- Hard to parse
- Storage intensive

#### Option C: Hybrid Unit + Integration

**Approach:** Unit test components, integration test critical paths

**Architecture:**
```
Unit Tests (Fast, CI-friendly)
├── Test marker formatting
├── Test prompt parsing
├── Test piping logic
└── Test mock AI modes

Integration Tests (Manual)
├── Full lazy-llm workflow
├── Multi-pane interaction
└── Real AI tool testing
```

**Example Unit Test:**
```bash
# tests/unit/test-markers.sh
test_marker_format() {
    local marker="### PROMPT 2025-11-06 10:30:45"
    assert_pattern "$marker" "^### PROMPT [0-9]{4}-[0-9]{2}-[0-9]{2}"
}
```

---

## Specific Tool Recommendations

### For Current Needs (Immediate)

**Stick with current bash + tmux approach** with these additions:

1. **Better Waiting Primitives**
   ```bash
   # Already have wait_for_text_in_pane
   # Add:
   wait_for_pane_stable "$pane_id" 1.0  # Wait for output to stop
   wait_for_process "$pid"              # Wait for process
   ```

2. **Test Flakiness Tracking**
   ```bash
   # Run test N times, track success rate
   ./test-runner.sh --flakiness-check 10 01-simple-send.sh
   # Output: 8/10 passed (80% success rate)
   ```

3. **Parallel Test Execution** (for speed)
   ```bash
   # Run independent tests in parallel
   ./test-runner.sh --parallel 4
   ```

### For Future Enhancement

If you want Python integration:

**Consider pytest-tmux for additional test types:**

```python
# tests/python/test_integration.py
def test_prompt_send(tmux):
    """Complementary Python test for complex scenarios"""
    tmux.config.session.window_command = 'lazy-llm -s test -t mock-ai-tool'

    # More complex assertions with Python
    screen = tmux.screen()
    lines = screen.split('\n')

    prompt_idx = next(i for i, line in enumerate(lines) if '### PROMPT' in line)
    assert prompt_idx >= 0
    assert '### END PROMPT' in lines[prompt_idx + 2:]
```

---

## Implementation Plan

### Phase 1: Enhance Current Tests (Week 1)
- [ ] Add test stability metadata to scenarios
- [ ] Implement better waiting primitives
- [ ] Add retry logic for timing-sensitive tests
- [ ] Improve debug artifacts on failure
- [ ] Add flakiness detection mode

### Phase 2: CI Integration (Week 2)
- [ ] Create stable test suite
- [ ] Write GitHub Actions workflow
- [ ] Test on multiple Ubuntu versions
- [ ] Document CI limitations in README
- [ ] Keep interactive tests manual

### Phase 3: Extended Coverage (Future)
- [ ] Add unit tests for shell functions
- [ ] Consider Python pytest-tmux for complex cases
- [ ] Add performance benchmarks
- [ ] Create visual regression suite (optional)

---

## Comparative Analysis

| Approach | Reliability | Speed | Maintenance | CI-Friendly | Coverage |
|----------|-------------|-------|-------------|-------------|----------|
| **Current (tmux + bash)** | ⚠️ Medium | ⚡ Fast | ✅ Easy | ⚠️ Partial | 🎯 High |
| **pexpect (Python)** | ⚠️ Medium | ⚡ Fast | ⚠️ Medium | ⚠️ Partial | 🎯 High |
| **pytest-tmux** | ⚠️ Medium | ⚡ Fast | ✅ Easy | ⚠️ Partial | 🎯 High |
| **VT100 emulation** | ✅ High | ⚡⚡ Very Fast | ❌ Hard | ✅ Yes | ⚠️ Medium |
| **Manual only** | ✅ High | ❌ Slow | ✅ Easy | ❌ No | 🎯 High |
| **Hybrid (unit+int)** | ✅ High | ⚡ Fast | ⚠️ Medium | ✅ Partial | 🎯🎯 Very High |

**Legend:**
- ✅ Good / ⚠️ Medium / ❌ Poor
- ⚡ Fast / ❌ Slow

---

## Conclusion

### The Reality of PTY Testing

**There is no perfect solution.** Even tmux—a project entirely about terminal management—chooses manual testing over fully automated CI for their PTY tests. This is not a lazy-llm problem; it's a fundamental characteristic of testing terminal applications.

### Our Advantages

1. ✅ **We already have excellent infrastructure** (tmux-based tests)
2. ✅ **We have a mock AI tool** (deterministic testing)
3. ✅ **We have comprehensive scenarios** (7 test cases)
4. ✅ **We have good documentation** (tests/README.md)
5. ✅ **We follow industry best practices** (same approach as tmux)

### Recommended Path Forward

**Short Term (Do Now):**
1. ✅ Use existing test infrastructure as-is
2. ✅ Add minor enhancements (better waits, retry logic)
3. ✅ Document test execution in PR templates
4. ✅ Run tests manually before releases

**Medium Term (Next Quarter):**
1. Identify 2-3 most stable tests
2. Add selective CI automation for those only
3. Keep complex tests manual
4. Add flakiness monitoring

**Long Term (Future):**
1. Consider unit tests for pure functions
2. Evaluate pytest-tmux for Python tests
3. Add performance benchmarks
4. Create visual regression suite

### The Bottom Line

**Don't over-engineer this.** Our current approach is solid and mirrors what major terminal projects do. The goal isn't 100% automated CI—it's having reliable, maintainable tests that catch regressions. We have that.

Focus on:
- Making tests more robust (better waits, retries)
- Better documentation of manual test process
- Quick feedback loops for developers
- Stability over coverage

---

## References

### Projects Studied
- [tmux](https://github.com/tmux/tmux) - regress/ directory, PR #3962
- [Alacritty](https://github.com/alacritty/alacritty) - vtebench
- [WezTerm](https://github.com/wezterm/wezterm) - terminal emulation tests
- [Zellij](https://github.com/zellij-org/zellij) - PTY handling

### Tools & Libraries
- [pexpect](https://github.com/pexpect/pexpect) - Python PTY automation
- [pytest-tmux](https://github.com/rockandska/pytest-tmux) - pytest plugin for tmux
- [tmux-test](https://github.com/tmux-plugins/tmux-test) - tmux plugin testing
- [expect](https://www.nist.gov/services-resources/software/expect) - TCL-based automation
- [DejaGnu](https://www.gnu.org/software/dejagnu/) - GCC test framework
- [vttest](https://invisible-island.net/vttest/) - VT100/VT220 testing
- [esctest](https://gitlab.freedesktop.org/terminal-wg/esctest) - Automated VT tests
- [ShellSpec](https://shellspec.info/) - BDD for shell scripts
- [BATS](https://github.com/bats-core/bats-core) - Bash testing framework

### Articles & Discussions
- [Gamlor's Blog: Creating Pseudo Terminals for Test Scripts with tmux](https://gamlor.info/posts-output/2022-08-29-using-tmux-for-pty-scripts/en/)
- [Has anyone found a robust way to test interactive CLI programs?](https://lobste.rs/s/qfbqsj/has_anyone_found_robust_way_test)
- [tmux-users: Using tmux for testing](https://groups.google.com/g/tmux-users/c/QEsOgQGOPa8)
- [Stack Exchange: Does TMUX have unit tests?](https://unix.stackexchange.com/questions/125637/does-tmux-have-unit-tests-or-a-test-suite)

### Key Insight
> "Thanks but I don't think I want these tests run on every commit, they are not 100% reliable, it is better if they are run manually."
> — Nicholas Marriott (tmux maintainer), August 2024

This validates our cautious approach to CI automation.

---

**Document maintained by:** lazy-llm team
**Last updated:** 2025-11-06
**Next review:** After Phase 1 implementation
