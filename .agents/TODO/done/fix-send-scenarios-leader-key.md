---
slug: fix-send-scenarios-leader-key
title: Fix scenarios 01-07: they assume a backslash leader and window 0
priority: P2
status: done
created: 2026-09-27_16:13
updated: 2026-09-28_13:42
depends-on: []
tags: [tests]
commits: [0cc0a23, 792395a]
---

# Fix scenarios 01-07: they assume a backslash leader and window 0

## Context
Found during workspace-save-restore. `tests/lib/tmux-helpers.sh` `trigger_llm_send` sends `\llms`, assuming nvim's leader is backslash; under LazyVim the leader is Space, so the send never fires and the trailing `s` substitutes a character. The helpers also hard-code window `:0` / pane indexes, which breaks under a `base-index 1` tmux.conf. Scenarios 01-07 have failed for these reasons since before that task. Resolve the leader (`nvim --headless -c 'echo mapleader'` or send `<Space>`) and the window and pane indexes from tmux instead of assuming them.

## Acceptance Criteria
- [x] Scenarios 01-07 pass under the user's LazyVim config and `base-index 1` tmux.conf
- [x] The full suite passes, repeatably (21/21, three consecutive runs)
- [x] Running the suite from inside the user's tmux leaves their server and Saved list untouched

## Work Report

The leader key and window `:0` were only part of it. Once the keymaps fired, each scenario hit its
own problem:

| Scenario | Cause | Fix |
|---|---|---|
| all | keymaps typed with a `\` leader (LazyVim: Space) | `nvim_leader` reads it from the user's config (headless, 0.04s, once per session) |
| all | panes looked up at window `:0` by index | `resolve_test_panes` uses the `@AI_PANE_ID`/`@PROMPT_PANE_ID` that lazy-llm records |
| 02, 04 | timestamp matched as `YYYY-MM-DD-HH:MM:SS`; `llm-send` has written `%F %T` since 2025 | test regexes |
| 04 | every line doubled (tty echo + mock echo) | mock runs with `stty -echo`, like a real TUI |
| 04, 05, 07 | mock mode taken from whoever first started the tmux server (pane shells inherit the server's env) | `tmux set-environment -g` per session |
| 05 | prompt pane 5 rows tall in an 80x24 detached session, so the pulled response is off-screen | runner's server uses `default-size 220x80` |
| 06 | **real bug:** visual `<leader>llms` ran `<,'>write!` (malformed range; would also have used the previous selection) and never sent anything | `0cc0a23`: read lines via `line("v")`/`line(".")` |
| 07 | mock's choice prompt waited for Enter; `<leader>llmk` sends one key, and `llm-send`'s submit Enter was still queued | mock reads one key and skips a bare Enter |

Harness hardening (`792395a`):
- The runner uses a private tmux server, `LAZY_LLM_STATE_DIR` and a work root, all cleaned up on
  exit (kept with `-d`, which prints the attach command).
- Each test session gets a fresh working dir, so no prompt snapshot leaks between tests.
- Cleanup waits for exiting nvims and async saves before `rm`, since they would otherwise recreate
  the dirs.
- The README run instructions were wrong (`cd tests` breaks the runner) and are fixed.

Verified: full suite 21/21 three times in a row, run plainly from inside the user's tmux. No
`test-*` sessions on the live server afterwards, and no new `/tmp` leftovers (the fixed
`lazy-llm-test-{state,logs}` paths predate this).
