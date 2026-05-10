-- Issue detail buffer. Spec §7.2.
local cli = require('redmine.cli')
local config = require('redmine.config')
local util = require('redmine.util')

local M = {}

local function buf_name(id)
  return ('redmine://issue/%d'):format(id)
end

local function bind_keys(bufnr, id)
  local km = config.get().keymaps.issue_buffer or {}

  util.bmap(bufnr, km.close, function()
    pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
  end, 'redmine: close issue')

  util.bmap(bufnr, km.refresh, function()
    M.refresh(id)
  end, 'redmine: refresh issue')

  util.bmap(bufnr, km.hard_refresh, function()
    M.refresh(id, { hard = true })
  end, 'redmine: hard refresh issue')

  util.bmap(bufnr, km.comment, function()
    require('redmine.ui.compose').open(id)
  end, 'redmine: compose comment')

  util.bmap(bufnr, km.status, function()
    require('redmine.actions').change_status(id)
  end, 'redmine: change status')

  util.bmap(bufnr, km.progress, function()
    require('redmine.actions').change_progress(id)
  end, 'redmine: change progress')

  util.bmap(bufnr, km.timelog, function()
    require('redmine.actions').log_time(id)
  end, 'redmine: log time')

  util.bmap(bufnr, km.assign, function()
    require('redmine.actions').assign(id)
  end, 'redmine: assign')

  util.bmap(bufnr, km.open_attachment, function()
    local line = vim.api.nvim_get_current_line()
    local att_id = line:match('%[#(%d+)%]')
    if not att_id then
      vim.notify('redmine: 커서 라인에 첨부가 없습니다 (▸ 첨부 섹션의 줄에서 실행)',
        vim.log.levels.WARN, { title = 'redmine' })
      return
    end
    cli.run({ 'attachment', 'download', '--id', att_id, '--issue', tostring(id) }, {}, function(stdout)
      local path = vim.trim(stdout or '')
      if path == '' then return end
      local opener = (vim.fn.has('mac') == 1 and 'open')
                  or (vim.fn.has('win32') == 1 and 'cmd.exe')
                  or 'xdg-open'
      local argv = (opener == 'cmd.exe') and { 'cmd.exe', '/C', 'start', '', path } or { opener, path }
      vim.system(argv, { detach = true })
      vim.notify('redmine: 열기 → ' .. path, vim.log.levels.INFO, { title = 'redmine' })
    end)
  end, 'redmine: open attachment')
end

local function render(bufnr, id, opts)
  opts = opts or {}
  util.set_lines(bufnr, { ('⏳ Fetching #%d ...'):format(id) })

  -- The CLI has no cache layer yet (M3+); `R` and `r` are equivalent today.
  local args = { 'fetch', tostring(id), '--format=display' }

  cli.run(args, {}, function(stdout)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local lines = vim.split(stdout, '\n', { plain = true })
    -- Trim a single trailing blank line if present (CLI emits a final \n).
    if #lines > 0 and lines[#lines] == '' then
      table.remove(lines)
    end
    util.set_lines(bufnr, lines)
  end)
end

function M.open(id)
  local strategy = config.get().ui.open_strategy or 'split'
  local _, bufnr, created = util.open_buffer(buf_name(id), strategy)

  if created then
    util.lock_buffer(bufnr, 'redmine-issue')
    bind_keys(bufnr, id)
  end
  render(bufnr, id)
end

function M.refresh(id, opts)
  local name = buf_name(id)
  local bufnr = vim.fn.bufnr(name)
  if bufnr == -1 then return end
  render(bufnr, id, opts)
end

return M
