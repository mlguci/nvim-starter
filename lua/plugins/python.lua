-- Python: the debugger, the test runner, the REPL and notebooks. The language
-- servers (basedpyright and ruff) are in lua/configs/lspconfig.lua and the
-- formatter passes in lua/configs/conform.lua; every piece here that needs an
-- interpreter asks lua/python.lua for it, so all of them agree with the type
-- checker on which venv a buffer belongs to.
--
-- Plain `opts` tables wherever a spec has any, for the reason given on the
-- neogit spec in lua/plugins/init.lua: none of these are specs NvChad defines.

return {
  -- Debugging. nvim-dap-python registers the `python` adapter and a set of
  -- launch configurations (current file, with arguments, attach, ...) in
  -- dap.configurations.python, so <leader>dc / <F5> in lua/plugins/dap.lua work
  -- in a Python buffer without anything of ours on top -- and the dap-ui and
  -- signs from lua/configs/dap.lua come with them.
  {
    "mfussenegger/nvim-dap-python",
    dependencies = { "mfussenegger/nvim-dap" },
    ft = "python",
    config = function()
      local dap_python = require "dap-python"

      -- Mason's debugpy (lua/configs/mason.lua) is the adapter, in a venv of its
      -- own -- so no project has to list debugpy as a dependency. The program
      -- itself runs on resolve_python's answer, which is lua/python.lua's, and
      -- debugpy injects itself into that interpreter at launch.
      dap_python.setup "debugpy-adapter"
      dap_python.resolve_python = function()
        return require("python").python()
      end
      dap_python.test_runner = "pytest"
    end,
  },

  -- Tests. neotest parses the file with treesitter, so the summary tree shows
  -- every test function and every parametrized case before anything has run,
  -- then marks each with its result in the sign column. `Td` runs the nearest
  -- test under debugpy, which is the fastest way from a red test to the line
  -- that made it red. <leader>T rather than <leader>t, which is the terminal
  -- group.
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/neotest-python",
    },
    config = function()
      require("neotest").setup {
        adapters = {
          require "neotest-python" {
            runner = "pytest",
            -- neotest hands over the adapter root, not a buffer, and calls this
            -- from a coroutine -- hence the fast-safe python_at.
            python = function(root)
              return require("python").python_at(root)
            end,
            -- Step into library code too: the failing call is often in it.
            dap = { justMyCode = false },
          },
        },
        -- Geometric shapes rather than neotest's nerd-font defaults, matching
        -- the dap signs in lua/configs/dap.lua: these sit in the sign column
        -- next to them and have to render in any terminal.
        icons = {
          passed = "✓",
          failed = "✗",
          running = "◐",
          skipped = "○",
          unknown = "?",
          watching = "◎",
        },
        -- Failures as diagnostics too, so `]d` walks them and the message
        -- shows inline on the failing assert.
        diagnostic = { enabled = true, severity = vim.diagnostic.severity.ERROR },
        output = { open_on_run = false },
        quickfix = { open = false },
      }
    end,
    keys = {
      {
        "<leader>Tn",
        function()
          require("neotest").run.run()
        end,
        desc = "test run nearest",
      },
      {
        "<leader>Tf",
        function()
          require("neotest").run.run(vim.fn.expand "%:p")
        end,
        desc = "test run file",
      },
      {
        "<leader>Ta",
        function()
          require("neotest").run.run(require("project").root())
        end,
        desc = "test run suite",
      },
      {
        "<leader>Td",
        function()
          require("neotest").run.run { strategy = "dap" }
        end,
        desc = "test debug nearest",
      },
      {
        "<leader>Tl",
        function()
          require("neotest").run.run_last()
        end,
        desc = "test run last",
      },
      {
        "<leader>Ts",
        function()
          require("neotest").summary.toggle()
        end,
        desc = "test toggle summary",
      },
      {
        "<leader>To",
        function()
          require("neotest").output.open { enter = true, auto_close = true }
        end,
        desc = "test show output",
      },
      {
        "<leader>TO",
        function()
          require("neotest").output_panel.toggle()
        end,
        desc = "test toggle output panel",
      },
      {
        "<leader>Tw",
        function()
          require("neotest").watch.toggle(vim.fn.expand "%:p")
        end,
        desc = "test toggle watch file",
      },
      {
        "<leader>Tx",
        function()
          require("neotest").run.stop()
        end,
        desc = "test stop",
      },
    },
  },

  -- The REPL: IPython in a bottom split, fed lines, selections, `# %%` cells or
  -- the whole file. For exploring with plain .py files; notebooks proper are
  -- molten's, below.
  {
    "Vigemus/iron.nvim",
    ft = "python",
    main = "iron.core",
    config = function()
      local view = require "iron.view"
      local common = require "iron.fts.common"

      require("iron.core").setup {
        config = {
          repl_definition = {
            python = {
              -- The project venv's IPython when it has one, which is what makes
              -- the project's own package importable in the REPL. Asked per
              -- REPL, so one opened from another project gets that project's.
              -- `--no-autoindent` because iron sends already-indented code.
              command = function(meta)
                local python = require("python").python(meta.current_bufnr)
                local ipython = vim.fs.joinpath(vim.fs.dirname(python), "ipython")
                if vim.uv.fs_stat(ipython) then
                  return { ipython, "--no-autoindent" }
                end
                return { python }
              end,
              format = common.bracketed_paste_python,
              block_dividers = { "# %%", "#%%" },
            },
          },
          repl_open_cmd = view.split.botright "35%",
        },
        -- Every map is ours (below), so iron binds nothing on its own.
        keymaps = {},
        highlight = { italic = true },
        ignore_blank_lines = true,
      }
    end,
    keys = {
      { "<leader>is", "<cmd>IronRepl<cr>", desc = "repl toggle" },
      { "<leader>ir", "<cmd>IronRestart<cr>", desc = "repl restart" },
      {
        "<leader>il",
        function()
          require("iron.core").send_line()
        end,
        desc = "repl send line",
      },
      {
        "<leader>iv",
        function()
          require("iron.core").visual_send()
        end,
        mode = "x",
        desc = "repl send selection",
      },
      {
        "<leader>ic",
        function()
          require("iron.core").send_code_block(true)
        end,
        desc = "repl send cell and move",
      },
      {
        "<leader>if",
        function()
          require("iron.core").send_file()
        end,
        desc = "repl send file",
      },
      {
        "<leader>ix",
        function()
          require("iron.core").send(nil, string.char(12))
        end,
        desc = "repl clear",
      },
      {
        "<leader>iq",
        function()
          require("iron.core").close_repl()
        end,
        desc = "repl quit",
      },
    },
  },

  -- .ipynb files open as `# %%` Python. Not lazy: setup() registers the
  -- BufReadCmd that does the conversion, so it has to exist before the first
  -- notebook is opened, and a lazy `event` trigger on BufReadCmd would load the
  -- plugin only *after* Neovim had already read the raw JSON. It is one small
  -- module and an autocmd. The `jupytext` binary it calls is the host venv's,
  -- reached through the shim directory lua/python.lua explains.
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    init = function()
      local shims = require("python").host_shims
      if not vim.env.PATH:find(shims, 1, true) then
        vim.env.PATH = shims .. ":" .. vim.env.PATH
      end
    end,
    opts = {
      style = "percent",
      output_extension = "auto",
    },
  },

  -- Notebooks: cells run on a Jupyter kernel, output shown under the cell as
  -- virtual text, and in a float on demand. A remote plugin -- it needs the host
  -- venv (:PythonHostInstall), `rplugin` left enabled (lua/configs/lazy.lua) and
  -- a `:Lazy build molten-nvim` once the host exists, which runs
  -- :UpdateRemotePlugins with molten on the runtimepath.
  {
    "benlubas/molten-nvim",
    version = "^1.0.0",
    build = ":UpdateRemotePlugins",
    ft = "python",
    init = function()
      vim.g.molten_auto_open_output = false
      vim.g.molten_virt_text_output = true
      vim.g.molten_wrap_output = true
      vim.g.molten_output_win_max_height = 20
      -- The output goes below the last line of the cell, not on it, which is
      -- where it belongs when cells are delimited by `# %%` lines.
      vim.g.molten_virt_lines_off_by_1 = true
    end,
    config = function()
      -- Plots inline when the terminal speaks a graphics protocol (kitty,
      -- ghostty, wezterm), through snacks.nvim, which is already installed;
      -- otherwise molten says "image" in the text output. Decided here, at
      -- load, because molten reads it at :MoltenInit.
      local ok, snacks = pcall(require, "snacks")
      vim.g.molten_image_provider = (ok and snacks.image.supports_terminal()) and "snacks.nvim" or "none"
    end,
    keys = {
      {
        "<leader>ji",
        function()
          require("python").molten_init()
        end,
        desc = "jupyter init kernel for this venv",
      },
      {
        "<leader>jr",
        function()
          local first, last = require("python").cell_range()
          vim.fn.MoltenEvaluateRange(first, last)
        end,
        desc = "jupyter run cell",
      },
      { "<leader>jl", "<cmd>MoltenEvaluateLine<cr>", desc = "jupyter run line" },
      { "<leader>jv", ":<C-u>MoltenEvaluateVisual<cr>gv<esc>", mode = "x", desc = "jupyter run selection" },
      { "<leader>jc", "<cmd>MoltenReevaluateCell<cr>", desc = "jupyter re-run cell" },
      { "<leader>jo", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "jupyter enter output" },
      { "<leader>jh", "<cmd>MoltenHideOutput<cr>", desc = "jupyter hide output" },
      { "<leader>jd", "<cmd>MoltenDelete<cr>", desc = "jupyter delete cell output" },
      { "<leader>jI", "<cmd>MoltenInterrupt<cr>", desc = "jupyter interrupt kernel" },
      { "<leader>jR", "<cmd>MoltenRestart!<cr>", desc = "jupyter restart kernel" },
    },
  },
}
