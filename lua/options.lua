require "nvchad.options"

-- add yours here!

-- Keep a visible cursor line, but a neutral one: NvChad ships
-- cursorlineopt = "number", which highlights only the line number. Orange is
-- reserved for the window bar so it means exactly one thing -- which window
-- has focus -- while this just locates the cursor.
vim.o.cursorlineopt = "both"

-- Active-window cue. 'winbar' is global-local, so one global value covers
-- every split with no autocmd, and floating windows are excluded for free:
-- "Floating windows do not use the global value of 'winbar'" (:help 'winbar').
vim.o.winbar = "%!v:lua.require('winbar').render()"

-- What a session file is allowed to carry. Three deliberate departures from the
-- Neovim default (blank,buffers,curdir,folds,help,tabpages,winsize,terminal):
--
-- `blank` is out because it restores empty windows -- the scratch split a layout
-- happened to be left with comes back as part of the layout.
--
-- `terminal` is out because every terminal in this config is owned by something
-- that cannot have one handed back to it. The overseer task list is a terminal
-- buffer with no process behind it (the whole reason for the terminal_job_id test
-- in lua/autocmds.lua), the Claude sidebar is a snacks window with its own
-- lifecycle, and the <leader>t terminals belong to nvchad.term. :mksession knows
-- none of that and would recreate shells none of them recognise.
--
-- `skiprtp` is in as insurance rather than because it does anything today: it
-- only takes effect alongside `options` or `localoptions`, neither of which is in
-- the list. Those two are the real exclusions, and both are deliberate -- `options`
-- would have a session restore every global option as it stood when the session was
-- written, clobbering whatever this file has since changed, and `localoptions`
-- would restore per-window 'winbar' and so break the focus cue in lua/winbar.lua.
-- If either is ever added, `skiprtp` is what keeps a stale 'runtimepath' from
-- being re-imposed on lazy.nvim, which owns it.
vim.o.sessionoptions = "buffers,curdir,folds,help,tabpages,winsize,skiprtp"
