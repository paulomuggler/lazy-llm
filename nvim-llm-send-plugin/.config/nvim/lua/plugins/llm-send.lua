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
	vim.fn.jobstart({ "bash", "-lc", cmd }, { detach = false })
end

-- Create namespace for LLM response extmark tagging
local llm_ns = vim.api.nvim_create_namespace("llm_response_lines")

-- Define custom highlight group for LLM response lines (lighter gray, slightly transparent)
vim.api.nvim_set_hl(0, "LLMResponse", {
	--	fg = "#999999", -- Lighter gray text
	bg = "#333333", -- Slightly darker gray background
	-- italic = true, -- Subtle italic to distinguish
	-- blend = 90, -- Slightly transparent to show through syntax
	-- nocombine = false, -- Combine with other highlights
})

-- Helper function to get untagged lines (user annotations only)
local function get_untagged_lines()
	local bufnr = vim.api.nvim_get_current_buf()
	local total_lines = vim.api.nvim_buf_line_count(bufnr)
	local untagged = {}

	-- Get all extmarks and build set of tagged rows
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, llm_ns, 0, -1, {})
	local tagged_rows = {}
	for _, mark in ipairs(marks) do
		tagged_rows[mark[2]] = true -- mark[2] is row (0-indexed)
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

-- Global flag to prevent recursive autocmd triggering
local _at_completion_active = false

