# Response Pull with Virtual Text - Implementation Plan

## Overview

Enable pulling LLM responses back into nvim as virtual text, allowing inline annotation without context bloat. User can write comments/questions between response lines, then submit only their annotations (not the full response) for iterative refinement.

## Goals

1. Pull latest LLM response from AI pane into nvim
2. Display response as virtual text (gray, non-editable)
3. User writes annotations as actual buffer content
4. Send only annotations back to LLM (not the response text)
5. Support iterative annotation workflow

## Technical Design

### Component 1: Enhanced Prompt Marker

**File:** `llm-send-bin/.local/bin/llm-send`

**Change:** Add END marker to prompt line

```bash
# Current:
tmux send-keys -t "$TARGET" "### PROMPT $(date +'%F %T')" Enter

# New:
tmux send-keys -t "$TARGET" "### PROMPT $(date +'%F %T') ### END PROMPT" Enter
```

**Why:** Makes response extraction trivial - everything after last `### END PROMPT` is the latest response.

### Component 2: llm-pull Script

**File:** `llm-send-bin/.local/bin/llm-pull`

**Purpose:** Extract latest LLM response from AI pane and output to stdout

**Implementation:**

```bash
#!/usr/bin/env bash
# llm-pull - Extract latest LLM response from AI pane

set -euo pipefail

# Get AI_PANE from tmux environment (session-specific, like llm-send/llm-append)
if [ -z "${AI_PANE:-}" ]; then
  CURRENT_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
  if [ -n "$CURRENT_SESSION" ]; then
    AI_PANE=$(tmux show-environment -t "$CURRENT_SESSION" AI_PANE 2>/dev/null | cut -d= -f2- || echo "")
  fi
  # Fallback to global
  if [ -z "$AI_PANE" ]; then
    AI_PANE=$(tmux show-environment -g AI_PANE 2>/dev/null | cut -d= -f2- || echo "")
  fi
fi

TARGET="${AI_PANE:-:.0}"

# Exit copy-mode if active
tmux send-keys -t "$TARGET" -X cancel 2>/dev/null || true

# Capture pane with history
content=$(tmux capture-pane -t "$TARGET" -p -S -2000)

# Extract everything after last "### END PROMPT"
# Using awk to find last occurrence and print everything after
response=$(echo "$content" | awk '
  /### END PROMPT/ { found=NR; next }
  found && NR > found { print }
')

# Strip ANSI escape codes (optional but cleaner)
# response=$(echo "$response" | sed 's/\x1b\[[0-9;]*m//g')

# Output to stdout
echo "$response"
```

**Key Points:**
- Retrieves AI_PANE from session-specific tmux environment (same pattern as llm-send/llm-append)
- Exits copy-mode before capturing (handles scrolled-up pane state)
- Uses awk to extract everything after last `### END PROMPT` marker
- Outputs to stdout (nvim reads via system())

### Component 3: Virtual Text Display in nvim

**File:** `nvim-llm-send-plugin/.config/nvim/lua/plugins/llm-send.lua`

**Add namespace at top level:**

```lua
-- Create namespace for LLM response virtual text (after other helper functions)
local llm_ns = vim.api.nvim_create_namespace('llm_response_virtual')
```

**Add function:**

```lua
-- Function to pull response and display as virtual text
local function pull_response_virtual()
  -- Get current buffer
  local bufnr = vim.api.nvim_get_current_buf()

  -- Clear all existing virtual text in this buffer
  vim.api.nvim_buf_clear_namespace(bufnr, llm_ns, 0, -1)

  -- Call llm-pull to get response
  local response = vim.fn.system("bash -lc 'llm-pull'")

  if vim.v.shell_error ~= 0 or response == "" then
    vim.notify("Failed to pull response or no response found", vim.log.levels.WARN)
    return
  end

  -- Split into lines
  local lines = vim.split(response, "\n", { trimempty = false })

  -- Get current cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1  -- 0-indexed

  -- Insert virtual text lines BELOW cursor position
  for i, line in ipairs(lines) do
    vim.api.nvim_buf_set_extmark(bufnr, llm_ns, row, 0, {
      virt_lines = {{{line, "Comment"}}},  -- Gray comment color
      virt_lines_below = true,
    })
  end

  vim.notify(string.format("Pulled %d lines as virtual text", #lines), vim.log.levels.INFO)
end
```

**Add keybinding:**

```lua
{
  "<leader>llmp",
  pull_response_virtual,
  mode = "n",
  desc = "LLM: Pull response as virtual text",
}
```

**Key Points:**
- Creates dedicated namespace for virtual text markers
- Clears ALL previous virtual text on each pull (fresh slate)
- Displays below cursor position
- Uses "Comment" highlight group (gray text)
- Virtual text is NOT part of buffer content

