require "nvchad.autocmds"

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
    vim.opt_local.spelllang = { "en", "nl" }
    vim.opt_local.conceallevel = 2
  end,
})

-- Full-window screens have nothing to label and no sibling to be confused
-- with, so they opt out of the window bar from options.lua. An empty local
-- value disables it for just that window.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("WinBarExclude", { clear = true }),
  pattern = { "nvdash", "nvcheatsheet" },
  callback = function()
    vim.opt_local.winbar = ""
  end,
})
