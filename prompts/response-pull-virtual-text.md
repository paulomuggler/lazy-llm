# Response Pull with Extmark Tagging - Implementation Plan

## Overview

Enable pulling LLM responses back into nvim as real buffer lines tagged with extmarks, allowing inline annotation without context bloat. Response lines are visually distinct (gray) but fully editable. User can insert new lines between any response lines to add annotations. When sending, only untagged lines (user annotations) are sent to the LLM, not the response text.

## Goals

1. Pull latest LLM response from AI pane into nvim as real buffer lines
2. Tag each response line with an extmark to identify it
3. Highlight response lines as gray (visually distinct from user annotations)
4. User can insert new lines between any response lines (normal editing)
5. On send: filter out extmark-tagged lines, send only user annotations
6. Support iterative annotation workflow with zero context bloat

## Key Insight: Hybrid Approach

**Problem with pure virtual text:** Virtual lines are render-only overlays - you can't insert "between" them because they don't create real line positions.

**Solution:** Use real buffer lines + extmark tagging:
- Response pulled as **real lines** (one line per response line)
- Each response line **tagged with extmark** (metadata: "llm_response")
- Response lines **highlighted gray** (looks like virtual text)
- User **inserts lines normally** - new lines DON'T get tagged
- **On send:** Filter out extmark-tagged lines, send only untagged lines

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

### Component 3: Extmark-Tagged Response Lines in nvim

**File:** `nvim-llm-send-plugin/.config/nvim/lua/plugins/llm-send.lua`

**Add namespace at top level:**

```lua
-- Create namespace for LLM response extmark tagging
local llm_ns = vim.api.nvim_create_namespace('llm_response_lines')
```

**Add function to pull and insert response:**

```lua
-- Function to pull response and insert as extmark-tagged lines
local function pull_response()
  -- Get current buffer
  local bufnr = vim.api.nvim_get_current_buf()

  -- Clear all existing response lines (delete lines with llm_response extmarks)
  -- Get all extmarks in buffer
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, llm_ns, 0, -1, {})
  -- Delete lines from bottom to top (avoid line number shifts)
  for i = #marks, 1, -1 do
    local mark = marks[i]
    local row = mark[2]
    -- Check if this extmark is a response line tag
    local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, llm_ns, mark[1], { details = true })
    if details[3] and details[3].llm_response then
      vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, {})
    end
  end
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
  local row = cursor[1]  -- 1-indexed for buf_set_lines

  -- Insert response lines into buffer
  vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)

  -- Tag each inserted line with extmark and highlight
  for i = 0, #lines - 1 do
    vim.api.nvim_buf_set_extmark(bufnr, llm_ns, row + i, 0, {
      end_col = 0,
      hl_group = "Comment",  -- Gray highlight
      hl_eol = true,         -- Highlight entire line
      llm_response = true,   -- Custom metadata tag
    })
  end

  vim.notify(string.format("Pulled %d response lines", #lines), vim.log.levels.INFO)
end
```

**Add function to filter and send:**

```lua
-- Modify existing llms send function to filter out response lines
-- Add this helper function:
local function get_untagged_lines()
  local bufnr = vim.api.nvim_get_current_buf()
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local untagged = {}

  -- Get all extmarks
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, llm_ns, 0, -1, { details = true })
  local tagged_rows = {}
  for _, mark in ipairs(marks) do
    if mark[4] and mark[4].llm_response then
      tagged_rows[mark[2]] = true  -- mark[2] is row (0-indexed)
    end
  end

  -- Collect untagged lines
  for i = 0, total_lines - 1 do
    if not tagged_rows[i] then
      local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
      table.insert(untagged, line)
    end
  end

  return untagged
end
```

**Update llms keybinding to use filtered content:**

```lua
-- In the <leader>llms keybinding function, before writing to temp file:
-- Instead of writing entire buffer, write only untagged lines:

if bufname == "" then
  local tmp = vim.fn.tempname() .. ".md"

  -- Get untagged lines (user annotations only)
  local untagged_lines = get_untagged_lines()

  -- Write untagged lines to temp file
  vim.fn.writefile(untagged_lines, tmp)

  vim.fn.jobstart(
    { "bash", "-lc", "llm-send " .. vim.fn.fnameescape(tmp) .. " ; rm -f " .. vim.fn.fnameescape(tmp) },
    { detach = true }
  )
end
```

**Add keybinding:**

```lua
{
  "<leader>llmp",
  pull_response,
  mode = "n",
  desc = "LLM: Pull response as tagged lines",
}
```

**Key Points:**
- Response lines are **real buffer lines** (fully editable, scrollable)
- Each line tagged with **extmark containing metadata** `llm_response = true`
- Lines highlighted with **"Comment" highlight group** (gray)
- User can **insert lines between response lines** - new lines have no extmark
- **On send:** Only lines without `llm_response` extmark are sent
- Subsequent pulls **delete previous response lines** (clean slate)

## User Workflow

### Happy Path:

1. **User writes prompt in prompt buffer (bottom pane)**
2. **User presses `<leader>llms`**
   - Prompt sent to AI pane with markers
   - LLM responds in AI pane
