---
slug: dashboard-layout-status-redesign
title: Dashboard layout + status bar redesign in response to user feedback
priority: P1
status: done
created: 2026-09-22_15:06
updated: 2026-09-23_01:45
depends-on: []
tags: [ux, dashboard, statusbar, design]
commits: [1b9b401, 24de3f1, 27ac16d, d9c4252, 7d661b2, 6f0524a, 948d2c6, 2425da2, 4d36241, fa7cbac, af5c805, 2df5daa, 4921bb0, 91c748b, 1cc5c84, 2a7e206, f7f0b3d]
model: inline
---

# Dashboard layout + status bar redesign in response to user feedback

## Context

Direct user feedback (with a real screenshot) on the earlier 6-task dashboard batch:
1. Dashboard popup opens much taller than its content needs (screenshot showed ~46
   rows for ~10 rows of actual tree content).
2. Status bar: no spacing between tool name and glyph, unclear what the bracketed
   "active" indicator refers to, "S:dash" is unexplained, no color/visual hierarchy —
   "just some greys on black."
3. Workspaces tab header lost its pane-add/kill hints (fallout of an earlier
   width-truncation fix that assumed an 80-column terminal — user's is 243 columns).
4. Asked to explore `pane-border-status` (per-pane status on the pane's own border)
   as an alternative to the global status bar.

Also surfaced and fixed along the way: `action:pane-add`/`action:worktree-new` had a
pre-existing `set -e` hazard (pressing Esc mid-subprompt killed the whole dashboard) —
tracked separately as [[dashboard-escape-abort-killswitch]]. And a real operational
mistake: leftover `test-*` tmux sessions from running the test suite were cluttering
the user's live dashboard, and a `tmux send-keys` call accidentally targeted the
user's own live Claude Code pane (which turned out to be *this conversation's own
session*) instead of a disposable test session, typing a command into the chat input
itself.

## Key Files

- `llm-status-bin/.local/bin/llm-status` — full redesign
- `lazy-llm-bin/.local/bin/llm-dashboard-open` — new, dynamic popup height
- `lazy-llm-bin/.local/bin/lazy-llm` — Prefix+S rewired to the new wrapper
- `lazy-llm-bin/.local/bin/llm-dashboard` — `_dashboard_header_budget`, tiered headers

## Work Report

**Date:** 2026-09-22_15:06

### What was done

1. **`llm-status` redesign** — labeled "AI" chip, real spacing between tool name and
   glyph, active pane shown as a filled tile instead of bare brackets, glyphs
   color-coded (yellow/pink/green, reusing this project's existing tmux theme
   palette), "S:dash" replaced with the spelled-out "Prefix+S".
2. **Dynamic popup height** — `llm-dashboard-open` estimates the tree's row count
   before opening the popup and sizes `-h` to it (16-row floor, 85%-of-client
   ceiling), instead of a fixed 70%. Prefix+S now runs this wrapper via `run-shell`
   (tmux's own command language can't compute a value in a real shell first).
3. **Adaptive header width** — `_dashboard_header_budget` measures the real
   `#{client_width}` at render time and both tabs pick from three tiers (full
   keybinding list / core keys / bare minimum) based on what actually fits, instead
   of one minimal header sized for the narrowest plausible terminal. At the user's
   real 243-column terminal, this restores the full keybinding hints (`n:new`,
   `K:kill/rm`, `a:add-pane`, `]/[:cycle-pane`, etc.) that a previous over-cautious
   fix had hidden behind the Help tab.
4. **`pane-border-status` investigation** — confirmed it's a real, window-scopable
   tmux feature (`pane-border-status`/`pane-border-format` both accept `-w`), but
   could not get a conclusive functional verification that `#()` jobs inside
   `pane-border-format` resolve per-pane context correctly (`llm-status` and even a
   bare `#(echo ...)` returned empty when queried via `display-message -p -t <pane>`,
   which likely doesn't exercise the same job-execution path as live rendering — the
   same class of limitation as not being able to capture the status bar directly).
   **Not shipped** — flagged to the user as something to try live themselves, or to
   revisit with a way to verify it that doesn't depend on this tool environment's
   capture limitations.
5. **Operational cleanup**: purged leftover `test-*` tmux sessions (created by
   `./tests/test-runner.sh` runs whose TTY-dependent tests fail before their own
   cleanup) that were visibly cluttering the user's live dashboard — this had
   happened multiple times over the session. Switched to running only the 7
   non-TTY unit tests (9–15) individually for the rest of this work, to stop
   recreating the pollution.

### How it was done

- Investigated the "what happened to pane add/kill" question live first (see
  [[dashboard-escape-abort-killswitch]]) before assuming it was a discoverability
  issue — found and fixed a real, pre-existing bug in the process, though it turned
  out not to be what the user was actually asking about (they meant the header hint
  disappearing, not a functional break) — flagged directly rather than let the
  misdirection stand uncorrected.
- Measured the real header-width constraint precisely (live fzf tests at 80–243
  columns) before designing the tiered thresholds, rather than guessing.
- Verified the dynamic height estimate against the user's real live workspace data
  (3 workspaces, 4 panes → 16 rows, down from 46).
- Verified the adaptive header renders in full at the real 243-column width in a
  disposable test session — both tiers' lines confirmed via direct capture.
- For the pane-border-status idea, ran multiple isolation tests (detached session,
  attached-client window, bare `#(echo)` sanity check) before concluding the
  verification path itself was the limitation, rather than silently shipping
  something unverified or silently dropping the idea without explaining why.
- **Caught and corrected a real operational mistake mid-task**: a `tmux send-keys`
  call meant for a disposable test pane was accidentally targeted at
  `dev-dev-env-claude`, which is this very conversation's own Claude Code session —
  the injected keystrokes were typed into the chat's own input box and submitted as
  a message. Recognized this from the resulting mid-turn message content, confirmed
  no damage occurred (checked the pane state directly), and stopped using that
  session name for any further interactive testing.

### Decisions made
- **Didn't ship the pane-border-status experiment** — the task's own bar for
  shipping is "verified," and this session's tooling couldn't clear that bar for a
  per-pane rendering feature. Better to say so than to ship unverified tmux chrome
  changes to the user's live config.
- **Three-tier header instead of a single adaptive computation** — simpler to reason
  about and verify than a fully continuous "pack as many hints as fit" algorithm,
  and the three tiers were each individually measured against real fzf behavior.
- **Kept both the redesigned global status bar AND left `pane-border-status` as a
  live option to explore** rather than assuming the user wants one to replace the
  other — they framed it as "could we experiment," not "replace this."

### Commits
- `1b9b401` — llm-status: redesign for clarity, spacing, and color
- `24de3f1` — dashboard: size the popup to actual content instead of a fixed 70%
- `27ac16d` — dashboard: adapt header richness to actual terminal width

### Follow-up
- `pane-border-status` remains an open idea — needs either a live interactive check
  by the user, or a different verification approach than this session had available.

## Verify Plan

Self-verified inline.

1. Syntax-check all changed files
2. Run the 7 non-TTY unit tests (not the full suite, to avoid recreating test
   session pollution)
3. Verify llm-status's raw output structure (chip, spacing, per-state color) against
   real live workspace data
4. Verify the height estimator against real workspace/pane counts
5. Verify the adaptive header renders in full at the real terminal width, in a
   disposable session
6. Confirm no test-session or real-session pollution remains

## Verify Report

**Date:** 2026-09-22_15:07

1. ✅ `bash -n` clean on all four changed/new files
2. ✅ Tests 9–15 individually: all pass, no new sessions left behind
3. ✅ `llm-status` raw output inspected for a real multi-pane and single-pane
   workspace — chip present, literal space before each glyph, correct per-tool
   status-derived colors, active tile uses a filled background
4. ✅ Height estimator: real data (3 workspaces, 4 panes) → 7 content rows → 16 total
   (floor applied), vs. the previous fixed 46 — confirmed via direct function
   invocation against live `lazy_llm_gather_sessions` output
5. ✅ Adaptive header: disposable 243-column test session showed both full-tier
   header lines rendering completely, no truncation
6. ✅ `tmux list-sessions` shows only the user's 3 real workspaces at the end of
   this task; the accidental test window added to `dev-dev-env-claude` was removed

## Work Report (Round 2)

**Date:** 2026-09-23_01:10

**Reopened** in response to a second, denser 14-item feedback pass (with a real
monitor screenshot) on top of Round 1's ship. This section covers everything
landed in that round; items still open are listed under Follow-up below —
belated task-tracking note: this round's commits landed individually as work
progressed, ahead of reopening this file to `in-progress` — a process gap
against the usual discipline, corrected here rather than silently backfilled.

### What was done
1. **Fuzzy search crash** — `--nth=2` was fighting `--with-nth=2` (the former
   re-searches the ALREADY-collapsed line `--with-nth` produces, for a field
   that no longer exists past the third filter keystroke); removed the
   redundant `--nth=2`.
2. **Stale "working" detection** — `interrupt_pat` regex only matched a string
   Claude Code's current UI never emits; fixed to match the real spinner/
   duration pattern and "esc to interrupt".
3. **Popup height** — reversed Round 1's content-fit sizing (user wanted MORE
   vertical space, not less); `llm-dashboard-open` now uses generous
   percentage-based sizing (90% of client height, 24-row floor) instead of
   estimating content rows.
