-- Public entry point. Spec §14.
local M = {}

local function set_global_keymap(lhs, rhs, desc)
  if lhs == nil or lhs == false or lhs == '' then return end
  vim.keymap.set('n', lhs, rhs, { silent = true, desc = desc })
end

function M.setup(user_opts)
  local cfg = require('redmine.config').setup(user_opts)
  require('redmine.commands').register()

  local km = cfg.keymaps or {}
  set_global_keymap(km.inbox,   '<cmd>Rminbox<CR>', 'redmine: inbox')
  set_global_keymap(km.open,    '<cmd>Rm<CR>',      'redmine: open current issue')
  set_global_keymap(km.comment, '<cmd>Rmcomment<CR>', 'redmine: compose comment')
  set_global_keymap(km.status,  '<cmd>Rmstatus<CR>', 'redmine: change status')
  set_global_keymap(km.timelog, '<cmd>Rmlog<CR>',    'redmine: log time')
  set_global_keymap(km.assign,  '<cmd>Rmassign<CR>', 'redmine: assign')
end

function M.open_inbox()
  require('redmine.ui.inbox').open()
end

function M.open_issue(id)
  require('redmine.ui.issue').open(id)
end

function M.current_issue_id(callback)
  require('redmine.detect').current(callback)
end

return M
