-- Register :Rm* commands. Spec §6.
local M = {}

local function open_inbox()
  require('redmine.ui.inbox').open()
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
    if id then open_issue(id) else open_inbox() end
  end)
end

function M.register()
  vim.api.nvim_create_user_command('Rm', rm_command, { nargs = '?', desc = 'redmine: open issue or inbox' })
  vim.api.nvim_create_user_command('Rminbox', open_inbox, { desc = 'redmine: open inbox' })

  vim.api.nvim_create_user_command('Rmcomment', function(args)
    with_id(args, 'Rmcomment', function(id) require('redmine.ui.compose').open(id) end)
  end, { nargs = '?', desc = 'redmine: compose comment' })

  vim.api.nvim_create_user_command('Rmpost', function()
    require('redmine.ui.compose').post_current()
  end, { desc = 'redmine: post current compose buffer' })

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
