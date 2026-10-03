---
slug: claude-worktree-followups
title: Follow-up pass after Claude's subagent worktrees — runner exit status, project-scope plugin update, Saved tab "no", pane-id reuse, cleanup sweep, full e2e
priority: P1
status: done
created: 2026-10-03_03:49
updated: 2026-10-03_22:27
depends-on: [claude-subagent-worktrees, claude-subagent-worktrees-ui]
tags: [worktree, claude-plugin, dashboard, tests]
model: inline
commits: [414f605, 349b031, d967855, d13b13c, 3554b9c, 5137aaa, 7f28302, 2d825a1, 28bc04b, b7b8b1b, 5141401, 31ee1a4, 232931f, 17d67ee, 132b211, 85b8d9c, 452a38c, e0f4631, 2448d48, 3b9af01, 4441892, 715f74e, 65db253, a1c23a9, b9a2ff2]
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
- [x] Deployed (install.sh), pushed, dev-env pointer bumped

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

## Deploy

**Date:** 2026-10-03_13:16

- lazy-llm `main` pushed (gitleaks clean). The plugin itself is unchanged (0.4.0); the bins and
  the nvim plugin are live through stow (nvim needs a restart for the picker change).
- The real `./install.sh` exercised item 2: "Updated project-scope install in …/dev-env", and
  "Skipped" for the four entries whose pane worktrees no longer exist.
- dev-env submodule pointer bumped and pushed.
- Human validation: not added. The feature was exercised for real in this session's lazy-llm
  pane (four probes, four isolated fix agents landed with `llm-wt integrate --remove`) and in
  scenario 25 Test 4. The two REVIEW-QUEUE items from the earlier tasks remain for the user's
  own look.

## Reopened: persistence (2026-10-03, user: "is it all working properly with lazy-llm's session persistence features?")

Spike facts (live, headless `claude -p` in a sandbox, Claude Code 2.1.288):
- P1. `claude --resume <id>` keeps the session id; SessionStart says `source: "resume"`.
- P2. During an EnterWorktree session the **pane's cwd stays the main directory** (Claude tracks
  the worktree internally), so `llm-persist save` records the right cwd. `claude --resume`
  from the main directory **re-enters the worktree itself** (its Bash `pwd` was the worktree).
- P3. The resumed session's SessionStart `cwd` is the main directory, so the worktree rules
  weren't re-injected on resume or compaction.

Gaps and fixes:
- After `lazy-llm restore` (a new server, new pane ids), a session's subagent worktrees showed
  as orphaned, and the resumed session wasn't reminded of them. An EnterWorktree session lost
  its rules at the next resume or compact. Fixed in `232931f`: SessionStart finds the session's
  worktrees by `lazyLlmSession`, re-stamps `lazyLlmPane`/`lazyLlmPaneServer` (so the border,
  Worktrees tab and picker re-attach), re-injects worktree-agent.md for an entered worktree, and
  lists subagent worktrees still waiting to land. Scenario 24 Test 11b (the old code fails 8).
- Scenario 28 (`85b8d9c`, written by an isolated subagent, dogfooding again): a real
  `llm-persist save` → server killed → `lazy-llm restore` with a mock tool. Covers re-owning on
  resume (the old llm-wt fails exactly the 9 re-owning checks), a pane adopted into a Claude
  worktree restored into it (with `LAZY_LLM_WORKTREE=1`, and recreated from its branch when
  deleted), and nothing leaking. 45/45. No product bug found.
- Live Test 5 (`17d67ee`, `132b211`): resumes the real session that left an unlanded subagent
  commit, and checks the reminder reached the model as SessionStart `hook_additional_context`.
  A real `lazy-llm restore` with live Claude wasn't automated: restored panes run the user's
  installed status hooks, whose per-pane caches (under the real HOME, keyed by pane id) would
  collide with the user's own `%0` (backlog `per-pane-cache-cross-server`). The deterministic
  scenario 28 plus live Test 5 cover the same path.
