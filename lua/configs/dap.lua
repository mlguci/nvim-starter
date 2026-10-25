-- Debugger wiring. The specs and every keymap are in lua/plugins/dap.lua; this
-- file is the part that has to run once nvim-dap is actually loaded.
local dap = require "dap"
local dapui = require "dapui"

-- codelldb does not speak DAP on stdio: it opens a socket and expects to be told
-- which port to use, which is what the ${port} placeholders are -- nvim-dap picks
-- a free port, substitutes it into both, and connects. Installed with
-- `:MasonInstall codelldb`; mason's bin directory is first on $PATH, so the bare
-- name resolves (NvChad sets mason's own PATH handling to "skip", so nothing else
-- would).
dap.adapters.codelldb = {
  type = "server",
  port = "${port}",
  executable = {
    command = "codelldb",
    args = { "--port", "${port}" },
  },
}

-- A standalone configuration, so <leader>dc does something useful in a C or C++
-- buffer with no CMake project behind it. Inside one, :CMakeDebug never consults
-- this list -- it passes nvim-dap the cmake_dap_configuration from
-- lua/configs/cmake.lua with the selected launch target already filled in.
dap.configurations.cpp = {
  {
    name = "Launch (prompt for binary)",
    type = "codelldb",
    request = "launch",
    program = function()
      return vim.fn.input("Path to executable: ", vim.uv.cwd() .. "/", "file")
    end,
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
    runInTerminal = true,
    console = "integratedTerminal",
  },
}

dap.configurations.c = dap.configurations.cpp

-- Open the debug UI when a session starts and close it when one ends, so
-- <leader>du is only needed to get a closed UI back during a live session.
-- `before` rather than `after` on the openers: the UI should exist before the
-- first stop event arrives, or its windows miss the frame that caused it.
dap.listeners.before.launch.dapui = dapui.open
dap.listeners.before.attach.dapui = dapui.open
dap.listeners.before.event_terminated.dapui = dapui.close
dap.listeners.before.event_exited.dapui = dapui.close

-- Signs borrow the diagnostic highlight groups rather than defining Dap* colours
-- of their own: base46 themes the diagnostic groups for every colorscheme, so
-- these follow a theme change (<leader>ut) for free. Geometric shapes rather
-- than nerd-font glyphs, matching the git markers on the nvim-tree spec in
-- lua/plugins/init.lua -- these have to render in the sign column of any
-- terminal, and a filled circle reads as "stop here" without a font to help.
--
-- `text` is load-bearing and must be one or two cells wide: a sign with an empty
-- or oversized text cannot be placed, vim.fn.sign_place then returns -1, and
-- nvim-dap *discards the breakpoint* when it does -- silently, so the only
-- symptom is breakpoints that never bind.
local signs = {
  DapBreakpoint = { text = "●", texthl = "DiagnosticError" },
  DapBreakpointCondition = { text = "◆", texthl = "DiagnosticWarn" },
  DapBreakpointRejected = { text = "○", texthl = "DiagnosticInfo" },
  DapLogPoint = { text = "◌", texthl = "DiagnosticInfo" },
  DapStopped = { text = "▶", texthl = "DiagnosticOk", linehl = "CursorLine" },
}

for name, opts in pairs(signs) do
  vim.fn.sign_define(name, opts)
end
