# tinker-nvim

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

## License

MIT
