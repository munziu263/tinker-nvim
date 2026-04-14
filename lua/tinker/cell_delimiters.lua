-- tinker/cell_delimiters.lua — Full-line background highlight on every cell
-- delimiter line so cell boundaries are visually obvious at a glance.
--
-- Cell delimiters per filetype (same convention init.lua uses for navigation):
--   python      `# %%`           code cell
--               `# %% [markdown]` markdown cell
--   sh / bash   `# ---`          code cell
--   other       `// ---`         code cell

local M = {}

-- Namespace for line-highlight extmarks. Dedicated so toggling this feature
-- doesn't affect markdown-content highlighting or user extmarks.
local ns = vim.api.nvim_create_namespace("tinker_cell_delimiters")

-- Highlight groups applied to delimiter lines. Configurable via setup(opts).
local code_hl = "TinkerCellDelimiter"
local markdown_hl = "TinkerCellDelimiterMarkdown"

--- Return the cell-delimiter patterns for a given filetype. The `markdown`
--- key is optional: filetypes without a markdown-cell variant (e.g. sh, js)
--- simply omit it.
--- @param ft string
--- @return table|nil patterns { code = <lua pattern>, markdown? = <lua pattern> }
local function patterns_for(ft)
  if ft == "python" then
    return {
      markdown = "^# %%%% %[markdown%]",
      code = "^# %%%%",
    }
  elseif ft == "sh" or ft == "bash" then
    return { code = "^# %-%-%-" }
  elseif
    ft == "javascript"
    or ft == "typescript"
    or ft == "javascriptreact"
    or ft == "typescriptreact"
  then
    return { code = "^// %-%-%-" }
  end
  return nil
end

--- Scan a buffer for cell-delimiter lines.
--- @param bufnr integer
--- @return table[] delims List of { row = 0-indexed, kind = "code"|"markdown" }
function M.find_delimiters(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local pats = patterns_for(vim.bo[bufnr].filetype)
  if not pats then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local delims = {}

  for i, line in ipairs(lines) do
    local row = i - 1 -- 0-indexed
    if pats.markdown and line:match(pats.markdown) then
      table.insert(delims, { row = row, kind = "markdown" })
    elseif line:match(pats.code) then
      table.insert(delims, { row = row, kind = "code" })
    end
  end

  return delims
end

--- Apply line-highlight extmarks to every cell delimiter in a buffer.
--- Clears any previous extmarks in this module's namespace first, so repeated
--- calls produce no duplicates. No-op on unsupported filetypes or invalid
--- buffers.
--- @param bufnr integer|nil
function M.apply_highlights(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  for _, delim in ipairs(M.find_delimiters(bufnr)) do
    local hl = delim.kind == "markdown" and markdown_hl or code_hl
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, delim.row, 0, {
      line_hl_group = hl,
      priority = 150,
      strict = false,
    })
  end
end

--- Define fallback highlight groups for colorschemes that don't style
--- TinkerCellDelimiter* themselves. Uses `default = true` so user-defined
--- groups (either directly or via a colorscheme) always win.
function M.set_fallback_highlights()
  -- Subtle dark-grey tint for code cells.
  vim.api.nvim_set_hl(0, "TinkerCellDelimiter", { bg = "#2c323c", default = true })
  -- A hair warmer/lighter for markdown cells so they're distinguishable.
  vim.api.nvim_set_hl(0, "TinkerCellDelimiterMarkdown", { bg = "#3a3340", default = true })
end

--- Filetypes we auto-apply highlights on. Matches the patterns in
--- `patterns_for()`; keep them in sync.
local autocmd_filetypes = {
  "python",
  "sh",
  "bash",
  "javascript",
  "typescript",
  "javascriptreact",
  "typescriptreact",
}

--- Setup cell-delimiter highlighting.
--- @param opts table|nil {
---   enabled             boolean (default true),
---   code_hl             string  (default "TinkerCellDelimiter"),
---   markdown_hl         string  (default "TinkerCellDelimiterMarkdown"),
---   fallback_highlights boolean (default true),
--- }
function M.setup(opts)
  opts = opts or {}

  local cd_opts = vim.tbl_deep_extend("force", {
    enabled = true,
    code_hl = "TinkerCellDelimiter",
    markdown_hl = "TinkerCellDelimiterMarkdown",
    fallback_highlights = true,
  }, opts)

  code_hl = cd_opts.code_hl
  markdown_hl = cd_opts.markdown_hl

  if not cd_opts.enabled then
    return
  end

  if cd_opts.fallback_highlights then
    M.set_fallback_highlights()
  end

  local augroup = vim.api.nvim_create_augroup("TinkerCellDelimiters", { clear = true })

  if cd_opts.fallback_highlights then
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = augroup,
      callback = function()
        M.set_fallback_highlights()
      end,
    })
  end

  -- Re-apply on filetype set (initial buffer entry) and on edits.
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = autocmd_filetypes,
    callback = function(args)
      M.apply_highlights(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave" }, {
    group = augroup,
    callback = function(args)
      M.apply_highlights(args.buf)
    end,
  })
end

return M
