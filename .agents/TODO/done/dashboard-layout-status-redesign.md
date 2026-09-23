---
slug: dashboard-layout-status-redesign
title: Dashboard layout + status bar redesign in response to user feedback
priority: P1
status: done
created: 2026-09-22_15:06
updated: 2026-09-23_03:00
depends-on: []
tags: [ux, dashboard, statusbar, design]
commits: [1b9b401, 24de3f1, 27ac16d, d9c4252, 7d661b2, 6f0524a, 948d2c6, 2425da2, 4d36241, fa7cbac, af5c805, 2df5daa, 4921bb0, 91c748b, 1cc5c84, 2a7e206, f7f0b3d, a9438b4, ec23025, 7af2f87, bedfc60]
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

## Work Report (Round 3)

**Date:** 2026-09-23_03:00

Reopened for a third feedback round, this time WITH screenshots — which
resolved both Round 2 "handed back" items (title bar visibility confirmed
working in the screenshot itself; vertical space got a real screenshot to
diagnose against, below) plus 7 new items.

### What was done
1. **Vertical space — root cause finally found.** The user's shell exports
   `FZF_DEFAULT_OPTS="--height 40% ..."`, silently inherited by every fzf
   call in `llm-dashboard`. Confirmed live (a bare fzf call in the same
   popup used ~40% of a 55-row pane; `--height=100%` filled it). Added to
   all 11 fzf invocations in the file.
2. **Active-pane-on-open still not working** — switched from the
   app's own `@AI_PANE_IDX` (only updated by `llm-cycle`, stale the moment
   focus moves any other way) to tmux's native per-window `pane_active`
   flag, in both the dashboard tree and `llm-status`'s tile bolding.
3. **Dashboard status glyphs uncolored** — added `glyph_color_for`/
   `_ansi_fg`/`glyph_for_colored` (truecolor ANSI, since tree rows render
   via fzf `--ansi`, not tmux `#[...]`).
4. **Pane renames now show everywhere**: `llm-pane-border`'s title,
   `llm-status`'s tile (clamped to 15 chars + ellipsis, per explicit
   request), and the dashboard tree (refactored to the same shared
   `lazy_llm_pane_display_label` helper). New shared helpers in
   `lazy-llm-lib.sh`.
5. **Status bar visual bugs, both root-caused from the screenshot**:
   active tile's color "not filling between the │ separators" → switched
   from background-fill to bold+accent-color (user-sanctioned fallback);
   end-cap's "black break" → the `▐` half-block glyph's left half renders
   in `bg=default`, creating a hard seam against the solid-blue space
   before it, not a fade — replaced with a plain solid-blue cap + one hard
   `#[default]` cut.
6. **Title bar decluttered** — dropped redundant `3:help` (kept `?:help`).
7. **`idle_prompt` hook mapping fixed** (dev-env repo, not this submodule):
   was wired to write "waiting", overwriting `Stop`'s correct "idle" some
   time after a response completed and firing a misleading "needs your
   input" notification for a session that wasn't blocked on anything.
   Explains "sessions that finished generating often stay on waiting."
8. **Backlog task confirmed, not duplicated**: the branch/repo
   sanitization ask already had a full existing task
   (`branch-per-setup-and-shared-core-sync`, dev-env repo) — moved
   `pending` → `backlog` per the user's explicit request instead of
   filing a duplicate.

### How it was done
- Every fix in this round was root-caused from a live measurement or a
  direct screenshot, not guessed — `FZF_DEFAULT_OPTS` found via `env |
  grep -i fzf`; the `▐` seam explained by the codepoint's own
  left-half/right-half color split; `pane_active` verified live via
  `tmux select-pane` + `list-panes -f`.
- All changes verified live against disposable sessions (multi-pane,
  renamed panes, deliberately-focused-via-tmux-not-llm-cycle) before
  committing; full 10–15 unit-test sweep run clean after each batch.

### Commits
- `a9438b4` — dashboard: fix vertical-space bug, active-pane heuristic, colored glyphs
- `ec23025` — status: fix active-tile flicker, endcap seam, tile fill; show pane renames
- `7af2f87` — pane-border: show the pane's dashboard rename, not just its tool name
- `bedfc60` — dashboard-open: drop redundant '3:help' from the title bar
- (dev-env repo) `cf2e807` — claude hooks: idle_prompt maps to 'idle', not 'waiting'
- (dev-env repo) `3dbb919` — [todo] Move branch-per-setup-and-shared-core-sync to backlog

