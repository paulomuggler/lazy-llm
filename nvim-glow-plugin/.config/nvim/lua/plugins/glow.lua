-- Glow markdown preview for the LazyVim setup.
-- Requires the glow CLI (installed via install-glow.sh).
--   :Glow         glow.nvim's own full-window preview
--   <leader>mg / <leader>uM
--                 toggle a glow overlay of the current buffer over its window
--                 (see lua/glow_overlay.lua; q / <Esc> or buffer switch closes)

return {
  {
    "ellisonleao/glow.nvim",
    config = true,
    cmd = "Glow",
  },
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>mg",
        function()
          require("glow_overlay").toggle()
        end,
        desc = "Glow overlay (toggle, current buffer)",
        ft = "markdown",
      },
      {
        "<leader>uM",
        function()
          require("glow_overlay").toggle()
        end,
        desc = "Glow overlay (current window)",
        ft = "markdown",
      },
    },
  },
}
