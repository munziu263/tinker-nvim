-- tinker/markdown.lua — Syntax highlighting for markdown cells in Python tinker files
--
-- Markdown cells are delimited by `# %% [markdown]` and contain markdown content
-- with a `# ` prefix on each line. This module parses the content, applies
-- treesitter highlighting, and maps captures back to buffer extmarks.

local M = {}

-- Namespace for extmarks
local ns = vim.api.nvim_create_namespace("tinker_markdown")

--- Find all markdown cells in a buffer
--- @param bufnr number Buffer number
--- @return table[] List of {start_row (0-indexed), content_lines} tables
function M.find_markdown_cells(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cells = {}
  local current_cell = nil

  for i, line in ipairs(lines) do
    local row = i - 1 -- Convert to 0-indexed

    if line:match("^# %%%% %[markdown%]") then
      -- Start of a markdown cell
      current_cell = { start_row = row, content_lines = {} }
    elseif current_cell then
      -- Check if this line ends the markdown cell
      if line:match("^# %%%%") and not line:match("^# %%%% %[markdown%]") then
        -- End of markdown cell (hit a code cell delimiter)
        if #current_cell.content_lines > 0 then
          table.insert(cells, current_cell)
        end
        current_cell = nil
      elseif line:match("^# ") then
        -- Content line with `# ` prefix - strip the prefix
        local content = line:sub(3) -- Remove "# " prefix
        table.insert(current_cell.content_lines, content)
      elseif line:match("^#$") then
        -- Empty comment line
        table.insert(current_cell.content_lines, "")
      elseif line:match("^%s*$") then
        -- Blank line ends the markdown cell
        if #current_cell.content_lines > 0 then
          table.insert(cells, current_cell)
        end
        current_cell = nil
      else
        -- Non-comment line ends the markdown cell
        if #current_cell.content_lines > 0 then
          table.insert(cells, current_cell)
        end
        current_cell = nil
      end
    end
  end

  -- Handle cell at end of file
  if current_cell and #current_cell.content_lines > 0 then
    table.insert(cells, current_cell)
  end

  return cells
end

--- Set fallback highlight groups for colorschemes that don't define @markup.*
function M.set_fallback_highlights()
  -- Headings: blues and greens, bold
  vim.api.nvim_set_hl(0, "@markup.heading", { fg = "#61afef", bold = true, default = true })
  vim.api.nvim_set_hl(0, "@markup.heading.1", { fg = "#61afef", bold = true, default = true })
  vim.api.nvim_set_hl(0, "@markup.heading.2", { fg = "#56b6c2", bold = true, default = true })
  vim.api.nvim_set_hl(0, "@markup.heading.3", { fg = "#98c379", bold = true, default = true })
  vim.api.nvim_set_hl(0, "@markup.heading.4", { fg = "#7ec699", bold = true, default = true })

  -- Strong (bold): amber
  vim.api.nvim_set_hl(0, "@markup.strong", { fg = "#e5c07b", bold = true, default = true })

  -- Italic: purple
  vim.api.nvim_set_hl(0, "@markup.italic", { fg = "#c678dd", italic = true, default = true })

  -- Raw/code: orange (inline `code` and fenced code blocks)
  vim.api.nvim_set_hl(0, "@markup.raw", { fg = "#d19a66", default = true })
  vim.api.nvim_set_hl(0, "@markup.raw.markdown_inline", { fg = "#d19a66", default = true })
  vim.api.nvim_set_hl(0, "@markup.raw.block", { fg = "#d19a66", default = true })

  -- Strikethrough
  vim.api.nvim_set_hl(0, "@markup.strikethrough", { strikethrough = true, default = true })

  -- Lists: red
  vim.api.nvim_set_hl(0, "@markup.list", { fg = "#e06c75", default = true })

  -- Quotes: muted italic
  vim.api.nvim_set_hl(0, "@markup.quote", { fg = "#5c6370", italic = true, default = true })

  -- Links: blue + underline
  vim.api.nvim_set_hl(0, "@markup.link", { fg = "#61afef", default = true })
  vim.api.nvim_set_hl(0, "@markup.link.label", { fg = "#61afef", underline = true, default = true })
  vim.api.nvim_set_hl(0, "@markup.link.url", { fg = "#56b6c2", underline = true, default = true })

  -- Punctuation: muted grey for markup delimiters (*, _, `, etc.)
  vim.api.nvim_set_hl(0, "@punctuation.special", { fg = "#5c6370", default = true })
  vim.api.nvim_set_hl(0, "@punctuation.delimiter", { fg = "#5c6370", default = true })
end

--- Apply a highlights query to a single tree and map captures back to buffer
--- positions. The markdown content was assembled from `cell.content_lines`,
--- each buffer line of which is prefixed by `# ` (2 chars) relative to the
--- original buffer row `cell.start_row + 1`.
--- @param bufnr number
--- @param cell table
--- @param markdown_text string
--- @param tree userdata  Treesitter tree
--- @param query userdata Treesitter query
local function apply_query_on_tree(bufnr, cell, markdown_text, tree, query)
  local root = tree:root()

  for id, node, _ in query:iter_captures(root, markdown_text, 0, -1) do
    local capture_name = query.captures[id]
    local sr, sc, er, ec = node:range()

    -- Clamp end position when er > sr and ec == 0 to avoid bleeding
    if er > sr and ec == 0 then
      er = er - 1
      if cell.content_lines[er + 1] then
        ec = #cell.content_lines[er + 1]
      else
        ec = 0
      end
    end

    -- Calculate buffer positions. Content starts at cell.start_row + 1 and
    -- every content line has a `# ` prefix, so shift columns by +2.
    local buf_start_row = cell.start_row + 1 + sr
    local buf_end_row = cell.start_row + 1 + er
    local buf_start_col = sc + 2
    local buf_end_col = ec + 2

    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, buf_start_row, buf_start_col, {
      end_row = buf_end_row,
      end_col = buf_end_col,
      hl_group = "@" .. capture_name,
      priority = 200,
      strict = false,
    })
  end
end

--- Recursively walk a LanguageTree and all injected children, applying each
--- language's own highlights query to its trees. This is what picks up
--- inline markup (bold/italic/inline code) which lives in the injected
--- `markdown_inline` language tree.
--- @param bufnr number
--- @param cell table
--- @param markdown_text string
--- @param ltree userdata  LanguageTree
local function apply_ltree(bufnr, cell, markdown_text, ltree)
  local lang = ltree:lang()
  local query_ok, query = pcall(vim.treesitter.query.get, lang, "highlights")

  if query_ok and query then
    for _, tree in ipairs(ltree:trees()) do
      apply_query_on_tree(bufnr, cell, markdown_text, tree, query)
    end
  end

  for _, child in pairs(ltree:children()) do
    apply_ltree(bufnr, cell, markdown_text, child)
  end
end

--- Apply treesitter highlights to markdown cells in a buffer. Callers must
--- have verified parser availability via `ensure_parsers()` during setup.
--- @param bufnr number Buffer number
function M.apply_highlights(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Only apply to Python files
  if vim.bo[bufnr].filetype ~= "python" then
    return
  end

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local cells = M.find_markdown_cells(bufnr)

  for _, cell in ipairs(cells) do
    local markdown_text = table.concat(cell.content_lines, "\n")

    if #markdown_text > 0 then
      local parser = vim.treesitter.get_string_parser(markdown_text, "markdown")
      parser:parse(true) -- parse injections too
      apply_ltree(bufnr, cell, markdown_text, parser)
    end
  end
end

--- Verify the required treesitter parsers are available. Returns true on
--- success; on failure, notifies the user with an actionable message and
--- returns false so the caller can bail out of setup.
--- @return boolean
local function ensure_parsers()
  if not vim.treesitter or not vim.treesitter.language or not vim.treesitter.language.add then
    vim.notify(
      "tinker.markdown: requires Neovim >= 0.10 with treesitter support",
      vim.log.levels.ERROR
    )
    return false
  end

  for _, lang in ipairs({ "markdown", "markdown_inline" }) do
    local ok, err = pcall(vim.treesitter.language.add, lang)
    if not ok then
      vim.notify(
        ("tinker.markdown: missing treesitter parser '%s' (install via `:TSInstall %s`). %s")
          :format(lang, lang, err or ""),
        vim.log.levels.ERROR
      )
      return false
    end
  end

  return true
end

--- Setup markdown cell highlighting
--- @param opts table|nil Options table from tinker.setup()
function M.setup(opts)
  opts = opts or {}

  -- Get markdown_cells options with defaults
  local md_opts = vim.tbl_deep_extend("force", {
    enabled = false,
    fallback_highlights = true,
  }, opts.markdown_cells or {})

  -- Return early if not enabled
  if not md_opts.enabled then
    return
  end

  -- Verify treesitter parsers are available. If not, notify and bail out
  -- rather than silently doing nothing on every buffer event.
  if not ensure_parsers() then
    return
  end

  -- Set fallback highlights if requested
  if md_opts.fallback_highlights then
    M.set_fallback_highlights()
  end

  -- Create augroup
  local augroup = vim.api.nvim_create_augroup("TinkerMarkdownCells", { clear = true })

  -- Re-apply fallback highlights on colorscheme change
  if md_opts.fallback_highlights then
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = augroup,
      callback = function()
        M.set_fallback_highlights()
      end,
    })
  end

  -- Apply highlights on buffer events
  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave" }, {
    group = augroup,
    pattern = "*.py",
    callback = function(args)
      M.apply_highlights(args.buf)
    end,
  })
end

return M
