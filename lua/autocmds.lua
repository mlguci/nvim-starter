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

    -- A terminal buffer is not always something you can type into. Overseer
    -- renders task output with nvim_open_term, which produces a terminal buffer
    -- with no process behind it -- a read-only log. Terminal mode in front of a
    -- dead channel swallows every normal-mode key and answers none of them, so
    -- these must never be put into it, and must be taken *out* of it when we
    -- arrive from a terminal that was (entering a terminal buffer from terminal
    -- mode otherwise stays in terminal mode, per the comment below). termopen()
    -- sets b:terminal_job_id and nvim_open_term does not, which is the only
    -- reliable way to tell the two apart -- buftype is "terminal" for both.
    local typeable = vim.b[ev.buf].terminal_job_id ~= nil

    -- A terminal nobody has left yet (just opened, or unhidden) defaults to
    -- terminal mode, which is where every way of opening one already starts.
    if typeable and vim.b[ev.buf].term_insert ~= false then
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

-- :MasonInstallAll, over the tool list in lua/configs/mason.lua -- the external
-- binaries lazy-lock.json cannot pin. Created eagerly and loading mason by hand
-- rather than added to the `cmd` list on NvChad's mason spec, which looks like
-- the tidier way to do it and does not work: lazy's cmd handler re-dispatches
-- through vim.cmd() once the plugin is loaded, and mason's installer is a
-- blocking async run that does nothing from inside that nested command context
-- -- the install is skipped, and lazy's "command not found" fallback is
-- vim.schedule'd, so a `nvim --headless +MasonInstallAll +qa` exits 0 having
-- done nothing at all. Calling lazy.load first keeps the whole thing on one
-- stack frame. Mirrors NvChad's own :TSInstallAll, which is eager for its own
-- reasons (nvchad/lua/nvchad/autocmds.lua).
vim.api.nvim_create_user_command("MasonInstallAll", function()
  require("lazy").load { plugins = { "mason.nvim" } }
  require("configs.mason").install_all()
end, { desc = "Install every mason package this config needs" })

-- Projects: records which project each buffer belongs to, and restores the
-- session when nvim is started inside one. Here rather than on a plugin spec
-- because neither half may wait for a plugin -- the recording has to see the
-- first file of the session, and the restore has to happen on VimEnter whether or
-- not persistence.nvim has been reached yet. lua/project.lua explains both.
require("project").setup()
