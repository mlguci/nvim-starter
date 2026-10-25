require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

-- Rebind a few NvChad defaults so every which-key group has a single purpose.
-- Group labels live in the which-key `spec` in lua/plugins/init.lua.
local function unmap(mode, lhs)
  pcall(vim.keymap.del, mode, lhs)
end

-- <leader>? -- help / keymaps (was <leader>ch, <leader>wk, <leader>wK)
unmap("n", "<leader>ch")
unmap("n", "<leader>wk")
unmap("n", "<leader>wK")

map("n", "<leader>?c", "<cmd>NvCheatsheet<CR>", { desc = "toggle nvcheatsheet" })
map("n", "<leader>?K", "<cmd>WhichKey<CR>", { desc = "whichkey all keymaps" })

map("n", "<leader>?k", function()
  vim.cmd("WhichKey " .. vim.fn.input "WhichKey: ")
end, { desc = "whichkey query lookup" })

-- <leader>b -- buffers (were the bare <leader>b and <leader>x)
unmap("n", "<leader>b")
unmap("n", "<leader>x")

-- `:enew` reuses the current buffer when it is empty, unnamed and unmodified,
-- so it cannot open a second scratch buffer -- create one explicitly instead.
map("n", "<leader>bn", function()
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
end, { desc = "buffer new" })

map("n", "<leader>bd", function()
  require("nvchad.tabufline").close_buffer()
end, { desc = "buffer close" })

map("n", "<leader>bD", function()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].modified = false
  require("nvchad.tabufline").close_buffer(buf)
end, { desc = "buffer close (discard changes)" })

-- <leader>c -- code (was <leader>fm, which sat under the find group)
unmap({ "n", "x" }, "<leader>fm")

map({ "n", "x" }, "<leader>cf", function()
  require("conform").format { lsp_fallback = true }
end, { desc = "general format file" })

map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "LSP code action" })

-- <leader>f -- find (marks moved off <leader>m, now the markdown group)
unmap("n", "<leader>ma")
map("n", "<leader>fm", "<cmd>Telescope marks<CR>", { desc = "telescope find marks" })

-- <leader>g -- git. The group belongs to neogit (mapped in lua/plugins/init.lua),
-- which covers both of the telescope pickers that used to live here and does not
-- stop at browsing, so neither gets a replacement: <leader>cm was git commits
-- under the cheatsheet group, <leader>gt was git status.
--
-- The first unmap has since become load-bearing for a second reason: <leader>cm
-- is now the CMake prefix (lua/plugins/cmake.lua). A mapping sitting on a prefix
-- shadows the whole group behind it, so this line is what lets <leader>cmb reach
-- cmake-tools at all -- do not drop it as merely historical.
unmap("n", "<leader>cm")
unmap("n", "<leader>gt")

-- <leader>t -- terminals (were the bare <leader>h, <leader>v and <leader>pt;
-- <leader>th was the theme picker, which moves to the UI toggles group below)
unmap("n", "<leader>h")
unmap("n", "<leader>v")
unmap("n", "<leader>pt")
unmap("n", "<leader>th")

map("n", "<leader>th", function()
  require("nvchad.term").new { pos = "sp" }
end, { desc = "terminal new horizontal term" })

map("n", "<leader>tv", function()
  require("nvchad.term").new { pos = "vsp" }
end, { desc = "terminal new vertical term" })

map("n", "<leader>tp", "<cmd>Telescope terms<CR>", { desc = "terminal pick hidden term" })

-- Window navigation straight out of terminal mode, so leaving a terminal (the
-- Claude sidebar in particular) no longer needs a <C-x> detour first. These
-- shadow the same chords inside the running program: in Claude that costs
-- <C-l> (redraw, which `/clear` and a toggle both cover) and <C-j> (insert a
-- newline, which <S-CR> still does).
map("t", "<C-h>", "<cmd>wincmd h<CR>", { desc = "terminal switch window left" })
map("t", "<C-l>", "<cmd>wincmd l<CR>", { desc = "terminal switch window right" })
map("t", "<C-j>", "<cmd>wincmd j<CR>", { desc = "terminal switch window down" })
map("t", "<C-k>", "<cmd>wincmd k<CR>", { desc = "terminal switch window up" })

