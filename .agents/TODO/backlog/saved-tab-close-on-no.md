---
slug: saved-tab-close-on-no
title: Saved tab — answering no/Esc in the forget and switch prompts closes the whole dashboard
priority: P3
status: backlog
created: 2026-10-02_20:10
updated: 2026-10-02_20:10
depends-on: []
tags: [dashboard]
---

# Saved tab: a "no" closes the dashboard

## Context
Found by the `claude-subagent-worktrees-ui` executor (2026-10-02), which fixed the same bug in the
Worktrees tab (Esc in the add-pane prompt, "keep" in the close dialog both quit the dashboard;
they're now ordinary branches). The Saved tab's forget and switch actions have the same pattern:
a non-affirmative answer falls through to quitting.

## Acceptance Criteria
- [ ] Declining or escaping the Saved tab's forget/switch prompts returns to the dashboard
- [ ] Covered by a scenario like the Worktrees-tab one
