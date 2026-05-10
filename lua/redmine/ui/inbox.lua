-- Inbox buffer. Spec §7.1.
local cli = require('redmine.cli')
local config = require('redmine.config')
local util = require('redmine.util')

local M = {}

local BUF_NAME = 'redmine://inbox'

local state = {
  bufnr = nil,
  filter = nil,
  -- 1-based: line_to_id[lnum] = issue id (nil for header/footer lines)
  line_to_id = {},
}

local FILTER_CYCLE = { open = 'all', all = 'mine', mine = 'open' }

local function format_lines(items, filter)
  local lines = {}
  state.line_to_id = {}

  table.insert(lines, ('Redmine — 내 일감 (%d)        [필터: %s]'):format(#items, filter))
  table.insert(lines, '')

  for _, it in ipairs(items) do
    local line = ('  #%-6d %-8s %-12s %3d%%   %s'):format(
      it.id or 0,
      it.tracker or '-',
      it.status or '-',
      it.progress or 0,
      it.subject or ''
    )
    table.insert(lines, line)
    state.line_to_id[#lines] = it.id
  end

  table.insert(lines, '')
  table.insert(lines, 'q close   r refresh   f filter   /  search   <CR> open')
  return lines
end

local function render(bufnr)
  local filter = state.filter or config.get().inbox.default_filter or 'open'
  state.filter = filter
  util.set_lines(bufnr, { '⏳ Fetching...' })

  cli.run_json({ 'list', '--filter', filter }, function(items)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    items = items or {}
    util.set_lines(bufnr, format_lines(items, filter))
    -- After data is rendered, place cursor on the first issue line if any.
    for lnum, id in pairs(state.line_to_id) do
      if id then
        local win = vim.fn.bufwinid(bufnr)
        if win ~= -1 then
          pcall(vim.api.nvim_win_set_cursor, win, { lnum, 2 })
        end
        break
      end
    end
  end)
end

local function id_under_cursor()
  local win = vim.fn.bufwinid(state.bufnr or -1)
  if win == -1 then return nil end
  local cursor = vim.api.nvim_win_get_cursor(win)
  return state.line_to_id[cursor[1]]
end

local function bind_keys(bufnr)
  local km = config.get().keymaps.inbox_buffer or {}

  util.bmap(bufnr, km.close, function()
    pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
  end, 'redmine: close inbox')

  util.bmap(bufnr, km.refresh, function()
    render(bufnr)
  end, 'redmine: refresh inbox')

  util.bmap(bufnr, km.open, function()
    local id = id_under_cursor()
    if not id then
      vim.notify('이 줄에는 issue 가 없습니다', vim.log.levels.INFO)
      return
    end
    require('redmine.ui.issue').open(id)
  end, 'redmine: open issue under cursor')

  util.bmap(bufnr, km.filter, function()
    state.filter = FILTER_CYCLE[state.filter] or 'open'
    render(bufnr)
  end, 'redmine: cycle filter')

  -- `/` is left as-is (built-in search) per spec.
end

function M.open()
  local strategy = config.get().ui.inbox_strategy or 'edit'
  local _, bufnr, created = util.open_buffer(BUF_NAME, strategy)
  state.bufnr = bufnr

  if created then
    util.lock_buffer(bufnr, 'redmine-inbox')
    bind_keys(bufnr)
  end
  render(bufnr)
end

return M
