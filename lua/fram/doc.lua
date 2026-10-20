local M = {}

function M.text(value) return { kind = "text", value = value } end
function M.concat(parts) return { kind = "concat", parts = parts } end
function M.indent(doc, amount) return { kind = "indent", doc = doc, amount = amount or 2 } end
function M.group(doc) return { kind = "group", doc = doc } end
M.line = { kind = "line", value = " " }
M.soft = { kind = "line", value = "" }
M.hard = { kind = "hard" }

local function flat_width(doc)
  if doc.kind == "text" then
    if doc.value:find("\n", 1, true) then return math.huge end
    return vim.fn.strdisplaywidth(doc.value)
  elseif doc.kind == "hard" then return math.huge
  elseif doc.kind == "line" then return #doc.value
  elseif doc.kind == "concat" then
    local width = 0
    for _, part in ipairs(doc.parts) do width = width + flat_width(part) end
    return width
  end
  return flat_width(doc.doc)
end

function M.render(doc, width)
  local output, column, pending = {}, 0, ""
  local function emit(value)
    if value ~= "" then
      output[#output + 1], pending = pending, ""
    end
    output[#output + 1] = value
    local tail = value:match("\n([^\n]*)$")
    column = tail and vim.fn.strdisplaywidth(tail) or column + vim.fn.strdisplaywidth(value, column)
  end
  local stack = { { doc, 0, false } }
  local function push(parts, indent, flat, target)
    for n = #parts, 1, -1 do target[#target + 1] = { parts[n], indent, flat } end
  end
  local function fits(item)
    if flat_width(item) > width - column then return false end
    local trial = {}
    for n, frame in ipairs(stack) do trial[n] = frame end
    trial[#trial + 1] = { item, 0, true }
    local col = column
    while #trial > 0 do
      local frame = table.remove(trial)
      local part, flat = frame[1], frame[3]
      if part.kind == "text" then
        local first = part.value:match("^[^\n]*")
        col = col + vim.fn.strdisplaywidth(first, col)
        if col > width then return false end
        if part.value:find("\n", 1, true) then return true end
      elseif part.kind == "hard" or (part.kind == "line" and not flat) then return true
      elseif part.kind == "line" then col = col + #part.value
      elseif part.kind == "concat" then push(part.parts, 0, flat, trial)
      else trial[#trial + 1] = { part.doc, 0, flat } end
      if col > width then return false end
    end
    return true
  end
  while #stack > 0 do
    local frame = table.remove(stack)
    local item, indent, flat = frame[1], frame[2], frame[3]
    if item.kind == "text" then emit(item.value)
    elseif item.kind == "concat" then push(item.parts, indent, flat, stack)
    elseif item.kind == "indent" then stack[#stack + 1] = { item.doc, indent + item.amount, flat }
    elseif item.kind == "group" then stack[#stack + 1] = { item.doc, indent, flat or fits(item.doc) }
    elseif item.kind == "line" and flat then emit(item.value)
    else
      output[#output + 1] = "\n"
      pending, column = string.rep(" ", indent), indent
    end
  end
  return table.concat(output)
end

return M
