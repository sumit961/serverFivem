-- cm-police cuffing & arrest (client).
--
-- Every client runs this file, but it only ever acts on the LOCAL player's
-- own replicated state -- there is no "officer moves the suspect's ped"
-- code path here. When you're cuffed, YOUR OWN client locks your controls
-- and (while cmEscortedBy is set) tasks your cuffed ped to follow behind the
-- escorting officer. The officer's client never
-- touches your ped directly --
-- matches the constraint that FiveM tasks are only reliable when run on the
-- entity's own owning client, which for a player ped is always that
-- player's machine.

local restrainedAnimDict = 'mp_arresting'
local escortFollowing = false
local groundDragActive = false

local function requestAnimDict(dict, timeoutMs)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + (timeoutMs or 2000)
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function playRestrainedIdle()
    local ped = PlayerPedId()
    if not requestAnimDict(restrainedAnimDict) then return end
    if not IsEntityPlayingAnim(ped, restrainedAnimDict, 'idle', 3) then
        TaskPlayAnim(ped, restrainedAnimDict, 'idle', 2.0, -2.0, -1, escortFollowing and 49 or 1, 0.0, false, false, false)
    end
end

local function releaseGroundDrag()
    local ped = PlayerPedId()
    if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
    SetPedCanRagdoll(ped, true)
    SetEntityCollision(ped, true, true)
    -- cmEscortedBy=false can replicate after the seat operation completes.
    -- Clearing tasks at that point ejects the suspect from the vehicle.
    if not IsPedInAnyVehicle(ped, false) then
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
        ClearPedTasksImmediately(ped)
    end
    groundDragActive = false
end

local function beginGroundDrag(officerServerId)
    local officerPlayer = GetPlayerFromServerId(tonumber(officerServerId) or -1)
    local ped = PlayerPedId()
    if officerPlayer == -1 or IsPedInAnyVehicle(ped, false) then return false end
    local officerPed = GetPlayerPed(officerPlayer)
    if officerPed == 0 or not DoesEntityExist(officerPed) then return false end
    if groundDragActive then return true end
    releaseGroundDrag()
    ClearPedTasksImmediately(ped)
    SetPedCanRagdoll(ped, false)
    SetEntityCollision(ped, true, true)
    playRestrainedIdle()
    TaskFollowToOffsetOfEntity(ped, officerPed, 0.0, -1.15, 0.0, 1.2, -1, 0.7, true)
    groundDragActive = true
    return true
end

-- ── Control lock while cuffed ─────────────────────────────────────────────
CreateThread(function()
    while true do
        local cuffed = LocalPlayer.state.cmCuffed == true
        if not cuffed then
            Wait(500)
        else
            local ped = PlayerPedId()
            DisableControlAction(0, 24, true)   -- attack
            DisableControlAction(0, 25, true)   -- aim
            DisableControlAction(0, 45, true)   -- reload
            DisableControlAction(0, 37, true)   -- weapon wheel
            DisableControlAction(0, 140, true)  -- melee light
            DisableControlAction(0, 141, true)  -- melee heavy
            DisableControlAction(0, 142, true)  -- melee alt
            DisableControlAction(0, 257, true)  -- attack 2
            DisableControlAction(0, 263, true)  -- melee attack light
            DisableControlAction(0, 264, true)  -- melee attack heavy
            DisableControlAction(0, 22, true)   -- jump
            DisableControlAction(0, 75, true)   -- exit vehicle (stay put unless the officer moves them)
            DisableControlAction(0, 30, true)   -- left/right movement
            DisableControlAction(0, 31, true)   -- forward/back movement
            DisableControlAction(0, 21, true)   -- sprint
            DisableControlAction(0, 23, true)   -- enter vehicle
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
            if not escortFollowing and not IsPedInAnyVehicle(ped, false) then playRestrainedIdle() end
            Wait(0)
        end
    end
end)

