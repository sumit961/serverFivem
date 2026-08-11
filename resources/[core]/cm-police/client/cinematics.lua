local active, camera, cancelled, startedAt, protectedEntities, wasFrozen
local shot, begin
local HUD_REASON = 'cm-police:cinematic'
local rules = { enabled = true, allowSkip = true, cameraCollision = true, sequenceSpeed = 1.0,
    cameraFov = 45.0, responseDurationMs = 2200, soundEnabled = true, soundVolume = 1.0 }
local preferences = { mode = 'full', subtitleScale = 1.0, soundVolume = 1.0, reducedFlash = false, skipSeen = false }
local ACCESS_KVP = 'cm-police:cinematic-accessibility'

local function loadPreferences()
    local raw = GetResourceKvpString(ACCESS_KVP)
    if raw and raw ~= '' then
        local ok, value = pcall(json.decode, raw)
        if ok and type(value) == 'table' then
            preferences.mode = value.mode == 'off' and 'off' or value.mode == 'reduced' and 'reduced' or 'full'
            preferences.subtitleScale = math.max(0.9, math.min(1.4, tonumber(value.subtitleScale) or 1.0))
            preferences.soundVolume = math.max(0, math.min(1, tonumber(value.soundVolume) or 1.0))
            preferences.reducedFlash, preferences.skipSeen = value.reducedFlash == true, value.skipSeen == true
        end
    end
    SendNUIMessage({ action = 'cinematicAccessibility:apply', subtitleScale = preferences.subtitleScale })
end
CreateThread(function() Wait(500); loadPreferences() end)

local function shouldPlay(kind)
    if rules.enabled == false or preferences.mode == 'off' then return false end
    return not (preferences.skipSeen and GetResourceKvpInt(('cm-police:cinematic-seen:%s'):format(kind)) == 1)
end
local function markSeen(kind) SetResourceKvpInt(('cm-police:cinematic-seen:%s'):format(kind), 1) end

RegisterCommand('policecinematics', function()
    if active then return end
    SetNuiFocus(true, true); SendNUIMessage({ action = 'cinematicAccessibility:open', preferences = preferences })
end, false)
RegisterNUICallback('closeCinematicAccessibility', function(_, cb) SetNuiFocus(false, false); SendNUIMessage({ action = 'cinematicAccessibility:close' }); cb({ ok = true }) end)
RegisterNUICallback('saveCinematicAccessibility', function(data, cb)
    data = type(data) == 'table' and data or {}
    preferences = { mode = data.mode == 'off' and 'off' or data.mode == 'reduced' and 'reduced' or 'full',
        subtitleScale = math.max(0.9, math.min(1.4, tonumber(data.subtitleScale) or 1.0)),
        soundVolume = math.max(0, math.min(1, tonumber(data.soundVolume) or 1.0)),
        reducedFlash = data.reducedFlash == true, skipSeen = data.skipSeen == true }
    SetResourceKvp(ACCESS_KVP, json.encode(preferences)); SetNuiFocus(false, false)
    SendNUIMessage({ action = 'cinematicAccessibility:apply', subtitleScale = preferences.subtitleScale })
    SendNUIMessage({ action = 'cinematicAccessibility:close' }); PoliceNotify('Cinematic accessibility preferences saved.', 'success'); cb({ ok = true })
end)

CreateThread(function()
    Wait(1000)
    local loaded = lib.callback.await('cm-police:server:cinematicRules', false)
    if type(loaded) == 'table' then rules = loaded end
end)
RegisterNetEvent('cm-police:client:cinematicRulesUpdated', function(value) if type(value) == 'table' then rules = value end end)

function PoliceCinematicResponseDuration() return tonumber(rules.responseDurationMs) or 2200 end
function PoliceCinematicCameraFov(fallback) return math.max(30, math.min(70, tonumber(rules.cameraFov) or tonumber(fallback) or 45)) end
function PoliceResolveCinematicCameraPosition(ignoreEntity, focus, position)
    if rules.cameraCollision == false then return position end
    local ray = StartShapeTestRay(focus.x, focus.y, focus.z, position.x, position.y, position.z, 17, ignoreEntity or 0, 7)
    local _, hit, hitCoords = GetShapeTestResult(ray)
    if hit ~= 1 then return position end
    local direction, length = focus - hitCoords, #(focus - hitCoords)
    return length > 0.01 and hitCoords + direction / length * 0.28 or position
