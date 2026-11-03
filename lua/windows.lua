-- Window helpers: where nvim-tree opens files, and maximize/restore.
--
-- nvim-tree's default window picker labels every candidate window A/B/C and
-- waits for a key whenever there are two or more of them -- two editor splits
-- beside the tree are enough. What is almost always meant is "the window I was
-- just editing in", so that is tracked here and handed to nvim-tree as its
-- picker (actions.open_file.window_picker.picker in lua/plugins/init.lua).
-- <C-v>, <C-x> and <C-t> in the tree still place a file deliberately.

local M = {}

-- A window a file can be opened into: not a float, not a terminal, help page,
-- picker or other special buffer, and not the tree itself.
local function is_editor_win(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "NvimTree"
end

-- On WinLeave rather than WinEnter: when a window is entered its buffer may not
-- be set up yet (the tree's own window has no filetype at that point, so it
-- passed as an editor window), whereas the window being left is complete.
function M.setup()
  vim.api.nvim_create_autocmd("WinLeave", {
    group = vim.api.nvim_create_augroup("LastEditorWindow", { clear = true }),
    desc = "Remember the last editor window, for nvim-tree to open files into",
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if is_editor_win(win) then
        vim.t.last_editor_win = win
      end
    end,
  })
end

-- nvim-tree only calls this when there are two or more candidate windows, so
-- the fallback always finds one; nil (cancel) is only a last resort.
function M.pick_for_tree()
  local tab_wins = vim.api.nvim_tabpage_list_wins(0)
  local last = vim.t.last_editor_win
  if last and is_editor_win(last) and vim.tbl_contains(tab_wins, last) then
    return last
  end
  for _, win in ipairs(tab_wins) do
    if is_editor_win(win) then
      return win
    end
  end
end

-- `cmd` is "vsplit" or "split". From the tree, a plain split would give a second
-- tree window, so split the editor window it would open files into. With no
-- editor window to split, start a new one beside the tree.
function M.split(cmd)
  if vim.bo.filetype == "NvimTree" then
    local win = M.pick_for_tree()
    if not win then
      vim.cmd "botright vnew"
      return
    end
    vim.api.nvim_set_current_win(win)
  end
  vim.cmd(cmd)
end

-- Per tab, because a winrestcmd() only makes sense in the layout it came from.
function M.toggle_maximize()
  if vim.t.restore_cmd then
    vim.cmd(vim.t.restore_cmd)
    vim.t.restore_cmd = nil
  else
    vim.t.restore_cmd = vim.fn.winrestcmd()
    vim.cmd "wincmd _ | wincmd |"
  end
end

-- After equalizing, a pending restore would snap back to sizes that are gone.
function M.equalize()
  vim.t.restore_cmd = nil
  vim.cmd "wincmd ="
end

return M