-- ── Escort: follow the officer holding you ────────────────────────────────
-- bagName is checked live inside the handler (not baked into the filter at
-- registration time) -- matches the convention already used for cmEms/
-- cmPolice state bags elsewhere in this codebase, since GetPlayerServerId
-- may not be reliable yet at the moment this script first loads.
AddStateBagChangeHandler('cmEscortedBy', nil, function(bagName, _, value)
    if bagName ~= ('player:%s'):format(GetPlayerServerId(PlayerId())) then return end
    escortFollowing = type(value) == 'number' and value > 0
    if not escortFollowing then
        releaseGroundDrag()
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end
    else
        beginGroundDrag(value)
    end
end)

CreateThread(function()
    while true do
        Wait(350)
        local officerServerId = LocalPlayer.state.cmEscortedBy
        if type(officerServerId) == 'number' and officerServerId > 0 then
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                if beginGroundDrag(officerServerId) then
                    local officerPlayer = GetPlayerFromServerId(officerServerId)
                    local officerPed = officerPlayer ~= -1 and GetPlayerPed(officerPlayer) or 0
                    if officerPed ~= 0 and DoesEntityExist(officerPed) then
                        TaskFollowToOffsetOfEntity(ped, officerPed, 0.0, -1.15, 0.0, 1.2, 700, 0.7, true)
                        playRestrainedIdle()
                    end
                end
            end
        end
    end
end)

AddStateBagChangeHandler('cmCuffed', nil, function(bagName, _, value)
    if bagName ~= ('player:%s'):format(GetPlayerServerId(PlayerId())) then return end
    if value ~= true then
        releaseGroundDrag()
        ClearPedTasksImmediately(PlayerPedId())
    else
        playRestrainedIdle()
    end
end)

RegisterNetEvent('cm-police:client:placeInVehicle', function(vehicleNetId, seat, token)
    if LocalPlayer.state.cmCuffed ~= true then
        return TriggerServerEvent('cm-police:server:vehicleSeatResult', token, false)
    end
    releaseGroundDrag()
    local deadline = GetGameTimer() + 2500
    local vehicle = 0
    repeat
        vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId) or 0)
        if vehicle ~= 0 and DoesEntityExist(vehicle) then break end
        Wait(50)
    until GetGameTimer() >= deadline
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return TriggerServerEvent('cm-police:server:vehicleSeatResult', token, false)
    end
    seat = nil
    local totalSeats = math.max(0, tonumber(GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))) or 0)
    -- GTA uses -1 for the driver. Search passenger indices from the rear-most
    -- seat toward the front passenger seat so suspects never replace the driver.
    for candidate = totalSeats - 2, 0, -1 do
        if IsVehicleSeatFree(vehicle, candidate) then seat = candidate; break end
    end
    if seat == nil then return TriggerServerEvent('cm-police:server:vehicleSeatResult', token, false) end
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetPedCanRagdoll(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    SetPedIntoVehicle(ped, vehicle, seat)
    local enteredDeadline = GetGameTimer() + 1500
    while GetGameTimer() < enteredDeadline and GetVehiclePedIsIn(ped, false) ~= vehicle do Wait(50) end
    local entered = GetVehiclePedIsIn(ped, false) == vehicle
    SetPedCanRagdoll(ped, true)
    TriggerServerEvent('cm-police:server:vehicleSeatResult', token, entered)
end)

RegisterNetEvent('cm-police:client:removeFromVehicle', function(vehicleNetId)
    if LocalPlayer.state.cmCuffed ~= true then return end
    local ped = PlayerPedId()
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId) or 0)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local drop = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -3.0, 0.0)
    ClearPedTasksImmediately(ped)
    SetPedCanRagdoll(ped, false)
    SetEntityCoords(ped, drop.x, drop.y, drop.z, false, false, false, false)
    Wait(100)
    SetPedCanRagdoll(ped, true)
end)