- Runner: several patterns now run their union (`452a38c`); before, only the last ran silently.

## Verify Report (persistence)

**Date:** 2026-10-03 · verifier, fresh context · commits `232931f` `85b8d9c` `17d67ee` `132b211` `452a38c`

All probes ran under `/tmp/lzv.*` with `TMUX`/`TMUX_PANE` unset, a private `TMUX_TMPDIR`, a sandbox
`HOME`, and `GIT_CEILING_DIRECTORIES=/tmp`. Real `claude` was never run.

### Checks that passed
- [x] **Suite:** `tests/test-runner.sh 20 22 24 26 28` (sandbox HOME) ran all 5 scenarios, each
  once: 20 117/117, 22 129/129, 24 212/212, 26 55/55, 28 45/45, runner exit 0. This also shows
  that `452a38c` runs the union of several patterns.
- [x] **Claims that the tests fail on the old code:** I ran a `git archive HEAD` copy with
  `232931f^`'s llm-wt. Scenario 24 fails exactly the 8 Test 11b checks, and scenario 28 fails
  exactly the 9 re-owning checks (border, owner, re-stamp, additionalContext). Both claims hold.
- [x] **shellcheck:** `llm-wt` is clean. The test files only have the warnings every scenario
  already has (TEST_NAME, SC1091).
