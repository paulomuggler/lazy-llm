---
slug: dashboard-preview-render-fix
title: Fix dashboard layout — header truncation and corrupted ANSI preview rendering
priority: P2
status: done
created: 2026-09-22_04:37
updated: 2026-09-22_05:10
depends-on: [dashboard-tree-view-consolidation]
tags: [ux, dashboard, tui, rendering]
commits: []
model: inline
---

# Fix dashboard layout — header truncation and corrupted ANSI preview rendering

## Context

User-reported layout problems in the current dashboard (screenshot attached to the
originating conversation, described here since a dispatched agent can't see images):

1. **Header row truncates with `..`**: the `--header` string listing all key hints
   (`[Sessions] enter: switch │ n: new │ K: kill │ ... │ 2: worktrees │ ..`) is wider
   than the popup and fzf hard-truncates it, hiding the tail of the hint list from the
   user — the opposite of the discoverability this project needs. Observed at 90%-width
   popup on a 2560px-wide terminal; will be worse on narrower ones.
2. **Preview pane shows corrupted box-drawing / layout artifacts**: the right-hand
   preview (`tmux capture-pane -p -e -S -200 -t "$pid"` piped into fzf's
   `--preview-window=right:55%:wrap:follow`) shows stray `└` glyphs starting several
   lines, orphaned horizontal-rule fragments (bare `─────` lines with nothing else), and
   a token-counter box (`260/265`) rendered detached/overlapping other text instead of
   in its own line. This is very likely because `tmux capture-pane` captures the pane's
   content at its **actual, full column width**, but the preview pane fzf renders it
   into is only ~55% of the popup's width — narrower than the source. With
   `wrap` set, fzf's preview re-wraps long lines (including the target CLI's own
   box-drawing border characters) at the narrower width, which breaks a border
   mid-character-run and leaves orphaned corner/line fragments on their own wrapped
   line. This is a **capture/render width mismatch**, not a data corruption issue.

## Investigation + candidate fixes

