---
slug: workspace-save-restore
title: Save lazy-llm workspaces to a manifest and rebuild them after the tmux server dies (lazy-llm restore)
priority: P1
status: pending
created: 2026-09-25_20:44
updated: 2026-09-27_13:00
depends-on: []
tags: [resilience, restore, tmux, dashboard, design]
model: inline
commits: []
---

# Workspace save/restore

**Design: [`specs/workspace-save-restore.md`](specs/workspace-save-restore.md).** Every
decision there is settled. This file is the brief, the acceptance criteria and the work log.

**Deadline:** land this and run the pre-reboot runbook (spec §11) before the dev machine
reboots for BIOS changes. The three live workspaces (`ai-dev-workflow`, `dev-env`,
`microdots_digital`: 6 Claude panes, 3 of them held) are the real-world acceptance test.

## Context

On 2026-09-25 the whole default tmux server died, taking every lazy-llm workspace with it. Root
cause is outside lazy-llm: the server lived in the systemd scope of the Ghostty tab it was first
started from, and closing that tab killed the scope (full write-up and options in the dev-env
repo: `.agents/TODO/backlog/tmux-server-outside-terminal-cgroup.md`). The user decided against
re-plumbing how tmux is started and wants **lazy-llm itself to save and restore its workspaces**.
No work was lost (`claude --resume` recovers every conversation), but the workspace layout was:
which repos had workspaces, which AI panes each had, their names, order, fold state, and which
conversation each pane was on.

### Why tmux-resurrect can't do this

Resurrect restores tmux shape (sessions, windows, layouts, cwd, a whitelist of commands), but
not tmux user options or pane IDs. That is exactly where lazy-llm keeps its state:

| State | Where it lives | Survives resurrect? |
|---|---|---|
| Workspace marker | session `@lazy_llm` | no → workspace invisible to dashboard (`lazy_llm_gather_sessions` filters on it) |
| AI pane list, tools, index | window `@AI_PANES`, `@AI_TOOLS`, `@AI_PANE_IDX`, `@AI_PANE_ID`, `@AI_TOOL`, `@AI_PANE` | no, and the `%N` pane IDs are reassigned anyway |
| Prompt pane | window `@PROMPT_PANE_ID`, `@PROMPT_PANE` | no → `llm-send` can't find its AI pane |
| Hidden AI panes | window `@AI_HOLD_WIN`, hold window `@lazy_llm_hold` | no → `_hold_N` windows come back as plain windows |
| Display names | window `@AI_PANE_NAMES` | no |
| Dashboard order / folds | server `@lazy_llm_ws_order`, session `@lazy_llm_collapsed` | no |
| Per-pane model | `$_LAZY_LLM_MODEL_DIR/<pane_id>` files | keyed by the old pane ID → stale |
| Claude conversation | only in argv when the pane was started with `--resume <id>` | fresh panes have no id to resume |
| Prompt buffer | `nvim … .lazy-llm/prompts/prompt-*.md` with swap/undo `--cmd` flags | comes back as plain `nvim` |

Restoring a snapshot while same-named sessions are live also makes resurrect **merge** into
them, which mangles the live workspaces.

### What planning found (2026-09-27; details in the spec)

- `claude --resume <uuid>` exists, and every hook payload carries `session_id`, so the hook
  can track the current conversation, `/clear` included.
- Claude Code keeps `~/.claude/sessions/<pid>.json` with `sessionId`. It resolved all 6 live
  panes. It becomes the fallback for panes that were already running before this change.
- No jq dependency and macOS portability → the manifest is TSV parsed in bash, one file per
  workspace.
- A pre-existing bug: `llm-remove` and `lazy_llm_prune_stale_panes` never drop the
  `@AI_PANE_NAMES` slot, so names shift onto the wrong panes. It's live now (`dev-env`: 4
  names, 3 panes). It's fixed here, because names are saved by position.
- A hazard caught in design: a `session-closed` hook would fire during shutdown while the
  server is still up, and drop the very entries the reboot needs. So there's no such hook, a
  60s grace period applies before a same-server drop, and restore takes entries from dead
  servers.

## Key Files

- `llm-send-bin/.local/bin/lazy-llm-lib.sh`: gains `lazy_llm_build_window` and
  `lazy_llm_add_ai_pane` (moved in from the launcher and `llm-add`),
  `lazy_llm_tool_launch_cmd`, a conversation store (`lazy_llm_set_pane_conv` /
  `lazy_llm_pane_conv`), a Claude registry reader, a raw model reader,
  `lazy_llm_save_async`, and the names fix in `lazy_llm_prune_stale_panes` (`:356-407`).
- `lazy-llm-bin/.local/bin/lazy-llm`: `create_workspace_window` (`:157-313`) moves to the
  lib. It gains the `save|restore|saved|forget` dispatch (`:67-71`) and help text.
- `lazy-llm-bin/.local/bin/llm-persist`: **new**, holding `save`, `restore`, `saved`,
  `forget`.
- `llm-add-bin/.local/bin/llm-add`: calls the lib add-pane function, then save.
- `llm-remove-bin/.local/bin/llm-remove`: names slot fix (`:190-198`), then save.
- `llm-cycle-bin/.local/bin/llm-cycle`: save after a cycle.
- `lazy-llm-bin/.local/bin/llm-dashboard`: save after rename and rename-pane
  (`dispatch_action`, `:763-818`) and in `--fold-transform` / `--reorder-transform`
  (`:1128-1260`).
- `lazy-llm-bin/.local/bin/llm-sessions`: `cmd_kill` (`:52-85`) calls `forget` before
  `kill-session`.
