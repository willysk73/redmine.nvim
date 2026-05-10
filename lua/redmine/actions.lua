-- Mid-level actions: pickers + CLI calls. Used by global commands
-- (:Rmstatus, :Rmprogress, :Rmlog, :Rmassign) and issue-buffer keymaps.
local cli = require('redmine.cli')
local picker = require('redmine.picker')

local M = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'redmine' })
end

local function refresh_issue(id)
  -- Best-effort: refresh open issue buffer if visible. Avoid require cycles.
  vim.schedule(function()
    pcall(function()
      require('redmine.ui.issue').refresh(id)
    end)
  end)
end

---@param id integer
---@param target string|nil       optional name/id; if nil, opens picker
function M.change_status(id, target)
  local function apply(name)
    cli.run({ 'update', tostring(id), '--status', name }, {}, function()
      notify(('#%d 상태 → %s'):format(id, name))
      refresh_issue(id)
    end)
  end

  if target and target ~= '' then
    apply(target)
    return
  end

  cli.run_json({ 'meta', 'statuses', '--issue', tostring(id) }, function(items)
    items = items or {}
    if #items == 0 then
      notify('가용 상태가 없습니다', vim.log.levels.WARN)
      return
    end
    picker.select(items, {
      prompt = ('#%d 상태 변경'):format(id),
      label = function(it) return it.name end,
    }, function(choice)
      if not choice then return end
      apply(choice.name)
    end)
  end)
end

---@param id integer
---@param value integer|nil
function M.change_progress(id, value)
  local function apply(n)
    if n == nil then return end
    n = tonumber(n)
    if not n or n < 0 or n > 100 then
      notify('진척률은 0~100 사이 숫자여야 합니다', vim.log.levels.ERROR)
      return
    end
    cli.run({ 'update', tostring(id), '--progress', tostring(n) }, {}, function()
      notify(('#%d 진척 → %d%%'):format(id, n))
      refresh_issue(id)
    end)
  end

  if value ~= nil then apply(value) return end
  vim.ui.input({ prompt = ('#%d 진척률 (0-100): '):format(id) }, apply)
end

---@param id integer
---@param hours number|nil
function M.log_time(id, hours)
  local function apply(h)
    if h == nil or h == '' then return end
    h = tonumber(h)
    if not h or h <= 0 then
      notify('시간은 양수여야 합니다', vim.log.levels.ERROR)
      return
    end
    cli.run({ 'log', tostring(id), '--hours', tostring(h) }, {}, function()
      notify(('#%d 시간 기록 → %sh'):format(id, h))
      refresh_issue(id)
    end)
  end
  if hours ~= nil then apply(hours) return end
  vim.ui.input({ prompt = ('#%d 기록할 시간 (h): '):format(id) }, apply)
end

---@param id integer
---@param target string|nil
function M.assign(id, target)
  local function apply(user_arg)
    cli.run({ 'assign', tostring(id), '--user', user_arg }, {}, function()
      notify(('#%d 담당자 → %s'):format(id, user_arg == '' and '(할당 해제)' or user_arg))
      refresh_issue(id)
    end)
  end

  if target ~= nil then apply(target) return end

  -- Need project id to fetch members; cheapest is `redmine fetch <id> --format=json`.
  cli.run({ 'fetch', tostring(id), '--format=json' }, {}, function(stdout)
    local ok, issue = pcall(vim.json.decode, stdout)
    if not ok or type(issue) ~= 'table' then
      notify('issue fetch 파싱 실패', vim.log.levels.ERROR)
      return
    end
    local pid = issue.project and issue.project.id
    if not pid then
      notify('project id 를 찾을 수 없습니다', vim.log.levels.ERROR)
      return
    end
    cli.run_json({ 'meta', 'members', '--project', tostring(pid) }, function(members)
      members = members or {}
      -- Prepend an "unassign" sentinel.
      local items = { { id = '__unassign__', name = '― 할당 해제 ―' } }
      for _, m in ipairs(members) do table.insert(items, m) end
      picker.select(items, {
        prompt = ('#%d 담당자 변경'):format(id),
        label = function(it) return it.name end,
      }, function(choice)
        if not choice then return end
        if choice.id == '__unassign__' then
          apply('')
        else
          apply(tostring(choice.id))
        end
      end)
    end)
  end)
end

return M
