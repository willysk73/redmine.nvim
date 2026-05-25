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

-- Build the read-only Reference section that sits BELOW the cutoff. The CLI
-- post path already ignores everything past the cutoff (see fm_mod.split's
-- body_end), so this is pure documentation context for the user.
-- `statuses` / `issue` are nil when the underlying fetch failed; we surface
-- a short hint in that case rather than dropping the section entirely.
local function build_reference_lines(statuses, issue)
  local out = {}

  table.insert(out, '## 가능한 status')
  if statuses == nil then
    table.insert(out, '_(status fetch failed — :checkhealth redmine 확인)_')
  elseif #statuses == 0 then
    table.insert(out, '_(no statuses returned — check Redmine config)_')
  else
    for _, s in ipairs(statuses) do
      local suffix = s.is_closed and '*' or ''
      table.insert(out, ('- %s: %s%s'):format(tostring(s.id), tostring(s.name), suffix))
    end
  end
  table.insert(out, '')

  table.insert(out, '## progress')
  table.insert(out, '0 ~ 100 정수. UI 관례: 0/10/20/.../100.')
  table.insert(out, '예: progress: 50')
  table.insert(out, '')

  table.insert(out, '## assignee 후보')
  if issue then
    local author_name = (issue.author or {}).name
    if author_name then
      table.insert(out, '- 작성자: ' .. author_name)
    end
    local seen, participants = {}, {}
    if author_name then seen[author_name] = true end
    for _, j in ipairs(issue.journals or {}) do
      local n = (j.user or {}).name
      if n and not seen[n] then
        seen[n] = true
        table.insert(participants, n)
      end
    end
    if #participants > 0 then
      table.insert(out, '- 참여자: ' .. table.concat(participants, ', '))
    end
    -- `redmine meta members --project` accepts both numeric id and string
    -- identifier; /issues/X.json only carries the id+name, so we prefer
    -- identifier when present (e.g. via API include) and fall back to id.
    local proj = issue.project or {}
    local key = proj.identifier or (proj.id ~= nil and tostring(proj.id)) or '<project>'
    table.insert(out, '- 전체 멤버: redmine meta members --project ' .. key)
  else
    table.insert(out, '_(assignee 후보 fetch failed — :checkhealth redmine 확인)_')
  end
  table.insert(out, '- 빈 값 / none / unassign / - → 할당 해제')

  return out
end

---Build initial draft scaffold (frontmatter + empty body + cutoff + task context).
---@param id integer
---@param task_md string  output of `redmine fetch <id> --format=task`
---@param suggested_assignee string|nil
---@param reference_lines string[]|nil  Reference section lines (statuses /
---       progress / assignee candidates). Inserted BELOW the cutoff so the
---       post path stays byte-identical to pre-T-4 when reference is off.
-- Scaffold lists only the common-path fields. CLI still accepts
-- `progress:` / `time:` if the user adds them by hand — useful occasionally
-- but uncluttered as the default. Single PUT bundles everything into one
-- journal entry regardless of how many fields are filled.
local function scaffold(id, task_md, suggested_assignee, reference_lines)
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
  if reference_lines and #reference_lines > 0 then
    for _, ln in ipairs(reference_lines) do table.insert(lines, ln) end
    table.insert(lines, '')
  end
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

