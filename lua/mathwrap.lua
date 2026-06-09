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

local is_escaped_at

local protected_text_commands = {
  ["\\text"] = true,
  ["\\textrm"] = true,
  ["\\textit"] = true,
  ["\\textbf"] = true,
  ["\\mathrm"] = true,
  ["\\operatorname"] = true,
}

local function find_matching_brace(text, opener_index)
  local depth = 1
  local index = opener_index + 1

  while index <= #text do
    local char = text:sub(index, index)
    if char == "{" and not is_escaped_at(text, index) then
      depth = depth + 1
    elseif char == "}" and not is_escaped_at(text, index) then
      depth = depth - 1
      if depth == 0 then
        return index
      end
    end
    index = index + 1
  end

  return nil
end

local function protect_text_command_arguments(text)
  local protected = {}
  local output = {}
  local index = 1
  local protected_count = 0
  local placeholder_prefix = "\31MATHWRAP_TEXT_ARG_"

  while index <= #text do
    local matched_command
    for command in pairs(protected_text_commands) do
      if text:sub(index, index + #command - 1) == command then
        local after = index + #command
        local next_char = text:sub(after, after)
        if next_char == "{" then
          matched_command = command
          break
        end
      end
    end

    if matched_command then
      local opener = index + #matched_command
      local closer = find_matching_brace(text, opener)
      if closer then
        protected_count = protected_count + 1
        local placeholder = ("%s%d\31"):format(placeholder_prefix, protected_count)
        while text:find(placeholder, 1, true) do
          protected_count = protected_count + 1
          placeholder = ("%s%d\31"):format(placeholder_prefix, protected_count)
        end
        table.insert(protected, { placeholder = placeholder, original = text:sub(index, closer) })
        table.insert(output, placeholder)
        index = closer + 1
      else
        table.insert(output, text:sub(index, index))
        index = index + 1
      end
    else
      table.insert(output, text:sub(index, index))
      index = index + 1
    end
  end

  return table.concat(output), protected
end

local function replace_literal(text, needle, replacement)
  local output = {}
  local position = 1

  while position <= #text do
    local start_index, end_index = text:find(needle, position, true)
    if not start_index then
      table.insert(output, text:sub(position))
      break
    end

    table.insert(output, text:sub(position, start_index - 1))
    table.insert(output, replacement)
    position = end_index + 1
  end

  return table.concat(output)
end

local function restore_protected_text(line, protected)
  for _, entry in ipairs(protected) do
    line = replace_literal(line, entry.placeholder, entry.original)
  end
  return line
end

local function normalize_math_body(lines)
  local protected_body, protected = protect_text_command_arguments(table.concat(lines, " "))
  return vim.trim(protected_body:gsub("%s+", " ")), protected
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

is_escaped_at = function(text, index)
  local backslashes = 0
  local cursor = index - 1
  while cursor >= 1 and text:sub(cursor, cursor) == "\\" do
    backslashes = backslashes + 1
    cursor = cursor - 1
  end

  return backslashes % 2 == 1
end

local function is_attached_to_left_command(text, index)
  return text:sub(math.max(1, index - 5), index - 1) == "\\left"
end

local function is_attached_to_right_command(text, index)
  return text:sub(math.max(1, index - 6), index - 1) == "\\right"
end

local function escaped_opener_at(text, index)
  local opener = text:sub(index, index)
  if not raw_openers[opener] or not is_escaped_at(text, index) then
    return nil
  end

  return {
    start = index - 1,
    finish = index,
    token = text:sub(index - 1, index),
    kind = "escaped",
    opener = opener,
    expected_closer = raw_closers[opener],
  }
end

local function escaped_closer_at(text, index)
  local closer = text:sub(index, index)
  if not raw_closer_set[closer] or not is_escaped_at(text, index) then
    return nil
  end

  return {
    start = index - 1,
    finish = index,
    token = text:sub(index - 1, index),
    kind = "escaped",
    closer = closer,
  }
end

local function scalable_delimiter_at(text, index, command)
  if text:sub(index, index + #command - 1) ~= command then
    return nil
  end

  local delimiter_start = index + #command
  local delimiter = text:sub(delimiter_start, delimiter_start)
  if delimiter == "" then
    return nil
  end

  local finish = delimiter_start
  if delimiter == "\\" then
    local command_end = text:find("[^%a]", delimiter_start + 1)
    if command_end then
      finish = command_end - 1
    else
      finish = #text
    end
    if finish < delimiter_start + 1 then
      finish = delimiter_start + 1
    end
  elseif delimiter:match("[%a]") then
    return nil
  end

  return {
    start = index,
    finish = finish,
    token = text:sub(index, finish),
  }
end

local function left_delimiter_at(text, index)
  return scalable_delimiter_at(text, index, "\\left")
end

local function right_delimiter_at(text, index)
  return scalable_delimiter_at(text, index, "\\right")
end

local raw_opener_at
local raw_closer_at
local unsupported_opener_at
local unsupported_closer_at
local any_depth_opener_at
local any_depth_closer_at
local advance_delimiter_depth

local interval_openers = {
  ["("] = true,
  ["["] = true,
}

local interval_closers = {
  [")"] = true,
  ["]"] = true,
}

local function delimiter_payload(token)
  local payload = token:gsub("^\\left", ""):gsub("^\\right", "")
  if #payload > 1 and payload:sub(1, 1) == "\\" then
    return payload:sub(#payload, #payload)
  end
  return payload
end

local function is_interval_endpoint(text)
  text = vim.trim(text)
  if text == "" or #text > 28 then
    return false
  end
  if text:find("[,;=_]") then
    return false
  end

  local compact = text:gsub("%s+", "")
  if compact:match("^%-?\\infty$") or compact:match("^%+?\\infty$") then
    return true
  end
  if compact:match("^%-?%d+%.?%d*$") then
    return true
  end
  if compact:match("^%-?\\frac{%d+}{%d+}$") then
    return true
  end
  if compact:match("^%-?%a$") then
    return true
  end

  return false
end

local function has_one_top_level_comma(text)
  local comma_count = 0
  local stack = {}
  local index = 1

  while index <= #text do
    local advanced, next_index = advance_delimiter_depth(text, index, stack)
    if advanced then
      index = next_index
    elseif #stack == 0 and text:sub(index, index) == "," then
      comma_count = comma_count + 1
      if comma_count > 1 then
        return false
      end
      index = index + 1
    else
      index = index + 1
    end
  end

  return comma_count == 1
end

local function find_interval_comma(text)
  local stack = {}
  local index = 1

  while index <= #text do
    local advanced, next_index = advance_delimiter_depth(text, index, stack)
    if advanced then
      index = next_index
    elseif #stack == 0 and text:sub(index, index) == "," then
      return index
    else
      index = index + 1
    end
  end

  return nil
end

local function is_interval_inner(text)
  if not has_one_top_level_comma(text) then
    return false
  end

  local comma = find_interval_comma(text)
  return comma ~= nil and is_interval_endpoint(text:sub(1, comma - 1)) and is_interval_endpoint(text:sub(comma + 1))
end

local function raw_interval_atom_at(text, index)
  local opener = raw_opener_at(text, index)
  if not opener or not interval_openers[opener.opener] then
    return nil
  end

  local stack = {}
  local cursor = opener.finish + 1
  while cursor <= #text do
    local nested_opener = raw_opener_at(text, cursor)
    local closer = raw_closer_at(text, cursor)
    local unsupported_opener = unsupported_opener_at(text, cursor)
    local unsupported_closer = unsupported_closer_at(text, cursor)

    if unsupported_opener then
      table.insert(stack, { unsupported = true })
      cursor = unsupported_opener.finish + 1
    elseif unsupported_closer and #stack > 0 and stack[#stack].unsupported then
      table.remove(stack)
      cursor = unsupported_closer.finish + 1
    elseif nested_opener then
      table.insert(stack, { closer = nested_opener.expected_closer, unsupported = false })
      cursor = nested_opener.finish + 1
    elseif closer and #stack > 0 then
      if not stack[#stack].unsupported and closer.closer ~= stack[#stack].closer then
        return nil
      end
      table.remove(stack)
      cursor = closer.finish + 1
    elseif closer and #stack == 0 then
      local inner = text:sub(opener.finish + 1, closer.start - 1)
      if interval_closers[closer.closer] and is_interval_inner(inner) then
        return { start = opener.start, finish = closer.finish, token = text:sub(opener.start, closer.finish) }
      end
      return nil
    else
      cursor = cursor + 1
    end
  end

  return nil
end

local function scalable_interval_atom_at(text, index)
  local opener = left_delimiter_at(text, index)
  if not opener or not interval_openers[delimiter_payload(opener.token)] then
    return nil
  end

  local stack = {}
  local cursor = opener.finish + 1
  while cursor <= #text do
    local nested_opener = any_depth_opener_at(text, cursor)
    local closer = any_depth_closer_at(text, cursor)
    local right = right_delimiter_at(text, cursor)

    if right and #stack == 0 then
      local closer_payload = delimiter_payload(right.token)
      local inner = text:sub(opener.finish + 1, right.start - 1)
      if interval_closers[closer_payload] and is_interval_inner(inner) then
        return { start = opener.start, finish = right.finish, token = text:sub(opener.start, right.finish) }
      end
      return nil
    elseif nested_opener then
      table.insert(stack, { closer = nested_opener.expected_closer, unsupported = nested_opener.expected_closer == nil })
      cursor = nested_opener.finish + 1
    elseif closer and #stack > 0 then
      table.remove(stack)
      cursor = closer.finish + 1
    else
      cursor = cursor + 1
    end
  end

  return nil
end

local function interval_atom_at(text, index)
  return raw_interval_atom_at(text, index) or scalable_interval_atom_at(text, index)
end

raw_opener_at = function(text, index)
  local opener = text:sub(index, index)
  if not raw_openers[opener] or is_escaped_at(text, index) or is_attached_to_left_command(text, index) then
    return nil
  end

  return {
    start = index,
    finish = index,
    token = opener,
    kind = "raw",
    opener = opener,
    expected_closer = raw_closers[opener],
  }
end

raw_closer_at = function(text, index)
  local closer = text:sub(index, index)
  if not raw_closer_set[closer] or is_escaped_at(text, index) or is_attached_to_right_command(text, index) then
    return nil
  end

  return {
    start = index,
    finish = index,
    token = closer,
    kind = "raw",
    closer = closer,
  }
end

unsupported_opener_at = function(text, index)
  return left_delimiter_at(text, index)
end

unsupported_closer_at = function(text, index)
  return right_delimiter_at(text, index)
end

any_depth_opener_at = function(text, index)
  return raw_opener_at(text, index) or escaped_opener_at(text, index) or unsupported_opener_at(text, index)
end

any_depth_closer_at = function(text, index)
  return raw_closer_at(text, index) or escaped_closer_at(text, index) or unsupported_closer_at(text, index)
end

advance_delimiter_depth = function(text, index, stack)
  local interval_atom = interval_atom_at(text, index)
  if interval_atom then
    return true, interval_atom.finish + 1
  end

  local unsupported_opener = unsupported_opener_at(text, index)
  local unsupported_closer = unsupported_closer_at(text, index)
  local opener = raw_opener_at(text, index) or escaped_opener_at(text, index)
  local closer = raw_closer_at(text, index) or escaped_closer_at(text, index)
  local inside_unsupported = #stack > 0 and stack[#stack].unsupported

  if unsupported_opener then
    table.insert(stack, { unsupported = true })
    return true, unsupported_opener.finish + 1
  end
  if unsupported_closer and inside_unsupported then
    table.remove(stack)
    return true, unsupported_closer.finish + 1
  end
  if inside_unsupported then
    return opener ~= nil or closer ~= nil, index + 1
  end
  if opener then
    table.insert(stack, { closer = opener.expected_closer, kind = opener.kind, unsupported = false })
    return true, opener.finish + 1
  end
  if closer then
    if #stack > 0 and closer.kind == stack[#stack].kind and closer.closer == stack[#stack].closer then
      table.remove(stack)
    end
    return true, closer.finish + 1
  end

  return false, index
end

local function advance_unsupported_depth(text, index, stack)
  local unsupported_opener = unsupported_opener_at(text, index)
  local unsupported_closer = unsupported_closer_at(text, index)

  if unsupported_opener then
    table.insert(stack, { unsupported = true })
    return true, unsupported_opener.finish + 1
  end
  if unsupported_closer and #stack > 0 then
    table.remove(stack)
    return true, unsupported_closer.finish + 1
  end

  return false, index
end

local function has_operand_before(text, operator_index, segment_start)
  local left = vim.trim(text:sub(segment_start, operator_index - 1))
  if left == "" then
    return false
  end

  local last = left:sub(#left, #left)
  if last:match("[%+%-%*/=<>:]") then
    return false
  end

  local command = left:match("(\\%a+)%s*$")
  if command then
    return not ({
      ["\\cdot"] = true,
      ["\\times"] = true,
      ["\\leq"] = true,
      ["\\geq"] = true,
      ["\\in"] = true,
      ["\\sim"] = true,
      ["\\to"] = true,
    })[command]
  end

  return true
end

local function has_operand_after(text, operator_index)
  local right = vim.trim(text:sub(operator_index + 1))
  if right == "" then
    return false
  end

  local first = right:sub(1, 1)
  if first == "+" or first == "-" then
    local after_sign = vim.trim(right:sub(2))
    return after_sign ~= ""
  end

  return true
end

local function find_matching_closer(text, opener_token)
  local expected_closer = opener_token.expected_closer
  if not expected_closer then
    return nil
  end

  local stack = { { closer = expected_closer, kind = opener_token.kind, unsupported = false } }
  local index = opener_token.finish + 1
  while index <= #text do
    local interval_atom = interval_atom_at(text, index)
    local nested_opener = raw_opener_at(text, index) or escaped_opener_at(text, index)
    local closer_token = raw_closer_at(text, index) or escaped_closer_at(text, index)
    local unsupported_opener = unsupported_opener_at(text, index)
    local unsupported_closer = unsupported_closer_at(text, index)

    if interval_atom then
      index = interval_atom.finish + 1
    elseif unsupported_opener then
      table.insert(stack, { unsupported = true })
      index = unsupported_opener.finish + 1
    elseif unsupported_closer and stack[#stack].unsupported then
      table.remove(stack)
      index = unsupported_closer.finish + 1
    elseif nested_opener and not stack[#stack].unsupported then
      table.insert(stack, { closer = nested_opener.expected_closer, kind = nested_opener.kind, unsupported = false })
      index = nested_opener.finish + 1
    elseif closer_token and not stack[#stack].unsupported then
      if closer_token.kind ~= stack[#stack].kind then
        index = closer_token.finish + 1
      elseif closer_token.closer ~= stack[#stack].closer then
        return nil
      else
        table.remove(stack)
        if #stack == 0 then
          return closer_token
        end
        index = closer_token.finish + 1
      end
    else
      index = index + 1
    end
  end

  return nil
end

local function split_top_level_additive(text)
  local segments = {}
  local segment_start = 1
  local stack = {}
  local index = 1

  while index <= #text do
    local char = text:sub(index, index)
    local advanced, next_index = advance_delimiter_depth(text, index, stack)
    if advanced then
      index = next_index
    elseif #stack == 0 and (char == "+" or char == "-") then
      if has_operand_before(text, index, segment_start) and has_operand_after(text, index) then
        table.insert(segments, vim.trim(text:sub(segment_start, index - 1)))
        segment_start = index
      end
      index = index + 1
    else
      index = index + 1
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
  local stack = {}
  local index = 1

  while index <= #text do
    local char = text:sub(index, index)
    local advanced, next_index = advance_delimiter_depth(text, index, stack)
    if advanced then
      index = next_index
    elseif #stack == 0 and (char == "," or char == ";") then
      table.insert(items, { text = vim.trim(text:sub(item_start, index - 1)), separator = char })
      item_start = index + 1
      index = index + 1
    else
      index = index + 1
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

local function find_top_level_token(text, token, position)
  local stack = {}
  local index = position
  while index <= #text do
    local advanced, next_index = advance_delimiter_depth(text, index, stack)
    if advanced then
      index = next_index
    elseif #stack == 0 and text:sub(index, index + #token - 1) == token then
      return index, index + #token - 1
    else
      index = index + 1
    end
  end

  return nil
end

local function find_expandable_group(line)
  if #line <= 60 then
    return nil
  end

  local stack = {}
  local opener_index = 1
  while opener_index <= #line do
    local advanced, next_index = advance_unsupported_depth(line, opener_index, stack)
    local opener_token = nil
    if advanced then
      opener_index = next_index
    elseif #stack == 0 then
      opener_token = raw_opener_at(line, opener_index) or escaped_opener_at(line, opener_index)
      if not opener_token then
        opener_index = opener_index + 1
      end
    else
      opener_index = opener_index + 1
    end

    if opener_token then
      local closer_token = find_matching_closer(line, opener_token)
      if closer_token then
        local inner = vim.trim(line:sub(opener_token.finish + 1, closer_token.start - 1))
        local segments = split_bracket_inner(inner)
        if segments then
          return opener_token, closer_token, segments
        end
      end
      opener_index = opener_token.finish + 1
    end
  end

  return nil
end

local expand_bracketed_segment

local function append_expanded_bracketed_line(output, line, indent)
  local opener_token, closer_token, segments = find_expandable_group(line)
  if not opener_token then
    table.insert(output, indent .. line)
    return
  end

  local opener_prefix = vim.trim(line:sub(1, opener_token.finish))
  local suffix = vim.trim(line:sub(closer_token.finish + 1))
  table.insert(output, indent .. opener_prefix)
  for _, segment in ipairs(segments) do
    expand_bracketed_segment(output, segment, indent .. "  ")
  end
  table.insert(output, indent .. closer_token.token)
  if suffix ~= "" then
    expand_bracketed_segment(output, suffix, indent)
  end
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
  local leq_start, leq_end = find_top_level_token(body, "\\leq", position)
  local geq_start, geq_end = find_top_level_token(body, "\\geq", position)
  local eq_start, eq_end = find_top_level_token(body, "=", position)

  local relation_start, relation_end, relation
  for _, candidate in ipairs({
    { start = find_top_level_token(body, ":=", position), token = ":=" },
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
    local start_index, end_index = find_top_level_token(body, token, position)
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
  local body, protected = normalize_math_body(lines)
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

  for index, line in ipairs(formatted) do
    formatted[index] = restore_protected_text(line, protected)
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
