# tinker-nvim

> Part of the **tinker** toolkit: [tinker-cli](https://github.com/munziu263/tinker-cli) · **tinker-nvim** (this repo)

A Neovim plugin for interactive code exploration. Sends cells to a REPL and runs files with a configurable command. Uses [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) for terminal management.

This is the editor-side companion to [tinker-cli](https://github.com/munziu263/tinker-cli) -- the CLI produces demo files with cell delimiters, and this plugin runs them interactively. They are fully independent: you can use either one without the other.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "munziu263/tinker-nvim",
  event = "VeryLazy",
  dependencies = { "akinsho/toggleterm.nvim" },
  config = function()
    require("tinker").setup()
  end,
}
```

**Dependency:** [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)

## Keybindings

| Key           | Action                     |
|---------------|----------------------------|
| `<leader>rs`  | Send current cell to REPL  |
| `<leader>rf`  | Run file (execute set command) |
| `<leader>rr`  | Rerun last command         |
| `<leader>rc`  | Set run command            |
| `]h`          | Next cell                  |
| `[h`          | Previous cell              |

## Cell formats

Cell delimiters mark boundaries between code blocks. The format depends on the language:

| Language              | Delimiter  |
|-----------------------|------------|
| Python                | `# %%`     |
| Shell (sh, bash)      | `# ---`    |
| Everything else       | `// ---`   |

The Python format (`# %%`) is the percent-format used by jupytext and VS Code. Markdown cells (`# %% [markdown]`) are recognized and skipped when sending to the REPL.

## Configuration

Pass an opts table to `setup()` to override defaults:

```lua
require("tinker").setup({
  -- Override or add REPL configs per filetype
  repl = {
    python = {
      cmd = "ipython",              -- default: "uvx ipython"
      startup = {},                  -- default: autoreload commands
    },
    lua = {
      cmd = "lua",
      startup = {},
    },
  },
  -- Override keymaps (set to false to disable)
  keys = {
    send_cell = "<leader>cs",       -- default: "<leader>rs"
    run_file = "<leader>cr",        -- default: "<leader>rf"
    rerun = "<leader>cx",           -- default: "<leader>rr"
    set_command = "<leader>cc",     -- default: "<leader>rc"
    next_cell = "]c",               -- default: "]h"
    prev_cell = "[c",               -- default: "[h"
  },
})
```

With no arguments, `setup()` uses these defaults:

| Setting | Default |
|---------|---------|
| `repl.python.cmd` | `"uvx ipython"` |
| `repl.python.startup` | `{"%load_ext autoreload", "%autoreload 2"}` |
| `repl.javascript.cmd` | `"node"` |
| `keys.send_cell` | `<leader>rs` |
| `keys.run_file` | `<leader>rf` |
| `keys.rerun` | `<leader>rr` |
| `keys.set_command` | `<leader>rc` |
| `keys.next_cell` | `]h` |
| `keys.prev_cell` | `[h` |

User-provided REPL configs are deep-merged with defaults, so you only need to specify what you want to change.

## Markdown cell highlighting

Python tinker files can contain markdown cells (delimited by `# %% [markdown]`). The plugin highlights them using treesitter and conceals inline markup delimiters. **Both are on by default** — `require("tinker").setup()` with no arguments gets you styled headings, bold, italic, inline code, links, strikethrough, and lists, with `**`, `*`, `_`, `` ` ``, and `~~` markers concealed.

To customize or disable:

```lua
require("tinker").setup({
  markdown_cells = {
    enabled = true,              -- Enable markdown cell highlighting (default: true)
    fallback_highlights = true,  -- Define fallback @markup.* groups (default: true)
    conceal = true,              -- Conceal markup delimiters (default: true)
    concealcursor = "nc",        -- Modes to keep concealment under cursor (default: "nc"; "" reveals)
  },
})

-- Fully disable the feature:
require("tinker").setup({ markdown_cells = { enabled = false } })
```

The `# ` prefix on each line is preserved; highlighting and conceal apply only to the content portion.

**Requirements:** Neovim >= 0.10 with the `markdown` and `markdown_inline` treesitter parsers installed (`:TSInstall markdown markdown_inline`). If they are missing, `setup()` notifies an error and leaves the feature off. Concealment is only visible when `conceallevel >= 1` (set `:set conceallevel=2` in your config — same requirement as every other markdown rendering plugin).

**Known limitations:**

- Fenced code blocks inside markdown cells are highlighted as plain text (no nested language highlighting)

## Cell delimiter highlighting

Every cell-delimiter line (`# %%`, `# %% [markdown]`, `# ---`, `// ---`) gets a full-line background tint so cell boundaries jump out visually. Code and markdown cells use distinct colors so you can tell at a glance which kind of cell is starting.

On by default. Customize or disable:

```lua
require("tinker").setup({
  cell_delimiters = {
    enabled = true,                                   -- default: true
    code_hl = "TinkerCellDelimiter",                  -- highlight group for `# %%`, `# ---`, `// ---`
    markdown_hl = "TinkerCellDelimiterMarkdown",      -- highlight group for `# %% [markdown]`
    fallback_highlights = true,                       -- define subtle default tints
  },
})
```

Supported filetypes: `python`, `sh`, `bash`, `javascript`, `typescript`, `javascriptreact`, `typescriptreact` (same set that `send_cell` understands).

## Terminal setup

The plugin creates two named toggleterm instances:

- **REPL** (ID 50) -- vertical split, runs the language REPL (e.g. IPython, node).
- **Runner** (ID 51) -- vertical split, executes the run command set via `<leader>rc`.

Both open as vertical splits taking half the screen width. The high IDs (50, 51) avoid clashing with any existing toggleterm terminals.

## Workflow

1. Open a file with cell delimiters (a tinker demo file, or any file using the formats above).
2. Press `<leader>rs` to open the REPL and send the current cell. For Python, this launches IPython with autoreload enabled.
3. Navigate between cells with `]h` and `[h`.
4. Press `<leader>rc` to set a run command (e.g. `python main.py`), then `<leader>rf` to execute it in the runner terminal. `<leader>rr` reruns the same command.

## Companion: tinker-cli

[tinker-cli](https://github.com/munziu263/tinker-cli) is a CLI tool that generates demo files for exploring libraries and APIs. Install it with:

```
pip install tinker-cli
```

The CLI produces files with cell delimiters that this plugin can run. See the [tinker-cli repo](https://github.com/munziu263/tinker-cli) for details.

## Development

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) busted-style specs and run against a headless Neovim.

```
make test
```

On first run, this clones plenary into `.deps/` (gitignored). Subsequent runs reuse it. To drop the cache:

```
make clean-deps
```

CI runs the same `make test` command on every push to `master` and on pull requests (see `.github/workflows/test.yml`).

## License

MIT
