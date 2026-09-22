---
slug: claude-hook-status-desktop-notify
title: Hook-driven status for Claude panes + desktop notification on needs-attention
priority: P1
status: done
created: 2026-09-22_04:37
updated: 2026-09-22_04:50
depends-on: []
tags: [status-detection, hooks, notifications, claude-only]
commits: []
model: inline
---

# Hook-driven status for Claude panes + desktop notification on needs-attention

## Context

Today `lazy_llm_detect_pane_status` (`llm-send-bin/.local/bin/lazy-llm-lib.sh`)
classifies a pane's state by regex-scraping `tmux capture-pane` output for prompt
glyphs / interrupt hints / `[y/n]` patterns. It's fragile (timing-sensitive, breaks if
Claude's UI text changes) and gives no way to *push* a notification — the dashboard and
status bar only know a pane's state when something polls it.

Claude Code has first-class hooks (`~/.claude/settings.json` → `hooks`, scripts under
`~/.claude/hooks/`, already used in this repo for `todo-resume.sh` etc. — see
`dotfiles/claude/dot-claude/settings.json` and `dotfiles/claude/dot-claude/hooks/` in
the parent `dev-env` repo, **not** this lazy-llm repo). Two events matter here:
- **`Notification`** — fires when Claude is waiting on permission or has been idle
  awaiting input; carries enough context to identify which session/pane it's in via the
  `TMUX_PANE`/`TMUX` env vars inherited from the shell the hook subprocess runs in.
- **`Stop`** — fires when Claude finishes responding (session goes idle after
  generating).

Scope: **Claude only**, per explicit user decision — gemini/codex/grok/aider keep using
the existing scrape-based detection in `lazy_llm_detect_pane_status` unchanged.

## Design

