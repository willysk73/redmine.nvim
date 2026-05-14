-- Async wrapper for the `redmine` CLI. Spec §11.
local config = require('redmine.config')

local M = {}

local EXIT_AUTH = 11

local function notify_error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = 'redmine' })
end

-- In-memory TTL cache. Opt-in per call via opts.cache.key ('inbox'|'issue').
-- Keyed by env-hash + key + argv tuple so swapping REDMINE_URL / API_KEY
-- mid-session implicitly invalidates (different hash → different bucket).
-- See .ccx/tasks/T-3.md.
local cache_store = {}
local cache_stats = { hits = 0, misses = 0 }

local function now_ms()
  return (vim.uv or vim.loop).now()
end

local env_hash_cache = { url = nil, key = nil, hash = nil }
local function env_hash()
  local url = vim.env.REDMINE_URL or ''
  local key = vim.env.REDMINE_API_KEY or ''
  if env_hash_cache.url == url and env_hash_cache.key == key and env_hash_cache.hash then
    return env_hash_cache.hash
  end
  -- Length-prefix the URL so distinct (url, key) pairs can't alias.
  -- A plain delimiter is unsafe because the delimiter character may
  -- already appear inside a URL or token (e.g. url='a:b', key='c' would
  -- collide with url='a', key='b:c' under a `:` separator). The brief
  -- proposed '\0' but Neovim marshals NUL-containing Lua strings to
  -- vim.fn as Blobs, which sha256 rejects.
  local h = vim.fn.sha256(tostring(#url) .. ':' .. url .. key):sub(1, 16)
  env_hash_cache.url, env_hash_cache.key, env_hash_cache.hash = url, key, h
  return h
end

local function ttl_for(key)
  local c = (config.get().cache or {})
  if key == 'inbox' then return c.inbox_ttl_ms or 0 end
  if key == 'issue' then return c.issue_ttl_ms or 0 end
  return 0
end

local function cache_key_for(key, args)
  -- NUL separator between argv elements so {'a','b\0c'} and {'a\0b','c'}
  -- can't collide. Lua strings are byte-arrays, so this round-trips fine
  -- as a table key.
  return env_hash() .. '|' .. key .. '|' .. table.concat(args, '\0')
end

local function cache_lookup(key, args)
  local cfg = config.get().cache or {}
  if not cfg.enabled then return nil end
  local ttl = ttl_for(key)
  if ttl <= 0 then return nil end
  local entry = cache_store[cache_key_for(key, args)]
  if not entry then return nil end
  if (now_ms() - entry.captured_at_ms) >= ttl then return nil end
  return entry.stdout
end

local function cache_store_write(key, args, stdout)
  local cfg = config.get().cache or {}
  if not cfg.enabled then return end
  if ttl_for(key) <= 0 then return end
  cache_store[cache_key_for(key, args)] = {
    stdout = stdout,
    captured_at_ms = now_ms(),
  }
end

-- Server-mutating subcommands. After a successful run of any of these we
-- drop the issue + inbox caches: the affected views' renderers may not
-- be open (so the existing refresh(id) chain has nothing to fetch), and
-- list-membership can change on status updates. Conservative: clear both
-- buckets rather than tracking which one each subcommand affects.
local MUTATING_SUBCOMMANDS = {
  update = true,
  post   = true,
  assign = true,
  log    = true,
}

-- Bumped every time the cache is dropped. In-flight cached fetches capture
-- this value at request start and only write back if it still matches at
-- completion — otherwise a mutation that cleared the cache mid-flight
-- would be undone by the older, pre-mutation payload landing late.
local cache_generation = 0

local function cache_drop_all()
  cache_store = {}
  cache_generation = cache_generation + 1
end

local function cache_evict(key, args)
  cache_store[cache_key_for(key, args)] = nil
end

---@class RedmineCacheOpts
---@field key 'inbox'|'issue'|nil  bucket name; nil means do not cache
---@field hard boolean|nil          true → evict any existing entry, bypass
---                                 lookup, and skip the write back. The
---                                 fetch is one-off uncached.

---Run the CLI asynchronously.
---@param args string[]   subcommand + flags (e.g. {'fetch', '1', '--format=display'})
---@param opts table|nil  {cache = {key, hard}, on_error = fun(code, stderr)}
---@param on_done fun(stdout: string)
function M.run(args, opts, on_done)
  opts = opts or {}
  local cache_opts = opts.cache
  local cache_key = cache_opts and cache_opts.key or nil
  local hard = cache_opts and cache_opts.hard or false

  local request_generation = cache_generation

  if cache_key then
    if not hard then
      local hit = cache_lookup(cache_key, args)
      if hit ~= nil then
        cache_stats.hits = cache_stats.hits + 1
        vim.schedule(function() on_done(hit) end)
        return
      end
    else
      -- Hard refresh: drop any existing entry up front so a stale value
      -- can't outlive the bypassed fetch, AND bump the generation so an
      -- older in-flight cached fetch can't write its pre-hard payload
      -- back after we've evicted. The write below is also skipped, so
      -- `hard=true` is a genuine one-off uncached request — the next
      -- cached `r` will miss and re-fetch.
      cache_evict(cache_key, args)
      cache_generation = cache_generation + 1
    end
    cache_stats.misses = cache_stats.misses + 1
  end

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
      -- Write only on the normal (non-hard) cached path. `hard=true`
      -- already evicted the entry up front and stays uncached, so the
      -- next `r` will miss & re-fetch. Errors (handled above) bypass
      -- write — `exit_code == 0` only. Skip the write if a mutation
      -- ran between request-start and now (generation bump) — otherwise
      -- the pre-mutation payload would resurrect the stale entry.
      if cache_key and not hard then
        if request_generation == cache_generation then
          cache_store_write(cache_key, args, obj.stdout or '')
        end
      elseif not cache_key and MUTATING_SUBCOMMANDS[args[1] or ''] then
        cache_drop_all()
      end
      on_done(obj.stdout or '')
    end)
  end)
end

---Like run() but parses stdout as JSON. opts is optional; if the second arg
---is callable, it's treated as on_done (back-compat with existing 2-arg
---callers outside this task's scope).
---@param args string[]
---@param opts table|fun(any)|nil
---@param on_done fun(any)|nil
function M.run_json(args, opts, on_done)
  if type(opts) == 'function' then
    on_done, opts = opts, nil
  end
  opts = opts or {}

  local with_flag = vim.deepcopy(args)
  local has_json = false
  for _, a in ipairs(with_flag) do
    if a == '--json' then has_json = true; break end
  end
  if not has_json then table.insert(with_flag, '--json') end

  M.run(with_flag, opts, function(stdout)
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

---Return a shallow copy of cache hit/miss counters. Used by tests and
---:checkhealth redmine.
function M.cache_stats()
  return { hits = cache_stats.hits, misses = cache_stats.misses }
end

return M
