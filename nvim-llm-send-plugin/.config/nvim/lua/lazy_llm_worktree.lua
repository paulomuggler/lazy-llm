-- lazy_llm_worktree - the nvim side of per-pane worktree isolation (llm-wt)
--
-- An isolated AI pane runs in its own git worktree of the workspace's repo;
-- nvim stays in the main directory and never changes its cwd. This module:
--   * toggles the current buffer between the main copy of a file and the copy
--     in the visible AI pane's worktree (<leader>llmw, set up in llm-send.lua)
--   * gives code references and notes a worktree buffer's path as the SAME
--     repo-relative path its main copy has, which is what the agent sees from
--     its own cwd (not ".worktrees/.panes/…/src/x")
--   * marks worktree buffers with b:lazy_llm_wt (the branch), which the
--     dropbar winbar shows as "⎇ <branch>"

local M = {}

-- git facts per directory: { top, common } or false (not a repo). Cached for
-- the session: a directory doesn't change repos under a running nvim.
local git_cache = {}

local function git_info(dir)
	if git_cache[dir] ~= nil then
		return git_cache[dir] or nil
	end
	local out = vim.fn.systemlist({
		"git", "-C", dir, "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir",
	})
	if vim.v.shell_error ~= 0 or #out < 2 then
		git_cache[dir] = false
		return nil
	end
	git_cache[dir] = { top = out[1], common = out[2] }
	return git_cache[dir]
end

local function under(path, root)
	return path:sub(1, #root + 1) == root .. "/"
end

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "lazy-llm worktree" })
end

-- The main-directory counterpart of file `name` when it lives in ANOTHER
-- worktree of the repo nvim's cwd is in. Returns counterpart, worktree top;
-- nil for files of the main worktree itself, or of other repos.
function M.main_counterpart(name)
	local cwd = git_info(vim.fn.getcwd())
	if not cwd then
		return nil
	end
	local buf = git_info(vim.fn.fnamemodify(name, ":h"))
	if not buf or buf.top == cwd.top or buf.common ~= cwd.common or not under(name, buf.top) then
		return nil
	end
	return cwd.top .. name:sub(#buf.top + 1), buf.top
end

-- The path a code reference or note should carry for buffer `bufnr`:
-- relative to nvim's cwd, with a worktree file mapped to its main copy.
function M.reference_path(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr or 0)
	if name == "" then
		return vim.fn.expand("%:.")
	end
	return vim.fn.fnamemodify(M.main_counterpart(name) or name, ":.")
end

local function tmux(args)
	local out = vim.fn.system(vim.list_extend({ "tmux" }, args))
	return vim.v.shell_error == 0 and vim.trim(out) or ""
end

-- The worktree the window's visible AI pane runs in ("" when it shares the
-- main directory).
function M.visible_pane_worktree()
	local pane = vim.env.TMUX_PANE
	if not pane then
		return ""
	end
	local ai = tmux({ "display-message", "-p", "-t", pane, "#{@AI_PANE_ID}" })
	if ai == "" then
		return ""
	end
	return tmux({ "show-option", "-pqv", "-t", ai, "@lazy_llm_wt" })
end

-- Flip the current buffer between its main copy and the visible AI pane's
-- worktree copy, keeping the cursor line. The buffer is a normal, editable
-- one: writing it writes that worktree's file.
function M.toggle()
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		notify("No file in this buffer")
		return
	end
	local target = M.main_counterpart(name)
	if not target then
		local wt = M.visible_pane_worktree()
		if wt == "" then
			notify("The AI pane in view shares the main directory; it has no worktree copy")
			return
		end
		local cwd = git_info(vim.fn.getcwd())
		if not cwd or not under(name, cwd.top) then
			notify("This file isn't in the workspace's repository")
			return
		end
		target = wt .. name:sub(#cwd.top + 1)
	end
	if vim.fn.filereadable(target) == 0 then
		notify("No counterpart (new on one side only): " .. vim.fn.fnamemodify(target, ":~:."), vim.log.levels.WARN)
		return
	end
	local line = vim.fn.line(".")
	vim.cmd.edit(vim.fn.fnameescape(target))
	pcall(vim.api.nvim_win_set_cursor, 0, { math.min(line, vim.api.nvim_buf_line_count(0)), 0 })
end

-- Set b:lazy_llm_wt (the worktree's branch) on a buffer of another worktree
-- of this repo; leave every other buffer alone.
function M.mark(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return
	end
	local _, wt_top = M.main_counterpart(name)
	if not wt_top then
		return
	end
	local branch = vim.fn.systemlist({ "git", "-C", wt_top, "branch", "--show-current" })[1] or ""
	vim.b[bufnr].lazy_llm_wt = branch ~= "" and branch or vim.fn.fnamemodify(wt_top, ":t")
end

return M
