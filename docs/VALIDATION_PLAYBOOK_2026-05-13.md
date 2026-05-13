# Validation Playbook — 2026-05-13 work-loop session

This playbook covers every deferred manual check across the 6 tasks shipped in the work loop on 2026-05-13. Each task's agent-verifiable surface (static checks, unit tests, live shell probes) was fully verified — what remains is interactive UI confirmation that requires human eyes and keystrokes.

## Pre-flight

The new keybindings are set at lazy-llm-workspace-creation time. Existing tmux servers that were running before this work landed still have the **old** `Prefix+S` and `Prefix+L` bindings registered. Two options to refresh:

**Option A — re-bind manually (fastest):**
```bash
# Repoint Prefix+S at the new dashboard
tmux bind-key -T prefix S if-shell \
  "tmux show-option -wqv @AI_PANES" \
  "display-popup -E -w 90% -h 70% '$HOME/.local/bin/llm-dashboard'"

# Retire Prefix+L
tmux unbind-key -T prefix L
```

**Option B — restart a workspace:** Just run `lazy-llm` once. The script re-registers both bindings (and now only registers `Prefix+S`).

For the statusline glyph (from `pane-status-detection`) to render, you'll also need this in your `~/.tmux.conf` if it isn't already there:
```
set -g status-right '#(llm-status)'
```
Optional: lower the refresh cadence so glyph transitions are visible faster:
```
set -g status-interval 1
```

---

## 1. `fix-llm-sessions-marker-bug` (commit `2f2bc18`)

Quick smoke: the `Prefix+S` popup used to be broken (always reported "no sessions"). It should now find your real sessions.

- [ ] **Prefix+S lists existing sessions.** From inside a lazy-llm session, press `Prefix+S`. Confirm both `dev-ai-dev-workflow-claude` and `dev-lazy-llm-claude` (or whatever lazy-llm sessions you currently have) appear. Press `Esc` — popup closes cleanly.
- [ ] **Empty-state popup closeable.** From a fresh tmux server with no lazy-llm sessions: `tmux display-popup -E '~/.local/bin/llm-sessions'`. Popup shows the empty header with `ctrl-n: new | esc: close`. `Esc` closes; `Ctrl-n` launches `lazy-llm`.

---

## 2. `pane-status-detection` (commit `2301c86`)

Status glyph shows after each AI tool name in the tmux statusline.

- [ ] **`AI: claude○`** appears in the statusline when claude is idle.
- [ ] **State transition `○ → ● → ○`.** Send a prompt to claude, watch the glyph become `●` (working) while it generates, then return to `○` (idle). Glyph updates within one `status-interval` tick.
- [ ] **`◐` on permission prompt.** Trigger a `[y/n]` style permission prompt in claude. Statusline glyph becomes `◐`. Resolving the prompt returns it to the active state.
- [ ] **Multi-pane statusline.** If you have multiple AI panes (claude + gemini), confirm both tools appear with independent glyphs, with the active one bracketed/bolded.

---

## 3. `dashboard-shell-and-sessions-tab` + `dashboard-panes-tab-and-prefix-l-retire` (commits `9b536db`, `885b305`, `8504d66`)

The Sessions and Panes tabs of the unified dashboard. Use one popup session for both — open via `Prefix+S` (or `tmux display-popup -E -w 90% -h 70% '~/.local/bin/llm-dashboard'`).

### Sessions tab (default)

- [ ] **Renders both sessions with status glyph + live preview.** The right-hand preview pane shows ANSI-rendered tail of the highlighted session's AI pane content.
- [ ] **Navigation:** `j`/`k` (or arrows) move selection, preview updates live as selection changes.
- [ ] **`Enter`** on a row switches to that session and closes the popup.
- [ ] **`K`** prompts a yes/no confirm; choosing `yes` kills the highlighted session and re-renders the list.
- [ ] **`r`** prompts for a new name (pre-filled with current), pressing `Enter` renames the session.
- [ ] **`n`** opens a nested lazy-llm popup to create a new session.
- [ ] **`?`** opens the help overlay showing all keybindings. Any keypress dismisses it.
- [ ] **`Esc`** / **`q`** closes the dashboard cleanly.

### Panes tab (press `3`)

- [ ] **Renders AI panes for the current session** with index, tool, status glyph, active marker, and pane ID. Live preview on the right shows the highlighted pane's content.
- [ ] **`Enter`** on a non-active pane cycles to it (visible AI pane swaps).
- [ ] **`]`** cycles to next AI pane; **`[`** cycles to previous. Verify the visible AI pane changes.
- [ ] **`a`** opens a tool picker (claude/gemini/codex/grok/aider); selecting one spawns a new AI pane and the tab refreshes.
- [ ] **`K`** prompts confirm; `yes` removes the highlighted pane.
- [ ] **Empty state**: switch to a tmux window without `@AI_PANES`, press `Prefix+S → 3`. Tab shows the "not a lazy-llm workspace" placeholder with `a: add` hint.

### Cross-tab navigation

- [ ] **Numeric tab keys** `1`/`2`/`3` switch between Sessions / Worktrees / Panes from any tab.

### Prefix+L is retired

- [ ] After refreshing bindings (pre-flight Option A or B above), press `Prefix+L`. It should fall through to tmux's default action (usually `next-layout`), NOT open the old `llm-panes` popup.

---

## 4. `worktree-per-task-primitive` (commit `3a3e54f`)

`lazy-llm -W <branch>` spawns a session bound to a git worktree.

