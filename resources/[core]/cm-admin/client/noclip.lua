local noclip = false
local noclipEntity = 0
local lastGoodGround = nil
local oldAlpha = nil
local oldVisible = true
local oldInvincible = false

local function notify(msg, msgType)
    if GetResourceState('ox_lib') == 'started' and lib and lib.notify then
        lib.notify({ title = 'CM Admin', description = msg, type = msgType or 'inform' })
    else
        print(('[CM-ADMIN] %s'):format(msg))
    end
end

RegisterNetEvent('cm-admin:client:notify', function(msg, msgType)
    notify(msg, msgType)
end)

local lastReportedNoclipState = nil

local function reportNoclipState(enabled)
    enabled = enabled == true
    if lastReportedNoclipState == enabled then return end
    lastReportedNoclipState = enabled
    if LocalPlayer and LocalPlayer.state then
        -- Local hide is immediate; server also validates and replicates it to others.
        pcall(function() LocalPlayer.state:set('cm_admin_noclip', enabled, false) end)
    end
    TriggerServerEvent('cm-admin:server:setNoclipState', enabled)
end

local function getControlEntity()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
        return veh
    end
    return ped
end

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function rightVectorFromForward(forward)
    return vector3(forward.y, -forward.x, 0.0)
end

local function restoreEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    SetEntityCompletelyDisableCollision(entity, false, true)
    SetEntityCollision(entity, true, true)
    SetEntityHasGravity(entity, true)
    SetEntityDynamic(entity, true)
    ActivatePhysics(entity)
    FreezeEntityPosition(entity, false)
    ResetEntityAlpha(entity)
    SetEntityVisible(entity, true, false)
    SetEntityInvincible(entity, false)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)

    if IsEntityAVehicle(entity) then
        SetVehicleUndriveable(entity, false)
        SetVehicleHandbrake(entity, false)
    end
end

local function restorePed()
    local ped = PlayerPedId()
    restoreEntity(ped)
    SetPlayerControl(PlayerId(), true, 0)
    SetPlayerInvincible(PlayerId(), oldInvincible or false)
    SetPedCanRagdoll(ped, true)
    -- SetPedCanRagdollFromPlayerImpact stays false: cm-playerdata owns the
    -- push-protection rule and expects it to survive noclip.
    SetPedConfigFlag(ped, 32, false)
    ResetPedMovementClipset(ped, 0.0)
    ResetPedStrafeClipset(ped)
    ClearPedTasksImmediately(ped)
end

local function applyNoclipState(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    FreezeEntityPosition(entity, true)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    SetEntityHasGravity(entity, false)

    if Config.DisableCollision then
        SetEntityCollision(entity, false, false)
        SetEntityCompletelyDisableCollision(entity, true, true)
    end

    if Config.InvincibleDuringNoclip then
        SetEntityInvincible(entity, true)
        SetPlayerInvincible(PlayerId(), true)
    end

    if Config.MakeInvisible then
        oldAlpha = GetEntityAlpha(entity)
        oldVisible = IsEntityVisible(entity)
        SetEntityAlpha(entity, 0, false)
        SetEntityVisible(entity, false, false)
        local ped = PlayerPedId()
        if entity ~= ped then
            SetEntityAlpha(ped, 0, false)
            SetEntityVisible(ped, false, false)
        end
    end

    if not IsEntityAVehicle(entity) then
        local ped = PlayerPedId()
        SetPedCanRagdoll(ped, false)
        SetPedCanRagdollFromPlayerImpact(ped, false)
    else
        SetVehicleUndriveable(entity, false)
        SetVehicleHandbrake(entity, false)
    end
end

local function raycastSurfaceBelow(coords)
    local ray = StartShapeTestRay(coords.x, coords.y, coords.z + 8.0, coords.x, coords.y, coords.z - 80.0, 1, PlayerPedId(), 7)
    local _, hit, hitCoords = GetShapeTestResult(ray)
    if hit == 1 and hitCoords then
        return vector3(hitCoords.x, hitCoords.y, hitCoords.z + 1.05)
    end
    return nil
end

local function groundAt(coords)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    local surface = raycastSurfaceBelow(coords)
    if surface then return surface end

    for i = 1, 20 do
        local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 100.0, false)
        if found then
            return vector3(coords.x, coords.y, groundZ + 1.05)
        end
        Wait(0)
    end

    return nil
end

local function safeStandingCoords(coords)
    local found = groundAt(coords)
    if found then return found end

    if lastGoodGround then return lastGoodGround end

    local safe = Config.SafeCoords or vector4(215.76, -810.12, 30.73, 157.0)
    return vector3(safe.x, safe.y, safe.z + 0.5)
end

