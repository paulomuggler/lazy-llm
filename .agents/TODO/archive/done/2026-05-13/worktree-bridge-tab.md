---
slug: worktree-bridge-tab
title: Worktree bridge tab in unified dashboard (lazy-llm ↔ worktree view + cleanup)
priority: P2
status: done
created: 2026-05-13
updated: 2026-05-13
depends-on: [dashboard-shell-and-sessions-tab, worktree-per-task-primitive]
tags: [enhancement, git, worktree, dashboard, gh, lazygit]
commits: [fa2d128]
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

- [x] Worktrees tab in unified dashboard lists all worktrees in the current repo with: path, branch, dirty status, ahead/behind vs default branch, attached lazy-llm session (if any), PR state (when `gh` + GitHub remote available)
- [x] `Enter` spawns or switches to a lazy-llm **session** (not just a pane) in the highlighted worktree (composes with [[worktree-per-task-primitive]] via `lazy-llm -W <branch>`)
- [x] `n` creates a new worktree + spawns a session bound to it, all from inside the tab (prompts for branch via fzf, delegates to `lazy-llm -W`)
- [x] `g` launches `lazygit` for lifecycle operations (nested `tmux display-popup` with `lazygit -p <path>`)
- [x] `K` triggers the cleanup flow:
  - [x] Pre-flight warnings shown for: dirty working tree, ahead of default, no upstream, attached lazy-llm session, open PR
  - [x] Separate confirmations for worktree removal vs branch deletion (branch default pre-selects "no" when warnings present)
  - [x] Atomic execution: kills lazy-llm session, removes worktree, optionally deletes branch
  - [x] Tab refreshes after cleanup
- [x] PR state lookup is best-effort and silent on failure (only attempted when `gh` exists AND remote is github.com)
- [x] No new global tmux/nvim keybindings added (Worktrees tab is the 3rd tab inside the existing Prefix+S dashboard)
- [ ] Manual verify: on a repo with 2+ worktrees including one dirty + one with an open PR, cleanup of the dirty one shows all expected warnings; cleanup of a clean worktree skips dirty-related warnings
- [x] Tests in `tests/scenarios/14-worktree-bridge-tab-unit.sh` cover: default-branch resolution, gather output format, detached-HEAD skipping, dirty marker, cleanup happy path with branch deletion, cleanup preserving branch, force cleanup against dirty worktree, dashboard structural wiring (16 assertions)

Performance for ~10 worktrees deferred to manual evaluation — git calls are per-worktree and not parallelized in v1; can profile and optimize if it bites.

## Verify Plan

### Structural / code-site — covered by 14-worktree-bridge-tab-unit.sh
- [x] Three new lib helpers defined: `lazy_llm_default_branch`, `lazy_llm_gather_worktrees`, `lazy_llm_cleanup_worktree`
- [x] `render_worktrees_tab` in `llm-dashboard` calls `lazy_llm_gather_worktrees` (placeholder gone)
- [x] Four new dispatch verbs: `action:worktree-open:*`, `action:worktree-new`, `action:worktree-lazygit:*`, `action:worktree-cleanup:*`
- [x] Main-loop allowlist extended for all four verbs
- [x] Help text mentions Worktrees tab actions including `g` (lazygit)

### Behavioral — covered in unit test (16 assertions)
- [x] `lazy_llm_default_branch` returns main / master fallback / origin/HEAD lookup
- [x] `lazy_llm_gather_worktrees` emits 7-column tab-separated rows per worktree
- [x] Detached-HEAD worktrees skipped from gather output
- [x] Dirty marker `*` shown for dirty worktrees, blank for clean
- [x] `lazy_llm_cleanup_worktree` removes the worktree and deletes the branch when `delete_branch=yes`
- [x] Cleanup preserves branch when `delete_branch=no`
- [x] Cleanup with `force=yes` succeeds against dirty worktrees

### Static
- [x] `bash -n` clean on `llm-dashboard` and `lazy-llm-lib.sh`

### Regression
- [x] All 5 prior unit tests still green (09, 10, 11, 12, 13)

### Live smoke (live, non-disruptive)
- [x] `lazy_llm_default_branch` against this repo returns `main`
- [x] `lazy_llm_gather_worktrees` against this repo emits the expected row for the main checkout (dirty=*, ahead=N reflecting recent commits)

