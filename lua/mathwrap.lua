local M = {}

local function is_display_math_delimiter(line)
  return line:match("^%s*%$%$%s*$") ~= nil
end

local function find_enclosing_display_math_block(bufnr, cursor_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local opener

  for line_number = cursor_line, 1, -1 do
    if is_display_math_delimiter(lines[line_number] or "") then
      opener = line_number
      break
    end
  end

  if not opener then
    return nil
  end

  local closer
  for line_number = opener + 1, #lines do
    if is_display_math_delimiter(lines[line_number] or "") then
      closer = line_number
      break
    end
  end

  if not closer or cursor_line > closer then
    return nil
  end

  return opener, closer
end

local function format_math_body(lines)
  local formatted = {}
  for _, line in ipairs(lines) do
    table.insert(formatted, vim.trim(line))
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