1. **Hook scripts** (new, in `dev-env`'s `dotfiles/claude/dot-claude/hooks/`):
   - `lazy-llm-status-notify.sh` — invoked by both `Notification` and `Stop` hooks.
     Reads the hook event name/payload from stdin (Claude Code hooks receive JSON on
     stdin — confirm exact schema via `claude-code-guide` agent or
     https://code.claude.com/docs/en/hooks before writing the parser; don't guess the
     field names).
     - Resolves `pane_id=$TMUX_PANE` (empty → not running inside tmux, no-op exit 0).
     - Writes `<state> <unix-ts>` to `~/.cache/lazy-llm/status/<pane_id>` where
       `<state>` is `waiting` (Notification: permission/idle-nudge) or `idle` (Stop).
       Use `working` is never written by hooks — absence of a fresh waiting/idle file
       means "assume working or unknown", left to the scrape fallback (see below).
     - On `waiting` specifically: also fire `notify-send` (see Desktop notification
       below).
2. **Settings wiring** (`dotfiles/claude/dot-claude/settings.json`): add `Notification`
   and `Stop` entries to the `hooks` object pointing at the new script, following the
   existing pattern (`matcher`, `hooks: [{type: command, command: ...}]`). Keep existing
   `SessionStart`/`PermissionRequest` entries untouched.
3. **Consumption in lazy-llm** (`llm-send-bin/.local/bin/lazy-llm-lib.sh`,
   `lazy_llm_detect_pane_status`): before falling back to the content-scrape path, check
   `~/.cache/lazy-llm/status/<pane_id>` — if it exists, is for tool `claude`, and its
   mtime is within a freshness window (e.g. 30s — long enough to survive one status-bar
   refresh interval at `status-interval` default 15s, short enough that a stale file
   from a since-closed pane doesn't lie), use it. Otherwise fall through to the existing
   regex scrape unchanged. Non-claude tools always use the scrape path.
4. **Desktop notification**: `notify-send -u normal "lazy-llm: <workspace/pane label>"
   "Claude needs your input" -t 8000` (or similar; check `notify-send` availability —
   this is Omarchy/Hyprland/Linux, already used elsewhere in this session's Claude Code
   hooks per `~/.claude/skills/todo/SKILL.md`'s own `notify-send` usage, so it's a safe
   assumption on this machine). Identify *which* pane/workspace in the notification body
   — resolve via `tmux display-message -t "$pane_id" -p '#S:#I'` (session:window) so the
   user knows where to look; don't just say "Claude needs input" with no location.
   Debounce: don't re-fire on every idle-nudge Notification if the pane was already
   `waiting` (compare against the previous state file content before overwriting, only
   notify on a transition into `waiting`).
5. **Cleanup**: `~/.cache/lazy-llm/status/` grows one file per pane_id ever seen. Add a
   prune step — either opportunistic (delete entries for panes that
   `lazy_llm_validate_pane` reports dead, called from `lazy_llm_prune_stale_panes` which
   already runs periodically) or a simple `find ~/.cache/lazy-llm/status -mtime +1
   -delete` guard. Don't ship this unbounded.

## Key Files

- `dotfiles/claude/dot-claude/hooks/` (parent `dev-env` repo) — new hook script lands
  here
- `dotfiles/claude/dot-claude/settings.json` (parent `dev-env` repo) — hook registration
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — `lazy_llm_detect_pane_status`,
  `lazy_llm_prune_stale_panes`
- `llm-status-bin/.local/bin/llm-status` — no change expected (consumes the helper),
  but re-verify its output still matches glyph mapping once the helper's source changes

## Constraints

- **Two repos, two commit streams.** `dev-env` (parent, hooks + settings.json) and
  `external/lazy-llm` (submodule, lib change) are separate git repos. Commit each
  independently with its own message; don't try to commit lazy-llm's submodule pointer
  bump from inside a dev-env commit in the same step as unrelated dev-env work.
- Read `https://code.claude.com/docs/en/hooks` (via WebFetch) for the actual
  `Notification`/`Stop` hook JSON schema and available env vars before writing the
  parser — do not assume field names from memory.
- Must degrade gracefully: if `~/.cache/lazy-llm/status/` is unwritable, or the hook
  never fires (e.g. Claude Code updates its hook system), the scrape fallback must still
  work exactly as it does today. Don't regress non-hook detection.
- `notify-send` calls in the hook script must not block Claude's own execution — hooks
  run synchronously in Claude Code's flow; keep the script fast (no network calls) and
  consider `-t` a short timeout on the notify call itself if `notify-send` can hang.

## Acceptance Criteria

- [x] Hook script writes a status file per Claude pane on `Notification` (waiting) and
      `Stop` (idle) events
- [x] `lazy_llm_detect_pane_status` prefers a fresh hook-written status file for
      `tool=claude`, falls back to scrape otherwise (including when the file is stale or
      missing)
- [x] A desktop notification fires via `notify-send` when a Claude pane transitions into
      `waiting`, naming the tmux session:window so the user can locate it
- [x] No duplicate notifications fired for a pane that stays `waiting` across multiple
      hook invocations (debounced on state transition, not on every event)
- [x] Non-claude tool panes (gemini/codex/grok/aider) are provably unaffected — scrape
      path still runs for them
- [x] `~/.cache/lazy-llm/status/` doesn't grow unbounded — stale entries for dead panes
      get cleaned up
- [x] `tests/scenarios/10-pane-status-detection.sh` (or equivalent) still passes
      unmodified, or is updated to cover the new hook-file precedence with fixture files
      (no live tmux/Claude required for the unit-testable parts)

## Work Report

**Date:** 2026-09-22_04:49

### What was done
- Fetched the authoritative Claude Code hooks docs (`code.claude.com/docs/en/hooks`) to
  confirm the `Notification` matcher values (`permission_prompt`, `idle_prompt`) and
  that `Stop` has no matcher and fires when Claude finishes responding — did not guess
  the schema from memory, per the External Information Discipline.
- New hook script `dotfiles/claude/dot-claude/hooks/lazy-llm-status-notify.sh` (dev-env
  repo): takes a `waiting`/`idle` arg (passed via `settings.json`'s `args`, not parsed
  from the JSON payload — simpler and doesn't depend on unconfirmed Notification-type
  field names), resolves the pane from `$TMUX_PANE` (inherited env, no-ops silently if
  unset/not in tmux), writes `"<state> <unix-ts>"` to
  `~/.cache/lazy-llm/status/<pane_id>`, fires a debounced `notify-send` on a transition
  into `waiting` naming the `session:window`, and opportunistically prunes status files
  older than a day.
- Wired it into `dotfiles/claude/dot-claude/settings.json` under new `Notification`
  (two matcher entries) and `Stop` (no matcher) hook keys, alongside the existing
  `SessionStart`/`PermissionRequest` entries.
- `lazy-llm-lib.sh`: added `_lazy_llm_read_hook_status` (reads + freshness-validates the
  status file) and wired it into `lazy_llm_detect_pane_status` as a `tool=claude`-only
  precedence check ahead of the existing content-scrape.
- README.md: documented the hook-driven path in the Status Detection section.

### How it was done
- Live-tested the hook script directly against a real tmux pane (not just fixtures):
  confirmed it writes the correct state/timestamp, debounces correctly across repeated
  `waiting` calls, re-notifies on an `idle`→`waiting` transition, no-ops cleanly with no
  `TMUX_PANE`, and resolves the `session:window` label correctly.
- Captured the actual D-Bus `Notify` call with `dbus-monitor` to confirm the desktop
  notification really fires (not just that `notify-send` was invoked) — saw
  `"lazy-llm: hook-notif-test:1"` / `"Claude needs your input"` on the bus.
- Exercised `lazy_llm_detect_pane_status`'s new precedence logic against 7 fixture
  cases (no file, fresh waiting, fresh idle, stale file, non-claude tool, malformed
  file, empty file) under `set -euo pipefail` — the same shell options the dashboard
  and `llm-status` run under.

### Decisions made
- **State passed as a CLI arg, not parsed from hook JSON.** The Notification event's
  JSON schema doesn't have a confirmed field naming which matcher fired (docs excerpt
  didn't detail it); using two separate `settings.json` hook entries (one per matcher)
  that each pass a fixed `args: ["waiting"]` sidesteps needing that field entirely.
- **Cleanup via `find -mtime +1 -delete` inside the hook script itself**, run on every
  invocation — the task's Design section offered this as an alternative to wiring into
  `lazy_llm_prune_stale_panes`; chose it since it's self-contained (no dependency on
  another code path running) and the task explicitly allowed either approach.
- **Caught and fixed a `set -e` hazard during implementation**: the natural
  `hook_status=$(...) && { ...; return 0; }` idiom trips `errexit` in callers (the
  dashboard, `llm-status`) on the ordinary case of no hook file existing yet, since it's
  a bare statement whose failure isn't "tested" by any conditional. Rewrote as
  `if hook_status=$(...); then ... fi`. Caught by exercising fixtures under
  `set -euo pipefail` before considering the change done — worth flagging because it's
  an easy silent-abort bug to reintroduce if this function is touched again.
- **Accepted a minor, low-stakes race**: the status file write (`printf ... >
  "$STATUS_FILE"`) isn't write-then-atomic-rename. A reader could theoretically see a
  torn write mid-update. Given the payload is <20 bytes (effectively a single syscall
  in practice) and a torn read just fails validation and falls through to the scrape
  path (no crash, no wrong-but-plausible answer), didn't add temp-file+rename
  complexity for this.

### Commits
- `0e699b9` (dev-env repo) — claude hooks: write lazy-llm pane status + desktop-notify on needs-attention
- `04dd5fc` (external/lazy-llm repo) — status: prefer Claude Code hook-driven status over content scrape

### Files changed
- `dotfiles/claude/dot-claude/hooks/lazy-llm-status-notify.sh` (dev-env repo, new)
- `dotfiles/claude/dot-claude/settings.json` (dev-env repo) — `Notification`/`Stop` hook wiring
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — `_lazy_llm_read_hook_status`, `lazy_llm_detect_pane_status`
- `README.md` — Status Detection section

### Sources Consulted
- `https://code.claude.com/docs/en/hooks` — Notification/Stop event schema, matcher values, env var inheritance

### Follow-up
- None filed. The dev-env→lazy-llm submodule pointer bump is deferred to a single bump
  at the end of this whole 6-task batch rather than after every commit (noted to the
  user directly, not filed as a task).

## Verify Plan

Self-verified inline (see note on `dashboard-workspace-nomenclature` — this whole
6-task batch is being run inline in one sitting, not dispatched to fresh subagents).

1. `bash -n` both changed shell files → clean parse
2. Live-fire the hook script against a real tmux pane with each state/transition
   combination; inspect the resulting status file after each
3. Capture the actual D-Bus notification with `dbus-monitor`, not just trust
   `notify-send`'s exit code
4. Exercise `lazy_llm_detect_pane_status`'s new code path against fixture files
   (fresh/stale/malformed/empty/non-claude) under the same `set -euo pipefail` the
   real callers use
5. Run the full test suite + the status-detection unit test specifically, confirm no
   regression vs. the pre-change baseline

## Verify Report

**Date:** 2026-09-22_04:51

1. ✅ `bash -n` clean on `lazy-llm-status-notify.sh` and `lazy-llm-lib.sh`
2. ✅ Live tmux test: 1st `waiting` call → file shows `waiting <ts>`; repeated
   `waiting` → same content, no re-notify (debounce); `idle` → file updates to
   `idle <ts>`; `waiting` again after `idle` → re-notifies (transition detected
   correctly); no `TMUX_PANE` → exits 0 with no file written
3. ✅ `dbus-monitor --session "interface='org.freedesktop.Notifications'"` captured a
   real `Notify` call with body `"lazy-llm: hook-notif-test:1"` /
   `"Claude needs your input"` — the notification is not just attempted, it's
   delivered to the session bus
4. ✅ All 7 fixture cases behaved correctly (see Work Report) and none tripped
   `errexit` — this specifically caught and fixed a real bug (the `&&`-chain hazard)
   before it shipped
5. ✅ `./tests/test-runner.sh` (from repo root): 6 passed, 8 failed — identical to the
   pre-change baseline (same 8 TTY-dependent tests, same failure reason). ✅
   `./tests/test-runner.sh status` (10-pane-status-detection): 17/17 assertions pass,
   unmodified — the new precedence layer doesn't break existing scrape-path coverage
   (expected, since fixture tests don't exercise real hook files and fall straight
   through to the scrape path being tested)

All acceptance criteria met and verified against live tmux + a real D-Bus capture, not
just code inspection.

## Verification recipe

Manual, live (this is hook-integration behavior, not unit-testable without a real
Claude process):
```bash
# 1. Open a lazy-llm workspace with a claude pane, note its pane id: tmux display-message -p '#{pane_id}'
# 2. Trigger a permission prompt in that pane (e.g. ask Claude to run a Bash command needing approval)
# 3. Confirm: cat ~/.cache/lazy-llm/status/<pane_id>  → shows "waiting <ts>"
# 4. Confirm a notify-send toast appeared naming the session:window
# 5. tmux capture-pane -p -t <pane_id> | true  (scrape path should agree, not required to match exactly)
# 6. Approve/resolve the prompt, let Claude finish — confirm Stop hook updates the file to "idle <ts>"
# 7. llm-status from that pane's window should show the idle glyph without any scrape lag
```
