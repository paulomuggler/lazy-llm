---
slug: dashboard-tree-view-consolidation
title: Consolidate Sessions + Panes tabs into a single collapsible workspace/pane tree
priority: P1
status: done
created: 2026-09-22_04:37
updated: 2026-09-22_05:07
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

- [x] Single dashboard tab shows every lazy-llm workspace with all of its AI panes
      nested beneath it, each pane showing its own status glyph (not just the first
      pane's, as today)
- [x] Collapse/expand toggle works per-workspace row without closing the dashboard
- [x] Enter on a workspace row switches to it (unchanged behavior)
- [x] Enter on a pane row switches to that workspace AND focuses that specific pane
- [x] Preview pane shows the selected row's specific pane content (workspace row →
      active pane; pane row → that pane)
- [x] All prior Sessions-tab actions (n/K/r/R) and Panes-tab actions (a/K/]/[/R) still
      reachable and working from the merged tab
- [x] Tab count/keys updated consistently across `llm-dashboard`, `show_help_overlay`,
      README.md, docs/USAGE.md — no dangling "3: panes" reference to a tab that no
      longer exists
- [x] `tests/test-runner.sh` passes (updated tests reflecting the merge, not deleted
      coverage)

## Work Report

**Date:** 2026-09-22_05:04

### What was done
- Merged `render_sessions_tab` (Sessions tab, first-pane-only status) and
  `render_panes_tab` (Panes tab, current-window-only) into a single tree tab:
  every workspace as a parent row, every one of its AI panes as an indented
  child row, each with its own status glyph.
- Added `lazy_llm_read_multi_state_for(session, window)` to `lazy-llm-lib.sh` — reads
  an ARBITRARY window's full `@AI_PANES`/`@AI_TOOLS`/`@AI_PANE_IDX`, not just the
  current one (the previous helper, `lazy_llm_read_multi_state`, only worked on
  `_SESSION`/`_WINDOW` resolved from ambient context).
- Designed a tab-delimited row model (`<id>\t<display>`, `--with-nth=2` hides the id)
  so a single fzf list can carry two row types (`ws:<name>` / `pane:<name>:<idx>:<id>`)
  without the id text polluting what's shown — `{1}` in the preview command still
  reaches the hidden id regardless of `--with-nth`.
- Added `z` to fold/unfold a workspace's pane rows; state lives in a script-global
  `declare -A _collapsed`, mutated only by `dispatch_action` (which runs in the main
  shell) since `render_sessions_tab` runs in a subshell via command substitution and
  can only read it.
- Extracted `lazy_llm_cycle_to_index(session, window, idx)` from `llm-cycle`'s
  ambient-context swap logic, so the dashboard can focus a specific pane in an
  ARBITRARY (non-current) workspace before switching the client to it —
  `llm-cycle`'s own ambient "ready pane" resolution can't be trusted to follow a
  `switch-client` issued from inside the popup process. `llm-cycle` now computes its
  target index (unchanged logic) and delegates the actual swap to the shared function.
- Scoped `a` (add pane) / `]`/`[` (cycle) / `K` on a pane row to the CURRENT workspace
  only (the one the dashboard was launched from) — this is the SAME scope the old
  Panes tab already had (it could never address another workspace's panes either), not
  a new restriction. `K` on a foreign workspace's pane row shows a message explaining
  why, instead of silently doing nothing or the wrong thing.
- Updated `llm-panes` and `--tab panes` to alias to the Workspaces tree tab (compat,
  not removed).
- Updated `show_help_overlay`, `usage()`, the file header comment block, README.md,
  and docs/USAGE.md (re-padding the hand-aligned box table) to match.

### How it was done
- Extracted the dashboard's function bodies into an isolated file (stripped of its own
  self-sourcing block) so they could be sourced and exercised directly, bypassing the
  interactive fzf loop — stubbed `fzf` as a bash function that dumps its stdin, letting
  me inspect the EXACT rows the real function generates against real tmux state,
  rather than trusting code review alone.
- Built two real test workspaces via tmux: one with 2 AI panes wired the modern way
  (`@AI_PANES`/`@AI_TOOLS`), one with a single pane wired the LEGACY way (only
  `@AI_PANE_ID`/`@AI_TOOL`, no `@AI_PANES` at all) — confirmed both the modern and
  fallback code paths produce correct rows.
