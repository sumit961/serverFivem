local roomOpen, committed, activeOrg, camera = false, false, nil, nil
local personalOutfit = nil
local dutyUniform = nil
local uniformGeneration = 0

local function sex() return GetEntityModel(PlayerPedId()) == `mp_f_freemode_01` and 'female' or 'male' end

local function captureOutfit()
    local ped, outfit = PlayerPedId(), { components = {}, props = {} }
    for index = 0, 11 do outfit.components[tostring(index)] = { drawable = GetPedDrawableVariation(ped, index), texture = GetPedTextureVariation(ped, index) } end
    for index = 0, 7 do outfit.props[tostring(index)] = { drawable = GetPedPropIndex(ped, index), texture = GetPedPropTextureIndex(ped, index) } end
    return outfit
end

local function applyOutfit(outfit)
    local ped = PlayerPedId()
    for key, value in pairs(type(outfit) == 'table' and outfit.components or {}) do
        local index = tonumber(key)
        if index and type(value) == 'table' then SetPedComponentVariation(ped, index, tonumber(value.drawable) or 0, tonumber(value.texture) or 0, 0) end
    end
    for key, value in pairs(type(outfit) == 'table' and outfit.props or {}) do
        local index, drawable = tonumber(key), tonumber(value.drawable) or -1
        if index then if drawable < 0 then ClearPedProp(ped, index) else SetPedPropIndex(ped, index, drawable, tonumber(value.texture) or 0, true) end end
    end
end

local function restoreEquippedClothing()
    if GetResourceState('cm-inventory') == 'started' then
        TriggerEvent('cm-inventory:client:restoreEquippedClothing')
        TriggerEvent('cm-inventory:client:requestEquipmentRefresh')
    end
end

local function scheduleUniformApply(uniform)
    uniformGeneration = uniformGeneration + 1
    local generation = uniformGeneration
    dutyUniform = type(uniform) == 'table' and uniform or nil
    if not dutyUniform or type(dutyUniform.outfit) ~= 'table' then
        restoreEquippedClothing()
        return
    end
    CreateThread(function()
        for _, delay in ipairs({ 0, 500, 1600, 3500 }) do
            if delay > 0 then Wait(delay) end
            if generation ~= uniformGeneration then return end
            local state = LocalPlayer.state.cmLegalOrg
            if type(state) ~= 'table' or state.onDuty ~= true or state.uniformActive ~= true then return end
            applyOutfit(dutyUniform.outfit)
        end
    end)
end

local function recoverDutyUniform()
    CreateThread(function()
        local uniform = lib.callback.await('cm-law:server:dutyUniform', false)
        scheduleUniformApply(uniform)
    end)
end

local function setLocked(locked)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, locked); SetPedCanRagdoll(ped, not locked)
    DisplayRadar(not locked); DisplayHud(not locked)
end

local function openCamera()
    local ped, pos = PlayerPedId(), GetEntityCoords(PlayerPedId())
    local rad, distance = math.rad(GetEntityHeading(ped)), 4.35
    local camPos = vector3(pos.x - math.sin(rad) * distance, pos.y + math.cos(rad) * distance, pos.z + 0.33)
    SetEntityHeading(ped, GetHeadingFromVector_2d(pos.x - camPos.x, pos.y - camPos.y) % 360.0)
    camera = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, 38.0, false, 0)
    PointCamAtCoord(camera, pos.x, pos.y, pos.z + 0.18); SetCamActive(camera, true); RenderScriptCams(true, false, 0, true, true)
end

local function closeRoom(restore)
    if not roomOpen then return end
    if restore and not committed and personalOutfit then applyOutfit(personalOutfit) end
    roomOpen = false; activeOrg = nil
    RenderScriptCams(false, true, 350, true, true)
    if camera and DoesCamExist(camera) then DestroyCam(camera, false) end
    camera = nil; setLocked(false); SetNuiFocus(false, false)
    SendNUIMessage({ action = 'legalWardrobeClose' })
end

RegisterNetEvent('cm-law:client:openWardrobe', function(orgId, label)
    if roomOpen then return end
    local result = lib.callback.await('cm-law:server:wardrobeCatalog', false, orgId, sex())
    if not result or not result.ok then return TriggerEvent('cm-hud:client:notify', result and result.error or 'Wardrobe unavailable.', 'error') end
    if #(result.items or {}) == 0 then return TriggerEvent('cm-hud:client:notify', 'No approved clothing has been configured for this organization.', 'error') end
    local membership = LocalPlayer.state.cmLegalOrg
    if type(membership) ~= 'table' or membership.onDuty ~= true or not personalOutfit then personalOutfit = captureOutfit() end
    committed = false; roomOpen = true; activeOrg = orgId
    setLocked(true); openCamera(); SetNuiFocus(true, true)
    SendNUIMessage({ action = 'legalWardrobeOpen', items = result.items, label = label or result.label })
end)

RegisterNUICallback('legalWardrobePreview', function(data, cb)
    if not roomOpen then return cb({ ok = false }) end
    local ped, kind, index = PlayerPedId(), tostring(data.componentType or 'component'), tonumber(data.componentIndex)
    local drawable, texture = tonumber(data.drawableId), math.max(0, tonumber(data.textureId) or 0)
    if not index or not drawable then return cb({ ok = false }) end
    if kind == 'prop' then if drawable < 0 then ClearPedProp(ped, index) else SetPedPropIndex(ped, index, drawable, texture, true) end
    else SetPedComponentVariation(ped, index, drawable, texture, 0) end
    cb({ ok = true })
end)

RegisterNUICallback('legalWardrobeRotate', function(data, cb)
    if roomOpen then SetEntityHeading(PlayerPedId(), (GetEntityHeading(PlayerPedId()) + math.max(-25.0, math.min(25.0, tonumber(data.delta) or 0.0))) % 360.0) end
    cb({ ok = roomOpen })
end)

RegisterNUICallback('legalWardrobeDone', function(_, cb)
    if not roomOpen then return cb({ ok = false }) end
    local result = lib.callback.await('cm-law:server:finishWardrobeDuty', false, activeOrg, captureOutfit(), sex())
    if result and result.ok then committed = true; closeRoom(false) end
    TriggerEvent('cm-hud:client:notify', result and (result.message or result.error) or 'No response from server.', result and result.ok and 'success' or 'error')
    cb(result or { ok = false })
end)

RegisterNUICallback('legalWardrobeCancel', function(_, cb) closeRoom(true); cb({ ok = true }) end)

RegisterNetEvent('cm-law:client:restorePersonalOutfit', function()
    uniformGeneration = uniformGeneration + 1
    dutyUniform = nil
    restoreEquippedClothing()
end)

RegisterNetEvent('cm-law:client:dutyUniformState', function(uniform)
    scheduleUniformApply(uniform)
end)

AddEventHandler('cm-spawn:client:spawned', function() SetTimeout(700, recoverDutyUniform) end)
AddEventHandler('cm-spawn:client:spawnComplete', function() SetTimeout(700, recoverDutyUniform) end)
AddEventHandler('playerSpawned', function() SetTimeout(700, recoverDutyUniform) end)

CreateThread(function()
    Wait(1200)
    recoverDutyUniform()
end)

AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then closeRoom(true) end end)
