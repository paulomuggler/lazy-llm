-- IDE-like breadcrumbs with dropbar.nvim
-- Provides context-aware breadcrumbs at the top of the window
-- Includes markdown header navigation support

return {
  {
    "Bekaboo/dropbar.nvim",
    event = "LazyFile",
    dependencies = {
      "nvim-telescope/telescope-fzf-native.nvim",
    },
    init = function()
      -- Custom highlight groups for dropbar (bold, italic, distinct colors)
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          -- Path/filename: bold with accent color + background highlight for icons
          vim.api.nvim_set_hl(0, "DropBarIconKindFile", { fg = "#89b4fa", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindFolder", { fg = "#fab387", bold = true, bg = "#313244" })

          -- Symbols: bold icons with background highlight
          vim.api.nvim_set_hl(0, "DropBarIconKindFunction", { fg = "#a6e3a1", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindMethod", { fg = "#a6e3a1", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindClass", { fg = "#f9e2af", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindModule", { fg = "#cba6f7", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindVariable", { fg = "#89dceb", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindConstant", { fg = "#fab387", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindStruct", { fg = "#f9e2af", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindInterface", { fg = "#89dceb", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindProperty", { fg = "#94e2d5", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindField", { fg = "#94e2d5", bold = true, bg = "#313244" })

          -- Symbol text: same colors as icons, bold
          vim.api.nvim_set_hl(0, "DropBarKindFile", { fg = "#89b4fa", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindFolder", { fg = "#fab387", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindFunction", { fg = "#a6e3a1", bold = true, italic = true })
          vim.api.nvim_set_hl(0, "DropBarKindMethod", { fg = "#a6e3a1", bold = true, italic = true })
          vim.api.nvim_set_hl(0, "DropBarKindClass", { fg = "#f9e2af", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindModule", { fg = "#cba6f7", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindVariable", { fg = "#89dceb", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindConstant", { fg = "#fab387", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindStruct", { fg = "#f9e2af", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindInterface", { fg = "#89dceb", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindProperty", { fg = "#94e2d5", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindField", { fg = "#94e2d5", bold = true })

          -- Separator arrows - slightly brighter
          vim.api.nvim_set_hl(0, "DropBarIconUISeparator", { fg = "#7f849c", bold = true })

          -- Markdown header ICONS: bold with background
          vim.api.nvim_set_hl(0, "DropBarIconKindMarkdownH1", { fg = "#f38ba8", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindMarkdownH2", { fg = "#fab387", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindMarkdownH3", { fg = "#f9e2af", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindMarkdownH4", { fg = "#a6e3a1", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindMarkdownH5", { fg = "#89b4fa", bold = true, bg = "#313244" })
          vim.api.nvim_set_hl(0, "DropBarIconKindMarkdownH6", { fg = "#cba6f7", bold = true, bg = "#313244" })

          -- Markdown header TEXT: same colors as icons, bold
          vim.api.nvim_set_hl(0, "DropBarKindMarkdownH1", { fg = "#f38ba8", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindMarkdownH2", { fg = "#fab387", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindMarkdownH3", { fg = "#f9e2af", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindMarkdownH4", { fg = "#a6e3a1", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindMarkdownH5", { fg = "#89b4fa", bold = true })
          vim.api.nvim_set_hl(0, "DropBarKindMarkdownH6", { fg = "#cba6f7", bold = true })
        end,
      })
      -- Apply immediately for current colorscheme
      vim.cmd("doautocmd ColorScheme")
    end,
    opts = function()
      local sources = require("dropbar.sources")

      return {
        bar = {
          -- Configure sources based on file type
          sources = function(buf, _)
            local ft = vim.bo[buf].ft

            -- Markdown files: show path and markdown heading hierarchy
            if ft == "markdown" then
              return {
                sources.path,
                sources.markdown,
              }
            end

            -- Default fallback: LSP -> Treesitter -> path
            return {
              sources.lsp,
              sources.treesitter,
              sources.path,
            }
          end,

          padding = {
            left = 1,
            right = 1,
          },
        },

        -- Enable markdown source
        sources = {
          markdown = {
            -- Markdown heading parser is enabled by default
          },
        },

        -- Custom icons (slightly larger visual presence)
        icons = {
          ui = {
            bar = {
              separator = "  ",  -- wider separator
            },
          },
        },
      }
    end,
    keys = {
      {
        "<leader>;",
        function()
          require("dropbar.api").pick()
        end,
        desc = "Pick symbols in winbar",
      },
      {
        "[;",
        function()
          require("dropbar.api").goto_context_start()
        end,
        desc = "Go to start of current context",
      },
      {
        "];",
        function()
          require("dropbar.api").select_next_context()
        end,
        desc = "Select next context",
      },
    },
  },
}
