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
			-- @ Path Completion for LLM Workspace References
			-- Opens fuzzy file picker to insert file paths with @ prefix
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

					-- Get list of files using fd (fast file finder)
					vim.schedule(function()
						local cwd = vim.fn.getcwd()
						local fd_cmd = string.format("fd --type f . %s", vim.fn.shellescape(cwd))
						local files = vim.fn.systemlist(fd_cmd)

						-- Make paths relative to cwd
						for i, file in ipairs(files) do
							files[i] = vim.fn.fnamemodify(file, ":.")
						end

						-- Use vim.ui.select which will use Snacks.picker if configured
						vim.ui.select(files, {
							prompt = "@ Workspace File",
							format_item = function(item)
								return item
							end,
						}, function(selected)
							if selected then
								vim.schedule(function()
									-- Return to original window/buffer
									vim.api.nvim_set_current_win(win)
									vim.api.nvim_set_current_buf(buf)

									-- Insert the file path right after the @ (at_col + 1)
									vim.api.nvim_buf_set_text(
										buf,
										row - 1,
										at_col + 1,
										row - 1,
										at_col + 1,
										{ selected }
									)

									-- Move cursor to end of inserted text (after @ and path)
									vim.api.nvim_win_set_cursor(win, { row, at_col + 1 + #selected })
								end)
							end
						end)
					end)
				end,
				mode = "i",
				desc = "@ fuzzy file picker for workspace references",
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
