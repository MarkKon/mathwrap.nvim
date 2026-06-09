local M = {}

local defaults = {
  command = true,
  source_layout = {
    max_width = 60,
  },
}

function M.normalize(opts)
  opts = opts or {}

  return {
    command = opts.command ~= false,
    source_layout = {
      max_width = defaults.source_layout.max_width,
    },
  }
end

return M
