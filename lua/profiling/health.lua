-- :checkhealth profiling. Mostly environment rather than config, which is why a
-- missing piece here gets its fix spelled out: the tools come from the OS, and on
-- Ubuntu the kernel settings matter as much as the packages.
local platform = require "profiling.platform"

local M = {}

local function check_tool(tool, purpose)
  local path = platform.find(tool)
  if path then
    vim.health.ok(("%s: %s"):format(tool, path))
  else
    vim.health.warn(("%s not found (%s)"):format(tool, purpose), platform.install_hint(tool))
  end
end

function M.check()
  vim.health.start "profiling: shared tools"
  check_tool("samply", "<leader>Pr, <leader>Pa, <leader>Pv")
  check_tool("llvm-symbolizer", "source lines for samply recordings")
  check_tool("hyperfine", "<leader>Pb")
  check_tool("py-spy", "<leader>Pr in Python buffers")
  if platform.find "flamegraph.pl" then
    vim.health.ok "flamegraph.pl renders Python recordings"
  else
    check_tool("inferno-flamegraph", "<leader>Pv for Python recordings")
  end

  if platform.is_mac then
    vim.health.start "profiling: macOS"
    if platform.has_xctrace() then
      vim.health.ok "xctrace runs"
    else
      vim.health.warn("xctrace does not run (<leader>PR, <leader>PM)", platform.install_hint "xctrace")
    end
    local devtools = vim.system({ "DevToolsSecurity", "-status" }, { text = true }):wait()
    if (devtools.stdout or ""):find("enabled", 1, true) then
      vim.health.ok "developer mode is on"
    else
      vim.health.info(
        "Allocations and Leaks recordings will ask for an admin password each time",
        "sudo DevToolsSecurity -enable"
      )
    end
    check_tool("leaks", "<leader>Pm")
    check_tool("dsymutil", "source lines for samply recordings")
  else
    vim.health.start "profiling: Linux"
    if platform.perf_works() then
      vim.health.ok "perf runs on this kernel"
    else
      vim.health.warn("perf does not run on this kernel (<leader>PR)", platform.install_hint "perf")
    end

    local level = platform.paranoid_level()
    if level and level > 1 then
      vim.health.warn(("kernel.perf_event_paranoid is %d, which blocks sampling"):format(level), platform.paranoid_fix)
    elseif level then
      vim.health.ok(("kernel.perf_event_paranoid is %d"):format(level))
    end

    if platform.has_hardware_counters() then
      vim.health.ok "hardware counters are available"
    else
      vim.health.info "no hardware counters, as is usual in a VM: <leader>PR will record cpu-clock"
    end

    if platform.find "hotspot" then
      vim.health.ok "hotspot: <leader>Pi opens it"
    else
      vim.health.info "hotspot not found: <leader>Pi uses samply import instead"
    end
    check_tool("heaptrack", "<leader>PM")
    check_tool("valgrind", "<leader>Pm")
  end

  vim.health.start "profiling: display"
  if platform.has_display() then
    vim.health.ok "desktop session: GUI viewers can open"
  else
    vim.health.info "no display: annotations work, <leader>Pv prints an ssh -L command, and <leader>Pi is unavailable"
  end
end

return M
