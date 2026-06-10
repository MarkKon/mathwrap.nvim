local function reset_mathwrap()
  package.loaded["mathwrap"] = nil
end

local function assert_lines(expected)
  local actual = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(vim.deep_equal(actual, expected), ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end

local function assert_format_snapshot(name, input, expected, opts)
  reset_mathwrap()
  local mathwrap = require("mathwrap")
  mathwrap.setup(opts or {})

  local once = assert(mathwrap.format(input))
  assert(vim.deep_equal(once, expected), ("%s: expected %s, got %s"):format(name, vim.inspect(expected), vim.inspect(once)))

  local twice = assert(mathwrap.format(once))
  assert(vim.deep_equal(twice, once), ("%s: expected idempotent output, got %s then %s"):format(name, vim.inspect(once), vim.inspect(twice)))
end

local tests = {}

tests["public format entry point formats math body lines without registering commands"] = function()
  reset_mathwrap()
  local mathwrap = require("mathwrap")
  mathwrap.setup({ command = false })

  local command_exists = vim.fn.exists(":LatexMathFormat")
  local formatted = assert(mathwrap.format({ "  a=b  " }))

  assert(command_exists == 0, "expected setup({ command = false }) to skip command registration")
  assert(vim.deep_equal(formatted, { "a", "= b" }), ("expected formatted lines, got %s"):format(vim.inspect(formatted)))
end

tests["setup command registration can disable repeatedly and re-enable"] = function()
  reset_mathwrap()
  local mathwrap = require("mathwrap")

  mathwrap.setup({})
  assert(vim.fn.exists(":LatexMathFormat") == 2, "expected default setup to register command")

  mathwrap.setup({ command = false })
  assert(vim.fn.exists(":LatexMathFormat") == 0, "expected command=false to remove command")

  mathwrap.setup({ command = false })
  assert(vim.fn.exists(":LatexMathFormat") == 0, "expected repeated command=false to keep command absent")

  mathwrap.setup({})
  assert(vim.fn.exists(":LatexMathFormat") == 2, "expected setup to re-enable command")
end

tests["setup exposes indentation and soft width formatting defaults"] = function()
  reset_mathwrap()
  local mathwrap = require("mathwrap")
  mathwrap.setup({ indent = "    ", max_width = 20 })

  local formatted = assert(mathwrap.format({
    "  F = alpha(beta_one + beta_two + beta_three)  ",
  }))

  assert(vim.deep_equal(formatted, {
    "F",
    "= alpha(",
    "    beta_one",
    "    + beta_two",
    "    + beta_three",
    ")",
  }), ("expected configured indentation and width, got %s"):format(vim.inspect(formatted)))
end

tests["setup exposes split classes and protected text commands"] = function()
  reset_mathwrap()
  local mathwrap = require("mathwrap")
  mathwrap.setup({
    split_classes = {
      equation_relations = { "=", "\\approx" },
      logical_connectors = { "\\iff", "\\therefore" },
      clause_separators = { "\\quad" },
    },
    protected_text_commands = { "\\text", "\\customtext" },
  })

  local formatted = assert(mathwrap.format({
    "  a \\approx b \\therefore c = \\customtext{keep   spaces = inline}  ",
  }))

  assert(vim.deep_equal(formatted, {
    "a",
    "\\approx b",
    "\\therefore",
    "c",
    "= \\customtext{keep   spaces = inline}",
  }), ("expected configured split classes and protected commands, got %s"):format(vim.inspect(formatted)))
end

tests["custom split class lists replace defaults"] = function()
  reset_mathwrap()
  local mathwrap = require("mathwrap")
  mathwrap.setup({
    split_classes = {
      equation_relations = { "=" },
      logical_connectors = {},
    },
  })

  local formatted = assert(mathwrap.format({
    "  a\\leq b = c \\iff d = e  ",
  }))

  assert(vim.deep_equal(formatted, {
    "a\\leq b",
    "= c \\iff d",
    "= e",
  }), ("expected provided split lists to replace defaults, got %s"):format(vim.inspect(formatted)))
end

tests["empty split class list disables that class"] = function()
  reset_mathwrap()
  local mathwrap = require("mathwrap")
  mathwrap.setup({
    split_classes = {
      equation_relations = {},
    },
  })

  local formatted = assert(mathwrap.format({
    "  a=b\\leq c:=d\\geq e  ",
  }))

  assert(vim.deep_equal(formatted, {
    "a=b\\leq c:=d\\geq e",
  }), ("expected empty equation relation list to disable relation splits, got %s"):format(vim.inspect(formatted)))
end

tests["setup exposes relation policy bracket expansion and compact atom width"] = function()
  reset_mathwrap()
  local mathwrap = require("mathwrap")
  mathwrap.setup({
    max_width = 80,
    relation_split_policy = "width",
    bracket_expansion = false,
    compact_atom_width = 3,
  })

  local formatted = assert(mathwrap.format({
    "  a=b  ",
    "  value = [0,10] + alpha_one + alpha_two + alpha_three + alpha_four  ",
  }))

  assert(vim.deep_equal(formatted, {
    "a=b value = [0,10] + alpha_one + alpha_two + alpha_three + alpha_four",
  }), ("expected configured policy and disabled expansion, got %s"):format(vim.inspect(formatted)))
end

tests["width relation split policy only splits relations under width pressure"] = function()
  reset_mathwrap()
  local mathwrap = require("mathwrap")
  mathwrap.setup({ max_width = 9, relation_split_policy = "width" })

  local compact = assert(mathwrap.format({ "  a=b  " }))
  local wide = assert(mathwrap.format({ "  alpha=beta  " }))

  assert(vim.deep_equal(compact, { "a=b" }), ("expected compact relation chain to stay inline, got %s"):format(vim.inspect(compact)))
  assert(vim.deep_equal(wide, { "alpha", "= beta" }), ("expected wide relation chain to split, got %s"):format(vim.inspect(wide)))
end

tests["context regression snapshots format idempotently"] = function()
  local snapshots = {
    {
      name = "equation relations use leading operator lines",
      input = { "  a=b\\leq c:=d\\geq e  " },
      expected = { "a", "= b", "\\leq c", ":= d", "\\geq e" },
    },
    {
      name = "logical connectors and spacing separators split clauses",
      input = { "  a=b \\iff c=d \\quad e=f  " },
      expected = { "a", "= b", "\\iff", "c", "= d", "\\quad", "e", "= f" },
    },
    {
      name = "compact membership relations stay inline",
      input = { "  z\\sim\\pi x\\in A f:X\\to Y  " },
      expected = { "z\\sim\\pi x\\in A f:X\\to Y" },
    },
    {
      name = "over-width membership relations split with leading operator lines",
      input = { "  source_object_with_long_name\\to target_object_with_long_name  " },
      expected = { "source_object_with_long_name", "\\to target_object_with_long_name" },
      opts = { max_width = 40 },
    },
    {
      name = "custom membership relations replace defaults",
      input = { "  alpha\\mapsto beta\\to gamma  " },
      expected = { "alpha", "\\mapsto beta\\to gamma" },
      opts = { max_width = 10, split_classes = { membership_relations = { "\\mapsto" } } },
    },
    {
      name = "bracket expansion uses leading operators and aligned closers",
      input = { "  F = alpha(beta_one + beta_two + beta_three + beta_four + beta_five + beta_six)  " },
      expected = { "F", "= alpha(", "  beta_one", "  + beta_two", "  + beta_three", "  + beta_four", "  + beta_five", "  + beta_six", ")" },
    },
    {
      name = "interval atoms remain compact inside expanded groups",
      input = { "  intervals = outer((-\\infty, 0] + [0,1) + \\left[0,\\frac{1}{2}\\right) + tail_one + tail_two)  " },
      expected = { "intervals", "= outer(", "  (-\\infty, 0]", "  + [0,1)", "  + \\left[0,\\frac{1}{2}\\right)", "  + tail_one", "  + tail_two", ")" },
    },
    {
      name = "protected text command arguments keep internal whitespace",
      input = { "  label = \\text{two   spaces = stay + inline} \\quad name = \\operatorname{very   long + operator + name + stays + inline}  " },
      expected = { "label", "= \\text{two   spaces = stay + inline}", "\\quad", "name", "= \\operatorname{very   long + operator + name + stays + inline}" },
    },
    {
      name = "row separators and alignment markers are preserved",
      input = { "  a & = b \\\\ c&\\leq d \\\\ e = f  " },
      expected = { "a", "&= b", "\\\\", "c", "&\\leq d", "\\\\", "e", "= f" },
    },
  }

  for _, snapshot in ipairs(snapshots) do
    assert_format_snapshot(snapshot.name, snapshot.input, snapshot.expected, snapshot.opts)
  end
end

tests["format outside enclosing display math block leaves buffer unchanged and reports error"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  local notifications = {}
  local original_notify = vim.notify
  vim.notify = function(message, level)
    table.insert(notifications, { message = message, level = level })
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "before",
    "$$",
    "  a + b  ",
    "$$",
    "after",
  })
  vim.api.nvim_win_set_cursor(0, { 5, 0 })

  vim.cmd("LatexMathFormat")

  vim.notify = original_notify
  assert_lines({
    "before",
    "$$",
    "  a + b  ",
    "$$",
    "after",
  })
  assert(#notifications == 1, "expected one error notification")
  assert(notifications[1].level == vim.log.levels.ERROR, "expected error notification level")
  assert(notifications[1].message:match("no enclosing display math block"), "expected clear missing target error")
end

tests["setup registers LatexMathFormat and formats enclosing display math block"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "before",
    "$$",
    "  a + b  ",
    "$$",
    "after",
  })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "before",
    "$$",
    "a + b",
    "$$",
    "after",
  })
