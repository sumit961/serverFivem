-- cm-law cuffing & arrest (client). Ported from cm-police/client/cuffs.lua --
-- every client only ever acts on the LOCAL player's own replicated state
-- (cmCuffed/cmEscortedBy are plain FiveM state bags, not cm-police-specific).
-- The one adaptation: cm-police uses its own custom PoliceNotify toolkit;
-- this uses ox_lib's lib.notify, matching every other cm-law client file.

local restrainedAnimDict = 'mp_arresting'
local escortFollowing = false
local groundDragActive = false

local function notify(message, kind)
    if lib and lib.notify then lib.notify({ title = 'Legal Organization', description = message, type = kind or 'inform' }) end
end

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
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 263, true)
            DisableControlAction(0, 264, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 23, true)
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
            if not escortFollowing and not IsPedInAnyVehicle(ped, false) then playRestrainedIdle() end
            Wait(0)
        end
    end
end)

-- ── Escort: follow the officer holding you ────────────────────────────────
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

RegisterNetEvent('cm-law:client:placeInVehicle', function(vehicleNetId, token)
    if LocalPlayer.state.cmCuffed ~= true then
        return TriggerServerEvent('cm-law:server:vehicleSeatResult', token, false)
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
        return TriggerServerEvent('cm-law:server:vehicleSeatResult', token, false)
    end
    local seat = nil
    local totalSeats = math.max(0, tonumber(GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))) or 0)
    for candidate = totalSeats - 2, 0, -1 do
        if IsVehicleSeatFree(vehicle, candidate) then seat = candidate; break end
    end
    if seat == nil then return TriggerServerEvent('cm-law:server:vehicleSeatResult', token, false) end
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
    TriggerServerEvent('cm-law:server:vehicleSeatResult', token, entered)
end)

RegisterNetEvent('cm-law:client:removeFromVehicle', function(vehicleNetId)
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

-- ── X key: direct cuff/uncuff of the nearest interaction target ──────────
local currentTarget = nil
AddEventHandler('cm-playerdata:client:interactionTargetChanged', function(serverId)
    currentTarget = serverId
end)

RegisterCommand('lawcuffkey', function()
    local state = LocalPlayer.state.cmLegalOrg
    if type(state) ~= 'table' or state.onDuty ~= true then return notify('You must be on duty to do that.', 'error') end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return notify('Exit the vehicle before handling a suspect.', 'error') end
    local permissions = state.permissions or {}
    if not (state.isLeader == true or permissions['law.cuff'] == true) then return notify('Your rank cannot cuff suspects.', 'error') end
    if not currentTarget then return notify('No one nearby to cuff.', 'error') end
    local targetCuffed = Player(currentTarget).state.cmCuffed == true
    local action = targetCuffed and 'law_uncuff' or 'law_cuff'
    TriggerServerEvent('cm-playerdata:server:extensionInteraction', currentTarget, action, {})
end, false)
RegisterKeyMapping('lawcuffkey', 'Legal org: Cuff/uncuff nearest target', 'keyboard', tostring(Config.CuffKey or 'X'))
