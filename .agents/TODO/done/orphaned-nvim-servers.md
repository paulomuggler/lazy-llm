---
slug: orphaned-nvim-servers
title: Orphaned nvim --embed servers stuck on a prompt after their pane dies (24 GB leak)
priority: P0
status: done
created: 2026-09-30_15:00
updated: 2026-09-30_15:40
depends-on: []
tags: [nvim, tests, memory, teardown]
commits: [c4f9efc]
---

# Orphaned nvim --embed servers stuck on a prompt after their pane dies

## Context

Reported by the ai-dev-workflow-c8 session: 29 `nvim --embed` processes, parent
= the systemd user manager, 1.5–2.5 days old, held ~24 GB of homelab-zrh-dev's
60 GB. 27 had a deleted `/tmp/lazy-llm-test-*` cwd (test runs); 2 were real
workspace nvims in `external/lazy-llm`.

## Findings

- Every one was in `nvim_get_mode() = {mode="r"|"rm", blocking=true}`: stuck on a
  hit-enter/pager prompt with its TUI gone. SIGTERM did nothing — a blocking
  prompt defers deadly signals (and the UI's departure) until a key answers it.
- Growth: events keep queuing while blocked and never run. Pressing `<CR>` via
  `nvim_input` on one released the queued SIGTERM, but RSS then went 3.9 → 7.3 GB
  working through the backlog; the rest were SIGKILLed. ~29 GB freed.
- Deterministic repro: scenario 21 test 7 (swap-file ATTENTION on the `-- More --`
  pager, then `kill-server`) leaked one server every run.
- Scenarios 04/05 left two prompt nvims in `mode="r"` in one full run out of two;
  the message behind that prompt wasn't identified (race at teardown). A plain
  hit-enter or pager prompt, modified buffer, VimLeavePre error or deleted cwd
  at kill time did not reproduce it in isolation.

## Fix (c4f9efc)

- `lua/lazy_llm/orphan.lua`, started from the session plugin's `init` in every
  lazy-llm nvim (before file args, so the startup swap prompt is covered): a
  libuv timer (fires even while blocked) exits the process once its parent is
  gone and it's still blocked, two 5s checks in a row. `:detach`ed servers
  aren't blocked and are left alone (verified).
- `tests/test-runner.sh`: records the tmux server's process tree before
  `kill-server` and SIGKILLs survivors; reaps reparented processes in the run's
  workroot, and at start those >10 min old under `/tmp/lazy-llm-test-*`
  (leftovers of runs killed before their cleanup).
- Scenario 21: test 7 kills its blocked nvim; new test 8 checks the guard ends
  the orphaned server within 15s.

## Verification

Full suite 22/22, zero orphans or leftover processes afterwards (previous
unfixed runs: 3 and 1 orphans).
