-- Regression spec for lua/tinker/cell_delimiters.lua.
--
-- Tests exercise the module through its public interface. See tests.md in
-- .claude/skills/tdd for the style guide.

local cells = require("tinker.cell_delimiters")

--- Create a scratch buffer pre-populated with the given lines and filetype.
--- @param lines string[]
--- @param filetype? string
--- @return integer bufnr
local function make_buf(lines, filetype)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  if filetype then
    vim.bo[bufnr].filetype = filetype
  end
  return bufnr
end

describe("tinker.cell_delimiters.find_delimiters", function()
  it("returns an empty list when the buffer has no cell delimiters", function()
    local bufnr = make_buf({ "import os", "x = 1" }, "python")
    local delims = cells.find_delimiters(bufnr)
    assert.are.equal(0, #delims)
  end)

  it("detects a '# %%' line as a code delimiter in a python buffer", function()
    local bufnr = make_buf({
      "import os",
      "# %%",
      "x = 1",
    }, "python")
    local delims = cells.find_delimiters(bufnr)
    assert.are.equal(1, #delims)
    assert.are.same({ row = 1, kind = "code" }, delims[1])
  end)

  it("detects a '# %% [markdown]' line as a markdown delimiter", function()
    local bufnr = make_buf({
      "# %% [markdown]",
      "# notes",
      "",
      "# %%",
      "x = 1",
    }, "python")
    local delims = cells.find_delimiters(bufnr)
    assert.are.equal(2, #delims)
    assert.are.same({ row = 0, kind = "markdown" }, delims[1])
    assert.are.same({ row = 3, kind = "code" }, delims[2])
  end)

  it("detects '# ---' as a code delimiter in a sh buffer", function()
    local bufnr = make_buf({
      "echo 'before'",
      "# ---",
      "echo 'after'",
    }, "sh")
    local delims = cells.find_delimiters(bufnr)
    assert.are.equal(1, #delims)
    assert.are.same({ row = 1, kind = "code" }, delims[1])
  end)

  it("detects '// ---' as a code delimiter in a javascript buffer", function()
    local bufnr = make_buf({
      "const a = 1;",
      "// ---",
      "const b = 2;",
    }, "javascript")
    local delims = cells.find_delimiters(bufnr)
    assert.are.equal(1, #delims)
    assert.are.same({ row = 1, kind = "code" }, delims[1])
  end)

  it("returns an empty list for unsupported filetypes", function()
    local bufnr = make_buf({ "# %%", "# ---" }, "text")
    local delims = cells.find_delimiters(bufnr)
    assert.are.equal(0, #delims)
  end)
end)

describe("tinker.cell_delimiters.apply_highlights", function()
  local function get_marks(bufnr)
    local ns = vim.api.nvim_create_namespace("tinker_cell_delimiters")
    return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  end

  it("sets a line highlight on each code delimiter using the configured group", function()
    local bufnr = make_buf({
      "import os",
      "# %%",
      "x = 1",
    }, "python")
    cells.apply_highlights(bufnr)

    local marks = get_marks(bufnr)
    assert.are.equal(1, #marks)
    assert.are.equal(1, marks[1][2]) -- row
    assert.are.equal("TinkerCellDelimiter", marks[1][4].line_hl_group)
  end)

  it("uses a distinct highlight group for markdown-cell delimiters", function()
    local bufnr = make_buf({
      "# %% [markdown]",
      "# notes",
      "",
      "# %%",
      "x = 1",
    }, "python")
    cells.apply_highlights(bufnr)

    local marks = get_marks(bufnr)
    assert.are.equal(2, #marks)
    -- Marks come back sorted by position.
    assert.are.equal(0, marks[1][2])
    assert.are.equal("TinkerCellDelimiterMarkdown", marks[1][4].line_hl_group)
    assert.are.equal(3, marks[2][2])
    assert.are.equal("TinkerCellDelimiter", marks[2][4].line_hl_group)
  end)

  it("clears previous extmarks on re-apply (no duplicates)", function()
    local bufnr = make_buf({ "# %%", "x = 1" }, "python")

    cells.apply_highlights(bufnr)
    cells.apply_highlights(bufnr)

    assert.are.equal(1, #get_marks(bufnr))
  end)

  it("is a no-op on unsupported filetypes", function()
    local bufnr = make_buf({ "# %%", "# ---" }, "text")
    cells.apply_highlights(bufnr)
    assert.are.equal(0, #get_marks(bufnr))
  end)

  it("handles an invalid buffer without raising", function()
    -- Just needs to not throw.
    cells.apply_highlights(nil)
    cells.apply_highlights(999999)
  end)
end)

describe("tinker.cell_delimiters.set_fallback_highlights", function()
  it(
    "defines TinkerCellDelimiter and TinkerCellDelimiterMarkdown with distinct backgrounds",
    function()
      cells.set_fallback_highlights()

      local code = vim.api.nvim_get_hl(0, { name = "TinkerCellDelimiter" })
      local md = vim.api.nvim_get_hl(0, { name = "TinkerCellDelimiterMarkdown" })

      assert.is_not_nil(code.bg)
      assert.is_not_nil(md.bg)
      assert.are_not.equal(code.bg, md.bg)
    end
  )
end)

describe("tinker.cell_delimiters.setup", function()
  local function get_marks(bufnr)
    local ns = vim.api.nvim_create_namespace("tinker_cell_delimiters")
    return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  end

  it("honors custom code_hl and markdown_hl in subsequent apply_highlights calls", function()
    cells.setup({ code_hl = "CustomCode", markdown_hl = "CustomMd" })

    local bufnr = make_buf({ "# %% [markdown]", "# x", "", "# %%" }, "python")
    cells.apply_highlights(bufnr)

    local marks = get_marks(bufnr)
    assert.are.equal(2, #marks)
    assert.are.equal("CustomMd", marks[1][4].line_hl_group)
    assert.are.equal("CustomCode", marks[2][4].line_hl_group)

    -- Reset for other tests
    cells.setup({})
  end)
end)
