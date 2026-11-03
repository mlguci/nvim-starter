-- NvChad's buffer-local LSP maps, regrouped under <leader>c (Code / LSP) so the
-- which-key menu has no single-key <leader>r group, no rarely-used <leader>w
-- group and no loose <leader>D. Replaced on the module table *before* defaults()
-- rather than deleted afterwards: the LspAttach autocmd defaults() registers
-- looks up M.on_attach each time it fires, so NvChad's maps are never created at
-- all and there is no ordering race with another LspAttach handler.
local nvlsp = require "nvchad.configs.lspconfig"

nvlsp.on_attach = function(_, bufnr)
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = "LSP " .. desc })
  end

  map("gD", vim.lsp.buf.declaration, "Go to declaration")
  map("gd", vim.lsp.buf.definition, "Go to definition")
  map("<leader>ct", vim.lsp.buf.type_definition, "Go to type definition")
  map("<leader>cr", require "nvchad.lsp.renamer", "rename symbol")
  map("<leader>cwa", vim.lsp.buf.add_workspace_folder, "Add workspace folder")
  map("<leader>cwr", vim.lsp.buf.remove_workspace_folder, "Remove workspace folder")
  map("<leader>cwl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, "List workspace folders")
end

nvlsp.defaults()

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
-- taplo validates and completes TOML, using SchemaStore schemas it matches by
-- filename (Cargo.toml, pyproject.toml, ...). nvim-lspconfig's lsp/taplo.lua
-- is complete on its own, so it needs no vim.lsp.config here either.
-- No html or cssls: they were in the starter's list, but vscode-langservers-extracted
-- has never been installed for them, and vim.lsp.enable on a server whose `cmd`
-- is not on PATH fails per buffer rather than at startup -- so they were two
-- silent errors waiting on the first .html file. Add the mason package to
-- lua/configs/mason.lua at the same time as putting either one back.
-- Python is split between two servers, each doing what it is best at.
-- basedpyright (the maintained pyright fork) owns types: completion, hover,
-- go-to-definition, inlay hints and type errors. ruff owns style: lint
-- diagnostics with their quick fixes, formatting (through conform, see
-- lua/configs/conform.lua) and import sorting. The overlap is handed to ruff --
-- organize-imports here, hover in the LspAttach handler in lua/autocmds.lua.
--
-- before_init is the one hook that runs per client *after* the root is known and
-- *before* the settings are sent, so it is where pythonPath is filled in from
-- lua/python.lua -- the same interpreter the debugger, the tests and the REPL
-- use. Without it basedpyright takes whichever python is first on PATH and every
-- third-party import in a uv project reads as unresolved.
--
-- typeCheckingMode is deliberately left unset: a project states it in
-- [tool.basedpyright] in its pyproject.toml, and a value here would override
-- that. diagnosticMode stays on basedpyright's own "openFilesOnly" default --
-- workspace mode would type-check every file in the venv's site-packages too.
vim.lsp.config("basedpyright", {
  before_init = function(_, config)
    local root = config.root_dir
    local buf = vim.api.nvim_get_current_buf()
    -- A buffer from this root, if the current one is not: before_init can run
    -- while a different buffer is current (a session restore, say).
    if root and not vim.startswith(vim.api.nvim_buf_get_name(buf), root) then
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.startswith(vim.api.nvim_buf_get_name(b), root .. "/") then
          buf = b
          break
        end
      end
    end
    -- Mutated in place, not replaced with vim.tbl_deep_extend as :h
    -- vim.lsp.ClientConfig suggests: the client captured this very table as
    -- client.settings when it was created, which is what it later sends and
    -- answers workspace/configuration from, so a new table would never reach
    -- the server.
    config.settings.python = config.settings.python or {}
    config.settings.python.pythonPath = require("python").python(buf)
  end,
  settings = {
    basedpyright = {
      disableOrganizeImports = true,
    },
  },
})

-- rumdl's server reports the markdown rules it cannot fix on save (duplicate
-- headings, skipped heading levels, bare URLs, ...). marksman stays alongside it
-- for links, references and the document outline. The command is built per
-- root because a fallback config can only be handed over as an argument, and
-- only when the project has none (lua/rumdl.lua).
vim.lsp.config("rumdl", {
  cmd = function(dispatchers, config)
    local cmd = vim.list_extend({ "rumdl", "server" }, require("rumdl").config_args(config.root_dir))
    return vim.lsp.rpc.start(cmd, dispatchers)
  end,
})

local servers = { "marksman", "rumdl", "clangd", "neocmake", "taplo", "basedpyright", "ruff" }
vim.lsp.enable(servers)

-- read :h vim.lsp.config for changing options of lsp servers
