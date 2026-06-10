local config = require("mathwrap.config")
local math_structure = require("mathwrap.math_structure")
local scanner = require("mathwrap.scanner")

local M = {}

local format_options = config.normalize({}).source_layout

local structure_context = math_structure.new_context(format_options)
local append_expanded_bracketed_line

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

local function split_top_level_additive(text)
  local split_segments = scanner.split_top_level(text, function(candidate, index, segment_start)
    local char = candidate:sub(index, index)
    return vim.tbl_contains(format_options.split_classes.additive_operators, char)
      and has_operand_before(candidate, index, segment_start)
      and has_operand_after(candidate, index)
  end, structure_context.advance_delimiter_depth, { keep_token_with_next = true })

  if not split_segments then
    return nil
  end

  local segments = {}
  for index = 2, #split_segments do
    table.insert(segments, split_segments[index - 1].text)
  end
  table.insert(segments, split_segments[#split_segments].text)

  return segments
end

local function split_top_level_punctuation_items(text)
  local split_segments = scanner.split_top_level(text, function(candidate, index)
    local char = candidate:sub(index, index)
    return vim.tbl_contains(format_options.split_classes.punctuation_separators, char)
  end, structure_context.advance_delimiter_depth)

  if not split_segments or #split_segments < 3 then
    return nil
  end

  local items = {}
  for index, segment in ipairs(split_segments) do
    table.insert(items, {
      text = segment.text,
      separator = index < #split_segments and segment.token or "",
    })
  end
  return items
end

local function split_top_level_implicit_products(text)
  local factors = {}
  local structural_factor_count = 0

  local function skip_spaces(index)
    while index <= #text and text:sub(index, index):match("%s") do
      index = index + 1
    end
    return index
  end

  local parse_factor

  local function consume_script(index)
    local marker = text:sub(index, index)
    if marker ~= "^" and marker ~= "_" then
      return index
    end

    local argument_start = skip_spaces(index + 1)
    local application = structure_context.math_command_application_at(text, argument_start)
    if application then
      return application.finish + 1
    end

    local opener = structure_context.raw_opener_at(text, argument_start)
      or structure_context.escaped_opener_at(text, argument_start)
      or structure_context.left_delimiter_at(text, argument_start)
      or structure_context.vertical_delimiter_at(text, argument_start)
    if opener then
      local closer = structure_context.find_matching_closer(text, opener)
      if closer then
        return closer.finish + 1
      end
    end

    local command = structure_context.command_token_at(text, argument_start)
    if command then
      return command.finish + 1
    end

    if argument_start <= #text then
      return argument_start + 1
    end
    return index
  end

  local function consume_scripts(index)
    local cursor = index
    while cursor <= #text do
      local next_cursor = consume_script(cursor)
      if next_cursor == cursor then
        break
      else
        cursor = next_cursor
      end
    end
    return cursor
  end

  local function consume_primary(index)
    local application = structure_context.math_command_application_at(text, index)
    if application then
      return application.finish + 1, "command_application", true
    end

    local opener = structure_context.raw_opener_at(text, index)
      or structure_context.escaped_opener_at(text, index)
      or structure_context.left_delimiter_at(text, index)
      or structure_context.vertical_delimiter_at(text, index)
    if opener then
      local closer = structure_context.find_matching_closer(text, opener)
      if closer then
        return closer.finish + 1, "delimiter", true
      end
    end

    local command = structure_context.command_token_at(text, index)
    if command then
      return command.finish + 1, "command", false
    end

    local char = text:sub(index, index)
    if char == "" or char:match("[%+%-%*/=,;]") then
      return nil
    end
    local finish = index
    if char:match("[%w]") then
      while finish <= #text and text:sub(finish, finish):match("[%w']") do
        finish = finish + 1
      end
      return finish, "atom", false
    end
    return index + 1, "atom", false
  end

  parse_factor = function(index)
    index = skip_spaces(index)
    if index > #text then
      return nil
    end

    local start_index = index
    local cursor, kind, structural = consume_primary(index)
    if not cursor then
      return nil
    end

    local before_scripts = cursor
    cursor = consume_scripts(cursor)
    local has_scripts = cursor ~= before_scripts

    if kind == "command" or (kind == "atom" and has_scripts) then
      local argument_start = skip_spaces(cursor)
      local opener = structure_context.raw_opener_at(text, argument_start)
        or structure_context.escaped_opener_at(text, argument_start)
        or structure_context.left_delimiter_at(text, argument_start)
      if opener then
        local closer = structure_context.find_matching_closer(text, opener)
        if closer then
          cursor = consume_scripts(closer.finish + 1)
          structural = true
        end
      end
    end

    if text:sub(cursor, cursor) == "." then
      cursor = cursor + 1
    end

    return vim.trim(text:sub(start_index, cursor - 1)), cursor, structural
  end

  local cursor = 1
  while cursor <= #text do
    local factor, next_cursor, structural = parse_factor(cursor)
    if not factor then
      return nil
    end
    table.insert(factors, factor)
    if structural then
      structural_factor_count = structural_factor_count + 1
    end
    cursor = skip_spaces(next_cursor)
  end

  if #factors < 2 or structural_factor_count < 2 then
    return nil
  end
  return factors
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

local function has_top_level_structural_separator(text, start_index, finish_index)
  local stack = {}
  local index = start_index

  while index <= finish_index do
    local advanced, next_index = structure_context.advance_delimiter_depth(text, index, stack)
    if advanced then
      index = next_index
    elseif #stack == 0 then
      local char = text:sub(index, index)
      if
        vim.tbl_contains(format_options.split_classes.additive_operators, char)
        or vim.tbl_contains(format_options.split_classes.punctuation_separators, char)
      then
        return true
      end
      index = index + 1
    else
      index = index + 1
    end
  end

  return false
end

local function find_top_level_token(text, token, position)
  return scanner.find_top_level_token(text, token, position, structure_context.advance_delimiter_depth)
end

local function suffix_closes_containing_group(suffix)
  local stack = {}
  local index = 1
  while index <= #suffix do
    local closer = structure_context.raw_closer_at(suffix, index) or structure_context.escaped_closer_at(suffix, index) or structure_context.right_delimiter_at(suffix, index)
    if closer and #stack == 0 then
      return vim.trim(suffix:sub(closer.finish + 1)) == ""
    end

    local advanced, next_index = structure_context.advance_delimiter_depth(suffix, index, stack)
    if advanced then
      index = next_index
    else
      index = index + 1
    end
  end

  return false
end

local function suffix_can_attach_to_child_closer(suffix, opener_prefix)
  if suffix == "" then
    return true
  end
  if suffix:find("=", 1, true) then
    return false
  end
  if suffix_closes_containing_group(suffix) then
    return true
  end
  if vim.trim(suffix):match("^[%^_]") then
    return true
  end
  if vim.trim(suffix):match("^[%.,;]$") then
    return true
  end

  local first = vim.trim(suffix):sub(1, 1)
  local follows_command_argument = opener_prefix:match("\\[%a]+.*[%[{]$") ~= nil
  return follows_command_argument
    and (
      vim.tbl_contains(format_options.split_classes.additive_operators, first)
      or vim.tbl_contains(format_options.split_classes.punctuation_separators, first)
    )
end

local function candidate_direct_lines_fit(line, candidate)
  if candidate.opener.kind == "vertical" then
    return false
  end

  local opener_prefix = vim.trim(line:sub(1, candidate.opener.finish))
  local suffix = vim.trim(line:sub(candidate.closer.finish + 1))
  if not suffix_can_attach_to_child_closer(suffix, opener_prefix) then
    return false
  end

  if #opener_prefix > format_options.max_width then
    return false
  end
  for _, segment in ipairs(candidate.segments) do
    if #segment + #format_options.indent > format_options.max_width then
      return false
    end
  end

  local closer_line = candidate.closer.token
  if suffix ~= "" then
    closer_line = closer_line .. " " .. suffix
  end
  return #closer_line <= format_options.max_width
end

local function is_substantial_scalable_group(opener_token, inner)
  return opener_token.kind == "scalable" and #inner > format_options.compact_atom_width
end

local function find_expandable_group(line, force)
  if not force and #line <= format_options.max_width then
    return nil
  end

  local candidates = {}
  local stack = {}
  local opener_index = 1
  while opener_index <= #line do
    local advanced, next_index = structure_context.advance_unsupported_depth(line, opener_index, stack)
    local opener_token = nil
    if advanced then
      opener_index = next_index
    elseif #stack == 0 then
      local command_application = structure_context.math_command_application_at(line, opener_index)
      if command_application then
        opener_index = command_application.start + 1
      else
        opener_token = structure_context.raw_opener_at(line, opener_index) or structure_context.escaped_opener_at(line, opener_index) or structure_context.left_delimiter_at(line, opener_index) or structure_context.vertical_delimiter_at(line, opener_index)
        if not opener_token then
          opener_index = opener_index + 1
        end
      end
    else
      opener_index = opener_index + 1
    end

    if opener_token then
      local closer_token = structure_context.find_matching_closer(line, opener_token)
      if closer_token then
        local inner = vim.trim(line:sub(opener_token.finish + 1, closer_token.start - 1))
        local segments = split_bracket_inner(inner)
        local synthetic_scalable_segments = false
        if not segments and opener_token.kind == "scalable" then
          segments = { inner }
          synthetic_scalable_segments = true
        end
        if segments and #inner > format_options.compact_atom_width then
          table.insert(candidates, {
            opener = opener_token,
            closer = closer_token,
            segments = segments,
            synthetic_scalable_segments = synthetic_scalable_segments and not is_substantial_scalable_group(opener_token, inner),
          })
        end
      end
      opener_index = opener_token.finish + 1
    end
  end

  local satisfying_candidate
  for _, candidate in ipairs(candidates) do
    if not candidate.synthetic_scalable_segments and candidate_direct_lines_fit(line, candidate) then
      satisfying_candidate = candidate
    end
  end
  if satisfying_candidate then
    return satisfying_candidate.opener, satisfying_candidate.closer, satisfying_candidate.segments, true
  end

  for _, candidate in ipairs(candidates) do
    if candidate.opener.kind == "scalable" then
      local first_candidate = candidates[1]
      local contains_eligible_nested_candidate = false
      if candidate.synthetic_scalable_segments then
        for _, nested_candidate in ipairs(candidates) do
          if
            nested_candidate ~= candidate
            and candidate.opener.start < nested_candidate.opener.start
            and nested_candidate.closer.finish < candidate.closer.finish
          then
            contains_eligible_nested_candidate = true
            break
          end
        end
      end
      if
        (not candidate.synthetic_scalable_segments or contains_eligible_nested_candidate)
        and not (
          first_candidate ~= candidate
          and first_candidate.opener.start < candidate.opener.start
          and candidate.closer.finish < first_candidate.closer.finish
        )
        and (
          first_candidate == candidate
          or not has_top_level_structural_separator(line, first_candidate.opener.start, candidate.opener.start - 1)
        )
      then
        return candidate.opener, candidate.closer, candidate.segments, false
      end
      break
    end
  end

  for _, candidate in ipairs(candidates) do
    if not candidate.synthetic_scalable_segments then
      return candidate.opener, candidate.closer, candidate.segments, false
    end
  end

  return nil
end

local expand_bracketed_segment

append_expanded_bracketed_line = function(output, line, indent, force)
  if indent == "" then
    local leading_indent = line:match("^(%s*)") or ""
    if leading_indent ~= "" then
      indent = leading_indent
      line = vim.trim(line)
    end
  end

  local opener_token, closer_token, segments, attach_suffix = find_expandable_group(line, force)
  if not opener_token then
    table.insert(output, indent .. line)
    return
  end

  local opener_prefix = vim.trim(line:sub(1, opener_token.finish))
  local suffix = vim.trim(line:sub(closer_token.finish + 1))
  table.insert(output, indent .. opener_prefix)
  for _, segment in ipairs(segments) do
    expand_bracketed_segment(output, segment, indent .. format_options.indent)
  end
  if suffix ~= "" and (attach_suffix or vim.trim(suffix):match("^[%^_]") or vim.trim(suffix):match("^[%.,;]$")) and suffix_can_attach_to_child_closer(suffix, opener_prefix) then
    local trimmed_suffix = vim.trim(suffix)
    local separator = (trimmed_suffix:match("^[%^_]") or trimmed_suffix:match("^[%.,;]$")) and "" or " "
    table.insert(output, indent .. closer_token.token .. separator .. suffix)
    return
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
  if not format_options.bracket_expansion then
    return lines
  end

  local expanded = {}

  for _, line in ipairs(lines) do
    append_expanded_bracketed_line(expanded, line, "")
  end

  return expanded
end

local function find_next_equation_relation(body, position)
  local relation_start, relation_end, relation
  for _, token in ipairs(format_options.split_classes.equation_relations) do
    local start_index, end_index = find_top_level_token(body, token, position)
    local candidate = { start = start_index, finish = end_index, token = token }
    if candidate.start and (not relation_start or candidate.start < relation_start) then
      relation_start = candidate.start
      relation = candidate.token
      relation_end = candidate.finish
    end
  end

  return relation_start, relation_end, relation
end

local function find_next_membership_relation(body, position)
  local relation_start, relation_end, relation
  for _, token in ipairs(format_options.split_classes.membership_relations or {}) do
    local start_index, end_index = find_top_level_token(body, token, position)
    if start_index and (not relation_start or start_index < relation_start) then
      relation_start = start_index
      relation_end = end_index
      relation = token
    end
  end

  return relation_start, relation_end, relation
end

local function split_width_pressure_membership_relations(lines)
  local split = {}

  for _, line in ipairs(lines) do
    if #line <= format_options.max_width then
      table.insert(split, line)
    else
      local position = 1
      local line_split = false
      while position <= #line do
        local relation_start, relation_end, relation = find_next_membership_relation(line, position)
        if not relation_start then
          local segment = vim.trim(line:sub(position))
          if segment ~= "" then
            if not line_split then
              table.insert(split, segment)
            else
              split[#split] = split[#split] .. " " .. segment
            end
          end
          break
        end

        local segment = vim.trim(line:sub(position, relation_start - 1))
        if not line_split then
          if segment ~= "" then
            table.insert(split, segment)
          end
          line_split = true
        elseif segment ~= "" then
          split[#split] = split[#split] .. " " .. segment
        end
        table.insert(split, relation)
        position = relation_end + 1
      end
    end
  end

  return split
end

local function leading_relation_prefix(line)
  for _, token in ipairs(format_options.split_classes.equation_relations) do
    if line:sub(1, #token + 1) == token .. " " then
      return token, vim.trim(line:sub(#token + 2))
    end
  end
  return nil, line
end

local function split_width_pressure_implicit_products(lines)
  local split = {}

  local function append_product_factor(line)
    if line:find("\\left", 1, true) then
      append_expanded_bracketed_line(split, line, "", true)
    else
      table.insert(split, line)
    end
  end

  for _, line in ipairs(lines) do
    if #line <= format_options.max_width then
      table.insert(split, line)
    else
      local relation, body = leading_relation_prefix(line)
      local factors = split_top_level_implicit_products(body)
      if not factors then
        table.insert(split, line)
      else
        for index, factor in ipairs(factors) do
          if index == 1 and relation then
            append_product_factor(relation .. " " .. factor)
          elseif relation then
            append_product_factor(format_options.indent .. factor)
          else
            append_product_factor(factor)
          end
        end
      end
    end
  end

  return split
end

local function format_equation_clause(body)
  if format_options.relation_split_policy == "width" and #body <= format_options.max_width then
    return expand_bracketed_expressions({ body })
  end

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
    local relation_prefix = ""
    if segment:match("&%s*$") then
      relation_prefix = "&"
      segment = vim.trim(segment:gsub("%s*&%s*$", ""))
    end
    if #formatted == 0 then
      table.insert(formatted, segment)
    elseif segment ~= "" then
      formatted[#formatted] = formatted[#formatted] .. " " .. segment
    end
    table.insert(formatted, relation_prefix .. relation)
    position = relation_end + 1
  end

  return expand_bracketed_expressions(split_width_pressure_implicit_products(split_width_pressure_membership_relations(formatted)))
end

local function find_next_clause_separator(body, position)
  local separator_start, separator_end, separator
  local tokens = {}
  for _, token in ipairs(format_options.split_classes.logical_connectors) do
    table.insert(tokens, token)
  end
  for _, token in ipairs(format_options.split_classes.clause_separators) do
    table.insert(tokens, token)
  end
  for _, token in ipairs(tokens) do
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

local function split_top_level_rows(body)
  local rows = {}
  local row_start = 1
  local stack = {}
  local index = 1

  while index <= #body do
    local advanced, next_index = structure_context.advance_delimiter_depth(body, index, stack)
    if advanced then
      index = next_index
    elseif #stack == 0 and body:sub(index, index + 1) == "\\\\" then
      table.insert(rows, vim.trim(body:sub(row_start, index - 1)))
      row_start = index + 2
      index = index + 2
    else
      index = index + 1
    end
  end

  if row_start == 1 then
    return nil
  end

  table.insert(rows, vim.trim(body:sub(row_start)))
  return rows
end

local function format_row(body)
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

function M.format(lines, opts)
  opts = opts or {}
  format_options = {
    indent = opts.indent or "  ",
    max_width = opts.max_width or 60,
    relation_split_policy = opts.relation_split_policy or "always",
    bracket_expansion = opts.bracket_expansion ~= false,
    compact_atom_width = opts.compact_atom_width or 28,
    split_classes = opts.split_classes or format_options.split_classes,
    protected_text_commands = opts.protected_text_commands or format_options.protected_text_commands,
    math_commands = opts.math_commands or format_options.math_commands,
  }
  structure_context = math_structure.new_context(format_options)

  local body, protected = structure_context.normalize_math_body(lines)
  if structure_context.has_line_bound_comment(body) then
    return nil, "line-bound comment outside protected text command"
  end
  if body == "" then
    return #lines == 0 and {} or { "" }
  end

  local formatted = {}
  local rows = split_top_level_rows(body) or { body }

  for row_index, row in ipairs(rows) do
    if row ~= "" then
      for _, line in ipairs(format_row(row)) do
        table.insert(formatted, line)
      end
    end
    if row_index < #rows then
      table.insert(formatted, "\\\\")
    end
  end

  for index, line in ipairs(formatted) do
    formatted[index] = structure_context.restore_protected_text(line, protected)
  end

  return formatted
end

return M
