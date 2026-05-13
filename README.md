# lazy-llm

A tmux + Neovim workflow for seamless interaction with agentic TUI tools like Claude Code, Gemini, &tc.

## Overview

lazy-llm creates a tmux session with a three-pane layout optimized for AI-assisted development:

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
- **Smart window management**: Auto-detects if inside tmux and adds new window to current session
- **Git integration**: Editor pane includes vim-fugitive, gitsigns, and vgit for tracking changes
- **Multiple AI tools**: Supports Claude, Gemini, Codex, Grok, Aider, or any agentic TUI tool
- **Multi-AI pane tabbing**: Run multiple AI tools side-by-side, cycling between them with keybindings
- **Dashboard popup**: List sessions with status glyphs + live ANSI preview; tabbed (Sessions / Worktrees) (`Prefix+S`)
- **Panes tab in dashboard**: View AI pane status and switch between them — opens via `Prefix+S` then `3`
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

### Starting a Session

```bash
# Start with default AI tool (claude)
lazy-llm

# Specify a different tool
lazy-llm -t gemini
lazy-llm -t codex
lazy-llm -t grok

# Custom session name and directory
lazy-llm -s my-project -d ~/projects/foo -t claude
```

Options:
- `-s session_name` - Custom tmux session name (auto-generated if not provided)
- `-d directory` - Working directory (defaults to current)
- `-t ai_tool` - AI tool to launch (claude, gemini, codex, grok, aider, etc.)
- `-w` - Force new window mode (otherwise auto-detected when in tmux)

**Smart Behavior:**
- **Outside tmux**: Creates new session or attaches to existing one
- **Inside tmux**: Automatically adds new window to current session
- **With `-s <existing>`**: Adds window to that session (attaches if needed)
- **With `-W <branch>`**: Always creates a new session bound to a git worktree for `<branch>`; attaches to an existing lazy-llm session there if one already exists

### Worktree-per-task

For parallel work on multiple branches without stepping on each other:

```bash
# Create branch + worktree at .worktrees/feature-foo/, then spawn a session there
lazy-llm -W feature/foo

# Spawn with a specific AI tool
lazy-llm -W bugfix/auth -t gemini

# Override the worktree base path
LAZY_LLM_WORKTREE_DIR=$HOME/wt lazy-llm -W feature/foo
```

If the branch doesn't exist, it's created from current `HEAD`. If a worktree for it already exists, it's reused. If a lazy-llm session is already pointed at that worktree, you're attached to it instead of duplicating. Worktree binding is **session-scoped** — all panes (AI, editor, prompt) start in the worktree path, so `@` path completion and code references resolve correctly.

When using the in-repo default (`.worktrees/`), the path is automatically added to `.gitignore`. For cleanup, prefer the dashboard's Worktrees tab `K` action (atomic: kills attached session, removes worktree, optionally deletes branch — with safety prompts for dirty/ahead/open-PR cases) or fall back to `git worktree remove .worktrees/feature-foo && git branch -d feature/foo` from the shell.

### Worktree dashboard

`Prefix+S` → `2` opens the Worktrees tab. Lists all worktrees in the current repo with branch, dirty marker, ahead/behind vs default branch, attached lazy-llm session (`●`), and PR state (when `gh` is installed and the remote is GitHub).

Actions:
- `Enter` — open / attach a lazy-llm session in the highlighted worktree (via `lazy-llm -W`)
- `n` — new worktree + session (prompts for branch name)
- `g` — launch `lazygit` pointed at the highlighted worktree (delegates lifecycle ops)
- `K` — atomic cleanup with safety prompts: shows warnings for dirty / ahead-of-default / no-upstream / attached-session / open-PR, asks separately whether to also delete the branch
- `R` — refresh; `?` — help; `q`/`Esc` — close

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
| `<leader>ni` | **Insert Note** - Insert `[NOTE: ]` marker at cursor, ready to type |
| `<leader>nb` | **Buffer Notes** - Send all notes from current file to prompt pane |
| `<leader>np` | **Project Notes** - Send all notes from entire project to prompt pane |
| `]n` | **Next Note** - Jump to next note in buffer |
| `[n` | **Previous Note** - Jump to previous note in buffer |
| `<leader>nf` | **Find Notes** - Fuzzy picker for all project notes |
| `<leader>nq` | **Quickfix Buffer** - Buffer notes to quickfix list |
| `<leader>nQ` | **Quickfix Project** - Project notes to quickfix list |

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
# Notes from project

- **src/services/user.py:42**
  Should this handle empty lists differently?

- **src/services/user.py:47**
  Consider adding caching here for performance
```

**Smart Cross-Pane Collection:**

The `<leader>nb` (buffer notes) command is smart about which buffer to collect from:
- **In editor pane**: Collects notes from the current file
- **In prompt pane**: Automatically collects notes from the file open in the editor pane

This allows you to stay in the prompt pane and pull notes from whatever file you're viewing in the editor without switching panes. Scatter notes throughout your codebase while working, then collect them all at once to discuss with your AI assistant.

### Tmux Keybindings

Registered automatically when a workspace is created. Keybindings are **scoped to lazy-llm windows** — in non-lazy-llm windows, `C-n`/`C-p` fall back to tmux's default `next-window`/`previous-window` and other bindings are no-ops.

| Key | Action |
|-----|--------|
| `Prefix + C-n` | Cycle to next AI pane |
| `Prefix + C-p` | Cycle to previous AI pane |
| `Prefix + A` | Add new AI pane (tool picker menu) |
| `Prefix + C-x` | Remove current AI pane |
| `Prefix + S` | Dashboard popup (Sessions / Worktrees / Panes tabs; switch with `1`/`2`/`3`) |

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
| `llm-add [-t tool]` | Add a new AI pane (default: claude) |
| `llm-cycle [next\|prev\|N]` | Cycle between AI panes |
| `llm-remove [-f] [current\|N]` | Remove an AI pane (`-f` skips confirmation) |
| `llm-status` | Status line output for tmux (e.g. `[claude●] gemini◐` — glyphs reflect AI pane state) |
| `llm-append [text]` | Append text to prompt buffer (supports stdin: `echo "foo" \| llm-append`) |
| `llm-dashboard` | Tabbed popup dashboard (Sessions, Worktrees) with live ANSI preview. Bound to `Prefix+S`. |
| `llm-sessions` | CLI helper for non-interactive listing/killing (`--list`, `--kill <name>`). Interactive mode subsumed by `llm-dashboard`. |
| `llm-panes` | Alias for `llm-dashboard --tab panes` (kept for CLI muscle memory) |

### Workflow

1. Start session: `lazy-llm`
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
| `●` | working | AI is generating (interrupt hint visible in pane) |
| `○` | idle | Prompt visible, waiting for input |
| `◐` | waiting | Permission prompt (`[y/n]`) or numbered choice |
| `?` | unknown | Pane capture failed or content unrecognized |

Detection runs against the AI pane's content via `tmux capture-pane`. Patterns live in `lazy_llm_detect_status_from_content` in `lazy-llm-lib.sh` and default to Claude-tuned regexes; other tools (gemini, codex, grok, aider) fall through to the same defaults as best-effort.

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
