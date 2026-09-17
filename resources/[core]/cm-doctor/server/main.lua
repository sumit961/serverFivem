-- Dual-hospital treatment, pharmacy, bed occupancy and EMS facility access.

local PLAYERDATA, INVENTORY, ITEMACTIONS, EMS = 'cm-playerdata', 'cm-inventory', 'cm-itemactions', 'cm-ems'
local treatmentLocks, bedOccupancy, patientBeds = {}, {}, {}
local waitQueues, queuedHospital = {}, {}
local pendingMedkits = {}
local medicineCooldowns = {}
local pharmacyPurchaseCooldowns = {}

local function notify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function operationSetting(key, fallback)
    if GetResourceState(EMS) == 'started' then
        local ok, value = pcall(function() return exports[EMS]:GetSetting(key) end)
        if ok and value ~= nil then return value end
    end
    return fallback
end

local function coordsTable(coords)
    if not coords then return nil end
    return { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0, h = (coords.w or coords.h or 0.0) + 0.0 }
end

local function distance(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0), (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function playerCoords(src)
    local ped = GetPlayerPed(tonumber(src))
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local coords = GetEntityCoords(ped)
    return { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }
end

local function playerAlive(src)
    local ok, dead = pcall(function() return exports[PLAYERDATA]:IsDead(src) end)
    return ok and dead ~= true
end

local function doctorById(id)
    for _, doctor in ipairs(Config.Doctors or {}) do if doctor.id == tostring(id or '') then return doctor end end
end

local function doctorServices(doctor)
    local services = doctor and doctor.services or {}
    return {
        treatment = services.treatment ~= false,
        pharmacy = services.pharmacy ~= false,
        medicineRun = services.medicineRun == true,
    }
end

local function medicineStockFor(src)
    if GetResourceState(EMS) ~= 'started' then
        return { ready = false, current = 0, maximum = 100, percent = 0, low = true,
            runAvailable = false, runReason = 'EMS medicine stock is unavailable.' }
    end
    local ok, state = pcall(function() return exports[EMS]:GetMedicineStockForSource(tonumber(src)) end)
    if ok and type(state) == 'table' then return state end
    return { ready = false, current = 0, maximum = 100, percent = 0, low = true,
        runAvailable = false, runReason = 'EMS medicine stock is still loading.' }
end

local function characterIdFor(src)
    local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterId(tonumber(src)) end)
    return ok and value and tostring(value) or nil
end

local function medicineReady(itemName)
    itemName = tostring(itemName or ''):lower()
    if itemName == '' or GetResourceState('cm-items') ~= 'started'
        or GetResourceState(ITEMACTIONS) ~= 'started'
        or GetResourceState(INVENTORY) ~= 'started' then
        return false, 'Medicine services are still starting.'
    end
    local itemOk, item = pcall(function() return exports['cm-items']:GetItem(itemName, false) end)
    if not itemOk or type(item) ~= 'table' or item.usable ~= true then
        return false, ('Medicine item "%s" is not registered as usable.'):format(itemName)
    end
    local routeOk, ready, reason = pcall(function() return exports[ITEMACTIONS].IsItemReady(itemName) end)
    if not routeOk or ready ~= true then
        return false, reason or ('Medicine item "%s" has no active use handler.'):format(itemName)
    end
    return true
end

local function medicineEffect(itemName)
    return ((Config.MedicineEffects or {})[tostring(itemName or ''):lower()]) or {}
end

local function cooldownRemaining(src, itemName)
    local expires = medicineCooldowns[tonumber(src)] and medicineCooldowns[tonumber(src)][tostring(itemName or ''):lower()]
    return expires and math.max(0, expires - os.time()) or 0
end

local function startMedicineCooldown(src, itemName)
    local seconds = math.max(0, math.floor(tonumber(medicineEffect(itemName).cooldownSeconds) or 0))
    if seconds <= 0 then return end
    src = tonumber(src)
    medicineCooldowns[src] = medicineCooldowns[src] or {}
    medicineCooldowns[src][tostring(itemName):lower()] = os.time() + seconds
end

local function nearPoint(src, coords, maximum)
    return distance(playerCoords(src), coords) <= (tonumber(maximum) or Config.AccessDistance or 3.0)
end

