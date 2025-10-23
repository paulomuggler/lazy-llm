# Image-Aware LLM Send Feature Specification

## Overview

### Problem Statement

The current `llm-send` workflow in DevEnv enables seamless prompt composition in Neovim with text sent to Claude Code or Gemini CLI via tmux. However, it breaks down when users want to include images (screenshots, UI mockups, diagrams) in their prompts, forcing them to:

1. Switch context from Neovim to the LLM TUI
2. Manually paste images directly into the TUI prompt
3. Lose the unified, buffer-based prompt composition workflow

### Solution Approach

Extend the `llm-send` plugin to support clipboard images while maintaining the elegant, memory-only architecture that LLM TUIs already use. No disk I/O, no temporary files - just capture clipboard images in Lua memory at insert-time and programmatically inject them during send.

### Key Design Principles

- **Memory-only**: Images stored in Lua buffers, never written to disk
- **Unified workflow**: Users never leave Neovim for image-enhanced prompts
- **Multi-image support**: Handle multiple images in a single prompt naturally
- **Clipboard drift immunity**: Images captured at insert-time, not send-time
- **Clean visual markers**: Users see clear placeholders indicating where images will be sent
- **Leverage existing TUI capabilities**: Use LLM TUIs' native Ctrl+V image paste functionality

## Architecture

### Components

#### 1. Image Buffer Manager (`llm-image-buffer.lua`)

Core module responsible for capturing, storing, and retrieving clipboard images.

```lua
-- Module: llm-image-buffer.lua
local M = {}

-- Internal state
M._state = {
  images = {},      -- images[marker_id] = { data = <binary>, format = "png", timestamp = ... }
  next_id = 1,      -- Auto-incrementing marker ID
}

-- API Functions
function M.insert_clipboard_image()
  -- 1. Detect if clipboard contains image
  -- 2. Extract binary image data from clipboard
  -- 3. Store in _state.images with unique ID
  -- 4. Insert marker text [IMG:N] at cursor position
  -- 5. Return marker_id
end

function M.get_image(marker_id)
  -- Retrieve stored image data by marker_id
end

function M.write_to_clipboard(marker_id)
  -- Write stored image back to system clipboard
end

function M.clear_all()
  -- Clear all stored images (cleanup after send)
end

function M.list_markers()
  -- Return array of all current marker IDs
end
```

**Data Structure:**
```lua
_state.images[1] = {
  data = <binary PNG data>,
  format = "png",              -- Future: support jpeg, etc.
  size_bytes = 245678,
  timestamp = 1729622400,      -- Capture time
  cursor_pos = {row = 5, col = 10}  -- Where marker was inserted
}
```

#### 2. Enhanced LLM Send (`llm-send.lua`)

Extended prompt-sending logic that interleaves text and images.

```lua
-- Enhanced send flow
function send_prompt_with_images()
  local prompt_text = get_buffer_content()
  local markers = extract_image_markers(prompt_text)  -- Parse [IMG:N] markers

  if #markers == 0 then
    -- Fallback to simple text-only send (current behavior)
    send_text_to_llm_pane(prompt_text)
    return
  end

  -- Complex flow: interleave text chunks and images
  local segments = split_by_markers(prompt_text, markers)

  for _, segment in ipairs(segments) do
    if segment.type == "text" then
      send_text_to_llm_pane(segment.content)

    elseif segment.type == "image" then
      local marker_id = segment.id

      -- Write image from memory back to clipboard
      require('llm-image-buffer').write_to_clipboard(marker_id)

      -- Simulate Ctrl+V paste to LLM pane
      tmux_send_keys(llm_pane, "C-v")

      -- Wait for paste to complete
      wait_for_paste(100)  -- 100ms delay
    end
  end

  -- Submit the complete prompt
  tmux_send_keys(llm_pane, "Enter")

  -- Cleanup: clear image buffer
  require('llm-image-buffer').clear_all()
end
```

