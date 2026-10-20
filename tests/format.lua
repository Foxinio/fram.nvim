-- From fram.nvim: /opt/nvim-linux-x86_64/bin/nvim --headless -u NONE -i NONE -l tests/format.lua /path/to/fram.so
vim.opt.runtimepath:prepend(".")
vim.treesitter.language.add("fram", { path = assert(arg[1], "Fram parser library required") })
local F, D = require("fram.format"), require("fram.doc")
local function equal(actual, expected, label)
  assert(actual == expected, (label or "mismatch") .. "\nEXPECTED:\n" .. expected .. "\nACTUAL:\n" .. actual)
end

local doc = D.group(D.concat({ D.text("ab"), D.indent(D.concat({ D.line, D.text("cd") })) }))
equal(D.render(doc, 5), "ab cd")
equal(D.render(doc, 4), "ab\n  cd")
equal(D.render(D.concat({ doc, D.text(")") }), 5), "ab\n  cd)")
equal(D.render(D.group(D.concat({ D.text("界"), D.line, D.text("x") })), 3), "界\nx")
equal(D.render(D.concat({ D.text("a"), D.indent(D.concat({ D.hard, D.hard, D.text("b") })) }), 80), "a\n\n  b")

for _, case in ipairs(dofile("tests/fixtures/format.lua")) do
  for _, width in ipairs({ 80, 100 }) do
    local output = F.source(case.source, width)
    equal(output, case[width] or case.expected, case.name .. " at " .. width)
    equal(F.source(output, width), output, case.name .. " idempotence")
    for line in output:gmatch("[^\n]+") do assert(vim.fn.strdisplaywidth(line) <= width, line) end
  end
end

local function stable(source, width)
  local output = F.source(source, width)
  equal(F.source(output, width), output, "comment/literal idempotence")
  return output
end
equal(stable("#\n##\nlet x=1\n", 80), "#\n##\nlet x = 1\n")
equal(stable('let a="#"\nlet longer="text"\n', 80), 'let a      = "#"\nlet longer = "text"\n')
equal(stable("module rec M # keep beside header\nlet x=1\nend\n", 80),
  "module rec M # keep beside header\n  let x = 1\nend\n")

local protected = {
  "{#tag body {# nested-looking text #} tag#}",
  "{#!a! operator tag !a!#}",
  "{###\n```fram\nlet  x=1\n{## nested ##}\n```\n###}",
  "# https://example.com/a/very/long/protected/url",
  "# @lexer preserve this directive",
  "# Example: let  x=1",
}
for _, value in ipairs(protected) do
  local output = stable(value .. "\nlet x=1\n", 30)
  assert(output:find(value, 1, true), value)
end
local fenced = "# ```fram\n# let   first=1\n# let second =   2\n# ```\nlet x=1\n"
assert(stable(fenced, 20):find(fenced:match("^(.-)\nlet x"), 1, true))
local fenced_docs = fenced:gsub("# ", "## ")
assert(stable(fenced_docs, 20):find(fenced_docs:match("^(.-)\nlet x"), 1, true))
local documentation = "## A documentation paragraph that is long enough to wrap and contains ##} safely.\n## Another sentence follows.\nlet x=1\n"
local documented = stable(documentation, 40)
assert(documented:find("{###\n", 1, true), documented)
assert(documented:find("\n###}", 1, true), documented)
local paragraphs = stable("module M\n# First paragraph with enough words to wrap onto several lines.\n#\n# A second paragraph.\nlet x=1 # keep inline\nend\n", 40)
assert(paragraphs:find("\n  #\n", 1, true), paragraphs)
assert(paragraphs:find("let x = 1 # keep inline", 1, true), paragraphs)
for line in paragraphs:gmatch("[^\n]+") do
  if line:find("#", 1, true) then assert(line:match("^  #") or line:find("keep inline", 1, true), line) end
end
local literal = 'let x = "first\n  second\\n\\x41\nlast"\n'
assert(stable(literal, 20):find('"first\n  second\\n\\x41\nlast"', 1, true))
assert(stable('let x = "' .. string.rep("a", 200) .. '"\n', 80):find(string.rep("a", 200), 1, true))
local no_alignment = "let a = " .. string.rep("a", 70) .. "\nlet longerName = b\n"
assert(not F.source(no_alignment, 80):find("let a          =", 1, true))

for _, source in ipairs({ "let =", "let x = (", "{#tag unfinished", 'let x = "bad \\q"' }) do
  assert(not pcall(F.source, source), source)
end
for _, width in ipairs({ 0, -1, 1.5, math.huge, "80", false }) do assert(not pcall(F.source, "let x=1", width)) end

local parsers = {}
package.loaded["nvim-treesitter.parsers"] = { get_parser_configs = function() return parsers end }
local fram = require("fram")
fram.setup({ format = { line_width = 80 } })
assert(vim.fn.exists(":FramFormat") == 2)
assert(not pcall(fram.setup, { format = { line_width = -1 } }))
vim.cmd.enew()
vim.bo.filetype = "fram"
vim.bo.swapfile = false
local original = "let result = transform firstArgument secondArgument thirdArgument fourthArgument fifthArgument"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { original })
-- End the setup edit's undo block as an interactive command would.
vim.cmd('let &undolevels = &undolevels')
local view = vim.fn.winsaveview()
assert(fram.format())
local output = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n"
equal(output, F.source(original .. "\n", 80))
assert(vim.fn.winsaveview().lnum == view.lnum)
vim.cmd.undo()
equal(vim.api.nvim_get_current_line(), original, "single undo")
vim.cmd("FramFormat 100")
assert(vim.api.nvim_buf_line_count(0) == 1)
local tick = vim.api.nvim_buf_get_changedtick(0)
vim.bo.modified = false
assert(not fram.format(100))
assert(vim.api.nvim_buf_get_changedtick(0) == tick and not vim.bo.modified)
local notified = {}
local notify = vim.notify
vim.notify = function(message) notified[#notified + 1] = message end
for _, command in ipairs({ "FramFormat nope", "FramFormat 0", "FramFormat -1", "FramFormat 1.5" }) do
  vim.cmd(command)
  assert(vim.api.nvim_buf_get_changedtick(0) == tick)
end
assert(#notified == 4)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "{#unfinished" })
tick = vim.api.nvim_buf_get_changedtick(0)
vim.cmd.FramFormat()
assert(vim.api.nvim_buf_get_changedtick(0) == tick)
local language = vim.treesitter.get_string_parser
vim.treesitter.get_string_parser = function() error("parser missing") end
assert(not pcall(fram.format))
assert(vim.api.nvim_buf_get_changedtick(0) == tick)
vim.treesitter.get_string_parser = language
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "let x=1" })
tick = vim.api.nvim_buf_get_changedtick(0)
local render = D.render
D.render = function() return "let x = 2" end
assert(not pcall(fram.format))
assert(vim.api.nvim_buf_get_changedtick(0) == tick)
D.render = render
vim.notify = notify
vim.bo.filetype = "text"
assert(not pcall(fram.format))
local reference = table.concat(vim.fn.readfile("tests/fixtures/reference.fram"), "\n") .. "\n"
equal(F.source(reference), reference, "normalized reference")
print("Fram formatter fixtures, renderer, preservation, configuration, command, and undo checks passed")
