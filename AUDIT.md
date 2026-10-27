# Security audit

Date: 2026-10-27 · Neovim 0.12.6 · repo at `8ee3cb3` plus the `lua/chadrc.lua` fix
described under finding 1.

## Scope and method

- **Repo code** — every tracked file, read in full and checked for code-execution
  sinks (shell and process launches, `vim.cmd` / `dofile` / `:source`, statusline
  expressions, build hooks) and for the data that reaches them.
- **Plugins** — not audited for code execution. Verified only for provenance:
  remote URL, pinned commit, upstream reachability, local tampering, and checksums
  for prebuilt binaries.
- **Also checked** — git history for secrets, file permissions on the config, data
  and state directories, effective security options with the config loaded, Mason
  package sources, and the gitignored `.claude/settings.local.json`.
- **Evidence** — behaviour claims marked *verified* were reproduced in headless
  Neovim with the real config loaded, using scratch `nofile` buffers so that no
  project registry entry, LSP client or session was created.

## Summary

No malicious or hidden code execution was found in the repo. There was one
injection bug in the statusline code (fixed, verified), plus one over-broad local
Claude Code permission file. All 37 plugins come from their canonical GitHub repos
and match `lazy-lock.json` exactly. The remaining items are low or informational,
mostly the familiar case where opening an untrusted repo runs that repo's tooling.

| # | Severity | Status | Where | Issue |
| --- | --- | --- | --- | --- |
| 1 | Medium | **Fixed** | [`lua/chadrc.lua`](lua/chadrc.lua) | CMake statusline module inserted project data without escaping `%`, allowing command execution |
| 2 | Medium | Open | `.claude/settings.local.json` | Rules pre-approve arbitrary Python and reading all of `$HOME` |
| 3 | Low | Open | [`lua/configs/conform.lua`](lua/configs/conform.lua) | Formatters run code supplied by the project |
| 4 | Low | Open | [`lua/plugins/init.lua`](lua/plugins/init.lua) | markdown-preview: unmaintained, vulnerable dependencies, unpinned build |
| 5 | Info | By design | [`lua/autocmds.lua`](lua/autocmds.lua) | Saving a chezmoi source runs `chezmoi apply`, which runs scripts and templates |
| 6 | Info | By design | various | Opening an untrusted repo runs its tooling |
| 7 | Info | Open | `init.lua`, Mason | Supply-chain hygiene |

## Findings

### 1. Statusline expression injection — Medium, fixed

NvChad's statusline is a `%!` expression
(`%!v:lua.require('nvchad.stl.default')()`), so whatever a module returns is
parsed again as statusline format. A `%{...}` item in it is evaluated with no
sandbox, because the option was set from config rather than from a modeline.
[`lua/winbar.lua`](lua/winbar.lua) already escapes `%` for this reason; the
`cmake` module in [`lua/chadrc.lua`](lua/chadrc.lua) did not.

- The build type comes straight from the project: cmake-tools'
  `Preset:get_build_type()` returns `cacheVariables.CMAKE_BUILD_TYPE` from
  `CMakePresets.json` (`cmake-tools/preset.lua:281`). The launch target is a name
  from the build tree.
- A malicious repo can ship
  `"CMAKE_BUILD_TYPE": "%{system('id > /tmp/x')}"`. Selecting that configure
  preset (`<leader>cmp`, or the prompt the first `<leader>cmb` shows) made every
  statusline redraw in a C, C++ or CMake buffer run the command.
- cmake-tools serializes `build_type` and `launch_target` into its per-project
  session (`cmake-tools/session.lua`), so the payload kept running in later
  sessions without being selected again.
- The only constraint on the payload is that it cannot contain `}`.
- Caveat: configuring an untrusted CMake project runs its CMake code anyway. The
  bug added execution at preset *selection*, before any configure, from a JSON
  field that a review of `CMakeLists.txt` would not catch, and it repeated on
  every redraw.

**Fix.** A `stl_literal` helper ([`lua/chadrc.lua:86`](lua/chadrc.lua)) doubles
every `%`. Both getters now go through it (lines 125 and 134).

**Verification** (headless, real NvChad statusline, cmake-tools getters mocked):