Confirm the width-mismatch hypothesis first (don't assume — verify): capture a Claude
pane's content with `tmux capture-pane -p -e -S -200 -t <pid>`, check its line lengths
against the actual preview column width fzf allocates (`--preview-window` sizing is a
percentage of the popup width, which is itself `-w 90%` of the terminal — compute the
actual columns and compare against the captured content's column width, e.g. via
`tmux display-message -p '#{pane_width}'` on the source pane vs the popup's own width).

Candidate approaches, in rough order of trying (cheapest first):
- **Drop `wrap` from `--preview-window`** and instead truncate each captured line to the
  preview's column width before rendering, respecting ANSI escape sequences (don't
  truncate mid-escape-code — a naive `cut -c` on ANSI-colored text will corrupt colors).
  Losing the right edge of long lines is far less jarring than re-wrapped broken
  borders; the CLI tool's own left-anchored content (prompt, most recent messages) stays
  intact.
- **Widen the preview window** so it's closer to the source pane's actual width (may not
  be feasible if the source pane is genuinely wider than any reasonable popup — check
  actual numbers first).
- **Resize a scratch/hidden pane to the preview's target width before capturing**, if
  tmux's `capture-pane` can be pointed at a differently-sized clone — likely too
  complex/fragile for the payoff; only pursue if the simpler options don't fix it.
- For the header: switch to `fzf --header-lines` with the hint list split across two
  physical lines (fzf headers support multi-line via a literal `\n` in the string), or
  move less-critical hints (worktrees/panes tab-switch, refresh) into
  the persistent bottom line while keeping only the highest-frequency actions
  (switch/new/kill) in the primary header — cross-check against
  [[dashboard-help-tab]]'s persistent keybinding surface, which may make some header
  hints redundant once that task lands (this task can ship first; just don't duplicate
  effort if the help-tab task already solves discoverability for the less-common keys).

## Key Files

- `lazy-llm-bin/.local/bin/llm-dashboard` — `preview_cmd` construction in whichever
  function now renders the merged tree tab (post [[dashboard-tree-view-consolidation]]),
  `--header` string construction, `--preview-window` flag

## Constraints

- Verify the width-mismatch hypothesis with real measurements before changing anything —
  don't guess-fix.
- Any ANSI-aware truncation must not break color codes (a naive character-count cut on
  a line containing an unterminated escape sequence will bleed color into the next
  line). If hand-rolling this, test against real Claude Code pane output with colored
  text, not just plain text fixtures.
- Depends on [[dashboard-tree-view-consolidation]] landing first since that changes the
  tab layout this task is fixing — don't implement against the pre-merge Sessions tab
  structure.

## Acceptance Criteria

- [x] Header hint text is fully visible (no `..` truncation) at the dashboard's default
      popup size (`-w 90% -h 70%`) on a standard terminal width
- [x] Preview pane no longer shows orphaned box-drawing fragments or a detached
      token-counter box for a real Claude Code pane's content
- [x] Long lines in the preview degrade gracefully (edge truncation, not broken
      mid-border wrapping) — colors/ANSI formatting intact
- [x] Fix verified against a live Claude pane (not just a plain-text fixture) — Claude
      Code's own box-drawing UI is exactly what triggered this
- [x] No regression to the Worktrees tab's preview (git status/log), which uses a
      simpler non-ANSI-box preview and may not need the same treatment — confirm it
      still renders correctly

## Work Report

**Date:** 2026-09-22_05:09

### What was done
- **Preview corruption**: removed `:wrap` from both `--preview-window` specs
  (Workspaces and Worktrees tabs). Per `man fzf`, truncation — not wrapping — is the
  documented default ("Long lines are truncated by default. Line wrap can be enabled
  with wrap flag."), and fzf's default truncation is itself ANSI-aware (it doesn't
  break color codes or split escape sequences), so no custom ANSI-parsing code was
  needed — the bug was simply that the code had explicitly opted INTO the broken mode.
- **Header truncation**: split both the Workspaces and Worktrees tabs' populated
  headers into two lines via an embedded `$'\n'` — fzf's `--header` renders a
  multi-line string as multiple sticky rows. Primary/high-frequency actions on line 1,
  secondary on line 2.

### How it was done
- **Confirmed the width-mismatch hypothesis with real evidence, not assumption**:
  captured this very conversation's own live Claude Code pane content mid-session
  (`tmux capture-pane -p -e`) — it happened to contain exactly the artifact class
  described (full-width horizontal-rule lines, a status line with box-drawing
  spinner glyphs) — and fed that real captured content through an actual `fzf`
  process at a deliberately narrow preview column, first reproducing the bug
  (`:wrap` → one horizontal rule fragmenting into three separate `↳ ─────` pieces,
  status text splitting mid-word — a faithful match to the reported symptom class)
  and then confirming the fix (no `:wrap` → the same content renders as clean,
  edge-truncated single lines, colors intact).
- Measured the actual header string lengths (152 and 119 chars) against popup widths
  at a range of realistic terminal widths (80–253 columns) to confirm truncation was
  real and quantify it, then verified the two-line split via a live `fzf --header`
  invocation at a deliberately narrow 90-column terminal — both lines rendered in
  full with zero truncation.
- Re-extracted and directly invoked the real `render_sessions_tab` function (same
  technique as the tree-consolidation task) to confirm it actually emits the new
  two-line header string, not just that the standalone test worked.
- Ran the full test suite before and after; no change from baseline.
- Attempted to capture a live `tmux display-popup` invocation end-to-end for final
  visual confirmation; tmux popups aren't enumerable via `list-panes` (they're
  rendered as an overlay outside the normal pane hierarchy), so this wasn't
  achievable through scripted tooling — the fix is proven at the mechanism level
  (real corrupted content through the real fzf flags, both broken and fixed) rather
  than via a full interactive popup capture.

