local M = {}

function M.setup()
	-- Filetype detection
	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		pattern = "*.fram",
		callback = function()
			vim.bo.filetype = "fram"
		end,
	})

	-- Register the external tree-sitter grammar
	local ts_parsers = require("nvim-treesitter.parsers").get_parser_configs()
	ts_parsers.fram = {
		install_info = {
			url = "https://github.com/Foxinio/tree-sitter-fram",
			files = { "src/parser.c", "src/scanner.c" },
			branch = "main",
			generate_requires_npm = false,
			requires_generate_from_grammar = false,
		},
		filetype = "fram",
	}
end

return M
