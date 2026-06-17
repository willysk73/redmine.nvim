local M = {}

---Apply buffer-local options consistently across our buffer types.
function M.lock_buffer(bufnr, filetype)
  vim.api.nvim_set_option_value('filetype', filetype, { buf = bufnr })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })
  -- 'hide' (not 'wipe') so a transient un-display under nvim-tree or
  -- similar doesn't destroy our virtual buffer and force a re-fetch on
  -- every re-display.
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = bufnr })
  vim.api.nvim_set_option_value('swapfile', false, { buf = bufnr })
  vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
end

---Render lines into a buffer that we may have locked previously.
function M.set_lines(bufnr, lines)
  vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
end

---Map a buffer-local key (no-op if `lhs` is false/nil — supports user opt-out).
function M.bmap(bufnr, lhs, rhs, desc)
  if lhs == nil or lhs == false or lhs == '' then return end
  vim.keymap.set('n', lhs, rhs, { buffer = bufnr, nowait = true, silent = true, desc = desc })
end

---Find a buffer by exact name. Returns -1 when no buffer has that name.
function M.find_buf_by_name(name)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(bufnr) == name then
      return bufnr
    end
  end
  return -1
end

---Reuse-or-create pattern. Returns (winid, bufnr, created).
---If a buffer named `name` exists, just focus its window (creating one if needed).
function M.open_buffer(name, strategy)
  local existing = M.find_buf_by_name(name)
  if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then
    -- Focus an existing window or open a new split for it.
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == existing then
        vim.api.nvim_set_current_win(win)
        return win, existing, false
      end
    end
    -- Open it via the requested strategy.
    if strategy == 'vsplit' then vim.cmd('vsplit')
    elseif strategy == 'tab' then vim.cmd('tabnew')
    elseif strategy == 'edit' then vim.cmd('enew')
    else vim.cmd('split') end
    vim.api.nvim_set_current_buf(existing)
    return vim.api.nvim_get_current_win(), existing, false
  end

  -- Use `:new` / `:vnew` (not `:split` / `:vsplit`) — the latter share the
  -- current buffer between both windows, so the subsequent
  -- `nvim_buf_set_name` would rename the existing buffer and both panes
  -- would show the new content. `:new` / `:vnew` allocate a fresh buffer
  -- in the new window. `noswapfile` suppresses the dialog when a stale
  -- `redmine://*.swp` from a crashed prior nvim exists on disk.
  if strategy == 'vsplit' then vim.cmd('noswapfile vnew')
  elseif strategy == 'tab' then vim.cmd('noswapfile tabnew')
  elseif strategy == 'edit' then vim.cmd('noswapfile enew')
  else vim.cmd('noswapfile new') end
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value('swapfile', false, { buf = bufnr })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })
  vim.api.nvim_buf_set_name(bufnr, name)
  return vim.api.nvim_get_current_win(), bufnr, true
end

return M
