-- Debugging. Reached either through :CMakeDebug (<leader>cmd, see
-- lua/plugins/cmake.lua) or directly through the <leader>d maps below; the
-- adapter and UI wiring are in lua/configs/dap.lua.
--
-- <leader>d is shared with NvChad's <leader>ds diagnostic loclist, hence the
-- two-purpose group label in lua/plugins/init.lua -- the same compromise
-- <leader>? and <leader>f already make.
return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      -- nvim-nio is a hard requirement of dap-ui, not an optional extra.
      { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" }, opts = {} },
      -- Values of the variables in scope, inline at their declarations. The
      -- single most useful thing a debugger UI can add to a buffer.
      { "theHamsta/nvim-dap-virtual-text", opts = {} },
    },

    -- nvim-dap has no setup() of its own, so this is a config function rather
    -- than an opts table. Dependencies are loaded before it runs, which is what
    -- lets configs/dap.lua require "dapui" at the top.
    config = function()
      require "configs.dap"
    end,

    keys = {
      {
        "<leader>db",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "debug toggle breakpoint",
      },
      {
        "<leader>dB",
        function()
          require("dap").set_breakpoint(vim.fn.input "Breakpoint condition: ")
        end,
        desc = "debug conditional breakpoint",
      },
      {
        "<leader>dc",
        function()
          require("dap").continue()
        end,
        desc = "debug continue / start",
      },
      {
        "<leader>di",
        function()
          require("dap").step_into()
        end,
        desc = "debug step into",
      },
      {
        "<leader>do",
        function()
          require("dap").step_over()
        end,
        desc = "debug step over",
      },
      {
        "<leader>dO",
        function()
          require("dap").step_out()
        end,
        desc = "debug step out",
      },
      {
        "<leader>dr",
        function()
          require("dap").repl.toggle()
        end,
        desc = "debug toggle repl",
      },
      {
        "<leader>dl",
        function()
          require("dap").run_last()
        end,
        desc = "debug run last",
      },
      {
        "<leader>dt",
        function()
          require("dap").terminate()
        end,
        desc = "debug terminate",
      },
      {
        "<leader>du",
        function()
          require("dapui").toggle()
        end,
        desc = "debug toggle ui",
      },
      {
        "<leader>de",
        function()
          require("dapui").eval(nil, { enter = true })
        end,
        mode = { "n", "v" },
        desc = "debug eval expression",
      },

      -- The function keys every debugger front end has used for twenty years.
      -- Nothing in this config claims F5-F12, so they cost nothing and mean a
      -- stepping session needs no leader at all.
      {
        "<F5>",
        function()
          require("dap").continue()
        end,
        desc = "debug continue / start",
      },
      {
        "<F10>",
        function()
          require("dap").step_over()
        end,
        desc = "debug step over",
      },
      {
        "<F11>",
        function()
          require("dap").step_into()
        end,
        desc = "debug step into",
      },
      {
        "<F12>",
        function()
          require("dap").step_out()
        end,
        desc = "debug step out",
      },
    },
  },
}
