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

-- <leader>g -- git (was <leader>cm, which sat under the cheatsheet group)
unmap("n", "<leader>cm")
map("n", "<leader>gc", "<cmd>Telescope git_commits<CR>", { desc = "telescope git commits" })

-- <leader>u -- UI toggles (were the bare <leader>n and <leader>rn)
unmap("n", "<leader>n")
unmap("n", "<leader>rn")

map("n", "<leader>un", "<cmd>set nu!<CR>", { desc = "toggle line number" })
map("n", "<leader>ur", "<cmd>set rnu!<CR>", { desc = "toggle relative number" })

map({ "n", "t" }, "<A-m>", function()
  if vim.t.restore_cmd then
    vim.cmd(vim.t.restore_cmd)
    vim.t.restore_cmd = nil
  else
    vim.t.restore_cmd = vim.fn.winrestcmd()
    vim.cmd("wincmd _ | wincmd |")
  end
end, { desc = "window toggle maximize" })

-- easy ways to quit our nvim relationship
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "quit all" })
map("n", "<leader>qQ", "<cmd>qa!<cr>", { desc = "quit all (discard changes)" })
