# Spec: workspace save/restore

Companion to the task `../workspace-save-restore.md`. The task file holds the brief, the
acceptance criteria and the work log. This file holds the design: every decision here is
settled, so an executor implements it as written. If a premise proves false, stop and report
it. Don't redesign.

Grounded in a read of the code at `d5c5b32` and in the live tmux state on 2026-09-27: three
workspaces (`ai-dev-workflow`, `dev-env`, `microdots_digital`) with 6 Claude panes, 3 of them
held.

---

## 1. Goal and scope

After the tmux server dies (crash, `kill-server`, reboot), one command, `lazy-llm restore`,
rebuilds every lazy-llm workspace that isn't running: same session names, same AI panes in
the same order (visible or held), same display names, the same Claude conversation per pane,
the same prompt file, and the same dashboard order and fold state.

**In scope**
- Recording each Claude pane's conversation ID.
- A manifest under XDG state, written when state changes.
- `lazy-llm save | restore | saved | forget`.
- Refactors that let restore reuse the launcher's own build code.
- The `@AI_PANE_NAMES` slot bug (§9.2), because names are saved by position.
- A headless test.

**Out of scope** (follow-ups, §13)
- Resuming non-Claude conversations.
- Restoring nvim editor state.
- A dashboard row for workspaces that are saved but not running.
- `--pick`.
- Non-lazy-llm windows inside a lazy-llm session.
- How the tmux server itself is started (the user decided against changing that).

## 2. Identity

| Concept | Definition |
|---|---|
| Workspace | A tmux session with `@lazy_llm 1` (unchanged). |
| Workspace ID | New session option `@lazy_llm_ws_id`: a random token, set once when the session is first marked. It survives renames, and restore sets it back to the saved value, so a restored workspace keeps its identity. Format: `$(date +%Y%m%d%H%M%S)-$(printf '%04x%04x' $RANDOM $RANDOM)`. |
| Workspace dir | New session option `@lazy_llm_dir`: the launcher's `TARGET_DIR` (for a `-W` workspace, the worktree path), set when the session is first marked. Restore uses it as the session's `-c`. |
| Server ID | `tmux display -p '#{pid}-#{start_time}'`. It tells "this server's own session was closed" apart from "that session died with an earlier server" (§6.3). |
| Lazy-llm window | A window with `@AI_PANES` set. Hold windows (`@lazy_llm_hold 1`, named `_hold_*`) are not windows in their own right: their panes are the owning window's held AI panes. |

A session can hold more than one lazy-llm window, because `lazy-llm` run inside tmux adds a
window to the current session. The manifest saves every lazy-llm window, in index order.
Other windows in the session aren't saved.

## 3. What gets saved, and where each field comes from

