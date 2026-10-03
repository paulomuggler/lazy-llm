-- lazy_llm_worktree - the nvim side of per-pane worktree isolation (llm-wt)
--
-- An isolated AI pane runs in its own git worktree of the workspace's repo;
-- nvim stays in the main directory and never changes its cwd. This module:
--   * toggles the current buffer between the main copy of a file and the copy
--     in the visible AI pane's worktree (<leader>llmw, set up in llm-send.lua);
--     when that pane's Claude session has worktrees of its own (subagents,
--     llm-wt claude-hook), it picks among all of them
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

-- The window's visible AI pane ("" outside lazy-llm).
function M.visible_ai_pane()
	local pane = vim.env.TMUX_PANE
	if not pane then
		return ""
	end
	return tmux({ "display-message", "-p", "-t", pane, "#{@AI_PANE_ID}" })
end

-- The worktree the window's visible AI pane runs in ("" when it shares the
-- main directory).
function M.visible_pane_worktree()
	local ai = M.visible_ai_pane()
	if ai == "" then
		return ""
	end
	return tmux({ "show-option", "-pqv", "-t", ai, "@lazy_llm_wt" })
end

-- Claude's worktrees (llm-wt claude-hook: lazyLlmKind=claude) whose
-- lazyLlmPane is tmux pane `ai` of this tmux server, in the repo of `dir`,
-- that still exist: { { path, branch }, ... } sorted by path. Pane ids
-- restart at %0 with each server, so one whose lazyLlmPaneServer isn't the
-- current server's #{start_time} is left out; one without it (made before it
-- was recorded) goes by the pane id alone. One git config call for the repo,
-- plus a for-each-ref only when some are found, plus one tmux call for the
-- start time only when some of them record a server.
function M.claude_worktrees(dir, ai)
	if not ai or ai == "" then
		return {}
	end
	local lines = vim.fn.systemlist({
		"git", "-C", dir, "config", "--get-regexp", [[^branch\..*\.lazyllm(kind|pane|paneserver)$]],
	})
	if vim.v.shell_error ~= 0 then
		return {}
	end
	local kind, pane, server = {}, {}, {}
	for _, l in ipairs(lines) do
		local b, k, v = l:match("^branch%.(.+)%.(lazyllm%a+) (.*)$")
		if k == "lazyllmkind" then
			kind[b] = v
		elseif k == "lazyllmpane" then
			pane[b] = v
		elseif k == "lazyllmpaneserver" then
			server[b] = v
		end
	end
	local now
	local refs = {}
	for b, p in pairs(pane) do
		if p == ai and kind[b] == "claude" then
			local s = server[b]
			if s and s ~= "" and now == nil then
				now = tmux({ "display-message", "-p", "-t", ai, "#{start_time}" })
			end
			if not s or s == "" or s == now then
				table.insert(refs, "refs/heads/" .. b)
			end
		end
	end
	if #refs == 0 then
		return {}
	end
	local out = vim.fn.systemlist(vim.list_extend({
		"git", "-C", dir, "for-each-ref", "--format=%(refname:lstrip=2)%09%(worktreepath)",
	}, refs))
	local wts = {}
	local missing = {}
	for _, l in ipairs(out) do
		local b, path = l:match("^(.-)\t(.*)$")
		if path and path ~= "" and vim.fn.isdirectory(path) == 1 then
			table.insert(wts, { path = path, branch = b })
		elseif b then
			missing[b] = true
		end
	end
	-- A worktree mid-rebase (a conflicted llm-wt integrate) has a detached
	-- HEAD, so for-each-ref gives it no path: find it among the detached
	-- worktrees by the branch its rebase is on.
	if next(missing) then
		local function rebase_branch(wt)
			local f = io.open(wt .. "/.git")
			if not f then
				return nil
			end
			local line = f:read("*l")
			f:close()
			local gitdir = line and line:match("^gitdir: (.*)$")
			if not gitdir then
				return nil
			end
			-- worktree.useRelativePaths: the gitdir is relative to the worktree.
			if gitdir:sub(1, 1) ~= "/" then
				gitdir = wt .. "/" .. gitdir
			end
			for _, sub in ipairs({ "rebase-merge", "rebase-apply" }) do
				local h = io.open(gitdir .. "/" .. sub .. "/head-name")
				if h then
					local head = h:read("*l")
					h:close()
					return head and head:match("^refs/heads/(.+)$")
				end
			end
			return nil
		end
		local cur, detached = nil, false
		local function consider()
			if cur and detached then
				local b = rebase_branch(cur)
				if b and missing[b] then
					table.insert(wts, { path = cur, branch = b })
				end
			end
		end
		for _, l in ipairs(vim.fn.systemlist({ "git", "-C", dir, "worktree", "list", "--porcelain" })) do
			if l:match("^worktree ") then
				consider()
				cur, detached = l:sub(10), false
			elseif l == "detached" then
				detached = true
			end
		end
		consider()
	end
	table.sort(wts, function(a, b)
		return a.path < b.path
	end)
	return wts
