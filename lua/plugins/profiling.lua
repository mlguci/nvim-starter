-- Profiling: record, read the cost beside the source, jump to what is hot. The
-- logic is lua/profiling/, and perfanno.nvim draws the annotations and runs the
-- hottest-line finders. Plain `opts` is not used because perfanno's highlight
-- helpers have to be required at setup time.
local function perfanno(command)
  return "<cmd>" .. command .. "<cr>"
end

local function profiling(method)
  return function()
    require("profiling")[method]()
  end
end

vim.api.nvim_create_user_command("ProfileBaseline", function()
  require("profiling").save_baseline()
end, { desc = "keep the current binary as the <leader>Pb baseline" })

return {
  {
    "t-troebst/perfanno.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    cmd = {
      "PerfLoadFlat",
      "PerfLoadCallGraph",
      "PerfLoadFlameGraph",
      "PerfAnnotate",
      "PerfToggleAnnotations",
      "PerfAnnotateFunction",
      "PerfPickEvent",
      "PerfCycleFormat",
      "PerfHottestLines",
      "PerfHottestSymbols",
      "PerfHottestCallersFunction",
    },

    config = function()
      local util = require "perfanno.util"

      -- Nord's aurora red, so hot lines match the theme lua/chadrc.lua sets. The
      -- background is the ramp from it to the normal background, and the first
      -- argument being nil is what asks perfanno to read that background.
      local red = "#BF616A"
      require("perfanno").setup {
        line_highlights = util.make_bg_highlights(nil, red, 10),
        vt_highlight = util.make_fg_highlight(red),

        -- lua/profiling/init.lua annotates itself after choosing which event to
        -- show. Left on, perfanno would ask for that choice first.
        annotate_after_load = false,
      }
    end,

    -- Keys for perfanno's own commands sit here beside the ones for
    -- lua/profiling/, as one group is what a user reads them as.
    keys = {
      { "<leader>Pr", profiling "record", desc = "profile record" },
      { "<leader>PR", profiling "record_deep", desc = "profile deep record (Instruments / perf)" },
      { "<leader>Pa", profiling "attach", desc = "profile attach to process" },
      { "<leader>Pl", profiling "pick", desc = "profile load recording" },
      { "<leader>Pv", profiling "flamegraph", desc = "profile flamegraph" },
      { "<leader>Pi", profiling "open_gui", desc = "profile open deep recording" },
      { "<leader>Pb", profiling "benchmark", desc = "profile benchmark against baseline" },
      { "<leader>Pm", profiling "leak_check", desc = "profile leak check" },
      { "<leader>PM", profiling "heap", desc = "profile heap growth" },
      { "<leader>PB", profiling "build_time", desc = "profile build time" },
      { "<leader>Pe", perfanno "PerfPickEvent", desc = "profile pick event" },
      { "<leader>Pt", perfanno "PerfToggleAnnotations", desc = "profile toggle annotations" },
      { "<leader>Pf", perfanno "PerfAnnotateFunction", desc = "profile annotate function" },
      { "<leader>Ph", perfanno "PerfHottestLines", desc = "profile hottest lines" },
      { "<leader>Ps", perfanno "PerfHottestSymbols", desc = "profile hottest symbols" },
      { "<leader>Pc", perfanno "PerfHottestCallersFunction", desc = "profile hottest callers of function" },
    },
  },
}
