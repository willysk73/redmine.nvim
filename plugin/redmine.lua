-- Lazy command registration. Calling :Rm or :Rminbox before setup() still works
-- (auto-uses defaults). Users who call setup() will reset commands with their
-- config; that's fine — vim.api.nvim_create_user_command replaces by name.
if vim.g.loaded_redmine_nvim then return end
vim.g.loaded_redmine_nvim = 1

require('redmine.commands').register()
