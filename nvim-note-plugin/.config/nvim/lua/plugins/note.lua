-- nvim-note-plugin: NOTE marker tool for LLM workflow
-- Insert, collect, and navigate NOTE markers across files

-- Configuration
local config = {
  marker = "[NOTE: ]", -- The marker to insert (cursor placed between : and ])
  pattern = "%[NOTE:.-]", -- Lua pattern to match markers (.- = non-greedy any)
  rg_pattern = "\\[NOTE:.*\\]", -- ripgrep pattern for project-wide search
  editor_buffer_file = "/tmp/lazy-llm-editor-buffer", -- Track editor pane's current file
}

-- Helper: Get workspace root (git root or cwd)
local function get_workspace_root()
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
  return (git_root and git_root ~= "" and vim.v.shell_error == 0) and git_root or vim.fn.getcwd()
end

-- Helper: Get relative path from workspace root
local function get_relative_path(filepath)
  local root = get_workspace_root()
  if filepath:sub(1, #root) == root then
    return filepath:sub(#root + 2) -- +2 to skip the trailing /
  end
  return filepath
end

-- Helper: Check if we're in the prompt pane (via tmux @PROMPT_PANE window option)
local function is_prompt_pane()
  local tmux_pane = vim.env.TMUX_PANE
  if not tmux_pane then
    return false
  end

  -- Get session and window from current pane (like llm-append does)
  local session = vim.trim(vim.fn.system("tmux display-message -t " .. tmux_pane .. " -p '#S' 2>/dev/null"))
  local window = vim.trim(vim.fn.system("tmux display-message -t " .. tmux_pane .. " -p '#I' 2>/dev/null"))

  if session == "" or window == "" then
    return false
  end

  local result = vim.fn.system("tmux show-option -wv -t " .. session .. ":" .. window .. " @PROMPT_PANE 2>/dev/null")
  local prompt_pane = vim.trim(result)

  return prompt_pane ~= "" and tmux_pane == prompt_pane
end

-- Helper: Track current buffer for cross-pane access (called on BufEnter)
-- Only tracks if we're NOT in the prompt pane (to avoid overwriting editor's tracking)
local function track_editor_buffer()
  -- Double-check we're not in prompt pane before tracking
  if is_prompt_pane() then
    return
  end

  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname and bufname ~= "" then
    -- Only track real files (not special buffers)
    if vim.fn.filereadable(bufname) == 1 then
      vim.fn.writefile({ bufname }, config.editor_buffer_file)
    end
  end
end

-- Helper: Get the editor pane's current file (for use from prompt pane)
local function get_editor_buffer_file()
  if vim.fn.filereadable(config.editor_buffer_file) == 1 then
    local lines = vim.fn.readfile(config.editor_buffer_file)
    if #lines > 0 and lines[1] ~= "" then
      return lines[1]
    end
  end
  return nil
end

-- Collect notes from a specific file path
local function collect_file_notes(filepath)
  if vim.fn.filereadable(filepath) ~= 1 then
    return {}
  end

  local lines = vim.fn.readfile(filepath)
  local relative_path = get_relative_path(filepath)
  local notes = {}

  for lnum, line in ipairs(lines) do
    local note_text = line:match("%[NOTE:%s*(.-)%]")
    if note_text then
      table.insert(notes, {
        file = relative_path,
        lnum = lnum,
        text = note_text,
        line = line,
      })
    end
  end

  return notes
end

-- Insert NOTE marker at cursor position
local function insert_note()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- Insert marker at cursor position: [NOTE: ]
  -- Cursor will be positioned between : and ] (where the space is)
  local before = line:sub(1, col)
  local after = line:sub(col + 1)
  local new_line = before .. config.marker .. after

  vim.api.nvim_set_current_line(new_line)

  -- Position cursor after "[NOTE: " (before the closing ])
  -- marker = "[NOTE: ]" has length 8, position 7 is before ]
  vim.api.nvim_win_set_cursor(0, { row, col + #config.marker - 1 })

  -- Enter insert mode
  vim.cmd("startinsert")
end

-- Collect all NOTEs from current buffer
local function collect_buffer_notes()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local filepath = get_relative_path(vim.api.nvim_buf_get_name(bufnr))
  local notes = {}

  for lnum, line in ipairs(lines) do
    -- Match [NOTE: ...] and extract the content inside
    local note_text = line:match("%[NOTE:%s*(.-)%]")
    if note_text then
      table.insert(notes, {
        file = filepath,
        lnum = lnum,
        text = note_text,
        line = line,
      })
    end
  end

  return notes
end

-- Collect all NOTEs from project (using ripgrep)
local function collect_project_notes()
  local root = get_workspace_root()
  local cmd = string.format(
    "rg --no-heading --line-number --column '%s' %s 2>/dev/null",
    config.rg_pattern,
    vim.fn.shellescape(root)
  )

  local output = vim.fn.systemlist(cmd)
  local notes = {}

  for _, line in ipairs(output) do
    -- Parse rg output: file:line:col:content
    local file, lnum, content = line:match("^([^:]+):(%d+):%d+:(.*)$")
    if file and lnum then
      local relative_file = get_relative_path(file)
      -- Extract note text from [NOTE: ...] pattern
      local note_text = content:match("%[NOTE:%s*(.-)%]") or ""
      table.insert(notes, {
        file = relative_file,
        lnum = tonumber(lnum),
        text = note_text,
        line = content,
      })
    end
  end

  return notes
end

-- Format notes for output (markdown format)
local function format_notes(notes, title)
  local lines = {}

  -- Title as ## heading
  table.insert(lines, "## " .. title:gsub("^# ", ""))
  table.insert(lines, "")

  if #notes == 0 then
    table.insert(lines, "(No notes found)")
  else
    for _, note in ipairs(notes) do
      -- ### heading with file:line, then verbatim [NOTE: ...] on next line
      table.insert(lines, string.format("### - **%s:%d**", note.file, note.lnum))
      table.insert(lines, string.format("[NOTE: %s]", note.text))
      table.insert(lines, "")
    end
  end

  return table.concat(lines, "\n")
end

-- Send notes to prompt pane via temp file + tmux (handles multiline properly)
local function send_notes_to_prompt(notes, title)
  local formatted = format_notes(notes, title)
  local tmpfile = "/tmp/lazy-llm-notes-output.txt"

  -- Write to temp file (preserves newlines)
  vim.fn.writefile(vim.split(formatted, "\n"), tmpfile)

  -- Build tmux command to paste content
  -- 1. Get PROMPT_PANE from tmux window option
  -- 2. Load file into tmux buffer
  -- 3. Ensure insert mode and paste
  local script = [[
    PROMPT_PANE=""
    if [ -n "${TMUX_PANE:-}" ]; then
      _session=$(tmux display-message -t "${TMUX_PANE}" -p '#S' 2>/dev/null)
      _window=$(tmux display-message -t "${TMUX_PANE}" -p '#I' 2>/dev/null)
      if [ -n "$_session" ] && [ -n "$_window" ]; then
        PROMPT_PANE=$(tmux show-option -wv -t "$_session:$_window" @PROMPT_PANE 2>/dev/null)
      fi
    fi
    TARGET="${PROMPT_PANE:-:.2}"
    tmux send-keys -t "$TARGET" -X cancel 2>/dev/null || true
    tmux send-keys -t "$TARGET" Escape
    tmux send-keys -t "$TARGET" A
    tmux send-keys -t "$TARGET" "" Enter
    tmux send-keys -t "$TARGET" "" Enter
    tmux load-buffer ]] .. vim.fn.shellescape(tmpfile) .. [[

    tmux paste-buffer -t "$TARGET"
    tmux send-keys -t "$TARGET" "" Enter
  ]]

  vim.fn.jobstart({ "bash", "-lc", script }, { detach = false })
  vim.notify(string.format("Sent %d notes to prompt pane", #notes), vim.log.levels.INFO)
end

-- Pull buffer notes to prompt pane (smart: detects if in prompt pane)
local function pull_buffer_notes()
  local notes
  local title
  local in_prompt = is_prompt_pane()

  if in_prompt then
    -- We're in prompt pane, get notes from editor pane's buffer
    local editor_file = get_editor_buffer_file()
    if editor_file then
      if vim.fn.filereadable(editor_file) == 1 then
        notes = collect_file_notes(editor_file)
        title = "# Notes from " .. get_relative_path(editor_file)
        vim.notify("Pulling notes from editor: " .. get_relative_path(editor_file), vim.log.levels.INFO)
      else
        vim.notify("Tracked file not readable: " .. editor_file, vim.log.levels.WARN)
        return
      end
    else
      -- Debug: show tracking file status
      local track_file = config.editor_buffer_file
      local exists = vim.fn.filereadable(track_file) == 1
      vim.notify(
        string.format("No editor buffer tracked. Track file exists: %s", exists and "yes" or "no"),
        vim.log.levels.WARN
      )
      return
    end
  else
    -- Normal case: get notes from current buffer
    notes = collect_buffer_notes()
    local filepath = get_relative_path(vim.api.nvim_buf_get_name(0))
    title = "# Notes from " .. filepath
  end

  send_notes_to_prompt(notes, title)
end

-- Pull project notes to prompt pane
local function pull_project_notes()
  local notes = collect_project_notes()
  send_notes_to_prompt(notes, "# Notes from project")
end

-- Pattern for matching notes in navigation
local nav_pattern = "%[NOTE:"

-- Navigate to next NOTE in buffer
local function goto_next_note()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_row = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Search forward from current line
  for lnum = current_row + 1, #lines do
    if lines[lnum]:match(nav_pattern) then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      vim.cmd("normal! zz")
      return
    end
  end

  -- Wrap around to beginning
  for lnum = 1, current_row do
    if lines[lnum]:match(nav_pattern) then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      vim.cmd("normal! zz")
      vim.notify("Wrapped to beginning", vim.log.levels.INFO)
      return
    end
  end

  vim.notify("No notes found in buffer", vim.log.levels.WARN)
end

-- Navigate to previous NOTE in buffer
local function goto_prev_note()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_row = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Search backward from current line
  for lnum = current_row - 1, 1, -1 do
    if lines[lnum]:match(nav_pattern) then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      vim.cmd("normal! zz")
      return
    end
  end

  -- Wrap around to end
  for lnum = #lines, current_row, -1 do
    if lines[lnum]:match(nav_pattern) then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      vim.cmd("normal! zz")
      vim.notify("Wrapped to end", vim.log.levels.INFO)
      return
    end
  end

  vim.notify("No notes found in buffer", vim.log.levels.WARN)
end

-- Navigate project notes with fzf-lua picker
local function pick_project_notes()
  local notes = collect_project_notes()

  if #notes == 0 then
    vim.notify("No notes found in project", vim.log.levels.WARN)
    return
  end

  -- Format for fzf display
  local entries = {}
  for _, note in ipairs(notes) do
    local display = string.format("%s:%d: %s", note.file, note.lnum, note.text)
    table.insert(entries, display)
  end

  require("fzf-lua").fzf_exec(entries, {
    prompt = "Notes > ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          -- Parse selection: file:lnum: text
          local file, lnum = selected[1]:match("^([^:]+):(%d+):")
          if file and lnum then
            local root = get_workspace_root()
            local full_path = root .. "/" .. file
            vim.cmd("edit " .. vim.fn.fnameescape(full_path))
            vim.api.nvim_win_set_cursor(0, { tonumber(lnum), 0 })
            vim.cmd("normal! zz")
          end
        end
      end,
    },
    previewer = "builtin",
  })
end

-- List buffer notes in quickfix
local function quickfix_buffer_notes()
  local notes = collect_buffer_notes()
  local qf_list = {}

  for _, note in ipairs(notes) do
    table.insert(qf_list, {
      filename = vim.api.nvim_buf_get_name(0),
      lnum = note.lnum,
      text = note.text,
    })
  end

  if #qf_list > 0 then
    vim.fn.setqflist(qf_list)
    vim.cmd("copen")
    vim.notify(string.format("Found %d notes", #qf_list), vim.log.levels.INFO)
  else
    vim.notify("No notes found in buffer", vim.log.levels.WARN)
  end
end

-- List project notes in quickfix
local function quickfix_project_notes()
  local notes = collect_project_notes()
  local root = get_workspace_root()
  local qf_list = {}

  for _, note in ipairs(notes) do
    table.insert(qf_list, {
      filename = root .. "/" .. note.file,
      lnum = note.lnum,
      text = note.text,
    })
  end

  if #qf_list > 0 then
    vim.fn.setqflist(qf_list)
    vim.cmd("copen")
    vim.notify(string.format("Found %d notes in project", #qf_list), vim.log.levels.INFO)
  else
    vim.notify("No notes found in project", vim.log.levels.WARN)
  end
end

-- Set up buffer tracking autocmd for cross-pane note collection
vim.api.nvim_create_autocmd("BufEnter", {
  callback = track_editor_buffer,
  desc = "Track editor buffer for NOTE plugin cross-pane access",
})

return {
  {
    "LazyVim/LazyVim",
    keys = {
      -- Insert NOTE marker
      {
        "<leader>ni",
        insert_note,
        mode = "n",
        desc = "Note: Insert [NOTE:] marker",
      },

      -- Pull notes to prompt pane
      {
        "<leader>nb",
        pull_buffer_notes,
        mode = "n",
        desc = "Note: Pull buffer notes to prompt",
      },
      {
        "<leader>np",
        pull_project_notes,
        mode = "n",
        desc = "Note: Pull project notes to prompt",
      },

      -- Navigate notes in buffer
      {
        "]n",
        goto_next_note,
        mode = "n",
        desc = "Note: Go to next note",
      },
      {
        "[n",
        goto_prev_note,
        mode = "n",
        desc = "Note: Go to previous note",
      },

      -- Pick/browse notes
      {
        "<leader>nf",
        pick_project_notes,
        mode = "n",
        desc = "Note: Find notes in project (fzf)",
      },

      -- Quickfix lists
      {
        "<leader>nq",
        quickfix_buffer_notes,
        mode = "n",
        desc = "Note: Buffer notes to quickfix",
      },
      {
        "<leader>nQ",
        quickfix_project_notes,
        mode = "n",
        desc = "Note: Project notes to quickfix",
      },
    },
  },
}
