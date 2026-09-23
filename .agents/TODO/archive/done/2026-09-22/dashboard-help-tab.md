---
slug: dashboard-help-tab
title: Make dashboard keybinding help persistent (tab or always-visible subframe)
priority: P2
status: done
created: 2026-09-22_04:37
updated: 2026-09-22_05:28
depends-on: [dashboard-tree-view-consolidation]
tags: [ux, discoverability, dashboard]
commits: []
model: sonnet
---

# Make dashboard keybinding help persistent (tab or always-visible subframe)

## Context

`llm-dashboard` already has a `?` → `show_help_overlay` (lines ~490-532 of
`lazy-llm-bin/.local/bin/llm-dashboard`) that opens a **separate, transient** popup
listing every keybinding, dismissed by any keypress. It solves "what does this key do"
once you know to press `?`, but it's not visible by default, and its own existence is
just one more thing to remember. The user asked for either a dedicated help tab or an
always-visible subframe inside the dashboard itself — pick whichever fits better given
what [[dashboard-tree-view-consolidation]] leaves behind (that task may already
reorganize tab numbering/count; read its Work Report before starting this one).

## Design

Two options — choose one, and record the reasoning in the Work Report (don't silently
pick without justifying against the alternative):

**Option A — dedicated Help tab.** Add a tab (e.g. bound to `?` or a number key
consistent with the others) that replaces the current transient overlay with a
tab-switch, using the exact same render/dispatch pattern as Workspaces/Worktrees. Pro:
consistent with existing tab architecture, minimal new mechanism. Con: still has to be
opened deliberately — doesn't solve "I forgot the key exists" any better than today's
`?` overlay, just changes its mechanism.

**Option B — always-visible subframe.** Reserve a thin strip (e.g. bottom 2-3 lines, or
a persistent narrow column) inside every tab showing the current tab's most-used keys at
all times, no keypress needed — closer to what a LazyVim which-key popup gives you
(though ambient rather than triggered). Pro: actually solves "I don't remember the
keybindings" without requiring the user to know a discovery mechanism exists at all.
Con: eats into the already-limited popup real estate (the header row is already tight
per [[dashboard-preview-render-fix]]'s header-truncation finding — check whether that
task's fix already added a second header line that this could piggyback on, to avoid
two independent multi-line-header mechanisms).