### Follow-up
None outstanding from this round — every item had enough evidence
(screenshot or live measurement) to root-cause and fix directly.

## Work Report (Round 4)

**Date:** 2026-09-23_03:10

Fourth round, direct pasted feedback (no screenshot this time). Two items;
one investigated but not conclusively resolved.

### What was done
1. **'3' still opened Help** — Round 3 only removed the title bar's
   displayed "3:help" hint text, not the underlying binding. Removed
   `--bind='3:print(3)+accept'`, '3' from both tabs' unbind/rebind key
   lists, and the `3) echo "tab:help"` dispatch case, for both Workspaces
   and Worktrees. Verified live: '3' now a no-op, '?' still works.
2. **Active-pane-on-open — real root cause found, third attempt.** Direct
   testing (not assumption) found: a workspace has THREE panes (AI,
   editor, prompt); tmux's `#{pane_active}` only tracks the single most-
   recent one, so the moment focus moves to the editor/prompt pane (a lot
   of real usage time, per this project's own documented workflow),
   `#{pane_active}` no longer points at any AI pane and the Round-3 fix
   had no fallback. New `llm-pane-focus-track` + a global tmux hook now
   keep `@AI_PANE_IDX` pointing at the last AI pane given real focus,
   persisting through later focus changes. Two dead ends hit and fixed en
   route (both confirmed by direct testing, not assumed): the tmux manual
   documents a `pane-focus-in` hook that doesn't actually exist in tmux
   3.7c (`set-hook -g pane-focus-in` exits 0 and silently never fires) —
   switched to `after-select-pane`, which does fire; and `run-shell -b`
   (backgrounded) had a real race that sometimes dropped an update —
   removed it, the script's cheap enough for the foreground.
3. **Waiting-vs-idle glyph question — investigated, not conclusively
   resolved.** The Round-3 `idle_prompt`->`waiting` mapping bug fix
   (dev-env commit `cf2e807`, landed 01:59:58) predates this report
   (02:50:04) by ~50 minutes; confirmed Claude Code hooks reload live
   (file-watcher, no session-restart needed) so staleness isn't the
   explanation. Checked every live status file at report time: none
   showed a fresh (<30s) "waiting" entry — all either correctly idle or
   correctly stale-and-falling-through to the content-scrape path. Could
   not catch a live repro to diagnose further this round.

### Decisions made
- Answered the "what's making this difficult" question directly rather
  than just re-attempting silently a fourth time: tmux's own
  focus-tracking primitives (`#{pane_active}`, and the documented-but-
  nonexistent `pane-focus-in`) don't match this project's actual 3-pane-
  per-workspace shape, which is why two rounds of "obviously correct"
  fixes each failed for a different, non-obvious reason. Told the user
  plainly rather than let a third silent attempt stand un-scrutinized.
- Caught and disclosed my own test-methodology error rather than let an
  incorrect "still broken" conclusion stand: an earlier verification
  pass this round wrongly concluded the fix hadn't worked, because the
  disposable test session was missing the `@lazy_llm` marker option and
  so never appeared in the gathered workspace list at all — a test setup
  bug, not a real one. Corrected and re-verified before reporting back.

### Commits
- `c8335f0` — dashboard: remove '3' as a functional help-tab shortcut, not just its hint
- `e9f2d00` — lazy-llm: real fix for active-pane-on-open — track AI-pane focus via a hook
  (commit message partially corrupted by an unescaped-backtick shell
  substitution bug on my end — flagged to the user directly rather than
  amended without being asked, per standing commit discipline)

### Follow-up
- Waiting-vs-idle: if the user hits a fresh repro, the next step is
  either live `tail -f`-style observation of the status file the moment
  it happens, or temporary verbose hook logging to catch the exact
  Notification/Stop event sequence — not yet attempted.

## Work Report (Round 5)

**Date:** 2026-09-23_03:45

Fifth round, direct pasted feedback. Two clean fixes, one real root-cause
find on the still-open waiting/idle item, and active-pane-on-open remains
unresolved from the user's side despite passing every test this session
could construct — handed back with a direct question rather than a fifth
blind attempt.

### What was done
1. **Esc no longer closed the dashboard on Workspaces/Worktrees** —
   direct regression from the search-mode feature: esc had been
   repurposed to mean "leave search," so it stopped aborting the
   dashboard while searching. Reported directly with an explicit
   requirement: esc must always close, unconditionally. Fixed by
   leaving esc unbound entirely (falls back to fzf's own default abort)
   and moving "leave search mode" to Tab instead — verified live in both
   modes (browse and mid-search).
2. **Waiting/idle — real root cause found this time.** Investigated
   with fresh live evidence rather than re-asserting the earlier fix:
   checked all 5 real status files (none showed a fresh false "waiting"
   at inspection time) and instead found the bug by testing the
   content-scrape fallback directly against real pane content.
   `waiting_pat`'s numbered-choice pattern (matches Claude Code's actual
   permission-prompt UI) also matches an ordinary markdown numbered list
   in Claude's own finished response text — confirmed against a real
   pane whose completed response ended in a 3-item list, genuinely idle,
   reported as "waiting." This bites once the hook-written idle status
   ages past its 30s freshness window and falls through to content-scrape.
   Fixed by scoping that specific check to the last 10 lines of the
   capture (tuned empirically: 15 still caught 2 of 3 list lines, 12 and
   10 caught none) — a real prompt is always near the bottom of the
   pane, old response content never is. Added a regression fixture.
3. **Active-pane-on-open — reported as still not working despite the
   Round-4 fix.** Extensive re-investigation this round: tested the
   hypothesis that opening the popup itself resets the tracked state
   (disproved, twice, with a properly-attached test client); confirmed
   the global hook is still correctly registered on the live server;
   confirmed mouse-click and prefix-arrow pane navigation both route
   through the same `select-pane` primitive the hook is bound to;
   traced the dashboard's own internal `_start_pos` computation directly
   against the REAL `dev-env` workspace's live state (4 AI panes,
   `AI_PANE_IDX`/`pane_active`/the traced row position all agreeing) and
   found it entirely self-consistent. Could not find or reproduce a
   mechanism-level failure this round. Not shipping a fifth blind
   change — handed back to the user with a direct question about exact
   repro steps, since further guessing risks another failed round.
