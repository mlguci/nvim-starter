require("nvchad.configs.lspconfig").defaults()

-- Homebrew LLVM's clangd (23.x) in preference to the Apple one that wins on
-- $PATH (21.x), with a fallback so this file still works on a machine chezmoi
-- has not given Homebrew LLVM. Overriding `cmd` replaces nvim-lspconfig's
-- bundled `{ "clangd" }` outright, which is the intent; its on_attach -- and so
-- the :LspClangdSwitchSourceHeader command that lua/autocmds.lua binds `gs` to
-- -- survives untouched, because we do not pass one of our own.
--
-- This has to come *before* vim.lsp.enable below, not after. NvChad loads
-- nvim-lspconfig on "User FilePost", which fires once the first file buffer
-- already exists, and vim.lsp.enable attaches to matching open buffers there and
-- then -- so a config registered afterwards would miss the very first C++ file
-- of the session and start the wrong binary for it.
--
-- The flags are the ones that change behaviour rather than taste:
-- --background-index makes cross-file references work without opening the files,
-- --clang-tidy turns on the lint checks clangd can run in-process, and
-- --header-insertion=iwyu adds the #include a completion needs instead of
-- leaving it to be noticed at compile time.
local brew_clangd = "/opt/homebrew/opt/llvm/bin/clangd"

vim.lsp.config("clangd", {
  cmd = {
    vim.uv.fs_stat(brew_clangd) and brew_clangd or "clangd",
    "--background-index",
    "--clang-tidy",
    "--header-insertion=iwyu",
    "--completion-style=detailed",
    "--function-arg-placeholders",
    "--all-scopes-completion",
    "--pch-storage=memory",
  },
})

-- neocmake is neocmakelsp: completion, hover and go-to-definition inside
-- CMakeLists.txt, which is most of what makes the <leader>cm workflow in
-- lua/plugins/cmake.lua bearable to set up. It needs no configuration of its own
-- -- it only offers completions to a client that advertises `snippetSupport`,
-- and NvChad's defaults() above already sets that for every server through
-- vim.lsp.config("*", { capabilities = ... }).
local servers = { "html", "cssls", "marksman", "clangd", "neocmake" }
vim.lsp.enable(servers)

-- read :h vim.lsp.config for changing options of lsp servers
