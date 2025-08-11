--- *hide-comment* Hide comments
--- *HideComment*
---
--- MIT License Copyright (c) 2025 William Roy
---
--- ==============================================================================
---
--- Features:
--- - Hide comment lines using Neovim's conceal feature with smart navigation.
--- - Automatic detection of comments using treesitter queries.
--- - Smart navigation that skips concealed comment lines and inline comments.
--- - Buffer-local and global configuration support.
--- - Customizable concealing level and refresh behavior.
--- - User commands for easy control.
---
--- Notes:
--- - Requires treesitter parser for the current buffer's filetype.
--- - Uses conceal feature which requires 'conceallevel' > 0.
---
--- # Setup ~
---
--- This module needs a setup with `require('hide-comment').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `HideComment`
--- which you can use for scripting or manually (with `:lua HideComment.*`).
---
--- See |HideComment.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.hidecomment_config` which should have same structure as
--- `HideComment.config`. See |nvim-buffer-local-config| for more details.
---
--- To stop module from showing non-error feedback, set `config.silent = true`.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.hidecomment_disable` (globally) or
--- `vim.b.hidecomment_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |nvim-disabling-recipes| for common recipes.

---@alias __hide_comment_buffer_handle number
---@alias __hide_comment_line_number number
---@alias __hide_comment_column_number number
---@alias __hide_comment_extmark_id number
---@alias __hide_comment_namespace_id number

---@class CommentNode
---@field start_row __hide_comment_line_number 0-based line number
---@field start_col __hide_comment_column_number 0-based column number
---@field end_row __hide_comment_line_number 0-based line number
---@field end_col __hide_comment_column_number 0-based column number
---@field text string The comment text content

---@class ConcealedLine
---@field row __hide_comment_line_number 0-based line number
---@field extmark_id __hide_comment_extmark_id The extmark ID for this concealed line
---@field original_text string The original line content

---@class NavigationDirection
---@field down number
---@field up number

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
local HideComment = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |HideComment.config|.
---
---@usage >lua
---   require('hide-comment').setup() -- use default config
---   -- OR
---   require('hide-comment').setup({}) -- replace {} with your config table
--- <
HideComment.setup = function(config)
  -- Export module
  _G.HideComment = HideComment

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()
  H.create_user_commands()

  -- Create default highlighting
  H.create_default_hl()
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Options ~
---
--- ## Auto enable ~
---
--- `auto_enable` controls whether comment hiding is automatically enabled for
--- all supported filetypes (those with treesitter parsers). When `false`,
--- you need to manually call |HideComment.enable()| or use commands.
---
--- ## Smart navigation ~
---
--- `smart_navigation` enables special j/k/h/l movement that skips over concealed
--- comment lines and inline comments. This prevents getting "stuck" on hidden 
--- lines when navigating vertically or on concealed inline comments when 
--- navigating horizontally.
---
--- ## Conceal level ~
---
--- `conceal_level` sets the value of 'conceallevel' when comment hiding is active.
--- Must be between 0-3. Higher values provide more aggressive concealing.
---
--- ## Refresh behavior ~
---
--- `refresh_on_change` automatically refreshes hidden comments when buffer
--- content changes. This ensures new comments are hidden and deleted comments
--- are no longer concealed.
---
--- ## Debug mode ~
---
--- `debug` enables debug logging to help troubleshoot issues.
HideComment.config = {
  -- Whether to automatically enable for all supported languages
  auto_enable = false,

  -- Whether to enable smart navigation that skips concealed lines and inline comments
  smart_navigation = true,

  -- The conceallevel to set when concealing (0-3)
  conceal_level = 3,

  -- Refresh concealing when buffer content changes
  refresh_on_change = true,

  -- Whether to enable debug logging
  debug = false,

  -- Don't show non-error feedback
  silent = false,
}
--minidoc_afterlines_end

-- Module data ================================================================
---@type NavigationDirection The navigation directions
H.direction = {
  down = 1,
  up = -1,
}

---@type string The universal treesitter query for comments
H.comment_query = "(comment) @comment"

---@type table<__hide_comment_buffer_handle, ConcealedLine[]> Track concealed lines per buffer
H.concealed_buffers = {}

---@type __hide_comment_namespace_id The namespace for concealing extmarks
H.namespace_id = vim.api.nvim_create_namespace("hide-comment")