end

tests["format targets block when cursor is on either display math delimiter"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  a + b  ",
    "$$",
    "",
    "$$",
    "  c + d  ",
    "$$",
  })

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("LatexMathFormat")

  vim.api.nvim_win_set_cursor(0, { 7, 0 })
  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "a + b",
    "$$",
    "",
    "$$",
    "c + d",
    "$$",
  })
end

tests["format recognizes only standalone display math delimiters and preserves delimiter spelling"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$ \\tag{not-a-delimiter}",
    "  $$  ",
    "  a + b  ",
    "\t$$",
    "$$ decorated",
  })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$ \\tag{not-a-delimiter}",
    "  $$  ",
    "a + b",
    "\t$$",
    "$$ decorated",
  })
end

tests["format normalizes equality chains with leading operator lines"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  a   =",
    "    b  =   c  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "a",
    "= b",
    "= c",
    "$$",
  })
end

tests["format definition chains with leading operator lines"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  f:=g   :=  h  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "f",
    ":= g",
    ":= h",
    "$$",
  })
end

tests["format inequality chains with leading operator lines"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  x\\leq  y",
    "    \\geq z  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "x",
    "\\leq y",
    "\\geq z",
    "$$",
  })
end

tests["format relation chains idempotently"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  a=b\\leq c:=d\\geq e  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")
  local once = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  vim.cmd("LatexMathFormat")
  local twice = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  assert(vim.deep_equal(twice, once), ("expected idempotent output, got %s then %s"):format(vim.inspect(once), vim.inspect(twice)))
  assert_lines({
    "$$",
    "a",
    "= b",
    "\\leq c",
    ":= d",
    "\\geq e",
    "$$",
  })
end

tests["preserve row separators and format each row independently"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  a=b \\\\ c \\leq d  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "a",
    "= b",
    "\\\\",
    "c",
    "\\leq d",
    "$$",
  })
