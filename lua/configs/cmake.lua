-- Build-system half of the C/C++ setup: configure, build, run, test and debug a
-- CMake project. The language-server half -- clangd over the generated
-- compile_commands.json, plus neocmakelsp for the listfiles themselves -- is in
-- lua/configs/lspconfig.lua. The keymaps that reach any of this are the `keys`
-- table on the spec in lua/plugins/cmake.lua.

-- Ninja rather than the Unix Makefiles generator CMake still defaults to here,
-- and set through the environment rather than as a `-G Ninja` in
-- cmake_generate_options: cmake refuses a -G passed alongside a --preset whose
-- configure preset names its own generator, while CMAKE_GENERATOR is only a
-- *default*, which such a preset overrides silently. The variable is read by the
-- cmake binary itself, so this also means a build typed into a :terminal picks
-- the same generator as one started from <leader>cmb.
vim.env.CMAKE_GENERATOR = vim.env.CMAKE_GENERATOR or "Ninja"

local options = {
  -- Presets first, falling back to variants when a project has no
  -- CMakePresets.json. Kits -- the pre-presets way of naming a toolchain -- are
  -- left at their default and reachable only as :CMakeSelectKit.
  cmake_use_preset = true,

  -- Saving a CMakeLists.txt re-runs the configure step, so a newly added source
  -- file is in the build graph (and in compile_commands.json, and so known to
  -- clangd) before the next build rather than after it.
  cmake_regenerate_on_save = true,

  cmake_generate_options = { "-DCMAKE_EXPORT_COMPILE_COMMANDS=1" },

  -- `build/` and not the plugin's own `out/`: build/ is the directory every C++
  -- project's .gitignore already covers. The ${variant:buildType} suffix keeps
  -- the Debug and Release trees side by side, so switching build type costs a
  -- re-link rather than a full rebuild. A function and not a plain string
  -- because that is the shape the plugin's own default has.
  cmake_build_directory = function()
    return "build/${variant:buildType}"
  end,

  -- Symlink the generated compile_commands.json into the project root, where
  -- clangd's own root_markers already look for it (see the bundled config in
  -- nvim-lspconfig's lsp/clangd.lua). Not the plugin's "lsp" action, which hands
  -- the build directory to clangd through lspconfig's `on_new_config` hook -- that
  -- hook does not exist under the vim.lsp.config API this config uses. `target`
  -- is a function *reference*: the plugin calls it itself, so it must not be
  -- invoked here.
  cmake_compile_commands_options = {
    action = "soft_link",
    target = vim.uv.cwd,
  },

  -- Selected build type and target as virtual text on the project() line, which
  -- is the one place the answer is always wanted and never visible otherwise.
  cmake_virtual_text_support = true,

  -- Handed to nvim-dap by :CMakeDebug with the selected launch target filled in.
  -- The adapter this `type` names is registered in lua/configs/dap.lua.
  cmake_dap_configuration = {
    name = "cpp",
    type = "codelldb",
    request = "launch",
    stopOnEntry = false,
    runInTerminal = true,
    console = "integratedTerminal",
  },

  -- Builds run as overseer tasks: a build is a long job worth having a status,
  -- a history and a re-run for, which is exactly what a task list is.
  cmake_executor = {
    name = "overseer",
    opts = {
      new_task_opts = {
        components = {
          -- The build itself stays quiet -- errors are what deserve the screen.
          -- on_output_quickfix fills the quickfix list through &errorformat,
          -- which already parses clang's file:line:col diagnostics and ignores
          -- ninja's [n/m] progress lines, and `set_diagnostics` hands the same
          -- items to on_result_diagnostics so they also land as signs and
          -- virtual text in the offending buffers. `items_only` keeps everything
          -- errorformat did not recognise out of the list, so :cnext never stops
          -- on a progress line.
          { "open_output", on_start = "never", on_result = "if_diagnostics" },
          {
            "on_output_quickfix",
            errorformat = vim.o.errorformat,
            items_only = true,
            open = false,
            open_on_match = true,
            set_diagnostics = true,
          },
          { "on_result_diagnostics", virtual_text = true, signs = true, underline = true },
          -- An overseer alias, not a component: summarize, set status, notify,
          -- dispose. Dropping it leaves a task that never reports finishing.
          "default",
        },
      },
    },
  },

  -- A terminal and not overseer for *running*: an overseer task has no usable
  -- stdin, and an interactive program is the whole point of :CMakeRun. Mode is
  -- left to the TermModeMemory autocmds in lua/autocmds.lua, which put a
  -- terminal back in whichever mode it was left in -- a terminal this one has
  -- just created has no remembered mode, so `start_insert` still decides where
  -- it opens.
  cmake_runner = {
    name = "terminal",
    opts = {
      split_direction = "horizontal",
      split_size = 15,
      single_terminal_per_instance = true,
      start_insert = true,
      focus = true,
    },
  },
}

return options