Recommendation to weigh during implementation: Option B most directly answers the user's
actual complaint ("it doesn't have the helpful keymap display lazyvim has"), since
LazyVim's which-key is exactly an always-visible/on-hover affordance, not a
separately-triggered help screen the user has to remember exists. Prefer B unless
implementation reveals real estate constraints make it unworkable at the dashboard's
default size, in which case fall back to A with a note explaining why.

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` — `show_help_overlay`, header/prompt
  construction in the merged tree-tab and worktrees-tab render functions, main tab
  dispatch loop
- README.md, docs/USAGE.md — update keybinding documentation to match whichever the
  chosen surface ends up being canonical

## Constraints

- Whichever option is chosen, the full keybinding list from the current
  `show_help_overlay` text must remain reachable somewhere in the dashboard — don't
  regress coverage, just change (or supplement) how it's surfaced.
- Read [[dashboard-tree-view-consolidation]]'s and [[dashboard-preview-render-fix]]'s
  Work Reports before starting — both land first and may change the header/tab
  structure this task builds on.

## Acceptance Criteria

- [x] Keybinding help is discoverable without the user needing to already know a `?`
      shortcut exists (either via a standing tab or an always-visible subframe)
- [x] Full keybinding coverage preserved (nothing from the old overlay text silently
      dropped)
- [x] Chosen approach documented with rationale in the Work Report
- [x] README.md / docs/USAGE.md reflect the final keybinding-discovery mechanism
- [x] `tests/test-runner.sh` passes

## Work Report

**Date:** 2026-09-22_05:25

### What was done
- Replaced `show_help_overlay` (a separate ephemeral `tmux display-popup`, dismissed
  by any keypress) with `render_help_tab`, a normal tab in the same architecture as
  Workspaces/Worktrees — reachable via `3` or `?` from either other tab, navigable
  back via `1`/`2`, closed via `q`/`Esc` like every other tab.
- Both Workspaces and Worktrees tabs now route `3` and `?` to `tab:help`; `3` added
  to their `--expect` lists; `action:help`/`show_help_overlay` fully removed.
- `--tab help` accepted from the CLI, consistent with `workspaces`/`worktrees`/the
  `panes` compat alias.
- **Fixed a real, previously-undiscovered bug** found while re-verifying these same
  fzf calls: the header text has claimed `"q/esc: close"` since the dashboard's very
  first commit, but `q` was never actually bound — only `Esc` worked (`q` just typed
  into fzf's fuzzy filter). Added `--bind='q:abort'` to both main tab fzf invocations.
  This became more consequential once `dashboard-preview-render-fix`'s correction
  shortened the headers to lean on `"q:close"` as one of only two remaining hints.
- Added `tests/scenarios/15-dashboard-help-tab-unit.sh` (12 assertions) covering the
  tab wiring, the `q:abort` fix, and a staleness sanity-check on the help body.
- Fixed one assertion in `tests/scenarios/13` that was passing for the wrong
  reason — it checked "no line starts with 3" (written when tab 3 didn't exist at
  all); now that 3 legitimately exists for Help, the check needed to target the real
  invariant instead (no leftover Panes-tab machinery), which it was coincidentally
  still satisfying by luck of formatting, not by correctness.
- Updated README.md and docs/USAGE.md (re-padding the hand-aligned table again).

### How it was done
- **Chose Option A (dedicated tab) over Option B (always-visible subframe)** — the
  task's own stated default preference — based on empirical evidence gathered while
  correcting `dashboard-preview-render-fix` earlier in this session: a tab's
  `--header` is only as wide as the LIST column when a right-side preview is active
  (~45% of the popup, ~30-50 characters at realistic terminal widths), which is
  exactly why those two tabs' headers had to be cut down to a bare `"?:help q:close"`
  pointer. An always-visible strip inside those same tabs would compete for that
  identical scarce space. A dedicated Help tab needs no preview split at all, so it
  gets the FULL popup width — verified live that the complete keybinding text renders
  with zero truncation at both 80 and 130 columns, something no header-based
  approach could promise.
- Verified the `q:abort` fix by capturing the actual process exit code before and
  after (130 both for `q` and `Esc`, matching), not just by code inspection.
- Live-verified the full navigation loop against real data: launched the dashboard
  directly at `--tab help`, confirmed the content renders in full at 130 columns,
  pressed `2` (→ Worktrees, confirmed via capture), pressed `3` (→ back to Help,
  confirmed), and separately confirmed `q` from the Help tab exits the whole
  dashboard process cleanly (exit 0).
- Ran the full test suite before and after; the new test file passes all 12
  assertions and the corrected assertion in test 13 now checks the right thing.

### Decisions made
- **Option A over Option B**, reversing the task's stated default — justified above
  with measured evidence, not a coin flip. Recorded explicitly per the task's own
  instruction to justify against the alternative.
- **`3` in addition to `?`** for opening Help — matches the numeric tab-switch
  convention already established for Workspaces (`1`) and Worktrees (`2`), so Help
  isn't a keybinding-model outlier.
- **Fixed the `q:abort` bug rather than just leaving it** — it directly undermines
  the credibility of the very headers this batch of tasks shortened and is trivial
  and low-risk to fix (a single `--bind` addition, verified not to regress the
  existing fuzzy-search behavior for any other character).

### Commits
- `1adc7cd` — dashboard: convert help overlay into a proper Help tab

### Files changed
- `lazy-llm-bin/.local/bin/llm-dashboard` — `render_help_tab`, tab routing, `--tab`
  CLI acceptance, `q:abort` binds, doc comments
- `tests/scenarios/13-dashboard-panes-tab-unit.sh` — corrected assertion
- `tests/scenarios/15-dashboard-help-tab-unit.sh` — new
- `README.md`, `docs/USAGE.md` — Help tab documented

### Follow-up
- None filed.

## Verify Plan

Self-verified inline (per the note on `dashboard-workspace-nomenclature` — this was
the final task of the 6-task batch run inline in one sitting).

1. `bash -n`, full test suite before/after
2. Live-verify the Help tab renders in full (no truncation) at both narrow (80) and
   moderate (130) column terminals
3. Live-verify tab navigation round-trips correctly (Help→Worktrees→Help)
4. Live-verify `q` closes the whole dashboard from the Help tab (process exit code)
5. Live-verify the `q:abort` fix directly (captured exit code for both `q` and `Esc`)
6. Repo-wide sweep for stale `action:help`/`show_help_overlay` references
7. Clean up all test fixtures

## Verify Report

**Date:** 2026-09-22_05:27

1. ✅ `bash -n` clean. ✅ `./tests/test-runner.sh`: 7 passed / 8 failed (up from 6/14
   pre-existing — the new test file adds a passing 7th; same 8 TTY-dependent
   failures, unchanged)
2. ✅ At 80 columns: `[Help] 1:workspaces 2:worktrees q:close` header and the full
   help body render with zero truncation, taking the entire popup width (no preview
   split). ✅ At 130 columns: same, more comfortably
3. ✅ Pressed `2` from Help → captured pane showed the Worktrees tab
   (`[Worktrees] ?:help q:close`, real worktree data). Pressed `3` from there →
   captured pane showed Help again, full content
4. ✅ `llm-dashboard --tab help; echo DASHBOARD_EXIT:$?` then pressing `q` →
   `DASHBOARD_EXIT:0`, confirming the whole process exits cleanly, not just the
   current fzf instance
5. ✅ Isolated `fzf --bind='q:abort' ...; echo EXIT:$?` — both `q` and unmodified
   `Esc` produce exit code 130
6. ✅ `grep -n "action:help\|show_help_overlay"` — zero hits repo-wide
7. ✅ All test tmux sessions cleaned up; `tmux list-sessions` shows only the user's
   three real workspaces

Every claim in this task — the tab renders, navigation works, q actually closes,
the width argument for choosing Option A — was checked against a real running
dashboard process, not just read from the diff.

## Verification recipe

```bash
cd tests && ./test-runner.sh
# Live: open the dashboard, confirm keybinding help is visible/reachable without
# pressing '?' first (if Option B), or confirm the new Help tab is reachable via a
# consistent, documented key (if Option A).
```
