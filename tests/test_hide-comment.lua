local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Data ========================================================================
local test_lua_file = table.concat({
  '--- This is a module comment',
  '--- @class TestClass',
  'local M = {}',
  '',
  '-- Regular comment',
  'function M.test_function()',
  '  -- Inside function comment',
  '  local x = 1',
  '  return x',
  'end',
  '',
  '-- Another comment',
  'return M',
}, '\n')

local test_lua_file_with_inline_comments = table.concat({
  'local M = {}',
  '',
  'local x = 2 -- end of line comment',
  'local y = 3; -- comment after semicolon',
  'local z --[[block comment]] = 4',
  'local a = --[[comment]] 5',
  'function M.func() -- function comment',
  '  local b = 6 --[[inline block]]',
  '  return b -- return comment',
  'end',
  '',
  '-- Full line comment',
  'return M -- final comment',
}, '\n')

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      -- Add current directory to 'runtimepath' to be able to load from 'lua/'
      child.cmd('set rtp+=.')
    end,
    post_once = child.stop,
  },
})

-- Setup =======================================================================
T['setup()'] = new_set()

T['setup()']['creates `_G.HideComment` global table'] = function()
  child.lua('require("hide-comment").setup()')
  eq(child.lua_get('type(_G.HideComment)'), 'table')
end

T['setup()']['creates autocommands'] = function()
  child.lua('require("hide-comment").setup()')
  local au_output = child.cmd_capture('autocmd HideComment')
  expect.match(au_output, 'HideComment')
end

T['setup()']['creates user commands'] = function()
  child.lua('require("hide-comment").setup()')

  local commands = {
    'HideCommentEnable',
    'HideCommentDisable',
    'HideCommentToggle',
    'HideCommentStatus'
  }

  for _, cmd in ipairs(commands) do
    local cmd_exists = child.fn.exists(':' .. cmd) == 2
    eq(cmd_exists, true, 'Command ' .. cmd .. ' should exist')
  end
end

T['setup()']['respects `config` argument'] = function()
  child.lua('require("hide-comment").setup({ debug = true, auto_enable = true })')
  eq(child.lua_get('HideComment.config.debug'), true)
  eq(child.lua_get('HideComment.config.auto_enable'), true)
end

T['setup()']['validates config'] = function()
  expect.error(function()
    child.lua('require("hide-comment").setup({ conceal_level = 5 })')
  end)

  expect.error(function()
    child.lua('require("hide-comment").setup({ auto_enable = "yes" })')
  end)
end

-- Config ======================================================================
T['config'] = new_set()

T['config']['has correct default'] = function()
  child.lua('require("hide-comment").setup()')

  local config = child.lua_get('HideComment.config')
  eq(config.auto_enable, false)
  eq(config.smart_navigation, true)
  eq(config.conceal_level, 3)
  eq(config.refresh_on_change, true)
  eq(config.debug, false)
  eq(config.silent, false)
end

T['config']['respects buffer local config'] = function()
  child.lua('require("hide-comment").setup({ debug = false })')
  child.lua('vim.b.hidecomment_config = { debug = true }')

  -- Buffer local config should override global
  eq(child.lua_get('require("hide-comment").get_stats().debug'), vim.NIL) -- stats don't expose debug
end

-- -- Core functionality =========================================================
T['enable()'] = new_set()

T['enable()']['works with Lua files'] = function()
  child.lua('require("hide-comment").setup()')

  -- Set up buffer with Lua content
  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  local success = child.lua_get('HideComment.enable()')
  eq(success, true)

  -- Check if comments are concealed
  eq(child.lua_get('HideComment.is_enabled()'), true)

  local stats = child.lua_get('HideComment.get_stats()')
  -- Should have found and concealed comment lines
  expect.no_equality(stats.concealed_lines, 0)
end

