# hide-comment.lua

Hide comment lines using Neovim's built-in conceal feature, with smart navigation that skips concealed lines.

![Alt text](hide-comment.gif)

## Features

- **Comment Detection**: Automatically detects comment lines using treesitter queries
- **Smart Navigation**: j/k navigation skips over concealed comment lines
- **Auto Enable**: Optionally auto-enable for all supported filetypes
- **Buffer Local**: Support for buffer-local configuration
- **Refresh on Change**: Automatically refresh when buffer content changes
- **User Commands**: Easy-to-use commands for controlling comment hiding

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'wroyca/hide-comment',
  config = function()
    require('hide-comment').setup({
      -- Your configuration here
    })
  end
}
```

### With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'wroyca/hide-comment',
  config = function()
    require('hide-comment').setup()
  end
}
```

## Setup

```lua
require('hide-comment').setup({
  -- Whether to automatically enable for all supported languages
  auto_enable = false,

  -- Whether to enable smart navigation that skips concealed lines
  smart_navigation = true,

  -- The conceallevel to set when concealing (0-3)
  conceal_level = 3,

  -- Refresh concealing when buffer content changes
  refresh_on_change = true,

  -- Enable debug logging
  debug = false,

  -- Don't show non-error feedback
  silent = false,
})
```

## Usage

### Manual Control

```lua
-- Hide comments in current buffer
HideComment.enable()

-- Show comments in current buffer
HideComment.disable()

-- Toggle comments in current buffer
HideComment.toggle()

-- Check if enabled
if HideComment.is_enabled() then
  print("Comments are hidden")
end

-- Get statistics
local stats = HideComment.get_stats()
print(string.format("Hidden %d/%d lines (%.1f%%)",
      stats.concealed_lines,
      stats.total_lines,
      stats.concealed_percentage))
```

### User Commands

- `:HideCommentEnable` - Hide comments in current buffer
- `:HideCommentDisable` - Show comments in current buffer
- `:HideCommentToggle` - Toggle comments in current buffer
- `:HideCommentStatus` - Show current status

### Buffer-local Configuration

You can override settings per buffer:

```lua
-- Disable auto-refresh for this buffer only
vim.b.hidecomment_config = { refresh_on_change = false }
```

### Disabling

Disable globally:
```lua
vim.g.hidecomment_disable = true
```

Disable for current buffer:
```lua
vim.b.hidecomment_disable = true
```

## Requirements

- Neovim >= 11
- Treesitter parser for the target language
- The language must have comment syntax supported by treesitter

## Supported Languages

Any language with treesitter support that includes comment detection should work, including:

- Lua
- JavaScript/TypeScript
- Python
- Rust
- Go
- C/C++
- And many more...

## Development

### Running Tests

```bash
nvim --headless -u scripts/minimal_init.lua -l scripts/run_tests.lua
```

### Generating Documentation

```bash
nvim --headless -u scripts/minimal_init.lua -l scripts/gen_doc.lua
```

## Inspiration

This plugin replicates the functionality of [hide-comnt.el](https://github.com/emacsmirror/hide-comnt) from Emacs, bringing it to Neovim with modern treesitter integration.

## License

MIT License
