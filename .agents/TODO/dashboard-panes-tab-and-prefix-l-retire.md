---
slug: dashboard-panes-tab-and-prefix-l-retire
title: Dashboard panes tab + retire Prefix+L
priority: P2
status: in-progress
created: 2026-05-13
updated: 2026-05-13
depends-on: [dashboard-shell-and-sessions-tab]
tags: [enhancement, dashboard, llm-panes, keybindings, cleanup]
commits: [8504d66]
---

# Dashboard panes tab + retire Prefix+L

## Context

Third slice of the unified dashboard work. Add the **panes tab** to the dashboard (for the current session's AI panes: list + status glyphs + live preview + cycle/add/remove), then **retire `Prefix+L`** since the panes tab covers it. Either delete the standalone `llm-panes` script or keep it as a thin alias for `llm-dashboard --tab panes`.

This is the final consolidation step that completes the original `unified-llm-dashboard` vision: one popup binding, three tabs (sessions / panes / worktrees-placeholder), one entrypoint.

### Panes tab

Columns: pane index, tool name, pane ID, status glyph (from [[pane-status-detection]]), active marker.

Actions:
- `Enter` / `↵` — cycle to selected pane (becomes the visible AI pane)
- `a` — add new AI pane (existing `llm-add` flow, with tool picker)
- `K` — remove pane (with confirmation, existing `llm-remove` flow)
- `]` / `[` — cycle to next / prev pane without explicit selection
- `R` — refresh
- `q` / `Esc` — quit (or back to previous tab)
- Tab switching shared with sessions tab (`1`/`2`/`3`, `Tab`/`Shift-Tab`)

### Retiring `Prefix+L` and the standalone `llm-panes` script

Decide during planning:
- **Option A**: Delete `lazy-llm-bin/.local/bin/llm-panes` entirely; remove the `Prefix+L` binding.
- **Option B**: Keep `llm-panes` as a thin alias: `exec llm-dashboard --tab panes` (preserves muscle memory for anyone using it from the CLI); remove the `Prefix+L` binding.

In either case, the help text and READMEs must be cleaned up so neither documents the old binding.

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` (extend) — add panes tab
- `lazy-llm-bin/.local/bin/llm-panes` — delete or shrink to an alias
- `lazy-llm-bin/.local/bin/lazy-llm` — remove `Prefix+L` keybinding; update help text
- `README.md` / `USAGE.md` — remove all references to `llm-panes` / `Prefix+L`; add panes tab notes
- `tests/scenarios/` — extend dashboard tests to cover panes tab listing, switching, add/remove flows

## Acceptance Criteria

- [x] Panes tab implemented in `llm-dashboard` with columns: index, tool, status glyph, active marker, pane ID (5 fields, ID used by preview)
- [x] Panes tab actions: switch (Enter), add (`a`), remove+confirm (`K`), cycle next/prev (`]`/`[`), refresh (`R`), quit
- [x] Live preview pane shows ANSI tail of the highlighted AI pane via `{5}` field expansion to pane ID
- [x] `Prefix+L` keybinding removed from `lazy-llm`
- [x] `llm-panes` reduced to a 5-line alias for `llm-dashboard --tab panes`
- [x] README + USAGE no longer reference `Prefix+L` or `llm-panes` as a separate concept; panes tab documented
- [x] No regressions in `llm-add` / `llm-remove` / `llm-cycle` CLI commands (they're delegated to from dispatch; not modified)
- [x] Tests cover panes tab structural wiring: 12 assertions in `13-dashboard-panes-tab-unit.sh` covering alias shrink, Prefix+L retirement, --tab panes parsing, render function presence, action dispatch verbs, canonical detector usage, cross-tab routing, help text
- [ ] Manual verify: with 2+ AI panes in a session, opening the dashboard and switching to the Panes tab shows them with status glyphs; cycling via `Enter` or `]`/`[` swaps the visible pane; `a` adds a new pane via tool picker; `K` removes with confirmation
