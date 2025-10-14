# Enhanced Response Pull - Design Specification

## Goal
Extend Response Pull to support extracting earlier responses from conversation history:
- Pull the N-th most recent response: `llm-pull -n 2`
- Pull a range of responses: `llm-pull -r 1:3`
- Maintain efficient in-memory conversation state

## Current Behavior
- `llm-pull` extracts latest response (everything after last `### END PROMPT` marker)
- No history access - can only pull the most recent response
- Re-parses tmux pane capture on every invocation

## Proposed Enhancements

### 1. Response Indexing
- **Response definition**: Content between `### END PROMPT` and next `### PROMPT`
- **Numbering**: 1 = most recent, counting backwards (2 = previous, 3 = before that, etc.)
- **Order**: Most recent first (intuitive for "give me response 1")

### 2. CLI Interface
```bash
# Current behavior - pull latest response
llm-pull

# Pull N-th most recent response (1-indexed, backwards from latest)
llm-pull -n 2      # 2nd most recent
llm-pull -n 5      # 5th most recent

# Pull range of responses (concatenated with delimiters)
llm-pull -r 1:3    # Latest 3 responses (1, 2, 3)
llm-pull -r 2:4    # Responses 2, 3, 4

# Error handling
llm-pull -n 99     # Error if not enough responses in history
```

### 3. Output Format

**Single response** (`llm-pull` or `llm-pull -n N`):
```
<response content>
```

**Range of responses** (`llm-pull -r START:END`):
```
<response 1 content>

--- Response 2 ---

<response 2 content>

--- Response 3 ---

<response 3 content>
```

### 4. nvim Keybinding UX

**Current:**
- `<leader>llmp` - pull latest response

**Proposed patterns:**

**Option A: Direct index binding** (requires space for simple pull)
```lua
<leader>llmp<space>  -- pull latest (need space to commit the 'p')
<leader>llmp2        -- pull 2nd most recent
<leader>llmp3        -- pull 3rd most recent
<leader>llmp2-4      -- pull range 2:4
```

**Option B: Input prompt** (simpler but extra step)
```lua
<leader>llmp         -- prompts: "Which response(s)? [enter=latest, N, or START:END]"
```

**Option C: Separate bindings**
```lua
<leader>llmp         -- pull latest (current behavior)
<leader>llmP         -- prompts for specific response/range
<leader>llm1-9       -- direct number keys for responses 1-9
```

**Recommendation**: Start with Option B (input prompt) for simplicity, consider Option A later if heavily used.

## Architecture: In-Memory Conversation State

### Problem with Current Approach
- Re-parses entire tmux pane capture on every `llm-pull` invocation
- Inefficient for repeated pulls or range queries
- No persistent conversation structure

### Proposed Solution: Conversation State Manager

**Concept**: Maintain a persistent background process or state file that tracks conversation structure:

```bash
# Conversation state structure (JSON or simple text format)
{
  "session": "dev-lazy-llm-claude",
  "window": "0",
  "pane": "0",
  "responses": [
    {
      "index": 1,
      "timestamp": "2025-10-14 10:30:22",
      "prompt_marker_line": 142,
      "end_marker_line": 144,
      "response_end_line": 198  # where next prompt starts or current end
    },
    {
      "index": 2,
      "timestamp": "2025-10-14 10:25:10",
      "prompt_marker_line": 85,
      "end_marker_line": 87,
      "response_end_line": 141
    }
  ]
}
```

**Implementation approaches:**

**Approach A: State file** (simpler, stateless scripts)
- `~/.local/state/lazy-llm/conversation-state-<session>-<window>-<pane>.json`
- Updated by `llm-send` after each prompt submission
- Updated by periodic watcher or on-demand by `llm-pull`
- Scripts remain stateless, state persists across invocations

**Approach B: Background daemon** (more complex, real-time)
- Long-running process monitors AI pane for markers
- Maintains in-memory conversation array
- Scripts communicate via Unix socket or named pipe
- More responsive but adds complexity

