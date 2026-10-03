---
slug: claude-worktree-followups
title: Follow-up pass after Claude's subagent worktrees — runner exit status, project-scope plugin update, Saved tab "no", pane-id reuse, cleanup sweep, full e2e
priority: P1
status: in-progress
created: 2026-10-03_03:49
updated: 2026-10-03_03:49
depends-on: [claude-subagent-worktrees, claude-subagent-worktrees-ui]
tags: [worktree, claude-plugin, dashboard, tests]
owner: homelab-zrh-dev-3446176
model: inline
commits: [414f605, 349b031, d967855, d13b13c, 3554b9c, 5137aaa, 7f28302, 2d825a1, 28bc04b, b7b8b1b, 5141401]
---

# Follow-up pass: Claude's subagent worktrees

## Context
The user asked (2026-10-03) for the follow-ups filed after `claude-subagent-worktrees` and
`claude-subagent-worktrees-ui` to be one pass, not five tasks, done now with a complete
end-to-end run of the feature. This replaces the backlog tasks `test-runner-exit-status`,
`install-updates-project-scope-plugins`, `saved-tab-close-on-no`,
`claude-worktree-pane-id-reuse` and `claude-worktree-cleanup-sweep` (deleted, never started).
Specs: `specs/claude-subagent-worktrees.md`. Fixes are dispatched to isolated subagents from a
real lazy-llm pane and landed with `llm-wt integrate --remove`, which exercises the feature.

## Items
1. **Runner exit status.** `tests/test-runner.sh` exits 1 even when every scenario passes. It
   should exit 0 when everything passes, non-zero otherwise, and a skipped opt-in scenario
   shouldn't count as a failure.
2. **Project-scope plugin installs.** `install.sh` runs `claude plugin update` for one
   (auto-detected) scope. dev-env enables the plugin in its checked-in `.claude/settings.json`,
   so Claude recorded project-scope installs (0.3.0) that install.sh left behind. Update every
   project-scope lazy-llm install whose project path exists, and say which.
3. **Saved tab "no" closes the dashboard.** Declining or escaping the Saved tab's forget and
   switch prompts falls through to quitting. The Worktrees-tab version was fixed in `1feb369`.
4. **Pane-id reuse.** A Claude worktree records `lazyLlmPane=%N`. tmux reuses pane ids with a new
   server, so a leftover worktree can look owned by an unrelated pane (Worktrees tab owner,
   border ⎇×N, llmw picker). Record the tmux server's identity at creation and only honor the
   pane when it matches.
5. **Claude's cleanup sweep.** Find out whether Claude Code's periodic worktree cleanup
   (`cleanupPeriodDays`) can touch `.worktrees/.claude/`, and how (git directly, or
   WorktreeRemove). Fix it if it can delete work; otherwise record the finding in spec §11.
6. **Full e2e.** The whole suite, plus a live test of the full lazy-llm integration: a real
   Claude session in a (sandbox) tmux pane fans out isolated subagents, and while they run the
   border ⎇×N, the Worktrees tab owner and `llm-wt list` reflect them. Afterwards everything has
   landed and nothing is left.

## Acceptance Criteria
- [x] 1. Runner exit status correct (all pass → 0; a failure → non-zero; opt-in skip → pass)
- [x] 2. install.sh updates existing project-scope installs
- [x] 3. Saved tab: no/Esc returns to the dashboard; covered by a scenario
- [x] 4. Pane ownership requires the same tmux server; covered by tests
- [x] 5. Cleanup sweep finding recorded (and fixed if needed)
- [x] 6. Full suite green; live scenarios green, including the in-pane e2e
- [ ] Deployed (install.sh), pushed, dev-env pointer bumped

## Work Report

**Date:** 2026-10-03_04:09

### How it was done: dogfooding the feature
This session ran in a real lazy-llm pane (`dev-env`, `%15`) with plugin 0.4.0. Four probes,
then items 1–4 were dispatched in one message to four `isolation: "worktree"` subagents, with
item 5 to a read-only research agent. Each fix landed with `llm-wt integrate --remove` (all
fast-forwards after rebase). `llm-wt list` is empty after the last one.

