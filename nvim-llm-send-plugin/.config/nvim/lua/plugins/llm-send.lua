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

-- Create namespace for LLM response extmark tagging
local llm_ns = vim.api.nvim_create_namespace('llm_response_lines')

-- Helper function to get untagged lines (user annotations only)
local function get_untagged_lines()
	local bufnr = vim.api.nvim_get_current_buf()
	local total_lines = vim.api.nvim_buf_line_count(bufnr)
	local untagged = {}

	-- Get all extmarks and build set of tagged rows
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, llm_ns, 0, -1, {})
	local tagged_rows = {}
	for _, mark in ipairs(marks) do
		tagged_rows[mark[2]] = true  -- mark[2] is row (0-indexed)
	end

	-- Collect untagged lines only
	for i = 0, total_lines - 1 do
		if not tagged_rows[i] then
			local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
			table.insert(untagged, line)
		end
	end

	return untagged
end

-- Function to pull response and insert as extmark-tagged lines
local function pull_response()
	-- Get current buffer
	local bufnr = vim.api.nvim_get_current_buf()

	-- Clear all existing response lines (delete lines with extmarks in our namespace)
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, llm_ns, 0, -1, {})
	-- Delete lines from bottom to top (avoid line number shifts)
	for i = #marks, 1, -1 do
		local mark = marks[i]
		local row = mark[2]
		vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, {})
	end
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
	local row = cursor[1]  -- 1-indexed for buf_set_lines

	-- Insert response lines into buffer
	vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)

	-- Tag each inserted line with extmark and highlight
	-- Just the presence of extmark in our namespace = tagged as response
	for i = 0, #lines - 1 do
		local line_len = #lines[i + 1]
		vim.api.nvim_buf_set_extmark(bufnr, llm_ns, row + i, 0, {
			end_row = row + i,
			end_col = line_len,
			hl_group = "Comment",  -- Gray text
			priority = 200,         -- Override syntax highlighting
		})
	end

	vim.notify(string.format("Pulled %d response lines (gray=response, normal=annotations)", #lines), vim.log.levels.INFO)
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

						-- Get untagged lines (user annotations only, filter out response lines)
						local untagged_lines = get_untagged_lines()

						-- Write untagged lines to temp file
						vim.fn.writefile(untagged_lines, tmp)

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
				desc = "LLM: Send Buffer (filters out response lines)",
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
				pull_response,
				mode = "n",
				desc = "LLM: Pull response as tagged lines",
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
