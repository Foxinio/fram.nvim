local D = require("fram.doc")
local T, C, I, G = D.text, D.concat, D.indent, D.group
local M = {}
local supported = {}
for kind in ([[source_file lid uid tlid qlid num num64 chr str string_content escape_sequence interpolation
line_comment line_doc_comment block_comment block_comment_unfinished method rec pub def_list attributes attribute
def_let def_method def_parameter def_data def_data_record def_type def_label def_handle def_handle_with
def_module def_section def_rec def_open import_path_rel import_path_abs open imprt type_annot kind_type
kind_effect kind_arrow kind_wildcard ty_expr_arr ty_expr_app ty_expr_type ty_expr_aff uid_path ty_kind_annot
ty_expr_wildcard ty_effect ty_record ty_fld_anontype ty_fld_type ty_fld_typeval ty_fld_name ty_fld_nameval
ctor_decl ctor_unit ctor_nil ex_or_pattern ex_def_list ex_fn ex_effect effect_label resumption ex_binop
ex_if ex_if_no_else ex_annot ex_unop ex_app ex_method_call ex_extern ex_pub ex_select ex_method wildcard
ex_list ex_match match_clause ex_handler ex_handlerfn h_return h_finally ex_record fld_anontype fld_type
fld_typeval fld_name fld_nameval fld_nameannot fld_module fld_open fld_fn fld_effect_fn data_vis effect_var op]]):gmatch("%S+") do
  supported[kind] = true
end

