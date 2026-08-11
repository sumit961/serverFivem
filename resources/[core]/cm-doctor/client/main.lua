local spawnedPeds, hospitalBlips, nuiOpen, activeDoctor, assignedBed = {}, {}, false, nil, nil
local dialogueCamera

local function notify(message, kind)
    if lib and lib.notify then lib.notify({ title = 'Hospital', description = message, type = kind or 'inform' }) end
end

local function drawScreenPrompt(label)
    SetTextFont(4); SetTextScale(0.36, 0.36); SetTextColour(245, 251, 255, 235); SetTextCentre(false); SetTextOutline()
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(label); EndTextCommandDisplayText(0.040, 0.790)
    DrawRect(0.155, 0.806, 0.235, 0.050, 5, 13, 20, 190)
    DrawRect(0.045, 0.806, 0.032, 0.036, 77, 231, 255, 220)
    SetTextFont(4); SetTextScale(0.34, 0.34); SetTextColour(3, 17, 23, 255); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName('E'); EndTextCommandDisplayText(0.045, 0.795)
end

local function spawnDoctorPed(doctor)
    local model = joaat(Config.PedModel)
    RequestModel(model)
    local deadline = GetGameTimer() + 8000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(10) end
    if not HasModelLoaded(model) then return end
    local c = doctor.coords
    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetEntityAsMissionEntity(ped, true, true); FreezeEntityPosition(ped, true); SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true); SetPedCanRagdoll(ped, false); SetPedDiesWhenInjured(ped, false)
    TaskStartScenarioInPlace(ped, Config.Scenario, 0, true); SetModelAsNoLongerNeeded(model)
    spawnedPeds[#spawnedPeds + 1] = { entity = ped, doctor = doctor }
end

local function createHospitalBlip(doctor)
    local settings = Config.HospitalBlips or {}
    local services = doctor.services or {}
    if settings.enabled == false or (services.treatment == false and services.pharmacy == false) then return end
    local c = doctor.coords
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, tonumber(settings.sprite) or 61)
    SetBlipColour(blip, tonumber(settings.colour) or 3)
    SetBlipScale(blip, tonumber(settings.scale) or 0.82)
    SetBlipAsShortRange(blip, settings.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('Hospital - %s'):format(doctor.name or 'Doctor'))
    EndTextCommandSetBlipName(blip)
    hospitalBlips[#hospitalBlips + 1] = blip
end

local function destroyDialogueCamera()
    if dialogueCamera and DoesCamExist(dialogueCamera) then
        RenderScriptCams(false, true, 350, true, true)
        DestroyCam(dialogueCamera, false)
    end
    dialogueCamera = nil
end

local function focusNpcFace(ped)
    destroyDialogueCamera()
    if not ped or not DoesEntityExist(ped) then return end
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.08)
    local forward = GetEntityForwardVector(ped)
    dialogueCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(dialogueCamera,
        head.x + (forward.x * 1.05),
        head.y + (forward.y * 1.05),
        head.z + 0.08)
    PointCamAtCoord(dialogueCamera, head.x, head.y, head.z)
    SetCamFov(dialogueCamera, 38.0)
    SetCamActive(dialogueCamera, true)
    RenderScriptCams(true, true, 450, true, true)
end

local function closeMenu()
    if not nuiOpen then return end
    nuiOpen, activeDoctor = false, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    destroyDialogueCamera()
end

local function openMenu(doctor, ped)
    if nuiOpen then return end
    local menuState, errorMessage = lib.callback.await('cm-doctor:server:getDoctorMenuState', false, doctor.id)
    if type(menuState) ~= 'table' then
        return notify(errorMessage or 'Doctor services are unavailable.', 'error')
    end
    activeDoctor, nuiOpen = doctor, true
    focusNpcFace(ped)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        data = {
            doctorId = doctor.id,
            doctorName = doctor.name,
            hospital = menuState.hospital,
            stock = menuState.stock,
            services = menuState.services,
            treatment = Config.Treatment,
            medkit = Config.Medkit,
            medicines = Config.Medicines,
        },
    })
