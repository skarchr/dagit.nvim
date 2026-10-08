--- Test helper used by busted. The script runner does not need this file.

vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/dagit.lua")
