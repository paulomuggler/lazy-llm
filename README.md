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
- **Context picker**: Reference specific lines/blocks of code in your prompts (`<leader>llmr`)
- **File & folder references**: @ autocomplete with fuzzy picker supports both files and directories
- **Smart window management**: Auto-detects if inside tmux and adds new window to current session
- **Git integration**: Editor pane includes vim-fugitive, gitsigns, and vgit for tracking changes
- **Multiple AI tools**: Supports Claude, Gemini, Codex, Grok, Aider, or any agentic TUI tool

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

### Keymaps

All keymaps are under the `<leader>llm` prefix:

- `<leader>llms` - **Send Buffer** - Send entire buffer to AI pane
- `<leader>llms` (visual) - **Send Selection** - Send visual selection to AI pane
- `<leader>llmd` - **Delete Buffer** - Clear prompt buffer content
- `<leader>llmk` - **Send Keypress** - Send next keypress to AI pane (for responding to prompts)
- `<leader>llmr` - **Add Code Reference** - Insert line/block reference to prompt buffer (normal/visual mode)

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

- **llm-send script**: Bash script that loads content into tmux clipboard and pastes it to the AI pane
- **llm-append script**: Appends context references to prompt buffer without clearing or submitting
- **Neovim plugin**: LazyVim plugin providing keymaps to trigger llm-send and other utilities
- **Scroll-aware sending**: Auto-exits tmux copy-mode before sending to prevent key binding conflicts
- **Scratch buffer**: No-file buffer that writes to temp files when sending
- **Environment variables**:
  - `AI_PANE`: Target pane for AI tool (left pane)
  - `PROMPT_PANE`: Target pane for prompt buffer (bottom pane)

## License

MIT
