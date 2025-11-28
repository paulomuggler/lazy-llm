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
  -- Using config instead of opts to completely override LazyVim's gitsigns config
  {
    "lewis6991/gitsigns.nvim",
    enabled = true,
    event = "LazyFile",
    -- Override snacks_picker <leader>gd binding with our toggle
    keys = {
      {
        "<leader>gd",
        function()
          local gs = require("gitsigns")
          gs.toggle_signs()          -- gutter signs
          gs.toggle_linehl()         -- line background
          gs.toggle_deleted()        -- show removed lines as virtual lines
          gs.toggle_word_diff()      -- optional intra-line word diff
          gs.toggle_numhl()          -- number column highlight
          if gs.toggle_virt_lines then gs.toggle_virt_lines() end
        end,
        desc = "Toggle Diff Overlay",
      },
      {
        "<leader>gDh",
        function()
          if pcall(require, "snacks") then
            require("snacks").picker.git_diff()
          else
            vim.notify("Snacks.nvim not available", vim.log.levels.WARN)
          end
        end,
        desc = "Git Diff (hunks picker)",
      },
    },
    -- Use config for complete control (bypasses lazy.nvim opts merging)
    config = function()
      local gs = require("gitsigns")
      gs.setup({
        signs = {
          add          = { text = '│' },
          change       = { text = '│' },
          delete       = { text = '_' },
          topdelete    = { text = '‾' },
          changedelete = { text = '~' },
          untracked    = { text = '┆' },
        },
        signcolumn = true,
        numhl = false,
        linehl = false,
        word_diff = false,
        current_line_blame = false,
        current_line_blame_opts = {
          virt_text = true,
          virt_text_pos = "eol",
          delay = 1000,
        },
        attach_to_untracked = true,
        watch_gitdir = {
          interval = 1000,
          follow_files = true,
        },
        _threaded_diff = true,
        preview_config = {
          border = 'single',
          style = 'minimal',
          relative = 'cursor',
          row = 0,
          col = 1,
        },
        on_attach = function(bufnr)
          local gitsigns = require("gitsigns")

          -- Stage/reset/unstage hunks
          vim.keymap.set({ "n", "v" }, "<leader>hs", gitsigns.stage_hunk, { buffer = bufnr, desc = "Stage/Unstage Hunk" })
          vim.keymap.set({ "n", "v" }, "<leader>hr", gitsigns.reset_hunk, { buffer = bufnr, desc = "Reset Hunk" })
          vim.keymap.set({ "n", "v" }, "<leader>hu", gitsigns.undo_stage_hunk, { buffer = bufnr, desc = "Undo Stage Hunk" })
          vim.keymap.set("n", "<leader>hS", gitsigns.stage_buffer, { buffer = bufnr, desc = "Stage Buffer" })
          vim.keymap.set("n", "<leader>hR", gitsigns.reset_buffer, { buffer = bufnr, desc = "Reset Buffer" })
          vim.keymap.set("n", "<leader>hU", gitsigns.reset_buffer_index, { buffer = bufnr, desc = "Unstage Buffer" })

          -- Preview hunk (per-hunk inline preview)
          vim.keymap.set("n", "<leader>hp", function()
            gitsigns.preview_hunk_inline()
          end, { buffer = bufnr, desc = "Preview Hunk Inline" })

          -- Show all hunks inline
          vim.keymap.set("n", "<leader>hd", function()
            local current_deleted = vim.b.gitsigns_status_dict and vim.b.gitsigns_status_dict.show_deleted
            local current_word_diff = vim.b.gitsigns_status_dict and vim.b.gitsigns_status_dict.word_diff

            if current_deleted or current_word_diff then
              if current_deleted then gitsigns.toggle_deleted() end
              if current_word_diff then gitsigns.toggle_word_diff() end
              gitsigns.toggle_linehl()
            else
              if not current_deleted then gitsigns.toggle_deleted() end
              if not current_word_diff then gitsigns.toggle_word_diff() end
              gitsigns.toggle_linehl()
            end
          end, { buffer = bufnr, desc = "Toggle Full File Diff View" })

          -- Blame
          vim.keymap.set("n", "<leader>hb", function()
            gitsigns.blame_line({ full = true })
          end, { buffer = bufnr, desc = "Blame Line" })
          vim.keymap.set("n", "<leader>tb", gitsigns.toggle_current_line_blame, { buffer = bufnr, desc = "Toggle Line Blame" })

          -- Text object for hunks
          vim.keymap.set({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { buffer = bufnr, desc = "Select Hunk" })
        end,
      })
    end,
  },

  -- vgit: unified inline diff view (better git diff visualization)
  {
    "tanvirtin/vgit.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "LazyFile",
    keys = {
      -- Hunk navigation
      { "<leader>V]", function() require("vgit").hunk_down() end, desc = "Next Hunk (VGit)" },
      { "<leader>V[", function() require("vgit").hunk_up() end, desc = "Prev Hunk (VGit)" },

      -- Diff/blame/history previews
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

  -- Unified hunk navigation: tries both gitsigns and vgit
  {
    "lewis6991/gitsigns.nvim", -- depends on gitsigns being loaded
    config = function()
      local function next_hunk()
        -- try gitsigns
        pcall(function()
          require("gitsigns").nav_hunk("next")
        end)

        -- try vgit
        pcall(function()
          require("vgit").hunk_down()
        end)
      end

      local function prev_hunk()
        pcall(function()
          require("gitsigns").nav_hunk("prev")
        end)

        pcall(function()
          require("vgit").hunk_up()
        end)
      end

      vim.keymap.set("n", "]h", next_hunk, { desc = "Next hunk (gitsigns/VGit)" })
      vim.keymap.set("n", "[h", prev_hunk, { desc = "Prev hunk (gitsigns/VGit)" })
    end,
  },
}
