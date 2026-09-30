-- lazy_llm.orphan - end an nvim server left stuck on a prompt by its dead UI
--
-- The nvim in a tmux pane is two processes: the TUI (the pane's process) and
-- the `nvim --embed` server it starts. Kill the pane or the tmux server while
-- the server waits on a prompt (the swap-file ATTENTION pager, a hit-enter
-- prompt) and the TUI dies but the server never exits: a blocking prompt
-- defers both the UI's departure and SIGHUP/SIGTERM until a key answers it,
-- and no UI is left to send one. It sits reparented to init for good, and
-- every event it can't run while blocked queues up, until it holds gigabytes
-- (seen: 29 of them, 24 GB, days old).
--
-- libuv timers still fire while nvim blocks on input, and nvim_get_mode() may
-- be called from them, so poll: once the process that started this server is
-- gone and nvim is still blocked on input, exit. A server that outlives its
-- TUI on purpose (:detach) isn't blocked, so it's left alone.

local M = {}

local INTERVAL_MS = 5000

function M.start()
	if not vim.tbl_contains(vim.v.argv, "--embed") then
		return
	end
	local parent = vim.uv.os_getppid()
	-- Two checks in a row, so a prompt that the orphaned server is about to
	-- get past on its own (it's exiting) isn't cut short.
	local strikes = 0
	local timer = assert(vim.uv.new_timer())
	timer:start(INTERVAL_MS, INTERVAL_MS, function()
		if vim.uv.os_getppid() == parent or not vim.api.nvim_get_mode().blocking then
			strikes = 0
			return
		end
		strikes = strikes + 1
		if strikes >= 2 then
			-- Only a hard exit gets out from under the prompt. Unsaved changes
			-- are in the swap file, as after a crash.
			os.exit(1)
		end
	end)
	timer:unref()
end

return M
