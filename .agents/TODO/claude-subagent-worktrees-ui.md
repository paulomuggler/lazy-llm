---
slug: claude-subagent-worktrees-ui
title: Show Claude's agent worktrees in lazy-llm (Worktrees tab tag + integrate, pane border ⎇×N, llmw picker)
priority: P2
status: in-progress
created: 2026-10-02_18:25
updated: 2026-10-02_20:06
depends-on: [claude-subagent-worktrees]
tags: [worktree, dashboard, nvim]
owner: homelab-zrh-dev-2409537
model: opus
spec: ../specs/claude-subagent-worktrees.md
commits: [1feb369, 4a09545]
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
