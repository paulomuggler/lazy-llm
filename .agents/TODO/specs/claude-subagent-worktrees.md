# Spec: Claude Code's own worktrees run through `llm-wt`

Companion to the tasks `../claude-subagent-worktrees.md` (backend, hooks, guidance) and
`../claude-subagent-worktrees-ui.md` (dashboard, border, editor). The task files hold the brief
and the acceptance criteria. This file holds the design. The user approved the design on
2026-10-02 ("nice comprehensive design") and flagged **correctness and verification** as the
main risks, so §12 (tests) carries as much weight as the code.

Grounded in a read of lazy-llm `main` at `47619a2`, Claude Code 2.1.287, git 2.55, and a live
spike on 2026-10-02 (§2). Where the spike and the docs disagree, the spike wins. If an
executor finds a spike fact no longer holds, stop and report it. Don't redesign around it.

## 1. Goal and scope

A single Claude session can fan work out to subagents that each run in their own worktree
(`Agent(isolation: "worktree")`), and that work lands back cleanly, with lazy-llm aware of it.
Today that path bypasses lazy-llm completely.

- Claude's worktree **creation and removal** go through `llm-wt`, via the `WorktreeCreate` and
  `WorktreeRemove` hooks in lazy-llm's own Claude plugin. Same layout, bootstrap (linked
  `.env*`, `.work-state`, `settings.local.json`), init hook and ownership config as pane
  worktrees.
- **The parent session integrates**, using `llm-wt integrate`. Subagents commit and stop.
- Each party gets **just-in-time guidance** from hooks: the subagent at `SubagentStart`, the
  parent at `PostToolUse` of the `Agent` call, a session that entered a worktree at
  `PostToolUse` of `EnterWorktree` (and at `SessionStart`).
- lazy-llm **shows** these worktrees (task 2): Worktrees tab, pane border count, `<leader>llmw`.

Not in scope: steering Claude toward using isolation (the user or a skill asks for it); the
`worktree.sparsePaths` / `worktree.symlinkDirectories` settings (the hook replaces Claude's
creation, so those settings stop applying; documented in §11).

## 2. Observed Claude Code behavior (spike, 2026-10-02, v2.1.287)

Headless `claude -p` runs in throwaway repos (local branch `feature` one commit ahead of
`origin/trunk`), logging every hook payload. Evidence was in the session scratchpad. Re-run
the live scenario (§12.2) to re-confirm.