- [x] **SessionStart exit status and JSON:** `cmd_claude_hook` maps SessionStart to rc 0 whatever
  the child does. This includes `die` from `lock_repo` (`llm-wt:881-887`). Nothing reaches stdout
  except the final `emit_context`. A non-git cwd, a missing session_id, a truncated payload and an
  empty payload all gave rc 0 with no output. Repo paths containing `"` and `\` gave valid JSON.
- [x] **Lock:** each re-stamp sits in `lock_repo "$path"`/`unlock_repo`, keyed by that worktree's
  common dir, so a worktree in another repo locks its own repo. With the lock held for 4 s by
  another process, SessionStart waited 3.7 s, then returned valid JSON with rc 0.
- [x] **Removed worktree:** if the directory was deleted with `rm -rf` (not pruned), or removed
  with `git worktree remove`, it is skipped silently (`-d "$path"`, empty `%(worktreepath)`).
- [x] **Cost:** on a SessionStart(startup) with nothing of this session, the new code adds two
  `git config --get-regexp` calls. The repo is scanned twice when CLAUDE_PROJECT_DIR is cwd's repo.
  Measured over 20 runs: non-git cwd 19→23 ms, and a repo with 400 lazyLlmSession entries
  27→40 ms. Acceptable.
- [x] **No bad matches:** sessions are matched on exact equality, and the kind must be `claude`.
  `for-each-ref refs/heads/lazy/<b>` prefix matching can't catch a second branch, because git
  forbids `lazy/x` and `lazy/x/y` existing together. Session ids colliding across repos isn't a
  realistic risk (UUIDs, and only two repos are scanned).
- [x] **Scenario 28's sandbox:** it uses its own server (`TMUX_TMPDIR=$SB`, `env -u TMUX`), its
  own HOME (bins symlinked as stow lays them out), its own `LAZY_LLM_STATE_DIR`, and a fake claude.
  It does a real `llm-persist save` → `kill-server` → `llm-persist restore`. The restored pane
  reuses `%0` with a different start time, which is the case that matters. One limit: the
  SessionStart(resume) is a synthesized payload, not one fired by a resumed claude. That rests on
  spike fact P1 and on live Test 5 (the section says so).
- [x] **Live Test 5 assertion (judged from the code):** the assertion is sound. It counts only
  transcript attachments with `type == hook_additional_context` and `hookEvent == SessionStart`.
  I checked real transcripts on this machine: the field is `.attachment.hookEvent`, and SessionStart
  records carry it. The text it counts is emitted only by `hook_session_start`. The startup
  SessionStart in `$R3` injects nothing, so a count of 1 means it came from the resume. It can't
  pass wrongly. It could fail wrongly in two ways:
  - if Claude doesn't write SessionStart(resume) context as a `hook_additional_context`
    attachment;
  - through `assert_dir_exists "$kwt"`. The reminder says "Land each with `llm-wt integrate
    --remove`". A `--dangerously-skip-permissions` model that obeys it would remove the worktree.
    So that check depends on the model's behaviour, which the file header says the scenario never
    does.

### Failures

**F1. Re-stamping takes ownership away from a live pane.** It happens whenever a second pane
resumes the same conversation, and lazy-llm does exactly that itself: `restore --snapshot` of a
running workspace makes a copy that resumes the same conversation ids (`restore_snapshot_entry`
leaves `conv` alone). `hook_session_start` re-stamps without checking that the current owner is
dead. `llm-claude-hook` has a guard against nested claude runs (`spawned_by_nested_claude`);
llm-wt has none. So `claude -p -c` or `claude --resume <id>` run from another pane also takes
ownership. `232931f` introduced this; before it, ownership was fixed when the worktree was made.
Repro, using the scenario-28 sandbox helpers (`sbx`, `wopt`, `hook_from`, `p_create`, `p_resume`,
`border`):
```
sbx lazy-llm -s wsC -d "$C" -t claude; P=$(wopt wsC @AI_PANE_ID)
printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"S1"}' | sbx env TMUX_PANE="$P" llm-claude-hook
p_create S1 "$C" agent-c1 | hook_from "$P"                     # border(P): ⎇×1
sbx llm-persist save                                           # manual save → snapshot
sbx llm-persist restore --snapshot "<ts>/<id>"                 # "as wsC-2 (a copy: wsC is running)"
P2=$(wopt wsC-2 @AI_PANE_ID)                                    # launched: claude --resume S1
p_resume S1 "$C" | hook_from "$P2"
```
- Observed: `lazyLlmPane=%3` (the copy). The original's border has no ⎇×1. After `kill-session
  -t wsC-2` the owner is still `%3`, so the live original stays without its ⎇ until its next
  compact or resume.
- Expected: a pane that is still alive keeps its worktrees. Re-stamp only when the recorded
  pane/server is dead, or when the owner is already this pane.

**F2. A Claude worktree in the middle of a rebase is neither re-owned nor mentioned in the
reminder.** `llm-wt integrate` leaves a worktree in this state on a conflict (exit 5).
`session_worktrees` (`llm-wt:541-563`) gets the path from `%(worktreepath)`, which is empty while
HEAD is detached for the rebase. llm-wt already has `wt_branch()`, written for exactly this case.
Repro, in the probe helpers' sandbox:
```
W=$(p_create S "$R" agent-x | hook "$P1")                      # R on branch feature
echo a > "$R/c.txt"; git -C "$R" add c.txt; git -C "$R" commit -qm base-c
echo b > "$W/c.txt"; git -C "$W" add c.txt; git -C "$W" commit -qm sub-c
git -C "$W" rebase feature                                     # conflict → rebase in progress
git -C "$R" for-each-ref --format='%(refname:short) [%(worktreepath)]' refs/heads/lazy/   # "lazy/agent-x []"
git -C "$R" config branch.lazy/agent-x.lazyLlmPane %99         # stand-in for a dead owner
p_sess S "$R" resume | hook "$P3"
```
- Observed: `lazyLlmPane` stays `%99`, and the hook prints no output.
- Expected: re-stamped to `$P3`, and listed in the reminder. This is the worktree that most needs
  the reminder after a restore.
- Also, `llm-wt list "$R"` says "no Claude worktrees integrate into …" in this state.

**F3. The superproject/submodule layout, which is this user's own setup, is never re-owned.** This
session was launched in dev-env and works in the lazy-llm submodule. The Work Report (`414f605`)
observed that WorktreeCreate's cwd is the submodule there. The worktrees therefore live in the
submodule's repo. On resume, SessionStart's cwd is the launch directory (spike fact P3), and
CLAUDE_PROJECT_DIR is the superproject. `session_worktrees` scans only those two, so it scans the
superproject twice and never reaches the submodule. Repro (real `git submodule add`):
```
W=$(p_create S "$SUPER/ext/lib" agent-s | CLAUDE_PROJECT_DIR="$SUPER" hook "$P1")
T kill-server; sleep 1.2; T -f /dev/null new-session -d -s b "exec sleep 300"; P2=...
p_sess S "$SUPER" resume | CLAUDE_PROJECT_DIR="$SUPER" hook "$P2"
```
- Observed: no output, and the stamp is unchanged (old server).
- Control: the same payload with cwd = the submodule gives the reminder.
- Premise: the resumed SessionStart cwd is the launch directory, as P3 found for EnterWorktree. A
  live resume of a submodule session would confirm it.
- A possible fix: find the session's worktrees with something that doesn't depend on the cwd at
  resume, for example a per-session index written at WorktreeCreate.

### Persistence gaps worth fixing (not failures of the section's claims)
- **G1. /clear.** `/clear` starts a new session id. `llm-claude-hook` records it as the pane's
  conversation, so the next save stores that id. After a later restore, `claude --resume <new id>`
  never re-owns the worktrees made before the `/clear`: they stay orphaned for good. The new
  conversation is never reminded of them either (SessionStart(clear) prints nothing). Repro:
  `p_sess S2 "$R" clear | hook "$P1"` gives no output. Then kill the server, start a new one and
  run `p_sess S2 "$R" resume | hook "$P3"`: agent-x keeps the old server's start time.
- **G2. A background subagent running at save time** is killed by the restore. Its worktree can
  hold uncommitted work and 0 commits. The reminder lists it as "0 commit(s) beyond `feature`" and
  offers `llm-wt remove --force`, which drops uncommitted work without asking. It never mentions
  dirty or untracked files. A compact while a background subagent is still running also lists that
  worktree as "waiting to land". Repro: `echo wip > "$W/wip.txt"`, then
  `p_sess S "$R" resume | hook "$P"`.
- **G3. `llm-persist` mid-rebase:** `pane_worktree_json` uses `git branch --show-current`, which
  saves `"branch": null` during a rebase. On restore, `branch..lazyLlmBase` is empty, so an
  adopted pane (`llm-add -w`) or an isolated pane comes back with `@lazy_llm_wt` but **without**
  `LAZY_LLM_WORKTREE`/`BASE`/`PRIMARY`. Observed launch: `claude --resume Sd PWD=<wt> WT= BASE=`.
  This predates these commits; `wt_branch()` would fix it.
- **G4. `claude -w` panes.** If Claude chdirs into the `-w` worktree (P2 covered EnterWorktree
  only, so this is unverified), `pane_current_path` is the worktree. The manifest then saves
  `cwd=<wt>` with `worktree: null`.
  - While the worktree exists, restore is `cd '<wt>' && claude --resume 'Sw'`, which is fine.
  - Once it has been landed and removed, restore is a bare `claude --resume 'Sw'` from the
    workspace dir. The transcript may be filed under the worktree's project dir, so Claude may not
    find the conversation.
  - The worktree is not recreated from its branch, unlike `llm-add -w` panes.
  Seen with `restore --dry-run` in a sandbox.
- **G5. The guidance doubles.** Take an isolated pane whose session also entered a Claude
  worktree. Every resume and compact injects two full copies of worktree-agent.md (about 6.8 KB),
  one for each worktree, plus the list.
- **G6. "resuming puts it back there" can be wrong.** The text is used for every non-`agent-*`
  session worktree that still exists. That includes one the session left with ExitWorktree `keep`,
  and it is sent on `compact` too, not only on resume. It can tell the model it is somewhere it
  isn't.
- **G7. The Saved tab** pane rows (`pane_rows`, dashboard `saved-pane:`) show tool, name and
  conversation, but not the pane's worktree. A pane that runs in a Claude worktree, or whose
  worktree is gone, looks like any other.
- **Nits:**
  - If tmux can't answer, the re-stamp writes the new pane id but keeps the stale
    `lazyLlmPaneServer`. Observed `%7` paired with the old start time; it should clear the server
    or skip the write.
  - A repo path containing a tab gives no output.
  - `json_escape` doesn't escape control characters other than `\t`, `\n` and `\r`.
  - Re-stamps rewrite `.git/config` even when nothing changed.
  - The runner silently ignores a pattern that matches nothing when another pattern does match.

VERDICT: fail (3 items)

## Rework (persistence round 1)

**Date:** 2026-10-03_20:44

All three failures and most of the gaps from "Verify Report (persistence)":
1. **No stealing from a live pane** (`e0f4631`): re-owning happens only when the recorded owner
   is gone, or belongs to another server. Test 11c.1.
2. **Mid-rebase** (`e0f4631`): `worktrees_by_branch` resolves the branch from the rebase state
   for the resume lookup and `llm-wt list`. An isolated subagent made the persistence/display
   side (`4441892`, `715f74e`): llm-persist saves the branch mid-rebase, the Worktrees tab and
   border ⎇×N keep the worktree, and the llmw picker too (`65db253`). Tests 11c.2, scenario 26
   Test 6, scenario 28 Test 7.
3. **Submodule layout** (`e0f4631`): a session registry
   (`$XDG_STATE_HOME/lazy-llm/claude-sessions/<id>`) lists the worktrees each session made, so
   the lookup no longer depends on the resumed cwd. Confirmed live: a real session launched in
   a superproject that `cd`'d into a submodule and left a subagent commit resumed with
   cwd = the superproject, and its reminder named the submodule's worktree. This is now live
   Test 6 (`3b9af01`). Unit test 11c.3.
- **Gaps fixed:** `/clear` inheritance (a registry hand-off; the recorded session is
  unchanged); the reminder counts uncommitted and untracked work, flags a rebase, and warns
  about running or cut-off subagents and what `--force` drops; the guidance is de-duplicated;
  the wording no longer promises a re-enter on compaction; control characters are stripped
  from the JSON; config is written only when it changes; re-owning is skipped when tmux can't
  give the server; `claude -w` panes are saved with their worktree (`715f74e`); registries
  whose worktrees are all gone are pruned at `/clear`; and the runner fails on an unmatched
  pattern (`2448d48`).
- **Not done:** the Saved tab showing a pane's worktree (cosmetic); a repo path containing a
  tab (unsupported).
- Scenario 24: 231/231 (the pre-rework llm-wt fails 16). Scenarios 26: 67/67, 28: 69/69.

## Verify Report (persistence round 2)

**Date:** 2026-10-03 · verifier, fresh context · commits `e0f4631` `4441892` `715f74e` `65db253` `2448d48` `3b9af01`

All probes ran under `/tmp/lzv.*`. In every probe `TMUX`/`TMUX_PANE` were unset, and each had a private `TMUX_TMPDIR`, a sandbox `HOME`
and `XDG_STATE_HOME`, `GIT_CEILING_DIRECTORIES=/tmp`, and fake `claude`/`nvim`. The helpers in `h.sh` mirror scenario 28's
(`sbx`, `hook_from`, `p_create`, `p_sess`, `border`, `cfg`, plus `reg <sid>` to cat a registry). I didn't run scenario 25.
Afterwards the user's `~/.local/state/lazy-llm/claude-sessions` still doesn't exist, and `git status` is clean.

### The 3 original failures: fixed
- [x] **F1 (stealing from a live pane):** repro used the full flow: `lazy-llm -s wsC`, `llm-persist save`, then `restore
  --snapshot`, which gives "as wsC-2 (a copy: wsC is running)". The copy's pane `%3` was launched with `claude --resume S1` and
  then sent SessionStart(resume). Owner stays `%0`. `border(%0)` keeps ⎇×1 and the copy's border shows none. The copy still
  gets the reminder. After `kill-session wsC-2`, a compact in the original still leaves it as owner.
- [x] **F2 (mid-rebase):** a conflicted `git rebase feature` gives `lazy/agent-x []`, then `lazyLlmPane=%99`. A resume from
  P3 re-stamps the worktree to P3. The JSON is valid. The reminder names the worktree with "1 commit(s) beyond `feature`, 1
  uncommitted, 0 untracked; a rebase is in progress there". `llm-wt list` lists it, `border(P3)` shows ⎇×1 (the pane's cwd
  is the repo), and the Worktrees tab's owner is `claude:a:%1`.
- [x] **F3 (submodule):** used a real `git submodule add`. WorktreeCreate ran with cwd = the submodule and
  `CLAUDE_PROJECT_DIR=$SUPER`, and the registry lists the worktree. Then the server was killed and a new one started.
  SessionStart(resume) with cwd = `$SUPER` re-stamped the worktree to the new server (1791053380 → 1791053381) and named it
  in the reminder. The JSON is valid.

### Other checks that passed
- [x] **Suite** (`tests/test-runner.sh 14 20 22 24 26 28`, sandbox HOME/XDG_STATE_HOME): runner exit 0. Results: 14 76/76,
  20 117/117, 22 129/129, 24 231/231, 26 67/67, 28 69/69.
- [x] **Claim: "the pre-rework llm-wt fails 16".** I ran scenario 24 in a `git archive HEAD` copy with
  `e0f4631^:llm-wt` and got exactly 16 ✗ (Tests 11b and 11c).
- [x] **Runner (`2448d48`):** `test-runner.sh 24 nomatchzz` exits 1 and runs nothing.
- [x] **shellcheck:** `llm-wt` and `llm-persist` have 0 findings. `lazy-llm-lib.sh` has 7 and `test-runner.sh` has 10,
  the same as before these commits.
- [x] **Concurrent registry writes:** 24 parallel WorktreeCreates for one session gave 24 worktrees and 24 unique,
  well-formed registry lines. In 15 rounds of six `/clear`s (prune) racing a WorktreeCreate for a new session, no
  registry was lost.
- [x] **Re-owning rule:** a live owner on the same server is kept (F1). An owner whose pane was closed is re-owned (Test
  11c). A different server is re-owned (F3). An empty server (tmux can't answer) means no write. Config is written only
  when the pane or server changes.
- [x] **`worktrees_by_branch`:**
  - Bare repo (`clone --bare` plus a linked main worktree): `list`, the resume lookup without a registry (cwd = the main
    worktree or the bare dir), and mid-rebase all work. The `bare` entry is skipped.
  - Submodule: the first entry is `.git/modules/…` on `main`, which is not of kind claude, so it's harmless.
  - Rebasing a detached HEAD gives "detached HEAD" as the branch, and the config lookup rejects it.
- [x] **`/clear` hand-off:**
  - The new session's registry gets the pane's worktree.
  - A `/clear` in another pane, or outside tmux, inherits nothing.
  - After a server restart, resuming the post-`/clear` id re-owns the worktree and reminds the session.
  - `lazyLlmSession` stays the old id.
- [x] **JSON validity:** repo paths containing `"`, `\`, spaces or non-ASCII characters gave valid JSON. A path with a
  control character, or a tab, gives no output (WorktreeCreate itself can't make one there; both were already known).
- [x] **Border cost:** I counted calls with a `git` wrapper. Both normal and mid-rebase make 4 git calls
  (rev-parse, status, config, for-each-ref), and so does a branch whose worktree was removed. The claim holds.
- [x] **`pane_worktree_json`'s claude -w detection:** I moved the AI pane's cwd with `respawn-pane -c` and saved each time.
  - Saved with `worktree: null`: the workspace dir, a subdir, a submodule, a pane worktree without `@lazy_llm_wt`, and a
    symlinked path.
  - Saved with `{path, branch}`: a `claude -w` worktree, including mid-rebase.
  - An isolated pane mid-rebase is saved with branch `lazy/pw` (this was G3).
- [x] **Live Test 6 (`3b9af01`), judged from the code:** it uses the runner's XDG_STATE_HOME, so its registry is the
  sandbox's. Its assertion is about the registry path: the cwd and the project are both the superproject, so the repo
  scan can't find the worktree.

### Failures (real defects)

**D1. A stale registry entry claims another session's worktree.** A registry path that is now a worktree of kind claude
skips the session check (`session_worktrees`, `[[ "$sess" == "$sid" || "$listed" == *" $path "* ]]`). That applies to any
entry, not only one inherited at `/clear`. Entries are never removed while the registry has another live path, or until
a `/clear`. A path comes back whenever a name is reused after landing: `claude_create` only adds `-2` while the old branch
or directory exists. Repro:
```
WB=$(p_create sess-B "$R" fix-login | hook_from "$PB"); commit in WB; llm-wt integrate --remove "$WB"   # branch gone; reg sess-B still lists the path
WC=$(p_create sess-C "$R" fix-login | hook_from "$PC")                                       # same path, lazyLlmSession=sess-C
p_sess sess-B "$R" compact | hook_from "$PB"
#  -> "this session created the worktree `…/fix-login` with EnterWorktree … this applies:" plus the full worktree-agent.md
T kill-pane -t "$PC"; p_sess sess-B "$R" resume | hook_from "$PX"
#  -> lazyLlmPane=%PX (re-owned by B); C resuming later can't take it back while PX is alive
```
- Expected: the registry exemption applies only to an entry that was handed over, for the session that made it. For
  example, store `path<TAB>maker-session` and require `lazyLlmSession == maker`.
- With an `agent-*` name, the same bug would list C's work as B's "not landed" and offer B `llm-wt remove --force`.
  Subagent names are random, so that case is unlikely. A user-chosen `claude -w <name>` or EnterWorktree name is a
  realistic reuse.

**D2. The Lua picker fallback misses a mid-rebase worktree with `worktree.useRelativePaths=true`.** `rebase_branch()` in
`lazy_llm_worktree.lua` opens `gitdir .. "/rebase-merge/head-name"` as written. With relative paths, the `.git` file holds
`gitdir: ../../../.git/worktrees/agent-x`, which resolves against nvim's cwd, not the worktree. The bash side handles this
case (`lazy_llm_rebase_branch` uses `$wt/$gitdir`, and the owners scan uses `cd "$admin$p"`).
Repro: `git -C "$R" config worktree.useRelativePaths true`, create an agent worktree via the hook, start a conflicting
rebase in it, then run `M.claude_worktrees(R, P)` headless from a cwd other than the worktree.
- Observed: `0` worktrees. The border shows ⎇×1, the Worktrees tab shows `claude:a:%0`, and `llm-wt list` lists it.
- Control: after `useRelativePaths false` plus `worktree repair`, the picker returns 1.

**D3. Each `/clear` costs more than the last while worktrees stay unlanded.** Each `/clear` copies every live worktree the
pane owns into a new registry. `inherit_pane_worktrees` then walks every live path of every registry (wt_branch plus two
config reads each), and none of those registries can be pruned while one path lives.
Measured with 5 unlanded agent worktrees in one pane, SessionStart(clear) took:

| `/clear` # | Registries | Lines | Time |
|---|---|---|---|
| 1 | 2 | 10 | 250 ms |
| 10 | 11 | 55 | 541 ms |
| 20 | 21 | 105 | 863 ms |
| 40 | 41 | 205 | 1399 ms |

By comparison, a compact takes 208 ms and an unrelated startup 37 ms. There's no upper bound. Repro: `a3.sh` (40 ×
`p_sess sess-$k "$R" clear | hook_from "$P"`).

