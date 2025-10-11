-- /nvim_config/lua/plugins/llm-send.lua

-- Configuration
local config = {
	clear_on_send = true, -- Clear buffer after sending (default: true)
}

-- Helper function to get tmux pane_base_index
local function get_pane_base_index()
	local handle = io.popen("tmux show-options -gw | grep pane-base-index | awk '{print $2}'")
	local result = handle:read("*a")
	handle:close()
	return tonumber(result) or 0
end

-- Helper function for code reference insertion
-- raw_mode: if true, insert inline; if false, wrap with newlines
local function add_code_reference(raw_mode)
	-- Get file path (relative to git root or cwd)
	local filepath = vim.fn.expand("%:.")

	-- Get line number(s)
	local mode = vim.fn.mode()
	local line_ref

	if mode == "v" or mode == "V" or mode == "\22" then -- \22 is visual block mode
		-- Visual mode: read current visual selection using line('v') and line('.')
		-- line('v') = start of visual selection, line('.') = cursor position (end)
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")

		-- Ensure start_line <= end_line (selection could go either direction)
		if start_line > end_line then
			start_line, end_line = end_line, start_line
		end

		if start_line == end_line then
			line_ref = "line " .. start_line
		else
			line_ref = "lines " .. start_line .. "-" .. end_line
		end
	else
		-- Normal mode: current line
		line_ref = "line " .. vim.fn.line(".")
	end

	-- Format reference
	local reference = string.format("# See %s in %s", line_ref, filepath)

	-- Build command with --raw flag if needed
	local cmd = raw_mode and "llm-append --raw " or "llm-append "
	cmd = cmd .. vim.fn.shellescape(reference)

	-- Send to prompt buffer
	vim.fn.jobstart({ "bash", "-lc", cmd }, { detach = true })
end

return {
	{
		"LazyVim/LazyVim",
		-- Define keymaps in a dedicated 'llm' namespace
		keys = {
			{
				"<leader>llms",
				function()
					local bufnr = vim.api.nvim_get_current_buf()
					local bufname = vim.api.nvim_buf_get_name(bufnr)

					if bufname == "" then
						-- Scratch buffer: write to temp file
						local tmp = vim.fn.tempname() .. ".md"
						vim.cmd("write! " .. tmp)
						vim.fn.jobstart(
							{
								"bash",
								"-lc",
								"llm-send " .. vim.fn.fnameescape(tmp) .. " ; rm -f " .. vim.fn.fnameescape(tmp),
							},
							{ detach = true }
						)
					else
						-- Named file: save and send
						vim.cmd("write")
						local file = vim.fn.expand("%:p")
						vim.fn.jobstart({ "bash", "-lc", "llm-send " .. vim.fn.fnameescape(file) }, { detach = true })
					end

					if config.clear_on_send then
						vim.cmd([[%delete _]])
					end
				end,
				mode = "n",
				desc = "LLM: Send Buffer",
			},
			{
				"<leader>llms",
				function()
					local tmp = vim.fn.tempname() .. ".md"
					vim.cmd([[
					<,'>write! 
					]] .. tmp)
					vim.fn.jobstart({
						"bash",
						"-lc",
						"llm-send " .. vim.fn.fnameescape(tmp) .. " ; rm -f " .. vim.fn.fnameescape(tmp),
					}, { detach = true })
				end,
				mode = "v",
				desc = "LLM: Send Selection",
			},
			{
				"<leader>llmd",
				function()
					vim.cmd([[%delete _]])
				end,
				mode = "n",
				desc = "LLM: Delete Buffer Content",
			},
			{
				"<leader>llmk",
				function()
					local char = vim.fn.getcharstr()
					local pane_base_index = get_pane_base_index()
					local cmd = string.format(
						'tmux send-keys -t "${AI_PANE:-:.%d}" %s',
						pane_base_index,
						vim.fn.shellescape(char)
					)
					vim.fn.jobstart({ "bash", "-c", cmd }, { detach = true })
				end,
				mode = "n",
				desc = "LLM: Send Next Keypress",
			},
			{
				"<leader>llmr",
				function()
					add_code_reference(true) -- raw mode
				end,
				mode = { "n", "v" },
				desc = "LLM: Add Code Reference (raw/inline)",
			},
			{
				"<leader>llmR",
				function()
					add_code_reference(false) -- wrapped mode
				end,
				mode = { "n", "v" },
				desc = "LLM: Add Code Reference (wrapped/newlines)",
			},
			-- @ Path Completion for LLM Workspace References
			-- Opens fuzzy picker to insert file or folder paths with @ prefix
			{
				"@",
				function()
					-- Save the buffer and position before opening picker
					local buf = vim.api.nvim_get_current_buf()
					local win = vim.api.nvim_get_current_win()
					local row, col = unpack(vim.api.nvim_win_get_cursor(win))

					-- Insert @ character first and mark the position
					vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { "@" })
					local at_col = col -- Save the column where @ was inserted
					vim.api.nvim_win_set_cursor(win, { row, col + 1 })

					-- Get list of files AND directories using fd
					vim.schedule(function()
						local cwd = vim.fn.getcwd()
						-- Include both files and directories (no --type flag = all)
						local fd_cmd = string.format("fd . %s", vim.fn.shellescape(cwd))
						local paths = vim.fn.systemlist(fd_cmd)

						-- Make paths relative to cwd and detect if directory
						local items = {}
						for _, path in ipairs(paths) do
							local rel_path = vim.fn.fnamemodify(path, ":.")
							-- Remove trailing slash if present (fd might add it)
							rel_path = rel_path:gsub("/$", "")
							-- Check if it's a directory
							local is_dir = vim.fn.isdirectory(path) == 1
							table.insert(items, {
								path = rel_path,
								is_dir = is_dir,
							})
						end

						-- Use vim.ui.select which will use Snacks.picker if configured
						vim.ui.select(items, {
							prompt = "@ Workspace Path (file or folder)",
							format_item = function(item)
								-- Add trailing / for directories to make them obvious
								return item.is_dir and (item.path .. "/") or item.path
							end,
						}, function(selected)
							if selected then
								vim.schedule(function()
									-- Return to original window/buffer
									vim.api.nvim_set_current_win(win)
									vim.api.nvim_set_current_buf(buf)

									-- Get the path to insert (add trailing / for directories)
									local path_to_insert = selected.is_dir and (selected.path .. "/") or selected.path

									-- Insert the file/folder path right after the @ (at_col + 1)
									vim.api.nvim_buf_set_text(
										buf,
										row - 1,
										at_col + 1,
										row - 1,
										at_col + 1,
										{ path_to_insert }
									)

									-- Move cursor to end of inserted text (after @ and path)
									vim.api.nvim_win_set_cursor(win, { row, at_col + 1 + #path_to_insert })
								end)
							end
						end)
					end)
				end,
				mode = "i",
				desc = "@ fuzzy picker for workspace file/folder references",
			},
			-- <C-f> in insert mode triggers native vim file completion
			{
				"<C-f>",
				"<C-x><C-f>",
				mode = "i",
				desc = "Trigger native file completion",
			},
		},
	},
}