| # | Fact | Consequence |
|---|---|---|
| S1 | **Without** a `WorktreeCreate` hook, `isolation: "worktree"` creates `.claude/worktrees/agent-<agentId>` on branch `worktree-agent-<agentId>`, **based on `origin`'s default branch** (`6480cbb init`, not the local `feature` HEAD). Gitignored files (`.env`) are not copied. | Subagents start from stale code on a non-trunk branch. The motivating bug. |
| S2 | `WorktreeCreate` stdin: `session_id`, `transcript_path`, `cwd` (the **parent's** cwd), `prompt_id`, `hook_event_name`, **`name`**. No `worktree_name`, `branch` or `base_path`, contrary to the docs. `name` is `agent-<agentId>` for subagents and a random slug (e.g. `wise-exploring-metcalfe`) for `EnterWorktree`. | We pick the branch and base. `name` maps a worktree to its subagent. |
| S3 | The hook's stdout path is used as-is (the subagent's cwd). Exit 0 with no stdout means creation fails. | The hook must never print nothing (§8). |
| S4 | With the hook, the parent's `Agent` `tool_response` has `worktreePath` (our path) and **no `worktreeBranch`**. Without the hook it has both. | The parent learns the branch from our guidance (§7.2). |
| S5 | With the hook, Claude **never calls `WorktreeRemove` for a subagent**, even one that changed nothing. The worktree is left in place. Without the hook, an unchanged one is removed silently and a changed one kept. | We clean up at `SubagentStop` (§5.2). |
| S6 | `EnterWorktree` fires `WorktreeCreate`. `ExitWorktree action:"remove"` fires `WorktreeRemove` with `worktree_path` and `cwd` (= the worktree). For a hook-made worktree, `ExitWorktree` first refuses ("Could not verify worktree state") until it's called with `discard_changes: true`. | Our remove must refuse on its own when work would be lost (§5.1). |
| S7 | `SubagentStart` stdin has `agent_id`, `agent_type`, and `cwd` = the worktree. Its `hookSpecificOutput.additionalContext` **reaches the subagent** (it repeated a planted word). | Subagent guidance goes here (§7.1). |
| S8 | `SubagentStop` stdin has `agent_id`, `agent_type`, `cwd` = the worktree, `agent_transcript_path`, `last_assistant_message`. | Cleanup trigger. |
| S9 | Every hook, the subagent's included, runs as a child of the **main** claude process, with its environment (a planted env var was present). `CLAUDE_PROJECT_DIR` is the parent's project dir. Subagents fire no `SessionStart`. Tool hooks fired inside a subagent carry `agent_id`, and their `cwd` is the worktree. | `TMUX_PANE` is available to all worktree hooks in a lazy-llm pane. |
| S11 | (Found by the live scenario.) A **background** subagent (`run_in_background: true`): the `Agent` `PostToolUse` fires at launch with `status: "async_launched"`, `agentId`, `outputFile`, and **no `worktreePath`**. No hook fires when it completes: the parent hears of it only through its completion notification, which carries the subagent's final message. | §7.2 finds the worktree by `agentId` and gives the land procedure at launch. §7.1 has the subagent end its final message with the land command. |
| S10 | In a session isolated by `EnterWorktree`, the Bash tool refuses git commands it can't verify stay inside the worktree. | Guidance shouldn't tell such a session to run raw `git -C <primary>`. `llm-wt` itself is fine (not "git" to the checker). Confirm in §12.2. |

## 3. Three kinds of worktree

| | Task (existing) | Pane (existing) | Claude (new) |
|---|---|---|---|
| Created by | `lazy-llm -W`, Worktrees `n` | `llm-add -i`, dashboard `A` | Claude Code's `WorktreeCreate` (subagent isolation, `EnterWorktree`, `claude -w`) |
| Directory | `.worktrees/<branch>` | `.worktrees/.panes/<name>` | `.worktrees/.claude/<name>` |
| Branch | the user's | `lazy/<name>` | `lazy/<name>` (`name` from the payload) |
| `lazyLlmKind` | — | absent (= pane) | `claude` |
| Integrates | however | the agent, `llm-wt integrate` | subagent: **the parent**. `EnterWorktree`/`-w` session: itself |
| Removed | the user | closing the last pane asks | `SubagentStop` if empty; parent's `llm-wt integrate --remove`; `WorktreeRemove`; Worktrees tab `K` |

## 4. Creation: `llm-wt claude-hook`, event `WorktreeCreate`

New subcommand `llm-wt claude-hook`: reads a hook payload on stdin and dispatches on
`hook_event_name`. JSON fields are read with the grep/sed `field` approach `llm-claude-hook`
uses (portable, no jq), and escaped with its `json_escape`. Unknown events: exit 0, no output.

`WorktreeCreate`:

1. `cwd` from the payload, falling back to `$PWD`. `PARENT=$(git -C "$cwd" rev-parse --show-toplevel)`.
   Not a repo: exit 1, stderr "not in a git repository: $cwd". Claude reports that, the same as
   its own failure.
2. **Base**: `git -C "$PARENT" branch --show-current`. **Primary**: `$PARENT`. If the parent is
   itself an llm-wt worktree (pane or claude), that's correct as-is: the subagent integrates into
   the parent's branch, and the parent integrates onward. Detached HEAD (or mid-rebase): create
   the worktree anyway from `HEAD` on `lazy/<name>` with `lazyLlmKind=claude` and **no** base or
   primary. `llm-wt integrate` then exits 2, and no guidance is injected.
3. **Root** (where `.worktrees/` lives): walk the ownership chain. While `PARENT`'s branch has
   `lazyLlmPrimary`, step to it. The last one is the root. **Don't** use `git worktree list`'s
   first entry: in a submodule it's the gitdir (`.git/modules/...`), not the working tree.
   Directory: `${LAZY_LLM_WORKTREE_DIR:-$ROOT/.worktrees}/.claude/<safe_name(name)>`.
