---
slug: status-unread-state-and-aggregate-counts
title: "Unread" pane status (finished, not yet looked at) + per-status aggregate counts in status bars
priority: P1
status: done
human-validation: pending
created: 2026-09-24_00:00
updated: 2026-09-24_01:00
depends-on: []
tags: [ux, dashboard, statusbar, status-detection]
commits: [b467a14, dev-env:5f6df63]
model: inline
---

# "Unread" pane status + per-status aggregate counts in status bars

## Context

User request (2026-09-24):
1. Distinguish a pane that just *stopped* working and that the user hasn't interacted
   with since ("it's my turn — go look at it") from a pane that's truly idle (already
   dealt with; nothing to do until a follow-up or close).
2. The cross-workspace summary in `llm-status` / `llm-pane-border` only shows workspace
   count + workspaces-with-a-waiting-pane. Show aggregate counts of AI panes per status
   (waiting / unread / working / idle) across all workspaces.

## Design

New status `unread` (glyph `◉`): the pane finished a turn and nobody has looked at it.

- **Marker**: `~/.cache/lazy-llm/unread/<pane_id>`, content = the pane's `pane_pid` (guards
  against tmux reusing `%N` ids after a server restart). No age-out — unread can last
  overnight.
- **Set** when:
  - Claude `Stop` hook fires (dev-env's `lazy-llm-status-notify.sh`, reliable, event-driven)
    — NOT on `Notification:idle_prompt`, which fires ~60s later and would re-mark a pane
    the user already cleared.
  - Any tool: the scrape observes a working → idle transition (`busy/<pane_id>` marker
    left by an earlier "working" observation). Covers gemini/codex/etc. that have no hook.
  - Skipped if the pane is focused in an attached client at that moment (user watched it
    finish).
- **Cleared** when:
  - Focus lands on the pane (`after-select-pane` → `llm-pane-focus-track`).
  - It's cycled into view (`lazy_llm_cycle_to_index`).
  - A prompt is sent to it (`llm-send`) — the prompt-buffer workflow never focuses it.
  - Picked from the dashboard tree (switch-pane).
  - It starts working again.
- **Precedence**: waiting > working > unread > idle > unknown.

Aggregate summary: `lazy_llm_compute_summary` returns per-status pane counts; one shared
renderer in the lib, used by both llm-status and llm-pane-border. Zero counts omitted.
Glyph/color mapping consolidated into the lib (was triplicated).

## Key Files

- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — marker helpers, detect precedence, summary, glyphs
- `llm-status-bin/.local/bin/llm-status`, `lazy-llm-bin/.local/bin/llm-pane-border` — summary render
- `lazy-llm-bin/.local/bin/llm-dashboard` — aggregate glyph, legend, help tab
- `lazy-llm-bin/.local/bin/llm-pane-focus-track`, `llm-send-bin/.local/bin/llm-send` — clearing
- dev-env: `dotfiles/claude/dot-claude/hooks/lazy-llm-status-notify.sh` — mark on Stop
- `tests/scenarios/10-pane-status-detection.sh` — unit coverage

## Acceptance Criteria

- [x] A pane that finishes while unfocused shows `◉` in dashboard, status tile, pane border
- [x] Focusing / cycling to / sending to the pane turns it into `○`
- [x] `idle_prompt` notification does not re-mark a cleared pane
- [x] Status bar summary shows per-status counts across all workspaces, zeros omitted
- [x] Unit tests cover marker set/clear/precedence and summary rendering

## Work Report

**Date:** 2026-09-24

### What was done
- `lazy-llm-lib.sh`: unread markers (`lazy_llm_mark_unread` / `lazy_llm_clear_unread` /
  `lazy_llm_is_unread` / `lazy_llm_pane_is_focused`), layered onto
  `lazy_llm_detect_pane_status`; per-status `lazy_llm_compute_summary`
  (`ws waiting unread working idle`); shared `lazy_llm_render_summary`; glyph/color
  mapping moved here from its three copies (llm-status, llm-pane-border, dashboard).
- Clearing wired into `llm-pane-focus-track`, `lazy_llm_cycle_to_index`, `llm-send`,
  and the dashboard's switch-pane action.
- Dashboard: workspace aggregate glyph ranks unread between waiting and working;
  legend + Help tab updated.
- dev-env hook `lazy-llm-status-notify.sh`: marks unread on `Stop` only (checked via
  payload `hook_event_name`, since `idle_prompt` shares the "idle" arg).
- Idle's color changed green -> gray `#bcbcbc`; green now means unread ("your turn").

### Verification
- New `tests/scenarios/17-pane-unread-state-unit.sh` (23 assertions, isolated tmux server
  + isolated HOME): mark/clear, pid-mismatch cleanup, working-over-unread precedence,
  non-claude transition marking, claude transition NOT marking, summary counts, renderer.
- Existing unit tests 09–16 all pass.
- Hook exercised end-to-end in a sandbox: Stop payload marks (pid matches pane_pid),
  idle_prompt payload does not.
- Live render of `llm-status` / `llm-pane-border` against the real workspaces:
  `3ws 1● 4○`.
- Not verified: the visual look of `◉` in the live status bar / dashboard (needs a
  human eye), and the after-select-pane clear on mouse-click focus (relies on the same
  hook llm-pane-focus-track already uses).

### Known limits
- Reading a pane's output from the prompt pane without focusing, cycling, or sending to
  it leaves it unread. Focus it once (or pick it in the dashboard) to dismiss.
- Non-claude tools: turns shorter than the status-interval poll can be missed.