**Helper Functions:**
```lua
function extract_image_markers(text)
  -- Parse text for [IMG:N] patterns
  -- Return: { {id=1, pos=123}, {id=2, pos=456}, ... }
end

function split_by_markers(text, markers)
  -- Split text into segments: text/image/text/image/...
  -- Return: { {type="text", content="..."}, {type="image", id=1}, ... }
end

function wait_for_paste(ms)
  -- Small delay to ensure tmux paste completes
  vim.defer_fn(function() end, ms)
end
```

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ User Workflow                                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. User types in prompt buffer: "Here's the bug:"          │
│  2. User takes screenshot → clipboard                       │
│  3. <leader>cI (insert-clipboard-image)                     │
│      │                                                       │
│      ├──> llm-image-buffer.insert_clipboard_image()         │
│      │    ├─ Read clipboard (pngpaste/osascript)            │
│      │    ├─ Store binary in _state.images[1]               │
│      │    └─ Insert "[IMG:1]" at cursor                     │
│      │                                                       │
│  4. User continues: "and here's the expected UI:"           │
│  5. Takes another screenshot                                │
│  6. <leader>cI again → [IMG:2] inserted, stored             │
│  7. <leader>ls (llm-send)                                   │
│      │                                                       │
│      ├──> send_prompt_with_images()                         │
│      │    ├─ Parse markers: [IMG:1], [IMG:2]                │
│      │    ├─ Segment 1: Send "Here's the bug:"              │
│      │    ├─ Segment 2: Paste image 1 (via Ctrl+V)          │
│      │    ├─ Segment 3: Send "and here's the expected UI:"  │
│      │    ├─ Segment 4: Paste image 2 (via Ctrl+V)          │
│      │    ├─ Submit prompt (Enter)                          │
│      │    └─ Clear image buffer                             │
│      │                                                       │
│  8. LLM TUI receives complete prompt with images            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## User Workflow

### Single Image Example

```
┌─────────────────────────────────────┐
│ Neovim Prompt Buffer                │
├─────────────────────────────────────┤
│ This button isn't rendering         │
│ correctly:                          │
│ [IMG:1]                             │ ← Inserted via <leader>cI
│                                     │
│ Please fix the CSS to match the     │
│ design system.                      │
└─────────────────────────────────────┘

Keys pressed:
- <leader>cI  → Insert clipboard image marker
- <leader>ls  → Send prompt with image to LLM
```

### Multiple Images Example

```
┌─────────────────────────────────────┐
│ Neovim Prompt Buffer                │
├─────────────────────────────────────┤
│ The current UI:                     │
│ [IMG:1]                             │ ← First screenshot
│                                     │
│ Should look like this instead:      │
│ [IMG:2]                             │ ← Second screenshot (mockup)
│                                     │
│ Focus on the header alignment and   │
│ color scheme.                       │
└─────────────────────────────────────┘
```

### Error Handling Example

```
User presses <leader>cI but clipboard has no image:

┌─────────────────────────────────────┐
│ Error: Clipboard does not contain  │
│ an image. Please take a screenshot │
│ first.                              │
└─────────────────────────────────────┘

No marker inserted, prompt buffer unchanged.
```

## Technical Design

### Clipboard Integration (macOS)

#### Reading Clipboard Images

```bash
#!/bin/bash
# Check if clipboard contains image
if osascript -e 'clipboard info' | grep -q 'picture'; then
  # Extract PNG data as base64
  pngpaste - | base64
else
  exit 1
fi
```

**Lua integration:**
```lua
function read_clipboard_image()
  local handle = io.popen("pngpaste - | base64")
  local result = handle:read("*a")
  handle:close()

  if result and result ~= "" then
    return result  -- base64-encoded PNG
  else
    return nil, "No image in clipboard"
  end
end
```

#### Writing to Clipboard

```bash
#!/bin/bash
# Write PNG data back to clipboard
echo "$BASE64_DATA" | base64 -d | pbcopy -pboard general -Prefer png
```

**Lua integration:**
```lua
function write_clipboard_image(base64_data)
  local temp_cmd = string.format("echo '%s' | base64 -d | pbcopy -pboard general -Prefer png", base64_data)
  os.execute(temp_cmd)
end
```

### Tmux Integration

#### Sending Keys to LLM Pane

```lua
function tmux_send_keys(pane_id, keys)
  local cmd = string.format("tmux send-keys -t %s %s", pane_id, keys)
  os.execute(cmd)
end

-- Usage
tmux_send_keys("prompt-pane.0", "C-v")   -- Ctrl+V
tmux_send_keys("prompt-pane.0", "Enter") -- Submit prompt
```

#### Identifying Target Pane

Current `llm-send.lua` already identifies the LLM pane. Reuse existing logic:

```lua
local llm_pane = get_llm_pane_id()  -- Returns "session:window.pane" identifier
```

### Marker Syntax

**Chosen format:** `[IMG:N]` where N is auto-incrementing integer

**Rationale:**
- Simple and readable
- Easy to parse with regex: `%[IMG:(%d+)%]`
- Visually distinct from markdown image syntax
- Unlikely to conflict with user text

**Alternatives considered:**
- `![img:1]` - Too similar to markdown, might confuse users
- `{{img:1}}` - Template-like, less intuitive
- `:image1:` - Could conflict with emoji syntax

### File Structure

```
dotfiles/nvim/.config/nvim/lua/plugins/
├── llm-send.lua              # Enhanced with image-aware send logic
└── llm-image-buffer.lua      # New: image buffer management module

dotfiles/nvim/.config/nvim/lua/config/
└── keymaps.lua               # Add <leader>cI for insert-clipboard-image
```

