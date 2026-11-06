-- Record a profile from inside nvim and read the cost beside the source. samply is
-- the default sampler on macOS and Linux alike, so there is one recording path, one
-- converter and one flamegraph UI. Each OS adds a deeper backend for what sampling
-- cannot see: xctrace on macOS and perf on Linux, both behind <leader>PR.
--
-- lua/profiling/platform.lua holds every OS difference, lua/profiling/convert.lua
-- turns each format into perfanno's traces, and the keymaps are on the spec in
-- lua/plugins/profiling.lua.
--
-- Recordings go to .profiles/ at the project root, and a project should gitignore it.
local platform = require "profiling.platform"
local convert = require "profiling.convert"

local M = {}

local TITLE = { title = "Profiling" }

local function info(message)
  vim.notify(message, vim.log.levels.INFO, TITLE)
end

local function warn(message)
  vim.notify(message, vim.log.levels.WARN, TITLE)
end

local function root()
  return vim.fs.root(0, { "CMakePresets.json", "Cargo.toml", "pyproject.toml", ".git" }) or vim.uv.cwd()
end

local function profiles_dir()
  local dir = vim.fs.joinpath(root(), ".profiles")
  vim.fn.mkdir(dir, "p")
  return dir
end

local function new_file(name, extension)
  return vim.fs.joinpath(profiles_dir(), ("%s-%s.%s"):format(name, os.date "%Y%m%d-%H%M%S", extension))
end

-- Runs in a terminal split rather than a background job: the program's output is
-- worth seeing, py-spy on macOS needs a sudo password typed, and a stdin-reading
-- target needs its terminal. `prepare` is a build command to run first.
local function run_in_terminal(job, on_success)
  -- exec, so that the job's pid is the tool itself and a signal reaches it.
  local command = "exec " .. vim.iter(job.argv):map(vim.fn.shellescape):join " "
  if job.prepare then
    command = vim.iter(job.prepare):map(vim.fn.shellescape):join " " .. " && " .. command
  end

  local origin = vim.api.nvim_get_current_win()
  vim.cmd "botright 12new"
  local id = vim.fn.jobstart({ "sh", "-c", command }, {
    term = true,
    cwd = job.cwd or root(),
    env = job.env,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 and not job.ignore_exit then
          warn(("%s exited with %d -- see the terminal"):format(job.argv[1], code))
          return
        end
        if vim.api.nvim_win_is_valid(origin) then
          vim.api.nvim_set_current_win(origin)
        end
        if on_success then
          on_success()
        end
      end)
    end,
  })
  vim.cmd.startinsert()
  return id
end

-- --- what to profile -----------------------------------------------------------

local function cmake_target()
  local cmake = require "cmake-tools"
  if not cmake.is_cmake_project() then
    return nil
  end

  local name = cmake.get_launch_target()
  local binary = name and cmake.get_launch_target_path()
  if not binary then
    return nil, "no launch target -- pick one with <leader>cmR and build it first"
  end

  if cmake.get_build_type() == "Debug" then
    warn "profiling a Debug build measures unoptimised code -- <leader>cmp selects the Profile preset"
  end

  return {
    kind = "native",
    name = name,
    binary = binary,
    args = cmake.get_launch_args() or {},
    prepare = { "cmake", "--build", cmake.get_config():build_directory_path(), "--target", name },
  }
end

-- CARGO_PROFILE_RELEASE_DEBUG adds line tables to a release build without editing
-- the project's Cargo.toml.
local function cargo_target()
  local manifest = vim.fs.find("Cargo.toml", { upward = true, path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)) })[1]
  if not manifest then
    return nil
  end

  local out = vim
    .system({ "cargo", "metadata", "--no-deps", "--format-version", "1" }, {
      cwd = vim.fs.dirname(manifest),
      text = true,
    })
    :wait()
  if out.code ~= 0 then
    return nil, "cargo metadata failed: " .. (out.stderr or "")
  end

  local metadata = vim.json.decode(out.stdout)
  for _, package in ipairs(metadata.packages) do
    for _, target in ipairs(package.targets) do
      if vim.tbl_contains(target.kind, "bin") then
        return {
          kind = "native",
          name = target.name,
          binary = vim.fs.joinpath(metadata.target_directory, "release", target.name),
          args = {},
          cwd = vim.fs.dirname(manifest),
          env = { CARGO_PROFILE_RELEASE_DEBUG = "true" },
          prepare = { "cargo", "build", "--release", "--bin", target.name },
        }
      end
    end
  end
  return nil, "no binary target in " .. manifest
