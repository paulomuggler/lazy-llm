---
slug: claude-worktrees-polish
title: Claude worktrees — remaining polish (Saved tab marker, claude -w restore edge cases, theoretical races)
priority: P3
status: backlog
created: 2026-10-03_22:26
updated: 2026-10-03_22:26
depends-on: [claude-worktree-followups]
tags: [worktree, dashboard, persistence]
---

# Claude worktrees: remaining polish

## Context
Leftovers from the verification rounds of `claude-worktree-followups`, gathered into one task.
None of them loses work.

## Items
1. **Saved tab**: pane rows don't show that a saved pane runs in a worktree (pane or Claude).
   The manifest has `worktree: {path, branch}`; show `⎇` on those rows.
2. **A restored `claude -w` pane whose worktree was landed and removed** comes back as a fresh
   conversation in the workspace dir, instead of trying `claude --resume`. That conversation
   was keyed by the worktree path, which no longer exists. Decide whether to keep this or to
   recreate the worktree from its branch when the branch survives (today it's recreated only
   if the branch exists).
3. A pane whose shell is cd'd into a subagent's `agent-*` worktree is saved as a `claude -w`
   pane (isolated on restore). Probably fine; confirm.
4. **Theoretical:**
   - A registry rewrite (prune at SessionStart) racing a parallel WorktreeCreate's append for
     the same session can drop the new entry. The repo scan still finds it when cwd is that
     repo.
   - Two tmux servers started in the same second look like the same server to the pane-id
     guard.

## Acceptance Criteria
- [ ] 1 done, with a test
- [ ] 2 and 3 decided (and done or documented)
- [ ] 4 assessed: fixed or explicitly accepted in spec §11
