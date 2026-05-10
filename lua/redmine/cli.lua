-- Async wrapper for the `redmine` CLI. Spec §11.
local config = require('redmine.config')

local M = {}

local EXIT_AUTH = 11

local function notify_error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = 'redmine' })
end

---Run the CLI asynchronously.
---@param args string[]   subcommand + flags (e.g. {'fetch', '1', '--format=display'})
---@param opts table|nil  reserved
---@param on_done fun(stdout: string)
function M.run(args, opts, on_done)
  opts = opts or {}
  local cli = config.get().cli or 'redmine'
  local cmd = { cli }
  vim.list_extend(cmd, args)

  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        if obj.code == EXIT_AUTH then
          notify_error('Redmine 인증 실패. `redmine whoami` 로 토큰 확인.')
        else
          local stderr = (obj.stderr and obj.stderr ~= '') and obj.stderr or '(no stderr)'
          notify_error(('redmine %s 실패 (exit %d): %s'):format(args[1] or '?', obj.code, stderr))
        end
        if opts.on_error then opts.on_error(obj.code, obj.stderr or '') end
        return
      end
      on_done(obj.stdout or '')
    end)
  end)
end

---Like run() but parses stdout as JSON.
function M.run_json(args, on_done)
  local with_flag = vim.deepcopy(args)
  -- Add --json only if the caller didn't already include it.
  local has_json = false
  for _, a in ipairs(with_flag) do
    if a == '--json' then has_json = true; break end
  end
  if not has_json then table.insert(with_flag, '--json') end

  M.run(with_flag, {}, function(stdout)
    local ok, data = pcall(vim.json.decode, stdout)
    if not ok then
      notify_error('redmine ' .. (args[1] or '?') .. ': JSON 파싱 실패')
      return
    end
    on_done(data)
  end)
end

---Convenience: tolerates exit 1 (used by `detect`).
function M.run_allow_fail(args, on_done)
  local cli = config.get().cli or 'redmine'
  local cmd = { cli }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      on_done(obj.code, obj.stdout or '', obj.stderr or '')
    end)
  end)
end

return M
