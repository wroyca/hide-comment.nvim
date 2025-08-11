-- Script to run tests for hide-comment
local mini_test = require ("mini.test")

-- Configure test collection
mini_test.setup ({
  collect = {
    find_files = function ()
      return { "tests/test_hide-comment.lua" }
    end,
  },
})

-- Run all tests
mini_test.run ()
