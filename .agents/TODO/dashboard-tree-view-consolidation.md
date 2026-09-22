---
slug: dashboard-tree-view-consolidation
title: Consolidate Sessions + Panes tabs into a single collapsible workspace/pane tree
priority: P1
status: pending
created: 2026-09-22_04:37
updated: 2026-09-22_04:37
depends-on: [dashboard-workspace-nomenclature]
tags: [ux, dashboard, tui, tree-view]
commits: []
model: inline
---

# Consolidate Sessions + Panes tabs into a single collapsible workspace/pane tree

## Context

`llm-dashboard` (`lazy-llm-bin/.local/bin/llm-dashboard`) currently has three fzf-driven
tabs: Sessions (renamed Workspaces by [[dashboard-workspace-nomenclature]]), Worktrees,
Panes. Sessions lists every lazy-llm workspace with a single status glyph (the *first*
AI pane's status only — see `render_sessions_tab`, lines 68-77) and requires switching
to a *different* workspace before its Panes tab becomes relevant (Panes only shows the
**current** window's AI panes — `render_panes_tab` calls `lazy_llm_resolve_pane` against
the pane the dashboard was launched from, it can't show another workspace's panes at
all). This means: to see the status of an AI pane in a workspace you're not currently
in, there's no path in the UI — you have to switch to it first.

Merge Sessions + Panes into one tab: a tree where each top-level row is a workspace, and
each workspace's AI panes render as indented child rows beneath it, each with their own
status glyph. Collapsed by default (or expanded — pick one and justify it in the Work
Report) with a toggle key. This gives the "see all AI panes and their status" visibility
the user asked for without switching away from what they're doing, which is the actual
UX gap here.

## Design

**Tree rendering strategy** (fzf has no native tree/collapse widget — fake it):

- Maintain a collapse-state set for the render loop's lifetime (a bash associative
  array keyed by workspace name, e.g. `declare -A _collapsed`; default: start all
  **expanded** — the whole point is seeing panes without extra keystrokes, and 3
  workspaces × ~2 panes each is not a wall of text at this repo's typical scale per the
  screenshot the user shared).
- Build `lines` as: for each workspace (via `lazy_llm_gather_sessions`), emit the parent
  row (workspace name, dir, per-pane summary — reuse existing formatting), then for each
  of its AI panes (need a per-workspace pane list — currently only the *current*
  window's panes are readable via `@AI_PANES`; for **other** workspaces' windows, read
  their window options directly: `tmux show-option -wv -t "$name:$first_win" @AI_PANES`
  / `@AI_TOOLS`, same pattern `render_sessions_tab` already uses for `@AI_PANE_ID` at
  line 70 — extend it to pull the full multi-pane list, not just the first), emit one
  indented child row per pane with its own glyph (reuse `lazy_llm_detect_pane_status`
  per pane, not just the first).
- Toggle key (e.g. `Tab` or `z` — check fzf's `--bind` doesn't already claim it; avoid
  colliding with existing single-letter action keys `n K r R ? 1 2 3`) collapses/expands
  the workspace row under the cursor; re-renders `lines` and re-invokes fzf preserving
  the query/position (fzf doesn't support live tree mutation mid-session, so this means
  the same outer-loop re-render pattern the tab-switch actions already use — return an
  `action:toggle:<workspace>` result, dispatch flips the state, outer loop re-renders the
  same tab).
- Row identification for existing actions (switch/kill/rename operate on workspace rows;
  pane actions — cycle/add/remove — operate on pane rows): parse the row type from a
  leading marker column (e.g. first char `▾`/`▸` for workspace rows vs indentation +
  pane index for child rows) so `chosen_name`/`chosen_idx` extraction in the dispatch
  logic can tell which kind of row was selected and route Enter/K accordingly (Enter on
  a workspace row switches to it; Enter on a pane row cycles to that specific pane
  *within* its workspace, which requires switching workspace + cycling — compose the two
  existing actions).
- Preview pane: when a workspace row is selected, preview its *active* pane (current
  behavior). When a pane row is selected, preview *that* pane specifically (this
  actually improves on today's Panes tab, which can only preview panes in the current
  window).

**What to keep**: the Worktrees tab stays separate (different entity, no reason to fold
it in). `llm-panes` binary can become a thin wrapper that opens the merged tab (still
useful as an alias per the existing "kept for CLI muscle memory" comment); `llm-sessions
--list`/`--kill` CLI (non-interactive) is unaffected — only the interactive dashboard
tab structure changes. Retarget any `3: panes` / `2: worktrees` tab-number references
in headers now that there are two tabs instead of three (workspaces-tree, worktrees) —
renumber consistently and update `show_help_overlay` and `README.md`/`docs/USAGE.md`
tab references (`Prefix+S → 3` etc.) to match the new tab count/keys.

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` — `render_sessions_tab`, `render_panes_tab`
  (merge into one `render_workspaces_tab`), `dispatch_action`, main outer loop's tab
  case statement, `show_help_overlay`, `usage()`
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — may need a new helper to read another
  workspace's full `@AI_PANES`/`@AI_TOOLS` list (not just the current window's) if
  `lazy_llm_read_multi_state` doesn't already generalize to an arbitrary `session:window`
  target — check before adding a duplicate
- `tests/scenarios/11-dashboard-shell-unit.sh`,
  `tests/scenarios/13-dashboard-panes-tab-unit.sh` — likely need updates or a merged
  replacement test
- README.md, docs/USAGE.md — tab count/keybinding references (`Prefix+S → 3`, "Sessions
  / Worktrees / Panes tabs")

## Constraints

- Don't touch the Worktrees tab's implementation.
- Preserve every existing action's behavior (switch, kill, rename, refresh, add pane,
  remove pane, cycle pane) — this is a layout/navigation consolidation, not a feature
  cut. If an action's semantics must change because of the tree structure (e.g. what
  `K` deletes when a pane row vs. workspace row is selected), document the new behavior
  explicitly in the Work Report and in `show_help_overlay`.
- Run the existing test suite (`tests/test-runner.sh`) before and after — know what
  breaks and fix or deliberately update it, don't leave red tests.

## Acceptance Criteria

- [ ] Single dashboard tab shows every lazy-llm workspace with all of its AI panes
      nested beneath it, each pane showing its own status glyph (not just the first
      pane's, as today)
- [ ] Collapse/expand toggle works per-workspace row without closing the dashboard
- [ ] Enter on a workspace row switches to it (unchanged behavior)
- [ ] Enter on a pane row switches to that workspace AND focuses that specific pane
- [ ] Preview pane shows the selected row's specific pane content (workspace row →
      active pane; pane row → that pane)
- [ ] All prior Sessions-tab actions (n/K/r/R) and Panes-tab actions (a/K/]/[/R) still
      reachable and working from the merged tab
- [ ] Tab count/keys updated consistently across `llm-dashboard`, `show_help_overlay`,
      README.md, docs/USAGE.md — no dangling "3: panes" reference to a tab that no
      longer exists
- [ ] `tests/test-runner.sh` passes (updated tests reflecting the merge, not deleted
      coverage)

## Verification recipe

```bash
cd tests && ./test-runner.sh
# Live: open 2+ lazy-llm workspaces, each with 2+ AI panes of mixed status
# (idle/working/waiting via mock tool if tests/ has one, per docs/VALIDATION_PLAYBOOK).
# Prefix+S → confirm the tree shows every workspace with all its panes nested,
# glyphs correct per pane, toggle collapses/expands, Enter on a nested pane row
# switches + focuses correctly.
```
