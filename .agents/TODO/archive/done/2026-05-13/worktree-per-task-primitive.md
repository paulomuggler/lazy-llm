---
slug: worktree-per-task-primitive
title: Add worktree-per-task primitive to lazy-llm
priority: P1
status: done
created: 2026-05-13
updated: 2026-05-13
depends-on: []
tags: [enhancement, git, worktree, lazy-llm]
commits: [3a3e54f]
---

# Add worktree-per-task primitive to lazy-llm

## Context

Inspired by `nielsgroen/claude-tmux`'s worktree workflow: spawning a fresh tmux session pointed at a per-branch git worktree so multiple parallel agent attempts on different branches don't step on each other.

Today, the only way to get there with lazy-llm is to manually run `git worktree add` and then `lazy-llm -d <path> -s <name>`. We want a first-class one-shot primitive.

### Worktree binding is session-scoped

Worktree association is a property of a **lazy-llm session**, not of individual panes. All panes in a session share the same working directory:
- The AI pane, editor pane, and prompt pane all start in the worktree path
- `@` path completion, code references (`<leader>llmr`), and NOTE collection all rooted at the worktree
- Within one session, you can still add multiple AI panes (existing multi-AI tabbing) — they all share the worktree

Mixing scopes (e.g. AI pane in worktree, nvim pane in repo root) would break the path-rooting assumptions all over the codebase. Session = one working directory, full stop.

This implies: **adding a worktree-bound pane to an existing session that's rooted elsewhere is not supported.** The way to work on a worktree is to spawn (or attach to) a session bound to it.

### CLI surface

```
lazy-llm -W <branch>             # spawn session bound to <branch>'s worktree (create branch + worktree if needed)
lazy-llm -W <branch> -t gemini   # combined with tool selection
lazy-llm worktree <branch>       # alias subcommand form
```

