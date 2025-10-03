return {
  -- Disable mini.diff if LazyVim pulled it in
  { "nvim-mini/mini.diff", enabled = false },

  -- vim-fugitive: comprehensive git integration
  {
    "tpope/vim-fugitive",
    cmd = { "G", "Git", "Gdiffsplit", "Gread", "Gwrite", "Ggrep", "GMove", "GDelete", "GBrowse", "GRemove", "GRename", "Glgrep", "Gedit" },
    ft = { "fugitive" },
    keys = {
      { "<leader>gs", "<cmd>Git<cr>", desc = "Git Status" },
      { "<leader>gc", "<cmd>Git commit<cr>", desc = "Git Commit" },
      { "<leader>gp", "<cmd>Git push<cr>", desc = "Git Push" },
      { "<leader>gl", "<cmd>Git pull<cr>", desc = "Git Pull" },
      { "<leader>gb", "<cmd>Git blame<cr>", desc = "Git Blame" },
      { "<leader>gD", "<cmd>Gdiffsplit<cr>", desc = "Git Diff Split" },
    },
  },

  -- gitsigns: block-style inline diffs and git decorations
  {
    "lewis6991/gitsigns.nvim",
    enabled = true,
    event = "LazyFile",
    opts = function(_, opts)
      opts = opts or {}
      opts.signs = {
        add          = { text = '│' },
        change       = { text = '│' },
        delete       = { text = '_' },
        topdelete    = { text = '‾' },
        changedelete = { text = '~' },
        untracked    = { text = '┆' },
      }
      opts.signcolumn = true
      opts.numhl = false
      opts.linehl = false
      opts.word_diff = false
      opts.current_line_blame = false
      opts.current_line_blame_opts = {
        virt_text = true,
        virt_text_pos = "eol",
        delay = 1000,
      }
      opts.attach_to_untracked = true
      opts.watch_gitdir = {
        interval = 1000,
        follow_files = true,
      }
      opts._threaded_diff = true  -- Better performance
      opts.preview_config = {
        border = 'single',
        style = 'minimal',
        relative = 'cursor',
        row = 0,
        col = 1
      }

      opts.on_attach = function(bufnr)
        local gs = package.loaded.gitsigns

        -- Navigate hunks
        vim.keymap.set("n", "]h", gs.next_hunk, { buffer = bufnr, desc = "Next Hunk" })
        vim.keymap.set("n", "[h", gs.prev_hunk, { buffer = bufnr, desc = "Prev Hunk" })

        -- Toggle a clean "diff overlay" quickly
        vim.keymap.set("n", "<leader>gd", function()
          gs.toggle_signs()          -- gutter signs
          gs.toggle_linehl()         -- line background
          gs.toggle_deleted()        -- show removed lines as virtual lines
          gs.toggle_word_diff()      -- optional intra-line word diff
          gs.toggle_numhl()          -- number column highlight
          -- If on a recent gitsigns, also:
          if gs.toggle_virt_lines then gs.toggle_virt_lines() end
        end, { buffer = bufnr, desc = "Toggle Diff Overlay" })

        -- Stage/reset/unstage hunks
        vim.keymap.set({ "n", "v" }, "<leader>hs", gs.stage_hunk, { buffer = bufnr, desc = "Stage/Unstage Hunk" })
        vim.keymap.set({ "n", "v" }, "<leader>hr", gs.reset_hunk, { buffer = bufnr, desc = "Reset Hunk" })
        vim.keymap.set({ "n", "v" }, "<leader>hu", gs.undo_stage_hunk, { buffer = bufnr, desc = "Undo Stage Hunk" })
        vim.keymap.set("n", "<leader>hS", gs.stage_buffer, { buffer = bufnr, desc = "Stage Buffer" })
        vim.keymap.set("n", "<leader>hR", gs.reset_buffer, { buffer = bufnr, desc = "Reset Buffer" })
        vim.keymap.set("n", "<leader>hU", gs.reset_buffer_index, { buffer = bufnr, desc = "Unstage Buffer" })

        -- Preview hunk (per-hunk inline preview)
        vim.keymap.set("n", "<leader>hp", function()
          gs.preview_hunk_inline()
        end, { buffer = bufnr, desc = "Preview Hunk Inline" })

        -- Show all hunks inline using setqflist approach
        vim.keymap.set("n", "<leader>hd", function()
          -- Use gitsigns' show_deleted feature which shows all deleted lines inline
          -- Combined with word_diff, this gives a full file diff view
          local current_deleted = vim.b.gitsigns_status_dict and vim.b.gitsigns_status_dict.show_deleted
          local current_word_diff = vim.b.gitsigns_status_dict and vim.b.gitsigns_status_dict.word_diff

          if current_deleted or current_word_diff then
            -- Turn off if already on
            if current_deleted then gs.toggle_deleted() end
            if current_word_diff then gs.toggle_word_diff() end
            gs.toggle_linehl()
          else
            -- Turn on full inline diff view
            if not current_deleted then gs.toggle_deleted() end
            if not current_word_diff then gs.toggle_word_diff() end
            gs.toggle_linehl()
          end
        end, { buffer = bufnr, desc = "Toggle Full File Diff View" })

        -- Blame
        vim.keymap.set("n", "<leader>hb", function()
          gs.blame_line({ full = true })
        end, { buffer = bufnr, desc = "Blame Line" })
        vim.keymap.set("n", "<leader>tb", gs.toggle_current_line_blame, { buffer = bufnr, desc = "Toggle Line Blame" })


        -- Text object for hunks
        vim.keymap.set({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { buffer = bufnr, desc = "Select Hunk" })
      end

      return opts
    end,
  },

  -- vgit: unified inline diff view (better git diff visualization)
  {
    "tanvirtin/vgit.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "LazyFile",
    keys = {
      { "<leader>Vd", function() require("vgit").buffer_diff_preview() end, desc = "Buffer Diff Preview" },
      { "<leader>Vh", function() require("vgit").buffer_history_preview() end, desc = "Buffer History Preview" },
      { "<leader>Vb", function() require("vgit").buffer_blame_preview() end, desc = "Buffer Blame Preview" },
      { "<leader>Vp", function() require("vgit").project_diff_preview() end, desc = "Project Diff Preview" },
      { "<leader>Vc", function() require("vgit").buffer_gutter_blame_preview() end, desc = "Buffer Conflict Resolution" },
      { "<leader>Vs", function() require("vgit").project_stash_preview() end, desc = "Project Stash Browser" },
      { "<leader>Vl", function() require("vgit").project_logs_preview() end, desc = "Project Logs Browser" },
    },
    config = function()
      require("vgit").setup({
        settings = {
          live_blame = {
            enabled = false,
          },
          live_gutter = {
            enabled = false, -- Let gitsigns handle the gutter
          },
          scene = {
            diff_preference = "unified", -- unified = block-style inline
          },
        },
      })
    end,
  },
}
