# @ Workspace Path Completion

Simple fuzzy file picker for workspace-wide path references, triggered by `@` in insert mode.

## Implementation

**File**: `nvim-llm-send-plugin/.config/nvim/lua/plugins/llm-send.lua`

Uses fzf-lua picker with `fd` to search workspace files recursively.

## Features

- **Fuzzy search** - Type to filter entire workspace
- **Workspace-aware** - Searches from git root (or cwd)
- **Auto-continuation** - Directory selections automatically trigger next level
- **Manual continuation** - Type `@` at end of path to continue/refine
- **Pre-filled search** - Continuation pre-fills incomplete segment
- **Directory support** - Trailing `/` preserved for folders
- **Hidden files** - Includes dotfiles, excludes `.git`, `node_modules`
- **Limit 500 results** - Prevents UI freeze on huge workspaces

## Usage

### Basic

```
@          → Opens fuzzy picker with all workspace files
Type: nv   → Filters to "nvim", "env", etc.
<Enter>    → Inserts selected path
```

### Auto-continuation (directories)

```
@                    → Pick "external/"
                     → Automatically opens picker for external/*
                     → Pick "lazy-llm/"
                     → Automatically opens picker for external/lazy-llm/*
                     → Pick "README.md" (file, stops auto-continuing)
Result: @external/lazy-llm/README.md
```

### Manual continuation (refine/edit)

```
@external/lazy      → Cursor after "lazy", press @
                    → Opens picker searching external/*
                    → Pre-fills "lazy" in search box
                    → Type more or select different path
```

## Trigger Rules

Only triggers when `@` is:
1. At start of line: `@path`
2. After whitespace: `  @path`

Does NOT trigger: `user@email.com`, `some@thing`

(Just inserts literal `@` if not at valid position)

## Technical Details

### Workspace Root Detection

```lua
local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
local workspace_root = (git_root and vim.v.shell_error == 0) and git_root or vim.fn.getcwd()
```

Priority: git root > current working directory

### fd Command

```bash
fd --hidden \
   --exclude .git \
   --exclude node_modules \
   --max-results 500 \
   --base-directory <workspace_root>
```

### Path Insertion Logic

```lua
-- Strip trailing slash from fd output
local path = selected[1]:gsub("/$", "")

-- Check if directory, add trailing slash
if vim.fn.isdirectory(workspace_root .. "/" .. path) == 1 then
    path = path .. "/"
end
```

Ensures clean insertion without double slashes.

## Why fzf-lua?

Initial implementation attempted custom blink.cmp source for native completion feel. **Issues**:

1. **No project-wide fuzzy** - blink.cmp only fuzzy-matches current result set
2. **Complex implementation** - Custom source, async handling, range calculations
3. **Brittle** - Regex patterns, edge cases, double slashes

**fzf-lua advantages**:
- True fuzzy search over entire workspace
- Simple, proven picker UI
- Direct control over insertion logic
- Much less code to maintain

**Trade-off**: Opens picker UI instead of inline completion menu. Acceptable given superior search capabilities.

## Configuration

Located in `llm-send.lua` keymap definition:

```lua
{
    "@",
    function()
        -- ... implementation ...
    end,
    mode = "i",
    desc = "@ workspace path completion (fzf-lua)",
}
```

### Adjust Result Limit

```lua
fd --max-results 1000  -- Increase from 500
```

### Add Exclusions

```lua
fd --exclude .git --exclude build --exclude dist
```

## Example Use Case

LLM prompt with file references:

```markdown
Please review these files:

@external/lazy-llm/nvim-llm-send-plugin/.config/nvim/lua/plugins/llm-send.lua
@docs/architecture.md

And update @README.md with implementation details.
```

## Related Files

- `nvim-llm-send-plugin/.config/nvim/lua/plugins/llm-send.lua` - Implementation
- `~/.config/nvim/lua/plugins/fzf-lua.lua` - fzf-lua configuration
