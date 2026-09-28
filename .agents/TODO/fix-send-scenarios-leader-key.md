---
slug: fix-send-scenarios-leader-key
title: Fix scenarios 01-07: they assume a backslash leader and window 0
priority: P2
status: in-progress
created: 2026-09-27_16:13
updated: 2026-09-28_13:26
depends-on: []
tags: [tests]
commits: []
---

# Fix scenarios 01-07: they assume a backslash leader and window 0

## Context
Found during workspace-save-restore. `tests/lib/tmux-helpers.sh` `trigger_llm_send` sends `\llms`, assuming nvim's leader is backslash; under LazyVim the leader is Space, so the send never fires and the trailing `s` substitutes a character. The helpers also hard-code window `:0` / pane indexes, which breaks under a `base-index 1` tmux.conf. Scenarios 01-07 have failed for these reasons since before that task. Resolve the leader (`nvim --headless -c 'echo mapleader'` or send `<Space>`) and the window and pane indexes from tmux instead of assuming them.
