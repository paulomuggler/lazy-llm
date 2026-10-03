---
slug: claude-worktrees-polish
title: Claude worktrees — remaining polish (Saved tab marker, claude -w restore edge cases, theoretical races)
priority: P3
status: done
created: 2026-10-03_22:26
updated: 2026-10-04_00:22
depends-on: [claude-worktree-followups]
tags: [worktree, dashboard, persistence]
commits: [3860f0d, e45e515, fd72410, a9c543e]
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
   if the branch exists). [NOTE: keep]
3. A pane whose shell is cd'd into a subagent's `agent-*` worktree is saved as a `claude -w`
   pane (isolated on restore). Probably fine; confirm. [NOTE: not aware of all ramifications of this, but sounds fine]
4. **Theoretical:**
   - A registry rewrite (prune at SessionStart) racing a parallel WorktreeCreate's append for
     the same session can drop the new entry. The repo scan still finds it when cwd is that
     repo. [NOTE: how bad is this vs. how hard/flaky it is to fix?]
   - Two tmux servers started in the same second look like the same server to the pane-id
     guard. [NOTE: anything in particular that could cause this, or is this omre of an unlikely edge case scenario?]

## Resolutions ({T}, with the user)
- **2: keep** (user). Document in spec §11 as intended: a landed `claude -w` worktree's conversation
  can't be resumed, so the pane comes back fresh.
- **3: accept** (user: "sounds fine"). Ramifications traced, none loses work:
  - a Claude started in the restored pane gets the self-integrating rules, as it would starting
    in that directory today;
  - if the parent hasn't landed the worktree either, both may integrate, but integrate is a
    rebase + fast-forward that refuses on conflict, so the second finds nothing to do;
  - landed before the restore (branch gone): the pane comes back shared and fresh;
  - directory gone but branch alive: recreated, which only happens while it holds unmerged work;
  - closing the pane asks keep/remove, listing what's unmerged.

  Document in spec §11.
- **4a: fix.** It practically can't happen: SessionStart fires between turns, and WorktreeCreate
  during them. The impact is one lost registry entry, which only matters for re-owning or the
  reminder in the submodule case. Still cheap and deterministic: lock the registry file around
  `registry_prune`'s rewrite and `_registry_append` (reuse the lock_repo machinery on a lock file
  next to the registry). Test by holding the lock and checking a writer waits, not by racing.
- **4b: accept and document.** It needs two tmux servers on different sockets started in the same
  second, plus a leftover worktree from one and a same-id pane on the other: a multi-server boot
  script, or test sandboxes (no real worktrees). `lazy-llm restore` starts its server long after
  the old one died. The user runs one default server. Hardening (recording `#{pid}` too) would
  touch llm-wt, the lib and the Lua picker, with legacy handling: not worth it now. Spec §11.

## Acceptance Criteria
- [x] 1 done, with a test
- [x] 2 and 3 decided (and done or documented)
- [x] 4 assessed: fixed or explicitly accepted in spec §11

## Work Report

**Date:** 2026-10-04_00:22

- **1 (Saved tab ⎇):** done by an isolated subagent, landed with `llm-wt integrate --remove`.
  - `e45e515`: llm-persist's pane rows carry the worktree path as a 9th column. The dashboard
    is its only reader.
  - `fd72410`: rows show `⎇ <worktree name>`, plus a Help-tab line.
  - Follow-up commit: a bare `⎇` when the pane is named after its worktree, as the Workspaces
    tree does.
  - Scenario 20 checks the listing and the rendered row; the old code fails 4.
- **2, 3, 4b:** accepted with the user, documented in spec §11.
- **4a:** `3860f0d`. The registry prune and appends hold a soft lock, the repo lock generalized
  to `lock_path`. Scenario 24 Test 23e holds the lock from outside in flock and symlink modes
  and checks the create waits and records its entry; the old code doesn't wait (118 ms).
- Tests ran through decoy tmux panes: full suite 28/28, exit 0. Old-code checks used throwaway
  worktrees.
