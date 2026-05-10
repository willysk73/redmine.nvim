-- Drives the plugin against the Docker Redmine, captures buffer contents,
-- and writes them to /tmp/redmine_e2e_*.txt for inspection.

local function dump(path, lines)
  local f = assert(io.open(path, 'w'))
  for _, l in ipairs(lines) do f:write(l, '\n') end
  f:close()
end

local function wait_until(predicate, timeout_ms)
  local ok = vim.wait(timeout_ms or 8000, predicate, 50)
  return ok
end

local results = {}
local function record(name, ok, detail)
  table.insert(results, { name = name, ok = ok, detail = detail or '' })
end

-- ---------- Test 1: :Rminbox renders issues ------------------
do
  vim.cmd('Rminbox')
  local ok = wait_until(function()
    local bufnr = vim.fn.bufnr('redmine://inbox')
    if bufnr == -1 then return false end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:match('#%d+') then return true end
    end
    return false
  end, 8000)

  local bufnr = vim.fn.bufnr('redmine://inbox')
  local lines = bufnr ~= -1 and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
  dump('/tmp/redmine_e2e_inbox.txt', lines)

  if not ok then
    record('inbox renders issues', false, 'no #N row appeared in 8s')
  else
    record('inbox renders issues', true, ('%d lines'):format(#lines))
  end

  -- header sanity
  local header_ok = lines[1] and lines[1]:match('내 일감 %((%d+)%)') ~= nil
  record('inbox header has count', header_ok, lines[1] or '(empty)')

  -- footer sanity
  local has_footer = false
  for _, l in ipairs(lines) do if l:match('q close') then has_footer = true; break end end
  record('inbox footer present', has_footer)
end

-- ---------- Test 2: :Rm 1 renders issue body ------------------
do
  vim.cmd('Rm 1')
  local ok = wait_until(function()
    local bufnr = vim.fn.bufnr('redmine://issue/1')
    if bufnr == -1 then return false end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:match('이메일 검증 함수 추가') then return true end
    end
    return false
  end, 8000)

  local bufnr = vim.fn.bufnr('redmine://issue/1')
  local lines = bufnr ~= -1 and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
  dump('/tmp/redmine_e2e_issue1.txt', lines)

  record('issue #1 body fetched', ok, ('%d lines'):format(#lines))

  local has_status = false
  for _, l in ipairs(lines) do if l:match('상태%s*:') then has_status = true; break end end
  record('issue page has 상태 field', has_status)

  -- Buffer should be non-modifiable.
  local mod = vim.api.nvim_get_option_value('modifiable', { buf = bufnr })
  record('issue buffer is read-only', mod == false, ('modifiable=%s'):format(tostring(mod)))

  -- filetype set
  local ft = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  record('issue filetype set', ft == 'redmine-issue', ft)
end

-- ---------- Test 3: bad id (not a number) ------------------
do
  -- Headless nvim turns vim.notify(ERROR, ...) into an :echoerr inside a
  -- user command, which raises a Vim error from vim.cmd(). We just want to
  -- capture the message and confirm nothing crashed; swallow the forward.
  local notif_seen = nil
  local orig = vim.notify
  vim.notify = function(msg, _level, _opts) notif_seen = msg end
  local ok = pcall(vim.cmd, 'Rm abc')
  vim.notify = orig
  record('bad id rejected without crashing', ok and notif_seen ~= nil and notif_seen:match('숫자') ~= nil,
    notif_seen or '(no notify)')
  -- Also verify no issue buffer was opened for the bogus id.
  record('bad id does not open issue buffer', vim.fn.bufnr('redmine://issue/abc') == -1)
end

-- ---------- Test 4: :Rm with no arg + no detect → falls back to inbox ----------
do
  -- We're not in a git repo or with .redmine here, so detect should fail.
  -- Close existing inbox first to verify it's reopened.
  local existing = vim.fn.bufnr('redmine://inbox')
  if existing ~= -1 then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end
  vim.cmd('Rm')
  local ok = wait_until(function()
    return vim.fn.bufnr('redmine://inbox') ~= -1
  end, 8000)
  record(':Rm fallback opens inbox', ok)
end

-- ---------- Test 5: compose+post round trip on issue #1 ------------------
-- Also asserts post creates exactly ONE journal entry, even when changing
-- status + progress in the same draft (Redmine bundles them via a single PUT).
do
  local id = 1

  -- Reset to a known starting state so the post below always produces real
  -- status/progress deltas (otherwise re-running the suite finds the issue
  -- already at Resolved/80 and the bundled-PUT yields zero detail entries).
  vim.system({ 'redmine', 'update', tostring(id), '--status', 'New', '--progress', '0' },
             { text = true }):wait(8000)

  -- Snapshot journal count before.
  local before_proc = vim.system({ 'redmine', 'fetch', tostring(id), '--format=json' }, { text = true }):wait(8000)
  local before_ok, before_issue = pcall(vim.json.decode, before_proc.stdout or '')
  local journals_before = before_ok and #(before_issue.journals or {}) or -1

  -- Open compose buffer
  vim.cmd('Rmcomment ' .. tostring(id))

  -- Wait for scaffold to be written.
  local ok = wait_until(function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and
         vim.api.nvim_get_option_value('filetype', { buf = b }) == 'redmine-compose' then
        local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
        if lines[1] == '---' and lines[2] == ('id: ' .. tostring(id)) and #lines > 6 then
          return true
        end
      end
    end
    return false
  end, 8000)
  record('compose buffer scaffold ready', ok)

  -- Find the buffer and edit it.
  local cbuf
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and
       vim.api.nvim_get_option_value('filetype', { buf = b }) == 'redmine-compose' then
      cbuf = b; break
    end
  end

  if cbuf then
    local lines = vim.api.nvim_buf_get_lines(cbuf, 0, -1, false)

    -- Scaffold is now id / status / assignee — no progress/time. assignee
    -- should be pre-filled with the suggested user (last commenter or
    -- issue author). Verify that.
    local assignee_line = lines[4] or ''
    record('scaffold pre-fills assignee with suggestion',
      assignee_line:match('^assignee:%s*%S') ~= nil,
      assignee_line)

    -- Add progress: 80 (manually inserted) to also exercise the bundled-PUT
    -- path even though it's not in the default scaffold.
    for i, ln in ipairs(lines) do
      if ln == 'status:' then lines[i] = 'status: Resolved' end
    end
    -- Insert `progress: 80` right before the closing `---` (line 5 in scaffold).
    table.insert(lines, 5, 'progress: 80')
    -- Body line is now line 8 in 1-based indexing (after id, status, assignee, progress, ---, blank, body).
    lines[8] = 'M2 e2e: 검증 함수 통합 테스트 결과 통과. 코드 머지 완료.'
    vim.api.nvim_buf_set_lines(cbuf, 0, -1, false, lines)
    vim.api.nvim_buf_call(cbuf, function() vim.cmd('silent! write') end)

    -- Post — buffer was already focused after :Rmcomment + edit.
    vim.cmd('Rmpost')

    -- Wait for buffer to close (after_post=archive deletes/moves the file and wipes the buf).
    local closed = wait_until(function()
      return not vim.api.nvim_buf_is_valid(cbuf) or
             not vim.api.nvim_buf_is_loaded(cbuf)
    end, 8000)
    record('post completed (buffer closed)', closed)

    -- Verify state on server using CLI.
    local proc = vim.system({ 'redmine', 'fetch', tostring(id), '--format=json' }, { text = true }):wait(8000)
    local server_ok, server = pcall(vim.json.decode, proc.stdout or '')
    if not server_ok then
      record('issue state verifiable via CLI', false, 'json parse failed')
    else
      record('post applied: status=Resolved',
        (server.status or {}).name == 'Resolved',
        ('got %s'):format((server.status or {}).name or '?'))
      record('post applied: progress=80',
        server.done_ratio == 80,
        ('got %s'):format(tostring(server.done_ratio)))
      local last = (server.journals or {})[#(server.journals or {})] or {}
      record('post applied: comment present',
        type(last.notes) == 'string' and last.notes:match('M2 e2e') ~= nil,
        last.notes or '(no notes)')

      -- Single-journal invariant: comment + status + progress = 1 journal,
      -- not 3. This is the user-visible difference between compose-post
      -- and three separate :Rmstatus/:Rmprogress/etc. calls.
      local journals_after = #(server.journals or {})
      record('post creates exactly 1 journal entry (comment + 2 field changes bundled)',
        journals_before >= 0 and journals_after == journals_before + 1,
        ('before=%d after=%d'):format(journals_before, journals_after))
      -- And that the single journal carries both attribute deltas.
      local details = last.details or {}
      local saw_status, saw_progress = false, false
      for _, det in ipairs(details) do
        if det.name == 'status_id'  then saw_status = true end
        if det.name == 'done_ratio' then saw_progress = true end
      end
      record('the single journal has status + progress details',
        saw_status and saw_progress,
        ('details=%d (status=%s, progress=%s)'):format(#details, tostring(saw_status), tostring(saw_progress)))
    end
  else
    record('compose buffer found', false)
  end
end

-- ---------- Test 6: action wrappers (status/progress) ------------------
do
  local id = 2
  local actions = require('redmine.actions')

  actions.change_progress(id, 55)
  local ok = wait_until(function()
    local proc = vim.system({ 'redmine', 'fetch', tostring(id), '--format=json' }, { text = true }):wait(4000)
    local jok, j = pcall(vim.json.decode, proc.stdout or '')
    return jok and j.done_ratio == 55
  end, 6000)
  record('actions.change_progress(2, 55) applied', ok)

  actions.change_status(id, 'Closed')
  local ok2 = wait_until(function()
    local proc = vim.system({ 'redmine', 'fetch', tostring(id), '--format=json' }, { text = true }):wait(4000)
    local jok, j = pcall(vim.json.decode, proc.stdout or '')
    return jok and ((j.status or {}).name == 'Closed')
  end, 6000)
  record('actions.change_status(2, "Closed") applied', ok2)
end

-- ---------- Test 7: post with empty body, frontmatter changes only ----------
do
  local id = 3

  local before_proc = vim.system({ 'redmine', 'fetch', tostring(id), '--format=json' }, { text = true }):wait(8000)
  local before_ok, before_issue = pcall(vim.json.decode, before_proc.stdout or '')
  local journals_before = before_ok and #(before_issue.journals or {}) or -1
  local current_status = before_ok and (before_issue.status or {}).name or '?'
  local target_status = current_status == 'Feedback' and 'In Progress' or 'Feedback'

  vim.cmd('Rmcomment ' .. tostring(id))

  local ok = wait_until(function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and
         vim.api.nvim_get_option_value('filetype', { buf = b }) == 'redmine-compose' then
        local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
        if lines[1] == '---' and lines[2] == ('id: ' .. tostring(id)) and #lines > 6 then
          return true
        end
      end
    end
    return false
  end, 8000)
  record('compose buffer scaffold ready (#3)', ok)

  local cbuf
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and
       vim.api.nvim_get_option_value('filetype', { buf = b }) == 'redmine-compose' then
      cbuf = b; break
    end
  end

  if cbuf then
    local lines = vim.api.nvim_buf_get_lines(cbuf, 0, -1, false)
    for i, ln in ipairs(lines) do
      if ln == 'status:' then lines[i] = 'status: ' .. target_status end
    end
    -- Body line stays empty: this exercises the "no comment, change only" path.
    vim.api.nvim_buf_set_lines(cbuf, 0, -1, false, lines)
    vim.api.nvim_buf_call(cbuf, function() vim.cmd('silent! write') end)

    vim.cmd('Rmpost')

    local closed = wait_until(function()
      return not vim.api.nvim_buf_is_valid(cbuf) or
             not vim.api.nvim_buf_is_loaded(cbuf)
    end, 8000)
    record('post (empty body) completed', closed)

    local proc = vim.system({ 'redmine', 'fetch', tostring(id), '--format=json' }, { text = true }):wait(8000)
    local sok, server = pcall(vim.json.decode, proc.stdout or '')
    if not sok then
      record('issue #3 fetchable after empty-body post', false, 'json parse failed')
    else
      record(('post (empty body) applied: status=%s'):format(target_status),
        (server.status or {}).name == target_status,
        ('got %s'):format((server.status or {}).name or '?'))

      local journals_after = #(server.journals or {})
      record('post (empty body) creates exactly 1 journal',
        journals_before >= 0 and journals_after == journals_before + 1,
        ('before=%d after=%d'):format(journals_before, journals_after))

      local last = (server.journals or {})[#(server.journals or {})] or {}
      local notes_empty = (last.notes == nil) or (last.notes == vim.NIL) or (type(last.notes) == 'string' and last.notes == '')
      record('the journal has empty notes (no comment)',
        notes_empty,
        ('notes=%q'):format(tostring(last.notes or '')))
    end
  else
    record('compose buffer found (#3)', false)
  end
end

-- ---------- Report ------------------
local pass = 0
for _, r in ipairs(results) do if r.ok then pass = pass + 1 end end

print('---- redmine.nvim E2E ----')
for _, r in ipairs(results) do
  print(('[%s] %s%s'):format(
    r.ok and 'PASS' or 'FAIL',
    r.name,
    (r.detail ~= '' and ('  — ' .. r.detail) or '')
  ))
end
print(('---- %d/%d passed ----'):format(pass, #results))

if pass ~= #results then
  vim.cmd(('cquit ' .. tostring(1)))
else
  vim.cmd('qall!')
end