end

tests["preserve alignment markers as relation operator prefixes without creating new markers"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  a & = b \\\\ c&\\leq d \\\\ e = f  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "a",
    "&= b",
    "\\\\",
    "c",
    "&\\leq d",
    "\\\\",
    "e",
    "= f",
    "$$",
  })
end

tests["format rows with alignment markers idempotently"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  total & = first + second \\\\ bound & \\geq lower  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")
  local once = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  vim.cmd("LatexMathFormat")
  local twice = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  assert(vim.deep_equal(twice, once), ("expected idempotent output, got %s then %s"):format(vim.inspect(once), vim.inspect(twice)))
  assert_lines({
    "$$",
    "total",
    "&= first + second",
    "\\\\",
    "bound",
    "&\\geq lower",
    "$$",
  })
end

tests["format logical connectors as standalone clause-level lines"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  a=b \\iff c=d  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "a",
    "= b",
    "\\iff",
    "c",
    "= d",
    "$$",
  })
end

tests["format spacing clause separators as standalone lines"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  a=b \\quad c=d  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "a",
    "= b",
    "\\quad",
    "c",
    "= d",
    "$$",
  })
end

tests["keep compact membership relations inline by default"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  z\\sim\\pi",
    "  x\\in A",
    "  f:X\\to Y  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "z\\sim\\pi x\\in A f:X\\to Y",
    "$$",
  })
