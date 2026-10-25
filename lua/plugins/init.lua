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
        { "<leader>a", group = "Claude", mode = { "n", "v" } }, -- aa, ab, ac, ad, af, as (as is visual)
        { "<leader>b", group = "Buffers" }, -- bd, bD, bn
        { "<leader>c", group = "Code", mode = { "n", "x" } }, -- ca, cf
        { "<leader>d", group = "Diagnostics" }, -- ds
        { "<leader>f", group = "Find files / search" }, -- fa, fb, ff, fh, fm, fo, fw, fz
        { "<leader>g", group = "Git" }, -- gc, gt
        { "<leader>m", group = "Markdown" }, -- mp, mr
        { "<leader>q", group = "Quit" }, -- qQ, qq
        { "<leader>r", group = "Rename", mode = { "n" } }, -- ra (LSP buffers only)
        { "<leader>t", group = "Terminal" }, -- th, tp, tv
        { "<leader>u", group = "UI toggles" }, -- un, ur, ut
        { "<leader>w", group = "Workspace", mode = { "n" } }, -- wa, wl, wr (LSP buffers only)
      },
    },
  },

  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    cmd = { "ClaudeCode", "ClaudeCodeFocus", "ClaudeCodeSend", "ClaudeCodeAdd" },
    opts = {
      terminal = {
        split_side = "right",
        split_width_percentage = 0.35, -- default is 0.30
      },
      diff_opts = {
        -- Review the diff on a scratch tab holding nothing but the two diff
        -- panes and the Claude terminal, instead of splitting it into whatever
        -- the working tab happens to contain. Closing the diff closes the tab,
        -- so the working layout comes back untouched.
        open_in_new_tab = true,
      },
    },
    -- Registered in `init` rather than `config` so the handler exists from
    -- startup; it only ever fires once the plugin itself has loaded.
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "ClaudeCodeDiffClosed",
        group = vim.api.nvim_create_augroup("ClaudeCodeDiffFocus", { clear = true }),
        desc = "Return focus to Claude after a diff is accepted or denied",
        callback = function(args)
          -- Teardown only guarantees the terminal is *visible* (ensure_visible
          -- deliberately keeps focus), so after a tabclose focus lands on
          -- whichever editor window the original tab left current.
          local reason = (args.data or {}).reason or ""
          -- Not user resolutions: another diff is about to claim the screen, or
          -- setup never got far enough to show one.
          if reason:match "^replaced" or reason:match "^setup failed" then
            return
          end
          -- After the cleanup stack unwinds, so nothing re-steals focus.
          vim.schedule(function()
            pcall(function()
              require("claudecode.terminal").open()
            end)
          end)
        end,
      })
    end,
    keys = {
      { "<A-c>", "<cmd>ClaudeCode<cr>", mode = { "n", "t" }, desc = "claude toggle" },
      { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "claude toggle" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "claude focus" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "claude add current buffer" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "claude send selection" },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "claude accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "claude deny diff" },
    },
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {
      file_types = { "markdown" },
      code = { width = "block", border = "thin" },
      checkbox = { enabled = true },
    },
    keys = { { "<leader>mr", "<cmd>RenderMarkdown toggle<cr>", desc = "markdown toggle inline render" } },
  },
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },
    cmd = { "MarkdownPreviewToggle" },
    build = "cd app && npx --yes yarn install",
    keys = { { "<leader>mp", "<cmd>MarkdownPreviewToggle<cr>", desc = "markdown browser preview" } },
  },
  -- Parsers to install. Both `:TSInstallAll` and NvChad's `build` step read the
  -- *raw* spec.opts, which is this fragment on its own: NvChad's own `opts` is a
  -- function that discards incoming fragments (the same trap as blink above), so
  -- the two lists never merge and whichever side is read wins outright. NvChad's
  -- defaults are therefore repeated here -- drop them and they stop installing.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        -- NvChad defaults
        "lua",
        "luadoc",
        "printf",
        "vim",
        "vimdoc",
        -- markdown notes
        "html",
        "markdown",
        "markdown_inline",
        "yaml",
      },
    },
  },
}