-- Helper function to trigger @ path completion
-- Can be called from keymap or autocmd
local function trigger_at_completion()
	if _at_completion_active then
		return
	end

	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()
	local row, col = unpack(vim.api.nvim_win_get_cursor(win))
	local line_before = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]:sub(1, col)

	-- Check if we're at an @ path position (bare @ or with content)
	local existing_at_path = line_before:match("^@([^%s]*)$") or line_before:match("%s@([^%s]*)$")

	if not existing_at_path then
		return -- Not in an @ path context
	end

	-- Trigger the @ keymap by calling it directly
	local keys = vim.api.nvim_replace_termcodes("@", true, false, true)
	vim.api.nvim_feedkeys(keys, "m", false) -- Use 'm' mode for mapping
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
	local row = cursor[1] -- 1-indexed for buf_set_lines

	-- Insert response lines into buffer
	vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)

	-- Tag each inserted line with extmark and highlight
	-- Just the presence of extmark in our namespace = tagged as response
	for i = 0, #lines - 1 do
		local line_len = #lines[i + 1]
		vim.api.nvim_buf_set_extmark(bufnr, llm_ns, row + i, 0, {
			end_row = row + i,
			end_col = line_len,
			hl_group = "LLMResponse", -- Custom lighter gray
			priority = 200, -- Override syntax highlighting
			hl_mode = "combine", -- Combine with existing syntax
		})
	end

	vim.notify(
		string.format("Pulled %d response lines (gray=response, normal=annotations)", #lines),
		vim.log.levels.INFO
	)
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

						vim.fn.jobstart({
							"bash",
							"-lc",
							"llm-send " .. vim.fn.fnameescape(tmp) .. " ; rm -f " .. vim.fn.fnameescape(tmp),
						}, { detach = false })
					else
						-- Named file: save and send
						vim.cmd("write")
						local file = vim.fn.expand("%:p")
						vim.fn.jobstart({ "bash", "-lc", "llm-send " .. vim.fn.fnameescape(file) }, { detach = false })
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
					}, { detach = false })
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
			-- @ Path Completion using fzf-lua
			{
				"@",
				function()
					-- Set flag to prevent autocmd from triggering during completion
					_at_completion_active = true

					local buf = vim.api.nvim_get_current_buf()
					local win = vim.api.nvim_get_current_win()
					local row, col = unpack(vim.api.nvim_win_get_cursor(win))

					-- Check trigger criteria: start of line OR after whitespace OR after @ (continuation)
					local line_before = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]:sub(1, col)
					local char_before_cursor = col > 0 and line_before:sub(-1) or ""

					-- Check if we're continuing an existing @ path
					local is_continuation = line_before:match("@[^%s]+$") ~= nil

					-- Only trigger if at start of line, after whitespace, or continuing @ path
					if col > 0 and char_before_cursor ~= "" and not char_before_cursor:match("%s") and not is_continuation then
						-- Not at valid trigger position, just insert @
						vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { "@" })
						vim.api.nvim_win_set_cursor(win, { row, col + 1 })
						_at_completion_active = false
						return
					end

					-- Get workspace root (git root or cwd)
					local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
					local workspace_root = (git_root and git_root ~= "" and vim.v.shell_error == 0) and git_root
						or vim.fn.getcwd()

					-- Helper function to open picker and handle selection
					-- at_col_start: position of @ character (0-based)
					-- at_col_end: position after the @ path (0-based, where cursor was when triggered)
					local function open_picker(search_dir, base_path, initial_query, at_col_start, at_col_end)
						local query = initial_query or ""
						local cmd = string.format(
							"fd --hidden --exclude .git --exclude node_modules --max-results 500 --base-directory %s",
							vim.fn.shellescape(search_dir)
						)

						-- Track whether we've made a selection (vs ESC cancel)
						local selection_made = false

						require("fzf-lua").fzf_exec(cmd, {
							prompt = "@ " .. (base_path ~= "" and base_path or "workspace") .. " > ",
							query = query,
							-- Try using keymap.fzf for fzf native bindings
							keymap = {
								fzf = {
									["tab"] = "replace-query",
								},
							},
							winopts = {
								-- When picker closes, handle insert mode re-entry based on how it closed
								on_close = function()
									vim.schedule(function()
										if not selection_made then
											-- ESC was pressed - re-enter insert mode at original position
											vim.api.nvim_set_current_win(win)
											vim.api.nvim_set_current_buf(buf)

											-- Get current line to check if we're at EOL
											local current_line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
											local line_len = #current_line

											-- Check if we're at end of line
											if at_col_end >= line_len then
												-- At EOL: position cursor on last char, then append with 'a'
												vim.api.nvim_win_set_cursor(win, { row, line_len > 0 and line_len - 1 or 0 })
												local keys = vim.api.nvim_replace_termcodes("a", true, false, true)
												vim.api.nvim_feedkeys(keys, "n", false)
											else
												-- Mid-line: position cursor after the @ content, use insert
												vim.api.nvim_win_set_cursor(win, { row, at_col_end })
												local keys = vim.api.nvim_replace_termcodes("<Cmd>startinsert<CR>", true, false, true)
												vim.api.nvim_feedkeys(keys, "n", false)
											end
										end
										-- Clear flag in all cases
										if _at_completion_active then
											_at_completion_active = false
										end
									end)
								end,
							},
							actions = {
								["default"] = function(selected)
									if selected and selected[1] then
										selection_made = true
										vim.schedule(function()
											vim.api.nvim_set_current_win(win)
											vim.api.nvim_set_current_buf(buf)

											local path = selected[1]:gsub("/$", "")
											local full_path = base_path .. path

											-- Check if it's a directory
											local is_dir = vim.fn.isdirectory(workspace_root .. "/" .. full_path) == 1
											if is_dir then
												full_path = full_path .. "/"
											end

											-- Use original buffer position (don't use current cursor - fzf moved it)
											-- We want to replace from at_col_start to at_col_end on the original row
											vim.api.nvim_buf_set_text(
												buf,
												row - 1, -- Use original row (0-indexed for API)
												at_col_start + 1, -- +1 to preserve the @, start replacing after @
												row - 1,
												at_col_end or at_col_start + 1, -- End of current @ path content
												{ full_path }
											)

											-- Calculate final cursor position (0-based)
											-- at_col_start is position of @
											-- We inserted path starting at at_col_start + 1
											-- Path has length #full_path
											-- Last char position is: at_col_start + #full_path
											local final_col = at_col_start + #full_path

											-- Move cursor to last character of completion
											vim.api.nvim_win_set_cursor(win, { row, final_col })

											-- Clear flag before re-entering insert mode
											_at_completion_active = false

											-- Enter insert mode AFTER the cursor (append mode) using feedkeys
											local keys = vim.api.nvim_replace_termcodes("a", true, false, true)
											vim.api.nvim_feedkeys(keys, "n", false)

											-- If directory, auto-trigger completion again after a short delay
											if is_dir then
												vim.defer_fn(function()
													trigger_at_completion()
												end, 20)
											end
										end)
									end
								end,
							},
						})
					end

					-- Check if we're continuing an existing @ path
					local existing_at_path = line_before:match("^@([^%s]*)$") or line_before:match("%s@([^%s]*)$")

					if existing_at_path and existing_at_path ~= "" then
						-- Continuing an existing path - search from that subdirectory
						local base_path = existing_at_path:match("^(.*/)[^/]*$") or ""
						local search_dir = workspace_root .. "/" .. base_path
						search_dir = search_dir:gsub("/+", "/"):gsub("/$", "") -- Clean up

						-- Find the @ position (find returns 1-based, convert to 0-based for API)
						local at_pos = line_before:find("@[^%s]*$")
						local at_col_start = at_pos - 1 -- Convert to 0-based column index
						local at_col_end = col -- End of @ path is current cursor position
						local after_last_slash = existing_at_path:match("([^/]*)$")

						open_picker(search_dir, base_path, after_last_slash, at_col_start, at_col_end)
					else
						-- New @ - insert it and open picker
						vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { "@" })
						local at_col_start = col
						local at_col_end = col + 1 -- Position after the @
						vim.api.nvim_win_set_cursor(win, { row, col + 1 })

						vim.schedule(function()
							open_picker(workspace_root, "", "", at_col_start, at_col_end)
						end)
					end
				end,
				mode = "i",
				desc = "@ workspace path completion (fzf-lua)",
			},
			-- <C-f> in insert mode triggers native vim file completion
			{
				"<C-f>",
				"<C-x><C-f>",
				mode = "i",
				desc = "Trigger native file completion",
			},
			-- Ctrl+Space to manually trigger @ completion when editing @ path
			{
				"<C-Space>",
				trigger_at_completion,
				mode = "i",
				desc = "Manually trigger @ path completion",
			},
		},
		-- Setup autocmd for blink-like auto-triggering on text change
		init = function()
			local debounce_timer = nil

			-- Use InsertCharPre to detect when user is typing (not backspacing)
			vim.api.nvim_create_autocmd("InsertCharPre", {
				pattern = "*",
				callback = function()
					-- Cancel previous timer if still running
					if debounce_timer then
						vim.fn.timer_stop(debounce_timer)
					end

					-- Only trigger after a short delay of no typing
					if _at_completion_active then
						return
					end

					-- Schedule check for after the character is inserted
					debounce_timer = vim.fn.timer_start(15, function()
						vim.schedule(function()
							local buf = vim.api.nvim_get_current_buf()
							local win = vim.api.nvim_get_current_win()

							-- Check if still in insert mode
							if vim.fn.mode() ~= 'i' then
								return
							end

							local row, col = unpack(vim.api.nvim_win_get_cursor(win))
							local line_before = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]:sub(1, col)

							-- Check if we're at an @ path (bare @ or with content)
							local at_path = line_before:match("^@([^%s]*)$") or line_before:match("%s@([^%s]*)$")

							if at_path then
								-- Get workspace root to check if path exists
								local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
								local workspace_root = (git_root and git_root ~= "" and vim.v.shell_error == 0) and git_root or vim.fn.getcwd()

								-- Only check file existence if there's content after @
								if at_path ~= "" then
									local full_path = workspace_root .. "/" .. at_path

									-- Don't trigger if path is complete (exists as file)
									if vim.fn.filereadable(full_path) == 1 then
										return -- Complete file path, don't retrigger
									end
								end

								-- Trigger completion
								trigger_at_completion()
							end
						end)
					end)
				end,
			})
		end,
	},
}
