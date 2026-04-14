-- Regression spec for lua/tinker/markdown.lua.
--
-- These tests lock in the current behavior so future changes surface as
-- real regressions. Ran headless via plenary.busted; see Makefile `test`.

local md = require("tinker.markdown")

--- Create a scratch buffer pre-populated with the given lines.
--- @param lines string[]
--- @return integer bufnr
local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

describe("tinker.markdown.find_markdown_cells", function()
  it("returns an empty list when the buffer has no markdown cells", function()
    local bufnr = make_buf({
      "import os",
      'print("hello")',
    })
    local cells = md.find_markdown_cells(bufnr)
    assert.are.equal(0, #cells)
  end)

  it("detects a single markdown cell and strips the '# ' prefix", function()
    local bufnr = make_buf({
      "# %% [markdown]",
      "# Hello **world**",
      "# second content line",
      "",
      "code_follows()",
    })
    local cells = md.find_markdown_cells(bufnr)

    assert.are.equal(1, #cells)
    assert.are.equal(0, cells[1].start_row)
    assert.are.same({
      "Hello **world**",
      "second content line",
    }, cells[1].content_lines)
  end)

  it("ends a markdown cell when a non-markdown code cell delimiter appears", function()
    local bufnr = make_buf({
      "# %% [markdown]",
      "# first cell content",
      "# %% another code cell",
      "x = 1",
    })
    local cells = md.find_markdown_cells(bufnr)

    assert.are.equal(1, #cells)
    assert.are.same({ "first cell content" }, cells[1].content_lines)
  end)

  it("ends a markdown cell on a blank line", function()
    local bufnr = make_buf({
      "# %% [markdown]",
      "# line one",
      "",
      "x = 1",
    })
    local cells = md.find_markdown_cells(bufnr)

    assert.are.equal(1, #cells)
    assert.are.same({ "line one" }, cells[1].content_lines)
  end)

  it("preserves empty comment lines ('#') inside a cell as blank content", function()
    local bufnr = make_buf({
      "# %% [markdown]",
      "# before blank",
      "#",
      "# after blank",
      "",
    })
    local cells = md.find_markdown_cells(bufnr)

    assert.are.equal(1, #cells)
    assert.are.same({
      "before blank",
      "",
      "after blank",
    }, cells[1].content_lines)
  end)

  it("detects multiple markdown cells across the buffer", function()
    local bufnr = make_buf({
      "# %% [markdown]",
      "# cell one",
      "",
      "# %% [markdown]",
      "# cell two",
    })
    local cells = md.find_markdown_cells(bufnr)

    assert.are.equal(2, #cells)
    assert.are.same({ "cell one" }, cells[1].content_lines)
    assert.are.same({ "cell two" }, cells[2].content_lines)
  end)
end)
