-- A Compiler Explorer view of the current C/C++ buffer, built locally: the
-- compiler and flags come from the project's compile_commands.json, so project
-- includes resolve and the active CMake preset decides the codegen -- Debug and
-- Release show what they really build. Nothing leaves the machine.
--
-- The assembly opens in a split to the right. Moving the cursor in either
-- window highlights the matching lines in the other, and every source line
-- that produced code gets an alternating background so the blocks stay
-- visible. Saving the source recompiles.
--
-- The database read is the root copy cmake-tools rewrites on every generate
-- (cmake_compile_commands_options in lua/configs/cmake.lua), which is why
-- switching preset and regenerating is all it takes to switch the view.
local M = {}

local ns = vim.api.nvim_create_namespace "asm_view"
local cursor_ns = vim.api.nvim_create_namespace "asm_view_cursor"

-- Source buffer -> view state. One view per source buffer.
---@type table<integer, { asm: integer, group: integer, map: table<integer, integer>, rev: table<integer, integer[]> }>
local views = {}

-- Homebrew LLVM's demangler in preference to the system one, the same
-- preference lua/configs/lspconfig.lua gives clangd. Both strip the extra
-- leading underscore Mach-O adds to symbol names.
local function demangler()
  local brew = "/opt/homebrew/opt/llvm/bin/llvm-cxxfilt"
  if vim.uv.fs_stat(brew) then
    return brew
  end
  for _, exe in ipairs { "llvm-cxxfilt", "c++filt" } do
    if vim.fn.executable(exe) == 1 then
      return exe
    end
  end
end

