return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

 -- blink
 { import = "nvchad.blink.lazyspec" },

 -- improve which key menues
 {
  "folke/which-key.nvim",
  opts = {
    preset = "modern",

    -- One purpose per group. Mappings that did not fit their prefix are
    -- rebound in lua/mappings.lua -- keep the two files in sync.
    spec = {
      { "<leader>?", group = "Help / keymaps" }, -- ?c, ?K, ?k
      { "<leader>c", group = "Code" }, -- ca, cf
      { "<leader>d", group = "Diagnostics" }, -- ds
      { "<leader>f", group = "Find files / search" }, -- fa, fb, ff, fh, fo, fw, fz
      { "<leader>g", group = "Git" }, -- gc, gt
      { "<leader>m", group = "Marks" }, -- ma
      { "<leader>p", group = "Pick terminal" }, -- pt
      { "<leader>r", group = "Rename", mode = { "n" } }, -- ra (LSP buffers only)
      { "<leader>t", group = "Theme" }, -- th
      { "<leader>u", group = "UI toggles" }, -- un, ur
      { "<leader>w", group = "Workspace", mode = { "n" } }, -- wa, wl, wr (LSP buffers only)
    },
  },
},
}

