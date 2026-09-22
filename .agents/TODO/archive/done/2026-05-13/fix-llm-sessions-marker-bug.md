---
slug: fix-llm-sessions-marker-bug
title: Fix llm-sessions @lazy_llm marker scope mismatch (Prefix+S broken)
priority: P0
status: done
created: 2026-05-13
updated: 2026-05-13
depends-on: []
tags: [bug, llm-sessions, tmux]
commits: [2f2bc18]
---

# Fix llm-sessions @lazy_llm marker scope mismatch (Prefix+S broken)

## Context

`Prefix+S` opens an `llm-sessions` popup that always says "No lazy-llm sessions, press Enter to create one" — even when lazy-llm sessions exist. The popup also can't be closed normally (no Esc/q binding active during the `read -r` prompt) and pressing Enter doesn't actually create a session either.

Root cause: scope mismatch on the `@lazy_llm` user option.

- **Set** in `lazy-llm-bin/.local/bin/lazy-llm:189`:
  ```
  tmux set-option -t "$session" @lazy_llm 1
  ```
  Default scope for `set-option` is **session-scoped**.
- **Read** in `lazy-llm-bin/.local/bin/llm-sessions:21` and `:93`:
  ```
  tmux show-option -sv -t "$session" @lazy_llm
  ```
  The `-s` flag means **server-scoped** (global). This always returns empty unless `@lazy_llm` is also set as a server option, so `gather_sessions()` always returns an empty list.

Secondary issue: the empty-sessions code path in `cmd_interactive()` (lines 124–128) calls `read -r` with no way to abort, and on Enter just `return 0` — it doesn't actually launch `lazy-llm`. Even when fixed, the popup hangs until Enter.

## Key Files

- `lazy-llm-bin/.local/bin/llm-sessions` — reads `@lazy_llm` with wrong scope flag (lines 21, 93); empty-state UX dead end (lines 124–128)
- `lazy-llm-bin/.local/bin/lazy-llm:189` — sets `@lazy_llm` session-scoped (correct, keep as-is)
- `lazy-llm-bin/.local/bin/llm-panes` — verify same bug doesn't exist there; align reading scope

## Acceptance Criteria

- [x] `tmux show-option` calls in `llm-sessions` read `@lazy_llm` with session scope (`-v`, default session scope; `-sv` removed)
- [x] Audit all `tmux show-option`/`set-option` calls across `lazy-llm-bin/.local/bin/*` for similar scope mismatches; fix any found (audit done — no other mismatches)
- [ ] With one or more active lazy-llm sessions, `Prefix+S` shows them in the picker (manual verify)
- [x] Empty-state path: show a message with a clearly bound key to close (`Esc`) and another to create (`Ctrl-n`); both code paths unified through fzf
- [x] Popup is always closable with `Esc`, even in the empty-sessions state (fzf handles Esc natively)
- [ ] Manual verify: open a fresh tmux server, run `lazy-llm`, press `Prefix+S` — session appears; `Esc` closes the popup

## Verify Plan

### Static / code-site inspections