---@type number Augroup ID for autocommands
H.augroup_id = vim.api.nvim_create_augroup("HideComment", { clear = true })

-- Helper functions ===========================================================
---@param message string
---@param level? number vim.log.levels
H.debug_log = function(message, level)
  local config = H.get_config()
  if not config.debug then return end
  level = level or vim.log.levels.DEBUG
  H.notify("[HideComment] " .. message, level)
end

---@param msg string
---@param level? number
H.notify = function(msg, level)
  local config = H.get_config()
  if config.silent then return end
  level = level or vim.log.levels.INFO
  vim.notify(msg, level)
end

---@param bufnr __hide_comment_buffer_handle
---@return boolean is_valid
---@return string? error_message
H.validate_buffer = function(bufnr)
  if not bufnr or type(bufnr) ~= "number" then
    return false, "Invalid buffer handle"
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "Buffer is not valid"
  end

  return true, nil
end

---@param bufnr __hide_comment_buffer_handle
---@return any? parser
---@return string? error_message
H.get_treesitter_parser = function(bufnr)
  local is_valid, error_msg = H.validate_buffer(bufnr)
  if not is_valid then return nil, error_msg end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil, "Failed to get treesitter parser"
  end

  return parser, nil
end

---@param bufnr __hide_comment_buffer_handle
---@return CommentNode[] nodes
---@return string? error_message
H.get_comment_nodes = function(bufnr)
  H.debug_log("Getting comment nodes for buffer " .. bufnr)

  local parser, parser_error = H.get_treesitter_parser(bufnr)
  if not parser then return {}, parser_error end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return {}, "No syntax trees available"
  end

  local root = trees[1]:root()
  if not root then return {}, "No root node available" end

  -- Try to parse the universal comment query
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  local ok, query = pcall(vim.treesitter.query.parse, filetype, H.comment_query)
  if not ok or not query then
    return {}, "Failed to parse comment query for filetype: " .. filetype
  end

  local nodes = {}
  for _, node in query:iter_captures(root, bufnr) do
    if node and node.range then
      local start_row, start_col, end_row, end_col = node:range()
      local text_lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
      local text = table.concat(text_lines, "\n")

      table.insert(nodes, {
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col,
        text = text,
      })
    end
  end

  H.debug_log("Found " .. #nodes .. " comment nodes")
  return nodes, nil
end

---@param bufnr __hide_comment_buffer_handle
---@param node CommentNode
---@param row __hide_comment_line_number
---@return boolean is_full_line_comment
H.is_full_line_comment = function(bufnr, node, row)
  local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

  -- Get the portion before the comment
  local start_col = (row == node.start_row) and node.start_col or 0
  local before_comment = line_text:sub(1, start_col)

  -- Get the portion after the comment
  local end_col = (row == node.end_row) and node.end_col or #line_text
  local after_comment = line_text:sub(end_col + 1)

  -- Check if both before and after contain only whitespace
  local before_only_whitespace = before_comment:match("^%s*$") ~= nil
  local after_only_whitespace = after_comment:match("^%s*$") ~= nil

  return before_only_whitespace and after_only_whitespace
end

---@param bufnr __hide_comment_buffer_handle
---@param nodes CommentNode[]
---@return ConcealedLine[]
H.create_concealing_extmarks = function(bufnr, nodes)
  local concealed_lines = {}

  for _, node in ipairs(nodes) do
    -- Handle single-line comments
    if node.start_row == node.end_row then
      local row = node.start_row
      local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
      local is_full_line_comment = H.is_full_line_comment(bufnr, node, row)

      if is_full_line_comment then
        -- Full line comment - conceal the entire line
        local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, H.namespace_id, row, 0, {
          end_row = row,
          end_col = #line_text,
          conceal_lines = "",
          priority = 1000,
        })

        if ok then
          table.insert(concealed_lines, {
            row = row,
            extmark_id = extmark_id,
            original_text = line_text,
          })
        else
          H.debug_log("Failed to create extmark for row " .. row, vim.log.levels.WARN)
        end
      else
        -- Inline comment - conceal only the comment part
        local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, H.namespace_id, row, node.start_col, {
          end_row = row,
          end_col = node.end_col,
          conceal = "",
          priority = 1000,
        })

        if ok then
          H.debug_log("Created inline comment extmark for row " .. row ..
                     " cols " .. node.start_col .. "-" .. node.end_col)
          -- Note: We don't add inline comments to concealed_lines since the line remains visible
        else
          H.debug_log("Failed to create inline comment extmark for row " .. row, vim.log.levels.WARN)
        end
      end
    else
      -- Multi-line comment - handle each line separately
      for row = node.start_row, node.end_row do
        local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

        -- Determine column range for this line
        local start_col, end_col
        if row == node.start_row then
          start_col = node.start_col
          end_col = #line_text
        elseif row == node.end_row then
          start_col = 0
          end_col = node.end_col
        else
          start_col = 0
          end_col = #line_text
        end

        -- Check if this line is entirely within the comment
        local spans_entire_line = start_col == 0 and end_col == #line_text
        local is_full_line_comment = spans_entire_line and line_text:match("^%s*$") == nil
        local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, H.namespace_id, row, start_col, {
          end_row = row,
          end_col = end_col,
          conceal_lines = "",
          priority = 1000,
        })

        if ok then
          -- Only add to concealed_lines if the entire line is concealed
          if is_full_line_comment then
            table.insert(concealed_lines, {
              row = row,
              extmark_id = extmark_id,
              original_text = line_text,
            })
          else
            H.debug_log("Created partial line comment extmark for row " .. row ..
                       " cols " .. start_col .. "-" .. end_col)
          end
        else
          H.debug_log("Failed to create extmark for row " .. row, vim.log.levels.WARN)
        end
      end
    end
  end

  return concealed_lines
