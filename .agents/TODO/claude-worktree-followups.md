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
commits: [414f605, 349b031, d967855, d13b13c, 3554b9c, 5137aaa, 7f28302, 2d825a1, 28bc04b, b7b8b1b, 5141401, 31ee1a4]
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

## Verify Plan
- [ ] AC1 runner exit: full suite through `tests/test-runner.sh` → 27/27 and exit 0; a copy of the tree with a synthetic failing scenario → exit 1 alone and mixed with a passing one; opt-in 25 skipped → exit 0; no-match pattern → 1. Read the `d13b13c` trap changes.
- [ ] AC2 install.sh: extract `update_lazy_llm_project_installs`, run it under `set -e` with a stub `claude` and a sandbox HOME (jq and python3 paths, spaces, duplicates, missing dir, failing update, malformed JSON, missing file, `CLAUDE_CONFIG_DIR`, wrong types, local and user scopes ignored). Check `claude plugin update --scope` in the 2.1.288 bundle.
- [ ] AC3 Saved tab: read the 4 `if` conversions and check for other `&&`-terminated arms in `dispatch_action`; run scenario 27; run 27 against the pre-`3554b9c` dashboard (claim: 9 failures).
- [ ] AC4 pane server: read `claude_create`, the lib (owners, emit_row, gather, git_segment), the border and the nvim picker for mismatch and legacy handling; reproduce a real tmux server restart (not a forged start time) in a sandbox; check the tmux calls per border refresh; run 24 and 26, and 26 against the pre-`2d825a1` consumers.
- [ ] `414f605` wait: time PostToolUse for non-isolated, isolated with no worktree, and two repos scanned; work out from the 2.1.288 bundle which payloads can reach the 25 s path.
- [ ] `414f605` scan order: two repos that both have `agent-<id>`, a stale name in the cwd repo, cwd a subdirectory.
- [ ] `414f605` log mode: stdout bytes and exit codes with the log on and off for WorktreeCreate (ok, fail), WorktreeRemove (fail), PostToolUse and SessionStart; a log that can't be written; whether the test scenarios sandbox the log path.
- [ ] `349b031`/`b7b8b1b`: read the slimmer guidance (path still in intro and land command, exit codes kept) and audit Test 4's isolation (tmux server, HOME and XDG for helpers, what the real claude can reach).
- [ ] AC5 spec §11: spot-check the sweep claims against the 2.1.288 bundle.
- [ ] Static: shellcheck on the changed scripts, before and after.
- [ ] Claim audit: 27/27, the old-code failure counts, the unchecked "Deployed" AC, unfiled follow-ups.

## Verify Report

**Date:** 2026-10-03. Verifier: fresh agent. Every run was in /tmp sandboxes (`/tmp/lzv.*`), with `TMUX`, `TMUX_PANE` and `TMUX_SOCKET` unset, a private `TMUX_TMPDIR`, `GIT_CEILING_DIRECTORIES=/tmp` and a sandbox `XDG_STATE_HOME`. No install.sh, no real `claude`, and the repo was left untouched (`git status` clean, stash intact). Live scenario 25 was not rerun: no diff gave a concrete reason, and the real hook log shows the in-pane runs of 04:09 and 04:11.

