return {
  defaults = { lazy = true },
  install = { colorscheme = { "nvchad" } },

  -- Keep the spec reload on config edits, drop its "Config Change Detected"
  -- notice. With no notification UI installed, vim.notify writes to the
  -- message area, and that notice landing there was a hit-enter prompt on
  -- every save of a file under this config.
  change_detection = { notify = false },

  ui = {
    icons = {
      ft = "",
      lazy = "󰂠 ",
      loaded = "",
      not_loaded = "",
    },
  },

  performance = {
    rtp = {
      disabled_plugins = {
        "2html_plugin",
        "tohtml",
        "getscript",
        "getscriptPlugin",
        "gzip",
        "logipat",
        "netrw",
        "netrwPlugin",
        "netrwSettings",
        "netrwFileHandlers",
        "matchit",
        "tar",
        "tarPlugin",
        "rrhelper",
        "spellfile_plugin",
        "vimball",
        "vimballPlugin",
        "zip",
        "zipPlugin",
        "tutor",
        -- "rplugin" is deliberately *not* disabled: it is what loads the
        -- remote-plugin manifest :UpdateRemotePlugins writes, and molten (the
        -- notebook runner in lua/plugins/python.lua) is a remote plugin. With it
        -- disabled molten's commands simply never exist.
        "syntax",
        "synmenu",
        "optwin",
        "compiler",
        "bugreport",
        "ftplugin",
      },
    },
  },
}