end

---@param bufnr __hide_comment_buffer_handle
---@return boolean success
---@return string? error_message
H.apply_concealing = function(bufnr)
  H.debug_log("Applying concealing to buffer " .. bufnr)

  local is_valid, error_msg = H.validate_buffer(bufnr)
  if not is_valid then return false, error_msg end

  -- Clear existing concealing
  vim.api.nvim_buf_clear_namespace(bufnr, H.namespace_id, 0, -1)
  H.concealed_buffers[bufnr] = nil

  local nodes, nodes_error = H.get_comment_nodes(bufnr)
  if nodes_error then return false, nodes_error end

  if #nodes == 0 then
    H.debug_log("No comment nodes found")
    return true, nil
  end

  -- Set conceallevel and concealcursor
  local config = H.get_config()
  local current_win = vim.api.nvim_get_current_win()
  local buf_win = vim.fn.bufwinid(bufnr)

  if buf_win ~= -1 then
    vim.api.nvim_set_option_value("conceallevel", config.conceal_level, { win = buf_win })
    vim.api.nvim_set_option_value("concealcursor", "nvic", { win = buf_win })
  else
    vim.api.nvim_set_option_value("conceallevel", config.conceal_level, { win = current_win })
    vim.api.nvim_set_option_value("concealcursor", "nvic", { win = current_win })
  end

  local concealed_lines = H.create_concealing_extmarks(bufnr, nodes)
  H.concealed_buffers[bufnr] = concealed_lines

  H.debug_log("Successfully concealed " .. #concealed_lines .. " lines")
  return true, nil
end

---@param bufnr __hide_comment_buffer_handle
---@return boolean success
---@return string? error_message
H.remove_concealing = function(bufnr)
  H.debug_log("Removing concealing from buffer " .. bufnr)

  local is_valid, error_msg = H.validate_buffer(bufnr)
  if not is_valid then return false, error_msg end

  vim.api.nvim_buf_clear_namespace(bufnr, H.namespace_id, 0, -1)
  H.concealed_buffers[bufnr] = nil

  -- Reset conceallevel and concealcursor
  local current_win = vim.api.nvim_get_current_win()
  local buf_win = vim.fn.bufwinid(bufnr)

  if buf_win ~= -1 then
    vim.api.nvim_set_option_value("conceallevel", 0, { win = buf_win })
    vim.api.nvim_set_option_value("concealcursor", "", { win = buf_win })
  else
    vim.api.nvim_set_option_value("conceallevel", 0, { win = current_win })
    vim.api.nvim_set_option_value("concealcursor", "", { win = current_win })
  end

  H.debug_log("Successfully removed concealing")
  return true, nil
end

---@param bufnr __hide_comment_buffer_handle
---@param line_nr __hide_comment_line_number 1-based line number
---@return boolean is_concealed
H.is_line_concealed = function(bufnr, line_nr)
  local concealed_lines = H.concealed_buffers[bufnr]
  if not concealed_lines then return false end

  for _, concealed_line in ipairs(concealed_lines) do
    if concealed_line.row + 1 == line_nr then -- Convert 0-based to 1-based
      return true
    end
  end

  return false
end

---@param bufnr __hide_comment_buffer_handle
---@param current_line __hide_comment_line_number 1-based line number
---@param direction number H.direction.down or H.direction.up
---@return __hide_comment_line_number next_line
H.find_next_visible_line = function(bufnr, current_line, direction)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local next_line = current_line + direction

  while next_line >= 1 and next_line <= total_lines do
    if not H.is_line_concealed(bufnr, next_line) then
      return next_line
    end
    next_line = next_line + direction
  end

  -- Return boundary if no visible line found
  return direction > 0 and total_lines or 1
end

---@param bufnr __hide_comment_buffer_handle
---@param line_nr __hide_comment_line_number 1-based line number
---@param col_nr __hide_comment_column_number 0-based column number
---@return boolean is_in_concealed_region
H.is_position_concealed = function(bufnr, line_nr, col_nr)
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, H.namespace_id,
    { line_nr - 1, 0 }, { line_nr - 1, -1 }, { details = true })

  for _, extmark in ipairs(extmarks) do
    local start_row, start_col = extmark[2], extmark[3]
    local details = extmark[4]

    -- Check if this position is within a concealed region
    if details and details.end_row and details.end_col then
      local end_row, end_col = details.end_row, details.end_col

      -- Convert to 0-based for comparison
      if start_row == line_nr - 1 and end_row == line_nr - 1 then
        if col_nr >= start_col and col_nr < end_col then
          return true
        end
      end
    end
  end

  return false
