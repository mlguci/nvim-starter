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
  },

  -- format_on_save = {
  --   -- These options will be passed to conform.format()
  --   timeout_ms = 500,
  --   lsp_fallback = true,
  -- },
}

return options
