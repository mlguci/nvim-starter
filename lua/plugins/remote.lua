-- Remote editing in the style of VS Code Remote-SSH. :RemoteStart installs Neovim on
-- the remote host, copies this config there, and starts a headless server. It then
-- forwards the server's port and attaches a local `nvim --remote-ui`. Only drawing
-- happens on this machine. clangd, :make, the debugger and terminals all run on the
-- remote, next to the code, its headers and its compile_commands.json. That is the
-- point for C++: a clangd running locally against sshfs-mounted sources sees the wrong
-- toolchain and the wrong paths.
--
-- On the first start for a host, lazy and Mason install everything again on the remote.
-- That gives Linux builds of clangd, codelldb and the rest, so it takes a while. Later
-- starts reuse that install. <leader>rc removes it.
--
-- A plain `opts` table for the reason given on the neogit spec in
-- lua/plugins/init.lua.
return {
  {
    "amitds1997/remote-nvim.nvim",
    version = "*",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-telescope/telescope.nvim", -- picks between ssh / devpod and between saved hosts
    },
    cmd = { "RemoteStart", "RemoteStop", "RemoteInfo", "RemoteCleanup", "RemoteConfigDel", "RemoteLog" },

    opts = {
      -- The plugin's default puts the remote UI in a floating terminal inside this
      -- Neovim. Instead, open it in its own kitty OS window, so the remote session gets
      -- a whole window and its own title. This launches kitty as a new process, which
      -- needs no allow_remote_control in kitty.conf. The full path is the fallback for
      -- when Neovim was started without kitty's directory on PATH.
      client_callback = function(port, workspace_config)
        local kitty = vim.fn.exepath "kitty"
        if kitty == "" then
          kitty = "/Applications/kitty.app/Contents/MacOS/kitty"
        end
        vim.fn.jobstart({
          kitty,
          "--title",
          "remote: " .. workspace_config.host,
          "nvim",
          "--server",
          "localhost:" .. port,
          "--remote-ui",
        }, { detach = true })
      end,
    },

    keys = {
      { "<leader>rs", "<cmd>RemoteStart<cr>", desc = "remote start / connect" },
      { "<leader>rS", "<cmd>RemoteStop<cr>", desc = "remote stop session" },
      { "<leader>ri", "<cmd>RemoteInfo<cr>", desc = "remote session info" },
      { "<leader>rc", "<cmd>RemoteCleanup<cr>", desc = "remote cleanup install on host" },
      { "<leader>rd", "<cmd>RemoteConfigDel<cr>", desc = "remote forget saved host" },
      { "<leader>rl", "<cmd>RemoteLog<cr>", desc = "remote open log" },
    },
  },
}