end

---@param bufnr __hide_comment_buffer_handle
---@param line_nr __hide_comment_line_number 1-based line number
---@param col_nr __hide_comment_column_number 0-based column number
---@param direction number 1 for right, -1 for left
---@return __hide_comment_column_number next_col
H.find_next_visible_column = function(bufnr, line_nr, col_nr, direction)
  local line_text = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1] or ""
  local max_col = #line_text
  local next_col = col_nr + direction

  -- Boundary checks
  if direction > 0 and next_col > max_col then
    return max_col
  elseif direction < 0 and next_col < 0 then
    return 0
  end

  -- Find next non-concealed position
  while next_col >= 0 and next_col <= max_col do
    if not H.is_position_concealed(bufnr, line_nr, next_col) then
      return next_col
    end
    next_col = next_col + direction
  end

  -- Return boundary if no visible column found
  return direction > 0 and max_col or 0
end

---@param direction number 1 for right, -1 for left
---@param count number Number of moves to make
H.smart_navigate_horizontal = function(direction, count)
  local bufnr = vim.api.nvim_get_current_buf()

  -- Use normal navigation if concealing is not active
  if not H.concealed_buffers[bufnr] then
    local key = direction > 0 and "l" or "h"
    local cmd = count > 1 and (count .. key) or key
    vim.cmd("normal! " .. cmd)
    return
  end

  local current_pos = vim.api.nvim_win_get_cursor(0)
  local current_line, current_col = current_pos[1], current_pos[2]
  local target_col = current_col

  for _ = 1, count do
    local next_col = H.find_next_visible_column(bufnr, current_line, target_col, direction)
    if next_col == target_col then break end
    target_col = next_col
  end

  if target_col ~= current_col then
    vim.api.nvim_win_set_cursor(0, { current_line, target_col })
  end
end

---@param direction number H.direction.down or H.direction.up
---@param count number Number of moves to make
H.smart_navigate = function(direction, count)
  local bufnr = vim.api.nvim_get_current_buf()

  -- Use normal navigation if concealing is not active
  if not H.concealed_buffers[bufnr] then
    local key = direction > 0 and "j" or "k"
    local cmd = count > 1 and (count .. key) or key
    vim.cmd("normal! " .. cmd)
    return
  end

  local current_line = vim.fn.line(".")
  local target_line = current_line

  for _ = 1, count do
    local next_line = H.find_next_visible_line(bufnr, target_line, direction)
    if next_line == target_line then break end
    target_line = next_line
  end

  if target_line ~= current_line then
    vim.api.nvim_win_set_cursor(0, { target_line, vim.fn.col(".") - 1 })
  end
