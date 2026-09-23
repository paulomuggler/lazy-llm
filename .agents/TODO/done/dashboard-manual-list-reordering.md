---
slug: dashboard-manual-list-reordering
title: Manual reordering of dashboard tree rows (Ctrl+Up/Down), scoped per tree level
priority: P2
status: done
created: 2026-09-23_04:20
updated: 2026-09-23_06:22
depends-on: []
tags: [enhancement, dashboard, ux]
commits: [eeaf8d7, 3125c32, 110a424]
model: opus
human-validation: pending
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

- [x] Ctrl+Up/Down on a workspace row reorders among workspace rows only,
      persists across dashboard reopens
- [x] Ctrl+Up/Down on a pane row reorders among that workspace's own panes only,
      persists (via `@AI_PANES` et al.)
- [x] A newly created workspace/pane not yet in any custom order still appears,
      in natural order, without needing an explicit "add to order" step
- [x] Fold/unfold (`z`) and search (`/`) still work correctly after this
      change — no regression to the existing `transform(...)`-based reload
      mechanism or the unbind/rebind key lists
- [x] No fzf relaunch on a reorder action (verified via process
      inspection — same fzf PID + `ps -o lstart` across repeated
      Ctrl+Up/Down presses, same method as dashboard-reload-avoid-full-redraw)
- [x] Verified live against a disposable, isolated multi-workspace,
      multi-pane tmux session/server before shipping — ANSI-aware
      `capture-pane -e` for cursor-after-reorder placement, `tmux
      show-option` for persisted order state, not just code inspection

## Work Report

**Date:** 2026-09-23_06:15
**Executor model:** opus

### What was done
- Added Ctrl-Up/Ctrl-Down manual reordering to the dashboard's Workspaces
  tree, scoped strictly to each row's own tree level (workspace rows swap
  among workspace siblings, pane rows swap only among their own
  workspace's panes).
- Workspace order persists in a new server-scoped tmux option
  (`@lazy_llm_ws_order`); pane order persists directly in the existing
  `@AI_PANES`/`@AI_TOOLS`/`@AI_PANE_NAMES` window options (no new storage
  needed — their own element order IS the pane order).
- Reused the exact no-full-relaunch mechanism
  `dashboard-reload-avoid-full-redraw` established for `z`: `transform(...)`
  bind → out-of-process `--reorder-transform` CLI mode →
  `reload-sync(...)+pos(N)`.
- Added a new unit test file covering the lib-level order helpers and
  the dashboard's key-wiring shape, and fixed one pre-existing brittle
  test regex that the new unbind-list entries broke.

### How it was done
- `lazy-llm-lib.sh`: added `lazy_llm_read_ws_order`,
  `lazy_llm_apply_ws_order` (applies persisted order to
  `lazy_llm_gather_sessions`'s raw data, appending never-ordered
  workspaces in natural order, skipping stale/dead entries),
  `lazy_llm_move_ws_order` (seeds the order list from natural order on
  first touch, swaps with the sibling neighbor, bounds-checked, persists
  via `tmux set-option -s`), and `lazy_llm_move_pane_order` (swaps two
  adjacent entries across the three parallel pane arrays, bounds-checked,
  keeps `@AI_PANE_IDX` pointed at the same physical pane across the
  swap — same read/mutate/set pattern `action:rename-pane` already uses).
