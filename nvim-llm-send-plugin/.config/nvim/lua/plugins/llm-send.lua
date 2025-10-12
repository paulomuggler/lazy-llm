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

-- Create namespace for LLM response virtual text
local llm_ns = vim.api.nvim_create_namespace('llm_response_virtual')

-- Function to pull LLM response and display as virtual text
local function pull_response_virtual()
	-- Get current buffer
	local bufnr = vim.api.nvim_get_current_buf()

	-- Clear all existing virtual text in this buffer
	vim.api.nvim_buf_clear_namespace(bufnr, llm_ns, 0, -1)

	-- Call llm-pull to get response
	local response = vim.fn.system("bash -lc 'llm-pull'")

	if vim.v.shell_error ~= 0 or response == "" then
		vim.notify("Failed to pull response or no response found", vim.log.levels.WARN)
		return
	end

	-- Split into lines
	local lines = vim.split(response, "\n", { trimempty = false })

	-- Get current cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1  -- Convert to 0-indexed

	-- Insert virtual text lines BELOW cursor position
	-- Place all virtual lines on a single extmark at the cursor line
	-- They will render below the cursor line
	local virt_lines_table = {}
	for i, line in ipairs(lines) do
		table.insert(virt_lines_table, {{line, "Comment"}})
	end

	vim.api.nvim_buf_set_extmark(bufnr, llm_ns, row, 0, {
		virt_lines = virt_lines_table,  -- Gray comment color
	})

	vim.notify(string.format("Pulled %d lines as virtual text", #lines), vim.log.levels.INFO)
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
			{
				"<leader>llmp",
				pull_response_virtual,
				mode = "n",
				desc = "LLM: Pull response as virtual text",
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
