-- Default config and merge logic. Spec §5.
local M = {}

---@class RedmineConfig
local defaults = {
  cli = 'redmine',

  keymaps = {
    inbox    = '<leader>ri',
    open     = '<leader>ro',
    comment  = '<leader>rc',
    status   = '<leader>rs',
    timelog  = '<leader>rt',
    assign   = '<leader>ra',

    inbox_buffer = {
      open         = '<CR>',
      refresh      = 'r',
      hard_refresh = 'R',
      filter       = 'f',
      search       = '/',
      close        = 'q',
    },
    issue_buffer = {
      comment         = 'cc',
      timelog         = 'tt',
      status          = 'ss',
      progress        = 'pp',
      assign          = 'aa',
      open_attachment = 'oo',
      refresh         = 'r',
      hard_refresh    = 'R',
      close           = 'q',
    },
    compose_buffer = {
      post            = '<leader>p',
      post_no_confirm = '<leader>P',
      discard         = '<leader>x',
    },
  },

  compose = {
    cutoff_pattern    = '^<!%-%-.*━━━.*%-%->%s*$',
    confirm_post      = true,
    after_post        = 'archive',
    -- Append a Reference section (statuses / progress / assignee candidates)
    -- below the cutoff line in `:Rmcomment` scaffolds. Read-only context for
    -- the user; ignored by the CLI post path because it sits below the
    -- cutoff. See lua/redmine/ui/compose.lua scaffold().
    reference_section = true,
  },

  inbox = {
    default_filter = 'open',
    columns        = { 'id', 'tracker', 'status', 'progress', 'subject' },
  },

  ui = {
    open_strategy    = 'split',
    compose_strategy = 'vsplit',
    inbox_strategy   = 'edit',
  },

  notify = {
    level = 'minimal',
  },

  cache = {
    enabled      = true,
    inbox_ttl_ms = 30 * 1000,
    issue_ttl_ms = 60 * 1000,
  },
}

local current

function M.setup(user)
  current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), user or {})
  return current
end

function M.get()
  return current or vim.deepcopy(defaults)
end

function M.defaults()
  return vim.deepcopy(defaults)
end

return M
