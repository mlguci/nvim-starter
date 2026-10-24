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

-- <leader>c -- code (was <leader>fm, which sat under the find group)
unmap({ "n", "x" }, "<leader>fm")

map({ "n", "x" }, "<leader>cf", function()
  require("conform").format { lsp_fallback = true }
end, { desc = "general format file" })

map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "LSP code action" })

-- <leader>g -- git (was <leader>cm, which sat under the cheatsheet group)
unmap("n", "<leader>cm")
map("n", "<leader>gc", "<cmd>Telescope git_commits<CR>", { desc = "telescope git commits" })

-- <leader>u -- UI toggles (were the bare <leader>n and <leader>rn)
unmap("n", "<leader>n")
unmap("n", "<leader>rn")

map("n", "<leader>un", "<cmd>set nu!<CR>", { desc = "toggle line number" })
map("n", "<leader>ur", "<cmd>set rnu!<CR>", { desc = "toggle relative number" })
