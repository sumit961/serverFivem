while not Config or not Config.Evidences do
    Citizen.Wait(500)
end

if not Config.Evidences.enabled then
    return
end

local EvConfig = Config.Evidences
local spatialCellSize = 50.0
local VehicleConfig = EvConfig.Vehicle or {}

Evidences = {
    list = {},
    spatial = {},
    serialCache = {},
    registeredStashes = {},
    vehicles = {},
    nextId = 1,
}

function spatialKey(x, y)
    return ("%d:%d"):format(math.floor(x / spatialCellSize), math.floor(y / spatialCellSize))
end

function getSpatialCellsInRadius(x, y, radius)
    local cellRadius = math.ceil(radius / spatialCellSize)
    local baseX = math.floor(x / spatialCellSize)
    local baseY = math.floor(y / spatialCellSize)
    local cells = {}

    for offsetX = -cellRadius, cellRadius do
        for offsetY = -cellRadius, cellRadius do
            cells[#cells + 1] = ("%d:%d"):format(baseX + offsetX, baseY + offsetY)
        end
    end

    return cells
end

function hashString(value)
    if not value then
        return 0
    end
    local hash = 0
    for index = 1, #value do
        hash = (hash * 31 + string.byte(value, index)) % 2147483647
    end
    return hash
end

function getOrCreateForensics(uniqueId, playerId)
    if not uniqueId then
        return nil
    end

    local cached = Evidences.serialCache[uniqueId]
    if cached then
        return cached
    end

    local hash = hashString(uniqueId)
    local fingerprint = ("FP-%04X-%04X"):format(hash % 65535, math.floor(hash / 65535) % 65535)
    local dna = ("DNA-%05X-%05X-%05X"):format(
        hash % 1048575,
        math.floor(hash / 1048575) % 1048575,
        (hash * 17) % 1048575
    )
    local bloodTypes = EvConfig.BloodTypes
    local bloodType = bloodTypes[(hash % #bloodTypes) + 1] or "O+"

    if playerId and Bridge.Framework.getForensics then
        local forensics = Bridge.Framework.getForensics(playerId)
        if forensics then
            if forensics.fingerprint and forensics.fingerprint ~= "" then
                fingerprint = forensics.fingerprint
            end
            if forensics.bloodType and forensics.bloodType ~= "" then
                bloodType = forensics.bloodType
            end
        end
    end

    local forensicsData = {
        fingerprint = fingerprint,
        dna = dna,
        bloodType = bloodType,
    }
    Evidences.serialCache[uniqueId] = forensicsData
    return forensicsData
end

function hasPoliceJobAccess(playerId)
    if not Config.Jobs then
        return true
    end
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job then
        return false
    end
    local requiredGrade = Config.Jobs[job.name]
    if requiredGrade == nil then
        return false
    end
    return requiredGrade <= job.grade
end

function consumeRequiredItems(playerId, requiredItems)
    if not requiredItems then
        return true
    end
    for itemName, amount in pairs(requiredItems) do
        if Bridge.Inventory.getItemCount(playerId, itemName) < amount then
            return false, itemName
        end
    end
    for itemName, amount in pairs(requiredItems) do
        Bridge.Inventory.removeItem(playerId, itemName, amount)
    end
    return true
end

function Evidences.removeEvidence(self, evidenceId)
    local evidence = self.list[evidenceId]
    if not evidence then
        return
    end

    self.list[evidenceId] = nil
    local cellKey = spatialKey(evidence.coords.x, evidence.coords.y)
    if self.spatial[cellKey] then
        self.spatial[cellKey][evidenceId] = nil
    end
    TriggerClientEvent("p_policejob/client/evidences/remove", -1, evidenceId)
end

function Evidences.enforceAreaLimits(self, evidence)
    local nearbyCells = getSpatialCellsInRadius(evidence.coords.x, evidence.coords.y, EvConfig.AreaRadius)
    local nearbyEvidence = {}

    for _, cellKey in ipairs(nearbyCells) do
        local cell = self.spatial[cellKey]
        if cell then
            for evidenceId in pairs(cell) do
                local existingEvidence = self.list[evidenceId]
                if existingEvidence then
                    local distance = #(evidence.coords - existingEvidence.coords)
                    if distance <= EvConfig.AreaRadius then
                        nearbyEvidence[#nearbyEvidence + 1] = existingEvidence
                    end
                end
            end
        end
    end

    if #nearbyEvidence > EvConfig.MaxPerArea then
        table.sort(nearbyEvidence, function(a, b)
            return a.createdAt < b.createdAt
        end)
        for index = 1, #nearbyEvidence - EvConfig.MaxPerArea do
            self:removeEvidence(nearbyEvidence[index].id)
        end
    end

    local totalCount = 0
    for _ in pairs(self.list) do
        totalCount = totalCount + 1
    end

    if totalCount > EvConfig.MaxWorldEvidences then
        local allEvidence = {}
        for _, existingEvidence in pairs(self.list) do
            allEvidence[#allEvidence + 1] = existingEvidence
        end
        table.sort(allEvidence, function(a, b)
            return a.createdAt < b.createdAt
        end)
        for index = 1, totalCount - EvConfig.MaxWorldEvidences do
            self:removeEvidence(allEvidence[index].id)
        end
    end
end

function serializeEvidence(evidence)
    return {
        id = evidence.id,
        type = evidence.type,
        coords = {
            x = evidence.coords.x,
            y = evidence.coords.y,
            z = evidence.coords.z,
        },
        rotation = {
            x = evidence.rotation.x,
            y = evidence.rotation.y,
            z = evidence.rotation.z,
        },
        metadata = evidence.metadata,
        createdAt = evidence.createdAt,
        expiresAt = evidence.expiresAt,
    }
end

function Evidences.Create(self, payload)
    local typeConfig = EvConfig.Types[payload.type]
    if not typeConfig or not payload.coords then
        return nil
    end

    local evidenceId = self.nextId
    self.nextId = evidenceId + 1
    local createdAt = os.time()

    local evidence = {
        id = evidenceId,
        type = payload.type,
        coords = vec3(payload.coords.x, payload.coords.y, payload.coords.z),
        rotation = payload.rotation and vec3(
            payload.rotation.x or 0,
            payload.rotation.y or 0,
            payload.rotation.z or 0
        ) or vec3(0, 0, math.random() * 360.0),
        owner = payload.owner,
        metadata = payload.metadata or {},
        createdAt = createdAt,
        expiresAt = createdAt + (typeConfig.expire or 3600),
    }

    evidence.metadata.label = typeConfig.label
    evidence.metadata.color = typeConfig.color
    evidence.metadata.prop = typeConfig.prop

    self.list[evidenceId] = evidence

    local cellKey = spatialKey(evidence.coords.x, evidence.coords.y)
    if not self.spatial[cellKey] then
        self.spatial[cellKey] = {}
    end
    self.spatial[cellKey][evidenceId] = true
    self:enforceAreaLimits(evidence)
    return evidence
end

function Evidences.Nearby(self, coords, radius)
    radius = radius or EvConfig.StreamDistance
    local cells = getSpatialCellsInRadius(coords.x, coords.y, radius)
    local nearby = {}

    for _, cellKey in ipairs(cells) do
        local cell = self.spatial[cellKey]
        if cell then
            for evidenceId in pairs(cell) do
                local evidence = self.list[evidenceId]
                if evidence and #(coords - evidence.coords) <= radius then
                    nearby[#nearby + 1] = serializeEvidence(evidence)
                end
            end
        end
    end

    return nearby
end

CreateThread(function()
    while true do
        Citizen.Wait(EvConfig.StreamInterval)
        for _, playerId in ipairs(GetPlayers()) do
            local serverId = tonumber(playerId)
            local ped = GetPlayerPed(serverId)
            if ped and ped ~= 0 then
                TriggerClientEvent(
                    "p_policejob/client/evidences/sync",
                    serverId,
                    Evidences:Nearby(GetEntityCoords(ped), EvConfig.StreamDistance)
                )
            end
        end
    end
end)

CreateThread(function()
    while true do
        Citizen.Wait(30000)
        local now = os.time()
        local expiredIds = {}

        for evidenceId, evidence in pairs(Evidences.list) do
            if now >= evidence.expiresAt then
                expiredIds[#expiredIds + 1] = evidenceId
            end
        end

        for _, evidenceId in ipairs(expiredIds) do
            Evidences:removeEvidence(evidenceId)
        end

        for plate, vehicleEvidence in pairs(Evidences.vehicles) do
            for index = #vehicleEvidence, 1, -1 do
                if now >= vehicleEvidence[index].expiresAt then
                    table.remove(vehicleEvidence, index)
                end
            end
            if #vehicleEvidence == 0 then
                Evidences.vehicles[plate] = nil
            end
        end
    end
end)

RegisterNetEvent("p_policejob/server/evidences/gunshot", function(payload)
    local playerId = source
    if not EvConfig.AutoCreate.gunshot.enabled then
        return
    end
    if type(payload) ~= "table" or not payload.coords then
        return
    end

    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then
        return
    end

    local pedCoords = GetEntityCoords(ped)
    local reportedCoords = vec3(payload.coords.x, payload.coords.y, payload.coords.z)
    if #(pedCoords - reportedCoords) > 12.0 then
        return
    end

    local uniqueId = Bridge.Framework.getUniqueId(playerId)
    local weaponHash = tonumber(payload.weaponHash) or 0
    local caliber = EvConfig.WeaponCalibers[weaponHash] or "Unknown"

    Evidences:Create({
        type = "bullet_casing",
        coords = payload.coords,
        rotation = payload.rotation,
        owner = uniqueId,
        metadata = {
            weaponHash = weaponHash,
            weaponName = payload.weaponName,
            serial = payload.serial,
            caliber = caliber,
            tracerFrom = payload.tracerFrom,
            tracerTo = payload.tracerTo,
        },
    })

    local fingerprintChance = EvConfig.AutoCreate.gunshot.fingerprintChance or 0
    if math.random() < fingerprintChance then
        local forensics = getOrCreateForensics(uniqueId, playerId)
        Evidences:Create({
            type = "fingerprint",
            coords = payload.coords,
            owner = uniqueId,
            metadata = {
                fingerprintId = forensics and forensics.fingerprint or nil,
            },
        })
    end
end)

RegisterNetEvent("p_policejob/server/evidences/blood", function(payload)
    local playerId = source
    if not EvConfig.AutoCreate.bloodOnDamage.enabled then
        return
    end
    if type(payload) ~= "table" or not payload.coords then
        return
    end

    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then
        return
    end

    local pedCoords = GetEntityCoords(ped)
    local reportedCoords = vec3(payload.coords.x, payload.coords.y, payload.coords.z)
    if #(pedCoords - reportedCoords) > 5.0 then
        return
    end

    local uniqueId = Bridge.Framework.getUniqueId(playerId)
    local forensics = getOrCreateForensics(uniqueId, playerId)
    Evidences:Create({
        type = "blood",
        coords = payload.coords,
        owner = uniqueId,
        metadata = {
            dna = forensics and forensics.dna or nil,
            bloodType = forensics and forensics.bloodType or nil,
        },
    })
end)

RegisterNetEvent("p_policejob/server/evidences/collect", function(evidenceId)
    local playerId = source
    local evidence = Evidences.list[tonumber(evidenceId) or 0]
    if not evidence then
        return Bridge.Notify.showNotify(playerId, locale("evidence_not_found"), "error")
    end

    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then
        return
    end

    if #(GetEntityCoords(ped) - evidence.coords) > EvConfig.InteractDistance + 1.5 then
        return Bridge.Notify.showNotify(playerId, locale("evidence_too_far"), "error")
    end

    local typeConfig = EvConfig.Types[evidence.type]
    if not typeConfig then
        return
    end

    local isPolice = hasPoliceJobAccess(playerId)
    local requiredItems = isPolice and typeConfig.requiredItems.police or typeConfig.requiredItems.civilian
    local hasItems, missingItem = consumeRequiredItems(playerId, requiredItems)
    if not hasItems then
        return Bridge.Notify.showNotify(
            playerId,
            locale("evidence_missing_item"):format(missingItem),
            "error"
        )
    end

    if isPolice then
        local bagMetadata = {
            evidenceId = evidence.id,
            evidenceType = evidence.type,
            label = typeConfig.label,
            coords = { x = evidence.coords.x, y = evidence.coords.y, z = evidence.coords.z },
            collectedBy = Bridge.Framework.getPlayerName(playerId),
            collectedAt = os.time(),
            analyzed = false,
            metadata = evidence.metadata,
        }
        local description = ("%s\nCollected: %s"):format(
            typeConfig.label,
            os.date("%Y-%m-%d %H:%M", bagMetadata.collectedAt)
        )
        Bridge.Inventory.addItem(playerId, typeConfig.item, 1, bagMetadata, nil, description)
        Bridge.Notify.showNotify(playerId, locale("evidence_collected"):format(typeConfig.label), "success")

        if Config.Webhooks and Config.Webhooks.evidences and Config.Webhooks.evidences ~= "" then
            Bridge.Logs.Send(
                playerId,
                "Evidences",
                ("%s collected %s (#%d)"):format(bagMetadata.collectedBy, typeConfig.label, evidence.id),
                Config.Webhooks.evidences
            )
        end
    else
        Bridge.Notify.showNotify(playerId, locale("evidence_cleaned"), "success")
        if Config.Webhooks and Config.Webhooks.evidences and Config.Webhooks.evidences ~= "" then
            Bridge.Logs.Send(
                playerId,
                "Evidences",
                ("%s cleaned %s (#%d)"):format(
                    Bridge.Framework.getPlayerName(playerId),
                    typeConfig.label,
                    evidence.id
                ),
                Config.Webhooks.evidences
            )
        end
    end

    Evidences:removeEvidence(evidence.id)
end)

function collectSampleFromPlayer(collectorId, targetId, evidenceType, requiredItems)
    if not hasPoliceJobAccess(collectorId) then
        return Bridge.Notify.showNotify(collectorId, locale("locker_no_access"), "error")
    end

    local targetPed = GetPlayerPed(targetId)
    local collectorPed = GetPlayerPed(collectorId)
    if not targetPed or targetPed == 0 or not collectorPed or collectorPed == 0 then
        return
    end

    if #(GetEntityCoords(collectorPed) - GetEntityCoords(targetPed)) > 3.5 then
        return Bridge.Notify.showNotify(collectorId, locale("evidence_too_far"), "error")
    end

    local typeConfig = EvConfig.Types[evidenceType]
    if not typeConfig then
        return
    end

    local hasItems, missingItem = consumeRequiredItems(collectorId, requiredItems)
    if not hasItems then
        return Bridge.Notify.showNotify(
            collectorId,
            locale("evidence_missing_item"):format(missingItem),
            "error"
        )
    end

    local uniqueId = Bridge.Framework.getUniqueId(targetId)
    local forensics = getOrCreateForensics(uniqueId, targetId)
    local sampleMetadata = {}

    if evidenceType == "blood" then
        sampleMetadata.dna = forensics and forensics.dna or nil
        sampleMetadata.bloodType = forensics and forensics.bloodType or nil
    elseif evidenceType == "fingerprint" then
        sampleMetadata.fingerprintId = forensics and forensics.fingerprint or nil
    end

    local bagMetadata = {
        evidenceType = evidenceType,
        label = typeConfig.label,
        coords = nil,
        collectedBy = Bridge.Framework.getPlayerName(collectorId),
        collectedAt = os.time(),
        analyzed = false,
        metadata = sampleMetadata,
    }

    local description = ("%s\nSuspect ID: %s\nCollected: %s"):format(
        typeConfig.label,
        tostring(targetId),
        os.date("%Y-%m-%d %H:%M", bagMetadata.collectedAt)
    )

    Bridge.Inventory.addItem(collectorId, typeConfig.item, 1, bagMetadata, nil, description)
    Bridge.Notify.showNotify(collectorId, locale("evidence_collected"):format(typeConfig.label), "success")

    if Config.Webhooks and Config.Webhooks.evidences and Config.Webhooks.evidences ~= "" then
        Bridge.Logs.Send(
            collectorId,
            "Evidences",
            ("%s took a %s sample from player %s"):format(
                bagMetadata.collectedBy,
                typeConfig.label,
                tostring(targetId)
            ),
            Config.Webhooks.evidences
        )
    end
end

RegisterNetEvent("p_policejob/server/interactions/TakeBloodSample", function(targetId)
    collectSampleFromPlayer(source, tonumber(targetId), "blood", {
        evidence_kit = 1,
        swab_kit = 1,
    })
end)

RegisterNetEvent("p_policejob/server/interactions/TakeFingerprintSample", function(targetId)
    collectSampleFromPlayer(source, tonumber(targetId), "fingerprint", {
        evidence_kit = 1,
        fingerprint_kit = 1,
    })
end)

local evidenceItemTypes = {}
for evidenceType, typeConfig in pairs(EvConfig.Types) do
    if typeConfig.item then
        evidenceItemTypes[typeConfig.item] = evidenceType
    end
end

function parseEvidenceBag(item)
    if type(item) ~= "table" then
        return nil
    end

    local metadata = item.metadata or item.info or {}
    local evidenceType = metadata.evidenceType or evidenceItemTypes[item.name]
    local typeConfig = evidenceType and EvConfig.Types[evidenceType]
    if not typeConfig then
        return nil
    end

    return {
        slot = item.slot,
        itemName = item.name,
        type = evidenceType,
        label = metadata.label or typeConfig.label,
        coords = metadata.coords,
        collectedBy = metadata.collectedBy,
        collectedAt = metadata.collectedAt,
        analyzed = metadata.analyzed or false,
        metadata = metadata.metadata or {},
        results = metadata.results,
    }
end

function getPlayerEvidenceBags(playerId)
    local items = Bridge.Inventory.getPlayerItems and Bridge.Inventory.getPlayerItems(playerId)
    local bags = {}

    if items then
        for _, item in pairs(items) do
            local bag = parseEvidenceBag(item)
            if bag then
                bags[#bags + 1] = bag
            end
        end
    end

    table.sort(bags, function(a, b)
        return (a.collectedAt or 0) > (b.collectedAt or 0)
    end)

    return bags
end

function generateAnalysisResults(evidenceType, metadata)
    local results = {}

    if evidenceType == "bullet_casing" then
        results.weapon = metadata.weaponName or "Unknown"
        results.serial = metadata.serial or "Unknown"
        results.caliber = metadata.caliber or "Unknown"
        results.residue = ("GSR-%04X"):format(math.random(0, 65535))
        results.rifling = ("R-%04X"):format((metadata.weaponHash or 0) % 65535)
    elseif evidenceType == "blood" then
        results.dna = metadata.dna or "Unknown"
        results.bloodType = metadata.bloodType or "Unknown"
        results.dnaSample = ("SMP-%04X"):format(math.random(0, 65535))
    elseif evidenceType == "fingerprint" then
        results.fingerprintId = metadata.fingerprintId or "Unknown"
        results.matchConfidence = ("%d%%"):format(85 + math.random(0, 14))
        local patterns = { "Loop", "Whorl", "Arch", "Tented Arch" }
        results.pattern = patterns[math.random(1, 4)]
    elseif evidenceType == "drug_residue" then
        results.substanceId = ("SUB-%04X"):format(math.random(0, 65535))
        local substances = metadata.substance or { "Cocaine", "Methamphetamine", "Heroin", "MDMA" }
        results.substance = type(substances) == "table" and substances[math.random(1, #substances)] or substances
        results.purity = ("%d%%"):format(40 + math.random(0, 59))
    elseif evidenceType == "weapon_fragment" then
        results.fragmentId = ("FRG-%04X"):format(math.random(0, 65535))
        local materials = { "Steel", "Polymer", "Aluminum", "Brass" }
        local origins = { "Slide", "Grip", "Magazine", "Barrel" }
        results.material = materials[math.random(1, 4)]
        results.origin = origins[math.random(1, 4)]
    end

    return results
end

lib.callback.register("p_policejob/server/evidences/getInventory", function(source)
    if not hasPoliceJobAccess(source) then
        return {}
    end
    return getPlayerEvidenceBags(source)
end)

lib.callback.register("p_policejob/server/evidences/analyze", function(source, slot)
    if not hasPoliceJobAccess(source) then
        return { success = false }
    end

    local itemSlot = Bridge.Inventory.getItemSlot and Bridge.Inventory.getItemSlot(source, tonumber(slot) or 0)
    if not itemSlot then
        return { success = false }
    end

    local metadata = itemSlot.metadata or {}
    local evidenceType = metadata.evidenceType or evidenceItemTypes[itemSlot.name]
    if not evidenceType or not EvConfig.Types[evidenceType] then
        return { success = false }
    end
    if metadata.analyzed then
        return { success = false }
    end

    local results = generateAnalysisResults(evidenceType, metadata.metadata or {})
    metadata.evidenceType = evidenceType
    metadata.label = metadata.label or EvConfig.Types[evidenceType].label
    metadata.analyzed = true
    metadata.results = results

    if not Bridge.Inventory.setMetadata then
        return { success = false }
    end

    Bridge.Inventory.setMetadata(source, tonumber(slot) or 0, metadata)

    if Config.Webhooks and Config.Webhooks.evidences and Config.Webhooks.evidences ~= "" then
        Bridge.Logs.Send(
            source,
            "Evidences",
            ("%s analyzed %s"):format(
                Bridge.Framework.getPlayerName(source),
                metadata.label or "evidence"
            ),
            Config.Webhooks.evidences
        )
    end

    return { success = true, results = results, type = evidenceType }
end)

lib.callback.register("p_policejob/server/evidences/destroyBag", function(source, slot)
    if not hasPoliceJobAccess(source) then
        return { success = false }
    end

    local itemSlot = Bridge.Inventory.getItemSlot and Bridge.Inventory.getItemSlot(source, tonumber(slot) or 0)
    if not itemSlot then
        return { success = false }
    end

    Bridge.Inventory.removeItem(
        source,
        itemSlot.name,
        itemSlot.count or itemSlot.amount or 1,
        nil,
        tonumber(slot) or 0
    )
    return { success = true }
end)

function registerEvidenceStash(stashId, label, slots, weight)
    if Evidences.registeredStashes[stashId] then
        return
    end
    Evidences.registeredStashes[stashId] = true
    if Bridge.Inventory.registerStash then
        Bridge.Inventory.registerStash(stashId, label, slots, weight)
    end
end

RegisterNetEvent("p_policejob/server/evidences/openStorage", function(lockerId)
    local playerId = source
    if not hasPoliceJobAccess(playerId) then
        return Bridge.Notify.showNotify(playerId, locale("locker_no_access"), "error")
    end

    lockerId = tostring(lockerId or "main"):sub(1, 64)
    registerEvidenceStash(
        EvConfig.StorageStashPrefix .. "_" .. lockerId,
        lockerId,
        EvConfig.StorageStashSlots,
        EvConfig.StorageStashWeight
    )
end)

function getStorageEvidenceBags(stashId)
    local inventory = Bridge.Inventory.getInventory and Bridge.Inventory.getInventory(stashId)
    local items = inventory and inventory.items
    local bags = {}

    if not items then
        return bags
    end

    for _, item in pairs(items) do
        local bag = parseEvidenceBag(item)
        if bag then
            bags[#bags + 1] = bag
        end
    end

    table.sort(bags, function(a, b)
        return (a.collectedAt or 0) > (b.collectedAt or 0)
    end)

    return bags
end

lib.callback.register("p_policejob/server/evidences/getStorageBags", function(source, lockerId)
    if not hasPoliceJobAccess(source) then
        return {}
    end
    lockerId = tostring(lockerId or "main"):sub(1, 64)
    return getStorageEvidenceBags(EvConfig.StorageStashPrefix .. "_" .. lockerId)
end)

lib.callback.register("p_policejob/server/evidences/reconstruction", function(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        return {}
    end
    if Bridge.Inventory.getItemCount(source, EvConfig.ReconstructionItem) < 1 then
        return {}
    end
    return Evidences:Nearby(GetEntityCoords(ped), EvConfig.ReconstructionRadius)
end)

function normalizePlate(plate)
    if type(plate) ~= "string" then
        return nil
    end
    plate = plate:gsub("%s+$", ""):upper()
    if plate == "" then
        return nil
    end
    return plate
end

function addVehicleEvidenceInternal(plate, evidenceType, payload)
    if not VehicleConfig.enabled then
        return nil
    end

    plate = normalizePlate(plate)
    if not plate then
        return nil
    end

    local typeConfig = EvConfig.Types[evidenceType]
    if not typeConfig then
        return nil
    end

    payload = payload or {}
    local evidenceId = Evidences.nextId
    Evidences.nextId = evidenceId + 1
    local createdAt = os.time()
    local expireSeconds = payload.expire or VehicleConfig.expire or typeConfig.expire or 3600

    local evidence = {
        id = evidenceId,
        type = evidenceType,
        plate = plate,
        model = payload.model,
        owner = payload.owner,
        metadata = payload.metadata or {},
        createdAt = createdAt,
        expiresAt = createdAt + expireSeconds,
    }

    evidence.metadata.plate = evidence.metadata.plate or plate
    if evidence.model and not evidence.metadata.model then
        evidence.metadata.model = evidence.model
    end

    if not Evidences.vehicles[plate] then
        Evidences.vehicles[plate] = {}
    end

    local vehicleEvidence = Evidences.vehicles[plate]
    vehicleEvidence[#vehicleEvidence + 1] = evidence

    local maxPerVehicle = VehicleConfig.maxPerVehicle or 20
    while #vehicleEvidence > maxPerVehicle do
        table.remove(vehicleEvidence, 1)
    end

    return evidence
end

exports("addVehicleEvidence", function(plate, evidenceType, payload)
    return addVehicleEvidenceInternal(plate, evidenceType, payload)
end)

local vehicleEvidenceCooldowns = {}

RegisterNetEvent("p_policejob/server/evidences/vehicle", function(payload)
    local playerId = source
    if not VehicleConfig.enabled or type(payload) ~= "table" then
        return
    end

    local evidenceType = payload.evidenceType
    if not EvConfig.Types[evidenceType] then
        return
    end

    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then
        return
    end

    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    if not plate then
        return
    end

    local now = os.time()
    if vehicleEvidenceCooldowns[playerId] and now < vehicleEvidenceCooldowns[playerId] then
        return
    end
    vehicleEvidenceCooldowns[playerId] = now + 1

    local uniqueId = Bridge.Framework.getUniqueId(playerId)
    local forensics = getOrCreateForensics(uniqueId, playerId)
    local metadata = {
        plate = plate,
        model = payload.model,
        player = Bridge.Framework.getPlayerName(playerId),
    }

    if evidenceType == "fingerprint" then
        if not VehicleConfig.fingerprintOnEnter then
            return
        end
        metadata.fingerprintId = forensics and forensics.fingerprint or nil
    elseif evidenceType == "blood" then
        if not VehicleConfig.bloodInVehicle then
            return
        end
        metadata.dna = forensics and forensics.dna or nil
        metadata.bloodType = forensics and forensics.bloodType or nil
    elseif evidenceType == "bullet_casing" then
        if not VehicleConfig.casingInVehicle then
            return
        end
        local weaponHash = tonumber(payload.weaponHash) or 0
        metadata.weaponHash = weaponHash
        metadata.weaponName = payload.weaponName
        metadata.serial = payload.serial
        metadata.caliber = EvConfig.WeaponCalibers[weaponHash] or "Unknown"
    else
        return
    end

    addVehicleEvidenceInternal(plate, evidenceType, {
        owner = uniqueId,
        model = payload.model,
        metadata = metadata,
    })
end)

AddEventHandler("playerDropped", function()
    vehicleEvidenceCooldowns[source] = nil
end)

lib.callback.register("p_policejob/server/evidences/getVehicleEvidence", function(source, plate)
    if not hasPoliceJobAccess(source) then
        return {}
    end

    plate = normalizePlate(plate)
    if not plate then
        return {}
    end

    local vehicleEvidence = Evidences.vehicles[plate]
    if not vehicleEvidence then
        return {}
    end

    local results = {}
    for _, evidence in ipairs(vehicleEvidence) do
        local typeConfig = EvConfig.Types[evidence.type]
        results[#results + 1] = {
            id = evidence.id,
            type = evidence.type,
            plate = evidence.plate,
            model = evidence.model,
            label = (typeConfig and typeConfig.label) or evidence.type,
            metadata = evidence.metadata,
            createdAt = evidence.createdAt,
            date = os.date("%Y-%m-%d %H:%M", evidence.createdAt),
        }
    end

    return results
end)

RegisterNetEvent("p_policejob/server/evidences/collectVehicle", function(plate, evidenceId)
    local playerId = source
    if not hasPoliceJobAccess(playerId) then
        return Bridge.Notify.showNotify(playerId, locale("locker_no_access"), "error")
    end

    plate = normalizePlate(plate)
    if not plate then
        return
    end

    local vehicleEvidence = Evidences.vehicles[plate]
    if not vehicleEvidence then
        return Bridge.Notify.showNotify(playerId, locale("evidence_not_found"), "error")
    end

    evidenceId = tonumber(evidenceId) or 0
    local foundIndex, foundEvidence

    for index, evidence in ipairs(vehicleEvidence) do
        if evidence.id == evidenceId then
            foundIndex = index
            foundEvidence = evidence
            break
        end
    end

    if not foundEvidence then
        return Bridge.Notify.showNotify(playerId, locale("evidence_not_found"), "error")
    end

    local typeConfig = EvConfig.Types[foundEvidence.type]
    if not typeConfig then
        return
    end

    local hasItems, missingItem = consumeRequiredItems(playerId, typeConfig.requiredItems.police)
    if not hasItems then
        return Bridge.Notify.showNotify(
            playerId,
            locale("evidence_missing_item"):format(missingItem),
            "error"
        )
    end

    local bagMetadata = {
        evidenceType = foundEvidence.type,
        label = typeConfig.label,
        coords = nil,
        collectedBy = Bridge.Framework.getPlayerName(playerId),
        collectedAt = os.time(),
        analyzed = false,
        metadata = foundEvidence.metadata,
        source = "vehicle",
        plate = foundEvidence.plate,
    }

    local description = ("%s\nVehicle: %s\nCollected: %s"):format(
        typeConfig.label,
        foundEvidence.plate,
        os.date("%Y-%m-%d %H:%M", bagMetadata.collectedAt)
    )

    Bridge.Inventory.addItem(playerId, typeConfig.item, 1, bagMetadata, nil, description)
    Bridge.Notify.showNotify(playerId, locale("evidence_collected"):format(typeConfig.label), "success")

    table.remove(vehicleEvidence, foundIndex)
    if #vehicleEvidence == 0 then
        Evidences.vehicles[plate] = nil
    end

    if Config.Webhooks and Config.Webhooks.evidences and Config.Webhooks.evidences ~= "" then
        Bridge.Logs.Send(
            playerId,
            "Evidences",
            ("%s collected %s from vehicle %s (#%d)"):format(
                bagMetadata.collectedBy,
                typeConfig.label,
                foundEvidence.plate,
                foundEvidence.id
            ),
            Config.Webhooks.evidences
        )
    end
end)

exports("createEvidence", function(payload)
    return Evidences:Create(payload)
end)

exports("getNearbyEvidences", function(coords, radius)
    return Evidences:Nearby(coords, radius)
end)