| Input | Rendered | Command ran |
| --- | --- | --- |
| Before fix: `%{system('touch …')}` as build type | (evaluated) | **yes**, proof file created |
| After fix: `Debug` / `app` | `Debug 󰑃 app` | — |
| After fix: nothing selected | `no build type` | — |
| After fix: payload in both getters | payload shown literally | no |

**Follow-up (out of scope).** NvChad's own statusline modules render file names
and similar strings through the same `%!` expression. Whether they escape `%` is
plugin code and was not checked; it is the same bug class.

### 2. Over-broad Claude Code permissions — Medium, open

`.claude/settings.local.json` is gitignored and was never committed (checked
across the full history). It still applies to every Claude Code session started
in this directory, including the claudecode.nvim sidebar.

- `Bash(python3 -)` approves any Python program passed in on stdin, network
  access included. In effect this is arbitrary code execution without a prompt.
- `Read(//Users/gunter/**)` approves reading the whole home directory, including
  `~/.ssh`, cloud credentials and tokens.
- Together, a prompt injection in anything Claude reads could read secrets and
  send them out without the user being asked.

**Recommendation.** Remove `Bash(python3 -)`, narrow `Read` to this repo, and
delete the stale one-off rules (the scratchpad `verify.lua` command and the
lazyman `cp` / `rm`). The stale scratchpad rule is not exploitable by other
users, since `/private/tmp/claude-502` is mode `0700`.

### 3. Formatters run project code — Low, open

These run only on `<leader>cf`; format-on-save is off (commented out in
[`lua/configs/conform.lua`](lua/configs/conform.lua)). Keep it off when working
in untrusted repos.

- conform resolves `prettier` from the project's own `node_modules/.bin`
  before Mason's copy (`conform/formatters/prettier.lua:55`). Prettier also
  loads JS config files (`prettier.config.js`, `.prettierrc.cjs`, …) and the
  plugins they name.
- markdownlint-cli2 loads `.markdownlint-cli2.cjs` / `.mjs` config files and
  custom rules.
- gersemi 0.29.2 accepts extensions as paths to Python files.
- clang-format and stylua read declarative config only.

### 4. markdown-preview.nvim — Low, open

- The pinned commit is from 2023-10-17; the plugin is unmaintained.
- Its local preview server ships dependencies with published advisories:
  socket.io 2.4.0, socket.io-parser 3.4.1 (CVE-2022-2421, CVE-2023-32695),
  engine.io 3.5.0 (CVE-2022-41940) and ws 7.4.6 (CVE-2024-37890). These are
  mostly denial-of-service bugs, and the server listens on `127.0.0.1` only
  while a preview is open (`g:mkdp_open_to_the_world` defaults to 0).
- The build step `cd app && npx --yes yarn install` downloads whatever `yarn`
  version is latest and runs the dependencies' install scripts.

**Recommendation.** Consider dropping it; render-markdown.nvim already renders
markdown in the editor.

### 5. chezmoi apply-on-save — Info, by design

The `ChezmoiApply` autocmd ([`lua/autocmds.lua:106`](lua/autocmds.lua)) calls
`chezmoi apply --source-path <file>` with arguments as a list
([`lua/dotfiles.lua:76`](lua/dotfiles.lua)), so there is no shell or option
injection. But `chezmoi apply` runs `run_` / `modify_` scripts and evaluates
templates, which can call `output`. Any write from nvim triggers it, including
`:wa` or an accepted Claude diff.

Today the source directory has no scripts, no templates and no git remote, so
nothing is exposed.

### 6. Untrusted-repo exposure — Info, by design

- `cmake_regenerate_on_save` ([`lua/configs/cmake.lua`](lua/configs/cmake.lua))
  runs CMake configure, and so the project's own code, when a `CMakeLists.txt`
  is saved.
- gitsigns, nvim-tree and neogit run git, which obeys repo-local settings such
  as `core.fsmonitor`. This matters only for repos obtained from an archive
  rather than a clone.
- clangd reads the repo's `compile_commands.json` and `.clangd`, but runs
  without `--query-driver`, so it does not execute the compiler named in the
  compilation database.

### 7. Supply-chain hygiene — Info, open

- The bootstrap in [`init.lua`](init.lua) clones lazy.nvim's `stable` branch
  unpinned; the lockfile only takes over at `Lazy! restore`.
- `import = "nvchad.plugins"` lets NvChad upstream add plugins whenever
  `:Lazy sync` runs.