| Field | Source at save time |
|---|---|
| name | `#{session_name}` |
| dir | `@lazy_llm_dir`. **Adoption:** if unset (the workspace was started before this feature), take the prompt pane's `#{pane_current_path}` (the launcher `cd`s that pane into the target dir) and write it back to `@lazy_llm_dir`. |
| id | `@lazy_llm_ws_id`. Adoption: if unset, generate one and write it back. |
| collapsed | `@lazy_llm_collapsed` (`1`, or empty → `0`) |
| order | 0-based position in `lazy_llm_apply_ws_order "$(lazy_llm_gather_sessions)"` |
| per window: visible idx | window `@AI_PANE_IDX` |
| per window: prompt file | New window option `@lazy_llm_prompt_file`, set by the build function. Adoption: if unset, take the last argument ending in `.md` from `ps -o args= -p <child>` for each child (`pgrep -P #{pane_pid}`) of the `@PROMPT_PANE_ID` pane, and write it back. If nothing is found, leave the field empty (restore creates a new prompt file). |
| per pane: tool | `@AI_TOOLS[i]` |
| per pane: display name | `@AI_PANE_NAMES[i]` (`_` if missing or unset) |
| per pane: conversation ID | §4 (Claude only; `-` otherwise) |
| per pane: model | raw model id from `$_LAZY_LLM_MODEL_DIR/<pane_id>` with the pid guard (`-` if none). Add a raw reader; `lazy_llm_pane_model` shortens. |
| per pane: cwd | `#{pane_current_path}` of the AI pane (the foreground `claude`'s cwd, which is the project dir the transcript is keyed under) |

The adoption paths exist so workspaces started by an older launcher (the three live ones here,
and whatever is running on the Mac) are saved correctly. Each one writes its result back to
tmux, so it runs at most once per workspace.

Not saved: `%N` pane IDs, the legacy `@AI_PANE`/`@PROMPT_PANE`/`@AI_TOOL`/`@AI_PANE_ID` (the
build path sets these fresh), status, unread, busy markers.

## 4. Capturing conversation IDs (Claude)

Two sources. The first one that yields an ID wins.

1. **Hook record (primary; a documented contract).** Every Claude Code hook payload carries
   `session_id`. In `llm-claude-hook`, before the `case`, on every event:
   `sid=$(field session_id)`. If it's non-empty, call
   `lazy_llm_set_pane_conv "$PANE_ID" "$sid"`. That writes
   `~/.cache/lazy-llm/conv/<pane_id>` = `"<pane_pid> <session_id>"`, using the same pid guard
   and reuse-safety as the model store. It returns 0 if the value changed and 1 if it was
   unchanged. **Only on a change** does the hook call `lazy_llm_save_async`. `SessionStart`
   fires for `startup | resume | clear | compact`, so `/clear` and `--resume` are tracked.
   Stop re-sends the same ID and triggers nothing. Reader: `lazy_llm_pane_conv <pane_id>`,
   which returns an empty string if the file is missing or the pid is stale.
2. **Claude session registry (fallback; internal to Claude Code, best effort).** Claude Code
   writes `~/.claude/sessions/<claude_pid>.json` with `"sessionId":"<uuid>"` (confirmed on
   2.1.283: all 6 live panes resolved correctly, including the one that had restarted `claude`
   in the same shell). For each child `c` of the pane's `#{pane_pid}` (`pgrep -P`), if
   `~/.claude/sessions/$c.json` exists, pull `sessionId` out with grep/sed (no jq; same style as
   `field()`). This covers panes that were already running before the hook change and have
   been idle since, and setups with the plugin disabled.

If neither source yields an ID, save `-` and restore starts plain `claude` (it logs this).

Non-Claude tools: save `-` and start fresh. (Codex `resume <id>` and grok `--resume <id>`
exist, but capture needs per-tool work; see §13.)

## 5. Manifest

**Location:** `${XDG_STATE_HOME:-$HOME/.local/state}/lazy-llm/`, overridable with
`LAZY_LLM_STATE_DIR` (the tests use it).

```
lazy-llm/
  workspaces/<ws_id>   one file per saved workspace
  closed/<ws_id>       entries dropped by a deliberate close/forget (safety net, pruned after 30 days)
  .lock/               save/restore mutex (holds a pid file)
  .pending             "another save was requested while locked"
```

One file per workspace means save only ever rewrites the files of live workspaces. Nothing
another server wrote is touched, so no global rewrite can clobber a good entry.

**Format:** tab-separated records, one per line, key first. The format is chosen so that
bash `IFS=$'\t' read -r` parses it without jq, which keeps it portable to macOS. The last
field of `pane` is the cwd, so a path containing spaces is fine. Tabs and newlines in values
are not supported: session names, `@AI_PANE_NAMES` entries and tool names can't contain them
in practice, and save refuses (skips the workspace, logs to stderr) if one does.

```
version	1
id	20260927130000-3fa2c91e
name	dev-env
dir	/home/paulomuggler/Projects/dev-env
collapsed	0
order	2
server	3141-1789900000
saved	1789913801
window	0	1	/home/paulomuggler/Projects/dev-env/.lazy-llm/prompts/prompt-20260925-194824.md
pane	0	0	claude	lazy-llm-dashboard-improvements	11111111-1111-4111-8111-111111111111	claude-opus-5-5[1m]	/home/paulomuggler/Projects/dev-env
pane	0	1	claude	tmux-lazyllm-session-persistance	22222222-2222-4222-8222-222222222222	claude-opus-5-5	/home/paulomuggler/Projects/dev-env
pane	0	2	claude	general-system-UX-improvements	33333333-3333-4333-8333-333333333333	claude-opus-5-5	/home/paulomuggler/Projects/dev-env
```

- `gone <epoch>` (optional, one line): first time a save under the **same** server found this
  workspace not live (§6.3). Removed if the workspace shows up live again.
- `window <wseq> <visible_idx> <prompt_file>`: `wseq` is the window's 0-based position among
  the session's lazy-llm windows, not its tmux index.
- `pane <wseq> <idx> <tool> <name|_> <conv|-> <model|-> <cwd>`: `idx` is the position in
  `@AI_PANES`.
- The reader rejects a file with any `version` other than `1`: it prints an error naming the
  file and skips it.
- Writes are atomic: write `<file>.tmp.$$` in the same dir, then `mv`.

## 6. Save

### 6.1 Entry points

- `llm-persist save [--async]` is the only writer of `workspaces/` (apart from `forget` and
  restore's final save).
  - Plain `save` **waits** for the lock (polls up to 10s, then errors).
  - `--async` does the touch-`.pending`-and-exit described in §6.3 step 1 instead, and prints
    nothing.
  - Explicit and test calls use plain `save`, so they never return before their own write
    lands.
- `lazy_llm_save_async` (lib) is a fire-and-forget wrapper:
  `[ -x "$HOME/.local/bin/llm-persist" ] && ( "$HOME/.local/bin/llm-persist" save --async </dev/null >/dev/null 2>&1 & )`.
  It always returns 0. **Every fd must be redirected.** The dashboard calls it from fzf
  `transform()` subprocesses, and fzf reads the transform's stdout until EOF, so a background
  child that inherits stdout would stall the UI. (The review queue already notes ~1s of fold
  and reorder latency; this must not add to it.)

### 6.2 Triggers (call `lazy_llm_save_async` after the state change)

| Where | Event |
|---|---|
| lib build-window function (§9.1) | new workspace or window (covers `lazy-llm` and restore; restore also saves explicitly at the end) |
| `llm-add`, `llm-remove` | pane list changed |
| `llm-cycle` (after `lazy_llm_cycle_to_index`) | visible pane changed |
| `llm-dashboard` `action:rename:*`, `action:rename-pane:*` | names |
| `llm-dashboard` `--fold-transform`, `--reorder-transform` | fold, order (workspace and pane order) |
| `llm-claude-hook` | conversation ID changed (§4) |
| `llm-sessions --kill` | calls `llm-persist forget --id <ws_id>` **before** `kill-session` (§6.3) |
| tmux global hook `session-renamed`, registered by the build function next to `after-select-pane` | `run-shell -b '$HOME/.local/bin/llm-persist save --async'` (catches a Prefix-$ rename) |

**No `session-closed` hook, on purpose.** At shutdown or `kill-server`, the pane processes die
while the server is still up, so sessions close one after another with the server alive. A
save fired then would see "same server, session gone", which is exactly the case §6.3 treats
as a deliberate close, and it would start dropping the entries the reboot needs. The grace
period in §6.3 is the second line of defense against the same scenario.

`llm-pane-focus-track` does **not** trigger a save: it fires on every pane selection, and
`@AI_PANE_IDX` only changes meaningfully through cycling.

### 6.3 Algorithm

1. Take the lock (§6.4). If it's held: with `--async`, touch `.pending` and exit 0; without
   it, wait.
2. `srv=$(tmux display -p '#{pid}-#{start_time}' 2>/dev/null)`. **If there's no server, exit 0
   without touching anything.** This is the "don't clobber" guarantee: a save that runs with
   no server running never drops entries.
3. For each live lazy-llm session (`lazy_llm_gather_sessions`): run adoption (§3), build the
   record, and write `workspaces/<id>` with `server $srv`, `saved <now>`, and no `gone` line.
   Skip `@AI_PANES` entries that fail `lazy_llm_validate_pane`.
4. For each `workspaces/<id>` that isn't live:
   - If its `server` is not `$srv`, it died with an earlier server. **Leave the file exactly as
     it is.** That's what restore is for.
   - If its `server` is `$srv` (this server saw it alive):
     - With no `gone` line, add `gone <now>`.
     - With a `gone` line at least 60s old, move the file to `closed/<id>`: the server outlived
       the workspace, so someone closed it on purpose.

     The 60s grace means a save racing a dying server (shutdown, `kill-server`) can only
     *mark* entries. It can't drop them. Restore only picks entries from other servers
     (§7 step 1), so a mark never blocks a restore after a reboot.
5. Delete `closed/*` older than 30 days (`find -mtime +30`).
6. Release the lock. If `.pending` exists, remove it and go back to step 1 (at most once more).

`forget` (`--id <id>` or a name): move `workspaces/<id>` to `closed/`. For a name, match on the
file's `name` line among entries that aren't live. It errors if nothing matches, and asks you to
disambiguate with `--id` if two entries match.

Known edge, accepted: if the last lazy-llm session is closed with plain `tmux kill-session`,
tmux exits with the session, so no save runs with the old `$srv`. That entry survives and is
offered by the next restore. Remove it with `lazy-llm forget <name>`. The dashboard and
`lazy-llm kill` go through `forget`, so they don't hit this.

### 6.4 Lock

The lock is `mkdir "$STATE/.lock"` with `echo $$ > .lock/pid`. It uses `mkdir` rather than
`flock`, which macOS doesn't ship. If `mkdir` fails and the pid in `.lock/pid` is dead
(`kill -0` fails), remove the lock and retry once. That handles a lock left over from before
a reboot. Restore holds the same lock while it reads the manifest and builds, then drops it
before its final save.

## 7. Restore

`llm-persist restore [--dry-run] [name...]`

1. Take the entries in `workspaces/` whose `id` is **not** the `@lazy_llm_ws_id` of any live
   session. Default candidates are those whose `server` is **not** the current server: they
   died with an earlier one. Entries whose `server` is the current one were closed during this
   server's lifetime, so list them as skipped ("closed in this server") unless they're named
   explicitly. If names were given, keep only those (from either group); each name must match
   exactly one entry, or the command errors. With no server running, every entry is a
   candidate. Sort by `order`.
2. `--dry-run`: for each entry, print the name, dir, and each pane's tool, name, visibility,
   conversation ID and the exact launch command, then exit 0 without touching tmux.
3. For each entry:
   - If `dir` no longer exists, print a warning and skip.
   - **Name:** if a live session already has that name (a different workspace, since live IDs
     were filtered out in step 1), use the launcher's de-dup rule (`name-2`, `name-3`, …) and
     say so. Never merge into an existing session.
   - `tmux new-session -d -s <name> -n dev -c <dir>`. Set `@lazy_llm_ws_id <saved id>` and
     `@lazy_llm_dir <dir>` **before** building, so the build function's "set if unset" keeps
     them.
   - For each saved window, in `wseq` order: the first uses the session's initial window, and
     later ones use `new-window -d`. Prompt file: the saved path if the file still exists,
     otherwise a new `prompt-<ts>.md` in `<dir>/.lazy-llm/prompts/`. Build the window with
     pane 0's tool and launch command. Add panes 1..n with the lib add-pane function (they go
     to the hold window). Set `@AI_PANE_NAMES` from the saved names. Then
     `lazy_llm_cycle_to_index` to the saved visible index.
   - Set `@lazy_llm_collapsed 1` if `collapsed 1`.
4. **Order:** `@lazy_llm_ws_order` becomes the restored names in saved order, followed by the
   workspaces that were already live, in their current effective order.
5. Release the lock and run `llm-persist save` in the foreground (this stamps the entries with
   the current server).
6. Print a summary: restored, renamed, skipped (and why), and panes without a conversation ID.
   If outside tmux with a tty on stdin (`[ -z "$TMUX" ] && [ -t 0 ]`), attach to the first
   restored session. Otherwise print `tmux attach -t <first>`.

**Launch command:** `lazy_llm_tool_launch_cmd <tool> <conv|-> <model|->`
- `claude` with a conversation ID: `claude --resume <id>`, plus `--model '<model>'` when a
  model is recorded (see V2 in §12).
- Any other case: the tool name. This matches today's launcher, which sends just the tool
  name. The special `*)` branch that echoes `# AI Tool:` first goes away.
- If the pane's saved cwd differs from the workspace dir, restore prefixes `cd '<cwd>' && `
  (claude looks up `--resume` IDs under the project dir).

The command is typed into an interactive shell with `send-keys`, as today, so the user's
`claude` alias or wrapper (here: `--dangerously-skip-permissions`) still applies.

## 8. CLI surface

New script: `lazy-llm-bin/.local/bin/llm-persist` (`save`, `restore`, `saved`, `forget`,
`--help`), in the style of `llm-sessions`: sibling lib sourcing with the dev fallback, and
`set -euo pipefail`. Add these to the `lazy-llm` subcommand dispatch (`lazy-llm:67-71`):

```
save)    exec llm-persist save "$@"
restore) exec llm-persist restore "$@"
saved)   exec llm-persist saved "$@"
forget)  exec llm-persist forget "$@"
```

Update `-h` and `docs/USAGE.md`. `saved` prints one line per entry, marked live or saved:
name, dir, pane count, `n/m` panes with a conversation ID, and when it was last saved. With
`-v` it also lists the panes.

Because this is a new file in a stowed package, **re-run `install.sh`** (or restow
`lazy-llm-bin`) to create `~/.local/bin/llm-persist`.

## 9. Refactors and fixes

### 9.1 Move the build code into the lib (no behavior change for `lazy-llm` or `llm-add`)

- `create_workspace_window` (`lazy-llm:157-313`) moves to `lazy-llm-lib.sh` as
  `lazy_llm_build_window <session> <win_idx> <dir> <tool> <launch_cmd> <prompt_file>`.
  - It derives swap and undo dirs from `<dir>/.lazy-llm/`. It still `mkdir -p`s them, because
    restore doesn't call `init_state_dirs`, and it must not run `cleanup_old_files`, which
    would delete prompt files restore is about to reopen.
  - The per-tool `case` becomes one `send-keys "$launch_cmd"`.
  - New: set `@lazy_llm_prompt_file` on the window. Set `@lazy_llm_ws_id` and `@lazy_llm_dir`
    on the session only if they're unset. Register the `session-closed` and `session-renamed`
    hooks. Call `lazy_llm_save_async` at the end.
  - The launcher calls it with `launch_cmd="$AI_TOOL"`.
- The pane creation in `llm-add` (hold-window creation, split, `send-keys`, title, appending
  to `@AI_PANES`/`@AI_TOOLS`) becomes
  `lazy_llm_add_ai_pane <session> <window> <dir> <tool> <launch_cmd>` → prints the new pane
  ID. It works on an explicit target, not the ambient pane, so restore can call it. It also
  appends `_` to `@AI_PANE_NAMES` when that option is set, which keeps the slots in line.
  `llm-add` keeps its ambient resolution, the focus restore, and the cycle to the new pane, and
  calls `lazy_llm_save_async`.

### 9.2 Bug: `@AI_PANE_NAMES` isn't kept in line with `@AI_PANES`

`llm-remove` (`:190-198`) and `lazy_llm_prune_stale_panes` (`lib:356-407`) rebuild
`@AI_PANES`/`@AI_TOOLS` without the removed slot, but never touch `@AI_PANE_NAMES`. Every
display name after the removed pane shifts onto the wrong pane. This is live now: `dev-env`
has 4 names for 3 panes. Fix: drop the same index from the names array, padding with `_`
first, the way `lazy_llm_move_pane_order` does. Save then reads names by position, and
`lazy_llm_pane_display_label`'s fallback to `_` covers a short list.

This goes in its own commit, before the others.

## 10. Tests: `tests/scenarios/20-workspace-save-restore-unit.sh`

Model it on `19-claude-hook-unit.sh`. Isolation:
- A tmux server under `TMUX_TMPDIR=$sandbox/tmux`.
- `HOME=$sandbox/home`, with a stow-shaped `$HOME/.local/bin` symlinking every repo bin plus
  the lib.
- `LAZY_LLM_STATE_DIR=$sandbox/state`.
- `PATH=$sandbox/fake:$PATH`, where `fake/claude` and `fake/nvim` append `"$0 $*"` to
  `$sandbox/argv.log` and then `exec sleep 600`.

Because the sandboxed `HOME` has no `.bashrc`, the pane shells keep that `PATH`. Never touch
the user's real server; each tmux call uses the sandbox's `TMUX_TMPDIR` with `TMUX` unset.

Steps and assertions:
1. **Build.** Run `lazy-llm -s wsA -d $sandbox/a -t claude` (outside tmux, no tty: the final
   attach fails harmlessly) and `llm-add -t claude` twice into it (via `TMUX_PANE=<prompt pane>`).
   Run `lazy-llm -s wsB -d $sandbox/b -t claude`.
   - Feed the `SessionStart` payloads (`session_id` = fixed UUIDs) through `llm-claude-hook`
     for three panes.
   - For one wsB pane, write **no** hook record. Instead write
     `$HOME/.claude/sessions/<fake claude pid>.json` (registry fallback).
   - Set pane names with `@AI_PANE_NAMES`, cycle wsA to index 1, fold wsB, and move wsB above
     wsA with `lazy_llm_move_ws_order`.
2. **Save.** `llm-persist save`. Assert that both files exist with the expected
   `window`/`pane` lines (including the registry-sourced conversation ID) and the same
   `server`.
3. **No-server no-op.** `tmux kill-server`, then `llm-persist save`. Assert the manifest files
   are byte-identical to before.
4. **Restore.** `llm-persist restore`. Assert for both sessions:
   - `@lazy_llm 1` and the same `@lazy_llm_ws_id`.
   - `@AI_TOOLS`, the `@AI_PANES` count, `@AI_PANE_NAMES`, `@AI_PANE_IDX`.
   - A hold window with `@lazy_llm_hold 1` holding the non-visible panes.
   - `@lazy_llm_collapsed` on wsB.
   - `@lazy_llm_ws_order` = `wsB wsA`.
   - `argv.log` has `claude --resume <uuid>` for all 4 panes, and each prompt pane's `nvim`
     got the saved prompt file.
   - `llm-dashboard --emit-rows` lists `ws:wsB` before `ws:wsA`, with no pane rows under the
     folded wsB and 3 pane rows under wsA.
5. **Idempotent.** A second `llm-persist restore` restores nothing, and the session count is
   unchanged.
6. **Deliberate close.** `tmux kill-session -t wsA` (same server), then save. Assert
   `workspaces/<A>` still exists, now with a `gone` line. `llm-persist restore` skips it
   ("closed in this server"). Rewrite the `gone` timestamp to 61s ago and save again. Assert
   the file moved to `closed/`.
7. **Explicit kill.** `llm-sessions --kill wsB`. Assert `workspaces/<B>` is gone (in
   `closed/`).
8. **Collision.** Put a saved entry back from a "dead server" (copy `closed/<A>` to
   `workspaces/` with the `server` line rewritten), then create a live session `wsA` with a
   different ID. Restore. Assert that `wsA-2` exists with the saved ID and the live `wsA` is
   untouched (same pane count).
9. **Names fix.** In a 3-pane window with 3 names, `llm-remove -f 1`. Assert
   `@AI_PANE_NAMES` = names 0 and 2.

Also extend `19-claude-hook-unit.sh`: a payload with `session_id` records
`lazy_llm_pane_conv`, and a second event with the same ID reports unchanged.

The existing scenarios `01`–`19` must still pass. Run them through `tests/test-runner.sh`.

## 11. Pre-reboot runbook (this machine)

1. Implement, and get the tests green.
2. `cd ~/Projects/dev-env/external/lazy-llm && ./install.sh` (stows `llm-persist`; the hook
   is a live symlink, so running Claude panes pick up the new `llm-claude-hook` on their next
   event).
3. `lazy-llm save`, then `lazy-llm saved -v`. Expect 3 workspaces and 6 panes, all with
   conversation IDs (from the registry, for panes idle since the upgrade). `dev-env` shows 3
   names (the stale 4th is dropped), `dev-env` and `microdots_digital` have their held panes,
   and the order is `ai-dev-workflow microdots_digital dev-env`.
4. `lazy-llm restore --dry-run` prints "nothing to restore (all live)". To rehearse without
   touching the live workspaces, copy one file to a scratch state dir with its `server` line
   changed, then run `LAZY_LLM_STATE_DIR=<scratch> lazy-llm restore --dry-run` and read its
   launch commands.
5. Right before rebooting, run `lazy-llm save` one more time.
6. After the reboot, open a terminal (outside tmux) and run `lazy-llm restore`. Check the
   dashboard (Prefix+S), and in one pane press ↑ to confirm the conversation came back.

Manual fallback if restore fails: each `pane` line gives the pieces to run
`cd <cwd> && claude --resume <conv>` by hand.

## 12. Decisions made, and checks to run during execution

**Decided (don't revisit):**
- Rebuild workspaces through the lazy-llm build path, not tmux-resurrect.
- Write the manifest on events, not on a timer.
- One manifest file per workspace.
- The retention rule is based on server identity, with a 60s grace period (§6.3). There's no
  snapshot rotation.
- There's no `session-closed` hook (§6.2).
- Don't store the worktree branch: `dir` is the worktree path, which survives on disk.
- Restore never attaches when stdin isn't a tty.
- A name collision de-dups to `name-N`.
- Non-Claude tools start fresh.
- No `--pick`.

**Check during execution, each with its outcome already decided:**
- **V1 (resume keeps the ID).** In a throwaway sandbox server with a real `claude`, confirm
  that `claude --resume <id>` fires SessionStart with `source: resume` and the same
  `session_id`. If the ID differs, nothing changes: the hook records whatever arrives.
- **V2 (`--model` accepts the saved id).** Run
  `claude --model 'claude-opus-5-5[1m]' --resume <id>` in a throwaway sandbox and check that
  it starts without an error (resuming alone doesn't call the API; send no prompt). If it's
  rejected, restore drops `--model` altogether: the model is still saved and shown by
  `saved -v`.
- **V3 (registry after `/clear`).** Check whether `~/.claude/sessions/<pid>.json`'s
  `sessionId` follows a `/clear`. This is informational only: the hook record wins
  whenever it exists.

## 13. Follow-ups (backlog tasks to file after this lands)

- A dashboard section or row for saved-but-not-running workspaces, with restore and forget
  actions.
- Conversation capture and resume for codex (`codex resume <id>`) and grok (`--resume <id>`).
  Gemini only resumes by index or `latest`.
- nvim editor state (`:mksession` per workspace).
- `lazy-llm restore --pick` (fzf multi-select).
- `worktree-concurrency-mode`: per-pane worktrees would make the per-pane `cwd` field carry
  real weight. It's already in the format.