-- <leader>u -- UI toggles (were the bare <leader>n and <leader>rn, plus the
-- theme picker that used to own the <leader>t prefix)
unmap("n", "<leader>n")
unmap("n", "<leader>rn")

map("n", "<leader>un", "<cmd>set nu!<CR>", { desc = "toggle line number" })
map("n", "<leader>ur", "<cmd>set rnu!<CR>", { desc = "toggle relative number" })

map("n", "<leader>ut", function()
  require("nvchad.themes").open()
end, { desc = "toggle theme picker" })

-- Buffer-local state, so this toggles hints for the file being read rather than
-- globally: clangd's inlay hints (parameter names, deduced types) are worth
-- having on demand and in the way the rest of the time. Harmless in a buffer
-- whose server has none -- `is_enabled` just reports false forever.
map("n", "<leader>uh", function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = 0 }, { bufnr = 0 })
end, { desc = "toggle inlay hints" })

map({ "n", "t" }, "<A-m>", function()
  if vim.t.restore_cmd then
    vim.cmd(vim.t.restore_cmd)
    vim.t.restore_cmd = nil
  else
    vim.t.restore_cmd = vim.fn.winrestcmd()
    vim.cmd "wincmd _ | wincmd |"
  end
end, { desc = "window toggle maximize" })

-- <leader>C -- chezmoi. The picker and :ChezmoiEdit halves of the group are
-- keys on the chezmoi.nvim spec in lua/plugins/init.lua; these two only shell
-- out to the chezmoi binary, so they stay here instead of lazy-loading a plugin
-- neither of them uses.
map("n", "<leader>Ca", function()
  require("dotfiles").apply()
end, { desc = "chezmoi apply all" })

-- A terminal rather than a scratch buffer: chezmoi colours its own diff, and
-- nvchad.term keeps the shell alive once the command exits so the output stays
-- readable.
map("n", "<leader>Cd", function()
  require("nvchad.term").new { pos = "sp", cmd = "chezmoi diff" }
end, { desc = "chezmoi diff" })

-- easy ways to quit our nvim relationship
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "quit all" })
map("n", "<leader>qQ", "<cmd>qa!<cr>", { desc = "quit all (discard changes)" })

-- A plain `:qa!` is cancelled when a QuitPre/ExitPre autocmd closes the window
-- the quit was issued from -- Neovim refuses rather than quit out of a window
-- that no longer exists ("Exiting may still be cancelled", :help ExitPre).
-- Snacks installs exactly such a handler for its terminals, so <C-q> inside the
-- Claude sidebar closed the sidebar and left us sitting in the editor. Asking
-- twice is the whole fix: the second attempt starts from the window that
-- replaced it, where nothing is left to cancel.
local function quit_all()
  vim.cmd "qa!"
  vim.cmd "qa!"
end

-- <C-q> -- quit all, from anywhere, unconditionally. Nothing global claims
-- <C-q>: Neovim's own use is as a <C-V> synonym for terminals that eat <C-V>,
-- which ours do not. Every mode is listed so no corner needs an <Esc> or <C-x>
-- detour first -- insert, visual, select, operator-pending, the command line
-- and terminal mode, so the tree, an editor split and the Claude sidebar all
-- behave the same. In terminal mode this shadows <C-q> inside the running
-- program, which nothing here uses. The one window that could still shadow it
-- is a picker prompt, which binds <C-q> buffer-locally -- Telescope's copy is
-- switched off in lua/plugins/init.lua.
map({ "n", "i", "x", "s", "o", "c", "t" }, "<C-q>", quit_all, { desc = "quit all (unconditional)" })
