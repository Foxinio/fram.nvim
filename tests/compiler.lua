-- From fram.nvim: nvim --headless -u NONE -i NONE -l tests/compiler.lua PARSER COMPILER_REPO APPLY_PATCH
vim.opt.runtimepath:prepend(".")
vim.treesitter.language.add("fram", { path = assert(arg[1], "Fram parser library required") })
local repo = vim.fn.fnamemodify(assert(arg[2], "compiler repository required"), ":p"):gsub("/$", "")
local format = require("fram.format").source
local paths = vim.fn.glob(repo .. "/test/ok/*.fram", false, true)
paths[#paths + 1] = "../formatting-example.fram"
local failures, count = {}, 0
local patch = assert(arg[3], "bundled apply_patch executable required")
local temporary = vim.fn.tempname() .. ".fram"
local function apply(value)
  local result = vim.system({ patch }, { stdin = value, text = true }):wait()
  assert(result.code == 0, result.stderr)
end
local function run(source, path)
  apply("*** Begin Patch\n*** Add File: " .. temporary .. "\n+" .. source:gsub("\n", "\n+") .. "\n*** End Patch\n")
  local command = { repo .. "/_build/default/src/dbl.exe", "-L", repo .. "/lib", "-L", repo .. "/test/stdlib",
    "-I", vim.fn.fnamemodify(path, ":p:h"), "-color", "never" }
  -- The success suite intentionally includes ill-typed tagged definitions.
  if path == "../formatting-example.fram" then vim.list_extend(command, { "-test", "-test-tags", "*" }) end
  command[#command + 1] = temporary
  local result = vim.system(command, { text = true }):wait(10000)
  apply("*** Begin Patch\n*** Delete File: " .. temporary .. "\n*** End Patch\n")
  return result
end
for _, path in ipairs(paths) do
  local source = table.concat(vim.fn.readfile(path), "\n") .. "\n"
  local baseline = run(source, path)
  for _, width in ipairs({ 80, 100 }) do
    local ok, err = pcall(function()
      local output = format(source, width)
      assert(format(output, width) == output, "not idempotent")
      assert(baseline.code == 0, "original failed dbl: " .. baseline.stderr)
      local result = run(output, path)
      assert(result.code == 0, "formatted failed dbl: " .. result.stderr)
      assert(result.stdout == baseline.stdout, "program output changed")
    end)
    if not ok then failures[#failures + 1] = path .. " at " .. width .. ": " .. tostring(err) end
    count = count + 1
  end
end
for _, failure in ipairs(failures) do io.stderr:write(failure .. "\n") end
assert(#failures == 0, #failures .. " compiler checks failed")
print(count .. " formatted compiler runs passed preservation, idempotence, dbl, and output comparison; reference includes all tags")
