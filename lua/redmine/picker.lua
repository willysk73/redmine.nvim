-- Thin picker wrapper. Currently uses vim.ui.select; spec §4 leaves room
-- for a telescope adapter later (M4).
local M = {}

---@param items table[]            list of items
---@param opts {prompt:string?, label:fun(item):string}
---@param on_choice fun(item: any|nil)
function M.select(items, opts, on_choice)
  opts = opts or {}
  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = opts.label,
  }, function(choice)
    on_choice(choice)
  end)
end

return M
