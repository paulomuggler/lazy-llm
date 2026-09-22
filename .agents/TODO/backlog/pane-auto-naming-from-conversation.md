---
slug: pane-auto-naming-from-conversation
title: Auto-rename AI panes/workspaces from conversation content (hook and/or LLM call)
priority: P3
status: backlog
created: 2026-09-23_00:58
updated: 2026-09-23_00:58
depends-on: []
tags: [enhancement, dashboard, naming, hooks]
commits: []
---

# Auto-rename AI panes/workspaces from conversation content

## Context

Investigated during the dashboard layout/status redesign work whether pane labels
could show Claude Code's own descriptive session title/summary (the kind you see in
`claude --resume`'s picker) instead of just the tool name ("claude").

**Findings (see dashboard-layout-status-redesign and the live session for full
detail):**
- Claude Code stores these summaries in
  `~/.claude/projects/<project-slug>/sessions-index.json` (`sessionId` → `summary`).
- There is no reliable EXTERNAL way to map "this specific running pane" → "that
  session ID" — no environment variable, no CLI flag on the running process, no held-
  open file descriptor exposes it (checked `/proc/<pid>/environ`, `/proc/<pid>/cmdline`,
  `/proc/<pid>/fd/*`).
- The only available heuristic (most-recently-modified `.jsonl` for the project
  directory) works for a single active session, but breaks exactly where lazy-llm
  needs it most: multiple simultaneous panes/workspaces in the same project directory.
- `summary` also isn't populated until the conversation has progressed enough to
  generate one — wouldn't be available immediately for a freshly-opened pane anyway.

User's own suggestion, to explore later rather than block on: a **hook-driven**
approach — since Claude Code hooks (`Notification`, `Stop`, etc.) already run with
correct pane/session context (see `dotfiles/claude/dot-claude/hooks/
lazy-llm-status-notify.sh`, which resolves `$TMUX_PANE` correctly from inside a hook),
a hook could:
1. Write its own `session_id` (available in the hook's JSON stdin payload, confirmed
   present in the schema fetched from `code.claude.com/docs/en/hooks` during the
   original hook-status task) to a pane-keyed file, alongside the existing
   `~/.cache/lazy-llm/status/<pane_id>` status file.
2. Either derive a short slug directly from `sessions-index.json`'s `summary` once one
   exists, or make an additional LLM call (cheap model, small prompt) summarizing the
   last few turns into a short slug on some cadence (e.g. every N turns, not every
   hook fire — cost/latency tradeoff to design).
3. Have the dashboard tree / pane-border-format / tmux window name pick up that slug.

## Acceptance Criteria (once picked up — not scoped in detail yet)

- [ ] Design doc or plan resolving: hook event(s) to key off, slug source (existing
      `summary` field vs. a fresh LLM call), update cadence, and where the slug surfaces
      (dashboard tree row, pane-border, tmux window name — pick one or more)
- [ ] Cost/latency impact assessed if an LLM call is involved (this must not add
      noticeable latency to the hook path, which already runs synchronously in Claude
      Code's own flow — see the existing hook's own "must not block Claude's execution"
      constraint)
- [ ] Fallback behavior when no slug is available yet (freshly-opened pane) — should
      degrade to today's plain tool name, not show empty/broken text

## Key Files

- `dotfiles/claude/dot-claude/hooks/lazy-llm-status-notify.sh` (dev-env repo) — existing
  hook this would likely extend or sit alongside
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — pane resolution helpers
- `lazy-llm-bin/.local/bin/llm-dashboard`, `llm-pane-border` — where a slug would render