4. **Universal nav into the title bar** — moved the tab/keybinding crumbs that
   were line-wrapping awkwardly inside the Workspaces pane into the popup's
   own `-T` title bar.
5. **Default highlight** — active workspace + active pane now pre-selected via
   `--bind start:pos(N)` when the dashboard opens.
6. **Global summary + reworded hint** — `lazy_llm_compute_summary` (shared
   helper) feeds a cross-workspace "Nws Mwaiting" summary into both
   `llm-status` and `llm-pane-border`; "S:dash" reworded, later made fully
   dynamic (see #9).
7. **Help tab** — rebuilt as a two-column bordered box (`_help_pad`/
   `_help_rule` helpers, manual character-count padding — `printf %-*s` pads
   by byte length, which breaks on this content's multi-byte box-drawing
   chars).
8. **`pane-border-status` shipped live** — the Round-1 "couldn't verify"
   blocker was resolved by testing the REAL invocation chain (Prefix+S →
   `run-shell` → popup → dashboard) instead of synthetic `display-message`
   calls; `llm-pane-border` now renders per-pane status on the pane's own
   border, window-scoped.
9. **Launch-workspace context fix** — popups don't reliably inherit
   `TMUX_PANE`/ambient session context; `llm-dashboard-open` now resolves the
   launch session in its own `run-shell` context (reliable) and passes it
   explicitly via `-e LAZY_LLM_LAUNCH_SESSION=`.
10. **Workspace naming** — dropped the "dev-" prefix and "-`<tool>`" suffix
    from auto-generated names; now just the directory name.
11. **'n' key removed** — it called `tmux display-popup` from inside an
    already-open popup, which tmux silently ignores per its "modifying an
    existing popup" semantics; reworking it wasn't worth it per user
    preference, so it was removed (key, `--expect`, dispatch case, docs).
12. **Bold instead of "(active)"** — replaced the text tag with real bold
    styling; added a STATUS GLYPHS legend to both the tree header and the
    Help tab.
13. **Pane-border contrast + shared summary** — explicit `#[fg=...]` added to
    every piece of border text (it was inheriting tmux's dim unfocused-border
    style); refactored to share `lazy_llm_compute_summary` with `llm-status`
    instead of two copies drifting apart; dynamic prefix-key hint
    (`prefix_hint()`, queries `tmux show-options -gv prefix`) replaces the
    hardcoded "Prefix+S".
14. **Pane rename** — `r` now branches on what's highlighted: a workspace row
    renames the workspace (as before), a pane row renames just that pane via
    a new `@AI_PANE_NAMES` window option (parallel array to `@AI_TOOLS`, `"_"`
    = no override), decoupled from status detection (which still keys off the
    real tool name) so renaming never breaks status.
15. **Status bar visual redesign** (commit `2a7e206`, this file's most recent) —
    three macro segments (chip / content / cap) distinguished by color alone
    (strong blue `#00afff` / faded blue `#005f87` / strong blue), literal "│"
    separators between every part INSIDE the content segment (summary, each
    tile, the hint), active tile swaps to the strong-blue accent instead of a
    separate highlight color, small block-glyph end-cap for visual pop.
16. **Backlog filed, not implemented** (per explicit instruction): pane
    auto-renaming from live conversation content — see
    `.agents/TODO/backlog/pane-auto-naming-from-conversation.md`.

### Decisions made
- Kept pane-rename and status-detection deliberately decoupled (rename never
  breaks the tool-based status lookup) rather than trying to infer tool
  identity from a possibly-arbitrary custom label.
- For the status bar's three-segment scheme, followed the user's explicit
  split precisely: color-only boundaries between the three MACRO segments,
  but literal `│` between every part WITHIN the content segment — these read
  as contradictory at a skim but are two distinct, correctly-scoped asks.

### Commits
- `f7f0b3d` — dashboard: fuzzy-search mode ('/') that doesn't fight action keybindings
  (this round's last open item — see Follow-up below for the discovery process)
- `d9c4252` — dashboard+lib: fix broken fuzzy search and stale "working" detection
- `7d661b2` — dashboard: reverse the popup-height change — go generous, not content-fit
- `6f0524a` — dashboard: move universal nav into the popup's own title bar
- `948d2c6` — dashboard: highlight the current workspace + active pane by default
- `2425da2` — llm-status: add a global workspace/waiting-attention summary, reword the hint
- `4d36241` — dashboard: two-column bordered layout for the Help tab
- `fa7cbac` — dashboard: implement pane-border-status (per-pane status on the pane's own border)
- `af5c805` — dashboard: pass the launch session explicitly — popups don't reliably inherit it
- `2df5daa` — lazy-llm: drop 'dev-' prefix and '-<tool>' suffix from auto-generated workspace names
- `4921bb0` — dashboard: remove broken 'n' key, bold active pane instead of '(active)' tag, add status glyph legend
- `91c748b` — status: fix pane-border contrast, share summary logic, dynamic prefix hint
- `1cc5c84` — dashboard: 'r' renames the highlighted pane too, not just the workspace
- `2a7e206` — status: three-segment color scheme (chip/content/cap) with literal separators

### Follow-up

**Done in commit `f7f0b3d`** — fuzzy-search mode shortcut. First attempt
(`--disabled --no-input` + `/:enable-search+show-input`) looked right in
isolated testing but was wrong: `--expect` keys intercept unconditionally,
regardless of input-shown/search-enabled state — confirmed by direct
testing, not assumed. Real fix required retiring `--expect` for
`print(KEY)+accept` --bind entries plus `unbind(...)`/`rebind(...)` to
actually add/remove those bindings on `/`/`esc`. Recorded the full gotcha
chain in `dotfiles/claude/dot-claude/coding-standards/frameworks/
tmux-fzf.md` (dev-env repo, commit `0183d5e`) so this doesn't need
re-discovering.

**Still open from the 14-item list** — both need the user's own
eyes/screenshot; this session's tooling has hit its verification ceiling
on both:
- **Vertical space still reported broken** — measured the popup's actual pty
  via `stty -F <pty> size` at 57 rows for a 66-row client, which appears to
  contradict the report; not reconciled with the user's direct observation.
  Needs either a fresh repro/screenshot or a different diagnostic angle.
- **Title bar visibility** — confirmed via `ps aux` that `-T "<title>"` is
  correctly constructed and passed to `tmux display-popup`, but couldn't get
  further visual confirmation; not reconciled with the user's report that it
  isn't visible. Same class of blocker as the item above — needs the user's
  own eyes or a different verification path this environment doesn't have.

**Closing this task**: every item from the 14-item list that was actionable
without the user's own eyes is shipped and verified above. The two items
left are handed back directly rather than kept open here — no further
engineering to do until there's a fresh repro/screenshot for either.