- [x] **AC1 runner exit.** Full suite: 27 TEST PASSED, `RUNNER_EXIT=0`, with 25 printing "skipped: set LAZY_LLM_LIVE_CLAUDE=1". In a tarred copy of the tree: synthetic pass → 0, synthetic fail (`exit 1`) → 1, both → 1, `25-claude` → 0, no-match pattern → 1. The trap now uses `if` blocks plus `|| true`, which is correct under `set -e`. PASS.
- [x] **AC2 install.sh.** With jq and with python3 only, the function does the right thing. `p one` (with a space) and `p2` are updated once each (the duplicate is dropped). The missing dir is "Skipped". The failing stub prints a warning. Empty, user, local and non-object entries are ignored. Malformed JSON prints the warning and returns rc 0. A missing file and wrong types are silent with rc 0, and `CLAUDE_CONFIG_DIR` is honored. Every stub call was `cd <path> && plugin update lazy-llm@lazy-llm --scope project`. The bundle has `update <plugin>` with `-s, --scope <scope>`, and project records are matched on the exact `projectPath`, which fits running it from inside each path. Not checked: whether a real `claude` run from a pane-worktree path updates that record (that needs the real CLI). Note: `scope: "local"` installs are left behind the same way; outside this AC. PASS.
- [x] **AC3 Saved tab.** All four arms (saved-close/kill, forget-snap, saved-switch, saved-forget) are `if`s now. No other `dispatch_action` arm ends on a `&&` test. Scenario 27: 32/32. Against the pre-`3554b9c` dashboard it fails 9: no and Esc for each of the 3 forget prompts, c and K on a stopped row, and Enter's clean exit. The claim holds. PASS.
- [x] **AC4 pane server.** The server is asked only when `TMUX_PANE` and `TMUX` are both set, and it's written in the rollback-covered loop.
  - Real restart in a sandbox: server A records `%0`/1791025264 and owns it. Server B (new `%0`, start 1791025265) gives owners `[]`, segment `main 48aceaf local` (no ⎇) and gather `claude:orphaned`. Legacy (key unset) → owned by `%0`: the old behavior, by design.
  - Mismatch is handled in all four consumers. Lib owners skip when `server != now`. emit_row's awk needs `s == "" || $4 == s`. The border passes `#{start_time}` from its existing `display-message`. nvim trims the tmux output, and a failed query gives `now=""`, which excludes the worktree (fail-closed).
  - Cost: zero extra tmux calls when the start time is passed (the border's case), one otherwise (scenario 26 shim count). Border average is 27 ms per run in the sandbox.
  - Scenarios: 24 193/193, 26 55/55, 14 66/66, 22 129/129. Against the pre-`2d825a1` consumers, 26 fails 10 (with today's llm-wt; the claimed 11 likely counts the old llm-wt's setup line too). PASS.
- [x] **`414f605` wait.** Timings for PostToolUse, where each wait ends in no output:
  - Non-isolated async: 1.08 s. Non-isolated sync `completed` with an `agentId`: 1.09 s.
  - Isolated, no worktree to find: 26.26 s. With `CLAUDE_PROJECT_DIR` set to a second repo holding 40 names: 26.50 s, which leaves 3.5 s under the 30 s hook timeout.
  - What can reach the long wait in 2.1.288: a sync `completed` result always carries `worktreePath` for hook-made worktrees, because the bundle's `W&&(E===void 0||S===void 0)` keeps them. So the 25 s path is reached only by background launches whose worktree has no `lazyLlmName`, i.e. the shim's fallback after llm-wt's WorktreeCreate failed.
  - Answer: a non-isolated launch is never blocked long (about 1 s). It pays that on every non-isolated Agent call, foreground ones included, because the loop isn't gated on `status == async_launched`. Recommendation, not a failure: gate the wait on `async_launched`.
- [x] **`414f605` scan order.** When both repos have `agent-dup`, cwd=A returns A's worktree, which is right because WorktreeCreate also uses the payload cwd. A stale `lazyLlmName` in A with no worktree falls through to S's real one. A cwd in a subdirectory of A returns A's. Agent ids are random, so a real collision between repos isn't expected. PASS.
- [ ] **`414f605` log mode: FAIL (2 items, below).** With a writable log, stdout is byte-identical (md5 equal on PostToolUse) and the trailing newline is kept. Exit codes match: WorktreeCreate 0/1, WorktreeRemove 1, others 0, and stderr is still passed through. Scenarios 14, 22, 24, 26 and 27 also pass in log mode.
- [x] **`349b031`/`b7b8b1b` guidance and Test 4.** The guidance names `{{path}}` in the intro and the land command and keeps exit codes 3–7 and the drop command. The real log shows PostToolUse output fell from 2686 to about 1600 bytes (about 40%, roughly "half").
  - Test 4 isolation:
    - The tmux server is private: `tmx` runs `env -u TMUX -u TMUX_PANE TMUX_TMPDIR=$TM`, and the trap kills it the same way.
    - The helpers run under `benv`, with a sandbox HOME, `XDG_CACHE_HOME`, `XDG_STATE_HOME` and `TMUX_TMPDIR`.
    - The real claude runs with `--setting-sources project,local` and the installed plugin off, so no `llm-claude-hook` writes to the real `~/.cache/lazy-llm/status/%0`.
    - `llm-wt list` is read-only.
  - Leak: the real claude's hooks inherit the real `XDG_STATE_HOME` and append to the user's opt-in log (item F2). Otherwise sandboxed. PASS apart from F2.
- [x] **AC5 spec §11.** Checked in the 2.1.288 bundle:
  - `QHr` reads `qg(root)` = `<root>/.claude/worktrees`.
  - It filters by `sso`: `agent-a<hex16>`, `agent-a<hex7>`, `wf_…`, `wf-N`, `bridge-…`, `job-…`, `bg-…`.
  - It needs an mtime older than the cutoff, and `KCt` needs a clean status and no unpushed commits.
  - It removes through `d7(H, gFe(B), n, !1, "stale_cleanup")`: the 4th argument (hookBased) is false, so it's git directly, never WorktreeRemove. `gFe` = `worktree-<name>`.
  
  The claims hold. PASS.
- [x] **Static.** shellcheck `-S warning` counts are the same before and after for llm-wt (0), llm-pane-border (0), the lib (2), llm-dashboard (1), install.sh (1) and test-runner (3): no new warnings. PASS.
- [x] **Claim audit.** 27/27 with exit 0: reproduced. The 9 failures for item 3: reproduced. Item 4: 10 reproduced (consumers only). The unchecked "Deployed (install.sh), pushed, dev-env pointer bumped" AC is honestly open: main is 15 ahead of origin, and dev-env shows `M external/lazy-llm`. No unfiled follow-ups in the report.

### Failures

**F1. A log that can't be written turns every hook into a failure, and orphans a WorktreeCreate worktree.** (`414f605`, `llm-wt` `cmd_claude_hook` ~l.792–795, under `set -euo pipefail`.) When `claude-hook.log` exists but can't be appended to (read-only, a full disk, a root-owned file), `printf ... >> "$log"` fails, `set -e` exits before `printf '%s\n' "$out"`, stdout is lost and the exit status is 1. For WorktreeCreate the llm-wt worktree has already been made, but the shim sees rc 1, falls back and makes a second, plain worktree. The first one is orphaned. A debugging aid shouldn't be able to change the hook's result: guard the log writes (`|| true`, or `2>/dev/null` on the tee/printf).
Repro:
```
SB=$(mktemp -d /tmp/lzv.XXXX); export HOME=$SB/home GIT_CEILING_DIRECTORIES=/tmp TMUX_TMPDIR=$SB/t XDG_STATE_HOME=$SB/st
unset TMUX TMUX_PANE; mkdir -p $HOME $XDG_STATE_HOME/lazy-llm; : > $XDG_STATE_HOME/lazy-llm/claude-hook.log; chmod 0444 $XDG_STATE_HOME/lazy-llm/claude-hook.log
git init -q $SB/r; git -C $SB/r -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
printf '{"session_id":"s","cwd":"%s","hook_event_name":"WorktreeCreate","name":"agent-ro1"}' $SB/r | ~/Projects/dev-env/external/lazy-llm/llm-wt-bin/.local/bin/llm-wt claude-hook; echo rc=$?
```
Observed: `Permission denied` from tee and from line 794, empty stdout, `rc=1`, and `$SB/r/.worktrees/.claude/agent-ro1` exists anyway. Expected: the path on stdout and rc 0 (the same as with no log file).

**F2. Test scenarios write into the user's real opt-in hook log.** (`414f605` added the log at `${XDG_STATE_HOME:-$HOME/.local/state}`. Scenario 24 unsets `XDG_STATE_HOME`, but 14, 22 and 26 only sandbox HOME, and the runner keeps the user's `XDG_STATE_HOME`.) The log is enabled on this machine, so every suite run appends test payloads to `~/.local/state/lazy-llm/claude-hook.log`, and those scenarios run in log mode. The real log already holds 93 `/tmp/lazy-llm-test-claudeui-*` entries (26), 30 `wbtclaude` (14) and `wtpane` (22). The live scenario 25, Test 4 included, adds more through the real claude's inherited `XDG_STATE_HOME`. The writes are append-only and don't destroy anything, but they break the "never touch the user's state" rule the suite follows elsewhere (`LAZY_LLM_STATE_DIR`, TMUX).
Repro (writes only to a sandbox):
```
SB=$(mktemp -d /tmp/lzv.XXXX); mkdir -p $SB/xs/lazy-llm; : > $SB/xs/lazy-llm/claude-hook.log
cd ~/Projects/dev-env/external/lazy-llm && env -u TMUX -u TMUX_PANE XDG_STATE_HOME=$SB/xs bash tests/test-runner.sh 26-
grep -c '^===' $SB/xs/lazy-llm/claude-hook.log
```
Observed: 8 blocks after 26 alone (14 → 5, 22 → 2, 24 → 0). Expected: 0. Fix: unset or sandbox `XDG_STATE_HOME` in the runner (or in 14, 22 and 26), and point 25's claude runs at a sandbox `XDG_STATE_HOME`.