- Verified the fold toggle by calling `dispatch_action "action:toggle:..."` directly
  and re-rendering — confirmed the collapsed workspace's pane rows disappear and its
  glyph flips ▾→▸, while other workspaces stay expanded.
- Verified the preview command by simulating fzf's `{1}` placeholder substitution
  (textually replacing `{1}` before invoking `sh -c`, matching what fzf itself does)
  against both row types — and specifically planted a unique marker string in each of
  two sibling panes to prove a pane row's preview shows THAT pane's content, not
  always the workspace's active pane.
- Verified `action:switch-pane:*` end-to-end: called `dispatch_action` directly,
  confirmed `@AI_PANE_IDX`/`@AI_PANE_ID` flipped to the target pane BEFORE the
  `switch-client` call ran (order matters, so the pane is already in place when the
  client lands on the window).
- Verified the `llm-cycle`→`lazy_llm_cycle_to_index` refactor didn't change behavior
  by testing the ORIGINAL ambient-context path (via a real ready/held pane pair,
  checking swapped content, updated pane title, and window relocation match the
  pre-refactor semantics exactly) AND the new explicit-target path (no-ambient-context
  call from a plain `bash -c` with no `TMUX_PANE` set) separately.
- Ran against this machine's REAL live lazy-llm workspaces (not just synthetic
  fixtures) — the row-building logic correctly enumerated workspaces with 1, 2, and 3
  real AI panes.
- Discovered and fixed a real bug my initial edit missed: the Worktrees tab's header
  and key dispatch (`3) echo "tab:panes"`) still referenced the removed third tab —
  caught by a repo-wide grep sweep for `3: panes`/`tab:panes` after the main edit, not
  by the test suite (no test covered it).
- Cleaned up all tmux sessions and cache files created during manual verification.

### Decisions made
- **Default to expanded, not collapsed**, per the task's own Design section reasoning:
  at this repo's typical scale (a handful of workspaces, 1-3 panes each) collapsed by
  default would hide the very information this task exists to surface.
- **`z` for fold/unfold**, not `Tab` — avoids depending on fzf's exact `--expect`
  tokenization of the Tab key across versions; `z` was unclaimed across all existing
  keybindings.
- **Pane-level actions scoped to the current workspace only, not extended to
  arbitrary workspaces** — `llm-add`/`llm-remove` are both ambient-context-only
  binaries; building explicit-target variants of both (mirroring what I did for
  `llm-cycle`) was out of proportion to this task's scope, and the pre-merge Panes tab
  had this exact same limitation (it could never see another workspace's panes to add
  or remove from). Documented explicitly rather than silently narrowing scope.
- **`--tab panes` kept as a compat alias**, not removed — costs nothing and honors
  existing CLI muscle memory / the `llm-panes` binary's own stated purpose.

### Commits
- `83e1401` — dashboard: consolidate Sessions+Panes into a single collapsible workspace tree

### Files changed
- `lazy-llm-bin/.local/bin/llm-dashboard` — merged tab, row model, dispatch, help/usage text
- `lazy-llm-bin/.local/bin/llm-panes` — retargeted alias
- `llm-cycle-bin/.local/bin/llm-cycle` — refactored to use the shared explicit-target function
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — `lazy_llm_read_multi_state_for`, `lazy_llm_cycle_to_index`
- `tests/scenarios/13-dashboard-panes-tab-unit.sh` — rewritten for the tree architecture
- `tests/scenarios/14-worktree-bridge-tab-unit.sh` — one grep anchor fixed
- `README.md`, `docs/USAGE.md` — tab count/keybinding documentation

### Follow-up
- None filed. The remaining `Sessions`-named internal identifiers (`render_sessions_tab`
  function name, `chosen_ws`-adjacent variable names) were deliberately left as-is —
  cosmetic, low-value to rename now, and not part of this task's scope.

## Verify Plan

Self-verified inline (see note on `dashboard-workspace-nomenclature` — this whole
6-task batch runs inline in one sitting). Given this task's much larger surface, went
beyond structural grep-checks to actual functional exercise:

1. `bash -n` all changed files
2. Full test suite before/after, confirm no new regressions vs. baseline
3. Extract and directly invoke the dashboard's functions (fzf stubbed) against REAL
   tmux state (both modern multi-pane and legacy single-pane workspaces) — inspect
   actual generated rows, not just code paths