**D4. Claim audit: a follow-up was not filed.** "Not done: the Saved tab showing a pane's worktree (cosmetic)" names no task
slug, and there is none in `backlog/` or INDEX.md (this is G7 from the previous report).

### Theoretical (not counted)
- **T1.** An owner with no recorded `lazyLlmPaneServer` is taken even while its pane is alive on this server. That covers
  worktrees made before item 4, or when tmux didn't answer at creation. The display side honors such ownership (empty
  server = trust the pane). Repro: unset `lazyLlmPaneServer`, owner `%0` alive, resume from `%1` → owner `%1`. A rule like
  `[[ -z $osrv || $osrv == $server ]] && pane_alive` would keep it.
- **T2.** Pruning deletes a registry it can't read (`chmod 000` → deleted, observed). It also deletes one whose worktrees are
  only temporarily missing (an unmounted volume, a moved repo).
- **T3.** Two races, neither reproduced in 15 stress rounds:
  - `registry_add`'s open-then-write leaves a window where a concurrent prune sees an empty file and unlinks it.
  - A registry removed between the `-f` test and `done < "$f"` would fail the redirection under `set -e`. SessionStart would
    still return 0, but with no reminder.
- **T4.** `listed`/`seen` test membership against a space-joined string. That misfires only for paths containing a
  `" /…"` sequence.
