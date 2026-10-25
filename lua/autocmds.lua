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

-- Terminal windows remember the mode they were left in. Leaving a terminal
-- window always drops it out of terminal mode -- window navigation only
-- happens from normal mode -- so coming back lands in nterminal mode even when
-- the last thing done there was typing. Recording the mode on the way out and
-- replaying it on the way in makes a terminal pick up where it was left.
local term_mode = vim.api.nvim_create_augroup("TermModeMemory", { clear = true })

vim.api.nvim_create_autocmd("WinLeave", {
  group = term_mode,
  callback = function(ev)
    if vim.bo[ev.buf].buftype == "terminal" then
      -- Still "t" here: WinLeave runs before the mode actually changes, and
      -- TermLeave is no use because it fires once the *new* window is current.
      vim.b[ev.buf].term_insert = vim.fn.mode() == "t"
    end
  end,
})

-- TermOpen is in the list because a terminal is not always a terminal yet when
-- its window is entered: Snacks (the Claude sidebar) shows the window first and
-- turns the buffer into a terminal after, so the enter events see buftype "".
vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "TermOpen" }, {
  group = term_mode,
  callback = function(ev)
    -- Terminals shown in a window we are not in -- a Telescope preview, say --
    -- fire these too, and must not pull the cursor along with them.
    if vim.bo[ev.buf].buftype ~= "terminal" or ev.buf ~= vim.api.nvim_get_current_buf() then
      return
    end

    -- A terminal nobody has left yet (just opened, or unhidden) defaults to
    -- terminal mode, which is where every way of opening one already starts.
    if vim.b[ev.buf].term_insert ~= false then
      vim.cmd.startinsert()
    elseif vim.fn.mode() == "t" then
      -- Stepping straight from one terminal into another keeps terminal mode:
      -- Neovim only drops out of it when the buffer being entered is not a
      -- terminal. A terminal left in normal mode has to be put back by hand.
      vim.cmd.stopinsert()
    end
  end,
})