end

RegisterNUICallback('close', function(_, cb) closeMenu(); cb({ ok = true }) end)
RegisterNUICallback('getTreated', function(_, cb)
    local ok, message = lib.callback.await('cm-doctor:server:getTreated', false, activeDoctor and activeDoctor.id)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, error = message })
end)
RegisterNUICallback('buyItem', function(data, cb)
    data = type(data) == 'table' and data or {}
    local ok, message, stock = lib.callback.await(
        'cm-doctor:server:buyItem', false, activeDoctor and activeDoctor.id, data.item, data.quantity)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, error = message, stock = stock })
end)

RegisterNUICallback('takeMedicineRun', function(_, cb)
    local ok, message, stock = lib.callback.await(
        'cm-doctor:server:takeMedicineRun', false, activeDoctor and activeDoctor.id)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, error = message, stock = stock })
    if ok then closeMenu() end
end)

RegisterNetEvent('cm-doctor:client:medicineStockChanged', function(stock)
    if not nuiOpen or type(stock) ~= 'table' then return end
    CreateThread(function()
        local menuState = activeDoctor and lib.callback.await(
            'cm-doctor:server:getDoctorMenuState', false, activeDoctor.id) or nil
        SendNUIMessage({
            action = 'stock',
            stock = type(menuState) == 'table' and menuState.stock or stock,
        })
    end)
end)

local function monitorBed(reservation)
    CreateThread(function()
        while assignedBed == reservation and LocalPlayer.state.isDead == true do Wait(500) end
        if assignedBed ~= reservation then return end
        local started = GetGameTimer()
        local origin = vector3(reservation.spawn.x, reservation.spawn.y, reservation.spawn.z)
        local releaseAfter = tonumber((Config.Hospital or {}).treatmentBedReleaseMs) or 45000
        local maxDistance = tonumber((Config.Hospital or {}).dischargeDistance) or 5.0
        while assignedBed == reservation do
            Wait(1000)
            if GetGameTimer() - started >= releaseAfter or #(GetEntityCoords(PlayerPedId()) - origin) > maxDistance then
                TriggerServerEvent('cm-doctor:server:discharge', 'left_bed')
                assignedBed = nil
                break
            end
        end
    end)
end

RegisterNetEvent('cm-doctor:client:bedAssigned', function(reservation)
    if type(reservation) ~= 'table' or type(reservation.spawn) ~= 'table' then return end
    assignedBed = reservation
    if reservation.kind == 'death_respawn' then monitorBed(reservation) end
end)

RegisterNetEvent('cm-doctor:client:startTreatment', function(duration, reservation)
    duration = tonumber(duration) or Config.Treatment.durationMs
    if type(reservation) == 'table' and type(reservation.spawn) == 'table' then
        closeMenu()
        assignedBed = reservation
    end
    if lib and lib.progressCircle then
        local completed = lib.progressCircle({ duration = duration, label = 'Treatment active — remain inside the hospital', position = 'bottom',
            useWhileDead = false, canCancel = true, disable = { combat = true } })
        if completed == false and assignedBed == reservation then
            TriggerServerEvent('cm-doctor:server:cancelTreatment')
        end
    else
        Wait(duration)
    end
end)

RegisterNetEvent('cm-doctor:client:treatmentComplete', function()
    assignedBed = nil
    ClearPedTasksImmediately(PlayerPedId())
end)

RegisterNetEvent('cm-doctor:client:treatmentCancelled', function(message)
    assignedBed = nil
    if lib and lib.progressActive and lib.progressActive() and lib.cancelProgress then lib.cancelProgress() end
    notify(message or 'Hospital treatment cancelled.', 'error')
end)

local function nearbyMedkitPatients(maxDistance)
    local mine, myCoords, patients = PlayerId(), GetEntityCoords(PlayerPedId()), {}
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= mine then
            local ped = GetPlayerPed(player)
            if ped ~= 0 and DoesEntityExist(ped) then
                local dist = #(myCoords - GetEntityCoords(ped))
                if dist <= (maxDistance or 3.5) then
                    patients[#patients + 1] = {
                        value = tostring(GetPlayerServerId(player)),
                        label = ('%s · %.1fm'):format(GetPlayerName(player) or 'Nearby player', dist),
                        distance = dist,
                    }
                end
            end
        end
    end
    table.sort(patients, function(a, b) return a.distance < b.distance end)
    return patients
