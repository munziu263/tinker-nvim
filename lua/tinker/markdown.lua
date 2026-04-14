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

  -- Raw/code: orange
  vim.api.nvim_set_hl(0, "@markup.raw", { fg = "#d19a66", default = true })

  -- Lists: red
  vim.api.nvim_set_hl(0, "@markup.list", { fg = "#e06c75", default = true })

  -- Links: blue + underline
  vim.api.nvim_set_hl(0, "@markup.link.label", { fg = "#61afef", underline = true, default = true })

  -- Punctuation special: muted grey
  vim.api.nvim_set_hl(0, "@punctuation.special", { fg = "#5c6370", default = true })
end

--- Apply treesitter highlights to markdown cells in a buffer
--- @param bufnr number Buffer number
function M.apply_highlights(bufnr)
  -- Validate buffer
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Only apply to Python files
  local ft = vim.bo[bufnr].filetype
  if ft ~= "python" then
    return
  end

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  -- Try to load markdown parser
  local ok = pcall(vim.treesitter.language.add, "markdown")
  if not ok then
    return
  end

  -- Get the highlights query for markdown
  local query_ok, query = pcall(vim.treesitter.query.get, "markdown", "highlights")
  if not query_ok or not query then
    return
  end

  -- Find all markdown cells
  local cells = M.find_markdown_cells(bufnr)

  for _, cell in ipairs(cells) do
    -- Join content lines into a single markdown string
    local markdown_text = table.concat(cell.content_lines, "\n")

    if #markdown_text > 0 then
      -- Create a string parser for the markdown content
      local parser_ok, parser = pcall(vim.treesitter.get_string_parser, markdown_text, "markdown")
      if parser_ok and parser then
        local parse_ok = pcall(function()
          parser:parse()
        end)

        if parse_ok then
          parser:for_each_tree(function(tree, _)
            local root = tree:root()

            for id, node, _ in query:iter_captures(root, markdown_text, 0, -1) do
              local capture_name = query.captures[id]
              local sr, sc, er, ec = node:range()

              -- Clamp end position when er > sr and ec == 0 to avoid bleeding
              if er > sr and ec == 0 then
                er = er - 1
                -- Get the length of the line at er
                if cell.content_lines[er + 1] then
                  ec = #cell.content_lines[er + 1]
                else
                  ec = 0
                end
              end

              -- Calculate buffer positions
              -- cell.start_row is the `# %% [markdown]` line (0-indexed)
              -- Content starts at cell.start_row + 1
              -- sr is relative to the markdown content, so buffer row = cell.start_row + 1 + sr
              local buf_start_row = cell.start_row + 1 + sr
              local buf_end_row = cell.start_row + 1 + er

              -- Column offset: add 2 to skip the `# ` prefix
              local buf_start_col = sc + 2
              local buf_end_col = ec + 2

              -- Apply the extmark
              pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, buf_start_row, buf_start_col, {
                end_row = buf_end_row,
                end_col = buf_end_col,
                hl_group = "@" .. capture_name,
                priority = 200,
                strict = false,
              })
            end
          end)
        end
      end
    end
  end
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
