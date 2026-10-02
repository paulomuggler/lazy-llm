---
slug: claude-subagent-worktrees-ui
title: Show Claude's agent worktrees in lazy-llm (Worktrees tab tag + integrate, pane border ⎇×N, llmw picker)
priority: P2
status: pending
created: 2026-10-02_18:25
updated: 2026-10-02_18:25
depends-on: [claude-subagent-worktrees]
tags: [worktree, dashboard, nvim]
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

## Constraints
- Pane and task worktree display must be unchanged.
- Keep the \x1f row format. Add owner values (`claude:<session>:<pane>`, `claude:orphaned`), don't add columns unless needed.
- The border segment must stay cheap. It's rendered often: one `git config --get-regexp` per repo, not per worktree.

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
