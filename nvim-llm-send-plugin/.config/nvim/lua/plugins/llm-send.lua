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
		},
	},
}