- [x] Syntax check: `bash -n lazy-llm-bin/.local/bin/llm-sessions` exits 0.
- [x] Confirm scope flag fix at both read sites — `grep -nE 'show-option.*@lazy_llm' lazy-llm-bin/.local/bin/llm-sessions` should show exactly two lines, both using `-v -t "$session"` / `-v -t "$target"` (no `-s` flag, no `-sv`).
- [x] Confirm no regressions in the broader codebase: `grep -RnE 'show-option[^|]*-s[v]?[^w].*@lazy_llm' lazy-llm-bin/.local/bin/` returns no matches.
- [x] AC: Set site unchanged — read `lazy-llm-bin/.local/bin/lazy-llm:189`, confirm it is still `tmux set-option -t "$session" @lazy_llm 1` (no `-g`, so session-scoped; matches reader).
- [x] AC: Audit completeness — `grep -nE 'show-option|set-option' lazy-llm-bin/.local/bin/*` and confirm every `@AI_*` window-scoped option uses `-w` / `-wv` / `-wqv` on both sides (set in `lazy-llm` lines 175-186 with `-w`; read in `llm-sessions:31-32` and `lazy-llm:196-218` with `-wv`/`-wqv`). No scope mismatches remain.
- [x] Code: `llm-sessions:114-185` (`cmd_interactive`) — confirm there is **no** early `return 0` on empty `$data` before the fzf call; both empty and populated paths must reach the `fzf` invocation.
- [x] Code: `llm-sessions:127-128` — empty-state branch sets `lines=""` and a `header` mentioning `ctrl-n: new | esc: close`.
- [x] Code: `llm-sessions:149` — fzf `--expect="ctrl-d,ctrl-n"` is present so Ctrl-n is captured as a key event in all states.
- [x] Code: `llm-sessions:166-169` — `ctrl-n` case launches `tmux display-popup -E "$HOME/.local/bin/lazy-llm"` **without** a `[[ -z "$chosen_name" ]] && return 0` guard (so it works on an empty list); kill (170-176) and switch (177-183) branches each retain their own guard.

### Functional checks (require a live tmux server; run inside an interactive shell)

- [x] Run `tmux kill-server 2>/dev/null; tmux new-session -d -s _verify_baseline`; then `tmux show-option -v -t _verify_baseline @lazy_llm` returns empty AND `lazy-llm-bin/.local/bin/llm-sessions --list` prints `No lazy-llm sessions found.` Clean up: `tmux kill-session -t _verify_baseline`.
- [x] Simulate a lazy-llm session marker: `tmux new-session -d -s _verify_lazy && tmux set-option -t _verify_lazy @lazy_llm 1`; then `lazy-llm-bin/.local/bin/llm-sessions --list` includes a row whose first column is `_verify_lazy`. Clean up: `tmux kill-session -t _verify_lazy`.
- [x] Negative case for `--kill`: with no `@lazy_llm` marker, `tmux new-session -d -s _verify_plain && lazy-llm-bin/.local/bin/llm-sessions --kill _verify_plain` exits non-zero and prints `Error: '_verify_plain' is not a lazy-llm session`. Clean up: `tmux kill-session -t _verify_plain`.
- [x] Positive case for `--kill`: `tmux new-session -d -s _verify_kill && tmux set-option -t _verify_kill @lazy_llm 1 && lazy-llm-bin/.local/bin/llm-sessions --kill _verify_kill` exits 0, prints `Killed session: _verify_kill`, and `tmux has-session -t _verify_kill` returns non-zero afterward.

### Manual checks (live tmux, interactive popup — human eyeballs required)

- [ ] AC: With one or more active lazy-llm sessions, run `lazy-llm`, then in the attached session press `Prefix+S` — the popup lists the session (not "No lazy-llm sessions").
- [ ] AC: In the popup with sessions listed, press `Esc` — popup closes cleanly, returns to tmux without hanging.
- [ ] AC: Kill all lazy-llm sessions, then run `tmux display-popup -E ~/.local/bin/llm-sessions` from inside a non-lazy-llm tmux session — popup shows header `No lazy-llm sessions. ctrl-n: new | esc: close`, **does not** hang on `read`, and `Esc` closes it immediately.
- [ ] AC: From the empty-state popup, press `Ctrl-n` — a `lazy-llm` popup is launched (previously this was unreachable from the empty branch).
- [ ] AC: From a populated popup, `Ctrl-d` on a selected row kills that session and re-invokes the picker with the updated list.

## Verify Report

**Date:** 2026-05-13

