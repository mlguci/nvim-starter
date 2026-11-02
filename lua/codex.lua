-- Codex (OpenAI's CLI) in a right-hand sidebar, set up to match the Claude one
-- from claudecode.nvim: same side, width and window bar, and the same terminal
-- mode handling. auto_insert is off so the TermModeMemory autocmds in
-- lua/autocmds.lua decide the mode, exactly as they do for Claude. The SnacksWinBar
-- links in lua/chadrc.lua apply because this is a snacks window too. Keys are
-- in the <leader>ax group (lua/plugins/init.lua).
local M = {}

local CMD = "codex"

local opts = {
  -- Pinned, because Snacks keys terminals by v:count1: without this, a stray
  -- count before the key would open a second Codex session.
  count = 1,
  auto_insert = false,
  start_insert = true,
  win = {
    position = "right",
    width = 0.35,
    wo = { winbar = "%!v:lua.require('winbar').render()" },
  },
}

local function available()
  if vim.fn.executable(CMD) == 1 then
    return true
  end
  vim.notify(
    "codex is not on PATH -- install it with `npm i -g @openai/codex` or `brew install codex`",
    vim.log.levels.WARN,
    { title = "Codex" }
  )
  return false
end

function M.toggle()
  if available() then
    require("snacks").terminal.toggle(CMD, opts)
  end
end

-- Open if needed, then move into the sidebar in terminal mode.
function M.focus()
  if not available() then
    return
  end
  local term = require("snacks").terminal.get(CMD, opts)
  if not term then
    return
  end
  if not term:win_valid() then
    term:show()
  end
  term:focus()
  vim.cmd "startinsert"
end

-- Type text into the Codex prompt without submitting it.
local function send(text)
  if not available() then
    return
  end
  local term, created = require("snacks").terminal.get(CMD, opts)
  if not term then
    return
  end
  if not term:win_valid() then
    term:show()
  end
  -- A codex that was only just started is still drawing its UI. Give it a
  -- moment, or the input arrives before the composer can take it.
  vim.defer_fn(function()
    if term:buf_valid() then
      vim.api.nvim_chan_send(vim.bo[term.buf].channel, text)
      M.focus()
    end
  end, created and 1500 or 0)
end

local function relpath(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or vim.bo[buf].buftype ~= "" then
    vim.notify("No file in this buffer", vim.log.levels.WARN, { title = "Codex" })
    return nil
  end
  return vim.fn.fnamemodify(name, ":.")
end

-- Mention the current file in the prompt (Codex's composer resolves @paths).
function M.add_buffer()
  local path = relpath(0)
  if path then
    send("@" .. path .. " ")
  end
end

-- Mention the selected lines, the way ClaudeCodeSend references a selection
-- instead of pasting it.
function M.send_selection()
  local path = relpath(0)
  if not path then
    return
  end
  local s, e = vim.fn.line "v", vim.fn.line "."
  if s > e then
    s, e = e, s
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  local ref = s == e and ("@%s:L%d "):format(path, s) or ("@%s:L%d-%d "):format(path, s, e)
  send(ref)
end

return M
