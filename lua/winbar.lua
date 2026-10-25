-- Window bar used as the active-window cue. The focused window's bar is filled
-- with orange (hl-WinBar), every other window's is flat and muted
-- (hl-WinBarNC) -- Neovim picks between those two groups on its own, so there
-- is no focus-tracking autocmd here. Colours live in chadrc.lua.
local M = {}

-- Pure Lua rather than fnamemodify(): the bar is re-evaluated for every window
-- on every redraw, so this stays off the vimscript bridge.
local function basename(path)
  return path:match "[^/]+$" or path
end

local function label(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local buftype = vim.bo[buf].buftype

  if buftype == "terminal" then
    -- Buffer name is term://{cwd}//{pid}:{cmd}. Show just the program: it stays
    -- short and stable, where b:term_title grows long and tracks the cwd.
    local cmd = name:match "^term://.*//%d+:(.+)$"
    return cmd and basename(cmd:match "^%S+" or cmd) or "terminal"
  end

  local ft = vim.bo[buf].filetype

  -- Scratch-type windows carry a synthetic name ("NvimTree_1"), so the
  -- filetype is the more useful label; real files fall through to the basename.
  if name == "" or buftype == "nofile" or buftype == "prompt" then
    return ft ~= "" and ft or "[No Name]"
  end

  return basename(name)
end

M.render = function()
  -- A "%!" expression runs in the context of the *current* window, not the one
  -- being drawn (:help 'statusline'), so the window has to come from
  -- g:statusline_winid or every bar would show the focused window's name.
  local win = vim.g.statusline_winid
  local buf

  if win and win ~= 0 and vim.api.nvim_win_is_valid(win) then
    buf = vim.api.nvim_win_get_buf(win)
  else
    buf = vim.api.nvim_get_current_buf()
  end

  local text = " " .. label(buf) .. (vim.bo[buf].modified and " [+] " or " ")

  -- Escape % so a filename containing one is not read back as a statusline item.
  return (text:gsub("%%", "%%%%"))
end

return M