end
function PoliceCinematicSound(kind, ped)
    if rules.soundEnabled == false or (tonumber(rules.soundVolume) or 0) <= 0 or preferences.soundVolume <= 0 then return end
    local sounds = {
        radio = { 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET' }, shutter = { 'Camera_Shoot', 'Phone_Soundset_Franklin' },
        confirm = { 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET' }, door = { 'DOOR_BUZZ', 'MP_PLAYER_APARTMENT' },
        tow = { 'CONFIRM_BEEP', 'HUD_MINI_GAME_SOUNDSET' },
    }
    local sound = sounds[kind] or sounds.confirm
    local soundId = GetSoundId()
    PlaySoundFrontend(soundId, sound[1], sound[2], true)
    pcall(SetVariableOnSound, soundId, 'Volume', math.max(0.0, math.min(1.0, (tonumber(rules.soundVolume) or 1.0) * preferences.soundVolume)))
    SetTimeout(2500, function() ReleaseSoundId(soundId) end)
    if ped and DoesEntityExist(ped) then pcall(PlayPedAmbientSpeechNative, ped, kind == 'radio' and 'GENERIC_HI' or 'GENERIC_THANKS', 'SPEECH_PARAMS_FORCE') end
end

local function hud(hidden)
    if GetResourceState('cm-hud') ~= 'started' then return end
    TriggerEvent(hidden and 'cm-hud:client:hideForUi' or 'cm-hud:client:showAfterUi', HUD_REASON)
end

local function clearCamera(fade)
    if fade then DoScreenFadeOut(250); while not IsScreenFadedOut() do Wait(0) end end
    if camera and DoesCamExist(camera) then DestroyCam(camera, false) end
    camera = nil
    RenderScriptCams(false, true, 350, true, true)
    if fade then DoScreenFadeIn(350) end
end

local function finish()
    clearCamera(false)
    SendNUIMessage({ action = 'policeCinematic:hide' })
    FreezeEntityPosition(PlayerPedId(), wasFrozen == true)
    hud(false)
    active, cancelled, protectedEntities, wasFrozen = false, false, nil, nil
end

function PoliceCancelCinematic()
    if active then finish() end
end

function PolicePreviewCinematic(kind)
    local ped = PlayerPedId()
    if not begin({ ped }, 9000) then return end
    SendNUIMessage({ action = 'policeCinematic:show', mode = kind, eyebrow = 'ADMIN CAMERA PREVIEW',
        title = kind == 'impound' and 'IMPOUND COMPLETE' or 'BOOKING INTAKE',
        stars = kind == 'booking' and 3 or 0, minutes = kind == 'booking' and 45 or 0,
        plate = kind == 'impound' and 'PREVIEW' or nil, fee = kind == 'impound' and 5000 or nil,
        reason = 'Preview uses your current position. Hold ESC to finish.' })
    shot(ped, vector3(2.6, 3.8, 1.5), ped, 52.0, 1300)
    shot(ped, vector3(0.0, 1.25, 0.68), ped, 34.0, 1300)
    if active then SendNUIMessage({ action = 'policeCinematic:stamp', label = 'PREVIEW COMPLETE' }); PoliceCinematicSound('confirm'); Wait(1200); finish() end
end

shot = function(entity, offset, target, fov, duration)
    if cancelled or not active then return false end
    if not entity or entity == 0 or not DoesEntityExist(entity) then Wait(duration or 500); return end
    local interior = GetInteriorFromEntity(entity)
    local position = GetOffsetFromEntityInWorldCoords(entity, offset.x * (interior ~= 0 and 0.72 or 1.0), offset.y * (interior ~= 0 and 0.72 or 1.0), offset.z)
    local focus = GetEntityCoords(target and target ~= 0 and target or entity)
    if target and target ~= 0 and DoesEntityExist(target) and IsEntityAPed(target) then focus = GetPedBoneCoords(target, 31086, 0.0, 0.0, 0.0) end
    if rules.cameraCollision ~= false then
        local ray = StartShapeTestRay(focus.x, focus.y, focus.z, position.x, position.y, position.z, 17, entity, 7)
        local _, hit, hitCoords = GetShapeTestResult(ray)
        if hit == 1 then
            local direction = focus - hitCoords
            local length = #direction
            if length > 0.01 then position = hitCoords + direction / length * 0.28 end
        end
    end
    local nextCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(nextCamera, position.x, position.y, position.z)
    if target and target ~= 0 and DoesEntityExist(target) then PointCamAtEntity(nextCamera, target, 0.0, 0.0, 0.65, true)
    else PointCamAtEntity(nextCamera, entity, 0.0, 0.0, 0.65, true) end
    SetCamFov(nextCamera, math.max(30.0, math.min(70.0, (fov or 45.0) + ((tonumber(rules.cameraFov) or 45.0) - 45.0))))
    if camera and DoesCamExist(camera) then
        SetCamActiveWithInterp(nextCamera, camera, 550, true, true)
        local old = camera; SetTimeout(650, function() if DoesCamExist(old) then DestroyCam(old, false) end end)
    else
        SetCamActive(nextCamera, true); RenderScriptCams(true, true, 450, true, true)
    end
    camera = nextCamera
    local effectiveSpeed = (tonumber(rules.sequenceSpeed) or 1.0) * (preferences.mode == 'reduced' and 1.8 or 1.0)
    local deadline = GetGameTimer() + math.floor((duration or 1000) / math.max(0.5, effectiveSpeed))
    while active and not cancelled and GetGameTimer() < deadline do Wait(25) end
    return active and not cancelled
end

begin = function(entities, timeoutMs)
    if active then return false end
    active, cancelled, startedAt, protectedEntities = true, false, GetGameTimer(), entities or {}
    local ok, frozen = pcall(IsEntityPositionFrozen, PlayerPedId()); wasFrozen = ok and frozen == true
    FreezeEntityPosition(PlayerPedId(), true); hud(true)
    CreateThread(function()
        local heldSince
        while active do
            HideHudAndRadarThisFrame(); DisableAllControlActions(0)
            if IsDisabledControlPressed(0, 200) then heldSince = heldSince or GetGameTimer()
            else heldSince = nil end
            local invalid = false
            for _, entity in ipairs(protectedEntities or {}) do
                if entity and entity ~= 0 and not DoesEntityExist(entity) then invalid = true break end
            end
            if invalid or GetGameTimer() - startedAt > (timeoutMs or 15000)
                or (rules.allowSkip ~= false and GetGameTimer() - startedAt > 1000 and heldSince and GetGameTimer() - heldSince > 650) then
                cancelled = true; finish(); break
            end
            Wait(0)
        end
    end)
    return true
end

function PolicePlayBookingIntakeCinematic(targetServerId, preview)
    if not shouldPlay('booking') then return false end
    local player = GetPlayerFromServerId(tonumber(targetServerId) or -1)
    local suspect = player ~= -1 and GetPlayerPed(player) or 0
    if not begin({ PlayerPedId(), suspect }, 12000) then return false end
    local officer, intake = PlayerPedId(), type(PoliceGetJailIntakePed) == 'function' and PoliceGetJailIntakePed() or 0
    SendNUIMessage({ action = 'policeCinematic:show', mode = 'booking', eyebrow = 'POLICE INTAKE',
        title = 'BOOKING IN PROGRESS', stars = tonumber(preview.stars) or 0,
        minutes = tonumber(preview.minutes) or 0, reason = tostring(preview.reason or 'Wanted'),
        suspect = tostring(preview.suspectName or 'Suspect'), characterId = tostring(preview.characterId or ''),
        officer = tostring(preview.officerName or '') })
    shot(intake ~= 0 and intake or officer, vector3(2.2, 3.0, 1.5), suspect ~= 0 and suspect or officer, 52.0, 1000)
    shot(intake ~= 0 and intake or officer, vector3(0.65, 1.35, 0.7), intake ~= 0 and intake or officer, 36.0, 850)
    shot(suspect ~= 0 and suspect or officer, vector3(0.0, 1.25, 0.68), suspect ~= 0 and suspect or officer, 32.0, 1350)
    if not active then return false end
    PoliceCinematicSound('shutter'); if not preferences.reducedFlash then SendNUIMessage({ action = 'policeCinematic:flash' }) end; Wait(450)
    markSeen('booking')
    clearCamera(true); finish(); return true
end

RegisterNetEvent('cm-police:client:bookingCompleted', function(summary)
    if not shouldPlay('jail') then return end
    if active or type(summary) ~= 'table' then return end
    active = true; hud(true)
    SendNUIMessage({ action = 'policeCinematic:show', mode = 'cell', eyebrow = 'CUSTODY CONFIRMED',
        title = 'CELL ASSIGNMENT COMPLETE', stars = tonumber(summary.stars) or 0,
        minutes = tonumber(summary.minutes) or 0, reason = tostring(summary.reason or 'Police booking'), imageUrl = summary.mugshotUrl })
    SendNUIMessage({ action = 'policeCinematic:stamp', label = 'SENTENCE STARTED' })
    PoliceCinematicSound('door')
    markSeen('jail'); Wait(2200); finish()
end)

function PolicePlayImpoundArrival(towTruck, vehicle)
    if not shouldPlay('impound') then
        if towTruck and vehicle and DoesEntityExist(towTruck) and DoesEntityExist(vehicle) then DetachVehicleFromTowTruck(towTruck, vehicle) end
        return true
    end
    if not begin({ PlayerPedId(), towTruck, vehicle }, 12000) then return false end
    SendNUIMessage({ action = 'policeCinematic:show', mode = 'impound', eyebrow = 'POLICE IMPOUND', title = 'VEHICLE INTAKE' })
    shot(towTruck, vector3(5.8, 7.0, 2.5), vehicle, 55.0, 1300)
    shot(vehicle, vector3(2.8, 4.0, 1.2), vehicle, 42.0, 800)
    if towTruck and vehicle and DoesEntityExist(towTruck) and DoesEntityExist(vehicle) then
        PoliceCinematicSound('tow')
        for step = 10, 0, -1 do pcall(SetTowTruckCraneHeight, towTruck, step / 10.0); Wait(55) end
        DetachVehicleFromTowTruck(towTruck, vehicle)
    end
    Wait(650); clearCamera(false); return true
end

RegisterNetEvent('cm-police:client:prepareBookingMugshot', function(duration)
    local ped = PlayerPedId()
    if active or IsEntityDead(ped) then return end
    active, cancelled, startedAt, protectedEntities = true, false, GetGameTimer(), { ped }
    local ok, frozen = pcall(IsEntityPositionFrozen, ped); wasFrozen = ok and frozen == true
    FreezeEntityPosition(ped, true); hud(true)
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.04)
    local forward = GetEntityForwardVector(ped)
    camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(camera, head.x + forward.x * 1.15, head.y + forward.y * 1.15, head.z + 0.02)
    PointCamAtCoord(camera, head.x, head.y, head.z); SetCamFov(camera, 31.0); SetCamActive(camera, true)
    RenderScriptCams(true, false, 0, true, true)
    CreateThread(function()
        local deadline = GetGameTimer() + math.min(5000, math.max(1200, tonumber(duration) or 2200))
        while active and GetGameTimer() < deadline do HideHudAndRadarThisFrame(); Wait(0) end
        if active then finish() end
    end)
end)

RegisterNetEvent('cm-police:client:endBookingMugshot', function()
    if active then finish() end
end)

function PolicePlayImpoundCompletion(towTruck, summary)
    if not active then return end
    summary = type(summary) == 'table' and summary or {}
    SendNUIMessage({ action = 'policeCinematic:update', mode = 'impound', title = 'EVIDENCE FILED',
        imageUrl = summary.imageUrl, reason = summary.reason, plate = summary.plate,
        officer = summary.officerName, owner = summary.ownerName, model = summary.model,
        completedAt = summary.completedAt, fee = summary.fee })
    shot(towTruck, vector3(-4.5, 6.0, 2.0), towTruck, 48.0, 1400)
    local operator = type(PoliceGetNearestImpoundOperator) == 'function' and PoliceGetNearestImpoundOperator() or 0
    if operator ~= 0 then shot(operator, vector3(0.7, 1.4, 0.7), operator, 36.0, 850) end
    SendNUIMessage({ action = 'policeCinematic:stamp', label = 'IMPOUND COMPLETE' })
    PoliceCinematicSound('confirm')
    markSeen('impound'); Wait(1900); clearCamera(true); finish()
end

AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() and active then finish() end end)
