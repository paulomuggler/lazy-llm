---
slug: statusbar-dashboard-hint
title: Add a status-bar reminder of the dashboard keybinding
priority: P2
status: pending
created: 2026-09-22_04:37
updated: 2026-09-22_04:37
depends-on: [dashboard-workspace-nomenclature]
tags: [ux, discoverability, statusbar, tmux]
commits: []
model: sonnet
---

# Add a status-bar reminder of the dashboard keybinding

## Context

lazy-llm's tmux config is entirely keyboard-driven with no LazyVim-style persistent
keymap display (`which-key`-equivalent), so the dashboard's `Prefix+S` binding is easy
to forget between sessions. The user explicitly said the main friction is *remembering
the keybinding to open the dashboard* — solve that narrowly and cheaply here rather than
via a bigger which-key-style system.

`llm-status` (`llm-status-bin/.local/bin/llm-status`) already renders AI pane status
into `tmux status-right` (wired via `#(llm-status)` — confirm exact wiring location,
likely in `dotfiles/tmux/.config/tmux/tmux.conf.local` or a lazy-llm-owned config
fragment; grep for `llm-status` in tmux config to find it). Add a short static hint
alongside it, visible only in lazy-llm windows (gated the same way the existing
`@AI_PANES` check gates other lazy-llm-only UI, so plain tmux windows don't show a
dashboard hint that does nothing there).

## Design

- Append a short fixed string to `llm-status`'s output, e.g. `⌘S` or `[S: dashboard]` —
  pick something compact; status-right is already fairly busy (mouse/pairing/battery/
  clock/hostname per `tmux.conf.local:250`) so don't add a full sentence.
- Only show it when the window is a lazy-llm workspace (i.e. `@AI_PANES`/`@AI_TOOL` is
  set — `llm-status` already exits early via `lazy_llm_resolve_pane`/
  `lazy_llm_resolve_session_window` when it isn't, so the hint should live inside that
  same gated path, not before it).
- Keep it static text, not another `tmux capture-pane` call — this must stay cheap since
  it runs on every `status-interval` tick (default 15s, per README's Status Detection
  section).

## Key Files

- `llm-status-bin/.local/bin/llm-status` — append the hint string to existing output
- `dotfiles/tmux/.config/tmux/tmux.conf.local` (parent `dev-env` repo) — only if the
  hint needs its own status-right segment rather than living inside `llm-status`'s
  single `#()` call; prefer folding it into `llm-status`'s existing output to avoid a
  second shell-out per status-bar refresh

## Acceptance Criteria

- [ ] A short, static "open dashboard" hint (naming the actual bound key, `Prefix+S`)
      appears in the tmux status bar whenever the current window is a lazy-llm
      workspace
- [ ] Hint does not appear in non-lazy-llm tmux windows
- [ ] No additional `tmux` shell-outs added to the status-bar refresh path (fold into
      `llm-status`'s existing single invocation)
- [ ] Existing `llm-status` glyph output (working/idle/waiting glyphs) unchanged aside
      from the appended hint

## Verification recipe

```bash
./llm-status-bin/.local/bin/llm-status   # run from inside a lazy-llm workspace pane —
                                          # output should include both the existing
                                          # glyph info and the new dashboard hint
# From a plain (non-lazy-llm) tmux window, confirm the hint is absent
tmux refresh-client -S   # force status bar redraw, visually confirm placement/legibility
```
