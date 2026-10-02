# TODO Index
> Auto-generated. Run `/todo lint` to regenerate.

## Pending (2)

### P1 - High
- [ ] [claude-subagent-worktrees](claude-subagent-worktrees.md) - Claude Code's subagent / EnterWorktree worktrees go through llm-wt (hooks, parent integration, guidance)

### P2 - Normal
- [ ] [claude-subagent-worktrees-ui](claude-subagent-worktrees-ui.md) - Show Claude's agent worktrees in lazy-llm (Worktrees tab tag + integrate, pane border ⎇×N, llmw picker)

## Done (7)

- [x] [status-unread-state-and-aggregate-counts](done/status-unread-state-and-aggregate-counts.md) - Unread" pane status (finished, not yet looked at) + per-status aggregate counts in status bars
- [x] [workspace-save-restore](done/workspace-save-restore.md) - Save lazy-llm workspaces to a manifest and rebuild them after the tmux server dies (lazy-llm restore)
- [x] [dashboard-manual-list-reordering](done/dashboard-manual-list-reordering.md) - Manual reordering of dashboard tree rows (Ctrl+Up/Down), scoped per tree level
- [x] [dashboard-reload-avoid-full-redraw](done/dashboard-reload-avoid-full-redraw.md) - Use fzf's reload() to avoid a full fzf relaunch on fold/toggle/refresh
- [x] [pane-border-identity-suffixes](done/pane-border-identity-suffixes.md) - AI pane border shows workspace - pane name - harness - model
- [x] [claude-notify-detail](done/claude-notify-detail.md) - Permission notifications name the conversation, the pending command, and the pane
- [x] [claude-notify-click-finished](done/claude-notify-click-finished.md) - Notifications — click to jump to the pane, "finished" notices, elicitation/subagent prompts

## Backlog (6)

### P3 - Low
- [-] [lazy-llm-refinement-pass](backlog/lazy-llm-refinement-pass.md) - Refinement pass over lazy-llm feature space and codebase
- [-] [pane-auto-naming-from-conversation](backlog/pane-auto-naming-from-conversation.md) - Auto-rename AI panes/workspaces from conversation content (hook and/or LLM call)
- [-] [resume-adapters-codex-grok](backlog/resume-adapters-codex-grok.md) - Resume adapters for codex and grok in lazy-llm restore

### P4 - Someday
- [-] [per-pane-cache-cross-server](backlog/per-pane-cache-cross-server.md) - Per-pane cache files are keyed by %N and shared across tmux servers
- [-] [saved-tab-multi-select](backlog/saved-tab-multi-select.md) - Saved tab: multi-select restore

### P5 - Wishlist
- [-] [restore-into-live-workspace](backlog/restore-into-live-workspace.md) - Restore a removed pane into a live workspace / revert a workspace to its saved layout
