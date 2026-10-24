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

 -- lua_ls type info for plugin APIs, loaded on demand per require.
 -- NvChad's lspconfig defaults already cover $VIMRUNTIME, nvchad_types and
 -- lazy.nvim; lazydev adds the rest of the installed plugins as you use them.
 {
  "folke/lazydev.nvim",
  ft = "lua",
  opts = {
    library = {
      { path = "${3rd}/luv/library", words = { "vim%.uv" } },
    },
  },
 },

 -- Feed lazydev's module completions into blink. This must stay *after* the
 -- lazyspec import above: nvchad.blink.config is an opts function that ignores
 -- incoming opts, so an earlier fragment would be discarded.
 {
  "saghen/blink.cmp",
  dependencies = { "folke/lazydev.nvim" },
  opts = function(_, opts)
    table.insert(opts.sources.default, "lazydev")
    opts.sources.providers = opts.sources.providers or {}
    opts.sources.providers.lazydev = {
      name = "LazyDev",
      module = "lazydev.integrations.blink",
      score_offset = 100,
    }
    return opts
  end,
 },

 -- improve which key menues
 {
  "folke/which-key.nvim",
  lazy = false,
  opts = {
    delay = 0,
    preset = "modern",

    -- One purpose per group. Mappings that did not fit their prefix are
    -- rebound in lua/mappings.lua -- keep the two files in sync.
    spec = {
      { "<leader>?", group = "Help / keymaps" }, -- ?c, ?K, ?k
      { "<leader>b", group = "Buffers" }, -- bd, bD, bn
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

