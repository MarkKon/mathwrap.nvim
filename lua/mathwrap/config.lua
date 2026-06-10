local M = {}

local defaults = {
  command = true,
  indent = "  ",
  max_width = 60,
  relation_split_policy = "always",
  bracket_expansion = true,
  compact_atom_width = 28,
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

local function normalize_split_classes(opts)
  local split_classes = vim.deepcopy(defaults.split_classes)
  for name, tokens in pairs(opts.split_classes or {}) do
    split_classes[name] = tokens
  end
  return split_classes
end

function M.normalize(opts)
  opts = opts or {}
  local max_width = opts.max_width or opts.source_layout and opts.source_layout.max_width or defaults.max_width
  local indent = opts.indent or opts.source_layout and opts.source_layout.indent or defaults.indent
  local relation_split_policy = opts.relation_split_policy or defaults.relation_split_policy
  local bracket_expansion = opts.bracket_expansion
  if bracket_expansion == nil then
    bracket_expansion = defaults.bracket_expansion
  end
  local compact_atom_width = opts.compact_atom_width or defaults.compact_atom_width
  local split_classes = normalize_split_classes(opts)

  return {
    command = opts.command ~= false,
    indent = indent,
    max_width = max_width,
    relation_split_policy = relation_split_policy,
    bracket_expansion = bracket_expansion,
    compact_atom_width = compact_atom_width,
    split_classes = split_classes,
    protected_text_commands = opts.protected_text_commands or defaults.protected_text_commands,
    source_layout = {
      indent = indent,
      max_width = max_width,
      relation_split_policy = relation_split_policy,
      bracket_expansion = bracket_expansion,
      compact_atom_width = compact_atom_width,
      split_classes = split_classes,
      protected_text_commands = opts.protected_text_commands or defaults.protected_text_commands,
    },
  }
end

return M
