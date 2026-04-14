# CLAUDE.md

Guidance for AI assistants working in this repository.

## Project overview

`tinker-nvim` is a small Neovim plugin (pure Lua) for interactive code exploration. It sends code cells to a REPL and runs files via a configurable command, using [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) for terminal management. It is the editor-side companion to [tinker-cli](https://github.com/munziu263/tinker-cli), but the two are fully independent.

## Repository layout

```
.
├── LICENSE                       MIT
├── README.md                     User-facing docs (install, keys, config)
└── lua/
    └── tinker/
        ├── init.lua              Main module: cells, REPL, runner, keymaps, setup()
        └── markdown.lua          Optional treesitter highlighting for `# %% [markdown]` cells
```

There is no `plugin/` directory, no test suite, no build system, and no CI. The plugin is activated entirely by the user calling `require("tinker").setup(opts)` (typically via lazy.nvim). No Vimscript.

## Core concepts

### Cells and delimiters

A "cell" is the range between two delimiter lines. The delimiter pattern is filetype-dependent — see `get_cell_pattern` and `M.next_cell`/`M.prev_cell` in `lua/tinker/init.lua`:

| Filetype      | Delimiter   | Lua pattern              |
|---------------|-------------|--------------------------|
| `python`      | `# %%`      | `^# %%%%`                |
| `sh`, `bash`  | `# ---`     | `^# %-%-%-`              |
| everything else | `// ---`  | `^// %-%-%-`             |

Python additionally recognizes `# %% [markdown]` as a markdown cell. `get_current_cell` skips these when searching backward; if the cursor lands inside one, the user gets a warning and nothing is sent.

Note: `get_cell_pattern` uses escaped Lua patterns (for `string.match`), while `next_cell`/`prev_cell` use Vim regex patterns for `vim.fn.search`. Keep both in sync when changing a delimiter.

### REPL terminal (ID 50) and Runner terminal (ID 51)

Two named toggleterm terminals are created lazily:

- **REPL** (`REPL_TERM_ID = 50`) — launched with the filetype's configured `cmd`, receives cells via bracketed paste (`\27[200~…\27[201~`).
- **Runner** (`RUNNER_TERM_ID = 51`) — executes the string set via `<leader>rc`.

Both are vertical splits sized to `vim.o.columns / 2`, with `close_on_exit = false` and `<C-d>`/`<C-u>` rebound in terminal mode to pass through to the underlying shell. High IDs deliberately avoid collisions with user-managed toggleterm instances.

### REPL config resolution

Order of precedence when `send_cell` runs (see `M.send_cell`):

1. `default_repl_config[ft]` — hardcoded defaults (currently `python` and `javascript`).
2. `opts.repl[ft]` passed to `setup()` — deep-merged over defaults.
3. Per-demo `.tinker/<demo>/tinker.toml` `[repl]` section — deep-merged on top, only when the open file's path contains `/.tinker/<demo>/`.

The per-demo TOML parser (`parse_repl_section`) is intentionally minimal: it only understands `cmd = "…"` and `startup = ["…", "…"]` inside a `[repl]` section. Do not reach for a full TOML library; match the narrow format expected from tinker-cli.

Root discovery (`find_project_root`) walks up for `.git`, `pyproject.toml`, `setup.py`, `setup.cfg`, `package.json`, `Cargo.toml` — keep this list aligned with tinker-cli.

### Session state

`state` in `init.lua` holds `run_command` (last command set via `<leader>rc`) and `repl_started` (whether startup commands have been sent). State is module-local, not per-buffer. `repl_started` flips back to `false` if the REPL terminal's buffer becomes invalid.

### Startup sequencing

First `send_cell` opens the REPL and schedules work with `vim.defer_fn`:

- 500 ms wait for the REPL to become interactive,
- optionally send each `startup` line, wait another 200 ms,
- then send the cell as a bracketed-paste block.

Subsequent sends skip the delays. If you change this, remember that IPython needs time to initialize and that interleaving startup + first cell without a delay causes lost input.

### Markdown cell highlighting (`markdown.lua`)

Opt-in via `opts.markdown_cells.enabled = true`. Finds `# %% [markdown]` regions, strips the `# ` prefix, parses the content with the treesitter markdown parser, and projects capture ranges back into the buffer as extmarks in the `tinker_markdown` namespace. `set_fallback_highlights` defines `@markup.*` groups with `default = true` so they don't override a colorscheme that already defines them. Re-applied on `BufEnter`, `TextChanged`, `InsertLeave` for `*.py`. Known limits: no inline injection chaining, no nested code-block language highlights, requires Neovim ≥ 0.10.

## Public API

From `require("tinker")`:

- `setup(opts)` — merge config, register keymaps, optionally enable markdown highlighting.
- `send_cell()` — send current cell to REPL.
- `run_file()` / `rerun()` — run stored command in runner terminal (`rerun` is an alias).
- `set_command()` — prompt for and store a run command.
- `next_cell()` / `prev_cell()` — jump to adjacent delimiter.

All five actions are bound in `setup()` via `keymap_actions`. Setting a key to `false` in `opts.keys` disables that binding.

## Conventions

- **Two-space indentation, no tabs.** Match the existing style.
- **`local M = {}` … `return M`** module pattern. Private helpers are `local function`s; public entry points hang off `M`.
- **Comment style:** top-of-file block summary, then short `--` comments above non-obvious functions. `markdown.lua` uses LuaLS-style `--- @param` annotations; `init.lua` does not. Don't retrofit annotations unless you're already rewriting the function.
- **Guard external calls with `pcall`.** Treesitter, toggleterm, and extmark APIs are all wrapped in `pcall` in `markdown.lua`. Preserve that — this plugin should never blow up a user's Neovim session.
- **Defaults then deep-merge.** Use `vim.tbl_deep_extend("force", defaults, user)` so users can override one field without restating the whole table.
- **Keymap descriptions** follow the `[R]EPL [S]end cell` style (capitalized letters hint the mnemonic). Keep it.
- **No new runtime dependencies.** Only `toggleterm.nvim` and (optionally) the nvim-treesitter markdown parser.

## Development workflow

There are no tests, linters, or formatters wired up. To validate a change:

1. Point a local Neovim config at the working tree (e.g. `dir = "/home/user/tinker-nvim"` in a lazy.nvim spec).
2. Open a Python or shell file with cell delimiters.
3. Exercise `<leader>rs`, `<leader>rf`, `<leader>rc`, `]h`, `[h`.
4. For markdown work, set `markdown_cells = { enabled = true }` and open a file with `# %% [markdown]` cells.

If you can't run Neovim, say so in the response — don't claim a feature works when you haven't exercised it.

## Git workflow

- Default branch: `main`.
- Commit style from history: Conventional Commits (`feat:`, `fix:`) with an optional `(#N)` / `(closes #N)` issue reference. Keep subject lines short and imperative.
- Work on a feature branch; do not push directly to `main`.
- **Do not create pull requests unless the user explicitly asks.**

## When editing

- Changing a delimiter format? Update both `get_cell_pattern` (init.lua Lua patterns) and `next_cell`/`prev_cell` (Vim regex), the README table, and `find_markdown_cells` if Python is involved.
- Adding a new filetype REPL default? Add to `default_repl_config` and mention it in the README's defaults table.
- Adding a new keymap? Extend `default_keys` and `keymap_actions` together, and update the README keybindings table.
- Touching TOML parsing? Remember it's intentionally minimal; coordinate with tinker-cli's actual output format before expanding it.
