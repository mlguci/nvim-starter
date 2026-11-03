# nvim

A Neovim config built on [NvChad](https://github.com/NvChad/NvChad) v2.5, which
is used here as a plugin rather than as a framework to live inside: this repo is
the config, and `init.lua` pulls NvChad in as the first spec.

Oriented around four things — C/C++ with CMake, Python with uv, markdown notes,
and dotfiles managed by chezmoi — plus a project switcher that restores a session, a file
tree and a task list per project.

## Prerequisites

Neovim **0.11 or newer**. The LSP setup uses `vim.lsp.config` / `vim.lsp.enable`,
which do not exist before 0.11.

Everything below is a host dependency. The plugins are pinned in
`lazy-lock.json` and the Mason packages are listed in `lua/configs/mason.lua`,
but nothing in this repo can install a system package for you.

```sh
brew install neovim git ripgrep fd python@3.13 cmake ninja llvm uv chezmoi pandoc jq
```

| Formula | Needed by |
| --- | --- |
| `ripgrep`, `fd` | the `<leader>f` and `<leader>p` pickers — telescope's `live_grep` and `find_files` shell out to them |
| `python@3.13` | Mason's PyPI packages (clang-format, gersemi), which it installs into a venv |
| `cmake`, `ninja` | the `<leader>cm` workflow. `lua/configs/cmake.lua` sets `CMAKE_GENERATOR=Ninja` |
| `llvm` | clangd. `lua/configs/lspconfig.lua` prefers Homebrew's build (23.x) over the Apple one that wins on `PATH` (21.x), and falls back to bare `clangd` when it is absent — so this is the one entry that is a preference rather than a hard requirement. Its `llvm-cxxfilt` demangles the `<leader>cs` assembly view, with the system `c++filt` as the fallback |
| `uv` | Python. `:PythonHostInstall` builds the venv molten runs on with it, and the projects it manages are what `lua/python.lua` looks for: the nearest `.venv` at or above the file. Projects are expected to bring their own venv (`uv sync`); nothing here creates one |
| `chezmoi` | optional: the `<leader>C` group, chezmoi.nvim and the filetype recovery and apply-on-save in `lua/autocmds.lua`. When the binary is not on `PATH` all of it is skipped (`require("dotfiles").enabled`), so the config works unchanged on machines without chezmoi |
| `pandoc`, `jq` | the `<leader>h` DevDocs group. devdocs.nvim pipes each docset through both (plus the system `curl`) to turn it into markdown pages; `:checkhealth devdocs` reports anything missing |

The AI sidebars under `<leader>a` each need their own CLI. Claude (`<leader>ac`)
needs the Claude Code CLI, which is not a brew formula:

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

Codex (`<leader>ax`, `lua/codex.lua`) needs OpenAI's Codex CLI. Run `codex` once
afterwards to sign in. Until it is installed, the `<leader>ax` maps only warn:

```sh
npm i -g @openai/codex   # or: brew install codex
```

Remote editing (`<leader>r`, `lua/plugins/remote.lua`) needs nothing extra on
this machine beyond `ssh` and kitty, which the remote UI opens in. The remote
host needs only an SSH server, `bash`, `curl` or `wget`, and access to GitHub. `:RemoteStart`
installs Neovim there, copies this config over, and lazy and Mason then install
the Linux builds of everything on the first start.

## Install

```sh
git clone git@github.com:mlguci/nvim-starter.git ~/.config/nvim
nvim --headless "+Lazy! restore" +qa     # plugins, at the pinned commits
nvim --headless +MasonInstallAll +qa     # formatters, servers, debug adapters
nvim --headless +PythonHostInstall +qa   # the python3 host molten runs on
nvim --headless "+Lazy! build molten-nvim" +qa   # register molten with that host
```

The last two are only for Jupyter notebooks (`<leader>j`). Molten is a remote
plugin: it runs on Neovim's python3 provider, which NvChad switches off and
`lua/options.lua` switches back on once the host venv exists, and its commands
only exist after `:UpdateRemotePlugins` -- which is what its build step runs --
has seen it with that host in place. Order matters for that reason.

`restore` rather than `sync`: `sync` updates to upstream HEAD and rewrites
`lazy-lock.json`, which defeats the point of having one. Treesitter parsers
install themselves on first use; `:TSInstallAll` does the lot up front.

Starting nvim normally is also fine — plugins bootstrap on first launch. Only
the Mason step genuinely has to be asked for.

## Layout

```text
init.lua              lazy bootstrap, NvChad spec, load order
lua/
  chadrc.lua          NvChad overrides: theme, winbar colours, statusline, nvdash
  options.lua         vim options
  autocmds.lua        terminal mode memory, chezmoi filetype recovery and apply-on-save
  mappings.lua        all keymaps not attached to a lazy spec
  project.lua         project registry, session restore, per-project teardown
  dotfiles.lua        chezmoi source <-> $HOME path mapping. No plugin dependency
  winbar.lua          'winbar' expression — the active-window cue
  python.lua          which interpreter a buffer runs on (.venv lookup), # %% cells, the host venv
  docs.lua            DevDocs picker, grep, float viewer and HTML -> markdown conversion
  asm.lua             godbolt-style assembly view, compiled locally from compile_commands.json
  rumdl.lua           which config the markdown formatter and linter run with
pandoc/devdocs.lua    pandoc filter for that conversion: HTML-only tables etc. into markdown
.rumdl.toml           fallback rumdl rules for markdown whose project has none
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
  them. They hold the _why_; the specs hold the loading conditions and keys.

## Keymaps

Leader is `<Space>`. `<leader>?K` lists everything; the groups are:

| Prefix | Group                           | Prefix | Group                |
| ------ | ------------------------------- | ------ | -------------------- |
| `a`    | Claude                          | `i`    | Python REPL (iron)   |
| `b`    | Buffers                         | `j`    | Jupyter (molten)     |
| `c`    | Code / LSP                      | `m`    | Markdown             |
| `cm`   | CMake                           | `p`    | Projects             |
| `cw`   | Workspace folders (LSP buffers) | `q`    | Quit                 |
| `C`    | Chezmoi                         | `r`    | Remote (remote-nvim) |
| `d`    | Debug                           | `t`    | Terminal             |
| `f`    | Find                            | `T`    | Tests (neotest)      |
| `g`    | Git                             | `u`    | UI toggles           |
| `h`    | Docs (DevDocs)                  | `w`    | Windows              |
|        |                                 | `?`    | Keymaps              |

The group definitions live in the which-key spec in `lua/plugins/init.lua`,
which also lists the members of each group in a trailing comment — keep those in
sync with `lua/mappings.lua`.

Windows: opening a file from nvim-tree reuses the editor window you were last
in, with no window-letter prompt (`<C-v>`/`<C-x>`/`<C-t>` in the tree still split
or open a tab). `<leader>ww` is a window mode that keeps the `<C-w>` menu open
until `<Esc>`, so resizing and moving windows doesn't need repeated chords. `<A-m>` or
`<leader>wm` maximizes and restores, and `<C-A-h/j/k/l>` resizes by 5, also from
inside a terminal.

## Formatting

Saving a buffer formats it with conform (`lua/configs/conform.lua`). That
includes Python, where `ruff_fix` removes imports that are unused at the moment
you save. `:FormatDisable` turns it off globally and `:FormatDisable!` for the
current buffer. `:FormatEnable` turns both back on, and `<leader>cF` toggles the
global switch. `<leader>cf` formats on demand.

Markdown is formatted by [rumdl](https://github.com/rvben/rumdl), which applies
the fixes for the markdownlint rules. Then `injected` formats each fenced code
block with the formatter for its language. A table is aligned when it fits in
80 columns and left unpadded when it would not. rumdl's language server reports
the rules it cannot fix as diagnostics. rumdl uses a project's own rumdl or
markdownlint config when there is one, and otherwise this repo's `.rumdl.toml`
(`lua/rumdl.lua`).

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