end

local function python_target()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    return nil, "save the script first"
  end
  return {
    kind = "python",
    name = vim.fn.fnamemodify(file, ":t:r"),
    python = require("python").python(0),
    script = file,
  }
end

local function current_target()
  local filetype = vim.bo.filetype
  if filetype == "python" then
    return python_target()
  end
  if filetype == "rust" then
    return cargo_target()
  end

  local target, problem = cmake_target()
  if target or problem then
    return target, problem
  end

  target, problem = cargo_target()
  if target or problem then
    return target, problem
  end
  return nil, "nothing to profile here: no CMake launch target, Cargo.toml or Python buffer"
end

local function with_target(callback)
  local target, problem = current_target()
  if not target then
    warn(problem)
    return
  end
  callback(target)
end

-- --- loading -------------------------------------------------------------------

local function total(traces)
  local sum = 0
  for _, trace in ipairs(traces) do
    sum = sum + trace.count
  end
  return sum
end

-- The event shown first. A counter recording exists to show a bottleneck, so the
-- largest one wins over plain time.
local function preferred_event(traces)
  local worst, worst_total = nil, 0
  for event, list in pairs(traces) do
    if event:find("Bottleneck", 1, true) and total(list) > worst_total then
      worst, worst_total = event, total(list)
    end
  end
  if worst then
    return worst
  end

  for _, event in ipairs { "cpu time", "time", "samples" } do
    if traces[event] then
      return event
    end
  end
  return next(traces)
end

local function show(traces, label)
  if not traces or vim.tbl_isempty(traces) then
    warn("no samples in " .. label)
    return
  end

  local perfanno = require "perfanno"
  perfanno.load_traces(traces)
  require("perfanno.config").selected_event = preferred_event(traces)
  perfanno.annotate()
  info(("%s loaded, showing %s"):format(vim.fn.fnamemodify(label, ":t"), preferred_event(traces)))
end

function M.load(path)
  local traces, problem, stale
  if path:match "%.json%.gz$" then
    traces, problem, stale = convert.samply(path, vim.fs.joinpath(vim.fs.dirname(path), "symbols"))
  elseif path:match "%.trace$" then
    traces, problem = convert.xctrace(path)
  elseif path:match "%.perf$" then
    traces = convert.perf(path)
  elseif path:match "%.pyspy$" then
    traces, problem = convert.pyspy(path)
  else
    problem = "no reader for " .. path
  end

  if problem then
    warn(problem)
    return
  end
  if stale then
    warn(stale .. " was rebuilt after this recording, so lines may be off")
  end
  show(traces, path)
end

local function recordings()
  local files = vim.fn.glob(vim.fs.joinpath(root(), ".profiles", "*"), false, true)
  files = vim.tbl_filter(function(path)
    return path:match "%.json%.gz$" or path:match "%.trace$" or path:match "%.perf$" or path:match "%.pyspy$"
  end, files)

  local stamp = {}
  for _, path in ipairs(files) do
    stamp[path] = vim.fn.getftime(path)
  end
  table.sort(files, function(a, b)
    return stamp[a] > stamp[b]
  end)
  return files
end

function M.pick()
  local files = recordings()
  if #files == 0 then
    warn "no recordings in .profiles/ -- <leader>Pr makes one"
    return
  end

  vim.ui.select(files, {
    prompt = "Load recording",
    format_item = function(path)
      return vim.fs.basename(path)
    end,
  }, function(path)
    if path then
      M.load(path)
    end
  end)
end

local function latest(pattern)
  for _, path in ipairs(recordings()) do
    if path:match(pattern) then
      return path
    end
  end
end

-- --- recording -----------------------------------------------------------------