4. **Name**: `safe_name "$name"` (empty or missing → `claude-wt`). If the branch `lazy/<n>` or the
   directory is taken, append `-2`, `-3`, … (first free).
5. Under the repo lock (§9): `add_exclude "/.worktrees/"` when the dir is in-repo,
   `lazy_llm_setup_worktree "lazy/<n>" "<base dir>" HEAD "<n>"` from `PARENT` (start point
   `HEAD` of the parent's worktree, never `origin/*`). Then git config on the branch:
   `lazyLlmKind=claude`, `lazyLlmName=<payload name>` (raw, for the agent-id match),
   `lazyLlmSession=<session_id>`, `lazyLlmPane=<$TMUX_PANE or unset>`, plus `lazyLlmBase` and
   `lazyLlmPrimary` (step 2). With `TMUX_PANE` set, also
   `lazyLlmPaneServer=<that server's #{start_time}>`, from
   `tmux display-message -p -t "$TMUX_PANE" '#{start_time}'` (through the hook's inherited
   `$TMUX`), unset when that query fails. tmux numbers panes from `%0` again in each new server,
   so after a restart the pane id alone would name an unrelated pane (§10). All of these are set
   in one loop: a failed write rolls the worktree back.
6. Bootstrap (`cmd_bootstrap`), outside the lock except for its `info/exclude` writes. The init
   hook gets `LAZY_LLM_WORKTREE_KIND=claude` (pane worktrees get `pane`), so a slow
   `worktree-init` can skip work for throwaway agent worktrees.
7. **stdout: exactly the absolute worktree path, one line.** Everything else (git, bootstrap,
   init hook) goes to stderr.

The parent's uncommitted changes are not in the subagent's worktree, since it starts from
`HEAD`. The parent guidance says so (§7.2).

`.worktreeinclude`: Claude's own creation copies the gitignored files it lists. Since the hook
replaces that, `read_file_entries` also reads `<repo>/.worktreeinclude` (after the two
`worktree-files` lists) and treats every pattern there as `copy:`. This applies to pane
worktrees too, so one file serves both.

## 5. Removal

### 5.1 `WorktreeRemove` (from `ExitWorktree remove`, and any other caller)

`worktree_path` from the payload:
- an llm-wt worktree (`load_ctx` succeeds): `cmd_remove` **without** `--force`. It refuses
  (exit 1, stderr naming what would be lost and `llm-wt integrate` / `llm-wt remove --force`)
  when anything is uncommitted, untracked, unintegrated, or a changed copy. Otherwise the
  worktree and its branch go.
- any other worktree (made by the fallback, §8): `git worktree remove` without `--force`, and
  its exit status.
- the path doesn't exist: exit 0.

### 5.2 `SubagentStop`: remove what the subagent left empty

The cleanup Claude skips (S5). On `SubagentStop` with an `agent_id`:
1. Find the worktree: the payload `cwd`'s toplevel if its branch has `lazyLlmKind=claude` and
   `lazyLlmName=agent-<agent_id>`. Otherwise scan `git -C "${CLAUDE_PROJECT_DIR:-$cwd}" worktree list`
   for a branch with that `lazyLlmName`. None found: exit 0. That covers every non-isolated
   subagent.
2. `cmd_status --porcelain`. If dirty, untracked, unintegrated, copies-changed and rebasing are
   all 0, run `cmd_remove` (non-force). Anything else stays for the parent.
3. Never fails the hook: always exit 0, with problems on stderr.

`SubagentStop` fires before the parent's `PostToolUse` for that `Agent` call (S8 then S4 order
in the spike logs), so by the time the parent is told anything, an empty worktree is gone.

## 6. Integration by the parent

