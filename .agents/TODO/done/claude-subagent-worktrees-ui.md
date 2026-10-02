---
slug: claude-subagent-worktrees-ui
title: Show Claude's agent worktrees in lazy-llm (Worktrees tab tag + integrate, pane border ⎇×N, llmw picker)
priority: P2
status: done
created: 2026-10-02_18:25
updated: 2026-10-02_20:42
depends-on: [claude-subagent-worktrees]
tags: [worktree, dashboard, nvim]
model: opus
spec: ../specs/claude-subagent-worktrees.md
commits: [1feb369, 4a09545, 87a5d8c, adf088e, 544aaf6]
human-validation: pending
---

# Show Claude's agent worktrees in lazy-llm

## Context

After `claude-subagent-worktrees`, Claude's worktrees are llm-wt worktrees of kind `claude`
(git config `branch.<b>.lazyLlmKind=claude`, with `lazyLlmPane` = the owning tmux pane id and
`lazyLlmSession`). lazy-llm should show them so the user can see a fan-out in progress and act
on leftovers. Design: [`specs/claude-subagent-worktrees.md`](specs/claude-subagent-worktrees.md) §10.

## Key Files
- `llm-send-bin/.local/bin/lazy-llm-lib.sh`: `_lazy_llm_emit_worktree_row` (owner field), pane border git segment
- `lazy-llm-bin/.local/bin/llm-dashboard`: Worktrees tab render + keys (`render_worktrees_tab`, action dispatch), tree rows, Help tab
- `nvim-llm-send-plugin/.config/nvim/lua/lazy_llm_worktree.lua`: `<leader>llmw` toggle
- `tests/scenarios/14-worktree-bridge-tab-unit.sh`, `22-worktree-pane-unit.sh`: existing coverage to extend

## Read first
- `.agents/TODO/specs/claude-subagent-worktrees.md` §3, §10
- `.agents/TODO/specs/worktree-concurrency-mode.md` §9, §10, §12: how pane worktrees are displayed today

## Where things are (orchestrator discovery, lazy-llm `1f61ecd`)
- **Claude worktree metadata** (from task 1, `llm-wt-bin/.local/bin/llm-wt`, `claude_create`): git
  config `branch.<b>.lazyLlmKind=claude`, `lazyLlmPane=<tmux pane id>` (only when `TMUX_PANE` was
  set), `lazyLlmSession`, `lazyLlmName`, `lazyLlmBase`, `lazyLlmPrimary`. Directory
  `.worktrees/.claude/<name>`, branch `lazy/<name>`. Pane worktrees have no `lazyLlmKind`.
  `llm-wt list [dir] --porcelain` → `path<TAB>branch<TAB>name<TAB>dirty<TAB>untracked<TAB>unintegrated`
  for the claude worktrees whose primary is `dir`. `llm-wt integrate --remove <path>` exit codes:
  0 landed · 2 not an llm-wt worktree · 3 uncommitted changes · 4 main dir not on base · 5 rebase
  conflict left in progress · 6 base kept moving (rerun) · 7 main dir's uncommitted changes overlap.
- **Worktrees tab rows**: `_lazy_llm_emit_worktree_row` in `llm-send-bin/.local/bin/lazy-llm-lib.sh`
  (~l.592–625) computes OWNER: any branch with `lazyLlmBase` is `pane:<s>:<p>` if a pane's
  `@lazy_llm_wt` equals its path, else `orphaned`. **Today a claude worktree shows as
  `⎇ orphaned`**: `Enter` adopts it into a pane and `K` runs the pane-cleanup flow
  (`llm-wt close`/`remove`). Keep those actions for claude rows. Add the new owner values.
- **Worktrees tab render/keys**: `render_worktrees_tab` in `lazy-llm-bin/.local/bin/llm-dashboard`
  (~l.684–815): row building ~693–719 (`owner_mark`), key dispatch ~769–815 (`K`, `Enter`,
  emits `action:…` strings handled further down; find `action:worktree-pane-cleanup`'s handler
  and mirror it for a new `action:worktree-integrate:<path>`). Help tab text ~l.1480–1494.
- **Border git segment**: `lazy_llm_git_segment <dir> <c_text> <c_dim>` (lib ~l.1208), called
  only from `lazy-llm-bin/.local/bin/llm-pane-border:90` with `$pane_dir`. The pane id is known in
  llm-pane-border. Pass it in (an optional 4th arg) or append `⎇×N` there. Count = claude
  worktrees with `lazyLlmPane == <pane id>` whose directory exists: one
  `git config --get-regexp '^branch\..*\.lazyllmpane$'` on the pane dir's repo. Check
  `lazy_llm_git_segment`'s cost notes (GIT_OPTIONAL_LOCKS=0, it runs on every border refresh).
