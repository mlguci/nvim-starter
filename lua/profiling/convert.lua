-- Turns each recorder's output into the stack traces perfanno takes through
-- load_traces: { [event] = { { count = n, frames = { root, ..., leaf } } } }. Root
-- first is perfanno's order, which its caller lookups depend on. A frame is
-- { symbol, file, linenr }, and one with no file is still a stack entry, shown in
-- nothing but kept so that caller and callee links stay intact.
local platform = require "profiling.platform"

local M = {}

local NIL = vim.NIL

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read "*a"
  file:close()
  return text
end

local function location(symbol, file, line)
  if file and file:sub(1, 1) == "/" and line and line > 0 then
    return { symbol = symbol, file = file, linenr = line }
  end
  return { symbol = symbol or "?" }
end

-- --- symbolization ------------------------------------------------------------

-- llvm-symbolizer's JSON lists a location's inlined frames innermost first. Going
-- through it rather than asking only for the physical function matters because
-- optimised code is mostly inlined, and the line a person wants to see is usually
-- inside something the compiler folded away.
local function llvm_lines(tool, binary, dsym, addresses)
  local argv = { tool, "--output-style=JSON", "--inlines", "--demangle", "--obj=" .. binary }
  if dsym then
    argv[#argv + 1] = "--dsym-hint=" .. dsym
  end

  local out = vim.system(argv, { stdin = table.concat(addresses, "\n") .. "\n", text = true }):wait()
  local resolved = {}
  for line in (out.stdout or ""):gmatch "[^\n]+" do
    local ok, entry = pcall(vim.json.decode, line)
    if ok and type(entry) == "table" and entry.Address then
      local frames = {}
      for _, symbol in ipairs(entry.Symbol or {}) do
        table.insert(frames, 1, location(symbol.FunctionName, symbol.FileName, symbol.Line))
      end
      resolved[tonumber(entry.Address:sub(3), 16)] = frames
    end
  end
  return resolved
end

-- Fallback for a Linux host with binutils but no llvm package. With -a each
-- address is printed first, followed by function and location pairs, innermost
-- first.
local function addr2line_lines(tool, binary, addresses)
  local argv = { tool, "-a", "-C", "-f", "-i", "-e", binary }
  vim.list_extend(argv, addresses)

  local resolved, current, pending = {}, nil, nil
  for line in ((vim.system(argv, { text = true }):wait()).stdout or ""):gmatch "[^\n]+" do
    local address = line:match "^0x(%x+)$"
    if address then
      current = {}
      resolved[tonumber(address, 16)] = current
      pending = nil
    elseif current and not pending then
      pending = line
    elseif current then
      local file, number = line:match "^(.-):(%d+)"
      table.insert(current, 1, location(pending, file, tonumber(number)))
      pending = nil
    end
  end
  return resolved
end

-- Resolves link-relative addresses in one binary, returning relative address ->
-- frames, outermost first. One process per binary: spawning per address would
-- reload the debug info thousands of times.
local function symbolize(binary, relative, cache_dir)
  local base = platform.image_base(binary)
  local addresses = {}
  for _, address in ipairs(relative) do
    addresses[#addresses + 1] = ("0x%x"):format(address + base)
  end

  local resolved
  local llvm = platform.find "llvm-symbolizer"
  if llvm then
    resolved = llvm_lines(llvm, binary, platform.prepare_symbols(binary, cache_dir), addresses)
  elseif vim.fn.executable "addr2line" == 1 then
    resolved = addr2line_lines("addr2line", binary, addresses)
  else
    vim.notify("no symbolizer -- " .. platform.install_hint "llvm-symbolizer", vim.log.levels.WARN)
    return {}
  end

  local by_relative = {}
  for _, address in ipairs(relative) do
    by_relative[address] = resolved[address + base]
  end
  return by_relative
end

-- --- samply --------------------------------------------------------------------

local function add_trace(traces, event, count, frames)
  if count > 0 and #frames > 0 then
    traces[event] = traces[event] or {}
    table.insert(traces[event], { count = count, frames = frames })
  end
end

-- Stack table rows are linked to their callers through `prefix`, and neighbouring
-- samples share most of a chain, so the walk is memoised on the row.
local function frames_of(thread, row, memo, frame_at)
  if row == nil or row == NIL then
    return {}
  end
  if memo[row] then
    return memo[row]
  end

  local table_ = thread.stackTable
  local frames = vim.list_extend({}, frames_of(thread, table_.prefix[row + 1], memo, frame_at))
  vim.list_extend(frames, frame_at(table_.frame[row + 1]))
  memo[row] = frames
  return frames
end

-- A samply profile (.json.gz). It stores bare addresses, with symbolication left
-- to its web UI, so the lines are resolved here against the recorded binaries.
function M.samply(path, cache_dir)
  local out = vim.system({ "gunzip", "-c", path }, { text = false }):wait()
  if out.code ~= 0 then
    return nil, "could not read " .. path
  end
  local profile = vim.json.decode(out.stdout)

  -- Pass one: which addresses each binary needs. Library paths are absolute
  -- because recordings launch absolute paths.
  local wanted = {}
  local function library_of(thread, frame)
    local resource = thread.funcTable.resource[thread.frameTable.func[frame + 1] + 1]
    if resource == nil or resource == NIL or resource < 0 then
      return nil
    end
    local lib = thread.resourceTable.lib[resource + 1]
    if lib == nil or lib == NIL then
      return nil
    end
    return profile.libs[lib + 1]
  end

  for _, thread in ipairs(profile.threads) do
    for frame = 0, thread.frameTable.length - 1 do
      local lib = library_of(thread, frame)
      if lib and lib.path and not platform.is_system_library(lib.path) and vim.uv.fs_stat(lib.path) then
        wanted[lib.path] = wanted[lib.path] or { seen = {}, list = {} }
        local address = thread.frameTable.address[frame + 1]
        if address ~= NIL and address >= 0 and not wanted[lib.path].seen[address] then
          wanted[lib.path].seen[address] = true
          table.insert(wanted[lib.path].list, address)
        end
      end
    end
  end

  local symbols, stale = {}, nil
  local recorded = vim.uv.fs_stat(path)
  for binary, want in pairs(wanted) do
    symbols[binary] = symbolize(binary, want.list, cache_dir)
    local built = vim.uv.fs_stat(binary)
    if built and recorded and built.mtime.sec > recorded.mtime.sec then
      stale = binary
    end
  end

  -- Pass two: fold samples into one trace per distinct stack. Samples whose thread
  -- used no CPU were blocked, so they count toward wall time alone.
  local traces = {}
  for _, thread in ipairs(profile.threads) do
    local memo, frame_memo = {}, {}

    local function frame_at(frame)
      if frame_memo[frame] then
        return frame_memo[frame]
      end
      local lib = library_of(thread, frame)
      local found = lib and symbols[lib.path] and symbols[lib.path][thread.frameTable.address[frame + 1]]
      local frames = found and #found > 0 and found or { { symbol = lib and lib.name or "?" } }
      frame_memo[frame] = frames
      return frames
    end

    local samples = thread.samples
    local cpu, wall = {}, {}
    for i = 1, samples.length do
      local stack = samples.stack[i]
      if stack ~= NIL then
        local weight = samples.weight and samples.weight[i] or 1
        wall[stack] = (wall[stack] or 0) + weight
        local delta = samples.threadCPUDelta and samples.threadCPUDelta[i]
        if delta == nil or delta == NIL or delta > 0 then
          cpu[stack] = (cpu[stack] or 0) + weight
        end
      end
    end

    for stack, count in pairs(wall) do
      local frames = frames_of(thread, stack, memo, frame_at)
      add_trace(traces, "wall time", count, frames)
      add_trace(traces, "cpu time", cpu[stack] or 0, frames)
    end
  end

  return traces, nil, stale
end

-- --- py-spy --------------------------------------------------------------------

-- `--format raw` is folded stacks, root first: `func (file.py:12);... count`. Paths
-- are absolute because recordings pass --full-filenames.
function M.pyspy(path)
  local text = read_file(path)
  if not text then
    return nil, "could not read " .. path
  end

  local traces = {}
  for line in text:gmatch "[^\n]+" do
    local stack, count = line:match "^(.*) (%d+)$"
    if stack then
      local frames = {}
      for frame in stack:gmatch "[^;]+" do
        local symbol, file, number = frame:match "^(.-) %((.+):(%d+)%)$"
        frames[#frames + 1] = symbol and location(symbol, file, tonumber(number)) or { symbol = frame }
      end
      add_trace(traces, "samples", tonumber(count), frames)
    end
  end
  return traces
end

-- --- xctrace -------------------------------------------------------------------

local entities = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }

local function unescape(text)
  return (text:gsub("&(%a+);", entities))
end

-- A parser for the subset `xctrace export` writes: elements, attributes, text.
-- Nothing else in the config needs XML, so this is cheaper than a dependency, and
-- it keeps the macOS and Linux paths both free of Python.
local function parse_xml(text)
  local root = { children = {} }
  local stack = { root }
  local position = 1

  while true do
    local open, close = text:find("<[^>]*>", position)
    if not open then
      break
    end

    local parent = stack[#stack]
    local content = text:sub(position, open - 1)
    if content:find "%S" then
      parent.text = (parent.text or "") .. unescape(content)
    end

    local tag = text:sub(open + 1, close - 1)
    local first = tag:sub(1, 1)
    if first == "/" then
      stack[#stack] = nil
    elseif first ~= "?" and first ~= "!" then
      local self_closing = tag:sub(-1) == "/"
      local name = tag:match "^[%w%-_:]+"
      local node = { name = name, attrs = {}, children = {} }
      for key, value in tag:gmatch '([%w%-_:]+)="([^"]*)"' do
        node.attrs[key] = unescape(value)
      end
      for key, value in tag:gmatch "([%w%-_:]+)='([^']*)'" do
        node.attrs[key] = unescape(value)
      end
      table.insert(parent.children, node)
      if not self_closing then
        stack[#stack + 1] = node
      end
    end
    position = close + 1
  end

  return root
end

-- xctrace writes each distinct value once with an `id` and refers back to it with
-- `ref` afterwards, across rows as well as within one.
local function index_ids(node, ids)
  if node.attrs and node.attrs.id then
    ids[node.attrs.id] = node
  end
  for _, child in ipairs(node.children) do
    index_ids(child, ids)
  end
end

local function find_rows(node, rows)
  for _, child in ipairs(node.children) do
    if child.name == "row" then
      rows[#rows + 1] = child
    else
      find_rows(child, rows)
    end
  end
  return rows
end

local function load_table(trace, schema)
  local xpath = ('/trace-toc/run[@number="1"]/data/table[@schema="%s"]'):format(schema)
  local out = vim.system({ "xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath }, { text = true }):wait()
  if out.code ~= 0 then
    return nil
  end

  local root, ids = parse_xml(out.stdout), {}
  index_ids(root, ids)

  local function resolve(node)
    return node.attrs.ref and ids[node.attrs.ref] or node
  end
  return find_rows(root, {}), resolve
end

local function child_named(node, name)
  for _, child in ipairs(node.children) do
    if child.name == name then
      return child
    end
  end
end

-- Time Profiler rows already carry source locations for binaries with debug info,
-- so unlike samply these need no symbolizer. Backtraces are leaf first.
local function backtrace_frames(backtrace, resolve)
  local frames = {}
  for _, entry in ipairs(backtrace.children) do
    local frame = resolve(entry)
    if frame.name == "frame" then
      local source = child_named(frame, "source")
      local path = source and child_named(source, "path")
      local file = path and resolve(path).text
      local line = source and tonumber(source.attrs.line)
      table.insert(frames, 1, location(frame.attrs.name, file, line))
    end
  end
  return frames
end

local function thread_id(row, resolve)
  for _, cell in ipairs(row.children) do
    local node = resolve(cell)
    if node.name == "thread" then
      local tid = child_named(node, "tid")
      return tid and resolve(tid).text
    end
  end
end

local function sample_time(row, resolve)
  return tonumber(resolve(row.children[1]).text)
end

local function count_stacks(traces, event, counts, stacks)
  for key, count in pairs(counts) do
    add_trace(traces, event, count, stacks[key])
  end
end

local function nearest_sample(samples, time)
  local low, high = 1, #samples
  while low < high do
    local middle = math.floor((low + high) / 2)
    if samples[middle].time < time then
      low = middle + 1
    else
      high = middle
    end
  end

  local nearest = samples[low]
  if low > 1 and math.abs(samples[low - 1].time - time) < math.abs(nearest.time - time) then
    nearest = samples[low - 1]
  end
  return nearest
end

-- A CPU Counters recording reports, per thread and per ~1 ms slice, how the
-- pipeline's time split between useful work and each kind of bottleneck. Each slice
-- is charged to the Time Profiler stack nearest its middle, in microseconds, so one
-- event per metric answers "where is this bottleneck being paid for". Slices and
-- stacks are about 1 ms apart, so this holds per function and is approximate per
-- line, which the event name says.
--
-- These metrics and not the PMI samples that the template can also record: tested
-- against a program with a known answer, PMI rows arrive at a rate that follows time
-- rather than the event, and their stack column exports empty.
local function bottlenecks(path, by_thread, stacks, traces)
  local rows, resolve = load_table(path, "MetricTableForThread")
  if not rows or #rows == 0 then
    return
  end

  for _, samples in pairs(by_thread) do
    table.sort(samples, function(a, b)
      return a.time < b.time
    end)
  end

  local totals = {}
  for _, row in ipairs(rows) do
    -- Columns: start, duration, thread, process, sum, average, name, display name.
    local cells = row.children
    local average = resolve(cells[6])
    local samples = by_thread[thread_id(row, resolve) or ""]

    if samples and average.name ~= "sentinel" then
      local start, duration = tonumber(resolve(cells[1]).text), tonumber(resolve(cells[2]).text)
      local nearest = nearest_sample(samples, start + duration / 2)
      local metric = resolve(cells[8]).text .. " (approx)"

      totals[metric] = totals[metric] or {}
      totals[metric][nearest.key] = (totals[metric][nearest.key] or 0) + tonumber(average.text) * duration / 1000
    end
  end

  for metric, counts in pairs(totals) do
    for key, microseconds in pairs(counts) do
      add_trace(traces, metric, math.floor(microseconds + 0.5), stacks[key])
    end
  end
end

function M.xctrace(path)
  local rows, resolve = load_table(path, "time-profile")
  if not rows then
    return nil, "xctrace could not export " .. path
  end

  local traces, counts, stacks = {}, {}, {}
  local by_thread = {}

  for _, row in ipairs(rows) do
    local backtrace
    for _, cell in ipairs(row.children) do
      local node = resolve(cell)
      if node.name == "tagged-backtrace" or node.name == "backtrace" then
        backtrace = node
      end
    end

    if backtrace then
      local key = backtrace.attrs.id or tostring(backtrace)
      stacks[key] = stacks[key] or backtrace_frames(backtrace, resolve)
      counts[key] = (counts[key] or 0) + 1

      local tid = thread_id(row, resolve)
      if tid then
        by_thread[tid] = by_thread[tid] or {}
        table.insert(by_thread[tid], { time = sample_time(row, resolve), key = key })
      end
    end
  end

  count_stacks(traces, "time", counts, stacks)
  bottlenecks(path, by_thread, stacks, traces)
  return traces
end

-- --- perf ----------------------------------------------------------------------

-- perfanno reads this format itself. Its loader is called directly because the
-- :PerfLoadCallGraph command would prompt for the path.
function M.perf(path)
  return require("perfanno.parse_perf").perf_callgraph(path)
end

-- --- build time ----------------------------------------------------------------

-- Per-file -ftime-trace output, merged into totals across translation units. Each
-- header counts every time it is parsed, which is the cost worth seeing: a header
-- that is cheap once and included everywhere is the usual finding.
function M.time_trace(files)
  local groups = { Source = {}, InstantiateClass = {}, InstantiateFunction = {} }
  local frontend, backend = 0, 0

  for _, path in ipairs(files) do
    local ok, trace = pcall(vim.json.decode, read_file(path) or "")
    if ok and type(trace) == "table" and trace.traceEvents then
      -- Headers are written as begin and end events, unlike everything else here
      -- which has a duration. They nest as includes do, so a stack pairs them, and
      -- a header's time includes what it pulled in.
      local open = {}
      local function add(group, detail, time)
        local entry = group[detail] or { time = 0, count = 0 }
        entry.time = entry.time + time
        entry.count = entry.count + 1
        group[detail] = entry
      end

      for _, event in ipairs(trace.traceEvents) do
        local group = groups[event.name]
        local detail = type(event.args) == "table" and event.args.detail
        if event.ph == "b" and event.name == "Source" then
          open[#open + 1] = { detail = detail, start = event.ts }
        elseif event.ph == "e" and event.name == "Source" then
          local begun = table.remove(open)
          if begun and type(begun.detail) == "string" then
            add(group, begun.detail, event.ts - begun.start)
          end
        elseif group and type(detail) == "string" then
          add(group, detail, event.dur or 0)
        elseif event.name == "Total Frontend" then
          frontend = frontend + (event.dur or 0)
        elseif event.name == "Total Backend" then
          backend = backend + (event.dur or 0)
        end
      end
    end
  end

  return { groups = groups, frontend = frontend, backend = backend, files = #files }
end

return M
