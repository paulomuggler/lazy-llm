---
slug: per-pane-cache-cross-server
title: Per-pane cache files are keyed by %N and shared across tmux servers
priority: P4
status: backlog
created: 2026-09-27_16:13
updated: 2026-09-27_16:13
depends-on: []
tags: [status, robustness]
commits: []
---

# Per-pane cache files are keyed by %N and shared across tmux servers

## Context
Found during workspace-save-restore. `~/.cache/lazy-llm/{status,unread,busy,model,conv}/<pane_id>` are keyed by the tmux pane id alone, and a second tmux server (a test sandbox, a `-L` socket) reuses the same `%N` ids. The pid guard stops a wrong read, but a hook in the other server's `%N` overwrites, and on the next read deletes, the live pane's record. Key the files by server too (e.g. `<server pid>-<pane id>`), or live with it.
