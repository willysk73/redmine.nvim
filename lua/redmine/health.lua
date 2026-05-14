local M = {}

local h = vim.health
local h_start = h.start or h.report_start
local h_ok    = h.ok    or h.report_ok
local h_warn  = h.warn  or h.report_warn
local h_error = h.error or h.report_error
local h_info  = h.info  or h.report_info

local MIN_CLI_VERSION = '0.1.1'

local function parse_semver(s)
  local t = {}
  for n in s:gmatch('(%d+)') do t[#t + 1] = tonumber(n) end
  return t
end

local function semver_lt(a, b)
  local pa, pb = parse_semver(a), parse_semver(b)
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y end
  end
  return false
end

local function run(argv, timeout_ms)
  local p = vim.system(argv, { text = true }):wait(timeout_ms or 4000)
  return p.code, vim.trim(p.stdout or ''), vim.trim(p.stderr or '')
end

local PLACEHOLDER_URLS = {
  ['https://redmine.example.com'] = true,
  ['http://redmine.example.com']  = true,
}

function M.check()
  h_start('redmine.nvim')

  if vim.fn.executable('redmine') ~= 1 then
    h_error('`redmine` CLI not found in $PATH', {
      'pipx install redmine-core',
      '또는 sibling repo 에서 `pip install -e /path/to/redmine-core`',
    })
    return
  end

  local rc, out, errout = run({ 'redmine', '--version' }, 3000)
  if rc ~= 0 then
    h_error('`redmine --version` failed (exit ' .. rc .. ')', { errout ~= '' and errout or out })
    return
  end
  local ver = out:match('redmine%-core%s+(%S+)') or out
  if semver_lt(ver, MIN_CLI_VERSION) then
    h_warn(('redmine-core %s < required %s'):format(ver, MIN_CLI_VERSION),
      { 'pip install -U redmine-core' })
  else
    h_ok(('redmine-core %s'):format(ver))
  end

  local url = vim.env.REDMINE_URL
  local key = vim.env.REDMINE_API_KEY

  if not url or url == '' then
    h_info('REDMINE_URL env not set (CLI will fall back to ~/.config/redmine-core/config.toml)')
  elseif PLACEHOLDER_URLS[url] or url:match('redmine%.example%.com') then
    h_error('REDMINE_URL is the placeholder ("' .. url .. '")', {
      'shell rc / ~/.secrets 의 placeholder 를 실제 URL 로 교체 후 nvim 재시작',
    })
  else
    h_ok('REDMINE_URL = ' .. url)
  end

  if not key or key == '' then
    h_info('REDMINE_API_KEY env not set (CLI will fall back to config.toml)')
  elseif key == 'your-api-key-here' or key:match('^your%-') then
    h_error('REDMINE_API_KEY is the placeholder', {
      '실제 API 키로 교체 후 nvim 재시작',
    })
  else
    h_ok(('REDMINE_API_KEY set (%d chars)'):format(#key))
  end

  local cache_cfg = (require('redmine.config').get().cache) or {}
  if cache_cfg.enabled then
    h_ok(('cache: enabled (inbox_ttl=%ds, issue_ttl=%ds)'):format(
      math.floor((cache_cfg.inbox_ttl_ms or 0) / 1000),
      math.floor((cache_cfg.issue_ttl_ms or 0) / 1000)))
  else
    h_ok('cache: disabled')
  end

  local rc2, out2, err2 = run({ 'redmine', 'whoami' }, 5000)
  if rc2 == 0 then
    h_ok('whoami → ' .. out2)
  elseif rc2 == 11 then
    h_error('auth failed (exit 11)', { err2 ~= '' and err2 or out2, '`redmine whoami` 로 직접 확인' })
  else
    h_warn(('whoami failed (exit %d)'):format(rc2), {
      err2 ~= '' and err2 or out2,
      '도커 stack 이 떠있는지: docker ps | grep redmine',
    })
  end
end

return M