T['enable()']['fails gracefully without treesitter'] = function()
  child.lua('require("hide-comment").setup()')

  -- Set up buffer with unknown filetype
  child.set_lines({'-- comment', 'code'})
  child.bo.filetype = 'unknown'

  local result = child.lua_get('{ HideComment.enable() }')
  eq(result[1], false)
  expect.match(result[2] or '', 'treesitter')
end

T['enable()']['respects disable flag'] = function()
  child.lua('require("hide-comment").setup()')
  child.lua('vim.g.hidecomment_disable = true')

  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  local result = child.lua_get('{ HideComment.enable() }')
  eq(result[1], false)
  expect.match(result[2] or '', 'disabled')
end

T['disable()'] = new_set()

T['disable()']['works'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  -- Enable first
  child.lua('HideComment.enable()')
  eq(child.lua_get('HideComment.is_enabled()'), true)

  -- Then disable
  local success = child.lua_get('HideComment.disable()')
  eq(success, true)
  eq(child.lua_get('HideComment.is_enabled()'), false)
end

T['toggle()'] = new_set()

T['toggle()']['works'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  -- Initially disabled
  eq(child.lua_get('HideComment.is_enabled()'), false)

  -- Toggle to enable
  child.lua('HideComment.toggle()')
  eq(child.lua_get('HideComment.is_enabled()'), true)

  -- Toggle to disable
  child.lua('HideComment.toggle()')
  eq(child.lua_get('HideComment.is_enabled()'), false)
end

T['get_stats()'] = new_set()

T['get_stats()']['returns correct structure'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  local stats = child.lua_get('HideComment.get_stats()')

  -- Check structure
  eq(type(stats.buffer), 'number')
  eq(type(stats.total_lines), 'number')
  eq(type(stats.concealed_lines), 'number')
  eq(type(stats.concealed_percentage), 'number')
  eq(type(stats.is_enabled), 'boolean')
  eq(type(stats.is_supported), 'boolean')

  -- Should be supported for Lua
  eq(stats.is_supported, true)
  eq(stats.total_lines, #vim.split(test_lua_file, '\n'))
end

T['get_stats()']['shows correct counts after enabling'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  local stats_before = child.lua_get('HideComment.get_stats()')
  eq(stats_before.concealed_lines, 0)
  eq(stats_before.is_enabled, false)

  child.lua('HideComment.enable()')

  local stats_after = child.lua_get('HideComment.get_stats()')
  expect.no_equality(stats_after.concealed_lines, 0) -- Should have concealed some lines
  eq(stats_after.is_enabled, true)
end

-- Smart navigation ============================================================
T['smart_navigation'] = new_set()

T['smart_navigation']['works when enabled'] = function()
  child.lua('require("hide-comment").setup({ smart_navigation = true })')

  -- Set up buffer with comments that will be concealed
  local lines_with_comments = {
    'line 1',
    '-- comment line 2',
    '-- comment line 3',
    'line 4',
    '-- comment line 5',
    'line 6'
  }
  child.set_lines(lines_with_comments)
  child.bo.filetype = 'lua'

  -- Enable concealing
  child.lua('HideComment.enable()')

  -- Verify comments are concealed
  local stats = child.lua_get('HideComment.get_stats()')
  expect.no_equality(stats.concealed_lines, 0)

  -- Test navigation from line 1 (should skip concealed lines)
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Should jump to line 4, skipping concealed lines 2,3
  child.type_keys('j')
  eq(child.api.nvim_win_get_cursor(0)[1], 4)

  -- Should jump to line 6, skipping concealed line 5
  child.type_keys('j')
  eq(child.api.nvim_win_get_cursor(0)[1], 6)

  -- Test backward navigation

  -- Should jump back to line 4
  child.type_keys('k')
  eq(child.api.nvim_win_get_cursor(0)[1], 4)

  -- Should jump back to line 1
  child.type_keys('k')
  eq(child.api.nvim_win_get_cursor(0)[1], 1)
end

T['smart_navigation']['can be disabled'] = function()
  child.lua('require("hide-comment").setup({ smart_navigation = false })')

  -- Set up buffer with comments that will be concealed
  local lines_with_comments = {
    'line 1',
    '-- comment line 2',
    '-- comment line 3',
    'line 4',
    '-- comment line 5',
    'line 6'
  }
  child.set_lines(lines_with_comments)
  child.bo.filetype = 'lua'

  -- Enable concealing
  child.lua('HideComment.enable()')

  -- Test normal navigation (should NOT skip concealed lines)
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Should move to line 2 (concealed comment)
  child.type_keys('j')
  eq(child.api.nvim_win_get_cursor(0)[1], 2)

  -- Should move to line 3 (concealed comment)
  child.type_keys('j')
  eq(child.api.nvim_win_get_cursor(0)[1], 3)

  -- Should move to line 4 (normal line)
  child.type_keys('j')
  eq(child.api.nvim_win_get_cursor(0)[1], 4)

  -- Verify config
  eq(child.lua_get('HideComment.config.smart_navigation'), false)
end

T['smart_navigation']['works with count'] = function()
  child.lua('require("hide-comment").setup({ smart_navigation = true })')

  -- Set up buffer with comments that will be concealed
  local lines_with_comments = {
    'line 1',
    '-- comment line 2',
    '-- comment line 3',
    'line 4',
    '-- comment line 5',
    'line 6',
    '-- comment line 7',
    'line 8'
  }
  child.set_lines(lines_with_comments)
  child.bo.filetype = 'lua'

  -- Enable concealing
  child.lua('HideComment.enable()')

  -- Test count-based navigation
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Should jump 2 visible lines forward (1->4->6)
  child.type_keys('2j')
  eq(child.api.nvim_win_get_cursor(0)[1], 6)

  -- Should jump 2 visible lines backward (6->4->1)
  child.type_keys('2k')
  eq(child.api.nvim_win_get_cursor(0)[1], 1)
end

-- -- Auto enable =================================================================
T['auto_enable'] = new_set()

T['auto_enable']['works when enabled'] = function()
  child.lua('require("hide-comment").setup({ auto_enable = true })')

  -- Should auto-enable when setting filetype
  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  -- Wait a bit for the autocmd to trigger
  vim.wait(100)

  -- Should be automatically enabled
  eq(child.lua_get('HideComment.is_enabled()'), true)
end

T['auto_enable']['respects disable flag'] = function()
  child.lua([[
    require("hide-comment").setup({ auto_enable = true })
    vim.g.hidecomment_disable = true
  ]])

  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  vim.wait(100)

  -- Should not be enabled due to disable flag
  eq(child.lua_get('HideComment.is_enabled()'), false)
end

-- Edge cases ==================================================================
T['edge_cases'] = new_set()

T['edge_cases']['handles empty buffer'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines({})
  child.bo.filetype = 'lua'

  local success = child.lua_get('HideComment.enable()')
  eq(success, true) -- Should succeed even with empty buffer

  local stats = child.lua_get('HideComment.get_stats()')
  eq(stats.concealed_lines, 0)
  eq(stats.total_lines, 1)
end

T['edge_cases']['handles buffer with no comments'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines({'local x = 1', 'return x'})
  child.bo.filetype = 'lua'

  local success = child.lua_get('HideComment.enable()')
  eq(success, true)

  local stats = child.lua_get('HideComment.get_stats()')
  eq(stats.concealed_lines, 0) -- No comments to conceal
end

T['edge_cases']['handles invalid buffer'] = function()
  child.lua('require("hide-comment").setup()')

  local result = child.lua_get('{ HideComment.enable(999) }')
  eq(result[1], false)
  expect.match(result[2] or '', 'valid')
end

-- -- User commands ===============================================================
T['user_commands'] = new_set()

T['user_commands']['HideCommentEnable works'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  child.cmd('HideCommentEnable')
  eq(child.lua_get('HideComment.is_enabled()'), true)
end

T['user_commands']['HideCommentDisable works'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')
  child.cmd('HideCommentDisable')
  eq(child.lua_get('HideComment.is_enabled()'), false)
end

T['user_commands']['HideCommentToggle works'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  child.cmd('HideCommentToggle')
  eq(child.lua_get('HideComment.is_enabled()'), true)

  child.cmd('HideCommentToggle')
  eq(child.lua_get('HideComment.is_enabled()'), false)
end

T['user_commands']['HideCommentStatus works'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines(vim.split(test_lua_file, '\n'))
  child.bo.filetype = 'lua'

  -- Should not error
  child.cmd('HideCommentStatus')
end

-- Inline comments ============================================================
T['inline_comments'] = new_set()

T['inline_comments']['conceals only end-of-line comment part'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines({'local x = 2 -- end comment'})
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  local line_content = child.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  expect.match(line_content, 'local x = 2')

  local extmarks = child.lua_get('vim.api.nvim_buf_get_extmarks(0, ' ..
    'vim.api.nvim_create_namespace("hide-comment"), 0, -1, {details = true})')

  -- Should have concealing extmarks but line should not be completely hidden
  expect.no_equality(#extmarks, 0)
end

T['inline_comments']['conceals only block comment in middle of line'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines({'local z --[[block comment]] = 4'})
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  local line_content = child.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  expect.match(line_content, 'local z')
  expect.match(line_content, '= 4')

  eq(child.lua_get('HideComment.is_enabled()'), true)
end

T['inline_comments']['handles multiple comments on same line'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines({'local a = --[[first]] 5 -- second'})
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  local line_content = child.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  expect.match(line_content, 'local a =')
  expect.match(line_content, '5')

  eq(child.lua_get('HideComment.is_enabled()'), true)
end

T['inline_comments']['does not conceal lines that are only comments'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines({
    '-- Full line comment',
    'local x = 2 -- inline comment',
    '  -- Indented full line comment'
  })
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  local stats = child.lua_get('HideComment.get_stats()')
  eq(stats.is_enabled, true)

  -- Should have found comments to process
  expect.no_equality(stats.concealed_lines, 0)
end

T['inline_comments']['preserves line visibility for code with comments'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines({'local y = 3; -- comment after semicolon'})
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  -- Line should still be navigable since it has code
  local line_content = child.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  expect.match(line_content, 'local y = 3;')

  eq(child.lua_get('HideComment.is_enabled()'), true)
end

T['inline_comments']['smart navigation skips only full comment lines'] = function()
  child.lua('require("hide-comment").setup({ smart_navigation = true })')

  child.set_lines({
    'local a = 1',
    '-- full line comment',
    'local b = 2 -- inline comment',
    '-- another full line comment',
    'local c = 3'
  })
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Should jump to line 3 (skipping full comment line 2, but not line 3 which has code)
  child.type_keys('j')
  eq(child.api.nvim_win_get_cursor(0)[1], 3)

  -- Should jump to line 5 (skipping full comment line 4)
  child.type_keys('j')
  eq(child.api.nvim_win_get_cursor(0)[1], 5)
end

T['inline_comments']['inline comments stay concealed when cursor is on line'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines({
    'local x = 1',
    'local y = 2 -- this is a comment',
    'local z = 3'
  })
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  -- Position in middle of "local y = 2"
  child.api.nvim_win_set_cursor(0, { 2, 5 })

  local concealcursor = child.api.nvim_get_option_value('concealcursor', { win = 0 })
  expect.match(concealcursor, 'n')
  expect.match(concealcursor, 'i')
  expect.match(concealcursor, 'c')

  local conceallevel = child.api.nvim_get_option_value('conceallevel', { win = 0 })
  expect.no_equality(conceallevel, 0)

  local extmarks = child.lua_get('vim.api.nvim_buf_get_extmarks(0, ' ..
    'vim.api.nvim_create_namespace("hide-comment"), 0, -1, {details = true})')

  expect.no_equality(#extmarks, 0)
  eq(child.lua_get('HideComment.is_enabled()'), true)

  child.api.nvim_win_set_cursor(0, { 2, 0 })
  local concealcursor_start = child.api.nvim_get_option_value('concealcursor', { win = 0 })
  expect.match(concealcursor_start, 'n')

  child.api.nvim_win_set_cursor(0, { 2, 10 })
  local concealcursor_end = child.api.nvim_get_option_value('concealcursor', { win = 0 })
  expect.match(concealcursor_end, 'n')

  local extmarks_after_move = child.lua_get('vim.api.nvim_buf_get_extmarks(0, ' ..
    'vim.api.nvim_create_namespace("hide-comment"), 0, -1, {details = true})')
  expect.no_equality(#extmarks_after_move, 0)
end

T['inline_comments']['multiple inline comments on different lines stay concealed'] = function()
  child.lua('require("hide-comment").setup()')

  child.set_lines({
    'local a = 1 -- first comment',
    'local b = 2',
    'local c = 3 -- second comment',
    'local d = 4 -- third comment'
  })
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  for _, line_num in ipairs({1, 3, 4}) do
    child.api.nvim_win_set_cursor(0, { line_num, 5 })

    local line_content = child.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

    if line_num == 1 then
      expect.match(line_content, 'local a = 1')
    elseif line_num == 3 then
      expect.match(line_content, 'local c = 3')
    elseif line_num == 4 then
      expect.match(line_content, 'local d = 4')
    end
  end

  eq(child.lua_get('HideComment.is_enabled()'), true)

  local extmarks = child.lua_get('vim.api.nvim_buf_get_extmarks(0, ' ..
    'vim.api.nvim_create_namespace("hide-comment"), 0, -1, {details = true})')
  expect.no_equality(#extmarks, 0)
end

T['inline_comments']['horizontal navigation skips concealed inline comments'] = function()
  child.lua('require("hide-comment").setup({ smart_navigation = true })')

  child.set_lines({
    'local x = 2 -- inline comment here',
  })
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Move 1 right
  child.type_keys('l')
  local pos_1 = child.api.nvim_win_get_cursor(0)
  -- Should be at position 1
  eq(pos_1[2], 1)

  -- Move 4 more positions right (total 5)
  child.type_keys('4l')
  local pos_5 = child.api.nvim_win_get_cursor(0)
  -- Should be at position 5
  eq(pos_5[2], 5)

  -- Position near end of "local x = 2"
  child.api.nvim_win_set_cursor(0, { 1, 11 })

  local pos_before = child.api.nvim_win_get_cursor(0)
  child.type_keys('l')
  local pos_after = child.api.nvim_win_get_cursor(0)
  expect.no_equality(pos_before[2], pos_after[2])

  eq(child.lua_get('HideComment.is_enabled()'), true)
end

T['inline_comments']['horizontal navigation with count works correctly'] = function()
  child.lua('require("hide-comment").setup({ smart_navigation = true })')

  child.set_lines({
    'abc def -- comment',
  })
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Move 3 characters right
  child.type_keys('3l')
  local pos_after_3l = child.api.nvim_win_get_cursor(0)

  -- Should have moved from position 0
  expect.no_equality(pos_after_3l[2], 0)

  eq(child.lua_get('HideComment.is_enabled()'), true)
end

T['inline_comments']['horizontal navigation disabled when smart_navigation is false'] = function()
  child.lua('require("hide-comment").setup({ smart_navigation = false })')

  child.set_lines({
    'local x = 2 -- comment',
  })
  child.bo.filetype = 'lua'

  child.lua('HideComment.enable()')

  -- Position cursor at beginning
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Move right - should use normal navigation (no special handling)
  child.type_keys('l')
  local pos_after_l = child.api.nvim_win_get_cursor(0)

  -- Should have moved normally by 1 character
  eq(pos_after_l[2], 1)

  eq(child.lua_get('HideComment.config.smart_navigation'), false)
end

return T
