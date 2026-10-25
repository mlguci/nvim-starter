-- One answer to "what project is this buffer in", a list of the projects seen so
-- far, and the switch between them. Plugin-free on purpose: this is required from
-- lua/chadrc.lua, which is read while lazy.nvim is still assembling its specs, so
-- nothing here may touch a plugin at require time. The two plugins that do take
-- part -- snacks.nvim for the picker, persistence.nvim for the sessions -- are
-- specced in lua/plugins/project.lua and only ever reached from inside a function.
--
-- Named after the subject rather than the plugin, the same way lua/dotfiles.lua is:
-- `require "project"` is ours and shadows nothing (project.nvim's module is
-- `project_nvim`).

local M = {}

-- What makes a directory a project root, in priority order. vim.fs.root tries
-- each entry against *every* ancestor before moving to the next, so this is not
-- "nearest marker wins" -- it is ".git wins, and only if there is no .git
-- anywhere above do the build markers get a turn". That ordering is the opposite
-- of what most root-detection plugins do, and it is deliberate: in a repo with
-- per-subproject build directories, the thing worth switching to and grepping is
-- the repo. The second tier therefore only ever fires for directories that are
-- not in git at all.
--
-- CMakeLists.txt is deliberately absent. It exists in every subdirectory of a
-- CMake project, so as a marker it resolves to whichever directory the file being
-- edited happens to sit in.
local markers = {
  ".git",
  { "CMakePresets.json", "compile_commands.json", ".clangd", "Cargo.toml", "pyproject.toml", "package.json" },
}

-- Mirrors persistence.nvim's own default (lua/persistence/config.lua), including
-- the "%"-escaped filename scheme below. Restated rather than read from it because
-- will_restore() runs before the plugin has loaded -- persistence's
-- Config.options is an empty table until its setup() has run. The spec in
-- lua/plugins/project.lua therefore does not override `dir`: leave it alone and
-- the two cannot drift.
local sessions_dir = vim.fn.stdpath "state" .. "/sessions/"

local registry_path = vim.fn.stdpath "state" .. "/projects.json"

-- Directories that are never projects, however many root markers they contain:
-- every lazy.nvim plugin is a git checkout, and browsing one would otherwise put
-- it in the picker alongside real work.
local excluded = {
  vim.fs.normalize(vim.fn.stdpath "data"),
  vim.fs.normalize(vim.fn.stdpath "state"),
  vim.fs.normalize(vim.fn.stdpath "cache"),
}

-- Guards switch() against being re-entered -- from the picker, from
-- :ProjectSwitch, or from a keypress landing during a restore. Everything between
-- the save and the source is a half-dismantled editor.
local switching = false

-- Where the last switch came from, for M.back(). In memory only: "the project I
-- was just in" is a property of this nvim run, not something to carry across one.
local previous

---@param path string
---@return string
local function normalize(path)
  local dir = vim.fs.normalize(path)
  -- A trailing slash would make the same project two different registry keys.
  -- gsub returns a count as its second value, which a bare return would leak.
  return (dir:gsub("(.)/$", "%1"))
end

---@param dir string
---@return boolean
local function is_excluded(dir)
  for _, prefix in ipairs(excluded) do
    if dir == prefix or vim.startswith(dir, prefix .. "/") then
      return true
    end
  end
  return false
end

