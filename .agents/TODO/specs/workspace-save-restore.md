# Spec: workspace save/restore

Companion to the task `../done/workspace-save-restore.md`. The task file holds the brief, the
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

Revision 4 (2026-09-27 15:18), correcting revision 3 after checking the live nvims:
- The user's persistence setup is manual only (`qs` saves, `qr` restores). The "prompt
  overwrites editor on exit" bug didn't exist; the real problem is that both panes share one
  per-cwd session file.
- The prompt pane now gets its own persistence dir, and lazy-llm doesn't stop or change
  persistence in any other way.
- The snapshots are workspace-local (`<dir>/.lazy-llm/sessions/`), and the prompt one is
  restored on **every** open.
- Retention no longer deletes prompt files that a snapshot still references (§5.2).

Revision 5 (2026-09-27 23:20, after first use): **closing a workspace keeps it.** The user closed
workspaces and they vanished from the Saved tab. The vocabulary is now the user's: *close* keeps an
entry, *kill* and *forget* drop it.
- A new `closed` state (◇): kept, restored on demand only.
- The old hidden "closed" state is renamed `dropped` (✕), and `closed/` becomes `dropped/`.
- A workspace that vanishes under the same server becomes `closed` after the grace period, instead of
  being moved out.
- `lazy-llm close <name>`, `c` in the Saved tab, and a close-or-kill choice on the Workspaces tab's `K`.
- The dashboard's `s` shows "saving…" and then the summary in the tab header, not just a toast.
- The test runner isolates `LAZY_LLM_STATE_DIR`. Sections 2, 7.3, 8 and 9.3 below are updated to match.

Revision 6 (2026-09-28 00:00, after the first real reboot and restore). This supersedes §7.1–7.3,
§9.2 and §9.3 below where they differ:
- **Manual saves are dated snapshots.** Autosave keeps rewriting the rolling entry. A manual save
  (`save` with no `--async` or `--no-rpc`, `--notify` included) also writes
  `snapshots/<YYYYmmdd-HHMMSS>/<id>.json` for each workspace whose digest changed since its last
  snapshot. The digest covers the entry minus save metadata, plus its nvim snapshots' contents. The
  snapshot also copies the nvim snapshots, as `<id>/{editor,prompt}-N.vim` (`snap_editor` and
  `snap_prompt` in the JSON).
- `restore --snapshot <ts>/<id>` (or `<ts> <name>`) restores a snapshot:
  - If the workspace is running, it comes back as a copy: a new id, `name-N`, and its own nvim
    files `<dir>/.lazy-llm/sessions/<newid>-{editor,prompt}-N.vim`.
  - Otherwise it comes back as that workspace. The copies are written over its rolling nvim files
    first.
- `forget --snapshot <ts>[/<id>]` deletes a snapshot or one entry of it. There's no automatic
  pruning.
- **Saved tab:**
  - Rolling rows come first.
  - Then, newest first, a `snap-hdr:<ts>` divider per manual save, followed by `saved:<ts>/<id>`
    rows (◆).
  - `z` expands any entry into `saved-pane:<key>:<w>:<p>` rows, folded by default. The open set is
    kept in `@lazy_llm_saved_open`.
- **Prefix+S** is no longer guarded to lazy-llm windows. `llm-tmux-init`, run from tmux.conf at
  server start, registers the bindings in a fresh server. Without `--tab`, the dashboard opens on
  Saved when no workspace is running.
