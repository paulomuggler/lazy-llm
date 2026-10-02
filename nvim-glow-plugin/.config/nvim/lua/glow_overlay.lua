-- Per-window, toggleable glow markdown overlay.
-- Renders the *current* buffer's live contents (unsaved edits included) with the
-- glow CLI, wrapped to the window's width, in a float that covers just that
-- window (the one it was opened from); the rest of the layout stays visible.
--   toggle key        open / close
--   q / <Esc>         close (from inside the overlay)
--   <C-h/j/k/l>, <C-w>h/j/k/l
--                     move to the neighbouring window / tmux pane, as from the
--                     source window; the overlay stays up, and entering the
--                     source window lands back on it
--   switch buffer     closes the overlay if the source window or the overlay
--                     itself shows another buffer (reopen manually)
--   window closed     closes the overlay
--   resize / maximize re-renders at the window's new size
--
-- glow is run under a pty (via `script`) so it emits ANSI styling, then its
-- output is fed into a process-less terminal (nvim_open_term) -- this keeps the
-- markdown formatting while avoiding a "[Process exited]" trailer and the
-- pty-resize truncation of a live terminal job.

local M = {}

local overlay = { win = nil, buf = nil, src = nil, src_win = nil }
local resize_timer = nil
-- Set while the overlay hands focus to its source window to navigate from there,
-- so the WinEnter redirect below doesn't bounce it straight back.
local navigating = false

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
  overlay.win, overlay.buf, overlay.src, overlay.src_win = nil, nil, nil, nil
end

-- Navigation keys inside the overlay act as if pressed in the source window:
-- from a float, `wincmd h` etc. only reach the window underneath it.
local NAV = {
  h = "TmuxNavigateLeft",
  j = "TmuxNavigateDown",
  k = "TmuxNavigateUp",
  l = "TmuxNavigateRight",
}

local function nav(dir, tmux)
  return function()
    local src_win = overlay.src_win
    if not (is_open() and src_win and vim.api.nvim_win_is_valid(src_win)) then
      return
    end
    navigating = true
    vim.api.nvim_set_current_win(src_win)
    local cmd = "wincmd " .. dir
    if tmux and vim.fn.exists(":" .. NAV[dir]) == 2 then
      cmd = NAV[dir]
    end
    pcall(vim.cmd, cmd)
    navigating = false
    -- Edge of the layout (or crossed into a tmux pane): stay on the overlay.
    if is_open() and vim.api.nvim_get_current_win() == src_win then
      vim.api.nvim_set_current_win(overlay.win)
    end
  end
end

-- src: buffer to render (default current); win: window to cover (default
-- current); enter: focus the overlay (default true).
function M.open(src, win, enter)
  if vim.fn.executable("glow") == 0 then
    vim.notify("glow CLI not found in PATH", vim.log.levels.ERROR)
    return
  end

  src = src or vim.api.nvim_get_current_buf()
  win = win or vim.api.nvim_get_current_win()
  if enter == nil then
    enter = true
  end
  if not vim.api.nvim_buf_is_valid(src) or vim.api.nvim_buf_get_name(src) == "" then
    vim.notify("Glow overlay: current buffer has no file name", vim.log.levels.WARN)
    return
  end

  local content = table.concat(vim.api.nvim_buf_get_lines(src, 0, -1, false), "\n")
  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile(vim.split(content, "\n"), tmp)

  overlay.buf = vim.api.nvim_create_buf(false, true)
  -- Anchored to the window, so it follows it around the layout; covers its
  -- winbar and text area (its statusline, if it has its own, stays visible).
  overlay.win = vim.api.nvim_open_win(overlay.buf, enter, {
    relative = "win",
    win = win,
    row = 0,
    col = 0,
    width = vim.api.nvim_win_get_width(win),
    height = vim.api.nvim_win_get_height(win),
    style = "minimal",
    border = "none",
  })
  overlay.src, overlay.src_win = src, win

  local opts = { buffer = overlay.buf, nowait = true, silent = true }
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set({ "n", "t" }, lhs, M.close, opts)
  end
  for dir in pairs(NAV) do
    vim.keymap.set({ "n", "t" }, "<C-" .. dir .. ">", nav(dir, true), opts)
    vim.keymap.set({ "n", "t" }, "<C-w>" .. dir, nav(dir, false), opts)
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
  local src, src_win = overlay.src, overlay.src_win
  local focused = vim.api.nvim_get_current_win() == overlay.win
  M.close()
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(src_win) then
      M.open(src, src_win, focused)
    end
  end)
end

local aug = vim.api.nvim_create_augroup("GlowOverlay", { clear = true })

-- Close the overlay when its window, or the window it covers, switches to a
-- different buffer (reopen manually).
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  group = aug,
  callback = function()
    if not is_open() then
      return
    end
    local src_win = overlay.src_win
    if
      not vim.api.nvim_win_is_valid(src_win)
      or vim.api.nvim_win_get_buf(src_win) ~= overlay.src
      or vim.api.nvim_win_get_buf(overlay.win) ~= overlay.buf
    then
      M.close()
    end
  end,
})

-- Close the overlay along with the window it covers (WinClosed fires while that
-- window is still valid, hence the match on its id).
vim.api.nvim_create_autocmd("WinClosed", {
  group = aug,
  callback = function(args)
    if is_open() and tonumber(args.match) == overlay.src_win then
      M.close()
    end
  end,
})

-- The covered window is hidden under the overlay: entering it (e.g. <C-l> from
-- its left neighbour) lands on the overlay instead.
vim.api.nvim_create_autocmd("WinEnter", {
  group = aug,
  callback = function()
    if navigating or not is_open() or vim.api.nvim_get_current_win() ~= overlay.src_win then
      return
    end
    vim.schedule(function()
      if is_open() and vim.api.nvim_get_current_win() == overlay.src_win then
        vim.api.nvim_set_current_win(overlay.win)
      end
    end)
  end,
})

-- Reflow to the new size when the covered window is resized (splits opened or
-- closed, tmux pane maximized, ...).
vim.api.nvim_create_autocmd("WinResized", {
  group = aug,
  callback = function()
    if not is_open() or not vim.tbl_contains(vim.v.event.windows, overlay.src_win) then
      return
    end
    if resize_timer then
      resize_timer:stop()
    end
    resize_timer = vim.defer_fn(refresh, 100)
  end,
})

return M
