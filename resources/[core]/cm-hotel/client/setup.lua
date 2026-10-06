local editorOpen = false
local focusActive = false
local setupToken = nil
local draftSetup = nil
local previewPed = nil
local previewVehicle = nil

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function pointFromDraft(pointId)
    if type(draftSetup) ~= 'table' then return nil end
    if pointId == 'firstSpawn' then return draftSetup.firstSpawn end
    if pointId == 'receptionist' then return draftSetup.receptionist and draftSetup.receptionist.coords end
    if pointId == 'rentalNpc' then return draftSetup.rental and draftSetup.rental.coords end
    if pointId == 'rentalVehicleSpawn' then return draftSetup.rental and draftSetup.rental.vehicleSpawn end
    if pointId == 'license' or pointId == 'jobCentre' or pointId == 'hospital' then return draftSetup.help and draftSetup.help[pointId] end
    if pointId == 'blip' then return draftSetup.blip and draftSetup.blip.coords end
    local floorId = pointId:find('Rooms') and 'rooms' or pointId:find('Lobby') and 'lobby' or nil
    if floorId then
        for _, floor in ipairs(draftSetup.lifts and draftSetup.lifts.main and draftSetup.lifts.main.floors or {}) do
            if floor.id == floorId then return pointId:find('Interaction') and floor.interaction or (floor.arrival or floor.destination) end
        end
    end
    return nil
end

local function assignDraftPoint(pointId, point)
    if type(draftSetup) ~= 'table' or type(point) ~= 'table' then return end
    if pointId == 'firstSpawn' then draftSetup.firstSpawn = point; return end
    if pointId == 'receptionist' then draftSetup.receptionist = draftSetup.receptionist or {}; draftSetup.receptionist.coords = point; return end
    if pointId == 'rentalNpc' then draftSetup.rental = draftSetup.rental or {}; draftSetup.rental.coords = point; return end
    if pointId == 'rentalVehicleSpawn' then draftSetup.rental = draftSetup.rental or {}; draftSetup.rental.vehicleSpawn = point; return end
    if pointId == 'license' or pointId == 'jobCentre' or pointId == 'hospital' then draftSetup.help = draftSetup.help or {}; draftSetup.help[pointId] = point; return end
    if pointId == 'blip' then draftSetup.blip = draftSetup.blip or {}; draftSetup.blip.coords = point; return end
    local floorId = pointId:find('Rooms') and 'rooms' or pointId:find('Lobby') and 'lobby' or nil
    if not floorId then return end
    for _, floor in ipairs(draftSetup.lifts and draftSetup.lifts.main and draftSetup.lifts.main.floors or {}) do
        if floor.id == floorId then
            if pointId:find('Interaction') then floor.interaction = point else floor.arrival, floor.destination = point, point end
            return
        end
    end
end

local function sendPoint(pointId)
    SendNUIMessage({ action = 'pointUpdated', point = pointId, coords = pointFromDraft(pointId) })
end

local function setFocus(active)
    focusActive = active == true
    SetNuiFocus(focusActive, focusActive)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'focus', active = focusActive })
end

local function deletePreview()
    if previewPed and DoesEntityExist(previewPed) then DeletePed(previewPed) end
    if previewVehicle and DoesEntityExist(previewVehicle) then DeleteVehicle(previewVehicle) end
    previewPed, previewVehicle = nil, nil
end

local function showSetupMessage(message, kind)
    SendNUIMessage({ action = 'toast', message = message, kind = kind or 'info' })
end

local function validPreviewModel(model)
    if type(model) ~= 'string' or model == '' then return nil end
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function closeEditor(notifyServer)
    if notifyServer and setupToken then TriggerServerEvent('cm-hotel:server:setupClose', setupToken) end
    deletePreview()
    editorOpen = false
    setupToken = nil
    draftSetup = nil
    setFocus(false)
    TriggerEvent('cm-hotel:client:setupEditing', false)
    CMHotelClient.SetEditorActive(false)
    SendNUIMessage({ action = 'close' })
end

local function openEditor(payload)
    if type(payload) ~= 'table' or type(payload.data) ~= 'table' then return end
    editorOpen = true
    setupToken = payload.token
    draftSetup = copy(payload.data.setup)
    TriggerEvent('cm-hotel:client:setupEditing', true)
    CMHotelClient.SetEditorActive(true)
    setFocus(true)
    SendNUIMessage({ action = 'open', data = payload.data, token = setupToken })
end

RegisterNetEvent('cm-hotel:client:setupOpen', function(payload)
    if editorOpen then closeEditor(true) end
    openEditor(payload)
end)

