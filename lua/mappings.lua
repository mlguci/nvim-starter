require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- Macro recording is never used here and a stray `q` dropping into "recording
-- @x" is only confusing, so the global key does nothing. Buffer-local `q` maps
-- (close in help, nvim-tree, neogit, lazy, ...) win over a global one and keep
-- working. Only normal mode: `q` in visual mode is not a command anyway.
map("n", "q", "<Nop>", { desc = "disabled (macro recording)" })

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

-- Modified buffers still get the usual save prompt (tabufline uses `confirm bd`).
map("n", "<leader>ba", function()
  require("nvchad.tabufline").closeAllBufs()
end, { desc = "buffer close all" })

-- <leader>c -- code / LSP (format was <leader>fm, which sat under the find
-- group; the diagnostic loclist was <leader>ds, which made <leader>d a
-- two-purpose group). The buffer-local LSP maps of the group -- cr, ct, cw* --
-- are set in the on_attach in lua/configs/lspconfig.lua.
unmap({ "n", "x" }, "<leader>fm")
unmap("n", "<leader>ds")

map("n", "<leader>cd", vim.diagnostic.setloclist, { desc = "LSP diagnostic loclist" })

map({ "n", "x" }, "<leader>cf", function()
  require("conform").format { lsp_format = "fallback" }
end, { desc = "general format file" })

-- Format on save (lua/configs/conform.lua) checks these two flags. The global
-- one is what <leader>cF flips; the bang form of the commands is per buffer.
vim.api.nvim_create_user_command("FormatDisable", function(args)
  if args.bang then
    vim.b.disable_autoformat = true
  else
    vim.g.disable_autoformat = true
  end
end, { bang = true, desc = "Stop formatting on save (! for this buffer only)" })

vim.api.nvim_create_user_command("FormatEnable", function()
  vim.b.disable_autoformat = false
  vim.g.disable_autoformat = false
end, { desc = "Format on save again" })

map("n", "<leader>cF", function()
  vim.g.disable_autoformat = not vim.g.disable_autoformat
  vim.notify("Format on save " .. (vim.g.disable_autoformat and "off" or "on"))
end, { desc = "general toggle format on save" })

map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "LSP code action" })

-- Compiler Explorer view of the buffer, compiled locally with the project's own
-- flags (lua/asm.lua). The command exists before the module is loaded, so the
-- first :Asm costs nothing at startup.
local function asm_toggle()
  require("asm").toggle()
end
map("n", "<leader>cs", asm_toggle, { desc = "show assembly (godbolt view)" })
vim.api.nvim_create_user_command("Asm", asm_toggle, { desc = "Toggle the assembly view for this buffer" })

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
-- <leader>th was the theme picker, which moves to the UI toggles group below).
-- The <leader>h unmap is load-bearing too: <leader>h is now the DevDocs group
-- (lua/plugins/devdocs.lua), and a mapping on the prefix would shadow it.
unmap("n", "<leader>h")
unmap("n", "<leader>v")
-- <leader>pt was a terminal picker; <leader>p is now the Projects group, so this
-- unmap is also what keeps <leader>pp and friends reachable -- a mapping sitting
-- on a prefix shadows the whole group behind it, the same trap the <leader>cm
-- comment above describes.
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

