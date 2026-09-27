---
slug: workspace-save-restore
title: Save lazy-llm workspaces to a manifest and rebuild them after the tmux server dies (lazy-llm restore)
priority: P1
status: pending
created: 2026-09-25_20:44
updated: 2026-09-27_15:30
depends-on: []
tags: [resilience, restore, tmux, dashboard, nvim, design]
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
- All per-tool knowledge sits behind two adapter functions (`lazy_llm_tool_conv` and
  `lazy_llm_tool_launch_cmd`). Only Claude has a branch today; adding a tool means adding a
  branch to each.
- The manifest is one JSON file per workspace, handled with jq (the user approved jq as a
  dependency).
- nvim state for **both** panes is kept in lazy-llm's own workspace-local rolling snapshots
  (`<dir>/.lazy-llm/sessions/{editor,prompt}.vim`, one file per nvim, overwritten in place).
  The **prompt** snapshot restores on every open, so the several prompt files the user keeps
  open in parallel come back even on a plain `lazy-llm` launch. The editor snapshot restores
  on workspace restore.
- The user's persistence config is manual only (dev-env `a570bf6`: `qs` saves, `qr`
  restores, no exit save), and it stays as it is. **A real collision today:** both panes have
  the workspace dir as cwd, so they share one `qs`/`qr` file (confirmed over RPC on all six
  live nvims). The fix: the prompt role uses `sessions/lazy-llm-prompt/`.
- For nvims already running, `lazy-llm save` writes their first snapshots over nvim's RPC
  socket (confirmed live on 0.12: the socket belongs to the `--embed` child).
- The launcher's 7-day prompt retention must skip files that a snapshot references.
- A pre-existing bug: `llm-remove` and `lazy_llm_prune_stale_panes` never drop the
  `@AI_PANE_NAMES` slot, so names shift onto the wrong panes. It's live now (`dev-env`: 4
  names, 3 panes).
- A hazard caught in design: a `session-closed` hook would fire during shutdown while the
  server is still up, and drop the very entries the reboot needs. So there's no such hook, a
  60s grace period applies before a same-server drop, and restore takes entries from dead
  servers.
- Hot restore (restoring while other workspaces are running) is the normal path. Restore only
  creates sessions, and the launcher offers to restore when you open a dir that has a saved
  entry (spec §8).
- User surface: automatic saves, Prefix+C-s (registered on the live server by a plain
  `lazy-llm save`; no tmux reload needed), dashboard `s`, a new **Saved** tab (`3`) with
  restore, forget, restore-all and a closed view, and `lazy-llm save|restore|saved|forget`.

## Key Files

- `llm-send-bin/.local/bin/lazy-llm-lib.sh`: gains `lazy_llm_build_window` and
  `lazy_llm_add_ai_pane` (moved in from the launcher and `llm-add`), the tool adapters, a
  conversation store (`lazy_llm_set_pane_conv` / `lazy_llm_pane_conv`), a raw model reader,
  `lazy_llm_save_async`, `lazy_llm_with_timeout`, and the names fix in
  `lazy_llm_prune_stale_panes` (`:356-407`).
- `lazy-llm-bin/.local/bin/lazy-llm`: `create_workspace_window` (`:157-313`) moves to the
  lib. It gains the `save|restore|saved|forget` dispatch (`:67-71`), help text, and the
  "restore instead?" prompt (spec §8.2).
- `lazy-llm-bin/.local/bin/llm-persist`: **new**, holding `save`, `restore`, `saved`,
  `forget` and `find-dir`.
- `lazy-llm-bin/.local/bin/llm-dashboard`: the Saved tab plus `--emit-saved-rows`; `s` and
  the restorable-count header on the Workspaces tab; save calls after rename, rename-pane
  (`dispatch_action`, `:763-818`), `--fold-transform` and `--reorder-transform`
  (`:1128-1260`); the Help tab; `--tab saved`.
- `nvim-session-plugin/.config/nvim/lua/lazy_llm/session.lua` and
  `…/lua/plugins/lazy-llm-session.lua`: **new** stow package (spec §5.2).
- `install.sh`: jq in `DEPS`, and `nvim-session-plugin` in `STOW_PACKAGES`.
- `nvim-llm-send-plugin/.config/nvim/lua/plugins/llm-send.lua`: `open_new_prompt_file`
  (`:40-50`) moves into `lazy_llm/session.lua`, and the `<leader>fn` override (`:702-720`)
  calls it from there.
