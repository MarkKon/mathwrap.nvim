local function reset_mathwrap()
  package.loaded["mathwrap"] = nil
end

local function assert_lines(expected)
  local actual = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(vim.deep_equal(actual, expected), ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end

local tests = {}

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