### Static / code-site inspections — all 9 PASS
- `bash -n` exits 0.
- Both `@lazy_llm` read sites (lines 21 and 93) now use `-v -t "$session"` / `-v -t "$target"`.
- Repo-wide regex for stale `-s`/`-sv` reads of `@lazy_llm` returns no matches.
- Set site at `lazy-llm:189` unchanged (`tmux set-option -t "$session" @lazy_llm 1`).
- `@AI_*` audit: every site uses `-w`/`-wv`/`-wqv` consistently; no other scope mismatches.
- `cmd_interactive` structure: single fzf exit point at `... || return 0`; empty-state header set to `"No lazy-llm sessions. ctrl-n: new | esc: close"`; `--expect="ctrl-d,ctrl-n"` present; `ctrl-n` case has no `chosen_name` guard, `ctrl-d` and `*)` (switch) branches each retain their guard.

### Functional checks — all 4 PASS
- Empty baseline: `--list` correctly prints `No lazy-llm sessions found.` on a fresh server with no marker.
- Positive marker: `_verify_lazy` with `@lazy_llm=1` appears in `--list` output.
- `--kill` rejects an unmarked session with exit 1 and the expected error message.
- `--kill` succeeds on a marked session and the session is gone afterward.

### Live smoke test (bonus, not in plan)
Against the user's actual tmux server, `~/.local/bin/llm-sessions --list` now correctly identifies both pre-existing lazy-llm sessions (`dev-ai-dev-workflow-claude`, `dev-lazy-llm-claude`) with their directories, tools, window counts, and attached `*` markers. Before the fix, this command would have reported "No lazy-llm sessions found." even with these sessions present.

### Initial failure note
First pass of functional checks hit "server exited unexpectedly" on a fresh `TMUX_TMPDIR` server — that was a side effect of the user's `.tmux.conf` failing under unusual server boot conditions, not a regression. Re-running with `-f /dev/null` (skip config) confirmed all four checks pass against an isolated server. The fix itself is config-independent.

### Manual checks — deferred to user
Five UI-bound checks (popup behavior, Esc/Ctrl-n/Ctrl-d in live tmux popups) genuinely require human interaction with the keyboard inside an attached tmux session. The static + structural + functional checks have verified the code paths that drive each of them; the user can confirm the UX is as expected when convenient.

## Work Report

**Date:** 2026-05-13

### What was done
- Fixed the `@lazy_llm` tmux user-option scope mismatch in `llm-sessions` (two read sites)
- Refactored `cmd_interactive`'s empty-state branch so both empty and populated paths flow through fzf
- Caught and fixed a follow-on bug: the pre-existing early `[[ -z "$chosen_name" ]] && return 0` would have blocked `Ctrl-n` (new session) from the empty list — moved the guard into the kill/switch branches only