end

H.setup_navigation_keymaps = function()
  local config = H.get_config()
  if not config.smart_navigation then return end

  local keymap_opts = { desc = "Smart comment navigation" }

  local function move_down() H.smart_navigate(H.direction.down, vim.v.count1) end
  local function move_up() H.smart_navigate(H.direction.up, vim.v.count1) end
  local function move_right() H.smart_navigate_horizontal(1, vim.v.count1) end
  local function move_left() H.smart_navigate_horizontal(-1, vim.v.count1) end

  -- Normal mode mappings
  vim.keymap.set("n", "j", move_down, keymap_opts)
  vim.keymap.set("n", "k", move_up, keymap_opts)
  vim.keymap.set("n", "<Down>", move_down, keymap_opts)
  vim.keymap.set("n", "<Up>", move_up, keymap_opts)
  vim.keymap.set("n", "l", move_right, keymap_opts)
  vim.keymap.set("n", "h", move_left, keymap_opts)
  vim.keymap.set("n", "<Right>", move_right, keymap_opts)
  vim.keymap.set("n", "<Left>", move_left, keymap_opts)

  -- Visual mode mappings
  vim.keymap.set("v", "j", move_down, keymap_opts)
  vim.keymap.set("v", "k", move_up, keymap_opts)
  vim.keymap.set("v", "<Down>", move_down, keymap_opts)
  vim.keymap.set("v", "<Up>", move_up, keymap_opts)
  vim.keymap.set("v", "l", move_right, keymap_opts)
  vim.keymap.set("v", "h", move_left, keymap_opts)
  vim.keymap.set("v", "<Right>", move_right, keymap_opts)
  vim.keymap.set("v", "<Left>", move_left, keymap_opts)
end

H.create_autocommands = function()
  local config = H.get_config()

  if config.auto_enable then
    vim.api.nvim_create_autocmd("FileType", {
      group = H.augroup_id,
      pattern = "*",
      callback = function(args)
        if H.is_disabled() then return end
        vim.schedule(function()
          if vim.treesitter.get_parser(args.buf, nil, { error = false }) then
            HideComment.enable(args.buf)
          end
        end)
      end,
      desc = "Auto-enable comment hiding for all supported languages",
    })
  end

  if config.refresh_on_change then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = H.augroup_id,
      callback = function(args)
        if H.is_disabled() then return end
        if H.concealed_buffers[args.buf] then
          vim.schedule(function()
            HideComment.enable(args.buf)
          end)
        end
      end,
      desc = "Refresh comment hiding on text changes",
    })
  end

  -- Cleanup on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    group = H.augroup_id,
    callback = function(args)
      H.concealed_buffers[args.buf] = nil
    end,
    desc = "Cleanup hiding data on buffer delete",
  })
end

H.create_user_commands = function()
  vim.api.nvim_create_user_command("HideCommentEnable", function()
    local success, error_msg = HideComment.enable()
    if not success then
      vim.notify("Failed to hide comments: " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
    end
  end, { desc = "Hide comments in current buffer" })

  vim.api.nvim_create_user_command("HideCommentDisable", function()
    local success, error_msg = HideComment.disable()
    if not success then
      vim.notify("Failed to show comments: " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
    end
  end, { desc = "Show comments in current buffer" })

  vim.api.nvim_create_user_command("HideCommentToggle", function()
    local success, error_msg = HideComment.toggle()
    if not success then
      vim.notify("Failed to toggle comment hiding: " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
    end
  end, { desc = "Toggle comment hiding in current buffer" })

  vim.api.nvim_create_user_command("HideCommentStatus", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local stats = HideComment.get_stats(bufnr)
    local status = stats.is_enabled and "enabled" or "disabled"
    H.notify(string.format("Comment hiding is %s (%d lines hidden)", status, stats.concealed_lines))
  end, { desc = "Show comment hiding status" })
end

H.create_default_hl = function()
  -- Define highlight groups for any future visual features
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi("HideCommentConceal", { link = "Conceal" })
end

-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, "table", true } })
  config = vim.tbl_deep_extend("force", vim.deepcopy(H.default_config), config or {})

  vim.validate({
    auto_enable = { config.auto_enable, "boolean" },
    smart_navigation = { config.smart_navigation, "boolean" },
    conceal_level = { config.conceal_level, "number" },
    refresh_on_change = { config.refresh_on_change, "boolean" },
    debug = { config.debug, "boolean" },
    silent = { config.silent, "boolean" },
  })

  -- Validate conceal_level range
  if config.conceal_level < 0 or config.conceal_level > 3 then
    error("(hide-comment) `conceal_level` should be between 0 and 3")
  end

  return config