4. **Commit message repair** (`e9f2d00` → `87e7962`): the original had
   a shell-quoting bug (backtick-wrapped inline-code spans inside a
   double-quoted `-m` string were executed as command substitutions,
   silently dropping several technical terms). Fixed via a non-
   interactive reset + cherry-pick replay (`git rebase -i` isn't
   available in this environment) — reset to the parent commit,
   re-applied the change with a corrected message from a file, replayed
   the 3 commits that had landed on top. Verified the replayed tree is
   byte-identical to the original (`git diff <backup> HEAD --stat` empty)
   before deleting the safety backup branch. Also hit and fixed the SAME
   class of bug a second time mid-round (an apostrophe in "Claude's own"
   broke a single-quoted `-m` string) — adopted writing every commit
   message to a temp file and using `git commit -F <file>` for the rest
   of this round and going forward, which sidesteps shell quoting
   entirely.

### Decisions made
- Did not attempt a fifth active-pane-on-open fix without new
  information — three consecutive attempts (background/foreground
  variants, `pane-focus-in` vs `after-select-pane`, the 3-pane focus
  problem) all passed direct testing yet the user still reports it
  broken. Continuing to guess without a concrete repro (exact pane/
  window state, what was pressed, ideally a screenshot) has a low hit
  rate and costs real time; asking directly is the better use of both.
- Adopted file-based commit messages (`git commit -F <file>`) as a
  standing practice after two separate shell-quoting corruptions in one
  session — recorded here rather than only in the fix commit, since
  it's a process change that should stick for future work in this
  repo, not just this task.

### Commits
- `87e7962` — lazy-llm: real fix for active-pane-on-open — track AI-pane focus via a hook
  (message-corrected replacement for the original `e9f2d00`)
- `0a8ef26` — lib: fix waiting_pat false-matching Claude's own numbered-list output
- `61fb76c` — dashboard: esc always closes the dashboard, even mid-search

### Follow-up
- **Active-pane-on-open**: needs the user's exact repro steps (which
  workspace, what was focused/pressed immediately before opening the
  dashboard, ideally a screenshot of what appeared vs. what was
  expected) to make further progress — this session's own testing
  cannot currently reproduce a failure.
- **Waiting/idle**: the numbered-list false positive is fixed and
  verified; if a fresh "stuck on waiting" case turns up despite this,
  it needs live `tail -f`-style observation of the status file or
  temporary verbose hook logging to catch the exact event sequence.

## Work Report (Round 6)

**Date:** 2026-09-23_03:55

