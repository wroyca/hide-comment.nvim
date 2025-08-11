-- Script to generate documentation for hide-comment
local mini_doc = require ("mini.doc")

-- Configure hooks for our module
local hooks = vim.deepcopy (mini_doc.default_hooks)

-- Remove delimiter lines for local-additions compliance
hooks.write_pre = function (lines)
  table.remove (lines, 1) -- Remove first line
  table.remove (lines, 1) -- Remove second line
  return lines
end

-- Generate documentation
mini_doc.generate ({ "lua/hide-comment.lua" }, "doc/hide-comment.txt", { hooks = hooks })

print ("Documentation generated successfully!")
