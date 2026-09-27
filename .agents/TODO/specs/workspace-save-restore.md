# Spec: workspace save/restore

Companion to the task `../workspace-save-restore.md`. The task file holds the brief, the
acceptance criteria and the work log. This file holds the design: every decision here is
settled, so an executor implements it as written. If a premise proves false, stop and report
it. Don't redesign.

Grounded in a read of the code at `d5c5b32` and in the live state on 2026-09-27: three
workspaces (`ai-dev-workflow`, `dev-env`, `microdots_digital`) with 6 Claude panes, 3 of them
held; nvim 0.12.5 with LazyVim and persistence.nvim; tmux 3.7c; Claude Code 2.1.283; jq 1.8.2.

Revision 2 (2026-09-27 14:18), after the user's review:
- jq is allowed, so the manifest is JSON.
- nvim editor state is in scope (revision 3 reworks how; see §5).
- Each tool's handling goes through one adapter seam.
- The dashboard gets a Saved tab.
- There's an explicit save key.
- Hot restore is spelled out (§8).

Revision 3 (2026-09-27 14:44):
- The prompt pane's nvim state is restored too.
- lazy-llm keeps its own rolling snapshot, one file per nvim. persistence.nvim and its
  `<leader>q*` keys are left exactly as they are today (§5.2).
- Tmux bindings get registered on the live server by an explicit save (§11.1).

---

## 1. Goal and scope

After the tmux server dies (crash, `kill-server`, reboot), one command, `lazy-llm restore`, or
one dashboard key, rebuilds every lazy-llm workspace that isn't running: same session names,
same AI panes in the same order (visible or held), same display names, the same Claude
conversation per pane, the same prompt file, the same editor session (open buffers, splits,
tabs, cursor positions), and the same dashboard order and fold state.

**In scope**
- Recording each Claude pane's conversation ID through a per-tool adapter.
- A JSON manifest under XDG state, written when state changes.
- `lazy-llm save | restore | saved | forget`.
- Prefix+C-s to save now.
- A **Saved** tab in the dashboard.
- The launcher offering to restore instead of creating a new workspace.
- Editor and prompt nvim state through lazy-llm's rolling snapshots, plus the fix for the
  prompt nvim overwriting the editor's persistence session (§5, §11.3).
- Refactors that let restore reuse the launcher's build code.
- The `@AI_PANE_NAMES` slot bug (§11.2).
- Tests.

