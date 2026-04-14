-- tinker.nvim — Interactive code exploration for Neovim
--
-- Keymaps:
--   <leader>rs  Send current cell to REPL
--   <leader>rf  Run file (execute set command)
--   <leader>rr  Rerun last command
--   <leader>rc  Set run command
--   ]h / [h     Navigate cells

local M = {}

-- Default REPL configuration per filetype
local default_repl_config = {
  python = {
    cmd = "uvx ipython",
    startup = {
      "%load_ext autoreload",
      "%autoreload 2",
    },
  },
  javascript = {
    cmd = "node",
    startup = {},
  },
}

-- Default keymaps
local default_keys = {
  send_cell = "<leader>rs",
  run_file = "<leader>rf",
  rerun = "<leader>rr",
  set_command = "<leader>rc",
  next_cell = "]h",
  prev_cell = "[h",
}

-- Active config (set during setup)
M.repl_config = {}

-- Session state
local state = {
  run_command = nil,
  repl_started = false,
}

-- Terminal IDs (high numbers to avoid clashes)
local REPL_TERM_ID = 50
local RUNNER_TERM_ID = 51

-- Get the cell delimiter pattern for a filetype
local function get_cell_pattern(ft)
  if ft == "python" then
    return "^# %%%%"
  elseif ft == "sh" or ft == "bash" then
    return "^# %-%-%-"
  else
    return "^// %-%-%-"
  end
end

-- Get the cell delimiter for checking markdown cells (Python only)
local function is_markdown_cell(line)
  return line:match("^# %%%% %[markdown%]") ~= nil
end

-- Find cell boundaries around cursor
local function get_current_cell()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] -- 1-indexed
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local ft = vim.bo.filetype
  local pattern = get_cell_pattern(ft)

  -- Search backward for cell delimiter
  local cell_start = 1
  local found_delimiter = false
  for i = cursor_row, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
    if line:match(pattern) then
      if ft == "python" and is_markdown_cell(line) then
        -- Skip markdown cells - keep searching backward
      else
        cell_start = i
        found_delimiter = true
        break
      end
    end
  end

  -- If we landed on a markdown cell, report it
  if found_delimiter and ft == "python" then
    local start_line = vim.api.nvim_buf_get_lines(bufnr, cell_start - 1, cell_start, false)[1]
    if is_markdown_cell(start_line) then
      return nil, "Cursor is in a markdown cell. Move to a code cell."
    end
  end

  -- Search forward for next cell delimiter
  local cell_end = line_count
  for i = (found_delimiter and cell_start + 1 or 2), line_count do
    local line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
    if line:match(pattern) then
      cell_end = i - 1
      break
    end
  end

  -- Extract lines between delimiters (exclusive of delimiter lines)
  local content_start = found_delimiter and cell_start + 1 or cell_start
  local lines = vim.api.nvim_buf_get_lines(bufnr, content_start - 1, cell_end, false)

  -- Trim leading and trailing blank lines
  while #lines > 0 and lines[1]:match("^%s*$") do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines, #lines)
  end

  if #lines == 0 then
    return nil, "Cell is empty"
  end

  return lines, nil
end

-- Get or create the REPL terminal
local function get_repl_terminal(cmd)
  local Terminal = require("toggleterm.terminal").Terminal
  local term = require("toggleterm.terminal").get(REPL_TERM_ID)

  if term then
    if term.bufnr and vim.api.nvim_buf_is_valid(term.bufnr) then
      return term
    else
      state.repl_started = false
    end
  end

  term = Terminal:new({
    cmd = cmd,
    count = REPL_TERM_ID,
    direction = "vertical",
    size = function()
      return math.floor(vim.o.columns / 2)
    end,
    close_on_exit = false,
    on_open = function(t)
      local opts = { buffer = t.bufnr, silent = true }
      vim.keymap.set("t", "<C-d>", [[<C-\><C-n><C-d>]], opts)
      vim.keymap.set("t", "<C-u>", [[<C-\><C-n><C-u>]], opts)
    end,
  })

  return term