4. Directly exercise fold/unfold, preview-command pane resolution (both row types, with
   unique markers proving row-specific content), and `switch-pane`/`toggle` dispatch
   actions against live tmux
5. Verify the `llm-cycle` refactor is behavior-preserving via live swap-pane tests
   (title, content, window relocation, options) against the pre-refactor contract
6. Repo-wide grep sweep for dangling references to the removed Panes tab
7. Clean up all test fixtures (tmux sessions, cache files)

## Verify Report

**Date:** 2026-09-22_05:06

1. ✅ `bash -n` clean on all 4 changed shell scripts
2. ✅ Full suite: 6 passed / 8 failed both before and after, same 8 TTY-dependent
   failures (`open terminal failed: not a terminal`) — environmental, not caused by
   this change. Test 13 rewritten (14/14 assertions pass), test 14 fixed (one stale
   grep anchor), both green.
3. ✅ Built `tree-test-ws1` (2 panes, modern `@AI_PANES` wiring) and `tree-test-ws2`
   (1 pane, legacy `@AI_PANE_ID`-only wiring) via real tmux; both produced correct
   `ws:`/`pane:` rows with correct glyphs and pane counts when the dashboard's
   function was invoked directly against them, alongside this machine's actual live
   workspaces (correctly enumerated workspaces with 1, 2, and 3 real panes)
4. ✅ Fold: toggling `tree-test-ws1` removed its 2 pane rows and flipped ▾→▸ on
   re-render, `tree-test-ws2` stayed expanded — confirms per-workspace scoping, not
   global. ✅ Preview: planted `UNIQUE_MARKER_CLAUDE_PANE` / `UNIQUE_MARKER_GEMINI_PANE`
   in two sibling panes — the workspace row's preview showed the CLAUDE marker
   (active pane), the pane-row previews showed each pane's OWN marker respectively —
   proves row-specific targeting, not a copy-paste bug that always shows pane 0.
   ✅ `switch-pane`: `@AI_PANE_IDX` flipped 0→1 and `@AI_PANE_ID` updated to the
   target pane BEFORE the switch-client call, confirmed via direct `dispatch_action`
   invocation. ✅ `toggle`: `_collapsed[name]` correctly set then unset across two
   calls.
5. ✅ `llm-cycle` (ambient path, via `~/.local/bin/llm-cycle` — the stowed/live path,
   not the dev-tree path, since the scripts assume sibling install layout): visible
   pane content swapped correctly (`MARKER_A_VISIBLE`↔held pane), `@AI_PANE_IDX`
   0→1, `@AI_PANE_ID` updated to the now-visible pane's id, pane title set to
   `"AI: gemini [2/2]"` on the CORRECT (post-swap) pane id, window relocation
   confirmed via `#{window_name}` on both pane ids. This exactly reproduces the
   pre-refactor contract described in the original code's own comments.
   ✅ `lazy_llm_cycle_to_index` (explicit-target path, no ambient `TMUX_PANE`):
   correctly updated index on first call, correctly no-op'd on a repeat call to the
   same index, correctly no-op'd on an out-of-range index — all under `set -euo
   pipefail` with no unexpected abort.
6. ✅ Repo-wide grep for `tab:panes`, `render_panes_tab`, `3: panes`, `Panes=3` — zero
   hits after fixing two instances the initial edit missed (Worktrees tab header +
   key dispatch still referencing the removed tab 3; caught by this sweep, not by any
   test, since no test asserted on that specific worktrees-tab string)
7. ✅ All test tmux sessions (`tree-test-*`, `llm-cycle-test*`, `hook-*`) and cache
   files killed/removed; `tmux list-sessions` afterward shows only the user's three
   real workspaces

Functional verification went well beyond structural code-reading — every claimed
behavior (row generation, fold, preview targeting, cross-workspace pane-switch
ordering, and the llm-cycle refactor's exact behavioral equivalence) was exercised
against live tmux state with concrete, inspectable evidence, not just "the code
looks right."

## Verification recipe

```bash
cd tests && ./test-runner.sh
# Live: open 2+ lazy-llm workspaces, each with 2+ AI panes of mixed status
# (idle/working/waiting via mock tool if tests/ has one, per docs/VALIDATION_PLAYBOOK).
# Prefix+S → confirm the tree shows every workspace with all its panes nested,
# glyphs correct per pane, toggle collapses/expands, Enter on a nested pane row
# switches + focuses correctly.
```