--- The project root a buffer belongs to.
---
--- Markers first, the attached language server second, cwd last. The LSP answer is
--- the fallback and not the lead for the same reason .git leads the marker list:
--- clangd roots itself wherever the compilation database is, which in a repo with
--- per-subproject builds is below the project. It is still worth asking, because a
--- server that roots on something this file has never heard of still knows better
--- than cwd does.
---@param buf? integer defaults to the current buffer
---@return string
function M.root(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf

  if not vim.api.nvim_buf_is_valid(buf) then
    return normalize(vim.uv.cwd())
  end

  local cached = vim.b[buf].project_root
  if cached then
    return cached
  end

  -- Terminals, the overseer task list, nvdash, picker previews: no file, so
  -- nothing to resolve. Checked explicitly rather than left to vim.fs.root --
  -- it diverts to cwd for a non-empty 'buftype', but an unnamed *normal* buffer
  -- gets its empty name joined onto cwd instead, which is the same answer by
  -- accident rather than by rule.
  if vim.bo[buf].buftype ~= "" or vim.api.nvim_buf_get_name(buf) == "" then
    return normalize(vim.uv.cwd())
  end

  local found = vim.fs.root(buf, markers)

  if not found then
    for _, client in ipairs(vim.lsp.get_clients { bufnr = buf }) do
      if client.root_dir then
        found = client.root_dir
        break
      end
    end
  end

  if not found then
    -- Not cached: cwd is not a property of the buffer, and this is the one
    -- branch a later LspAttach might be able to improve on.
    return normalize(vim.uv.cwd())
  end

  found = normalize(found)
  vim.b[buf].project_root = found
  return found
end

-- The registry: { [dir] = last-seen unix time }. A map and not a list, so a touch
-- is one assignment with no dedupe pass, and the order the picker wants is
-- derived at read time.

---@return table<string, integer>
local function read_registry()
  local fd = io.open(registry_path, "r")
  if not fd then
    return {}
  end

  local raw = fd:read "*a"
  fd:close()

  local ok, decoded = pcall(vim.json.decode, raw)
  -- An empty file decodes to nil and a truncated one throws; either way a
  -- damaged registry is worth less than a fresh one, so start over rather than
  -- making every call site nil-check.
  return (ok and type(decoded) == "table") and decoded or {}
end

--- Merge `changes` into the registry on disk.
---
--- Re-read and take the newer timestamp per entry rather than writing our own
--- view wholesale: two nvim instances open at once would otherwise each clobber
--- the other's projects. Written to a temporary file and renamed, because
--- fs_rename is atomic -- a crash partway through a plain write would leave
--- truncated JSON, and while read_registry() recovers from that, it recovers by
--- throwing the whole list away.
---@param changes table<string, integer|nil>
---@param remove? string a key to delete rather than merge
local function merge_registry(changes, remove)
  local merged = read_registry()

  for dir, seen in pairs(changes) do
    if not merged[dir] or merged[dir] < seen then
      merged[dir] = seen
    end
  end

  if remove then
    merged[remove] = nil
  end

  local tmp = registry_path .. ".tmp"
  local fd = io.open(tmp, "w")
  if not fd then
    return
  end
  fd:write(vim.json.encode(merged))
  fd:close()

  vim.uv.fs_rename(tmp, registry_path)
end

--- Record a directory as a project, with the time it was last seen.
---@param dir string
function M.add(dir)
  dir = normalize(dir)

  if is_excluded(dir) or vim.fn.isdirectory(dir) == 0 then
    return
  end

  local registry = read_registry()
  local seen = registry[dir]

  -- This runs on every BufReadPost and LspAttach, so most calls are about a
  -- project already at the top of the list. Rewriting the file to move a
  -- timestamp by a few seconds buys nothing; five minutes is fine granularity
  -- for a "most recent first" ordering, and it keeps the write off the path of
  -- opening a dozen files in a row.
  if seen and os.time() - seen < 300 then
    return
  end

  merge_registry { [dir] = os.time() }
end

--- Drop a directory from the registry. The picker's <C-x>.
---@param dir string
function M.forget(dir)
  merge_registry({}, normalize(dir))
end

--- Known projects, most recently used first.
---
--- The registry is the real source; v:oldfiles is folded in behind it so the
--- picker is not empty before anything has been recorded. It cannot replace the
--- registry, for three reasons: v:oldfiles is a snapshot loaded from the shada
--- file at startup and never refreshed (:help v:oldfiles), so after one switch it
--- still describes the project we left; it is capped by 'shada's ' value, 100
--- here, and a monorepo spends all hundred entries on one project; and it records
--- files, so there is no per-project recency in it to sort by.
---@return string[]
function M.list()
  local registry = read_registry()

  local dirs = vim.tbl_keys(registry)
  table.sort(dirs, function(a, b)
    return registry[a] > registry[b]
  end)

  local seen = {}
  local out = {}

  for _, dir in ipairs(dirs) do
    -- Pruned on read rather than on write: a project that has been deleted or
    -- renamed would otherwise sit in the list forever, and switching into it
    -- would cd to nothing.
    if vim.fn.isdirectory(dir) == 1 then
      seen[dir] = true
      out[#out + 1] = dir
    end
  end

  -- Resolved per *directory* rather than per file: a hundred oldfiles routinely
  -- share a dozen directories, and the walk up the tree is what costs.
  local checked = {}
  for _, file in ipairs(vim.v.oldfiles) do
    local parent = vim.fs.dirname(vim.fs.normalize(file))
    if parent and not checked[parent] then
      checked[parent] = true
      local root = vim.fs.root(file, markers)
      if root then
        root = normalize(root)
        if not seen[root] and not is_excluded(root) and vim.fn.isdirectory(root) == 1 then
          seen[root] = true
          out[#out + 1] = root
        end
      end
    end
  end

  return out
end

--- Session files belonging to a directory.
---
--- Matched by name rather than globbed, because the escaped names are prefixes of
--- one another: /a/b becomes %a%b, and a glob of "%a%b*.vim" would also match
--- /a/bc's session. Only the exact name and the "%%<branch>" suffix form count,
--- which is what persistence.nvim's current() produces.
---@param dir string
---@return string[] absolute paths
local function session_files(dir)
  if vim.fn.isdirectory(sessions_dir) == 0 then
    return {}
  end

  local name = (normalize(dir):gsub("[\\/:]+", "%%"))
  local out = {}

  for _, entry in ipairs(vim.fn.readdir(sessions_dir)) do
    if entry == name .. ".vim" or vim.startswith(entry, name .. "%%") then
      out[#out + 1] = sessions_dir .. entry
    end
  end

  return out
end

--- Delete every session recorded for a directory.
---
--- The escape hatch for a session that no longer loads. :source aborts partway
--- through when a file it names has been deleted, leaving a half-built layout,
--- and without this the only fix is deleting a file out of stdpath("state") by
--- hand.
---@param dir string
function M.delete_session(dir)
  local files = session_files(dir)
  for _, file in ipairs(files) do
    vim.fn.delete(file)
  end
  vim.notify(("deleted %d session(s) for %s"):format(#files, vim.fn.fnamemodify(dir, ":~")))
end

--- Should starting nvim here restore a session instead of showing the dashboard?
---
--- Both halves matter. A session on disk without a registry entry is a directory
--- that was only ever visited, and a registry entry without a session is a
--- project that has not been worked in yet -- neither is worth taking the startup
--- screen away for.
---@return boolean
function M.will_restore()
  local cwd = normalize(vim.uv.cwd())
  return read_registry()[cwd] ~= nil and #session_files(cwd) > 0
end

--- Is there anything in this session worth saving?
---
--- persistence.save() is a bare `mks!` -- the `need` check lives in its
--- VimLeavePre handler, not in save() -- so without this a switch out of a
--- freshly started nvim, or out of a project whose session was just abandoned,
--- would write an empty session over a good one. The filter is persistence's own,
--- kept in step with it deliberately.
---@return boolean
local function worth_saving()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
      return true
    end
  end
  return false
end

---@return boolean
local function tree_is_open()
  return package.loaded["nvim-tree.view"] ~= nil and require("nvim-tree.view").is_visible()
end

--- Close the windows that must not end up in a session file.
---
--- This is not housekeeping, it is the difference between a session that restores
--- and one that poisons the project. :mksession saves any window whose buffer has
--- a *name*, and nvim-tree's buffer is named "NvimTree_1", overseer's
--- "OverseerList" -- so a session written with either on screen contains `edit
--- NvimTree_1`, which restores as a real, empty, file-backed buffer of that name
--- in the project root. Dropping `blank` from 'sessionoptions' does not help:
--- `blank` only governs *unnamed* windows. nvim-tree does clean this up itself,
--- but only from 0.13 -- its SessionLoadPost handler is gated on
--- has("nvim-0.13") and this is 0.12 -- so on this Neovim nothing else will.
---
--- Each plugin is reached through package.loaded rather than require: with
--- `defaults.lazy = true` (lua/configs/lazy.lua) a require here would make
--- quitting the thing that drags overseer or the Claude sidebar in.
---
--- The Claude sidebar goes first. Snacks installs a QuitPre handler that closes
--- its own window, and a handler closing the window a teardown was issued from is
--- what cancels the teardown -- the trap the <C-q> comment in lua/mappings.lua
--- describes.
function M.close_transient_windows()
  if package.loaded["claudecode.terminal"] then
    pcall(function()
      require("claudecode.terminal").close()
    end)
  end

  if package.loaded["nvim-tree.api"] then
    pcall(function()
      require("nvim-tree.api").tree.close()
    end)
  end

  if package.loaded.overseer then
    pcall(function()
      require("overseer").close()
    end)
  end

  pcall(vim.cmd.cclose)
end

--- Leave the current project and open another one: save, clear, cd, restore.
---
--- The order below is the content of this function; several steps are only safe
--- because of the one before them, and two are easy to get backwards.
---@param dir string
function M.switch(dir)
  dir = normalize(vim.fn.fnamemodify(dir, ":p"))

  if switching then
    return
  end

  if vim.fn.isdirectory(dir) == 0 then
    vim.notify("not a directory: " .. dir, vim.log.levels.ERROR)
    return
  end

  if dir == normalize(vim.uv.cwd()) then
    return
  end

  -- Nothing below this point is reversible, so every refusal comes first.
  -- Refuse rather than prompt: the wipe is forced, so the alternative to
  -- stopping here is losing the edit.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].modified and vim.bo[buf].buftype == "" and vim.fn.buflisted(buf) == 1 then
      local name = vim.api.nvim_buf_get_name(buf)
      name = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":~:.")
      vim.notify("unsaved changes in " .. name, vim.log.levels.WARN)
      return
    end
  end

  -- A build would survive the switch still rooted in the old project, with
  -- nothing on screen to say so: overseer reads a task's cwd once, when the task
  -- is created, and never revisits it.
  if package.loaded.overseer then
    local running = require("overseer").list_tasks { status = "RUNNING" }
    if #running > 0 then
      vim.notify(("%d task(s) still running"):format(#running), vim.log.levels.WARN)
      return
    end
  end

  switching = true
  local from = normalize(vim.uv.cwd())
  local reopen_tree = tree_is_open()

  local persistence = require "persistence"

  -- Before the save, not after: see close_transient_windows.
  M.close_transient_windows()

  if worth_saving() then
    persistence.save()
  end
  M.add(from)

  -- Disarm the autosave for the duration of the switch. Two things go wrong
  -- otherwise: quitting before the new session has loaded writes the *new*
  -- project's file from the old project's buffers, and a switch into a project
  -- with no session leaves a buffer list that would be saved over whatever is
  -- already there.
  persistence.stop()

  -- Collapse to one window -- after the save, so the layout we just recorded is
  -- the real one. This is also the whole E444 defence: :only and :tabonly keep
  -- the *current* window, so from here on nothing is ever asked to close the
  -- last one.
  pcall(vim.cmd, "silent! tabonly")
  pcall(vim.cmd, "silent! only")

  -- A plain listed buffer, shaped exactly as :mksession's own prologue looks for
  -- (unnamed, unmodified, a single empty line) -- so a restored session wipes it
  -- in its epilogue and we need no bookkeeping. It is what stops the wipe below
  -- leaving the last window without a buffer.
  local anchor = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, anchor)

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= anchor and vim.api.nvim_buf_is_valid(buf) then
      -- force, because a terminal buffer counts as modified and refuses a plain
      -- wipe. Safe only because of the unsaved-changes guard above.
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  -- Detaching a buffer does not stop its server: Client:_on_detach clears
  -- attached_buffers[bufnr] and returns, and the only unconditional stop is an
  -- autocmd on VimLeavePre. Without this every project visited leaks a clangd --
  -- and lua/configs/lspconfig.lua runs it with --background-index and
  -- --pch-storage=memory, so each one is expensive to leave lying around. A
  -- client with no buffers left cannot be reattached to, so this needs no
  -- comparison against the new root: vim.lsp.enable starts a fresh one with the
  -- right root_dir when a file of its filetype is opened.
  for _, client in ipairs(vim.lsp.get_clients()) do
    if next(client.attached_buffers) == nil then
      client:stop()
    end
  end

  -- vim.cmd.cd and not vim.fn.chdir. chdir() with no scope argument changes
  -- whichever scope happens to be in effect -- window-local if any :lcd is
  -- active, else tab-local, else global -- so a single stray :tcd anywhere would
  -- turn this into a tab-local cd and leave the global cwd behind. :cd is the one
  -- variant that also *clears* the window's and tab's local directories
  -- (:help :cd), which is what keeps persistence's getcwd()-keyed session names
  -- honest.
  --
  -- Before the restore, not as a side effect of it: persistence derives the
  -- session filename from getcwd(), so loading first would re-read the session we
  -- came from. (The session file sets its own directory too, since `curdir` is in
  -- 'sessionoptions', which is what makes the mistake look harmless.) It also
  -- means cmake-tools' DirChanged handler re-keys its build config before any
  -- CMakeLists.txt is restored.
  vim.cmd.cd(vim.fn.fnameescape(dir))
  M.add(dir)
  previous = from

  -- Measured, not predicted: a session file existing for *some* branch does not
  -- mean persistence will load one, because it wants this branch's or the
  -- branchless one. SessionLoadPost is what actually happened, and `source` is
  -- synchronous, so by the time load() returns it has either fired or never
  -- will.
  local restored = false
  local probe = vim.api.nvim_create_autocmd("SessionLoadPost", {
    once = true,
    callback = function()
      restored = true
    end,
  })

  persistence.load()

  if restored then
    -- The tree was closed before the save precisely so it would not be in the
    -- session, so putting it back is on us.
    if reopen_tree then
      pcall(function()
        require("nvim-tree.api").tree.toggle { focus = false }
      end)
    end
  else
    -- A `once` autocmd that never fired is still armed, and would otherwise
    -- claim the *next* session load in this run.
    pcall(vim.api.nvim_del_autocmd, probe)

    -- Nothing to restore: land on the tree, rooted on the new project by
    -- nvim-tree's own sync_root_with_cwd.
    pcall(function()
      require("nvim-tree.api").tree.open()
    end)
  end

  persistence.start()
  switching = false
end

--- Switch back to the project this one was reached from.
function M.back()
  if not previous then
    vim.notify("no previous project", vim.log.levels.WARN)
    return
  end
  M.switch(previous)
end

--- Move cwd to the current buffer's project root, without touching the layout.
function M.cd_root()
  local root = M.root()
  vim.cmd.cd(vim.fn.fnameescape(root))
  M.add(root)
  vim.notify("cwd: " .. vim.fn.fnamemodify(root, ":~"))
end

function M.setup()
  local group = vim.api.nvim_create_augroup("Project", { clear = true })

  -- Both events, because neither is enough on its own: BufReadPost catches files
  -- in projects no language server serves, and LspAttach is the second chance for
  -- a buffer whose markers resolved to nothing (root() leaves that case uncached
  -- precisely so this can improve on it).
  vim.api.nvim_create_autocmd({ "BufReadPost", "LspAttach" }, {
    group = group,
    desc = "Record the project a buffer belongs to",
    callback = function(ev)
      if vim.bo[ev.buf].buftype == "" and vim.api.nvim_buf_get_name(ev.buf) ~= "" then
        M.add(M.root(ev.buf))
      end
    end,
  })

  -- The same cleanup switch() does, for the other route into a save: quitting.
  -- persistence fires this from its VimLeavePre handler, which is the one save
  -- this module is not in the middle of, and a session written with the tree or
  -- the task list on screen is poisoned in exactly the same way.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "PersistenceSavePre",
    desc = "Keep plugin windows out of the session file",
    callback = function()
      M.close_transient_windows()
    end,
  })

  -- `nested` is load-bearing. A session file restores its buffers with `edit`,
  -- and commands run from an autocmd callback do not fire autocmds of their own
  -- unless the autocmd asks for it -- without this the restored buffers come
  -- back with no filetype, so no treesitter highlighting ('syntax' is
  -- rtp-disabled in lua/configs/lazy.lua, leaving no fallback) and no LSP.
  --
  -- argc(-1) rather than argc(): it counts the whole argument list including
  -- files after `--`, so `nvim file`, `nvim -` and `nvim +Man ...` are all left
  -- alone and only a bare `nvim` restores.
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    nested = true,
    desc = "Restore the session when nvim starts in a known project",
    callback = function()
      if vim.fn.argc(-1) == 0 and M.will_restore() then
        require("persistence").load()
      end
    end,
  })

  -- The picker is the usual way in; this is the scriptable one, and what makes
  -- the switch testable without a UI.
  vim.api.nvim_create_user_command("ProjectSwitch", function(args)
    M.switch(args.args ~= "" and args.args or M.root())
  end, { nargs = "?", complete = "dir", desc = "Switch to a project directory" })
end

return M
