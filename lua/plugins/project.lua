-- Projects: the picker that switches between them and the sessions that make a
-- switch non-destructive. The logic both specs call into is lua/project.lua --
-- see that file for why the switch is ordered the way it is. `{ import =
-- "plugins" }` in init.lua picks up every file in this directory, so this needs no
-- registration.
--
-- Plain `opts` tables on both specs: the "opts function" trap documented on the
-- blink and telescope fragments in lua/plugins/init.lua only applies to specs
-- NvChad defines as well, and neither of these is one.
return {
  -- snacks.nvim is already installed and pinned -- claudecode.nvim depends on it
  -- for its terminal sidebar -- but it has no spec of its own, so Snacks.setup()
  -- is never called and none of its modules are configured. This fragment is what
  -- starts calling it. lazy merges it with claudecode's `dependencies` entry by
  -- name, and runs this `config` once, on whichever of the two loads first.
  {
    "folke/snacks.nvim",

    -- The one spec here that is not loaded on demand, and only because
    -- ui_select below is on. vim.ui.select is a global that snacks replaces when
    -- it loads, so on `keys` alone the menus behind <leader>cm would be the
    -- builtin cmdline prompt until the first <leader>pp of the session and a
    -- snacks picker after it -- a UI that changes under you is worse than either
    -- one consistently. VeryLazy and not an earlier event: it fires after the
    -- first screen is drawn, so this costs nothing visible, and Snacks.setup()
    -- enables nothing but `picker` (every other module defaults to off and we
    -- pass no opts for them), whose own setup is the single assignment above.
    event = "VeryLazy",

    opts = {
      picker = {
        -- Hand every vim.ui.select in the config to the snacks picker.
        -- Snacks.picker.setup()'s only job is that one assignment, so this
        -- reaches well past the project picker: all of cmake-tools' target,
        -- preset and build-type menus behind <leader>cm, persistence's own
        -- <leader>pS, and anything else that asks the user to choose from a
        -- list. It is snacks' own default; it is stated anyway because it is a
        -- config-wide change in UI and nothing else here would explain it.
        --
        -- The `event` above is what makes this consistent rather than intermittent.
        ui_select = true,
      },
    },

    config = function(_, opts)
      -- base46 compiles one highlight cache file per integration but dofiles
      -- almost none of them itself: init.lua loads `defaults` and `statusline`,
      -- and every other integration is loaded by the plugin config that needs it
      -- (nvchad/configs/telescope.lua line 1 does exactly this). So without this
      -- line the SnacksPicker* groups stay undefined and the project picker
      -- renders unthemed beside every telescope one, even with "snacks" listed
      -- in chadrc.
      --
      -- pcall, not a bare dofile: the cache file does not exist until base46 has
      -- been rebuilt once (see the comment in lua/chadrc.lua), and an unthemed
      -- picker is a much better first run than an error on first keypress.
      pcall(dofile, vim.g.base46_cache .. "snacks")
      require("snacks").setup(opts)
    end,

    keys = {
      {
        "<leader>pp",
        function()
          local project = require "project"
          local snacks = require "snacks"

          snacks.picker {
            source = "projects",
            title = "Projects",

            -- A finder function and not a static `items` list: the forget and
            -- delete actions below re-run the finder through picker:find(),
            -- which with `items` would just hand back the same stale table.
            --
            -- Our registry, too, and not snacks' own `recent_projects` finder.
            -- That one shells out to `fd` across `opts.dev` to discover projects
            -- under fixed parent directories, and there is no way to ask it for
            -- nothing: handed an empty `dev` list, `fd` gets no search path and
            -- scans the current directory instead, filling the picker with
            -- whatever happens to sit below wherever you are.
            finder = function()
              return vim.tbl_map(function(dir)
                return { file = dir, text = dir, dir = true }
              end, project.list())
            end,

            -- Not `format = "file"`. That path goes through snacks' truncpath
            -- helper, which shortens a file against its git root -- and for a
            -- project *directory* the git root is the directory itself, so the
            -- remainder is empty and every row renders as a bare "⋮name" with no
            -- path at all. Two home-relative lines instead.
            format = function(item)
              local icon, hl = snacks.util.icon(item.file, "directory")
              return {
                { icon .. " ", hl, virtual = true },
                { vim.fn.fnamemodify(item.file, ":~"), "SnacksPickerDirectory" },
              }
            end,

            -- The default is snacks' `load_session` action, which chdirs and
            -- sources a session but neither saves the session being left nor
            -- clears its buffers -- so the old project's files follow you into
            -- the new one. project.switch does the full exchange.
            --
            -- Scheduled after the close: switch() runs :tabonly and :only, which
            -- have no business racing the teardown of the picker's own floating
            -- layout.
            confirm = function(picker, item)
              picker:close()
              if item then
                vim.schedule(function()
                  project.switch(item.file)
                end)
              end
            end,

            actions = {
              forget_project = function(picker, item)
                if item then
                  project.forget(item.file)
                  picker:refresh()
                end
              end,
              delete_session = function(picker, item)
                if item then
                  project.delete_session(item.file)
                  picker:refresh()
                end
              end,
            },

            -- The registry is already ordered most-recently-used first, so the
            -- matcher must not re-order it. snacks' `projects` source turns
            -- `frecency` and `sort_empty` on (its global defaults have both
            -- off), which would sort an empty prompt by snacks' own frecency
            -- database instead -- a second, disagreeing notion of "recent".
            matcher = {
              frecency = false,
              sort_empty = false,
              cwd_bonus = false,
            },

            win = {
              input = {
                keys = {
                  -- snacks' defaults for this source all begin with a tab-local
                  -- `tcd` (<c-e> explorer, <c-f> files, <c-g> grep, <c-w> just
                  -- cd, <c-t> new tab then pick again). They have to go:
                  -- persistence keys its session files on getcwd(), which answers
                  -- per-tab once any tab has a local directory, so one <c-f>
                  -- would quietly start saving sessions under the wrong name.
                  -- `false` removes a key without binding anything in its place.
                  ["<c-e>"] = false,
                  ["<c-f>"] = false,
                  ["<c-g>"] = false,
                  ["<c-w>"] = false,
                  ["<c-t>"] = false,

                  ["<c-x>"] = { "forget_project", mode = { "i", "n" } },
                  ["<c-d>"] = { "delete_session", mode = { "i", "n" } },
                },
              },
            },
          }
        end,
        desc = "project switch",
      },
    },
  },

  -- Sessions, keyed on cwd and git branch. `dir` is deliberately not set: the
  -- default is restated in lua/project.lua, which has to find session files
  -- before this plugin has loaded, and overriding it here is how the two would
  -- drift apart.
  {
    "folke/persistence.nvim",
    opts = { need = 1, branch = true },

    -- An event and not only `keys`, because the whole point of the plugin is an
    -- autosave on VimLeavePre, and `defaults.lazy = true` (lua/configs/lazy.lua)
    -- means a keys-only spec would never arm it unless a <leader>p map happened
    -- to be pressed first. These two events are exactly the right trigger rather
    -- than a conservative guess: `need = 1` makes persistence decline to save a
    -- session with no file buffers in it, so there is nothing to lose by not
    -- loading until the first file buffer exists.
    event = { "BufReadPre", "BufNewFile" },

    keys = {
      {
        "<leader>ps",
        function()
          require("persistence").load()
        end,
        desc = "project restore session (cwd)",
      },
      {
        "<leader>pl",
        function()
          require("persistence").load { last = true }
        end,
        desc = "project restore last session",
      },
      {
        "<leader>pS",
        function()
          require("persistence").select()
        end,
        desc = "project select session",
      },
      -- Stops the autosave for the rest of this nvim run, so an exploratory
      -- detour through a project does not become its remembered layout.
      {
        "<leader>pd",
        function()
          require("persistence").stop()
          vim.notify "session saving stopped for this run"
        end,
        desc = "project stop saving session",
      },
    },
  },
}
