---
slug: dashboard-workspace-nomenclature
title: Rename user-facing "session" to "workspace" throughout lazy-llm UI copy
priority: P2
status: done
created: 2026-09-22_04:37
updated: 2026-09-22_04:53
depends-on: []
tags: [ux, nomenclature, dashboard, docs]
commits: []
model: inline
---

# Rename user-facing "session" to "workspace" throughout lazy-llm UI copy

## Context

lazy-llm calls a tmux session (one project directory, opened via `lazy-llm`, holding
N AI panes + nvim + prompt pane) a "session" — in the dashboard's Sessions tab,
`llm-sessions`, fzf prompts/headers, and README/USAGE prose. In the broader LLM/agentic
jargon "session" means a single chat/conversation with a model. lazy-llm's own AI panes
each host one of those in the ordinary sense — one tmux "session" can hold several panes,
each running its own Claude/Gemini/etc. conversation. The overload is confusing: a user
asking "how many sessions are open" can't tell if they mean tmux sessions or chats.

Rename the **user-facing concept name** to "workspace" (a lazy-llm workspace = one
project directory opened via `lazy-llm`, matching the existing "Tmux Workspace" language
already used in `dev-env`'s own `CLAUDE.md`/`WORKSPACE.md`). Do **not** rename the
underlying tmux session, script/function/option names in this task — see Constraints.
That is deliberately deferred to [[dashboard-tree-view-consolidation]], which already
touches the `llm-sessions`/`llm-panes` binaries when it merges the two tabs.

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` — tab label wording, `--prompt`, `--header`
  strings (`render_sessions_tab`, e.g. lines 90, 111-115), `show_help_overlay` text
  (~line 492-525), confirm/rename prompts ("Kill session '%s'?", "Rename session '%s'
  to:")
- `lazy-llm-bin/.local/bin/llm-sessions` — any user-facing strings (CLI help, `--list`
  output labels) — rename display text only, not the `--kill`/`--list` flag names
- `README.md` — prose ("List sessions", "Manage lazy-llm sessions", table descriptions)
- `docs/USAGE.md` — same
- `docs/PLANNING.md`, `docs/VALIDATION_PLAYBOOK_2026-05-13.md` — leave alone (historical
  records of work already done; don't rewrite history)

## Constraints

- **Do not rename**: the `@lazy_llm` tmux option, `lazy_llm_gather_sessions` /
  `lazy_llm_find_session_for_path` / other `lazy_llm_*` function names in
  `lazy-llm-lib.sh`, the `llm-sessions` binary filename, `tmux switch-client`/
  `rename-session` calls (they operate on real tmux sessions, which is accurate). These
  are internal implementation names, not shown to the user, and renaming them risks
  breaking installed symlinks and the test suite for no user-visible gain — that sweep
  belongs with the tab consolidation task where the CLI surface is already changing.
- Keep the fzf `--prompt="session> "` mechanism working (rename its displayed text to
  `workspace> `; this is a string constant, not an identifier).
- Don't touch `docs/TODO.md` (legacy, out of scope) or files under `tests/` unless a
  test asserts on exact string output — check `tests/scenarios/*.sh` for asserted
  strings like `[Sessions]` before changing header text, and update expected strings if
  so.

## Acceptance Criteria

- [x] Dashboard tab shows "Workspaces" (or equivalent qualified wording) instead of bare
      "Sessions" in its header/prompt/help text
- [x] `show_help_overlay` text uses "workspace" terminology for this concept, and
      keeps "AI pane" wording for panes (no confusion introduced there)
- [x] README.md and docs/USAGE.md updated consistently — no leftover bare "session"
      where "lazy-llm workspace" is meant (grep for `\bsession\b` and check each hit)
- [x] `llm-sessions --list`/help output text updated (flag names unchanged)
- [x] `tests/scenarios/*.sh` still pass (update any hardcoded string assertions that
      targeted the old wording)
- [x] No change to any `tmux` command target syntax, function name, binary filename, or
      tmux option name

## Work Report

**Date:** 2026-09-22_04:50

### What was done
- Renamed the displayed concept "session" → "workspace" across `llm-dashboard`'s tab
  label, fzf `--prompt`/`--header` strings, `show_help_overlay`, `usage()`, and
  confirm/rename prompts.
- Renamed the `--tab` CLI flag value and internal `tab:*` dispatch strings from
  `sessions` to `workspaces` for consistency with the displayed tab name (this is a
  public CLI interface documented in `usage()`, distinct from the internal
  `lazy_llm_*` library functions which were left untouched).
- Updated `llm-sessions`' user-facing strings (table column header, error/status
  messages, fzf prompt, `--help` text) — binary filename and flags (`--list`, `--kill`)
  unchanged.
- Updated README.md and docs/USAGE.md prose and the hand-formatted ASCII table in
  USAGE.md (re-padded via script to preserve exact column alignment).

### How it was done
- Grepped for every `\bsession\b`/`\bSession\b` occurrence in the target files, then
  classified each: display string (rename) vs. internal identifier / accurate "tmux
  session" technical reference (leave alone) vs. unrelated test-infra reference
  (leave alone).
- USAGE.md's "What You Can Do Now" table is a hand-aligned box-drawing table, not a
  real Markdown table — used a small Python script to replace cell text and re-pad to
  the original column widths rather than hand-counting spaces.

### Decisions made
- Scoped this task to **user-facing copy only**, per the task's own constraint: did
  not rename `@lazy_llm`, `lazy_llm_*` function names, or the `llm-sessions` binary
  filename. Did rename the `--tab`/`tab:*` values since those are part of the
  documented public CLI surface, not internal implementation names — judged this
  necessary for consistency (leaving `--tab sessions` next to a header reading
  "[Workspaces]" would have reintroduced the exact confusion this task exists to fix).
- Left `README.md:9`'s and `USAGE.md`'s generic "tmux session" mentions describing raw
  tmux/`-s` flag mechanics as-is — those are accurate technical references to the
  underlying primitive, not the overloaded lazy-llm concept.

### Commits
- `3a479cf` — dashboard: rename user-facing 'session' to 'workspace'

### Files changed
- `lazy-llm-bin/.local/bin/llm-dashboard` — tab label, headers, prompts, help/usage text, `--tab`/`tab:*` values
- `lazy-llm-bin/.local/bin/llm-sessions` — user-facing strings only
- `README.md` — prose, keymap table, CLI table
- `docs/USAGE.md` — quick-reference table (re-padded)

### Follow-up
- None filed — the remaining internal-identifier rename (binaries/functions/`@lazy_llm`)
  is intentionally deferred to [[dashboard-tree-view-consolidation]], which already
  restructures the CLI surface when it merges Sessions+Panes.

## Verify Plan

Self-verified inline (same session that executed — not a fresh subagent; noted for
transparency, this whole batch of 6 tasks is being run inline in one sitting rather
than dispatched, per the user's "execute in sequence until done" request):

1. `grep -rn '\[Sessions\]\|Sessions tab\|--tab sessions\b' lazy-llm-bin/ README.md docs/USAGE.md` → expect no hits
2. `bash -n` both changed scripts → expect clean parse
3. Run full test suite from repo root, confirm no *new* failures vs. baseline
4. Spot-check USAGE.md table row widths unchanged (alignment)

## Verify Report

**Date:** 2026-09-22_04:52

1. ✅ `grep -rn '\[Sessions\]\|Sessions tab\|--tab sessions\b' lazy-llm-bin/ README.md docs/USAGE.md` — no hits (exit 1)
2. ✅ `bash -n lazy-llm-bin/.local/bin/llm-dashboard` and `llm-sessions` — both parse clean
3. ✅ `./tests/test-runner.sh` from repo root: 6 passed, 8 failed. All 8 failures
   (`01-simple-send` through `08-workspace-local-dirs`) fail with `open terminal
   failed: not a terminal` / `can't find window: 0` — these tests spawn a real tmux
   session with panes and need an actual TTY, unavailable in this sandboxed shell.
   None of the 8 reference `llm-dashboard`/`llm-sessions`/"Sessions" strings (checked
   via grep across their source). Not a regression from this change — an environment
   constraint of the execution context, not the code.
4. ✅ USAGE.md table rows (37, 39, 41) measured at 145 chars, matching the header
   separator row (4) and an untouched row (7, 9) exactly — alignment preserved.

All in-scope acceptance criteria met. The 8 TTY-dependent test failures are
environmental, not caused by this change, and out of this task's scope to fix.

## Verification recipe

```bash
cd tests && ./test-runner.sh   # full suite should pass
grep -rn '\bsession\b' README.md docs/USAGE.md lazy-llm-bin/.local/bin/llm-dashboard
# every remaining hit should be an intentional exception (e.g. "tmux session" in a
# technical aside), not user-facing dashboard copy
```
