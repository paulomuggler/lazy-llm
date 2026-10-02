---
slug: claude-subagent-worktrees-ui
title: Show Claude's agent worktrees in lazy-llm (Worktrees tab tag + integrate, pane border ⎇×N, llmw picker)
priority: P2
status: in-progress
created: 2026-10-02_18:25
updated: 2026-10-02_19:46
depends-on: [claude-subagent-worktrees]
tags: [worktree, dashboard, nvim]
owner: homelab-zrh-dev-2409537
model: opus
spec: ../specs/claude-subagent-worktrees.md
commits: []
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
- [ ] Worktrees tab tags claude-kind rows (`⎇` + `claude`), owner resolved to a live pane or orphaned
- [ ] `I` on a claude- or pane-kind row runs `llm-wt integrate --remove`, explaining a non-zero exit
- [ ] AI pane border / tree row shows `⎇×N` for the pane's live claude-kind worktrees
- [ ] `<leader>llmw` picker over main / pane worktree / claude worktrees, unchanged when none
- [ ] Help tab + README document the above
- [ ] Tests cover the above; existing 14/22 still pass
