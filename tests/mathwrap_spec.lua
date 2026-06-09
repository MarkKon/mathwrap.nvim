local function reset_mathwrap()
  package.loaded["mathwrap"] = nil
end

local function assert_lines(expected)
  local actual = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(vim.deep_equal(actual, expected), ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end

local tests = {}

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

tests["do not expand visible or scalable delimiter groups in raw delimiter slice"] = function()
  reset_mathwrap()
  require("mathwrap").setup({})

  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "$$",
    "  visible = \\{alpha_one + alpha_two + alpha_three + alpha_four + alpha_five\\}  ",
    "  scalable = \\left(beta_one + beta_two + beta_three + beta_four + beta_five\\right)  ",
    "  escaped = \\(gamma_one + gamma_two + gamma_three + gamma_four + gamma_five\\)  ",
    "$$",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.cmd("LatexMathFormat")

  assert_lines({
    "$$",
    "visible",
    "= \\{alpha_one + alpha_two + alpha_three + alpha_four + alpha_five\\} scalable",
    "= \\left(beta_one + beta_two + beta_three + beta_four + beta_five\\right) escaped",
    "= \\(gamma_one + gamma_two + gamma_three + gamma_four + gamma_five\\)",
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