end

RegisterNetEvent('cm-doctor:client:chooseMedkitPatient', function()
    local patients = nearbyMedkitPatients(3.5)
    if #patients == 0 then
        TriggerServerEvent('cm-doctor:server:useMedkit', GetPlayerServerId(PlayerId()))
        return
    end
    local options = {{ value = 'self', label = 'Use on myself (full health)' }}
    for _, patient in ipairs(patients) do
        options[#options + 1] = { value = patient.value, label = patient.label }
    end
    local answer = lib.inputDialog('Use medkit', {{
        type = 'select', label = 'Choose patient', required = true,
        options = options, default = patients[1].value,
    }})
    if not answer then TriggerServerEvent('cm-doctor:server:cancelMedkit'); return end
    TriggerServerEvent('cm-doctor:server:useMedkit', answer[1] == 'self' and GetPlayerServerId(PlayerId()) or tonumber(answer[1]))
end)

local FacilityLabels = {
    storage = 'Open EMS medical storage', wardrobe = 'Open EMS wardrobe',
    garage = 'Open ambulance fleet', helipad = 'Open air ambulance fleet',
}

local function useFacility(hospitalId, kind)
    local ok, result = lib.callback.await('cm-doctor:server:facilityAccess', false, hospitalId, kind)
    if not ok then notify(result or 'Access denied.', 'error'); return end
    if kind == 'wardrobe' then TriggerEvent('nvCloth:client:openEmsWardrobe', false)
    elseif kind == 'garage' or kind == 'helipad' then TriggerEvent('cm-ems:client:openFleet', kind) end
end

CreateThread(function()
    for _, doctor in ipairs(Config.Doctors or {}) do
        spawnDoctorPed(doctor)
        createHospitalBlip(doctor)
    end
end)

CreateThread(function()
    while true do
        local sleep, playerPosition = 1000, GetEntityCoords(PlayerPedId())
        for _, spawned in ipairs(spawnedPeds) do
            if DoesEntityExist(spawned.entity) then
                local c = spawned.doctor.coords
                local dist = #(playerPosition - vector3(c.x, c.y, c.z))
                if dist <= Config.PromptDistance then
                    sleep = 0
                    if dist <= Config.InteractDistance and not nuiOpen then
                        local services = spawned.doctor.services or {}
                        local prompt = services.medicineRun == true
                            and ('Check medicine stock · %s'):format(spawned.doctor.name)
                            or ('Check in with %s'):format(spawned.doctor.name)
                        drawScreenPrompt(prompt)
                        if IsControlJustPressed(0, Config.Key) then openMenu(spawned.doctor, spawned.entity) end
                    end
                end
            end
        end
        if not nuiOpen then
            local nearest
            for hospitalId, hospital in pairs(Config.Hospitals or {}) do
                for _, kind in ipairs({ 'storage', 'wardrobe', 'garage', 'helipad' }) do
                    local point = hospital[kind]
                    if point then
                        local dist = #(playerPosition - point)
                        if dist <= Config.PromptDistance and (not nearest or dist < nearest.distance) then
                            nearest = { hospitalId = hospitalId, kind = kind, distance = dist }
                        end
                    end
                end
            end
            if nearest then
                sleep = 0
                if nearest.distance <= Config.AccessDistance then
                    drawScreenPrompt(FacilityLabels[nearest.kind])
                    if IsControlJustPressed(0, Config.Key) then useFacility(nearest.hospitalId, nearest.kind) end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closeMenu()
    destroyDialogueCamera()
    for _, blip in ipairs(hospitalBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    for _, spawned in ipairs(spawnedPeds) do if DoesEntityExist(spawned.entity) then DeleteEntity(spawned.entity) end end
end)
