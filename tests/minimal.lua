-- Minimal init for headless tests. Adds the plugin's lua dir and runs setup().
local root = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, 'S').source:sub(2)), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.opt.swapfile = false
vim.opt.more = false
vim.opt.shortmess:append('I')

-- E2E disables the post-confirm dialog so headless tests can drive Rmpost.
require('redmine').setup({
  compose = { confirm_post = false, after_post = 'archive' },
})
