-- Tiny frontmatter splitter, mirrors redmine-core/redmine_core/frontmatter.py.
-- Used only for the post-confirmation preview; CLI re-parses authoritatively.
local M = {}

local CUTOFF_LUA = '^<!%-%-.*━━━.*%-%->%s*$'

---@class redmine.Composed
---@field fm    table<string,string|nil>
---@field body  string  -- between frontmatter and cutoff, trimmed
---@field cutoff_line integer|nil  -- 1-based line number of cutoff, or nil

function M.split(text, opts)
  opts = opts or {}
  local cutoff_pat = opts.cutoff_pattern or CUTOFF_LUA

  local lines = vim.split(text, '\n', { plain = true })
  local fm = {}
  local body_start = 1

  if lines[1] and vim.trim(lines[1]) == '---' then
    for i = 2, #lines do
      if vim.trim(lines[i]) == '---' then
        for j = 2, i - 1 do
          local key, value = lines[j]:match('^([^:]+):(.*)$')
          if key then
            local k = vim.trim(key):lower()
            local v = vim.trim(value)
            if v == '' then v = nil end
            fm[k] = v
          end
        end
        body_start = i + 1
        break
      end
    end
  end

  local cutoff_line = nil
  local body_end = #lines
  for i = body_start, #lines do
    if lines[i]:match(cutoff_pat) then
      cutoff_line = i
      body_end = i - 1
      break
    end
  end

  local body_lines = {}
  for i = body_start, body_end do
    table.insert(body_lines, lines[i])
  end
  local body = vim.trim(table.concat(body_lines, '\n'))
  return { fm = fm, body = body, cutoff_line = cutoff_line }
end

---First N non-empty lines of body, for the confirm preview.
function M.body_preview(body, n)
  n = n or 5
  local out = {}
  for _, ln in ipairs(vim.split(body, '\n', { plain = true })) do
    if vim.trim(ln) ~= '' then
      table.insert(out, ln)
      if #out >= n then break end
    end
  end
  return out
end

return M
