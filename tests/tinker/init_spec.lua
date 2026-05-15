-- Regression spec for lua/tinker/init.lua.
--
-- Tests cover get_current_cell, next_cell, prev_cell, and markdown cell
-- skipping. REPL/terminal integration is out of scope (requires toggleterm).

local tinker = require("tinker")

--- Create a scratch buffer, set its filetype, populate with lines, and
--- position the cursor. Returns the buffer number.
--- @param lines string[]
--- @param filetype string
--- @param cursor_row number 1-indexed row to place the cursor
--- @return integer bufnr
local function make_buf(lines, filetype, cursor_row)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = filetype
  vim.api.nvim_win_set_cursor(0, { cursor_row, 0 })
  return bufnr
end

describe("tinker._get_current_cell", function()
  it("extracts code lines from a Python cell (cursor inside cell)", function()
    make_buf({
      "# %% [markdown]",
      "# Title",
      "",
      "# %%",
      "x = 1",
      "y = 2",
      "",
      "# %%",
      "z = 3",
    }, "python", 5)

    local lines, err = tinker._get_current_cell()
    assert.is_nil(err)
    assert.are.same({ "x = 1", "y = 2" }, lines)
  end)

  it("extracts code from a sh cell with # --- delimiters", function()
    make_buf({
      "echo 'header'",
      "# ---",
      "echo 'cell one'",
      "# ---",
      "echo 'cell two'",
    }, "sh", 3)

    local lines, err = tinker._get_current_cell()
    assert.is_nil(err)
    assert.are.same({ "echo 'cell one'" }, lines)
  end)

  it("extracts code from a javascript cell with // --- delimiters", function()
    make_buf({
      "const a = 1;",
      "// ---",
      "const b = 2;",
    }, "javascript", 3)

    local lines, err = tinker._get_current_cell()
    assert.is_nil(err)
    assert.are.same({ "const b = 2;" }, lines)
  end)

  it("skips markdown delimiter when cursor is in a markdown cell body", function()
    -- When cursor is inside a markdown cell's comment body, the backward search
    -- skips the markdown delimiter and falls through to the header region.
    make_buf({
      "# %% [markdown]",
      "# Some notes",
      "",
      "# %%",
      "code()",
    }, "python", 2)

    local lines, err = tinker._get_current_cell()
    -- Falls through to header — returns the lines before the first code cell
    assert.is_nil(err)
    assert.are.same({ "# %% [markdown]", "# Some notes" }, lines)
  end)

  it("returns an error for an empty cell", function()
    make_buf({
      "# %%",
      "",
      "# %%",
      "code()",
    }, "python", 2)

    local lines, err = tinker._get_current_cell()
    assert.is_nil(lines)
    assert.are.equal("Cell is empty", err)
  end)

  it("trims leading and trailing blank lines from cell content", function()
    make_buf({
      "# %%",
      "",
      "x = 1",
      "",
      "# %%",
      "y = 2",
    }, "python", 3)

    local lines, err = tinker._get_current_cell()
    assert.is_nil(err)
    assert.are.same({ "x = 1" }, lines)
  end)

  it("extracts content before the first delimiter (header region)", function()
    make_buf({
      "import os",
      "import sys",
      "# %%",
      "x = 1",
    }, "python", 1)

    local lines, err = tinker._get_current_cell()
    assert.is_nil(err)
    assert.are.same({ "import os", "import sys" }, lines)
  end)
end)

describe("tinker.next_cell", function()
  it("moves cursor to the next cell delimiter", function()
    make_buf({
      "# %%",
      "x = 1",
      "# %%",
      "y = 2",
    }, "python", 1)

    tinker.next_cell()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    assert.are.equal(3, row)
  end)

  it("does not move past the last delimiter", function()
    make_buf({
      "# %%",
      "x = 1",
      "# %%",
      "y = 2",
    }, "python", 3)

    tinker.next_cell()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    -- Should stay at 3 (no more delimiters ahead)
    assert.are.equal(3, row)
  end)
end)

describe("tinker.prev_cell", function()
  it("moves cursor to the previous cell delimiter", function()
    make_buf({
      "# %%",
      "x = 1",
      "# %%",
      "y = 2",
    }, "python", 4)

    tinker.prev_cell()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    assert.are.equal(3, row)
  end)

  it("moves to the first delimiter when at the second", function()
    make_buf({
      "# %%",
      "x = 1",
      "# %%",
      "y = 2",
    }, "python", 3)

    tinker.prev_cell()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    assert.are.equal(1, row)
  end)
end)
