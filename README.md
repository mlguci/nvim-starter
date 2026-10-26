# nvim

A Neovim config built on [NvChad](https://github.com/NvChad/NvChad) v2.5, which
is used here as a plugin rather than as a framework to live inside: this repo is
the config, and `init.lua` pulls NvChad in as the first spec.

Oriented around three things — C/C++ with CMake, markdown notes, and dotfiles
managed by chezmoi — plus a project switcher that restores a session, a file
tree and a task list per project.

## Prerequisites

Neovim **0.11 or newer**. The LSP setup uses `vim.lsp.config` / `vim.lsp.enable`,
which do not exist before 0.11.

Everything below is a host dependency. The plugins are pinned in
`lazy-lock.json` and the Mason packages are listed in `lua/configs/mason.lua`,
but nothing in this repo can install a system package for you.

```sh
brew install neovim git ripgrep fd node python@3.13 cmake ninja llvm chezmoi
```

| Formula | Needed by |
| --- | --- |
| `ripgrep`, `fd` | the `<leader>f` and `<leader>p` pickers — telescope's `live_grep` and `find_files` shell out to them |
| `node` | Mason's npm packages (prettier, markdownlint-cli2) and markdown-preview's `yarn install` build step |
| `python@3.13` | Mason's PyPI packages (clang-format, gersemi), which it installs into a venv |
| `cmake`, `ninja` | the `<leader>cm` workflow. `lua/configs/cmake.lua` sets `CMAKE_GENERATOR=Ninja` |
| `llvm` | clangd. `lua/configs/lspconfig.lua` prefers Homebrew's build (23.x) over the Apple one that wins on `PATH` (21.x), and falls back to bare `clangd` when it is absent — so this is the one entry that is a preference rather than a hard requirement |
| `chezmoi` | the `<leader>C` group and the apply-on-save in `lua/autocmds.lua`. Without it those maps fail; the rest of the config is unaffected |

The Claude sidebar (`<leader>a`) needs the Claude Code CLI, which is not a brew
formula:

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

## Install

```sh
git clone git@github.com:mlguci/nvim-starter.git ~/.config/nvim
nvim --headless "+Lazy! restore" +qa     # plugins, at the pinned commits
nvim --headless +MasonInstallAll +qa     # formatters, servers, debug adapter
```

`restore` rather than `sync`: `sync` updates to upstream HEAD and rewrites
`lazy-lock.json`, which defeats the point of having one. Treesitter parsers
install themselves on first use; `:TSInstallAll` does the lot up front.

Starting nvim normally is also fine — plugins bootstrap on first launch. Only
the Mason step genuinely has to be asked for.

## Layout

```
init.lua              lazy bootstrap, NvChad spec, load order
lua/
  chadrc.lua          NvChad overrides: theme, winbar colours, statusline, nvdash
  options.lua         vim options
  autocmds.lua        terminal mode memory, chezmoi filetype recovery and apply-on-save
  mappings.lua        all keymaps not attached to a lazy spec
  project.lua         project registry, session restore, per-project teardown
  dotfiles.lua        chezmoi source <-> $HOME path mapping. No plugin dependency
  winbar.lua          'winbar' expression — the active-window cue
  plugins/            lazy specs, one file per concern
  configs/            plugin options, required from the specs
```

Two conventions worth knowing before editing:

- **NvChad's `opts` functions discard incoming fragments.** Several NvChad specs
  define `opts` as a function that ignores its second argument and returns a
  fresh table, so a plain `opts = { ... }` of yours can be dropped on the floor.
  Where that bites, the fragments here are functions that edit what they are
  handed, or restate NvChad's defaults — see the comments on the blink,
  telescope and treesitter fragments in `lua/plugins/init.lua`.
- **`lua/configs/*.lua` are plain modules**, `require`d from the spec that owns
  them. They hold the *why*; the specs hold the loading conditions and keys.

## Keymaps

Leader is `<Space>`. `<leader>?k` lists everything; the groups are:

| Prefix | Group | Prefix | Group |
| --- | --- | --- | --- |
| `a` | Claude | `m` | Markdown |
| `b` | Buffers | `p` | Projects |
| `c` | Code | `q` | Quit |
| `cm` | CMake | `r` | Rename (LSP buffers) |
| `C` | Chezmoi | `t` | Terminal |
| `d` | Debug / diagnostics | `u` | UI toggles |
| `f` | Find files / search | `w` | Workspace (LSP buffers) |
| `g` | Git | `?` | Help / keymaps |

The group definitions live in the which-key spec in `lua/plugins/init.lua`,
which also lists the members of each group in a trailing comment — keep those in
sync with `lua/mappings.lua`.

## Maintenance

| | |
| --- | --- |
| Update plugins | `:Lazy sync`, then commit `lazy-lock.json` |
| Roll back to the lockfile | `:Lazy restore` |
| Add an external tool | add it to `ensure_installed` in `lua/configs/mason.lua`, then `:MasonInstallAll` |
| Add a language server | `vim.lsp.enable` list in `lua/configs/lspconfig.lua` **and** the Mason list, or it fails silently per buffer |
| Format this repo | `stylua .` — settings in `.stylua.toml` |

`.claude/settings.local.json` is gitignored: it holds absolute per-machine paths
and is not shareable.

## Credits

- [NvChad](https://github.com/NvChad/NvChad) — used as a plugin, v2.5 branch.
- [LazyVim starter](https://github.com/LazyVim/starter), by way of NvChad's
  starter, which was inspired by it.