end

tests["preserve atomic spacing tokens inline"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  a\\,b  c\\:d",
    "  e\\;f g\\!h i\\ j  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "a\\,b c\\:d e\\;f g\\!h i\\ j",
    "$$",
  })
end

tests["expand long parenthesized sums with leading operator lines"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  F = alpha(beta_one + beta_two + beta_three + beta_four + beta_five + beta_six)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "F",
    "= alpha(",
    "  beta_one",
    "  + beta_two",
    "  + beta_three",
    "  + beta_four",
    "  + beta_five",
    "  + beta_six",
    ")",
    "$$",
  })
end

tests["expand list-like bracketed groups with trailing separators before additive splits"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  values = [alpha_one + alpha_two, beta_one + beta_two, gamma_one + gamma_two]  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "values",
    "= [",
    "  alpha_one",
    "  + alpha_two,",
    "  beta_one",
    "  + beta_two,",
    "  gamma_one",
    "  + gamma_two",
    "]",
    "$$",
  })
end

tests["keep interval atoms compact inside expandable groups"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  intervals = outer((-\\infty, 0] + [0,1) + \\left[0,\\frac{1}{2}\\right) + tail_one + tail_two)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "intervals",
    "= outer(",
    "  (-\\infty, 0]",
    "  + [0,1)",
    "  + \\left[0,\\frac{1}{2}\\right)",
    "  + tail_one",
    "  + tail_two",
    ")",
    "$$",
  })
end

tests["do not force uncertain mixed comma groups into interval atoms"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  uncertain = outer((alpha_one,beta_two] + gamma_three + delta_four + epsilon_five + zeta_six)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "uncertain",
    "= outer((alpha_one,beta_two] + gamma_three + delta_four + epsilon_five + zeta_six)",
    "$$",
  })
end

tests["preserve protected text command arguments without normalization or expansion"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  label = \\text{two   spaces = stay + inline} \\quad name = \\operatorname{very   long + operator + name + stays + inline}  ",
    "  \\quad styles = \\textrm{roman   text} + \\textit{italic   text} + \\textbf{bold   text} + \\mathrm{math   roman}  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "label",
    "= \\text{two   spaces = stay + inline}",
    "\\quad",
    "name",
    "= \\operatorname{very   long + operator + name + stays + inline}",
    "\\quad",
    "styles",
    "= \\textrm{roman   text} + \\textit{italic   text} + \\textbf{bold   text} + \\mathrm{math   roman}",
    "$$",
  })
end