- `lazy-llm-bin/.local/bin/lazy-llm` `cleanup_old_files` (`:46-52`): skip prompt files that a
  snapshot references.
- `llm-add-bin/.local/bin/llm-add`: calls the lib add-pane function, then save.
- `llm-remove-bin/.local/bin/llm-remove`: names slot fix (`:190-198`), then save.
- `llm-cycle-bin/.local/bin/llm-cycle`: save after a cycle.
- `lazy-llm-bin/.local/bin/llm-sessions`: `cmd_kill` (`:52-85`) calls `forget` before
  `kill-session`.
- `llm-status-bin/.local/bin/llm-claude-hook`: records `session_id` on every event and saves
  on a change.
- `tests/scenarios/20-workspace-save-restore-unit.sh` and `21-nvim-session-unit.sh`:
  **new**. `19-claude-hook-unit.sh`: extended.
- `docs/USAGE.md`, `README.md`: document the commands, the keys and the Saved tab.

## Read first

- `specs/workspace-save-restore.md`: the whole design. The load-bearing parts are §5
  (editor), §7.3 (retention) and §8 (restore and hot restore).
- `tests/scenarios/19-claude-hook-unit.sh`: the isolation pattern the new tests copy
  (sandbox `TMUX_TMPDIR` plus `HOME`).
- `lazy-llm-bin/.local/bin/llm-dashboard` `render_worktrees_tab` (`:621-715`): the model for
  the Saved tab.
- `~/.local/share/nvim/lazy/persistence.nvim/lua/persistence/init.lua`: the API the nvim
  module works with, and dev-env's
  `dotfiles/omarchy/dot-config/nvim/lua/plugins/persistence.lua` (the user's manual-only
  override: `qs`/`qr`).
- `~/Projects/dev-env/.claude/coding-standards/frameworks/tmux-fzf.md`: `set -e` with
  fzf/tmux, and the testing notes (never send keys into a pane you haven't verified as a
  sandbox pane).
- `~/.claude/plugins/steward/skills/standards/references/principles.md` and
  `languages/shell.md`: lifecycle `development`.

## Constraints

- **Never touch the user's live tmux server during development or testing.** Every test and
  experiment runs under a sandbox `TMUX_TMPDIR` with `TMUX` unset, and nvim experiments use
  `--clean` or a sandboxed `XDG_STATE_HOME`. Before the reboot, the live server gets only
  `lazy-llm save` (writes adoption options and runs the editor save and prompt stop over RPC),
  `saved`, `--dry-run`, and Prefix+C-s.
- jq is the only new dependency (no flock). Everything must run on macOS bash and BSD
  userland as well as Linux (no `timeout`: use `lazy_llm_with_timeout`).
- `lazy_llm_save_async` redirects every fd (spec §7.1), or fzf `transform()` stalls. The
  dashboard's row rendering never runs RPC or save (spec §10).
- `llm-claude-hook` must always exit 0 and must not add latency to Claude's flow. The save it
  triggers is async, and only fires when the recorded conversation ID changes.
- Restore never modifies an existing session.
- Any nvim that lazy-llm didn't start (no `LAZY_LLM_NVIM_ROLE`) keeps today's persistence
  behavior exactly.
- The refactor in spec §11.1 must not change behavior for `lazy-llm` or `llm-add`, apart from
  the new role env vars. Scenarios 01–19 stay green.
- Out of scope: everything in spec §15. File those as backlog tasks when this lands.

## Commit plan (code commits, in order)

1. `@AI_PANE_NAMES` slot fix in `llm-remove` and `lazy_llm_prune_stale_panes` (spec §11.2).
2. `nvim-session-plugin` (module plus spec), move `open_new_prompt_file` from `llm-send` into
   the module, the role and session env on the launcher's two nvims, prompt auto-restore, the
   retention skip, and `install.sh` stowing the package (§5, §11.3). Include scenario 21.
3. Move the build and add-pane code into the lib, and add the tool adapters. No other
   behavior change (§11.1, §4).
4. Conversation capture: conversation store, hook recording, registry fallback, raw model
   reader, and the scenario 19 extension (§4).
5. `llm-persist save`, jq in `DEPS`, `lazy_llm_save_async`, the triggers, Prefix+C-s, editor
   save and prompt stop over RPC, the new tmux options, and forget in `llm-sessions --kill`
   (§7).
6. `llm-persist restore | saved | forget | find-dir`, the `lazy-llm` dispatch and help, and
   the launcher's "restore instead?" prompt (§8, §9.1).