**Out of scope** (follow-ups, §15)
- Resume adapters for codex and grok (the seam exists; the branches don't).
- Restoring single panes into a live workspace.
- Non-lazy-llm windows inside a lazy-llm session.
- How the tmux server itself is started (the user decided against changing that).

## 2. Identity

| Concept | Definition |
|---|---|
| Workspace | A tmux session with `@lazy_llm 1` (unchanged). |
| Workspace ID | New session option `@lazy_llm_ws_id`: a random token, set once when the session is first marked. It survives renames, and restore sets it back to the saved value. Format: `$(date +%Y%m%d%H%M%S)-$(printf '%04x%04x' $RANDOM $RANDOM)`. |
| Workspace dir | New session option `@lazy_llm_dir`: the launcher's `TARGET_DIR` (for a `-W` workspace, the worktree path), set when the session is first marked. |
| Server ID | `tmux display -p '#{pid}-#{start_time}'`. It tells "this server's own session was closed" apart from "that session died with an earlier server" (§7.3). |
| Lazy-llm window | A window with `@AI_PANES` set. Hold windows (`@lazy_llm_hold 1`, `_hold_*`) are not windows in their own right: their panes are the owning window's held AI panes. |

A session can hold more than one lazy-llm window, because `lazy-llm` run inside tmux adds a
window to the current session. The manifest saves every lazy-llm window, in index order.

**Entry states**, used by the CLI, the dashboard and restore:

| State | Meaning |
|---|---|
| `live` | Its `id` is the `@lazy_llm_ws_id` of a running session. |
| `restorable` | Not live, and its `server` is not the current server: it died with an earlier one. With no server running, every non-live entry is restorable. |
| `closed` | Not live, with `server` equal to the current server (it was closed during this server's lifetime, marked `gone`), **or** moved to `closed/`. It can be restored when asked for explicitly. |

## 3. What gets saved, and where each field comes from

| Field | Source at save time |
|---|---|
| `name` | `#{session_name}` |
| `id` | `@lazy_llm_ws_id`. **Adoption:** if unset, generate one and write it back. |
| `dir` | `@lazy_llm_dir`. Adoption: if unset, take the prompt pane's `#{pane_current_path}` (the launcher `cd`s that pane into the target dir) and write it back. |
| `collapsed` | `@lazy_llm_collapsed == "1"` |
| `order` | 0-based position in `lazy_llm_apply_ws_order "$(lazy_llm_gather_sessions)"` |
| window `visible` | `@AI_PANE_IDX` |
| window `prompt_file` | New window option `@lazy_llm_prompt_file`, set by the build function. Adoption: if unset, take the last argument ending in `.md` from `ps -o args=` of the prompt pane's descendant `nvim` processes, and write it back. If nothing is found, use `null` (restore creates a new prompt file). |
| window `editor_session`, `prompt_session` | The window options `@lazy_llm_editor_session` and `@lazy_llm_prompt_session`: the fixed snapshot paths from §5.2. Adoption: if they're unset, assign `@lazy_llm_win_token` and both paths. They're recorded whether or not the file exists yet; restore only passes one on if it's readable. |
| pane `tool` | `@AI_TOOLS[i]` |
| pane `name` | `@AI_PANE_NAMES[i]`, or `null` when missing or `_` |
| pane `conv` | `lazy_llm_tool_conv <tool> <pane_id>` (§4), or `null` |
| pane `model` | Raw model id from `$_LAZY_LLM_MODEL_DIR/<pane_id>` with the pid guard (add a raw reader; `lazy_llm_pane_model` shortens), or `null` |
| pane `cwd` | The AI pane's `#{pane_current_path}` (the foreground tool's cwd, which is the project dir Claude keys transcripts under) |

The adoption paths exist so workspaces started by an older launcher (the three live ones here,
and whatever is running on the Mac) are saved correctly. Each one writes its result back to
tmux, so it runs at most once per workspace.

Not saved: `%N` pane IDs, the legacy `@AI_PANE`/`@PROMPT_PANE`/`@AI_TOOL`/`@AI_PANE_ID` (the
build path sets these fresh), status, unread, busy markers.

## 4. Tool adapter seam (conversation capture and resume)

All per-tool knowledge lives in two lib functions, each a single `case "$tool"`. **To support a
new tool, add one branch to each** (plus a capture source such as a hook, if the tool needs one).
Nothing else in save, restore or the manifest is tool-specific: `conv` and `model` are opaque
strings.

```bash
# Stdout: the pane's current conversation id, or nothing.
lazy_llm_tool_conv <tool> <pane_id>
#   claude) hook store first, then the registry fallback (below)
#   *)      nothing

# Stdout: the command line typed into the AI pane's shell.
lazy_llm_tool_launch_cmd <tool> <conv|""> <model|"">
#   claude) conv set: claude --resume '<conv>' [--model '<model>' (see V2)]
#           no conv:  claude
#   *)      <tool>
```

**Claude capture sources**, the first that yields an ID wins:
1. **Hook store (primary; a documented contract).** Every hook payload carries `session_id`.
   In `llm-claude-hook`, before the `case`, on every event: `sid=$(field session_id)`. If it's
   non-empty, call `lazy_llm_set_pane_conv "$PANE_ID" "$sid"`. That writes
   `~/.cache/lazy-llm/conv/<pane_id>` = `"<pane_pid> <session_id>"`, using the same pid guard
   and reuse-safety as the model store. It returns 0 if the value changed and 1 if it was
   unchanged. **Only on a change** does the hook call `lazy_llm_save_async`. `SessionStart`
   fires for `startup | resume | clear | compact`, so `/clear` and `--resume` are tracked.
   Reader: `lazy_llm_pane_conv <pane_id>`. The hook keeps its existing grep-based `field()`
   (it's on Claude's hot path); jq is for lazy-llm's own files.
2. **Claude session registry (fallback; internal to Claude Code, best effort).**
   `~/.claude/sessions/<claude_pid>.json` holds `sessionId`. It was confirmed against all 6
   live panes, including one that had restarted `claude` in the same shell. For each child `c`
   of the pane's `#{pane_pid}` (`pgrep -P`), read `jq -r .sessionId ~/.claude/sessions/$c.json`
   if the file exists. This covers panes that were running before the hook change and have been
   idle since.

The command is typed into an interactive shell with `send-keys`, as today, so the user's
`claude` alias or wrapper (here: `--dangerously-skip-permissions`) still applies. If a pane's
saved `cwd` differs from the workspace `dir`, restore prefixes `cd '<cwd>' && ` (claude looks
up `--resume` IDs under the project dir).

## 5. nvim state: editor and prompt panes

Both nvims in a workspace get their state restored: open buffers, splits, tabs, cursor
positions and cwd. For the prompt pane, that covers every prompt file it has open, not only
the current one. File contents come from disk. Unsaved text comes from the swap file (the
prompt nvim already keeps swap and undo under `.lazy-llm/`), and undo history comes from the
undofile.

### 5.1 Facts this design rests on (checked 2026-09-27)

- LazyVim ships `folke/persistence.nvim`, lazy-loaded on `BufReadPre`, with
  `branch = true, need = 1`. It saves `:mksession!` to
  `stdpath("state")/sessions/<cwd>[%%<branch>].vim` **only on `VimLeavePre`**. Its keys are
  `<leader>qs` (restore this dir's session), `qS` (pick one), `ql` (last) and `qd` (don't save).
  The user's config adds nothing on top.
- **A bug that exists today:** the prompt-buffer nvim runs with the same cwd, loads
  persistence (it reads the prompt file, which fires `BufReadPre`) and saves on exit, which
  overwrites the editor's session. `…%microdots.digital.vim` currently holds only
  `.lazy-llm/prompts/prompt-*.md` buffers.
- A tmux death sends SIGHUP to nvim. Whether `VimLeavePre` runs then isn't guaranteed, so
  nothing may depend on exit-time saving.
- nvim 0.12 runs as a TUI client plus an `nvim --embed` server child. The RPC socket belongs to
  the **server**: `$XDG_RUNTIME_DIR/nvim.<pid>.0` on Linux, and
  `$TMPDIR/nvim.$USER/*/nvim.<pid>.0` on macOS. It was confirmed live with
  `nvim --server <sock> --remote-expr 'luaeval(...)'` against the running editor.

### 5.2 Two mechanisms that never touch each other's files

**persistence.nvim stays as it is today in both nvims.** Its keys, its per-dir files and its
exit save are unchanged, with one exception: in the **prompt** nvim its exit save is turned off
(`persistence.stop()`), which fixes the overwrite bug. `<leader>qs` and the other keys still
work there.

**lazy-llm keeps its own rolling snapshots:** exactly **one file per nvim**, overwritten in place
and never added to.

```
$STATE/nvim/<ws_id>/<win_token>-editor.vim
$STATE/nvim/<ws_id>/<win_token>-prompt.vim
```

- `<win_token>` is a random per-window token, set once as window option
  `@lazy_llm_win_token`. The build function records both paths as window options
  `@lazy_llm_editor_session` and `@lazy_llm_prompt_session`. Restore reuses the saved paths,
  so the same two files keep rolling across restores.
- The directory `$STATE/nvim/<ws_id>/` is deleted when its entry is deleted for good (§7.3
  closed-pruning, or the Saved tab's closed-view `K`). Nothing else ever creates files in it,
  so it can't grow.

**New stow package `nvim-session-plugin`** (added to `install.sh` `STOW_PACKAGES`):

- `.config/nvim/lua/lazy_llm/session.lua`, a module:
  - `snapshot(path)`: if at least one listed buffer has `buftype == ""` and a name
    (persistence's own `need` filter), run `mksession! <path>.tmp` and then rename it to
    `<path>` (atomic). Return `path`. Otherwise return `""` and write nothing, so an empty
    nvim never overwrites a good snapshot. It uses the user's `sessionoptions`, just as
    persistence does.
  - `restore(path)`: `vim.cmd("silent! source " .. vim.fn.fnameescape(path))` if the file is
    readable (see V5).
  - `autosave(path)`: debounced (1s) `snapshot(path)` on `BufEnter`, `BufWritePost`,
    `BufDelete`, `WinClosed`, `TabClosed`, `FocusLost` and `VimLeavePre`.
  - `stop_persistence_autosave()`: `require("persistence").stop()` if
    `package.loaded.persistence`. Otherwise register a `User LazyLoad` autocmd that does it
    once `persistence.nvim` loads.
- `.config/nvim/lua/plugins/lazy-llm-session.lua`, a lazy.nvim spec that adds only an `init`
  to LazyVim's persistence spec. It changes neither `lazy` nor `cond`, so persistence loads
  exactly as it does today:

  ```lua
  return {
    "folke/persistence.nvim",
    init = function()
      local role, path = vim.env.LAZY_LLM_NVIM_ROLE, vim.env.LAZY_LLM_NVIM_SESSION
      if not role then return end            -- not started by lazy-llm: behave as today
      local s = require("lazy_llm.session")
      if role == "prompt" then s.stop_persistence_autosave() end
      if path then
        vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function()
          s.restore(path)
          s.autosave(path)
        end })
      end
    end,
  }
  ```

**Build function (§11.1):**
- Editor pane: `LAZY_LLM_NVIM_ROLE=editor LAZY_LLM_NVIM_SESSION='<editor path>' nvim`.
- Prompt pane: `LAZY_LLM_NVIM_ROLE=prompt LAZY_LLM_NVIM_SESSION='<prompt path>' nvim --cmd … '<prompt_file>'`.

The prompt file argument stays. With no snapshot yet, nvim opens it as today. With a
snapshot, the session sourced at `VimEnter` brings back the whole prompt-buffer layout, and
the current prompt file is part of it.

**Save-time RPC (in `llm-persist save`), for every lazy-llm window, on both nvim panes.**
Find the descendant `nvim` processes of the pane's `#{pane_pid}` (`pgrep -P`, two levels deep)
and the first socket that exists for one of them (the paths in §5.1). Then call it under a 2s
timeout:
- Both panes: `luaeval('require("lazy_llm.session").snapshot(_A)', '<path>')`.
- The prompt pane also gets `…stop_persistence_autosave()`.

This is what gives the **already-running, pre-feature** nvims their snapshots, and stops their
prompt nvims from overwriting the editor sessions at shutdown. For those nvims, adoption
(§3) first assigns `@lazy_llm_win_token` and the two paths. For nvims started by lazy-llm, it
just refreshes a snapshot their own autosave keeps anyway. The stowed module is on every
nvim's runtimepath, so `require` works in nvims started before the install.

**Timeout:** a lib helper `lazy_llm_with_timeout <secs> <cmd…>` that runs the command in the
background, polls, and kills it when time runs out. macOS has no `timeout`.

## 6. Manifest

**Location:** `${XDG_STATE_HOME:-$HOME/.local/state}/lazy-llm/`, overridable with
`LAZY_LLM_STATE_DIR` (the tests use it).

```
lazy-llm/
  workspaces/<ws_id>.json  one file per saved workspace
  closed/<ws_id>.json      entries dropped by a deliberate close or a forget (pruned after 30 days)
  .lock/                   save/restore mutex (holds a pid file)
  .pending                 "another save was requested while locked"
```

One file per workspace means save only ever rewrites the files of live workspaces. Nothing
another server wrote is touched, so no global rewrite can clobber a good entry.

**Format** (written with `jq -n --arg/--argjson`, read with `jq`). jq becomes a hard
dependency: add it to `install.sh` `DEPS`.

```json
{
  "version": 1,
  "id": "20260927130000-3fa2c91e",
  "name": "dev-env",
  "dir": "/home/paulomuggler/Projects/dev-env",
  "collapsed": false,
  "order": 2,
  "server": "3141-1789900000",
  "saved": 1789913801,
  "gone": null,
  "windows": [
    {
      "visible": 1,
      "prompt_file": "/home/paulomuggler/Projects/dev-env/.lazy-llm/prompts/prompt-20260925-194824.md",
      "editor_session": "/home/paulomuggler/.local/state/lazy-llm/nvim/20260927130000-3fa2c91e/5c1e9a0b-editor.vim",
      "prompt_session": "/home/paulomuggler/.local/state/lazy-llm/nvim/20260927130000-3fa2c91e/5c1e9a0b-prompt.vim",
      "panes": [
        { "tool": "claude", "name": "lazy-llm-dashboard-improvements",
          "conv": "11111111-1111-4111-8111-111111111111", "model": "claude-opus-5-5[1m]",
          "cwd": "/home/paulomuggler/Projects/dev-env" },
        { "tool": "claude", "name": "tmux-lazyllm-session-persistance",
          "conv": "22222222-2222-4222-8222-222222222222", "model": "claude-opus-5-5",
          "cwd": "/home/paulomuggler/Projects/dev-env" }
      ]
    }
  ]
}
```

- `gone` is the epoch of the first save under the **same** server that found the workspace not
  live (§7.3), or `null`. It's reset to `null` if the workspace shows up live again.
- The reader skips any file whose `version` isn't `1` and prints an error naming it.
- Writes are atomic: write `<file>.tmp.$$` in the same dir, then `mv`.

## 7. Save

### 7.1 Entry points

- `llm-persist save [--async]` is the only writer of `workspaces/` (apart from `forget` and
  restore's final save).
  - Plain `save` **waits** for the lock (polls up to 10s, then errors) and prints a one-line
    summary.
  - `--async` touches `.pending` and exits if the lock is held, and prints nothing.
- `lazy_llm_save_async` (lib) is a fire-and-forget wrapper:
  `[ -x "$HOME/.local/bin/llm-persist" ] && ( "$HOME/.local/bin/llm-persist" save --async </dev/null >/dev/null 2>&1 & )`.
  It always returns 0. **Every fd must be redirected.** The dashboard calls it from fzf
  `transform()` subprocesses, and fzf reads the transform's stdout until EOF, so a background
  child that inherits stdout would stall the UI. (The review queue already notes ~1s of fold
  and reorder latency; this must not add to it.)

### 7.2 Triggers

| Where | Event |
|---|---|
| lib build-window function (§11.1) | new workspace or window |
| `llm-add`, `llm-remove` | pane list changed |
| `llm-cycle` (after `lazy_llm_cycle_to_index`) | visible pane changed |
| `llm-dashboard` rename, rename-pane, `--fold-transform`, `--reorder-transform` | names, folds, order |
| `llm-claude-hook` | conversation ID changed (§4) |
| `llm-sessions --kill` | `llm-persist forget --id <ws_id>` **before** `kill-session` |
| tmux global hook `session-renamed`, registered by the build function | `run-shell -b '… save --async'` |
| **Prefix+C-s** (new binding, scoped to lazy-llm windows the way Prefix+S is; registered as in §11.1) | `run-shell '… save'`, then `display-message` with the summary ("lazy-llm: saved 3 workspaces, 6/6 conversations") |
| Dashboard `s` (Workspaces and Saved tabs) | foreground `save`, with its summary shown in the tab header after the refresh |

nvim state has its own trigger (each nvim's own autosave, §5.2). Every save also refreshes
both snapshots through RPC.

**No `session-closed` hook, on purpose.** At shutdown or `kill-server`, the pane processes die
while the server is still up, so sessions close one after another with the server alive. A save
fired then would see "same server, session gone", which is the "deliberate close" case of §7.3.
The grace period in §7.3 is the second line of defense against the same scenario.
`llm-pane-focus-track` doesn't save either: it fires on every pane selection.

### 7.3 Algorithm

1. Take the lock (§7.4). If it's held: with `--async`, touch `.pending` and exit 0; without it,
   wait.
2. `srv=$(tmux display -p '#{pid}-#{start_time}' 2>/dev/null)`. **If there's no server, exit 0
   without touching anything.**
3. For each live lazy-llm session: run adoption (§3) and the RPC editor save and prompt stop
   (§5.2), then build the record and write `workspaces/<id>.json` with `server = $srv`,
   `saved = now` and `gone = null`. Skip `@AI_PANES` entries that fail
   `lazy_llm_validate_pane`.
4. For each `workspaces/<id>.json` that isn't live:
   - If its `server` is not `$srv`, **leave the file exactly as it is**: it's `restorable`.
   - If its `server` is `$srv`:
     - With `gone == null`, set `gone = now`.
     - With `gone` at least 60s old, move the file to `closed/`.

     The grace means a save racing a dying server can only *mark* entries, never drop them.
5. Delete `closed/*.json` older than 30 days, along with each one's `$STATE/nvim/<id>/`.
6. Release the lock. If `.pending` exists, remove it and go back to step 1 (at most once more).

**forget** (`--id <id>` or a name): move `workspaces/<id>.json` to `closed/`. With a name, it
matches non-live entries; an ambiguous match errors and asks for `--id`. **forget on a `closed/`
entry** (dashboard `K` in the closed view) deletes it for good, after confirmation, together
with `$STATE/nvim/<id>/`.

Known edge, accepted: if the last lazy-llm session is closed with plain `tmux kill-session`,
tmux exits with the session, so the entry stays `restorable`. Remove it with
`lazy-llm forget <name>` or `K` in the Saved tab. `lazy-llm kill` and the dashboard kill go
through forget, so they don't hit this.

### 7.4 Lock

The lock is `mkdir "$STATE/.lock"` with `echo $$ > .lock/pid`. If `mkdir` fails and the pid is
dead (`kill -0` fails), remove the lock and retry once (covers a lock left over from before a
reboot). Restore holds the lock while it reads and builds, then releases it before its final
save.

## 8. Restore, including hot restore

`llm-persist restore [--dry-run] [--id <id>]… [name…]`

**Hot restore is the normal case, not a special one.** Restore always runs against whatever
tmux server is up, or starts one. It only ever **creates** sessions, never modifies or merges
into existing ones, so live workspaces (fresh ones started after a crash, or ones that never
died) are untouched. Concretely:

| Situation | What happens |
|---|---|
| Reboot or crash, no server yet | Every non-live entry is restorable. Restore starts the server and rebuilds them all. |
| After a crash you already started a fresh workspace elsewhere | The old entries are `restorable` (they have the old server ID) and are restored alongside it. |
| After a crash you ran `lazy-llm` in a dir that has a restorable entry | The launcher asks first (§8.2), so you normally never get a duplicate. If you did create a fresh one anyway, restore brings the saved one back as `name-2` next to it, and says so. |
| You closed a workspace earlier in this same server | It's `closed`. The default restore skips it; it comes back with an explicit `restore <name>` or from the Saved tab's closed view. |
| You want a live workspace put back to its saved state, or a removed pane back | Not supported. Restore never touches a live session. |

### 8.1 Algorithm

1. Candidates are the `restorable` entries, sorted by `order`. Names or `--id` pick entries
   explicitly from `restorable` or `closed` (a `closed/` entry is moved back to `workspaces/`
   first). Each selector must match exactly one entry, or the command errors. `live` entries
   are never candidates.
2. `--dry-run`: for each candidate, print the name, dir, each pane's tool, name, visibility,
   conversation ID and exact launch command, and the editor session. Exit 0 without touching
   tmux.
3. For each candidate:
   - If `dir` no longer exists, warn and skip.
   - **Name:** if a live session has that name, use the launcher's de-dup rule (`name-2`,
     `name-3`, …) and say so.
   - `tmux new-session -d -s <name> -n dev -c <dir>`. Set `@lazy_llm_ws_id` and
     `@lazy_llm_dir` from the entry **before** building, so the build function's "set if unset"
     keeps them.
   - For each window in order: the first uses the session's initial window, and later ones use
     `new-window -d`.
     - Prompt file: the saved one if it still exists, otherwise a new
       `<dir>/.lazy-llm/prompts/prompt-<ts>.md`.
     - Snapshots: set `@lazy_llm_win_token` and the two session paths from the saved
       `editor_session`/`prompt_session`, so the same files keep rolling. The nvims get
       `LAZY_LLM_NVIM_SESSION` as in §5.2, which restores their layout when the file is
       readable.
     - Build the window with pane 0's `lazy_llm_tool_launch_cmd`, add panes 1..n with
       `lazy_llm_add_ai_pane` (they go to the hold window), set `@AI_PANE_NAMES` (`_` for
       `null`), then `lazy_llm_cycle_to_index` to `visible`.
   - Set `@lazy_llm_collapsed 1` if `collapsed`.
4. **Order:** `@lazy_llm_ws_order` becomes the restored names in saved order, followed by the
   already-live workspaces in their current effective order.
5. Release the lock and run `save` in the foreground (this stamps the entries with the current
   server).
6. Print a summary: restored, renamed, skipped (and why), and panes without a conversation ID.
   - Outside tmux with a tty on stdin: attach to the first restored session.
   - Inside tmux with exactly one session restored (the dashboard case): `switch-client` to it.
   - Otherwise print `tmux attach -t <first>`.

### 8.2 Launcher: offer to restore instead

When `lazy-llm` is about to **create a new session** (either path, including `-W`) and stdin is
a tty, it runs `llm-persist find-dir <TARGET_DIR>` (hidden subcommand; realpath comparison).
That prints `<id>\t<name>\t<summary>` for each `restorable` entry with that dir. If there's
one, ask:

```
Saved workspace 'dev-env' for this dir (3 AI panes, 3 conversations, saved 2h ago).
Restore it instead? [Y/n]
```

`Y` (the default) runs `exec llm-persist restore --id <id>`. `n` continues with a fresh
workspace. With several entries, list them numbered, plus an `n` choice. Without a tty, don't
prompt: create the fresh workspace as today.

## 9. User surface

### 9.1 CLI

New script `lazy-llm-bin/.local/bin/llm-persist` (`save`, `restore`, `saved`, `forget`,
`find-dir`, `--help`), in the style of `llm-sessions`: sibling lib sourcing with the dev
fallback, and `set -euo pipefail`. Add these to the `lazy-llm` dispatch (`lazy-llm:67-71`):
`save`, `restore`, `saved` and `forget` → `exec llm-persist <sub> "$@"`. Update `-h`.

`saved [-v] [--closed]` prints one line per entry: state glyph, name, dir, AI panes (held
count), conversations `m/n`, and when it was last saved. `-v` adds per-window and per-pane
detail (tool, name, visible or held, conv, model, cwd, prompt file, editor session).
`--closed` includes `closed` entries.

Because this is a new file in a stowed package, **re-run `install.sh`**. It also stows the new
`nvim-session-plugin` and now requires jq.

### 9.2 Keys

| Key | Where | Action |
|---|---|---|
| Prefix+C-s | any lazy-llm window | save now, with a status message (§7.2) |
| `s` | dashboard, Workspaces tab | save now |
| `3` | dashboard, any tab | Saved tab |

Prefix+C-s is unbound by default and in the user's `tmux.conf`. It's the conventional "save
session" chord (tmux-resurrect's). That plugin exists only in `tmux.conf.backup`, so there's no
clash.

### 9.3 Dashboard: Saved tab (`3`)

Modeled on `render_worktrees_tab`, with the same modal search, `--height=100%` and
`print(KEY)+accept` binds. Row building goes in `_dashboard_build_saved_rows [--closed]` so a
test can call it through a hidden `--emit-saved-rows [--closed]` flag, the way `--emit-rows`
works for the Workspaces tab.

- **Rows:** one per entry, live first in dashboard order, then restorable by saved order, then
  (with the closed view on) closed. Columns: state glyph (`●` live, `◌` restorable, `✕` closed),
  name, `~`-shortened dir, AI panes (`3 (2 held)`), conversations `3/3`, and "saved 2h ago".
  The hidden first field is `saved:<id>`.
- **Preview:** `llm-persist saved -v --id <id>`.
- **Keys:**

  | Key | live | restorable | closed |
  |---|---|---|---|
  | Enter | switch to it | restore it, then switch to it | restore it, then switch to it |
  | `K` | ignored ("kill it from the Workspaces tab") | forget → closed (confirm) | delete for good (confirm) |

  - `A`: restore all restorable (confirm), then refresh.
  - `s`: save now.
  - `c`: toggle the closed view.
  - `R`: refresh. `1`/`2`/`?`: other tabs. `q`/Esc: quit.
- **Header:** `enter:restore/switch A:restore-all s:save K:forget c:closed R:refresh`, sized by
  `_dashboard_header_budget` like the other tabs.

**Workspaces tab:** when at least one entry is `restorable`, add a header line
`◌ N saved workspaces not running — 3: Saved` (counting these must be cheap: one `jq` over the
files, and no RPC). Add `s` to its binds.

Help tab: document the new keys. `llm-dashboard` usage: accept `--tab saved`.

## 10. Hot paths and performance

- The Workspaces header count and the Saved tab rows read the manifest only. They never RPC and
  never run save.
- `lazy_llm_save_async` returns immediately (§7.1).
- RPC is bounded by 2s per nvim, and it runs only inside `save`.

## 11. Refactors and fixes

### 11.1 Move the build code into the lib (no behavior change for `lazy-llm` or `llm-add`)

- `create_workspace_window` (`lazy-llm:157-313`) moves to `lazy-llm-lib.sh` as
  `lazy_llm_build_window <session> <win_idx> <dir> <tool> <launch_cmd> <prompt_file>`. It reads the session paths from the window options, setting them if unset.
  - It derives swap and undo dirs from `<dir>/.lazy-llm/` and `mkdir -p`s them. It must not
    run `cleanup_old_files`, which would delete prompt files restore is about to reopen.
  - The per-tool `case` becomes one `send-keys "$launch_cmd"`.
  - The editor and prompt nvim commands gain `LAZY_LLM_NVIM_ROLE` (and
    `LAZY_LLM_NVIM_SESSION`) as in §5.2.
  - New: `@lazy_llm_prompt_file`, `@lazy_llm_win_token` and the two session paths on the
    window; `@lazy_llm_ws_id` and `@lazy_llm_dir` on the session if unset;
    `lazy_llm_save_async` at the end.
  - The server-global hooks and key bindings it registers today (`after-select-pane`,
    Prefix+C-n/C-p/C-x/A/S), plus the new `session-renamed` hook and Prefix+C-s, move into
    `lazy_llm_register_tmux_integration` (idempotent). The build function calls it, and so
    does a plain (non-`--async`) `llm-persist save`. That's how a live server started before
    this feature gets Prefix+C-s without a tmux restart or config reload.
  - The launcher calls it with `launch_cmd="$AI_TOOL"`.
- The pane creation in `llm-add` becomes
  `lazy_llm_add_ai_pane <session> <window> <dir> <tool> <launch_cmd>` → prints the new pane ID.
  It creates the hold window if needed, splits, runs `send-keys`, sets the title, appends to
  `@AI_PANES`/`@AI_TOOLS`, and appends `_` to `@AI_PANE_NAMES` when that option is set. It works
  on an explicit target, so restore can call it. `llm-add` keeps its ambient resolution, the
  focus restore and the cycle to the new pane, and calls `lazy_llm_save_async`.

### 11.2 Bug: `@AI_PANE_NAMES` isn't kept in line with `@AI_PANES`

`llm-remove` (`:190-198`) and `lazy_llm_prune_stale_panes` (`lib:356-407`) drop the slot from
`@AI_PANES`/`@AI_TOOLS` but not from `@AI_PANE_NAMES`, so every name after it shifts onto the
wrong pane. This is live now: `dev-env` has 4 names for 3 panes. Fix: pad with `_`, then drop
the same index. This goes in its own commit, first.

### 11.3 Bug: the prompt nvim overwrites the editor's persistence session

Fixed by §5.2: the prompt role stops persistence's exit save, and the RPC `stop()` covers
prompt nvims that are already running. The keys keep working. This goes in its own commit,
before the save work.

## 12. Tests

**`tests/scenarios/20-workspace-save-restore-unit.sh`**, modeled on `19-claude-hook-unit.sh`.
Isolation:
- A tmux server under `TMUX_TMPDIR=$sandbox/tmux`, with `TMUX` unset.
- `HOME=$sandbox/home`, with a stow-shaped `$HOME/.local/bin` symlinking every repo bin plus
  the lib.
- `LAZY_LLM_STATE_DIR=$sandbox/state`.
- `PATH=$sandbox/fake:$PATH`, where `fake/claude` and `fake/nvim` append
  `"$0 $* ROLE=$LAZY_LLM_NVIM_ROLE SESSION=$LAZY_LLM_NVIM_SESSION"` to `$sandbox/argv.log`
  and then `exec sleep 600`.

Because the sandboxed `HOME` has no `.bashrc`, the pane shells keep that `PATH`. The fake nvim
has no socket, so the RPC finds nothing and no snapshot is written. That's the
graceful-degradation path, and asserting it is part of the test. Never touch the user's real
server.

1. **Build.** Run `lazy-llm -s wsA -d $sandbox/a -t claude`, then `llm-add -t claude` twice
   (via `TMUX_PANE=<prompt pane>`). Run `lazy-llm -s wsB -d $sandbox/b -t claude`.
   - Feed `SessionStart` payloads with fixed UUIDs through `llm-claude-hook` for three panes.
   - For one wsB pane, write no hook record. Instead write
     `$HOME/.claude/sessions/<fake claude pid>.json`.
   - Set names, cycle wsA to index 1, fold wsB, and move wsB above wsA.
   - Assert: the editor pane's fake nvim was started with `ROLE=editor` and
     `SESSION=$STATE/nvim/<id>/<token>-editor.vim`, and the prompt pane's with `ROLE=prompt`
     and the matching `-prompt.vim` path.
2. **Save.** Plain `llm-persist save`. Assert both JSON files match the expected structure (jq
   assertions on `windows[].panes[]`, including the registry-sourced `conv`,
   `editor_session`/`prompt_session` equal to the window options, no snapshot files on disk,
   and the same `server`).
3. **No-server no-op.** `kill-server`, then `save`. Assert the files are byte-identical.
4. **Restore.** Assert for both sessions:
   - `@lazy_llm 1` and the same `@lazy_llm_ws_id`.
   - `@AI_TOOLS`, the `@AI_PANES` count, `@AI_PANE_NAMES`, `@AI_PANE_IDX`.
   - A hold window with `@lazy_llm_hold 1` holding the non-visible panes.
   - `@lazy_llm_collapsed` on wsB.
   - `@lazy_llm_ws_order` = `wsB wsA`.
   - `argv.log` has `claude --resume <uuid>` for all 4 panes, and each prompt nvim got the
     saved prompt file.
   - `llm-dashboard --emit-rows` lists `ws:wsB` first, with no pane rows under the folded wsB
     and 3 pane rows under wsA.
5. **Snapshot paths carry over.** Before the step 4 restore, create both snapshot files for
   wsA. Assert the restored nvims logged the same `SESSION=` paths, and that the window
   options hold those same paths (the files keep rolling, with no new ones). Deleting wsA for
   good (step 7's closed-view `K`, via `forget` on a `closed/` entry) removes
   `$STATE/nvim/<id>/`.
6. **Idempotent.** A second restore restores nothing, and the session count is unchanged.
7. **Deliberate close.** `kill-session -t wsA`, then save → `gone` is set. Restore skips it
   ("closed"), and `--emit-saved-rows --closed` shows it as `✕`. Backdate `gone` by 61s and
   save → the file moves to `closed/`. `restore wsA` brings it back (explicit), with the same ID.
8. **Explicit kill.** `llm-sessions --kill wsB` → the file is in `closed/`.
9. **Collision.** Copy an entry into `workspaces/` with a foreign `server`, and create a live
   session with the same name and a different ID. Restore → `<name>-2` exists with the saved ID,
   and the live one is untouched.
10. **find-dir.** For a restorable entry, `llm-persist find-dir <dir>` prints its ID; for a live
    one it prints nothing.
11. **Saved rows.** `llm-dashboard --emit-saved-rows` shows the live, restorable and closed
    glyphs in the §9.3 order.
12. **Names fix.** In a 3-pane window with 3 names, `llm-remove -f 1` leaves names 0 and 2.

**`tests/scenarios/21-nvim-session-unit.sh`**: real headless nvim, and **no user config**:
`nvim --headless --clean`, with `rtp` = the installed `persistence.nvim` (from
`stdpath("data")/lazy/`; skip the scenario if it's missing) + the repo's
`nvim-session-plugin/.config/nvim`, `persistence` `dir` set to a sandbox, and
`XDG_STATE_HOME` sandboxed. Assert:
- `snapshot(p)` with a file buffer writes `p` containing that file and returns `p`. Calling it
  again overwrites the same single file (the dir holds exactly one file, and no `.tmp` is left).
- `snapshot(p)` with no file buffers returns `""` and leaves an existing `p` byte-identical.
- `restore(p)` in a fresh nvim opens the buffers.
- **Prompt role:** with `LAZY_LLM_NVIM_ROLE=prompt` and the plugin spec loaded through a
  minimal lazy.nvim bootstrap (or by calling `stop_persistence_autosave()` directly if the
  bootstrap is impractical under `--clean`), quitting with a file open writes **no** file into
  persistence's `dir`. With no role set, quitting writes one, as today.
- **RPC:** start nvim with `--listen $sandbox/n.sock` and a file open, then run
  `nvim --server … --remote-expr` with `snapshot(_A)`. Assert the returned path and the
  file.

**`19-claude-hook-unit.sh`**: extend it. A payload with `session_id` records
`lazy_llm_pane_conv`, and a repeat of the same ID reports unchanged.

The existing scenarios 01–19 must stay green (run `tests/test-runner.sh`).

## 13. Pre-reboot runbook (this machine)

1. Implement, and get the tests green.
2. Run `cd ~/Projects/dev-env/external/lazy-llm && ./install.sh`. It stows `llm-persist` and
   `nvim-session-plugin`. The hook is a live symlink, so running Claude panes pick it up on
   their next event.
3. Run `lazy-llm save`, then `lazy-llm saved -v`. Expect:
   - 3 workspaces and 6 panes, 6 of 6 with conversation IDs.
   - `dev-env` shows 3 names.
   - Held panes present.
   - Order `ai-dev-workflow microdots_digital dev-env`.
   - For each window, the snapshot files exist under `~/.local/state/lazy-llm/nvim/<id>/`:
     the editor's holds its buffers and the prompt's holds its prompt files. The prompt nvims
     had persistence's exit save stopped (check one with
     `--remote-expr 'luaeval("require(\"persistence\").active()")'` → `v:false`). The
     persistence file for each dir is left alone (`…microdots.digital.vim` still has its old,
     overwritten content until the editor nvim next exits normally).
4. `lazy-llm restore --dry-run` → nothing to restore. To rehearse, copy one file into a
   scratch state dir with a foreign `server`, then run
   `LAZY_LLM_STATE_DIR=<scratch> lazy-llm restore --dry-run` and read the launch commands.
5. Right before rebooting, press Prefix+C-s (or run `lazy-llm save`).
6. After the reboot, open a terminal and run `lazy-llm restore`. Check the dashboard
   (Prefix+S, then `3`), the editor buffers, and that one pane's conversation came back.

Manual fallback if restore fails: each pane gives `cd <cwd> && claude --resume <conv>`, and
each nvim gives `nvim -c 'source <editor_session|prompt_session>'`.

## 14. Decisions made, and checks to run during execution

**Decided (don't revisit):**
- Rebuild workspaces through the lazy-llm build path, not tmux-resurrect.
- Write the manifest on events, not on a timer.
- One JSON file per workspace, using jq.
- The retention rule is based on server identity, with a 60s grace period, and there's no
  `session-closed` hook.
- nvim state is saved in lazy-llm's own rolling snapshots (one file per nvim), through
  `:mksession`. persistence.nvim is untouched, apart from the prompt nvim's exit save.
- Don't store the worktree branch: `dir` is the worktree path, which survives on disk.
- A name collision de-dups to `name-N`, and restore never merges.
- Non-Claude tools start fresh until they get adapter branches.
- Restore is per workspace, not per pane.

**Check during execution, each with its outcome already decided:**
- **V1 (resume keeps the ID).** In a sandbox server with a real `claude`, confirm that
  `claude --resume <id>` fires SessionStart with `source: resume`. If the ID differs, nothing
  changes: the hook records whatever arrives.
- **V2 (`--model` accepts the saved id).** Run
  `claude --model 'claude-opus-5-5[1m]' --resume <id>` in a sandbox, without sending a prompt.
  If it's rejected, the claude adapter drops `--model` altogether (the model is still saved and
  shown).
- **V3 (the `init` merge and the prompt stop).** With the real config under a sandboxed
  `XDG_STATE_HOME`: in a prompt-role nvim, `<leader>qs` still loads the dir's session, and
  quitting writes nothing to persistence's `dir`. In a no-role nvim, behavior is exactly as
  today. If lazy.nvim drops the `init` merge, move the same body into a standalone spec file
  whose top level runs it at startup (files in `lua/plugins/` are evaluated when lazy loads the
  specs).
- **V5 (swap recovery through a sourced session).** After killing an nvim that has unsaved
  changes, check that `restore(path)` (`silent! source`) still shows nvim's swap-recovery
  prompt for that buffer. If `silent!` suppresses it, or the buffer opens read-only without
  asking, source without `silent!` (session errors then show, but recovery works).
- **V4 (registry after `/clear`).** Informational only: the hook record wins whenever it
  exists.

## 15. Follow-ups (backlog tasks to file after this lands)

- A codex adapter (`codex resume <id>`; capture its session ID from `~/.codex/sessions` or the
  process's open rollout file) and a grok adapter (`--resume <id>`). Gemini only resumes by
  index or `latest`.
- Multi-select in the Saved tab (restore a picked subset in one go).
- Minor QoL, low priority: per-pane restore into a live workspace (bring back a removed pane
  from its saved `conv`), and reverting a live workspace to its saved layout.
- `worktree-concurrency-mode`: per-pane worktrees would make the per-pane `cwd` carry real
  weight. It's already in the format.
