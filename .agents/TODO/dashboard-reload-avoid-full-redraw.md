---
slug: dashboard-reload-avoid-full-redraw
title: Use fzf's reload() to avoid a full fzf relaunch on fold/toggle/refresh
priority: P2
status: pending
created: 2026-09-23_04:20
updated: 2026-09-23_04:20
depends-on: []
tags: [enhancement, dashboard, performance, ux]
commits: []
model: opus
---

# Avoid full redraw/reprint on dashboard actions

## Context

Direct request: fold/unfold (and every other in-place action — refresh, rename,
kill, add-pane) currently causes what reads as a full redraw of the dashboard
popup. Asked whether this is a hard limitation of the current TUI approach.

**It is not — confirmed via `man fzf`.** The current architecture
(`llm-dashboard`'s main loop, near the bottom of the file) calls
`render_sessions_tab()` fresh on every iteration; that function pipes freshly
gathered data into a BRAND NEW `fzf` subprocess every time. Any action that
doesn't `break` out of the loop (fold/toggle, refresh, rename, add-pane, etc.)
causes the running fzf process to exit (via `print(KEY)+accept`), the outer bash
loop to rebuild `$lines` from scratch, and a new fzf process to start — which is
a real process exit+relaunch, not a lightweight redraw, and reads as a flicker.

fzf has a real mechanism for the "update the list without restarting" case:
`reload(...)` (`--bind 'key:reload(command)'`) — "dynamically update the input
list without restarting fzf," per the manual. This is the fix, but it's an
architecture change, not a flag flip.

## What's actually needed (sketched during the request, not yet implemented)

1. **Extract row-building into a standalone, reusable path.** Today the
   tree-row text (workspace + pane rows, with glyphs/preview-id-fields/ANSI
   color) is built inline inside `render_sessions_tab()`, in the same function
   that also constructs and runs the `fzf` command. `reload(...)`'s command runs
   as an independent subprocess — it needs to be able to call something that
   prints the SAME row format to stdout, without going through the whole
   tab-render-and-launch-fzf function. Likely a new small script (matching this
   project's convention of one `llm-*` binary per concern) or a `--emit-rows`-style
   flag on the existing render path.
2. **Move fold state (`_collapsed`) out of the in-process bash associative
   array into persistent external storage** (a tmux option, matching every
   other piece of lazy-llm state) — a `reload()` subprocess is a fresh process
   with no access to the parent script's in-memory array. This is required
   before fold/unfold specifically can use `reload()`.
3. **Rewire the relevant action keys** (`z` fold/unfold at minimum; refresh,
   rename, add-pane, kill are candidates too, though kill/add-pane change the
   AVAILABLE ROW SET more substantially and may still need special handling) to
   `reload(...)` instead of `print(KEY)+accept`, keeping the fzf process alive
   across the action instead of exiting it.
4. **Cursor position after a reload** needs its own thought — `reload()` refreshes
   the list but doesn't itself reposition the cursor; may need to pair it with
   `pos(N)` (this project's own hard-won `load` vs `start` event lesson from
   [[dashboard-layout-status-redesign]] Round 6 likely applies here too — verify
   which event context `reload()`'s own completion fires under, don't assume).

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` — `render_sessions_tab`, `dispatch_action`,
  the main loop, `_collapsed`

## Constraints

- Verify any `reload()`-based cursor-positioning claim the same way the
  `start:pos(N)` bug was eventually caught — ANSI-aware `capture-pane -e`
  against a live render, not just a computed value via debug prints (see
  coding-standards/frameworks/tmux-fzf.md for the full story of why the
  weaker verification missed a real bug for three rounds)
- Should compose with [[dashboard-manual-list-reordering]] if that lands
  first/alongside

## Acceptance Criteria

- [ ] Fold/unfold no longer exits and relaunches the fzf process (verified via
      process inspection — no new fzf PID across a fold action — not just "it
      looks the same")
- [ ] Fold state survives the reload correctly and is still scoped per-workspace
- [ ] Cursor position after a reload lands where expected, verified with
      ANSI-aware capture against real data
- [ ] No regression in the existing 10–15 test suite