end

-- Get or create the runner terminal
local function get_runner_terminal()
  local Terminal = require("toggleterm.terminal").Terminal
  local term = require("toggleterm.terminal").get(RUNNER_TERM_ID)

  if term then
    if term.bufnr and vim.api.nvim_buf_is_valid(term.bufnr) then
      return term
    end
  end

  term = Terminal:new({
    count = RUNNER_TERM_ID,
    direction = "vertical",
    size = function()
      return math.floor(vim.o.columns / 2)
    end,
    close_on_exit = false,
    on_open = function(t)
      local opts = { buffer = t.bufnr, silent = true }
      vim.keymap.set("t", "<C-d>", [[<C-\><C-n><C-d>]], opts)
      vim.keymap.set("t", "<C-u>", [[<C-\><C-n><C-u>]], opts)
    end,
  })

  return term
end

-- Project-root markers (same as tinker CLI)
local root_markers = { ".git", "pyproject.toml", "setup.py", "setup.cfg", "package.json", "Cargo.toml" }

-- Walk up from `path` to find the project root
local function find_project_root(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  while dir and dir ~= "/" do
    for _, marker in ipairs(root_markers) do
      if vim.fn.glob(dir .. "/" .. marker) ~= "" then
        return dir
      end
    end
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  return nil
end

-- Parse a minimal TOML [repl] section from lines
local function parse_repl_section(lines)
  local in_repl = false
  local result = {}
  for _, line in ipairs(lines) do
    if line:match("^%[repl%]") then
      in_repl = true
    elseif in_repl then
      if line:match("^%[") then
        break -- next section
      end
      local key, value = line:match("^(%w+)%s*=%s*(.*)")
      if key and value then
        if key == "cmd" then
          result.cmd = value:match('^"(.*)"')
        elseif key == "startup" then
          -- Parse array: startup = ["a", "b"]
          local items = {}
          for item in value:gmatch('"([^"]*)"') do
            items[#items + 1] = item
          end
          result.startup = items
        end
      end
    end
  end
  if result.cmd or result.startup then
    return result
  end
  return nil
end

-- Read per-demo [repl] config from .tinker/<name>/tinker.toml
local function read_demo_repl_config(filepath)
  if not filepath or not filepath:find("/.tinker/") then
    return nil
  end

  -- Extract demo name: the directory immediately after .tinker/
  local demo_name = filepath:match("/.tinker/([^/]+)")
  if not demo_name then
    return nil
  end

  local root = find_project_root(filepath)
  if not root then
    return nil
  end

  local toml_path = root .. "/.tinker/" .. demo_name .. "/tinker.toml"
  if vim.fn.filereadable(toml_path) ~= 1 then
    return nil
  end

  local lines = vim.fn.readfile(toml_path)
  return parse_repl_section(lines)
end

-- Send current cell to REPL
function M.send_cell()
  local ft = vim.bo.filetype
  local config = M.repl_config[ft]

  if not config then
    vim.notify("No REPL configured for filetype: " .. ft, vim.log.levels.WARN)
    return
  end

  -- Override with per-demo config from tinker.toml if available
  local filepath = vim.api.nvim_buf_get_name(0)
  local demo_config = read_demo_repl_config(filepath)
  if demo_config then
    config = vim.tbl_deep_extend("force", config, demo_config)
  end

  local lines, err = get_current_cell()
  if not lines then
    vim.notify(err, vim.log.levels.WARN)
    return
  end

  local term = get_repl_terminal(config.cmd)

  if not state.repl_started then
    term:open()
    state.repl_started = true

    if #config.startup > 0 then
      vim.defer_fn(function()
        for _, cmd in ipairs(config.startup) do
          term:send({ cmd })
        end
        vim.defer_fn(function()
          local block = table.concat(lines, "\n")
          term:send("\27[200~" .. block .. "\n\27[201~")
        end, 200)
      end, 500)
    else
      vim.defer_fn(function()
        local block = table.concat(lines, "\n")
        term:send("\27[200~" .. block .. "\n\27[201~")
      end, 500)
    end
  else
    if not term:is_open() then
      term:open()
    end
    local block = table.concat(lines, "\n")
    term:send("\27[200~" .. block .. "\n\27[201~")
  end

  vim.cmd("wincmd p")
end

-- Run file with set command
function M.run_file()
  if not state.run_command then
    vim.notify("No run command set. Use <leader>rc to set one.", vim.log.levels.WARN)
    return
  end

  local term = get_runner_terminal()
  if not term:is_open() then
    term:open()
  end

  term:send({ state.run_command })
  vim.cmd("wincmd p")
end

-- Rerun last command (alias for run_file)
function M.rerun()
  M.run_file()
end

-- Set the run command
function M.set_command()
  vim.ui.input({
    prompt = "Run command: ",
    default = state.run_command or "",
  }, function(input)
    if input and input ~= "" then
      state.run_command = input
      vim.notify("Run command set: " .. input, vim.log.levels.INFO)
    end
  end)
end

-- Navigate to next cell
function M.next_cell()
  local ft = vim.bo.filetype
  local search_pattern
  if ft == "python" then
    search_pattern = "^# %%"
  elseif ft == "sh" or ft == "bash" then
    search_pattern = "^# ---"
  else
    search_pattern = "^// ---"
  end
  vim.fn.search(search_pattern, "W")
end

-- Navigate to previous cell
function M.prev_cell()
  local ft = vim.bo.filetype
  local search_pattern
  if ft == "python" then
    search_pattern = "^# %%"
  elseif ft == "sh" or ft == "bash" then
    search_pattern = "^# ---"
  else
    search_pattern = "^// ---"
  end
  vim.fn.search(search_pattern, "bW")
end

-- Setup with optional configuration
--
-- opts.repl: override or extend REPL configs per filetype
-- opts.keys: override default keymaps (set to false to disable)
--
-- Example:
--   require("tinker").setup({
--     repl = {
--       python = { cmd = "ipython", startup = {} },
--       lua = { cmd = "lua", startup = {} },
--     },
--     keys = {
--       send_cell = "<leader>cs",
--       run_file = "<leader>cr",
--     },
--   })
function M.setup(opts)
  opts = opts or {}

  -- Merge REPL configs: defaults + user overrides
  M.repl_config = vim.tbl_deep_extend("force", default_repl_config, opts.repl or {})

  -- Merge keymaps: defaults + user overrides
  local keys = vim.tbl_deep_extend("force", default_keys, opts.keys or {})

  -- Register keymaps (skip any set to false)
  local keymap_actions = {
    send_cell = { fn = M.send_cell, desc = "[R]EPL [S]end cell" },
    run_file = { fn = M.run_file, desc = "[R]un [F]ile" },
    rerun = { fn = M.rerun, desc = "[R]e-[R]un last command" },
    set_command = { fn = M.set_command, desc = "[R]un [C]ommand set" },
    next_cell = { fn = M.next_cell, desc = "Next cell" },
    prev_cell = { fn = M.prev_cell, desc = "Previous cell" },
  }

  for action, lhs in pairs(keys) do
    if lhs and keymap_actions[action] then
      local a = keymap_actions[action]
      vim.keymap.set("n", lhs, a.fn, { desc = a.desc })
    end
  end

  -- Setup markdown cell highlighting (if module is present)
  local md_ok, markdown = pcall(require, "tinker.markdown")
  if md_ok then
    markdown.setup(opts)
  end

  -- Setup cell-delimiter line highlighting (if module is present)
  local cd_ok, cell_delimiters = pcall(require, "tinker.cell_delimiters")
  if cd_ok then
    cell_delimiters.setup(opts.cell_delimiters)
  end
end

return M
