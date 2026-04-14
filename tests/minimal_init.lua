-- tests/minimal_init.lua — Bootstrap for plenary.nvim test runs.
--
-- Adds the plugin root and plenary.nvim (expected in .deps/) to the
-- runtimepath, disables swapfiles, and loads plenary's vim plugin so
-- :PlenaryBustedDirectory is available.
--
-- Usage (via Makefile):
--   nvim --headless --noplugin -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

local plugin_root = vim.fn.fnamemodify(
  vim.fn.resolve(debug.getinfo(1).source:sub(2)),
  ":p:h:h"
)
local plenary_path = plugin_root .. "/.deps/plenary.nvim"

vim.opt.runtimepath:prepend(plugin_root)
vim.opt.runtimepath:prepend(plenary_path)

vim.opt.swapfile = false
vim.opt.more = false

-- Make plenary's :PlenaryBustedDirectory command available.
vim.cmd("runtime plugin/plenary.vim")
