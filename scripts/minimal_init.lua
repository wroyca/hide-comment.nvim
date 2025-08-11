-- Minimal init.lua for testing
vim.cmd ("set rtp+=.")

-- Set up mini.test for running tests
vim.g.mapleader = " "

-- Basic settings for testing
vim.o.swapfile = false
vim.o.backup = false

-- Download and set up dependencies if not present
local function setup_plugin (url, name, branch)
  local install_path = vim.fn.stdpath ("data") .. "/site/pack/test/start/" .. name
  if vim.fn.isdirectory (install_path) == 0 then
    print ("Installing " .. name .. " for tests...")
    local cmd = { "git", "clone" }
    if branch then
      table.insert (cmd, "--branch")
      table.insert (cmd, branch)
    end
    table.insert (cmd, "--depth=1")
    table.insert (cmd, url)
    table.insert (cmd, install_path)
    vim.fn.system (cmd)
  end
  vim.cmd ("packadd " .. name)
end
setup_plugin ("https://github.com/echasnovski/mini.nvim.git", "mini.nvim")
setup_plugin ("https://github.com/nvim-treesitter/nvim-treesitter.git", "nvim-treesitter", "main")

-- Refresh package path
vim.cmd ("packloadall")

-- Set up nvim-treesitter
local parsers = { "lua" }
for _, parser in ipairs (parsers) do
  require ("nvim-treesitter").install (parser)
end

-- Load mini.test
local ok_test, mini_test = pcall (require, "mini.test")
if ok_test then
  mini_test.setup ()
else
  print ("Warning: mini.test could not be loaded")
end

-- Load mini.doc
local ok_doc, mini_doc = pcall (require, "mini.doc")
if ok_doc then
  mini_doc.setup ()
else
  print ("Warning: mini.doc could not be loaded")
end
