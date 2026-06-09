local M = {}

local function is_display_math_delimiter(line)
  return line:match("^%s*%$%$%s*$") ~= nil
end

local function find_enclosing_display_math_block(bufnr, cursor_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local opener

  for line_number = 1, #lines do
    if is_display_math_delimiter(lines[line_number] or "") then
      if opener then
        if opener <= cursor_line and cursor_line <= line_number then
          return opener, line_number
        end
        opener = nil
      else
        opener = line_number
      end
    end
  end

  return nil
end

local function normalize_math_body(lines)
  return vim.trim(table.concat(lines, " "):gsub("%s+", " "))
end

local raw_closers = {
  ["("] = ")",
  ["["] = "]",
  ["{"] = "}",
}

local raw_openers = {
  ["("] = true,
  ["["] = true,
  ["{"] = true,
}

local raw_closer_set = {
  [")"] = true,
  ["]"] = true,
  ["}"] = true,
}

local function find_matching_raw_closer(text, opener_index)
  local opener = text:sub(opener_index, opener_index)
  local expected_closer = raw_closers[opener]
  if not expected_closer then
    return nil
  end

  local stack = { expected_closer }
  for index = opener_index + 1, #text do
    local char = text:sub(index, index)
    if raw_openers[char] then
      table.insert(stack, raw_closers[char])
    elseif raw_closer_set[char] then
      if char ~= stack[#stack] then
        return nil
      end
      table.remove(stack)
      if #stack == 0 then
        return index
      end
    end
  end

  return nil
end

local function split_top_level_additive(text)
  local segments = {}
  local segment_start = 1
  local depth = 0

  for index = 1, #text do
    local char = text:sub(index, index)
    if raw_openers[char] then
      depth = depth + 1
    elseif raw_closer_set[char] then
      depth = depth - 1
    elseif depth == 0 and (char == "+" or char == "-") then
      local left = vim.trim(text:sub(segment_start, index - 1))
      local right = vim.trim(text:sub(index + 1))
      if left ~= "" and right ~= "" then
        table.insert(segments, left)
        segment_start = index
      end
    end
  end

  if #segments == 0 then
    return nil
  end

  table.insert(segments, vim.trim(text:sub(segment_start)))
  return segments
end

local function split_top_level_punctuation_items(text)
  local items = {}
  local item_start = 1
  local depth = 0

  for index = 1, #text do
    local char = text:sub(index, index)
    if raw_openers[char] then
      depth = depth + 1
    elseif raw_closer_set[char] then
      depth = depth - 1
    elseif depth == 0 and (char == "," or char == ";") then
      table.insert(items, { text = vim.trim(text:sub(item_start, index - 1)), separator = char })
      item_start = index + 1
    end
  end

  if #items < 2 then
    return nil
  end

  table.insert(items, { text = vim.trim(text:sub(item_start)), separator = "" })
  return items
end

local function split_bracket_inner(text)
  local items = split_top_level_punctuation_items(text)
  if items then
    local lines = {}
    for _, item in ipairs(items) do
      local item_segments = split_top_level_additive(item.text) or { item.text }
      if item.separator ~= "" then
        item_segments[#item_segments] = item_segments[#item_segments] .. item.separator
      end
      for _, segment in ipairs(item_segments) do
        table.insert(lines, segment)
      end
    end
    return lines
  end

  return split_top_level_additive(text)
end

local function find_expandable_raw_group(line)
  if #line <= 60 then
    return nil
  end

  for opener_index = 1, #line do
    if raw_openers[line:sub(opener_index, opener_index)] then
      local closer_index = find_matching_raw_closer(line, opener_index)
      if closer_index then
        local inner = vim.trim(line:sub(opener_index + 1, closer_index - 1))
        local segments = split_bracket_inner(inner)
        if segments then
          return opener_index, closer_index, segments
        end
      end
    end
  end

  return nil
end

local expand_bracketed_segment

local function append_expanded_bracketed_line(output, line, indent)
  local opener_index, closer_index, segments = find_expandable_raw_group(line)
  if not opener_index then
    table.insert(output, indent .. line)
    return
  end

  local opener_prefix = vim.trim(line:sub(1, opener_index))
  local suffix = vim.trim(line:sub(closer_index + 1))
  table.insert(output, indent .. opener_prefix)
  for _, segment in ipairs(segments) do
    expand_bracketed_segment(output, segment, indent .. "  ")
  end
  table.insert(output, indent .. vim.trim(line:sub(closer_index, closer_index) .. (suffix ~= "" and (" " .. suffix) or "")))
end

expand_bracketed_segment = function(output, segment, indent)
  append_expanded_bracketed_line(output, segment, indent)
end

local function expand_bracketed_expressions(lines)
  local expanded = {}

  for _, line in ipairs(lines) do
    append_expanded_bracketed_line(expanded, line, "")
  end

  return expanded
end

local function find_next_equation_relation(body, position)
  local leq_start, leq_end = body:find("(\\leq)", position)
  local geq_start, geq_end = body:find("(\\geq)", position)
  local eq_start, eq_end = body:find("(=)", position)

  local relation_start, relation_end, relation
  for _, candidate in ipairs({
    { start = body:find(":=", position, true), token = ":=" },
    { start = leq_start, finish = leq_end, token = "\\leq" },
    { start = geq_start, finish = geq_end, token = "\\geq" },
    { start = eq_start, finish = eq_end, token = "=" },
  }) do
    if candidate.start and (not relation_start or candidate.start < relation_start) then
      relation_start = candidate.start
      relation = candidate.token
      relation_end = candidate.finish or (candidate.start + #candidate.token - 1)
    end
  end

  return relation_start, relation_end, relation
end

local function format_equation_clause(body)
  local formatted = {}
  local position = 1
  while position <= #body do
    local relation_start, relation_end, relation = find_next_equation_relation(body, position)

    if not relation_start then
      local segment = vim.trim(body:sub(position))
      if segment ~= "" then
        if #formatted == 0 then
          table.insert(formatted, segment)
        else
          formatted[#formatted] = formatted[#formatted] .. " " .. segment
        end
      end
      break
    end

    local segment = vim.trim(body:sub(position, relation_start - 1))
    if #formatted == 0 then
      table.insert(formatted, segment)
    elseif segment ~= "" then
      formatted[#formatted] = formatted[#formatted] .. " " .. segment
    end
    table.insert(formatted, relation)
    position = relation_end + 1
  end

  return expand_bracketed_expressions(formatted)
end

local function find_next_clause_separator(body, position)
  local separator_start, separator_end, separator
  for _, token in ipairs({ "\\implies", "\\qquad", "\\quad", "\\iff" }) do
    local start_index, end_index = body:find(token, position, true)
    if start_index and (not separator_start or start_index < separator_start) then
      separator_start = start_index
      separator_end = end_index
      separator = token
    end
  end

  return separator_start, separator_end, separator
end

local function append_clause(formatted, clause)
  clause = vim.trim(clause)
  if clause == "" then
    return
  end

  for _, line in ipairs(format_equation_clause(clause)) do
    table.insert(formatted, line)
  end
end

local function format_math_body(lines)
  local body = normalize_math_body(lines)
  if body == "" then
    return #lines == 0 and {} or { "" }
  end

  local formatted = {}
  local position = 1
  while position <= #body do
    local separator_start, separator_end, separator = find_next_clause_separator(body, position)
    if not separator_start then
      append_clause(formatted, body:sub(position))
      break
    end

    append_clause(formatted, body:sub(position, separator_start - 1))
    table.insert(formatted, separator)
    position = separator_end + 1
  end

  return formatted
end

local function latex_math_format()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local opener, closer = find_enclosing_display_math_block(bufnr, cursor_line)

  if not opener then
    vim.notify("LatexMathFormat: no enclosing display math block found", vim.log.levels.ERROR)
    return
  end

  local body = vim.api.nvim_buf_get_lines(bufnr, opener, closer - 1, false)
  vim.api.nvim_buf_set_lines(bufnr, opener, closer - 1, false, format_math_body(body))
end

function M.setup(opts)
  opts = opts or {}

  if opts.command ~= false then
    vim.api.nvim_create_user_command("LatexMathFormat", latex_math_format, {})
  end
end

return M
