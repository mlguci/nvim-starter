-- Pandoc Lua filter for devdocs.nvim's HTML -> markdown pass. Not a Neovim
-- module: lua/docs.lua hands this file to pandoc with --lua-filter.
--
-- The target is GitHub markdown, which has no way to express a table cell holding
-- more than one line, a code block or a list. pandoc's gfm writer answers that by
-- writing the whole table out as raw HTML -- which is every declaration table
-- and member table in cppreference, nearly every C and C++ page -- and does the
-- same for definition lists (Python's signatures) and superscripts. Markdown
-- renderers in a terminal show those tags verbatim. So each of those is rewritten
-- here into what markdown does have: code blocks, lists and paragraphs. Tables
-- that *are* expressible stay tables.

local stringify = pandoc.utils.stringify

local function blocks_to_inlines(blocks)
  return pandoc.utils.blocks_to_inlines(blocks, { pandoc.Space() })
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "-" is the separator column of cppreference's parameter tables.
local function is_empty(cell)
  local text = trim(stringify(cell.contents))
  return text == "" or text == "-"
end

-- Inlines as source text: hard breaks become newlines and the non-breaking
-- spaces that HTML uses for indentation become spaces again.
local function code_text(inlines)
  local parts = {}
  pandoc.Inlines(inlines):walk {
    Str = function(el)
      parts[#parts + 1] = el.text
    end,
    Code = function(el)
      parts[#parts + 1] = el.text
    end,
    Space = function()
      parts[#parts + 1] = " "
    end,
    SoftBreak = function()
      parts[#parts + 1] = " "
    end,
    LineBreak = function()
      parts[#parts + 1] = "\n"
    end,
  }
  return (table.concat(parts):gsub("\194\160", " "))
end

-- A cell markdown can hold: at most one paragraph of inlines, no hard breaks,
-- spanning a single row and column.
local function simple_cell(cell)
  if cell.row_span ~= 1 or cell.col_span ~= 1 or #cell.contents > 1 then
    return false
  end
  local block = cell.contents[1]
  if block and block.t ~= "Plain" and block.t ~= "Para" then
    return false
  end
  local ok = true
  if block then
    block:walk {
      LineBreak = function()
        ok = false
      end,
    }
  end
  return ok
end

-- A cell of nothing but paragraphs and headings, run together onto one line.
-- nil when it holds anything with structure of its own (a list, code).
local function cell_inlines(cell)
  local inlines = pandoc.Inlines {}
  for _, block in ipairs(cell.contents) do
    if block.t ~= "Plain" and block.t ~= "Para" and block.t ~= "Header" then
      return nil
    end
    if #inlines > 0 then
      inlines:insert(pandoc.Space())
    end
    inlines:extend(block.content)
  end
  return inlines:walk {
    LineBreak = function()
      return pandoc.Space()
    end,
  }
end

local function all_rows(tbl)
  local rows = {}
  for _, row in ipairs(tbl.head.rows) do
    rows[#rows + 1] = row
  end
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.head) do
      rows[#rows + 1] = row
    end
    for _, row in ipairs(body.body) do
      rows[#rows + 1] = row
    end
  end
  for _, row in ipairs(tbl.foot.rows) do
    rows[#rows + 1] = row
  end
  return rows
end

local function comment_prefix(code)
  for _, class in ipairs(code.classes) do
    if class == "python" or class == "cmake" or class == "bash" or class == "sh" then
      return "# "
    end
  end
  return "// "
end

local function has_class(el, name)
  for _, class in ipairs(el.attr.classes) do
    if class == name then
      return true
    end
  end
  return false
end

-- A declaration row: one code block, then nothing but short annotations such as
-- "(1)" and "(since C++17)". A <pre> inside a <td> reaches the filter as plain
-- inlines with hard breaks rather than a CodeBlock, so cppreference's own row
-- class is what identifies those.
local function declaration(row)
  local code
  local notes = {}
  for i, cell in ipairs(row.cells) do
    if i == 1 then
      local block = cell.contents[1]
      if #cell.contents ~= 1 then
        return nil
      elseif block.t == "CodeBlock" then
        code = block
      elseif has_class(row, "t-dcl") and block.t == "Plain" then
        code = pandoc.CodeBlock(code_text(block.content), pandoc.Attr("", { "cpp" }))
      else
        return nil
      end
    elseif not is_empty(cell) then
      if not simple_cell(cell) then
        return nil
      end
      notes[#notes + 1] = trim(stringify(cell.contents))
    end
  end
  if not code then
    return nil
  end
  local text = code.text:gsub("%s+$", "")
  if #notes > 0 then
    text = comment_prefix(code) .. table.concat(notes, " ") .. "\n" .. text
  end
  return text, code
end

local function rewrite_table(tbl)
  local rows = all_rows(tbl)

  local expressible = true
  for _, row in ipairs(rows) do
    for _, cell in ipairs(row.cells) do
      if not simple_cell(cell) then
        expressible = false
      end
    end
  end
  if expressible then
    -- Column widths are what push pandoc to a grid table; markdown has none.
    for i, spec in ipairs(tbl.colspecs) do
      tbl.colspecs[i] = { spec[1], pandoc.ColWidthDefault }
    end
    tbl.attr = pandoc.Attr()
    return tbl
  end

  local out = {}
  local decls, decl_code = {}, nil
  local items = {}

  local function flush()
    if #decls > 0 then
      out[#out + 1] = pandoc.CodeBlock(table.concat(decls, "\n\n"), decl_code.attr)
      decls, decl_code = {}, nil
    end
    if #items > 0 then
      out[#out + 1] = pandoc.BulletList(items)
      items = {}
    end
  end

  for _, row in ipairs(rows) do
    local text, code = declaration(row)
    local filled = {}
    for _, cell in ipairs(row.cells) do
      if not is_empty(cell) then
        filled[#filled + 1] = cell
      end
    end

    if text then
      if #items > 0 then
        flush()
      end
      decls[#decls + 1] = text
      decl_code = decl_code or code
    elseif #filled == 1 and cell_inlines(filled[1]) then
      -- A heading row: "Defined in header <vector>", "Element access", ...
      flush()
      out[#out + 1] = pandoc.Para { pandoc.Strong(cell_inlines(filled[1])) }
    elseif #filled > 0 then
      if #decls > 0 then
        flush()
      end
      -- Name, then description, then any trailing note, on one line as a list
      -- item: "assign — assigns values to the container (public member
      -- function)". Once a cell with structure of its own turns up, it and the
      -- cells after it keep their blocks, so a list or code block inside a
      -- description survives as itself.
      local lead = pandoc.Plain(cell_inlines(filled[1]) or blocks_to_inlines(filled[1].contents))
      local item = { lead }
      for i = 2, #filled do
        local cell = filled[i]
        local inlines = #item == 1 and cell_inlines(cell)
        if inlines then
          local sep = i == 2 and { pandoc.Space(), pandoc.Str "—", pandoc.Space() } or { pandoc.Space() }
          lead.content:extend(sep)
          lead.content:extend(inlines)
        else
          for _, block in ipairs(cell.contents) do
            item[#item + 1] = block
          end
        end
      end
      items[#items + 1] = item
    end
  end
  flush()

  if tbl.caption and tbl.caption.long and #tbl.caption.long > 0 then
    table.insert(out, 1, pandoc.Para { pandoc.Emph(blocks_to_inlines(tbl.caption.long)) })
  end
  return out
end

return {
  {
    -- Containers markdown has no syntax for; their content is all that matters.
    Div = function(el)
      return el.content
    end,
    Span = function(el)
      return el.content
    end,
  },
  {
    Table = rewrite_table,

    -- Python's signatures and glossaries. The term becomes a bold line, its
    -- definitions follow as ordinary blocks.
    DefinitionList = function(el)
      local out = {}
      for _, entry in ipairs(el.content) do
        out[#out + 1] = pandoc.Para { pandoc.Strong(entry[1]) }
        for _, def in ipairs(entry[2]) do
          for _, block in ipairs(def) do
            out[#out + 1] = block
          end
        end
      end
      return out
    end,

    -- cppreference's [1] citation markers point at footnotes that are rendered
    -- as plain text further down anyway; anything else keeps a caret.
    Superscript = function(el)
      local cite = false
      el:walk {
        Link = function(link)
          if link.target:match "^#cite_note" then
            cite = true
          end
        end,
      }
      if cite then
        return {}
      end
      return pandoc.Str("^" .. stringify(el.content))
    end,
    Subscript = function(el)
      return pandoc.Str("_" .. stringify(el.content))
    end,

    -- Link titles are the source wiki's page names ("cpp/container/vector")
    -- and only add noise next to the link text.
    -- Any attribute at all (cppreference's class="external text") makes the gfm
    -- writer fall back to a raw <a> tag.
    Link = function(el)
      el.title = ""
      el.attr = pandoc.Attr()
      if #el.content == 1 and el.content[1].text == el.target then
        return pandoc.Str(el.target)
      end
      return el
    end,

    Code = function(el)
      el.attr = pandoc.Attr()
      return el
    end,
    Image = function(el)
      el.attr = pandoc.Attr()
      el.title = ""
      return el
    end,

    Para = function(el)
      if #el.content == 0 then
        return {}
      end
    end,
    Header = function(el)
      if #el.content == 0 then
        return {}
      end
    end,
  },
}
