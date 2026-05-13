---
slug: dashboard-shell-and-sessions-tab
title: Dashboard shell + sessions tab (live preview)
priority: P1
status: pending
created: 2026-05-13
updated: 2026-05-13
depends-on: [pane-status-detection]
tags: [enhancement, dashboard, tui, popup, llm-sessions]
commits: []
---

# Dashboard shell + sessions tab (live preview)

## Context

Second slice of the unified dashboard work. Build the **shell** (a new `llm-dashboard` script with a tabbed popup framework) and the **sessions tab** (list of lazy-llm sessions with status glyphs and a live ANSI-color preview pane). Keep `llm-panes` and `Prefix+L` untouched for now — no regression, panes tab lands in a follow-up.

Worktrees tab ships as a "Coming soon" placeholder so the framework is exercised by ≥2 tabs from day one (sessions + placeholder).

### Architecture

- New entrypoint: `lazy-llm-bin/.local/bin/llm-dashboard`
- Launched via `tmux display-popup -E` from the existing `Prefix+S` binding (which retargets from `llm-sessions` to `llm-dashboard`)
- Tab switching via single-letter / number / `Tab` keys (decide during planning)
- Live preview using `tmux capture-pane -p -e -t <pane>` (ANSI rendered) with periodic refresh (1–2s)
- Implementation: evaluate `fzf --preview` (lowest friction, may flicker), `gum`, or a custom bash TUI with `tput` + alternate screen. Avoid adding a new compiled binary unless absolutely needed.
- All bindings inside the popup are **dense single-letter only**, no Ctrl+ chords. Popup-scoped, no global keymap changes.

### Sessions tab

Columns: session name, directory, tools, window count, attached `*`, status glyph (from [[pane-status-detection]]).

Actions:
- `Enter` / `↵` — switch to session
- `n` — new session (launches `lazy-llm` nested popup)
- `K` — kill (with confirmation)
- `r` — rename
- `/` — filter
- `R` — refresh
- `1`/`2`/`3` or `Tab`/`Shift-Tab` — switch tabs
- `?` — help
- `q` / `Esc` — quit

### Worktrees tab (placeholder)

Shows a single line: "Worktrees tab — coming soon. See task worktree-bridge-tab."

This is enough to validate the tab framework and lets users discover the upcoming feature.

### Backwards compatibility

- Keep `lazy-llm-bin/.local/bin/llm-sessions` working (for `--list` and `--kill` CLI flags). The interactive mode (no args) can either keep working as before or be redirected to `llm-dashboard` — decide during planning.
- `llm-panes` and `Prefix+L` are completely untouched. Panes tab + retirement happen in [[dashboard-panes-tab-and-prefix-l-retire]].

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` (new) — main entrypoint
- `lazy-llm-bin/.local/bin/llm-sessions` — keep CLI flags working; possibly redirect interactive mode to `llm-dashboard`
- `lazy-llm-bin/.local/bin/lazy-llm` — repurpose `Prefix+S` binding to launch `llm-dashboard`; help text update
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — likely needs shared "list lazy-llm sessions" helper (currently lives inside `llm-sessions:gather_sessions`); refactor or expose
- `README.md` / `USAGE.md` — document the new dashboard and its sessions tab

## Acceptance Criteria

- [ ] New `llm-dashboard` script launches under `Prefix+S` (replaces the existing direct `llm-sessions` invocation)
- [ ] Dashboard shows at least two tabs: Sessions (functional) and Worktrees (placeholder line)
- [ ] Tab switching works via at least one of: single-letter keys (`1`/`2`), `Tab`/`Shift-Tab`, or arrow keys (decide during planning)
- [ ] Sessions tab columns: name, directory, tools, window count, attached marker, status glyph
- [ ] Live preview pane shows ANSI-rendered tail of the selected session's active AI pane; refresh interval reasonable (1–2s) without noticeable flicker
- [ ] Sessions tab actions: switch (Enter), new (`n`), kill+confirm (`K`), rename (`r`), filter (`/`), refresh (`R`), quit (`q`/`Esc`)
- [ ] No Ctrl+ chords used inside the dashboard (dense letter bindings only)
- [ ] `llm-panes` and `Prefix+L` continue to work unchanged
- [ ] `llm-sessions --list` and `llm-sessions --kill` continue to work unchanged
- [ ] Tests in `tests/scenarios/` cover: dashboard launch, sessions tab listing (mock tmux state), tab switching
- [ ] README + USAGE updated; old `Prefix+S → llm-sessions` documentation replaced with `Prefix+S → llm-dashboard`
- [ ] Manual verify: with 2+ lazy-llm sessions, `Prefix+S` opens the dashboard at the Sessions tab; both sessions appear with correct status glyphs; preview shows live ANSI of the highlighted session's AI pane; all single-letter actions work; `Esc` closes
