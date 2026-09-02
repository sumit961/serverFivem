-- cm-police speed radar (client only -- no server file). Display-only: it
-- reads GetEntitySpeed off a vehicle the officer is aiming at and shows the
-- number on screen. Nothing is written anywhere and no other player's
-- state changes, so gating this off the replicated cmPolice state bag
-- client-side (rather than a server round trip) is proportionate here --
-- worst case a modified client sees a fake number on their own screen.
-- The officer still has to pull the vehicle over and use the existing
-- Citations G-menu to actually issue a fine; this feature only detects.

local active = false
local handProp = nil

local function notify(message, kind)
    PoliceNotify(message, kind)
end

-- Purely visual device prop while radar is active -- a base-game model, no
-- custom asset registration needed. Same attach shape (bone id, offset/
-- rotation) as cm-vehicles/client/menu.lua's own proven attachProp helper.
local function attachHandProp()
    local cfg = Config.Radar.HandProp
    if not cfg or not cfg.Model or cfg.Model == '' then return end
    local hash = GetHashKey(cfg.Model)
    RequestModel(hash)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    handProp = CreateObject(hash, coords.x, coords.y, coords.z, true, true, false)
    local offset, rotation = cfg.Offset or vector3(0.0, 0.0, 0.0), cfg.Rotation or vector3(0.0, 0.0, 0.0)
    AttachEntityToEntity(handProp, ped, GetPedBoneIndex(ped, cfg.Bone or 57005),
        offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
end

local function detachHandProp()
    if handProp and DoesEntityExist(handProp) then DeleteEntity(handProp) end
    handProp = nil
end

local function canUseRadar()
    local state = LocalPlayer.state.cmPolice
    if type(state) == 'table' and state.onDuty == true then
        if type(PoliceCapabilityClientEnabled)=='function' and not PoliceCapabilityClientEnabled('radar') then return false end
        local permissions = state.permissions or {}
        return state.isLeader == true or permissions['police.radar'] == true
    end
    state = LocalPlayer.state.cmLegalOrg
    if type(state) ~= 'table' or state.onDuty ~= true or state.suspended
        or (state.capabilities and state.capabilities.radar == false) then return false end
    local permissions = state.permissions or {}
    return state.isLeader == true or permissions['law.radar'] == true
end

-- Same rotation-to-direction formula cm-vehicles/client/main.lua already
-- uses to build a camera forward vector for its own vehicle raycast.
local function cameraForward()
    local rot = GetGameplayCamRot(2)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

-- Same raycast shape/flags as cm-vehicles' own GetLookedAtVehicle (vehicle-
-- only flag 10) -- reused for consistency, simplified since radar doesn't
-- need that function's screen-centre fallback pass.
local function lookedAtVehicle(maxDistance)
    local ped = PlayerPedId()
    local camCoords = GetGameplayCamCoord()
    local dest = camCoords + cameraForward() * maxDistance
    local ray = StartShapeTestCapsule(camCoords.x, camCoords.y, camCoords.z, dest.x, dest.y, dest.z, 0.55, 10, ped, 7)
    local _, hit, _, _, entity = GetShapeTestResult(ray)
    if hit == 1 and entity and entity ~= 0 and GetEntityType(entity) == 2 then return entity end
    return nil
end

local function readingFor(vehicle)
    local multiplier = Config.Radar.Unit == 'MPH' and 2.236936 or 3.6
    local speed = math.floor(GetEntitySpeed(vehicle) * multiplier + 0.5)
    return ('%d %s'):format(speed, Config.Radar.Unit)
end

local function stopRadar()
    if not active then return end
    active = false
    PoliceHideHint()
    detachHandProp()
end

local function startRadar()
    active = true
    attachHandProp()
    CreateThread(function()
        while active do
            Wait(Config.Radar.UpdateIntervalMs or 200)
            if not canUseRadar() then
                notify('Radar disabled -- you are off duty.', 'error')
                return stopRadar()
            end
            local vehicle = lookedAtVehicle(Config.Radar.MaxDistance or 150.0)
            if vehicle then
                PoliceShowHint(readingFor(vehicle))
            else
                PoliceHideHint()
            end
        end
    end)
end

-- Global (not local) so client/quickmenu.lua's J-key menu can toggle radar
-- without duplicating this logic -- the /policeradar command below is just
-- a thin wrapper around the same function.
function PoliceToggleRadar()
    if active then return stopRadar() end
    if not canUseRadar() then return notify('You must be an on-duty officer with radar permission.', 'error') end
    startRadar()
end

function IsPoliceRadarActive()
    return active
end

RegisterCommand('policeradar', PoliceToggleRadar, false)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then stopRadar() end
end)
