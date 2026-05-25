-- Register :Rm* commands. Spec §6.
local M = {}

local function open_inbox(args)
  local inbox = require('redmine.ui.inbox')
  local arg = args and args.args or ''
  if arg ~= '' then
    if not inbox.is_valid_filter(arg) then
      vim.notify(
        ('redmine: Rminbox 필터는 %s 중 하나여야 합니다 (받은 값: %s)')
          :format(table.concat(inbox.FILTERS, '|'), arg),
        vim.log.levels.ERROR)
      return
    end
    inbox.open(arg)
    return
  end
  inbox.open()
end

local function complete_inbox(arg_lead)
  local inbox = require('redmine.ui.inbox')
  local matches = {}
  for _, v in ipairs(inbox.FILTERS) do
    if v:sub(1, #arg_lead) == arg_lead then table.insert(matches, v) end
  end
  return matches
end

local function open_issue(id)
  require('redmine.ui.issue').open(id)
end

local function with_id(args, kind, callback)
  -- Resolve issue id from explicit arg or `redmine detect`.
  if args.args and args.args ~= '' then
    local id = tonumber(args.args:match('^%s*(%d+)'))
    if not id then
      vim.notify(('redmine: %s 첫 인자는 issue id 여야 합니다 (받은 값: %s)'):format(kind, args.args),
        vim.log.levels.ERROR)
      return
    end
    callback(id, vim.trim(args.args:gsub('^%d+%s*', '')))
    return
  end
  require('redmine.detect').current(function(id)
    if not id then
      vim.notify('redmine: issue id 를 감지할 수 없습니다 — 인자로 지정하세요', vim.log.levels.ERROR)
      return
    end
    callback(id, '')
  end)
end

local function rm_command(args)
  if args.args and args.args ~= '' then
    local id = tonumber(args.args)
    if not id then
      vim.notify('redmine: issue id 가 숫자여야 합니다 (받은 값: ' .. args.args .. ')',
        vim.log.levels.ERROR)
      return
    end
    open_issue(id)
    return
  end
  require('redmine.detect').current(function(id)
    if id then
      open_issue(id)
    else
      require('redmine.ui.pending').open()
    end
  end)
end

local function complete_post(arg_lead)
  local out = {}
  local function maybe(s)
    if s:sub(1, #arg_lead) == arg_lead then table.insert(out, s) end
  end
  maybe('all')
  for _, id in ipairs(require('redmine.ui.pending').draft_ids()) do
    maybe(id)
  end
  return out
end

local function rmpost_command(args)
  local arg = vim.trim(args.args or '')
  if arg == '' then
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
    if ft == 'redmine-compose' then
      require('redmine.ui.compose').post_current()
    elseif ft == 'redmine-pending' then
      -- Pin to the listing's snapshot so a cwd drift doesn't reroute.
      require('redmine.ui.pending').post_listed()
    else
      vim.notify(
        ':Rmpost — compose 또는 pending 버퍼에서 호출하거나, :Rmpost <id> / :Rmpost all 사용',
        vim.log.levels.ERROR, { title = 'redmine' })
    end
    return
  end
  if arg == 'all' then
    require('redmine.ui.pending').post_all()
    return
  end
  local id = tonumber(arg)
  if not id then
    vim.notify(':Rmpost 인자는 issue id 또는 all 이어야 합니다 (받은 값: ' .. arg .. ')',
      vim.log.levels.ERROR, { title = 'redmine' })
    return
  end
  require('redmine.ui.pending').post_id(id)
end

function M.register()
  vim.api.nvim_create_user_command('Rm', rm_command, { nargs = '?', desc = 'redmine: open issue or inbox' })
  vim.api.nvim_create_user_command('Rminbox', open_inbox, {
    nargs = '?',
    complete = complete_inbox,
    desc = 'redmine: open inbox (filter: open|all|mine)',
  })

  vim.api.nvim_create_user_command('Rmcomment', function(args)
    with_id(args, 'Rmcomment', function(id) require('redmine.ui.compose').open(id) end)
  end, { nargs = '?', desc = 'redmine: compose comment' })

  vim.api.nvim_create_user_command('Rmpost', rmpost_command, {
    nargs = '?',
    complete = complete_post,
    desc = 'redmine: post compose buffer / draft by id / all',
  })

  vim.api.nvim_create_user_command('Rmstatus', function(args)
    with_id(args, 'Rmstatus', function(id, rest)
      require('redmine.actions').change_status(id, rest ~= '' and rest or nil)
    end)
  end, { nargs = '*', desc = 'redmine: change status (optional name)' })

  vim.api.nvim_create_user_command('Rmprogress', function(args)
    with_id(args, 'Rmprogress', function(id, rest)
      require('redmine.actions').change_progress(id, rest ~= '' and tonumber(rest) or nil)
    end)
  end, { nargs = '*', desc = 'redmine: change progress' })

  vim.api.nvim_create_user_command('Rmlog', function(args)
    with_id(args, 'Rmlog', function(id, rest)
      require('redmine.actions').log_time(id, rest ~= '' and tonumber(rest) or nil)
    end)
  end, { nargs = '*', desc = 'redmine: log time' })

  vim.api.nvim_create_user_command('Rmassign', function(args)
    with_id(args, 'Rmassign', function(id, rest)
      require('redmine.actions').assign(id, rest ~= '' and rest or nil)
    end)
  end, { nargs = '*', desc = 'redmine: change assignee' })

  vim.api.nvim_create_user_command('Rmfetch', function(args)
    -- Refreshes the local task.md (CLI writes through `path task --id`).
    with_id(args, 'Rmfetch', function(id)
      local cli = require('redmine.cli')
      cli.run({ 'path', 'task', '--id', tostring(id) }, {}, function(stdout)
        local target = vim.trim(stdout)
        if target == '' then
          vim.notify('task 경로 결정 실패', vim.log.levels.ERROR); return
        end
        cli.run({ 'fetch', tostring(id), '--format=task' }, {}, function(content)
          vim.fn.mkdir(vim.fn.fnamemodify(target, ':h'), 'p')
          local f, err = io.open(target, 'w')
          if not f then vim.notify('task 파일 쓰기 실패: ' .. (err or '?'), vim.log.levels.ERROR); return end
          f:write(content); f:close()
          vim.notify('task 갱신: ' .. target, vim.log.levels.INFO, { title = 'redmine' })
        end)
      end)
    end)
  end, { nargs = '?', desc = 'redmine: refresh task file' })
end

return M
