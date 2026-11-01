local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    markdown = { "prettier", "markdownlint-cli2" },
    -- css = { "prettier" },
    -- html = { "prettier" },

    -- clang-format reads the project's .clang-format and falls back to the LLVM
    -- style when there is none, so it never imposes a house style on a project
    -- that has its own.
    c = { "clang_format" },
    cpp = { "clang_format" },

    -- gersemi rather than cmake-format: it is the maintained one, it preserves
    -- the formatting it cannot improve instead of reflowing everything, and
    -- conform's builtin already roots it at a project's .gersemirc.
    cmake = { "gersemi" },

    -- All three are the one ruff binary, run as three passes because ruff keeps
    -- them apart on purpose: `ruff_fix` applies the safe lint fixes (unused
    -- imports, pyupgrade rewrites), `ruff_organize_imports` sorts the imports
    -- (the `I` rules -- run even when a project does not select them), and
    -- `ruff_format` is the Black-compatible formatter. Each reads the project's
    -- [tool.ruff] table, so a project's line length and rule set are honoured.
    python = { "ruff_fix", "ruff_organize_imports", "ruff_format" },
  },

  formatters = {},

  -- format_on_save = {
  --   -- These options will be passed to conform.format()
  --   timeout_ms = 500,
  --   lsp_fallback = true,
  -- },
}

-- A notebook is a Python buffer whose name ends in .ipynb: jupytext.nvim
-- (lua/plugins/python.lua) shows its cells as `# %%` text but leaves the
-- buffer named after the notebook. ruff picks its parser from the
-- --stdin-filename extension, so on that name it expects notebook JSON, gets
-- Python, and fails -- <leader>cf in a notebook would error every time. Each of
-- the three ruff formatters is therefore handed a .py name for those buffers.
-- An override of a builtin's name inherits the rest of the builtin (command,
-- cwd, stdin), so only the argument list is restated -- and it is taken from
-- the builtin itself, inside the function, so that requiring it does not load
-- conform at startup and a conform update cannot leave a stale copy here.
local function py_filename(args, ctx)
  local name = (ctx.filename:gsub("%.ipynb$", ".py"))
  return vim.tbl_map(function(arg)
    return arg == "$FILENAME" and name or arg
  end, args)
end

for _, name in ipairs { "ruff_fix", "ruff_organize_imports", "ruff_format" } do
  options.formatters[name] = {
    args = function(self, ctx)
      return py_filename(require("conform.formatters." .. name).args, ctx)
    end,
  }
end

-- ruff_format also formats a selection, through range_args.
options.formatters.ruff_format.range_args = function(self, ctx)
  return py_filename(require("conform.formatters.ruff_format").range_args(self, ctx), ctx)
end

return options