- Mason installs the latest version of each tool; nothing pins them.
- gersemi's virtualenv uses Apple's Command Line Tools Python 3.9.6, which is
  end-of-life, not the `python@3.13` the README asks for.
- `nvim-cmp` is listed in `lazy-lock.json` but not installed (stale entry).
- The README's `curl -fsSL https://claude.ai/install.sh | bash` pipes a script to
  the shell; it is the vendor's official installer.

## Code-execution points in the repo

| Location | What runs | Verdict |
| --- | --- | --- |
| `init.lua:9` | `git clone`, arguments as a list | Safe |
| `init.lua:29`, `lua/plugins/project.lua:57` | `dofile` on the base46 cache | Same trust level as the plugin directory |
| `lua/dotfiles.lua:76` | `chezmoi apply`, arguments as a list | No injection; see finding 5 |
| `lua/mappings.lua:27` | `vim.cmd("WhichKey " .. input())` | Only text the user types |
| `lua/mappings.lua:128` | `vim.cmd(vim.t.restore_cmd)` | Value from `winrestcmd()`; tab variables are not saved in sessions or ShaDa |
| `lua/mappings.lua:148` | `chezmoi diff` in a terminal | Fixed string |
| `lua/configs/mason.lua:74` | `MasonInstall` with a static list | Safe |
| `lua/project.lua:519`, `:574` | `:cd` with `fnameescape` | Safe |
| `lua/project.lua:536`, `:624` | Session restore (sources Vimscript) | Files live in `~/.local/state/nvim` (mode `0700`), outside any project, so a repo cannot plant one |
| `lua/winbar.lua:51` | Window bar `%!` expression | Escapes `%`; *verified*, a crafted file name renders literally |
| `lua/chadrc.lua:141` | Statusline `cmake` module | Finding 1, fixed |
| `lua/plugins/init.lua:225` | markdown-preview build command | Finding 4 |

## Plugin provenance — pass

- **Origin.** All 37 installed plugins come from `https://github.com/<owner>/<repo>`
  (lazy.nvim's default URL format, not overridden). Each is the canonical repo;
  none is archived or a third-party fork.
- **Pinning.** Every installed `HEAD` equals its `lazy-lock.json` commit and is
  reachable from the upstream branch. blink.cmp sits on tag `v1.10.2` on
  `origin/v1`, as selected by NvChad's version spec. No tracked files are
  modified in any plugin checkout.
- **Native code.** blink.cmp's prebuilt `libblink_cmp_fuzzy.dylib` matches the
  SHA-256 published with the official v1.10.2 release. LuaSnip's `.so` files are
  upstream test fixtures, tracked in its repo.
- **Mason.** Uses the official `mason-org/mason-registry`. Packages come from
  PyPI (clang-format, gersemi), npm (prettier, markdownlint-cli2) and each tool's
  own GitHub releases (codelldb, marksman, neocmakelsp, stylua).
- **Treesitter parsers.** Revisions are pinned by nvim-treesitter. Most come from
  the `tree-sitter`, `tree-sitter-grammars` and `neovim` orgs; three are
  single-maintainer repos: `uyha/tree-sitter-cmake`,
  `the-mikedavis/tree-sitter-git-config`, `georgeharker/tree-sitter-zsh`.
- **Smallest projects.** `xvzc/chezmoi.nvim` (219★) and
  `Civitasv/cmake-tools.nvim` (562★) each have a single maintainer; re-check them
  on update. `sindrets/diffview.nvim` has not been pushed since 2024-08, and
  `iamcco/markdown-preview.nvim` is covered in finding 4.

## Controls already in place

- `exrc` and `modelineexpr` are off; `modeline` is at Neovim's default.
- netrw, tar, zip, gzip, getscript and vimball are disabled in
  [`lua/configs/lazy.lua`](lua/configs/lazy.lua). These built-in plugins have had
  command-injection CVEs, for example tar.vim CVE-2025-27423 and zip.vim
  CVE-2025-29768.
- Every external process is started with an argument list, never an
  interpolated shell string; the two shell strings are fixed text.
- The project registry is decoded inside `pcall` and used only as directory
  names. Session deletion matches exact file names inside the sessions
  directory, so it cannot reach outside it.
- No secrets in the working tree or the git history; `.claude/` was never
  committed.
- Nothing in the config, data or state directories is world-writable.
