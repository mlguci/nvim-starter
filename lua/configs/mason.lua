-- Every external binary this config calls by name, and the :MasonInstallAll
-- that puts them on a fresh machine. The plugins themselves are pinned by
-- lazy-lock.json; these are not, so without this list a clone comes up with no
-- formatter, no debug adapter and two of its language servers missing.
--
-- mason.nvim has no `ensure_installed` of its own -- that option belongs to
-- mason-lspconfig and mason-tool-installer, neither of which is used here -- so
-- the list lives in this file and the user command walks it. Mirrors the shape
-- of NvChad's own :TSInstallAll (nvchad/lua/nvchad/autocmds.lua), which exists
-- for the same reason.
--
-- A bare name resolves at all because nvchad.options prepends mason's bin
-- directory to vim.env.PATH (nvchad/lua/nvchad/options.lua) -- mason's own PATH
-- handling is set to "skip" in NvChad's mason config, so nothing else would, and
-- the directory is on no login shell's PATH.

local M = {}

M.ensure_installed = {
  -- Formatters, in the order lua/configs/conform.lua asks for them. clang-format
  -- and gersemi come from PyPI and prettier and markdownlint-cli2 from npm, so
  -- these four are the reason the host needs python3 and node (see README).
  "stylua",
  "prettier",
  "markdownlint-cli2",
  "clang-format",
  "gersemi",

  -- The language servers vim.lsp.enable starts in lua/configs/lspconfig.lua that
  -- mason can supply. clangd is deliberately absent: that file wants Homebrew
  -- LLVM's build in preference to a mason one, and falls back to whichever
  -- clangd is on PATH.
  "marksman",
  "neocmakelsp",

  -- The adapter lua/configs/dap.lua registers under the name `codelldb` and
  -- lua/configs/cmake.lua names in cmake_dap_configuration.
  "codelldb",
}

-- Install whatever is missing. Safe to re-run: already-installed packages are
-- filtered out rather than reinstalled, which is what :MasonInstall on its own
-- would do (it only skips packages that are mid-install).
function M.install_all()
  local registry = require "mason-registry"

  -- A machine that has never opened mason has no registry cache, and
  -- get_package -- which is_installed calls -- throws on a name it cannot find.
  -- The callback-less form is the blocking one, and the form mason's own docs
  -- point third-party code at; it already no-ops when the cache is fresh.
  registry.refresh()

  local missing = vim.tbl_filter(function(name)
    return not registry.is_installed(name)
  end, M.ensure_installed)

  if #missing == 0 then
    vim.notify(("mason: all %d packages present"):format(#M.ensure_installed))
    return
  end

  -- mason.api.command exports the function behind :MasonInstall, and calling it
  -- is not the same as `vim.cmd("MasonInstall " .. names)`. Mason pipes each
  -- installer's stderr straight to nvim_err_write, and under a vim.cmd() the
  -- lines come back around as Ex input -- tar's verbose "x neocmakelsp" is read
  -- as the :x command, which fails the whole install with "Error in command
  -- line: x neocmakelsp" and no hint of where it came from. The function takes
  -- the names as a list, so nothing is re-parsed.
  --
  -- Reusing it rather than driving Package:install() directly keeps the
  -- queueing, the progress window, and -- under --headless -- a blocking wait
  -- plus a `1cq` exit on failure, which is what makes
  -- `nvim --headless +MasonInstallAll +qa` usable from a provisioning script.
  require("mason.api.command").MasonInstall(missing)
end

return M
