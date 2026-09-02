-- cm-law/client/tracking.lua
-- Member map blips and meeting points for legal organizations.
--
-- cm-ems and cm-police have had both since the beginning; cm-law never did --
-- no tracking module, no permissions, no dashboard buttons. This closes that
-- gap using the same shape as cm-police/client/tracking.lua.
--
-- The one real difference: cm-law is multi-organization. A SAHP supervisor
-- must only see SAHP members and must only be able to route SAHP to a meeting
-- point, so every broadcast is scoped server-side by organization_id (see
-- server/tracking.lua). This file never decides who is visible -- it only
-- draws what the server sent.

local blips = {}
local meetingBlip
local enabled = false

local function clearMembers()
    for _, blip in pairs(blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    blips = {}
end

local function state()
    local value = LocalPlayer.state.cmLegalOrg
    return type(value) == 'table' and value or nil
end

local function canViewMap()
    local current = state()
    if not current then return false end
    if current.isLeader then return true end
    return type(current.permissions) == 'table' and current.permissions['law.view_member_map'] == true
end

function CMLawTrackingToggle()
    if not canViewMap() then
        if lib then lib.notify({ title = 'Legal', description = 'Your rank cannot view members on the map.', type = 'error' }) end
        return nil
    end
    enabled = not enabled
    if not enabled then clearMembers() end
    if lib then
        lib.notify({
            title = 'Legal',
            description = enabled and 'Member map enabled.' or 'Member map disabled.',
            type = 'success',
        })
    end
    return enabled
end

-- The server pushes positions on its own cadence; we only render while the
-- local player has the map switched on, so a member who toggles off stops
-- paying any drawing cost even though the broadcast continues.
RegisterNetEvent('cm-law:client:memberPositions', function(members)
    if not enabled or type(members) ~= 'table' then return end
    local seen = {}
    for _, member in ipairs(members) do
        local cid = tostring(member.characterId or '')
        local x, y, z = tonumber(member.x), tonumber(member.y), tonumber(member.z)
        if cid ~= '' and x and y and z then
            seen[cid] = true
            local blip = blips[cid]
            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(x + 0.0, y + 0.0, z + 0.0)
                SetBlipSprite(blip, 1)
                SetBlipScale(blip, 0.75)
                SetBlipAsShortRange(blip, false)
                blips[cid] = blip
            end
            SetBlipCoords(blip, x + 0.0, y + 0.0, z + 0.0)
            SetBlipColour(blip, member.onDuty and 3 or 4)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(tostring(member.name or 'Member'))
            EndTextCommandSetBlipName(blip)
        end
    end
    -- Drop anyone who went off duty or disconnected since the last push.
    for cid, blip in pairs(blips) do
        if not seen[cid] then
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            blips[cid] = nil
        end
    end
end)

RegisterNetEvent('cm-law:client:setMeetingPoint', function(data)
    if type(data) ~= 'table' or not tonumber(data.x) or not tonumber(data.y) then return end
    if meetingBlip and DoesBlipExist(meetingBlip) then RemoveBlip(meetingBlip) end
    meetingBlip = AddBlipForCoord(tonumber(data.x) + 0.0, tonumber(data.y) + 0.0, (tonumber(data.z) or 0.0) + 0.0)
    SetBlipSprite(meetingBlip, 280)
    SetBlipColour(meetingBlip, 3)
    SetBlipScale(meetingBlip, 0.9)
    SetBlipRoute(meetingBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(tostring(data.label or 'Meeting point'))
    EndTextCommandSetBlipName(meetingBlip)
    SetNewWaypoint(tonumber(data.x) + 0.0, tonumber(data.y) + 0.0)
    if lib then
        lib.notify({
            title = 'Meeting point',
            description = ('%s set a meeting point.'):format(tostring(data.setterName or 'Command')),
            type = 'inform',
        })
    end
end)

RegisterNetEvent('cm-law:client:clearMeetingPoint', function()
    if meetingBlip and DoesBlipExist(meetingBlip) then
        SetBlipRoute(meetingBlip, false)
        RemoveBlip(meetingBlip)
    end
    meetingBlip = nil
    if lib then lib.notify({ title = 'Meeting point', description = 'Meeting point cleared.', type = 'inform' }) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearMembers()
    if meetingBlip and DoesBlipExist(meetingBlip) then RemoveBlip(meetingBlip) end
end)
