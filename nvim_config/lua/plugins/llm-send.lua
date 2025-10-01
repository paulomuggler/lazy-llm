-- /nvim_config/lua/plugins/llm-send.lua
return {
	{
		"LazyVim/LazyVim",
		-- Define keymaps in a dedicated 'llm' namespace
		keys = {
			{
				"<leader>llms",
				function()
					vim.cmd("write")
					local file = vim.fn.expand("%:p")
					vim.fn.jobstart({ "bash", "-lc", "llm-send " .. vim.fn.fnameescape(file) }, { detach = true })
				end,
				mode = "n",
				desc = "LLM: Send Buffer",
			},
			{
				"<leader>llms",
				function()
					local tmp = vim.fn.tempname() .. ".md"
					vim.cmd([[<,'>write! ]] .. tmp)
					vim.fn.jobstart(
						{
							"bash",
							"-lc",
							"llm-send " .. vim.fn.fnameescape(tmp) .. " ; rm -f " .. vim.fn.fnameescape(tmp),
						},
						{ detach = true }
					)
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
		},
	},
}