### Manual (deferred)
- [ ] Open dashboard → `2` → Worktrees tab renders this repo's worktrees with state columns
- [ ] `Enter` on a worktree row opens/attaches the lazy-llm session via `-W`
- [ ] `n` prompts for branch, creates worktree+session
- [ ] `g` opens lazygit (verify it shows the worktree's state)
- [ ] `K` on a dirty worktree shows the dirty warning; choosing `yes` removes it; branch-delete defaults to "no" on warnings
- [ ] PR state column populated when `gh` is authenticated and remote is github.com

## Work Report

**Date:** 2026-05-13

### What was done
- Replaced the Worktrees tab placeholder in `llm-dashboard` with a real bridge view that lists worktrees with state columns, supports open/attach/new/lazygit/cleanup actions, and renders a live `git status -sb` + recent-log preview
- Added three lib helpers: `lazy_llm_default_branch`, `lazy_llm_gather_worktrees`, `lazy_llm_cleanup_worktree`
- Wired four new dispatch verbs and extended the main-loop allowlist
- Implemented the atomic cleanup safety-prompt flow as a dashboard-local helper `_dashboard_worktree_cleanup_flow` (fzf-bound prompts can't live in the lib)
- 16 new unit assertions across all three helpers + dashboard structural wiring
- README + USAGE describe the new tab and its actions

### How it was done
- **Worktree listing**: parsed `git worktree list --porcelain` block-by-block, emitting one tab-separated row per worktree with 7 columns (path, branch, dirty, ahead, behind, session, PR state). Per-worktree calls to `git status --porcelain`, `git rev-list --left-right --count`, the existing `lazy_llm_find_session_for_path`, and (best-effort) `gh pr view`
- **Default branch resolution**: tried `git symbolic-ref --short refs/remotes/origin/HEAD` first, fell back to local `main`/`master` checks, then ultimately to `"main"`
- **Cleanup atomicity**: the order is `kill session → remove worktree → delete branch (optional)`. The repo path is cached BEFORE removing the worktree (via `git worktree list --porcelain | head -1`) — caught by a unit test when the initial implementation tried to query the just-removed worktree's toplevel
- **Safety prompts**: collected warnings in a single pass (dirty, ahead, no-upstream, attached session, open PR), displayed them via a multi-line fzf header, then asked two separate yes/no confirms. Branch-delete confirm defaults to `no` if any warnings were shown, `yes` otherwise
- **`--force` propagation**: `force=yes` is set when ANY warning is present, so the worktree-remove and the branch-delete both pick up the appropriate aggressive flags (`--force` / `-D`). Means clean cleanups stay safe, but acknowledged data loss continues through

### Decisions made
- **Main checkout included in gather output.** The dashboard shows everything in `git worktree list`; the main checkout can't be removed by `git worktree remove` (refused), so attempting `K` on it surfaces git's own error — natural guardrail without us needing to filter
- **Detached-HEAD worktrees skipped.** Without a branch, the `Enter` open flow can't compose with `-W` and cleanup can't delete a "branch". Cleaner to omit them
- **`lazy_llm_cleanup_worktree` lives in the lib; the safety prompts live in the dashboard.** Clean separation: the lib helper is the pure side-effect primitive that can be called from anywhere (scripts, future tools); the dashboard owns the interactive UX
- **PR state best-effort only.** Per-worktree `gh pr view` call when `gh` is available and remote is GitHub. ~100ms overhead per worktree; acceptable for typical 1–5 worktree counts. Silent on failure
- **Preview shows git status + log, not AI pane content.** Different mental model from the Sessions tab — for worktrees, what you want to see is "what's the state of this branch", not "what's the AI doing"

### Commits
- `fa2d128` — feat(dashboard): worktree bridge tab with atomic cleanup

### Files changed
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — three new helpers (~120 lines added)
- `lazy-llm-bin/.local/bin/llm-dashboard` — `render_worktrees_tab` rewritten (~70 lines, replacing placeholder), four new dispatch verbs (~30 lines), `_dashboard_worktree_cleanup_flow` (~50 lines), help text expanded
- `tests/scenarios/14-worktree-bridge-tab-unit.sh` (new, ~210 lines) — 16 assertions
- `README.md` — Worktree dashboard subsection added
- `docs/USAGE.md` — one row added for the cleanup action

### Sources Consulted
- None — followed existing project conventions

### Follow-up
- **Performance optimization**: `gather_worktrees` is sequential, ~100ms per worktree when `gh` is involved. For repos with many worktrees this could feel sluggish. Easy to parallelize per-worktree column lookups via background jobs + wait; defer to [[lazy-llm-refinement-pass]] if it bites
- **The PR state lookup uses `gh -R <remote-url> pr view <branch>`**. If the user has `gh` configured for a different default repo than the lazy-llm checkout, this avoids that ambiguity. Worth noting in case anyone reports weirdness
- **`lazy_llm_gather_worktrees` has trailing `return 0`** — added to suppress non-zero exits from the trailing `[[ -n "$path" ]]` check. Same fix-pattern that `find_session_for_path` could benefit from (flagged in the previous task's follow-up)

## Verify Report

**Date:** 2026-05-13

### Summary
All structural, behavioral, static, and regression checks pass. 16 unit assertions in the new test + 5 prior unit tests all green. Live smoke against this repo confirms `lazy_llm_default_branch` and `lazy_llm_gather_worktrees` produce expected output. The interactive popup flows (open/new/lazygit/cleanup chains) are deferred to human validation.

### Tests
- 14-worktree-bridge-tab-unit: 16/16 ✓ (after fixing the cleanup-after-remove bug caught by Test 6)
- 09: ✓ 10: ✓ 11: ✓ 12: ✓ 13: ✓

### Bug caught during verify
First implementation of `lazy_llm_cleanup_worktree` derived `$repo` from `git -C "$path" rev-parse --show-toplevel`, but `$path` is the worktree being removed — after the remove, the path is gone, so the subsequent `git branch -d` against `$repo=""` silently failed. Fixed by caching the **main** repo path from `git worktree list --porcelain | head -1` before doing the remove. Test 6 verifies branch deletion works.

### Deferred to human validation
- Live dashboard UI: open via `Prefix+S → 2`, navigate, exercise each action
- PR state column population (requires `gh` + GitHub remote in a test repo)
- Lazygit nested-popup composition
- Cleanup safety-prompt flow end-to-end with various warning combinations

## Human Validation

**Branch / commits:** main / `fa2d128`

### Checks

- [ ] **Worktrees tab renders.** From an attached lazy-llm session, press `Prefix+S` then `2`. Confirm the Worktrees tab shows at least the main checkout with its branch, dirty marker, ahead/behind, and (if any) attached session.
- [ ] **`Enter` opens/attaches session.** Highlight a worktree row that has a `lazy-llm -W` session already pointing there, press `Enter` — confirm the dashboard closes and tmux switches to that session.
- [ ] **`n` creates worktree + session.** From the Worktrees tab, press `n`, type a throwaway branch name (e.g. `_v_hv_smoke`), `Enter`. Confirm a new worktree is created at `.worktrees/_v_hv_smoke`, a new tmux session is spawned, and you're attached. Clean up afterward.
- [ ] **`g` launches lazygit.** Highlight a worktree, press `g`. Confirm `lazygit` opens in a nested popup pointed at that worktree (you should see its branches/log/status).
- [ ] **`K` cleanup with warnings.** Create a dirty worktree (e.g. `git worktree add .worktrees/_v_dirty -b _v_dirty && touch .worktrees/_v_dirty/junk`). From the Worktrees tab, highlight it and press `K`. Confirm the dirty warning is shown; confirm the "delete branch" prompt defaults to `no`; complete the cleanup and verify the worktree + branch state matches your choices.

### Design Decisions

- **PR state lookup adds ~100ms per worktree** when `gh` is configured. For repos with many worktrees this could feel sluggish on tab refresh. Acceptable for v1; flag if it bites.
- **Main checkout is included in the listing**, not filtered out. Trying to `K` it will fail because git refuses to remove the main worktree — natural guardrail.
- **Detached-HEAD worktrees are silently skipped** from the listing. Edge case; documented but invisible to most users.
- **Preview pane shows `git status` + recent log**, not AI pane content (different from Sessions tab). For worktrees, the relevant context is the branch state, not the AI's current output.
