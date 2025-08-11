-- Example configuration for hide-comment

-- Basic setup
require('hide-comment').setup()

-- Advanced setup with all options
require('hide-comment').setup({
  -- Auto-enable for all supported filetypes
  auto_enable = true,

  -- Enable smart navigation (j/k/h/l skips hidden lines and inline comments)
  smart_navigation = true,

  -- Set conceallevel (0-3, higher = more aggressive)
  conceal_level = 3,

  -- Refresh when buffer changes
  refresh_on_change = true,

  -- Enable debug logging
  debug = false,

  -- Silent mode (no notifications)
  silent = false,
})

-- Keybindings example
vim.keymap.set('n', '<leader>hc', function()
  require('hide-comment').toggle()
end, { desc = 'Toggle hide comments' })

vim.keymap.set('n', '<leader>hs', function()
  local stats = require('hide-comment').get_stats()
  print(string.format('Hidden %d/%d lines (%.1f%%)',
    stats.concealed_lines, stats.total_lines, stats.concealed_percentage))
end, { desc = 'Show hide comment stats' })

-- Auto-commands example
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'lua', 'javascript', 'python' },
  callback = function()
    -- Auto-enable for specific filetypes
    vim.schedule(function()
      require('hide-comment').enable()
    end)
  end,
})

-- Buffer-local configuration example
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    -- Disable auto-refresh for markdown files
    vim.b.hidecomment_config = {
      refresh_on_change = false,
      conceal_level = 1, -- Less aggressive concealing
    }
  end,
})

-- Integration with other plugins
-- Example: Disable during telescope usage
vim.api.nvim_create_autocmd('User', {
  pattern = 'TelescopePreviewerLoaded',
  callback = function()
    vim.b.hidecomment_disable = true
  end,
})

-- Example: Re-enable after telescope
vim.api.nvim_create_autocmd('User', {
  pattern = 'TelescopePreviewerClosed',
  callback = function()
    vim.b.hidecomment_disable = false
  end,
})
