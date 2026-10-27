-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "nord",

  -- Active-window cue: Neovim draws hl-WinBar in the current window and
  -- hl-WinBarNC in all others, so these two groups are the entire focus
  -- mechanism -- no focus-tracking autocmd involved. base46 ships both as
  -- { bg = "NONE" }.
  --
  -- A filled marker on the focused window rather than a dimmed background on
  -- the others: against nord's mid-dark #2E3440, darkening a region raises
  -- the contrast of the text on it, so the "dimmed" window pops instead of
  -- receding.
  hl_override = {
    WinBar = { fg = "black", bg = "orange", bold = true },
    WinBarNC = { fg = "grey_fg", bg = "NONE" },
  },

  -- The Claude sidebar is a snacks window, and snacks remaps WinBar/WinBarNC
  -- to its own groups and re-stamps that on every toggle. Defining those
  -- groups is therefore more robust than overriding the mapping: snacks
  -- registers them through Snacks.util.set_hl with `default = true`, which
  -- does not override an existing definition, and base46's cache is loaded at
  -- startup -- before snacks lazy-loads.
  hl_add = {
    SnacksWinBar = { link = "WinBar" },
    SnacksWinBarNC = { link = "WinBarNC" },
  },

  -- base46 ships integrations/snacks.lua, which themes the SnacksPicker* groups
  -- off the same nvconfig.ui.telescope.style the telescope ones use -- but
  -- "snacks" is not in its default integration list, so without this the project
  -- picker (lua/plugins/project.lua) renders unthemed next to every telescope
  -- picker. Named integrations are appended to base46's own list, not a
  -- replacement for it.
  --
  -- Listing it only makes base46 *compile* the highlight file; loading it is the
  -- snacks spec's job, which is why lua/plugins/project.lua dofiles it the way
  -- nvchad/configs/telescope.lua does. And compiling needs one rebuild --
  -- `:Lazy build base46`, or any theme switch through <leader>ut, which calls
  -- load_all_highlights() -- so a fresh clone gets an unthemed picker until then.
  integrations = { "snacks" },
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

-- The startup screen, except in a project we are about to restore a session into.
--
-- Decided here rather than in an autocmd because NvChad runs the
-- nvdash-on-startup check at *module load* time, not on VimEnter
-- (ui/lua/nvchad/au.lua), and `ui` is lazy = false -- so it happens before
-- init.lua even reaches `require "options"`. There is no window in which to
-- pre-empt it, but the flag it reads is ours. Making the flag conditional means
-- the dashboard is never opened in a session restore, so there is no dashboard
-- buffer to tear back down afterwards.
--
-- will_restore() is cheap and plugin-free by design -- it reads a JSON file and
-- lists a directory, no git and no persistence.nvim -- because this runs on the
-- startup path of every nvim, including the ones that restore nothing.
M.nvdash = { load_on_startup = not require("project").will_restore() }

-- Double every % so a string shows up literally in the statusline. Needed on
-- anything a module returns that did not originate in this file: the statusline
-- is a %! expression, so its result is parsed again as statusline format, and a
-- %{...} item inside it is evaluated -- unsandboxed, on every redraw.
-- lua/winbar.lua applies the same escape to file names.
local function stl_literal(s)
  return (s:gsub("%%", "%%%%"))
end

M.ui = {
  statusline = {
    -- NvChad's own "default" theme order (nvchad/stl/utils.lua) with "cmake"
    -- spliced in before the diagnostics counter. `order` replaces the default
    -- wholesale rather than extending it, so the rest has to be restated.
    order = { "mode", "file", "git", "%=", "lsp_msg", "%=", "cmake", "diagnostics", "lsp", "cwd", "cursor" },

    modules = {
      -- Which build type and which launch target the next <leader>cmb and
      -- <leader>cmr will act on. cmake-tools also writes this as virtual text on
      -- the project() line, but only CMakeLists.txt gets to see that -- the
      -- source file being edited is where the question actually comes up.
      cmake = function()
        -- The filetype test comes first because it is the cheap one: it costs a
        -- table lookup, and it is what keeps the rest off the redraw path of
        -- every buffer in the editor that is not C, C++ or cmake.
        local ft = vim.bo[require("nvchad.stl.utils").stbufnr()].filetype
        if ft ~= "c" and ft ~= "cpp" and ft ~= "cmake" then
          return ""
        end

        -- package.loaded and not require: with lazy.nvim's `defaults.lazy`,
        -- a require here would make the statusline the thing that drags
        -- cmake-tools in, on any C file anywhere. Nothing to report until the
        -- plugin has loaded on its own terms (lua/plugins/cmake.lua).
        local cmake = package.loaded["cmake-tools"]
        if not cmake or not cmake.is_cmake_project() then
          return ""
        end

        -- Both getters are `string?` -- nil until something has been selected --
        -- so neither can be concatenated unguarded. Both are also project data,
        -- not ours: the build type is the configure preset's CMAKE_BUILD_TYPE,
        -- verbatim from CMakePresets.json, and the target a name from the build
        -- tree -- hence stl_literal on each.
        local label = stl_literal(cmake.get_build_type() or "no build type")
        local target = cmake.get_launch_target()

        if target then
          -- \u{f0443}: nf-md-chevron_right. Written as escapes rather than
          -- pasted glyphs so the codepoints survive being edited by anything
          -- that is not a UTF-8-clean pipeline -- a silently dropped glyph here
          -- would leave stray padding, and in a sign definition it breaks the
          -- sign outright (see lua/configs/dap.lua).
          label = label .. " \u{f0443} " .. stl_literal(target)
        end

        -- \u{e794}: the cmake icon nvim-web-devicons gives a CMakeLists.txt, so
        -- the module is recognisable as the same subject as the file tree entry.
        -- St_Lsp is an existing base46 statusline group, so this themes itself
        -- with the rest of the bar instead of needing an hl_add entry.
        return (vim.o.columns > 100 and "%#St_Lsp# \u{e794} " .. label .. " ") or ""
      end,
    },
  },

  -- tabufline = { lazyload = false },
}

return M