- **T5.** Server identity is `#{start_time}` (seconds). Two concurrent servers (`-L` sockets) started in the same second
  compare equal. This is item 4's design.
- **T6.** The claude -w detection also matches an AI pane whose cwd is a subagent `agent-*` worktree (same kind), and
  restore then tags that pane `@lazy_llm_wt`. Also, a `claude -w` pane whose worktree and branch were landed now comes back
  as a fresh conversation (the conv is dropped, "comes back shared"). Before, it got a `claude --resume` attempt from the
  workspace dir. That matches the isolated-pane policy, but it's a behaviour change.
- **Nits:**
  - The reminder's header counts worktrees that `probe_ctx` then skips (no base, from a detached parent): "1 subagent
    worktree(s)" with no line under it.
  - Mid-rebase, the commit count double-counts replayed commits (3 instead of 2; `cmd_status`, which predates these
    commits; `llm-wt list` shows the same).
  - Registries are pruned only at a `/clear`.
  - Every compact or resume runs a full `cmd_status` per agent worktree, including `tree_hash` of copied directories.

VERDICT: fail (4 items)

## Rework (persistence round 2) and close

**Date:** 2026-10-03_22:26

All four round-2 failures fixed (`a1c23a9`); each new test fails on the previous code, checked in a
throwaway worktree:
- D1, a stale registry entry claimed another session's worktree: entries name the worktree's
  session. Test: the path is reused by another session.