local function pyspy_job(target)
  local output = new_file(target.name, "pyspy")
  local argv = {
    "py-spy",
    "record",
    "--format",
    "raw",
    "--full-filenames",
    "--output",
    output,
    "--",
    target.python,
    target.script,
  }
  -- macOS forbids inspecting another process without root, even a child.
  if platform.is_mac then
    table.insert(argv, 1, "sudo")
  end
  return { argv = argv }, output
end

local function samply_job(target)
  local output = new_file(target.name, "json.gz")
  local argv = { "samply", "record", "--save-only", "--output", output, "--", target.binary }
  vim.list_extend(argv, target.args)
  return { argv = argv, prepare = target.prepare, env = target.env, cwd = target.cwd }, output
end

-- <leader>Pr: sample the current target and annotate the source when it exits.
function M.record()
  with_target(function(target)
    local job, output
    if target.kind == "python" then
      if not platform.require_tool "py-spy" then
        return
      end
      job, output = pyspy_job(target)
    else
      local blocked = platform.sampling_blocked()
      if blocked then
        warn(blocked)
        return
      end
      if not platform.require_tool "samply" then
        return
      end
      job, output = samply_job(target)
    end

    run_in_terminal(job, function()
      M.load(output)
    end)
  end)
end

local function record_xctrace(target, recording)
  local output = new_file(target.name, "trace")
  local argv = { "xcrun", "xctrace", "record", "--template", recording.template, "--output", output, "--no-prompt" }
  vim.list_extend(argv, { "--launch", "--", target.binary })
  vim.list_extend(argv, target.args)

  local job = { argv = argv, prepare = target.prepare, env = target.env, cwd = target.cwd }
  run_in_terminal(job, function()
    if recording.annotate then
      M.load(output)
    else
      vim.system(platform.gui_argv(output))
    end
  end)
end

local function record_perf(target, recording)
  if not platform.perf_works() then
    warn("perf does not run for this kernel -- " .. platform.install_hint "perf")
    return
  end

  local blocked = platform.sampling_blocked()
  if blocked then
    warn(blocked)
    return
  end

  local events = recording.events
  if recording.counters and not platform.has_hardware_counters() then
    warn "no hardware counters here, which is usual in a VM -- recording cpu-clock instead"
    events = "cpu-clock"
  end

  local output = new_file(target.name, "perf")
  local argv =
    { platform.find "perf", "record", "--call-graph", "dwarf", "-e", events, "-o", output, "--", target.binary }
  vim.list_extend(argv, target.args)

  run_in_terminal({ argv = argv, prepare = target.prepare, env = target.env, cwd = target.cwd }, function()
    M.load(output)
  end)
end

-- <leader>PR: a deeper recording, chosen from what this OS offers.
function M.record_deep()
  if platform.is_mac and not platform.has_xctrace() then
    warn("xctrace is unavailable -- " .. platform.install_hint "xctrace")
    return
  end

  with_target(function(target)
    if target.kind ~= "native" then
      warn "deep recordings are for native binaries -- <leader>Pr samples Python"
      return
    end

    vim.ui.select(platform.deep_recordings(), {
      prompt = "Record",
      format_item = function(recording)
        return recording.label
      end,
    }, function(recording)
      if recording then
        local record = platform.is_mac and record_xctrace or record_perf
        record(target, recording)
      end
    end)
  end)
end

-- <leader>Pa: attach to something already running, for a fixed length of time.
function M.attach()
  local blocked = platform.sampling_blocked()
  if blocked then
    warn(blocked)
    return
  end
  if not platform.require_tool "samply" then
    return
  end

  local note = platform.attach_warning()
  if note then
    info(note)
  end

  local out = vim.system({ "ps", "-U", vim.env.USER or "", "-o", "pid=,comm=" }, { text = true }):wait()
  local processes = vim.tbl_filter(function(line)
    return line:find "%S" ~= nil
  end, vim.split(out.stdout or "", "\n"))

  vim.ui.select(processes, { prompt = "Attach to" }, function(line)
    local pid = line and line:match "(%d+)"
    if not pid then
      return
    end

    vim.ui.input({ prompt = "Seconds to record: ", default = "10" }, function(seconds)
      if not tonumber(seconds) then
        return
      end
      local output = new_file("pid" .. pid, "json.gz")
      -- Stopped with SIGINT, as Ctrl-C would be, rather than with --duration: samply
      -- 0.13 ignores that on macOS when attaching and then never exits.
      local argv = { "samply", "record", "--save-only", "--output", output, "--pid", pid }
      local job = run_in_terminal({ argv = argv, ignore_exit = true }, function()
        M.load(output)
      end)
      vim.defer_fn(function()
        vim.uv.kill(vim.fn.jobpid(job), "sigint")
      end, tonumber(seconds) * 1000)
    end)
  end)
