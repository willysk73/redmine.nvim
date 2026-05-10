-- Compose buffer: a real file on disk holding draft frontmatter + body +
-- cutoff context. `:w` saves; <leader>p calls `redmine post --file <draft>`.
local cli = require('redmine.cli')
local config = require('redmine.config')
local fm_mod = require('redmine.frontmatter')
local util = require('redmine.util')

local M = {}

local CUTOFF_LINE = '<!-- ━━━ 아래는 참고용. post 시 무시됨. ━━━ -->'

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'redmine' })
end

---Build initial draft scaffold (frontmatter + empty body + cutoff + task context).
---@param id integer
---@param task_md string  output of `redmine fetch <id> --format=task`
-- Scaffold lists only the common-path fields. CLI still accepts
-- `progress:` / `time:` if the user adds them by hand — useful occasionally
-- but uncluttered as the default. Single PUT bundles everything into one
-- journal entry regardless of how many fields are filled.
local function scaffold(id, task_md, suggested_assignee)
  local lines = {
    '---',
    'id: ' .. tostring(id),
    'status:',
    'assignee: ' .. (suggested_assignee or ''),
    '---',
    '',
    '',  -- caret will land here (line 7)
    '',
    CUTOFF_LINE,
    '',
  }
  for _, ln in ipairs(vim.split(task_md, '\n', { plain = true })) do
    table.insert(lines, ln)
  end
  return lines
end

---Refresh just the context portion below the cutoff, preserving user-authored body.
local function refresh_context(bufnr, task_md)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cutoff_idx = nil
  for i, ln in ipairs(lines) do
    if ln:match('^<!%-%-.*━━━.*%-%->%s*$') then
      cutoff_idx = i
      break
    end
  end
  if not cutoff_idx then
    -- No cutoff present (user removed it?). Append fresh.
    table.insert(lines, '')
    table.insert(lines, CUTOFF_LINE)
    cutoff_idx = #lines
  end

  local kept = {}
  for i = 1, cutoff_idx do table.insert(kept, lines[i]) end
  table.insert(kept, '')
  for _, ln in ipairs(vim.split(task_md, '\n', { plain = true })) do
    table.insert(kept, ln)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, kept)
end

local function post_buffer(bufnr, opts)
  opts = opts or {}
  local cfg = config.get().compose or {}
  if vim.api.nvim_get_option_value('modified', { buf = bufnr }) then
    -- Save first so the file we hand to the CLI matches the buffer.
    vim.api.nvim_buf_call(bufnr, function() vim.cmd('silent! write') end)
  end

  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == '' or vim.fn.filereadable(file) == 0 then
    notify('compose 버퍼에 연결된 파일이 없습니다', vim.log.levels.ERROR)
    return
  end

  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  local composed = fm_mod.split(text, { cutoff_pattern = cfg.cutoff_pattern })

  local issue_id = tonumber(composed.fm.id)
  if not issue_id then
    notify('frontmatter id 가 없거나 잘못되었습니다', vim.log.levels.ERROR)
    return
  end

  local has_body = composed.body ~= ''
  local has_changes = (composed.fm.status and composed.fm.status ~= '')
                  or (composed.fm.progress and composed.fm.progress ~= '')
                  or (composed.fm.assignee and composed.fm.assignee ~= '')
                  or (composed.fm.time and composed.fm.time ~= '')
  if not has_body and not has_changes then
    notify('본문도 비고 frontmatter 변경도 없음 — post 안 함', vim.log.levels.WARN)
    return
  end

  local function do_post()
    cli.run({ 'post', '--file', file }, {}, function(stdout)
      local ok, parsed = pcall(vim.json.decode, stdout)
      local actions_str = (ok and parsed and parsed.actions) and table.concat(parsed.actions, ', ') or ''
      notify(('#%d post 완료%s'):format(issue_id, actions_str ~= '' and (' — ' .. actions_str) or ''))

      -- after_post handling
      local after = cfg.after_post or 'archive'
      if after == 'delete' then
        pcall(os.remove, file)
      elseif after == 'archive' then
        local archive_dir = vim.fn.fnamemodify(file, ':h') .. '/posted'
        vim.fn.mkdir(archive_dir, 'p')
        local target = archive_dir .. '/' .. vim.fn.fnamemodify(file, ':t')
        pcall(os.rename, file, target)
      end
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })

      -- Refresh issue buffer if open.
      pcall(function() require('redmine.ui.issue').refresh(issue_id) end)
    end)
  end

  if opts.no_confirm or cfg.confirm_post == false then
    do_post()
    return
  end

  local lines = { ('Issue #%d post:'):format(issue_id) }
  if has_body then
    table.insert(lines, '─────')
    vim.list_extend(lines, fm_mod.body_preview(composed.body, 5))
    table.insert(lines, '─────')
  end
  local changes = {}
  if composed.fm.status   and composed.fm.status   ~= '' then table.insert(changes, 'status='   .. composed.fm.status) end
  if composed.fm.progress and composed.fm.progress ~= '' then table.insert(changes, 'progress=' .. composed.fm.progress) end
  if composed.fm.time     and composed.fm.time     ~= '' then table.insert(changes, 'time='     .. composed.fm.time .. 'h') end
  if composed.fm.assignee and composed.fm.assignee ~= '' then table.insert(changes, 'assignee=' .. composed.fm.assignee) end
  if #changes > 0 then
    table.insert(lines, '변경: ' .. table.concat(changes, ', '))
  end
  local prompt = table.concat(lines, '\n') .. '\n\n진행할까요? (y/N) '

  vim.ui.input({ prompt = prompt }, function(answer)
    if answer and (answer:lower() == 'y' or answer:lower() == 'yes') then
      do_post()
    else
      notify('post 취소')
    end
  end)
