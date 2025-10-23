# Mode-Specific LLM Send Feature Specification

## Overview

### Problem Statement

Claude Code operates in three distinct permission modes:
1. **Normal Mode** - Standard operation with confirmation prompts
2. **Plan Mode** - Claude presents a plan for approval before execution
3. **Auto-Accept Mode** - Claude automatically executes commands without approval

Currently, users must:
1. Start Claude Code in default mode (or configured `defaultMode`)
2. Manually cycle modes with `Shift+Tab` or `Alt+M`
3. Then send their prompt

This creates friction when users know upfront which mode they want (e.g., always use Plan Mode for architecture questions, Normal Mode for debugging).

### Desired Workflow

```
User in nvim prompt buffer:
"Refactor this component to use hooks"

Keys pressed:
- <leader>lsp  → Send to Claude in Plan Mode (auto-switch before submit)
- <leader>lsn  → Send to Claude in Normal Mode
- <leader>lsa  → Send to Claude in Auto-Accept Mode
```

### Key Questions to Answer

1. **Feasibility**: Can we programmatically control Claude Code's mode?
2. **Detection**: Can we detect which mode Claude is currently in?
3. **Automation**: Can we simulate `Shift+Tab` via tmux to cycle modes?
4. **Reliability**: How do we ensure mode switch completed before sending prompt?

## Research Findings

### Mode Switching Mechanisms

#### 1. Configuration-Based (Persistent)

**Settings file: `~/.claude/settings.json`**
```json
{
  "permissions": {
    "defaultMode": "plan"  // Options: "normal", "plan", "auto-accept"
  }
}
```

**Characteristics:**
- ✅ Official, documented approach
- ✅ Persists across all sessions
- ❌ Not dynamic per-prompt
- ❌ Requires restarting Claude or editing config before each use

**Use case:** Set global default mode preference

#### 2. Interactive Keyboard Shortcut

**Shortcut: `Shift+Tab` or `Alt+M`**

Cycles through modes in order:
```
Normal → Auto-Accept → Plan → Normal → ...
```

**Characteristics:**
- ✅ Fast, interactive switching
- ✅ Visual feedback in UI (breadcrumb indicator)
- ❌ No direct "jump to mode X" command
- ❌ Must cycle through to reach desired mode

**Use case:** Manual mode switching during interactive sessions

#### 3. Command-Line Flag (Requested, Not Implemented)

**Proposed syntax:** `claude --plan` or `claude --mode plan`

