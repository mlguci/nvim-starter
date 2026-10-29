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
        -- cma, cmb, cmB, cmc, cmd, cmg, cmo, cmp, cmP, cmq, cmr, cmR, cms, cmt, cmT, cmx
        { "<leader>cm", group = "CMake" },
        { "<leader>C", group = "Chezmoi" }, -- Ca, Cd, Ce, Cf
        -- db, dB, dc, de, di, dl, do, dO, dr, dt, du (nvim-dap) and ds (diagnostics).
        -- Two purposes in one group, the same compromise <leader>? and <leader>f make:
        -- a debugger wants the d, and the one diagnostic map left is not worth a
        -- prefix of its own.
        { "<leader>d", group = "Debug / diagnostics" },
        { "<leader>f", group = "Find files / search" }, -- fa, fb, ff, fh, fm, fo, fw, fz
        { "<leader>g", group = "Git" }, -- gb, gc, gd, gg, gl, gp, gP, gz
        { "<leader>m", group = "Markdown" }, -- mp, mr
        -- pb, pD, pd, pl, pp, pr, pS, ps
        { "<leader>p", group = "Projects" },
        { "<leader>q", group = "Quit" }, -- qQ, qq
        { "<leader>r", group = "Rename", mode = { "n" } }, -- ra (LSP buffers only)
        { "<leader>t", group = "Terminal" }, -- th, tp, tv
        { "<leader>u", group = "UI toggles" }, -- uh, un, ur, ut
        { "<leader>w", group = "Workspace", mode = { "n" } }, -- wa, wl, wr (LSP buffers only)
      },
    },
  },

  -- Give up <C-q> inside pickers so the global quit map in lua/mappings.lua
  -- reaches them: a prompt's buffer-local mapping always wins over a global
  -- one. `false` disables a default mapping without binding anything in its
  -- place. This fragment has to be an opts *function*: NvChad's telescope spec
  -- is one too, and it ignores incoming opts, so a table of ours would be
  -- discarded -- as a function we are handed its result and edit that.
  {
    "nvim-telescope/telescope.nvim",
    opts = function(_, opts)
      for _, mode in ipairs { "i", "n" } do
        opts.defaults.mappings[mode] = opts.defaults.mappings[mode] or {}
        opts.defaults.mappings[mode]["<C-q>"] = false
      end
      return opts
    end,
  },

  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    cmd = { "ClaudeCode", "ClaudeCodeFocus", "ClaudeCodeSend", "ClaudeCodeAdd" },
    opts = {
      terminal = {
        split_side = "right",
        split_width_percentage = 0.35, -- default is 0.30

        -- Hand mode control to the TermModeMemory autocmds in lua/autocmds.lua,
        -- which put the sidebar back in whichever mode it was left in. Snacks
        -- otherwise forces terminal mode on every BufEnter, so a sidebar left
        -- in normal mode (scrolled back through Claude's output, say) could
        -- never be returned to. Opening still lands in terminal mode: a
        -- terminal nobody has left yet has no remembered mode to restore.
        auto_insert = false,

        -- Give the sidebar the same window bar as every other window. Snacks
        -- only falls back to its own "id: term_title" bar when wo.winbar is
        -- unset, and re-applies opts.wo whenever the split is re-shown, so
        -- this survives toggling.
        snacks_win_opts = {
          wo = {
            winbar = "%!v:lua.require('winbar').render()",
          },
        },
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

  -- Magit-style git porcelain. The status buffer opens on its own tab, the same
  -- way the Claude diff does, so staging and committing never rearrange the
  -- working layout. It owns the whole <leader>g group -- the two telescope git
  -- pickers it replaces are removed in lua/mappings.lua.
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
    },
    cmd = "Neogit",
    -- A plain opts table is safe here: the "opts function" trap noted for blink,
    -- telescope and treesitter above only applies to specs NvChad already
    -- defines and whose own opts discard incoming fragments. This spec is ours
    -- alone, so lazy merges it normally.
    opts = {
      -- Stated rather than left nil: nil makes neogit pcall-probe for each
      -- integration, and both are hard dependencies above anyway.
      integrations = { telescope = true, diffview = true },
      graph_style = "unicode",
    },
    keys = {
      { "<leader>gg", "<cmd>Neogit<cr>", desc = "neogit status" },
      { "<leader>gb", "<cmd>Neogit branch<cr>", desc = "neogit branch" },
      { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "neogit commit" },
      { "<leader>gd", "<cmd>Neogit diff<cr>", desc = "neogit diff" },
      { "<leader>gl", "<cmd>Neogit log<cr>", desc = "neogit log" },
      { "<leader>gp", "<cmd>Neogit pull<cr>", desc = "neogit pull" },
      { "<leader>gP", "<cmd>Neogit push<cr>", desc = "neogit push" },
      { "<leader>gz", "<cmd>Neogit stash<cr>", desc = "neogit stash" },
    },
  },

  -- Markdown rendered in the buffer. Not lazy-loaded, on the plugin's own
  -- advice: it already defers its work to the buffers it attaches to, and
  -- loading it on `ft` would miss the attach for the first markdown buffer.
  -- `toggle` (lowercase) is per buffer; `Toggle` would flip every buffer.
  {
    "OXY2DEV/markview.nvim",
    lazy = false,
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {
      preview = { icon_provider = "devicons" },
    },
    keys = { { "<leader>mr", "<cmd>Markview toggle<cr>", desc = "markdown toggle inline render" } },
  },

  -- Markdown rendered in the browser. kitehost is a pure-Lua HTTP server bound
  -- to 127.0.0.1, so unlike markdown-preview.nvim there is no npm build step.
  -- The page itself loads markdown-it, KaTeX, Mermaid and highlight.js from
  -- jsdelivr/unpkg, so rendering needs network access. Defaults otherwise:
  -- one preview at a time on port 8421, opened in the system browser.
  {
    "selimacerbas/mdkite.nvim",
    dependencies = { "selimacerbas/kitehost.nvim" },
    cmd = "MdKite",
    opts = {},
    keys = { { "<leader>mp", "<cmd>MdKite toggle<cr>", desc = "markdown browser preview" } },
  },
  -- Edit dotfiles where chezmoi actually keeps them. The filetype recovery and
  -- the apply-on-save that make that bearable are in lua/autocmds.lua, which
  -- has to work without this plugin loaded; what the plugin adds on top is the
  -- picker over managed files and :ChezmoiEdit. The other half of the <leader>C
  -- group -- the maps that only shell out to chezmoi, and so have no reason to
  -- drag this plugin in -- is in lua/mappings.lua.
  {
    "xvzc/chezmoi.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "ChezmoiEdit", "ChezmoiList" },
    -- A plain opts table for the reason already given on the neogit spec: the
    -- "opts function" trap only applies to specs NvChad defines as well.
    opts = {
      -- The plugin's own watch applies on save too, but only for buffers it
      -- opened itself. lua/autocmds.lua covers every route into a source file,
      -- so leaving this off is what keeps a save from applying twice.
      edit = { watch = false },
    },
    keys = {
      -- Called through the Lua API rather than as a :Telescope extension:
      -- NvChad v2.5's `extensions_list` is vestigial -- nothing consumes it and
      -- the telescope spec has no config function -- so there is no
      -- load_extension hook to register against.
      {
        "<leader>Cf",
        function()
          require("chezmoi.pick").telescope()
        end,
        desc = "chezmoi find managed file",
      },
      { "<leader>Ce", "<cmd>ChezmoiEdit<cr>", desc = "chezmoi edit source" },
    },
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
        -- chezmoi sources. `syntax` is rtp-disabled in configs/lazy.lua, so
        -- treesitter is the only highlighter: without these the filetypes
        -- recovered in lua/autocmds.lua are correct but render unhighlighted.
        -- `zsh` and not `bash`: this branch of nvim-treesitter ships a separate
        -- zsh parser, so the zsh filetype does not fall back to bash.
        "zsh",
        "git_config",
        -- C/C++ development. `cmake` highlights the listfiles neocmakelsp serves
        -- (lua/configs/lspconfig.lua); `c` and `cpp` are what clangd's buffers
        -- are rendered with, and with `syntax` rtp-disabled there is no fallback
        -- highlighter if they are missing.
        "c",
        "cpp",
        "cmake",
      },
    },
  },

  {
    "nvim-tree/nvim-tree.lua",
    opts = {
      renderer = {
        highlight_git = "name", -- color the filename instead of relying only on the icon
        icons = {
          git_placement = "after",
          -- Plain Unicode shapes throughout, deliberately: nvim-tree's own
          -- defaults reach for nerd-font glyphs on `unmerged` and `deleted`, and
          -- NvChad swaps in another one for `unmerged`, none of which survive a
          -- terminal without the patched font. Every entry is restated because a
          -- key left out here inherits one of those instead -- and an entry set
          -- to "" does not fall back, it renders nothing at all, which is how
          -- `unmerged` and `untracked` silently lost their markers.
          glyphs = {
            git = {
              unstaged = "●",
              staged = "✓",
              unmerged = "◈",
              renamed = "➜",
              untracked = "★",
              deleted = "✗",
              ignored = "◌",
            },
          },
        },
      },
    },
  },
}
