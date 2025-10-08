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
- **Git integration**: Editor pane includes vim-fugitive, gitsigns, and vgit for tracking changes
- **Multiple AI tools**: Supports Claude, Gemini, or any of the agentic TUI tools, really

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

# Custom session name and directory
lazy-llm -s my-project -d ~/projects/foo -t claude
```

Options:
- `-s session_name` - Custom tmux session name
- `-d directory` - Working directory (defaults to current)
- `-t ai_tool` - AI tool to launch (claude, gemini, etc.)

### Keymaps

All keymaps are under the `<leader>llm` prefix:

- `<leader>llms` - **Send Buffer** - Send entire buffer to AI pane
- `<leader>llms` (visual) - **Send Selection** - Send visual selection to AI pane
- `<leader>llmd` - **Delete Buffer** - Clear prompt buffer content
- `<leader>llmk` - **Send Keypress** - Send next keypress to AI pane (for responding to prompts)

### File References with @ Autocomplete

Reference workspace files in your prompts using the `@` symbol for path completion:

**Method 1: Fuzzy Finder (Fast)**
1. Type `@` in insert mode
2. Fuzzy file picker opens showing all project files
3. Type fragments to filter: `comp butt tsx`
4. Select file → inserts: `@src/components/Button.tsx`

**Method 2: Native File Completion (Traditional)**
1. Type `@` followed by partial path: `@src/`
2. Press `<Ctrl-f>` to trigger vim's native file completion
3. Navigate directories level by level
4. Select files/folders to complete the path

**Example Prompt:**
```markdown
Please refactor @src/components/Button.tsx to use composition pattern.
Also update the tests in @tests/Button.test.tsx accordingly.
```

The `@` prefix helps LLM tools identify workspace file references and can be parsed by your AI tool for context loading.

**Tip**: For git-root-relative paths, ensure your nvim working directory is set to the repository root (use `:cd` or a rooter plugin).

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

- **llm-send script**: Bash script that loads content into tmux clipboard and pastes it to the target pane
- **Neovim plugin**: LazyVim plugin providing keymaps to trigger llm-send
- **Scratch buffer**: No-file buffer that writes to temp files when sending
- **AI_PANE environment variable**: Tmux session stores the AI pane target for keypress forwarding

## License

MIT
