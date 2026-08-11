-- cm-police wheel clamps (client). Toggle is officer-only, but the state
-- bag reaction thread at the bottom runs for EVERY player -- matches
-- client/spikes.lua's own tire-burst thread shape -- so a clamped vehicle
-- looks and behaves the same (prop attached, handbrake on, doors locked)
-- for whoever is nearby, not just the officer who clamped it.

local function notify(message, kind)
    PoliceNotify(message, kind)
end

local function canUseClamp()
    local state = LocalPlayer.state.cmPolice
    if type(state) ~= 'table' or state.onDuty ~= true then return false end
    local permissions = state.permissions or {}
    return state.isLeader == true or permissions['police.clamp'] == true
end

-- Global (not local) so client/quickmenu.lua's J-key menu can call this
-- without duplicating logic -- the /policeclamp command below is just a
-- thin wrapper around the same function. Same GetClosestVehicle shape
-- client/impound.lua's /policeimpound command already uses.
function PoliceToggleClamp()
    if not canUseClamp() then return notify('You must be an on-duty officer with clamp permission.', 'error') end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, Config.Clamp.MaxDistance or 3.0, 0, 71)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return notify('No nearby vehicle found.', 'error') end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local ok, message = lib.callback.await('cm-police:server:toggleClamp', false, netId)
    notify(message or (ok and 'Done.' or 'Clamp toggle failed.'), ok and 'success' or 'error')
end

RegisterCommand('policeclamp', PoliceToggleClamp, false)

local clampProps = {} -- [netId] = propObject

local function attachClampProp(vehicle, netId)
    if clampProps[netId] and DoesEntityExist(clampProps[netId]) then return end
    local cfg = Config.Clamp
    local hash = GetHashKey(cfg.Model or 'prop_clamp')
    RequestModel(hash)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then return end

    local coords = GetEntityCoords(vehicle)
    local prop = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    local boneIndex = GetEntityBoneIndexByName(vehicle, cfg.Bone or 'wheel_lf')
    local offset, rotation = cfg.Offset or vector3(0.0, 0.0, 0.0), cfg.Rotation or vector3(0.0, 0.0, 0.0)
    AttachEntityToEntity(prop, vehicle, boneIndex, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, true, true, false, false, 2, true)
    SetEntityAsMissionEntity(prop, true, true)
    FreezeEntityPosition(prop, true)
    SetModelAsNoLongerNeeded(hash)
    clampProps[netId] = prop

    SetVehicleHandbrake(vehicle, true)
    SetVehicleDoorsLockedForAllPlayers(vehicle, true)
end

local function removeClampProp(vehicle, netId)
    local prop = clampProps[netId]
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    clampProps[netId] = nil
    if vehicle and DoesEntityExist(vehicle) then
        SetVehicleHandbrake(vehicle, false)
        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
    end
end

AddStateBagChangeHandler('cmWheelClamped', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if value then
        attachClampProp(vehicle, netId)
    else
        removeClampProp(vehicle, netId)
    end
end)

-- Cleanup sweep, same shape as spikes.lua's tire-burst thread's own
-- "still exists" checks -- a vehicle despawning (impound, resource
-- restart) shouldn't leave an orphaned prop with no state bag left to
-- react to.
CreateThread(function()
    while true do
        Wait(10000)
        for netId, prop in pairs(clampProps) do
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
                if DoesEntityExist(prop) then DeleteEntity(prop) end
                clampProps[netId] = nil
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, prop in pairs(clampProps) do
        if DoesEntityExist(prop) then DeleteEntity(prop) end
    end
end)