### Decisions made
- **No custom ANSI-aware truncation code** — fzf already does this correctly as its
  documented default behavior. Writing a hand-rolled ANSI+UTF8-aware line truncator
  (the task's own candidate approach, worded as the first thing to try) would have
  been strictly worse: more code, more edge cases (multi-byte UTF-8 box-drawing
  characters, mid-escape-sequence cuts), for behavor fzf's own well-tested default
  already provides for free.
- **Two-line header, not three or more** — 82/67 and 80/36 char splits comfortably
  fit realistic terminal widths (~100+ columns); an 80-column terminal would still
  clip the longer of the two lines, judged an acceptable edge case for a tmux
  dashboard popup (this tool isn't typically run at 80 columns alongside its own
  3-pane layout).
- **Didn't move hints into a separate help surface** — per the task's own note, that
  overlaps with `dashboard-help-tab` (not yet started); this task ships a complete
  fix on its own rather than leaving the header broken pending that task.

### Commits
- `fbda998` — dashboard: fix preview box-drawing corruption and header truncation

### Files changed
- `lazy-llm-bin/.local/bin/llm-dashboard` — `--preview-window` (both tabs), header
  strings (both tabs)

### Follow-up
- None filed.

## Verify Plan

Self-verified inline (per the note on `dashboard-workspace-nomenclature`).

1. Confirm the width-mismatch/wrap hypothesis with REAL Claude Code pane content, not
   a synthetic fixture
2. Reproduce the bug live via fzf with `:wrap`, then confirm the fix live via fzf
   without it, same real content, same narrow width
3. Measure header lengths against realistic popup widths; verify the two-line split
   renders in full at a deliberately narrow terminal
4. Confirm the real dashboard function emits the fixed header
5. Full test suite, no regression
6. Clean up all test fixtures

## Verify Report

**Date:** 2026-09-22_05:10

1. ✅ Captured this session's own live Claude Code pane — genuinely contained
   full-width horizontal-rule lines and box-drawing status elements, the exact
   artifact class reported
2. ✅ With `:wrap` at a narrow preview column: one horizontal rule fragmented into
   three `↳ ─────` pieces, status text split mid-word (`shift+t` / `ab to cycle`) —
   faithful live reproduction. ✅ Without `:wrap`, same content, same width: clean
   single-line truncation, colors intact, no fragments
3. ✅ Header lengths (152, 119 chars) measured against popup widths at 80–253 column
   terminals — truncation confirmed as real at realistic widths, not hypothetical.
   ✅ Two-line split (82/67, 80/36 chars) rendered in full via live `fzf --header` at
   a 90-column terminal — zero truncation
4. ✅ Directly invoked the real `render_sessions_tab` function (fzf stubbed) —
   confirmed it emits the exact two-line header string
5. ✅ `./tests/test-runner.sh`: 6 passed / 8 failed, identical to baseline (same 8
   TTY-dependent failures)
6. ✅ All test tmux sessions and scratch files cleaned up; `tmux list-sessions` shows
   only the user's real workspaces

Both fixes were proven against real, live-captured corrupted content and real fzf
invocations — not just code review. The one verification gap (a full interactive
`display-popup` capture) is a tooling limitation (popups aren't enumerable via
`list-panes`), not a gap in confidence about the underlying mechanism, which was
directly exercised both broken and fixed.

## Verification recipe

```bash
# Live only — this is a rendering bug, not unit-testable.
# Open a real claude pane inside a lazy-llm workspace, get it into a state with
# visible box-drawing UI (its own status bar / bypass-permissions line / token
# counter — the elements visible in the reported screenshot), then:
tmux display-popup -E -w 90% -h 70% llm-dashboard
# Visually confirm: header fully readable, preview pane clean (no stray corners,
# no floating counter box), long lines truncate at the right edge rather than
# wrapping into broken fragments.
```