- `llm-status-bin/.local/bin/llm-claude-hook`: records `session_id` on every event and saves
  on a change.
- `tests/scenarios/20-workspace-save-restore-unit.sh`: **new**.
- `tests/scenarios/19-claude-hook-unit.sh`: extended.
- `docs/USAGE.md`, `README.md`: document the commands.

## Read first

- `specs/workspace-save-restore.md`: the whole design. §6.3 (retention) and §7 (restore) are
  the load-bearing parts.
- `tests/scenarios/19-claude-hook-unit.sh`: the isolation pattern the new test copies
  (sandbox `TMUX_TMPDIR` plus `HOME`).
- `~/Projects/dev-env/.claude/coding-standards/frameworks/tmux-fzf.md`: `set -e` with
  fzf/tmux, and the testing notes (never send keys into a pane you haven't verified as a
  sandbox pane).
- `~/.claude/plugins/steward/skills/standards/references/principles.md` and
  `languages/shell.md`: lifecycle `development`.

## Constraints

- **Never touch the user's live tmux server during development or testing.** Every test and
  experiment runs under a sandbox `TMUX_TMPDIR` with `TMUX` unset. The live server gets exactly
  one mutating command before the reboot: `lazy-llm save` (spec §11), plus the read-only
  `saved` and `--dry-run`. Of those, only `save` writes, and it writes only
  `@lazy_llm_ws_id`, `@lazy_llm_dir` and `@lazy_llm_prompt_file` options through adoption.
- No new dependencies (no jq, no flock). Everything must run on macOS bash and BSD userland as
  well as Linux.
- `lazy_llm_save_async` redirects every fd (spec §6.1), or fzf `transform()` stalls.
- `llm-claude-hook` must always exit 0 and must not add latency to Claude's flow. The save it
  triggers is async, and only fires when the recorded conversation ID changes.
- Restore never merges into an existing session and never attaches without a tty.
- The refactor in spec §9.1 must not change behavior for `lazy-llm` or `llm-add`. Scenarios
  01–19 stay green.
- Out of scope: everything in spec §13. File those as backlog tasks when this lands.

## Commit plan (code commits, in order)

1. `@AI_PANE_NAMES` slot fix in `llm-remove` and `lazy_llm_prune_stale_panes` (spec §9.2).
2. Move the build and add-pane code into the lib, and add the launch-command helper. No
   behavior change (spec §9.1).
3. Conversation capture: conversation store, hook recording, registry fallback, raw model
   reader (spec §4).
4. `llm-persist save`, `lazy_llm_save_async`, the triggers, the new tmux options, and forget
   in `llm-sessions --kill` (spec §6).
5. `llm-persist restore | saved | forget`, plus the `lazy-llm` dispatch and help (spec §7–8).
6. Tests: scenario 20, plus the scenario 19 extension (spec §10).
7. Docs: `USAGE.md` and `README.md`.

Before each commit: `bash -n` and `shellcheck` on the changed scripts (the repo has no
formatter; match the surrounding style).

## Verification recipe

1. `cd tests && ./test-runner.sh`: everything passes, including 20.
2. Spec §12 V1–V3 in a sandbox server (real `claude`, no prompt sent). Record the outcomes in
   the Work Report.
3. `./install.sh`, then `ls -l ~/.local/bin/llm-persist`.
4. On the live server: `lazy-llm save`, then `lazy-llm saved -v`. Expect 3 workspaces and 6
   panes, 6 of 6 with conversation IDs; `dev-env` names that match the dashboard; held panes
   present; order `ai-dev-workflow microdots_digital dev-env`.
   `lazy-llm restore --dry-run` → nothing to restore.
5. Rehearse with a scratch state dir (spec §11 step 4). The launch commands must read
   `claude --resume <id>` with the right cwd.
6. After the reboot (human): `lazy-llm restore`. All three workspaces come back with the same
   names, panes, held panes, names, order and folds, and each pane is on its old conversation.

## Acceptance Criteria

- [ ] `@AI_PANE_NAMES` stays in line with `@AI_PANES` after `llm-remove` and after pruning.
- [ ] `lazy-llm` and `llm-add` build through the lib functions, with unchanged behavior
      (scenarios 01–19 green).
- [ ] The Claude hook records `session_id` per pane on every event and saves only on a change.
      The registry fallback resolves panes that have no hook record.
- [ ] `lazy-llm save` writes one manifest file per live workspace in the spec §5 format,
      adopting pre-feature workspaces.
- [ ] Save never drops or alters an entry from another server. With no server running it's a
      no-op. A same-server close is marked `gone` and dropped only after 60s.
      `lazy-llm kill` and the dashboard's kill forget the entry immediately.
- [ ] `lazy-llm restore` rebuilds every workspace from a dead server: session name (de-duped on
      a collision), workspace ID, AI panes in order with tools and names, held panes in a hold
      window, visible pane, `claude --resume <id>` per pane (cd'd into its cwd), prompt file
      reopened with swap/undo flags, folds and dashboard order. It's idempotent.
- [ ] `lazy-llm restore --dry-run`, `lazy-llm saved [-v]` and `lazy-llm forget <name>` work as
      specified, and `lazy-llm -h` lists them.
- [ ] Scenario 20 covers spec §10 steps 1–9, scenario 19 covers the conversation ID, and the
      full suite passes.
- [ ] `docs/USAGE.md` and `README.md` document save and restore, including when saves happen
      and the forget edge case.
- [ ] The pre-reboot runbook (spec §11 steps 2–5) has run on this machine, with its output in
      the Work Report.
- [ ] Spec §13 follow-ups are filed as backlog tasks.
