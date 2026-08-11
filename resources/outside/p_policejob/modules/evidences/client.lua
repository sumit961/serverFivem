while not Config or not Config.Evidences do
    Citizen.Wait(500)
end

if not Config.Evidences.enabled then
    return
end

local EvConfig = Config.Evidences
local hasFlashlightEquipped = false
local lastGunshotTime = 0
local isAnalyzingVehicle = false

Evidences = {
    list = {},
    props = {},
    targets = {},
    recon = {
        active = false,
        expiresAt = 0,
        items = {},
    },
}

Laboratory = { isOpen = false }
Storage = { isOpen = false, lockerId = "main" }

local gloveDrawableWhitelist = {
    [-1] = true, [0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
    [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true,
    [11] = true, [12] = true, [13] = true, [14] = true, [15] = true, [16] = true,
    [113] = true, [114] = true, [115] = true, [199] = true,
}

local collectAnim = {
    dict = "amb@medic@standing@kneel@base",
    clip = "base",
    flag = 1,
}

function getEvidenceType(evidenceType)
    return EvConfig.Types[evidenceType]
end

function getStreetAndZone(coords)
    if not coords or not coords.x or not coords.y or not coords.z then
        return nil
    end

    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    if street == "" or not street then
        street = nil
    end

    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    if zone == "NULL" then
        zone = nil
    end

    return { street = street, zone = zone }
end

function enrichBagsWithLocation(bags)
    for _, bag in ipairs(bags or {}) do
        if bag.coords then
            local location = getStreetAndZone(bag.coords)
            if location then
                bag.street = location.street
                bag.zone = location.zone
            end
        end
    end
    return bags
end

function Evidences.removeTarget(self, evidenceId)
    local zoneId = self.targets[evidenceId]
    if zoneId and Bridge.Target.removeSphereZone then
        pcall(Bridge.Target.removeSphereZone, zoneId)
    end
    self.targets[evidenceId] = nil
end

function Evidences.removeProp(self, evidenceId)
    local prop = self.props[evidenceId]
    if prop and DoesEntityExist(prop) then
        DeleteEntity(prop)
    end
    self.props[evidenceId] = nil
end

function Evidences.cleanupVisuals(self)
    for evidenceId in pairs(self.props) do
        self:removeProp(evidenceId)
    end
    for evidenceId in pairs(self.targets) do
        self:removeTarget(evidenceId)
    end
end

function hasPoliceJobAccess()
    if not Config.Jobs then
        return true
    end
    local job = Bridge.Framework.fetchPlayerJob and Bridge.Framework.fetchPlayerJob()
    if not job then
        return false
    end
    local requiredGrade = Config.Jobs[job.name]
    if requiredGrade == nil then
        return false
    end
    return requiredGrade <= job.grade
end

function isWearingGloves()
    local ped = cache.ped or PlayerPedId()
    local pedModel = GetEntityModel(ped)
    if pedModel ~= 1885233650 and pedModel ~= -1667301416 then
        return false
    end
    return not gloveDrawableWhitelist[GetPedDrawableVariation(ped, 3)]
end

function getVehicleDisplayName(vehicle)
    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local label = GetLabelText(modelName)
    if label and label ~= "NULL" and label ~= "" then
        return label
    end
    return modelName
end

lib.onCache("weapon", function(weaponHash)
    hasFlashlightEquipped = weaponHash == -1951375401
    if not hasFlashlightEquipped then
        Evidences:cleanupVisuals()
    end
end)

lib.onCache("vehicle", function(vehicle)
    local vehicleConfig = EvConfig.Vehicle
    if not vehicleConfig or not vehicleConfig.enabled or not vehicleConfig.fingerprintOnEnter then
        return
    end
    if not vehicle or vehicle == 0 or not NetworkGetEntityIsNetworked(vehicle) then
        return
    end
    if vehicleConfig.checkGloves and isWearingGloves() then
        return
    end

    CreateThread(function()
        Wait(math.random(500, 3000))
        if cache.vehicle ~= vehicle then
            return
        end
        local chance = math.random(1, 100)
        local fingerprintChance = vehicleConfig.fingerprintChance or 100
        if chance > fingerprintChance then
            return
        end
        TriggerServerEvent("p_policejob/server/evidences/vehicle", {
            evidenceType = "fingerprint",
            model = getVehicleDisplayName(vehicle),
        })
    end)
end)

function Evidences.spawnProp(self, evidence)
    if self.props[evidence.id] and DoesEntityExist(self.props[evidence.id]) then
        return
    end

    local typeConfig = getEvidenceType(evidence.type)
    if not typeConfig or not typeConfig.prop then
        return
    end

    local modelHash = type(typeConfig.prop) == "number" and typeConfig.prop or joaat(typeConfig.prop)
    if not IsModelInCdimage(modelHash) or not IsModelValid(modelHash) then
        return
    end

    local loadedModel = lib.requestModel(modelHash, 5000)
    if not loadedModel then
        return
    end

    local zOffset = typeConfig.offset and typeConfig.offset.z or 0
    local prop = CreateObject(
        loadedModel,
        evidence.coords.x, evidence.coords.y, evidence.coords.z + zOffset,
        false, false, false
    )
    SetModelAsNoLongerNeeded(loadedModel)
    if not prop or prop == 0 then
        return
    end

    SetEntityAsMissionEntity(prop, true, true)
    SetEntityCollision(prop, false, false)
    FreezeEntityPosition(prop, true)
    SetEntityRotation(
        prop,
        evidence.rotation.x or 0.0,
        evidence.rotation.y or 0.0,
        evidence.rotation.z or 0.0,
        2, true
    )
    PlaceObjectOnGroundProperly(prop)
    SetEntityAlpha(prop, 220, false)

    if typeConfig.scale and typeConfig.scale ~= 1.0 then
        SetEntityScale(prop, typeConfig.scale, typeConfig.scale, typeConfig.scale)
    end

    self.props[evidence.id] = prop
end

function Evidences.createTarget(self, evidence)
    if self.targets[evidence.id] then
        return
    end

    local typeConfig = getEvidenceType(evidence.type)
    if not typeConfig or not Bridge.Target.addSphereZone then
        return
    end

    local zoneName = "p_policejob/evidence/" .. evidence.id
    local zoneId = Bridge.Target.addSphereZone({
        name = zoneName,
        coords = vec3(evidence.coords.x, evidence.coords.y, evidence.coords.z),
        radius = 0.5,
        debug = false,
        options = {
            {
                name = zoneName .. ":collect",
                label = locale("evidence_collect_target"):format(typeConfig.label),
                icon = "fa-solid fa-vial",
                distance = 2.5,
                onSelect = function()
                    Evidences:collect(evidence.id)
                end,
                canInteract = function()
                    return hasPoliceJobAccess()
                end,
            },
            {
                name = zoneName .. ":clean",
                label = locale("evidence_clean_target"):format(typeConfig.label),
                icon = "fa-solid fa-broom",
                distance = 2.5,
                onSelect = function()
                    Evidences:collect(evidence.id)
                end,
                canInteract = function()
                    return not hasPoliceJobAccess()
                end,
            },
        },
    })

    self.targets[evidence.id] = zoneId or zoneName
end

function Evidences.collect(self, evidenceId)
    local evidence = self.list[evidenceId]
    if not evidence then
        return
    end

    local typeConfig = getEvidenceType(evidence.type)
    if not typeConfig then
        return
    end

    local isPolice = hasPoliceJobAccess()
    local progressLabel = isPolice
        and locale("evidence_collecting"):format(typeConfig.label)
        or locale("evidence_cleaning"):format(typeConfig.label)

    local completed = lib.progressBar({
        duration = isPolice and 4000 or 6000,
        label = progressLabel,
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = collectAnim,
    })

    if not completed then
        return
    end

    self:removeTarget(evidenceId)
    TriggerServerEvent("p_policejob/server/evidences/collect", evidenceId)
end

RegisterNetEvent("p_policejob/client/evidences/sync", function(evidenceList)
    if type(evidenceList) ~= "table" then
        return
    end

    local syncedIds = {}
    for _, evidence in ipairs(evidenceList) do
        evidence.coords = vec3(evidence.coords.x, evidence.coords.y, evidence.coords.z)
        evidence.rotation = vec3(
            evidence.rotation.x or 0,
            evidence.rotation.y or 0,
            evidence.rotation.z or 0
        )
        syncedIds[evidence.id] = true
        Evidences.list[evidence.id] = evidence
    end

    for evidenceId in pairs(Evidences.list) do
        if not syncedIds[evidenceId] then
            Evidences.list[evidenceId] = nil
            Evidences:removeProp(evidenceId)
            Evidences:removeTarget(evidenceId)
        end
    end
end)

RegisterNetEvent("p_policejob/client/evidences/remove", function(evidenceId)
    Evidences.list[evidenceId] = nil
    Evidences:removeProp(evidenceId)
    Evidences:removeTarget(evidenceId)
end)

function drawEvidenceMarker(evidence, distance)
    local typeConfig = getEvidenceType(evidence.type)
    if not typeConfig then
        return
    end

    local color = typeConfig.color or { r = 255, g = 255, b = 255 }
    local alpha = math.floor(math.max(0, math.min(255, (1 - distance / EvConfig.RenderDistance) * 220)))

    DrawMarker(
        25,
        evidence.coords.x, evidence.coords.y, evidence.coords.z - 0.94,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.22, 0.22, 0.22,
        color.r, color.g, color.b, alpha,
        false, false, 2, false, nil, nil, false
    )
end

function drawBulletTracer(evidence)
    local metadata = evidence.metadata
    if not metadata or not metadata.tracerTo or not metadata.tracerFrom then
        return
    end

    local typeConfig = getEvidenceType(evidence.type)
    local color = (typeConfig and typeConfig.color) or { r = 255, g = 200, b = 80 }

    DrawLine(
        metadata.tracerFrom.x, metadata.tracerFrom.y, metadata.tracerFrom.z,
        metadata.tracerTo.x, metadata.tracerTo.y, metadata.tracerTo.z,
        color.r, color.g, color.b, 200
    )
end

CreateThread(function()
    while true do
        if not next(Evidences.list) and not Evidences.recon.active then
            Wait(500)
        elseif not hasFlashlightEquipped and not Evidences.recon.active then
            if next(Evidences.props) or next(Evidences.targets) then
                Evidences:cleanupVisuals()
            end
            Wait(500)
        else
            Wait(0)
            local playerCoords = GetEntityCoords(PlayerPedId())

            for evidenceId, evidence in pairs(Evidences.list) do
                local distance = #(playerCoords - evidence.coords)
                if hasFlashlightEquipped and distance <= EvConfig.RenderDistance then
                    if not Evidences.props[evidenceId] then
                        Evidences:spawnProp(evidence)
                    end
                    if not Evidences.targets[evidenceId] then
                        Evidences:createTarget(evidence)
                    end
                    drawEvidenceMarker(evidence, distance)
                    if evidence.type == "bullet_casing" then
                        drawBulletTracer(evidence)
                    end
                else
                    if Evidences.props[evidenceId] then
                        Evidences:removeProp(evidenceId)
                    end
                    if Evidences.targets[evidenceId] then
                        Evidences:removeTarget(evidenceId)
                    end
                end
            end

            if Evidences.recon.active then
                if GetGameTimer() > Evidences.recon.expiresAt then
                    Evidences.recon.active = false
                    Evidences.recon.items = {}
                else
                    for _, item in ipairs(Evidences.recon.items) do
                        local typeConfig = getEvidenceType(item.type)
                        if typeConfig then
                            local color = typeConfig.color or { r = 200, g = 200, b = 255 }
                            DrawMarker(
                                21,
                                item.coords.x, item.coords.y, item.coords.z + 0.4,
                                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                                0.35, 0.35, 0.35,
                                color.r, color.g, color.b, 120,
                                true, true, 2, true, nil, nil, false
                            )
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler("CEventGunShot", function()
    if not EvConfig.AutoCreate.gunshot.enabled then
        return
    end

    local ped = cache.ped or PlayerPedId()
    if not IsPedShooting(ped) then
        return
    end

    local now = GetGameTimer()
    if now < lastGunshotTime then
        return
    end
    lastGunshotTime = now + 250

    local _, weaponHash = GetCurrentPedWeapon(ped, true)
    local weaponName, serial
    local currentWeapon = Bridge.Inventory.getCurrentWeapon and Bridge.Inventory.getCurrentWeapon()
    if currentWeapon then
        serial = currentWeapon.metadata and currentWeapon.metadata.serial or nil
        weaponName = currentWeapon.label or currentWeapon.name
    end

    local vehicle = cache.vehicle
    local vehicleConfig = EvConfig.Vehicle
    if vehicleConfig and vehicleConfig.enabled and vehicleConfig.casingInVehicle
        and vehicle and vehicle ~= 0 and NetworkGetEntityIsNetworked(vehicle) then
        TriggerServerEvent("p_policejob/server/evidences/vehicle", {
            evidenceType = "bullet_casing",
            model = getVehicleDisplayName(vehicle),
            weaponHash = weaponHash,
            weaponName = weaponName,
            serial = serial,
        })
        return
    end

    local pedCoords = GetEntityCoords(ped)
    local tracerFrom, tracerTo
    local hasImpact, impactCoords = GetPedLastWeaponImpactCoord(ped)
    if hasImpact then
        local direction = pedCoords - impactCoords
        local directionLength = #direction
        if directionLength > 0.001 then
            direction = direction / directionLength
            local tracerLength = EvConfig.AutoCreate.gunshot.tracerLength or 2.5
            tracerFrom = { x = impactCoords.x, y = impactCoords.y, z = impactCoords.z }
            tracerTo = {
                x = impactCoords.x + direction.x * tracerLength,
                y = impactCoords.y + direction.y * tracerLength,
                z = impactCoords.z + direction.z * tracerLength,
            }
        end
    end

    TriggerServerEvent("p_policejob/server/evidences/gunshot", {
        coords = { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z - 0.95 },
        rotation = { x = 0.0, y = 0.0, z = math.random() * 360.0 },
        weaponHash = weaponHash,
        weaponName = weaponName,
        serial = serial,
        tracerFrom = tracerFrom,
        tracerTo = tracerTo,
    })
end)

AddEventHandler("gameEventTriggered", function(eventName, eventData)
    if eventName ~= "CEventNetworkEntityDamage" then
        return
    end
    if not EvConfig.AutoCreate.bloodOnDamage.enabled then
        return
    end

    local victimPed = eventData[1]
    local damageAmount = eventData[6] or 0
    local weaponHash = eventData[7] or 0
    if not IsPedAPlayer(victimPed) then
        return
    end

    local victimPlayer = NetworkGetPlayerIndexFromPed(victimPed)
    if victimPlayer ~= PlayerId() then
        return
    end

    local minDamage = EvConfig.AutoCreate.bloodOnDamage.minDamage or 15.0
    if damageAmount < minDamage or weaponHash == -1569615261 then
        return
    end

    local vehicle = cache.vehicle
    local vehicleConfig = EvConfig.Vehicle
    if vehicleConfig and vehicleConfig.enabled and vehicleConfig.bloodInVehicle
        and vehicle and vehicle ~= 0 and NetworkGetEntityIsNetworked(vehicle) then
        TriggerServerEvent("p_policejob/server/evidences/vehicle", {
            evidenceType = "blood",
            model = getVehicleDisplayName(vehicle),
        })
        return
    end

    local coords = GetEntityCoords(victimPed)
    TriggerServerEvent("p_policejob/server/evidences/blood", {
        coords = { x = coords.x, y = coords.y, z = coords.z - 0.95 },
    })
end)

function useEvidenceReconstructor()
    local nearbyEvidence = lib.callback.await("p_policejob/server/evidences/reconstruction", false)
    if not nearbyEvidence or #nearbyEvidence == 0 then
        return Bridge.Notify.showNotify(locale("evidence_recon_empty"), "error")
    end

    for _, item in ipairs(nearbyEvidence) do
        item.coords = vec3(item.coords.x, item.coords.y, item.coords.z)
    end

    Evidences.recon.active = true
    Evidences.recon.expiresAt = GetGameTimer() + EvConfig.ReconstructionDuration
    Evidences.recon.items = nearbyEvidence
    Bridge.Notify.showNotify(locale("evidence_recon_started"):format(#nearbyEvidence), "success")
end

exports("useEvidenceReconstructor", useEvidenceReconstructor)

if Bridge.Inventory.registerUsableItem then
    Bridge.Inventory.registerUsableItem(EvConfig.ReconstructionItem, useEvidenceReconstructor)
end

function Laboratory.open(self)
    if self.isOpen then
        return
    end
    if not hasPoliceJobAccess() then
        return Bridge.Notify.showNotify(locale("locker_no_access"), "error")
    end

    local bags = enrichBagsWithLocation(
        lib.callback.await("p_policejob/server/evidences/getInventory", false) or {}
    )

    self.isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "setVisibleLaboratory", data = true })
    SendNUIMessage({ action = "setLaboratoryData", data = { bags = bags } })
end

function Laboratory.close(self)
    if not self.isOpen then
        return
    end
    self.isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisibleLaboratory", data = false })
end

function Storage.open(self, lockerId)
    if self.isOpen then
        return
    end
    if not hasPoliceJobAccess() then
        return Bridge.Notify.showNotify(locale("locker_no_access"), "error")
    end

    self.lockerId = tostring(lockerId or "main"):sub(1, 64)
    TriggerServerEvent("p_policejob/server/evidences/openStorage", self.lockerId)
    Wait(100)

    local bags = enrichBagsWithLocation(
        lib.callback.await("p_policejob/server/evidences/getStorageBags", false, self.lockerId) or {}
    )

    self.isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "setVisibleEvidenceStorage", data = true })
    SendNUIMessage({
        action = "setEvidenceStorageData",
        data = { bags = bags, lockerId = self.lockerId },
    })
end

function Storage.close(self)
    if not self.isOpen then
        return
    end
    self.isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisibleEvidenceStorage", data = false })
end

RegisterNUICallback("hideFrame", function(data, cb)
    if data and data.name == "setVisibleLaboratory" then
        Laboratory:close()
    elseif data and data.name == "setVisibleEvidenceStorage" then
        Storage:close()
    end
    cb({})
end)

RegisterNUICallback("evidence/refreshBags", function(_, cb)
    cb(lib.callback.await("p_policejob/server/evidences/getInventory", false) or {})
end)

RegisterNUICallback("evidence/analyze", function(data, cb)
    cb(lib.callback.await("p_policejob/server/evidences/analyze", false, data and data.slot) or { success = false })
end)

RegisterNUICallback("evidence/destroy", function(data, cb)
    cb(lib.callback.await("p_policejob/server/evidences/destroyBag", false, data and data.slot) or { success = false })
end)

RegisterNUICallback("evidence/setWaypoint", function(data, cb)
    local coords = data and data.coords
    if coords and coords.x and coords.y then
        SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
        Bridge.Notify.showNotify(locale("evidence_waypoint_set"), "success")
    end
    cb({})
end)

RegisterNUICallback("evidence/copy", function(data, cb)
    if data and data.value ~= nil then
        lib.setClipboard(tostring(data.value))
        Bridge.Notify.showNotify(locale("copied_evidence_info"), "success")
    end
    cb({})
end)

RegisterNUICallback("evidence/storageOpenLocker", function(data, cb)
    local lockerId = tostring((data and data.lockerId) or "main"):sub(1, 64)
    Storage.lockerId = lockerId
    TriggerServerEvent("p_policejob/server/evidences/openStorage", lockerId)
    Wait(100)
    cb({
        bags = enrichBagsWithLocation(
            lib.callback.await("p_policejob/server/evidences/getStorageBags", false, lockerId) or {}
        ),
        lockerId = lockerId,
    })
end)

RegisterNUICallback("evidence/storageOpenInventory", function(data, cb)
    local lockerId = tostring((data and data.lockerId) or Storage.lockerId or "main"):sub(1, 64)
    TriggerServerEvent("p_policejob/server/evidences/openStorage", lockerId)
    Wait(100)
    Bridge.Inventory.openInventory("stash", {
        id = EvConfig.StorageStashPrefix .. "_" .. lockerId,
    })
    cb({})
end)

RegisterNUICallback("evidence/storagePromptLocker", function(_, cb)
    cb({})
    local defaultLocker = Storage.lockerId or "main"
    Storage:close()
    local input = lib.inputDialog(locale("evidence_storage_prompt_title"), {
        {
            type = "input",
            label = locale("evidence_storage_prompt_label"),
            required = true,
            default = defaultLocker,
        },
    })
    Storage:open(input and input[1] or defaultLocker)
end)

exports("openEvidenceLab", function()
    Laboratory:open()
end)

exports("openEvidenceStorage", function(lockerId)
    Storage:open(lockerId)
end)

exports("openEvidenceStoragePrompt", function()
    local input = lib.inputDialog(locale("evidence_storage_prompt_title"), {
        {
            type = "input",
            label = locale("evidence_storage_prompt_label"),
            required = true,
        },
    })
    if input and input[1] then
        Storage:open(input[1])
    end
end)

CreateThread(function()
    Citizen.Wait(2000)
    if not Bridge.Target.addSphereZone then
        return
    end

    for index, lab in ipairs(Config.DepartmentData.laboratories or {}) do
        if lab.coords then
            Bridge.Target.addSphereZone({
                name = "p_policejob/evidence/lab_" .. index,
                coords = vec3(lab.coords.x, lab.coords.y, lab.coords.z),
                radius = 1.2,
                debug = false,
                options = {
                    {
                        name = "p_policejob/evidence/lab_open_" .. index,
                        label = locale("evidence_open_lab"),
                        icon = "fa-solid fa-microscope",
                        distance = 1.8,
                        groups = Config.Jobs,
                        onSelect = function()
                            Laboratory:open()
                        end,
                    },
                    {
                        name = "p_policejob/evidence/lab_storage_" .. index,
                        label = locale("evidence_open_storage"),
                        icon = "fa-solid fa-boxes-stacked",
                        distance = 1.8,
                        groups = Config.Jobs,
                        onSelect = function()
                            local input = lib.inputDialog(locale("evidence_storage_prompt_title"), {
                                {
                                    type = "input",
                                    label = locale("evidence_storage_prompt_label"),
                                    required = true,
                                    default = "main",
                                },
                            })
                            if input and input[1] then
                                Storage:open(input[1])
                            end
                        end,
                    },
                },
            })

            if lab.blip then
                local blip = AddBlipForCoord(lab.coords.x, lab.coords.y, lab.coords.z)
                SetBlipSprite(blip, lab.blip.sprite or 458)
                SetBlipColour(blip, lab.blip.color or 38)
                SetBlipScale(blip, lab.blip.scale or 0.7)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentSubstringPlayerName(lab.blip.label or lab.label or "Crime Lab")
                EndTextCommandSetBlipName(blip)
            end
        end
    end
end)

function collectVehicleEvidence(plate, evidenceEntry)
    local completed = lib.progressBar({
        duration = 4000,
        label = locale("evidence_collecting"):format(evidenceEntry.label),
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = collectAnim,
    })
    if not completed then
        return
    end
    TriggerServerEvent("p_policejob/server/evidences/collectVehicle", plate, evidenceEntry.id)
end

function showVehicleEvidenceMenu(plate, evidenceList)
    local options = {}
    for _, evidenceEntry in ipairs(evidenceList) do
        options[#options + 1] = {
            title = ("%s - #%s"):format(evidenceEntry.label, evidenceEntry.id),
            description = locale("vehicle_evidence_desc", plate, evidenceEntry.date or "—"),
            icon = "fa-solid fa-vial",
            onSelect = function()
                collectVehicleEvidence(plate, evidenceEntry)
            end,
        }
    end

    lib.registerContext({
        id = "p_policejob_vehicle_evidence",
        title = locale("vehicle_analysis_title"),
        options = options,
    })
    lib.showContext("p_policejob_vehicle_evidence")
end

function analyzeVehicle(vehicle)
    if isAnalyzingVehicle then
        return
    end
    if not hasPoliceJobAccess() then
        return Bridge.Notify.showNotify(locale("locker_no_access"), "error")
    end

    if not vehicle or vehicle == 0 then
        vehicle = cache.vehicle
        if not vehicle or vehicle == 0 then
            vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 5.0, false)
        end
    end

    if not vehicle or vehicle == 0 or not NetworkGetEntityIsNetworked(vehicle) then
        return Bridge.Notify.showNotify(locale("no_closest_vehicle"), "error")
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    isAnalyzingVehicle = true

    local completed = lib.progressBar({
        duration = 3500,
        label = locale("analyzing_vehicle"),
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = collectAnim,
    })

    if not completed then
        isAnalyzingVehicle = false
        return
    end

    local evidenceList = lib.callback.await("p_policejob/server/evidences/getVehicleEvidence", false, plate) or {}
    isAnalyzingVehicle = false

    if #evidenceList == 0 then
        return Bridge.Notify.showNotify(locale("vehicle_evidence_none"), "info")
    end

    showVehicleEvidenceMenu(plate, evidenceList)
end

exports("analyzeVehicle", function(vehicle)
    analyzeVehicle(vehicle)
end)

AddEventHandler("p_policejob/analyzeVehicle", function()
    analyzeVehicle()
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    Evidences:cleanupVisuals()
end)
