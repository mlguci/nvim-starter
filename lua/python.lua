-- One answer to "which Python does this buffer run on". The language server, the
-- debugger, the test runner, the REPL and the statusline all ask here, so they
-- cannot disagree -- a type checker resolving imports against one interpreter
-- while the tests run on another is the classic way for a green editor to sit
-- on top of a red test suite.
--
-- Plugin-free, for the same reason lua/project.lua is: the statusline module in
-- lua/chadrc.lua calls label() on every redraw of a Python buffer, and nothing
-- on that path may drag a plugin in.

local M = {}

-- Where :PythonHostInstall (lua/autocmds.lua) puts the interpreter Neovim's own
-- remote plugins run on -- molten, for the notebooks. Kept apart from every
-- project venv: it needs pynvim and jupyter_client, which no project should have
-- to carry, and it must survive any project's `uv sync --exact`.
M.host_venv = vim.fn.stdpath "data" .. "/python3-host"

-- The packages that host needs. pynvim and jupyter_client are molten's hard
-- requirements; nbformat lets it import and export outputs to an .ipynb;
-- jupytext is the converter jupytext.nvim shells out to; cairosvg and pillow
-- turn SVG and other non-PNG plot output into something the terminal can draw.
-- jupytext.nvim runs a bare `jupytext`, so it has to be on PATH -- but the host
-- venv's bin directory cannot be: it holds a `python` that would then win over
-- every project's for anything resolving python off PATH. This directory holds a
-- symlink to that one binary and nothing else, and lua/plugins/python.lua puts
-- it on PATH. The symlink works because the script's shebang names the host
-- venv's interpreter by absolute path.
M.host_shims = vim.fn.stdpath "data" .. "/python3-host-shims"

M.host_packages = { "pynvim", "jupyter_client", "nbformat", "jupytext", "cairosvg", "pillow" }

-- The search itself, on a directory rather than a buffer, and built from calls
-- that are safe in a fast context (os.getenv, vim.fs, vim.uv) -- neotest-python
-- asks for the interpreter from inside a nio coroutine, where vim.env and most
-- of vim.fn would throw.
--
-- $VIRTUAL_ENV first: nvim started from an activated shell has been told
-- explicitly. Otherwise the nearest `.venv` directory at or above `start`, going
-- no higher than `ceiling` -- `uv sync` creates it beside the pyproject.toml,
-- which in a monorepo is below the git root that project.root() answers with,
-- so searching *for* the venv from the file outward is what finds the right one.
-- The ceiling is there so that a stray ~/.venv is never picked up for a project
-- that simply has not been synced.
---@param start string
---@param ceiling string
---@return string?
local function find_venv(start, ceiling)
  local active = os.getenv "VIRTUAL_ENV"
  if active and active ~= "" then
    return active
  end

  -- `stop` is exclusive -- the search halts *before* reaching it -- so it is the
  -- ceiling's parent, which keeps the ceiling itself in the search.
  local found = vim.fs.find(".venv", {
    path = start,
    upward = true,
    type = "directory",
    stop = vim.fs.dirname(ceiling),
  })[1]

  if found and vim.uv.fs_stat(found .. "/bin/python") then
    return found
  end
  return nil
end

