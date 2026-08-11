-- Server-authoritative shared medicine stock and low-stock delivery run.

local VEHICLES_RESOURCE = 'cm-vehicles'
local stockReady = false
local stockCache = { current = 0, maximum = 0 }
local activeRun
local runMutationBusy = false
local lowAlertSent = false
local lastLowAlertAt = 0

local function cfg()
    return Config.MedicineStock or {}
end

local function notifyStock(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function pointDistance(first, second)
    if not first or not second then return math.huge end
    local dx = (tonumber(first.x) or 0.0) - (tonumber(second.x) or 0.0)
    local dy = (tonumber(first.y) or 0.0) - (tonumber(second.y) or 0.0)
    local dz = (tonumber(first.z) or 0.0) - (tonumber(second.z) or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function playerCoords(src)
    local ped = GetPlayerPed(tonumber(src))
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local coords = GetEntityCoords(ped)
    return { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }
end

local function stockPercent()
    local maximum = math.max(1, tonumber(stockCache.maximum) or tonumber(cfg().maxUnits) or 100)
    return math.max(0, math.min(100, math.floor(((tonumber(stockCache.current) or 0) / maximum) * 100 + 0.5)))
end

local function stockSnapshot()
    local percentage = stockPercent()
    return {
        ready = stockReady,
        current = math.max(0, math.floor(tonumber(stockCache.current) or 0)),
        maximum = math.max(1, math.floor(tonumber(stockCache.maximum) or tonumber(cfg().maxUnits) or 100)),
        percent = percentage,
        low = percentage <= math.max(0, math.min(100, tonumber(cfg().triggerPercent) or 40)),
        triggerPercent = math.max(0, math.min(100, tonumber(cfg().triggerPercent) or 40)),
        active = activeRun ~= nil,
    }
end

local function publicRun(run)
    if not run then return nil end
    return {
        runId = run.runId,
        stage = run.stage,
        netId = run.netId,
        plate = run.plate,
        pickup = run.pickup,
        pickupIndex = run.pickupIndex,
        truckSpawn = cfg().truckSpawn,
        reward = math.max(0, math.floor(tonumber(cfg().reward) or 0)),
        xp = math.max(0, math.floor(tonumber(cfg().xp) or 0)),
    }
end

local function refreshStock()
    local row = MySQL.single.await([[
        SELECT current_units, max_units
        FROM cm_ems_medicine_stock
        WHERE stock_key = 'main'
        LIMIT 1
    ]])
    if row then
        stockCache.current = math.max(0, math.floor(tonumber(row.current_units) or 0))
        stockCache.maximum = math.max(1, math.floor(tonumber(row.max_units) or tonumber(cfg().maxUnits) or 100))
    end
    return stockSnapshot()
end

local function broadcastStock()
    local state = stockSnapshot()
    TriggerClientEvent('cm-doctor:client:medicineStockChanged', -1, state)
    return state
end

local function authorizedMember(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) then
        return nil, nil, 'You are not an active EMS employee.'
    end
    if not dbBoolean(member.on_duty) then
        return nil, nil, 'Go on duty before taking the medicine run.'
    end
    local permission = tostring(cfg().permission or 'ems.drive_ambulance')
    if permission ~= '' and not has(member, permission) then
        return nil, nil, 'Your EMS rank cannot take the medicine supply truck.'
    end
    return characterId, member
end

local function notifyLowStock(force)
    if not stockReady then return end
    local state = stockSnapshot()
    if not state.low then return end
    local reminderSeconds = math.max(300, math.floor(tonumber(cfg().lowStockReminderSeconds) or 900))
    if lowAlertSent and not force and os.time() - lastLowAlertAt < reminderSeconds then return end
    lowAlertSent = true
    lastLowAlertAt = os.time()
    local critical = state.percent <= math.max(0, math.min(100, tonumber(cfg().criticalPercent) or 15))
    for _, player in ipairs(GetPlayers()) do
        local src = tonumber(player)
        local characterId = src and cid(src)
        local member = characterId and memberFor(characterId)
        if member and not dbBoolean(member.is_suspended) and dbBoolean(member.on_duty)
            and has(member, tostring(cfg().permission or 'ems.drive_ambulance')) then
            notifyStock(src, ('%s Hospital medicine stock is at %d%%. A supply run is available from the Pillbox supply doctor.')
                :format(critical and 'CRITICAL:' or 'Low stock:', state.percent), critical and 'error' or 'warning')
        end
    end
end

local function itemStockCost(itemName, quantity)
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    local costs = cfg().itemCosts or {}
    local perItem = math.max(1, math.floor(tonumber(costs[tostring(itemName or '')]) or 1))
    return perItem * quantity
end

local function consumeStock(itemName, quantity, actorCharacterId, reason)
    if cfg().enabled == false then return true, stockSnapshot(), 0 end
    if not stockReady then return false, stockSnapshot(), 0, 'Medicine stock is still loading.' end
    local units = itemStockCost(itemName, quantity)
    local affected = MySQL.update.await([[
        UPDATE cm_ems_medicine_stock
        SET current_units = current_units - ?,
            updated_by = ?,
            updated_reason = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE stock_key = 'main' AND current_units >= ?
    ]], { units, actorCharacterId and tostring(actorCharacterId) or nil, tostring(reason or 'medicine_sale'), units })
    if (tonumber(affected) or 0) < 1 then
        local state = refreshStock()
        return false, state, units, ('Hospital medicine stock is too low (%d%%).'):format(state.percent)
    end
    local state = refreshStock()
    broadcastStock()
    notifyLowStock()
    return true, state, units
end

local function restoreStock(units, actorCharacterId, reason)
    if cfg().enabled == false then return true, stockSnapshot() end
    if not stockReady then return false, stockSnapshot() end
    units = math.max(0, math.floor(tonumber(units) or 0))
    if units <= 0 then return true, stockSnapshot() end
    MySQL.update.await([[
        UPDATE cm_ems_medicine_stock
        SET current_units = LEAST(max_units, current_units + ?),
            updated_by = ?,
            updated_reason = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE stock_key = 'main'
    ]], { units, actorCharacterId and tostring(actorCharacterId) or nil, tostring(reason or 'medicine_sale_rollback') })
    local state = refreshStock()
    if not state.low then lowAlertSent = false end
    broadcastStock()
    return true, state
end

local function setStockPercent(percent, actorCharacterId, reason)
    if not stockReady then return false, stockSnapshot(), 'Medicine stock is still loading.' end
    percent = math.max(0, math.min(100, math.floor(tonumber(percent) or 0)))
    local maximum = math.max(1, math.floor(tonumber(stockCache.maximum) or tonumber(cfg().maxUnits) or 100))
    local units = math.floor((maximum * percent) / 100 + 0.5)
    MySQL.update.await([[
        UPDATE cm_ems_medicine_stock
        SET current_units = ?,
            updated_by = ?,
            updated_reason = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE stock_key = 'main'
    ]], { units, actorCharacterId and tostring(actorCharacterId) or nil, tostring(reason or 'admin_stock_set') })
    local state = refreshStock()
    lowAlertSent = not state.low and false or lowAlertSent
    broadcastStock()
    if state.low then notifyLowStock() end
    return true, state
end

local function activeVehicle(run)
    if not run then return nil end
    local entity = tonumber(run.entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
    local netId = tonumber(run.netId)
    if netId and netId > 0 then
        entity = NetworkGetEntityFromNetworkId(netId)
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            run.entity = entity
            return entity
        end
    end
end

local function playerDrivingRunVehicle(src, run)
    local vehicle = activeVehicle(run)
    local ped = GetPlayerPed(tonumber(src))
    if not vehicle or not ped or ped == 0 then return false, vehicle end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return false, vehicle end
    local state = Entity(vehicle).state.cmEmsMedicineRun
    if type(state) ~= 'table' or tonumber(state.runId) ~= tonumber(run.runId)
        or tostring(state.characterId or '') ~= tostring(run.characterId or '') then
        return false, vehicle
    end
    return true, vehicle
end

local function deleteRunVehicle(run)
    if not run then return end
    if run.plate and GetResourceState(VEHICLES_RESOURCE) == 'started' then
        pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(run.plate) end)
        return
    end
    local vehicle = activeVehicle(run)
    if vehicle then DeleteEntity(vehicle) end
end

local function syncRun(run, target)
    if not run then return end
    TriggerClientEvent('cm-ems:client:medicineRunSync', tonumber(target or run.source), publicRun(run), stockSnapshot())
end

local function canTakeRun(src, requireNpc)
    if cfg().enabled == false then return false, 'Medicine stock runs are disabled.' end
    if not stockReady then return false, 'Medicine stock is still loading.' end
    local characterId, _, authError = authorizedMember(src)
    if not characterId then return false, authError end
    if requireNpc ~= false then
        local taskNpc = cfg().taskNpc and cfg().taskNpc.coords
        if not taskNpc or pointDistance(playerCoords(src), taskNpc) > 5.0 then
            return false, 'Move closer to the Pillbox supply doctor.'
        end
    end
    if activeRun then
        if tostring(activeRun.characterId) == tostring(characterId) then
            return false, 'You already have an active medicine supply run.'
        end
        return false, 'Another EMS employee is already completing the medicine supply run.'
    end
    local state = stockSnapshot()
    if not state.low then
        return false, ('Medicine stock is at %d%%. A run becomes available at %d%% or below.'):format(state.percent, state.triggerPercent)
    end
    if GetResourceState(VEHICLES_RESOURCE) ~= 'started' then
        return false, 'cm-vehicles is not ready to spawn the supply truck.'
    end
    return true, nil, characterId
end

local function stockForSource(src)
    local state = stockSnapshot()
    state.runAvailable = false
    state.runReason = nil
    local characterId = cid(src)
    if activeRun and characterId and tostring(activeRun.characterId) == tostring(characterId) then
        state.myRun = publicRun(activeRun)
        state.runReason = 'You already have an active medicine supply run.'
        return state
    end
    local allowed, reason = canTakeRun(src, false)
    state.runAvailable = allowed == true
    state.runReason = reason
    return state
end

local function startMedicineRun(src)
    src = tonumber(src)
    if runMutationBusy then return false, 'The medicine task is being assigned. Try again.' end
    runMutationBusy = true
    local allowed, reason, characterId = canTakeRun(src, true)
    if not allowed then runMutationBusy = false; return false, reason, stockForSource(src) end

    local pickupLocations = cfg().pickupLocations or {}
    if #pickupLocations == 0 then
        runMutationBusy = false
        return false, 'No medicine pickup locations are configured.', stockForSource(src)
    end
    local pickupIndex = math.random(1, #pickupLocations)
    local pickup = pickupLocations[pickupIndex]
    local spawn = cfg().truckSpawn or {}
    local model = tostring(cfg().truckModel or 'mule3')
    local callOk, result = pcall(function()
        return exports[VEHICLES_RESOURCE]:SpawnAdminVehicle(src, model, {
            x = tonumber(spawn.x) or 0.0,
            y = tonumber(spawn.y) or 0.0,
            z = tonumber(spawn.z) or 0.0,
            h = tonumber(spawn.h) or 0.0,
        }, {
            placementKind = 'car',
            label = 'EMS Medicine Supply Truck',
            warp = false,
            engineOn = false,
            frozen = false,
            invincible = false,
            routingBucket = GetPlayerRoutingBucket(src),
        })
    end)
    if not callOk or type(result) ~= 'table' or result.ok ~= true then
        runMutationBusy = false
        local spawnError = type(result) == 'table' and result.error or result
        return false, tostring(spawnError or 'The medicine supply truck could not be spawned.'), stockForSource(src)
    end

    local runId = MySQL.insert.await([[
        INSERT INTO cm_ems_medicine_runs
            (character_id, status, pickup_index, vehicle_plate, started_at, updated_at)
        VALUES (?, 'collect_truck', ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ]], { characterId, pickupIndex, result.plate })
    if not runId then
        pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(result.plate) end)
        runMutationBusy = false
        return false, 'The medicine run could not be saved.', stockForSource(src)
    end

    activeRun = {
        runId = tonumber(runId),
        source = src,
        characterId = characterId,
        stage = 'collect_truck',
        pickupIndex = pickupIndex,
        pickup = {
            label = tostring(pickup.label or ('Pickup ' .. pickupIndex)),
            x = tonumber(pickup.x) or 0.0,
            y = tonumber(pickup.y) or 0.0,
            z = tonumber(pickup.z) or 0.0,
            h = tonumber(pickup.h) or 0.0,
        },
        netId = tonumber(result.netId),
        entity = tonumber(result.entity),
        plate = result.plate,
    }
    local vehicle = activeVehicle(activeRun)
    if vehicle then
        Entity(vehicle).state:set('cmEmsMedicineRun', {
            runId = activeRun.runId,
            characterId = characterId,
            stage = activeRun.stage,
        }, true)
    end
    log(characterId, 'medicine_stock_run_started', {
        runId = activeRun.runId,
        pickupIndex = pickupIndex,
        vehiclePlate = result.plate,
        stockPercent = stockPercent(),
    })
    syncRun(activeRun, src)
    runMutationBusy = false
    return true, 'Medicine supply run started. Collect the marked truck.', stockForSource(src)
end

local function advanceRunStage(src, expectedStage, nextStage, validationPoint)
    src = tonumber(src)
    if runMutationBusy then return false, 'The medicine run is already being updated.' end
    runMutationBusy = true
    local characterId = cid(src)
    if not activeRun or tostring(activeRun.characterId) ~= tostring(characterId) then
        runMutationBusy = false
        return false, 'You do not have an active medicine supply run.'
    end
    if activeRun.stage ~= expectedStage then
        runMutationBusy = false
        return false, 'That medicine run step is no longer active.'
    end
    local driving = playerDrivingRunVehicle(src, activeRun)
    if not driving then
        runMutationBusy = false
        return false, 'You must be driving your assigned medicine supply truck.'
    end
    if validationPoint and pointDistance(playerCoords(src), validationPoint) > 10.0 then
        runMutationBusy = false
        return false, 'Move the medicine supply truck closer to the marked loading point.'
    end
    local run = activeRun
    run.stage = nextStage
    run.source = src
    local vehicle = activeVehicle(run)
    if vehicle then
        Entity(vehicle).state:set('cmEmsMedicineRun', {
            runId = run.runId,
            characterId = characterId,
            stage = nextStage,
        }, true)
    end
    MySQL.update.await([[
        UPDATE cm_ems_medicine_runs
        SET status = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND character_id = ?
    ]], { nextStage, run.runId, characterId })
    syncRun(run, src)
    runMutationBusy = false
    return true
end

local function completeMedicineRun(src)
    src = tonumber(src)
    if runMutationBusy then return false, 'The medicine run is already being updated.' end
    runMutationBusy = true
    local characterId = cid(src)
    if not activeRun or tostring(activeRun.characterId) ~= tostring(characterId) then
        runMutationBusy = false
        return false, 'You do not have an active medicine supply run.'
    end
    if activeRun.stage ~= 'return' then
        runMutationBusy = false
        return false, 'Load the medicine before returning to Pillbox.'
    end
    local driving = playerDrivingRunVehicle(src, activeRun)
    if not driving then
        runMutationBusy = false
        return false, 'You must return in your assigned medicine supply truck.'
    end
    if pointDistance(playerCoords(src), cfg().truckSpawn) > 10.0 then
        runMutationBusy = false
        return false, 'Park the medicine supply truck at the marked Pillbox return point.'
    end

    local run = activeRun
    local maximum = math.max(1, math.floor(tonumber(stockCache.maximum) or tonumber(cfg().maxUnits) or 100))
    MySQL.update.await([[
        UPDATE cm_ems_medicine_stock
        SET current_units = max_units,
            updated_by = ?,
            updated_reason = 'medicine_supply_run',
            updated_at = CURRENT_TIMESTAMP
        WHERE stock_key = 'main'
    ]], { characterId })
    MySQL.update.await([[
        UPDATE cm_ems_medicine_runs
        SET status = 'completed', completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND character_id = ?
    ]], { run.runId, characterId })
    stockCache.current = maximum
    stockCache.maximum = maximum
    lowAlertSent = false

    local reward = math.max(0, math.floor(tonumber(cfg().reward) or 0))
    local paid = reward == 0
    if reward > 0 then
        pcall(function()
            paid = exports[Config.PlayerDataResource]:AddMoney(src, 'bank', reward, 'ems_medicine_supply_run') == true
        end)
    end
    local xp = math.max(0, math.floor(tonumber(cfg().xp) or 0))
    if EMSAwardEmployeeXP then EMSAwardEmployeeXP(characterId, xp) end
    if EMSAddTaskProgress then
        EMSAddTaskProgress(characterId, 'missions_completed', 1, ('medicine_supply_run:%s'):format(run.runId))
    end
    log(characterId, 'medicine_stock_run_completed', {
        runId = run.runId,
        reward = reward,
        xp = xp,
        stock = maximum,
        paymentSucceeded = paid,
    })

    activeRun = nil
    deleteRunVehicle(run)
    broadcastStock()
    TriggerClientEvent('cm-ems:client:medicineRunEnded', src, true,
        paid and ('Medicine stock refilled to 100%%. You earned $%d and %d EMS XP.'):format(reward, xp)
            or ('Medicine stock refilled to 100%%, but the $%d payment failed safely.'):format(reward))
    runMutationBusy = false
    return true, 'Medicine stock refilled.'
end

local function cancelMedicineRun(src, reason)
    src = tonumber(src)
    if runMutationBusy then return false, 'The medicine run is currently updating. Try again.' end
    runMutationBusy = true
    local characterId = src and src > 0 and cid(src) or nil
    local ownsRun = activeRun and (
        src == 0
        or tonumber(activeRun.source) == tonumber(src)
        or (characterId and tostring(activeRun.characterId) == tostring(characterId))
    )
    if not ownsRun then
        runMutationBusy = false
        return false, 'You do not have an active medicine supply run.'
    end
    local run = activeRun
    activeRun = nil
    MySQL.update.await([[
        UPDATE cm_ems_medicine_runs
        SET status = 'cancelled', cancelled_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
    ]], { run.runId })
    deleteRunVehicle(run)
    log(run.characterId, 'medicine_stock_run_cancelled', {
        runId = run.runId,
        reason = tostring(reason or 'cancelled'),
    })
    if run.source and GetPlayerName(run.source) then
        TriggerClientEvent('cm-ems:client:medicineRunEnded', run.source, false, 'Medicine supply run cancelled.')
    end
    runMutationBusy = false
    return true, 'Medicine supply run cancelled.'
end

CreateThread(function()
    local maximum = math.max(1, math.floor(tonumber(cfg().maxUnits) or 100))
    local initial = math.max(0, math.min(maximum, math.floor(tonumber(cfg().initialUnits) or maximum)))
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_ems_medicine_stock (
            stock_key VARCHAR(32) NOT NULL,
            current_units INT UNSIGNED NOT NULL DEFAULT 100,
            max_units INT UNSIGNED NOT NULL DEFAULT 100,
            updated_by VARCHAR(64) NULL,
            updated_reason VARCHAR(80) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (stock_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_ems_medicine_runs (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            character_id VARCHAR(64) NOT NULL,
            status VARCHAR(32) NOT NULL,
            pickup_index TINYINT UNSIGNED NOT NULL,
            vehicle_plate VARCHAR(16) NULL,
            started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP NULL DEFAULT NULL,
            cancelled_at TIMESTAMP NULL DEFAULT NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_cm_ems_medicine_runs_character (character_id),
            KEY idx_cm_ems_medicine_runs_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    MySQL.insert.await([[
        INSERT IGNORE INTO cm_ems_medicine_stock
            (stock_key, current_units, max_units, updated_reason)
        VALUES ('main', ?, ?, 'initial_setup')
    ]], { initial, maximum })
    MySQL.update.await([[
        UPDATE cm_ems_medicine_runs
        SET status = 'cancelled', cancelled_at = COALESCE(cancelled_at, CURRENT_TIMESTAMP),
            updated_at = CURRENT_TIMESTAMP
        WHERE status IN ('collect_truck', 'load', 'return')
    ]])
    refreshStock()
    stockReady = true
    if not stockSnapshot().low then lowAlertSent = false end
    notifyLowStock()
    print(('[cm-ems] Medicine stock ready: %d/%d (%d%%).')
        :format(stockCache.current, stockCache.maximum, stockPercent()))
end)

CreateThread(function()
    while true do
        Wait(60000)
        if stockReady and stockSnapshot().low then notifyLowStock(false) end
    end
end)

-- Cross-file helpers used by server/medicine.lua after all server scripts load.
EMSConsumeMedicineStock = consumeStock
EMSRestoreMedicineStock = restoreStock
EMSGetMedicineStockForSource = stockForSource
EMSStartMedicineRun = startMedicineRun
EMSSetMedicineStockPercent = setStockPercent

exports('GetMedicineStock', function()
    return stockSnapshot()
end)

exports('GetMedicineStockForSource', function(src)
    return stockForSource(tonumber(src))
end)

exports('ConsumeMedicineStock', function(itemName, quantity, actorCharacterId, reason)
    return consumeStock(itemName, quantity, actorCharacterId, reason)
end)

exports('RestoreMedicineStock', function(units, actorCharacterId, reason)
    return restoreStock(units, actorCharacterId, reason)
end)

exports('SetMedicineStockPercent', function(percent, actorCharacterId, reason)
    return setStockPercent(percent, actorCharacterId, reason)
end)

exports('StartMedicineRun', function(src)
    return startMedicineRun(tonumber(src))
end)

lib.callback.register('cm-ems:server:getMedicineStockState', function(src)
    return stockForSource(src)
end)

lib.callback.register('cm-ems:server:medicineRunEnteredTruck', function(src, runId)
    if not activeRun or tonumber(runId) ~= tonumber(activeRun.runId) then return false, 'Medicine run is unavailable.' end
    return advanceRunStage(src, 'collect_truck', 'load')
end)

lib.callback.register('cm-ems:server:loadMedicineTruck', function(src, runId)
    if not activeRun or tonumber(runId) ~= tonumber(activeRun.runId) then return false, 'Medicine run is unavailable.' end
    return advanceRunStage(src, 'load', 'return', activeRun.pickup)
end)

lib.callback.register('cm-ems:server:completeMedicineRun', function(src, runId)
    if not activeRun or tonumber(runId) ~= tonumber(activeRun.runId) then return false, 'Medicine run is unavailable.' end
    return completeMedicineRun(src)
end)

lib.callback.register('cm-ems:server:cancelMedicineRun', function(src)
    return cancelMedicineRun(src, 'player_cancelled')
end)

AddEventHandler('cm-ems:server:memberWentOffDuty', function(src, characterId, reason)
    if not activeRun or tostring(activeRun.characterId or '') ~= tostring(characterId or '') then return end
    cancelMedicineRun(tonumber(src) or 0, reason == 'incapacitated' and 'medic_incapacitated' or 'off_duty')
end)

RegisterCommand('emsstock', function(src, args)
    local allowed = src == 0
    if not allowed then
        local ok, result = pcall(function()
            return exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission)
        end)
        allowed = ok and result == true
    end
    if not allowed then return notifyStock(src, 'You cannot manage EMS medicine stock.', 'error') end

    local requested = tonumber(args[1])
    if requested == nil then
        local state = stockSnapshot()
        local message = ('Medicine stock: %d/%d (%d%%).'):format(state.current, state.maximum, state.percent)
        if src == 0 then print('[cm-ems] ' .. message) else notifyStock(src, message, 'inform') end
        return
    end
    local actor = src == 0 and 'console' or cid(src)
    local ok, state, reason = setStockPercent(requested, actor, 'admin_stock_command')
    local message = ok and ('Medicine stock set to %d/%d (%d%%).'):format(state.current, state.maximum, state.percent)
        or tostring(reason or 'Medicine stock could not be changed.')
    if src == 0 then print('[cm-ems] ' .. message) else notifyStock(src, message, ok and 'success' or 'error') end
end, false)

RegisterCommand('cancelmedrun', function(src)
    if src == 0 then return end
    local ok, message = cancelMedicineRun(src, 'command')
    notifyStock(src, message, ok and 'success' or 'error')
end, false)

AddEventHandler('playerDropped', function()
    local src = source
    if activeRun and tonumber(activeRun.source) == tonumber(src) then
        CreateThread(function()
            local deadline = GetGameTimer() + 5000
            while runMutationBusy and GetGameTimer() < deadline do Wait(100) end
            if activeRun and tonumber(activeRun.source) == tonumber(src) then
                cancelMedicineRun(src, 'player_disconnected')
            end
        end)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if activeRun then deleteRunVehicle(activeRun) end
end)
