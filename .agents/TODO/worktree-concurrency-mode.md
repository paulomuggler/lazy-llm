---
slug: worktree-concurrency-mode
title: Optional per-pane worktree isolation for concurrent AI panes in one workspace
priority: P1
status: in-progress
created: 2026-09-23_04:20
updated: 2026-09-28_01:10
depends-on: []
tags: [worktree, concurrency, dashboard, design]
spec: specs/worktree-concurrency-mode.md
commits: []
---

# Optional per-pane worktree isolation for concurrent AI panes

## Context

Direct request, explicitly NOT to be implemented yet — "we won't do anything
about it now, except pull any related tasks out of backlog and give them
priority." No existing task actually covers this exact idea (checked: every
worktree-tagged task in this repo's `.agents/TODO/` — `worktree-per-task-primitive`,
`worktree-bridge-tab`, both in `archive/done/` — is about a worktree PER TASK/branch,
i.e. a whole separate `lazy-llm` workspace for a separate piece of work. This is a
different, narrower problem: **multiple AI panes added to the SAME already-open
workspace currently share one git working tree**, so if two concurrent agents in
that workspace both touch git state (checkout, commit, stage files), they can
collide with each other. The user's framing: "seems we have no choice but to
fully embrace worktrees here" for that specific problem — each additional AI pane
in a workspace getting its own worktree checkout instead of sharing the primary
directory.

**Explicit, unresolved design tension** (the user's own words, this is the actual
open question, not a detail): "most of the time I don't need the added
complexity of dealing with git worktrees for everything; so it should be kind of
like a mode, or an optional thing, idk?" — this must NOT default to giving every
additional pane its own worktree unconditionally. It needs to be opt-in at some
granularity not yet decided.

## Design (2026-09-28): spec revision 2 approved; implementing

Full design: [`specs/worktree-concurrency-mode.md`](specs/worktree-concurrency-mode.md).
Decisions made with the user:

- **Toggle**: opt-in per pane. Dashboard `A` and `llm-add --isolate`; `a` is unchanged.
- **Lifecycle**: the worktree and branch `lazy/<ws>/<tool>-<n>` are created on an isolated add.
  Closing the pane **always asks**, and warns about any work that would be lost.
- **Merging back** is the agent's job: it commits in logical units and runs `llm-wt integrate`
  (rebase in the worktree, then `--ff-only` into the main directory). A Claude skill and
  `SessionStart` context tell the agent it's isolated.
- **Reuse**: `lazy_llm_setup_worktree` / `lazy_llm_cleanup_worktree`, extended. Pane worktrees
  show in the Worktrees tab, tagged by owning pane or as orphaned.
- **Editor**: nvim's cwd never changes. `<leader>llmw` toggles the current buffer between the
  main copy and the visible pane's worktree copy (editable).
- **Untracked files**: link (the default) or copy, set in a gitignore-style `worktree-files`
  config, plus a `worktree-init` hook. Copies are checksummed and reconciled on close.
- **Prerequisite bug found**: the workspace directory is read from the active pane's cwd
  (`gather_sessions`, `llm-add`). With an isolated pane focused, worktree cleanup would kill
  the whole workspace. It must be fixed first (spec §2).

## Original open design questions (resolved above)

- **Toggle granularity**: per-workspace setting (e.g. a dashboard action or
  `lazy-llm` flag "make this workspace's additional panes worktree-isolated")?
  Per-pane-add prompt ("isolate this new pane in its own worktree? y/n")? A
  global default the user sets once and overrides per-case?
- **Worktree lifecycle**: created automatically on `action:pane-add` when the
  mode is on? Branch naming convention for the auto-created worktree (distinct
  from the EXISTING worktree-tab flow, which is user-named and task-oriented,
  not disposable)? Cleaned up on `action:pane-remove`, or left for the user to
  manage via the existing Worktrees tab?
- **Relationship to the existing Worktrees tab / worktree-bridge machinery**:
  should this REUSE `lazy_llm_setup_worktree`/`lazy_llm_gather_worktrees`/
  `lazy_llm_cleanup_worktree` (already built, see `lazy-llm-lib.sh`), or does
  the "ephemeral, pane-scoped" use case need its own, lighter-weight primitive
  that doesn't show up in the task-oriented Worktrees tab at all?
- **What "the pane's own worktree" means for the dashboard tree/status bar**:
  does the tree need to show which panes are worktree-isolated vs sharing the
  primary directory? Does `@AI_PANE_NAMES`/pane-border/status-bar need a marker?
- **Prompt/editor pane implications**: a workspace's nvim/prompt panes currently
  point at the ONE primary directory — if an AI pane gets its own worktree, do
  the OTHER panes (editor, prompt) need any awareness of it, or is this scoped
  purely to where each AI pane's own shell/tool process runs?

## Key Files (for whoever picks this up)

- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — `lazy_llm_setup_worktree`,
  `lazy_llm_gather_worktrees`, `lazy_llm_cleanup_worktree`, `lazy_llm_default_branch`
  (existing worktree primitives to potentially reuse)
- `lazy-llm-bin/.local/bin/llm-dashboard` — `action:pane-add` dispatch (where a
  mode toggle or prompt would likely hook in), `render_worktrees_tab` (existing
  worktree tab, for the "should this show up there" question)
- `lazy-llm-bin/.local/bin/lazy-llm` — workspace/window setup (where per-pane
  directory resolution would need to change if isolation is on)
- `.agents/TODO/archive/done/2026-05-13/worktree-per-task-primitive.md`,
  `.agents/TODO/archive/done/2026-05-13/worktree-bridge-tab.md` — read first,
  for the EXISTING worktree model this needs to sit alongside without confusing
  the two use cases (task-level worktree vs. pane-level concurrency isolation)

## Acceptance Criteria

- [x] Design spec resolving every open question, reviewed by the user (revision 2, 2026-09-28)
- [ ] Explicit non-default: a workspace with no isolation requested behaves exactly as today
      (shared directory, no worktree overhead). The full existing suite passes unchanged.
- [ ] Clear boundary between pane worktrees and task worktrees (spec §1.1, §9)
- [ ] §2 fix: the workspace directory comes from `@lazy_llm_dir`; cleanup can't kill a workspace
- [ ] `llm-wt` status / integrate / sync / create / close, per spec §7
- [ ] `llm-add --isolate` / `--worktree`, bootstrap config + init hook (§4, §5)
- [ ] Close flow with loss warnings, last-pane rule, copy reconciliation (§8)
- [ ] Dashboard: Workspaces `A`, `a` dialog, tree marker, Worktrees tab owner/Enter/K (§3, §9)
- [ ] AI pane border git segment for every AI pane (§12.1)
- [ ] Persist: worktree field, recreate on restore, snapshot-copy semantics (§11)
- [ ] nvim `<leader>llmw` toggle; references relative to the buffer's own git root (§10)
- [ ] Guidance injected via SessionStart only in isolated panes, incl. TODO rules (§6, §6.1)
- [ ] Tests per spec §14; docs updated