---Post a draft file directly. Shared by `:Rmpost` (compose buffer flow) and
---the pending buffer's `p` / `P` / `:Rmpost <id> | all` paths.
---@param path string  absolute path to the draft file on disk
---@param opts table|nil  {no_confirm = bool, on_done = fun(ok: bool, info: table|nil)}
function M.post_file(path, opts)
  opts = opts or {}
  local cfg = config.get().compose or {}

  local function finish(ok, info)
    if opts.on_done then opts.on_done(ok, info) end
  end

  if not path or path == '' or vim.fn.filereadable(path) == 0 then
    notify(('draft 파일을 찾을 수 없습니다: %s'):format(path or ''), vim.log.levels.ERROR)
    finish(false)
    return
  end

  -- If the draft is loaded as a modified buffer elsewhere (e.g. user typed
  -- into the compose buffer in one split and ran :Rmpost <id> in another),
  -- save it first so the CLI reads the live content instead of stale bytes.
  local canon_path = vim.fn.fnamemodify(path, ':p')
  for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bnr) then
      local bname = vim.api.nvim_buf_get_name(bnr)
      if bname ~= '' and vim.fn.fnamemodify(bname, ':p') == canon_path then
        if vim.api.nvim_get_option_value('modified', { buf = bnr }) then
          vim.api.nvim_buf_call(bnr, function() vim.cmd('silent! write') end)
        end
        break
      end
    end
  end

  local f = io.open(path, 'r')
  if not f then
    notify(('draft 파일 읽기 실패: %s'):format(path), vim.log.levels.ERROR)
    finish(false)
    return
  end
  local text = f:read('*a') or ''
  f:close()

  local composed = fm_mod.split(text, { cutoff_pattern = cfg.cutoff_pattern })

  local issue_id = tonumber(composed.fm.id)
  if not issue_id then
    notify(('frontmatter id 가 없거나 잘못되었습니다: %s'):format(path), vim.log.levels.ERROR)
    finish(false)
    return
  end

  local has_body = composed.body ~= ''
  local has_changes = (composed.fm.status and composed.fm.status ~= '')
                  or (composed.fm.progress and composed.fm.progress ~= '')
                  or (composed.fm.assignee and composed.fm.assignee ~= '')
                  or (composed.fm.time and composed.fm.time ~= '')
  if not has_body and not has_changes then
    notify(('본문도 비고 frontmatter 변경도 없음 — post 안 함 (%s)'):format(path),
      vim.log.levels.WARN)
    finish(false)
    return
  end

  local function do_post()
    cli.run({ 'post', '--file', path }, {
      on_error = function() finish(false) end,
    }, function(stdout)
      local ok, parsed = pcall(vim.json.decode, stdout)
      local actions_str = (ok and parsed and parsed.actions) and table.concat(parsed.actions, ', ') or ''
      notify(('#%d post 완료%s'):format(issue_id, actions_str ~= '' and (' — ' .. actions_str) or ''))

      -- after_post handling
      local after = cfg.after_post or 'archive'
      if after == 'delete' then
        pcall(os.remove, path)
      elseif after == 'archive' then
        -- Default layout: {worktree}/.redmine/{drafts,posted}/. file lives in
        -- .../drafts/ → archive sits next to drafts under the same parent.
        local archive_dir = vim.fn.fnamemodify(path, ':h:h') .. '/posted'
        vim.fn.mkdir(archive_dir, 'p')
        local target = archive_dir .. '/' .. vim.fn.fnamemodify(path, ':t')
        pcall(os.rename, path, target)
      end

      -- Wipe any compose buffer still pointing at the (now-archived) draft so
      -- a stray `:w` doesn't recreate the file and reintroduce it to pending.
      for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bnr) then
          local bname = vim.api.nvim_buf_get_name(bnr)
          if bname ~= '' and vim.fn.fnamemodify(bname, ':p') == canon_path then
            pcall(vim.api.nvim_buf_delete, bnr, { force = true })
          end
        end
      end

      -- Refresh issue buffer if open.
      pcall(function() require('redmine.ui.issue').refresh(issue_id) end)
      finish(true, { issue_id = issue_id })
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
      finish(false)
    end
  end)
end

local function post_buffer(bufnr, opts)
  opts = opts or {}
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == '' then
    notify('compose 버퍼에 연결된 파일이 없습니다', vim.log.levels.ERROR)
    return
  end
  -- post_file saves any modified buffer at the same path, archives the file,
  -- and wipes matching loaded buffers on success — so we just delegate.
  M.post_file(file, { no_confirm = opts.no_confirm })
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

---Open (or focus) the compose buffer at an explicit draft file path. Splits
---out of `M.open(id)` so callers that already know the path (e.g. the pending
---buffer entries, captured under one cwd) don't re-resolve via CLI under the
---current cwd — that would target the wrong worktree.
---@param file string  absolute path to the draft file
---@param id   integer issue id (used to fetch task / suggest / reference data)
function M.open_path(file, id)
  if not file or file == '' then
    notify('draft 경로가 비었습니다', vim.log.levels.ERROR)
    return
  end

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

  -- New draft: kick off task + suggest in parallel; build scaffold when
  -- everything arrives. When the Reference section is enabled (default)
  -- we also fetch issue JSON + meta statuses to populate it. Both
  -- reference fetches use run_allow_fail so a network glitch yields a
  -- short error placeholder in the section rather than aborting scaffold.
  local cfg = config.get().compose or {}
  local ref_enabled = cfg.reference_section ~= false
  local task_md, suggested
  local issue_json, statuses_json
  local issue_done, statuses_done = not ref_enabled, not ref_enabled

  local function maybe_finish()
    if task_md == nil or suggested == nil then return end
    if not issue_done or not statuses_done then return end
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local ref_lines = ref_enabled and build_reference_lines(statuses_json, issue_json) or nil
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false,
      scaffold(id, task_md, suggested, ref_lines))
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
  if ref_enabled then
    cli.run_allow_fail({ 'fetch', tostring(id), '--format=json' }, function(code, out, _)
      if code == 0 then
        local ok, decoded = pcall(vim.json.decode, out)
        if ok then issue_json = decoded end
      end
      issue_done = true
      maybe_finish()
    end)
    cli.run_allow_fail({ 'meta', 'statuses', '--issue', tostring(id), '--json' }, function(code, out, _)
      if code == 0 then
        local ok, decoded = pcall(vim.json.decode, out)
        if ok then statuses_json = decoded end
      end
      statuses_done = true
      maybe_finish()
    end)
  end
end

---Open (or focus) the compose buffer for an issue. Resolves the draft path
---via the CLI (cwd-dependent) and then defers to `M.open_path`.
---@param id integer
function M.open(id)
  cli.run({ 'path', 'draft', '--id', tostring(id) }, {}, function(path_stdout)
    local file = vim.trim(path_stdout)
    if file == '' then
      notify('draft 경로 결정 실패', vim.log.levels.ERROR)
      return
    end
    M.open_path(file, id)
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