end

H.apply_config = function(config)
  HideComment.config = config

  -- Set up navigation keymaps
  H.setup_navigation_keymaps()
end

H.is_disabled = function()
  return vim.g.hidecomment_disable == true or vim.b.hidecomment_disable == true
end

H.get_config = function(config)
  return vim.tbl_deep_extend("force", HideComment.config, vim.b.hidecomment_config or {}, config or {})
end

H.default_config = vim.deepcopy(HideComment.config)

-- Module functionality ======================================================

--- Enable comment hiding for a buffer
---
---@param bufnr? __hide_comment_buffer_handle Buffer handle (defaults to current buffer)
---@return boolean success
---@return string? error_message
---
---@usage >lua
---   -- Hide comments in current buffer
---   HideComment.enable()
---
---   -- Hide comments in specific buffer
---   HideComment.enable(5)
--- <
HideComment.enable = function(bufnr)
  if H.is_disabled() then return false, "Module is disabled" end

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local success, error_msg = H.apply_concealing(bufnr)
  return success, error_msg
end

--- Disable comment hiding for a buffer
---
---@param bufnr? __hide_comment_buffer_handle Buffer handle (defaults to current buffer)
---@return boolean success
---@return string? error_message
---
---@usage >lua
---   -- Show comments in current buffer
---   HideComment.disable()
---
---   -- Show comments in specific buffer
---   HideComment.disable(5)
--- <
HideComment.disable = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local success, error_msg = H.remove_concealing(bufnr)
  return success, error_msg
end

--- Toggle comment hiding for a buffer
---
---@param bufnr? __hide_comment_buffer_handle Buffer handle (defaults to current buffer)
---@return boolean success
---@return string? error_message
---
---@usage >lua
---   -- Toggle comment hiding in current buffer
---   HideComment.toggle()
---
---   -- Toggle comment hiding in specific buffer
---   HideComment.toggle(5)
--- <
HideComment.toggle = function(bufnr)
  if H.is_disabled() then return false, "Module is disabled" end

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if HideComment.is_enabled(bufnr) then
    return HideComment.disable(bufnr)
  else
    return HideComment.enable(bufnr)
  end
end

--- Check if comment hiding is enabled for a buffer
---
---@param bufnr? __hide_comment_buffer_handle Buffer handle (defaults to current buffer)
---@return boolean is_enabled
---
---@usage >lua
---   if HideComment.is_enabled() then
---     print("Comments are hidden")
---   end
--- <
HideComment.is_enabled = function(bufnr)
  -- Hello, world!
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return H.concealed_buffers[bufnr] ~= nil
end

--- Get hiding statistics for a buffer
---
---@param bufnr? __hide_comment_buffer_handle Buffer handle (defaults to current buffer)
---@return table stats Statistics object with concealed line count and other info
---
---@usage >lua
---   local stats = HideComment.get_stats()
---   print(string.format("Hidden %d/%d lines (%.1f%%)",
---     stats.concealed_lines, stats.total_lines, stats.concealed_percentage))
--- <
HideComment.get_stats = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf() -- test

  local concealed_lines = H.concealed_buffers[bufnr] or {}
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  return {
    buffer = bufnr,
    total_lines = total_lines,
    concealed_lines = #concealed_lines,
    concealed_percentage = total_lines > 0 and (#concealed_lines / total_lines * 100) or 0,
    is_enabled = HideComment.is_enabled(bufnr),
    is_supported = vim.treesitter.get_parser(bufnr, nil, { error = false }) ~= nil,
  }
end

return HideComment
