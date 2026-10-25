-- CMake: configure / build / run / test / debug, and the task runner that carries
-- the build output. `{ import = "plugins" }` in init.lua picks up every file in
-- this directory, so a new one needs no registration.
--
-- The long opts table lives in lua/configs/cmake.lua, following the
-- configs/conform.lua precedent. Plain `opts` values are safe on both specs here
-- for the reason spelled out on the neogit spec in lua/plugins/init.lua: the
-- "opts function" trap only applies to specs NvChad defines as well.
return {
  {
    "Civitasv/cmake-tools.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "stevearc/overseer.nvim" },

    -- Loaded on the cmake filetype so the virtual-text target display and the
    -- regenerate-on-save autocmd exist the moment a CMakeLists.txt is opened,
    -- and on its commands and keys so none of them has to wait for one. Not on
    -- c/cpp: those buffers get clangd, which needs nothing from this plugin.
    --
    -- nvim-dap is deliberately *not* a dependency: it would then load on every
    -- CMakeLists.txt. :CMakeDebug calls `require "dap"` itself, and lazy.nvim
    -- loads a lazy plugin on a require of its module, so the debugger arrives
    -- exactly when it is first needed.
    ft = "cmake",
    cmd = {
      "CMakeGenerate",
      "CMakeBuild",
      "CMakeBuildCurrentFile",
      "CMakeRun",
      "CMakeRunCurrentFile",
      "CMakeDebug",
      "CMakeDebugCurrentFile",
      "CMakeRunTest",
      "CMakeLaunchArgs",
      "CMakeSelectBuildType",
      "CMakeSelectBuildTarget",
      "CMakeSelectLaunchTarget",
      "CMakeSelectKit",
      "CMakeSelectConfigurePreset",
      "CMakeSelectBuildPreset",
      "CMakeSelectTestPreset",
      "CMakeSelectCwd",
      "CMakeSelectBuildDir",
      "CMakeOpenExecutor",
      "CMakeOpenRunner",
      "CMakeCloseExecutor",
      "CMakeCloseRunner",
      "CMakeStopExecutor",
      "CMakeStopRunner",
      "CMakeOpenCache",
      "CMakeInstall",
      "CMakeClean",
      "CMakeQuickBuild",
      "CMakeQuickRun",
      "CMakeQuickDebug",
      "CMakeQuickStart",
      "CMakeShowTargetFiles",
      "CMakeSettings",
      "CMakeTargetSettings",
    },

    opts = require "configs.cmake",

    -- Nested under the Code group rather than claiming a prefix of its own:
    -- lowercase verbs for the build cycle, uppercase for the selections each of
    -- those verbs acts on (build target, launch target, build type, build
    -- preset). Group label is in the which-key spec in lua/plugins/init.lua.
    keys = {
      { "<leader>cmg", "<cmd>CMakeGenerate<cr>", desc = "cmake generate" },
      { "<leader>cmb", "<cmd>CMakeBuild<cr>", desc = "cmake build" },
      { "<leader>cmB", "<cmd>CMakeSelectBuildTarget<cr>", desc = "cmake select build target" },
      { "<leader>cmr", "<cmd>CMakeRun<cr>", desc = "cmake run" },
      { "<leader>cmR", "<cmd>CMakeSelectLaunchTarget<cr>", desc = "cmake select launch target" },
      { "<leader>cmd", "<cmd>CMakeDebug<cr>", desc = "cmake debug" },
      { "<leader>cmt", "<cmd>CMakeRunTest<cr>", desc = "cmake run tests" },
      { "<leader>cmT", "<cmd>CMakeSelectBuildType<cr>", desc = "cmake select build type" },
      { "<leader>cmp", "<cmd>CMakeSelectConfigurePreset<cr>", desc = "cmake select configure preset" },
      { "<leader>cmP", "<cmd>CMakeSelectBuildPreset<cr>", desc = "cmake select build preset" },
      { "<leader>cma", "<cmd>CMakeLaunchArgs<cr>", desc = "cmake set launch args" },
      { "<leader>cmc", "<cmd>CMakeClean<cr>", desc = "cmake clean" },
      { "<leader>cmo", "<cmd>CMakeOpenExecutor<cr>", desc = "cmake open build output" },
      { "<leader>cmx", "<cmd>CMakeStopExecutor<cr>", desc = "cmake stop build" },
      { "<leader>cms", "<cmd>CMakeSettings<cr>", desc = "cmake settings" },
    },
  },

  -- The executor behind every cmake-tools build (configured in
  -- lua/configs/cmake.lua). No keymaps of its own: <leader>cmo is
  -- :CMakeOpenExecutor, which is what opens this task list.
  {
    "stevearc/overseer.nvim",
    cmd = { "OverseerToggle", "OverseerOpen", "OverseerRun", "OverseerInfo" },
    opts = {
      task_list = {
        direction = "bottom",
        min_height = 15,
        max_height = 25,

        -- Give <C-q> back to the global quit-all map in lua/mappings.lua, for
        -- exactly the reason the telescope spec in lua/plugins/init.lua does:
        -- a buffer-local mapping always beats a global one, and "quit from
        -- anywhere, unconditionally" is not true if the task list is an
        -- exception. Overseer binds it to "open task output in the quickfix",
        -- which is the one action here that is already redundant -- the
        -- on_output_quickfix component in lua/configs/cmake.lua has put the
        -- build's errors there before the list is ever opened.
        --
        -- `false` removes a default keymap; overseer's own config comment
        -- documents that, and its merge keeps the rest of the defaults.
        keymaps = { ["<C-q>"] = false },
      },
    },
  },
}