**Approach C: Hybrid - lazy state file**
- State file updated only when needed (lazy evaluation)
- `llm-pull` checks if state is stale (last update vs pane last-modified)
- Re-scans only if stale, otherwise uses cached state
- Balance between simplicity and efficiency

**Recommendation**: Start with Approach C (lazy state file) - good balance of efficiency and simplicity.

### State File Schema (v1)
```json
{
  "version": "1.0",
  "target_pane": "dev-lazy-llm-claude:0.0",
  "last_scan_line": 250,
  "last_updated": "2025-10-14T10:30:22Z",
  "conversations": [
    {
      "id": 1,
      "prompt_start": 142,
      "prompt_end": 144,
      "response_start": 145,
      "response_end": 198,
      "timestamp": "2025-10-14 10:30:22"
    }
  ]
}
```

### State Management Functions

**In `llm-pull` (or new `llm-state` utility):**

```bash
# Get or create state file for current AI pane
get_state_file() {
  local pane_id=$(echo "$TARGET" | tr ':.' '_')
  echo "$HOME/.local/state/lazy-llm/conversation-${pane_id}.json"
}

# Check if state is stale
is_state_stale() {
  local state_file=$1
  # Compare state last_scan_line with current pane history length
  # If pane has new content, state is stale
}

# Scan pane and rebuild state
rebuild_state() {
  local content=$(tmux capture-pane -t "$TARGET" -p -S -2000)

  # Find all ### PROMPT and ### END PROMPT markers
  # Build conversation array with line ranges
  # Write to state file
}

# Get response by index
get_response() {
  local index=$1
  local state_file=$(get_state_file)

  # Check if stale, rebuild if needed
  if is_state_stale "$state_file"; then
    rebuild_state
  fi

  # Extract response at index from state
  # Use line ranges to extract from tmux pane
}

# Get response range
get_response_range() {
  local start=$1
  local end=$2
  # Similar to get_response but for multiple
}
```

## Implementation Components

### Component 1: Update `llm-pull` script

**New features:**
```bash
#!/usr/bin/env bash
# llm-pull - Extract LLM responses from AI pane with history support

# Parse arguments
RESPONSE_INDEX=""
RESPONSE_RANGE=""

while getopts "n:r:" opt; do
  case $opt in
    n) RESPONSE_INDEX="$OPTARG" ;;
    r) RESPONSE_RANGE="$OPTARG" ;;
  esac
done

# Default behavior: latest response
if [ -z "$RESPONSE_INDEX" ] && [ -z "$RESPONSE_RANGE" ]; then
  RESPONSE_INDEX=1
fi

# Implementation...
```

### Component 2: Conversation State Manager

New utility: `llm-state` (or integrate into `llm-pull`)
- State file management
- Staleness detection
- State rebuild/update
- Query interface

### Component 3: Update nvim plugin

**Option B implementation** (input prompt):
```lua
{
  "<leader>llmp",
  function()
    vim.ui.input({
      prompt = "Response(s) [enter=latest, N, or START:END]: ",
      default = "",
    }, function(input)
      if not input or input == "" then
        input = "1"  -- default to latest
      end

      local cmd
      if input:match("^%d+$") then
        -- Single response number
        cmd = string.format("llm-pull -n %s", input)
      elseif input:match("^%d+:%d+$") then
        -- Range
        cmd = string.format("llm-pull -r %s", input)
      else
        vim.notify("Invalid format. Use: N or START:END", vim.log.levels.ERROR)
        return
      end

      -- Execute pull with specified response(s)
      local response = vim.fn.system("bash -lc " .. vim.fn.shellescape(cmd))

      if vim.v.shell_error ~= 0 or response == "" then
        vim.notify("Failed to pull response(s)", vim.log.levels.WARN)
        return
      end

      -- Insert into buffer with extmarks (same as current implementation)
      -- ... existing pull_response logic ...
    end)
  end,
  mode = "n",
  desc = "LLM: Pull response(s) by index/range"
}
```

## Implementation Phases