end

-- --- viewers -------------------------------------------------------------------

local viewer

-- samply serves symbols to the browser from a local server for as long as the page
-- is in use, so this keeps running until the key is pressed again. `load` reads its
-- own format and `import` reads perf.data, which is what puts perf recordings in the
-- same UI.
local function serve_samply(path)
  local args = { "samply", path:match "%.perf$" and "import" or "load", path }
  local headless = not platform.has_display()
  if headless then
    table.insert(args, "--no-open")
  end

  viewer = vim.fn.jobstart(args, {
    on_exit = function()
      viewer = nil
    end,
  })

  if headless then
    info(
      ("no display here. From your machine: ssh -L 3000:127.0.0.1:3000 %s\nthen open http://127.0.0.1:3000"):format(
        vim.uv.os_gethostname()
      )
    )
  else
    info "flamegraph opening in the browser -- <leader>Pv again stops the server"
  end
end

-- Python has no samply profile, so its folded stacks become a standalone SVG.
local function render_svg(path)
  local renderer = platform.find "inferno-flamegraph" or platform.find "flamegraph.pl"
  if not renderer then
    platform.require_tool "inferno-flamegraph"
    return
  end

  local svg = path:gsub("%.pyspy$", ".svg")
  local out = vim.system({ renderer, path }, { text = true }):wait()
  if out.code ~= 0 then
    warn(vim.fs.basename(renderer) .. " failed")
    return
  end
  vim.fn.writefile(vim.split(out.stdout, "\n"), svg)

  if platform.has_display() then
    vim.ui.open(svg)
  else
    info("flamegraph written to " .. svg)
  end
end

-- <leader>Pv: the newest recording, as a flamegraph.
function M.flamegraph()
  if viewer then
    vim.fn.jobstop(viewer)
    info "flamegraph server stopped"
    return
  end

  -- The newest one that has a flamegraph, so that an Instruments trace recorded in
  -- between does not hide it.
  for _, path in ipairs(recordings()) do
    if path:match "%.pyspy$" then
      render_svg(path)
      return
    elseif not path:match "%.trace$" then
      serve_samply(path)
      return
    end
  end
  warn "no flamegraph to show -- <leader>Pr makes one"
end

-- <leader>Pi: the newest deep recording, in Instruments or hotspot.
function M.open_gui()
  if not platform.has_display() then
    warn "no display here -- annotations work, but this one needs a desktop session"
    return
  end

  local path = latest(platform.is_mac and "%.trace$" or "%.perf$")
  if not path then
    warn "no deep recording yet -- <leader>PR makes one"
    return
  end
  vim.system(platform.gui_argv(path), { detach = true })
end

-- --- benchmark -----------------------------------------------------------------

local function baseline_path(target)
  return vim.fs.joinpath(profiles_dir(), "baseline", target.name)
end

-- :ProfileBaseline: keep the current binary as the "before" of a comparison.
function M.save_baseline()
  with_target(function(target)
    if target.kind ~= "native" then
      warn "baselines are for native binaries"
      return
    end
    if not vim.uv.fs_stat(target.binary) then
      warn("nothing to save yet -- build " .. target.name .. " first")
      return
    end

    local path = baseline_path(target)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.uv.fs_copyfile(target.binary, path)
    info(("baseline saved for %s -- change the code and press <leader>Pb"):format(target.name))
  end)
end