--- The virtualenv a buffer's code runs in, or nil when there is none. Searched
--- from the buffer's directory up to its project root (lua/project.lua).
---@param buf? integer defaults to the current buffer
---@return string?
function M.venv(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local root = require("project").root(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local start = (name ~= "" and vim.bo[buf].buftype == "") and vim.fs.dirname(name) or root
  return find_venv(start, root)
end

--- The interpreter for a buffer: its venv's, else whatever python3 is on PATH.
--- Takes a buffer or nothing, so it can be handed to dap-python as-is -- its
--- resolve_python hook is called with no arguments.
---@param buf? integer
---@return string
function M.python(buf)
  local venv = M.venv(buf)
  if venv then
    return venv .. "/bin/python"
  end
  local onpath = vim.fn.exepath "python3"
  return onpath ~= "" and onpath or "python3"
end

--- The interpreter for a directory that is itself the root -- what neotest
--- hands its adapters. Fast-context safe, so the PATH fallback is the bare name
--- rather than an exepath() lookup; a process spawn resolves it the same way.
---@param root string
---@return string
function M.python_at(root)
  local venv = find_venv(root, root)
  return venv and (venv .. "/bin/python") or "python3"
end

--- The venv's Python version, from pyvenv.cfg -- read, not asked of the
--- interpreter, because this runs on the statusline's redraw path and spawning
--- a process there is not an option. uv writes `version_info = 3.13.2`, the
--- stdlib venv module `version = 3.13.2`; both are accepted. Cached per venv:
--- the file only changes when the venv is recreated, and that is rare enough
--- that a restart to see it is a fair price.
---@type table<string, string|false>
local versions = {}

---@param venv string
---@return string?
local function version(venv)
  if versions[venv] == nil then
    versions[venv] = false
    local fd = io.open(venv .. "/pyvenv.cfg", "r")
    if fd then
      for line in fd:lines() do
        local v = line:match "^version_info%s*=%s*(%d+%.%d+)" or line:match "^version%s*=%s*(%d+%.%d+)"
        if v then
          versions[venv] = v
          break
        end
      end
      fd:close()
    end
  end
  return versions[venv] or nil
end

--- "name · 3.13" for the statusline, or nil when the buffer has no venv. The
--- name is the venv directory's -- except for the ubiquitous `.venv`, which says
--- nothing, so the project directory holding it stands in for it.
---@param buf? integer
---@return string?
function M.label(buf)
  local venv = M.venv(buf)
  if not venv then
    return nil
  end

  local name = vim.fs.basename(venv)
  if name == ".venv" then
    name = vim.fs.basename(vim.fs.dirname(venv))
  end

  local v = version(venv)
  return v and (name .. " · " .. v) or name
end

-- `# %%` cells -- the "percent" format jupytext writes notebooks in (see
-- lua/plugins/python.lua), which VS Code, Spyder and PyCharm all read as cells
-- in a plain .py file too. The REPL and the notebook runner both work in these.
local cell_marker = "^%s*#%s*%%%%"

--- The cell around the cursor as a 1-based inclusive line range, marker lines
--- excluded. A file with no markers is one cell; on a marker line, the cell is
--- the one that marker opens.
---@return integer first, integer last
function M.cell_range()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  local first = 1
  for l = cursor, 1, -1 do
    if lines[l]:match(cell_marker) then
      first = l + 1
      break
    end
  end
  local last = #lines
  for l = first, #lines do
    if lines[l]:match(cell_marker) then
      last = l - 1
      break
    end
  end
  return first, last
end

--- Move to the next (1) or previous (-1) cell marker, `count` times.
---@param dir 1|-1
function M.goto_cell(dir)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local l = vim.api.nvim_win_get_cursor(0)[1]
  for _ = 1, vim.v.count1 do
    local i = l + dir
    while i >= 1 and i <= #lines and not lines[i]:match(cell_marker) do
      i = i + dir
    end
    if i < 1 or i > #lines then
      break
    end
    l = i
  end
  vim.cmd "normal! m'"
  vim.api.nvim_win_set_cursor(0, { l, 0 })
end

-- Where Jupyter looks for per-user kernelspecs: jupyter_core's user data dir.
local function kernels_dir()
  if vim.fn.has "mac" == 1 then
    return vim.fs.normalize "~/Library/Jupyter/kernels"
  end
  return (vim.env.XDG_DATA_HOME or vim.fs.normalize "~/.local/share") .. "/jupyter/kernels"
end

--- :MoltenInit on a kernel that runs in this buffer's venv.
---
--- Jupyter only starts kernels it has a kernelspec for, and a project venv has
--- none until one is registered -- molten's own picker would offer the host's
--- interpreter, on which none of the project's packages import. So the venv is
--- registered as `nvim-<project>` (ipykernel's own installer, only when the spec
--- is missing or points elsewhere) and molten is started on that by name. With
--- no venv, or no ipykernel in it, it falls back to molten's picker and says why.
function M.molten_init()
  local venv = M.venv()
  local ipykernel = venv and vim.fn.glob(venv .. "/lib/python*/site-packages/ipykernel", false, true)[1]
  if not ipykernel then
    vim.notify(
      venv and "no ipykernel in " .. venv .. " -- `uv add --dev ipykernel` to run notebooks on it"
        or "no venv for this buffer -- `uv sync` first; falling back to the kernel picker",
      vim.log.levels.WARN
    )
    vim.cmd "MoltenInit"
    return
  end

  local python = venv .. "/bin/python"
  local project = vim.fs.basename(require("project").root())
  local name = "nvim-" .. project:lower():gsub("[^%w%-_.]", "-")
  local spec_file = kernels_dir() .. "/" .. name .. "/kernel.json"

  local current
  local fd = io.open(spec_file, "r")
  if fd then
    local ok, spec = pcall(vim.json.decode, fd:read "*a")
    fd:close()
    current = ok and spec.argv and spec.argv[1] or nil
  end

  if current ~= python then
    local res = vim
      .system({
        python,
        "-m",
        "ipykernel",
        "install",
        "--user",
        "--name",
        name,
        "--display-name",
        project .. " (" .. (M.label() or "venv") .. ")",
      }, { text = true })
      :wait()
    if res.code ~= 0 then
      vim.notify("ipykernel install failed:\n" .. (res.stderr or ""), vim.log.levels.ERROR)
      return
    end
  end

  vim.cmd("MoltenInit " .. name)
end

--- Create the host venv and install M.host_packages into it, blocking. Errors
--- out on failure, which is what makes `nvim --headless +PythonHostInstall +qa`
--- exit non-zero instead of reporting success over a half-built venv.
---
--- uv rather than python -m venv + pip: it fetches a managed 3.13 when the
--- machine has none, and does the install in seconds.
function M.install_host()
  if vim.fn.executable "uv" == 0 then
    error "PythonHostInstall: uv is not on PATH (brew install uv)"
  end

  local function run(cmd)
    local res = vim.system(cmd, { text = true }):wait()
    if res.code ~= 0 then
      error(("PythonHostInstall: `%s` failed:\n%s"):format(table.concat(cmd, " "), res.stderr or ""))
    end
  end

  if not vim.uv.fs_stat(M.host_venv .. "/bin/python") then
    run { "uv", "venv", "--python", "3.13", M.host_venv }
  end
  local cmd = { "uv", "pip", "install", "--upgrade", "--python", M.host_venv .. "/bin/python" }
  vim.list_extend(cmd, M.host_packages)
  run(cmd)

  vim.fn.mkdir(M.host_shims, "p")
  local shim = M.host_shims .. "/jupytext"
  if not vim.uv.fs_lstat(shim) then
    assert(vim.uv.fs_symlink(M.host_venv .. "/bin/jupytext", shim))
  end
  if not vim.env.PATH:find(M.host_shims, 1, true) then
    vim.env.PATH = M.host_shims .. ":" .. vim.env.PATH
  end

  -- options.lua only points the provider here when the venv already existed at
  -- startup, so a first install would otherwise need a restart to be used.
  vim.g.python3_host_prog = M.host_venv .. "/bin/python"
  vim.g.loaded_python3_provider = nil

  vim.notify("python host ready at " .. M.host_venv .. " -- now :Lazy build molten-nvim, then restart")
end

return M
