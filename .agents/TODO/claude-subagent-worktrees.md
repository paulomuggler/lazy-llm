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
- Scenario 25 live: run 2 caught S11 + a transcript-counting test bug; run 3 passed 30/30
  (the verifier's own rerun confirmed 30/30).

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
- `claude-worktree-cleanup-sweep` (backlog): Claude's `cleanupPeriodDays` sweep was not observed (spec §11).
- `test-runner-exit-status` (backlog): the runner exits 1 even when all scenarios pass (pre-existing).

## Verify Plan
- [x] Tests: `tests/test-runner.sh 24-claude-worktrees-unit.sh` passes; regressions 22, 19, 12, 14 pass
- [x] Static: shellcheck 0.11.0 clean on `llm-wt`, `worktree.sh`, `llm-claude-hook`, scenarios 22/24/25; `hooks.json`, `plugin.json`, `marketplace.json` parse with jq and carry version 0.4.0
- [x] AC1 (create): read `claude_create` — start point `HEAD` of the parent worktree, all config keys, stdout is only `printf '%s\n' "$wt"` (every other output redirected to stderr); probe with a git `post-checkout` hook and a `worktree-init` hook that write to stdout: WorktreeCreate stdout must still be exactly the path
- [ ] FAIL: AC2 (nested): parent in a pane worktree → dir under the main repo, base/primary = pane; then exercise `integrate --remove` and SubagentStop-on-empty in the nested case and check the `lazy/agent-*` branch and its config are gone (scenario 24 test 2 doesn't cover removal there)
- [x] AC2b (submodule): parent is a submodule checkout → root is the submodule working tree, create/integrate --remove/SubagentStop removal and branch deletion all work
- [ ] FAIL: AC3 (lock): 8 parallel creates in a sandbox, plus the mkdir-lock path forced (PATH without flock) — 8 parallel creates, no lock dir left, stale-lock (dead pid) recovery
- [ ] FAIL: AC4/AC5 (removal never loses work): SubagentStop and WorktreeRemove on: commits, dirty, untracked, changed copy, rebase in progress, base branch renamed/deleted after creation (unintegrated count must not silently become 0), WorktreeRemove given a subdirectory of an llm-wt worktree (must not remove the enclosing worktree), WorktreeRemove with the main dir
- [ ] FAIL: AC6 (guidance): SubagentStart/PostToolUse/SessionStart JSON validity with hostile path characters (`"`, `\`, tab, `&`, spaces), first-match `hook_field` robustness against `"cwd"`/`"status"` keys in tool_input/tool_response; llm-claude-hook diff removes `worktree_context` only
- [x] AC7: `integrate --remove` exit codes (0/3/5 and remove refusal after a successful integrate); `list` porcelain/human; `.worktreeinclude` incl. `!` exclusions and comments
- [ ] FAIL: AC8 (shim): fallback when llm-wt is missing / fails / prints junk / is killed; partial-failure leak (llm-wt created the worktree then failed); exit codes; `set -e`-free shim behavior; event filter
- [x] Edge: exit codes of every non-Create event are 0 even when the inner handler dies; WorktreeCreate never exits 2; SIGPIPE/pipefail in `cmd_claude_hook`'s `printf | "$0"` pipe
- [x] Portability: no jq/flock hard dependency in shipped code (grep); bash-3.2-incompatible constructs noted (`{fd}>` redirection, `mapfile`, `${var@Q}`) vs. the repo's existing baseline
- [ ] FAIL: Claim audit: Work Report claims (140 assertions, 17 cases, every §12.1 case covered, "Not filed" follow-up), spec §2 S11 placement, AC "Scenario 25 passes live — 30/30" (orchestrator-reported; rerun optional), unchecked Deploy AC

## Verify Report

**Date:** 2026-10-02 · verifier: independent agent · sandbox `/tmp/vfy-cw` (GIT_CEILING_DIRECTORIES=/tmp,
TMUX/TMUX_PANE unset, private TMUX_TMPDIR and HOME). Commits read: e99b6d0 b86940d aae105f f74c8e2 (+642deeb).

### Passing
- **Tests:** scenario 24 140/140; 22, 19, 12, 14 all pass. **Live scenario 25 rerun by the verifier: 30/30**
  (fan-out, background 1b, EnterWorktree, refusal). Note (pre-existing, unrelated): `tests/test-runner.sh`
  exits 1 even when every test passes (also for untouched scenario 12) — its EXIT trap/teardown, not this task.
- **Static:** shellcheck 0.11.0 clean on `llm-wt`, `worktree.sh`, `llm-claude-hook`; scenarios carry only the
  same info-level SC1091/SC2034 as the pre-existing baseline. hooks.json/plugin.json/marketplace.json valid,
  version 0.4.0, all six events wired with the §8 timeouts; `worktree.sh` mode 100755.
- **AC1 create:** `claude_create` (llm-wt ~429-466) starts at the parent worktree's `HEAD`, writes all keys, and
  stdout stays exactly the path even with a `post-checkout` hook and a `worktree-init` that both echo to stdout
  (both went to stderr). Init hook sees `LAZY_LLM_WORKTREE_KIND=claude`.
- **AC2b submodule:** parent = submodule checkout (`git worktree list` first entry is `.git/modules/sm`): root is
  the submodule working tree, `.env` linked, exclude in the module's info/exclude, `integrate --remove` and
  SubagentStop removal delete worktree **and** branch.
- **AC3 lock (flock path):** 8x3 parallel creates in test 24; my stress run of 12 parallel creates, then 12
  SubagentStops racing 6 more creates: all rc 0, every late branch has 5 keys, no stdout from SubagentStop,
  config sections removed with their branches. mkdir path (PATH without flock): 3 rounds of 8 parallel creates
  all pass, no lock dir left; a dead-pid lock dir is broken immediately.
- **AC4/5 basics:** SubagentStop keeps commits, dirty, untracked and changed-copy worktrees; WorktreeRemove refuses
  unintegrated work (exit 1) and the main dir (git refuses, exit 1). Ignored-only files are removed with an empty
  worktree (by design, §5.2).
- **AC7:** `integrate --remove` 0/3/5 paths per test 13; `list` per test 14.
- **Exit codes:** `cmd_claude_hook` maps WorktreeCreate 2→1, WorktreeRemove non-zero→1, all others 0; the child
  always drains stdin before work so the `printf | "$0"` pipe can't SIGPIPE under pipefail.
- **Portability:** no jq in shipped code; flock optional. `{fd}>>` (bash 4.1+) only in the flock branch; the file
  already needed bash 4 (`mapfile`).
- **Guidance:** valid JSON with spaces and `&` in the path; `hook_field` ignores escaped `"status"`/`"worktreePath"`
  inside tool_input (test 10). llm-claude-hook diff removes only `worktree_context` (json_escape still used).

### Failures

1. **Nested parent: removal leaves the branch and its config behind (AC2/AC4/AC7, spec §5.2 "removed, branch gone",
   §6, and the parent guidance "deletes the worktree and branch").**
   Repro: `mk_repo n; pane=$(llm-wt create n pw); wt=$(hook WorktreeCreate cwd=$pane name=agent-n1);` commit in
   `$wt`; `llm-wt integrate --remove $wt` → exit **0**, worktree gone, but stderr `error: the branch 'lazy/agent-n1'
   is not fully merged … Warning: failed to delete branch`; `lazy/agent-n1` and all five `branch.lazy/agent-n1.lazyLlm*`
   keys remain. Same for SubagentStop on an empty worktree once the pane has a commit of its own (`lazy/agent-n2` left).
   Expected: branch and config deleted. Cause: `lazy_llm_cleanup_worktree` (lazy-llm-lib.sh) runs `git branch -d`
   in the **main** worktree (first `worktree list` entry), whose HEAD is not the nested base `lazy/pw`. Applies to
   any parent that is itself an llm-wt worktree (pane, or an EnterWorktree session). Scenario 24 test 2 never removes.

2. **Base branch gone → worktree with unintegrated commits is removed automatically (AC4 "keeps any with work").**
   Repro: create agent-b1 from `feature`, commit in it, `git branch -m feature feature2`; SubagentStop → worktree
   removed (`llm-wt status --porcelain` showed `unintegrated 0`). Same via WorktreeRemove. Commits survived only
   because `git branch -d` happened to refuse. Expected: kept (unknown base = work at risk). Cause: `cmd_status`
   `unintegrated=$(git rev-list --count "$BASE..HEAD" 2>/dev/null || echo 0)` (llm-wt ~794) treats an unresolvable
   base as 0; pre-existing code, now reached by an automatic path.

3. **flock fd is inherited by children run under the lock (AC3).** `exec {_LOCK_FD}>>…` (llm-wt ~82) has no
   close-on-exec, so a background process spawned while locked (e.g. a `post-checkout` hook doing `ctags &`, a common
   pattern) holds the repo lock until it exits. Repro: post-checkout `(sleep 6) &` → each WorktreeCreate takes 6.0 s
   (its own bootstrap `add_exclude` blocks on the lock); the same create with the mkdir lock takes 0.09 s. With a job
   longer than 60 s, concurrent creates/removes time out and WorktreeCreate falls back to a plain worktree.
   Expected: the lock is released at `unlock_repo`. (Close the fd for child commands, or use the flock(1) command form.)

4. **Bootstrap failure after creation → leaked llm-wt worktree plus a second, fallback worktree (AC8).** Repro:
   `.worktreeinclude` lists an unreadable gitignored file (`chmod 000 secret.key`): llm-wt exits 1 after
   creating `.worktrees/.claude/agent-pf` (cp fails under set -e); through the shim, `agent-pg` gets both a full
   llm-wt worktree and a plain `.claude/worktrees/agent-pg` on `worktree-agent-pg`, and the parent repo now shows
   `?? .claude/`. The fallback worktree is never cleaned (S5). Expected: a bootstrap problem is a warning, like the
   init hook, and the created path is still printed.

5. **Paths with `"`, `\` or a tab: WorktreeCreate fails outright (AC6/AC8; README "a subagent never fails to
   start").** Repro: repo at `/tmp/vfy-cw/h-q"uote` (also `back\slash`, `ta<TAB>b`): llm-wt rc 1 and the shim
   fallback rc 1 — both read `cwd` with the grep/sed parser, which doesn't unescape JSON. Claude's own creation
   would have worked. Spaces and `&` are fine. Expected: documented in README §11-limits at least.

6. **mkdir lock never recovers from an empty pid file (AC3, macOS path, low).** Repro: `mkdir .git/lazy-llm-wt.lock.d`
   (no pid) → every create waits the full 60 s and fails (`timeout 5` → 124). An owner killed between `mkdir` and
   `echo $$ > pid` leaves exactly this. Also: two waiters that both see a dead pid both `rm -rf` the dir, and the
   second can delete the lock the first just took.

7. **Claim audit — follow-up not filed:** "Not filed, noted in spec §11: Claude's `cleanupPeriodDays` sweep was not
   observed." Under `### Follow-up`, with no task slug. (Work Report also cites "see the Verify Report for the final
   clean run", which didn't exist; the 30/30 is now confirmed by the rerun above.)

### Low / hardening (not counted)
- WorktreeRemove acts on the worktree *containing* `worktree_path`, of any kind: a subdirectory of a clean claude
  worktree removes it, and a pane worktree's path removes the pane worktree. Claude only sends its own paths, but a
  toplevel-equality + `KIND == claude` check would be cheap.
- A relative `LAZY_LLM_WORKTREE_DIR` makes WorktreeCreate print a relative path (`relwt/.claude/agent-rel`).
- Guidance commands interpolate `{{path}}` unquoted (`git -C {{path}} log …`): wrong for paths with spaces.
- `find_agent_wt` scans `CLAUDE_PROJECT_DIR` before `cwd` (as the spec says), so a background launch from a repo
  other than the project dir gets no parent guidance.
- `.worktreeinclude` matches top-level only and its `!` lines exclude from the link lists too; noted in a code
  comment, not in the README.
- README covers only the first of the four §11 limits.
- Deploy AC is unchecked (by design: deploy happens after verification).

VERDICT: fail (7 items)

## Rework (round 1)

**Date:** 2026-10-02_19:09

All seven verifier failures addressed in `dbe876e`, each with a regression test in scenario 24
(tests 18–24, 31 new assertions; 171/171, 3 consecutive runs). Run against the pre-rework
llm-wt and shim, those tests fail 20 assertions.

1. Nested branch left behind → `cmd_remove` deletes the branch with `-D` after its own status
   check (the check, not `git branch -d`, is the safety). Test 18.
2. Missing base read as "0 unintegrated" → counts commits no other branch has, reports
   `base-missing`, and a rev-list error counts as 1. Test 19.
3. flock fd inherited by hooks → `git worktree add` runs in a subshell with the fd closed. Test 20.
4. Bootstrap failure leaked two worktrees → bootstrap runs as a child; its failure warns, and
   creation still succeeds. A failed config write rolls the worktree back. Test 21.
5. `"`/`\` paths → JSON unescaping in `hook_field` and the shim's `field`. Test 22.
6. mkdir lock → a pid-less dir is broken after 5s; breaking is an atomic rename with a
   pid re-check. Test 24 (forced via `LAZY_LLM_WT_LOCK=mkdir`).
7. Claims → follow-ups filed (above); the report's live-run reference corrected.
- Hardening note taken: WorktreeRemove accepts only a Claude worktree's exact top directory
  (test 23).