local function emsAuthorized(src, permission)
    if GetResourceState(EMS) ~= 'started' then return false end
    local characterId
    pcall(function() characterId = exports[PLAYERDATA]:GetCharacterId(src) end)
    if not characterId then return false end
    local onDuty, allowed = false, false
    pcall(function()
        onDuty = exports[EMS]:IsOnDuty(characterId) == true
        allowed = exports[EMS]:HasPermission(characterId, permission) == true
    end)
    return onDuty and allowed
end

local function charge(src, account, amount, reason)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    account = tostring(account or 'cash')
    local canPay, removed = false, false
    pcall(function() canPay = exports[PLAYERDATA]:CanAfford(src, account, amount) == true end)
    if not canPay then return false, ('Not enough %s.'):format(account) end
    pcall(function() removed = exports[PLAYERDATA]:RemoveMoney(src, account, amount, reason) == true end)
    return removed, removed and nil or ('Not enough %s.'):format(account)
end

local function refund(src, account, amount, reason)
    pcall(function() exports[PLAYERDATA]:AddMoney(src, account, amount, reason) end)
end

local function bedKey(hospitalId, bedId) return tostring(hospitalId) .. ':' .. tostring(bedId) end

local function releaseBed(src, reason)
    src = tonumber(src)
    local reservation = src and patientBeds[src]
    if not reservation then return false end
    local key = bedKey(reservation.hospitalId, reservation.bedId)
    if bedOccupancy[key] and bedOccupancy[key].source == src then bedOccupancy[key] = nil end
    patientBeds[src] = nil
    TriggerEvent('cm-ems:server:recordMedicalEvent', src, {
        event = 'discharged', hospitalId = reservation.hospitalId, bedId = reservation.bedId,
        outcome = tostring(reason or 'discharged'),
    })
    return true
end

local function cleanExpiredBeds()
    local now = GetGameTimer()
    for key, reservation in pairs(bedOccupancy) do
        if not GetPlayerName(reservation.source) or now >= (reservation.expiresAt or 0) then
            if patientBeds[reservation.source] and bedKey(patientBeds[reservation.source].hospitalId, patientBeds[reservation.source].bedId) == key then
                patientBeds[reservation.source] = nil
            end
            bedOccupancy[key] = nil
        end
    end
end

