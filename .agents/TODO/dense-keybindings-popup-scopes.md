---
slug: dense-keybindings-popup-scopes
title: Dense single-letter keybindings within lazy-llm popups (replace Ctrl+ chords)
priority: P2
status: pending
created: 2026-05-13
updated: 2026-05-13
depends-on: []
tags: [enhancement, ux, keybindings, popup]
commits: []
---

# Dense single-letter keybindings within lazy-llm popups (replace Ctrl+ chords)

## Context

Inside our popup scopes (`llm-sessions`, `llm-panes`, and the upcoming [[unified-llm-dashboard]] + [[worktree-bridge-tab]]) the popup-local keymap currently uses `Ctrl+`-style chords for destructive/secondary actions (e.g. `ctrl-d` to kill, `ctrl-n` for new). These are unnecessarily heavy when the keymap is fully scoped to a modal popup that consumes all keys.

This task **does not** add or change any global nvim or tmux keybindings — the user has been clear that global keybinding space should be conservative to avoid conflicts. The scope here is **popup-local only**: while a lazy-llm popup is the focused tmux popup, the popup process owns all keystrokes, so single-letter bindings are safe and dense.

Target idiom (claude-tmux's keymap is a good reference):
- `j`/`k` or arrows — move selection
- `Enter` — primary action (switch)
- `n` — new
- `K` — kill (uppercase to require shift, mild safety)
- `r` — rename
- `/` — filter
- `R` — refresh
- `?` — help
- `q` / `Esc` — quit

## Key Files

- `lazy-llm-bin/.local/bin/llm-sessions` — fzf `--expect` list currently uses `ctrl-d,ctrl-n`; switch to lowercase letter bindings (or retire entirely if folded into the unified dashboard)
- `lazy-llm-bin/.local/bin/llm-panes` — same treatment (or retire)
- Any new dashboard introduced by [[unified-llm-dashboard]] / [[worktree-bridge-tab]] should adopt the convention from inception

**Coordination note:** if [[unified-llm-dashboard]] ships first and replaces both `llm-sessions` and `llm-panes`, this task may be fully absorbed into that one. Re-evaluate scope after the dashboard lands.

## Acceptance Criteria

- [ ] Audit current popup-scope keybindings across `llm-sessions`, `llm-panes`; document the existing map in the task body
- [ ] Replace `Ctrl+` chords with single-letter bindings within popups, where safe (avoid clashing with fzf's own bindings like `Ctrl-c` cancel, `Tab` select)
- [ ] Document the popup keymap in `README.md` under each manager's section
- [ ] No changes to global tmux or nvim keymaps in this task
- [ ] Manual verify: every popup action reachable by a single letter; `q` and `Esc` both quit
