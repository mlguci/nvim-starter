-- chezmoi glue, shared by the filetype and apply-on-save hooks in
-- lua/autocmds.lua and the <leader>C maps.
--
-- Named "dotfiles" rather than "chezmoi" deliberately: this config's own lua/
-- directory comes before lazy's plugin paths in the runtimepath, so a
-- lua/chezmoi.lua here would shadow chezmoi.nvim's own `chezmoi` module and
-- break the `require("chezmoi").setup()` lazy runs for that spec's opts.

local M = {}

-- chezmoi's default source directory. Taken from the environment rather than
-- asked of `chezmoi source-path`, which would put a subprocess on every
-- startup; no chezmoi.toml here redefines it.
M.source = vim.fs.normalize((vim.env.XDG_DATA_HOME or vim.env.HOME .. "/.local/share") .. "/chezmoi")

-- Attribute prefixes chezmoi puts in front of a source file name. They stack
-- in any order (encrypted_private_dot_netrc), so they are stripped in a loop
-- rather than once.
local attributes = {
  "encrypted_",
  "private_",
  "readonly_",
  "executable_",
  "symlink_",
  "modify_",
  "create_",
  "remove_",
  "run_",
  "once_",
  "onchange_",
  "before_",
  "after_",
  "literal_",
}

-- The source directory is itself a git repo, and nothing under .git/ is a
-- managed entry: a commit message buffer has to keep its own filetype and must
-- never trigger an apply.
function M.managed_source(path)
  return vim.startswith(path, M.source .. "/") and not path:find "/%.git/"
end

-- Source path -> the path in $HOME it maps to. chezmoi mirrors the directory
-- structure, so every component is unmangled, not just the last one: that is
-- what lets private_dot_config/git/config resolve to ~/.config/git/config.
function M.target(path)
  local relative = path:sub(#M.source + 2):gsub("%.tmpl$", "")
  local parts = {}

  for part in vim.gsplit(relative, "/", { plain = true, trimempty = true }) do
    local stripped = true
    while stripped do
      stripped = false
      for _, attribute in ipairs(attributes) do
        local shorter, found = part:gsub("^" .. attribute, "", 1)
        if found > 0 then
          part, stripped = shorter, true
        end
      end
    end
    parts[#parts + 1] = (part:gsub("^dot_", "."))
  end

  return vim.env.HOME .. "/" .. table.concat(parts, "/")
end

-- Push a source file to $HOME, or every target when called with no path.
-- `--source-path` keeps a save scoped to the one file it touched, so a
-- half-finished edit elsewhere in the source tree is never applied with it.
function M.apply(path)
  local cmd = { "chezmoi", "apply" }
  if path then
    vim.list_extend(cmd, { "--source-path", path })
  end

  vim.system(
    cmd,
    { text = true },
    vim.schedule_wrap(function(out)
      if out.code ~= 0 then
        vim.notify("chezmoi apply failed\n" .. (out.stderr or ""), vim.log.levels.ERROR)
      else
        vim.notify("chezmoi applied " .. (path and vim.fs.basename(M.target(path)) or "all targets"))
      end
    end)
  )
end

return M