**Status:** Feature request filed (Issue #2667), closed as "use settings.json instead"

**Characteristics:**
- ❌ Not currently available
- ❌ No timeline for implementation
- ✅ Would be ideal for scripted workflows

**Use case:** Would enable per-invocation mode selection

### UI Indicators

**Mode display:** Visual breadcrumb in TUI shows current mode
- "Normal Mode" or "Plan Mode" or "Auto-Accept Mode"
- Visible at top of interface

**Detection:** No known programmatic way to query current mode from external scripts

### Tmux Automation Possibilities

**Sending Shift+Tab to Claude pane:**
```bash
# Send Shift+Tab keystroke to specific tmux pane
tmux send-keys -t <pane_id> S-Tab
```

**Challenges:**
1. **Non-deterministic cycling**: Must know current mode to calculate how many `Shift+Tab` presses needed
2. **No mode detection**: Cannot query Claude's current mode from shell
3. **Timing issues**: Must wait for mode switch to complete before sending prompt
4. **Race conditions**: If Claude is processing, mode switch might be ignored

## Feasibility Assessment

### Approach 1: Tmux Keystroke Simulation (Brittle)

**Implementation:**
```bash
# Attempt to force Plan Mode by cycling
send_to_plan_mode() {
  local pane_id="$1"

  # Blind approach: Press Shift+Tab twice (assuming we're in Normal)
  # Normal → Auto-Accept → Plan
  tmux send-keys -t "$pane_id" S-Tab
  sleep 0.2
  tmux send-keys -t "$pane_id" S-Tab
  sleep 0.2

  # Now (hopefully) in Plan Mode
}
```

**Assessment:**
- 🔴 **Brittle**: Breaks if Claude is already in different mode
- 🔴 **No verification**: Cannot confirm mode switch succeeded
- 🔴 **Timing-dependent**: Race conditions likely
- 🟡 **Might work**: For personal use if you always start in known mode

**Verdict:** Not recommended for reliable automation

### Approach 2: Config File Toggle (Semi-Dynamic)

**Implementation:**
```lua
-- llm-send.lua enhancement
function send_with_mode(prompt, mode)
  -- 1. Read current ~/.claude/settings.json
  -- 2. Modify permissions.defaultMode to desired mode
  -- 3. Write settings back
  -- 4. Restart Claude Code (or send special command to reload config?)
  -- 5. Send prompt
  -- 6. Restore original settings
end
```

**Assessment:**
- 🔴 **Requires restart**: Settings only apply on Claude startup
- 🔴 **Session interruption**: Kills active conversation context
- 🔴 **Complex orchestration**: Manage Claude process lifecycle
- 🔴 **Slow**: Multi-second delay for restart

**Verdict:** Not viable for seamless workflow

### Approach 3: Multiple Claude Sessions (Workaround)

**Implementation:**
```bash
# Run 3 separate Claude Code instances in different panes
tmux split-window -h "claude"  # Pane 1: Normal mode (default)
tmux split-window -h "claude"  # Pane 2: Plan mode (via settings.json override)
tmux split-window -h "claude"  # Pane 3: Auto-accept (via settings.json override)
```

**Configuration:**
- Create 3 different config files:
  - `~/.claude/settings-normal.json`
  - `~/.claude/settings-plan.json`
  - `~/.claude/settings-auto.json`
- Use `CLAUDE_CONFIG_PATH` env var (if exists) or symlink hack

**Assessment:**
- 🟡 **Parallel sessions**: Each pane locked to one mode
- 🔴 **High overhead**: 3x memory/API usage
- 🔴 **Context fragmentation**: Conversations split across instances
- 🟡 **Might work**: If config path is customizable

**Verdict:** Possible but inefficient

### Approach 4: Wait for Official CLI Flag (Future)

**Timeline:** Unknown, feature request closed with "use settings.json"

**Assessment:**
- 🟢 **Clean solution**: `claude --mode plan < prompt.txt`
- 🟢 **No hacks needed**: Official, supported
- 🔴 **Not available now**: Cannot implement today
- 🟡 **Monitor**: Watch GitHub issues for implementation

**Verdict:** Best long-term solution, unavailable now

### Approach 5: Hybrid - Smart Config Management (Recommended)

**Concept:**
- Keep separate workspace configs for different use cases
- Quick switch before launching Claude session
- Use one mode per session (accept this constraint)

**Implementation:**
```bash
# DevEnv helper scripts
claude-plan() {
  # Set plan mode, launch Claude in current dir
  echo '{"permissions": {"defaultMode": "plan"}}' > ~/.claude/settings.json
  claude
}

claude-auto() {
  # Set auto-accept, launch Claude
  echo '{"permissions": {"defaultMode": "auto-accept"}}' > ~/.claude/settings.json
  claude
}

claude-normal() {
  # Set normal mode (or omit for default)
  rm ~/.claude/settings.json  # Or set to "normal"
  claude
}
```

**llm-send Integration:**
```lua
-- llm-send.lua
-- Detect which Claude pane user is targeting
-- Send prompt to that pane (already in desired mode)
-- No mode switching attempted
```

**Assessment:**
- 🟢 **Works today**: Uses documented features
- 🟢 **Reliable**: No race conditions or guessing
- 🟡 **User adaptation**: Must choose mode when starting Claude
- 🟡 **Session-level granularity**: Cannot change mode mid-conversation easily

**Verdict:** Best viable approach given current limitations

## Recommended Implementation Plan

### Phase 1: Multi-Claude Session Support (Foundation)

**Goal:** Enable DevEnv to manage multiple Claude Code sessions with different modes

**Tasks:**
1. Create tmux session layout with 3 Claude panes:
   - Pane 1: Normal mode (default)
   - Pane 2: Plan mode
   - Pane 3: Auto-accept mode

2. Create shell helper functions:
   ```bash
   # dotfiles/shell/claude.sh
   claude-normal() { set_claude_mode "normal" && claude; }
   claude-plan()   { set_claude_mode "plan" && claude; }
   claude-auto()   { set_claude_mode "auto-accept" && claude; }

   set_claude_mode() {
     local mode="$1"
     cat > ~/.claude/settings.json <<EOF
   {
     "permissions": {
       "defaultMode": "$mode"
     }
   }
   EOF
   }
   ```

3. Document tmux layout in `WORKSPACE.md`

**Success criteria:**
- User can start Claude in any mode with one command
- Each mode runs in dedicated tmux pane

### Phase 2: Enhanced llm-send with Pane Selection

**Goal:** Send prompts to specific Claude pane (implicitly selecting mode)

**Tasks:**
1. Extend `llm-send.lua` to support target pane selection:
   ```lua
   -- llm-send.lua
   function send_to_claude_pane(pane_name, prompt)
     -- pane_name: "claude-normal", "claude-plan", "claude-auto"
     local pane_id = resolve_pane_id(pane_name)
     send_text_to_pane(pane_id, prompt)
   end
   ```

2. Add keymaps:
   - `<leader>lsn` → Send to Normal mode pane
   - `<leader>lsp` → Send to Plan mode pane
   - `<leader>lsa` → Send to Auto-accept pane
   - `<leader>ls`  → Send to default/last-used pane (current behavior)

3. Visual feedback: Show which pane/mode received prompt

**Success criteria:**
- User can send same prompt to different modes via keymap
- No mode switching required - pane already in correct mode

### Phase 3: Smart Pane Discovery (Optional)

**Goal:** Auto-detect available Claude panes and their modes

**Tasks:**
1. Query tmux for panes running `claude` command
2. Attempt to infer mode from pane title or status line
3. Fallback to user configuration if detection fails

**Success criteria:**
- Works even if user starts Claude manually
- Graceful degradation if panes not found

### Phase 4: Future - Integrate with Official CLI Flag (When Available)

**Goal:** Replace multi-pane workaround with native mode selection

**Tasks:**
1. Monitor GitHub issues for `--mode` flag implementation
2. Refactor `llm-send.lua` to use flag when available
3. Deprecate multi-pane approach in favor of single-pane + flag

**Success criteria:**
- Seamless migration when flag lands
- Zero user configuration changes needed

## Alternative: Current Workaround (Minimal Effort)

If full implementation is too complex, offer this simple enhancement:

### Quick Config Switcher

**Add to `dotfiles/shell/claude.sh`:**
```bash
# Quick mode switchers
claude-mode-plan() {
  cat > ~/.claude/settings.json <<'EOF'
{
  "permissions": {
    "defaultMode": "plan"
  }
}
EOF
  echo "✓ Claude mode set to PLAN. Restart Claude to apply."
}

claude-mode-normal() {
  cat > ~/.claude/settings.json <<'EOF'
{
  "permissions": {
    "defaultMode": "normal"
  }
}
EOF
  echo "✓ Claude mode set to NORMAL. Restart Claude to apply."
}

claude-mode-auto() {
  cat > ~/.claude/settings.json <<'EOF'
{
  "permissions": {
    "defaultMode": "auto-accept"
  }
}
EOF
  echo "✓ Claude mode set to AUTO-ACCEPT. Restart Claude to apply."
}
```

**User workflow:**
1. In shell: `claude-mode-plan`
2. Restart Claude Code
3. Use normal `<leader>ls` - now sends to plan mode

**Assessment:**
- 🟢 Zero code complexity
- 🟢 Uses official mechanisms
- 🔴 Requires manual restart
- 🟡 Good enough for infrequent mode changes

## Technical Challenges & Limitations

### Challenge 1: No Mode Detection API

**Problem:** Cannot query Claude's current mode from external scripts

**Impact:**
- Blind mode switching (must assume starting mode)
- Cannot verify mode switch succeeded
- No error handling if switch fails

**Mitigation:**
- Avoid mid-session mode switching
- Use session-level mode selection (Phase 1 approach)

### Challenge 2: Shift+Tab Cycling is Non-Deterministic

**Problem:**
```
If Claude is in Unknown Mode, how many Shift+Tabs to reach Plan Mode?
- If currently Normal: 2 presses (Normal → Auto → Plan)
- If currently Auto: 1 press (Auto → Plan)
- If currently Plan: 0 presses (already there)
```

**Impact:**
- Cannot reliably automate mode switching via Shift+Tab
- Risk of ending up in wrong mode

**Mitigation:**
- Do not attempt Shift+Tab automation
- Use config-based mode setting instead

### Challenge 3: Settings Require Restart

**Problem:** Changes to `~/.claude/settings.json` only apply on Claude startup

**Impact:**
- Cannot change mode mid-conversation
- Must restart Claude, losing context

**Mitigation:**
- Accept session-level granularity
- Design workflow around "start in correct mode" rather than "switch modes"

### Challenge 4: Multiple Sessions = Multiple Conversations

**Problem:** Running 3 Claude instances means 3 separate conversation contexts

**Impact:**
- Cannot easily share context between modes
- Inefficient resource usage (3x API calls)

**Mitigation:**
- Use sparingly - only activate mode-specific pane when needed
- Primary workflow in one pane, others for specialized tasks

## User Experience Design

### Proposed Keymaps

```lua
-- In nvim
<leader>ls   → Send to Claude (current/default mode)
<leader>lsn  → Send to Claude Normal Mode pane
<leader>lsp  → Send to Claude Plan Mode pane
<leader>lsa  → Send to Claude Auto-Accept Mode pane

-- Visual feedback after send
-- → "Sent to Claude (Plan Mode) ✓"
```

### Tmux Session Layout

```
┌─────────────────────────────────────────────────┐
│ Window 1: Dev Workspace                         │
├──────────────┬──────────────┬───────────────────┤
│              │              │                   │
│  Neovim      │  Claude      │  Shell/Logs       │
│  (Prompts)   │  (Normal)    │                   │
│              │              │                   │
│              │              │                   │
│              │              │                   │
└──────────────┴──────────────┴───────────────────┘

┌─────────────────────────────────────────────────┐
│ Window 2: Mode-Specific Claude (Optional)       │
├──────────────┬──────────────────────────────────┤
│              │                                  │
│  Claude      │  Claude                          │
│  (Plan Mode) │  (Auto-Accept)                   │
│              │                                  │
│              │                                  │
│              │                                  │
└──────────────┴──────────────────────────────────┘
```

**User behavior:**
- Primary work in Window 1 with Normal mode Claude
- Switch to Window 2 when specific mode needed
- Send from nvim to any pane via keymap

### Visual Feedback

**On send success:**
```
┌────────────────────────────────────┐
│ ✓ Sent to Claude (Plan Mode)      │
│   Pane: claude-plan.2              │
└────────────────────────────────────┘
```

**On send failure:**
```
┌────────────────────────────────────┐
│ ✗ Claude pane not found            │
│   Start Claude with: claude-plan   │
└────────────────────────────────────┘
```

## Implementation Recommendation

### Recommended Approach: Multi-Pane Sessions

**Why:**
- ✅ Works with current Claude Code features (no hacks)
- ✅ Reliable (no race conditions or guessing)
- ✅ Flexible (user chooses mode per session)
- ✅ Maintainable (uses documented APIs)

**Tradeoffs:**
- ⚠️ Requires running multiple Claude instances (higher resource usage)
- ⚠️ Session-level mode selection (not per-prompt)
- ⚠️ User must decide mode upfront when starting Claude

**User impact:**
- Minimal learning curve (start Claude in desired mode, send as usual)
- Clear mental model (each pane = one mode)
- No surprises (mode never changes unexpectedly)

### Not Recommended: Tmux Keystroke Automation

**Why avoid:**
- 🔴 Brittle and unreliable
- 🔴 No way to verify success
- 🔴 Race conditions inevitable
- 🔴 Hard to debug when it fails

## Next Steps

1. **Decide:** Accept session-level mode granularity vs. wait for CLI flag?
   - **Accept**: Implement Phase 1 (multi-pane approach)
   - **Wait**: Document workaround, defer feature until `--mode` flag lands

2. **If implementing:** Start with Phase 1
   - Create shell helpers for mode switching
   - Document tmux layout for multi-Claude setup
   - Test with daily workflows

3. **If waiting:** Minimal approach
   - Add shell functions for config switching
   - Document manual restart workflow
   - Monitor GitHub for `--mode` flag progress

4. **Future integration:** When CLI flag available
   - Refactor llm-send to use `claude --mode <mode> < prompt.txt`
   - Deprecate multi-pane workaround
   - Simplify to single-pane architecture

## Conclusion

**Mode-specific sending is feasible but constrained by Claude Code's current architecture.**

The lack of a `--mode` CLI flag and inability to query/change mode programmatically limits automation options. The most reliable approach is to:

1. Run Claude in desired mode from the start (via settings.json)
2. Use multiple Claude sessions in separate tmux panes for different modes
3. Enhance llm-send to target specific panes (implicitly selecting mode)

This provides the desired UX (keymap per mode) while working within Claude Code's current capabilities. When the `--mode` flag is eventually added, the implementation can be simplified to single-pane + dynamic mode selection.

**Status:** Feasible with workarounds. Recommend implementing Phase 1 (multi-pane) for immediate value, with plan to migrate to native CLI flag when available.

---

**Document Version:** 1.0
**Created:** 2025-10-22
**Status:** Research Complete - Awaiting Decision
**Related Issues:**
- [anthropics/claude-code#2667](https://github.com/anthropics/claude-code/issues/2667) - Feature request for --plan flag
- [anthropics/claude-code#2881](https://github.com/anthropics/claude-code/issues/2881) - defaultMode settings bug

**Next Decision Point:** Accept multi-pane approach or wait for official CLI flag?
