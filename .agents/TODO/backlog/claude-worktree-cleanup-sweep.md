---
slug: claude-worktree-cleanup-sweep
title: Observe whether Claude Code's cleanupPeriodDays sweep touches llm-wt's .worktrees/.claude/ worktrees
priority: P3
status: backlog
created: 2026-10-02_19:09
updated: 2026-10-02_19:09
depends-on: []
tags: [worktree, claude-plugin]
---

# Observe Claude Code's worktree cleanup sweep

## Context
Follow-up from `claude-subagent-worktrees` (spec `specs/claude-subagent-worktrees.md` §11).
Claude Code periodically sweeps worktrees left by subagents (`cleanupPeriodDays`). It's
believed to act on `.claude/worktrees/` only. llm-wt's live in `.worktrees/.claude/`, and if
the sweep goes through `WorktreeRemove`, `llm-wt claude-hook` refuses to lose work. Neither
belief was observed: the sweep runs on a days-long period.

## Acceptance Criteria
- [ ] Find out from Claude Code's docs/changelog/behavior what the sweep removes and how (git directly, or WorktreeRemove)
- [ ] If it can delete an llm-wt worktree holding commits, file a fix; otherwise record the finding in spec §11
