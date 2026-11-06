-- Everything that differs between macOS and Linux. The rest of lua/profiling/
-- asks this file what to run and never looks at the OS itself, so adding a
-- platform or swapping a tool is a change in one place.
local M = {}

M.is_mac = vim.uv.os_uname().sysname == "Darwin"

-- samply, py-spy and inferno come from `cargo install` on Ubuntu, and inferno does on
-- macOS. That directory reaches PATH only through a shell profile, which a desktop
-- launcher skips, and every job started here inherits this.
local cargo_bin = vim.fs.joinpath(vim.uv.os_homedir(), ".cargo", "bin")
if vim.uv.fs_stat(cargo_bin) and not vim.env.PATH:find(cargo_bin, 1, true) then
  vim.env.PATH = vim.env.PATH .. ":" .. cargo_bin
end

local function run(argv)
  local ok, obj = pcall(function()
    return vim.system(argv, { text = true }):wait()
  end)
  return ok and obj or { code = 1, stdout = "", stderr = "" }
end

-- How to get each tool, shown when it is missing. Ubuntu packages neither samply,
-- py-spy nor any flamegraph renderer, and cargo supplies all three.
local install = {
  samply = { mac = "brew install samply", linux = "cargo install --locked samply" },
  ["py-spy"] = { mac = "brew install py-spy", linux = "cargo install --locked py-spy" },
  hyperfine = { mac = "brew install hyperfine", linux = "sudo apt install hyperfine" },
  perf = { linux = "sudo apt install linux-tools-common linux-tools-$(uname -r)" },
  heaptrack = { linux = "sudo apt install heaptrack heaptrack-gui" },
  valgrind = { linux = "sudo apt install valgrind" },
  ["llvm-symbolizer"] = { mac = "brew install llvm", linux = "sudo apt install llvm" },
  xctrace = { mac = "install Xcode, then: sudo xcode-select -s /Applications/Xcode.app" },
  ["inferno-flamegraph"] = { mac = "cargo install --locked inferno", linux = "cargo install --locked inferno" },
}

function M.install_hint(tool)
  local hint = install[tool]
  return hint and hint[M.is_mac and "mac" or "linux"] or ("install " .. tool)
end

-- Ubuntu's llvm packages install versioned names such as llvm-symbolizer-20, with
-- the bare name only sometimes present, so a PATH check alone misses them. Natural
-- sort, so that -9 does not beat -20.
local function versioned(name)
  local found = vim.fn.glob("/usr/bin/" .. name .. "-[0-9]*", false, true)
  table.sort(found, function(a, b)
    return (tonumber(a:match "%-(%d+)$") or 0) > (tonumber(b:match "%-(%d+)$") or 0)
  end)
  return found[1]
end

-- Homebrew LLVM first, the same preference lua/asm.lua and
-- lua/configs/lspconfig.lua give their tools.
function M.find(name)
  if M.is_mac then
    local brew = "/opt/homebrew/opt/llvm/bin/" .. name
    if vim.uv.fs_stat(brew) then
      return brew
    end
  end
  if vim.fn.executable(name) == 1 then
    return vim.fn.exepath(name)
  end
  return versioned(name)
end

-- The tool's path, or nil after telling the user how to install it.
function M.require_tool(name)
  local path = M.find(name)
  if not path then
    vim.notify(name .. " is not installed -- " .. M.install_hint(name), vim.log.levels.WARN, { title = "Profiling" })
  end
  return path
end

-- A shim for xctrace exists wherever the Command Line Tools do, so being on PATH
-- proves nothing: only running it does.
function M.has_xctrace()
  return M.is_mac and run({ "xcrun", "xctrace", "version" }).code == 0
end

function M.has_display()
  if M.is_mac then
    return vim.env.SSH_CONNECTION == nil
  end
  return (vim.env.DISPLAY or vim.env.WAYLAND_DISPLAY) ~= nil
end

-- samply and perf are both built on perf_event_open, which Ubuntu restricts by
-- default. The value is read and reported, and never changed: lowering it is a
-- security decision for whoever owns the machine.
function M.paranoid_level()
  if M.is_mac then
    return nil
  end
  local file = io.open "/proc/sys/kernel/perf_event_paranoid"
  if not file then
    return nil
  end
  local level = tonumber(file:read "*l")
  file:close()
  return level
end

M.paranoid_fix = "sudo sysctl kernel.perf_event_paranoid=1"

-- nil when sampling may go ahead, otherwise what is stopping it and the fix.
function M.sampling_blocked()
  local level = M.paranoid_level()
  if level and level > 1 then
    return ("kernel.perf_event_paranoid is %d, which blocks sampling -- run: %s"):format(level, M.paranoid_fix)
  end
end

-- Attaching on macOS goes through task_for_pid, which samply can only reach once it
-- has signed itself. On Linux it uses perf_event_open, so sampling_blocked() already
-- covers it, and Yama's ptrace_scope does not apply.
function M.attach_warning()
  if M.is_mac then
    return "attaching needs a one-off `samply setup`, and again after each samply update"
  end
end

