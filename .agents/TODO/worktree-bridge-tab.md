---
slug: worktree-bridge-tab
title: Worktree bridge tab in unified dashboard (lazy-llm ↔ worktree view + cleanup)
priority: P2
status: pending
created: 2026-05-13
updated: 2026-05-13
depends-on: [unified-llm-dashboard, worktree-per-task-primitive]
tags: [enhancement, git, worktree, dashboard, gh, lazygit]
commits: []
---

# Worktree bridge tab in unified dashboard

## Context

The third tab inside the [[unified-llm-dashboard]] — a **bridge view** between git worktrees and lazy-llm sessions.

### Why a bridge, not a full worktree manager

`lazygit` (v0.58+) already provides a full-featured Worktrees panel with `n` (new), `<space>` (switch), `o` (open in editor), `d` (remove with proper cleanup), `/` (filter), plus `w` from the Branches view for branch-driven worktree options. Reimplementing worktree lifecycle in bash would be reinventing the wheel.

What lazygit **cannot** show:
- Which worktree currently has an active lazy-llm session attached
- PR state from GitHub (lazygit doesn't do PRs; that's `gh`)
- One-keystroke "spawn a lazy-llm workspace in this worktree" action

That's the gap this tab fills. Lifecycle CRUD that lazygit already handles well can be delegated by launching `lazygit` from inside the tab.

### Tab contents

Columns:
| Column | Source |
|---|---|
| Path | `git worktree list --porcelain` |
| Branch | same |
| Dirty? | `git -C <path> status --porcelain` (non-empty → dirty) |
| Ahead/behind vs default branch | `git -C <path> rev-list --left-right --count <default>...HEAD` |
| lazy-llm session | scan tmux sessions for `@lazy_llm=1` whose first pane's `pane_current_path` is the worktree path |
| PR state | `gh pr view --json state,mergeable -q '.state + " " + .mergeable'` when remote is GitHub and `gh` is available |

### Worktree binding is session-scoped

A worktree is bound to a lazy-llm **session**, never to a pane. All panes in a worktree-bound session share that working directory. Within such a session, multiple AI panes can coexist (existing tabbing behavior) — they all share the worktree. See [[worktree-per-task-primitive]] for the rationale.

This shapes the tab's actions: every "open in worktree" verb means **session**, not pane.

### Actions (single-letter, popup-scoped)

- `Enter` — open / attach a lazy-llm session in the highlighted worktree (uses [[worktree-per-task-primitive]] machinery; spawns a new session if none exists, switches/attaches if one is already pointed there)
- `n` — **new worktree + session**: prompt for a branch name (or pick from existing branches), create the worktree via [[worktree-per-task-primitive]], spawn a session bound to it
- `g` — launch `lazygit` (lifecycle ops delegated there: press `w` from branches, or navigate to the Worktrees panel)
- `K` — **full cleanup of highlighted worktree** (see safety prompt flow below)
- `/` — filter
- `R` — refresh
- `q`/`Esc` — close (or back to previous tab)

### Cleanup action (`K`) — safety prompts

This is the one operation worth implementing here rather than delegating to lazygit, because it needs to atomically tear down state across **three subsystems** (filesystem worktree, git branch, lazy-llm tmux session).

Flow:
1. **Pre-checks and warnings** (all shown before any prompt; abort if user cancels):
   - If working tree is dirty → warn ("Worktree has uncommitted changes")
   - If branch is ahead of remote/default → warn ("Branch is N commits ahead of `<default>` — these will be lost if the branch is deleted")
   - If branch has no upstream → warn ("Branch has no upstream — local-only commits will be lost")
   - If a lazy-llm session is attached → note it ("Will also kill lazy-llm session `<name>`")
   - If an open PR exists → warn ("Open PR #N — branch deletion may close it remotely")
2. **Confirm worktree removal** (y/N) — if no, abort
3. **Confirm branch deletion** (y/N) — separate, optional. Default `N` if there were any of the "data loss" warnings above; `y` if clean
4. Execute atomically:
   - Kill attached lazy-llm session (if any) via existing kill helpers
   - Remove worktree (`git worktree remove --force` if dirty was confirmed, else plain `git worktree remove`)
   - Delete branch only if confirmed (`git branch -D` if force-needed, else `-d`)
5. Refresh the tab

Implementation note: the confirmation prompts can use `gum confirm` if available, otherwise a small inline yes/no reader. Either way, the dashboard must stay responsive (no global tmux/nvim binding leaks).

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` (or whatever the unified dashboard entrypoint is named) — add the worktrees tab
- `lazy-llm-bin/.local/bin/lazy-llm-lib.sh` — worktree introspection helpers, session-attachment matching helper, cleanup helper (atomic teardown)
- Possibly `lazy-llm-bin/.local/bin/llm-worktree-cleanup` if extraction is warranted

## Acceptance Criteria

- [ ] Worktrees tab in unified dashboard lists all worktrees in the current repo with: path, branch, dirty status, ahead/behind vs default branch, attached lazy-llm session (if any), PR state (when `gh` + GitHub remote available)
- [ ] `Enter` spawns or switches to a lazy-llm **session** (not just a pane) in the highlighted worktree (composes with [[worktree-per-task-primitive]])
- [ ] `n` creates a new worktree + spawns a session bound to it, all from inside the tab (no need to exit to a shell)
- [ ] `g` launches `lazygit` for lifecycle operations (worktree create/switch/remove/open-in-editor handled there)
- [ ] `K` triggers the cleanup flow:
  - [ ] Pre-flight warnings shown for: dirty working tree, ahead of upstream/default, no upstream, attached lazy-llm session, open PR
  - [ ] Separate confirmations for worktree removal vs branch deletion
  - [ ] Atomic execution: kills lazy-llm session, removes worktree, optionally deletes branch — all-or-nothing where possible
  - [ ] Tab refreshes after cleanup
- [ ] PR state lookup is best-effort and silent on failure (no errors when `gh` isn't installed or remote isn't GitHub)
- [ ] Performance: tab loads in <1s for a repo with ~10 worktrees (per-worktree git calls batched / parallelized where reasonable)
- [ ] No new global tmux/nvim keybindings added
- [ ] Manual verify: on a repo with 2+ worktrees including one dirty + one with an open PR, cleanup of the dirty one shows all expected warnings; cleanup of a clean worktree skips dirty-related warnings
- [ ] Tests in `tests/` cover: session-attachment detection, cleanup atomicity (mock `git` and `tmux` calls)