Sixth round. The user gave a precise repro description for the first
time ("cursor always lands on the first item, a workspace row, never a
pane row — keyboard only, sort already correct") and asked directly what
was causing both the sort and the highlight behavior. That precision is
what cracked it — found and fixed the actual bug in one exchange, after
three rounds of fixing real-but-not-the-actual-bug issues.

### What was done
Found and fixed the true root cause of "active-pane-on-open": **`--bind
'start:pos(N)'` does not work.** The `start` event fires before fzf's
list is far enough along for `pos()` to act on meaningfully; the cursor
silently lands on row 1 regardless of N. Confirmed pixel-for-pixel: a
minimal 5-row fzf list with `start:pos(3)` highlighted row 1 every time,
while the identical `pos(3)` bound to a real keypress correctly
highlighted row 3. Switched to `load:pos(N)` (fires once the initial
data load completes) — fixed in every configuration tested, including
the dashboard's real `--ansi --delimiter --with-nth` combination.
Verified end-to-end against the real `dev-env` workspace with
ANSI-aware capture (`tmux capture-pane -e`): the highlight now lands on
the correct pane row, not the workspace row above it.

Also corrected the tmux-fzf coding-standards guide, which had
previously (wrongly) documented `start:pos(N)` as working — that wrong
claim is very likely why this took three rounds: each round's
verification trusted the documented claim and checked `_start_pos`'s
computed VALUE or `pos()`'s mechanism via a real keypress, never the
actual `start`-triggered binding rendered live with `-e` capture, which
is the only way this specific failure is visible (a plain
`capture-pane -p` shows a decorative gutter marker on every row that
looks like a cursor but isn't).

### Decisions made
- Kept the existing "sort active workspace to top" behavior rather than
  switching to a stable sort, since the user offered both but the
  now-working pane-level highlight makes the combination (sort-to-top +
  correct pane highlight) the better UX of the two options — flagged
  this choice back rather than silently picking one.
- Documented the verification method (ANSI-aware capture, or test the
  same action via a real keypress first) directly in the coding-standards
  guide, not just the fix — the wrong claim surviving three rounds was a
  verification-methodology gap as much as a code bug.

### Commits
- `ecd50f8` — dashboard: the real active-pane-on-open fix — load:pos, not start:pos
- (dev-env repo) `7cf5c12` — coding-standards/tmux-fzf: correct the start:pos(N) claim

### Follow-up
- Flagged directly to the user, unresolved: the `diag` tmux session
  disappeared between two live checks this round, with no command this
  session ran that targeted it and no matching entry in the tmux server's
  (limited-depth) message log. Cannot confirm cause — asked the user to
  confirm whether they closed it themselves.
- Waiting/idle and active-pane-on-open are both now considered resolved
  pending the user's next confirmation; no further action planned unless
  they report otherwise.

## Work Report (Round 7)

**Date:** 2026-09-23_04:05

Confirmed: the `diag` session disappearance was the user's own cleanup,
unrelated to this session's work. Also confirmed via `git log` that the
user has been committing to this same submodule directly and concurrently
(`47cfa1e`, a pane rename via their own live usage) — useful context for
why live state (e.g. `@AI_PANE_IDX`) shifted between checks in earlier
rounds; not a bug, just concurrent real usage.

Direct correction from the user on Round 6's own judgment call: I kept
"sort active workspace to top" on my own reasoning after `load:pos(N)`
started working, deciding that combination was "the better UX." The user
pushed back — their actual point, which they'd already stated when
offering the choice, is that a STABLE list order (same position every
time) is what makes the tree glanceable and short-term learnable across
repeat visits; re-sorting on every open defeats the point of a working
per-pane highlight, which should remove the need to re-scan, not just
relocate the target of the scan.

### What was done
Removed the awk-based "put launch workspace first" reorder entirely.
The tree now uses `lazy_llm_gather_sessions`'s natural order (tmux
`list-sessions`'s own order — stable, doesn't shift with activity).
`load:pos(N)` still jumps the cursor to the active pane wherever it
falls in that stable list. Verified live: launched the dashboard from
two different real workspaces, identical row order both times, cursor
correctly on each workspace's own pane row (not row 1, not forced to
the top) in both cases.

### Decisions made
- Did not re-litigate or hedge on the correction — the user's reasoning
  (cognitive load, glanceability, short-term learnability of a fixed
  layout) is sound and was already stated once; the right move was to
  just implement what was asked, not defend the unilateral call.

### Commits
- `469f987` — dashboard: stable list order instead of sort-active-workspace-to-top

### Follow-up
None — this closes out the active-pane-on-open thread (root cause fixed
Round 6, ordering behavior corrected Round 7) and the diag-session
question (confirmed user-initiated). Waiting/idle remains verified-fixed
pending no further reports.