### Observations (not failures)
- The PostToolUse wait isn't gated on `status == async_launched`. Every non-isolated Agent call, foreground included, pays about 1.1 s. An isolated background launch in the shim-fallback case waits about 26.5 s, 3.5 s short of the hook's 30 s timeout. If a later Claude starts removing clean hook-made worktrees itself (dropping `worktreePath` from sync results), every such call would wait 26 s. Gating on `async_launched` removes all three.
- install.sh updates only `scope: "project"`, not `scope: "local"` installs.

VERDICT: fail (2 items)

## Rework (round 1)

**Date:** 2026-10-03_13:16

Both verifier failures, plus its suggestion, fixed in `31ee1a4`:
- F1, unwritable log → hooks failed: logging is skipped unless the log is writable, and a
  failed write is ignored. Test 23d makes the log read-only and checks the path and rc 0.
- F2, scenarios wrote to the user's log: `tests/test-runner.sh` exports `XDG_STATE_HOME`
  inside the run's workroot. Checked: a full run left the real log at 307 → 307 entries.
- Suggestion taken: a finished (foreground) launch without a worktreePath returns at once.
  Test 23d asserts under 800 ms.
Scenario 24: 198/198; the old llm-wt fails exactly the 2 new assertions. Full suite **27/27,
runner exit 0**. Not sent for another verify round: both deterministic, each with a test that
fails on the old code. The opt-in log was then switched off (file removed): `touch
~/.local/state/lazy-llm/claude-hook.log` re-enables it.
