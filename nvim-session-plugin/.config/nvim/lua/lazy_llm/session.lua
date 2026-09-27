-- lazy_llm.session - rolling session snapshots for lazy-llm's editor and prompt nvims
--
-- lazy-llm launches both nvims of a workspace window with
--   LAZY_LLM_NVIM_ROLE     editor | prompt
--   LAZY_LLM_NVIM_SESSION  <dir>/.lazy-llm/sessions/{editor,prompt}[-N].vim
--   LAZY_LLM_NVIM_RESTORE  1 when that snapshot should be sourced on VimEnter
-- (wired up by lua/plugins/lazy-llm-session.lua). Each nvim keeps exactly one
-- snapshot file, overwritten in place, and never touches persistence.nvim's own
-- session files: the manual <leader>qs / <leader>qr sessions stay as they are.
-- The prompt role only moves persistence's session dir to its own
-- subdirectory, because both nvims share the workspace dir as cwd and would
-- otherwise save and restore the same <cwd>.vim.
--
-- `lazy-llm save` also calls snapshot() over RPC, for nvims started before
-- this module existed.

local M = {}

local e = vim.fn.fnameescape

-- Listed, named, normal buffers: the same filter persistence.nvim applies
-- before saving, so an nvim with nothing open never writes a snapshot.
local function file_buffers()
	return vim.tbl_filter(function(b)
		return vim.bo[b].buflisted and vim.bo[b].buftype == "" and vim.api.nvim_buf_get_name(b) ~= ""
	end, vim.api.nvim_list_bufs())
end

-- Create a new prompt backing file (same convention as the launcher's
-- create_prompt_file) and open it in the current window.
function M.open_new_prompt_file()
	local prompts_dir = vim.fn.getcwd() .. "/.lazy-llm/prompts"
	vim.fn.mkdir(prompts_dir, "p")

	local path = prompts_dir .. "/prompt-" .. os.date("%Y%m%d-%H%M%S") .. ".md"
	if vim.fn.filereadable(path) == 0 then
		vim.fn.writefile({}, path)
	end

	vim.cmd("edit " .. e(path))
end

-- Write the session to `path` (atomically, via a temp file). Returns `path`,
-- or "" when there's nothing worth saving or the write failed.
function M.snapshot(path)
	if #file_buffers() == 0 then
		return ""
	end
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local tmp = path .. ".tmp"
	-- :mksession sets v:this_session; a background snapshot shouldn't.
	local this_session = vim.v.this_session
	local ok = pcall(vim.cmd, "mksession! " .. e(tmp))
	vim.v.this_session = this_session
	if not ok or not os.rename(tmp, path) then
		os.remove(tmp)
		return ""
	end
	return path
end

-- Source a snapshot, then drop buffers whose files have since been deleted
-- (e.g. prompt files removed by retention). A prompt nvim left with no file
-- buffer gets a fresh prompt file, like a new workspace.
function M.restore(path)
	if vim.fn.filereadable(path) == 0 then
		return false
	end
	vim.cmd("silent! source " .. e(path))
	for _, b in ipairs(file_buffers()) do
		local gone = vim.fn.filereadable(vim.api.nvim_buf_get_name(b)) == 0
		local empty = not vim.api.nvim_buf_is_loaded(b)
			or (vim.api.nvim_buf_line_count(b) == 1 and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == "")
		if gone and empty and not vim.bo[b].modified then
			pcall(vim.api.nvim_buf_delete, b, {})
		end
	end
	if vim.env.LAZY_LLM_NVIM_ROLE == "prompt" and #file_buffers() == 0 then
		M.open_new_prompt_file()
	end
	return true
end

-- Keep `path` current: snapshot 1s after the layout or buffer list settles,
-- and once more on the way out.
function M.autosave(path)
	local timer = assert(vim.uv.new_timer())
	local group = vim.api.nvim_create_augroup("lazy_llm_session", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "BufDelete", "WinClosed", "TabClosed", "FocusLost" }, {
		group = group,
		callback = function()
			timer:stop()
			timer:start(1000, 0, vim.schedule_wrap(function()
				M.snapshot(path)
			end))
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			timer:stop()
			M.snapshot(path)
		end,
	})
end

-- Point persistence.nvim at its own session dir for the prompt pane. It's
-- applied after persistence's config has run, so it wins over the user's
-- `opts.dir` whatever order lazy.nvim merged the specs in.
function M.use_prompt_session_dir()
	local dir = vim.fn.stdpath("state") .. "/sessions/lazy-llm-prompt/"
	local function apply()
		require("persistence.config").options.dir = dir
		vim.fn.mkdir(dir, "p")
	end
	local cfg = package.loaded["persistence.config"]
	if cfg and next(cfg.options) then
		apply()
		return
	end
	vim.api.nvim_create_autocmd("User", {
		pattern = "LazyLoad",
		callback = function(ev)
			if ev.data == "persistence.nvim" then
				apply()
				return true
			end
		end,
	})
end

return M
