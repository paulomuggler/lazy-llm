---
slug: dashboard-preview-render-fix
title: Fix dashboard layout — header truncation and corrupted ANSI preview rendering
priority: P2
status: in-progress
created: 2026-09-22_04:37
updated: 2026-09-22_05:05
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

- [ ] Header hint text is fully visible (no `..` truncation) at the dashboard's default
      popup size (`-w 90% -h 70%`) on a standard terminal width
- [ ] Preview pane no longer shows orphaned box-drawing fragments or a detached
      token-counter box for a real Claude Code pane's content
- [ ] Long lines in the preview degrade gracefully (edge truncation, not broken
      mid-border wrapping) — colors/ANSI formatting intact
- [ ] Fix verified against a live Claude pane (not just a plain-text fixture) — Claude
      Code's own box-drawing UI is exactly what triggered this
- [ ] No regression to the Worktrees tab's preview (git status/log), which uses a
      simpler non-ANSI-box preview and may not need the same treatment — confirm it
      still renders correctly

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