tests["unsafe comments outside protected text command arguments fail closed without changing buffer"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  local notifications = {}
  local original_notify = vim.notify
  vim.notify = function(message, level)
    table.insert(notifications, { message = message, level = level })
  end

  local original = {
    "$$",
    "  a = b % line-bound comment",
    "  c = d",
    "$$",
  }
  vim.api.nvim_buf_set_lines(0, 0, -1, false, original)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  vim.notify = original_notify
  assert_lines(original)
  assert(#notifications == 1, "expected one error notification")
  assert(notifications[1].level == vim.log.levels.ERROR, "expected error notification level")
  assert(notifications[1].message:match("line%-bound comment"), "expected clear unsafe comment error")
end

tests["preserve literal text that looks like a protected text placeholder"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  token = MWTEXTARG1 + \\text{real   protected text}  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "token",
    "= MWTEXTARG1 + \\text{real   protected text}",
    "$$",
  })
end

tests["restore many protected text command arguments idempotently"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  labels = \\text{one   stays} + \\text{two   stays} + \\text{three   stays} + \\text{four   stays} + \\text{five   stays} + \\text{six   stays} + \\text{seven   stays} + \\text{eight   stays} + \\text{nine   stays} + \\text{ten   stays}  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")
  local once = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  vim.cmd("LatexMathFormat")
  local twice = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  assert(vim.deep_equal(twice, once), ("expected idempotent output, got %s then %s"):format(vim.inspect(once), vim.inspect(twice)))
  assert_lines({
    "$$",
    "labels",
    "= \\text{one   stays} + \\text{two   stays} + \\text{three   stays} + \\text{four   stays} + \\text{five   stays} + \\text{six   stays} + \\text{seven   stays} + \\text{eight   stays} + \\text{nine   stays} + \\text{ten   stays}",
    "$$",
  })
end

tests["expand long non-text braced command arguments"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  value = \\frac{alpha_one + alpha_two + alpha_three + alpha_four + alpha_five}{denominator}  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "value",
    "= \\frac{",
    "  alpha_one",
    "  + alpha_two",
    "  + alpha_three",
    "  + alpha_four",
    "  + alpha_five",
    "}",
    "{denominator}",
    "$$",
  })
end

tests["expand nested raw bracketed groups recursively while preserving delimiter spelling"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  result = wrap(first_term + inner{alpha_one + alpha_two + alpha_three + alpha_four + alpha_five} + last_term)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "result",
    "= wrap(",
    "  first_term",
    "  + inner{",
    "    alpha_one",
    "    + alpha_two",
    "    + alpha_three",
    "    + alpha_four",
    "    + alpha_five",
    "  }",
    "  + last_term",
    ")",
    "$$",
  })
end

tests["expand raw bracketed expressions idempotently"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  output = {left_one + left_two; right_one + right_two; final_one + final_two}  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")
  local once = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  vim.cmd("LatexMathFormat")
  local twice = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  assert(vim.deep_equal(twice, once), ("expected idempotent output, got %s then %s"):format(vim.inspect(once), vim.inspect(twice)))
  assert_lines({
    "$$",
    "output",
    "= {",
    "  left_one",
    "  + left_two;",
    "  right_one",
    "  + right_two;",
    "  final_one",
    "  + final_two",
    "}",
    "$$",
  })
end

tests["expand visible brace delimiter groups while preserving escaped tokens"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  visible = \\{alpha_one + alpha_two + alpha_three + alpha_four + alpha_five\\}  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "visible",
    "= \\{",
    "  alpha_one",
    "  + alpha_two",
    "  + alpha_three",
    "  + alpha_four",
    "  + alpha_five",
    "\\}",
    "$$",
  })
end

tests["preserve escaped math delimiters without treating them as visible delimiter groups"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  visible = \\{alpha_one + alpha_two + alpha_three + alpha_four + alpha_five\\}  ",
    "  paren = \\(beta_one + beta_two + beta_three + beta_four + beta_five\\)  ",
    "  bracket = \\[gamma_one + gamma_two + gamma_three + gamma_four + gamma_five\\]  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "visible",
    "= \\{",
    "  alpha_one",
    "  + alpha_two",
    "  + alpha_three",
    "  + alpha_four",
    "  + alpha_five",
    "\\}",
    "paren",
    "= \\(beta_one + beta_two + beta_three + beta_four + beta_five\\) bracket",
    "= \\[gamma_one + gamma_two + gamma_three + gamma_four + gamma_five\\]",
    "$$",
  })
