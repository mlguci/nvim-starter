-- Offline devdocs.io. The plugin downloads docsets and converts them with pandoc
-- (an external dependency, alongside curl and jq; `:checkhealth devdocs` says
-- whether they are there). Picking, grepping and reading pages is done by
-- lua/docs.lua, which explains why it replaces the plugin's own viewer.
--
-- A plain `opts` table for the reason given on the neogit spec in
-- lua/plugins/init.lua: the "opts function" trap only applies to specs NvChad
-- defines as well.
return {
  {
    "maskudo/devdocs.nvim",
    dependencies = { "folke/snacks.nvim" },
    cmd = "DevDocs",

    -- Loaded after the first screen, not on demand, because setup() is what
    -- starts downloading `ensure_installed`. On `keys` alone, the first lookup
    -- of a fresh install would be the moment the download begins, and come back
    -- empty. The download and the pandoc pass run through vim.system, so they
    -- never block the editor; once a docset is extracted, setup() only reads a
    -- small state file.
    event = "VeryLazy",

    opts = {
      -- Matches lua/docs.lua's filetype table. `cmake` with no version tracks the
      -- newest release, as the cmake on this machine does; Lua is 5.1 for LuaJIT.
      ensure_installed = { "c", "cpp", "cmake", "lua~5.1", "python~3.15" },
    },

    -- Swaps in our own HTML -> markdown conversion before setup() can start one,
    -- and converts already installed docsets again when that conversion has
    -- changed. lua/docs.lua says why the plugin's own leaves HTML behind.
    config = function(_, opts)
      require("docs").setup(opts)
    end,

    keys = {
      {
        "<leader>hh",
        function()
          require("docs").pick()
        end,
        desc = "devdocs search filetype docs",
      },
      {
        "<leader>hH",
        function()
          require("docs").pick { all = true }
        end,
        desc = "devdocs search all docs",
      },
      {
        "<leader>hk",
        function()
          require("docs").cword()
        end,
        mode = { "n", "x" },
        desc = "devdocs search word under cursor",
      },
      {
        "<leader>hg",
        function()
          require("docs").grep()
        end,
        desc = "devdocs grep filetype docs",
      },
      {
        "<leader>ho",
        function()
          require("docs").online()
        end,
        desc = "devdocs open word online",
      },
      { "<leader>hi", "<cmd>DevDocs install<cr>", desc = "devdocs install docset" },
      { "<leader>hd", "<cmd>DevDocs delete<cr>", desc = "devdocs delete docset" },
    },
  },
}