- **nvim**: `nvim-llm-send-plugin/.config/nvim/lua/lazy_llm_worktree.lua`: `M.visible_pane_worktree()`
  (pane's `@lazy_llm_wt`) and `M.toggle()`. Add candidates from the visible AI pane id
  (`@AI_PANE_ID`): claude worktrees whose `lazyLlmPane` is that id (via `git config --get-regexp`).
  Picker via `vim.ui.select` only when there's more than one candidate other than the current side.
- **Making claude worktrees in tests** (no Claude needed): pipe a payload to the hook with the pane
  id set:
  `printf '{"session_id":"s","cwd":"%s","hook_event_name":"WorktreeCreate","name":"agent-x"}' "$repo" | TMUX_PANE=<sandbox pane id> llm-wt claude-hook`
  (stdout = the path). See `tests/scenarios/24-claude-worktrees-unit.sh` for helpers.

## Constraints
- Pane and task worktree display must be unchanged.
- Keep the \x1f row format. Add owner values (`claude:<session>:<pane>`, `claude:orphaned`), don't add columns unless needed.
- The border segment must stay cheap. It's rendered often: one `git config --get-regexp` per repo, not per worktree.
- Test safety (past incidents): every scenario runs only under `tests/test-runner.sh`; `unset TMUX
  TMUX_PANE` and use the runner's private `TMUX_TMPDIR` (a bare tmux call can reach the user's
  live server); `cd` into the sandbox and `export GIT_CEILING_DIRECTORIES=/tmp`; never run git
  with a possibly-empty path.
- Don't change `llm-wt` behavior. If something there is needed, stop and report BLOCKED.
- Don't touch `.agents/TODO/REVIEW-QUEUE.md` (it holds an uncommitted user edit).
- shellcheck: `~/.local/share/mise/installs/shellcheck/0.11.0/shellcheck-v0.11.0/shellcheck` (the
  mise shim is broken). Lua: keep the file's style (tabs).
- The test runner exits 1 even when all pass (known, `test-runner-exit-status`): read the summary lines.

## Verification recipe
- Unit: extend scenario 14 (owner values, `I` action) and 22 or a new scenario for the border count and the llmw candidate list
- Live: in a sandbox tmux server, create claude-kind worktrees via `llm-wt claude-hook` payloads with `TMUX_PANE` set to a sandbox pane; capture the dashboard Worktrees tab and the pane border

## Acceptance Criteria
- [x] Worktrees tab tags claude-kind rows (`⎇` + `claude`), owner resolved to a live pane or orphaned
- [x] `I` on a claude- or pane-kind row runs `llm-wt integrate --remove`, explaining a non-zero exit
- [x] AI pane border / tree row shows `⎇×N` for the pane's live claude-kind worktrees
- [x] `<leader>llmw` picker over main / pane worktree / claude worktrees, unchanged when none
- [x] Help tab + README document the above
- [x] Tests cover the above; existing 14/22 still pass

## Work Report

**Date:** 2026-10-02_20:06
**Executor model:** claude-opus-5-5

### What was done
- **Worktrees tab** (`lazy-llm-lib.sh` `_lazy_llm_emit_worktree_row`, `lazy_llm_gather_worktrees`;
  `llm-dashboard` `render_worktrees_tab`): claude-kind rows (`lazyLlmKind=claude`) get OWNER
  `claude:<tmux session>:<pane>` when `lazyLlmPane` is a live pane, else `claude:orphaned`
  (also when no pane was recorded). Rendered as `⎇ claude <workspace>` / `⎇ claude orphaned`.
  Pane and task rows are unchanged (same owner values, same rendering). Enter (adopt) and K
  (`llm-wt close`/`remove`) route claude rows exactly as orphaned pane rows did before.
