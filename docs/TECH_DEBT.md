# Technical Debt & Known Issues

 

This document tracks technical debt, known issues, and potential improvements for lazy-llm.

 

## High Priority

 

### 1. Tmux Pane Reference Resilience

 

**Issue**: Pane references use indices instead of IDs, making them fragile to manual pane operations.

 

**Current Behavior**:

- ✅ Works correctly for normal usage (no manual pane manipulation)

- ✅ Handles multiple windows in same session (uses window-scoped user options)

- ✅ Dynamically detects base-index and pane-base-index settings

- ❌ Breaks when users manually reorder, kill, or create panes

- ❌ Relies on specific 3-pane layout assumptions

 

**Root Cause**:

- Code stores pane **indices** (0, 1, 2) in `@AI_PANE` and `@PROMPT_PANE`

- Pane indices change when panes are reordered/deleted

- Pane **IDs** (%0, %1, %2) persist through layout changes but aren't being used

 

**Example of Brittleness**:

```bash

# Initial setup:

# @AI_PANE = "session:0.0"

# @PROMPT_PANE = "session:0.2"

 

# User manually swaps pane 0 and pane 1

# Now AI tool is at index 1, but @AI_PANE still points to index 0

# llm-send now sends to wrong pane!

```

 

**Impact**:

- Medium severity: Affects advanced users who manually manage tmux layouts

- Low frequency: Most users don't manually reorganize panes

- Confusing when it happens: Commands send to wrong panes silently

 

**Proposed Solution**:

 

**Option A: Use Pane IDs (Recommended)**

```bash

# During setup in lazy-llm:

AI_PANE_ID=$(tmux display-message -t "$session:$win_idx.$ai_pane" -p '#{pane_id}')

tmux set-option -w -t "$session:$win_idx" @AI_PANE_ID "$AI_PANE_ID"

 

# In llm-send:

AI_PANE_ID=$(tmux show-option -wv -t "$_session:$_window" @AI_PANE_ID 2>/dev/null)

TARGET="${AI_PANE_ID:-:.+}"

```

 

**Benefits**:

- Pane IDs persist through reordering

- Fully resilient to layout changes

- Simple implementation change

 

**Option B: Pane Title Discovery**

```bash

# Find pane by title instead of stored reference

AI_PANE=$(tmux list-panes -t "$_session:$_window" -F '#{pane_id}:#{pane_title}' | grep 'AI:' | cut -d: -f1)

```

 

**Benefits**:

- No storage needed

- Auto-discovers panes

- Works after any layout change

 

**Drawbacks**:

- Slower (needs to scan panes each time)

- Requires pane titles to be set correctly

- Fails if user renames panes

 

**Option C: Hybrid Approach**

1. Store pane IDs as primary reference

2. Fall back to pane title discovery if ID not found

3. Fall back to index-based for backwards compatibility

 

**Recommended**: Option A (pane IDs) for simplicity and performance.

 

**Implementation Checklist**:

- [ ] Update `lazy-llm` to store pane IDs in `@AI_PANE_ID` and `@PROMPT_PANE_ID`

- [ ] Update `llm-send` to use pane IDs

- [ ] Update `llm-append` to use pane IDs

- [ ] Update `llm-pull` to use pane IDs

- [ ] Update nvim plugin to use pane IDs

- [ ] Add migration logic for existing sessions (detect old format, update to new)

- [ ] Add validation: check if pane ID still exists before using

- [ ] Update documentation

- [ ] Add tests for pane reordering scenarios

 

**Estimated Effort**: 4-6 hours

 

**Files to Modify**:

- `lazy-llm-bin/.local/bin/lazy-llm` (lines 223-225)

- `llm-send-bin/.local/bin/llm-send` (lines 4-16)

- `llm-send-bin/.local/bin/llm-append` (lines 15-27)

- `llm-send-bin/.local/bin/llm-pull` (lines 7-17)

- `nvim-llm-send-plugin/.config/nvim/lua/plugins/llm-send.lua` (pane detection logic)

 

---

 

## Medium Priority

 

### 2. Autosubmit Reliability Issues

 

**Issue**: Autosubmit (final Enter keypress) works inconsistently across different AI TUI tools.

 

**Current Status**:

- ✅ **Claude Code**: Mostly reliable, occasional failures (~10%)

- ❌ **Gemini CLI**: Intermittent failures (~40%)

- ❌ **Grok (unofficial)**: Mangles multi-line pastes, autosubmit unreliable

- ⚠️ **Codex**: Needs more testing

 

**Symptoms**:

- Prompt appears in AI pane with markers but no response

- User must manually press Enter to submit

- Breaks workflow automation

 

**Investigation Notes**:

From `docs/TODO.md`:

- Refactored to use single-string approach (avoids intermediate Enter keypresses)

- Added delays for large pastes (>1KB gets 0.5s delay)

- Copy-mode exit before sending to prevent conflicts

- Still experiencing failures

 

**Theories**:

1. **Timing issues**: AI tool not ready to receive Enter

2. **Input buffering**: Tool buffers input differently

3. **Terminal escape sequence handling**: Tools interpret paste mode differently

4. **Tool-specific quirks**: Each tool has different input handling

 

**Potential Solutions**:

1. **Adaptive delays**: Detect tool type, apply tool-specific delays

2. **Wait for prompt**: Wait for AI tool to show ready prompt before Enter

3. **Retry logic**: Send Enter again if no response detected after timeout