local function comment(node) return node:type():find("comment", 1, true) ~= nil end
local function text(node, source) return vim.treesitter.get_node_text(node, source) end
local function children(node)
  local result = {}
  for child in node:iter_children() do result[#result + 1] = child end
  return result
end

local function parse(source)
  local ok, parser = pcall(vim.treesitter.get_string_parser, source, "fram")
  if not ok then error("Fram parser unavailable: " .. tostring(parser), 0) end
  local root = parser:parse()[1]:root()
  if root:has_error() then error("Fram syntax errors; buffer unchanged", 0) end
  local function check(node)
    if node:named() and not supported[node:type()] then
      error("Unsupported Fram syntax: " .. node:type() .. "; buffer unchanged", 0)
    end
    if node:missing() or node:type() == "block_comment_unfinished" or node:type() == "error_sentinel" then
      error("Unfinished or unsupported Fram syntax; buffer unchanged", 0)
    end
    for child in node:iter_children() do check(child) end
  end
  check(root)
  return root
end

-- Include anonymous punctuation and literal fragments, not just named nodes.
local function signature(node, source, result)
  result = result or {}
  if comment(node) then return result end
  result[#result + 1] = "(" .. node:type()
  if node:child_count() == 0 then result[#result + 1] = text(node, source) end
  for child in node:iter_children() do signature(child, source, result) end
  result[#result + 1] = ")"
  return result
end

local function protected(value)
  return value:find("```", 1, true) or value:find("~~~", 1, true)
    or value:find("`", 1, true) or value:find("https?://")
    or value:find("^#%s*[!@]") or value:find("^#%s*[%w_-]+:")
    or value:find("^##?%s*[./]+[%w/]") or value:find("^##?%s*[%w_/-]+%s+%-")
    or value:find("^##?  +%S")
    or value:find("\n%s*#?%s*[%$>] ")
end

local function protected_comments(root, source)
  local result, fence = {}, nil
  local function visit(node)
    if comment(node) then
      local value = text(node, source)
      if node:type() ~= "block_comment" then
        if fence then
          result[node:id()] = true
          if value:find(fence, 1, true) then fence = nil end
        elseif value:find("```", 1, true) or value:find("~~~", 1, true) then
          fence = value:find("```", 1, true) and "```" or "~~~"
          result[node:id()] = true
        end
      end
      return
    end
    for child in node:iter_children() do visit(child) end
  end
  visit(root)
  return result
end

local function prose(value)
  local paragraphs = {}
  value = value:gsub("\r\n", "\n")
  for paragraph in (value .. "\n\n"):gmatch("(.-)\n%s*\n") do
    paragraphs[#paragraphs + 1] = vim.trim(paragraph:gsub("%s+", " "))
  end
  return table.concat(paragraphs, "\n\n")
end

local function comment_body(value)
  if value:sub(1, 2) == "{#" then
    local tag, rest = value:match("^{#([^%s]*)%s(.*)$")
    if not tag then return nil end
    local ending = tag .. "#}"
    if rest:sub(-#ending) ~= ending then return nil end
    return rest:sub(1, -#ending - 1), tag:match("^#+$") ~= nil, tag
  end
  return value:gsub("^##?%s?", ""), value:sub(1, 2) == "##", nil
end

local function wrap_words(value, prefix, width)
  local lines, current = {}, prefix
  for word in value:gmatch("%S+") do
    local next_line = current == prefix and prefix .. word or current .. " " .. word
    if current ~= prefix and vim.fn.strdisplaywidth(next_line) > width then
      lines[#lines + 1], current = current, prefix .. word
    else current = next_line end
  end
  lines[#lines + 1] = current == prefix and vim.trim(current) or current
  return table.concat(lines, "\n")
end

local function format_comment(value, width, indent, inline)
  local body, doc, tag = comment_body(value)
  if not body or protected(value) or (tag and tag ~= "" and not doc) or inline then return value end
  body = prose(body)
  if doc then
    if not body:find("\n", 1, true) and vim.fn.strdisplaywidth("## " .. body) <= width - indent then
      return body == "" and "##" or "## " .. body
    end
    local delimiter = "#"
    while body:find(delimiter .. "#}", 1, true) do delimiter = delimiter .. "#" end
    local lines = { "{#" .. delimiter }
    for paragraph in (body .. "\n\n"):gmatch("(.-)\n\n") do
      if #lines > 1 then lines[#lines + 1] = "" end
      lines[#lines + 1] = wrap_words(paragraph, "  ", width - indent):gsub("\n", "\n" .. string.rep(" ", indent))
    end
    lines[#lines + 1] = delimiter .. "#}"
    return table.concat(lines, "\n" .. string.rep(" ", indent))
  end
  if tag then
    local wrapped = wrap_words(body, "  ", width - indent)
    if not wrapped:find("\n", 1, true) and vim.fn.strdisplaywidth(body) + 6 <= width - indent then
      return "{# " .. body .. " #}"
    end
    return "{#\n" .. string.rep(" ", indent) .. wrapped:gsub("\n", "\n" .. string.rep(" ", indent))
      .. "\n" .. string.rep(" ", indent) .. "#}"
  end
  local lines = {}
  for paragraph in (body .. "\n\n"):gmatch("(.-)\n\n") do
    if #lines > 0 then lines[#lines + 1] = "#" end
    lines[#lines + 1] = wrap_words(paragraph, "# ", width - indent)
  end
  return table.concat(lines, "\n"):gsub("\n", "\n" .. string.rep(" ", indent))
end

local function spacing(left, right)
  if not left then return "" end
  if left == "(" or right == ")" or left == "." or left == ">." then return "" end
  if right == "." then return " " end
  if right == "," or right == ";" then return "" end
  if left == "[" or right == "]" then return "" end
  if (left == "->" or left == "->>" or left == ":") and right:sub(1, 1) == "[" then return "" end
  if left == "/" or right == "/" then return " " end
  return " "
end

local function layout(root, source, width)
  local build, sequence
  local protected_nodes = protected_comments(root, source)
  local function raw(node) return text(node, source) end
  local function has_comments(nodes)
    for _, node in ipairs(nodes) do if comment(node) then return true end end
    return false
  end
  local function slice(nodes, first, last)
    local result = {}
    for n = first, last do result[#result + 1] = nodes[n] end
    return result
  end
  local function index(nodes, token)
    for n, node in ipairs(nodes) do if raw(node) == token then return n end end
  end
  local function units(nodes, indent)
    local result, n = {}, 1
    while n <= #nodes do
      local node, value = nodes[n], raw(nodes[n])
      if value == "(" then
        local depth, last = 1, n + 1
        while last <= #nodes do
          local token = raw(nodes[last])
          if token == "(" then depth = depth + 1 elseif token == ")" then depth = depth - 1 end
          if depth == 0 then break end
          last = last + 1
        end
        if depth ~= 0 then error("Unsupported parenthesis layout", 0) end
        result[#result + 1] = { first = "(", last = ")", doc = G(C({ T("("),
          sequence(slice(nodes, n + 1, last - 1), indent), T(")") })) }
        n = last + 1
      else
        result[#result + 1] = { first = value, last = value, doc = build(node, indent), node = node }
        n = n + 1
      end
    end
    return result
  end
  local function boundary(previous, node, top)
    local _, _, end_row = previous:range()
    local start_row = node:range()
    local gap = start_row - end_row
    if gap > 1 then
      return top and C({ D.hard, D.hard, D.hard }) or C({ D.hard, D.hard })
    end
    return D.hard
  end
  local function block(nodes, indent, top)
    local parts, previous, n = {}, nil, 1
    while n <= #nodes do
      local node = nodes[n]
      if previous then
        local _, _, end_row = previous:range()
        local row = node:range()
        parts[#parts + 1] = comment(node) and row == end_row and T(" ") or boundary(previous, node, top)
      end
      local row, col = node:range()
      local _, _, byte = node:start()
      local inline = col > 0 and (source:sub(1, byte):match("[^\n]*$") or ""):find("%S")
      if (node:type() == "line_doc_comment" or node:type() == "line_comment") and not inline
          and not protected_nodes[node:id()] then
        local values = { raw(node) }
        local last = node
        while nodes[n + 1] and nodes[n + 1]:type() == node:type() do
          local _, _, er = last:range()
          local sr = nodes[n + 1]:range()
          if sr ~= er + 1 or protected(raw(last)) or protected(raw(nodes[n + 1]))
              or protected_nodes[nodes[n + 1]:id()] then break end
          n, last = n + 1, nodes[n + 1]
          values[#values + 1] = raw(last)
        end
        local prefix = node:type() == "line_doc_comment" and "##" or "#"
        local bodies = {}
        for _, value in ipairs(values) do bodies[#bodies + 1] = value:sub(#prefix + 1) end
        parts[#parts + 1] = T(format_comment(prefix .. table.concat(bodies, "\n"), width, indent, false))
        previous = last
      else
        parts[#parts + 1] = build(node, indent)
        previous = node
      end
      n = n + 1
    end
    return C(parts)
  end

  sequence = function(nodes, indent, breaks)
    local parts, previous = {}, nil
    local entries = units(nodes, indent)
    for n, entry in ipairs(entries) do
      local value = entry.first
      local sep = spacing(previous, value)
      if previous then parts[#parts + 1] = breaks and sep == " " and D.line or T(sep) end
      parts[#parts + 1] = entry.doc
      if entry.node and comment(entry.node) and entry.node:type() ~= "block_comment" and n < #entries then
        parts[#parts + 1] = D.hard
      end
      previous = entry.last
    end
    return C(parts)
  end

  build = function(node, indent)
    local kind, value = node:type(), raw(node)
    if comment(node) then
      if protected_nodes[node:id()] then return T(value) end
      local row, col = node:range()
      local _, _, byte = node:start()
      local line = source:sub(1, byte):match("[^\n]*$") or ""
      local inline = col > 0 and line:find("%S") ~= nil
      return T(format_comment(value, width, indent, inline))
    end
    local nodes = children(node)
    if #nodes == 0 then return T(value) end
    if kind == "str" then
      local parts = {}
      for _, child in ipairs(nodes) do
        parts[#parts + 1] = child:type() == "interpolation" and build(child, indent) or T(raw(child))
      end
      return C(parts)
    end
    if kind == "source_file" or kind == "def_list" then return block(nodes, indent, indent == 0) end
    if kind == "def_module" or kind == "def_section" or kind == "def_rec" then
      local body = 2
      if kind == "def_module" then
        for n, child in ipairs(nodes) do if child:type() == "uid" then body = n + 1; break end end
      end
      if nodes[1]:type() == "pub" then body = body + (kind == "def_module" and 0 or 1) end
      if nodes[body] and nodes[body]:type() == "rec" then body = body + 1 end
      while body < #nodes and comment(nodes[body]) do
        local _, _, previous_row = nodes[body - 1]:range()
        local row = nodes[body]:range()
        if row ~= previous_row then break end
        body = body + 1
      end
      if body == #nodes and comment(nodes[body - 1]) then
        return C({ sequence(slice(nodes, 1, body - 1), indent), D.hard, T("end") })
      end
      if body >= #nodes then return sequence(nodes, indent) end
      if not body then return sequence(nodes, indent) end
      return C({ sequence(slice(nodes, 1, body - 1), indent), I(C({ D.hard, block(slice(nodes, body, #nodes - 1), indent + 2, false) })),
        D.hard, T("end") })
    end
    if kind == "imprt" or kind:match("^import_path") or kind == "uid_path" then
      if kind ~= "imprt" then return T(value:gsub("%s+", "")) end
      return sequence(nodes, indent)
    end
    if kind == "ex_unop" then return C({ build(nodes[1], indent), build(nodes[2], indent) }) end
    if kind == "ex_method" or kind == "ex_select" or kind == "effect_label" then
      local parts = {}
      for _, child in ipairs(nodes) do parts[#parts + 1] = build(child, indent) end
      return C(parts)
    end
    if kind == "ty_effect" then
      return G(C({ T("["), sequence(slice(nodes, 2, #nodes - 1), indent, true), T("]") }))
    end
    if kind == "ex_record" or kind == "ty_record" or kind == "ex_list" or kind == "attributes" then
      local open, close = raw(nodes[1]), raw(nodes[#nodes])
      local inner = slice(nodes, 2, #nodes - 1)
      if #inner == 0 then return T(open .. close) end
      local compact = false
      if kind == "ty_record" then
        compact = true
        for _, child in ipairs(inner) do
          if child:type():match("nameval") then compact = raw(child):match("^[~?]") ~= nil end
        end
      end
      if kind == "ex_record" and node:parent() then
        local parent = node:parent()
        local equals
        for child in parent:iter_children() do
          if raw(child) == "=" then equals = select(3, child:start()) end
        end
        local _, _, byte = node:start()
        compact = (equals and byte < equals) or false
        local fields = true
        for _, child in ipairs(inner) do
          if raw(child) ~= "," and child:type() ~= "fld_type" and child:type() ~= "fld_anontype"
              and not (child:type() == "fld_nameannot" and raw(child):match("^[~?]")) then fields = false end
        end
        compact = compact or fields
      end
      local parts = { T(open .. (compact and "" or " ")) }
      for n, child in ipairs(inner) do
        if raw(child) == "," then parts[#parts + 1] = D.soft; parts[#parts + 1] = T(", ")
        else parts[#parts + 1] = build(child, indent + 2) end
      end
      parts[#parts + 1] = compact and D.soft or D.line
      parts[#parts + 1] = T(close)
      return G(C(parts))
    end
    if kind == "ex_app" or kind == "ex_method_call" or kind == "ty_expr_app" then
      local entries = units(nodes, indent + 2)
      local parts = { entries[1].doc }
      for n = 2, #entries do
        local sep = spacing(entries[n - 1].last, entries[n].first)
        parts[#parts + 1] = I(G(C({ sep == " " and D.line or T(sep), entries[n].doc })))
      end
      return G(C(parts))
    end
    if kind == "ex_binop" or kind == "ex_or_pattern" or kind == "ty_expr_arr" then
      if #nodes == 3 then
        local op = raw(nodes[2])
        if kind == "ty_expr_arr" then
          return G(C({ build(nodes[1], indent), T(" " .. op), I(C({
            raw(nodes[3]):sub(1, 1) == "[" and T("") or D.line, build(nodes[3], indent + 2) })) }))
        end
        local parts = {}
        local function chain(current)
          local entries = children(current)
          if current:type() == kind and #entries == 3 then
            chain(entries[1])
            local operator = raw(entries[2])
            if operator == ";" then
              parts[#parts + 1] = T(";")
              parts[#parts + 1] = D.line
            elseif operator == "," then
              parts[#parts + 1] = D.soft
              parts[#parts + 1] = T(", ")
            else
              parts[#parts + 1] = D.line
              parts[#parts + 1] = T(operator .. " ")
            end
            chain(entries[3])
          else parts[#parts + 1] = build(current, indent + 2) end
        end
        chain(node)
        local first = table.remove(parts, 1)
        return G(C({ first, I(C(parts)) }))
      end
    end
    if kind == "ex_def_list" then
      return G(C({ build(nodes[1], indent), D.line, T("in"), D.line, sequence(slice(nodes, 3, #nodes), indent) }))
    end
    if kind == "ex_match" then
      local with = index(nodes, "with")
      if with and not has_comments(nodes) then
        local head = G(C({ T("match"), I(C({ D.line, sequence(slice(nodes, 2, with - 1), indent + 2) })), D.line, T("with") }))
        local parts = { head }
        for n = with + 1, #nodes - 1 do
          if raw(nodes[n]) ~= "|" then
            parts[#parts + 1] = D.line
            if n > with + 1 then parts[#parts + 1] = T("| ") end
            parts[#parts + 1] = build(nodes[n], indent)
          end
        end
        parts[#parts + 1], parts[#parts + 2] = D.line, T("end")
        return G(C(parts))
      end
    end
    if kind == "ex_if" or kind == "ex_if_no_else" then
      local parts = {}
      for n, child in ipairs(nodes) do
        local token = raw(child)
        if n > 1 then parts[#parts + 1] = (token == "then" or token == "else") and D.line or T(" ") end
        parts[#parts + 1] = build(child, indent)
      end
      return G(C(parts))
    end
    if kind == "ex_handler" or kind == "ex_handlerfn" then
      local parts = {}
      for n, child in ipairs(nodes) do
        if n > 1 then parts[#parts + 1] = D.line end
        parts[#parts + 1] = build(child, indent)
      end
      return G(C(parts))
    end
    if kind == "def_data" then
      local equals = index(nodes, "=")
      local parts = {}
      for n = equals + 1, #nodes do
        local child = nodes[n]
        if raw(child) == "|" then
          if n > equals + 1 then parts[#parts + 1] = D.line end
          parts[#parts + 1] = T("| ")
        else parts[#parts + 1] = build(child, indent + 2) end
      end
      if #parts == 0 then return sequence(nodes, indent) end
      return G(C({ sequence(slice(nodes, 1, equals), indent), I(C({ D.line, C(parts) })) }))
    end
    local equals = index(nodes, "=") or index(nodes, "=>")
    if equals then
      local head = sequence(slice(nodes, 1, equals), indent, false)
      if kind == "def_let" or kind == "def_method" then
        local lhs = nodes[equals - 1]
        if lhs and lhs:type() == "type_annot" then lhs = nodes[equals - 2] end
        if lhs and lhs:type() == "ex_app" then
          local params = units(children(lhs), indent + 4)
          local parts = { sequence(slice(nodes, 1, (nodes[equals - 1]:type() == "type_annot") and equals - 3 or equals - 2), indent), T(" "), params[1].doc }
          for n = 2, #params do parts[#parts + 1] = I(C({ D.line, params[n].doc }), 4) end
          if nodes[equals - 1]:type() == "type_annot" then
            parts[#parts + 1] = I(C({ D.line, build(nodes[equals - 1], indent + 4) }), 4)
          end
          parts[#parts + 1] = T(" =")
          head = G(C(parts))
        end
      end
      return G(C({ head, I(C({ D.line, sequence(slice(nodes, equals + 1, #nodes), indent + 2) })) }))
    end
    return G(sequence(nodes, indent, true))
  end
  return build(root, 0)
end

local function align(source, width)
  local root, lines = parse(source), vim.split(source, "\n", { plain = true })
  local function contains_comment(node)
    if comment(node) then return true end
    for child in node:iter_children() do if contains_comment(child) then return true end end
    return false
  end
  local function visit(node)
    if node:type() == "def_list" then
      local group = {}
      local function flush()
        if #group > 1 then
          local max = 0
          for _, entry in ipairs(group) do max = math.max(max, vim.fn.strdisplaywidth(entry.head)) end
          local fits = true
          for _, entry in ipairs(group) do
            if max + vim.fn.strdisplaywidth(entry.tail) > width then fits = false end
          end
          if fits then
            for _, entry in ipairs(group) do
              lines[entry.row] = entry.head .. string.rep(" ", max - vim.fn.strdisplaywidth(entry.head)) .. entry.tail
            end
          end
        end
        group = {}
      end
      for child in node:iter_children() do
        local sr, _, er = child:range()
        local head, tail = lines[sr + 1]:match("^(%s*let%s+[%a_][%w_']* )(%= .*)$")
        if child:type() == "def_let" and sr == er and head and not contains_comment(child) then
          if #group > 0 and group[#group].row ~= sr then flush() end
          group[#group + 1] = { row = sr + 1, head = head, tail = tail }
        else flush() end
      end
      flush()
    end
    for child in node:iter_children() do visit(child) end
  end
  visit(root)
  return table.concat(lines, "\n")
end

local function comments(root, source)
  local result, position = {}, 0
  local protected_nodes = protected_comments(root, source)
  local function visit(node)
    if comment(node) then
      local value = text(node, source)
      local body, doc, tag = comment_body(value)
      if not body or protected(value) or protected_nodes[node:id()] or (tag and tag ~= "" and not doc) then
        result[#result + 1] = { protected = value, position = position }
      else
        local last = result[#result]
        local words = prose(body):gsub("%s+", " ")
        if last and last.doc == doc and last.words and last.position == position then
          last.words = vim.trim(last.words .. " " .. words)
        else result[#result + 1] = { doc = doc, words = words, position = position } end
      end
      return
    end
    if node:child_count() == 0 then position = position + 1 end
    for child in node:iter_children() do visit(child) end
  end
  visit(root)
  return result
end

function M.source(source, width)
  if width == nil then width = 100 end
  if type(width) ~= "number" or width < 1 or width % 1 ~= 0 or width == math.huge then
    error("line_width must be a positive integer", 0)
  end
  local before = parse(source)
  local output = D.render(layout(before, source, width), width) .. "\n"
  output = align(output, width)
  local after = parse(output)
  if not vim.deep_equal(signature(before, source), signature(after, output)) then
    error("Fram syntax preservation validation failed; buffer unchanged", 0)
  end
  if not vim.deep_equal(comments(before, source), comments(after, output)) then
    error("Fram comment preservation validation failed; buffer unchanged", 0)
  end
  return output
end

function M.buffer(width)
  if vim.bo.filetype ~= "fram" then error("FramFormat requires a Fram buffer", 0) end
  if not vim.bo.modifiable then error("Fram buffer is not modifiable", 0) end
  local bufnr = vim.api.nvim_get_current_buf()
  local source = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n") .. "\n"
  local output = M.source(source, width)
  if output == source then return false end
  local view = vim.fn.winsaveview()
  local lines = vim.split(output:sub(1, -2), "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.fn.winrestview(view)
  return true
end

return M