end

tests["expand vertical delimiter pairs without treating bars as clause separators"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  raw = |alpha_one + alpha_two + alpha_three + alpha_four + alpha_five|  ",
    "  escaped = \\|beta_one + beta_two + beta_three + beta_four + beta_five\\|  ",
    "  condition = \\{x\\in A | x\\mid y\\}  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "raw",
    "= |",
    "  alpha_one",
    "  + alpha_two",
    "  + alpha_three",
    "  + alpha_four",
    "  + alpha_five",
    "|",
    "escaped",
    "= \\|",
    "  beta_one",
    "  + beta_two",
    "  + beta_three",
    "  + beta_four",
    "  + beta_five",
    "\\|",
    "condition",
    "= \\{x\\in A | x\\mid y\\}",
    "$$",
  })
end

tests["preserve unpaired vertical bars inside enclosing groups"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  builder = \\{x\\in A | predicate_one + predicate_two + predicate_three + predicate_four + predicate_five\\}  ",
    "  escaped_builder = \\{x\\in A \\| predicate_one + predicate_two + predicate_three + predicate_four + predicate_five\\}  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "builder",
    "= \\{",
    "  x\\in A | predicate_one",
    "  + predicate_two",
    "  + predicate_three",
    "  + predicate_four",
    "  + predicate_five",
    "\\}",
    "escaped_builder",
    "= \\{",
    "  x\\in A \\| predicate_one",
    "  + predicate_two",
    "  + predicate_three",
    "  + predicate_four",
    "  + predicate_five",
    "\\}",
    "$$",
  })
end

tests["expand scalable delimiter pairs while preserving attached delimiters"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  plain = \\left(beta_one + beta_two + beta_three + beta_four + beta_five\\right)  ",
    "  mixed = \\left[gamma_one + gamma_two + gamma_three + gamma_four + gamma_five\\right)  ",
    "  escaped = \\left.delta_one + delta_two + delta_three + delta_four + delta_five\\right\\}  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "plain",
    "= \\left(",
    "  beta_one",
    "  + beta_two",
    "  + beta_three",
    "  + beta_four",
    "  + beta_five",
    "\\right)",
    "mixed",
    "= \\left[",
    "  gamma_one",
    "  + gamma_two",
    "  + gamma_three",
    "  + gamma_four",
    "  + gamma_five",
    "\\right)",
    "escaped",
    "= \\left.",
    "  delta_one",
    "  + delta_two",
    "  + delta_three",
    "  + delta_four",
    "  + delta_five",
    "\\right\\}",
    "$$",
  })
end

tests["format visible vertical and scalable delimiter expansions idempotently"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  all = \\{alpha_one + alpha_two + alpha_three + alpha_four + alpha_five\\} + |beta_one + beta_two + beta_three + beta_four + beta_five| + \\left(gamma_one + gamma_two + gamma_three + gamma_four + gamma_five\\right]  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")
  local once = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  vim.cmd("LatexMathFormat")
  local twice = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  assert(vim.deep_equal(twice, once), ("expected idempotent output, got %s then %s"):format(vim.inspect(once), vim.inspect(twice)))
  assert_lines({
    "$$",
    "all",
    "= \\{",
    "  alpha_one",
    "  + alpha_two",
    "  + alpha_three",
    "  + alpha_four",
    "  + alpha_five",
    "\\}",
    "+ |",
    "  beta_one",
    "  + beta_two",
    "  + beta_three",
    "  + beta_four",
    "  + beta_five",
    "|",
    "+ \\left(",
    "  gamma_one",
    "  + gamma_two",
    "  + gamma_three",
    "  + gamma_four",
    "  + gamma_five",
    "\\right]",
    "$$",
  })
end

tests["expand bracketed additive chains without splitting unary signs"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  first = (alpha_one + -beta_two + gamma_three + delta_four + epsilon_five)  ",
    "  second = (alpha_one - -beta_two + gamma_three + delta_four + epsilon_five)  ",
    "  third = (-alpha_one + beta_two + gamma_three + delta_four + epsilon_five)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "first",
    "= (",
    "  alpha_one",
    "  + -beta_two",
    "  + gamma_three",
    "  + delta_four",
    "  + epsilon_five",
    ")",
    "second",
    "= (",
    "  alpha_one",
    "  - -beta_two",
    "  + gamma_three",
    "  + delta_four",
    "  + epsilon_five",
    ")",
    "third",
    "= (",
    "  -alpha_one",
    "  + beta_two",
    "  + gamma_three",
    "  + delta_four",
    "  + epsilon_five",
    ")",
    "$$",
  })
