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
