---
slug: dashboard-escape-abort-killswitch
title: Fix Esc-during-subprompt silently killing the whole dashboard
priority: P1
status: done
created: 2026-09-22_14:15
updated: 2026-09-22_14:15
depends-on: []
tags: [bug, dashboard, errexit]
commits: [b43b48a]
model: inline
---

# Fix Esc-during-subprompt silently killing the whole dashboard

## Context

User asked "what happened to the keybinding for pane manipulation (add/kill)?" after
the dashboard tree-consolidation work. Investigated live rather than guessing — set up
a disposable test workspace, launched the real dashboard, pressed `a` (add pane), then
`Esc` to cancel — and the **entire dashboard closed**, not just the tool-picker
sub-prompt.

Root cause: `dispatch_action`'s `action:pane-add` and `action:worktree-new` cases each
do `var=$(... | fzf ...)` with **no `|| true` guard**. `llm-dashboard` runs under
`set -euo pipefail`. When the user presses Esc, fzf exits nonzero; since the assignment
is a bare statement (not tested by any `if`/`while`/`||`), `errexit` kills the whole
script. Confirmed via git archaeology that this predates all of today's work (present
since `8504d66` for pane-add, `fa2d128` for worktree-new) — not something introduced by
the tree-consolidation batch. Same bug class already caught and fixed once today in
`lazy_llm_detect_pane_status` (`_lazy_llm_read_hook_status` call site).

Every OTHER `var=$(... | fzf ...)` call in `dispatch_action` (the various `yes/no`
confirms, the rename prompt, the worktree cleanup confirms) already had `|| echo ...`/
`|| true` guards — audited all of them, only these two were missing it.

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` — `dispatch_action`, `action:pane-add` and
  `action:worktree-new` cases

## Acceptance Criteria

- [x] Pressing Esc during the "add pane" tool picker returns to the Workspaces tab,
      not exits the dashboard
- [x] Pressing Esc during the "new worktree" branch-name prompt returns to the
      Worktrees tab, not exits the dashboard
- [x] Every other `var=$(... | fzf ...)` call site in `dispatch_action` audited and
      confirmed already guarded (no new instances of this bug class introduced)
- [x] `tests/test-runner.sh` passes, no regression

## Work Report

**Date:** 2026-09-22_14:15

### What was done
- Added `|| true` to both unguarded fzf command substitutions
  (`action:pane-add`'s tool picker, `action:worktree-new`'s branch-name prompt).

### How it was done
- Live-reproduced the bug first: built a disposable test tmux workspace (2 real AI
  panes, not the user's own workspaces), launched the actual `llm-dashboard` binary
  from inside it, pressed `a` then `Esc`, and captured the pane — confirmed the
  dashboard closed entirely rather than cancelling the sub-prompt.
- Audited every `var=$(... | fzf ...)` call site in `dispatch_action` (10 total) to
  confirm exactly which two lacked a guard, rather than assuming.
- Checked git history (`git show <commit>:<path>`) to confirm both bugs predate
  today's session — this is a discovered pre-existing issue, not a regression from
  the tree-consolidation work.
- Re-tested live after the fix: same repro steps, confirmed Esc now correctly returns
  to the Workspaces tab with the tree intact.
- Ran the full test suite; no change from baseline.

### Decisions made
- Scoped to exactly the two broken call sites — did not restyle the already-correctly
  guarded ones, per the parsimony principle.

### Commits
- `b43b48a` — dashboard: fix Esc-during-subprompt silently killing the whole dashboard

### Files changed
- `lazy-llm-bin/.local/bin/llm-dashboard`

## Verify Plan

Self-verified inline.

1. Live-reproduce the bug on a disposable test workspace before fixing
2. Apply the fix, live-retest the same repro steps
3. Full test suite, no regression

## Verify Report

**Date:** 2026-09-22_14:15

1. ✅ Reproduced: `a` → `Esc` closed the whole dashboard (captured pane showed a bare
   shell prompt, not the Workspaces tab)
2. ✅ Fixed: same steps now show the Workspaces tree, tool-picker cancelled cleanly
3. ✅ `./tests/test-runner.sh`: 7 passed / 8 failed, identical to baseline
