-- Full-screen, per-buffer, toggleable glow markdown overlay.
-- Renders the *current* buffer's live contents (unsaved edits included) with the
-- glow CLI, wrapped to the actual window width, in a full-editor overlay.
--   toggle key        open / close
--   q / <Esc>         close (from inside the overlay)
--   switch buffer     closes the overlay (reopen manually)
--   resize / maximize re-renders at the new width
--
-- glow is run under a pty (via `script`) so it emits ANSI styling, then its
-- output is fed into a process-less terminal (nvim_open_term) -- this keeps the
-- markdown formatting while avoiding a "[Process exited]" trailer and the
-- pty-resize truncation of a live terminal job.

local M = {}

local overlay = { win = nil, buf = nil, src = nil }
local resize_timer = nil

local function is_open()
  return overlay.win ~= nil and vim.api.nvim_win_is_valid(overlay.win)
end
M.is_open = is_open

function M.close()
  if is_open() then
    pcall(vim.api.nvim_win_close, overlay.win, true)
  end
  if overlay.buf and vim.api.nvim_buf_is_valid(overlay.buf) then
    pcall(vim.api.nvim_buf_delete, overlay.buf, { force = true })
  end
  overlay.win, overlay.buf, overlay.src = nil, nil, nil
end

function M.open(src)
  if vim.fn.executable("glow") == 0 then
    vim.notify("glow CLI not found in PATH", vim.log.levels.ERROR)
    return
  end

  src = src or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(src) or vim.api.nvim_buf_get_name(src) == "" then
    vim.notify("Glow overlay: current buffer has no file name", vim.log.levels.WARN)
    return
  end

  local content = table.concat(vim.api.nvim_buf_get_lines(src, 0, -1, false), "\n")
  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile(vim.split(content, "\n"), tmp)

  overlay.buf = vim.api.nvim_create_buf(false, true)
  overlay.win = vim.api.nvim_open_win(overlay.buf, true, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = math.max(1, vim.o.lines - vim.o.cmdheight - 1),
    style = "minimal",
    border = "none",
  })
  overlay.src = src

  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set({ "n", "t" }, lhs, M.close, { buffer = overlay.buf, nowait = true, silent = true })
  end

  local width = vim.api.nvim_win_get_width(overlay.win)
  -- Run glow under a pty (`script`) so it emits ANSI styling even though we are
  -- capturing its output rather than attaching it to a live terminal.
  local glow_cmd = string.format("glow -w %d %s", width, vim.fn.shellescape(tmp))
  local cmd
  if vim.fn.executable("script") == 1 then
    cmd = { "script", "-qfec", glow_cmd, "/dev/null" }
  else
    cmd = { "glow", "-w", tostring(width), tmp } -- no pty: plain text fallback
  end
  vim.system(cmd, {}, function(res)
    vim.schedule(function()
      vim.fn.delete(tmp)
      if not is_open() then
        return
      end
      local out = res.stdout or ""
      if (out == nil or out == "") and res.code ~= 0 then
        out = res.stderr or "glow failed"
      end
      -- A pty already emits CRLF; the fallback path emits LF only.
      if not out:find("\r\n") then
        out = out:gsub("\n", "\r\n")
      end
      local chan = vim.api.nvim_open_term(overlay.buf, {})
      vim.api.nvim_chan_send(chan, out)
      -- vterm processes the bytes on the next ticks; scroll to top after.
      vim.defer_fn(function()
        if is_open() then
          pcall(vim.api.nvim_win_call, overlay.win, function()
            vim.cmd("normal! gg")
          end)
        end
      end, 30)
    end)
  end)
end

function M.toggle()
  if is_open() then
    M.close()
  else
    M.open()
  end
end

local function refresh()
  if not is_open() then
    return
  end
  local src = overlay.src
  M.close()
  vim.schedule(function()
    M.open(src)
  end)
end

local aug = vim.api.nvim_create_augroup("GlowOverlay", { clear = true })

-- Close the overlay when moving to a different source buffer (reopen manually).
vim.api.nvim_create_autocmd("BufEnter", {
  group = aug,
  callback = function()
    if not is_open() then
      return
    end
    local cur = vim.api.nvim_get_current_buf()
    if cur ~= overlay.src and cur ~= overlay.buf then
      M.close()
    end
  end,
})

-- Reflow to the new width when the UI is resized (e.g. tmux pane maximized).
vim.api.nvim_create_autocmd("VimResized", {
  group = aug,
  callback = function()
    if not is_open() then
      return
    end
    if resize_timer then
      resize_timer:stop()
    end
    resize_timer = vim.defer_fn(refresh, 100)
  end,
})

return M