RegisterNetEvent('cm-hotel:client:setupSaved', function(payload)
    if type(payload) ~= 'table' or not editorOpen then return end
    if type(payload.data) == 'table' then
        draftSetup = copy(payload.data.setup)
        SendNUIMessage({ action = 'data', data = payload.data })
    end
    showSetupMessage('HOTEL SETUP SAVED', 'success')
end)

RegisterNetEvent('cm-hotel:client:setupReset', function(payload)
    if type(payload) ~= 'table' or not editorOpen then return end
    draftSetup = copy(payload.data and payload.data.setup or {})
    deletePreview()
    SendNUIMessage({ action = 'data', data = payload.data })
    showSetupMessage('HOTEL SETUP RESET TO CONFIG FALLBACKS', 'success')
end)

RegisterNetEvent('cm-hotel:client:setupPreviewNpc', function(payload)
    if not editorOpen or type(payload) ~= 'table' then return end
    deletePreview()
    local coords = payload.coords
    local hash = validPreviewModel(payload.model)
    if not hash or type(coords) ~= 'table' then showSetupMessage('NPC PREVIEW MODEL OR POSITION IS INVALID', 'error'); return end
    previewPed = CreatePed(4, hash, coords.x, coords.y, coords.z, coords.w or 0.0, false, true)
    SetEntityAsMissionEntity(previewPed, true, true)
    FreezeEntityPosition(previewPed, true)
    SetEntityInvincible(previewPed, true)
    SetEntityCanBeDamaged(previewPed, false)
    SetBlockingOfNonTemporaryEvents(previewPed, true)
    SetPedCanRagdoll(previewPed, false)
    SetEntityCollision(previewPed, false, false)
    SetModelAsNoLongerNeeded(hash)
    showSetupMessage('LOCAL NPC PREVIEW SPAWNED', 'success')
end)

RegisterNetEvent('cm-hotel:client:setupPreviewVehicle', function(payload)
    if not editorOpen or type(payload) ~= 'table' then return end
    if previewVehicle and DoesEntityExist(previewVehicle) then DeleteVehicle(previewVehicle) end
    local coords = payload.coords
    local hash = validPreviewModel(payload.model)
    if not hash or type(coords) ~= 'table' then showSetupMessage('RENTAL VEHICLE PREVIEW IS INVALID', 'error'); return end
    previewVehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w or 0.0, false, false)
    SetEntityAsMissionEntity(previewVehicle, true, true)
    SetVehicleEngineOn(previewVehicle, false, true, true)
    SetVehicleDoorsLocked(previewVehicle, 2)
    SetEntityInvincible(previewVehicle, true)
    SetEntityCollision(previewVehicle, false, false)
    FreezeEntityPosition(previewVehicle, true)
    SetModelAsNoLongerNeeded(hash)
    showSetupMessage('LOCAL RENTAL VEHICLE PREVIEW SPAWNED', 'success')
end)

RegisterNetEvent('cm-hotel:client:setupTestWaypoint', function(payload)
    if not editorOpen or type(payload) ~= 'table' or type(payload.coords) ~= 'table' then return end
    SetNewWaypoint(payload.coords.x + 0.0, payload.coords.y + 0.0)
    showSetupMessage('WAYPOINT SET', 'success')
end)

AddEventHandler('cm-hotel:client:setupDataApplied', function(payload)
    if not editorOpen or type(payload) ~= 'table' or type(payload.setup) ~= 'table' then return end
    draftSetup = copy(payload.setup)
    SendNUIMessage({ action = 'data', data = payload })
end)

RegisterNUICallback('close', function(_, cb)
    closeEditor(true)
    cb({ ok = true })
end)

RegisterNUICallback('setFocus', function(data, cb)
    if editorOpen then setFocus(data and data.active == true) end
    cb({ ok = true })
end)

RegisterNUICallback('capturePosition', function(data, cb)
    if not editorOpen or type(data) ~= 'table' then cb({ ok = false }); return end
    local pointId = tostring(data.point or '')
    local coords = GetEntityCoords(PlayerPedId())
    local point = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(PlayerPedId()) }
    if pointId == 'license' or pointId == 'jobCentre' or pointId == 'hospital' or pointId == 'blip' then point.w = nil end
    assignDraftPoint(pointId, point)
    sendPoint(pointId)
    cb({ ok = true, coords = point })
end)

RegisterNUICallback('nudge', function(data, cb)
    if not editorOpen or type(data) ~= 'table' then cb({ ok = false }); return end
    local pointId = tostring(data.point or '')
    local point = pointFromDraft(pointId)
    if type(point) ~= 'table' then cb({ ok = false }); return end
    point = copy(point)
    point.x = (tonumber(point.x) or 0) + (tonumber(data.dx) or 0)
    point.y = (tonumber(point.y) or 0) + (tonumber(data.dy) or 0)
    point.z = (tonumber(point.z) or 0) + (tonumber(data.dz) or 0)
    if point.w ~= nil then point.w = (tonumber(point.w) or 0) + (tonumber(data.dw) or 0) end
    assignDraftPoint(pointId, point)
    sendPoint(pointId)
    cb({ ok = true })
end)