-- ── X key: direct cuff/uncuff ──────────────────────────────────────────────
-- Independent of gmenu.lua's own handler for the same event -- multiple
-- resources/files can listen to one event name, so this doesn't interfere
-- with the G-menu's own rebuild. Firing the action goes through the exact
-- same TriggerServerEvent a menu click would make (cm-playerdata/client/
-- interactions.lua:1335), so cm-playerdata's own source/target/distance/
-- rate-limit/death-state validation still runs unchanged -- X only
-- shortcuts the input, not the authorization.
local currentTarget = nil
AddEventHandler('cm-playerdata:client:interactionTargetChanged', function(serverId)
    currentTarget = serverId
end)

local function notify(message, kind)
    PoliceNotify(message, kind)
end

RegisterCommand('policecuffkey', function()
    local state = LocalPlayer.state.cmPolice
    if type(state) ~= 'table' or state.onDuty ~= true then return notify('You must be on duty to do that.', 'error') end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return notify('Exit the vehicle before handling a suspect.', 'error') end
    local permissions = state.permissions or {}
    if not (state.isLeader == true or permissions['police.cuff'] == true) then return notify('Your rank cannot cuff suspects.', 'error') end
    if not currentTarget then return notify('No one nearby to cuff.', 'error') end
    local targetCuffed = Player(currentTarget).state.cmCuffed == true
    local action = targetCuffed and 'police_uncuff' or 'police_cuff'
    TriggerServerEvent('cm-playerdata:server:extensionInteraction', currentTarget, action, {})
end, false)
RegisterKeyMapping('policecuffkey', 'Police: Cuff/uncuff nearest target', 'keyboard', tostring(Config.CuffKey or 'X'))

local function draggedSuspectNearVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local police = LocalPlayer.state.cmPolice
    if type(police) ~= 'table' or police.onDuty ~= true then return nil end
    local permissions = police.permissions or {}
    if not (police.isLeader == true or permissions['police.cuff'] == true) then return nil end

    local myServerId = GetPlayerServerId(PlayerId())
    local vehicleCoords = GetEntityCoords(vehicle)
    local maxDistance = Config.Cuffs.VehicleSeatDistance or 6.0
    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local serverId = GetPlayerServerId(playerId)
            local state = Player(serverId).state
            local ped = GetPlayerPed(playerId)
            if state.cmCuffed == true and state.cmEscortedBy == myServerId
                and ped ~= 0 and DoesEntityExist(ped)
                and #(GetEntityCoords(ped) - vehicleCoords) <= maxDistance then
                return serverId
            end
        end
    end
    return nil
end

exports('GetDraggedSuspectForVehicle', draggedSuspectNearVehicle)

local function cuffedSuspectInVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local police = LocalPlayer.state.cmPolice
    if type(police) ~= 'table' or police.onDuty ~= true then return nil end
    local permissions = police.permissions or {}
    if not (police.isLeader == true or permissions['police.cuff'] == true) then return nil end
    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local serverId = GetPlayerServerId(playerId)
            local ped = GetPlayerPed(playerId)
            if Player(serverId).state.cmCuffed == true and ped ~= 0
                and DoesEntityExist(ped) and GetVehiclePedIsIn(ped, false) == vehicle then
                return serverId
            end
        end
    end
    return nil
end

exports('GetCuffedSuspectInVehicle', cuffedSuspectInVehicle)

RegisterNetEvent('cm-police:client:putDraggedInSelectedVehicle', function(vehicleNetId)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId) or 0)
    local targetServerId = draggedSuspectNearVehicle(vehicle)
    if not targetServerId then return notify('You are not dragging a cuffed suspect near this vehicle.', 'error') end
    TriggerServerEvent('cm-playerdata:server:extensionInteraction', targetServerId, 'police_put_in_vehicle', {
        vehicleNetId = tonumber(vehicleNetId),
    })
end)

RegisterNetEvent('cm-police:client:removeCuffedFromSelectedVehicle', function(vehicleNetId)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId) or 0)
    local targetServerId = cuffedSuspectInVehicle(vehicle)
    if not targetServerId then return notify('No cuffed suspect is inside this vehicle.', 'error') end
    TriggerServerEvent('cm-playerdata:server:extensionInteraction', targetServerId, 'police_take_out_vehicle', {})
end)
