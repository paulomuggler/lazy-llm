# DevEnv Feature Wishlist

This document tracks feature ideas that are currently blocked by upstream dependencies or technical limitations. These are good ideas worth implementing when the blockers are resolved.

---

## Mode-Specific LLM Send

**Status:** 🔴 Blocked - Waiting for upstream feature

**What:** Send prompts to Claude Code in a specific mode (Normal, Plan, Auto-Accept) via keymaps without manual mode switching.

**Desired UX:**
```
User in nvim prompt buffer:
"Refactor this component"

Keys pressed:
- <leader>lsp  → Send directly to Claude in Plan Mode
- <leader>lsn  → Send directly to Claude in Normal Mode
- <leader>lsa  → Send directly to Claude in Auto-Accept Mode
```

**Why it's valuable:**
- Eliminate context switching (no manual Shift+Tab cycling)
- Workflow optimization (user knows upfront which mode they want)
- Consistency (same prompt buffer workflow for all modes)

**Current blockers:**
1. **No CLI flag for mode selection**
   - Feature requested: [anthropics/claude-code#2667](https://github.com/anthropics/claude-code/issues/2667)
   - Status: Closed with "use settings.json" workaround
   - Need: `claude --mode plan` or similar

2. **Settings require restart**
   - `~/.claude/settings.json` only applies on startup
   - Cannot change mode mid-session without losing context

3. **No programmatic mode detection**
   - Cannot query Claude's current mode from scripts
   - Shift+Tab automation is non-deterministic (must know starting mode)

**Workarounds considered (and why they don't work):**
- ❌ **Multi-pane approach**: 3x resource usage, context fragmentation between panes
- ❌ **Tmux Shift+Tab automation**: Brittle, race conditions, no verification
- ❌ **Config toggle + restart**: Loses conversation context
- ⚠️ **Manual mode switching**: Works but defeats the purpose (not automated)

**What we need from upstream:**
- `claude --mode <normal|plan|auto-accept>` CLI flag
- Or: `claude set-mode <mode>` command that works mid-session
- Or: Programmatic mode query/control API

**Implementation plan when unblocked:**
Once CLI flag or API is available:
1. Extend `llm-send.lua` to accept mode parameter
2. Invoke Claude with `--mode` flag when sending
3. Add keymaps: `<leader>lsn`, `<leader>lsp`, `<leader>lsa`
4. Document usage in `WORKSPACE.md`

**Watch for:**
- GitHub issues/PRs mentioning "mode", "--mode", or "cli flag"
- Claude Code release notes about mode control
- Community workarounds that emerge

**Related documentation:**
- Full research: `docs/MODE_SPECIFIC_SEND.md`
- Claude Code docs: https://docs.claude.com/en/docs/claude-code/interactive-mode

---

## Future Wishlist Items

(Add more blocked/future features here as they come up)

### Template: Feature Name

**Status:** 🔴 Blocked | 🟡 Under Consideration | 🟢 Ready to Implement

**What:** Brief description

**Why it's valuable:** User benefit

**Current blockers:** What's preventing implementation

**What we need:** Dependencies or changes required

**Implementation plan when unblocked:** High-level steps

---

**Document Version:** 1.0
**Created:** 2025-10-22
**Purpose:** Track good ideas that can't be implemented yet