- D2, the picker with relative gitdirs: fixed, scenario 26 (the old Lua fails exactly that check).
- D3, `/clear` cost grew with each clear: a per-pane index. The relative test went 317→1291 ms on
  the old code and 390→389 ms on the new.
- D4, the unfiled follow-up: `claude-worktrees-polish` (backlog) gathers it with the theoretical
  items.
- Also: a legacy owner (no server recorded) isn't stolen from; unreadable registries are never
  deleted; dead registries are GC'd past 50.
- Not sent for a 3rd verify round (the two-round bound): each fix has a test that fails on the old
  code.

**Incident during this round (2026-10-03 21:07:37):** the user's whole tmux server exited while
a scenario-24 run was going, with the live `~/.local/bin/llm-wt` swapped to the previous version
for an old-code check. The swap was restored once the session came back. The root cause isn't
found yet (investigation follows; see the session notes). Since then every suite run goes through
a decoy tmux pane, and old-code checks use a throwaway `git worktree`, never a live swap.
Full suite in the decoy: 28/28, exit 0.

**Final (2026-10-03_22:27):** full suite 28/28 and live scenario 47/47, both run inside decoy tmux panes. Pushed,
and the dev-env pointer bumped. No plugin change since 0.4.0 (the hooks are unchanged; llm-wt is
live through stow).
