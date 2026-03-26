-- tinker.lua — Interactive code exploration for Neovim
-- Replaces script-runner.lua
--
-- Keymaps:
--   <leader>rs  Send current cell to REPL
--   <leader>rf  Run file (execute set command)
--   <leader>rr  Rerun last command
--   <leader>rc  Set run command
--   ]h / [h     Navigate cells

local Tinker = {}

-- REPL configuration per filetype
local repl_config = {
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
      -- For Python, check if this is a markdown cell
      if ft == "python" and is_markdown_cell(line) then
        -- Skip markdown cells - keep searching backward
        -- But first check if cursor is actually IN this markdown cell
        if i == cursor_row then
          -- Cursor is on the markdown delimiter itself, keep searching
        else
          -- We found a markdown cell above, keep searching for a code cell
        end
      else
        cell_start = i
        found_delimiter = true
        break
      end
    end
  end

  -- If we landed on a markdown cell delimiter or the cursor is in a markdown cell,
  -- we need to handle this case
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
    -- Check if the terminal buffer is still valid
    if term.bufnr and vim.api.nvim_buf_is_valid(term.bufnr) then
      return term
    else
      -- Terminal died, reset state
      state.repl_started = false
    end
  end

  -- Create new terminal
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

-- Send current cell to REPL
function Tinker.send_cell()
  local ft = vim.bo.filetype
  local config = repl_config[ft]

  if not config then
    vim.notify("No REPL configured for filetype: " .. ft, vim.log.levels.WARN)
    return
  end

  local lines, err = get_current_cell()
  if not lines then
    vim.notify(err, vim.log.levels.WARN)
    return
  end

  local term = get_repl_terminal(config.cmd)

  if not state.repl_started then
    -- First time: open terminal and send startup commands
    term:open()
    state.repl_started = true

    -- Send startup commands after a short delay
    if #config.startup > 0 then
      vim.defer_fn(function()
        for _, cmd in ipairs(config.startup) do
          term:send({ cmd })
        end
        -- Send the cell after startup
        vim.defer_fn(function()
          term:send(lines)
        end, 200)
      end, 500)
    else
      vim.defer_fn(function()
        term:send(lines)
      end, 500)
    end
  else
    -- Terminal already running, just ensure it's visible and send
    if not term:is_open() then
      term:open()
    end
    term:send(lines)
  end

  -- Return focus to the code buffer
  vim.cmd("wincmd p")
end

-- Run file with set command
function Tinker.run_file()
  if not state.run_command then
    vim.notify("No run command set. Use <leader>rc to set one.", vim.log.levels.WARN)
    return
  end

  local term = get_runner_terminal()
  if not term:is_open() then
    term:open()
  end

  term:send({ state.run_command })

  -- Return focus to code buffer
  vim.cmd("wincmd p")
end

-- Rerun last command (alias for run_file)
function Tinker.rerun()
  Tinker.run_file()
end

-- Set the run command
function Tinker.set_command()
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
function Tinker.next_cell()
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
function Tinker.prev_cell()
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

-- Lazy.nvim plugin spec
return {
  dir = vim.fn.stdpath("config") .. "/lua/custom/plugins",
  name = "tinker",
  event = "VeryLazy",
  dependencies = { "akinsho/toggleterm.nvim" },
  config = function()
    vim.keymap.set("n", "<leader>rs", Tinker.send_cell, { desc = "[R]EPL [S]end cell" })
    vim.keymap.set("n", "<leader>rf", Tinker.run_file, { desc = "[R]un [F]ile" })
    vim.keymap.set("n", "<leader>rr", Tinker.rerun, { desc = "[R]e-[R]un last command" })
    vim.keymap.set("n", "<leader>rc", Tinker.set_command, { desc = "[R]un [C]ommand set" })
    vim.keymap.set("n", "]h", Tinker.next_cell, { desc = "Next cell" })
    vim.keymap.set("n", "[h", Tinker.prev_cell, { desc = "Previous cell" })
  end,
}