Already works: `llm-wt integrate <path>` rebases in `<path>` and fast-forwards `<base>` in
`<primary>` (the parent's own directory). Additions:

- **`llm-wt integrate [path] --remove`**: after a successful integrate (exit 0), run
  `cmd_remove` on the worktree. That's the one-call "land it" the parent uses.
- **`llm-wt list [dir] [--porcelain]`**: the claude-kind worktrees whose `lazyLlmPrimary` is
  `dir`'s toplevel (default cwd). One row each: path, branch, name, and the `status` counts
  (uncommitted, unintegrated). It's the parent's view of what's still outstanding.
  `--porcelain` gives tab-separated `path branch name dirty untracked unintegrated`.

Exit codes are unchanged (0, 3, 4, 5, 6, 7). Exit 4 means the parent's directory is no longer
on the base branch; the guidance says to stop and tell the user. Exit 7 means the parent's own
uncommitted edits overlap; the parent commits or stashes its *own* work first.

Why the parent and not the subagent: it serializes merges, resolves conflicts with the most
context, can review before landing, and its directory doesn't move under it mid-turn.

## 7. Guidance (all from `llm-wt claude-hook`, all `hookSpecificOutput.additionalContext`)

Text lives in Markdown files under `llm-status-bin/.local/share/lazy-llm/`, live through stow
like `worktree-agent.md`. Placeholders are filled by the hook.

### 7.1 Subagent: `SubagentStart`

When the payload `cwd` is a claude-kind worktree whose `lazyLlmName` is `agent-<agent_id>` and
which has a base: `worktree-subagent.md`, with `{{path}} {{branch}} {{base}} {{primary}}`. It
covers:
- you're in your own worktree `{{path}}` on `{{branch}}`, split from `{{base}}`, and the parent
  session integrates it into `{{primary}}` after you finish;
- **commit** everything you want kept, in logical units (task-file edits included).
  Uncommitted changes are never integrated;
- don't run `llm-wt integrate`, don't push, don't check out `{{base}}`, don't write under
  `{{primary}}` (symlinked shared files excepted, as in `worktree-agent.md`);
- finish with `llm-wt status` and report your branch and commits in your final message, ending
  it (when it committed anything) with the line `lazy-llm: land this with llm-wt integrate
  --remove {{path}}`. For a background subagent, that final message is all the parent gets
  when it completes (S11);
- branch hygiene is settled. Don't ask about it.

### 7.2 Parent: `PostToolUse`, matcher `Agent`

The worktree is `tool_response.worktreePath`, or, when it's missing (a background launch, S11),
the one found by `tool_response.agentId` (`find_agent_wt`). `worktree-parent.md` takes an
`{{intro}}` that differs by case:
- the path exists and is a claude-kind worktree: `worktree-parent.md`, with the path, branch,
  base, primary, agent's commit count (`base..branch`), uncommitted count, and the land command
  `llm-wt integrate --remove <path>`. It also covers: review first with `git -C <path> log
  --oneline <base>..` and `git -C <path> diff <base>...`; integrate one worktree at a time; the
  exit-code table (with 3 = the subagent left uncommitted work: commit it there or `llm-wt
  remove --force <path>` to drop it); and `llm-wt list` to see what's outstanding.
- the path no longer exists: a one-line note that the subagent changed nothing and its
  worktree was removed.
- the `tool_response` `status` isn't `completed` (a background launch): the same guidance, with
  an intro saying it's running there, and that by the time it finishes a removed worktree means
  it changed nothing.

### 7.3 A session working in a claude-kind worktree: `PostToolUse` `EnterWorktree`, and `SessionStart`

`EnterWorktree` and `claude -w` put the **session itself** in a worktree. It integrates for
itself, like an isolated pane, so it gets the existing `worktree-agent.md`:
- `PostToolUse` with tool `EnterWorktree`: from `tool_response.worktreePath`.
- `SessionStart`: when the session's `cwd` is an llm-wt worktree of **any** kind (pane or
  claude) with a base. This **replaces** `llm-claude-hook`'s `LAZY_LLM_WORKTREE=1` check
  (remove `worktree_context` there), so the guidance comes from git config, not env, and works
  outside tmux too. Isolated panes keep getting it, exactly once.

## 8. Plugin wiring, fallback, deploy

`claude-plugin/hooks/hooks.json` gains (alongside the existing entries):

