local config = require("mathwrap.config")
local source_layout = require("mathwrap.source_layout")

local M = {}

local current_config = config.normalize()

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

local function latex_math_format()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local opener, closer = find_enclosing_display_math_block(bufnr, cursor_line)

  if not opener then
    vim.notify("LatexMathFormat: no enclosing display math block found", vim.log.levels.ERROR)
    return
  end

  local body = vim.api.nvim_buf_get_lines(bufnr, opener, closer - 1, false)
  local formatted, err = M.format(body)
  if not formatted then
    vim.notify("LatexMathFormat: " .. err, vim.log.levels.ERROR)
    return
  end
  vim.api.nvim_buf_set_lines(bufnr, opener, closer - 1, false, formatted)
end

function M.format(lines, opts)
  local format_config = current_config.source_layout
  if opts then
    format_config = config.normalize(vim.tbl_extend("force", current_config, opts)).source_layout
  end
  return source_layout.format(lines, format_config)
end

function M.setup(opts)
  current_config = config.normalize(opts)

  if current_config.command then
    vim.api.nvim_create_user_command("LatexMathFormat", latex_math_format, {})
  elseif vim.fn.exists(":LatexMathFormat") == 2 then
    vim.api.nvim_del_user_command("LatexMathFormat")
  end
end

return M
