---
slug: claude-subagent-worktrees
title: Claude Code's subagent / EnterWorktree worktrees go through llm-wt (hooks, parent integration, guidance)
priority: P1
status: in-progress
created: 2026-10-02_18:25
updated: 2026-10-02_18:49
depends-on: []
tags: [worktree, claude-plugin, hooks, concurrency]
spec: ../specs/claude-subagent-worktrees.md
model: inline
owner: homelab-zrh-dev-2409537
commits: [e99b6d0, b86940d, aae105f, f74c8e2]
---

# Claude Code's own worktrees go through llm-wt

## Context

A single Claude session can fan work out to subagents with `Agent(isolation: "worktree")`, but
that path bypasses lazy-llm. Claude branches the worktree from **origin's default branch** (stale
code, wrong base), skips the `.env`/`.work-state` bootstrap, nothing merges it back, and
lazy-llm never sees it. The fix is the `WorktreeCreate`/`WorktreeRemove` hooks in lazy-llm's
own plugin, which route creation and removal through `llm-wt`. The parent session integrates
with `llm-wt integrate --remove`, and hooks give just-in-time guidance to subagent, parent and
`EnterWorktree` sessions. The user approved the design on 2026-10-02 and flagged correctness and
verification as the main risks.

Full design: [`specs/claude-subagent-worktrees.md`](specs/claude-subagent-worktrees.md), §1–§9,
§11, §12. Spike facts S1–S10 (§2) are load-bearing. If one no longer holds, stop and report it.

## Key Files
- `llm-wt-bin/.local/bin/llm-wt`: new `claude-hook` subcommand, `integrate --remove`, `list`,
  repo lock, `.worktreeinclude`, kind-aware base dir, `LAZY_LLM_WORKTREE_KIND` for the init hook
- `llm-send-bin/.local/bin/lazy-llm-lib.sh`: `lazy_llm_setup_worktree` (reused as-is if possible)
- `llm-status-bin/.local/bin/llm-claude-hook`: remove `worktree_context` (moves to llm-wt, §7.3)
- `llm-status-bin/.local/share/lazy-llm/`: new `worktree-subagent.md`, `worktree-parent.md`;
  marker comment on `worktree-agent.md`
- `claude-plugin/hooks/hooks.json`, new `claude-plugin/hooks/worktree.sh`
- `claude-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`: version 0.4.0
- `tests/scenarios/24-claude-worktrees-unit.sh`, `tests/scenarios/25-claude-worktrees-live.sh`
- `README.md` (Isolated AI panes section + commands table), `docs/USAGE.md`

## Read first
- `.agents/TODO/specs/claude-subagent-worktrees.md`: the design
- `.agents/TODO/specs/worktree-concurrency-mode.md` §4–§8: the pane-worktree model this extends
- `tests/scenarios/22-worktree-pane-unit.sh`: the sandboxing pattern (cd into the sandbox, GIT_CEILING_DIRECTORIES)
- https://code.claude.com/docs/en/hooks.md: hook I/O. The spike overrides the docs on the WorktreeCreate payload (S2)

## Constraints
- `worktree.sh` must **never** leave `WorktreeCreate` without a path on stdout while git works
  (S3): fallback per §8. It must not sit behind llm-claude-hook's TMUX_PANE or nested-claude guards.
- Portable bash (Linux + macOS): no jq in shipped code, `flock` optional (mkdir-lock fallback).
- Never `--force` a removal from a hook. Unintegrated work survives every automatic path.
- Don't change pane-worktree behavior beyond what §4 (`.worktreeinclude`, KIND env) and §7.3
  (guidance source) state. Scenario 22 must still pass unchanged.
- Tests follow memory rules: `unset TMUX TMUX_PANE`; `cd` into the sandbox; never run git with
  a possibly-empty path.

## Verification recipe
- `tests/test-runner.sh 24-claude-worktrees-unit.sh`, plus 22, 19, 12 (regressions)
- `LAZY_LLM_LIVE_CLAUDE=1 tests/test-runner.sh 25-claude-worktrees-live.sh` (real Claude, ~3 runs)
- `shellcheck` on every changed shell file
- After deploy: `claude plugin list` shows lazy-llm 0.4.0, and the cached plugin's hooks.json has WorktreeCreate

## Acceptance Criteria
- [x] `WorktreeCreate` → `.worktrees/.claude/<name>` on `lazy/<name>` from the parent's HEAD, with kind/name/session/pane/base/primary config, bootstrap, stdout = path only (§4)
- [x] Nested parent (in a pane worktree) → base/primary = the pane worktree, dir under the main repo (§4.2–4.3)
- [x] Repo lock: 8 parallel creates all succeed with full config (§9)
- [x] `SubagentStop` removes an empty agent worktree, keeps any with work, ignores non-isolated agents (§5.2)
- [x] `WorktreeRemove` refuses to lose work, removes clean ones (§5.1)
- [x] Guidance: SubagentStart (§7.1), PostToolUse Agent (§7.2), PostToolUse EnterWorktree + SessionStart from git config (§7.3); llm-claude-hook no longer emits it
- [x] `llm-wt integrate --remove`, `llm-wt list` (§6); `.worktreeinclude` honored (§4)
- [x] Plugin shim with fallback (§8); hooks.json wired; version 0.4.0
- [x] Scenario 24 passes, covering every §12.1 case; 22/19/12 still pass
- [x] Scenario 25 passes live (§12.2) — 30/30 on the final run
- [x] README + USAGE updated (incl. §11 limits)
- [ ] Deployed: install.sh run, plugin 0.4.0 active for new sessions; lazy-llm pushed; dev-env submodule pointer bumped and pushed