| Event | Matcher | Command | Timeout |
|---|---|---|---|
| `WorktreeCreate` | — | `worktree.sh` | 600 (init hooks can be slow) |
| `WorktreeRemove` | — | `worktree.sh` | 60 |
| `SubagentStart` | — | `worktree.sh` | 30 |
| `SubagentStop` | — | `worktree.sh` | 60 |
| `PostToolUse` | `Agent\|EnterWorktree` | `worktree.sh` | 30 |
| `SessionStart` | — | `worktree.sh` (a second hook beside `run.sh`) | 30 |

`claude-plugin/hooks/worktree.sh`, a shim like `run.sh`:
- `LAZY_LLM_WT_BIN` (test override), else `$HOME/.local/bin/llm-wt`. If it's executable, buffer
  stdin and `llm-wt claude-hook`.
- **Fallback for `WorktreeCreate` only**: if llm-wt is missing, or exits non-zero, or prints no
  path, create a plain worktree so Claude's flow never breaks:
  `git -C "$cwd" worktree add -b "worktree-<name>" "<toplevel>/.claude/worktrees/<name>" HEAD`
  (stderr warning naming why), and print its path. If that fails too: exit 1.
- Every other event: no llm-wt means exit 0 with no output.
- **Not** behind `llm-claude-hook`'s `TMUX_PANE` guard or its nested-claude guard. A `claude -p`
  run by an agent needs worktrees too, and outside tmux there's no pane to attribute to.

The plugin is enabled at user scope, so this applies to **every** Claude session on the
machine, in any repo: worktrees land in `<repo>/.worktrees/.claude/` (excluded through
`.git/info/exclude`, never `.gitignore`), and branch from local `HEAD`. That's deliberate, and
it fixes S1 everywhere.

Deploy: bump the plugin version to `0.4.0` in `claude-plugin/.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json`, then run `./install.sh`, which stows and runs `claude plugin
marketplace update` + `claude plugin update`. New sessions load it. Already-running sessions
keep the old hooks.

## 9. Concurrency: the repo lock

Several subagents launched in one message mean concurrent `WorktreeCreate` hooks. Shared state
they write: `.git/config` (`git config` fails on `config.lock` under contention),
`.git/info/exclude` (unlocked appends), and the free-name probe.

`with_repo_lock <cmd…>`: an exclusive lock on `$(git rev-parse --git-common-dir)/lazy-llm-wt.lock`.
`flock` when present (Linux). Otherwise a `mkdir` lock dir holding the owner pid, retried every
0.1s and broken when the pid is dead, with a 60s cap. **Reentrant**: a `LAZY_LLM_WT_LOCKED=1`
guard, so `create` → `add_exclude` doesn't deadlock. Held for: name probe + worktree add +
config writes in `create` (both kinds), `add_exclude`, and `cmd_remove`. **Not** held for
bootstrap copies or the init hook.

## 10. Display (task 2)

- **Which pane owns it**: the pane recorded in `lazyLlmPane`, only while the current tmux
  server's `#{start_time}` equals `lazyLlmPaneServer` (§4 step 5). A mismatch means no pane
  owns it: a server restart reuses pane ids, so a leftover worktree would otherwise look owned
  by an unrelated new pane. A worktree without `lazyLlmPaneServer` (made before it was recorded)
  goes by the pane id alone. All three surfaces below apply this: the Worktrees tab reads
  `#{start_time}` in its existing single `tmux list-panes -a`, the border gets it from
  llm-pane-border's existing `display-message` (other callers of
  `lazy_llm_claude_worktree_owners` ask once, only when some worktree records a server), and
  `<leader>llmw` asks once, only then.
- **Worktrees tab**: `_lazy_llm_emit_worktree_row` owner for a claude-kind worktree is
  `claude:<session>:<pane>` when `lazyLlmPane` is a live pane of this server, else
  `claude:orphaned`; a live pane running in it (`@lazy_llm_wt`) still wins. The row
  shows `⎇` and a `claude` tag. Existing actions apply (`Enter` adopts into a pane, `K` cleans
  up through `llm-wt close`/`remove`). New: `I` runs `llm-wt integrate --remove` on the row,
  with the exit code's meaning shown on failure.
