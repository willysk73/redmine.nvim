-- Pending drafts buffer. Fugitive-style listing of `.redmine/drafts/`.
-- Spec §15 (T-5). Read-only, mtime-sorted (newest first), keymap-driven.
local config = require('redmine.config')
local fm_mod = require('redmine.frontmatter')
local util = require('redmine.util')

local M = {}

local BUF_NAME = 'redmine://pending'
local DRAFT_NAME_RE = '^comment%-draft%-(%d+)%.md$'

local state = {
  bufnr = nil,
  -- 1-based: line_to_entry[lnum] = {path, id}; nil for header/blank/empty-state lines.
  line_to_entry = {},
  -- Flat snapshot of entries captured at the last render. Used by post-all
  -- from the pending buffer so a cwd change between render and `P` doesn't
  -- silently pivot to a different worktree's drafts.
  entries = {},
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'redmine' })
end

-- Resolve drafts dir via `redmine path draft --id 1`. The CLI output is cwd-
-- dependent (each Redmine worktree has its own `.redmine/drafts/`), so we
-- re-resolve on every call rather than caching — a single nvim session can
-- visit multiple worktrees and a stale cache would post into the wrong one.
-- The id only affects the basename; picking 1 is arbitrary — see T-5 brief.
local function resolve_drafts_dir()
  local cli = config.get().cli or 'redmine'
  local raw = vim.fn.system({ cli, 'path', 'draft', '--id', '1' })
  if vim.v.shell_error ~= 0 then return nil end
  local p = vim.trim((raw:gsub('\n.*$', '')))
  if p == '' then return nil end
  return vim.fn.fnamemodify(p, ':h')
end

function M.drafts_dir()
  return resolve_drafts_dir()
end