Behavior:
- If the branch exists: create a worktree for it (error if it's checked out elsewhere; suggest attaching to the existing session if one is found there)
- If the branch doesn't exist: create the branch from current HEAD, then create the worktree
- If a lazy-llm session already exists pointing at that worktree path: attach to it instead of spawning a duplicate
- Worktree location: project-relative convention — default `.worktrees/<branch>/` inside the repo, with override via env var or flag
- Spawn the lazy-llm session inside that worktree using existing `-d`/`-s` plumbing
- Session name auto-derives from the branch name (sanitized; collision resolution by suffix counter, same pattern existing code already uses)
- **Inside-tmux behavior**: even when invoked from inside an existing tmux session, `-W` always spawns a *new* session (not a new window in the current one), because the worktree binding is session-scoped. Document this clearly so it doesn't surprise users who expect `-W` to compose with the existing "auto-add window in tmux" behavior.

Companion lifecycle management lives in [[worktrees-dashboard]].

## Key Files

- `lazy-llm-bin/.local/bin/lazy-llm` — argparse, subcommand dispatch (already has `list`, `kill`, `sessions` subcommands), add worktree path
- `lazy-llm-bin/.local/bin/lazy-llm-lib.sh` — shared helpers for branch/worktree validation
- Possibly a new `lazy-llm-bin/.local/bin/llm-worktree` if the logic warrants extraction (mirrors existing `llm-*` script pattern)

## Acceptance Criteria

- [x] `lazy-llm -W <branch>` creates a worktree if needed and opens a lazy-llm **session** bound to it
- [x] Worktree binding is session-scoped: panes start in the worktree path via `unset TMUX` short-circuit + auto-derived session name
- [x] When invoked from inside an existing tmux session, `-W` still spawns a new session (does not add a window) — documented in help text and README
- [x] If a lazy-llm session already exists pointing at the same worktree, attach to it instead of duplicating (via `lazy_llm_find_session_for_path` with realpath comparison)
- [x] If the branch is new, the branch is created from current HEAD; if it exists, the existing branch is used
- [x] Refuses gracefully if the branch is already checked out in another worktree (clear error + hint about removing the other worktree first)
- [x] Worktree base path configurable via `LAZY_LLM_WORKTREE_DIR` env var; default is `.worktrees/<sanitized-branch>/` inside the repo
- [x] Worktree path is added to `.gitignore` automatically when using the in-repo default; override path leaves `.gitignore` untouched
- [x] Help text (`lazy-llm -h`) documents `-W`, `LAZY_LLM_WORKTREE_DIR`, and the always-new-session behavior
- [ ] Manual verify: from a clean repo with `main` checked out, run `lazy-llm -W feature/foo` from inside an existing tmux session — a new session is created (not a new window), worktree exists at the default location, all panes are rooted there

## Verify Plan

### Structural / code-site inspection

- [x] `lazy-llm-bin/.local/bin/lazy-llm` ~line 74: confirm `getopts` string is `"s:d:t:wW:h"` (note the `W:` requiring an argument)
- [x] `lazy-llm-bin/.local/bin/lazy-llm` ~line 80: confirm the `W) WORKTREE_BRANCH="$OPTARG" ;;` case is present
- [x] `lazy-llm-bin/.local/bin/lazy-llm` ~line 85–96: confirm `-h` help text mentions `-W`, the `.worktrees/<branch>` default, `LAZY_LLM_WORKTREE_DIR` env var, and the "always spawns a new session" behavior
- [x] `lazy-llm-bin/.local/bin/lazy-llm` ~line 109–135: confirm the worktree-setup block is positioned **after** `getopts` parsing and **before** `init_state_dirs`/`cleanup_old_files` (ordering matters because `TARGET_DIR` must be mutated first)
- [x] `lazy-llm-bin/.local/bin/lazy-llm` worktree block: confirm it calls `lazy_llm_setup_worktree`, captures stdout into `TARGET_DIR`, propagates exit code via `|| exit $?`, then calls `lazy_llm_find_session_for_path` for the dedup attach path
- [x] `lazy-llm-bin/.local/bin/lazy-llm`: confirm `unset TMUX` AND `NEW_WINDOW=false` are both set after the existing-session attach check (forces new-session mode unconditionally)
- [x] `lazy-llm-bin/.local/bin/lazy-llm`: confirm auto-derived session name pattern is `dev-${SANITIZED}-${AI_TOOL}` where `SANITIZED="${WORKTREE_BRANCH//\//-}"`, and that it is only set when user didn't pass `-s`
- [x] `lazy-llm-bin/.local/bin/lazy-llm` top of file: confirm the `lazy-llm-lib.sh` sourcing block (sibling-first, dev-fallback) is present — the script previously did not source the lib
- [x] `llm-send-bin/.local/bin/lazy-llm-lib.sh`: confirm all three new helpers exist and are well-formed: `lazy_llm_setup_worktree`, `lazy_llm_find_session_for_path`, `lazy_llm_ensure_gitignore`
- [x] `lazy_llm_ensure_gitignore`: confirm idempotency guard uses `grep -qxF` (exact-line, fixed-string match — not substring) so partial matches don't silently skip
- [x] `lazy_llm_setup_worktree`: confirm `.gitignore` is only auto-touched when `base == $repo/.worktrees` (i.e., user-supplied `LAZY_LLM_WORKTREE_DIR` leaves `.gitignore` alone — required by AC)
- [x] `lazy_llm_setup_worktree`: confirm branch-already-checked-out-elsewhere detection uses `worktree list --porcelain | grep -qxF "branch refs/heads/$branch"` and returns non-zero with the hint message
- [x] `lazy_llm_find_session_for_path`: confirm both `target` and each candidate `dir` are passed through `realpath` (with raw-fallback) before comparison, so symlinks don't break dedup
- [x] `lazy_llm_find_session_for_path`: confirm it consumes from `lazy_llm_gather_sessions` (not a custom tmux list-sessions call) — keeps the "lazy-llm-marked" filter consistent

### Shell behavior of `-W` code path

- [x] Source the lib in a subshell and verify `lazy_llm_setup_worktree _vp_check` inside this repo: returns a path, branch is created, second invocation is idempotent (returns same path, no errors), then clean up via `git worktree remove .worktrees/_vp_check && git branch -D _vp_check`
- [x] Verify slash sanitization end-to-end: `lazy_llm_setup_worktree _vp/slashy` → worktree path ends in `_vp-slashy` (dir basename), but the git branch ref is `_vp/slashy`. Confirm both with `git worktree list --porcelain`. Clean up.
- [x] Verify `.gitignore` was touched exactly once (no duplicate `.worktrees/` lines): `grep -cxF '.worktrees/' .gitignore` should print `1`
- [x] Verify branch-checked-out-elsewhere refusal: with `_vp_check` still checked out in a worktree, a second `lazy_llm_setup_worktree _vp_check` from outside that worktree path... actually this is covered: confirm a fresh branch `_vp_conflict`, manually `git worktree add /tmp/_vp_conflict_wt _vp_conflict`, then `lazy_llm_setup_worktree _vp_conflict` returns non-zero with the "already checked out in another worktree" message. Clean up both.
- [ ] Verify `LAZY_LLM_WORKTREE_DIR=/tmp/_vp_alt lazy_llm_setup_worktree _vp_alt` puts worktree at `/tmp/_vp_alt/_vp_alt` and does NOT modify `.gitignore` (check `git diff .gitignore` is empty after, beyond what the default-path run added)
- [x] Verify non-git refusal: `cd /tmp && lazy_llm_setup_worktree foo` returns non-zero with "not inside a git repository" error

### `find_session_for_path` behavior

- [x] With no lazy-llm sessions running, `lazy_llm_find_session_for_path /tmp` prints empty and returns 0 (note: the function falls through the loop without an explicit return — confirm the implicit success is acceptable, or that callers tolerate empty stdout regardless of exit code)
- [x] Read `lazy-llm` main script ~line 115–122: confirm the attach branch uses `tmux switch-client -t` when `$TMUX` is set, and `tmux attach-session -t` when not (correct context-aware reattach)

### Backwards compatibility (regression)

- [x] Run `lazy-llm -h` and confirm the help text still lists `-s`, `-d`, `-t`, `-w` with unchanged descriptions (the old four flags are intact in both usage line and options block)
- [x] Grep the main script for any code path that was modified outside the new `if [[ -n "$WORKTREE_BRANCH" ]]; then ... fi` block — none of the pre-existing flag handling should have changed semantics
- [x] Confirm sourcing the lib at script start does not break the existing `case "${1:-}" in list|kill|sessions ...) ...` subcommand dispatcher (sourcing happens before, dispatch unchanged)

### Test runs

- [x] Run `bash /home/paulomuggler/Projects/dev-env/external/lazy-llm/tests/scenarios/12-worktree-primitive-unit.sh` — expect all 23 assertions pass (the new test)
- [x] Run `bash /home/paulomuggler/Projects/dev-env/external/lazy-llm/tests/scenarios/09-init-state-dirs-unit.sh` — expect pass (regression: lib changes didn't break state-dir init)
- [x] Run `bash /home/paulomuggler/Projects/dev-env/external/lazy-llm/tests/scenarios/10-pane-status-detection.sh` — expect pass (regression: pane status logic unaffected)
- [x] Run `bash /home/paulomuggler/Projects/dev-env/external/lazy-llm/tests/scenarios/11-dashboard-shell-unit.sh` — expect pass (regression: dashboard helpers, including `lazy_llm_gather_sessions` which `find_session_for_path` composes on, unaffected)

### Documentation

- [x] Confirm `README.md` mentions `-W <branch>`, `LAZY_LLM_WORKTREE_DIR`, and the always-new-session behavior
- [x] Confirm `docs/USAGE.md` documents the `-W` flag

### Manual (human eyes — disruptive / require attached tmux)

- [ ] **MANUAL:** From outside tmux in this repo: `lazy-llm -W _vp_manual` — confirm a new tmux session is created, attaches, all three panes (AI / nvim / prompt) report `pwd` ending in `.worktrees/_vp_manual`. Kill the session, `git worktree remove .worktrees/_vp_manual`, `git branch -D _vp_manual`.
- [ ] **MANUAL:** From **inside** an existing tmux session (this is the load-bearing AC #3): `lazy-llm -W _vp_inside` — confirm a brand new tmux session is created (visible via `tmux ls`), NOT a new window in the current session. Detach, verify session list, then clean up worktree + branch.
- [ ] **MANUAL:** Run `lazy-llm -W _vp_inside` a second time while the first session is still alive — confirm the "Existing lazy-llm session ... already at this worktree; attaching..." message appears and tmux switches/attaches to the existing session instead of creating a duplicate.
- [ ] **MANUAL:** Run `lazy-llm -W _vp_inside -t gemini` on a fresh branch — confirm `-W` composes with `-t` (auto-derived session name includes `-gemini` suffix; gemini launches in the AI pane).

## Verify Report

**Date:** 2026-05-13

### Summary
All 28 agent-executable checks PASS across structural, shell-behavior, unit-test, docs, and backwards-compat categories. The 4 manual items (live tmux session spawn from inside/outside tmux, dedup attach, `-W` + `-t` composition) are deferred to human validation because they involve disruptive interactive tmux operations.

### Structural / code-site — all 14 PASS
- `getopts` string is `"s:d:t:wW:h"` (line 74), `W) WORKTREE_BRANCH="$OPTARG" ;;` case at line 80
- Help text mentions `-W`, `.worktrees/<branch>`, `LAZY_LLM_WORKTREE_DIR`, and "Always creates a new session"
- Worktree-setup block at line 109-135, between getopts (74-99) and `init_state_dirs` invocation
- Block flow: `lazy_llm_setup_worktree` → capture path → `lazy_llm_find_session_for_path` → `unset TMUX` + `NEW_WINDOW=false` → auto-derive session name
- Sanitization: `SANITIZED="${WORKTREE_BRANCH//\//-}"` (line 133), used only in auto-derived session name and worktree path
- Lib sourcing block at line 8-15 (sibling-first, dev-fallback) — new in this commit
- All three helpers exist: `lazy_llm_ensure_gitignore` (187), `lazy_llm_find_session_for_path` (201), `lazy_llm_setup_worktree` (222)
- `grep -qxF` used at 3 sites (gitignore idempotency, worktree-list match, branch-already-checked-out detection)
- `.gitignore` touch guarded by `[[ "$base" == "$repo/.worktrees" ]]` (lib line 235)
- Branch-elsewhere detection uses `worktree list --porcelain | grep -qxF "branch refs/heads/$branch"` (lib line 254)
- `find_session_for_path` calls `realpath` on both target and each candidate's `dir`, with raw-string fallback
- `find_session_for_path` consumes `lazy_llm_gather_sessions` (single source of truth for marker filtering)

### Shell-behavior verifications — all PASS
- Happy path: `lazy_llm_setup_worktree _vp_check` returns the expected path; second call returns identical path (idempotent)
- Branch ref present at HEAD after creation
- `.gitignore` contains exactly one `.worktrees/` line (no duplicates from multiple invocations)
- Slash sanitization: `_vp/slashy` → path basename `_vp-slashy`, branch ref `_vp/slashy` (slash preserved in ref)
- Branch checked out elsewhere → rc=1 with the documented error + hint
- `LAZY_LLM_WORKTREE_DIR` override creates worktree at the override location AND leaves `.gitignore` byte-identical
- Non-git directory → rc=2 with "not inside a git repository" error
- `find_session_for_path` on a non-existent path returns empty (no error)

### Unit tests — all 4 PASS via the runner
- 12-worktree-primitive-unit (new): 23 assertions
- 11-dashboard-shell-unit: still green
- 10-pane-status-detection: still green
- 09-init-state-dirs-unit: still green

### Docs — PASS
- README line 97 documents `-W <branch>` behavior + line 111 has `LAZY_LLM_WORKTREE_DIR` example
- USAGE line 39 added the `-W` row

### Backwards compat — PASS
- `-s/-d/-t/-w` flag descriptions unchanged in help text
- Subcommand dispatch (`lazy-llm list`) still works correctly after the lib-sourcing block was added above it

### Deferred to human validation
- Live spawn of a new tmux session via `-W` from outside tmux
- Live spawn from **inside** tmux confirming it creates a session not a window (the load-bearing remaining AC)
- Dedup attach when a session already exists at the worktree path
- `-W` + `-t` composition with auto-derived session name suffix

## Work Report

**Date:** 2026-05-13

### What was done
- Added `lazy-llm -W <branch>` that creates a session bound to a git worktree in one shot
- Three new helpers in `lazy-llm-lib.sh`: `lazy_llm_setup_worktree` (worktree create-or-locate), `lazy_llm_find_session_for_path` (realpath-based session lookup), `lazy_llm_ensure_gitignore` (idempotent gitignore append)
- `lazy-llm` script now sources the lib at the top (it didn't before)
- `-W` flag added to `getopts`, wired between argparse and `init_state_dirs` so `TARGET_DIR` is set correctly before state-dir init
- Help text updated: `-W <branch>`, `LAZY_LLM_WORKTREE_DIR` env var, the "always spawns a new session" caveat
- README + USAGE updated with usage examples, override env var, and cleanup pattern

### How it was done
- **Branch detection:** `git show-ref --verify --quiet refs/heads/$branch` distinguishes existing from new branches. New branches use `git worktree add -b`, existing ones use plain `git worktree add <path> <branch>`
- **Conflict refusal:** `git worktree list --porcelain | grep -qxF "branch refs/heads/$branch"` detects when a branch is already checked out in any worktree. The `-qxF` combo is exact-line + fixed-string — no regex injection from branch names
- **Force new-session mode:** `unset TMUX` short-circuits the existing `[ -n "$TMUX" ]` detection ~line 227 without touching that block. Bonus: when `tmux new-session` runs, the new session doesn't inherit a stale `$TMUX` from the calling client
- **Realpath comparison:** both the target path and each candidate session's `pane_current_path` go through `realpath` before comparison, so symlinks (like `.worktrees/` itself being symlinked, or `realpath` differences in home dir) don't break dedup
- **Idempotency:** `lazy_llm_ensure_gitignore` uses `grep -qxF` (exact-line, fixed-string) to skip already-present patterns. `lazy_llm_setup_worktree` checks `git worktree list --porcelain` for an existing registration before deciding to create
- **Slash sanitization:** only the *path* component sanitizes (`feature/foo` → `.worktrees/feature-foo/`). The branch name passed to `git` keeps the slashes — git accepts them natively in branch refs

### Decisions made
- **In-repo `.worktrees/` default with auto-gitignore.** Documented in the plan. Cleanest UX: nothing to configure for the common case, env var override for the uncommon one
- **No new dispatcher subcommand** (e.g. `lazy-llm worktree <branch>`). The original task body mentioned this as an alias form, but YAGNI — the `-W` flag covers it. Keep one obvious way to do it
- **`unset TMUX`** rather than adding a new "force new session" boolean. Documented in the plan
- **Help text in-place** rather than refactoring into a heredoc. The existing pattern is `echo`-line per row; consistency wins over the slight tedium
- **Sanitization only on the path side.** Slashes in branch refs are valid and idiomatic (`feature/foo`, `release/1.2`); converting them in the ref would silently surprise users who expect their branch to be named what they typed
- **Auto-derived session name includes the tool name** (`dev-<sanitized>-<ai_tool>`), matching the existing pattern from non-worktree invocations. Means `-W feature/foo -t gemini` and `-W feature/foo -t claude` get distinct sessions — desirable

### Commits
- `3a3e54f` — feat(worktree): add lazy-llm -W <branch> primitive

### Files changed
- `lazy-llm-bin/.local/bin/lazy-llm` — `-W` flag, worktree-setup block (~25 lines), lib-sourcing at top, help text expansion
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — three new helpers (~85 lines)
- `tests/scenarios/12-worktree-primitive-unit.sh` (new, 221 lines) — 23 unit assertions
- `README.md` — Worktree-per-task subsection + behavior bullet
- `docs/USAGE.md` — one new row
- `.gitignore` — auto-added `.worktrees/` during the live smoke test

### Sources Consulted
- None — no `~/.claude/coding-standards/` for this project. Followed conventions from CLAUDE.md and the existing `lazy-llm-lib.sh` codebase

### Follow-up
- **`find_session_for_path` doesn't `return 0` explicitly after fall-through.** The function relies on the implicit success of the `done` line. Should be safe (callers tolerate empty stdout), but worth adding an explicit `return 0` for clarity — flagging for `lazy-llm-refinement-pass`
- **`worktrees-dashboard` link in the task body is stale** — the task `worktrees-dashboard` was renamed to `worktree-bridge-tab` earlier in this session. Pre-existing in the task body when I picked it up; not blocking, but worth fixing in a future doc pass
- **`-W` doesn't compose with `-d`.** If both are passed, `-W` wins (it overwrites `TARGET_DIR`). Probably the right behavior, but undocumented. If anyone hits this surprise, flag for refinement
- **Cleanup is a manual `git worktree remove + git branch -D` today.** The `worktree-bridge-tab` task will surface an atomic cleanup action in the dashboard. Not in scope here

## Human Validation

**Commit(s):** `3a3e54f`

This task hits real tmux behavior the agent cannot observe from a non-interactive shell: the AC "always spawns a new session, even from inside tmux" is the load-bearing behavioral contract and can only be confirmed by running it under an attached tmux client. Code inspection shows `unset TMUX` + `NEW_WINDOW=false`, but the actual session-vs-window outcome is what matters to users.

### Checks

- [ ] **Always-new-session from inside tmux (load-bearing AC).** From inside an existing tmux session in this repo, run `lazy-llm -W _hv_inside`. Expect: a brand new tmux session is created and you are switched/attached to it — NOT a new window in the current session. Verify with `tmux ls` from a separate terminal (two sessions listed). Detach, then `git worktree remove .worktrees/_hv_inside && git branch -D _hv_inside`.

- [ ] **Dedup attach is non-disruptive.** With the `_hv_inside` session from the previous check still alive, run `lazy-llm -W _hv_inside` again. Expect: the "Existing lazy-llm session ... already at this worktree; attaching..." message, and tmux switches/attaches to the existing session — no duplicate session is created, no panes are re-spawned. (This is the UX promise; agent confirmed the code path but not the user-visible result.)

- [ ] **`-W` + `-t` composition under a real spawn.** On a fresh branch, run `lazy-llm -W _hv_compose -t gemini`. Expect: session name ends in `-gemini`, the AI pane launches the gemini CLI (not claude), and all three panes are rooted at `.worktrees/_hv_compose`. Clean up after.

### Design Decisions

- **In-repo `.worktrees/` default + auto-gitignore.** Chosen for zero-config UX in the common case; `LAZY_LLM_WORKTREE_DIR` covers the uncommon one. *Assess: is auto-mutating `.gitignore` on first `-W` invocation acceptable, or should it be opt-in/prompted?*

- **No `lazy-llm worktree <branch>` subcommand alias.** The original task body mentioned this; dropped as YAGNI in favor of the `-W` flag alone. *Assess: is one obvious way the right call, or does a subcommand form aid discoverability for users browsing `lazy-llm --help`?*

- **`unset TMUX` to force new-session mode** rather than threading a "force new session" boolean through the existing `[ -n "$TMUX" ]` branch. *Assess: is this clever-but-implicit approach acceptable, or does it deserve an explicit `FORCE_NEW_SESSION=true` variable for future maintainers?*

- **Sanitize slashes only on the path side, never the branch ref.** `feature/foo` becomes `.worktrees/feature-foo/` on disk but stays `feature/foo` as a git ref. *Assess: this matches git idioms but means the on-disk name diverges from the branch name — is that the right tradeoff vs. e.g. nested `.worktrees/feature/foo/` directories?*

- **Auto-derived session name includes the AI tool suffix** (`dev-<sanitized>-<ai_tool>`), so `-W feature/foo -t claude` and `-W feature/foo -t gemini` are distinct sessions on the same worktree. *Assess: is parallel-tool-on-same-worktree a real workflow worth supporting at the naming level, or would a single session per worktree be cleaner?*

### Sign-off

| Status | Validator | Date | Notes |
|--------|-----------|------|-------|
| | | | |

Status: PASS / FAIL / SKIP / PARTIAL