end

local function bind_keys(bufnr)
  local km = config.get().keymaps.compose_buffer or {}
  util.bmap(bufnr, km.post, function() post_buffer(bufnr) end, 'redmine: post draft')
  util.bmap(bufnr, km.post_no_confirm, function() post_buffer(bufnr, { no_confirm = true }) end,
    'redmine: post draft (no confirm)')
  util.bmap(bufnr, km.discard, function()
    local file = vim.api.nvim_buf_get_name(bufnr)
    if vim.api.nvim_get_option_value('modified', { buf = bufnr }) then
      vim.ui.input({ prompt = '미저장 변경이 있습니다. 그래도 폐기할까요? (y/N) ' }, function(ans)
        if ans and ans:lower() == 'y' then
          if file ~= '' then pcall(os.remove, file) end
          pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
      end)
    else
      if file ~= '' then pcall(os.remove, file) end
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end, 'redmine: discard draft')
end

---Open (or focus) the compose buffer for an issue.
---@param id integer
function M.open(id)
  cli.run({ 'path', 'draft', '--id', tostring(id) }, {}, function(path_stdout)
    local file = vim.trim(path_stdout)
    if file == '' then
      notify('draft 경로 결정 실패', vim.log.levels.ERROR)
      return
    end
    -- mkdir parent
    vim.fn.mkdir(vim.fn.fnamemodify(file, ':h'), 'p')

    local existed = vim.fn.filereadable(file) == 1

    -- Focus if already open.
    local bufnr = vim.fn.bufnr(file)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
          vim.api.nvim_set_current_win(win)
          return
        end
      end
    end

    -- Open via configured strategy.
    local strategy = config.get().ui.compose_strategy or 'vsplit'
    if strategy == 'vsplit' then vim.cmd('vsplit ' .. vim.fn.fnameescape(file))
    elseif strategy == 'tab' then vim.cmd('tabedit ' .. vim.fn.fnameescape(file))
    elseif strategy == 'split' then vim.cmd('split ' .. vim.fn.fnameescape(file))
    else vim.cmd('edit ' .. vim.fn.fnameescape(file)) end

    bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_option_value('filetype', 'redmine-compose', { buf = bufnr })
    bind_keys(bufnr)

    -- File already existed → just freshen the context portion below cutoff.
    if existed then
      cli.run({ 'fetch', tostring(id), '--format=task' }, {}, function(task_md)
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        refresh_context(bufnr, task_md or '')
        vim.api.nvim_buf_call(bufnr, function() vim.cmd('silent! write') end)
      end)
      return
    end

    -- New draft: kick off task + suggest in parallel; build scaffold when both arrive.
    local task_md, suggested
    local function maybe_finish()
      if task_md == nil or suggested == nil then return end
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, scaffold(id, task_md, suggested))
      -- Move cursor onto the empty body line (line 7 in the scaffold).
      local win = vim.fn.bufwinid(bufnr)
      if win ~= -1 then pcall(vim.api.nvim_win_set_cursor, win, { 7, 0 }) end
      vim.api.nvim_buf_call(bufnr, function() vim.cmd('silent! write') end)
    end

    cli.run({ 'fetch', tostring(id), '--format=task' }, {}, function(out)
      task_md = out or ''
      maybe_finish()
    end)
    cli.run_allow_fail({ 'suggest', 'assignee', '--id', tostring(id) }, function(_, out, _)
      suggested = vim.trim(out or '')
      maybe_finish()
    end)
  end)
end

---Drive post from outside (`:Rmpost`).
function M.post_current()
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  if ft ~= 'redmine-compose' then
    notify(':Rmpost 는 redmine-compose 버퍼 안에서 호출해야 합니다', vim.log.levels.ERROR)
    return
  end
  post_buffer(bufnr)
end

return M
