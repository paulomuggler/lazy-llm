# lazy-llm

A tmux + Neovim workflow for seamless interaction with agentic TUI tools like Claude Code, Gemini, &tc.

## Overview

lazy-llm creates a workspace — a tmux session with a three-pane layout optimized for AI-assisted development. ("Workspace" is lazy-llm's own term for this: one project directory, opened via `lazy-llm`, holding N AI panes + nvim + prompt pane. It's distinct from an individual LLM chat/conversation, which is what each AI pane runs.)

```
+------------------+------------------+
|                  |                  |
|    AI Tool       |      Neovim      |
|   (Claude/etc)   |     (Editor)     |
|                  |                  |
+------------------+------------------+
|                                     |
|          Prompt Buffer              |
|      (Scratch buffer for LLM)       |
+-------------------------------------+
```

Send prompts and confirmations directly from the prompt editor pane to the agentic TUI pane.

## Features

- **Three-pane layout**: AI tool, editor, and dedicated prompt buffer
- **Scratch buffer**: Bottom pane opens in an empty markdown buffer ready for editing
- **Instant sending**: Send buffers or selections to your LLM with keymaps
- **Keypress forwarding**: Respond to LLM prompts directly from the prompt buffer
- **Response pulling**: Pull the latest AI response back into your nvim buffer for annotation
- **Context picker**: Reference specific lines/blocks of code in your prompts (`<leader>llmr`)
- **File & folder references**: @ autocomplete with fuzzy picker supports both files and directories
- **NOTE markers**: Insert `[NOTE: ]` markers in code, collect and send all notes to AI (`<leader>n` prefix)
- **Smart window management**: Auto-detects if inside tmux and adds new window to current workspace
- **Git integration**: Editor pane includes vim-fugitive, gitsigns, and vgit for tracking changes
- **Multiple AI tools**: Supports Claude, Gemini, Codex, Grok, Aider, or any agentic TUI tool
- **Multi-AI pane tabbing**: Run multiple AI tools side-by-side, cycling between them with keybindings
- **Dashboard popup**: `Prefix+S` opens a tabbed popup (Workspaces / Worktrees / Saved, plus Help on `?`). The Workspaces tab is a collapsible tree — every workspace with its AI panes nested beneath it, each with its own status glyph and live ANSI preview, `z` to fold/unfold. Full keybinding reference is in the Help tab (`?` from any tab) — the dashboard's own headers only have room for a couple of hints
- **Save & restore**: workspaces are saved on every change; after the tmux server dies, `lazy-llm restore` rebuilds them — AI panes resuming their Claude conversations, display names, held panes, prompt and editor state, folds and order (see [Save & Restore](#save--restore))
- **Prompt pane memory**: the prompt pane reopens every prompt file it had open, in the same layout, whenever you open a workspace in that directory
- **Scoped keybindings**: All tmux and nvim bindings are scoped — no interference outside lazy-llm workspaces
- **Confirmation dialogs**: Removing AI panes requires confirmation (bypass with `--force`)
- **Stale pane recovery**: Dead panes are auto-pruned; holding windows auto-recover if accidentally closed

## Installation

### Prerequisites

- `bash` - Shell for scripts
- `stow` - For symlink management of the installation files
- `git` - Version control recommended, but optional
- `nvim` - Neovim with LazyVim configuration
- `tmux` - Terminal multiplexer

### Install

```bash
git clone https://github.com/paulomuggler/lazy-llm.git
cd lazy-llm
./install.sh
```

The installer will:
1. Check dependencies
2. Handle conflicting files (with backup option)
3. Create symlinks using stow
4. Verify `~/.local/bin` is in your PATH

**Important**: Restart Neovim after installation to load the new plugins.

## Usage

### Starting a Workspace

```bash
# Start with default AI tool (claude)
lazy-llm

# Specify a different tool
lazy-llm -t gemini
lazy-llm -t codex
lazy-llm -t grok

# Custom workspace name and directory
lazy-llm -s my-project -d ~/projects/foo -t claude
```

Options:
- `-s session_name` - Custom workspace (tmux session) name (auto-generated if not provided)
- `-d directory` - Working directory (defaults to current)
- `-t ai_tool` - AI tool to launch (claude, gemini, codex, grok, aider, etc.)
- `-w` - Force new window mode (otherwise auto-detected when in tmux)

**Smart Behavior:**
- **Outside tmux**: Creates new workspace or attaches to an existing one
- **Inside tmux**: Automatically adds new window to current workspace
- **With `-s <existing>`**: Adds window to that workspace (attaches if needed)
- **With `-W <branch>`**: Always creates a new workspace bound to a git worktree for `<branch>`; attaches to an existing lazy-llm workspace there if one already exists

### Worktree-per-task

For parallel work on multiple branches without stepping on each other:

```bash
# Create branch + worktree at .worktrees/feature-foo/, then spawn a workspace there
lazy-llm -W feature/foo

# Spawn with a specific AI tool
lazy-llm -W bugfix/auth -t gemini

# Override the worktree base path
LAZY_LLM_WORKTREE_DIR=$HOME/wt lazy-llm -W feature/foo
```

If the branch doesn't exist, it's created from current `HEAD`. If a worktree for it already exists, it's reused. If a lazy-llm workspace is already pointed at that worktree, you're attached to it instead of duplicating. Worktree binding is **workspace-scoped** — all panes (AI, editor, prompt) start in the worktree path, so `@` path completion and code references resolve correctly.

When using the in-repo default (`.worktrees/`), the path is automatically added to `.gitignore`. For cleanup, prefer the dashboard's Worktrees tab `K` action (atomic: kills attached workspace, removes worktree, optionally deletes branch — with safety prompts for dirty/ahead/open-PR cases) or fall back to `git worktree remove .worktrees/feature-foo && git branch -d feature/foo` from the shell.

### Worktree dashboard

`Prefix+S` → `2` opens the Worktrees tab. Lists all worktrees in the current repo with branch, dirty marker, ahead/behind vs default branch, attached lazy-llm workspace (`●`), and PR state (when `gh` is installed and the remote is GitHub).

Actions:
- `Enter` — open / attach a lazy-llm workspace in the highlighted worktree (via `lazy-llm -W`)
- `n` — new worktree + workspace (prompts for branch name)
- `g` — launch `lazygit` pointed at the highlighted worktree (delegates lifecycle ops)
- `K` — atomic cleanup with safety prompts: shows warnings for dirty / ahead-of-default / no-upstream / attached-workspace / open-PR, asks separately whether to also delete the branch
- `R` — refresh; `?` — help; `q`/`Esc` — close

### Isolated AI panes (per-pane worktrees)

Several agents in one workspace normally share its working tree, so their checkouts, staging and commits can collide. An **isolated** pane runs in a git worktree of its own instead, and merges its work back into the branch the workspace is on. It's opt-in per pane; plain `a` / `llm-add` behave exactly as before.

- **Add one:** `Prefix+S` → `A`, or `llm-add -i [-n name] [-t tool]`. `A` asks for a name, pre-filled with `<repo>-wt-<n>` (e.g. `dev-env-wt-1`), and that one name is the worktree's directory (`.worktrees/.panes/<name>`), its branch (`lazy/<name>`, from the main directory's current branch) and the pane's label. It's set once: renaming the pane later changes only the label. `.worktrees/` is ignored through `.git/info/exclude`, never your `.gitignore`. The tree row and border show `⎇`.
- **Add another pane to the same worktree:** `a` while an isolated pane is in view asks whether the new pane joins that worktree or the main directory; `llm-add -w <path>` from the shell.
- **Merging back is the agent's job.** Claude sessions in an isolated pane are told where they are at session start (and after resume and compaction): commit in logical units and run `llm-wt integrate` for each one. It rebases in the worktree, then fast-forwards the main directory's branch, and never forces, stashes or resets. Distinct exit codes tell the agent to commit first, resolve a conflict, or stop and ask you.
- **See it from the editor:** `<leader>llmw` flips the current file between the main copy and the visible AI pane's worktree copy (same line, editable; the winbar shows `⎇ <branch>`). Code references and notes from a worktree buffer carry the path the agent sees.
- **Closing:** removing the last pane in a worktree always asks: keep the worktree, remove it and its branch, or cancel. It lists anything that would be lost first: uncommitted or untracked files, commits not yet integrated, changed copies. Kept and orphaned worktrees show in the Worktrees tab tagged `⎇`, where `Enter` puts a pane back in one and `K` cleans it up.
- **Save/restore:** isolated panes come back in their worktrees. A deleted worktree whose branch survives is recreated.

`llm-wt status | sync | integrate` is the agent's (and your) view of a pane worktree; `llm-wt --help` has the rest.

**Untracked files.** A fresh worktree has tracked files only. The files listed in `~/.config/lazy-llm/worktree-files` (global) and `<repo>/.lazy-llm/worktree-files` (per repo, added after the global list) are linked into it from the main directory, or copied:

```gitignore
.env*                          # no prefix = link (shared with the main directory)
.claude/settings.local.json
copy: config/local.yml         # a copy of its own; changes are offered back on close
!.env.production               # exclude matches of this glob from the entries above
```

With neither file, the default list is `.env*`, `.claude/settings.local.json` and `.agents/TODO/.work-state`, all linked. Tracked files are never shadowed. Then `<repo>/.lazy-llm/worktree-init` runs in the new worktree if it's executable, for things like `npm ci`.

### AI pane border

Every AI pane's border ends with its git state: branch, `*` when tracked files changed, short commit, upstream, and `↑ahead ↓behind`, e.g. `main* 1b3dafc origin ↑2↓1`. An isolated pane shows `⎇ dev-env-wt-1→main 1b3dafc ↑3`, counted against the branch it merges into. `tmux set -g @lazy_llm_border_git off` hides it.

### Keymaps

All keymaps are under the `<leader>llm` prefix:

| Key | Mode | Action |
|-----|------|--------|
| `<leader>llms` | n/v | **Send** - Send buffer (normal) or selection (visual) to AI pane |
| `<leader>llmc` | n/v | **Command** - Send as slash command |
| `<leader>llm/` | n | **Slash Command** - Interactive slash command input |
| `<leader>llmd` | n | **Delete** - Clear prompt buffer content |
| `<leader>llmk` | n | **Keypress** - Forward next keypress to AI pane |
| `<leader>llmr` | n/v | **Reference** - Add inline code reference (raw) |
| `<leader>llmR` | n/v | **Reference** - Add code reference (wrapped) |
| `<leader>llmw` | n | **Worktree** - Toggle file ⇄ the visible AI pane's worktree copy |
| `<leader>llmp` | n | **Pull** - Pull latest AI response into buffer |
| `<leader>llm]` | n | **Next AI** - Cycle to next AI pane |
| `<leader>llm[` | n | **Prev AI** - Cycle to previous AI pane |
| `<leader>llma` | n | **Add AI** - Add new AI pane (prompts for tool name) |
| `<leader>llmx` | n | **Remove AI** - Remove current AI pane |

### File & Folder References with @ Autocomplete

Reference workspace files and directories in your prompts using the `@` symbol for path completion:

**Method 1: Fuzzy Finder (Fast)**
1. Type `@` in insert mode
2. Fuzzy picker opens showing all project files and folders
3. Type fragments to filter: `comp butt tsx`
4. Select item:
   - File → inserts: `@src/components/Button.tsx`
   - Folder → inserts: `@src/components/` (with trailing slash)

**Method 2: Native File Completion (Traditional)**
1. Type `@` followed by partial path: `@src/`
2. Press `<Ctrl-f>` to trigger vim's native file completion
3. Navigate directories level by level
4. Select files/folders to complete the path

**Example Prompts:**
```markdown
Please refactor @src/components/Button.tsx to use composition pattern.
Also update the tests in @tests/Button.test.tsx accordingly.

Review all files in @src/api/ and identify potential performance issues.
```

The `@` prefix helps LLM tools identify workspace file references and can be parsed by your AI tool for context loading.

**Tip**: For git-root-relative paths, ensure your nvim working directory is set to the repository root (use `:cd` or a rooter plugin).

### Code Context References

Add specific line or block references from your workspace editor to the prompt buffer:

**In Workspace Editor (top-right pane):**
1. **Single line**: Position cursor on the line
2. **Code block**: Visually select the lines (V + j/k)
3. Press `<leader>llmr` (reference)
4. Reference appears in prompt buffer

**Example References:**
```markdown
# Single line reference
# See line 42 in src/components/Button.tsx

# Multi-line block reference
# See lines 42-50 in src/api/client.py
```

The LLM can use these lightweight references to understand context without including full file contents. Perfect for code reviews, debugging, or referencing specific implementations.

### NOTE Markers

Add inline notes throughout your codebase that can be collected and sent to your AI tool. Perfect for marking TODO items, questions, or context you want the AI to address.

**Keymaps** (under `<leader>n` prefix):

| Key | Action |
|-----|--------|
| `<leader>ni` | **Insert Note** - Append ` [NOTE: ]` to the end of the line, ready to type |
| `<leader>nI` | **Insert Note Below** - `[NOTE: ]` as a comment in the file's syntax (`-- [NOTE: ]`, `# [NOTE: ]`, `<!-- [NOTE: ] -->`…) on a new line below, at the line's indentation |
| `<leader>nb` | **Buffer Notes** - Send all notes from current file to prompt pane |
| `<leader>np` | **Project Notes** - Send all notes from entire project to prompt pane |
| `]n` | **Next Note** - Jump to next note in buffer |
| `[n` | **Previous Note** - Jump to previous note in buffer |
| `<leader>n/` | **Search Notes** - Fuzzy picker for all project notes; `alt-h` / `alt-i` include hidden / gitignored files |
| `<leader>nq` | **Quickfix Buffer** - Buffer notes to quickfix list |
| `<leader>nQ` | **Quickfix Project** - Project notes to quickfix list |
| `<leader>nn` | **Notification History** - LazyVim's `<leader>n`, moved here |

Inside tmux, LazyVim's own `<leader>n` (Notification History) moves to `<leader>nn`
so `<leader>n` is a plain which-key group: a key that is both a command and a
prefix only waits `timeoutlen` for the rest, and pausing after `<leader>n` used to
open the history instead of running the note command.

**Note Format:**
```
[NOTE: your note text here]
```

**Example Usage:**
```python
def calculate_total(items):
    # [NOTE: Should this handle empty lists differently?]
    return sum(item.price for item in items)

class UserService:
    # [NOTE: Consider adding caching here for performance]
    def get_user(self, user_id):
        return self.db.query(User).get(user_id)
```

**Pulling Notes to Prompt:**

When you press `<leader>np` (project notes), all notes are collected and sent to the prompt pane:

```markdown
## Notes from project

### - **src/services/user.py:42**
[NOTE: Should this handle empty lists differently?]

### - **src/services/user.py:47**
[NOTE: Consider adding caching here for performance]
```

**Smart Cross-Pane Collection:**

The `<leader>nb` (buffer notes) command is smart about which buffer to collect from:
- **In editor pane**: Collects notes from the current file
- **In prompt pane**: Automatically collects notes from the file open in the editor pane
  of the same window (tracked in the `@LAZY_LLM_EDITOR_FILE` window option; read from
  disk, so save the file first)

This allows you to stay in the prompt pane and pull notes from whatever file you're viewing in the editor without switching panes. Scatter notes throughout your codebase while working, then collect them all at once to discuss with your AI assistant.

### Tmux Keybindings

Registered automatically when a workspace is created. Keybindings are **scoped to lazy-llm windows** — in non-lazy-llm windows, `C-n`/`C-p` fall back to tmux's default `next-window`/`previous-window` and other bindings are no-ops.

| Key | Action |
|-----|--------|
| `Prefix + C-n` | Cycle to next AI pane |
| `Prefix + C-p` | Cycle to previous AI pane |
| `Prefix + A` | Add new AI pane (tool picker menu) |
| `Prefix + C-x` | Remove current AI pane |
| `Prefix + S` | Dashboard popup (Workspaces tree / Worktrees / Saved tabs; switch with `1`/`2`/`3`, `?` for Help) |
| `Prefix + C-s` | Save every workspace now (they're also saved automatically on every change) |

### Multi-AI Pane Tabbing

Run multiple AI tools simultaneously in the same workspace. Only one AI pane is visible at a time (top-left), and you cycle between them with keybindings.

```bash
# Start with one AI tool
lazy-llm -t claude

# Add more from inside the workspace:
# - Prefix + A (tmux) or <leader>llma (nvim)
# - Cycle with Prefix + C-n/C-p or <leader>llm]/[
# - Remove with Prefix + C-x or <leader>llmx
```

Inactive AI panes are held in a hidden tmux window. `tmux swap-pane` atomically exchanges the visible pane with a held one. All existing commands (`llm-send`, `llm-pull`, `llm-append`) automatically target whichever AI pane is currently active.

**CLI tools:**

| Command | Description |
|---------|-------------|
| `llm-add [-t tool] [-i \| -w path]` | Add a new AI pane (default: claude); `-i` in its own worktree, `-w` into an existing pane worktree |
| `llm-wt status\|sync\|integrate` | An isolated pane's worktree: what's pending, pull in integrated work, merge back (see [Isolated AI panes](#isolated-ai-panes-per-pane-worktrees)) |
| `llm-cycle [next\|prev\|N]` | Cycle between AI panes |
| `llm-remove [-f] [current\|N]` | Remove an AI pane (`-f` skips confirmation) |
| `llm-status` | Status line output for tmux (e.g. `[claude●] gemini◐` — glyphs reflect AI pane state) |
| `llm-append [text]` | Append text to prompt buffer (supports stdin: `echo "foo" \| llm-append`) |
| `llm-dashboard` | Tabbed popup dashboard (Workspaces, Worktrees) with live ANSI preview. Bound to `Prefix+S`. |
| `llm-sessions` | CLI helper for non-interactive listing/killing of workspaces (`--list`, `--kill <name>`). Interactive mode subsumed by `llm-dashboard`. |
| `llm-panes` | Alias for `llm-dashboard --tab workspaces` — AI panes live nested in the Workspaces tree now, not a separate tab (kept for CLI muscle memory) |
| `llm-persist` | Save/restore backend, reached as `lazy-llm save \| restore \| saved \| forget` (see [Save & Restore](#save--restore)) |

### Save & Restore

lazy-llm keeps its workspace state in tmux options, which die with the tmux server (and which tmux-resurrect can't bring back). So lazy-llm saves each workspace to its own manifest, `~/.local/state/lazy-llm/workspaces/<id>.json` (JSON, needs `jq`), and rebuilds from it:

```bash
lazy-llm restore            # rebuild every saved workspace whose tmux server is gone
lazy-llm restore --dry-run  # show what would be rebuilt, with the exact launch commands
lazy-llm restore dev-env    # just this one (also reopens one you closed)
lazy-llm saved [-v]         # list saved workspaces (add --dropped for dropped ones)
lazy-llm close dev-env      # close a running workspace but keep it saved
lazy-llm kill dev-env       # close it and drop it from the list
lazy-llm forget dev-env     # drop a saved workspace that isn't running
lazy-llm save               # save now (also Prefix+C-s, or s in the dashboard)
lazy-llm restore --snapshot 20260928-001210 dev-env   # dev-env as it was at that manual save
lazy-llm forget --snapshot 20260928-001210            # delete that manual save
```

**Autosave vs manual save.** Every change rewrites a workspace's *rolling* entry: its latest state, the one a plain `restore` uses. A *manual* save (`lazy-llm save`, Prefix+C-s, `s` in the dashboard) also writes a dated snapshot of each workspace that changed since its last one, including copies of its editor and prompt nvim state. So after closing a couple of panes you can still go back to how it was. Restoring a snapshot of a workspace that's running brings it back as a copy next to it (`name-2`). Otherwise it comes back as that workspace. Snapshots stay until you delete them.

**From a fresh tmux** (after a reboot), Prefix+S opens the dashboard straight on the Saved tab, provided lazy-llm's bindings are registered when the server starts. Add this to your tmux.conf:

```tmux
if-shell 'test -x "$HOME/.local/bin/llm-tmux-init"' 'run-shell -b "$HOME/.local/bin/llm-tmux-init"'
```

Or use the dashboard's **Saved** tab (`Prefix+S`, then `3`). It lists the rolling entries at the top, then each manual save under a divider with its date. `z` expands an entry to show its AI panes (folded by default). Enter restores (or switches to a running one), `c` closes a running one (kept), `K` kills or drops (on a manual save's entry or divider: deletes it), `A` restores everything in the highlighted section (the ones that died, or one manual save's workspaces), `s` saves, `d` shows dropped ones. `K` on a workspace in the Workspaces tab asks whether to close (keep) or kill (drop).

| State | Meaning |
|---|---|
| ● live | running |
| ◌ restorable | died with its tmux server (crash, reboot) — a plain `lazy-llm restore` brings these back |
| ◇ closed | you closed it (`lazy-llm close`, the dashboard, or just in tmux) — kept; reopen with Enter, `restore <name>`, or by running `lazy-llm` in its directory |
| ✕ dropped | killed or forgotten — hidden (`saved --dropped`, `d`), still restorable by name, deleted after 30 days |
| ◆ manual save | a dated snapshot, listed under its save's divider — restore brings that version back |

- **What comes back**: session name and identity, AI panes in order with their tools and display names, which one was visible (the rest held), each Claude pane resuming its conversation (`claude --resume <id>`, same model, same directory), the prompt file and the prompt pane's open buffers, the editor's open buffers and splits, fold state and dashboard order.
- **When it's saved**: automatically on launch, adding/removing/cycling AI panes, dashboard renames/folds/reorders, a Prefix+$ rename, and whenever a Claude pane moves to a new conversation (`/clear`, `--resume` — recorded by lazy-llm's Claude Code plugin hook). Nothing runs on a timer.
- **Restoring next to running workspaces** is fine: restore only ever creates sessions. A name that's taken comes back as `name-2`; it never merges into a live session. Opening a directory with `lazy-llm` that has a restorable workspace asks whether to restore it instead.
- **Crash safety**: every entry records the tmux server that last saw it. A save only rewrites running workspaces, never another server's entries, and does nothing when no server is running. A workspace that disappears while its server stays up counts as closed only after a minute (so a save racing a dying server can't turn a crash victim into a closed one). One edge: closing the *last* workspace with plain `tmux kill-session` also ends the server, so it shows as restorable, not closed — `lazy-llm close` doesn't have that problem.
- **Other AI tools** restart fresh for now; resume is wired per tool in `lazy_llm_tool_launch_cmd` / `lazy_llm_tool_conv` (lib), and only Claude has a branch so far.
- **nvim state**: each workspace nvim keeps one rolling `:mksession` snapshot in `<dir>/.lazy-llm/sessions/` (nvim-session-plugin). The prompt pane restores its snapshot on every open; the editor's is used by `lazy-llm restore`. Your persistence.nvim sessions (`<leader>qs`/`<leader>qr`) are untouched — except that the prompt pane keeps its own in `sessions/lazy-llm-prompt/`, so the two panes no longer overwrite each other's.

### Workflow

1. Start workspace: `lazy-llm`
2. Write your prompt in the bottom pane (opens in insert mode)
3. Send it: `<leader>llms`
4. Review AI response in left pane
5. When prompted for confirmation (1/2/3): `<leader>llmk` then press the number
6. Use the editor pane (right) to review and stage changes as the AI edits files

## Configuration

### Clear on Send

By default, the prompt buffer clears after sending. To disable:

Edit `nvim/.config/nvim/lua/plugins/llm-send.lua`:

```lua
local config = {
    clear_on_send = false, -- Keep content after sending
}
```

### Custom AI Tools

The lazy-llm script supports any of the agentic TUI tools. Just pass it with `-t`:

```bash
lazy-llm -t your-ai-tool
```

## Git Workflow

The editor pane (top-right) includes git tooling for managing changes:

- **vim-fugitive**: `<leader>gs` for status, `<leader>gc` to commit, `<leader>gp` to push
- **gitsigns**: `<leader>gd` toggles diff overlay, `<leader>hs` stages hunks, `]h`/`[h` navigate changes
- **vgit**: `<leader>Vd` for buffer diff preview, `<leader>Vp` for project-wide diff

While the AI makes edits, use the editor pane to review diffs, stage changes, and commit. The git plugins show inline diffs so you can see exactly what changed.

## How It Works

### Content Delivery

- **llm-send**: Loads content into tmux buffer and pastes it to the AI pane via `load-buffer` + `paste-buffer`. Uses tool-specific strategies (e.g. Gemini's external editor mode).
- **llm-append**: Appends context references to the prompt buffer using `load-buffer` + `paste-buffer`. Accepts text as argument or via stdin pipe.
- **llm-pull**: Captures AI pane history and extracts the latest response after `### END PROMPT` markers.
- **Scroll-aware sending**: Auto-exits tmux copy-mode before sending to prevent key binding conflicts.

### Status Detection

`llm-status` shows a glyph next to each AI tool name reflecting its current state, refreshed at tmux's `status-interval` (default 15s):

| Glyph | State | Meaning |
|-------|-------|---------|
| `◐` | waiting | Blocked on your decision (permission prompt, `[y/n]`, numbered choice) |
| `◉` | unread | Finished a turn you haven't looked at yet — your turn |
| `●` | working | AI is generating (interrupt hint visible in pane) |
| `○` | idle | Finished, and you've already seen it |
| `?` | unknown | Pane capture failed or content unrecognized |

A pane becomes **unread** when its turn ends while you're not looking at it (another
pane, window or session, or the terminal itself in the background), and goes back to
idle when it's in front of you again: you focus it, switch to its window or session,
refocus the terminal, cycle it into view, send it a prompt (`llm-send`), or pick it in
the dashboard. Markers live in `~/.cache/lazy-llm/unread/`.

The summary at the start of `llm-status` (and of the AI pane's border) counts AI panes
per status across every workspace — e.g. `3ws 1◐ 2◉ 1● 3○`, zero counts omitted. The AI
pane's border also names the pane: `workspace - pane name - harness - model`.

Detection runs against the AI pane's content via `tmux capture-pane`. Patterns live in `lazy_llm_detect_status_from_content` in `lazy-llm-lib.sh` and default to Claude-tuned regexes; other tools (gemini, codex, grok, aider) fall through to the same defaults as best-effort.

**Claude panes get a more reliable signal**, from lazy-llm's own Claude Code plugin
(`claude-plugin/`, registered by `install.sh` via `claude plugin marketplace add` +
`claude plugin install lazy-llm@lazy-llm`). Its hooks run `llm-claude-hook`, which:
- writes `working`/`waiting`/`idle` to `~/.cache/lazy-llm/status/<pane_id>` on
  `UserPromptSubmit`, `Notification` and `Stop`, and fires a desktop notification (`notify-send` on Linux, `osascript` on
  macOS) when a pane transitions into `waiting`;
- marks the pane unread on `Stop`, and clears the mark on `UserPromptSubmit`;
- records the pane's model on `SessionStart`, `PostModelSwitch` (so `/model` switches
  show up immediately), and `Stop` (fallback, from the transcript).

`lazy_llm_detect_pane_status` prefers the hook status (when fresh, ≤30s old) over the
content scrape for `tool=claude`; every other tool always uses the scrape, and marks
unread from an observed working → idle transition instead. The scrape only looks at the
bottom of the pane (the current spinner, input box and footer): Claude Code's redraws
leave stale spinner lines in scrollback, which used to read as `working` indefinitely.

**Dashboard reminder.** `llm-status`'s output always ends with `Dash ^B+S` — a
reminder of `Prefix+S` (opens the dashboard), derived from your actual prefix key.

**Dashboard key.** `S` by default. To use another key, set `@lazy_llm_dashboard_key` in
`tmux.conf` before `llm-tmux-init` runs (lazy-llm re-binds the key every time it builds a
workspace window, so a plain `bind` of your own wouldn't stick). To take over tmux's
session tree key and move the tree to `S`:

```tmux
set -g @lazy_llm_dashboard_key s
bind S choose-tree -Zs
```
Add `#(llm-status)` to your tmux `status-right` to show it — `llm-status` prints
nothing outside a lazy-llm workspace window, so it's safe there unconditionally.

### Neovim Plugins

- **llm-send plugin** (`llm-send.lua`): Keymaps for sending, pulling, cycling, context references, and @ path completion. All keymaps are gated on `$TMUX` — no interference in standalone nvim.
- **note plugin** (`note.lua`): `[NOTE:]` marker insertion, collection, and cross-pane delivery. Delegates to `llm-append` for content delivery. Also gated on `$TMUX`.
- **Error feedback**: All async `jobstart` calls include `on_exit` callbacks with error notifications. Temp file cleanup is handled in Lua, not shell.

### Pane State Management

- **Shared library** (`lazy-llm-lib.sh`): All 7 CLI scripts use a common library for pane resolution, validation, and state management.
- **Stable pane IDs**: Uses `%N` format pane IDs stored as tmux window-scoped options, which survive `swap-pane` and window reordering:
  - `@AI_PANE_ID`: Currently active AI pane
  - `@PROMPT_PANE_ID`: Prompt buffer pane
  - `@AI_PANES`: Space-separated list of all AI pane IDs
  - `@AI_TOOLS`: Parallel list of tool names
  - `@AI_PANE_IDX`: Index of the active pane in the list
  - `@AI_HOLD_WIN`: Window ID of the hidden holding window
- **Stale pane pruning**: `lazy_llm_validate_pane()` checks if panes are alive; `lazy_llm_prune_stale_panes()` auto-removes dead entries and cleans up empty holding windows.
- **Holding window resilience**: `lazy_llm_validate_hold_win()` auto-recovers if the holding window is accidentally closed. References use stable window IDs instead of names.

## Testing

lazy-llm includes a comprehensive test suite for automated integration testing. See [`tests/README.md`](tests/README.md) for details.

### Quick Start

```bash
# Run all tests
cd tests && ./test-runner.sh

# Run specific test
./test-runner.sh 01-simple-send.sh

# Debug mode (keeps sessions alive)
./test-runner.sh -d 02-multiline-send.sh
```

The test suite uses tmux to create real PTY sessions and includes a mock AI tool for deterministic testing. See [`docs/HEADLESS_TESTING_RESEARCH.md`](docs/HEADLESS_TESTING_RESEARCH.md) for research on automated PTY testing approaches.

## Contributing

Contributions are welcome! Please see [`CONTRIBUTING.md`](CONTRIBUTING.md) for guidelines on:
- Running tests before submitting PRs
- Code style and conventions
- Reporting issues

## License

MIT
