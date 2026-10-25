-- This file needs to have same structure as nvconfig.lua 
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :( 

---@type ChadrcConfig
local M = {}

M.base46 = {
	theme = "nord",

	-- hl_override = {
	-- 	Comment = { italic = true },
	-- 	["@comment"] = { italic = true },
	-- },
}

-- Split terminals take half the editor; NvChad defaults are 0.3 / 0.2.
-- The float keeps NvChad's remaining options (relative, border); row and col
-- are the top-left corner as a fraction of the editor, so they stay at half
-- the leftover space to keep the window centred.
M.term = {
  sizes = { sp = 0.5, vsp = 0.5, ["bo sp"] = 0.5, ["bo vsp"] = 0.5 },

  float = {
    width = 0.8,
    height = 0.8,
    row = 0.1,
    col = 0.1,
  },
}

-- M.nvdash = { load_on_startup = true }
-- M.ui = {
--       tabufline = {
--          lazyload = false
--      }
-- }

return M