- **`I`**: new key. `action:worktree-integrate:<path>` runs `llm-wt integrate <path> --remove`;
  on a live pane-kind row (`pane:*`) it's `action:worktree-integrate-keep:<path>` (no `--remove`).
  The outcome goes into the tab header via `_dashboard_flash` (the Worktrees tab now shows the
  flash, wrapped with `fold` to `_dashboard_header_budget`). Non-zero exits are explained by
  the new `lazy_llm_wt_integrate_reason` (codes 2–7 from llm-wt's header), plus llm-wt's own
  last `llm-wt:` line for exit 1. Header hint updated (50+ tier), Help tab and `--help` updated.
- **`⎇×N`** (`lazy_llm_claude_worktree_owners`, new; `lazy_llm_git_segment` optional 4th arg
  pane id; `llm-pane-border` passes it; `_dashboard_build_rows` tree rows): one
  `git config --get-regexp '^branch\..*\.lazyllm(kind|pane)$'` per repo, then one
  `git for-each-ref --format=%(refname:lstrip=2)\t%(worktreepath)` only when some claude branch
  records a pane; a worktree counts only if its directory exists. Off with `@lazy_llm_border_git off`
  (it's part of the git segment). Tree rows: one owners call per unfolded workspace with panes.
- **`<leader>llmw`** (`lazy_llm_worktree.lua`): new `M.visible_ai_pane()`, `M.claude_worktrees(dir, ai)`,
  `M.candidates(name, claude)`. When the visible AI pane owns claude worktrees, candidates are
  main copy, the pane's worktree (if isolated), each claude worktree, minus the buffer's own side;
  one left → opened directly, more → `vim.ui.select`. With none, the old code path runs unchanged.
- **Docs**: README (Worktree dashboard `I`, Claude's worktrees "Seeing them", AI pane border,
  keymap row), Help tab (WORKTREES TAB `I`, `⎇ claude`; ROW TYPES `⎇`, `⎇×N`), `--help`.
- **Fix found by the new live test**: Esc in the adopt prompt, or "keep" in the close dialog,
  closed the whole dashboard (`[[ … ]] && …` as the last command of a `dispatch_action` arm,
  under `set -e`). Converted those two arms (`worktree-pane-cleanup`, `worktree-adopt`) to `if`.

### How it was done
Tests drive the real code in the runner's sandbox: scenario 14 got a sandboxed section (own
`TMUX_TMPDIR`, HOME, `cd` into the sandbox, `GIT_CEILING_DIRECTORIES`, `unset TMUX TMUX_PANE` at the
top of the file) that makes claude worktrees through `llm-wt claude-hook` with `TMUX_PANE` set to
a sandbox pane, checks owner values, then runs the real `llm-dashboard --tab worktrees` (fzf) in a
400-column sandbox pane and drives it with `send-keys`: tags visible, `I` success (commit lands on
main, worktree and branch gone), `I` exit 3 explained, `I` on a live pane worktree (integrated, kept),
`I` on main (exit 2 explained), Enter on a claude row (adopt prompt), K (llm-wt close dialog, cancel
keeps it). New scenario 26 covers the owners helper, the border segment (exact strings, plus a git
shim counting calls: 4 with claude worktrees, 3 without, one `--get-regexp`), `llm-pane-border`,
`--emit-rows` tree rows, deleted/removed worktrees dropping out, the off switch, and the nvim
candidates/picker/direct-open/unchanged paths in headless nvim with stubbed pane lookups.
Live check: a sandbox tmux server with a client attached through `script` at 160×45 showed the
border `… │ main e5cd66c local ⎇×2` and the exit-3 flash wrapped over two header lines.

Results (all via `tests/test-runner.sh`): 11 (12/0), 13 (13/0), 14 (57/0, ran 3× green before
the final helper refactor), 15 (10/0), 16 (18/0), 17 (23/0), 18 (13/0), 22 (129/0), 24 (183/0),
26 (39/0). shellcheck 0.11.0: no new findings in the changed scripts versus HEAD (compared per file);
scenario files only carry the suite-wide `TEST_NAME` SC2034 / trap SC2329 notes.

### Decisions made
- `<session>` in `claude:<session>:<pane>` is the **tmux session name** of the live pane (mirrors
  `pane:<session>:<pane_id>`; `lazyLlmSession` is Claude's session id, not useful for display).
- A claude worktree with no `lazyLlmPane` (made outside tmux), or with a detached-HEAD parent (no
  `lazyLlmBase`), is still a claude row (`claude:orphaned`), keyed off `lazyLlmKind`.
- `I` on a **live** pane-kind row integrates **without** `--remove`: removing would delete the
  directory a running agent is in (K already refuses those rows). Claude rows always get
  `--remove`, per spec §10. Rows that aren't llm-wt worktrees (task, main) still dispatch, and
  llm-wt's exit 2 is shown explained, rather than adding another refusal path.
- Claude ownership also requires `lazyLlmKind=claude` (read in the same `--get-regexp` call).
- The tree row uses the workspace dir (`@lazy_llm_dir`) for the repo; the border uses the pane's
  cwd. Both see the same shared repo config.
- Worktrees tab header: `I:integrate` added to the 50+ tier, `R:refresh` dropped from it to keep its
  length; the 30 tier is unchanged.
- Scenario 15's unbind check matched the exact key list (its comment says it shouldn't); made it a
  prefix match so adding `I` doesn't break it.
- No formatter is configured for this repo (the `shfmt` mise shim has no version and the history
  shows no shfmt use); Lua edited by hand in the file's tab style. No Lua linter available;
  syntax checked by loading in nvim.

### Commits
- `1feb369` Show Claude's worktrees in the dashboard and on the AI pane border
- `4a09545` <leader>llmw: pick among the AI pane's Claude worktrees too

### Files changed
- `llm-send-bin/.local/bin/lazy-llm-lib.sh`
- `lazy-llm-bin/.local/bin/llm-pane-border`
- `lazy-llm-bin/.local/bin/llm-dashboard`
- `nvim-llm-send-plugin/.config/nvim/lua/lazy_llm_worktree.lua`
- `README.md`
- `tests/scenarios/14-worktree-bridge-tab-unit.sh`, `tests/scenarios/15-dashboard-help-tab-unit.sh`,
  `tests/scenarios/26-claude-worktrees-ui-unit.sh` (new)

### Sources Consulted
- Project `CLAUDE.md` (dev-env), `CONTRIBUTING.md`, `tests/README.md`; no `.claude/standards.yaml`
  in lazy-llm.
- Specs: `specs/claude-subagent-worktrees.md` §1–3, §10–12; `specs/worktree-concurrency-mode.md` §9, §10, §12.
- `llm-wt` header (exit codes), `claude_create`, `cmd_integrate`, `cmd_close`, `cmd_remove`, `load_ctx`.
- git docs (from memory, verified by the tests): `for-each-ref` `%(worktreepath)`, `%(refname:lstrip=2)`;
  `git config --get-regexp` lowercases section/key but keeps the subsection (branch name).

### Follow-up
- **The Worktrees tab's owner column is past the visible width at common popup sizes.** The list
  column is ~45% of the popup (beside the preview), and the columns before the owner already
  take ~87 characters, so `⎇ claude …`, like the existing pane `⎇ <workspace>` tag, is clipped
  unless the terminal is very wide (seen at 160 columns: even ahead/behind is cut). The tag is in
  the row data and visible when wide (the test uses 400 columns). Fixing it means changing the
  shared row layout (owner before the path, or a narrower path column), which the brief's
  "pane and task display unchanged" ruled out here. Worth a task.
- Same `set -e` hazard in the Saved tab's `dispatch_action` arms: `[[ "$confirm" == "yes" ]] && …`
  (saved-forget-snapshot and saved-forget) and `[[ -n "$sname" ]] && tmux switch-client …` end their
  arms, so a "no" or an empty name closes the dashboard. Not touched (outside this task).
- Pane id reuse: `lazyLlmPane` is a tmux pane id (`%N`), reused after a tmux server restart, so a
  leftover claude worktree from an earlier server can be shown as owned by an unrelated new pane
  (Worktrees tab owner, `⎇×N`, llmw candidates). A pid or start-time guard like the model/unread
  markers use would need llm-wt to record more, which this task couldn't change.

## Orchestrator notes (before verification)

- Executor follow-up 1 (owner tags past the visible edge) fixed by the orchestrator in the commit
  after `4a09545`: llm-wt rows show `⎇ claude <name>` / `⎇ pane <name>` in the path column.
  Checked by rendering the real dashboard in a sandbox tmux at a 65-column split: all three tags
  visible. Scenarios 14, 26, 15 and 11 pass.
- Follow-ups 2 and 3 filed: `saved-tab-close-on-no`, `claude-worktree-pane-id-reuse` (backlog).

## Verify Plan
- [ ] Tests: `tests/test-runner.sh` for 14, 26, 15, 11, 13, 16, 17, 18, 22, 24; read the Passed/Failed lines (runner exits 1 regardless)
- [ ] Static: shellcheck 0.11.0 on `lazy-llm-lib.sh`, `llm-dashboard`, `llm-pane-border`, findings at HEAD vs `5a0867e` (pre-task); scenario files
- [ ] AC1 code: `_lazy_llm_emit_worktree_row` (lib ~l.642–659): claude owner from `lazyLlmPane` matched against pane ids, `claude:orphaned` otherwise; pane/task branch unchanged; `gather_worktrees` now lists untagged panes too (check the pane lookup `$1 == w` can't match an untagged pane)
- [ ] AC1 live: real dashboard in a sandbox tmux (`mktemp -d /tmp/lzv.XXXX`), detached at 400/160/100 columns and with an attached client at 160x45: `⎇ claude <name>`, `⎇ pane <name>` in the path column (87a5d8c), task rows unchanged, owner column
- [ ] AC2 `I` safety: it must never remove a worktree a live pane is in. Inspect the routing (`render_worktrees_tab` `I)` arm, only `pane:*` gets `-keep`), then repro: a Claude worktree adopted into a pane (Enter → `llm-add -w`, i.e. `@lazy_llm_wt` set on a live pane), press `I` and `K`
- [ ] AC2 messages: every exit path's flash is accurate: 0 (integrated / nothing to integrate, removed / kept), 2 (task worktree, main), 3, and 1 from `integrate` succeeding but `--remove` refusing (untracked file in the worktree; `require_clean` only warns on untracked, `cmd_remove` refuses them)
- [ ] AC2 task rows: `I` on a plain `git worktree add` worktree changes nothing (llm-wt `load_ctx` dies 2 before any git write)
- [ ] AC3 border: `lazy_llm_claude_worktree_owners` / `lazy_llm_git_segment` 4th arg: exact strings, deleted dir stops counting, no output outside a repo, cost (git calls per refresh, timing with vs without), staleness (computed fresh per border render)
- [ ] AC3 tree row: `_dashboard_build_rows` per-workspace `local -A claude_n=()` resets per workspace in the loop (no count leaking between workspaces)
- [ ] AC4 nvim: `M.toggle` takes the old path unchanged when `M.claude_worktrees` is empty (code diff + scenario 26 Test 4)
- [ ] Refactor: the `worktree-pane-cleanup` / `worktree-adopt` arms (`&&` → `if`): confirm the old form closed the dashboard under `set -euo pipefail`, and drive Keep in the close dialog and Esc in the adopt prompt live
- [ ] AC5 docs: Help tab (render it live), README, `--help`
- [ ] Claim audit: Follow-ups 2 and 3 filed (`saved-tab-close-on-no`, `claude-worktree-pane-id-reuse`); Follow-up 1 fixed by 87a5d8c (check it visually)

## Verify Report

**Date:** 2026-10-02 · **Verifier:** claude-opus-5-5 (fresh context) · Reviewed diffs `1feb369`, `4a09545`, `87a5d8c`.
Sandbox repro scripts were run from the session scratchpad: private `TMUX_TMPDIR=/tmp/lzv.XXXX/t`, `TMUX`/`TMUX_PANE` unset, sandbox `HOME` with symlinks to this checkout's bins, `cd` into the sandbox, `GIT_CEILING_DIRECTORIES=/tmp`, `LC_ALL=C.UTF-8`. Nothing ran against the user's server or checkout.

- [x] **Tests**: all pass. 14: 57/0 · 26: 39/0 · 15: 10/0 · 11: 12/0 · 13: 13/0 · 16: 18/0 · 17: 23/0 · 18: 13/0 · 22: 129/0 · 24: 183/0.
- [x] **Static**: shellcheck finds nothing new in the 3 scripts compared with `5a0867e` (diffs of sorted findings are empty). Scenario files show only the suite-wide SC1091/SC2034/SC2329 notes.
- [x] **AC1 code**: correct. `$1 == w` uses a non-empty `path`, so an untagged pane (empty `$1`) can't match, and pane/task owners come out the same as before.
- [x] **AC1 live**: with an attached client at 160x45, the header reads `/:search enter:open n:new g:lazygit I:integrate K:cleanup`. Rows read `⎇ claude agent-keep`, `⎇ claude agent-x`, `⎇ pane pw`, `⎇ pane pworph`, and task rows show their full paths as before. At 100 columns the tags are still visible. (Detached sessions show no header hint: no client width, which predates this task.)
- [ ] **AC2 `I` safety: FAIL (1)**: see Failure 1. `I` deletes a worktree a live pane is in, and `K` offers to remove it.
- [ ] **AC2 messages: FAIL (2)**: see Failure 2. Exit 1 says "not integrated" after the commits have landed. These are accurate (seen live): 0 removed (`lazy/agent-live: integrated into main; worktree removed`), 0 nothing to integrate (`lazy/pworph: nothing to integrate: … ; worktree removed`), 0 kept (`lazy/pw: … worktree kept (its pane is open)`), 3 (`not integrated (exit 3): the worktree has uncommitted changes…`, wrapped over 2 header lines at 160 cols), 2 on task/main (`feat not integrated (exit 2): not a pane or Claude worktree…`).
- [x] **AC2 task rows**: `I` on `git worktree add -b feat` showed exit 2. The worktree still exists, its HEAD is unchanged and main is unchanged. `load_ctx` dies before any write. It does run llm-wt on the row; it doesn't change anything.
- [x] **AC3 border**: `1ws │ cws - claude ? │ main 9083d4c local ⎇×3`, and `⎇×2` after `rm -rf` of one worktree dir. Outside a repo the output is empty (the early `return 0` comes before the count). Cost: one `config --get-regexp`, plus one `for-each-ref` only when some Claude branch records a pane (scenario 26's git shim counts 4 calls vs 3). Timing for 30 renders: 0.204s with a pane id vs 0.092s without, about +3.7 ms per border render on a small repo. Staleness: recomputed on every `#()` render, so it lags by at most tmux's refresh interval. Pane-id reuse is filed (`claude-worktree-pane-id-reuse`).
- [x] **AC3 tree row**: `local -A claude_n=()` inside the loop resets on each pass (checked: `a 1 / b 1`).
- [x] **AC4 nvim**: with `#claude == 0`, `M.toggle` falls through to the old code. The only differences are that `cwd` is computed earlier (same value) and there is one extra tmux and git call. Scenario 26 covers the unchanged path, the picker, direct open, cancel, and cursor kept.
- [x] **Refactor**: the old form did close the dashboard: `bash -c 'set -euo pipefail; f(){ case x in x) [[ a == b ]] && echo hi;; esac; }; f; echo alive'` → rc=1, no "alive". New form, live: K on a clean Claude row → dialog → **Keep** → dashboard stays and the worktree is kept. Enter → adopt prompt → **Esc** → dashboard stays. The `if` arms are equivalent otherwise.
- [x] **AC5 docs**: the rendered Help tab shows `⎇ claude: add a pane in it`, `I ⎇: integrate into its base (llm-wt), then remove it; kept while its pane is open`, `⎇ claude a Claude subagent's worktree`, and the ROW TYPES `⎇`, `⎇×N`. README and `--help` are updated. Note the docs' "kept while its pane is open" is false for an adopted Claude worktree (Failure 1).
- [x] **Claim audit**: Follow-ups 2 and 3 are filed (`backlog/saved-tab-close-on-no.md`, `backlog/claude-worktree-pane-id-reuse.md`, both in INDEX). Follow-up 1 is fixed by 87a5d8c (tags seen at 160/100 cols). No checked criterion is contradicted by the report's notes, except AC2's "kept while its pane is open" claim (Failure 1).

### Failure 1: `I` deletes, and `K` offers to delete, a Claude worktree a live pane runs in
After **Enter** on a `⎇ claude` row (the documented adopt flow: `llm-add -t <tool> -w <path>`, which sets the new pane's `@lazy_llm_wt`), the row's owner is still computed only from `lazyLlmPane`. It shows `claude:<s>:<creator pane>` (or `claude:orphaned` if the creator is gone), never `pane:<s>:<adopting pane>`. Every live-pane guard keys on `pane:*`, so `I` dispatches `worktree-integrate` (with `--remove`) and `K` dispatches `worktree-pane-cleanup` (llm-wt close → `remove --force`). Before this task, the same adopted worktree had `lazyLlmBase` and so showed `pane:*`: `K` was refused as busy.
- Repro (sandbox): `R` repo; `P` = sandbox pane; `WA=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"WorktreeCreate","name":"agent-adopt"}' "$R" | TMUX_PANE=$P llm-wt claude-hook)`; commit a file in `$WA`; `P2=$(tmux split-window -t $P -c "$WA" -P -F '#{pane_id}' 'exec sleep 600'); tmux set-option -p -t $P2 @lazy_llm_wt "$WA"`. Then `lazy_llm_gather_worktrees` owner = `claude:cws:%0` (`claude:orphaned` when the creator pane is `%9999`). Open `llm-dashboard --tab worktrees` and press `K` on the row: `llm-wt close`'s "Closing the last pane in worktree…" remove dialog opens. Press `I`: the flash reads `⎇ lazy/agent-adopt: integrated into main; worktree removed`, the directory is gone, and `/proc/<P2 pid>/cwd -> …/.worktrees/.claude/agent-adopt (deleted)`.
- Expected: a Claude worktree that a live pane's `@lazy_llm_wt` points at gets the live-pane treatment: `I` → integrate-keep, `K` → busy (and Enter → go to its pane). For example, check `$1 == path` in `wt_panes` before (or as well as) the `lazyLlmPane` lookup in `_lazy_llm_emit_worktree_row` (`lazy-llm-lib.sh` ~l.646–653), or give the dashboard a separate "occupied" signal.
- Not covered by tests: scenario 14 adopts only up to the prompt (Esc), and never `I`/`K` after an adoption.

### Failure 2: exit 1 after a successful integrate is reported as "not integrated"
`llm-wt integrate --remove` integrates, then `cmd_remove` refuses (for example an untracked file, which `require_clean` only warns about) and exits 1. The dashboard shows `⎇ lazy/agent-untracked not integrated (exit 1): llm-wt integrate failed — …/agent-untracked has work that would be lost, or a rebase in progr…`, but `git log main` shows `untracked-case work` landed. The user is told the work didn't land when it did, and the advice in the message ("integrate it with llm-wt integrate") is circular.
- Repro (sandbox): a Claude worktree `WB` with one commit plus `printf junk > "$WB/scratch.log"` (untracked); press `I` on its row. Observed: flash as above, `main` contains the commit, and the worktree still exists. Expected: something like `integrated into main; worktree NOT removed: <reason>` (detect `integrated into`/`nothing to integrate` in `$out`, or that the branch is now an ancestor of base, before choosing the "not integrated" wording). Code: `llm-dashboard` `dispatch_action` `action:worktree-integrate:*` arm (~l.1400–1424). The same arm needs the exit-code table, which reads `1` as a generic failure.

### Observations (not failures)
- A Claude worktree whose directory was deleted by hand (still listed by `git worktree list`) renders as a task row with its full path, because `git -C <missing>` reads no config. `I` on it then says "not a pane or Claude worktree". Pane worktrees did the same before this task.
- `I` on `claude:<s>:<p>` (creator session live) removes the worktree even if that subagent is still running between commits. The spec (§10) asks for `--remove`; uncommitted work is protected by exit 3. Worth knowing.

VERDICT: fail (2 items)

## Rework (round 1)

**Date:** 2026-10-02_20:30

Both verifier failures fixed by the orchestrator in `adf088e`, with regression tests in scenario
14 (63/63). The pre-fix code fails exactly the 5 new assertions, including "the live pane's
directory still exists".
1. Adopted Claude worktree: `_lazy_llm_emit_worktree_row` checks for a live pane whose
   `@lazy_llm_wt` is the path first, for both kinds → `pane:<s>:<p>` (K busy, I keeps it).
2. Landed-but-kept: `I` runs `llm-wt integrate`, then `llm-wt remove` separately. A refused
   removal reads "integrated into main; worktree NOT removed: <reason>". The outcome line skips
   `llm-wt:` warnings, which came first and were shown as the outcome.
Full suite: 26/26.

## Verify Report (round 2)

**Date:** 2026-10-02_20:36 · **Verifier:** claude-opus-5-5 (fresh context) · Reviewed `adf088e` against `87a5d8c`, plus llm-wt `cmd_integrate`/`cmd_remove`/`integrate_into_base`.
Sandbox only: `TMUX`/`TMUX_PANE` unset, private `TMUX_TMPDIR=/tmp/lzv.XXXX/t`, sandbox `HOME` symlinked to this checkout's bins, `cd` into the sandbox, `GIT_CEILING_DIRECTORIES=/tmp`. Scripts are in the session scratchpad: `repro.sh` and `repro3.sh` (new: the round-1 cases plus every `I` exit path, run with an attached client at 160x45). Captures are in `out-r2/`.

- [x] **Round-1 Failure 1 (adopted Claude worktree): fixed.** A Claude worktree created by pane `%0` and adopted by `%1` (with `@lazy_llm_wt` set) has owner `pane:cws:%1`. One whose creator is gone (`%9999`) and that `%2` adopted has owner `pane:cws:%2`. Live results: **K** shows "That worktree's pane is still open — …" on the client status line and the dashboard stays open. **Enter** gives `action:switch` to its pane (no adopt prompt). **I** shows `⎇ lazy/agent-adopt: integrated into main; worktree kept (its pane is open)`, the directory still exists, `/proc/<pid>/cwd` is intact, and `adopt work` is on main.
- [x] **Round-1 Failure 2 (landed but kept): fixed.** A commit plus an untracked file shows `⎇ lazy/agent-untracked: integrated into main; worktree NOT removed: …/agent-untracked has work that would be lost, or a rebase in progress (llm-wt status …): …`. `untr work` is on main, and the worktree and branch are kept. The tail of llm-wt's message still says "integrate it with llm-wt integrate", but the headline is now accurate.
- [x] **Owner change, side effects.** Pane worktrees are unchanged: live gives `pane:cws:%2`, unadopted gives `orphaned`. A task worktree and main give `""`. Claude rows that aren't adopted give `claude:cws:%0` or `claude:orphaned`. The new `awk` runs only for `kind==claude || base` and carries `$1 != ""`, so an untagged pane can't match. For a Claude worktree made by A and adopted by B: B owns it in the tab; A's border still counts it (`main … local ⎇×4`, which includes agent-adopt); B's border shows its own git segment `⎇ agent-adopt→main … ↑1`. Rows are still 8 columns (scenario 14). **But see Failure 1 below (the tag).**
- [x] **Two-call integrate/remove, every exit path (live).** The two calls are equivalent to `integrate --remove`, since `cmd_integrate` is `integrate_into_base; cmd_remove "$WT"`.
  - rc 0, removal allowed: `lazy/agent-clean: integrated into main; worktree removed` (directory and branch gone). The orphaned pane worktree gives `lazy/pworph: integrated into main; worktree removed`.
  - rc 0 + removal refused: two cases. The untracked case is above. Untracked-only with no commits gives `nothing to integrate: lazy/agent-warnonly has no commits beyond main; worktree NOT removed: … has work that would be lost …`, and the worktree is kept.
  - rc 0 on a live pane (`-keep`): `remove` is never called. The live pane worktree with untracked files gives `lazy/pw: integrated into main; worktree kept (its pane is open)`, and so does the adopted Claude worktree above. Both directories exist.
  - rc≠0: `remove` is never called. Exit 3 gives `lazy/agent-dirty not integrated (exit 3): the worktree has uncommitted changes…`, and the worktree is kept. Exit 2 on a task worktree gives `feat not integrated (exit 2): not a pane or Claude worktree…`, and the worktree is kept with HEAD unchanged.
  - The dashboard is still open after all of these.
- [x] **Outcome line skips `llm-wt:` warnings.** Every untracked case above shows the outcome ("integrated into main" / "nothing to integrate"), not the `llm-wt: 1 untracked file(s)…` warning that comes first. With a rebase needed (main moved, plus an untracked file), the direct `llm-wt integrate` output is `llm-wt: 1 untracked…` / `integrated into main:` / `afbcf01 w`, and the picked line is `integrated into main:`. `git rebase --quiet` adds nothing.
- [x] **Tests**: 14: 63/0 · 26: 39/0 · 13: 13/0 · 11: 12/0 · 15: 10/0 · 22: 129/0 · 24: 183/0.
- [x] **Static**: shellcheck 0.11.0 on `lazy-llm-lib.sh` (10 vs 10) and `llm-dashboard` (17 vs 17) against `87a5d8c`: identical findings. Scenario 14 shows only the suite-wide SC1091/SC2034/SC2329 notes.
- [x] **Round-1 items, no regression**: border `⎇×N` (4, then 3 after `rm -rf` of one dir; empty outside a repo; 30 renders take 0.206s vs 0.096s, as in round 1). Tags at 400/160/100 columns. Exit-3 flash wraps. K→Keep and Enter→Esc keep the dashboard open (scenario 14). Help text untouched by `adf088e`.
- [ ] **Failure 1 (new, caused by the fix): an adopted Claude worktree loses its `⎇ claude` tag**

### Failure 1: an adopted Claude-kind worktree is tagged `⎇ pane`, not `⎇ claude`
AC1 and spec §10 say a claude-kind row "shows `⎇` and a `claude` tag". The render picks the tag from the owner (`llm-dashboard` ~l.722–740: `pane:* | orphaned) tag="⎇ pane"`, and the owner column `pane:*` → `⎇ <ws>`). Since `adf088e`, an adopted Claude worktree's owner is `pane:<s>:<p>`, so the row reads `⎇ pane agent-adopt … ⎇ cws`, with "claude" nowhere on it. It is still `lazyLlmKind=claude`, and the creator pane's border still counts it among its Claude worktrees (`⎇×4` while the tab shows 3 `⎇ claude` rows). The guards themselves are right (K busy, I keeps it). Only the kind display is wrong.
- Repro (sandbox, `repro3.sh` section A): `WA=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"WorktreeCreate","name":"agent-adopt"}' "$R" | TMUX_PANE=$P llm-wt claude-hook)`; `P2=$(tmux split-window -t $P -c "$WA" -P -F '#{pane_id}' 'exec sleep 600'); tmux set-option -p -t $P2 @lazy_llm_wt "$WA"`; `llm-dashboard --tab worktrees`. Observed row: `▌ ⎇ pane agent-adopt   lazy/agent-adopt … ⎇ cws`. Expected: `⎇ claude agent-adopt …`, with the live-pane guards kept.
- Likely fix: keep the guards keyed on the live pane, but carry the kind to the render. For example, a distinct owner value such as `claude-pane:<s>:<p>`, with the K/I/Enter arms matching `pane:*|claude-pane:*`. Or pick the tag from the branch's `lazyLlmKind` (or the `.worktrees/.claude/` path) instead of from the owner. Add a scenario 14 assertion on the adopted row's tag.

### Observations (not failures)
- In a **detached** sandbox (no client), `K` on any `pane:*` row closes the dashboard: `tmux display-message` fails with no client, and the `worktree-pane-busy` arm ends on it under `set -e`. This was already true for pane worktrees before this task, and it doesn't happen with a real client (the popup). Seen when `repro.sh` (detached) was rerun; `repro3.sh` with a client is fine.
- The NOT-removed flash reuses `cmd_remove`'s full message, which ends with "integrate it with llm-wt integrate, or use llm-wt remove --force". That is 5–6 header lines at 160 columns and slightly contradicts "integrated into main". Cosmetic.

VERDICT: fail (1 item)

## Rework (round 2) and acceptance

**Date:** 2026-10-02_20:42

Round 2 confirmed both round-1 fixes on every exit path, and found that the fix made an adopted
Claude worktree's row read `⎇ pane`. Fixed in `544aaf6`: the tag follows `lazyLlmKind`, not the owner.
The verifier's own suggested fix; scenario 14 asserts it (66/66; the previous dashboard fails
those 3 assertions). Also took its cosmetic note: a refused removal after `I` now reads "worktree
NOT removed: it still has files that aren't committed (llm-wt status <path>)". Checked visually:
a sandbox dashboard shows `⎇ claude agent-adopted`, `⎇ claude agent-solo`, `⎇ pane r-wt-1`.
Full suite 26/26. Not sent for a 3rd verify round: label-only change, verifier-proposed, covered
by assertions that fail on the old code.

Deploy: no plugin or stow changes (live symlinks). Pushed with lazy-llm `main`; dev-env pointer
bumped. nvim needs a restart to reload `lazy_llm_worktree.lua`.

## Human Validation

- [ ] With a Claude session that has isolated subagent worktrees open (or kept): open
      `Prefix+S` → Worktrees, and check the `⎇ claude` rows, `I` on one, and the pane border's
      `⎇×N` against what you expect.
- [ ] After restarting nvim, `<leader>llmw` in that workspace: is the picker over the Claude
      worktree copies useful, or noise?