### How it was done
- Started by auditing every `tmux set-option`/`show-option` call across the repo (bash scripts + nvim plugins) via an Explore subagent to confirm `@lazy_llm` was the only scope mismatch and that the `@AI_*` window-option machinery was consistent (it was)
- The scope fix is one character per site: `-sv` → `-v` (drop the server flag; the explicit `-t "$session"` keeps it session-scoped, which matches `lazy-llm:189`)
- For the empty-state refactor, kept the existing fzf invocation as the single exit point so `Esc` is handled natively by fzf (returns 130 → `|| return 0` closes the popup). The empty case now sets `lines=""` and a context-aware header pointing at `ctrl-n: new | esc: close`
- Restructured the `case "$key"` dispatch so `ctrl-n` runs without requiring a selection (it doesn't need one), while `ctrl-d` and the default switch branch keep their `-z "$chosen_name"` guards

### Decisions made
- **Kept `Ctrl-d`/`Ctrl-n` chords for this commit** — replacing them with dense single-letter bindings (`K`, `n`) is the explicit scope of [[dense-keybindings-popup-scopes]], not this P0
- **Did not add a `.gitignore` for `.agents/TODO/.work-state`** — scope creep for a P0 bug fix; the file is just left untracked
- **Did not add automated tests for `llm-sessions`** — the testability gap is real but covered separately by [[lazy-llm-refinement-pass]]; per parsimony principle, kept this commit focused on the bug

### Commits
- `2f2bc18` — fix(llm-sessions): read @lazy_llm marker with correct scope

### Files changed
- `lazy-llm-bin/.local/bin/llm-sessions` — two `-sv` → `-v` scope fixes (lines 21, 93); `cmd_interactive` empty-state unified with populated path through fzf; `chosen_name` empty guard moved into the kill/switch branches so `ctrl-n` works on empty lists

### Sources Consulted
- None — project has no `~/.claude/coding-standards/` configured; CLAUDE.md guidelines (directory awareness, library-first, state-based execution) were followed implicitly

### Follow-up
- `llm-panes` silently exits when invoked outside a lazy-llm workspace (no marker check at all). Not a bug per se, but worth noting in [[lazy-llm-refinement-pass]] when that runs
- No automated tests for either `llm-sessions` or `llm-panes` — already tracked in [[lazy-llm-refinement-pass]]

## Human Validation

**Commit(s):** `2f2bc18`

The agent verified the data layer end-to-end: code inspection, structural checks, four tmux-driven functional checks, plus a live smoke test confirming `llm-sessions --list` now finds the user's real lazy-llm sessions where it previously found none. What an agent cannot exercise is the actual interactive popup — fzf rendered inside `tmux display-popup`, driven by real keystrokes. The checks below cover the three distinct UX paths through `cmd_interactive`.

### Checks

- [ ] **Populated popup — primary fix** — With at least one lazy-llm session active (you already have `dev-ai-dev-workflow-claude` and `dev-lazy-llm-claude`), press `Prefix+S` from inside a tmux session. Expect: popup lists the sessions (not "No lazy-llm sessions"). Press `Esc`. Expect: popup closes cleanly, returns control to tmux, no hang.
- [ ] **Empty-state popup — refactored branch** — From a tmux session with **no** `@lazy_llm` markers anywhere on the server, run `tmux display-popup -E ~/.local/bin/llm-sessions`. Expect: popup shows header `No lazy-llm sessions. ctrl-n: new | esc: close`, does **not** hang on a `read` prompt, and `Esc` closes it immediately. Re-open and press `Ctrl-n` instead. Expect: a `lazy-llm` popup launches (this path was unreachable before the fix).
- [ ] **Kill-and-refresh chord** — From a populated `Prefix+S` popup, highlight a session you're willing to lose, press `Ctrl-d`. Expect: that session is killed and the picker re-invokes itself showing the updated list (or transitions to the empty state if it was the last one).

### Design Decisions

- **Single fzf exit point for both empty and populated states** rather than a separate `read`-based prompt for the empty case. Rationale: fzf already handles `Esc` natively (exits 130, `|| return 0` closes the popup) and supports `--expect` for chord bindings, so unifying through fzf eliminated the "hang on read with no abort key" UX bug for free. *Assess: agree that fzf-as-single-exit-point is the right shape, or would a dedicated empty-state UI (e.g., a one-key gum prompt) read better?*
- **Moved `[[ -z "$chosen_name" ]] && return 0` guard from top of `case` dispatch into the kill and switch branches only**, so `Ctrl-n` can fire on an empty list. Rationale: `ctrl-n` doesn't operate on a selection, so guarding it was the original bug masking the scope mismatch. *Assess: is per-branch guarding clear enough, or would an explicit `case "$key" in ctrl-n) ... ;; *) [[ -z "$chosen_name" ]] && return 0; ... esac` structure be more legible?*
- **Kept `Ctrl-d` / `Ctrl-n` chords** rather than rebinding to dense single-letter keys (`K`, `n`). Rationale: scope discipline — single-letter rebinding is the explicit subject of `[[dense-keybindings-popup-scopes]]`, not this P0. *Assess: confirm the deferral is the right call; nothing in the live UX feels broken with the chord bindings.*

### Sign-off

| Status | Validator | Date | Notes |
|--------|-----------|------|-------|
| | | | |

Status: PASS / FAIL / SKIP / PARTIAL
