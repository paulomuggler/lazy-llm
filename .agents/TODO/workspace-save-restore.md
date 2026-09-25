---
slug: workspace-save-restore
title: Save lazy-llm workspaces to a manifest and rebuild them after the tmux server dies (lazy-llm restore)
priority: P1
status: pending
created: 2026-09-25_20:44
updated: 2026-09-25_20:44
depends-on: []
tags: [resilience, restore, tmux, dashboard, design]
commits: []
---

# Workspace save/restore

## Context

On 2026-09-25 the whole default tmux server died, taking every lazy-llm workspace with it. Root
cause is outside lazy-llm: the server lived in the systemd scope of the Ghostty tab it was first
started from, and closing that tab killed the scope (full write-up and options in the dev-env
repo: `.agents/TODO/backlog/tmux-server-outside-terminal-cgroup.md`). The user decided against
re-plumbing how tmux is started and wants **lazy-llm itself to save and restore its workspaces**.
No work was lost (`claude --resume` recovers every conversation), but the workspace layout was:
which repos had workspaces, which AI panes each had, their names, order, fold state, and which
conversation each pane was on.

## Why tmux-resurrect can't do this

Resurrect restores tmux shape (sessions, windows, layouts, cwd, a whitelist of commands), but
not tmux user options or pane IDs. That is exactly where lazy-llm keeps its state:

| State | Where it lives | Survives resurrect? |
|---|---|---|
| Workspace marker | session `@lazy_llm` | no → workspace invisible to dashboard (`lazy_llm_gather_sessions` filters on it) |
| AI pane list, tools, index | window `@AI_PANES`, `@AI_TOOLS`, `@AI_PANE_IDX`, `@AI_PANE_ID`, `@AI_TOOL`, `@AI_PANE` | no, and the `%N` pane IDs are reassigned anyway |
| Prompt pane | window `@PROMPT_PANE_ID`, `@PROMPT_PANE` | no → `llm-send` can't find its AI pane |
| Hidden AI panes | window `@AI_HOLD_WIN`, hold window `@lazy_llm_hold` | no → `_hold_N` windows come back as plain windows |
| Display names | window `@AI_PANE_NAMES` | no |
| Dashboard order / folds | server `@lazy_llm_ws_order`, `@lazy_llm_collapsed` | no |
| Per-pane model | `$_LAZY_LLM_MODEL_DIR/<pane_id>` files | keyed by the old pane ID → stale |
| Claude conversation | only in argv when the pane was started with `--resume <id>` | fresh panes have no id to resume |
| Prompt buffer | `nvim … .lazy-llm/prompts/prompt-*.md` with swap/undo `--cmd` flags | comes back as plain `nvim` |

Also: restoring a snapshot while same-named sessions are live makes resurrect **merge** into them
(missing panes split into existing windows, saved layouts re-applied), which mangles the live
workspaces.

## Direction (to be refined in the plan phase)

Rebuild through lazy-llm's own launcher rather than replaying tmux geometry: lazy-llm already
knows how to build a workspace (`lazy-llm -s -d -t`, `llm-add`, hold windows), so restore =
re-run that per workspace with the right resume command per pane, then re-apply names, order and
folds.

1. **Capture conversation IDs.** `llm-claude-hook` already receives `session_id` (and
   `transcript_path`) in every payload; record it per pane (e.g. on SessionStart, which also
   fires after `/clear` and `--resume`, so it tracks the current conversation). Decide the
   equivalent for other tools (gemini, codex…) or fall back to starting them fresh.
2. **Manifest.** One file under XDG state (e.g. `~/.local/state/lazy-llm/`), per workspace:
   session name, dir, worktree branch if `-W`, dashboard position, fold state; per AI pane in
   order: tool, display name, model, conversation ID, visible vs held; current prompt file.
   Write it on state changes (launch, `llm-add`, `llm-remove`, rename, reorder, hook
   SessionStart) rather than on a timer.
3. **Don't clobber the good snapshot.** After a crash, the first fresh workspace must not
   overwrite the manifest that describes the lost ones (the failure mode of resurrect's `last`
   symlink under continuum). E.g. keep rotated snapshots, or never drop a workspace from the
   manifest just because its session is gone — only on an explicit kill via
   `llm-sessions --kill` / the dashboard.
4. **`lazy-llm restore`.** Rebuild every saved workspace that isn't live; skip (or offer to
   rename) names that already exist, never merge. Optional picker (`--pick`) to restore a subset.
   Reopen the saved prompt file with the usual swap/undo flags. A dashboard entry for "saved but
   not running" workspaces is a natural follow-up.
5. **Tests.** Headless restore test in `tests/`: build a workspace with 2+ AI panes (one held),
   names and folds, kill the server, restore, assert options and dashboard rows match.

## Related

- `backlog/pane-auto-naming-from-conversation.md`: display names are part of the manifest.
- `backlog/worktree-concurrency-mode.md`: per-pane worktrees would add a per-pane dir to the
  manifest if that lands first.
