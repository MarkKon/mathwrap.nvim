# Mathwrap.nvim

Mathwrap.nvim formats the enclosing Markdown display math block in the current buffer.

## Installation

LazyVim-style plugin spec:

```lua
{
  "MarkKon/mathwrap.nvim",
  opts = {},
}
```

Optional normal-mode keymap:

```lua
{
  "MarkKon/mathwrap.nvim",
  opts = {},
  keys = {
    { "<leader>mf", "<cmd>LatexMathFormat<cr>", desc = "Format display math" },
  },
}
```

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
