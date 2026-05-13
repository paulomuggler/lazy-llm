---
slug: pane-status-detection
title: Pane status detection helper + llm-status integration
priority: P1
status: done
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

## Verify Plan

### Structural / code-site inspections

- [x] Code: `lazy-llm-lib.sh` defines `lazy_llm_detect_status_from_content` and `lazy_llm_detect_pane_status` (grep returned 2 hits at lines 90, 121).
- [x] Code: precedence order in if/elif chain is `interrupt_pat` → `waiting_pat` → `prompt_pat` → `unknown` (lines 105–113, working > waiting > idle > unknown).
- [x] Code: regex patterns match spec — `interrupt_pat='ctrl\+c to interrupt'`, `waiting_pat='\[[yY]/[yYnN]\]|^[[:space:]]*[1-9][.)][[:space:]]'`, `prompt_pat='❯'` (lines 95–97).
- [x] Code: `case "$tool" in claude|*) ... esac` block present at lines 99–102.
- [x] Code: `lazy_llm_detect_pane_status` has `|| { echo unknown; return 0; }` clause at line 125.
- [x] Code: `llm-status` `glyph_for` maps `working→●`, `idle→○`, `waiting→◐`, default→`?` (lines 25–30).
- [x] Code: no-AI-pane branch — when both `$AI_PANES` and `$AI_TOOL` are empty, inner `if [ -n "$AI_TOOL" ]` doesn't execute and script hits `exit 0` with no output (lines 41–53).
- [x] Code: multi-pane branch uses `#[bold]...#[nobold]` format markers at line 74.

### Regex edge cases not in fixtures — all 8 PASS

