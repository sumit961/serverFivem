-- ============================================================
--  cm-family | cl_tracking.lua
--  Opt-in nearby family-member minimap blips and static vehicle-location
--  snapshots. No database polling and no continuous remote GPS stream.
-- ============================================================

CMFamilyTracking = CMFamilyTracking or {}
local T = CMFamilyTracking
local MEMBER_KVP = 'cm-family:member-blips-enabled'
local memberBlips = {}
local trackedVehicleBlip = nil
local trackedVehicleExpiresAt = 0
local meetingPointBlip = nil
local meetingPointExpiresAt = 0

local function clearMeetingPoint()
    ClearGpsMultiRoute()
    if meetingPointBlip and DoesBlipExist(meetingPointBlip) then
        RemoveBlip(meetingPointBlip)
    end
    meetingPointBlip = nil
    meetingPointExpiresAt = 0
end

-- Family meeting waypoints share this established tracking script so the
-- receiver is always registered with the rest of the map functionality.
RegisterNetEvent('cm-family:client:setMeetingPoint', function(data)
    if type(data) ~= 'table' then return end
    local x, y = tonumber(data.x), tonumber(data.y)
    if not x or not y then return end

    clearMeetingPoint()
    meetingPointBlip = AddBlipForCoord(x + 0.0, y + 0.0, (tonumber(data.z) or 0.0) + 0.0)
    SetBlipSprite(meetingPointBlip, 280)
    SetBlipColour(meetingPointBlip, 5)
    SetBlipScale(meetingPointBlip, 0.9)
    SetBlipAsShortRange(meetingPointBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Family meeting point')
    EndTextCommandSetBlipName(meetingPointBlip)
    -- Yellow GPS route from the player, explicitly rendered while on foot.
    StartGpsMultiRoute(10, true, true)
    AddPointToGpsMultiRoute(x + 0.0, y + 0.0, (tonumber(data.z) or 0.0) + 0.0)
    SetGpsMultiRouteRender(true)
    meetingPointExpiresAt = GetGameTimer() + 240000
    PlaySoundFrontend(-1, 'WAYPOINT_SET', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)

    local setter = tostring(data.setterName or 'A family member')
    if lib and lib.notify then
        lib.notify({
            title = 'Family meeting point',
            description = setter .. ' set a meeting point. Your GPS has been updated.',
            type = 'inform',
            duration = 7000,
        })
    end
end)

local function cfg(path, fallback)
    local node = Config and Config.Tracking
    for part in tostring(path):gmatch('[^.]+') do
        node = type(node) == 'table' and node[part] or nil
    end
    return node ~= nil and node or fallback
end

local function notify(message, kind)
    if lib and lib.notify then
        lib.notify({ description = tostring(message), type = kind or 'inform' })
    end
end

function T.IsMemberBlipsEnabled()
    local saved = GetResourceKvpInt(MEMBER_KVP)
    if saved == 1 then return true end
    if saved == 2 then return false end
    return cfg('members.defaultEnabled', false) == true
end

function T.SetMemberBlipsEnabled(enabled)
    enabled = enabled == true
    SetResourceKvpInt(MEMBER_KVP, enabled and 1 or 2)
    if not enabled then
        for serverId, blip in pairs(memberBlips) do
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            memberBlips[serverId] = nil
        end
    end
    notify(enabled and 'Nearby family members are now visible on your minimap.'
        or 'Family member minimap visibility disabled.', enabled and 'success' or 'inform')
    return enabled
end

local function removeMemberBlip(serverId)
    local blip = memberBlips[serverId]
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    memberBlips[serverId] = nil
end

local function sameActiveFamily(serverId, myFamilyId)
    -- Client state bags are keyed by the server ID, while GetActivePlayers()
    -- returns local player indexes. Always convert before reading the state.
    local state = Player(serverId).state
    local family = state and state.cmFamily or nil
    return type(family) == 'table' and family.active == true
        and tonumber(family.id) == tonumber(myFamilyId)
end

CreateThread(function()
    while true do
        local interval = math.max(500, tonumber(cfg('members.updateMs', 1500)) or 1500)
        Wait(interval)

        if cfg('members.enabled', true) ~= true or not T.IsMemberBlipsEnabled() then
            for serverId in pairs(memberBlips) do removeMemberBlip(serverId) end
        else
            local myFamily = LocalPlayer.state.cmFamily
            local myPed = PlayerPedId()
            local myCoords = DoesEntityExist(myPed) and GetEntityCoords(myPed) or nil
            local myFamilyId = type(myFamily) == 'table' and myFamily.active == true and tonumber(myFamily.id) or nil
            local seen = {}

            if myFamilyId and myCoords then
                local maxDistance = tonumber(cfg('members.nearbyDistance', 300.0)) or 300.0
                for _, playerIndex in ipairs(GetActivePlayers()) do
                    if playerIndex ~= PlayerId() then
                        local serverId = GetPlayerServerId(playerIndex)
                        local ped = GetPlayerPed(playerIndex)
                        if serverId and serverId > 0 and DoesEntityExist(ped)
                            and sameActiveFamily(serverId, myFamilyId) then
                            local distance = #(GetEntityCoords(ped) - myCoords)
                            if distance <= maxDistance then
                                seen[serverId] = true
                                local blip = memberBlips[serverId]
                                if not blip or not DoesBlipExist(blip) then
                                    blip = AddBlipForEntity(ped)
                                    memberBlips[serverId] = blip
                                    SetBlipSprite(blip, tonumber(cfg('members.blipSprite', 1)) or 1)
                                    SetBlipColour(blip, tonumber(cfg('members.blipColor', 3)) or 3)
                                    SetBlipScale(blip, tonumber(cfg('members.blipScale', 0.72)) or 0.72)
                                    SetBlipDisplay(blip, 4)
                                    SetBlipAsShortRange(blip, true)
                                    ShowHeadingIndicatorOnBlip(blip, true)
                                    BeginTextCommandSetBlipName('STRING')
                                    AddTextComponentString(tostring(cfg('members.label', 'Family member')))
                                    EndTextCommandSetBlipName(blip)
                                end
                            end
                        end
                    end
                end
            end

            for serverId in pairs(memberBlips) do
                if not seen[serverId] then removeMemberBlip(serverId) end
            end
        end
    end
end)

local function clearTrackedVehicleBlip()
    if trackedVehicleBlip and DoesBlipExist(trackedVehicleBlip) then
        RemoveBlip(trackedVehicleBlip)
    end
    trackedVehicleBlip = nil
    trackedVehicleExpiresAt = 0
end

RegisterNetEvent('cm-family:client:trackVehicleResult', function(location)
    location = type(location) == 'table' and location or nil
    if not location or not tonumber(location.x) or not tonumber(location.y) or not tonumber(location.z) then
        notify(location and location.message or 'The vehicle location is not available.', 'error')
        return
    end

    clearTrackedVehicleBlip()
    trackedVehicleBlip = AddBlipForCoord(tonumber(location.x) + 0.0, tonumber(location.y) + 0.0, tonumber(location.z) + 0.0)
    SetBlipSprite(trackedVehicleBlip, tonumber(cfg('vehicles.blipSprite', 225)) or 225)
    SetBlipColour(trackedVehicleBlip, tonumber(cfg('vehicles.blipColor', 3)) or 3)
    SetBlipScale(trackedVehicleBlip, tonumber(cfg('vehicles.blipScale', 0.85)) or 0.85)
    SetBlipRoute(trackedVehicleBlip, true)
    SetBlipRouteColour(trackedVehicleBlip, tonumber(cfg('vehicles.blipColor', 3)) or 3)
    SetBlipAsShortRange(trackedVehicleBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(tostring(location.label or location.plate or 'Family vehicle'))
    EndTextCommandSetBlipName(trackedVehicleBlip)

    local seconds = math.max(30, tonumber(location.blipDurationSeconds)
        or tonumber(cfg('vehicles.blipDurationSeconds', 300)) or 300)
    trackedVehicleExpiresAt = GetGameTimer() + (seconds * 1000)
    SetNewWaypoint(tonumber(location.x) + 0.0, tonumber(location.y) + 0.0)
    notify(tostring(location.message or 'Family vehicle location marked for five minutes.'), 'success')
end)

CreateThread(function()
    while true do
        Wait(1000)
        if trackedVehicleBlip and trackedVehicleExpiresAt > 0 and GetGameTimer() >= trackedVehicleExpiresAt then
            clearTrackedVehicleBlip()
            notify('Family vehicle tracking marker expired. You may request another location after the cooldown.', 'inform')
        end
        if meetingPointBlip and meetingPointExpiresAt > 0 and GetGameTimer() >= meetingPointExpiresAt then
            clearMeetingPoint()
            notify('The family meeting point has expired.', 'inform')
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for serverId in pairs(memberBlips) do removeMemberBlip(serverId) end
    clearTrackedVehicleBlip()
    clearMeetingPoint()
end)
