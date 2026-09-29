---
slug: dashboard-early-input-quits
title: Fix a key pressed before the dashboard list loads closing the dashboard
priority: P1
status: done
created: 2026-09-27_23:30
updated: 2026-09-27_23:40
depends-on: []
tags: [bug, dashboard, fzf]
commits: [4a7f63b]
model: inline
---

# Fix a key pressed before the dashboard list loads closing the dashboard

## Context

Reported: "the dashboard crashes if input comes too soon when opening it before it's
rendered".

Reproduced on a sandbox tmux socket with two fake lazy-llm workspaces: `2` or `R` sent
immediately after launching `llm-dashboard` exited it (EXIT=0, no stderr); the same keys
1.5s later switched tab / refreshed normally.

Root cause, confirmed with a bare fzf fed through `(sleep 1; printf ...)`: fzf starts
reading keys before its input has loaded. A `print(KEY)+accept` bind (or `--expect` key)
firing then accepts with no current row, fzf exits 1, and each tab's
`|| { echo quit; return 0; }` closes the dashboard. Not a crash, a quit.

## Fix

`--sync` on all four tab fzf calls (Workspaces, Worktrees, Saved, Help). fzf then holds
the finder and every keystroke until the input is read and start/load bindings (the
Workspaces `load:pos(N)`) have run; an early key is queued and acted on. Gating the keys
with `start:unbind`/`load:rebind` was tried in the bare repro and rejected: it drops the
key instead of acting on it.

## Verification

- Sandbox repro, keys sent at t=0: `2` → Worktrees, `3` → Saved, `?` → Help, `R` refresh,
  `j` reorders, `z` folds; none quit. Same keys after 1.5s unchanged.
- tests/scenarios 11, 13, 14, 15, 16 pass.
- shellcheck unavailable on this machine (mise shim errors); `bash -n` clean.

Note for sandbox testing: set `LAZY_LLM_STATE_DIR` to a scratch dir. Without it, killing
the sandbox server leaves its workspaces in the real manifest as "restorable" (hit and
cleaned up during this fix).