## Implementation Phases

### Phase 1: Core Image Buffer (MVP)

**Goal:** Basic single-image capture and storage

**Tasks:**
1. Create `llm-image-buffer.lua` module
2. Implement `insert_clipboard_image()` function
   - Detect clipboard image
   - Store in Lua table
   - Insert `[IMG:1]` marker at cursor
3. Implement `write_to_clipboard(marker_id)` function
4. Implement `clear_all()` cleanup function
5. Add keymap: `<leader>cI` → insert clipboard image

**Success criteria:**
- User can press `<leader>cI` and see `[IMG:1]` inserted
- Image data stored in memory (verify with debug print)

### Phase 2: Enhanced Send Logic

**Goal:** Send text + single image to LLM TUI

**Tasks:**
1. Modify `llm-send.lua` to detect `[IMG:N]` markers
2. Implement `extract_image_markers()` parser
3. Implement `split_by_markers()` text segmenter
4. Implement interleaved send logic:
   - Send text chunk
   - Write image to clipboard
   - Send Ctrl+V to LLM pane
   - Wait for paste completion
5. Add cleanup call after send completes

**Success criteria:**
- User can compose prompt with `[IMG:1]` marker
- Pressing `<leader>ls` successfully sends text + image to Claude Code/Gemini
- Image appears in LLM TUI prompt

### Phase 3: Multi-Image Support

**Goal:** Handle multiple images in single prompt

**Tasks:**
1. Extend `insert_clipboard_image()` to auto-increment IDs
2. Test send logic with multiple `[IMG:N]` markers
3. Handle edge case: markers out of order (e.g., [IMG:2] before [IMG:1])

**Success criteria:**
- User can insert multiple images: `[IMG:1]`, `[IMG:2]`, etc.
- All images sent in correct order during `llm-send`

### Phase 4: Error Handling & Edge Cases

**Goal:** Robust production-ready feature

**Tasks:**
1. Handle: Clipboard has no image on insert attempt
2. Handle: Marker exists but image missing from buffer
3. Handle: Large images (warn if >5MB?)
4. Handle: Send interrupted mid-flight
5. Handle: LLM TUI doesn't support images (warn user)
6. Add visual feedback (success/error notifications)

**Success criteria:**
- All edge cases handled gracefully with clear error messages
- No crashes or silent failures

### Phase 5: Polish & Documentation

**Goal:** Production-ready, documented feature

**Tasks:**
1. Add buffer-local highlights for `[IMG:N]` markers (visual distinction)
2. Add command: `:LLMImageClear` to manually clear buffer
3. Add command: `:LLMImageList` to show stored images
4. Update `llm-send` README with image workflow documentation
5. Add demo GIF/video to documentation

**Success criteria:**
- Feature fully documented
- Visual polish complete
- Ready for daily use

## Edge Cases & Error Handling

### 1. Clipboard has no image on insert

**Scenario:** User presses `<leader>cI` but clipboard contains text/nothing

**Handling:**
```lua
local data, err = read_clipboard_image()
if not data then
  vim.notify("Clipboard does not contain an image", vim.log.levels.ERROR)
  return
end
```

### 2. Marker exists but image missing from buffer

**Scenario:** User manually types `[IMG:99]` or buffer was cleared

**Handling:**
```lua
if not image_buffer.images[marker_id] then
  vim.notify(string.format("Image [IMG:%d] not found in buffer. Skipping.", marker_id), vim.log.levels.WARN)
  -- Continue with remaining segments
end
```

### 3. Large images

**Scenario:** User pastes 10MB screenshot

**Handling:**
```lua
local MAX_IMAGE_SIZE = 5 * 1024 * 1024  -- 5MB

if #data > MAX_IMAGE_SIZE then
  vim.notify("Warning: Image size exceeds 5MB. LLM may reject large images.", vim.log.levels.WARN)
  -- Still allow, but warn user
end
```

### 4. Send interrupted

**Scenario:** User cancels send mid-flight (Ctrl+C)

**Handling:**
```lua
-- Wrap send in pcall to ensure cleanup
local ok, err = pcall(send_prompt_with_images)
if not ok then
  vim.notify("Send interrupted: " .. err, vim.log.levels.ERROR)
end

-- Always cleanup, even on error
require('llm-image-buffer').clear_all()
```

### 5. LLM TUI doesn't support images

**Scenario:** User tries to send image to LLM that doesn't support them

**Handling:**
- Document which LLMs support images (Claude Code ✓, Gemini CLI ✓)
- Future: Detect LLM type and warn if unsupported
- For now: Rely on user knowledge

### 6. Markers out of order

**Scenario:** User has `[IMG:3]` before `[IMG:1]` in text

