---
slug: dashboard-manual-list-reordering
title: Manual reordering of dashboard tree rows (Ctrl+Up/Down), scoped per tree level
priority: P2
status: pending
created: 2026-09-23_04:20
updated: 2026-09-23_04:20
depends-on: []
tags: [enhancement, dashboard, ux]
commits: []
model: opus
---

# Manual reordering of dashboard tree rows

## Context

Direct request, after the stable-sort fix landed: now that the tree's list order
is stable (no more auto-sorting the active workspace to the top — see
[[dashboard-layout-status-redesign]]'s Round 7), the user wants to be able to
manually reorder rows — e.g. drag a frequently-used workspace to the top, or
reorder panes within a workspace to match how they think about the project.

**Key design point, corrected mid-conversation**: this does NOT require reordering
tmux's own session list, and does not need any tmux "reorder sessions" primitive
(tmux doesn't have one). The dashboard's displayed row order is already decoupled
from `tmux list-sessions`'s own order — it's just derived from it today. Manual
reordering only needs the dashboard to maintain its OWN ordering preference and
apply it as a sort step over the gathered data, independent of whatever order tmux
itself considers its sessions in.

**Scoping requirement, explicit**: this is a TREE, not a flat list — reordering
must stay bound to its level. A workspace row can only reorder among sibling
workspace rows; a pane row can only reorder among its own workspace's sibling
panes, never across workspaces.

## Proposed design (sketched during the request, not yet implemented)

- **Workspace-level order**: a new persistent, server-scoped tmux option (e.g.
  `@lazy_llm_ws_order`, set via `tmux set-option -s`, matching this project's
  existing pattern of storing lazy-llm state in tmux options rather than a config
  file) holding a delimited list of workspace names in custom order. Workspaces
  not yet present in it (new ones) are appended in their natural
  (`lazy_llm_gather_sessions`) order at render time — never silently dropped.
  `render_sessions_tab` consults this option (if set) to reorder the gathered
  workspace rows, in place of (or layered on top of) the current natural order.
- **Pane-level order**: no new storage needed — a workspace's pane order is
  already `@AI_PANES`/`@AI_TOOLS`/`@AI_PANE_NAMES` (parallel arrays, window-scoped).
  Reordering a pane row just swaps two adjacent entries across all three arrays
  and re-sets the options — same pattern already used by the rename-pane action.
- **Keybinding**: Ctrl+Up / Ctrl+Down. Confirmed free in fzf's default bindings
  (not used by up-match/down-match, which are plain Up/Down and Ctrl-N/Ctrl-P).
  Needs its own `--bind`/print(...)+accept entries like the other action keys, and
  inclusion in the search-mode unbind/rebind key lists (see
  dashboard-reload-avoid-full-redraw for how this interacts with a possible
  reload()-based redraw).
- **Dispatch**: on Ctrl+Up/Down, determine whether the highlighted row is a
  workspace or a pane (same `chosen_ws`/`chosen_pane_idx` resolution already used
  elsewhere in `dispatch_action`), find its sibling list at that level, swap it
  with its neighbor, persist (tmux option or window option array), refresh the
  view with the cursor following the moved row (reuse `_start_pos`/`load:pos(N)`
  targeting the row's NEW position).

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` — `render_sessions_tab`, `dispatch_action`,
  the fzf `--bind` list and search-mode unbind/rebind sets
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — `lazy_llm_gather_sessions` (workspace
  order source), pane-array helpers

## Constraints

- Reordering must never cross tree levels (a workspace can't be inserted between
  a different workspace's panes, etc.)
- A workspace absent from the custom order option (new, never explicitly moved)
  must still render, appended in natural order — never silently hidden
- Should compose with [[dashboard-reload-avoid-full-redraw]] if that lands
  first/alongside — the swap+refresh should ideally go through the same
  no-full-relaunch mechanism, not reintroduce a fresh fzf process per reorder

## Acceptance Criteria

- [ ] Ctrl+Up/Down on a workspace row reorders among workspace rows only,
      persists across dashboard reopens
- [ ] Ctrl+Up/Down on a pane row reorders among that workspace's own panes only,
      persists (via `@AI_PANES` et al.)
- [ ] A newly created workspace/pane not yet in any custom order still appears,
      in natural order, without needing an explicit "add to order" step
- [ ] Verified live against a disposable multi-workspace, multi-pane session
      before shipping