local function read_file(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local text = f:read('*a') or ''
  f:close()
  return text
end

-- Enumerate drafts by globbing `*.md` and reading each file's frontmatter id.
-- We don't filter by basename because the CLI's `[paths].draft_file` template
-- is user-configurable (see redmine-core paths.py). If frontmatter lacks an
-- `id` (broken draft), fall back to the default `comment-draft-<id>.md`
-- pattern, otherwise skip the file.
local function list_drafts(dir)
  local entries = {}
  if not dir or vim.fn.isdirectory(dir) == 0 then return entries end
  for _, path in ipairs(vim.fn.globpath(dir, '*.md', false, true)) do
    local text = read_file(path) or ''
    local composed = fm_mod.split(text)
    local id = composed.fm.id and tonumber(composed.fm.id) or nil
    if not id then
      id = tonumber((vim.fn.fnamemodify(path, ':t')):match(DRAFT_NAME_RE))
    end
    if id then
      local stat = (vim.uv or vim.loop).fs_stat(path)
      table.insert(entries, {
        path = path,
        id = id,
        mtime = stat and stat.mtime.sec or 0,
        composed = composed,
      })
    end
  end
  -- Newest first (per T-5 Decisions: matches git log / fugitive convention).
  table.sort(entries, function(a, b)
    if a.mtime == b.mtime then return a.id < b.id end
    return a.mtime > b.mtime
  end)
  return entries
end

local function fmt_mtime(mtime)
  local now = os.time()
  if os.date('%Y-%m-%d', now) == os.date('%Y-%m-%d', mtime) then
    return os.date('%H:%M', mtime)
  end
  if os.date('%Y', now) == os.date('%Y', mtime) then
    return os.date('%m-%d', mtime)
  end
  return os.date('%Y-%m-%d', mtime)
end

local function change_summary(fm)
  local parts = {}
  if fm.status   and fm.status   ~= '' then table.insert(parts, 'status: '   .. fm.status) end
  if fm.progress and fm.progress ~= '' then table.insert(parts, 'progress: ' .. fm.progress) end
  if fm.assignee and fm.assignee ~= '' then table.insert(parts, 'assignee: ' .. fm.assignee) end
  if fm.time     and fm.time     ~= '' then table.insert(parts, 'time: '     .. fm.time) end
  if #parts == 0 then return 'no field change' end
  return table.concat(parts, ', ')
end

local function first_body_line(body)
  for _, ln in ipairs(vim.split(body, '\n', { plain = true })) do
    if vim.trim(ln) ~= '' then
      if #ln > 80 then return ln:sub(1, 77) .. '...' end
      return ln
    end
  end
  return ''
end

local function id_line_label(fm)
  if fm.id and fm.id ~= '' then
    local text = 'id: ' .. fm.id
    if #text > 60 then return text:sub(1, 60) end
    return text
  end
  return '(unknown)'
end

---Render the buffer contents. Returns (lines, line_to_entry, cursor_lnum).
local function render(entries, drafts_dir)
  local lines = {}
  local line_to_entry = {}

  table.insert(lines, ('Pending Redmine posts — %s  (%d)'):format(drafts_dir or '<unknown>', #entries))

  if #entries == 0 then
    table.insert(lines, '')
    table.insert(lines, 'No pending posts.')
    table.insert(lines, ':Rmcomment <id>   — start a new draft')
    table.insert(lines, ':Rminbox          — open inbox (or press i)')
    -- Cursor lands on the first command-line.
    return lines, line_to_entry, 4
  end

  table.insert(lines, '')
  local first_block_lnum = nil
  for _, e in ipairs(entries) do
    local composed = e.composed or fm_mod.split(read_file(e.path) or '')
    local body_line_count = composed.body == '' and 0
      or #vim.split(composed.body, '\n', { plain = true })

    table.insert(lines, ('#%d  %s'):format(e.id, id_line_label(composed.fm)))
    line_to_entry[#lines] = { path = e.path, id = e.id }
    first_block_lnum = first_block_lnum or #lines

    table.insert(lines, ('  [%s]'):format(change_summary(composed.fm)))
    line_to_entry[#lines] = { path = e.path, id = e.id }

    table.insert(lines, ('  > %s  · %d lines · %s'):format(
      first_body_line(composed.body), body_line_count, fmt_mtime(e.mtime)))
    line_to_entry[#lines] = { path = e.path, id = e.id }

    table.insert(lines, '')
  end
  if lines[#lines] == '' then table.remove(lines) end

  return lines, line_to_entry, first_block_lnum or 1
end

function M.refresh(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  local dir = resolve_drafts_dir()
  local entries = list_drafts(dir)
  local lines, line_to_entry, cursor_lnum = render(entries, dir)
  util.set_lines(bufnr, lines)
  state.line_to_entry = line_to_entry
  state.entries = entries
  local win = vim.fn.bufwinid(bufnr)
  if win ~= -1 and cursor_lnum then
    pcall(vim.api.nvim_win_set_cursor, win, { math.min(cursor_lnum, math.max(#lines, 1)), 0 })
  end
end

local function entry_under_cursor()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return nil end
  -- Prefer the active window when it displays the pending buffer. The same
  -- buffer can be shown in several windows with independent cursors; reading
  -- via bufwinid() returns whichever happens to be first and would target
  -- the wrong row when the user invoked the keymap from a different split.
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= state.bufnr then
    win = vim.fn.bufwinid(state.bufnr)
    if win == -1 then return nil end
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  return state.line_to_entry[cursor[1]]
end

local function refresh_self()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    M.refresh(state.bufnr)
  end
end

-- ---- Action entry points (exposed for keymaps + tests). --------------------

function M.open_under_cursor()
  local entry = entry_under_cursor()
  if not entry then
    notify('이 줄에는 draft 가 없습니다')
    return
  end
  -- Open the path captured at listing time, not a re-resolved-from-id path.
  -- The two diverge when nvim's cwd changes between listing and `<CR>` —
  -- using the captured path keeps us inside the listing's worktree.
  require('redmine.ui.compose').open_path(entry.path, entry.id)
end

function M.post_under_cursor()
  local entry = entry_under_cursor()
  if not entry then
    notify('이 줄에는 draft 가 없습니다')
    return
  end
  require('redmine.ui.compose').post_file(entry.path, {
    on_done = function(ok) if ok then refresh_self() end end,
  })
end

function M.discard_under_cursor()
  local entry = entry_under_cursor()
  if not entry then
    notify('이 줄에는 draft 가 없습니다')
    return
  end
  local choice = vim.fn.confirm(('Discard draft for #%d?'):format(entry.id),
    '&Yes\n&No', 2)
  if choice == 1 then
    vim.fn.delete(entry.path)
    refresh_self()
  end
end

local function post_sequential(entries, on_complete)
  local posted, failed = 0, 0
  local compose = require('redmine.ui.compose')
  local i = 0
  local function step()
    i = i + 1
    if i > #entries then
      notify(('post 완료: %d posted, %d failed'):format(posted, failed),
        failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
      if on_complete then on_complete(posted, failed) end
      return
    end
    local e = entries[i]
    compose.post_file(e.path, {
      no_confirm = true,
      on_done = function(ok)
        if ok then
          posted = posted + 1
        else
          failed = failed + 1
          notify(('draft 실패: %s'):format(e.path), vim.log.levels.ERROR)
        end
        step()
      end,
    })
  end
  step()
end

---Post every draft currently in the drafts dir. Sequential, fail-soft.
---@param opts table|nil  {no_confirm, entries?: list}
---  `entries` overrides cwd-based discovery — used by the pending buffer to
---  pin post-all to the worktree the user is looking at, even if cwd has
---  drifted since the buffer was rendered.
function M.post_all(opts)
  opts = opts or {}
  local entries = opts.entries
  if not entries then
    local dir = resolve_drafts_dir()
    if not dir then
      notify('drafts 경로 결정 실패', vim.log.levels.ERROR)
      return
    end
    entries = list_drafts(dir)
  end
  if #entries == 0 then
    notify('pending 드래프트가 없습니다')
    return
  end
  local cfg = config.get().compose or {}
  local function run()
    post_sequential(entries, function(_p, _f) refresh_self() end)
  end
  if opts.no_confirm or cfg.confirm_post == false then
    run()
    return
  end
  vim.ui.input({
    prompt = ('%d개의 draft 를 post 합니다. 진행할까요? (y/N) '):format(#entries),
  }, function(ans)
    if ans and (ans:lower() == 'y' or ans:lower() == 'yes') then
      run()
    else
      notify('post 취소')
    end
  end)
end

---Post every draft listed in the pending buffer's last render. Use this from
---the pending buffer's `P` keymap (and pending-focused `:Rmpost`) so cwd
---changes since render don't reroute the post to a different worktree.
function M.post_listed(opts)
  opts = opts or {}
  -- Filter to entries whose file still exists (a draft may have been
  -- archived or deleted between render and `P`).
  local snapshot = {}
  for _, e in ipairs(state.entries or {}) do
    if vim.fn.filereadable(e.path) == 1 then
      table.insert(snapshot, e)
    end
  end
  M.post_all({ no_confirm = opts.no_confirm, entries = snapshot })
end

---Post the draft file for a specific id. ERROR if no such file.
---Defers path resolution to the CLI so a custom `[paths].draft_file` template
---in redmine-core's config.toml is honored.
function M.post_id(id, opts)
  opts = opts or {}
  local cli = config.get().cli or 'redmine'
  local raw = vim.fn.system({ cli, 'path', 'draft', '--id', tostring(id) })
  if vim.v.shell_error ~= 0 then
    notify(('#%s 의 draft 경로 결정 실패'):format(tostring(id)), vim.log.levels.ERROR)
    return
  end
  local path = vim.trim((raw:gsub('\n.*$', '')))
  if path == '' or vim.fn.filereadable(path) == 0 then
    notify(('#%s 의 draft 가 없습니다: %s'):format(tostring(id), path), vim.log.levels.ERROR)
    return
  end
  require('redmine.ui.compose').post_file(path, {
    no_confirm = opts.no_confirm,
    on_done = function(ok) if ok then refresh_self() end end,
  })
end

---List ids of currently-pending drafts. Used by `:Rmpost` completion.
function M.draft_ids()
  local dir = resolve_drafts_dir()
  if not dir then return {} end
  local out = {}
  for _, e in ipairs(list_drafts(dir)) do
    table.insert(out, tostring(e.id))
  end
  return out
end

local function bind_keys(bufnr)
  local km = (config.get().keymaps or {}).pending_buffer or {}
  util.bmap(bufnr, km.close,    function() pcall(vim.api.nvim_buf_delete, bufnr, { force = false }) end, 'redmine: close pending')
  util.bmap(bufnr, km.refresh,  function() M.refresh(bufnr) end, 'redmine: refresh pending')
  util.bmap(bufnr, km.open,     M.open_under_cursor,    'redmine: open draft under cursor')
  util.bmap(bufnr, km.post,     M.post_under_cursor,    'redmine: post draft under cursor')
  util.bmap(bufnr, km.post_all, function() M.post_listed() end, 'redmine: post all drafts')
  util.bmap(bufnr, km.discard,  M.discard_under_cursor, 'redmine: discard draft under cursor')
  util.bmap(bufnr, km.inbox,    function() vim.cmd('Rminbox') end, 'redmine: open inbox')
end

function M.open()
  local strategy = (config.get().ui or {}).pending_strategy or 'edit'
  local _, bufnr, _ = util.open_buffer(BUF_NAME, strategy)
  state.bufnr = bufnr
  -- Always re-apply; idempotent and survives nvim-tree wipe-and-recreate.
  util.lock_buffer(bufnr, 'redmine-pending')
  bind_keys(bufnr)
  M.refresh(bufnr)
end

return M