- **Dashboard tree / AI pane border**: an AI pane that owns claude-kind worktrees (`lazyLlmPane`
  = the pane id, of this server) shows `⎇×N` (N = how many still exist) after its existing git segment.
- **`<leader>llmw`**: when the visible AI pane owns claude-kind worktrees, the toggle offers a
  picker over {main copy, the pane's own worktree if isolated, each claude-kind worktree}. With
  none, it behaves exactly as today.

## 11. Known limits and residual risks

- `worktree.sparsePaths` / `worktree.symlinkDirectories` no longer apply (our hook replaces the
  creation they configure). Documented in the README. `.worktreeinclude` is honored (§4).
- Claude's periodic cleanup sweep (`cleanupPeriodDays`), established 2026-10-03 from the 2.1.288
  docs, changelog and bundled code (`claude-worktree-followups` item 5). It runs at most once a
  day after a session starts. It enumerates only `<repo>/.claude/worktrees/` entries whose names
  match Claude's own patterns (`agent-a<hex>`, `wf_…`, `job-…`, …). It removes one only when it's
  past the age cutoff, `git status` is clean, and it has no unpushed commits. It removes with
  `git worktree remove --force` + `git branch -D worktree-<name>`, directly, **never through
  `WorktreeRemove`**. A second sweep, for background-session jobs, skips hook-created
  worktrees. Another step unlocks stale worktree locks across all worktrees, but only locks in
  Claude's own lock format; llm-wt takes none. **Verdict: it can't touch
  `.worktrees/.claude/`.** The plugin's fallback worktrees (`.claude/worktrees/agent-…`, §8)
  are in scope, but only once clean with nothing unpushed, so no work is lost.
  Outside the sweep: deleting a background session with a second ctrl+x in `claude agents`
  forces removal even if `WorktreeRemove` refuses (an explicit user discard). Session-exit
  removal falls back to forced git removal only when no `WorktreeRemove` hook is configured.
  Re-check after Claude Code upgrades: this is version-specific.
- Two plugins that both define `WorktreeCreate` would conflict. Only lazy-llm does, on this
  machine.
- `name` → branch mapping changes if Claude changes its payload. The live scenario (§12.2) is
  the canary. Rerun it after Claude Code upgrades.

## 12. Tests

### 12.1 Unit: `tests/scenarios/24-claude-worktrees-unit.sh`

Pure git plus hook payloads on stdin, sandboxed like scenario 22 (`cd` into the sandbox,
`GIT_CEILING_DIRECTORIES`, sandboxed HOME and git identity, `unset TMUX TMUX_PANE`). Every
JSON the hook prints is checked with `jq -e` (jq is a test dependency only). Cases:

1. `WorktreeCreate` from a repo on `feature` with an `origin/trunk` behind it: stdout is one line
   and an existing directory under `.worktrees/.claude/agent-…`; branch `lazy/agent-…` at
   `feature`'s HEAD (not `origin/trunk`); config kind/name/session/base=`feature`/primary;
   `.env` is a link to the main copy; `/.worktrees/` is in `info/exclude`; `.gitignore` untouched.
2. Nested: the parent `cwd` is a pane worktree (`llm-wt create`). Base = `lazy/<pane>`,
   primary = the pane worktree, directory under the **main** repo's `.worktrees/.claude/`.
   `llm-wt integrate` from the agent worktree lands on the pane branch, not `main`.
3. Name collision: two creates with the same `name` get `-2`.
4. **Parallel**: 8 creates launched at once (`&`, then `wait`). All exit 0, 8 distinct
   directories, every branch has all six config keys, `info/exclude` has `/.worktrees/` exactly
   once. Run it 3 times.
5. Detached HEAD: creation succeeds, no base config, `llm-wt integrate` exits 2, and
   `SubagentStart` prints nothing.
6. Not a repo: exit 1 and nothing on stdout.
7. `SubagentStop`, empty worktree (agent id matches): removed, branch gone. With a commit:
   kept. Dirty only: kept. Agent id mismatch: untouched. Non-isolated (cwd = main dir): no-op.
8. `WorktreeRemove`: unintegrated → exit ≠ 0, still exists. After `integrate`: removed with its
   branch. A non-llm-wt worktree: plain removal. Missing path: exit 0.
9. `SubagentStart` guidance: valid JSON with `hookEventName` `SubagentStart` and the filled
   path/branch/base; no `{{` left. None for an agent-id mismatch or the main dir.
10. `PostToolUse` `Agent`: kept worktree → context names the path, branch, commit count and
    `llm-wt integrate --remove`. Removed → the "changed nothing" line. `status` ≠ completed →
    the background line. No `worktreePath` → no output.
11. `SessionStart`: cwd in a pane worktree → `worktree-agent.md` filled. In a claude-kind
    worktree → same. Main dir → nothing. `llm-claude-hook` no longer prints guidance (an
    isolated pane gets it once, from llm-wt).
12. `PostToolUse` `EnterWorktree` → `worktree-agent.md` for that path.
13. `llm-wt integrate --remove`: lands and removes. On exit 3/5 nothing is removed.
14. `llm-wt list` shows only the worktrees whose primary is this dir, with counts.
15. `.worktreeinclude` entries are copied (not linked) into new worktrees.
16. Shim `worktree.sh`: with `LAZY_LLM_WT_BIN` pointing at a missing file → `WorktreeCreate`
    falls back (path under `.claude/worktrees/`, branch `worktree-<name>`) and other events
    print nothing. With a stub llm-wt that exits 1 → fallback too, with a stderr warning.

### 12.2 Live: `tests/scenarios/25-claude-worktrees-live.sh` (opt-in, real Claude)

Skips (passes with a "skipped" note) unless `LAZY_LLM_LIVE_CLAUDE=1`. It costs real tokens.
`env -u TMUX -u TMUX_PANE`, a throwaway repo with an `origin` whose default branch is behind
the local `feature`. Runs `claude -p --model sonnet --dangerously-skip-permissions --settings <json>`:
the JSON disables the installed `lazy-llm@lazy-llm` plugin and wires this checkout's
`claude-plugin/hooks/worktree.sh` with `LAZY_LLM_WT_BIN` set to this checkout's `llm-wt`.
`LAZY_LLM_HOOK_LOG`-style payload logging records every event. Assertions are on **git state,
hook logs and transcripts**, never on model prose:

1. Fan-out: the prompt asks for 3 subagents in one message with `isolation: "worktree"`. A
   writes and commits `a.txt`, B writes and commits `b.txt`, C only reads. Then "follow any
   integration instructions you receive". Assert:
   - exactly 3 `WorktreeCreate` events, and the log shows one hook process per event (proves
     the installed plugin is off);
   - each subagent transcript (`agent_transcript_path`) contains the `worktree-subagent.md`
     marker line;
   - the parent transcript contains the `worktree-parent.md` marker for A and B, and the
     "changed nothing" line for C;
   - after the run, `feature` contains A's and B's commits, with no merge commits
     (`git rev-list --merges` empty);
   - no `.worktrees/.claude/*` left and no `lazy/agent-*` branches left;
   - `origin/trunk` is unchanged.
2. `EnterWorktree`: the prompt enters a worktree, commits a file, follows instructions, then
   exits with `remove`. Assert: `WorktreeCreate` under `.worktrees/.claude/`; the transcript has
   the `worktree-agent.md` marker; `feature` has the commit (the session integrated itself);
   the worktree is gone.
3. Refusal: in a run where the subagent commits and the prompt tells the parent **not** to
   integrate, the worktree and branch survive to the end (nothing deletes unintegrated work).

Marker lines: each guidance file starts with an HTML comment `<!-- lazy-llm:<file-stem> -->`,
which is what transcripts are grepped for.

### 12.3 Manual (human validation)

In a real lazy-llm workspace pane, ask Claude to fan out two write tasks to isolated subagents.
Watch the Worktrees tab and the pane border `⎇×N` while they run, and confirm both land on the
workspace branch.