### Found by dogfooding (not on the list), fixed first: `414f605`
- **Background launches: the parent was never told.** In this harness every `Agent` launch is
  async. The agentId lookup scanned `CLAUDE_PROJECT_DIR` (dev-env) before the session's cwd
  (the lazy-llm submodule), so it found nothing. The headless tests had cwd = project dir. It
  now scans cwd's repo first, and waits up to 25 s for the worktree when the call asked for
  isolation, because the launch's PostToolUse can fire mid-WorktreeCreate. Confirmed live:
  probes 1–3 got no guidance, probe 4 and the four fix agents got it at launch.
- An opt-in payload log: `touch ~/.local/state/lazy-llm/claude-hook.log`.
- Guidance volume, a REVIEW-QUEUE question answered by evidence: four launches put about 8 KB in
  the parent's context. `worktree-parent.md` now names the path twice, not ~10 times: `349b031`.

### Items
1. Runner exit status: `d13b13c`. Root cause: the EXIT trap's
   `[ -n "$tree" ] && kill -9 $tree` under `set -e`; the pids are normally gone, so the trap
   exited 1 over main's `exit 0`. Verified: a passing run gives 0, a failing scenario gives 1, a
   mixed run gives 1, and the opt-in skip counts as passed.
2. install.sh project scopes: `d967855`. `update_lazy_llm_project_installs` reads
   `installed_plugins.json` (jq, else python3) and updates each existing project path with
   `--scope project`, skipping missing ones, and never fails the install. Tested with a stub
   `claude` and a sandbox HOME (paths with spaces, duplicates, failures, malformed JSON).
3. Saved tab "no": `3554b9c` and `5137aaa`. Four `cond && action` arms are now `if`s: forget,
   manual-save forget, close/kill on a stopped workspace, switch. There is no switch prompt;
   Enter on a live row switches and closes by design. New scenario 27 (32 assertions; the old
   code fails 9).
4. Pane-id reuse: `7f28302`, `2d825a1` and `28bc04b`. `lazyLlmPaneServer` (the server's
   `#{start_time}`) is recorded at creation, asked only through the hook's `$TMUX`, and
   honored by the Worktrees owner, border ⎇×N, dashboard tree and llmw picker. Legacy
   worktrees without it are trusted. Scenario 26 Test 5; the old code fails 11 + 1 assertions.
5. Cleanup sweep: no code change needed. Findings are in spec §11 (`d6fdcb0`): the 2.1.288
   sweep only enumerates `.claude/worktrees/` with Claude's own name patterns, only removes
   clean worktrees with nothing unpushed, and goes through git directly, never WorktreeRemove.
   It can't touch `.worktrees/.claude/`.
6. Full e2e: `349b031` adds scenario 25 Test 4. A real Claude session in a sandbox tmux pane
   set up as a lazy-llm workspace fans out two pausing subagents; the test samples
   `llm-wt list`, the real `llm-pane-border` and the Worktrees owner mid-run. Helpers run with a
   sandbox HOME, because the per-pane caches are keyed by pane id. Results below.

### Test results
- Full suite: **27/27, runner exit 0** (`5141401`). An earlier full run caught scenario 26
  failing after the `$TMUX` guard (`28bc04b`): its helper set `TMUX_PANE` alone. Fixed in
  scenarios 14 and 26.
- Live scenario 25: **40/40, exit 0**, including Test 4 in a sandbox lazy-llm pane:
  `llm-wt list` showed 2 waiting, the real `llm-pane-border` showed `⎇×2` mid-run, the owner
  was `claude:e2e:%0`, both commits landed, and the list, border and worktrees were empty
  afterwards. The first run caught a test bug (`b7b8b1b`): llm-pane-border needs
  lazy-llm-lib.sh alongside, as stowed.
- Each agent fix was shown failing on the old code (item 1: rc 1 before; item 3: 9 failures;
  item 4: 11 + 1 failures). Item 2 was checked with a stub `claude`.
