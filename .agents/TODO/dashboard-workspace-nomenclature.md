---
slug: dashboard-workspace-nomenclature
title: Rename user-facing "session" to "workspace" throughout lazy-llm UI copy
priority: P2
status: in-progress
created: 2026-09-22_04:37
updated: 2026-09-22_04:40
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

- [ ] Dashboard tab shows "Workspaces" (or equivalent qualified wording) instead of bare
      "Sessions" in its header/prompt/help text
- [ ] `show_help_overlay` text uses "workspace" terminology for this concept, and
      keeps "AI pane" wording for panes (no confusion introduced there)
- [ ] README.md and docs/USAGE.md updated consistently — no leftover bare "session"
      where "lazy-llm workspace" is meant (grep for `\bsession\b` and check each hit)
- [ ] `llm-sessions --list`/help output text updated (flag names unchanged)
- [ ] `tests/scenarios/*.sh` still pass (update any hardcoded string assertions that
      targeted the old wording)
- [ ] No change to any `tmux` command target syntax, function name, binary filename, or
      tmux option name

## Verification recipe

```bash
cd tests && ./test-runner.sh   # full suite should pass
grep -rn '\bsession\b' README.md docs/USAGE.md lazy-llm-bin/.local/bin/llm-dashboard
# every remaining hit should be an intentional exception (e.g. "tmux session" in a
# technical aside), not user-facing dashboard copy
```
