---
slug: dashboard-help-tab
title: Make dashboard keybinding help persistent (tab or always-visible subframe)
priority: P2
status: in-progress
created: 2026-09-22_04:37
updated: 2026-09-22_05:20
depends-on: [dashboard-tree-view-consolidation]
tags: [ux, discoverability, dashboard]
commits: []
model: sonnet
---

# Make dashboard keybinding help persistent (tab or always-visible subframe)

## Context

`llm-dashboard` already has a `?` → `show_help_overlay` (lines ~490-532 of
`lazy-llm-bin/.local/bin/llm-dashboard`) that opens a **separate, transient** popup
listing every keybinding, dismissed by any keypress. It solves "what does this key do"
once you know to press `?`, but it's not visible by default, and its own existence is
just one more thing to remember. The user asked for either a dedicated help tab or an
always-visible subframe inside the dashboard itself — pick whichever fits better given
what [[dashboard-tree-view-consolidation]] leaves behind (that task may already
reorganize tab numbering/count; read its Work Report before starting this one).

## Design

Two options — choose one, and record the reasoning in the Work Report (don't silently
pick without justifying against the alternative):

**Option A — dedicated Help tab.** Add a tab (e.g. bound to `?` or a number key
consistent with the others) that replaces the current transient overlay with a
tab-switch, using the exact same render/dispatch pattern as Workspaces/Worktrees. Pro:
consistent with existing tab architecture, minimal new mechanism. Con: still has to be
opened deliberately — doesn't solve "I forgot the key exists" any better than today's
`?` overlay, just changes its mechanism.

**Option B — always-visible subframe.** Reserve a thin strip (e.g. bottom 2-3 lines, or
a persistent narrow column) inside every tab showing the current tab's most-used keys at
all times, no keypress needed — closer to what a LazyVim which-key popup gives you
(though ambient rather than triggered). Pro: actually solves "I don't remember the
keybindings" without requiring the user to know a discovery mechanism exists at all.
Con: eats into the already-limited popup real estate (the header row is already tight
per [[dashboard-preview-render-fix]]'s header-truncation finding — check whether that
task's fix already added a second header line that this could piggyback on, to avoid
two independent multi-line-header mechanisms).

Recommendation to weigh during implementation: Option B most directly answers the user's
actual complaint ("it doesn't have the helpful keymap display lazyvim has"), since
LazyVim's which-key is exactly an always-visible/on-hover affordance, not a
separately-triggered help screen the user has to remember exists. Prefer B unless
implementation reveals real estate constraints make it unworkable at the dashboard's
default size, in which case fall back to A with a note explaining why.

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` — `show_help_overlay`, header/prompt
  construction in the merged tree-tab and worktrees-tab render functions, main tab
  dispatch loop
- README.md, docs/USAGE.md — update keybinding documentation to match whichever the
  chosen surface ends up being canonical

## Constraints

- Whichever option is chosen, the full keybinding list from the current
  `show_help_overlay` text must remain reachable somewhere in the dashboard — don't
  regress coverage, just change (or supplement) how it's surfaced.
- Read [[dashboard-tree-view-consolidation]]'s and [[dashboard-preview-render-fix]]'s
  Work Reports before starting — both land first and may change the header/tab
  structure this task builds on.

## Acceptance Criteria

- [ ] Keybinding help is discoverable without the user needing to already know a `?`
      shortcut exists (either via a standing tab or an always-visible subframe)
- [ ] Full keybinding coverage preserved (nothing from the old overlay text silently
      dropped)
- [ ] Chosen approach documented with rationale in the Work Report
- [ ] README.md / docs/USAGE.md reflect the final keybinding-discovery mechanism
- [ ] `tests/test-runner.sh` passes

## Verification recipe

```bash
cd tests && ./test-runner.sh
# Live: open the dashboard, confirm keybinding help is visible/reachable without
# pressing '?' first (if Option B), or confirm the new Help tab is reachable via a
# consistent, documented key (if Option A).
```