local function standEntitySafely(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    local coords = GetEntityCoords(entity)
    local exitCoords = safeStandingCoords(coords)

    RequestCollisionAtCoord(exitCoords.x, exitCoords.y, exitCoords.z)

    restoreEntity(entity)
    restorePed()

    FreezeEntityPosition(entity, true)
    SetEntityCoordsNoOffset(entity, exitCoords.x, exitCoords.y, exitCoords.z, false, false, true)

    local start = GetGameTimer()
    while GetGameTimer() - start < 500 do
        RequestCollisionAtCoord(exitCoords.x, exitCoords.y, exitCoords.z)
        Wait(0)
    end

    restoreEntity(entity)
    restorePed()
    FreezeEntityPosition(entity, false)

    if IsEntityAVehicle(entity) then
        SetVehicleOnGroundProperly(entity)
    end
end

local function disableNoclip()
    if not noclip then return end
    noclip = false
    reportNoclipState(false)

    local entity = (noclipEntity ~= 0 and DoesEntityExist(noclipEntity)) and noclipEntity or getControlEntity()
    standEntitySafely(entity)

    noclipEntity = 0
    oldAlpha = nil
    oldVisible = true
    notify('Noclip disabled. Player placed on safe ground.', 'inform')
end

local function enableNoclip()
    if noclip then return end
    local entity = getControlEntity()
    noclip = true
    noclipEntity = entity
    -- Capture BEFORE applying: applyNoclipState sets invincible, and reading it
    -- afterwards would save 'true' and restore permanent god mode on exit.
    oldInvincible = GetPlayerInvincible(PlayerId())
    lastGoodGround = groundAt(GetEntityCoords(entity)) or GetEntityCoords(entity)
    applyNoclipState(entity)
    reportNoclipState(true)
    notify('Noclip enabled. F2 again to disable.', 'success')
end

local function toggleNoclip()
    if noclip then disableNoclip() else enableNoclip() end
end

RegisterNetEvent('cm-admin:client:toggleNoclip', toggleNoclip)

RegisterCommand(Config.KeybindCommand or 'cm_admin_noclip_toggle', function()
    TriggerServerEvent('cm-admin:server:requestNoclipToggle')
end, false)
RegisterKeyMapping(Config.KeybindCommand or 'cm_admin_noclip_toggle', 'CM Admin: Toggle noclip', 'keyboard', Config.DefaultKey or 'F2')

CreateThread(function()
    while true do
        if not noclip then
            Wait(250)
        else
            Wait(0)

            local entity = noclipEntity
            if not entity or entity == 0 or not DoesEntityExist(entity) then
                entity = getControlEntity()
                noclipEntity = entity
                applyNoclipState(entity) -- full state only when entity changes
            end

            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 36, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 38, true) -- E (used for up)
            DisableControlAction(0, 44, true) -- Q/cover (used for down)

            local speed = Config.Speeds.normal or 1.6
            if IsDisabledControlPressed(0, 21) then
                speed = Config.Speeds.fast or 5.8
            elseif IsDisabledControlPressed(0, 19) then
                speed = Config.Speeds.slow or 0.35
            end

            local camRot = GetGameplayCamRot(2)
            local forward = rotationToDirection(camRot)
            local right = rightVectorFromForward(forward)
            local pos = GetEntityCoords(entity)
            local move = vector3(0.0, 0.0, 0.0)

            if IsDisabledControlPressed(0, 32) then move = move + forward end
            if IsDisabledControlPressed(0, 33) then move = move - forward end
            if IsDisabledControlPressed(0, 35) then move = move + right end
            if IsDisabledControlPressed(0, 34) then move = move - right end
            if IsDisabledControlPressed(0, 22) or IsDisabledControlPressed(0, 38) then move = move + vector3(0.0, 0.0, 1.0) end
            if IsDisabledControlPressed(0, 36) or IsDisabledControlPressed(0, 44) then move = move - vector3(0.0, 0.0, 1.0) end

            if #(move) > 0.0 then
                move = move / #(move)
                -- Frame-time scaled: identical fly speed at 60 or 240 fps.
                pos = pos + (move * speed * GetFrameTime() * 60.0)
                SetEntityCoordsNoOffset(entity, pos.x, pos.y, pos.z, false, false, true)
            end

            SetEntityVelocity(entity, 0.0, 0.0, 0.0)
            SetEntityHeading(entity, camRot.z)

            -- Save a recent valid standing surface, but only when it is close below us.
            if GetGameTimer() % 750 < 20 then
                local g = groundAt(GetEntityCoords(entity))
                if g and #(g - GetEntityCoords(entity)) < 8.0 then
                    lastGoodGround = g
                end
            end

            if Config.ShowHelp then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(('NOCLIP ON | %.1f | W/S/A/D | Space/E up | Ctrl/Q down | Shift fast | Alt slow | F2 off'):format(speed))
                EndTextCommandDisplayHelp(0, false, false, -1)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if noclip then disableNoclip() end
    restorePed()
end)

-- Utility actions: triggered by the server after permission checks.
RegisterNetEvent('cm-admin:client:unstuck', function()
    if noclip then
        noclip = false
        reportNoclipState(false)
    end
    local entity = getControlEntity()
    standEntitySafely(entity)
    notify('Placed on safe standing ground.', 'success')
end)

RegisterNetEvent('cm-admin:client:stand', function()
    local entity = getControlEntity()
    standEntitySafely(entity)
    notify('Forced player to stand on nearest surface.', 'success')
end)

RegisterNetEvent('cm-admin:client:moveUp', function(args)
    local entity = getControlEntity()
    local amount = tonumber(args and args[1]) or 2.0
    amount = math.min(math.max(amount, 0.5), 25.0)
    restoreEntity(entity)
    restorePed()
    local pos = GetEntityCoords(entity)
    SetEntityCoordsNoOffset(entity, pos.x, pos.y, pos.z + amount, false, false, true)
    notify(('Moved up %.1fm.'):format(amount), 'success')
end)

RegisterNetEvent('cm-admin:client:safeTeleport', function()
    local entity = getControlEntity()
    local safe = Config.SafeCoords or vector4(215.76, -810.12, 30.73, 157.0)
    restoreEntity(entity)
    restorePed()
    FreezeEntityPosition(entity, true)
    RequestCollisionAtCoord(safe.x, safe.y, safe.z)
    SetEntityCoordsNoOffset(entity, safe.x, safe.y, safe.z + 0.5, false, false, true)
    Wait(500)
    restoreEntity(entity)
    restorePed()
    FreezeEntityPosition(entity, false)
    notify('Teleported to safe test point.', 'success')
end)

RegisterNetEvent('cm-admin:client:disableNoclip', function()
    if noclip then
        disableNoclip()
    else
        reportNoclipState(false)
    end
end)