**Handling:**
- Send in the order they appear in text (document order), not numerical order
- This is natural and expected behavior

### 7. Tmux paste timing

**Scenario:** Ctrl+V sent before clipboard write completes

**Handling:**
```lua
function send_image_segment(marker_id)
  -- 1. Write to clipboard
  write_to_clipboard(marker_id)

  -- 2. Small delay to ensure clipboard write completes
  vim.defer_fn(function()
    tmux_send_keys(llm_pane, "C-v")
  end, 50)  -- 50ms should be sufficient
end
```

## Future Enhancements

### Short-term (Next 1-2 months)

1. **Visual marker highlighting**
   - Syntax highlighting for `[IMG:N]` markers
   - Show preview thumbnail on hover (if terminal supports)

2. **JPEG/GIF support**
   - Extend beyond PNG to other image formats
   - Auto-detect format from clipboard

3. **Image editing markers**
   - `[IMG:1|resize:50%]` - Resize before sending
   - `[IMG:1|crop:100x100]` - Crop to dimensions

### Medium-term (3-6 months)

4. **Drag-and-drop file support**
   - `[FILE:/path/to/image.png]` - Load from disk
   - Useful for inserting existing images, not just clipboard

5. **Image preview buffer**
   - `:LLMImagePreview 1` - Show image preview in floating window
   - Requires terminal image protocol support (Kitty, iTerm2)

6. **Persistent image cache**
   - Optional: Save images to `.llm-cache/` for session recovery
   - Clear on git commit or manual cleanup

### Long-term (6+ months)

7. **Context-aware compression**
   - Auto-compress large images before send
   - Preserve quality within LLM token limits

8. **Multi-modal composition**
   - Support video clips (if LLMs support in future)
   - Support audio snippets

9. **Cross-platform support**
   - Linux clipboard integration (xclip, wl-clipboard)
   - Windows clipboard integration (powershell)

10. **Integration with screen capture tools**
    - Direct integration with macOS screenshot shortcuts
    - Automatically capture and insert without clipboard

## Dependencies

### Required Tools (macOS)

- **pngpaste** - Extract PNG from clipboard
  ```bash
  brew install pngpaste
  ```

- **tmux** - Already required by DevEnv

- **nvim** with Lua 5.1+ - Already required by LazyVim

### Optional Tools

- **osascript** - Alternative clipboard detection (built-in on macOS)

### Platform-Specific Alternatives

**Linux:**
- Replace `pngpaste` with `xclip -selection clipboard -t image/png -o`
- Or use `wl-paste` for Wayland

**Windows:**
- Use PowerShell clipboard cmdlets: `Get-Clipboard -Format Image`

## Testing Strategy

### Manual Testing Checklist

- [ ] Single image insert and send
- [ ] Multiple images (2+) in one prompt
- [ ] Empty clipboard → error message shown
- [ ] Large image (>5MB) → warning shown
- [ ] Send to Claude Code → image appears
- [ ] Send to Gemini CLI → image appears
- [ ] Cancel send mid-flight → cleanup occurs
- [ ] Marker exists but no image → graceful skip
- [ ] Re-send same prompt → works (images re-captured)

### Integration Testing

- [ ] Works with existing `llm-send` text workflow
- [ ] Doesn't break text-only prompts
- [ ] Keymaps don't conflict with existing LazyVim bindings
- [ ] Compatible with tmux session management

### Performance Testing

- [ ] 10+ images in single prompt → acceptable latency
- [ ] 5MB image → no memory issues
- [ ] Rapid insert/delete markers → no crashes

## Success Metrics

### User Experience

- **Context switching eliminated**: Users never leave Neovim to send image prompts
- **Cognitive load reduced**: Visual markers clearly indicate image placement
- **Workflow unified**: Same `<leader>ls` command for text and image prompts

### Technical

- **Zero disk I/O**: All images stored in memory only
- **<100ms latency**: Image insert feels instantaneous
- **100% cleanup rate**: No memory leaks or orphaned data

### Adoption

- **Daily use**: Feature becomes default workflow for image-enhanced prompts
- **Documentation quality**: New users can learn workflow in <5 minutes
- **Reliability**: Zero crash reports related to image handling

## Conclusion

This feature extends DevEnv's unified LLM workflow to support images while maintaining the project's core principles: modularity, elegance, and zero unnecessary disk I/O. By leveraging existing LLM TUI capabilities and tmux automation, we achieve a seamless user experience without reinventing image handling.

The incremental implementation phases allow for iterative development and early validation, while the comprehensive edge case handling ensures production-ready reliability.

---

**Document Version:** 1.0
**Created:** 2025-10-22
**Status:** Approved for Implementation
**Next Steps:** Begin Phase 1 - Core Image Buffer (MVP)
