local M = {}

function M.new_context(options)
  options = options or {}
  local is_escaped_at

  local function configured_protected_text_commands()
    local commands = {}
    for _, command in ipairs(options.protected_text_commands) do
      commands[command] = true
    end
    return commands
  end

  local function configured_math_commands()
    return options.math_commands or {}
  end

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
      for command in pairs(configured_protected_text_commands()) do
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

  local function has_line_bound_comment(text)
    for index = 1, #text do
      if text:sub(index, index) == "%" and not is_escaped_at(text, index) then
        return true
      end
    end

    return false
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

  local function command_token_at(text, index)
    if text:sub(index, index) ~= "\\" then
      return nil
    end

    local finish = index + 1
    if text:sub(finish, finish):match("%a") then
      while finish <= #text and text:sub(finish, finish):match("%a") do
        finish = finish + 1
      end
      finish = finish - 1
    elseif finish <= #text then
      finish = index + 1
    else
      return nil
    end

    return { start = index, finish = finish, token = text:sub(index, finish) }
  end

  local function skip_spaces(text, index)
    while index <= #text and text:sub(index, index):match("%s") do
      index = index + 1
    end
    return index
  end

  local function find_matching_raw_group(text, opener_index, opener, closer)
    local depth = 1
    local index = opener_index + 1
    while index <= #text do
      local char = text:sub(index, index)
      if char == opener and not is_escaped_at(text, index) then
        depth = depth + 1
      elseif char == closer and not is_escaped_at(text, index) then
        depth = depth - 1
        if depth == 0 then
          return index
        end
      end
      index = index + 1
    end
    return nil
  end

  local function command_argument_at(text, index, allow_optional)
    index = skip_spaces(text, index)
    local opener = text:sub(index, index)

    if allow_optional and opener == "[" and not is_escaped_at(text, index) then
      local closer = find_matching_raw_group(text, index, "[", "]")
      if closer then
        return { start = index, finish = closer, optional = true, braced = true }
      end
      return nil
    end

    if opener == "{" and not is_escaped_at(text, index) then
      local closer = find_matching_raw_group(text, index, "{", "}")
      if closer then
        return { start = index, finish = closer, optional = false, braced = true }
      end
      return nil
    end

    local command = command_token_at(text, index)
    if command then
      return { start = index, finish = command.finish, optional = false, braced = false }
    end

    if opener ~= "" and not opener:match("%s") and not opener:match("[%[%]{}(),;=+%-]") then
      return { start = index, finish = index, optional = false, braced = false }
    end

    return nil
  end

  local function math_command_application_at(text, index)
    local command = command_token_at(text, index)
    if not command then
      return nil
    end

    local behavior = configured_math_commands()[command.token]
    if not behavior then
      return nil
    end

    local args = {}
    local cursor = command.finish + 1
    for _ = 1, behavior.optional or 0 do
      local argument = command_argument_at(text, cursor, true)
      if argument and argument.optional then
        table.insert(args, argument)
        cursor = argument.finish + 1
      end
    end

    for _ = 1, behavior.required or 0 do
      local argument = command_argument_at(text, cursor, false)
      if not argument then
        return nil
      end
      table.insert(args, argument)
      cursor = argument.finish + 1
    end

    return {
      start = command.start,
      finish = cursor - 1,
      token = command.token,
      args = args,
    }
  end

  local function optional_command_argument_at(text, index)
    for command in pairs(configured_math_commands()) do
      local search_finish = index - 1
      while search_finish >= 1 and text:sub(search_finish, search_finish):match("%s") do
        search_finish = search_finish - 1
      end

      local command_start = search_finish - #command + 1
      if command_start >= 1 and text:sub(command_start, search_finish) == command then
        local before = command_start - 1
        local application = math_command_application_at(text, command_start)
        if
          application
          and (before < 1 or text:sub(before, before) ~= "\\")
          and skip_spaces(text, command_start + #command) == index
        then
          for _, argument in ipairs(application.args) do
            if argument.optional and argument.start == index then
              return argument
            end
          end
        end
      end
    end
    return nil
  end

  local function is_attached_to_left_command(text, index)
    return text:sub(math.max(1, index - 5), index - 1) == "\\left"
  end

  local function is_attached_to_right_command(text, index)
    return text:sub(math.max(1, index - 6), index - 1) == "\\right"
  end

  local function escaped_opener_at(text, index)
    local opener = text:sub(index, index)
    if opener ~= "{" or not is_escaped_at(text, index) then
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
    if closer ~= "}" or not is_escaped_at(text, index) then
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
      kind = "scalable",
      expected_closer = "\\right",
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
    if text == "" or #text > options.compact_atom_width then
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
    return nil
  end

  unsupported_closer_at = function(text, index)
    return nil
  end

  local function vertical_delimiter_at(text, index)
    if text:sub(index, index + 1) == "\\|" then
      return { start = index, finish = index + 1, token = "\\|", kind = "vertical", expected_closer = "\\|" }
    end
    if text:sub(index, index) == "|" and not is_escaped_at(text, index) then
      return { start = index, finish = index, token = "|", kind = "vertical", expected_closer = "|" }
    end
    return nil
  end

  local function has_matching_vertical_delimiter(text, opener_token)
    local stack = {}
    local index = opener_token.finish + 1

    while index <= #text do
      local interval_atom = interval_atom_at(text, index)
      local scalable_opener = left_delimiter_at(text, index)
      local scalable_closer = right_delimiter_at(text, index)
      local opener = raw_opener_at(text, index) or escaped_opener_at(text, index)
      local closer = raw_closer_at(text, index) or escaped_closer_at(text, index)
      local vertical = vertical_delimiter_at(text, index)

      if interval_atom then
        index = interval_atom.finish + 1
      elseif #stack == 0 and vertical and vertical.token == opener_token.token then
        return true
      elseif #stack == 0 and (scalable_closer or closer) then
        return false
      elseif scalable_opener then
        table.insert(stack, { kind = "scalable" })
        index = scalable_opener.finish + 1
      elseif scalable_closer then
        if #stack > 0 and stack[#stack].kind == "scalable" then
          table.remove(stack)
        end
        index = scalable_closer.finish + 1
      elseif opener then
        table.insert(stack, { closer = opener.expected_closer, kind = opener.kind })
        index = opener.finish + 1
      elseif closer then
        if #stack > 0 and stack[#stack].kind == closer.kind and stack[#stack].closer == closer.closer then
          table.remove(stack)
        end
        index = closer.finish + 1
      else
        index = index + 1
      end
    end

    return false
  end

  any_depth_opener_at = function(text, index)
    return raw_opener_at(text, index) or escaped_opener_at(text, index) or left_delimiter_at(text, index) or vertical_delimiter_at(text, index)
  end

  any_depth_closer_at = function(text, index)
    return raw_closer_at(text, index) or escaped_closer_at(text, index) or right_delimiter_at(text, index) or vertical_delimiter_at(text, index)
  end

  advance_delimiter_depth = function(text, index, stack)
    local command_application = math_command_application_at(text, index)
    if command_application then
      return true, command_application.finish + 1
    end

    local interval_atom = interval_atom_at(text, index)
    if interval_atom then
      return true, interval_atom.finish + 1
    end

    local unsupported_opener = unsupported_opener_at(text, index)
    local unsupported_closer = unsupported_closer_at(text, index)
    local scalable_opener = left_delimiter_at(text, index)
    local scalable_closer = right_delimiter_at(text, index)
    local vertical = vertical_delimiter_at(text, index)
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
    if scalable_opener then
      table.insert(stack, { kind = "scalable", unsupported = false })
      return true, scalable_opener.finish + 1
    end
    if scalable_closer then
      if #stack > 0 and stack[#stack].kind == "scalable" then
        table.remove(stack)
      end
      return true, scalable_closer.finish + 1
    end
    if vertical then
      if #stack > 0 and stack[#stack].kind == "vertical" and stack[#stack].token == vertical.token then
        table.remove(stack)
      elseif has_matching_vertical_delimiter(text, vertical) then
        table.insert(stack, { kind = "vertical", token = vertical.token, unsupported = false })
      else
        return false, index
      end
      return true, vertical.finish + 1
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
    local optional_argument = optional_command_argument_at(text, index)
    if optional_argument then
      return true, optional_argument.finish + 1
    end

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

  local function find_matching_closer(text, opener_token)
    local expected_closer = opener_token.expected_closer
    if not expected_closer then
      return nil
    end

    local stack = { { closer = expected_closer, kind = opener_token.kind, token = opener_token.token, unsupported = false } }
    local index = opener_token.finish + 1
    while index <= #text do
      local interval_atom = interval_atom_at(text, index)
      local nested_opener = raw_opener_at(text, index) or escaped_opener_at(text, index) or left_delimiter_at(text, index)
      local closer_token = raw_closer_at(text, index) or escaped_closer_at(text, index) or right_delimiter_at(text, index)
      local vertical = vertical_delimiter_at(text, index)
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
      elseif vertical and not stack[#stack].unsupported then
        if stack[#stack].kind == "vertical" and stack[#stack].token == vertical.token then
          table.remove(stack)
          if #stack == 0 then
            return vertical
          end
        elseif has_matching_vertical_delimiter(text, vertical) then
          table.insert(stack, { kind = "vertical", token = vertical.token, unsupported = false })
        end
        index = vertical.finish + 1
      elseif nested_opener and not stack[#stack].unsupported then
        table.insert(stack, { closer = nested_opener.expected_closer, kind = nested_opener.kind, unsupported = false })
        index = nested_opener.finish + 1
      elseif closer_token and not stack[#stack].unsupported then
        if stack[#stack].kind == "scalable" and closer_token.kind == "scalable" then
          table.remove(stack)
          if #stack == 0 then
            return closer_token
          end
          index = closer_token.finish + 1
        elseif closer_token.kind ~= stack[#stack].kind then
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

  return {
    normalize_math_body = normalize_math_body,
    restore_protected_text = restore_protected_text,
    has_line_bound_comment = has_line_bound_comment,
    command_token_at = command_token_at,
    command_argument_at = command_argument_at,
    math_command_application_at = math_command_application_at,
    optional_command_argument_at = optional_command_argument_at,
    advance_delimiter_depth = advance_delimiter_depth,
    advance_unsupported_depth = advance_unsupported_depth,
    find_matching_closer = find_matching_closer,
    raw_opener_at = raw_opener_at,
    raw_closer_at = raw_closer_at,
    escaped_opener_at = escaped_opener_at,
    escaped_closer_at = escaped_closer_at,
    left_delimiter_at = left_delimiter_at,
    right_delimiter_at = right_delimiter_at,
    vertical_delimiter_at = vertical_delimiter_at,
    interval_atom_at = interval_atom_at,
  }
end

return M
