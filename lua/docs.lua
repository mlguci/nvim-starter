-- DevDocs, the half devdocs.nvim does not do. The plugin (lua/plugins/devdocs.lua)
-- downloads docsets and has pandoc turn every page into a markdown file under
-- stdpath("data")/devdocs/docs/<slug>/. Everything after that is here: the
-- pages listed in the snacks picker rather than two nested vim.ui.selects, scoped
-- to the docsets that match the buffer's filetype, a full-text grep, and a float
-- to read the page in. The plugin's own viewer opens a :split, which rearranges
-- the working layout; a float does not, the same reason the Claude diff and
-- Neogit get tabs of their own.
local M = {}

-- Docsets per filetype, most specific first. Versioned slugs (`lua~5.1`) are what
-- `:DevDocs install` lists; unversioned ones track the newest release. Lua is
-- 5.1 because that is the language LuaJIT, and so Neovim, actually runs. cpp
-- pulls in c as well: the C library is half of what a C++ program calls.
local by_filetype = {
  c = { "c" },
  cpp = { "cpp", "c" },
  cmake = { "cmake" },
  lua = { "lua~5.1" },
  python = { "python~3.15" },
}

local function installed()
  local ok, devdocs = pcall(require, "devdocs")
  return ok and devdocs.GetInstalledDocs() or {}
end

--- The installed docsets for a filetype. Falls back to every installed docset
--- when the filetype has none -- a picker over everything beats an empty one.
---@param all? boolean skip the filetype and return every installed docset
---@return string[]
function M.slugs(all)
  local have = installed()
  if all then
    return have
  end
  local wanted = by_filetype[vim.bo.filetype] or {}
  local slugs = vim.tbl_filter(function(slug)
    return vim.list_contains(have, slug)
  end, wanted)
  return #slugs > 0 and slugs or have
end

