.PHONY: test test-deps clean-deps

DEPS_DIR  := .deps
PLENARY   := $(DEPS_DIR)/plenary.nvim

$(PLENARY):
	@mkdir -p $(DEPS_DIR)
	@git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY)

test-deps: $(PLENARY)

test: test-deps
	@nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

clean-deps:
	@rm -rf $(DEPS_DIR)