3. **User presses `<leader>llmp` in prompt buffer**
   - Previous response lines deleted (if any)
   - Latest response extracted (everything after last `### END PROMPT`)
   - Response inserted as real buffer lines below cursor
   - Each line tagged with extmark and highlighted gray
4. **User inserts annotations between response lines**
   - Press `o` on response line to insert new line below
   - Press `O` on response line to insert new line above
   - Type annotations - they appear in normal color (not gray)
   - New lines DON'T get extmark tags
5. **User presses `<leader>llms` again**
   - Filter runs: only untagged lines (annotations) collected
   - Only annotations sent to LLM
   - Response lines stay in buffer (still tagged gray)
   - Cycle repeats

### Example Buffer State After Pull:

```markdown
[cursor here - line 1]
⏺ Great feedback! Let me address each point...    ← gray (extmark tagged)
                                                    ← gray (extmark tagged)
### 1. Response Extraction                         ← gray (extmark tagged)
                                                    ← gray (extmark tagged)
You're right - we should...                        ← gray (extmark tagged)
[user pressed 'o' and typed:]
My inline question about extraction?               ← normal color (NO extmark)
                                                    ← gray (extmark tagged)
### 2. Virtual Text From The Start                 ← gray (extmark tagged)
                                                    ← gray (extmark tagged)
Actually simpler...                                ← gray (extmark tagged)
[user pressed 'o' and typed:]
What about performance with large responses?       ← normal color (NO extmark)
```

**Visual Distinction:**
- Gray lines = LLM response (extmark tagged, will be filtered out)
- Normal color lines = User annotations (no extmark, will be sent)

When `<leader>llms` is pressed, only:
```
My inline question about extraction?

What about performance with large responses?
```
is sent to the LLM (the untagged lines).

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

### Extmark Tagging vs Traditional Markers

**Why extmarks instead of comment markers:**
- **Invisible metadata:** Extmarks are tags, not text in the file
- **Precise filtering:** Can identify exact lines without regex/parsing
- **Visual feedback:** Can highlight tagged lines automatically
- **Robust:** Won't break if user edits response lines

**Extmark Properties Used:**
```lua
vim.api.nvim_buf_set_extmark(bufnr, llm_ns, row, 0, {
  end_col = 0,
  hl_group = "Comment",  -- Makes line gray
  hl_eol = true,         -- Highlight extends to end of line
  llm_response = true,   -- Custom metadata for filtering
})
```

**Key Insight:**
- `llm_response = true` is **custom metadata** stored in the extmark
- When filtering, we check: `if mark[4].llm_response then skip this line`
- User's inserted lines have **no extmark** = included in send

### How Filtering Works

**On Pull:**
1. Insert response as real lines
2. Tag each line with extmark containing `llm_response = true`
3. Highlight each line gray

**On Send:**
1. Get all extmarks in buffer
2. Build set of tagged row numbers
3. Iterate all buffer lines
4. Collect only lines NOT in tagged set
5. Send collected lines to LLM

**Code flow:**
```lua
-- Filtering logic
local tagged_rows = {}
for _, mark in ipairs(marks) do
  if mark[4] and mark[4].llm_response then
    tagged_rows[mark[2]] = true  -- row is 0-indexed
  end
end

-- Collect untagged
for i = 0, total_lines - 1 do
  if not tagged_rows[i] then
    table.insert(untagged, line_at_row_i)
  end
end
```

### Why This Works

- **Response lines:** Real buffer content + extmark tag
- **User annotations:** Real buffer content + NO extmark tag
- **Visual distinction:** Gray highlight on tagged lines
- **Editing freedom:** User can press o/O anywhere, edit anything
- **Perfect filtering:** Only untagged lines sent

**Benefits over virtual text:**
- User can scroll, navigate, edit anywhere in the buffer
- Can insert lines between any two response lines
- Response provides full context while editing
- Zero context bloat on send (filtered out)

## Testing Plan

1. **Basic pull:** Send prompt, pull response, verify lines appear gray with extmarks
2. **Line insertion:** Press `o` on response line, type annotation, verify normal color (no extmark)
3. **Send filtering:** Verify only untagged lines sent, check AI pane for confirmation
4. **Multiple iterations:** Pull → annotate → send → pull → verify annotations remain untagged
5. **Edge cases:**
   - Empty response
   - Very long response (500+ lines)
   - Scrolled AI pane
   - User edits response lines (tags should persist)
6. **Extmark validation:**
   - Check extmarks exist: `:lua vim.print(vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_get_namespaces()['llm_response_lines'], 0, -1, {details=true}))`
   - Verify gray highlighting on response lines
   - Verify no highlight on user lines
7. **Cross-TUI:** Test with Claude, Gemini, Grok (all use same marker)

## Success Criteria

- ✓ Response appears as gray highlighted real buffer lines
- ✓ Each response line has extmark with `llm_response = true`
- ✓ User can insert lines (o/O) anywhere - new lines are normal color
- ✓ User can edit, scroll, navigate freely
- ✓ Send filters correctly: only untagged lines sent to LLM
- ✓ Subsequent pulls delete previous response lines (clean slate)
- ✓ Works regardless of AI pane scroll state
- ✓ No context bloat (LLM doesn't receive its own response back)
- ✓ Extmarks persist even if response lines edited