## User Workflow

### Happy Path:

1. **User writes prompt in prompt buffer (bottom pane)**
2. **User presses `<leader>llms`**
   - Prompt sent to AI pane with `### PROMPT timestamp ### END PROMPT` marker
   - LLM responds in AI pane
3. **User presses `<leader>llmp` in prompt buffer**
   - Previous virtual text cleared (if any)
   - Latest response extracted (everything after last `### END PROMPT`)
   - Response displayed as gray virtual text below cursor
4. **User types annotations inline**
   - Annotations are actual buffer content
   - Can write between virtual text lines
   - Virtual text provides context
5. **User presses `<leader>llms` again**
   - Only buffer content (user's annotations) sent to LLM
   - Virtual text NOT included (it's not in buffer)
   - New marker added, cycle repeats

### Example Buffer State After Pull:

```markdown
[cursor here]
⏺ Great feedback! Let me address each point...    ← virtual text (gray)
                                                    ← virtual text
### 1. Response Extraction                         ← virtual text
                                                    ← virtual text
You're right - we should...                        ← virtual text

My inline question about extraction?               ← REAL buffer content (user typed)

### 2. Virtual Text From The Start                 ← virtual text
                                                    ← virtual text
Actually simpler...                                ← virtual text

What about performance with large responses?       ← REAL buffer content (user typed)
```

When `<leader>llms` is pressed, only:
```
My inline question about extraction?

What about performance with large responses?
```
is sent to the LLM (the actual buffer content).

## Implementation Order

1. **Modify llm-send** - Add `### END PROMPT` to marker line
2. **Create llm-pull script** - Extract and output response
3. **Stow llm-send-bin** - Deploy llm-pull
4. **Add nvim namespace and function** - Virtual text display logic
5. **Add nvim keybinding** - `<leader>llmp`
6. **Test workflow**:
   - Send prompt with `<leader>llms`
   - Wait for response
   - Pull with `<leader>llmp`
   - Add annotations
   - Send annotations with `<leader>llms`
   - Verify only annotations sent (check AI pane)

## Edge Cases & Considerations

### Handled:
- **Scrolled AI pane:** llm-pull exits copy-mode before capturing
- **Multiple pulls:** Clears previous virtual text completely
- **Empty response:** Warns user if extraction fails

### To Consider:
- **ANSI codes in response:** Currently commented out in llm-pull, may need to enable stripping
- **Very long responses:** Virtual text performance with 500+ lines (test and optimize if needed)
- **Multi-TUI support:** Currently relies on `### END PROMPT` marker, works across all TUIs

## Future Enhancements

- `<leader>llmP` - Pull to new split for side-by-side view
- `<leader>llmv` - Pull as actual text (not virtual) for editing response
- `<leader>llmx` - Manually clear virtual text (currently auto-clears on next pull)
- Multi-response tracking - Stack multiple responses with timestamps
- Partial pulling - Select range in AI pane copy-mode, pull only selection
- Response diffing - Compare consecutive responses

## Technical Notes

### Virtual Text vs Buffer Content

**Virtual Text (extmarks with virt_lines):**
- Not part of buffer content
- Rendered visually by nvim
- Cannot be edited or selected
- Does not affect buffer line count
- Cleared with `nvim_buf_clear_namespace()`

**Buffer Content:**
- Actual text in buffer
- Fully editable
- Included in `:w` writes and yank operations
- What gets sent via `<leader>llms`

### Why This Works

When `llm-send` reads the buffer to send:
```lua
-- From existing llm-send keybinding
if bufname == "" then
  local tmp = vim.fn.tempname() .. ".md"
  vim.cmd("write! " .. tmp)  -- Writes ONLY buffer content, not virtual text
  vim.fn.jobstart(...)
end
```

The `:write` command only writes actual buffer content, ignoring virtual text. Perfect for our use case!

## Testing Plan

1. **Basic pull:** Send prompt, pull response, verify virtual text appears
2. **Annotation workflow:** Add inline comments, verify they're real buffer content
3. **Send annotations:** Verify only annotations sent, not virtual text
4. **Multiple iterations:** Pull → annotate → send → pull → verify
5. **Edge cases:** Empty response, very long response, scrolled pane
6. **Cross-TUI:** Test with Claude, Gemini, Grok (all use same marker)

## Success Criteria

- ✓ Response appears as gray virtual text below cursor
- ✓ User can type annotations as normal buffer content
- ✓ Sending buffer only includes annotations (not virtual text)
- ✓ Subsequent pulls clear previous virtual text
- ✓ Works regardless of AI pane scroll state
- ✓ No context bloat (LLM doesn't receive its own response back)
