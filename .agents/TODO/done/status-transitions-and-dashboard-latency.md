---
slug: status-transitions-and-dashboard-latency
title: Fix stuck working/unread glyphs; cut dashboard fold/reorder latency to ~100ms
priority: P1
status: done
created: 2026-09-27_23:45
updated: 2026-09-28_00:05
depends-on: []
tags: [bug, status, dashboard, performance]
commits: [c8c4e6a, 984d630]
model: inline
---

# Fix stuck working/unread glyphs; cut dashboard fold/reorder latency

## Context

Reported: glyphs don't always go working -> unread, then stay stuck; `z` fold and
k/j/Ctrl-Up/Down reorder take almost a second to render (also REVIEW-QUEUE notes on
dashboard-reload-avoid-full-redraw and dashboard-manual-list-reordering).

## Status causes (all confirmed live)

1. Scrape matched working patterns across 200 lines of scrollback; Claude Code redraws
   leave stale spinner lines there, so a finished pane read "working" after the Stop
   hook's 30s window (pane %21: remnant 176 lines up). Now last 15 lines only.
2. Stop skipped marking unread while the pane was tmux-active even with the terminal in
   the background. Focus now also requires tmux's `focused` client flag (verified it
   drops on focus-out, returns on focus-in, starts set).
3. Reaching a pane via select-window / switch-client / terminal refocus never cleared
   unread (after-select-pane doesn't fire for them). New hooks: session-window-changed,
   client-session-changed, client-focus-in -> `llm-pane-focus-track --if-viewed`.
4. UserPromptSubmit hook -> "working" + clear unread (plugin 0.2.0).

## Latency

One tree build = ~55 tmux + ~80 other execs; fold/reorder built it twice. Now one
`list-panes -a` snapshot, status once per pane, no per-row subshells, transforms pass
rows via temp file; llm-persist saved uses one jq. emit-rows 1.2s -> 56ms (live),
fold keypress -> redraw 530ms -> 95ms (sandbox), saved --tsv 150 -> 36ms.

## Verification

- Sandbox server (isolated HOME/state/socket): old vs new emit-rows byte-identical
  except the stale-remnant pane (working -> idle).
- pty-attached client: 8/8 unread lifecycle checks (mark/clear on session, window,
  terminal focus; detached window change doesn't clear).
- Hook simulation via run-shell: working -> Stop -> unread -> UserPromptSubmit ->
  working -> Stop -> unread; stale-remnant pane stays unread after hook ages out.
- tests/scenarios 09-21 pass. shellcheck unavailable here (mise shim error).
- Live: hooks registered on the running server; plugin 0.2.0 at user + project scope
  (running Claude sessions need a restart to load the UserPromptSubmit hook).