-- <leader>w -- windows (NvChad's <leader>wk/wK moved to <leader>?, above).
-- Helpers in lua/windows.lua.
map({ "n", "t" }, "<A-m>", function()
  require("windows").toggle_maximize()
end, { desc = "window toggle maximize" })

map("n", "<leader>wm", function()
  require("windows").toggle_maximize()
end, { desc = "window toggle maximize" })

map("n", "<leader>w=", function()
  require("windows").equalize()
end, { desc = "window equalize sizes" })

-- Window mode: which-key keeps the <C-w> menu open after every key, so
-- `> > + + x` is one session instead of five <C-w> chords. <Esc> leaves.
map("n", "<leader>ww", function()
  require("which-key").show { keys = "<c-w>", loop = true }
end, { desc = "window mode (repeat <C-w> keys)" })

-- The <C-w> pair too, so splitting from the tree in window mode behaves the same.
for _, lhs in ipairs { "<leader>wv", "<C-w>v" } do
  map("n", lhs, function()
    require("windows").split "vsplit"
  end, { desc = "window split vertical" })
end

for _, lhs in ipairs { "<leader>ws", "<C-w>s" } do
  map("n", lhs, function()
    require("windows").split "split"
  end, { desc = "window split horizontal" })
end

map("n", "<leader>wd", "<cmd>close<CR>", { desc = "window close" })
map("n", "<leader>wo", "<cmd>only<CR>", { desc = "window close others" })
map("n", "<leader>wx", "<C-w>x", { desc = "window exchange with next" })
map("n", "<leader>wH", "<C-w>H", { desc = "window move far left" })
map("n", "<leader>wJ", "<C-w>J", { desc = "window move to bottom" })
map("n", "<leader>wK", "<C-w>K", { desc = "window move to top" })
map("n", "<leader>wL", "<C-w>L", { desc = "window move far right" })

-- Resize in steps of 5 rather than 1, both as <C-w> chords (which is what
-- window mode repeats) and directly on <C-A-hjkl>, which also works from inside
-- a terminal such as the Claude sidebar. h/l narrow/widen, j/k shrink/grow.
local function resize(dim, delta)
  return function()
    local win = vim.api.nvim_get_current_win()
    if dim == "width" then
      vim.api.nvim_win_set_width(win, math.max(1, vim.api.nvim_win_get_width(win) + delta))
    else
      vim.api.nvim_win_set_height(win, math.max(1, vim.api.nvim_win_get_height(win) + delta))
    end
  end
end

map("n", "<C-w><", resize("width", -5), { desc = "window narrower" })
map("n", "<C-w>>", resize("width", 5), { desc = "window wider" })
map("n", "<C-w>-", resize("height", -5), { desc = "window shorter" })
map("n", "<C-w>+", resize("height", 5), { desc = "window taller" })
map({ "n", "t" }, "<C-A-h>", resize("width", -5), { desc = "window narrower" })
map({ "n", "t" }, "<C-A-l>", resize("width", 5), { desc = "window wider" })
map({ "n", "t" }, "<C-A-j>", resize("height", -5), { desc = "window shorter" })
map({ "n", "t" }, "<C-A-k>", resize("height", 5), { desc = "window taller" })

-- <leader>l -- tab pages, used as layouts: each keeps its own windows and, through
-- tabufline (vim.t.bufs), its own buffer list. <Tab> cycles buffers, not these.
map("n", "<leader>ln", "<cmd>tabnew<CR>", { desc = "tab new" })
map("n", "<leader>ll", "<cmd>tabnext<CR>", { desc = "tab next" })
map("n", "<leader>lh", "<cmd>tabprevious<CR>", { desc = "tab previous" })
map("n", "<leader>lo", "<cmd>tabonly<CR>", { desc = "tab close others" })
map("n", "<leader>lw", "<C-w>T", { desc = "tab from current window" })

-- :tabclose on the last tab page and :tabmove past either end are errors, and a
-- count past the last tab page is one too: nothing to do in any of those cases.
map("n", "<leader>ld", function()
  if vim.fn.tabpagenr "$" > 1 then
    vim.cmd "tabclose"
  end
end, { desc = "tab close" })

map("n", "<leader>lH", function()
  if vim.fn.tabpagenr() > 1 then
    vim.cmd "-tabmove"
  end
end, { desc = "tab move left" })

map("n", "<leader>lL", function()
  if vim.fn.tabpagenr() < vim.fn.tabpagenr "$" then
    vim.cmd "+tabmove"
  end
end, { desc = "tab move right" })

for nr = 1, 9 do
  local function go()
    if nr <= vim.fn.tabpagenr "$" then
      vim.cmd.tabnext(nr)
    end
  end

  map("n", "<leader>l" .. nr, go, { desc = "tab go to " .. nr })
  if nr <= 8 then
    map({ "n", "t" }, "<A-" .. nr .. ">", go, { desc = "tab go to " .. nr })
  end
end

-- <leader>C -- chezmoi. The picker and :ChezmoiEdit halves of the group are
-- keys on the chezmoi.nvim spec in lua/plugins/init.lua; these two only shell
-- out to the chezmoi binary, so they stay here instead of lazy-loading a plugin
-- neither of them uses.
if require("dotfiles").enabled then
  map("n", "<leader>Ca", function()
    require("dotfiles").apply()
  end, { desc = "chezmoi apply all" })

  -- A terminal rather than a scratch buffer: chezmoi colours its own diff, and
  -- nvchad.term keeps the shell alive once the command exits so the output stays
  -- readable.
  map("n", "<leader>Cd", function()
    require("nvchad.term").new { pos = "sp", cmd = "chezmoi diff" }
  end, { desc = "chezmoi diff" })
end

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

-- <leader>f -- find, re-anchored. NvChad's three search maps run telescope
-- against cwd, which is only the project as long as nvim was started from the
-- project root and never left it. Routed through project.root() they answer the
-- same question the build does: <leader>ff in a file opened by absolute path from
-- an unrelated shell searches that file's project, not the shell's directory.
--
-- `cwd` and not `search_dirs`: telescope's `cwd` is what both find_files and
-- live_grep run their external command in, so rg and fd report paths relative to
-- the root and the results stay readable. The other five maps in the group are
-- left alone -- buffers, help tags, oldfiles, marks and the current buffer are
-- all either global or already buffer-scoped, so a root would mean nothing to
-- them.
unmap("n", "<leader>ff")
unmap("n", "<leader>fa")
unmap("n", "<leader>fw")

map("n", "<leader>ff", function()
  require("telescope.builtin").find_files { cwd = require("project").root() }
end, { desc = "telescope find files" })

map("n", "<leader>fa", function()
  require("telescope.builtin").find_files {
    cwd = require("project").root(),
    follow = true,
    no_ignore = true,
    hidden = true,
  }
end, { desc = "telescope find all files" })

map("n", "<leader>fw", function()
  require("telescope.builtin").live_grep { cwd = require("project").root() }
end, { desc = "telescope live grep" })

-- <leader>p -- projects. The rest of the group is keys on the snacks and
-- persistence specs in lua/plugins/project.lua; this one stays here because it
-- drags in no plugin at all -- the same reason the two chezmoi maps above do.
--
-- Worth having beside <leader>pp: the switch is for changing projects, this is for
-- the case where nvim was simply started in the wrong directory. It moves cwd
-- without touching the layout, which is what the statusline, nvim-tree's
-- sync_root_with_cwd and cmake-tools' DirChanged handler all key off.
map("n", "<leader>pr", function()
  require("project").cd_root()
end, { desc = "project cd to root" })

-- Highest value per line in the whole group: switching projects is usually a
-- round trip -- go look at the library, come back -- and this is the trip back
-- without going through the picker to find where you were.
map("n", "<leader>pb", function()
  require("project").back()
end, { desc = "project switch back" })

-- The escape hatch. A session that names a file which has since been deleted
-- aborts partway through :source and leaves a half-built layout, and without this
-- the only fix is deleting a file out of stdpath("state") by hand. <C-d> in the
-- picker does the same for a project other than this one.
map("n", "<leader>pD", function()
  require("project").delete_session(vim.uv.cwd())
end, { desc = "project delete session" })
