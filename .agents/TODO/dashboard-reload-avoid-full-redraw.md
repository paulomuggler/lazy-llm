---
slug: dashboard-reload-avoid-full-redraw
title: Use fzf's reload() to avoid a full fzf relaunch on fold/toggle/refresh
priority: P2
status: in-progress
created: 2026-09-23_04:20
updated: 2026-09-23_05:05
depends-on: []
tags: [enhancement, dashboard, performance, ux]
commits: []
model: opus
owner: homelab-zrh-dev-2339310
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

- `lazy-llm-bin/.local/bin/llm-dashboard` — `render_sessions_tab` (lines ~145-465,
  includes the fzf `--bind` list ~368-389 and the `load:pos(${_start_pos})`
  binding this task must not regress), `dispatch_action` (~568-740, includes
  `action:toggle:*` which currently mutates the in-process `_collapsed` array),
  the main outer loop (~979-1004, currently rebuilds `$lines` + relaunches fzf
  fresh every iteration via command substitution), `declare -A _collapsed=()`
  (~977)
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — `lazy_llm_gather_sessions`,
  pane-array helpers, existing tmux-option read/write patterns to match

## Read first

- `tests/scenarios/13-dashboard-panes-tab-unit.sh` — the existing pattern for
  dashboard unit tests: structural/wiring checks (grep for exec strings,
  binding presence, line counts) run against the actual script files, NOT
  live interactive fzf (PTY-dependent, explicitly out of scope for this test
  tier — see its own header comment). New tests for `reload()` wiring and
  the row-emission extraction should follow this same structural-check style;
  `tests/test-runner.sh` runs the full suite (`tests/scenarios/01`-`15`).
- `/home/paulomuggler/Projects/dev-env/dotfiles/claude/dot-claude/coding-standards/frameworks/tmux-fzf.md`
  — lives in the parent dev-env repo (this submodule has no local copy). Read
  in full before touching any `--bind`, `fzf`, or `tmux set-option` call.
  Directly load-bearing here: the `start:pos(N)` vs `load:pos(N)` postmortem
  (this task's own Constraints section restates the verification lesson, but
  the doc has the full root-cause story of how three prior rounds missed it);
  the `set -e` + bare `var=$(cmd)` hazard (every new `reload()`-triggering
  `--bind` and every new fzf/tmux call this task adds must be guarded the
  same way `action:pane-add` already is); the `--nth`/`--with-nth` field-index
  interaction (relevant if the extracted row-emission path changes field
  layout); and the `unbind`/`rebind` ordering note (relevant since the new
  action keys need to compose with the existing `/`-search unbind/rebind
  lists at lines ~385-386).
- `lazy-llm-bin/.local/bin/lazy-llm:254` (`tmux set-option -t "$session" @lazy_llm 1`)
  — existing precedent for a SESSION-scoped (not window-scoped) tmux option,
  the right shape to copy for fold state: `_collapsed[name]` is a per-workspace
  (i.e. per-session) property, not per-window or global, so its persistent
  replacement should be a session-scoped option (e.g. `@lazy_llm_collapsed`),
  parallel to how `@lazy_llm` itself is stored — not the `-w` window-scoped
  pattern `@AI_PANES` et al. use (those are correctly window-scoped since
  panes are a window-level concept; fold state isn't).

## Constraints

- Verify any `reload()`-based cursor-positioning claim the same way the
  `start:pos(N)` bug was eventually caught — ANSI-aware `capture-pane -e`
  against a live render, not just a computed value via debug prints (see
  coding-standards/frameworks/tmux-fzf.md for the full story of why the
  weaker verification missed a real bug for three rounds)
- Should compose with [[dashboard-manual-list-reordering]] if that lands
  first/alongside
- New/changed `fzf`/`tmux` calls must follow the `set -e` safety pattern
  already used elsewhere in this file (e.g. `action:pane-add`'s `|| true` on
  a bare assignment) — an unguarded fzf/tmux call that can legitimately
  return nonzero (Esc, no match) must not be allowed to kill the whole
  dashboard process under `set -e`
- The `reload()` command runs as an independent subprocess with no access to
  this script's in-process bash arrays (`_collapsed`) or shell variables —
  any state it needs (fold flags, row data inputs) must come from tmux
  options or be recomputed fresh, not read from parent-process memory
- Existing `tests/scenarios/01`-`15` (run via `tests/test-runner.sh`) must
  still pass — these are structural/wiring checks, not live-fzf, so they're
  a real regression gate, not something to skip because "fzf can't be unit
  tested"
- Don't touch the Worktrees or Help tabs' own fzf calls/dispatch — scope is
  the Workspaces tab only

## Acceptance Criteria

- [ ] Fold/unfold no longer exits and relaunches the fzf process (verified via
      process inspection — no new fzf PID across a fold action — not just "it
      looks the same")
- [ ] Fold state survives the reload correctly and is still scoped per-workspace
- [ ] Cursor position after a reload lands where expected, verified with
      ANSI-aware capture against real data
- [ ] No regression in the existing 10–15 test suite