## Work Report

**Date:** 2026-10-02_18:49

### What was done
- `llm-wt claude-hook`: one handler for WorktreeCreate, WorktreeRemove, SubagentStart, SubagentStop,
  PostToolUse (Agent, EnterWorktree) and SessionStart (spec §4–§7). Claude's worktrees land in
  `.worktrees/.claude/<name>` on `lazy/<name>` from the parent's HEAD, with kind/name/session/pane/
  base/primary in git config, the usual bootstrap, and integrate into the parent's branch (nesting
  through pane worktrees, root found by the lazyLlmPrimary chain, so submodules work).
- Removal never forces: WorktreeRemove refuses to lose work; SubagentStop removes only an empty
  worktree of kind claude whose name matches the agent.
- `llm-wt integrate --remove`, `llm-wt list`; repo lock (flock / mkdir) around shared-config writes;
  `.worktreeinclude` honored (copy); `LAZY_LLM_WORKTREE_KIND` for the init hook.
- Guidance files `worktree-subagent.md`, `worktree-parent.md` (+ marker on `worktree-agent.md`);
  SessionStart guidance moved from llm-claude-hook (env) to llm-wt (git config).
- Plugin 0.4.0: `hooks/worktree.sh` shim with a plain-worktree fallback for WorktreeCreate.
- Tests: scenario 24 (140 assertions, 17 cases), scenario 25 (live, opt-in), scenario 22 test 15
  repointed at the new guidance source. README + USAGE.

### How it was done
- Two spike rounds with headless `claude -p` and logging hooks established the payload facts S1–S10
  before writing the spec; the live scenario then found S11 (background launches carry no
  worktreePath and fire no completion hook), fixed in `aae105f`.
- Each hook event runs in a child process of llm-wt so `set -e` holds in handlers; exit statuses are
  mapped so no event ever exits 2 (blocking semantics), and only WorktreeCreate/Remove can fail.

### Decisions made
- The parent integrates subagent work (spec §6); subagents only commit.
- Deviation from the "scenario 22 unchanged" constraint: its test 15 tested the guidance in
  llm-claude-hook, which spec §7.3 moves to llm-wt. Rewritten to assert the same behavior
  (isolated pane gets it once, shared pane gets nothing) through the plugin shim.
- `safe_name` now collapses `..` (invalid in a ref). Found by scenario 24; it also affected
  pane names (`llm-wt create <dir> 'a..b'` failed).

### Verification evidence (executor's own)
- Scenario 24: 140/140, stable across 14 consecutive runs. Mutation runs: removing the lock (3
  failures), the kind check (1), starting from origin's default branch (5), not following the
  root chain (1), forcing WorktreeRemove (3) are all caught. Removing SubagentStop's cleanliness
  pre-check is not caught by design: `cmd_remove` refuses on its own (defense in depth).
- Full suite: 24/24 scenarios pass.
- Scenario 25 live: run 2 caught S11 + a transcript-counting test bug; see the Verify Report for
  the final clean run.

### Commits
- `e99b6d0` — llm-wt: create and remove Claude Code's worktrees, guide subagent and parent
- `b86940d` — Claude plugin 0.4.0: route Claude's worktree and subagent hooks to llm-wt
- `aae105f` — llm-wt: guide the parent of a background subagent too
- `f74c8e2` — Live scenario for Claude's worktrees through llm-wt; document them

### Files changed
- `llm-wt-bin/.local/bin/llm-wt` — claude-hook, claude_create, lock, list, integrate --remove, .worktreeinclude, safe_name
- `llm-status-bin/.local/bin/llm-claude-hook` — guidance removed (moved to llm-wt)
- `llm-status-bin/.local/share/lazy-llm/worktree-{agent,subagent,parent}.md`
- `claude-plugin/hooks/{hooks.json,worktree.sh}`, plugin/marketplace version 0.4.0
- `tests/scenarios/{22,24,25}-*.sh`, `README.md`, `docs/USAGE.md`

### Sources Consulted
- `~/.claude/plugins/steward/skills/standards/references/` not loaded (lifecycle: development, shell);
  followed the repo's own conventions (portable bash, no jq in shipped code, shellcheck clean)
- https://code.claude.com/docs/en/hooks.md (via a docs agent); the spike overrides it on the WorktreeCreate payload

### Follow-up
- `claude-subagent-worktrees-ui` (already filed): Worktrees tab tag + `I`, border `⎇×N`, llmw picker.
- Not filed, noted in spec §11: Claude's `cleanupPeriodDays` sweep was not observed.
