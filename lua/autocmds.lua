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

-- chezmoi mangles source file names -- dot_zshrc, private_dot_config/, a .tmpl
-- suffix -- which defeats filetype detection: dot_zshrc comes out as "conf"
-- and dot_zshenv as nothing at all, so a source opens with no highlighting, no
-- LSP and no formatter. Detect against the target path each source maps to
-- instead. This lives here rather than on the chezmoi.nvim spec because that
-- spec is lazy-loaded, and opening a source from telescope or neogit has to
-- work whether or not the plugin ever loads.
local dotfiles = require "dotfiles"

vim.filetype.add {
  pattern = {
    -- Escaped: the source path's own dots would otherwise match any character.
    [vim.pesc(dotfiles.source) .. "/.*"] = function(path)
      if not dotfiles.managed_source(path) then
        return nil
      end
      -- nil falls through to Neovim's own detection, so a name this does not
      -- recognise behaves exactly as it did before.
      return vim.filetype.match { filename = dotfiles.target(path) }
    end,
  },
}

-- Saving a source pushes it straight to $HOME. Editing the live file and
-- forgetting to `chezmoi add` is what lets the two drift apart -- a drift that
-- silently loses whichever side chezmoi did not know about -- so the source is
-- the only copy worth editing and saving keeps it authoritative.
vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("ChezmoiApply", { clear = true }),
  -- A pattern holding a slash is matched against the full path, and `*` spans
  -- path separators, so this covers nested sources too.
  pattern = dotfiles.source .. "/*",
  callback = function(ev)
    if dotfiles.managed_source(ev.file) then
      dotfiles.apply(ev.file)
    end
  end,
})

-- A C or C++ file and its header are the one pair of files always edited
-- together, and clangd is the only thing that can say which header goes with
-- which source -- it answers off the compilation database, not off a name guess.
-- Buffer-local and clangd-only, the same "LSP buffers only" scoping the
-- which-key comments note for <leader>r and <leader>w: it shadows the builtin
-- `gs` (sleep N seconds) in exactly those buffers, which is no loss.
-- :LspClangdSwitchSourceHeader is created by nvim-lspconfig's own clangd
-- on_attach, which lua/configs/lspconfig.lua is careful not to replace.
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("ClangdSwitchSourceHeader", { clear = true }),
  desc = "Bind gs to clangd's source/header switch",
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client or client.name ~= "clangd" then
      return
    end

    vim.keymap.set("n", "gs", "<cmd>LspClangdSwitchSourceHeader<cr>", {
      buffer = ev.buf,
      desc = "LSP switch source/header",
    })
  end,
})
