---
slug: dashboard-manual-list-reordering
title: Manual reordering of dashboard tree rows (Ctrl+Up/Down), scoped per tree level
priority: P2
status: in-progress
created: 2026-09-23_04:20
updated: 2026-09-23_05:58
depends-on: []
tags: [enhancement, dashboard, ux]
commits: []
model: opus
owner: homelab-zrh-dev-2339310
---

# Manual reordering of dashboard tree rows

## Context

Direct request, after the stable-sort fix landed: now that the tree's list order
is stable (no more auto-sorting the active workspace to the top — see
[[dashboard-layout-status-redesign]]'s Round 7), the user wants to be able to
manually reorder rows — e.g. drag a frequently-used workspace to the top, or
reorder panes within a workspace to match how they think about the project.

**Key design point, corrected mid-conversation**: this does NOT require reordering
tmux's own session list, and does not need any tmux "reorder sessions" primitive
(tmux doesn't have one). The dashboard's displayed row order is already decoupled
from `tmux list-sessions`'s own order — it's just derived from it today. Manual
reordering only needs the dashboard to maintain its OWN ordering preference and
apply it as a sort step over the gathered data, independent of whatever order tmux
itself considers its sessions in.

**Scoping requirement, explicit**: this is a TREE, not a flat list — reordering
must stay bound to its level. A workspace row can only reorder among sibling
workspace rows; a pane row can only reorder among its own workspace's sibling
panes, never across workspaces.

## Proposed design — UPDATED: dashboard-reload-avoid-full-redraw has now
landed (commits `d451421`, `121dcbf`, `52c91ff`, all on `main`). That task
built exactly the "no-full-relaunch" mechanism this task's own Constraints
section anticipated wanting to reuse — it is no longer a maybe, it is the
established pattern in the file today, and this task MUST follow it rather
than reintroduce `execute-silent()+reload()`, `--track --id-nth`, or
exit+relaunch (all of which were tried for fold/unfold and superseded — see
the extensive comments on `render_sessions_tab`'s `z` bind and on
`--fold-transform` in `lazy-llm-bin/.local/bin/llm-dashboard` for the full
history of why each alternative was dropped). Concretely, reordering's
keybinding should mirror `z`'s own wiring, not the `print(KEY)+accept` style
other action keys (K, r, R, a, ], [, ?) still use:

- **The established reload pattern (copy this shape exactly):** an fzf
  `transform(...)` bind action invokes `$_dashboard_self` (absolute path,
  already resolved at top of file, ~line 56) with a new out-of-process CLI
  flag (parallel to `--fold-transform`/`--emit-rows`, CLI-parsed at the
  bottom of the file, ~lines 1077-1141). That flag's handler: (1) mutates the
  persisted order state, (2) calls `_dashboard_build_rows` (the single
  shared row-building function, ~line 192 — do NOT reintroduce a second
  inline row-builder) to get the new `REPLY_ROWS`, (3) computes which row the
  MOVED item now occupies in the new list (same technique
  `--fold-transform` already uses: `awk -F'\t' -v id=... '$1==id{print NR;
  exit}'` against `REPLY_ROWS`, ~lines 1117-1124), (4) prints
  `reload-sync($_dashboard_self --emit-rows)+pos(N)` to stdout and exits 0.
  Use `reload-sync`, not `reload` — confirmed live in the prior task that a
  plain async `reload()` races with a chained `pos(N)` and silently discards
  it (see `--fold-transform`'s own comment, ~lines 1126-1138, for the
  verified root cause). `--track`/`--id-nth` were tried and dropped for
  fold/unfold for the same reason they're not viable here: the moved row's
  own id-based position is exactly what changes on a reorder, and `--track`
  has no fallback when the tracked id's ROW MOVES rather than vanishes
  cleanly — same class of problem as the fold vanish-case bug, don't
  re-litigate it, use explicit `pos(N)` like `--fold-transform` does.
- **`_dashboard_build_rows` is where order gets applied**, not
  `render_sessions_tab` (which now just calls it). Workspace order: after
  `data=$(lazy_llm_gather_sessions)` (~line 195), reorder `data`'s rows
  according to the persisted custom-order list before the `while IFS=$'\t'
  read ...` loop that builds `ws:`/`pane:` rows — workspaces not yet in the
  custom order list are appended in `lazy_llm_gather_sessions`'s own natural
  order (never silently dropped). Pane order: within the per-workspace block,
  `pane_arr`/`tool_arr` (built ~lines 224-239 from `lazy_llm_read_multi_state_for`)
  are already in the on-disk `@AI_PANES`/`@AI_TOOLS` order — reordering a
  pane means swapping two adjacent entries in those actual tmux options (see
  below), not just re-sorting the in-memory arrays for display, so the
  persisted order and the displayed order can't drift apart across dashboard
  reopens.
- **Workspace-level order storage**: a new persistent, server-scoped tmux
  option (e.g. `@lazy_llm_ws_order`, `tmux set-option -s` / `tmux show-option
  -s -v` — confirmed live and via `man tmux`'s OPTIONS section that `-s`
  server-scope works for a `@`-prefixed user option, no `-t target` needed)
  holding a delimited list of workspace names in custom order. This is
  correctly server-scoped, NOT session-scoped like fold state
  (`@lazy_llm_collapsed`, added by dashboard-reload-avoid-full-redraw) —
  fold is a property of one workspace, but relative ORDER is inherently a
  relationship across all workspaces, which is why it needs a scope broader
  than any single session.
- **Pane-level order**: no new storage needed — a workspace's pane order is
  already `@AI_PANES`/`@AI_TOOLS`/`@AI_PANE_NAMES` (parallel arrays, window-scoped).
  Reordering a pane row just swaps two adjacent entries across all three arrays
  and re-sets the options — same pattern already used by
  `dispatch_action`'s `action:rename-pane:*` (~lines 750-789: read via
  `lazy_llm_read_multi_state_for`, mutate the bash array, `tmux set-option -w`
  the joined result back).
- **Keybinding**: Ctrl+Up / Ctrl+Down. Confirmed free in fzf's default bindings
  (not used by up-match/down-match, which are plain Up/Down and Ctrl-N/Ctrl-P).
  Bind directly to `transform(...)` (see above), and add to the `/`-search
  unbind/rebind key lists (~lines 487-488 currently:
  `--bind='/:unbind(1,2,K,r,R,z,a,],[,?)+show-input+enable-search'` /
  `--bind='tab:clear-query+hide-input+rebind(1,2,K,r,R,z,a,],[,?)'`) —
  `z` is already precedent for a `transform(...)`-bound key living in that
  same unbind/rebind list alongside the `print(KEY)+accept` ones, so the new
  keys slot in the same way.
- **Dispatch**: the out-of-process CLI handler (not `dispatch_action`, which
  only runs for the `print(KEY)+accept` action-return path that `z` and now
  reordering both bypass) determines whether the target row is a workspace or
  a pane (reuse `_dashboard_ws_from_id`, ~line 121, plus its own pane-index
  parsing for the pane case), finds its sibling list at that level, swaps it
  with its neighbor (bounds-check: no-op, not an error, at either end of the
  sibling list), persists (tmux option), and returns the
  `reload-sync(...)+pos(N)` chain per the pattern above.

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` — `_dashboard_build_rows` (~line
  192, order application point), `render_sessions_tab`'s fzf call (~line
  469, the `--bind` list ~481-490 and the `/`-search unbind/rebind lists
  ~487-488), `_dashboard_ws_from_id` (~line 121), `--fold-transform`/
  `--emit-rows` CLI handling (~lines 1077-1141 — the pattern to copy for
  the new reorder CLI mode(s)), `dispatch_action`'s `action:rename-pane:*`
  (~lines 750-789, the pane-array swap-and-persist pattern to copy)
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — `lazy_llm_gather_sessions`
  (workspace natural-order source), `lazy_llm_read_collapsed`/
  `lazy_llm_toggle_collapsed` (~line 540-555, the session-scoped
  read/toggle-helper pattern to mirror for a server-scoped
  read/reorder-helper pair), `lazy_llm_read_multi_state_for` (pane-array
  reader)

## Read first

- The whole of `dashboard-reload-avoid-full-redraw`'s Work Report (in
  `.agents/TODO/done/dashboard-reload-avoid-full-redraw.md` after lint
  archival, or `git show 121dcbf` for the final state) — full design
  rationale and a documented rework round (a cursor-fallback bug, and a
  second latent `load:pos(N)` re-fire bug) that this task's own
  `pos(N)`-computation and `+unbind(load)` handling must not regress or
  reintroduce. The comments inline in `llm-dashboard` around `z`'s bind and
  `--fold-transform` are the condensed version of the same history.
- `/home/paulomuggler/Projects/dev-env/dotfiles/claude/dot-claude/coding-standards/frameworks/tmux-fzf.md`
  (parent dev-env repo, no local copy in this submodule) — same reasons as
  the reload task: `set -e` + bare `var=$(cmd)` hazard, `load` vs `start`
  event semantics, `--nth`/`--with-nth` field-index interaction, `unbind`/
  `rebind` ordering.

## Constraints

- Reordering must never cross tree levels (a workspace can't be inserted between
  a different workspace's panes, etc.)
- A workspace absent from the custom order option (new, never explicitly moved)
  must still render, appended in natural order — never silently hidden
- MUST use the same `transform(...)` + out-of-process CLI-flag +
  `reload-sync(...)+pos(N)` mechanism `dashboard-reload-avoid-full-redraw`
  established for `z` (fold/unfold) — see the updated Proposed design above
  for the exact shape. Do not reintroduce `execute-silent()+reload()`,
  `--track --id-nth`, or exit+relaunch (`print(KEY)+accept`) for the
  reorder keys; all three were tried and superseded for this exact class of
  in-place-list-mutation-without-flicker problem, for reasons documented
  inline in `llm-dashboard`.
- Verify cursor-after-reorder behavior live with ANSI-aware `capture-pane
  -e`, the same discipline both rounds of the reload task used — don't trust
  a computed `pos(N)` value without seeing it actually land on the moved
  row in a real render.
- Workspace order storage must be server-scoped (`tmux set-option -s`), not
  session- or window-scoped — verified live in this task's own brief
  preparation that `-s` works for a `@`-prefixed user option with no
  `-t target` needed.

## Acceptance Criteria

- [ ] Ctrl+Up/Down on a workspace row reorders among workspace rows only,
      persists across dashboard reopens
- [ ] Ctrl+Up/Down on a pane row reorders among that workspace's own panes only,
      persists (via `@AI_PANES` et al.)
- [ ] A newly created workspace/pane not yet in any custom order still appears,
      in natural order, without needing an explicit "add to order" step
- [ ] Fold/unfold (`z`) and search (`/`) still work correctly after this
      change — no regression to the existing `transform(...)`-based reload
      mechanism or the unbind/rebind key lists
- [ ] No fzf relaunch on a reorder action (verified via process
      inspection — same fzf PID + `ps -o lstart` across repeated
      Ctrl+Up/Down presses, same method as dashboard-reload-avoid-full-redraw)
- [ ] Verified live against a disposable, isolated multi-workspace,
      multi-pane tmux session/server before shipping — ANSI-aware
      `capture-pane -e` for cursor-after-reorder placement, `tmux
      show-option` for persisted order state, not just code inspection
