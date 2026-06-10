local M = {}

local defaults = {
  command = true,
  indent = "  ",
  max_width = 60,
  source_layout = {
    indent = "  ",
    max_width = 60,
  },
}

function M.normalize(opts)
  opts = opts or {}
  local max_width = opts.max_width or opts.source_layout and opts.source_layout.max_width or defaults.max_width
  local indent = opts.indent or opts.source_layout and opts.source_layout.indent or defaults.indent

  return {
    command = opts.command ~= false,
    indent = indent,
    max_width = max_width,
    source_layout = {
      indent = indent,
      max_width = max_width,
    },
  }
end

return M
