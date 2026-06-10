# Mathwrap.nvim

Mathwrap.nvim formats Markdown display math source so equations are easier to read in text form without changing rendered LaTeX semantics.

## Installation

LazyVim can use the default configuration with an empty `opts` table:

```lua
{
  "MarkKon/mathwrap.nvim",
  opts = {},
}
```

Add a normal-mode keymap in the same plugin spec when you want one:

```lua
{
  "MarkKon/mathwrap.nvim",
  opts = {},
  keys = {
    { "<leader>mf", "<cmd>LatexMathFormat<cr>", desc = "Format display math" },
  },
}
```

Direct setup uses the same options:

```lua
require("mathwrap").setup({
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
  protected_text_commands = {
    "\\text",
    "\\textrm",
    "\\textit",
    "\\textbf",
    "\\mathrm",
    "\\operatorname",
  },
  math_commands = {
    ["\\frac"] = { required = 2 },
    ["\\sqrt"] = { optional = 1, required = 1 },
    ["\\rootof"] = { optional = 1, required = 1 },
  },
})
```

Set `command = false` to skip `:LatexMathFormat` registration while keeping the Lua API available.
Entries in `math_commands` are merged with the built-in command behavior. Use `required = n` for required arguments and `optional = n` for leading optional arguments written in square brackets. Command arguments may be braced or unbraced; Mathwrap preserves the spelling you wrote instead of adding braces.

## Usage

Place the cursor inside an enclosing display math block, including on either standalone `$$` delimiter, and run:

```vim
:LatexMathFormat
```

Only standalone delimiter lines are recognized:

```markdown
$$
a + b
$$
```

Lines such as `$$ \tag{1}` or `$$ decorated` are not display math delimiters.

For custom mappings or tests, call the direct formatter:

```lua
local formatted, err = require("mathwrap").format({ "a=b" })
```

The public API is intentionally small: `setup(opts)` and `format(lines, opts)`.

## Default Behavior

By default, Mathwrap registers `:LatexMathFormat`, uses two-space indentation, and treats `max_width = 60` as a soft target. Relation operators split to leading operator lines, logical connectors and configured spacing commands become clause-level separator lines, and membership relations such as `x\in A` stay inline until they exceed the soft width target.

Bracket expansion is enabled for long grouped expressions with internal split points. Short interval-like atoms stay compact. Protected text command arguments keep their internal whitespace and are excluded from normalization.

Command-aware layout is enabled for built-in `\frac` and `\sqrt`, plus any configured `math_commands`. This keeps command arguments together for top-level split decisions while still allowing long braced math arguments to expand:

```latex
result = \frac a{b=c} = tail
```

formats as:

```latex
result
= \frac a{b=c}
= tail
```

When one command argument is wide enough to need expansion, Mathwrap prefers expanding only that child argument if the result satisfies `max_width`:

```latex
result = \frac a{long_one + long_two + long_three + long_four} + tail
```

formats as:

```latex
result
= \frac a{
  long_one
  + long_two
  + long_three
  + long_four
} + tail
```

Unknown commands are treated as ordinary command tokens unless configured. For example, `\unknown{a+b}` may still expand the adjacent `{...}` group as a normal math structure, but Mathwrap will not treat it as a command application.

Formatting is idempotent: formatting already formatted output should not change it again. Parse failures such as line-bound comments outside protected text commands fail closed and leave the buffer unchanged.

## Non-Goals

Mathwrap does not render LaTeX, change equation meaning, create LaTeX environments, invent alignment markers, or format inline math. It only rewrites source layout inside an enclosing Markdown display math block.
