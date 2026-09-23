--[[ Contains server-side helper functions. ]]

local Utils = {}

---@param source number
---@param title string
---@param type string
---@param description string
---@param duration number
function Utils.server_notify(source, title, type, description, duration)
    TriggerClientEvent("client:farming-v2:notify", source, title, type, description, duration)
end

return Utils