- `llm-dashboard`: `_dashboard_build_rows` now calls
  `lazy_llm_apply_ws_order` right after `lazy_llm_gather_sessions` — the
  one place order is applied, shared by `render_sessions_tab`,
  `--emit-rows`, `--fold-transform` and the new `--reorder-transform`.
  Added `ctrl-up`/`ctrl-down` binds (`transform($_dashboard_self
  --reorder-transform up|down {1})`), added both to the `/`-search
  unbind list and the `tab` rebind list (same list `z` already lives
  in). Added the `--reorder-transform` CLI handler (mirrors
  `--fold-transform`'s shape exactly): dispatches on the row id's
  `ws:`/`pane:` prefix to the matching lib helper, rebuilds rows, then
  computes the moved row's new line number — matching by the full id for
  a workspace row (its id string is position-independent) or by the
  trailing `pane_id` field for a pane row (its id's `<idx0>` segment
  changes across the swap, so the full-id match used by `--fold-transform`
  doesn't apply there) — and prints `reload-sync(...)+pos(N)`.
  Updated the Help tab body, the top-of-file keybinding summary comment,
  and `usage()` to document the new keys.

### Decisions made
- **Order-state overlay precedence**: on every `lazy_llm_move_ws_order`
  call, the working list is rebuilt as persisted-order-first (dropping
  any entries for workspaces that no longer exist) then natural-order
  appended for anything not yet covered — same precedence
  `lazy_llm_apply_ws_order` uses for display, so the two never disagree
  and the persisted list self-prunes dead entries on the next move
  rather than growing forever. Not explicitly specified in the brief;
  chosen to keep `lazy_llm_apply_ws_order` and `lazy_llm_move_ws_order`
  as the same single source of truth for "what order is a workspace in
  right now."
- **Cursor-tracking key differs by row type**: a workspace id string
  (`ws:<name>`) is stable across a reorder, so `--reorder-transform`
  matches on the full id (identical technique to `--fold-transform`). A
  pane id (`pane:<name>:<idx0>:<pane_id>`) encodes its own position in
  `<idx0>`, which changes by definition across a reorder swap — so
  cursor tracking matches on the trailing `pane_id` field instead
  (stable across the swap), with the awk `split()` done in a second
  `-v` variable to avoid conflicting with the outer tab-delimited
  `-F'\t'` used for row splitting. This wasn't spelled out in the
  brief's pseudocode (which only showed the workspace-id case) and
  needed working out from first principles; verified live (see below)
  that the cursor correctly follows the moved pane, not a fixed row
  index.
- **No header hint added** for the reorder keys — the Workspaces tab's
  `--header` budget is already near its width ceiling at the highest
  tier (`_budget -ge 85`). Documented only in the Help tab, the
  top-of-file comment, and `usage()`; not required by any acceptance
  criterion.
- **Test file mirrors `11-dashboard-shell-unit.sh`'s isolated-tmux-server
  convention** (`TMUX_TMPDIR` + `tmux -f /dev/null`, not the ambient
  default server) rather than the live `lazy-llm`-session harness tests
  01-08 use — that harness needs a real controlling TTY, unavailable in
  this environment (confirmed pre-existing via `git stash`), and is the
  wrong weight for pure order-helper logic anyway.

### Commits
- `eeaf8d7` — lib: add persisted manual order helpers for workspaces and panes
- `3125c32` — dashboard: Ctrl-Up/Ctrl-Down manual tree reordering, scoped per level
- `110a424` — tests: cover manual tree reordering; fix brittle unbind-list regex

### Files changed
- `llm-send-bin/.local/bin/lazy-llm-lib.sh` — `lazy_llm_read_ws_order`,
  `lazy_llm_apply_ws_order`, `lazy_llm_move_ws_order`,
  `lazy_llm_move_pane_order`
- `lazy-llm-bin/.local/bin/llm-dashboard` — `_dashboard_build_rows` order
  application, `ctrl-up`/`ctrl-down` fzf binds + unbind/rebind lists,
  `--reorder-transform` CLI handler, Help tab / usage / top comment text
- `tests/scenarios/16-dashboard-manual-reorder-unit.sh` — new, 14
  assertions (lib helpers via isolated tmux server + structural wiring
  checks)
- `tests/scenarios/15-dashboard-help-tab-unit.sh` — updated one grep
  pattern that hardcoded the pre-reorder unbind-list string

### Sources Consulted
- `/home/paulomuggler/Projects/dev-env/dotfiles/claude/dot-claude/coding-standards/frameworks/tmux-fzf.md`
  — `set -e`/bare-assignment hazard, `load` vs `start`, `--nth`/
  `--with-nth`, unbind/rebind ordering (all already reflected in the
  existing file; no violations introduced)
- `dashboard-reload-avoid-full-redraw`'s landed code (`git show
  121dcbf`) and its inline comments in `llm-dashboard` around `z`'s bind
  and `--fold-transform` — the mechanism this task copies
- `man fzf` — confirmed `ctrl-up`/`ctrl-down` are valid `--bind` key
  names (fzf 0.74.3, this repo's installed version)
- `man tmux` OPTIONS section, plus a live probe on an isolated `-L`
  server — confirmed `tmux set-option -s @foo` / `show-option -s -v @foo`
  needs no `-t` target and is genuinely server-scoped

### Follow-up
- None discovered. The pre-existing `open terminal failed: not a
  terminal` failure in tests 01-08 (no controlling TTY in this
  environment) is unrelated to this change — confirmed via `git stash`
  that it reproduces identically on clean HEAD — and out of this task's
  scope.
- One incidental note for whoever next touches the test harness: test
  01's `setup_test_env`/`teardown_test_env` only exports `TEST_SESSION`
  (which `teardown_test_env` uses to clean up) *after* pane IDs are
  successfully resolved — so a test that fails before that point (as it
  does in this TTY-less environment) leaves its tmux session behind on
  the **real default server** with no automatic cleanup. Not fixed here
  (out of scope), but worth flagging since it's exactly the kind of
  debris leak the isolation discipline on this task was trying to avoid;
  I found and killed one such leftover (`test-simple-send`) after
  running the full suite.

## Verify Plan

- [x] AC1: Workspace-level Ctrl+Up/Ctrl+Down reorders among sibling
      workspace rows only, persists across a fresh dashboard relaunch —
      live, isolated tmux server (`-L` socket, never default): launch
      `llm-dashboard` inside a pane of the isolated server, Ctrl+Down on
      top workspace row, confirm swap via `tmux show-option -s -v
      @lazy_llm_ws_order`, quit + relaunch dashboard, confirm order
      still applied on the fresh render.
- [x] AC2: Pane-level Ctrl+Up/Ctrl+Down reorders among that workspace's
      own sibling panes only, persists via `@AI_PANES`/`@AI_TOOLS`/
      `@AI_PANE_NAMES` — live: swap adjacent panes in a 2-pane workspace,
      confirm all three arrays swapped in lockstep via `tmux show-option
      -wv`; separately (non-interactive, sourced lib) probe a 3-pane
      workspace with a name_arr SHORTER than pane_arr (padding-logic /
      off-by-one check) swapping the middle pair (idx1↔idx2).
- [x] AC3: Reordering never crosses tree levels — live: Ctrl-Up on a
      workspace's first pane row must not touch the workspace row above
      it; Ctrl-Down on a workspace's last pane row must not spill into
      the next workspace's rows; verify via before/after row dump +
      `@AI_PANES` of the neighboring, unrelated workspace.
- [x] Boundary: Ctrl-Up on the first workspace sibling / Ctrl-Down on the
      last pane sibling is a clean no-op — live, ANSI-aware
      `tmux capture-pane -p -e`, no crash, no wraparound, unchanged
      persisted state.
- [x] AC: new workspace/pane not yet in any custom order still renders,
      natural order, not hidden — live: create a workspace AFTER a
      custom order already exists, press refresh, confirm it appears
      appended at the bottom.
- [x] AC5/perf: No fzf relaunch across a reorder action — live: capture
      fzf PID + `ps -o lstart` before/after repeated Ctrl-Up/Ctrl-Down
      presses (both row types, both directions), confirm identical
      PID+start-time throughout.
- [x] Regression: fold (`z`) and search (`/`) still work, and the
      unbind/rebind key lists include the new reorder keys — live
      keypresses + `tests/scenarios/15-dashboard-help-tab-unit.sh`.
- [x] AC6: cursor lands on the MOVED row after a reorder, both directions,
      both a pane row and a workspace row — live, ANSI-aware
      `capture-pane -e`, using the bold+bg-236 selection-style marker to
      locate the highlighted line, not a computed pos(N) value.
- [x] Standard: `set -e` safety for every new bare `var=$(cmd)` in
      `eeaf8d7`/`3125c32` per
      `/home/paulomuggler/Projects/dev-env/dotfiles/claude/dot-claude/coding-standards/frameworks/tmux-fzf.md`
      — read the standard in full, then audit each new assignment site
      for an unguarded legitimately-failing command.
- [x] Tests: `tests/scenarios/16-dashboard-manual-reorder-unit.sh` passes
      standalone; full `tests/test-runner.sh` shows the same pre-existing
      `01`-`08` baseline failures (TTY-less environment) and no NEW
      failures; check `tmux list-sessions` on the REAL server before/after
      the full suite and clean up any debris the 01-08 tests leave behind.
- [x] Constraint: grep the diff for `execute-silent`, `--track`,
      `--id-nth`, `print(KEY)+accept`/exit+relaunch actually being used
      (not just referenced in comments/tests) on the new reorder keys —
      confirm none present in live code.

## Verify Report

All checks executed live against a disposable, isolated tmux server —
socket `lazyllmverify_<pid>` (`tmux -L ... -f /dev/null`, unique
`TMUX_TMPDIR`), never the default/real server. Three workspace sessions
(`verify_a` 2 real panes, `verify_b`/`verify_c` 1 real pane each, all
tagged `@lazy_llm=1`) were created and driven interactively via
`send-keys`/`capture-pane -e` inside a `controller` session/pane running
`llm-dashboard --tab workspaces` on that same isolated server (ambient
ephemeral `$TMUX` correctly scoped every in-script `tmux` call with no
`-t`/`-L` needed). A separate, ad-hoc unique-`TMUX_TMPDIR` probe (matching
`tests/scenarios/16-...`'s own established convention) was used for the
non-interactive 3-pane off-by-one check. Real server (`tmux list-sessions`,
outside any isolated socket) was checked clean before and after every
round; the full `01-08` test run's 8 debris sessions on the real server
were found and killed at the end (see below).

- [x] AC1 — workspace reorder scoped + persists across relaunch.
      Natural order confirmed first: `verify_a, verify_b, verify_c`
      (cursor on `verify_a`, row 3). Ctrl-Down on `verify_a` (top row) →
      new order `verify_b, verify_a, verify_c`; `tmux show-option -s -v
      @lazy_llm_ws_order` → `verify_b verify_a verify_c` (server-scoped,
      no `-t` needed — confirmed directly). Quit (`q`) + relaunched
      `llm-dashboard` fresh → render came up `verify_b, verify_a,
      verify_c` — order survived the relaunch, not just the in-process
      reload. Later, Ctrl-Up on `verify_c` (a non-boundary workspace)
      correctly swapped it up with `verify_a` → order became `verify_b,
      verify_c, verify_a, verify_d` (verify_d was a still-untouched,
      newly created workspace correctly appended at the end — see the
      AC-new-workspace item below). Both directions exercised.
- [x] AC2 — pane reorder scoped to owning workspace, all 3 arrays in
      sync. Interactive: cursor moved onto `verify_a`'s first pane
      (`claude`, row 6). Ctrl-Down → `@AI_PANES` `%1 %2` → `%2 %1`,
      `@AI_TOOLS` `claude gemini` → `gemini claude`, `@AI_PANE_NAMES`
      `_ _` → `_ _` (both placeholders, correctly carried), `@AI_PANE_IDX`
      `0` → `1` (followed the tracked physical pane, claude/%1, to its
      new slot) — `verify_b`'s own `@AI_PANES` (`%3`) untouched.
      Non-interactive off-by-one probe (3-pane workspace `p3`,
      `@AI_PANES="%10 %11 %12"`, `@AI_TOOLS="claude gemini codex"`,
      `@AI_PANE_NAMES="mylabel"` — deliberately SHORTER than the other
      two arrays, `@AI_PANE_IDX=2`): `lazy_llm_move_pane_order p3 win 1
      down` (middle↔last swap) → `@AI_PANES` → `%10 %12 %11`, `@AI_TOOLS`
      → `claude codex gemini`, `@AI_PANE_NAMES` → `mylabel _ _` (padded
      to length 3 from 1 BEFORE the swap, `mylabel` at idx0 correctly
      left untouched, the two padded `_` slots correctly swapped),
      `@AI_PANE_IDX` `2` → `1` (followed %12 to its new slot). No
      off-by-one, no partial-array update, padding logic verified
      correct. (First attempt at this probe used a `-L` custom-socket
      server but called the lib functions from OUTSIDE any tmux pane
      with no ambient `$TMUX`/`-L` routing — the library's bare `tmux`
      calls silently targeted the wrong, empty "default" socket under
      the same `TMUX_TMPDIR` and the move silently no-op'd. Not a bug in
      the code — a test-harness mistake on my part, corrected by
      switching to a unique-`TMUX_TMPDIR`-only isolation, matching
      `tests/scenarios/16-...`'s own established, already-verified-safe
      convention.)
- [x] AC3 — never crosses tree levels. Ctrl-Up on `verify_a`'s FIRST pane
      row (`claude`) → no-op, cursor stayed on that same pane row, did
      NOT move to/reorder the `verify_a` workspace row above it,
      `@AI_PANES` unchanged (`%1 %2`). Ctrl-Down on `verify_a`'s LAST
      pane row (after the earlier swap, `claude` now last) → no-op,
      `@AI_PANES` unchanged (`%2 %1`), `verify_c`'s `@AI_PANES` (`%4`)
      untouched — no spill into the next workspace's rows in either
      direction.
- [x] Boundary no-ops — both the very-first workspace row (Ctrl-Up on
      `verify_a` at position 1) and pane-row boundaries above are clean
      no-ops: no crash, no wraparound (order/arrays byte-identical
      before/after), fzf PID unchanged, confirmed via ANSI capture each
      time.
- [x] New workspace/pane not yet ordered still renders, natural order —
      created `verify_d` (never touched by any reorder) AFTER a custom
      workspace order already existed (`verify_b, verify_a, verify_c`),
      pressed `R` (refresh): render came back `verify_b, verify_a,
      verify_c, verify_d` — appended at the bottom, not hidden. Held
      through a later reorder too (`verify_d` stayed correctly appended
      after `verify_b, verify_c, verify_a`).
- [x] No fzf relaunch — single fzf PID (first observed `3030841`, later
      `3034809`, later `3042761` — each fresh number was actually the
      SAME live process re-verified with `ps -o lstart`; the number only
      changed across the standalone off-by-one probe / different dashboard
      launch, not within a sequence of reorders) confirmed byte-identical
      PID **and** identical `ps -o lstart=` timestamp across: top-boundary
      Ctrl-Up, workspace Ctrl-Down, pane Ctrl-Up boundary, pane Ctrl-Down
      swap, pane Ctrl-Down boundary, workspace Ctrl-Up (non-boundary),
      pane Ctrl-Up (non-boundary) — 7 consecutive reorder actions, zero
      relaunches.
- [x] Fold/search regression — `z` on `verify_a` collapsed its pane rows
      (▾ → ▸, panes hidden), `z` again restored them, same fzf PID
      throughout. `/` + typing `verify_c` correctly filtered to matching
      rows (fzf fuzzy match, `3/7`), `Tab` correctly cleared the query and
      restored the full unfiltered list. `tests/scenarios/15-dashboard-
      help-tab-unit.sh` (the updated unbind-list regex) passes standalone
      and inside the full suite.
- [x] Cursor-on-moved-row — verified with the ANSI bold+`48;5;236`
      selection-style marker (not a computed value) for all 4
      combinations: workspace Ctrl-Down (cursor followed `verify_a` from
      row 3 to row 5), workspace Ctrl-Up (cursor followed `verify_c` to
      its new row 5), pane Ctrl-Down (cursor followed `claude` to row 7),
      pane Ctrl-Up (cursor followed `claude` back up to row 8) — every
      case landed the highlight on the id/trailing-pane_id that actually
      moved, matching the `--reorder-transform` comment's documented
      technique.
- [x] `set -e` safety — read `tmux-fzf.md` in full. Audited every new
      bare `var=$(cmd)` in `eeaf8d7`/`3125c32`:
      `lazy_llm_read_ws_order`'s `tmux show-option ... || true` (always
      0); `lazy_llm_apply_ws_order`'s `order=$(lazy_llm_read_ws_order)`
      (callee always returns 0) and `line=$(... | awk ...)` (awk with or
      without a match exits 0, no `pipefail` hazard);
      `lazy_llm_move_ws_order`'s `data=$(lazy_llm_gather_sessions)`
      (callee itself is guarded `|| return 0` / `|| true` throughout, so
      always 0) and `persisted=$(lazy_llm_read_ws_order)` (same as
      above); `lazy_llm_move_pane_order`'s `cur_idx=$(tmux show-option
      ...) || cur_idx=""` (explicitly guarded). The `--reorder-transform`
      CLI block's `_dashboard_reorder_win=$(tmux list-windows ... | head
      -1)` (pipeline exit status is `head`'s, always 0 even on empty
      input) and both `_dashboard_reorder_pos=$(... | awk ...) || true`
      sites (explicitly guarded, redundant but harmless) — no unguarded
      legitimately-failing bare assignment found.
- [x] Tests — `tests/scenarios/16-dashboard-manual-reorder-unit.sh` run
      standalone: 14/14 assertions pass. Full `tests/test-runner.sh`:
      16 scenarios, 8 passed (`09`-`16`, including the new `16`), 8 failed
      (`01`-`08` — identical pre-existing TTY-less-environment baseline
      the Work Report claims, no new failures). `tmux list-sessions` on
      the REAL server was empty of test debris before the run; after the
      run it had 8 leftover `test-*` sessions from `01`-`08`
      (`test-simple-send`, `test-multiline-send`, `test-large-paste`,
      `test-marker-placement`, `test-response-pull`,
      `test-visual-selection`, `test-keypress-forward`,
      `test-workspace-local-dirs-ws1`) — this is the exact pre-existing
      gap the Work Report's own Follow-up section flags; all 8 were
      found and killed (`tmux kill-session`) before finishing, real
      server confirmed back to exactly the user's 3 real sessions
      (`ai-dev-workflow`, `dev-env`, `microdots_digital`).
- [x] Constraint honored — grepped the added lines of all three commits
      for `execute-silent`, `--track`, `--id-nth`,
      `print(KEY)+accept`/exit+relaunch: every hit is either a comment
      explaining why the OLD mechanism was dropped, or the new test
      file's own negative assertions (`Test 6`/`Test 9`) that these are
      ABSENT — no live code path uses any of them for the reorder keys.
      Live-confirmed the same: 7 consecutive reorder actions never
      relaunched fzf and never printed a plain (non-sync) `reload(...)`.

No failures found. Implementation matches both the acceptance criteria
and the task's own Constraints section; all live checks reproduced the
Work Report's claims independently, plus one additional off-by-one/
padding scenario (3-pane, mismatched name-array length) not explicitly
covered by the Work Report or the unit test file, which also passed.

VERDICT: pass

## Human Validation

**Commit(s):** `eeaf8d7`, `3125c32`, `110a424`

### Checks
- [ ] **Keybinding feel in real daily use** — Use the dashboard in your
      actual `lazy-llm` session (not an isolated test server) for normal
      work: press Ctrl-Up/Ctrl-Down to reorder a workspace or pane row
      you actually care about moving. Confirm the binding is comfortable
      to reach, doesn't collide with muscle memory from other tmux/fzf
      keys, and is discoverable enough without the header hint that was
      deliberately left out (see Design Decisions below).
- [ ] **Reorder granularity matches what you pictured** — The
      implementation moves a row one step per keypress (swap with the
      adjacent sibling; walk a row to the top by pressing Ctrl-Up
      repeatedly), not a single "jump to top/bottom" action. Confirm
      this step-at-a-time model is what you meant by "drag a
      frequently-used workspace to the top" — or whether you actually
      want a jump-to-edge shortcut in addition.

### Design Decisions
- **Order-state overlay precedence**: persisted order is applied
  first, then anything not yet in the persisted list is appended in
  natural order, and dead entries silently drop off the persisted list
  on the next move rather than accumulating. *Assess: only if you want
  workspaces to ever be explicitly removed from the order rather than
  self-pruning.*
- **Cursor-tracking key differs by row type** (full id for workspaces,
  trailing `pane_id` for panes, since a pane's id encodes its own
  position): an implementation necessity worked out from the existing
  `--fold-transform` pattern, not a user-facing choice. *Flag only if
  cursor tracking ever visibly lands on the wrong row.*
- **No header hint added** for the new keys — the Workspaces tab's
  header text budget is already near its ceiling at the widest
  terminal tier; the keys are documented in the Help tab, `usage()`,
  and the top-of-file comment instead. *This is what the first check
  above is probing — flag if discoverability turns out to actually
  suffer without it.*
- **Test file uses an isolated `-f /dev/null` tmux server** rather than
  the live-session harness tests 01-08 use, because that harness needs
  a controlling TTY unavailable in this environment. Reversible,
  already the established convention for this class of test (matches
  the sibling `dashboard-reload-avoid-full-redraw` task).

### Sign-off

| Status | Validator | Date | Notes |
|--------|-----------|------|-------|
| | | | |

Status: PENDING
