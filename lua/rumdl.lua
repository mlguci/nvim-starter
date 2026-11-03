-- Which config rumdl, the markdown formatter and linter, runs with. Both callers
-- use this: the conform formatter (lua/configs/conform.lua) and the language
-- server (lua/configs/lspconfig.lua).
--
-- rumdl finds a project's config on its own, walking up from the file. That
-- covers its own .rumdl.toml, rumdl.toml, .config/rumdl.toml and a
-- [tool.rumdl] table in pyproject.toml, plus every markdownlint config name. A
-- file with none of those gets this repo's .rumdl.toml instead, through
-- `--config`. That flag is passed only when there is no project config,
-- because rumdl stops looking for one as soon as it is given a file.
-- rumdl's user-level config (~/.config/rumdl/rumdl.toml) would do the same
-- job, but it lives outside this repo, and a fresh clone would come up without
-- it.

local M = {}

M.fallback = vim.fn.stdpath "config" .. "/.rumdl.toml"

local names = {
  ".rumdl.toml",
  "rumdl.toml",
  ".markdownlint.jsonc",
  ".markdownlint.json",
  ".markdownlint.yaml",
  ".markdownlint.yml",
  ".markdownlint-cli2.jsonc",
  ".markdownlint-cli2.yaml",
  ".markdownlint-cli2.yml",
  "markdownlint.json",
  "markdownlint.jsonc",
  "markdownlint.yaml",
  "markdownlint.yml",
}

-- A pyproject.toml only counts when it has a [tool.rumdl] table: most Python
-- projects have the file and say nothing about markdown.
local function has_rumdl_table(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return false
  end
  for _, line in ipairs(lines) do
    if line:match "^%s*%[tool%.rumdl[%].]" then
      return true
    end
  end
  return false
end

---@param dir string? directory to search upward from; nil or missing means cwd
---@return boolean
function M.has_project_config(dir)
  if not dir or vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.getcwd()
  end
  local found = vim.fs.find(function(name, path)
    if name == "pyproject.toml" then
      return has_rumdl_table(path .. "/" .. name)
    elseif name == ".config" then -- an upward search never looks inside it
      return vim.fn.filereadable(path .. "/.config/rumdl.toml") == 1
    end
    return vim.tbl_contains(names, name)
  end, { path = dir, upward = true, limit = 1 })
  return found[1] ~= nil
end

---@param dir string?
---@return string[] arguments to put before rumdl's subcommand
function M.config_args(dir)
  return M.has_project_config(dir) and {} or { "--config", M.fallback }
end

return M
