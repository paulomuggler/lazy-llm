# Context Picker Feature - Design Plan

## Goal
From workspace editor (nvim), send a code reference to the prompt buffer:
- Single line: `# See line 42 in src/main.py`
- Block: `# See lines 42-50 in src/main.py`

## Core Functionality

**User flow:**
1. In workspace editor, position cursor on line OR visually select code block
2. Press `<leader>llmr` (for "reference")
3. Reference appears in prompt buffer (bottom pane), ready to include in next prompt

## What We Need to Implement

### 1. Capture Context (in nvim)
- Current file path (relative to git root or cwd)
- Line number(s):
  - Normal mode: current line
  - Visual mode: line range
- Optionally: the actual code snippet (for future enhancement)

### 2. Format the Reference
```markdown
# See line 42 in src/main.py
# See lines 42-50 in src/main.py

# Future: with code snippet
# See lines 42-50 in src/main.py:
```python
def example():
    pass
```
```

### 3. Target Pane Detection
Need to identify the prompt buffer pane. Options:
- **Option A**: Add `PROMPT_PANE` env var to lazy-llm (like `AI_PANE`)
- **Option B**: Detect dynamically (bottom full-width pane)
- **Recommended**: Option A - explicit and reliable

### 4. Insertion Method
Options:
- **Append** to end of prompt buffer (safest, won't interrupt typing)
- Insert at cursor (more complex, could interrupt user)
- **Recommended**: Append with blank line separator

## Implementation Components

### Component 1: New `llm-append` utility script
```bash
# ~/.local/bin/llm-append
#!/usr/bin/env bash
# Appends text to prompt pane without clearing or submitting

# Get PROMPT_PANE from tmux environment
PROMPT_PANE=$(tmux show-environment -g PROMPT_PANE 2>/dev/null | cut -d= -f2-)
TARGET="${PROMPT_PANE:-:.2}"  # fallback to pane 2 (bottom pane)

# Send text to prompt buffer
# Add blank line first for separation
tmux send-keys -t "$TARGET" "" Enter
tmux send-keys -t "$TARGET" "$1"
```

### Component 2: Update lazy-llm to set PROMPT_PANE
In `lazy-llm` script (similar to AI_PANE):
```bash
# Line ~107 in create_workspace_window function
tmux set-environment -t "$session" PROMPT_PANE "$session:$win_idx.$prompt_pane"

# Line ~256 in main session creation
tmux set-environment -t "$SESSION_NAME" PROMPT_PANE "$SESSION_NAME:$WIN_INDEX.$PROMPT_PANE"
```

### Component 3: Add keybinding in nvim
In `nvim-llm-send-plugin/.config/nvim/lua/plugins/llm-send.lua`:
```lua
{
  "<leader>llmr",
  function()
    -- Get file path (relative to git root or cwd)
    local filepath = vim.fn.expand("%:.")

    -- Get line number(s)
    local mode = vim.fn.mode()
    local line_ref

    if mode == 'v' or mode == 'V' then
      -- Visual mode: get range
      local start_line = vim.fn.line("'<")
      local end_line = vim.fn.line("'>")
      if start_line == end_line then
        line_ref = "line " .. start_line
      else
        line_ref = "lines " .. start_line .. "-" .. end_line
      end
    else
      -- Normal mode: current line
      line_ref = "line " .. vim.fn.line(".")
    end

    -- Format reference
    local reference = string.format("# See %s in %s", line_ref, filepath)

    -- Send to prompt buffer
    vim.fn.jobstart(
      { "llm-append", reference },
      { detach = true }
    )
  end,
  mode = {"n", "v"},
  desc = "LLM: Add Code Reference to Prompt"
}
```

## Implementation Steps

1. **Update lazy-llm script**
   - Add `PROMPT_PANE` environment variable (2 locations)

2. **Create llm-append script**
   - Place in `llm-send-bin/.local/bin/llm-append`
   - Make executable
   - Test manually first

3. **Add nvim keybinding**
   - Edit `nvim-llm-send-plugin/.config/nvim/lua/plugins/llm-send.lua`
   - Add `<leader>llmr` for both normal and visual modes

4. **Test scenarios**
   - Single line reference (normal mode)
   - Multi-line reference (visual mode)
   - Different file types
   - Multiple references in same prompt

## Design Decisions

✅ **Reference format**: Start with simple `# See line X in path` (language-agnostic)
✅ **Insertion**: Append to prompt buffer (non-disruptive)
✅ **Target detection**: Use PROMPT_PANE env var (explicit, reliable)
✅ **Script**: New `llm-append` utility (reusable for future features)

## Future Enhancements
- Include code snippet in reference (optional flag)
- Language-aware comment style (`//`, `--`, `#`, etc.)
- Smart relative path (git root vs cwd)
- Visual indicator that reference was added
