---
slug: pane-status-detection
title: Pane status detection helper + llm-status integration
priority: P1
status: in-progress
created: 2026-05-13
updated: 2026-05-13
depends-on: []
tags: [enhancement, status-detection, llm-status, library, tests]
commits: [2301c86]
---

# Pane status detection helper + llm-status integration

## Context

First slice of the unified dashboard work. Build the foundation: a shared helper that classifies an AI pane's current state (`working|idle|waiting|unknown`) by scraping its content, with per-tool regex patterns so detection isn't Claude-specific. Then wire it into `llm-status` so the tmux statusline shows status glyphs immediately — independent of any dashboard UI.

Inspired by `nielsgroen/claude-tmux`'s detection model. Default Claude patterns:
- **Working:** input prompt glyph (`❯`) + "ctrl+c to interrupt" hint
- **Idle:** input prompt glyph without interrupt hint
- **Waiting:** contains `[y/n]` / `[Y/n]` / numbered choice prompts (`1.`, `2.`, `3.`)
- **Unknown:** anything else

Pattern table should be config-driven (keyed by tool name) so claude / gemini / codex / grok / aider can each have their own set.

This task has **no UI changes** — the only user-visible difference is richer tmux statusline output. That keeps the surface small and gives the dashboard tasks a working foundation to build on.

## Key Files

- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — add `lazy_llm_detect_pane_status <pane_id> [tool]` helper + pattern table
- `lazy-llm-bin/.local/bin/llm-status` — consume the helper; render glyphs like `[claude●] gemini◐`
- `tests/scenarios/` — add a regex-only test exercising fixture pane content → expected status (no live tmux needed)
- `tests/fixtures/` (or wherever fixtures live) — add captured pane content samples for each status / tool combination

## Acceptance Criteria

- [x] `lazy_llm_detect_pane_status` helper in `lazy-llm-lib.sh` returns one of `working|idle|waiting|unknown`
- [x] Per-tool pattern table — at minimum claude (with the patterns above); structure supports adding gemini/codex/grok/aider entries via a single `case` block in `lazy_llm_detect_status_from_content`
- [x] When tool name is omitted or unknown, falls back to the claude patterns (default branch in the case statement)
- [x] `llm-status` consumes the helper; statusline output includes status glyphs per active AI pane (e.g. `[claude●] gemini◐`)
- [x] Glyph mapping documented and consistent: `●` working, `○` idle, `◐` waiting, `?` unknown
- [x] Tests added under `tests/scenarios/10-pane-status-detection.sh` that feed canned pane content through the detection helper and assert the expected status (17 assertions, all passing)
- [x] No live tmux required for the detection unit tests (fixtures piped through stdin)
- [x] No regressions in existing `llm-status` output for users who have no AI panes (no-AI branch unchanged)
- [ ] Manual verify: with `lazy-llm` running and an active claude session, the tmux statusline shows a status glyph reflecting reality (idle when not generating, working when claude is mid-stream)