4. **Paste mode bracketing**: Use tmux bracketed paste mode

5. **Tool-specific send strategies**: Different approach per tool

 

**Next Steps**:

- [ ] Instrument `llm-send` with debug logging

- [ ] Capture timing of all operations

- [ ] Test with different AI tools systematically

- [ ] Analyze tool input handling (strace, etc.)

- [ ] Implement tool detection and adaptive strategies

 

**Related**: Integration test suite can help identify patterns

 

---

 

### 3. Gemini CLI Truncation Bug

 

**Issue**: Gemini CLI repeats prompts 6-8 times when sending multi-paragraph text.

 

**Status**: Documented in integration tests (`tests/integration/scenarios/gemini/02-truncation-bug.sh`)

 

**Example**:

```

### PROMPT 2025-11-05-15:30:00

[User's multiline prompt]

### END PROMPT

 

### PROMPT 2025-11-05-15:30:00

[TRUNCATED REPETITION 1]

### END PROMPT

 

### PROMPT 2025-11-05-15:30:00

[TRUNCATED REPETITION 2]

### END PROMPT

 

... (repeats 6-8 times)

```

 

**Impact**:

- Makes Gemini CLI effectively unusable with lazy-llm

- Response pull (`llm-pull`) cannot extract correct response

- Visual clutter makes output unreadable

 

**Root Cause**: Unknown - likely Gemini CLI bug

 

**Potential Workarounds**:

1. Limit prompt size for Gemini

2. Use different send strategy (multiple smaller sends?)

3. Report to Gemini CLI team

4. Wait for upstream fix

 

**Priority**: Medium (affects one tool, workaround is "use Claude instead")

 

---

 

### 4. Gemini Marker Line Breaking

 

**Issue**: Gemini CLI doesn't properly handle newlines around `### PROMPT` and `### END PROMPT` markers.

 

**Status**: Documented in `tests/integration/scenarios/gemini/03-marker-linebreaks.sh`

 

**Symptoms**:

- Markers not on their own lines

- Response starts mid-line after END PROMPT

- Makes response extraction unreliable

 

**Impact**:

- `llm-pull` cannot reliably extract responses

- Breaks the annotation workflow

 

**Related to**: Issue #3 (may be same underlying problem)

 

---

 

## Low Priority

 

### 5. Mode-Specific Sending

 

**Issue**: Want to send prompts to specific Claude Code modes (code vs chat).

 

**Status**: Blocked by upstream - waiting for Claude CLI to support `--mode` flag

 

**Documented**: `docs/WISHLIST.md`, `docs/MODE_SPECIFIC_SEND.md`

 

**Priority**: Low (nice to have, not critical)

 

---

 

### 6. Enhanced Response Pull

 

**Issue**: `llm-pull` could support more options for partial response extraction.

 

**Requested Features**:

- `-n <num>` - Get last N responses

- `-r <range>` - Get specific response range

- Better metadata (which AI generated response, timestamp, etc.)

 

**Documented**: `docs/TODO.md`

 

**Priority**: Low (current functionality works for main use case)

 

---

 

### 7. Plugin Modularization

 

**Issue**: `nvim-llm-send-plugin/.config/nvim/lua/plugins/llm-send.lua` is ~525 lines, could be split into feature modules.

 

**Proposed Structure**:

```

lua/plugins/llm-send/

├── init.lua           # Plugin setup and keymaps

├── send.lua          # Sending functionality

├── pull.lua          # Response pulling

├── markers.lua       # Marker/extmark handling

├── completion.lua    # @ path completion

└── context.lua       # Context picker (llmr/llmR)

```

 

**Benefits**:

- Easier to maintain

- Clearer separation of concerns

- Easier to test individual features

 

**Priority**: Low (works fine as-is, this is just code organization)

 

---

 

## Testing Infrastructure

 

### Headless Environment Limitations

 

**Issue**: Integration tests cannot run in headless environments due to tmux requiring a PTY.

 

**Current Status**:

- Unit tests (mock AI tool) work fine

- Integration tests fail with "open terminal failed: not a terminal"

 

**Research Needed**:

- Tools for headless tmux testing (tmux-test, expect, etc.)

- CI/CD strategies for TUI testing

- Alternative testing approaches

 

**Documented**: See "Headless Testing Alternatives" research below

 

**Priority**: Medium (limits CI/CD capabilities)

 

---

 

## Future Enhancements

 

See `docs/FUTURE_FEATURES.md` for roadmap:

- Response code block actions

- Prompt templates/snippets

- Multi-shot prompting

- Workspace state capture

- Git-based conversation branching

 

---

 

## Maintenance Tasks

 

### Regular Cleanups

 

These work correctly but could be improved:

 

1. **Swap file cleanup**: Works but could be more intelligent

   - Currently: Delete after recovery or 30 days

   - Could: Detect truly orphaned vs. active session swaps

 

2. **Prompt file retention**: 7 days is arbitrary

   - Could: User-configurable retention period

   - Could: Archive old prompts instead of deleting

 

3. **Error handling**: Most scripts handle errors, but could be more robust

   - Add better error messages for common failure modes

   - Graceful degradation when tmux features unavailable

 

---

 

## Notes

 

- Priority levels: High (affects core functionality), Medium (affects specific use cases), Low (nice to have)

- Estimated efforts are rough and should be refined during implementation planning

- Some issues are blocked by upstream dependencies (Gemini CLI, Claude CLI)

- Integration test suite helps document and reproduce these issues systematically
