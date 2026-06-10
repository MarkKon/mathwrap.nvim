local M = {}

local defaults = {
  command = true,
  indent = "  ",
  max_width = 60,
  split_classes = {
    equation_relations = { ":=", "\\leq", "\\geq", "=" },
    logical_connectors = { "\\implies", "\\iff" },
    clause_separators = { "\\qquad", "\\quad" },
    membership_relations = { "\\in", "\\sim", "\\to" },
    additive_operators = { "+", "-" },
    punctuation_separators = { ",", ";" },
  },
  protected_text_commands = { "\\text", "\\textrm", "\\textit", "\\textbf", "\\mathrm", "\\operatorname" },
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
    split_classes = vim.tbl_deep_extend("force", defaults.split_classes, opts.split_classes or {}),
    protected_text_commands = opts.protected_text_commands or defaults.protected_text_commands,
    source_layout = {
      indent = indent,
      max_width = max_width,
      split_classes = vim.tbl_deep_extend("force", defaults.split_classes, opts.split_classes or {}),
      protected_text_commands = opts.protected_text_commands or defaults.protected_text_commands,
    },
  }
end

return M