end

tests["keep expanded closers alone before suffixes and later groups"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  F = alpha(beta_one + beta_two + beta_three + beta_four + beta_five + beta_six) + tail  ",
    "  G = first(left_one + left_two + left_three + left_four + left_five) + second(right_one + right_two + right_three + right_four + right_five)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "F",
    "= alpha(",
    "  beta_one",
    "  + beta_two",
    "  + beta_three",
    "  + beta_four",
    "  + beta_five",
    "  + beta_six",
    ")",
    "+ tail G",
    "= first(",
    "  left_one",
    "  + left_two",
    "  + left_three",
    "  + left_four",
    "  + left_five",
    ")",
    "+ second(",
    "  right_one",
    "  + right_two",
    "  + right_three",
    "  + right_four",
    "  + right_five",
    ")",
    "$$",
  })
end

tests["do not split relations or clause separators inside raw bracket groups before expansion"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  relation = outer(alpha = beta + gamma = delta + epsilon = zeta + eta = theta)  ",
    "  clause = outer(left_one \\quad right_one + left_two \\quad right_two + left_three \\quad right_three)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "relation",
    "= outer(",
    "  alpha = beta",
    "  + gamma = delta",
    "  + epsilon = zeta",
    "  + eta = theta",
    ")",
    "clause",
    "= outer(",
    "  left_one \\quad right_one",
    "  + left_two \\quad right_two",
    "  + left_three \\quad right_three",
    ")",
    "$$",
  })
end

tests["do not split relations or clause separators inside unsupported delimiter groups"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  visible = \\{alpha = beta \\quad gamma = delta\\}  ",
    "  scalable = \\left(alpha = beta \\quad gamma = delta\\right)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "visible",
    "= \\{alpha = beta \\quad gamma = delta\\} scalable",
    "= \\left(alpha = beta \\quad gamma = delta\\right)",
    "$$",
  })
end

tests["do not split inside unsupported delimiter spans nested in expanded raw groups"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  additive = outer(\\{alpha + beta\\} + gamma + delta + epsilon + zeta)  ",
    "  punctuation = outer(\\left(alpha, beta; eta\\right) + gamma + delta + epsilon + zeta)  ",
    "  relation = outer(\\{alpha = beta \\quad gamma = delta\\} + gamma + delta + epsilon + zeta)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "additive",
    "= outer(",
    "  \\{alpha + beta\\}",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    ")",
    "punctuation",
    "= outer(",
    "  \\left(alpha, beta; eta\\right)",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    ")",
    "relation",
    "= outer(",
    "  \\{alpha = beta \\quad gamma = delta\\}",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    ")",
    "$$",
  })
end

tests["do not split inside general scalable delimiter spans"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  dotted = \\left.alpha = beta \\quad gamma = delta\\right.  ",
    "  bars = \\left|alpha = beta \\quad gamma = delta\\right|  ",
    "  escaped = outer(\\left\\{alpha + beta, eta; theta\\right\\} + gamma + delta + epsilon + zeta)  ",
    "  command = outer(\\left\\langle alpha + beta, eta; theta\\right\\rangle + gamma + delta + epsilon + zeta)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "dotted",
    "= \\left.alpha = beta \\quad gamma = delta\\right. bars",
    "= \\left|alpha = beta \\quad gamma = delta\\right| escaped",
    "= outer(",
    "  \\left\\{alpha + beta, eta; theta\\right\\}",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    ")",
    "command",
    "= outer(",
    "  \\left\\langle alpha + beta, eta; theta\\right\\rangle",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    ")",
    "$$",
  })
