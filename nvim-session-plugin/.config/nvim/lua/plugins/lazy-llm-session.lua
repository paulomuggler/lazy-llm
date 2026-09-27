-- lazy-llm session wiring for the nvims lazy-llm launches (see lua/lazy_llm/session.lua).
-- Adds only an `init` to the persistence.nvim spec: loading, keys and options stay
-- whatever LazyVim and the user's own spec make them. An nvim not started by
-- lazy-llm (no LAZY_LLM_NVIM_ROLE) is left exactly as it was.
return {
	"folke/persistence.nvim",
	init = function()
		local role, path = vim.env.LAZY_LLM_NVIM_ROLE, vim.env.LAZY_LLM_NVIM_SESSION
		if not role then
			return
		end
		local session = require("lazy_llm.session")
		if role == "prompt" then
			session.use_prompt_session_dir()
		end
		if path then
			vim.api.nvim_create_autocmd("VimEnter", {
				once = true,
				-- The session's :edit/:badd run from inside this callback; without
				-- `nested` their BufRead/FileType autocmds never fire (no filetype,
				-- syntax or LSP on restored buffers).
				nested = true,
				callback = function()
					if vim.env.LAZY_LLM_NVIM_RESTORE == "1" then
						session.restore(path)
					end
					session.autosave(path)
				end,
			})
		end
	end,
}
