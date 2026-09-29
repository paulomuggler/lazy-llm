---
slug: resume-adapters-codex-grok
title: Resume adapters for codex and grok in lazy-llm restore
priority: P3
status: backlog
created: 2026-09-27_16:13
updated: 2026-09-27_16:13
depends-on: []
tags: [restore, adapters]
commits: []
---

# Resume adapters for codex and grok in lazy-llm restore

## Context
Filed from workspace-save-restore (spec §15). `lazy-llm restore` resumes only claude panes; others restart fresh. The seam is two lib functions, `lazy_llm_tool_conv` (capture) and `lazy_llm_tool_launch_cmd` (resume): add a branch to each. codex resumes with `codex resume <id>` (capture its id from `~/.codex/sessions` or the process's open rollout file), and grok with `--resume <id>`. gemini only resumes by index or `latest`, so it's probably not worth it.
