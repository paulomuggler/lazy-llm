---
slug: claude-worktree-pane-id-reuse
title: A leftover Claude worktree can look owned by an unrelated pane after a tmux server restart (pane ids reused)
priority: P4
status: backlog
created: 2026-10-02_20:10
updated: 2026-10-02_20:10
depends-on: []
tags: [worktree, dashboard]
---

# Claude worktree ownership vs reused pane ids

## Context
From `claude-subagent-worktrees-ui` (2026-10-02). Claude worktrees record the owning tmux pane as
`branch.<b>.lazyLlmPane=%N`. tmux pane ids restart from %0 with a new server, so after a restart a
leftover worktree can show as owned by an unrelated new pane (Worktrees tab owner, border ⎇×N).
`lazyLlmSession` (the Claude session id) is recorded too. A guard could compare it with the
pane's current conversation (`lazy_llm_set_pane_conv` / the pane's recorded session), or record
the tmux server's start time alongside the pane id.

## Acceptance Criteria
- [ ] A Claude worktree whose recorded pane id now belongs to another conversation or server shows as orphaned
