-- Issue detail buffer. Spec §7.2.
local cli = require('redmine.cli')
local config = require('redmine.config')
local util = require('redmine.util')

local M = {}

local generations = {}

local function buf_name(id)
  return ('redmine://issue/%d'):format(id)
end

-- Section headers in CLI render output start with `▾` (open by default)
-- or `▸` (closed by default). Return `>1` on those lines and on line 1
-- (the pre-section header block) so each section becomes its own
-- top-level fold; every other line returns `1` so it joins the current
-- fold.
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  if line:match('^▾ ') or line:match('^▸ ') then
    return '>1'
  end
  if lnum == 1 then
    return '>1'
  end
  return '1'
end

-- Show the raw section header. The CLI title already carries the count
-- (e.g. `▾ 코멘트 (7)`), so default `+-- N lines:` boilerplate is noise.
function M.foldtext()
  return vim.fn.getline(vim.v.foldstart)
end

local folding_group = vim.api.nvim_create_augroup('redmine.ui.issue.folding', { clear = true })

-- FileType: initial filetype set during lock_buffer. Resets foldlevel
-- so the brand-new window opens with sections visible (`▾` open).
-- BufWinEnter: any later window display of an existing issue buffer
-- (split, `:b redmine://issue/N`, tab switch). Sets only the fold
-- machinery — NOT foldlevel — so the user's manual zM/zm state survives
-- ordinary window switches. Tradeoff: `:b redmine://issue/N` in a
-- window whose previous buffer was zM'd will inherit that foldlevel
-- and show sections closed; the user can press `r` to refresh, which
-- restores defaults via apply_initial_folds. Brief Decisions accept
-- "refresh re-applies defaults" and forbid extra bookkeeping for
-- fold-state preservation.
vim.api.nvim_create_autocmd('FileType', {
  group = folding_group,
  pattern = 'redmine-issue',
  callback = function()
    vim.opt_local.foldmethod = 'expr'
    vim.opt_local.foldexpr = 'v:lua.require("redmine.ui.issue").foldexpr(v:lnum)'
    vim.opt_local.foldtext = 'v:lua.require("redmine.ui.issue").foldtext()'
    vim.opt_local.foldlevel = 99
  end,
})
vim.api.nvim_create_autocmd('BufWinEnter', {
  group = folding_group,
  callback = function(args)
    if vim.bo[args.buf].filetype ~= 'redmine-issue' then return end
    vim.opt_local.foldmethod = 'expr'
    vim.opt_local.foldexpr = 'v:lua.require("redmine.ui.issue").foldexpr(v:lnum)'
    vim.opt_local.foldtext = 'v:lua.require("redmine.ui.issue").foldtext()'
  end,
})

-- Reset fold state after a render: open everything (foldlevel high),
-- then close every section whose header starts with `▸`. Re-applied on
-- every render so `r`/`R` deliberately restore defaults — preserving
-- per-section state across refreshes was a non-goal (see T-2 brief).
-- Iterates real windows showing the buffer (across all tabpages) so the
-- compose→refresh path, which fires while the issue buffer is not
-- current, still applies window-local fold state to the correct window
-- rather than to a scratch autocmd window.
local function apply_initial_folds(bufnr, lines)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.api.nvim_win_call(winid, function()
      vim.wo.foldlevel = 99
      for lnum, line in ipairs(lines) do
        if line:match('^▸ ') then
          pcall(vim.cmd, lnum .. 'foldclose')
        end
      end
    end)
  end
end

local function bind_keys(bufnr, id)
  local km = config.get().keymaps.issue_buffer or {}

  util.bmap(bufnr, km.close, function()
    pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
  end, 'redmine: close issue')

  util.bmap(bufnr, km.refresh, function()
    M.refresh(id, { hard = false })
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
  generations[id] = (generations[id] or 0) + 1
  local gen = generations[id]
  util.set_lines(bufnr, { ('⏳ Fetching #%d ...'):format(id) })

  local args = { 'fetch', tostring(id), '--format=display' }
  local run_opts = { cache = { key = 'issue', hard = opts.hard or false } }

  cli.run(args, run_opts, function(stdout)
    if gen ~= generations[id] then return end
    -- See inbox.lua: a tree-style plugin can replace bufnr mid-flight.
    local target = vim.api.nvim_buf_is_valid(bufnr) and bufnr or util.find_buf_by_name(buf_name(id))
    if not target or target == -1 or not vim.api.nvim_buf_is_valid(target) then return end
    -- If replaced, the new buffer has no keymaps — re-apply.
    if target ~= bufnr then
      util.lock_buffer(target, 'redmine-issue')
      bind_keys(target, id)
    end
    local lines = vim.split(stdout, '\n', { plain = true })
    -- Trim a single trailing blank line if present (CLI emits a final \n).
    if #lines > 0 and lines[#lines] == '' then
      table.remove(lines)
    end
    util.set_lines(target, lines)
    apply_initial_folds(target, lines)
  end)
end

function M.open(id)
  local strategy = config.get().ui.open_strategy or 'split'
  local _, bufnr, _ = util.open_buffer(buf_name(id), strategy)
  -- Always re-apply; idempotent and survives nvim-tree wipe-and-recreate.
  util.lock_buffer(bufnr, 'redmine-issue')
  bind_keys(bufnr, id)
  render(bufnr, id)
end

-- External callers (compose.lua, actions.lua) call refresh(id) with no
-- opts after mutating the issue; in that case default to a hard refresh so
-- post-mutation views never serve stale cache. The `r` keymap above
-- explicitly passes {hard=false} to opt back into the cache.
function M.refresh(id, opts)
  if opts == nil then opts = { hard = true } end
  local name = buf_name(id)
  local bufnr = util.find_buf_by_name(name)
  if bufnr == -1 then return end
  render(bufnr, id, opts)
end

return M