- **Restore speed** (4.9s → 1.6s with real nvims):
  - The final save runs with `--no-rpc`, with the pending async save cleared, and behind the attach.
  - Entries are read in one jq pass.
  - RPC snapshots run in parallel in every save.

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
- Editor and prompt nvim state through lazy-llm's rolling snapshots. The prompt pane's
  state comes back on every open. The two panes get separate manual (`qs`/`qr`) sessions
  (§5, §11.3).
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
| `closed` | Not live, and closed on purpose: `closed: true` in the entry, set by `lazy-llm close` / the dashboard, or by a save 60s after the workspace vanished under the same server. The state also covers the grace period itself (same server, `gone` set). Kept indefinitely, and restored only on demand: by name, with Enter in the Saved tab, or through the launcher's prompt. |
| `dropped` | In `dropped/`: killed (`lazy-llm kill`, the dashboard's kill) or forgotten. Hidden unless asked for (`saved --dropped`, `d`). Still restorable by name. Deleted after 30 days. |

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
| window `editor_session`, `prompt_session` | The window options `@lazy_llm_editor_session` and `@lazy_llm_prompt_session`: the snapshot paths from §5.2 (`<dir>/.lazy-llm/sessions/{editor,prompt}[-N].vim`). Adoption: if they're unset, assign them by the window's position. They're recorded whether or not the file exists yet; the launch only adds restore when the file is readable. |
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

Both nvims in a workspace get their state back after a workspace restore: open buffers,
splits, tabs, cursor positions. The **prompt pane goes further and restores its last state
every time it opens**, including a plain `lazy-llm` launch in that dir. The user keeps several
prompt files open in parallel, and every new buffer in that pane is backed by a
`.lazy-llm/prompts/prompt-<ts>.md` file (`llm-send`'s `<leader>fn` override, `364a727`). File
contents come from disk, unsaved text from the swap file (already under `.lazy-llm/swap`), and
undo history from the undofile (already under `.lazy-llm/undo`).

### 5.1 Facts this design rests on (checked live 2026-09-27)

- The user's persistence config (dev-env `dotfiles/omarchy/dot-config/nvim/lua/plugins/persistence.lua`,
  `a570bf6`) is **manual only**: its `config` only loads the options, so nothing is saved on
  exit and nothing is restored on start.
  - `<leader>qs` saves the session for the cwd (plus the git branch).
  - `<leader>qr` restores it.
  - `qS` picks a session, and `ql` loads the most recent one.
  - The session file is `stdpath("state")/sessions/<cwd>[%%<branch>].vim`.
- **Both nvims in a workspace have the same cwd**, so both resolve to the same persistence
  file. The prompt pane is launched as `cd '<dir>' && nvim … '<prompt file>'`. RPC
  `getcwd()` and `persistence.current()` on all six live nvims returned the project dir and
  one shared file per workspace (e.g. `…dev-env%%omarchy-4.vim` for both of `dev-env`'s
  panes). So today, `qs` in one pane overwrites what `qs` saved in the other, and `qr` in
  either pane loads whichever pane saved last.
- A tmux death sends SIGHUP to nvim, so nothing may depend on exit-time saving.
- nvim 0.12 runs as a TUI client plus an `nvim --embed` server child. The RPC socket belongs to
  the **server**: `$XDG_RUNTIME_DIR/nvim.<pid>.0` on Linux, `$TMPDIR/nvim.$USER/*/nvim.<pid>.0`
  on macOS. `nvim --server <sock> --remote-expr …` worked against every live nvim.

### 5.2 Two layers, never sharing a file

**Layer 1: the manual sessions keep working as today, but the two panes get separate files.**
`<leader>qs`, `qr`, `qS` and `ql` keep their bindings and behavior in both nvims. The one
change is the **prompt** nvim's session dir: `stdpath("state")/sessions/lazy-llm-prompt/`
instead of `…/sessions/`. The file inside is still named after the cwd (plus branch), so
`qs`/`qr` in the prompt pane save and restore that dir's prompt layout, and `qS` there lists
the prompt sessions of every project. The editor pane, and any nvim lazy-llm didn't start,
keep exactly today's dir and files.

**Layer 2: lazy-llm's automatic rolling snapshots.** There's one file per nvim, overwritten in
place and never added to. They live workspace-local, next to the `prompts/`, `swap/` and
`undo/` dirs that already exist:

```
<dir>/.lazy-llm/sessions/editor.vim     editor nvim of the session's 1st lazy-llm window
<dir>/.lazy-llm/sessions/prompt.vim     prompt nvim of the 1st window
<dir>/.lazy-llm/sessions/editor-2.vim   … 2nd lazy-llm window in the same session, and so on
```

The suffix is the window's position among its session's lazy-llm windows, and the build
function stores the chosen path in window options `@lazy_llm_editor_session` and
`@lazy_llm_prompt_session`. Keying the files by dir, not by workspace ID, is what lets a
**fresh** launch in a dir pick up that dir's last prompt state. Nothing in manual Layer 1
reads or writes these files.

| Snapshot | Autosaved | Auto-restored |
|---|---|---|
| `prompt*.vim` | always (debounced) | **on every open**: plain `lazy-llm` launch and workspace restore |
| `editor*.vim` | always (debounced) | only on workspace restore; a plain launch opens a bare `nvim` as today (the user has `qr` for that) |

**New stow package `nvim-session-plugin`** (added to `install.sh` `STOW_PACKAGES`):

- `.config/nvim/lua/lazy_llm/session.lua`, a module:
  - `snapshot(path)`: if at least one listed buffer has `buftype == ""` and a name, run
    `mksession! <path>.tmp` and then rename it to `<path>` (atomic). Return `path`. Otherwise
    return `""` and write nothing, so an empty nvim never overwrites a good snapshot. It uses
    the user's `sessionoptions`.
  - `restore(path)`: `vim.cmd("silent! source " .. fnameescape(path))` if the file is
    readable (see V5). Then wipe listed buffers that are unmodified, empty, and whose file no
    longer exists on disk (for example, prompt files removed by retention). In the prompt
    role, if no file buffer is left, open a new `.lazy-llm/prompts/prompt-<ts>.md`. That's the
    same 4 lines as `llm-send`'s `open_new_prompt_file`; move that function into this module
    and have `llm-send` call it, so it exists once.
  - `autosave(path)`: debounced (1s) `snapshot(path)` on `BufEnter`, `BufWritePost`,
    `BufDelete`, `WinClosed`, `TabClosed`, `FocusLost` and `VimLeavePre`.
  - `use_prompt_session_dir()`: point persistence at the prompt dir. It must win over the
    user's own `persistence.lua` `opts` whatever the spec merge order, so apply it **after**
    persistence's config has run. If `package.loaded["persistence.config"]` is set, assign
    `require("persistence.config").options.dir = <prompt dir>` and `mkdir -p` it. Otherwise
    register a `User LazyLoad` autocmd that does the same once `persistence.nvim` loads.
- `.config/nvim/lua/plugins/lazy-llm-session.lua`, a spec adding only an `init` to the
  persistence spec (it doesn't touch `opts`, `config`, `keys`, `lazy` or `cond`):

  ```lua
  return {
    "folke/persistence.nvim",
    init = function()
      local role, path = vim.env.LAZY_LLM_NVIM_ROLE, vim.env.LAZY_LLM_NVIM_SESSION
      if not role then return end                -- not started by lazy-llm: exactly as today
      local s = require("lazy_llm.session")
      if role == "prompt" then s.use_prompt_session_dir() end
      if path then
        vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function()
          if vim.env.LAZY_LLM_NVIM_RESTORE == "1" then s.restore(path) end
          s.autosave(path)
        end })
      end
    end,
  }
  ```

**Build function (§11.1): how the nvims are launched.** `<ep>`/`<pp>` are the window's snapshot
paths. `R` means "set `LAZY_LLM_NVIM_RESTORE=1`" and is added only when that snapshot is
readable.

| Case | Editor pane | Prompt pane |
|---|---|---|
| Plain launch | `LAZY_LLM_NVIM_ROLE=editor LAZY_LLM_NVIM_SESSION='<ep>' nvim` | prompt snapshot readable: `R` + role/session env + `nvim --cmd <swap/undo> --cmd <VimEnter ft/insert>`, **with no file argument and no new prompt file created**. Otherwise: as today, with a new `prompt-<ts>.md` argument. |
| Workspace restore | `R` + the same env, if `<ep>` is readable | same as a plain launch |

The prompt pane's `--cmd 'autocmd VimEnter * ++once set filetype=markdown | set showtabline=0 | startinsert'`
stays. It runs alongside the session's own `VimEnter` restore; `.md` buffers get their filetype
from detection anyway.

**Retention must not eat restored prompts.** Once prompts persist across opens, a prompt file
that's open but untouched for more than `PROMPT_RETENTION_DAYS` (7) would be deleted by the
launcher's `cleanup_old_files`, and its text lost. So `cleanup_old_files` skips any
`prompt-*.md` referenced by a `badd`/`edit` line in any `<dir>/.lazy-llm/sessions/prompt*.vim`.

**Save-time RPC (in `llm-persist save`), for every lazy-llm window, on both nvim panes.**
Find the pane's descendant `nvim` processes (`pgrep -P`, two levels deep) and the first socket
that exists for one of them. Then call
`luaeval('require("lazy_llm.session").snapshot(_A)', '<path>')` under a 2s timeout. This is
what gives the **already-running, pre-feature** nvims their first snapshots (adoption, §3,
assigns the two window options first). For nvims started by lazy-llm, it only refreshes a
snapshot their autosave keeps anyway. The stowed module is on every nvim's runtimepath, so
`require` works in nvims started before the install. The RPC never touches persistence.

**Timeout:** a lib helper `lazy_llm_with_timeout <secs> <cmd…>` that runs the command in the
background, polls, and kills it when time runs out. macOS has no `timeout`.

**Known edge, accepted:** two *different* lazy-llm sessions opened on the same dir, which is
unusual, since the launcher attaches to an existing session for a `-W` worktree. Both would
autosave to that dir's `prompt.vim`/`editor.vim`, and the last writer wins.

## 6. Manifest

**Location:** `${XDG_STATE_HOME:-$HOME/.local/state}/lazy-llm/`, overridable with
`LAZY_LLM_STATE_DIR` (the tests use it).

```
lazy-llm/
  workspaces/<ws_id>.json  one file per saved workspace
  dropped/<ws_id>.json     entries dropped by a kill or a forget (pruned after 30 days)
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
      "editor_session": "/home/paulomuggler/Projects/dev-env/.lazy-llm/sessions/editor.vim",
      "prompt_session": "/home/paulomuggler/Projects/dev-env/.lazy-llm/sessions/prompt.vim",
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
     - With `gone` at least 60s old, set `closed: true`. The entry stays in `workspaces/`.

     The grace means a save racing a dying server can only *mark* entries, never drop them.
5. Delete `dropped/*.json` older than 30 days. The nvim snapshots are workspace-local and are
   left alone: the next launch in that dir still wants `prompt.vim`.
6. Release the lock. If `.pending` exists, remove it and go back to step 1 (at most once more).

**forget** (`--id <id>` or a name): move `workspaces/<id>.json` to `dropped/`. With a name, it
matches non-live entries; an ambiguous match errors and asks for `--id`. **forget on a `dropped/`
entry** (dashboard `K` in the closed view) deletes it for good, after confirmation.

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
   explicitly from `restorable` or `closed` (a `dropped/` entry is moved back to `workspaces/`
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
     - Snapshots: set the two window options from the saved `editor_session` and
       `prompt_session`, so the same files keep rolling, then launch both nvims with restore
       as in the §5.2 table.
     - Prompt file (only used when there's no readable prompt snapshot): the saved
       `prompt_file` if it still exists, otherwise a new
       `<dir>/.lazy-llm/prompts/prompt-<ts>.md`.
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
  - The editor and prompt nvim commands follow the §5.2 table: role and session env, prompt
    auto-restore on a plain launch, and no new prompt file when a prompt snapshot exists.
    `cleanup_old_files` skips prompt files that a snapshot references.
  - New: `@lazy_llm_prompt_file` and the two session paths on the window; `@lazy_llm_ws_id` and `@lazy_llm_dir` on the session if unset;
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

### 11.3 Bug: the editor and prompt panes share one manual session file

Both nvims have the workspace dir as cwd, so `qs`/`qr` in either pane read and write the same
`sessions/<cwd>.vim` (§5.1). Fixed by §5.2 Layer 1: the prompt role uses
`sessions/lazy-llm-prompt/`. This goes in its own commit (the nvim plugin package), before the
save work.

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
     `SESSION=<a>/.lazy-llm/sessions/editor.vim` with no `RESTORE`, and the prompt pane's with
     `ROLE=prompt`, `…/prompt.vim`, no `RESTORE`, and a new `prompt-<ts>.md` argument (no
     snapshot yet).
2. **Save.** Plain `llm-persist save`. Assert both JSON files match the expected structure (jq
   assertions on `windows[].panes[]`, including the registry-sourced `conv`,
   `editor_session`/`prompt_session` equal to the window options, no snapshot files on disk
   (the fake nvims have no socket), and the same `server`).
3. **No-server no-op.** `kill-server`, then `save`. Assert the files are byte-identical.
4. **Restore.** Assert for both sessions:
   - `@lazy_llm 1` and the same `@lazy_llm_ws_id`.
   - `@AI_TOOLS`, the `@AI_PANES` count, `@AI_PANE_NAMES`, `@AI_PANE_IDX`.
   - A hold window with `@lazy_llm_hold 1` holding the non-visible panes.
   - `@lazy_llm_collapsed` on wsB.
   - `@lazy_llm_ws_order` = `wsB wsA`.
   - `argv.log` has `claude --resume <uuid>` for all 4 panes. wsB's prompt nvim (no snapshot)
     got the saved prompt file as its argument.
   - `llm-dashboard --emit-rows` lists `ws:wsB` first, with no pane rows under the folded wsB
     and 3 pane rows under wsA.
5. **Snapshots restore.** Before the step 4 restore, create both snapshot files for wsA. Assert
   that wsA's restored editor and prompt nvims logged `RESTORE=1` with the same `SESSION=`
   paths, that the prompt nvim got **no** file argument, and that no new `prompt-*.md` was
   created in `<a>/.lazy-llm/prompts/`.
5b. **Prompt auto-restore on a plain launch.** With `<b>/.lazy-llm/sessions/prompt.vim`
   present, a fresh `lazy-llm -s wsC -d <b>` starts its prompt nvim with `RESTORE=1` and no
   file argument, and its editor with no `RESTORE`.
5c. **Retention.** Backdate a prompt file referenced by a `badd` line of a prompt snapshot to
   10 days, and an unreferenced one too. Launch → the referenced file survives and the
   unreferenced one is deleted.
6. **Idempotent.** A second restore restores nothing, and the session count is unchanged.
7. **Deliberate close.** `kill-session -t wsA`, then save → `gone` is set. Restore skips it
   ("closed"), and `--emit-saved-rows --closed` shows it as `✕`. Backdate `gone` by 61s and
   save → the entry gets `closed: true` and stays in `workspaces/`. `restore wsA` brings it back (explicit), with the same ID.
8. **Close vs kill.** `llm-persist close wsK` keeps it (◇, skipped by a plain restore, back by name); `llm-sessions --kill wsB` → the file is in `dropped/`.
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
- `restore(p)` in a fresh nvim opens the buffers. A buffer whose file was deleted after the
  snapshot is wiped. In the prompt role, when nothing is left, a new
  `.lazy-llm/prompts/prompt-<ts>.md` is opened.
- **Prompt session dir:** after `use_prompt_session_dir()`, persistence's `save()` (what `qs`
  runs) writes under `…/sessions/lazy-llm-prompt/`, and `load()` (`qr`) reads from there. Test
  both the "already loaded" and the `User LazyLoad` paths. With no role, `save()` writes to
  `…/sessions/` exactly as before.
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
   - For each window, `<dir>/.lazy-llm/sessions/editor.vim` and `prompt.vim` exist. The
     editor's holds its buffers and the prompt's holds all the prompt files it has open.
     Nothing under `~/.local/state/nvim/sessions/` changed (compare mtimes before and after).
     Note that the running pre-feature prompt nvims still share the editor's manual session
     file until they're restarted; the reboot takes care of that.
4. `lazy-llm restore --dry-run` → nothing to restore. To rehearse, copy one file into a
   scratch state dir with a foreign `server`, then run
   `LAZY_LLM_STATE_DIR=<scratch> lazy-llm restore --dry-run` and read the launch commands.
5. Right before rebooting, press Prefix+C-s (or run `lazy-llm save`).
6. After the reboot, open a terminal and run `lazy-llm restore`. Check the dashboard
   (Prefix+S, then `3`), the editor buffers, and that one pane's conversation came back.

Manual fallback if restore fails: each pane gives `cd <cwd> && claude --resume <conv>`, and
each nvim gives `nvim -c 'source <dir>/.lazy-llm/sessions/{editor,prompt}.vim'`.

## 14. Decisions made, and checks to run during execution

**Decided (don't revisit):**
- Rebuild workspaces through the lazy-llm build path, not tmux-resurrect.
- Write the manifest on events, not on a timer.
- One JSON file per workspace, using jq.
- The retention rule is based on server identity, with a 60s grace period, and there's no
  `session-closed` hook.
- nvim state is saved in lazy-llm's own workspace-local rolling snapshots (one file per nvim),
  through `:mksession`. The prompt snapshot restores on every open; the editor snapshot only
  on workspace restore.
- persistence.nvim's keys and behavior are unchanged. The only change is that lazy-llm's
  prompt nvim uses the `sessions/lazy-llm-prompt/` dir.
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
- **V3 (the `init` merge and the prompt session dir, with the user's real config).** Run
  under a sandboxed `XDG_STATE_HOME`. In a prompt-role nvim, `<leader>qs` writes to
  `sessions/lazy-llm-prompt/<cwd>.vim` and `<leader>qr` loads it back; in an editor-role or
  no-role nvim, they use `sessions/<cwd>.vim` exactly as today. The prompt snapshot restores on
  launch, the editor one doesn't. If lazy.nvim drops the `init` merge, move the same body into a standalone spec file
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