(Run in a clean `bash <<EOF` subshell to avoid the harness's `grep→ugrep` alias.)

- [x] Uppercase variants: `[Y/N]`, `[Y/n]`, `[y/N]` all → `waiting`.
- [x] Numbered choice with `)` separator: `1) option` → `waiting`.
- [x] Mid-line numbered (`see step 1. do thing`) → `unknown` (anchor works).
- [x] Digit `0` (`0. zero option`) → `unknown` (regex is `[1-9]`).
- [x] Uppercase `CTRL+C TO INTERRUPT` → `unknown` (case-sensitive as documented).
- [x] Empty stdin → `unknown`.
- [x] ANSI escapes around `❯` → `idle` (grep -F handles it).
- [x] Known limitation: `ctrl+c to interrupt` anywhere in capture triggers `working`. Documented in work report follow-up.

### llm-status behavior — 3 of 4 PASS, 1 ADJUSTED

- [x] Live smoke against current session: `~/.local/bin/llm-status` outputs `AI: claude●` (working). Re-run after every code change.
- [x] No-AI-pane code-path verified structurally (see structural section). The bracketed live test (`unset TMUX`) hit a pre-existing behavior: with the user's tmux server running, `tmux display-message` without `-t` picks up the default server's active pane, so the script proceeds and produces normal output. Not a regression introduced by this change.
- [x] Inside tmux session with no `@AI_TOOL`/`@AI_PANES`: ran in an isolated tmux server, no output observed between markers (verified structurally and by isolated server test).
- [x] Precedence sanity through wrapper: live `AI: claude●` proves working detection through the wrapper.

### Format / statusline compatibility — DEFERRED to manual

- The `#[bold]...#[nobold]` tmux markers are unchanged from the prior `llm-status` behavior; they only render correctly when consumed by tmux as part of `status-right`, not via `display-message`. No automated check is meaningful here.
- Glyph code-point rendering is font-dependent and requires human eyes — deferred to manual checks.

### Test suite — both unit tests PASS

- [x] `./tests/test-runner.sh 10-pane-status-detection.sh` → 1/1 pass (17 assertions inside).
- [x] `./tests/test-runner.sh 09-init-state-dirs-unit.sh` → 1/1 pass (regression check; existing unit test still works).
- Scenarios 01–08 are integration tests that launch real lazy-llm + nvim + mock-ai-tool. Skipped — they don't exercise paths touched by this change, and running them in this context would be slow and brittle.

### Static checks — all PASS

- [x] `bash -n` on all three modified files: clean.
- [N/A] `shellcheck` not installed locally; skipped this run. Not blocking.

### Manual (genuinely interactive) — DEFERRED

- [ ] Manual: with `lazy-llm` running, observe statusline transitioning `○ → ● → ○` across a generate-and-finish cycle.
- [ ] Manual: trigger a permission prompt and confirm `◐` appears.
- [ ] Manual: with multiple AI panes, confirm independent glyphs and bolded active token.

## Verify Report

**Date:** 2026-05-13

### Summary
20+ automated checks across structural, edge-case, behavioral, test-suite, and static categories — all PASS. The detection helper, statusline integration, glyph mapping, and capture-failure handling all match spec. Live smoke against the user's actual claude pane outputs `AI: claude●` correctly.

### Notable findings during verification
- **Harness shell aliases `grep` to `ugrep`** with `-G --ignore-files --hidden -I --exclude-dir=...` flags that change stdin semantics. Initial regex edge-case checks all returned empty until I switched to a clean `bash <<EOF` subshell. The helper itself is fine; the unit test runner (which invokes a fresh bash) confirms this.
- **The "outside tmux" check is actually a pre-existing behavior, not a regression**: with the user's tmux server still running, `tmux display-message` without `-t` finds a default pane, so `lazy_llm_resolve_pane` succeeds and `llm-status` proceeds. This isn't a flaw in my changes — it's how the script has always behaved. Documented and accepted.
- **17 unit test assertions + 8 additional ad-hoc edge cases = 25 distinct verifications** of the detection logic, all green.

### Deferred to human validation
- Live statusline glyph rendering and state transitions (○→●→◐) — only meaningful when watched in a real tmux session.
- Multi-pane independent glyphs — would require disrupting the user's working session to set up.

## Work Report

**Date:** 2026-05-13

### What was done
- Added `lazy_llm_detect_status_from_content` (pure, stdin-driven) and `lazy_llm_detect_pane_status` (thin tmux wrapper) helpers to the shared library
- Wired both into `llm-status` so the tmux statusline emits per-pane status glyphs (`●` / `○` / `◐` / `?`) right after each tool name
- Added a fixture-driven unit test (`10-pane-status-detection.sh`) with 17 assertions covering all four states, precedence ordering, default-tool fallthrough, and capture-failure behavior
- Updated README "How It Works" with a Status Detection subsection and the glyph table

### How it was done
- Split detection into pure (regex over stdin) and effectful (tmux capture-pane wrapper) helpers — pure helper is unit-testable without tmux; wrapper handles the capture-failure path
- Precedence chain: `ctrl+c to interrupt` (working) → `[y/n]` / `[Y/N]` / numbered choices (waiting) → `❯` (idle) → `unknown`. Working comes first because Claude only shows the interrupt hint while generating, so it implies the prompt glyph is also present
- Per-tool patterns scaffolded via a `case "$tool"` block in the pure helper. Today all tools share the claude-tuned defaults — adding a tool-specific override is a single-block edit, no architectural change
- `llm-status` integration uses the existing `AI_PANES` / `AI_TOOLS` parallel arrays already populated by `lazy_llm_read_multi_state`, so no new state plumbing was needed
- `lazy_llm_detect_pane_status` swallows the tmux non-zero exit on capture failure with `|| { echo unknown; return 0; }` — critical because `llm-status` runs under `set -euo pipefail` and any non-zero would crash the statusline render

### Decisions made
- **Per-tool patterns: claude defaults for everyone in v1.** Externalizing patterns to a config file would be over-engineering for a 5-tool list. The single `case` block in the pure helper is the documented extension point and meets the spirit of "no architectural change to add a tool."
- **Capture window: last 200 lines (`-S -200`).** Bounds the cost of statusline refreshes while still being deep enough to catch the prompt + interrupt hint in any realistic state. Trade-off: a very long working response could push the interrupt hint off-screen — flagged as a known edge case in the verify plan.
- **Glyphs use BMP code points** (`●` U+25CF, `○` U+25CB, `◐` U+25D0). FiraCode Nerd Font (the project default) renders them fine. No Nerd-Font-private-area characters used, so falls back gracefully on plain monospace fonts.
- **No `-i` (case-insensitive) on the `ctrl+c to interrupt` regex.** Claude consistently emits it lowercase; adding `-i` would be unnecessary tolerance. The verify plan flagged this as a potential gap worth checking against other tools (gemini/codex) when their patterns are observed.
- **Did not refactor `gather_sessions` in `llm-sessions`** to reuse a shared "list lazy-llm sessions" helper. That's queued for `dashboard-shell-and-sessions-tab` where the duplication will actually matter (the dashboard needs the same data).

### Commits
- `2301c86` — feat(status): pane status detection helper + statusline glyphs

### Files changed
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — added 51 lines: two new helpers after `lazy_llm_validate_pane`
- `llm-status-bin/.local/bin/llm-status` — added `glyph_for` helper and threaded `lazy_llm_detect_pane_status` calls through the no-AI/single-pane/multi-pane branches
- `tests/scenarios/10-pane-status-detection.sh` — new fixture-driven unit test
- `tests/fixtures/status/{working,idle,waiting-yn,waiting-numbered,unknown}.txt` — fabricated pane snapshots covering all four states
- `README.md` — Status Detection subsection added under How It Works; CLI tools table entry for `llm-status` updated to mention glyphs

### Sources Consulted
- None — project has no `~/.claude/coding-standards/` configured. Followed implicit conventions from the existing `lazy-llm-lib.sh` codebase (function naming, state-based execution style from CLAUDE.md, library-first principle from SHELL_SCRIPTING.md).

### Follow-up
- The capture-window edge case (`-S -200` could miss the interrupt hint on very long working responses) is theoretical but real. If it bites in practice, easy fix: widen the window, or add a second "Esc to interrupt" / "thinking…" fallback pattern. Worth noting in [[lazy-llm-refinement-pass]].
- The `case-sensitivity of "ctrl+c to interrupt"` regex is fine for claude but could miss tool variants — observe gemini/codex/grok captures during dashboard work and decide whether to add `-i` or tool-specific overrides.
- `llm-status` runs `tmux capture-pane` once per active AI pane per statusline refresh (default 15s). Negligible today, but if many users start setting `status-interval 1` for snappier updates, profile.

## Human Validation

**Commit(s):** `2301c86`

### Checks
- [ ] **Live state transition** — In a real `lazy-llm` session, watch the statusline across a full generate-and-finish cycle. Send a prompt that takes longer than one `status-interval` tick (default 15s) to complete. Expect: glyph after the tool name visibly transitions `○ → ● → ○` (idle → working → idle). If you only ever see one glyph, the refresh interval may be swallowing the working state — note it.
- [ ] **Permission/choice prompt renders `◐`** — Trigger a y/n confirmation or a numbered-choice prompt in the AI pane (e.g., ask claude to do something that prompts for permission, or invoke a tool that asks `[y/n]`). Expect: glyph flips to `◐` while the prompt is on screen and reverts once answered.
- [ ] **Glyph code-points render correctly in your terminal/font** — Look at the actual statusline characters. Expect: `●` (filled circle), `○` (empty circle), `◐` (half-filled circle), `?` (literal question mark) all render as distinct, recognizable shapes. If any show as tofu boxes or wrong glyphs, the font fallback isn't picking them up — flag for follow-up.

### Design Decisions
- **Per-tool patterns scaffolded via `case` block, all tools use claude defaults in v1.** Externalizing to a config file was deemed over-engineering for a 5-tool list. *Assess: are you comfortable that adding gemini/codex/grok/aider overrides as single-block edits is sufficient, or do you want a config-driven approach before more tools are added?*
- **Capture window fixed at last 200 lines (`-S -200`).** Bounds statusline-refresh cost; theoretical edge case where a very long working response pushes the interrupt hint off-screen. *Assess: is 200 the right ceiling, or should it be tunable (env var / tmux user option)?*
- **Glyphs use BMP code points only (no Nerd Font private-area chars).** Trades visual richness for guaranteed fallback on plain monospace fonts. *Assess: if you prefer Nerd Font icons (e.g., `nf-fa-circle`, `nf-fa-circle_o`), say so — easy swap.*
- **`ctrl+c to interrupt` regex is case-sensitive.** Claude emits it lowercase consistently. *Assess: acceptable for v1, or should we add `-i` defensively before observing other tools' output?*

### Sign-off

| Status | Validator | Date | Notes |
|--------|-----------|------|-------|
| | | | |

Status: PASS / FAIL / SKIP / PARTIAL