-- Virtual machines commonly expose no PMU. perf reports that per event in its
-- output and still exits zero, so the exit code cannot be trusted here.
function M.has_hardware_counters()
  if M.is_mac then
    return true
  end
  local perf = M.find "perf"
  if not perf then
    return false
  end
  local result = run { perf, "stat", "-x,", "-e", "cycles", "true" }
  return result.code == 0 and not (result.stderr or ""):find("not supported", 1, true)
end

-- `perf` on Ubuntu is a wrapper that refuses to run unless the linux-tools package
-- for the exact running kernel is installed, which a kernel update breaks.
function M.perf_works()
  local perf = M.find "perf"
  return perf ~= nil and run({ perf, "--version" }).code == 0
end

-- The address the file's first segment links at. Profilers record addresses
-- relative to it and symbolizers want link-time addresses, so this is what goes
-- back on. 0x100000000 for a Mach-O executable, 0 for a PIE, 0x400000 for a
-- non-PIE ELF, and reading it means none of those has to be assumed.
function M.image_base(path)
  if M.is_mac then
    local out = run({ "otool", "-l", path }).stdout or ""
    local vmaddr = out:match "segname __TEXT%s+vmaddr 0x(%x+)"
    return vmaddr and tonumber(vmaddr, 16) or 0
  end
  local out = run({ "readelf", "-lW", path }).stdout or ""
  local vaddr = out:match "LOAD%s+0x%x+%s+0x(%x+)"
  return vaddr and tonumber(vaddr, 16) or 0
end

-- System libraries have no line tables to find. On macOS most of them are not
-- even files any more, as they live in the dyld shared cache.
function M.is_system_library(path)
  return path:find "^/usr/lib" ~= nil or path:find "^/lib" ~= nil or path:find "^/System" ~= nil
end

-- Mach-O executables keep their DWARF in the .o files, which symbolizers cannot
-- follow, so it is gathered into a dSYM first. ELF needs nothing. Written under
-- .profiles so that the build tree stays as the build left it.
function M.prepare_symbols(binary, cache_dir)
  if not M.is_mac then
    return nil
  end
  local dsym = vim.fs.joinpath(cache_dir, vim.fs.basename(binary) .. ".dSYM")
  local built, made = vim.uv.fs_stat(binary), vim.uv.fs_stat(dsym)
  if built and (not made or made.mtime.sec < built.mtime.sec) then
    vim.fn.mkdir(cache_dir, "p")
    run { "dsymutil", binary, "-o", dsym }
  end
  return vim.uv.fs_stat(dsym) and dsym or nil
end

-- Deep recordings: what each OS measures beyond plain sampling, for the picker
-- behind <leader>PR. `annotate` means the result can be shown beside the source. The
-- rest are read in Instruments.
local mac_recordings = {
  { label = "Time Profiler", template = "Time Profiler", annotate = true },
  { label = "CPU Bottlenecks (hardware counters)", template = "CPU Counters", annotate = true },
  { label = "Allocations (Instruments)", template = "Allocations" },
  { label = "Leaks (Instruments)", template = "Leaks" },
  { label = "System Trace (Instruments)", template = "System Trace" },
}

local linux_recordings = {
  { label = "Cycles and cache misses", events = "cycles,cache-misses", counters = true },
  { label = "Branch mispredictions", events = "cycles,branch-misses", counters = true },
  { label = "CPU clock (no hardware counters needed)", events = "cpu-clock" },
}

function M.deep_recordings()
  return M.is_mac and mac_recordings or linux_recordings
end

-- The command that opens a deep recording. Ubuntu 26.04 does not package hotspot,
-- so it is used when someone has built it, and otherwise samply imports the
-- perf.data into the same Firefox Profiler UI as every other recording.
function M.gui_argv(file)
  if M.is_mac then
    return { "open", file }
  end
  if file:find("heaptrack", 1, true) then
    return { "heaptrack_gui", file }
  end
  if M.find "hotspot" then
    return { "hotspot", file }
  end
  return { "samply", "import", file }
end

-- An ASan build reports leaks itself on Linux, and on macOS it conflicts with
-- `leaks`, which walks the same heap the sanitizer has replaced.
function M.leak_check(binary, args)
  local asan = binary:find("/asan/", 1, true) ~= nil

  if M.is_mac then
    if asan then
      return nil, "`leaks` cannot inspect an ASan build -- switch to the profile or debug preset"
    end
    -- --quiet drops the process header and the long list of loaded images, which
    -- would otherwise push the leak report out of the terminal split.
    local argv = { "leaks", "--quiet", "--atExit", "--", binary }
    vim.list_extend(argv, args)
    return { argv = argv, env = { MallocStackLogging = "1" } }
  end

  if asan then
    local argv = { binary }
    vim.list_extend(argv, args)
    return { argv = argv, env = { ASAN_OPTIONS = "detect_leaks=1" } }
  end

  if not M.require_tool "valgrind" then
    return nil
  end
  local argv = { "valgrind", "--leak-check=full", "--show-leak-kinds=definite", "--", binary }
  vim.list_extend(argv, args)
  return { argv = argv }
end

return M