### Phase 1: Basic Index Support (MVP)
- [ ] Add `-n N` flag to `llm-pull`
- [ ] Parse all markers and extract N-th response
- [ ] Simple re-scan on each invocation (no state file yet)
- [ ] Update nvim to prompt for response number
- [ ] Test with Claude, Gemini, Codex

### Phase 2: Range Support
- [ ] Add `-r START:END` flag
- [ ] Concatenate multiple responses with delimiters
- [ ] Update nvim to support range syntax
- [ ] Test edge cases (invalid ranges, out of bounds)

### Phase 3: State File Optimization
- [ ] Implement conversation state file schema
- [ ] Add staleness detection
- [ ] Lazy rebuild on access
- [ ] Performance testing with long conversations

### Phase 4: Advanced Features (Future)
- [ ] State cleanup (old sessions)
- [ ] Export conversation history
- [ ] Search within responses
- [ ] Response diffing (compare two responses)

## Design Decisions

✅ **Response boundary**: Between `### END PROMPT` and next `### PROMPT`
✅ **Indexing**: 1 = most recent, counting backwards
✅ **Range output**: Concatenated responses with delimiter
✅ **nvim UX**: Input prompt (Phase 1), consider direct bindings later
✅ **State management**: Lazy state file (Phase 3 optimization)

## Future Research: Marker-Free Extraction

**Problem**: Relying on our own markers has limitations:
- Only works if markers are consistently added
- Requires modifying prompt send process
- Doesn't work with manual typing in TUI

**Potential solutions:**

### 1. Access Raw LLM Streams
**Approach**: Intercept network traffic or API calls
- Network packet sniffing (requires root, complex)
- Process memory reading (brittle, platform-specific)
- API call interception (if TUI uses library we can hook)

**Tools to explore:**
- `strace` / `dtrace` - system call tracing
- `mitmproxy` - HTTPS interception (if TUI uses web API)
- LD_PRELOAD hooks - intercept library calls

### 2. TUI-Specific Integration
**Approach**: Hook into TUI's native storage/history
- Claude CLI: Check if conversation history is stored locally
- Gemini CLI: Similar investigation
- Each TUI may have its own history format

**Research needed:**
- Where does each TUI store conversation data?
- Can we read their native formats?
- Would this be more reliable than tmux scraping?

### 3. AI-Assisted Parsing
**Approach**: Use heuristics to detect response boundaries
- Analyze text patterns (user vs AI style differences)
- Timestamp detection
- Whitespace/formatting analysis
- May work for simple cases, brittle for complex ones

**Recommendation**: Continue with marker-based approach for now (reliable, works today). Investigate TUI-specific integration in parallel for future enhancement.

## Testing Strategy

### Manual Testing Scenarios
1. **Basic index pull**: Pull responses 1, 2, 3 individually
2. **Range pull**: Pull 1:3, 2:4, verify concatenation
3. **Edge cases**:
   - Request index beyond history (should error gracefully)
   - Request range with start > end (should error)
   - Empty history (no responses yet)
4. **Long conversations**: 20+ exchanges, pull various ranges
5. **Multi-TUI**: Test with Claude, Gemini, Codex
6. **State staleness**: Verify state updates after new responses

### Integration Testing
1. Send prompt → pull latest → verify match
2. Send 3 prompts → pull range 1:3 → verify all included
3. Multiple windows/sessions → verify state isolation
4. Stale state → verify automatic rebuild

## Open Questions

1. **Keybinding ergonomics**: Is input prompt acceptable, or do we need faster access patterns?
2. **Response delimiter**: Is `--- Response N ---` clear enough, or use something else?
3. **State file location**: `~/.local/state/lazy-llm/` vs `~/.cache/lazy-llm/`?
4. **Max history**: Should we limit how far back we can pull? (e.g., last 50 responses)
5. **State cleanup**: When/how to clean up old state files?

## Success Criteria

- Can pull any response from history by index
- Can pull ranges of consecutive responses
- Performance acceptable even with long conversation history
- Works reliably across Claude, Gemini, Codex
- nvim UX feels natural and fast
- State management is transparent to user (just works™)
