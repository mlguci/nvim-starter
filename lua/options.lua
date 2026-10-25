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
