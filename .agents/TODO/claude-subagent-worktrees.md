---
slug: claude-subagent-worktrees
title: Claude Code's subagent / EnterWorktree worktrees go through llm-wt (hooks, parent integration, guidance)
priority: P1
status: in-progress
created: 2026-10-02_18:25
updated: 2026-10-02_18:25
depends-on: []
tags: [worktree, claude-plugin, hooks, concurrency]
spec: ../specs/claude-subagent-worktrees.md
model: inline
owner: homelab-zrh-dev-2409537
commits: []
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
- [ ] `WorktreeCreate` → `.worktrees/.claude/<name>` on `lazy/<name>` from the parent's HEAD, with kind/name/session/pane/base/primary config, bootstrap, stdout = path only (§4)
- [ ] Nested parent (in a pane worktree) → base/primary = the pane worktree, dir under the main repo (§4.2–4.3)
- [ ] Repo lock: 8 parallel creates all succeed with full config (§9)
- [ ] `SubagentStop` removes an empty agent worktree, keeps any with work, ignores non-isolated agents (§5.2)
- [ ] `WorktreeRemove` refuses to lose work, removes clean ones (§5.1)
- [ ] Guidance: SubagentStart (§7.1), PostToolUse Agent (§7.2), PostToolUse EnterWorktree + SessionStart from git config (§7.3); llm-claude-hook no longer emits it
- [ ] `llm-wt integrate --remove`, `llm-wt list` (§6); `.worktreeinclude` honored (§4)
- [ ] Plugin shim with fallback (§8); hooks.json wired; version 0.4.0
- [ ] Scenario 24 passes, covering every §12.1 case; 22/19/12 still pass
- [ ] Scenario 25 passes live (§12.2)
- [ ] README + USAGE updated (incl. §11 limits)
- [ ] Deployed: install.sh run, plugin 0.4.0 active for new sessions; lazy-llm pushed; dev-env submodule pointer bumped and pushed