7. Dashboard: the Saved tab, `s`, the header count, and the Help tab (§9.2–9.3).
8. Scenario 20 (§12).
9. Docs: `USAGE.md` and `README.md`.

Before each commit: `bash -n` and `shellcheck` on the changed scripts, and `stylua --check`
on the Lua if stylua is present (the repo has no formatter otherwise; match the surrounding
style).

## Verification recipe

1. `cd tests && ./test-runner.sh`: everything passes, including 20 and 21.
2. Run spec §14 V1–V3 in sandboxes (real `claude` with no prompt sent, and the real LazyVim
   config under a sandboxed `XDG_STATE_HOME`). Record the outcomes in the Work Report.
3. `./install.sh`, then check that `~/.local/bin/llm-persist` and
   `~/.config/nvim/lua/lazy_llm/session.lua` exist.
4. On the live server, run `lazy-llm save`, then `lazy-llm saved -v`. Expect:
   - 3 workspaces and 6 panes, 6 of 6 with conversation IDs.
   - `dev-env` names that match the dashboard.
   - Held panes present.
   - Order `ai-dev-workflow microdots_digital dev-env`.
   - An `editor_session` for each editor that has files open, and `…microdots.digital.vim`
     holding the editor's buffers again.

   Then `lazy-llm restore --dry-run` → nothing to restore. In the dashboard, `3` shows three
   `●` rows, and Prefix+C-s shows the save message.
5. Rehearse with a scratch state dir (spec §13 step 4). The launch commands must read
   `claude --resume <id>` with the right cwd, and the editor must get
   `LAZY_LLM_NVIM_SESSION`.
6. After the reboot (human): `lazy-llm restore`. All three workspaces come back with the same
   names, panes, held panes, names, order, folds and editor buffers, and each pane is on its
   old conversation.

## Acceptance Criteria

- [ ] `@AI_PANE_NAMES` stays in line with `@AI_PANES` after `llm-remove` and after pruning.
- [ ] Each workspace's editor and prompt nvims autosave to one rolling snapshot file each
      (`<dir>/.lazy-llm/sessions/`). The prompt snapshot restores on every open (with no
      stray new prompt file), and the editor snapshot on workspace restore. Retention skips
      prompt files a snapshot references.
- [ ] `qs`/`qr`/`qS`/`ql` work as today in both panes. The prompt pane's live in
      `sessions/lazy-llm-prompt/`, so the two panes no longer overwrite each other. nvims
      lazy-llm didn't start are unchanged.
- [ ] `lazy-llm` and `llm-add` build through the lib functions. Per-tool behavior sits only in
      the two adapter functions. Scenarios 01–19 are green.
- [ ] The Claude hook records `session_id` per pane on every event and saves only on a change.
      The registry fallback resolves panes that have no hook record.
- [ ] `lazy-llm save` writes one JSON file per live workspace in the spec §6 format, adopting
      pre-feature workspaces and snapshotting both nvims over RPC.
- [ ] Save never drops or alters an entry from another server. With no server running it's a
      no-op. A same-server close is marked `gone` and dropped only after 60s.
      `lazy-llm kill` and the dashboard's kill forget the entry immediately.
- [ ] `lazy-llm restore` rebuilds every restorable workspace while other workspaces are
      running: session name (de-duped on a collision), workspace ID, AI panes in order with
      tools and names, held panes in a hold window, the visible pane, `claude --resume <id>`
      per pane (cd'd into its cwd), the prompt file with swap/undo flags, the editor session,
      folds and dashboard order. It's idempotent, and it never modifies a live session.
- [ ] Explicit restore of `closed` entries, `--dry-run`, `saved [-v] [--closed]`,
      `forget <name>` and `find-dir` work as specified. `lazy-llm -h` lists the commands, and
      the launcher offers to restore a saved workspace for the dir it's opening.
- [ ] Prefix+C-s and dashboard `s` save now, with feedback. The Saved tab shows live,
      restorable and closed entries with a detail preview and supports Enter, `A`, `K`, `c`
      and `R` as in spec §9.3. The Workspaces tab header shows the restorable count.
- [ ] Scenarios 20 (§12 steps 1–12) and 21 are added, scenario 19 covers the conversation ID,
      and the full suite passes.
- [ ] `docs/USAGE.md`, `README.md` and the dashboard Help tab document save, restore, the keys,
      the Saved tab, when saves happen, and the forget edge case.
- [ ] The pre-reboot runbook (spec §13 steps 2–5) has run on this machine, with its output in
      the Work Report.
- [ ] Spec §15 follow-ups are filed as backlog tasks.
