# TODO Index
> Auto-generated. Run `/todo lint` to regenerate.

## Pending (0)

## Done (8)

- [x] [dashboard-early-input-quits](done/dashboard-early-input-quits.md) - Fix a key pressed before the dashboard list loads closing the dashboard
- [x] [workspace-save-restore](done/workspace-save-restore.md) - Save lazy-llm workspaces to a manifest and rebuild them after the tmux server dies (lazy-llm restore)
- [x] [pane-border-identity-suffixes](done/pane-border-identity-suffixes.md) - AI pane border shows workspace - pane name - harness - model; Claude hooks moved into lazy-llm's own plugin
- [x] [dashboard-escape-abort-killswitch](done/dashboard-escape-abort-killswitch.md) - Fix Esc-during-subprompt silently killing the whole dashboard
- [x] [dashboard-layout-status-redesign](done/dashboard-layout-status-redesign.md) - Dashboard layout + status bar redesign in response to user feedback
- [x] [dashboard-manual-list-reordering](done/dashboard-manual-list-reordering.md) - Manual reordering of dashboard tree rows (Ctrl+Up/Down), scoped per tree level
- [x] [status-unread-state-and-aggregate-counts](done/status-unread-state-and-aggregate-counts.md) - "Unread" pane status + per-status aggregate counts in status bars
- [x] [dashboard-reload-avoid-full-redraw](done/dashboard-reload-avoid-full-redraw.md) - Use fzf's reload() to avoid a full fzf relaunch on fold/toggle/refresh

## Backlog (8)

### P1 - High
- [-] [worktree-concurrency-mode](backlog/worktree-concurrency-mode.md) - Optional per-pane worktree isolation for concurrent AI panes in one workspace

### P2 - Normal
- [-] [fix-send-scenarios-leader-key](backlog/fix-send-scenarios-leader-key.md) - Fix scenarios 01-07: they assume a backslash leader and window 0

### P3 - Low
- [-] [lazy-llm-refinement-pass](backlog/lazy-llm-refinement-pass.md) - Refinement pass over lazy-llm feature space and codebase
- [-] [pane-auto-naming-from-conversation](backlog/pane-auto-naming-from-conversation.md) - Auto-rename AI panes/workspaces from conversation content (hook and/or LLM call)
- [-] [resume-adapters-codex-grok](backlog/resume-adapters-codex-grok.md) - Resume adapters for codex and grok in lazy-llm restore

### P4 - Someday
- [-] [per-pane-cache-cross-server](backlog/per-pane-cache-cross-server.md) - Per-pane cache files are keyed by %N and shared across tmux servers
- [-] [saved-tab-multi-select](backlog/saved-tab-multi-select.md) - Saved tab: multi-select restore

### P5 - Wishlist
- [-] [restore-into-live-workspace](backlog/restore-into-live-workspace.md) - Restore a removed pane into a live workspace / revert a workspace to its saved layout