end

tests["do not treat arrow commands as scalable delimiter commands"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  a \\leftarrow b = c \\rightarrow d = e  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "a \\leftarrow b",
    "= c \\rightarrow d",
    "= e",
    "$$",
  })
end

tests["do not split unary signs after relations or operators inside expanded brackets"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  relation = outer(alpha = -beta + gamma + delta + epsilon + zeta)  ",
    "  operator = outer(alpha \\cdot -beta + gamma + delta + epsilon + zeta + eta + theta)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "relation",
    "= outer(",
    "  alpha = -beta",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    ")",
    "operator",
    "= outer(",
    "  alpha \\cdot -beta",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    "  + eta",
    "  + theta",
    ")",
    "$$",
  })
end

tests["preserve compact additive operator spacing inside expanded brackets"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  compact = outer(alpha_one+beta_two+gamma_three+delta_four+epsilon_five+zeta_six)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "compact",
    "= outer(",
    "  alpha_one",
    "  +beta_two",
    "  +gamma_three",
    "  +delta_four",
    "  +epsilon_five",
    "  +zeta_six",
    ")",
    "$$",
  })
end

tests["do not close raw groups on closer-like characters inside unsupported spans"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  visible = outer(\\{alpha ) beta\\} + gamma + delta + epsilon + zeta)  ",
    "  scalable = outer(\\left.alpha ) beta\\right. + gamma + delta + epsilon + zeta)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "visible",
    "= outer(",
    "  \\{alpha ) beta\\}",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    ")",
    "scalable",
    "= outer(",
    "  \\left.alpha ) beta\\right.",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    ")",
    "$$",
  })
end

tests["expand visible and scalable delimiter spans recursively"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  visible = \\{inner(alpha_one + alpha_two + alpha_three + alpha_four + alpha_five)\\}  ",
    "  scalable = \\left.inner(alpha_one + alpha_two + alpha_three + alpha_four + alpha_five)\\right.  ",
    "  outer = wrap(\\{inner(alpha_one + alpha_two + alpha_three + alpha_four + alpha_five)\\} + gamma + delta + epsilon + zeta)  ",
    "  outer_scalable = wrap(\\left.inner(alpha_one + alpha_two + alpha_three + alpha_four + alpha_five)\\right. + gamma + delta + epsilon + zeta)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "visible",
    "= \\{inner(",
    "  alpha_one",
    "  + alpha_two",
    "  + alpha_three",
    "  + alpha_four",
    "  + alpha_five",
    ")",
    "\\} scalable",
    "= \\left.inner(",
    "  alpha_one",
    "  + alpha_two",
    "  + alpha_three",
    "  + alpha_four",
    "  + alpha_five",
    ")",
    "\\right. outer",
    "= wrap(",
    "  \\{inner(",
    "    alpha_one",
    "    + alpha_two",
    "    + alpha_three",
    "    + alpha_four",
    "    + alpha_five",
    "  )",
    "  \\}",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    ")",
    "outer_scalable",
    "= wrap(",
    "  \\left.inner(",
    "    alpha_one",
    "    + alpha_two",
    "    + alpha_three",
    "    + alpha_four",
    "    + alpha_five",
    "  )",
    "  \\right.",
    "  + gamma",
    "  + delta",
    "  + epsilon",
    "  + zeta",
    ")",
    "$$",
  })
end

local failures = {}
for name, test in pairs(tests) do
  vim.cmd("enew!")
  local ok, err = pcall(test)
  if not ok then
    table.insert(failures, ("%s\n%s"):format(name, err))
  end
end

if #failures > 0 then
  error(table.concat(failures, "\n\n"))
end
