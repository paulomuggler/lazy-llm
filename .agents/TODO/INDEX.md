# TODO Index
> Auto-generated. Run `/todo lint` to regenerate.

## Pending (1)

### P1 - High
- [ ] [workspace-save-restore](workspace-save-restore.md) - Save lazy-llm workspaces to a manifest and rebuild them after the tmux server dies (lazy-llm restore)

## Done (6)

- [x] [pane-border-identity-suffixes](done/pane-border-identity-suffixes.md) - AI pane border shows workspace - pane name - harness - model; Claude hooks moved into lazy-llm's own plugin
- [x] [dashboard-escape-abort-killswitch](done/dashboard-escape-abort-killswitch.md) - Fix Esc-during-subprompt silently killing the whole dashboard
- [x] [dashboard-layout-status-redesign](done/dashboard-layout-status-redesign.md) - Dashboard layout + status bar redesign in response to user feedback
- [x] [dashboard-manual-list-reordering](done/dashboard-manual-list-reordering.md) - Manual reordering of dashboard tree rows (Ctrl+Up/Down), scoped per tree level
- [x] [status-unread-state-and-aggregate-counts](done/status-unread-state-and-aggregate-counts.md) - "Unread" pane status + per-status aggregate counts in status bars
- [x] [dashboard-reload-avoid-full-redraw](done/dashboard-reload-avoid-full-redraw.md) - Use fzf's reload() to avoid a full fzf relaunch on fold/toggle/refresh

## Backlog (3)

### P1 - High
- [-] [worktree-concurrency-mode](backlog/worktree-concurrency-mode.md) - Optional per-pane worktree isolation for concurrent AI panes in one workspace

### P3 - Low
- [-] [lazy-llm-refinement-pass](backlog/lazy-llm-refinement-pass.md) - Refinement pass over lazy-llm feature space and codebase
- [-] [pane-auto-naming-from-conversation](backlog/pane-auto-naming-from-conversation.md) - Auto-rename AI panes/workspaces from conversation content (hook and/or LLM call)
