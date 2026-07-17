-- cm-family | client/cl_chat.lua
local function hexToRgb(hex)
    hex = tostring(hex or '#00f0ff'):gsub('#', '')
    if #hex ~= 6 then return { 0, 240, 255 } end
    return {
        tonumber(hex:sub(1, 2), 16) or 0,
        tonumber(hex:sub(3, 4), 16) or 240,
        tonumber(hex:sub(5, 6), 16) or 255,
    }
end

RegisterNetEvent('cm-family:client:familyChat', function(data)
    -- cm-chat owns the polished FAMILY channel when installed. This handler is
    -- only a compatibility fallback for servers using the default GTA chat.
    if GetResourceState('cm-chat') == 'started' then return end
    if type(data) ~= 'table' then return end
    local tag = tostring(data.tag or 'FAMILY')
    local role = tostring(data.title or data.rankName or 'Member')
    local author = ('[%s] [%s] %s (%s)'):format(tag, role, tostring(data.name or 'Unknown'), tostring(data.characterId or '?'))
    TriggerEvent('chat:addMessage', {
        color = hexToRgb(data.color),
        multiline = true,
        args = { author, tostring(data.message or '') },
    })
end)
