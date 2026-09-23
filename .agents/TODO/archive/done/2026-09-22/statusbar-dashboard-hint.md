---
slug: statusbar-dashboard-hint
title: Add a status-bar reminder of the dashboard keybinding
priority: P2
status: done
created: 2026-09-22_04:37
updated: 2026-09-22_05:14
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

- [x] A short, static "open dashboard" hint (naming the actual bound key, `Prefix+S`)
      appears in the tmux status bar whenever the current window is a lazy-llm
      workspace
- [x] Hint does not appear in non-lazy-llm tmux windows
- [x] No additional `tmux` shell-outs added to the status-bar refresh path (fold into
      `llm-status`'s existing single invocation)
- [x] Existing `llm-status` glyph output (working/idle/waiting glyphs) unchanged aside
      from the appended hint

## Work Report

**Date:** 2026-09-22_05:13

### What was done
- Appended a static `S:dash` hint to both of `llm-status`'s already-lazy-llm-gated
  output branches (single-pane, multi-pane) — no new tmux shell-outs.
- **Discovered and fixed a real prerequisite gap**: `llm-status` was never actually
  invoked anywhere in this live tmux config. It's a fully working, previously-tested
  binary that the README documents as available for `status-right`, but nothing
  wired it in — the status glyphs it's designed to show (and now this hint) have
  never been visible to the user until this task. Added `#(llm-status)` to
  `tmux_conf_theme_status_right` in `dev-env`'s
  `dotfiles/tmux/.config/tmux/tmux.conf.local`, matching that file's existing pattern
  of embedding status tokens (e.g. `#{prefix_highlight}`) directly in the theme
  template.
- Updated README.md's Status Detection section to document both the hint and where
  it's wired.

### How it was done
- Grepped the entire `dev-env` repo for `llm-status` usage to confirm it genuinely
  wasn't wired anywhere (not in tmux.conf, not in `lazy-llm`'s own launcher script,
  not in `install.sh`) before assuming and fixing — the discovery, not an assumption.
- Live-tested `llm-status`'s new output directly against three real contexts:
  a genuinely multi-pane lazy-llm workspace, a genuinely single-pane one, and a
  freshly-created plain (non-lazy-llm) tmux window — confirmed the hint appears
  correctly in the first two and the output is genuinely empty (not just visually
  blank) in the third.
- Reloaded the live tmux config (`tmux source-file`) after the wiring change —
  confirmed a clean reload (exit 0, no config errors) and that `#(llm-status)` now
  appears in the live `status-right` option.
- Confirmed `status-interval 10` (this repo's actual setting — the README's existing
  "default 15s" is describing tmux's own upstream default, not this project's
  override; left as-is, out of this task's scope) means the hint refreshes
  automatically without user action.

### Decisions made
- **`S:dash`** as the hint text — compact, names the actual key (`S`) and the target
  (dashboard), consistent with this status theme's existing short glyph/label style
  (`↗` for mouse, `⚇` for many-attached, etc.).
- **Fixed the wiring gap rather than working around it** — folding the hint into
  `llm-status`'s output would have been a no-op deliverable if `llm-status` itself
  was never called; the task's own acceptance criteria ("appears in the tmux status
  bar") could not have been satisfied without this.
- **Placed `#(llm-status)` at the front of `status-right`**, closest to the window
  list — the most likely place to catch attention for a "don't forget this
  keybinding" reminder, ahead of the more peripheral battery/clock/hostname segments.

### Commits
- `0b35118` (`external/lazy-llm` repo) — llm-status: add a static Prefix+S dashboard reminder
- `aa4d547` (`dev-env` repo) — tmux: wire llm-status into status-right (was never actually invoked)

### Files changed
- `llm-status-bin/.local/bin/llm-status` — hint appended to both output branches
- `README.md` — Status Detection section
- `dotfiles/tmux/.config/tmux/tmux.conf.local` (`dev-env` repo) — `#(llm-status)` wired into `tmux_conf_theme_status_right`

### Follow-up
- None filed.

## Verify Plan

Self-verified inline (per the note on `dashboard-workspace-nomenclature`).

1. Confirm `llm-status` was genuinely unwired before assuming a fix was even needed
2. Live-test the new hint against multi-pane, single-pane, and genuinely-plain
   (non-lazy-llm) tmux contexts
3. Reload the live tmux config, confirm no errors, confirm the wiring is live
4. Full test suite, no regression

## Verify Report

**Date:** 2026-09-22_05:14

1. ✅ Repo-wide grep for `llm-status` across `dev-env` found it in the binary itself,
   docs, and this task's own files — nowhere in any tmux config or launcher script.
   Confirmed a real, previously-invisible gap rather than assuming one.
2. ✅ Multi-pane workspace (`dev-dev-env-claude`): hint present. ✅ Single-pane
   workspace (`dev-microdots_digital-claude`): `AI: claude◐  S:dash`. ✅ Fresh plain
   tmux session created specifically for this test: genuinely empty output (not
   visually-blank-but-technically-present — checked the raw captured stdout)
3. ✅ `tmux source-file ~/.config/tmux/tmux.conf` exits 0, no errors. ✅
   `tmux show-options -g status-right` confirms `#(llm-status)` is present in the
   live option value post-reload
4. ✅ `./tests/test-runner.sh`: 6 passed / 8 failed, identical to baseline

One limitation: I could not literally screenshot the rendered terminal status bar
through available tooling (status-line `#()` job substitution is evaluated by tmux's
internal render loop, not reproducible via `capture-pane`, which only captures pane
content, or `display-message`, which returns the unexpanded format string). Confidence
instead rests on: `llm-status` itself proven correct via direct invocation matching
tmux's own invocation context, the `#()` job-substitution mechanism being the exact
same one already used elsewhere in this same config file (username/hostname segments),
and a clean config reload.

## Verification recipe

```bash
./llm-status-bin/.local/bin/llm-status   # run from inside a lazy-llm workspace pane —
                                          # output should include both the existing
                                          # glyph info and the new dashboard hint
# From a plain (non-lazy-llm) tmux window, confirm the hint is absent
tmux refresh-client -S   # force status bar redraw, visually confirm placement/legibility
```