RegisterNUICallback('save', function(data, cb)
    if not editorOpen or type(data) ~= 'table' then cb({ ok = false }); return end
    local point = pointFromDraft(tostring(data.point or ''))
    TriggerServerEvent('cm-hotel:server:setupSave', setupToken, tostring(data.point or ''), point)
    cb({ ok = true })
end)

RegisterNUICallback('saveModel', function(data, cb)
    if editorOpen and type(data) == 'table' then TriggerServerEvent('cm-hotel:server:setupSaveModel', setupToken, tostring(data.kind or ''), tostring(data.model or '')) end
    cb({ ok = true })
end)

RegisterNUICallback('reset', function(_, cb)
    if editorOpen then TriggerServerEvent('cm-hotel:server:setupReset', setupToken) end
    cb({ ok = true })
end)

RegisterNUICallback('previewNpc', function(data, cb)
    if editorOpen then TriggerServerEvent('cm-hotel:server:setupPreviewNpc', setupToken, tostring(data and data.kind or '')) end
    cb({ ok = true })
end)

RegisterNUICallback('previewVehicle', function(data, cb)
    if editorOpen then TriggerServerEvent('cm-hotel:server:setupPreviewVehicle', setupToken, tostring(data and data.optionId or '')) end
    cb({ ok = true })
end)

RegisterNUICallback('testLift', function(data, cb)
    if editorOpen then setFocus(false); TriggerServerEvent('cm-hotel:server:setupTestLift', setupToken, tostring(data and data.direction or '')) end
    cb({ ok = true })
end)

RegisterNUICallback('testWaypoint', function(data, cb)
    if editorOpen then setFocus(false); TriggerServerEvent('cm-hotel:server:setupTestWaypoint', setupToken, tostring(data and data.point or '')) end
    cb({ ok = true })
end)

CreateThread(function()
    while true do
        if editorOpen then
            if not focusActive and IsControlJustPressed(0, 168) then setFocus(true) end
            if focusActive then
                DisableControlAction(0, 1, true); DisableControlAction(0, 2, true)
                DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
                DisableControlAction(0, 30, true); DisableControlAction(0, 31, true)
                DisableControlAction(0, 32, true); DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true); DisableControlAction(0, 35, true)
            end
            Wait(0)
        else Wait(300) end
    end
end)

local markerPoints = {
    { id = 'firstSpawn', label = 'FIRST SPAWN', colour = { 0, 229, 255 } },
    { id = 'receptionist', label = 'RECEPTION', colour = { 46, 204, 113 } },
    { id = 'rentalNpc', label = 'RENTAL NPC', colour = { 255, 199, 0 } },
    { id = 'rentalVehicleSpawn', label = 'RENTAL VEHICLE', colour = { 255, 140, 0 } },
    { id = 'liftRoomsInteraction', label = 'LIFT ROOMS INTERACTION', colour = { 0, 229, 255 } },
    { id = 'liftRoomsArrival', label = 'LIFT ROOMS ARRIVAL', colour = { 0, 229, 255 } },
    { id = 'liftLobbyInteraction', label = 'LIFT LOBBY INTERACTION', colour = { 0, 229, 255 } },
    { id = 'liftLobbyArrival', label = 'LIFT LOBBY ARRIVAL', colour = { 0, 229, 255 } }
}

local function drawText3d(coords, text)
    local visible, sx, sy = World3dToScreen2d(coords.x, coords.y, coords.z + 0.35)
    if not visible then return end
    SetTextScale(0.24, 0.24); SetTextFont(4); SetTextProportional(1); SetTextColour(255, 255, 255, 220); SetTextCentre(true)
    SetTextOutline(); BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayText(sx, sy)
end

CreateThread(function()
    while true do
        if editorOpen then
            for _, marker in ipairs(markerPoints) do
                local value = pointFromDraft(marker.id)
                if type(value) == 'table' and value.x and value.y and value.z then
                    DrawMarker(2, value.x, value.y, value.z + 0.08, 0.0, 0.0, 0.0, 0.0, 0.0, value.w or 0.0, 0.18, 0.18, 0.18,
                        marker.colour[1], marker.colour[2], marker.colour[3], 210, false, true, 2, false, nil, nil, false)
                    drawText3d(value, marker.label)
                end
            end
            Wait(0)
        else Wait(300) end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeEditor(false) end
end)