-- <leader>Pb: the first press saves a baseline and later ones compare against it,
-- which makes the before-and-after loop one key.
function M.benchmark()
  if not platform.require_tool "hyperfine" then
    return
  end

  with_target(function(target)
    if target.kind ~= "native" then
      warn "hyperfine comparison is for native binaries"
      return
    end

    local baseline = baseline_path(target)
    if not vim.uv.fs_stat(baseline) then
      M.save_baseline()
      return
    end

    local function command(binary)
      return vim.iter({ binary, unpack(target.args) }):map(vim.fn.shellescape):join " "
    end

    run_in_terminal {
      prepare = target.prepare,
      argv = {
        "hyperfine",
        "--warmup",
        "1",
        "--command-name",
        "baseline",
        command(baseline),
        "--command-name",
        "current",
        command(target.binary),
      },
      env = target.env,
      cwd = target.cwd,
    }
  end)
end

-- --- memory --------------------------------------------------------------------

-- <leader>Pm: a leak check. `leaks` exits non-zero when it finds any, and so does
-- a sanitizer, which here means it worked.
function M.leak_check()
  with_target(function(target)
    if target.kind ~= "native" then
      warn "the leak check is for native binaries"
      return
    end

    local job, problem = platform.leak_check(target.binary, target.args)
    if not job then
      if problem then
        warn(problem)
      end
      return
    end
    job.prepare, job.cwd, job.ignore_exit = target.prepare, target.cwd, true
    run_in_terminal(job)
  end)
end

-- <leader>PM: where the heap grows, which a leak checker cannot see because all of
-- it is still reachable.
function M.heap()
  with_target(function(target)
    if target.kind ~= "native" then
      warn "heap profiling is for native binaries"
      return
    end

    if platform.is_mac then
      if not platform.has_xctrace() then
        warn("xctrace is unavailable -- " .. platform.install_hint "xctrace")
        return
      end
      record_xctrace(target, { template = "Allocations" })
      return
    end

    if not platform.require_tool "heaptrack" then
      return
    end

    local output = new_file(target.name .. "-heaptrack", "zst")
    -- --record-only because heaptrack otherwise opens its own GUI, which aborts with
    -- no display and on a desktop would be a second window beside the one below.
    local argv = { "heaptrack", "--record-only", "--output", output:gsub("%.zst$", ""), target.binary }
    vim.list_extend(argv, target.args)
    run_in_terminal({ argv = argv, prepare = target.prepare, cwd = target.cwd }, function()
      if platform.has_display() then
        vim.system(platform.gui_argv(output), { detach = true })
      else
        run_in_terminal { argv = { "heaptrack_print", output } }
      end
    end)
  end)
end

-- --- build time ----------------------------------------------------------------

local function microseconds(value)
  return ("%8.1f ms"):format(value / 1000)
end

local function report_group(lines, heading, group)
  local rows = {}
  for detail, entry in pairs(group) do
    rows[#rows + 1] = { detail = detail, time = entry.time, count = entry.count }
  end
  table.sort(rows, function(a, b)
    return a.time > b.time
  end)

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## " .. heading
  lines[#lines + 1] = ""
  for i = 1, math.min(15, #rows) do
    lines[#lines + 1] = ("%s  x%-4d %s"):format(microseconds(rows[i].time), rows[i].count, rows[i].detail)
  end
end

-- <leader>PB: where compile time went, from the timetrace preset's output.
function M.build_time()
  local files = vim.fn.glob(vim.fs.joinpath(root(), "build", "timetrace", "**", "*.dir", "**", "*.json"), false, true)
  if #files == 0 then
    warn "no -ftime-trace output -- build the Time trace preset first (<leader>cmp, then <leader>cmb)"
    return
  end

  local summary = convert.time_trace(files)
  local lines = {
    ("# Build time across %d translation units"):format(summary.files),
    "",
    "Front end " .. microseconds(summary.frontend),
    "Back end  " .. microseconds(summary.backend),
  }
  report_group(lines, "Headers, by total parse time", summary.groups.Source)
  report_group(lines, "Class templates", summary.groups.InstantiateClass)
  report_group(lines, "Function templates", summary.groups.InstantiateFunction)

  vim.cmd "botright new"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.buftype, vim.bo.bufhidden, vim.bo.filetype = "nofile", "wipe", "markdown"
  vim.bo.modifiable = false
end

return M
