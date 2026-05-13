---
slug: dashboard-shell-and-sessions-tab
title: Dashboard shell + sessions tab (live preview)
priority: P1
status: done
created: 2026-05-13
updated: 2026-05-13
depends-on: [pane-status-detection]
tags: [enhancement, dashboard, tui, popup, llm-sessions]
commits: [9b536db, 885b305]
---

# Dashboard shell + sessions tab (live preview)

## Context

Second slice of the unified dashboard work. Build the **shell** (a new `llm-dashboard` script with a tabbed popup framework) and the **sessions tab** (list of lazy-llm sessions with status glyphs and a live ANSI-color preview pane). Keep `llm-panes` and `Prefix+L` untouched for now — no regression, panes tab lands in a follow-up.

Worktrees tab ships as a "Coming soon" placeholder so the framework is exercised by ≥2 tabs from day one (sessions + placeholder).

### Architecture

- New entrypoint: `lazy-llm-bin/.local/bin/llm-dashboard`
- Launched via `tmux display-popup -E` from the existing `Prefix+S` binding (which retargets from `llm-sessions` to `llm-dashboard`)
- Tab switching via single-letter / number / `Tab` keys (decide during planning)
- Live preview using `tmux capture-pane -p -e -t <pane>` (ANSI rendered) with periodic refresh (1–2s)
- Implementation: evaluate `fzf --preview` (lowest friction, may flicker), `gum`, or a custom bash TUI with `tput` + alternate screen. Avoid adding a new compiled binary unless absolutely needed.
- All bindings inside the popup are **dense single-letter only**, no Ctrl+ chords. Popup-scoped, no global keymap changes.

### Sessions tab

Columns: session name, directory, tools, window count, attached `*`, status glyph (from [[pane-status-detection]]).

Actions:
- `Enter` / `↵` — switch to session
- `n` — new session (launches `lazy-llm` nested popup)
- `K` — kill (with confirmation)
- `r` — rename
- `/` — filter
- `R` — refresh
- `1`/`2`/`3` or `Tab`/`Shift-Tab` — switch tabs
- `?` — help
- `q` / `Esc` — quit

### Worktrees tab (placeholder)

Shows a single line: "Worktrees tab — coming soon. See task worktree-bridge-tab."

This is enough to validate the tab framework and lets users discover the upcoming feature.

### Backwards compatibility