local function realpath(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function absolute(dir, path)
  if path:sub(1, 1) == "/" then
    return path
  end
  return vim.fs.joinpath(dir, path)
end

-- POSIX-shell word splitting, enough for the `command` form of a database
-- entry: whitespace separates, single and double quotes group, backslash
-- escapes. CMake writes `command`, other generators may write `arguments`.
local function shell_split(s)
  local args, cur, quote = {}, nil, nil
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if quote then
      if c == quote then
        quote = nil
      elseif c == "\\" and quote == '"' then
        i = i + 1
        cur = cur .. s:sub(i, i)
      else
        cur = cur .. c
      end
    elseif c == "'" or c == '"' then
      quote = c
      cur = cur or ""
    elseif c == "\\" then
      i = i + 1
      cur = (cur or "") .. s:sub(i, i)
    elseif c:match "%s" then
      if cur then
        args[#args + 1] = cur
        cur = nil
      end
    else
      cur = (cur or "") .. c
    end
    i = i + 1
  end
  if cur then
    args[#args + 1] = cur
  end
  return args
end

-- Parsed databases by path, dropped when the file's mtime changes -- which is
-- every generate, since cmake-tools copies a fresh one over it.
local db_cache = {}

local function load_db(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  local cached = db_cache[path]
  if cached and cached.mtime == stat.mtime.sec and cached.nsec == stat.mtime.nsec then
    return cached.entries
  end
  local ok, entries = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok or type(entries) ~= "table" then
    return nil
  end
  db_cache[path] = { mtime = stat.mtime.sec, nsec = stat.mtime.nsec, entries = entries }
  return entries
end

--- The database entry that compiles `file`, or nil and a reason.
local function find_entry(file)
  local root = vim.fs.root(file, "compile_commands.json")
  if not root then
    return nil, "no compile_commands.json above this file -- configure first (<leader>cmg)"
  end
  local entries = load_db(vim.fs.joinpath(root, "compile_commands.json"))
  if not entries then
    return nil, "compile_commands.json could not be read"
  end
  local want = realpath(file)
  for _, entry in ipairs(entries) do
    if realpath(absolute(entry.directory, entry.file)) == want then
      return entry
    end
  end
  return nil, "this file is not in compile_commands.json -- is it in a target? (<leader>cmg after adding it)"
end

-- Flags that write files or describe the object being built. They take the next
-- word as their value, except the ones listed as standalone.
local drop_with_value = { ["-o"] = true, ["-MF"] = true, ["-MT"] = true, ["-MQ"] = true }
local drop_alone = { ["-c"] = true, ["-MD"] = true, ["-MMD"] = true }

--- The entry's own command, turned from "compile to an object" into "print
--- assembly". `-g` is always added: the `.loc` directives it produces are the
--- whole source <-> asm mapping, Release builds have none of their own, and
--- debug info does not change the instructions generated.
local function asm_command(entry)
  local words = entry.arguments and vim.deepcopy(entry.arguments) or shell_split(entry.command)
  local args = {}
  local skip = false
  for _, w in ipairs(words) do
    if skip then
      skip = false
    elseif drop_with_value[w] then
      skip = true
    elseif not drop_alone[w] then
      args[#args + 1] = w
    end
  end
  vim.list_extend(args, { "-S", "-g", "-o", "-" })
  return args
end

--- Debug/Release as the flags state it, for the window bar.
local function describe(args)
  local opt
  for _, a in ipairs(args) do
    local o = a:match "^%-O(.*)$"
    if o then
      opt = o == "" and "1" or o
    end
  end
  return ("%s -O%s"):format(vim.fs.basename(args[1]), opt or "0")
end

local function is_text_section(name)
  return name:match "^__TEXT,__text" or name:match "^%.text" or name:match "^__text"
end

--- Godbolt's default filters over raw compiler output: only code sections, no
--- directives, no comment lines, no compiler-internal labels, and no functions
--- that have no line in this file (the template instantiations from headers
--- that make up most of an unoptimised build). Returns the kept lines and, per
--- kept line, the source line it came from.
---@return string[] lines, table<integer, integer> map
local function parse(text, file)
  local want = realpath(file)
  local main = {} -- .file ids that name the source file itself
  local in_text = false
  local cur -- source line of the last .loc in this file, nil inside others

  local functions = {}
  local fn

  local function start_function(label)
    fn = { lines = {}, map = {}, mapped = false }
    functions[#functions + 1] = fn
    if label then
      fn.lines[1] = label
    end
    return fn
  end

  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    local id, dir, name = line:match '^%s*%.file%s+(%d+)%s+"([^"]*)"%s+"([^"]*)"'
    if not id then
      id, name = line:match '^%s*%.file%s+(%d+)%s+"([^"]*)"'
      dir = vim.fs.dirname(want)
    end
    if id then
      if realpath(absolute(dir, name)) == want then
        main[tonumber(id)] = true
      end
      goto continue
    end

    local section = line:match "^%s*%.section%s+([^%s]+)"
    if section then
      in_text = is_text_section(section) ~= nil
      goto continue
    end
    if line:match "^%s*%.text%s*$" then
      in_text = true
      goto continue
    end
    if line:match "^%s*%.data%s*$" or line:match "^%s*%.bss%s*$" then
      in_text = false
      goto continue
    end
    if not in_text then
      goto continue
    end

    local loc_file, loc_line = line:match "^%s*%.loc%s+(%d+)%s+(%d+)"
    if loc_file then
      loc_line = tonumber(loc_line)
      cur = (main[tonumber(loc_file)] and loc_line > 0) and loc_line or nil
      goto continue
    end

    -- Remaining directives, blank lines, and whole-line comments (`;` on
    -- arm64 Mach-O, `#` on x86, `//` on some assemblers).
    if line:match "^%s*%." or line:match "^%s*$" or line:match "^%s*[;#@]" or line:match "^%s*//" then
      goto continue
    end

    local label = line:match "^([%w_.$]+):"
    if label then
      if label:match "^%.?L" then
        -- Branch targets stay, as `.LBB0_3:`/`LBB0_3:`; Ltmp, Lfunc_begin,
        -- Lfunc_end and Lloh exist for the debug info and linker only.
        if label:match "^%.?LBB" then
          fn = fn or start_function()
          fn.lines[#fn.lines + 1] = label .. ":"
        end
      else
        start_function(label .. ":")
      end
      goto continue
    end

    do
      local mnemonic, rest = line:match "^%s*(%S+)%s*(.-)%s*$"
      if not fn then
        start_function()
      end
      rest = rest:gsub("%s+;", "  ;")
      fn.lines[#fn.lines + 1] = ("    %-7s %s"):format(mnemonic, rest):gsub("%s+$", "")
      if cur then
        fn.map[#fn.lines] = cur
        fn.mapped = true
      end
    end

    ::continue::
  end

  local lines, map = {}, {}
  for _, f in ipairs(functions) do
    if f.mapped then
      if #lines > 0 then
        lines[#lines + 1] = ""
      end
      local base = #lines
      for i, l in ipairs(f.lines) do
        lines[base + i] = l
        map[base + i] = f.map[i]
      end
    end
  end
  return lines, map
end

local function close(src)
  local view = views[src]
  if not view then
    return
  end
  views[src] = nil
  pcall(vim.api.nvim_del_augroup_by_id, view.group)
  if vim.api.nvim_buf_is_valid(src) then
    vim.api.nvim_buf_clear_namespace(src, ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(src, cursor_ns, 0, -1)
  end
  if vim.api.nvim_buf_is_valid(view.asm) then
    vim.api.nvim_buf_delete(view.asm, { force = true })
  end
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

-- Faint alternating backgrounds, one per source line that produced code, the
-- way Godbolt colours blocks. Linked to existing groups so the theme decides.
vim.api.nvim_set_hl(0, "AsmBlockA", { default = true, link = "CursorLine" })
vim.api.nvim_set_hl(0, "AsmBlockB", { default = true, link = "ColorColumn" })
vim.api.nvim_set_hl(0, "AsmLinked", { default = true, link = "Visual" })

local function paint(src, view)
  vim.api.nvim_buf_clear_namespace(src, ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(view.asm, ns, 0, -1)

  local lines = vim.tbl_keys(view.rev)
  table.sort(lines)
  local group = {}
  for i, l in ipairs(lines) do
    group[l] = i % 2 == 0 and "AsmBlockA" or "AsmBlockB"
  end

  local src_count = vim.api.nvim_buf_line_count(src)
  for l, hl in pairs(group) do
    if l <= src_count then
      vim.api.nvim_buf_set_extmark(src, ns, l - 1, 0, { line_hl_group = hl, priority = 10 })
    end
  end
  for a, l in pairs(view.map) do
    vim.api.nvim_buf_set_extmark(view.asm, ns, a - 1, 0, { line_hl_group = group[l], priority = 10 })
  end
end

local function win_of(buf)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
end

--- Highlight the lines linked to `line` of `from` in the other buffer, and
--- scroll the other window so the first of them is in view.
local function link(src, from_src, line)
  local view = views[src]
  if not view then
    return
  end
  vim.api.nvim_buf_clear_namespace(src, cursor_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(view.asm, cursor_ns, 0, -1)

  local target_buf, targets
  if from_src then
    target_buf, targets = view.asm, view.rev[line] or {}
  else
    target_buf, targets = src, view.map[line] and { view.map[line] } or {}
  end

  for _, t in ipairs(targets) do
    vim.api.nvim_buf_set_extmark(target_buf, cursor_ns, t - 1, 0, { line_hl_group = "AsmLinked", priority = 20 })
  end

  local win = win_of(target_buf)
  if win and targets[1] then
    local top, bot = vim.fn.line("w0", win), vim.fn.line("w$", win)
    if targets[1] < top or targets[1] > bot then
      vim.api.nvim_win_call(win, function()
        vim.api.nvim_win_set_cursor(win, { targets[1], 0 })
        vim.cmd "normal! zz"
      end)
    end
  end
end

local function compile(src)
  local view = views[src]
  if not view then
    return
  end
  local file = vim.api.nvim_buf_get_name(src)
  local entry, err = find_entry(file)
  if not entry then
    set_lines(view.asm, { "; " .. err })
    return
  end
  local args = asm_command(entry)
  vim.b[view.asm].winbar_label = "asm: " .. vim.fs.basename(file) .. "  " .. describe(args)

  vim.system(args, { cwd = entry.directory, text = true }, function(res)
    if res.code ~= 0 then
      vim.schedule(function()
        if views[src] == view and vim.api.nvim_buf_is_valid(view.asm) then
          view.map, view.rev = {}, {}
          set_lines(view.asm, vim.split(res.stderr or "compile failed", "\n", { trimempty = true }))
          paint(src, view)
        end
      end)
      return
    end

    -- Parsed on the main loop: vim.system callbacks run in a fast event, where
    -- most of the API is off limits.
    vim.schedule(function()
      local lines, map = parse(res.stdout or "", file)
      local function show(final)
        vim.schedule(function()
          if views[src] ~= view or not vim.api.nvim_buf_is_valid(view.asm) then
            return
          end
          view.map, view.rev = map, {}
          for a, l in pairs(map) do
            view.rev[l] = view.rev[l] or {}
            table.insert(view.rev[l], a)
          end
          for _, list in pairs(view.rev) do
            table.sort(list)
          end
          set_lines(view.asm, #final > 0 and final or { "; no code generated for this file" })
          paint(src, view)
          if vim.api.nvim_get_current_buf() == src then
            link(src, true, vim.api.nvim_win_get_cursor(0)[1])
          end
        end)
      end

      local filt = demangler()
      if not filt or #lines == 0 then
        return show(lines)
      end
      -- One process over the whole listing. Both demanglers are line-oriented,
      -- so line numbers -- and so the map -- survive; if the count ever comes
      -- back different the mangled listing is shown rather than a wrong map.
      vim.system({ filt }, { stdin = table.concat(lines, "\n") .. "\n", text = true }, function(d)
        local out = d.code == 0 and vim.split(d.stdout or "", "\n", { plain = true }) or {}
        if out[#out] == "" then
          out[#out] = nil
        end
        show(#out == #lines and out or lines)
      end)
    end)
  end)
end

local function open(src)
  local asm = vim.api.nvim_create_buf(false, true)
  vim.bo[asm].filetype = "asm"
  vim.bo[asm].bufhidden = "wipe"
  vim.bo[asm].modifiable = false
  pcall(vim.api.nvim_buf_set_name, asm, "asm://" .. vim.api.nvim_buf_get_name(src))
  vim.b[asm].asm_source = src

  local win = vim.api.nvim_open_win(asm, false, { split = "right", win = vim.api.nvim_get_current_win() })
  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].foldenable = false
  vim.wo[win].cursorline = false

  local group = vim.api.nvim_create_augroup("AsmView" .. src, { clear = true })
  views[src] = { asm = asm, group = group, map = {}, rev = {} }
  set_lines(asm, { "; compiling..." })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = src,
    callback = function()
      compile(src)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = src,
    callback = function()
      link(src, true, vim.api.nvim_win_get_cursor(0)[1])
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = asm,
    callback = function()
      link(src, false, vim.api.nvim_win_get_cursor(0)[1])
    end,
  })
  -- Closing the asm window, or wiping either buffer, tears the view down.
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = asm,
    callback = function()
      vim.schedule(function()
        close(src)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = src,
    callback = function()
      close(src)
    end,
  })

  compile(src)
end

--- Open the assembly view for the current buffer, or close it if it is open.
--- From inside an asm view, closes that view.
function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  local src = vim.b[buf].asm_source or buf
  if views[src] then
    return close(src)
  end
  if not vim.tbl_contains({ "c", "cpp", "objc", "objcpp", "cuda" }, vim.bo[src].filetype) then
    return vim.notify("asm view: not a C/C++ buffer", vim.log.levels.WARN)
  end
  if vim.bo[src].modified then
    vim.notify("asm view compiles the file on disk -- save to see your changes", vim.log.levels.INFO)
  end
  open(src)
end

-- Exposed for testing the filters without a window.
M._parse = parse
M._asm_command = asm_command

return M