local function orderedHospitals(from, preferredId)
    local rows = {}
    for id, hospital in pairs(Config.Hospitals or {}) do
        local first = hospital.beds and hospital.beds[1] and hospital.beds[1].coords
        rows[#rows + 1] = { id = id, hospital = hospital, distance = distance(from, first) }
    end
    table.sort(rows, function(a, b)
        if preferredId then
            if a.id == preferredId and b.id ~= preferredId then return true end
            if b.id == preferredId and a.id ~= preferredId then return false end
        end
        return a.distance < b.distance
    end)
    return rows
end

local function reserveBed(src, preferredId, from, kind)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false, 'Patient is offline.' end
    if operationSetting('hospitalEnabled', true) == false then return false, 'Hospital admissions are temporarily disabled.' end
    cleanExpiredBeds()
    if patientBeds[src] then return true, patientBeds[src] end

    for _, row in ipairs(orderedHospitals(from or playerCoords(src), preferredId)) do
        for _, bed in ipairs(row.hospital.beds or {}) do
            local key = bedKey(row.id, bed.id)
            if not bedOccupancy[key] then
                local reservation = {
                    source = src, hospitalId = row.id, hospitalLabel = row.hospital.label,
                    bedId = bed.id, spawn = coordsTable(bed.coords), kind = tostring(kind or 'treatment'),
                    reservedAt = GetGameTimer(),
                    expiresAt = GetGameTimer() + (tonumber((Config.Hospital or {}).bedReservationMs) or 90000),
                }
                bedOccupancy[key], patientBeds[src] = reservation, reservation
                TriggerClientEvent('cm-doctor:client:bedAssigned', src, reservation)
                return true, reservation
            end
        end
        -- A specifically selected clinic queues locally instead of silently
        -- moving a conscious walk-in to a different town.
        if preferredId then break end
    end
    return false, 'All treatment beds are occupied.'
end

local function hospitalState(hospitalId)
    cleanExpiredBeds()
    local hospital = Config.Hospitals and Config.Hospitals[tostring(hospitalId or '')]
    if not hospital then return nil end
    local occupied = 0
    for _, bed in ipairs(hospital.beds or {}) do if bedOccupancy[bedKey(hospitalId, bed.id)] then occupied = occupied + 1 end end
    return {
        id = hospitalId, label = hospital.label, totalBeds = #(hospital.beds or {}),
        occupiedBeds = occupied, availableBeds = math.max(0, #(hospital.beds or {}) - occupied),
        waiting = #(waitQueues[hospitalId] or {}),
        treatmentPrice = tonumber(operationSetting('treatmentPrice', Config.Treatment.price)) or Config.Treatment.price,
    }
end

local function removeFromQueue(src)
    local hospitalId = queuedHospital[src]
    if not hospitalId then return end
    for index, value in ipairs(waitQueues[hospitalId] or {}) do
        if value == src then table.remove(waitQueues[hospitalId], index); break end
    end
    queuedHospital[src] = nil
end

local function insideTreatmentArea(src, hospitalId)
    local hospital = Config.Hospitals and Config.Hospitals[tostring(hospitalId or '')]
    if not hospital then return false end
    local center = hospital.treatmentCenter or (hospital.beds and hospital.beds[1] and hospital.beds[1].coords)
    return center and distance(playerCoords(src), center) <= (tonumber(hospital.treatmentRadius) or 45.0)
end

local function startTreatment(src, hospitalId, fromQueue)
    if treatmentLocks[src] then return false, 'You are already being treated.' end
    if not playerAlive(src) then return false, 'You are unconscious and cannot check in.' end
    if not insideTreatmentArea(src, hospitalId) then return false, 'You left the hospital treatment area.' end
    local ok, reservation = reserveBed(src, hospitalId, playerCoords(src), 'treatment')
    if not ok then return false, reservation end

    local account = Config.Treatment.account or 'cash'
    local price = tonumber(operationSetting('treatmentPrice', Config.Treatment.price)) or 0
    local paid, why = charge(src, account, price, 'hospital_check_in')
    if not paid then releaseBed(src, 'payment_failed'); return false, why end

    removeFromQueue(src)
    local treatment = { hospitalId = hospitalId, startedAt = GetGameTimer() }
    treatmentLocks[src] = treatment
    TriggerClientEvent('cm-doctor:client:startTreatment', src, Config.Treatment.durationMs, reservation)
    TriggerEvent('cm-ems:server:recordMedicalEvent', src, {
        event = 'hospital_check_in', hospitalId = hospitalId, bedId = reservation.bedId,
        treatment = 'Hospital examination and restorative treatment', billing = price,
    })

    CreateThread(function()
        local data
        pcall(function() data = exports[PLAYERDATA]:GetPlayerData(src) end)
        local startHealth = tonumber(data and data.health) or Config.MaxHealth
        local steps = math.max(1, math.floor(tonumber(Config.Treatment.steps) or 15))
        local stepMs = math.max(50, math.floor((tonumber(Config.Treatment.durationMs) or 30000) / steps))
        for step = 1, steps do
            Wait(stepMs)
            if treatmentLocks[src] ~= treatment then return end
            if not GetPlayerName(src) or not playerAlive(src) or not insideTreatmentArea(src, hospitalId) then
                treatmentLocks[src] = nil
                releaseBed(src, 'treatment_cancelled_left_hospital')
                if GetPlayerName(src) then
                    notify(src, 'Treatment cancelled because you left the hospital area.', 'error')
                    TriggerClientEvent('cm-doctor:client:treatmentCancelled', src, 'You left the hospital treatment area.')
                    TriggerEvent('cm-ems:server:recordMedicalEvent', src, {
                        event = 'hospital_treatment_cancelled', hospitalId = hospitalId,
                        treatment = 'Hospital treatment interrupted', outcome = 'left_hospital', billing = price,
                    })
                end
                return
            end
            local target = math.floor(startHealth + (Config.MaxHealth - startHealth) * (step / steps))
            pcall(function() exports[PLAYERDATA]:SetHealth(src, target, 'hospital_treatment') end)
        end
        if treatmentLocks[src] ~= treatment then return end
        treatmentLocks[src] = nil
        releaseBed(src, 'treatment_complete')
        notify(src, 'Treatment complete. You have been discharged.', 'success')
        TriggerClientEvent('cm-doctor:client:treatmentComplete', src)
        TriggerEvent('cm-ems:server:recordMedicalEvent', src, {
            event = 'hospital_treatment_complete', hospitalId = hospitalId,
            treatment = 'Full hospital treatment', outcome = 'discharged', billing = price,
        })
    end)
    return true, fromQueue and 'A bed is ready. Treatment has started.' or ('Checked in at %s, bed %s.'):format(reservation.hospitalLabel, reservation.bedId)
end

RegisterNetEvent('cm-doctor:server:cancelTreatment', function()
    local src = source
    if not treatmentLocks[src] then return end
    treatmentLocks[src] = nil
    releaseBed(src, 'treatment_cancelled_by_patient')
    notify(src, 'Hospital treatment cancelled.', 'error')
    TriggerClientEvent('cm-doctor:client:treatmentCancelled', src, 'Treatment cancelled.')
end)

CreateThread(function()
    while true do
        Wait(2000)
        cleanExpiredBeds()
        for hospitalId, queue in pairs(waitQueues) do
            while #queue > 0 do
                local src = queue[1]
                if not GetPlayerName(src) or not playerAlive(src) then
                    table.remove(queue, 1); queuedHospital[src] = nil
                else
                    local state = hospitalState(hospitalId)
                    if not state or state.availableBeds <= 0 then break end
                    table.remove(queue, 1); queuedHospital[src] = nil
                    local ok, message = startTreatment(src, hospitalId, true)
                    notify(src, message, ok and 'success' or 'error')
                    break
                end
            end
        end
    end
end)

exports('UseMedicineItem', function(itemName, src, item, name)
    itemName, src = tostring(itemName or ''):lower(), tonumber(src)
    if not src or not GetPlayerName(src) then
        return { success = false, remove = 0, message = 'Invalid medicine user.' }
    end
    if itemName == tostring(Config.Medkit.item or 'medikit'):lower() or itemName == 'medkit' then
        local remaining = cooldownRemaining(src, itemName)
        if remaining > 0 then
            return { success = false, remove = 0, message = ('Wait %d seconds before using another medikit.'):format(remaining) }
        end
        local pending = pendingMedkits[src]
        if pending and GetGameTimer() < pending.expires then
            return { success = false, remove = 0, message = 'Finish your current medkit selection.' }
        end
        pendingMedkits[src] = { expires = GetGameTimer() + 20000, item = itemName }
        TriggerClientEvent('cm-doctor:client:chooseMedkitPatient', src)
        return { success = true, remove = 0, message = 'Choose who should receive the medkit.' }
    end
    local effect = medicineEffect(itemName)
    local healAmount = math.max(0, math.floor(tonumber(effect.heal) or 0))
    if healAmount <= 0 then return { success = false, remove = 0, message = 'This medicine has no configured effect.' } end
    local data
    pcall(function() data = exports[PLAYERDATA]:GetPlayerData(src) end)
    if not data or data.isDead == true then
        return { success = false, remove = 0, message = 'This medicine cannot revive an unconscious patient.' }
    end
    local remaining = cooldownRemaining(src, itemName)
    if remaining > 0 then
        return { success = false, remove = 0, message = ('Wait %d seconds before using %s again.'):format(remaining, itemName) }
    end
    local previousHealth = tonumber(data.health) or Config.MaxHealth
    if previousHealth >= Config.MaxHealth then return { success = false, remove = 0, message = 'You are already at full health.' } end
    local targetHealth = math.min(Config.MaxHealth, previousHealth + healAmount)
    local healed = false
    pcall(function() healed = exports[PLAYERDATA]:SetHealth(src, targetHealth, 'medicine_' .. itemName) == true end)
    if not healed then return { success = false, remove = 0, message = 'The medicine could not be used.' } end
    startMedicineCooldown(src, itemName)
    return { success = true, remove = 1,
        message = ('You used %s and restored %d health.'):format(name or itemName, targetHealth - previousHealth) }
end)

local function registerMedicineItems()
    if GetResourceState(ITEMACTIONS) ~= 'started' then return false end
    local registered = true
    for itemName, effect in pairs(Config.MedicineEffects or {}) do
        local healAmount = math.max(0, math.floor(tonumber(effect.heal) or 0))
        if healAmount > 0 then
            local ok, route = pcall(function()
                return exports[ITEMACTIONS]:RegisterExternalItem(itemName, GetCurrentResourceName(), 'UseMedicineItem')
            end)
            if not ok or route ~= true then
                print(('[cm-doctor] Medicine route failed: %s | call=%s result=%s'):format(itemName, tostring(ok), tostring(route)))
                registered = false
            end
        end
    end

    local function registerMedkit(itemName)
        local ok, route = pcall(function()
            return exports[ITEMACTIONS]:RegisterExternalItem(itemName, GetCurrentResourceName(), 'UseMedicineItem')
        end)
        if not ok or route ~= true then
            print(('[cm-doctor] Medicine route failed: %s | call=%s result=%s'):format(itemName, tostring(ok), tostring(route)))
            registered = false
        end
    end

    registerMedkit(Config.Medkit.item or 'medikit')
    if (Config.Medkit.item or 'medikit') ~= 'medkit' then
        registerMedkit('medkit')
    end
    if not registered then
        print('[cm-doctor] ERROR: One or more medicine use routes failed to register; affected pharmacy sales will remain disabled.')
    end
    return registered
end

CreateThread(function()
    while GetResourceState(ITEMACTIONS) ~= 'started' do Wait(1000) end
    for _ = 1, 30 do
        if registerMedicineItems() then return end
        Wait(1000)
    end
    print('[cm-doctor] ERROR: Medicine handlers were not ready after 30 seconds. Pharmacy sales remain fail-closed.')
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == ITEMACTIONS or resourceName == INVENTORY then
        CreateThread(function()
            Wait(750)
            registerMedicineItems()
        end)
    end
end)

local function withinMedkitRange(src, target)
    if src == target then return true end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then return false end
    local a, b = playerCoords(src), playerCoords(target)
    return distance(a, b) <= 3.5
end

RegisterNetEvent('cm-doctor:server:useMedkit', function(targetSrc)
    local src = source
    local pending = pendingMedkits[src]
    pendingMedkits[src] = nil
    if not pending or GetGameTimer() >= pending.expires then return notify(src, 'Your medkit selection expired.', 'error') end
    local itemName = pending.item
    targetSrc = tonumber(targetSrc) or src
    if not GetPlayerName(targetSrc) or not withinMedkitRange(src, targetSrc) then
        return notify(src, 'The patient is no longer close enough.', 'error')
    end
    local remaining = cooldownRemaining(src, itemName)
    if remaining > 0 then return notify(src, ('Wait %d seconds before using another medikit.'):format(remaining), 'error') end
    local targetData
    pcall(function() targetData = exports[PLAYERDATA]:GetPlayerData(targetSrc) end)
    if not targetData then return notify(src, 'The patient data is unavailable.', 'error') end
    if targetData.isDead ~= true and (tonumber(targetData.health) or Config.MaxHealth) >= Config.MaxHealth then
        return notify(src, targetSrc == src and 'You are already at full health.' or 'That patient is already at full health.', 'error')
    end
    local hasItem = false
    pcall(function() hasItem = exports[INVENTORY]:HasItem(src, itemName, 1) == true end)
    if not hasItem then return notify(src, 'You no longer have a medkit.', 'error') end
    local removed = false
    pcall(function() removed = exports[INVENTORY]:RemoveItem(src, itemName, 1, nil, 'medical_treatment') == true end)
    if not removed then return notify(src, 'The medkit could not be consumed.', 'error') end
    local healed = false
    pcall(function() healed = exports[PLAYERDATA]:Heal(targetSrc, 100, 'medkit') == true end)
    if not healed then
        pcall(function() exports[INVENTORY]:AddItem(src, itemName, 1, nil, 'medical_treatment_refund') end)
        return notify(src, 'Treatment failed. The medkit was returned.', 'error')
    end
    startMedicineCooldown(src, itemName)
    local other = targetSrc ~= src
    notify(src, other and 'You used a medkit and fully stabilized the patient.' or 'The medkit restored you to full health.', 'success')
    if other then
        notify(targetSrc, 'A medkit restored you to full health.', 'success')
        TriggerEvent('cm-ems:server:recordMedicalEvent', targetSrc, {
            event = 'medkit_field_treatment', medicSource = src,
            medications = { 'medkit' }, treatment = 'Medkit full stabilization', outcome = 'revived_or_healed_on_scene',
        })
    end
end)

RegisterNetEvent('cm-doctor:server:cancelMedkit', function()
    pendingMedkits[source] = nil
end)

local function findPurchasable(itemName)
    itemName = tostring(itemName or ''):lower()
    if Config.Medkit and Config.Medkit.item == itemName then return Config.Medkit end
    for _, entry in ipairs(Config.Medicines or {}) do if entry.item == itemName then return entry end end
end

lib.callback.register('cm-doctor:server:getHospitalState', function(_, hospitalId)
    return hospitalState(hospitalId)
end)

lib.callback.register('cm-doctor:server:getDoctorMenuState', function(src, doctorId)
    local doctor = doctorById(doctorId)
    if not doctor or not nearPoint(src, doctor.coords, Config.InteractDistance + 1.0) then
        return nil, 'Move closer to the doctor.'
    end
    return {
        hospital = hospitalState(doctor.hospitalId),
        stock = medicineStockFor(src),
        services = doctorServices(doctor),
    }
end)

lib.callback.register('cm-doctor:server:getTreated', function(src, doctorId)
    local doctor = doctorById(doctorId)
    if not doctor or not nearPoint(src, doctor.coords, Config.InteractDistance + 1.0) then return false, 'Move closer to reception.' end
    if doctorServices(doctor).treatment ~= true then return false, 'This doctor only manages medicine supplies.' end
    local ok, message = startTreatment(src, doctor.hospitalId, false)
    if not ok and message == 'All treatment beds are occupied.' then
        if not queuedHospital[src] then
            waitQueues[doctor.hospitalId] = waitQueues[doctor.hospitalId] or {}
            waitQueues[doctor.hospitalId][#waitQueues[doctor.hospitalId] + 1] = src
            queuedHospital[src] = doctor.hospitalId
        end
        local position = 1
        for index, value in ipairs(waitQueues[doctor.hospitalId]) do if value == src then position = index break end end
        return true, ('All beds are occupied. You joined the waiting room queue at position %d.'):format(position)
    end
    return ok, message
end)

lib.callback.register('cm-doctor:server:buyItem', function(src, doctorId, itemName, quantity)
    local now = GetGameTimer()
    if (pharmacyPurchaseCooldowns[src] or 0) > now then
        return false, 'Please wait before making another pharmacy purchase.', medicineStockFor(src)
    end
    pharmacyPurchaseCooldowns[src] = now + 1500
    local doctor = doctorById(doctorId)
    if not doctor or not nearPoint(src, doctor.coords, Config.InteractDistance + 1.0) then
        return false, 'Move closer to the pharmacy.', medicineStockFor(src)
    end
    if doctorServices(doctor).pharmacy ~= true then
        return false, 'This doctor only manages medicine supplies.', medicineStockFor(src)
    end
    local entry = findPurchasable(itemName)
    if not entry then return false, 'That item is not sold here.', medicineStockFor(src) end
    local ready, readyReason = medicineReady(entry.item)
    if not ready then return false, readyReason, medicineStockFor(src) end
    quantity = math.min(math.max(1, math.floor(tonumber(quantity) or 1)), tonumber(entry.maxQuantity) or 1)
    local total = (tonumber(entry.price) or 0) * quantity
    local canCarry, carryErr = exports[INVENTORY]:CanCarryItem(src, entry.item, quantity)
    if not canCarry then return false, carryErr or 'You cannot carry that much.', medicineStockFor(src) end

    local paid, why = charge(src, 'cash', total, 'hospital_pharmacy_' .. entry.item)
    if not paid then return false, why, medicineStockFor(src) end

    local actorCid = characterIdFor(src)
    local callOk, consumed, stockState, stockUnits, stockError = pcall(function()
        return exports[EMS]:ConsumeMedicineStock(entry.item, quantity, actorCid, 'doctor_pharmacy_sale')
    end)
    if not callOk or consumed ~= true then
        refund(src, 'cash', total, 'hospital_pharmacy_stock_refund')
        return false, stockError or 'Hospital medicine stock is unavailable.', medicineStockFor(src)
    end

    local added = false
    pcall(function()
        added = exports[INVENTORY]:AddItem(src, entry.item, quantity, nil, 'hospital_pharmacy') == true
    end)
    if not added then
        pcall(function()
            exports[EMS]:RestoreMedicineStock(stockUnits, actorCid, 'doctor_pharmacy_inventory_rollback')
        end)
        refund(src, 'cash', total, 'hospital_pharmacy_refund')
        return false, 'Purchase failed. Your money and hospital stock were restored.', medicineStockFor(src)
    end

    TriggerEvent('cm-ems:server:recordMedicalEvent', src, {
        event = 'pharmacy_purchase', hospitalId = doctor.hospitalId,
        medications = { { item = entry.item, quantity = quantity } }, billing = total,
    })
    return true, ('Bought %dx %s for $%d.'):format(quantity, entry.label or entry.item, total),
        type(stockState) == 'table' and stockState or medicineStockFor(src)
end)

lib.callback.register('cm-doctor:server:takeMedicineRun', function(src, doctorId)
    local doctor = doctorById(doctorId)
    if not doctor or not nearPoint(src, doctor.coords, Config.InteractDistance + 1.0) then
        return false, 'Move closer to the supply doctor.', medicineStockFor(src)
    end
    if doctorServices(doctor).medicineRun ~= true then
        return false, 'This doctor does not assign medicine runs.', medicineStockFor(src)
    end
    local callOk, started, message, state = pcall(function()
        return exports[EMS]:StartMedicineRun(src)
    end)
    if not callOk then
        return false, 'The EMS medicine task system is unavailable.', medicineStockFor(src)
    end
    return started == true, message, type(state) == 'table' and state or medicineStockFor(src)
end)

lib.callback.register('cm-doctor:server:facilityAccess', function(src, hospitalId, kind)
    hospitalId, kind = tostring(hospitalId or ''), tostring(kind or '')
    local hospital = Config.Hospitals and Config.Hospitals[hospitalId]
    local point = hospital and hospital[kind]
    if not point or not nearPoint(src, point, Config.AccessDistance + 1.0) then return false, 'Move closer to the facility point.' end
    local permission = ({ storage = 'ems.use_storage', wardrobe = 'ems.use_wardrobe', garage = 'ems.drive_ambulance', helipad = 'ems.fly_helicopter' })[kind]
    if not permission or not emsAuthorized(src, permission) then return false, 'You are not authorized to use this facility.' end
    if kind == 'storage' then
        local ok, err = exports[INVENTORY]:OpenExternalInventory(src, {
            allowed = true, ownerType = 'ems_hospital_storage', ownerId = hospitalId,
            slotPrefix = 'hospital-', slots = tonumber((Config.Hospital or {}).storageSlots) or 30,
            displaySlots = 30, kind = 'ems_storage', label = hospital.label .. ' EMS Storage',
            subtitle = 'On-duty medical supplies', replace = 'equipment', noWeightLimit = true,
            canDeposit = true, canWithdraw = true, data = { hospitalId = hospitalId },
        })
        return ok == true, err
    end
    return true, kind
end)

RegisterNetEvent('cm-doctor:server:discharge', function(reason)
    local src = source
    if releaseBed(src, tostring(reason or 'patient_left_bed')) then notify(src, 'You have been discharged.', 'inform') end
end)

exports('ReserveRespawnBed', function(src, deathCoords)
    local ok, reservation = reserveBed(tonumber(src), nil, deathCoords, 'death_respawn')
    if not ok then return false, reservation end
    reservation.bill = tonumber(operationSetting('deathRespawnPrice', (Config.Hospital or {}).deathRespawnPrice)) or 500
    TriggerEvent('cm-ems:server:recordMedicalEvent', tonumber(src), {
        event = 'hospital_respawn_reserved', hospitalId = reservation.hospitalId,
        bedId = reservation.bedId, treatment = 'Emergency stabilization', outcome = 'admitted', billing = reservation.bill,
    })
    return true, reservation
end)

exports('ReleasePatientBed', releaseBed)
exports('GetHospitalState', hospitalState)
exports('GetHospitals', function()
    local rows = {}
    for id in pairs(Config.Hospitals or {}) do rows[#rows + 1] = hospitalState(id) end
    return rows
end)

AddEventHandler('playerDropped', function()
    local src = source
    treatmentLocks[src] = nil
    pendingMedkits[src] = nil
    medicineCooldowns[src] = nil
    pharmacyPurchaseCooldowns[src] = nil
    removeFromQueue(src)
    releaseBed(src, 'disconnected')
end)
