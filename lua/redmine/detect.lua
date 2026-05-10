-- Issue id detection. Spec §10.
local M = {}

---@param callback fun(id: integer|nil)
function M.current(callback)
  require('redmine.cli').run_allow_fail({ 'detect' }, function(code, stdout, _)
    if code ~= 0 then
      callback(nil)
      return
    end
    local id = tonumber(vim.trim(stdout))
    callback(id)
  end)
end

return M