- [ ] **From outside tmux, in this repo:** `lazy-llm -W _v_hv_outside`. Verify:
  - `.worktrees/_v_hv_outside/` directory created
  - `.worktrees/` is in `.gitignore` (already added during prior smoke)
  - A new tmux session is created and you're attached
  - `pwd` in each pane (AI/editor/prompt) reports the worktree path, not the repo root
  - Cleanup: detach, then `tmux kill-session -t dev-_v_hv_outside-claude && git worktree remove .worktrees/_v_hv_outside && git branch -D _v_hv_outside`
- [ ] **From inside an existing tmux session** (the load-bearing AC): in your currently attached session, run `lazy-llm -W _v_hv_inside`. Confirm:
  - A **new tmux session** appears (visible via `tmux ls`), NOT a new window in your current session
  - You're switched/attached to it
  - All panes rooted at the worktree path
  - Cleanup as above
- [ ] **Dedup attach**: while the `_v_hv_inside` session is still alive, run `lazy-llm -W _v_hv_inside` again. Confirm it prints "Existing lazy-llm session ... already at this worktree; attaching..." and switches/attaches instead of creating a duplicate.
- [ ] **`-W` + `-t` composition**: on a fresh branch name, run `lazy-llm -W _v_hv_tool -t gemini`. Confirm the spawned session is named `dev-_v_hv_tool-gemini` (tool suffix) and that gemini launches in the AI pane. Cleanup.

---

## 5. `worktree-bridge-tab` (commit `fa2d128`)

The Worktrees tab of the dashboard — `Prefix+S → 2`.

- [ ] **Worktrees tab renders.** Lists all worktrees in this repo. For each row: path, branch, dirty marker (`*` if dirty), ahead/behind (`↑N ↓N`), session attached (`●` if a lazy-llm session is at that path), PR state (`PR●` open / `PR✓` merged / `PRx` closed — only when `gh` configured and remote is GitHub).
- [ ] **Preview**: the right pane shows `git status -sb` + `git log --oneline -10` for the highlighted worktree, with colors.
- [ ] **`Enter`** on a row spawns or attaches to a lazy-llm session bound to that worktree (composes with `-W`).
- [ ] **`n`** prompts for a branch name. Type `_v_hv_dashboard_new`, `Enter`. Creates worktree + spawns session. Cleanup afterward.
- [ ] **`g`** launches `lazygit` in a nested popup pointed at the highlighted worktree. Confirm lazygit shows that worktree's branches/log/status.
- [ ] **`K` cleanup — clean worktree**: create a clean worktree (`git worktree add .worktrees/_v_hv_clean -b _v_hv_clean`), open the dashboard's Worktrees tab, highlight it, press `K`. Confirm:
  - Warning section shows "(no warnings — clean removal)"
  - First confirm asks "remove worktree?" — choose `yes`
  - Second confirm asks "delete branch?" — defaults to `yes` (clean cleanup → safe to delete)
  - Worktree dir gone, branch deleted, tab refreshes
- [ ] **`K` cleanup — dirty worktree with safety flow**:
  - `git worktree add .worktrees/_v_hv_dirty -b _v_hv_dirty && touch .worktrees/_v_hv_dirty/junk`
  - In the Worktrees tab, highlight `_v_hv_dirty` and press `K`
  - Confirm the warnings section shows: ⚠ Worktree has uncommitted changes
  - "remove worktree?" — choose `yes`
  - "delete branch?" — should default to `no` (warnings present → safer default)
  - Choosing `yes` for branch delete proceeds with `-D` (force)
  - Worktree dir and branch both gone afterward
- [ ] **PR state column** (if you have `gh` configured and the repo's remote is on GitHub):
  - Create a worktree on a branch that has an open PR
  - The PR cell in the row shows `PR●`
- [ ] **Main checkout guardrail**: try `K` on the main checkout row. Git refuses to remove the main worktree; confirm the error surfaces gracefully and the tab doesn't crash.

---

## Smoke test for "everything still works"

Quick sanity that the non-changed surfaces still operate:

- [ ] **`<leader>llms`** still sends the prompt buffer to the AI pane.
- [ ] **`<leader>llmp`** still pulls the latest response.
- [ ] **`<leader>llmk`** still forwards a keypress.
- [ ] **`<leader>ni`** still inserts a `[NOTE: ]` marker; **`<leader>np`** still collects project notes.
- [ ] **`llm-sessions --list`** from a shell still shows the sessions table.
- [ ] **`llm-sessions --kill <name>`** still works for non-interactive scripting.
- [ ] **`llm-panes`** from a shell now opens the dashboard at the Panes tab (alias works).

---

## Cleanup after validation

If any test artifacts remain:

```bash
# Worktrees created during validation
for wt in _v_hv_outside _v_hv_inside _v_hv_tool _v_hv_dashboard_new _v_hv_clean _v_hv_dirty; do
  git worktree remove --force ".worktrees/$wt" 2>/dev/null
  git branch -D "$wt" 2>/dev/null
done

# Test tmux sessions
for s in $(tmux ls -F '#{session_name}' 2>/dev/null | grep '^dev-_v_hv'); do
  tmux kill-session -t "$s"
done
```

---

## What to do if something fails

If any of the manual checks fail:

1. Don't try to fix it in your head — flag it. Either:
   - Comment in this file, or
   - Add it to `.agents/TODO/` as a new pending task (`/todo` to create), or
   - Push back in conversation so we can address it before backlog work

2. Each task's individual `.agents/TODO/done/<slug>.md` file has a Work Report explaining *what* was done and *why*. Useful for tracking down the boundary of the issue.

3. The relevant commits per task are:
   - `2f2bc18` fix-llm-sessions-marker-bug
   - `2301c86` pane-status-detection
   - `9b536db`, `885b305` dashboard-shell-and-sessions-tab
   - `3a3e54f` worktree-per-task-primitive
   - `8504d66` dashboard-panes-tab-and-prefix-l-retire
   - `fa2d128` worktree-bridge-tab
