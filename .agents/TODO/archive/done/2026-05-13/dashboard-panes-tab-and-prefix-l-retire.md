---
slug: dashboard-panes-tab-and-prefix-l-retire
title: Dashboard panes tab + retire Prefix+L
priority: P2
status: done
created: 2026-05-13
updated: 2026-05-13
depends-on: [dashboard-shell-and-sessions-tab]
tags: [enhancement, dashboard, llm-panes, keybindings, cleanup]
commits: [8504d66]
---

# Dashboard panes tab + retire Prefix+L

## Context

Third slice of the unified dashboard work. Add the **panes tab** to the dashboard (for the current session's AI panes: list + status glyphs + live preview + cycle/add/remove), then **retire `Prefix+L`** since the panes tab covers it. Either delete the standalone `llm-panes` script or keep it as a thin alias for `llm-dashboard --tab panes`.

This is the final consolidation step that completes the original `unified-llm-dashboard` vision: one popup binding, three tabs (sessions / panes / worktrees-placeholder), one entrypoint.

### Panes tab

Columns: pane index, tool name, pane ID, status glyph (from [[pane-status-detection]]), active marker.

Actions:
- `Enter` / `↵` — cycle to selected pane (becomes the visible AI pane)
- `a` — add new AI pane (existing `llm-add` flow, with tool picker)
- `K` — remove pane (with confirmation, existing `llm-remove` flow)
- `]` / `[` — cycle to next / prev pane without explicit selection
- `R` — refresh
- `q` / `Esc` — quit (or back to previous tab)
- Tab switching shared with sessions tab (`1`/`2`/`3`, `Tab`/`Shift-Tab`)

### Retiring `Prefix+L` and the standalone `llm-panes` script

Decide during planning:
- **Option A**: Delete `lazy-llm-bin/.local/bin/llm-panes` entirely; remove the `Prefix+L` binding.
- **Option B**: Keep `llm-panes` as a thin alias: `exec llm-dashboard --tab panes` (preserves muscle memory for anyone using it from the CLI); remove the `Prefix+L` binding.

In either case, the help text and READMEs must be cleaned up so neither documents the old binding.

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` (extend) — add panes tab
- `lazy-llm-bin/.local/bin/llm-panes` — delete or shrink to an alias
- `lazy-llm-bin/.local/bin/lazy-llm` — remove `Prefix+L` keybinding; update help text
- `README.md` / `USAGE.md` — remove all references to `llm-panes` / `Prefix+L`; add panes tab notes
- `tests/scenarios/` — extend dashboard tests to cover panes tab listing, switching, add/remove flows

## Acceptance Criteria

- [x] Panes tab implemented in `llm-dashboard` with columns: index, tool, status glyph, active marker, pane ID (5 fields, ID used by preview)
- [x] Panes tab actions: switch (Enter), add (`a`), remove+confirm (`K`), cycle next/prev (`]`/`[`), refresh (`R`), quit
- [x] Live preview pane shows ANSI tail of the highlighted AI pane via `{5}` field expansion to pane ID
- [x] `Prefix+L` keybinding removed from `lazy-llm`
- [x] `llm-panes` reduced to a 5-line alias for `llm-dashboard --tab panes`
- [x] README + USAGE no longer reference `Prefix+L` or `llm-panes` as a separate concept; panes tab documented
- [x] No regressions in `llm-add` / `llm-remove` / `llm-cycle` CLI commands (they're delegated to from dispatch; not modified)
- [x] Tests cover panes tab structural wiring: 12 assertions in `13-dashboard-panes-tab-unit.sh` covering alias shrink, Prefix+L retirement, --tab panes parsing, render function presence, action dispatch verbs, canonical detector usage, cross-tab routing, help text
- [ ] Manual verify: with 2+ AI panes in a session, opening the dashboard and switching to the Panes tab shows them with status glyphs; cycling via `Enter` or `]`/`[` swaps the visible pane; `a` adds a new pane via tool picker; `K` removes with confirmation

## Verify Plan

### Structural / code-site — covered by 13-dashboard-panes-tab-unit.sh
- [x] `llm-panes` collapsed to ≤10-line alias execing `llm-dashboard --tab panes`
- [x] No `bind-key -T prefix L` remains in `lazy-llm`
- [x] `Prefix+S` binding untouched (still launches `llm-dashboard`)
- [x] `llm-dashboard --tab panes --help` accepts the new tab arg
- [x] `--tab bogus` rejected with "Unknown tab"
- [x] `render_panes_tab()` defined
- [x] `dispatch_action` handles `pane-cycle`, `pane-add`, `pane-remove`, `pane-next`, `pane-prev`
- [x] Main-loop case allowlist extended for those verbs
- [x] Dashboard uses canonical `lazy_llm_detect_pane_status` (no inline redefinition)
- [x] `3` → `tab:panes` routing present in Sessions and Worktrees tabs
- [x] Help text documents the Panes tab

### Regression — all prior unit tests green
- [x] 09-init-state-dirs-unit
- [x] 10-pane-status-detection
- [x] 11-dashboard-shell-unit (Test 9 updated to drop now-outdated Prefix+L assertion)
- [x] 12-worktree-primitive-unit
- [x] 13-dashboard-panes-tab-unit (12 new assertions)

### Static
- [x] `bash -n` on `llm-dashboard`, `llm-panes`, `lazy-llm`

### Live smoke (non-disruptive)
- [x] `~/.local/bin/llm-dashboard --tab panes --help` works
- [x] `~/.local/bin/llm-panes --help` (the alias) prints the same usage as the dashboard

### Manual (deferred)
- [ ] In an attached lazy-llm session: `Prefix+S → 3` opens Panes tab with the session's AI pane(s) listed and the status glyph next to each
- [ ] `]` and `[` cycle to next/prev AI pane (visible pane swaps)
- [ ] `a` opens tool picker; selecting a tool spawns a new AI pane via `llm-add`
- [ ] `K` on a non-active pane prompts yes/no confirm; `yes` removes the pane
- [ ] From outside a lazy-llm window: `Prefix+S → 3` renders the empty-state message with `a: add` hint
- [ ] After re-running `lazy-llm` to refresh bindings: `Prefix+L` no longer fires (falls through to tmux default `next-layout`)

## Work Report

**Date:** 2026-05-13

### What was done
- Added `render_panes_tab` to `llm-dashboard` — final tab in the unified dashboard. Lists AI panes for the current session+window, status glyph from `lazy_llm_detect_pane_status`, live ANSI preview keyed off the pane ID in column 5
- Five new dispatch verbs: `action:pane-cycle:N`, `action:pane-add`, `action:pane-remove:N`, `action:pane-next`, `action:pane-prev`. All delegate to existing `llm-cycle`, `llm-add`, `llm-remove` for the actual mutations — single source of truth for multi-pane machinery
- Retired the `Prefix+L` bind-key block from `lazy-llm`
- Shrunk `llm-panes` from 138 lines to a 5-line alias that execs `llm-dashboard --tab panes "$@"`
- Updated docs (README + USAGE) to remove `Prefix+L` references and document the Panes tab
- Added `tests/scenarios/13-dashboard-panes-tab-unit.sh` with 12 structural assertions
- Updated `11-dashboard-shell-unit.sh` Test 9 to drop the now-outdated "Prefix+L still untouched" assertion (that contract was intentionally broken by this slice)

### How it was done
- **Empty-state handling**: when `$AI_PANES` is empty (current window isn't a lazy-llm workspace), the tab renders a discoverable placeholder rather than erroring. The `a: add` hint lets users bootstrap from there
- **Context resolution**: Panes tab uses `lazy_llm_resolve_pane` → `lazy_llm_resolve_session_window` → `lazy_llm_read_multi_state` to focus on the user's *current* session+window (vs. Sessions tab which lists all)
- **Preview indexing**: pane ID embedded as the 5th column of each row, so the fzf preview command extracts it via `{5}` without needing to reverse-resolve from the 1-indexed pane number
- **Action delegation**: `dispatch_action` shells out to the existing scripts (`llm-cycle N`, `llm-add -t <tool>`, `llm-remove -f N`). Zero reimplementation of multi-pane state mutations
- **Tool picker**: nested fzf with `printf 'claude\ngemini\ncodex\ngrok\naider'` — same set the existing `Prefix+A` menu uses, but rendered as a single-letter-friendly fzf list
- **Confirm dialog for `K`**: same pattern as Sessions tab (`printf 'no\nyes' | fzf`) for consistency

### Decisions made
- **`llm-panes` aliased, not deleted.** Documented in the plan
- **`Prefix+L` retired completely.** No alias, no fallback. The dashboard's `3` key covers it
- **Tab order: Sessions / Worktrees / Panes (1/2/3).** Natural reading order; Panes is most session-local
- **Canonical `lazy_llm_detect_pane_status` for status**, replacing the inline regex from old `llm-panes`. Single source of truth across statusline + dashboard
- **`]`/`[` for cycle next/prev** — vim-style mnemonic. fzf accepts them as literal `--expect` keys
- **No "rename pane" action.** Panes don't have human-friendly names; renaming would be `K` + `a` together

### Commits
- `8504d66` — feat(dashboard): panes tab + retire Prefix+L; llm-panes → alias

### Files changed
- `lazy-llm-bin/.local/bin/llm-dashboard` — `render_panes_tab` (~100 lines added), 5 new dispatch verbs, expanded help text, `--tab panes` arg, `3` routing in Sessions and Worktrees tabs
- `lazy-llm-bin/.local/bin/llm-panes` — collapsed from 138 to 5 lines
- `lazy-llm-bin/.local/bin/lazy-llm` — removed `Prefix+L` bind-key block (3 lines, replaced with a comment)
- `tests/scenarios/13-dashboard-panes-tab-unit.sh` (new, 130 lines) — 12 structural assertions
- `tests/scenarios/11-dashboard-shell-unit.sh` — Test 9 updated for the intentional contract break
- `README.md` — Tmux Keybindings table, features bullet, CLI table all updated
- `docs/USAGE.md` — two rows updated

### Sources Consulted
- None — followed existing project conventions

### Follow-up
- **No regression in `09-init-state-dirs-unit`, `10-pane-status-detection`, `12-worktree-primitive-unit`** — confirmed via full unit-test sweep
- **The dashboard now has duplicate `glyph_for` definitions** (one in `llm-dashboard`, one was added by `pane-status-detection` to `llm-status`). Both are tiny case statements; pulling into the lib would save ~5 lines but adds a require step. Worth flagging for [[lazy-llm-refinement-pass]] but not urgent
- **`Prefix+L` is still bound on the user's currently-running tmux server** (because the binding was set at session-creation time and the new `lazy-llm` script hasn't run yet to re-register). Document the `tmux unbind-key -T prefix L` workaround in the validation playbook

## Verify Report

**Date:** 2026-05-13

### Summary
All 12 structural assertions in the new test pass. All 5 unit tests across the suite are green (including 11 with its updated Test 9). `bash -n` clean. The dashboard's `--help` documents all three tabs and the new keys. The `llm-panes` alias works. The agent-verifiable contract is fully verified; the live UI flows (popup keypresses, glyph rendering, pane cycling) are deferred to human validation as expected.

### Tests
- 13-dashboard-panes-tab-unit: 12/12 ✓
- 09: ✓ 10: ✓ 11: ✓ (after Test 9 update) 12: ✓

### Live smoke checks
- `llm-dashboard --tab panes --help` → exits 0 with usage
- `llm-panes --help` (via alias) → same usage as dashboard
- `--tab bogus` → exit 2 with "Unknown tab"

### Deferred to human validation
- Live `Prefix+S → 3` open and Panes tab UI rendering with actual AI panes
- `]`/`[` cycling visible pane swap
- `a` tool picker → spawning new pane
- `K` confirm + remove
- Empty-state from outside lazy-llm workspace
- Confirmation that `Prefix+L` is no longer fired after re-running `lazy-llm` (or after `tmux unbind-key -T prefix L`)
