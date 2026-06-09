local M = {}

function M.find_top_level_token(text, token, position, advance_depth)
  local stack = {}
  local index = position

  while index <= #text do
    local advanced, next_index = advance_depth(text, index, stack)
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

function M.split_top_level(text, is_split_token, advance_depth, opts)
  opts = opts or {}

  local segments = {}
  local segment_start = 1
  local stack = {}
  local index = 1

  while index <= #text do
    local advanced, next_index = advance_depth(text, index, stack)
    if advanced then
      index = next_index
    elseif #stack == 0 and is_split_token(text, index, segment_start) then
      table.insert(segments, { text = vim.trim(text:sub(segment_start, index - 1)), token = text:sub(index, index) })
      if opts.keep_token_with_next then
        segment_start = index
      else
        segment_start = index + 1
      end
      index = index + 1
    else
      index = index + 1
    end
  end

  if #segments == 0 then
    return nil
  end

  table.insert(segments, { text = vim.trim(text:sub(segment_start)), token = "" })
  return segments
end

return M
