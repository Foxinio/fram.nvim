local M = {}
local line_width = 100

function M.format(width)
	if width == nil then width = line_width end
	return require("fram.format").buffer(width)
end

function M.setup(opts)
	opts = opts or {}
	local width = opts.format and opts.format.line_width
	if width == nil then width = 100 end
	if type(width) ~= "number" or width < 1 or width % 1 ~= 0 or width == math.huge then
		error("format.line_width must be a positive integer")
	end
	line_width = width
	vim.api.nvim_create_user_command("FramFormat", function(args)
		local requested = args.args == "" and line_width or tonumber(args.args)
		if not requested then
			vim.notify("FramFormat width must be a positive integer", vim.log.levels.ERROR)
			return
		end
		local ok, err = pcall(M.format, requested)
		if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
	end, { nargs = "?", desc = "Format the current Fram buffer" })
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
