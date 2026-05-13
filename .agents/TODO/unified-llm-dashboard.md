---
slug: unified-llm-dashboard
title: Unified lazy-llm dashboard popup (sessions / panes / worktrees tabs)
priority: P1
status: pending
created: 2026-05-13
updated: 2026-05-13
depends-on: [fix-llm-sessions-marker-bug]
tags: [enhancement, dashboard, tui, llm-sessions, llm-panes, status-detection]
commits: []
---

# Unified lazy-llm dashboard popup (sessions / panes / worktrees tabs)

## Context

Today we have two separate popups under two separate tmux prefix bindings:
- `Prefix+S` → `llm-sessions` (session manager)
- `Prefix+L` → `llm-panes` (pane manager)

We want to consolidate these into a **single dashboard popup under one tmux prefix binding**, with multiple tabs/views inside it. Once inside the popup, we own all keystrokes — so we can use dense single-letter bindings freely without polluting the global tmux/nvim keymap. This avoids burning further top-level prefix slots.

Inspiration: `nielsgroen/claude-tmux`'s ratatui dashboard — a list with **live ANSI-color preview** of the selected entry's pane content.

Tabs to ship in this task:
1. **Sessions** — list lazy-llm sessions with status indicators + live preview of the active AI pane
2. **Panes** — for the current session, list AI panes with the same status + preview treatment
3. **Worktrees** — placeholder/empty for now (content lives in [[worktree-bridge-tab]] which depends on this task)

### Architecture

- One entrypoint script (working name: `llm-dashboard`) launched by `tmux display-popup -E`
- Tab switching via single-letter bindings (e.g. `1`/`2`/`3` or `Tab`/`Shift-Tab`)
- Shared status-detection helper in `lazy-llm-lib.sh`:
  - `lazy_llm_detect_pane_status <pane_id> [tool]` → `working|idle|waiting|unknown`
  - Per-tool regex table (claude, gemini, codex, grok, aider) so detection isn't Claude-only
- Live preview using `tmux capture-pane -p -e -t <pane>` (ANSI-rendered) with periodic refresh
- Implementation evaluated during planning: `fzf --preview` with a refresher, `gum`, or a custom bash TUI using `tput` + alternate screen. Avoid adding a Rust/Go binary unless bash approaches prove inadequate.

### Keybinding consolidation

- Retire `Prefix+L` (panes) — folded into the dashboard's Panes tab
- Repurpose `Prefix+S` (sessions) → opens the unified dashboard at the Sessions tab (default)
  - Or pick a different single key during planning; the only hard constraint is **no new top-level prefix bindings**
- Within the dashboard: dense single-letter bindings only (see [[dense-keybindings-popup-scopes]])

### Status detection (port from claude-tmux, generalize)

Per-tool regex table; default patterns for Claude:
- **Working:** input prompt glyph (`❯`) + "ctrl+c to interrupt" hint
- **Idle:** input prompt glyph without interrupt hint
- **Waiting:** contains `[y/n]` / `[Y/n]` / numbered choice prompts
- **Unknown:** anything else

`llm-status` should consume the same helper so the tmux statusline glyphs (e.g. `[claude●] gemini◐`) stay consistent with the dashboard.

## Key Files

- `lazy-llm-bin/.local/bin/llm-sessions` — fold into dashboard or rewrite as the dashboard entrypoint
- `lazy-llm-bin/.local/bin/llm-panes` — fold in / retire as a separate binary
- `lazy-llm-bin/.local/bin/llm-status` — consume the new detection helper
- `lazy-llm-bin/.local/bin/lazy-llm-lib.sh` — add `lazy_llm_detect_pane_status` helper + per-tool pattern table
- `lazy-llm-bin/.local/bin/lazy-llm` — tmux key binding definitions (`Prefix+S`, retire `Prefix+L`), popup launch invocation; help text update
- `README.md` / `USAGE.md` — document the unified dashboard, deprecate references to standalone `llm-sessions`/`llm-panes`

## Acceptance Criteria

- [ ] Status detection helper in `lazy-llm-lib.sh` with per-tool pattern table; returns `working|idle|waiting|unknown`
- [ ] `llm-status` uses the helper; tmux statusline shows status glyphs per AI tool
- [ ] New unified dashboard launches as a tmux popup under a single prefix binding (consolidating the prior `Prefix+S` and `Prefix+L`)
- [ ] Dashboard has at least 3 tabs: Sessions, Panes, Worktrees (Worktrees can be a "Coming soon" placeholder pending [[worktree-bridge-tab]])
- [ ] Tab switching via single-letter / number / `Tab` keys (decide during planning)
- [ ] Sessions tab: list of lazy-llm sessions with status indicators, live ANSI preview of the selected session's active AI pane, actions for switch / kill / new / rename / filter (single-letter bindings only)
- [ ] Panes tab: list of AI panes in the current session with status indicators + preview + cycle/add/remove actions
- [ ] Preview refresh interval reasonable (1–2s) without noticeable flicker
- [ ] `Prefix+L` keybinding removed; legacy `llm-panes` script either retired or kept as a thin alias for `llm-dashboard --tab panes`
- [ ] Backwards-compat: `llm-sessions --list` (non-interactive) continues to work, or is replaced by an equivalent flag on the dashboard binary
- [ ] Tests in `tests/` cover status-detection regexes at minimum (input fixtures → expected status)
- [ ] README + USAGE updated; keybinding tables reflect the new unified dashboard
- [ ] Manual verify: with 2+ lazy-llm sessions running, opening the dashboard shows both with statuses; switching tabs works; preview renders ANSI colors live; all actions reachable by single-letter keys
