local helpers = {}

-- Add all common test utilities
helpers.expect = vim.deepcopy (MiniTest.expect)
helpers.new_set = MiniTest.new_set

-- Add extra expectations that are missing from MiniTest.expect
helpers.expect.match = MiniTest.new_expectation ("string matching", function (str, pattern)
  return str:find (pattern) ~= nil
end, function (str, pattern)
  return string.format ("Pattern: %s\nObserved string: %s", vim.inspect (pattern), str)
end)

helpers.expect.no_match = MiniTest.new_expectation ("no string matching", function (str, pattern)
  return str:find (pattern) == nil
end, function (str, pattern)
  return string.format ("Pattern: %s\nObserved string: %s", vim.inspect (pattern), str)
end)

-- Create child Neovim process for testing
helpers.new_child_neovim = function ()
  local child = MiniTest.new_child_neovim ()

  -- Extend with helper methods
  function child.set_lines (lines)
    child.api.nvim_buf_set_lines (0, 0, -1, false, lines)
  end

  function child.get_lines ()
    return child.api.nvim_buf_get_lines (0, 0, -1, false)
  end

  return child
end

return helpers
