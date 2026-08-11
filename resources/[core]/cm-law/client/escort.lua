-- cm-law contextual cuffed-suspect interaction (E / Backspace). Additive on
-- top of the G-menu's own Grab/Release/Put in Vehicle/Take Out options
-- (client/gmenu.lua, server/cuffs.lua) -- ported from
-- cm-police/client/escort.lua, adapted to ox_lib's lib.showTextUI instead
-- of cm-police's own custom PoliceShowHint toolkit (cm-law doesn't have
-- one, and everything else in this resource already uses ox_lib for UI).

local function eligible()
    if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
    local state = LocalPlayer.state.cmLegalOrg
    if type(state) ~= 'table' or state.onDuty ~= true then return false end
    local permissions = state.permissions or {}
    return state.isLeader == true or permissions['law.cuff'] == true
end

local function fireExtension(targetServerId, action)
    TriggerServerEvent('cm-playerdata:server:extensionInteraction', targetServerId, action, {})
end

local function nearestCuffedPlayer(myCoords, maxDistance)
    local myPlayerId = PlayerId()
    local closestServerId, closestDist = nil, maxDistance
    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= myPlayerId then
            local targetPed = GetPlayerPed(playerId)
            if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
                local serverId = GetPlayerServerId(playerId)
                if Player(serverId).state.cmCuffed == true then
                    local dist = #(myCoords - GetEntityCoords(targetPed))
                    if dist <= closestDist then closestServerId, closestDist = serverId, dist end
                end
            end
        end
    end
    return closestServerId
end

local function nearbySeatedCuffedPlayer(myCoords, maxDistance)
    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local targetPed = GetPlayerPed(playerId)
            if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) and IsPedInAnyVehicle(targetPed, false) then
                local serverId = GetPlayerServerId(playerId)
                if Player(serverId).state.cmCuffed == true then
                    local vehicle = GetVehiclePedIsIn(targetPed, false)
                    if vehicle ~= 0 and #(myCoords - GetEntityCoords(vehicle)) <= maxDistance then return serverId end
                end
            end
        end
    end
    return nil
end

local function nearbyFreeSeatVehicle(myCoords, maxDistance)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and #(myCoords - GetEntityCoords(vehicle)) <= maxDistance then
            local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
            for index = 0, maxSeats - 1 do
                if IsVehicleSeatFree(vehicle, index) then return vehicle end
            end
        end
    end
    return nil
end

local currentPrompt = nil
local promptVisible = false

local function showPrompt(text)
    if lib and lib.showTextUI then lib.showTextUI(text, { position = 'left-center' }) end
    promptVisible = true
end

local function hidePrompt()
    if promptVisible and lib and lib.hideTextUI then lib.hideTextUI() end
    promptVisible = false
end

local function rescan()
    if not eligible() then return nil end

    local myCoords = GetEntityCoords(PlayerPedId())
    local vehicleDistance = Config.Cuffs.VehicleSeatDistance or 6.0

    local seatedTarget = nearbySeatedCuffedPlayer(myCoords, vehicleDistance)
    if seatedTarget then
        showPrompt('[E] Take Suspect Out of Vehicle')
        return { serverId = seatedTarget, primaryAction = 'law_take_out_vehicle' }
    end

    local targetServerId = nearestCuffedPlayer(myCoords, Config.Cuffs.InteractDistance or 2.5)
    if not targetServerId then return nil end

    local escortedBy = Player(targetServerId).state.cmEscortedBy
    local iAmEscorting = type(escortedBy) == 'number' and escortedBy == GetPlayerServerId(PlayerId())
    local anyoneEscorting = type(escortedBy) == 'number' and escortedBy > 0

    if iAmEscorting then
        if nearbyFreeSeatVehicle(myCoords, vehicleDistance) then
            showPrompt('[E] Put Suspect in Vehicle  ·  [Backspace] Release')
            return { serverId = targetServerId, primaryAction = 'law_put_in_vehicle', secondaryAction = 'law_escort_release' }
        end
        showPrompt('[Backspace] Release Suspect')
        return { serverId = targetServerId, secondaryAction = 'law_escort_release' }
    elseif not anyoneEscorting then
        showPrompt('[E] Grab Suspect')
        return { serverId = targetServerId, primaryAction = 'law_escort_grab' }
    end

    return nil
end

CreateThread(function()
    local nextScan = 0
    while true do
        Wait(0)
        local now = GetGameTimer()
        if now >= nextScan then
            nextScan = now + 250
            local next = rescan()
            if not next and currentPrompt then hidePrompt() end
            currentPrompt = next
        end

        if currentPrompt then
            if currentPrompt.primaryAction and IsControlJustPressed(0, 38) then
                fireExtension(currentPrompt.serverId, currentPrompt.primaryAction)
            elseif currentPrompt.secondaryAction and IsControlJustPressed(0, 194) then
                fireExtension(currentPrompt.serverId, currentPrompt.secondaryAction)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and currentPrompt then hidePrompt() end
end)