end

-- Where <leader>llmw can take file `name` when the visible AI pane's Claude
-- session has worktrees: the main copy, the pane's own worktree when it's
-- isolated, and each of those Claude worktrees, minus the side `name` is on.
-- Returns { { dir, label }, ... }, the repo-relative path ("/src/x"); or
-- nil, a message.
function M.candidates(name, claude)
	local cwd = git_info(vim.fn.getcwd())
	local buf = git_info(vim.fn.fnamemodify(name, ":h"))
	if not cwd or not buf or buf.common ~= cwd.common or not under(name, buf.top) then
		return nil, "This file isn't in the workspace's repository"
	end
	local list, seen = {}, { [buf.top] = true }
	local function add(dir, label)
		if dir ~= "" and not seen[dir] then
			seen[dir] = true
			table.insert(list, { dir = dir, label = label })
		end
	end
	add(cwd.top, "main copy")
	local wt = M.visible_pane_worktree()
	add(wt, "⎇ " .. vim.fn.fnamemodify(wt, ":t") .. " (this pane's worktree)")
	for _, c in ipairs(claude) do
		add(c.path, "⎇ " .. c.branch .. " (Claude worktree)")
	end
	return list, name:sub(#buf.top + 1)
end

-- Open `target` in the current window, keeping the cursor line.
local function open_counterpart(target)
	if vim.fn.filereadable(target) == 0 then
		notify("No counterpart (new on one side only): " .. vim.fn.fnamemodify(target, ":~:."), vim.log.levels.WARN)
		return
	end
	local line = vim.fn.line(".")
	vim.cmd.edit(vim.fn.fnameescape(target))
	pcall(vim.api.nvim_win_set_cursor, 0, { math.min(line, vim.api.nvim_buf_line_count(0)), 0 })
end

-- Flip the current buffer between its main copy and the visible AI pane's
-- worktree copy, keeping the cursor line. The buffer is a normal, editable
-- one: writing it writes that worktree's file. When the pane's Claude session
-- has worktrees too, pick among them all (directly, when only one other is
-- left).
function M.toggle()
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		notify("No file in this buffer")
		return
	end
	local cwd = git_info(vim.fn.getcwd())
	local claude = cwd and M.claude_worktrees(cwd.top, M.visible_ai_pane()) or {}
	if #claude > 0 then
		local list, rel = M.candidates(name, claude)
		if not list then
			notify(rel)
		elseif #list == 1 then
			open_counterpart(list[1].dir .. rel)
		else
			vim.ui.select(list, {
				prompt = "Open " .. rel:sub(2) .. " in",
				format_item = function(c)
					return c.label
				end,
			}, function(c)
				if c then
					open_counterpart(c.dir .. rel)
				end
			end)
		end
		return
	end
	local target = M.main_counterpart(name)
	if not target then
		local wt = M.visible_pane_worktree()
		if wt == "" then
			notify("The AI pane in view shares the main directory; it has no worktree copy")
			return
		end
		if not cwd or not under(name, cwd.top) then
			notify("This file isn't in the workspace's repository")
			return
		end
		target = wt .. name:sub(#cwd.top + 1)
	end
	open_counterpart(target)
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