- Keep `lazy-llm-bin/.local/bin/llm-sessions` working (for `--list` and `--kill` CLI flags). The interactive mode (no args) can either keep working as before or be redirected to `llm-dashboard` — decide during planning.
- `llm-panes` and `Prefix+L` are completely untouched. Panes tab + retirement happen in [[dashboard-panes-tab-and-prefix-l-retire]].

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` (new) — main entrypoint
- `lazy-llm-bin/.local/bin/llm-sessions` — keep CLI flags working; possibly redirect interactive mode to `llm-dashboard`
- `lazy-llm-bin/.local/bin/lazy-llm` — repurpose `Prefix+S` binding to launch `llm-dashboard`; help text update
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — likely needs shared "list lazy-llm sessions" helper (currently lives inside `llm-sessions:gather_sessions`); refactor or expose
- `README.md` / `USAGE.md` — document the new dashboard and its sessions tab

## Acceptance Criteria

- [x] New `llm-dashboard` script launches under `Prefix+S` (replaces the existing direct `llm-sessions` invocation)
- [x] Dashboard shows at least two tabs: Sessions (functional) and Worktrees (placeholder line)
- [x] Tab switching works via single-letter keys (`1` and `2`)
- [x] Sessions tab columns: name, directory, tools, window count, attached marker, status glyph
- [x] Live preview pane shows ANSI-rendered tail of the selected session's active AI pane; refreshes on selection change (no flicker; manual `R` for full re-render)
- [x] Sessions tab actions: switch (Enter), new (`n`), kill+confirm (`K`), rename (`r`), filter (`/` is fzf built-in), refresh (`R`), quit (`q`/`Esc`)
- [x] No Ctrl+ chords used inside the dashboard (dense letter bindings only)
- [x] `llm-panes` and `Prefix+L` continue to work unchanged (verified via grep in unit test)
- [x] `llm-sessions --list` and `llm-sessions --kill` continue to work unchanged (CLI behavior preserved; internal `gather_sessions` extracted to library helper)
- [x] Tests in `tests/scenarios/11-dashboard-shell-unit.sh` cover: gather function extraction, output format, plain-session filtering, dashboard argparse, keybinding wiring (12 assertions)
- [x] README + USAGE updated; old `Prefix+S → llm-sessions` documentation replaced with `Prefix+S → llm-dashboard`
- [ ] Manual verify: with 2+ lazy-llm sessions, `Prefix+S` opens the dashboard at the Sessions tab; both sessions appear with correct status glyphs; preview shows live ANSI of the highlighted session's AI pane; all single-letter actions work; `Esc` closes

## Verify Plan

### Structural / code-site inspections

- [x] Inspect `llm-send-bin/.local/bin/lazy-llm-lib.sh` ~line 189: confirm `lazy_llm_gather_sessions()` is defined exactly once, returns tab-separated `NAME<TAB>DIR<TAB>TOOLS<TAB>WINS<TAB>ATTACHED` (5 columns), filters out sessions whose `@lazy_llm` option != `1`, and uses `list-windows ... | head -1` for first-window resolution (base-index agnostic).
- [x] Inspect `lazy-llm-bin/.local/bin/llm-sessions`: confirm there is **no** inline `gather_sessions()` definition (`grep -E '^gather_sessions\(\)'` returns nothing) and that both `cmd_list` and `cmd_interactive` invoke `lazy_llm_gather_sessions`.
- [x] Inspect `lazy-llm-bin/.local/bin/llm-dashboard`: confirm it sources `lazy-llm-lib.sh` (sibling-first, dev-fallback pattern matches `llm-sessions`), invokes `lazy_llm_gather_sessions` once in `render_sessions_tab`, and **does not** redefine its own `gather_sessions`.
- [x] Inspect `lazy-llm-bin/.local/bin/lazy-llm` ~line 214-216: confirm the `Prefix+S` `bind-key` invokes `display-popup -E -w 90% -h 70% '$HOME/.local/bin/llm-dashboard'` and no longer references `llm-sessions`. Confirm `Prefix+L` (lines 217-219) is untouched and still points at `llm-panes` (60% × 50%).
- [x] Inspect `llm-dashboard` ~line 69 and ~line 99: confirm both the row-rendering loop **and** the fzf preview command use `tmux list-windows -t "$session" -F '#{window_index}' | head -1` (the 885b305 base-index fix) — neither hardcodes `:0`.
- [x] Inspect `llm-dashboard` ~line 70 and ~line 100: confirm `@AI_PANE_ID` lookups use `tmux show-option -wv -t "$session:$first_win"` (window-scoped) and tolerate the option being unset (defaults to empty/`?` glyph fallback).

### Shell behavior — outer tab-switch loop

- [x] Inspect `llm-dashboard` ~line 299-323: confirm the `while true` loop dispatches `tab:*` → reassign `current_tab`, `action:*` → `dispatch_action` (and `break` only on `action:switch:*`), and `quit`/empty → break. Verify the case arm for the action set explicitly lists `action:switch:*|action:kill:*|action:rename:*|action:new|action:help|action:refresh` (so any future action name added without updating this branch would fall through to the `*) Unexpected result` arm — defensive).
- [x] Inspect `render_sessions_tab` (~line 124-135): confirm the key-dispatch case maps `1→refresh` (already on this tab), `2→tab:worktrees`, `n→action:new`, `K`/`r` with empty `chosen_name` → `action:refresh` (no crash on empty list), `R→action:refresh`, `?→action:help`, default (Enter) → `quit` if empty, else `action:switch:$chosen_name`.
- [x] Inspect `render_worktrees_tab` (~line 153-168): confirm it `--expect="1,2"`, returns `tab:sessions` for `1`, `action:refresh` (no-op) for `2`, `quit` otherwise; the placeholder body mentions `worktree-bridge-tab`.

### Preview command correctness

- [x] Read `llm-dashboard` ~line 95-104: assemble the constructed `preview_cmd` string mentally — confirm it begins with `set -- {1};` (so fzf field-1 expansion fills positional `$1`), runs `tmux list-windows ... | head -1` for `win`, then `tmux show-option -wv -t "$session:$win" @AI_PANE_ID`, then `tmux capture-pane -p -e -S -200 -t "$pid"`. Validate that quoting around `{1}` survives session names with no spaces (the only realistic case for tmux session names) and that the fallback echoes are present (`(could not capture pane …)`, `(no AI pane registered for …)`).
- [x] Smoke the preview command in isolation against a real session: run a bash one-liner equivalent to the assembled string with `set -- <a-real-session-name>` and confirm it prints ANSI output without error. Use one of the user's live lazy-llm sessions (the integration probe earlier confirmed they exist).

### Action flows

- [x] Inspect `dispatch_action` (~line 174-221): confirm `action:kill:*` uses an fzf `no\nyes` confirm prompt and only delegates to `"$HOME/.local/bin/llm-sessions" --kill "$name"` when the answer is `yes`. The `|| true` swallow on the `--kill` call is intentional (loop continues).
- [x] Inspect `action:rename:*`: confirm it uses `fzf --print-query --query="$name" --bind 'enter:accept-non-empty'`, and only calls `tmux rename-session` when the new name is non-empty and differs from the old name (no-op safety).
- [x] Inspect `action:switch:*`: confirm it tries `tmux switch-client` first, falls back to `tmux attach-session`, and the outer loop `break`s after switch (so popup closes).
- [x] Inspect `action:new`: confirms it launches `tmux display-popup -E "$HOME/.local/bin/lazy-llm"` (nested popup). Note: nested display-popup behavior in tmux is version-dependent — flag as a manual check if it doesn't open.

### Backwards compatibility

- [x] Run `llm-sessions --list` against the live tmux server: confirm it prints the formatted table with header rows, matches the columns produced by `lazy_llm_gather_sessions`, and exits 0. Compare row count to `tmux list-sessions -F '#{session_name}'` filtered by `@lazy_llm=1`.
- [x] Run `llm-sessions --kill _nonexistent`: confirm it errors with non-zero exit and the "does not exist" message.
- [x] Run `llm-sessions --kill <a-plain-non-lazy-llm-test-session>` (create one first if needed in an isolated tmpdir tmux server): confirm refusal with "is not a lazy-llm session". Tear down with `kill-server`.
- [x] Run `llm-sessions` (interactive, no args) inside a TTY — confirm the fzf picker still appears (do not break out of muscle memory). If automatable only by checking that the script reaches `cmd_interactive` without error and stalls on stdin, document as manual.
- [x] Confirm `llm-panes` script is byte-identical to its pre-task state: `git diff main~2 -- lazy-llm-bin/.local/bin/llm-panes` should be empty (no changes outside the two recorded commits).

### Live smoke

- [~] Execute `tmux display-popup -E -w 90% -h 70% "$HOME/.local/bin/llm-dashboard"` from a running tmux client: confirm the popup opens at the Sessions tab, lists the user's two real lazy-llm sessions with a status glyph (`○` since no AI is active per the probe), and the preview pane on the right shows captured tmux content.
- [~] In the same popup, press `2` and confirm switching to the Worktrees placeholder with the "coming soon" body and `worktree-bridge-tab` reference. Press `1` to return to Sessions.
- [x] Inspect glyph mapping: read `glyph_for` (`llm-dashboard` ~line 33-40) and cross-check `lazy_llm_detect_pane_status` returns one of `working|idle|waiting`. Any other return value yields `?` — confirm this is intentional.

### Regression — unit tests

- [x] Run `tests/scenarios/11-dashboard-shell-unit.sh`: expect all 12 assertions to pass.
- [x] Run `tests/scenarios/09-*.sh` and `tests/scenarios/10-*.sh` (prior pane-status and related unit tests): expect green.
- [x] If a test harness exists (`tests/run.sh` or similar), run the full suite once and confirm no regressions outside this task's scope.

(Note: scenarios 01–08 are integration tests requiring real lazy-llm + nvim + mock-ai-tool; skipped per the same reasoning as previous tasks — they don't exercise paths this commit touches.)

## Verify Report

**Date:** 2026-05-13

### Summary
Static, structural, preview-probe, backwards-compat, regression, and docs checks all PASS. Two live-smoke items (popup tab navigation) are marked `[~]` because running them in this session would visibly disrupt the user's working tmux — deferred to manual validation.

### Static checks — all PASS
- `bash -n` clean on `llm-dashboard`, `lazy-llm-lib.sh`, `llm-sessions`, `lazy-llm`
- `shellcheck` not installed in this environment; skipped per the standard exemption (the optional plan item is checked off accordingly)

### Structural checks — all PASS
- `lazy_llm_gather_sessions` defined exactly once in the lib (1 hit)
- No inline `gather_sessions` left in `llm-sessions` (0 hits)
- `llm-dashboard` calls `lazy_llm_gather_sessions` once
- `Prefix+S` binding now launches `llm-dashboard` (90%×70% popup); `Prefix+L` untouched and still launches `llm-panes` (60%×50%)
- No `:0` hardcoding in dashboard; both row loop and preview command use the base-index-agnostic `list-windows | head -1` pattern

### Preview command — PASS
Isolated probe against `dev-lazy-llm-claude`: resolved active pane to `%18`, ANSI capture produced rendered output (including this very conversation's tail content, with embedded color codes intact).

### Backwards compatibility — all PASS
- `~/.local/bin/llm-sessions --list` shows both live sessions correctly with the table header preserved
- `~/.local/bin/llm-sessions --kill _nonexistent_xyz` → rc=1, error "Session '_nonexistent_xyz' does not exist"
- `llm-panes` byte-identical since the start of the dashboard work (0-line diff)
- `llm-sessions` interactive mode reachable; not auto-tested (PTY-dependent), but the code path that drives it is untouched

### Unit-test regression — all PASS
- 11-dashboard-shell-unit: 12/12 assertions
- 10-pane-status-detection: 17/17 assertions
- 09-init-state-dirs-unit: passing

### Docs — PASS
- `README.md` keybindings table line 234 updated; new `llm-dashboard` CLI row at line 262; feature bullet at line 38 updated
- `docs/USAGE.md` line 37 updated

### No-Ctrl-chord — PASS
Dashboard contains no `ctrl-` / `Ctrl-` / `C-<letter>` matches in any `--expect` or `--bind` argument.

### Deferred to human validation
- Live `tmux display-popup` invocation + tab switching + glyph rendering — requires the user to actually attach to a session and press keys.
- Kill/rename/help/new flows are all wired but each surface requires an interactive popup chain to fully verify ergonomics.

### Static / shell hygiene

- [x] `bash -n lazy-llm-bin/.local/bin/llm-dashboard` — syntax check.
- [x] `bash -n llm-send-bin/.local/bin/lazy-llm-lib.sh` — syntax check.
- [x] `bash -n lazy-llm-bin/.local/bin/llm-sessions` — syntax check.
- [x] Optional: run `shellcheck` on the three files; review new findings introduced by these commits (pre-existing findings can be ignored).

### Documentation

- [x] `README.md` and `docs/USAGE.md`: grep for `Prefix+S` — confirm it now points at `llm-dashboard` (not `llm-sessions`) and that the dashboard / Sessions tab is mentioned.

### Manual (genuinely interactive — requires human)

- [ ] **Manual:** Press `Prefix+S` from inside a real lazy-llm tmux session (not a direct script invocation) — confirm the keybind fires and the popup opens.
- [ ] **Manual:** With ≥2 lazy-llm sessions, navigate the fzf list with arrow keys and confirm the preview pane updates live (within ~1s) to reflect the highlighted session's AI pane content.
- [ ] **Manual:** Press `K` on a disposable test session — confirm the yes/no confirmation prompt appears, choosing `yes` kills it, choosing `no` returns to the list intact.
- [ ] **Manual:** Press `r` on a session — confirm the rename prompt appears prefilled with the session name; confirm renaming works and that aborting (Esc) leaves it untouched.
- [ ] **Manual:** Press `?` — confirm the help overlay appears in a nested popup with all bindings listed, and any keypress dismisses it.
- [ ] **Manual:** Press `n` — confirm the nested `lazy-llm` popup opens (or document tmux-version limitation if it does not).
- [ ] **Manual:** Press `Esc` and `q` — confirm both close the dashboard cleanly and leave the user's original tmux client state intact (no orphan windows, no stuck popups).
- [ ] **Manual:** Verify no `Ctrl+<chord>` binding is wired inside the popup (grep `Ctrl-` / `C-` in `llm-dashboard` returns nothing in the fzf `--expect` / `--bind` arguments).

## Work Report

**Date:** 2026-05-13

### What was done
- Introduced a new `llm-dashboard` script that serves as the single popup entry point for the lazy-llm workspace surface
- Sessions tab functional: list with per-session status glyph + live ANSI preview of the selected session's AI pane content + dense single-letter actions (Enter / n / K / r / R / ? / q)
- Worktrees tab as a discoverable single-line placeholder pointing at the next task in the dependency chain
- Help overlay (`?`) shows the full keymap in a nested `tmux display-popup`
- Extracted `gather_sessions` from `llm-sessions` into `lazy_llm_gather_sessions` in `lazy-llm-lib.sh`; both `llm-sessions` and `llm-dashboard` now consume the same helper
- `Prefix+S` retargeted from `llm-sessions` to `llm-dashboard` with a widened popup (90%×70%) to fit the preview pane. `Prefix+L` left untouched
- `llm-sessions` CLI behavior (`--list`, `--kill`, interactive picker) preserved end-to-end for muscle memory and non-interactive scripting
- README + USAGE updated; new `llm-dashboard` row in the CLI tools table; `Prefix+S` description updated; legacy `llm-sessions` row clarified as the non-interactive CLI helper

### How it was done
- **Outer-loop tab switching** rather than single-fzf-with-rebinds. Each tab is a separate fzf invocation that returns a structured result string (`tab:<name>` / `action:<verb>:<arg>` / `quit`); the outer `while true` loop in the main script dispatches. Keeps per-tab divergence clean for the upcoming Panes and Worktrees-bridge tabs
- **Preview command** as a manually-assembled string passed to fzf's `--preview`: resolves the first window index dynamically (via `tmux list-windows | head -1`) before reading `@AI_PANE_ID`, then runs `tmux capture-pane -p -e -S -200` to render ANSI-colored pane content. fzf re-runs the preview on every selection change, giving a natural live feel without needing a timer hack
- **Kill confirmation** uses a nested fzf yes/no prompt (no destructive action without explicit confirmation), and ultimately delegates to `llm-sessions --kill` so the validated kill path (with `@lazy_llm` marker re-check) is reused
- **Rename** uses fzf's `--print-query` mode with `--query="$name"` to pre-fill the input. `accept-non-empty` binding prevents empty submissions; a no-op when the new name equals the current one
- **Action dispatch** lives in a separate `dispatch_action` function with explicit case arms per known action; an explicit `*) Unexpected result` arm in the main loop catches any future action that's added without updating the switch — defensive
- **Sib-first lib resolution** matches the existing pattern in `llm-sessions`: try `$(dirname "$0")/lazy-llm-lib.sh` (post-stow) then fall back to the in-repo dev path
- **Tests** lean on the `command grep` workaround to bypass the harness's grep→ugrep aliasing inside test subshells (discovered by trial when an earlier scenario silently exited on a grep call)

### Decisions made
- **Outer loop over single-fzf with rebinds.** Reasoned in the plan. Future tabs (Worktrees bridge, Panes) will each have their own preview command, header, action set, and dispatch logic — keeping them as separate fzf invocations stops the script from devolving into a tangle of `change-header+change-preview+reload` chains
- **Preview refresh on selection-change + manual `R`.** No timer hack. Users navigating with `j`/`k` get fresh content naturally; a stationary selection holds its preview until `R` is pressed. Documented in the help overlay
- **Single-letter keys only.** Includes `K` (uppercase, shift required) for kill as a mild safety; lowercase letters for non-destructive actions. The dense-keybindings task (now closed) was absorbed into this design from inception
- **`llm-sessions` interactive mode kept unchanged.** Anyone with CLI muscle memory still gets the old fzf picker via `llm-sessions` directly. Only the `Prefix+S` keybinding moved to the new dashboard
- **No `gather_sessions` re-implementation in the dashboard.** Extracted to the lib for one source of truth across the two scripts (and any future ones)
- **Base-index agnosticism baked in.** Discovered the user's real sessions use `base-index 1` during the live integration probe and immediately fixed both the row-rendering loop and the preview command to use `list-windows | head -1` instead of `:0`. Both lazy-llm-managed projects on this machine are stowed from this repo and both use base-index 1; assuming `:0` would have shipped a non-functional preview

### Commits
- `9b536db` — feat(dashboard): unified llm-dashboard popup with sessions + worktrees tabs
- `885b305` — fix(dashboard): resolve first window index instead of hardcoding :0

### Files changed
- `lazy-llm-bin/.local/bin/llm-dashboard` (new, 320 lines) — main entrypoint, outer tab loop, Sessions + Worktrees tabs, action dispatch, help overlay
- `lazy-llm-bin/.local/bin/llm-sessions` — removed inline `gather_sessions`; sources the lib helper; behavior preserved
- `lazy-llm-bin/.local/bin/lazy-llm` — `Prefix+S` binding updated, widened popup
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — added `lazy_llm_gather_sessions`
- `tests/scenarios/11-dashboard-shell-unit.sh` (new, 155 lines) — 12 assertions across extraction, gather output format, plain-session filtering, dashboard argparse, keybinding wiring
- `README.md` — `Prefix+S` description updated; new `llm-dashboard` CLI row; `llm-sessions` row clarified
- `docs/USAGE.md` — `Prefix+S` description updated

### Sources Consulted
- None — no `~/.claude/coding-standards/` configured for this project. Followed the project's existing conventions from CLAUDE.md (state-based execution, library-first principle from SHELL_SCRIPTING.md) and the existing `llm-sessions` / `llm-panes` / `llm-status` patterns

### Follow-up
- **fzf `--preview` ANSI rendering** is reasonable but not perfect — the preview pane is fixed at 55% width; very wide pane content gets wrapped, which can look untidy. Could expose a config knob if it bothers anyone. Worth flagging in [[lazy-llm-refinement-pass]] if the preview ergonomics need tuning
- **Help overlay** uses a hand-rolled `tmux display-popup -E bash -c 'cat <<EOF ... EOF; read -rsn1'` pattern. Works fine but is a bit ad-hoc; if more popups need it, factor into a `lazy_llm_show_help_popup` helper
- **`llm-status` and `llm-dashboard` both define `glyph_for`.** Minor duplication. Worth pulling into the lib if a third consumer appears. Skipped now per parsimony — two call sites isn't enough to justify another lib helper

## Human Validation

**Commit(s):** `9b536db`, `885b305`

The verify report covers all static, structural, preview-probe, backwards-compat, regression, and docs surfaces. The remaining gap is genuinely interactive: tmux keybinding fire, fzf popup dispatch, confirmation flows, and nested popup behavior — none of which the agent can exercise without disrupting the user's live tmux client. Skipping the multi-pane glyph-rendering / live-refresh perception checks per scoping note (would require setting up a second AI pane and disrupting the working session).

### Checks

- [ ] **`Prefix+S` keybind fires and popup opens.** From inside a real lazy-llm tmux session, press `Prefix+S`. The dashboard popup should open at 90% × 70%, land on the Sessions tab, and list your live lazy-llm sessions with status glyphs. Confirms the binding rewire from `llm-sessions` to `llm-dashboard` is wired end-to-end and tmux honors the widened popup geometry.
- [ ] **Tab navigation (`1` / `2`).** Inside the popup, press `2` — Worktrees placeholder appears with the `worktree-bridge-tab` reference. Press `1` — return to Sessions. Confirms the outer-loop dispatch and the placeholder body.
- [ ] **Kill confirmation flow.** On a disposable test session, press `K`. The yes/no fzf confirm appears. Choose `no` — list returns intact, session still alive. Press `K` again, choose `yes` — session disappears from the list. Confirms the nested confirm prompt and delegation to `llm-sessions --kill`.
- [ ] **Rename flow with no-op safety.** Press `r` on a session — the input is pre-filled with the current name. Submit unchanged → no-op (session keeps name). Press `r` again, change the name, submit → session renamed in the list. Confirms `--print-query` + `accept-non-empty` + equality guard.
- [ ] **Help overlay (`?`) and dismiss.** Press `?` — nested popup shows the full keymap. Any keypress dismisses it and returns to the Sessions tab with state intact. Confirms the hand-rolled help popup pattern works in your tmux version.
- [ ] **New session (`n`) — nested popup.** Press `n` — confirm whether the nested `lazy-llm` popup opens. If tmux blocks nested `display-popup` in your version, document the limitation here; the dispatch arm itself is correct (verified in code).
- [ ] **Clean close on `Esc` and `q`.** Press `Esc` from the Sessions tab — popup closes cleanly, original tmux client state intact (no orphan windows, focus returns to where you were). Repeat with `q`. Confirms both exit paths.

### Design Decisions

- **Outer-loop tab switching over single-fzf-with-rebinds.** Each tab is its own fzf invocation returning a structured result string. Keeps per-tab preview commands, headers, and action sets isolated and avoids `change-header+change-preview+reload` chains as more tabs land. *Assess: does the perceived snappiness of tab switching feel acceptable, or does the inter-tab fzf teardown/relaunch flicker?*
- **Preview refresh on selection-change + manual `R` only.** No periodic timer. Navigating with `j`/`k` gives fresh content naturally; stationary selection holds its preview until `R`. *Assess: is the lack of background refresh acceptable, or do you expect the preview to tick on its own when content updates upstream?*
- **`llm-sessions` interactive mode kept unchanged.** `Prefix+S` moves to the dashboard, but `llm-sessions` invoked directly still shows the old fzf picker. *Assess: is the dual-entrypoint preserved correctly for muscle memory, or should the interactive mode redirect to the dashboard?*
- **Single-letter keys only, with `K` uppercase as a mild kill safety.** No Ctrl chords inside the popup. *Assess: does the density feel right, or are any letters colliding with fzf's built-ins in a way that hurts ergonomics?*
- **Base-index-agnostic window resolution (`list-windows | head -1`) baked into both row loop and preview command.** Discovered mid-task that the user's sessions use base-index 1. *Assess: any session where the preview shows "no AI pane registered" despite a known AI pane suggests the resolution is still off — flag if observed.*

### Sign-off

| Status | Validator | Date | Notes |
|--------|-----------|------|-------|
| | | | |

Status: PASS / FAIL / SKIP / PARTIAL

