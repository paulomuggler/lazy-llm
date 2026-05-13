---
slug: fix-llm-sessions-marker-bug
title: Fix llm-sessions @lazy_llm marker scope mismatch (Prefix+S broken)
priority: P0
status: in-progress
created: 2026-05-13
updated: 2026-05-13
depends-on: []
tags: [bug, llm-sessions, tmux]
commits: []
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

- [ ] `tmux show-option` calls in `llm-sessions` read `@lazy_llm` with session scope (`-tv`, not `-sv`)
- [ ] Audit all `tmux show-option`/`set-option` calls across `lazy-llm-bin/.local/bin/*` for similar scope mismatches; fix any found
- [ ] With one or more active lazy-llm sessions, `Prefix+S` shows them in the picker
- [ ] Empty-state path: either auto-launch `lazy-llm` (in a new popup or by exiting cleanly) or show a message with a clearly bound key to close (`q`/`Esc`) and another to create
- [ ] Popup is always closable with `Esc` and/or `q`, even in the empty-sessions state
- [ ] Manual verify: open a fresh tmux server, run `lazy-llm`, press `Prefix+S` — session appears; `Esc` closes the popup