--- The same prettifying devdocs.nvim's own picker does: the path inside the
--- docset with the slashes, `index` and extension dropped.
local function title(slug, file)
  local dir = require("devdocs").GetDocDir(slug)
  local name = file:sub(#dir + 2):gsub("%.md$", ""):gsub("/?index$", ""):gsub("/", " ")
  return name == "" and "index" or name
end

local function slug_of(file)
  local root = vim.fn.stdpath "data" .. "/devdocs/docs/"
  return file:sub(1, #root) == root and file:sub(#root + 1):match "^[^/]+" or "devdocs"
end

--- Read a page in a centered float. Nothing about the layout changes, and `q`
--- puts everything back.
---@param file string
---@param pos? integer[] { row, col } to put the cursor on, as grep reports it
function M.open(file, pos)
  local buf = vim.fn.bufadd(file)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = false
  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false
  vim.diagnostic.enable(false, { bufnr = buf })

  local slug = slug_of(file)
  Snacks.win {
    buf = buf,
    title = slug .. ": " .. title(slug, file),
    width = 0.85,
    height = 0.85,
    border = "rounded",
    enter = true,
    backdrop = false,
    -- minimal (the default) clears number, signcolumn and the rest; prose then
    -- wants to wrap at word boundaries.
    wo = { wrap = true, linebreak = true, conceallevel = 2 },
    keys = { q = "close", ["<Esc>"] = "close" },
    on_win = function(win)
      if pos then
        pcall(vim.api.nvim_win_set_cursor, win.win, pos)
      end
    end,
  }
end

local function confirm(picker, item)
  picker:close()
  if item then
    -- util.path, not item.file: grep items carry a path relative to their cwd.
    M.open(Snacks.picker.util.path(item), item.pos)
  end
end

--- Pick a page from the docsets for this filetype.
---@param opts? { all?: boolean, search?: string }
function M.pick(opts)
  opts = opts or {}
  local slugs = M.slugs(opts.all)
  if #slugs == 0 then
    vim.notify("No docsets installed yet -- <leader>hi to install one", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, slug in ipairs(slugs) do
    for _, file in ipairs(require("devdocs").GetDoc(slug) or {}) do
      local name = title(slug, file)
      items[#items + 1] = { text = slug .. "  " .. name, file = file, slug = slug, name = name }
    end
  end

  Snacks.picker.pick {
    title = "DevDocs: " .. table.concat(slugs, ", "),
    items = items,
    pattern = opts.search,
    format = function(item)
      return { { item.slug, "Comment" }, { "  " }, { item.name } }
    end,
    preview = "file",
    confirm = confirm,
  }
end

--- The word under the cursor, or the visual selection, as the search.
function M.cword()
  local search
  if vim.fn.mode():match "[vV\22]" then
    search = table.concat(vim.fn.getregion(vim.fn.getpos "v", vim.fn.getpos "."), " ")
    vim.api.nvim_feedkeys(vim.keycode "<Esc>", "n", false)
  else
    search = vim.fn.expand "<cword>"
  end
  M.pick { search = search }
end

--- Full-text search through the pages of this filetype's docsets.
function M.grep()
  local slugs = M.slugs()
  if #slugs == 0 then
    vim.notify("No docsets installed yet -- <leader>hi to install one", vim.log.levels.WARN)
    return
  end
  local devdocs = require "devdocs"
  Snacks.picker.grep {
    title = "DevDocs grep: " .. table.concat(slugs, ", "),
    dirs = vim.tbl_map(devdocs.GetDocDir, slugs),
    confirm = confirm,
  }
end

-- The HTML -> markdown conversion, replacing devdocs.nvim's own. Two things in
-- the plugin's version leave HTML in the pages:
--
--   * devdocs writes every code block as a bare <pre data-language="...">, and
--     pandoc only reads <pre><code> as code -- a bare <pre> becomes text with hard
--     line breaks, so every example in every docset came out escaped and
--     unhighlighted. The <code> is added here before pandoc sees the page.
--   * the gfm writer emits raw HTML for anything markdown cannot express, which
--     is every table in cppreference. pandoc/devdocs.lua rewrites those.
--
-- Bump this when either changes: docsets converted under an older format are
-- rebuilt from their downloaded JSON on the next start (see M.setup).
local FORMAT = 1
local filter = vim.fn.stdpath "config" .. "/pandoc/devdocs.lua"
local format_file = vim.fn.stdpath "data" .. "/devdocs/format"

-- cppreference labels all its code `c`, C++ included.
local language_override = { cpp = "cpp" }

---@param html string
---@param output string
---@param callback fun()
function M.convert(html, output, callback)
  local lang = language_override[slug_of(output)]
  html = html:gsub("<pre([^>]*)>", function(attrs)
    local code_lang = lang or attrs:match 'data%-language="([^"]+)"'
    return "<pre><code" .. (code_lang and (' class="language-' .. code_lang .. '"') or "") .. ">"
  end)
  html = html:gsub("</pre>", "</code></pre>")
  -- --wrap=none: pandoc would otherwise hard-wrap at 72 columns, and the float
  -- wraps (with 'linebreak') to its own, wider, width.
  local cmd = { "pandoc", "-f", "html", "-t", "gfm", "--wrap=none", "--lua-filter=" .. filter, "-o", output }
  vim.system(cmd, { stdin = html }, function(res)
    if res.code ~= 0 then
      vim.schedule(function()
        vim.notify("DevDocs pandoc error (" .. output .. "): " .. (res.stderr or ""), vim.log.levels.WARN)
      end)
    end
    callback()
  end)
end

--- Convert docsets again from the JSON devdocs.nvim keeps beside them, one
--- docset at a time -- each one already runs several pandoc jobs at once.
---@param slugs string[]
---@param done? fun()
function M.rebuild(slugs, done)
  local extract = require("devdocs.docs").ExtractDocs
  local i = 0
  local function next_slug()
    i = i + 1
    if not slugs[i] then
      if done then
        done()
      end
      return
    end
    vim.notify("DevDocs: converting " .. slugs[i] .. " again", vim.log.levels.INFO)
    extract(slugs[i], next_slug)
  end
  next_slug()
end

--- Called from the plugin spec in place of a bare setup().
function M.setup(opts)
  require("devdocs.docs").ConvertHtmlToMarkdown = M.convert
  require("devdocs").setup(opts)

  vim.api.nvim_create_user_command("DevDocsRebuild", function()
    M.rebuild(installed())
  end, { desc = "Convert every installed docset to markdown again" })

  local f = io.open(format_file)
  local current = f and tonumber(f:read "*l")
  if f then
    f:close()
  end
  if current ~= FORMAT then
    M.rebuild(installed(), function()
      local out = io.open(format_file, "w")
      if out then
        out:write(FORMAT, "\n")
        out:close()
      end
    end)
  end
end

--- devdocs.io in the browser, for docsets not installed or pages pandoc mangled.
function M.online()
  local slug = (by_filetype[vim.bo.filetype] or {})[1]
  local query = vim.trim(((slug or ""):gsub("~.*", "")) .. " " .. vim.fn.expand "<cword>")
  vim.ui.open("https://devdocs.io/#q=" .. vim.uri_encode(query))
end

return M
