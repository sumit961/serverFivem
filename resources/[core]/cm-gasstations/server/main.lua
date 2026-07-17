local Config = CMGas.Config
CMGas.Server = CMGas.Server or {}

local openSessions = {}
local orderLocks = {}
local openCooldowns = {}
local orderCooldowns = {}
local pendingUse = {}

local function dbg(...)
    if Config.Debug then print('[CM-GAS]', ...) end
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-gas:client:notify', src, tostring(message or ''), kind or 'info')
end

local function normalizePlate(value)
    return tostring(value or ''):upper():gsub('%s+', ''):sub(1, 12)
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function sameHash(left, right)
    left, right = tonumber(left), tonumber(right)
    if not left or not right then return false end
    return (left & 0xFFFFFFFF) == (right & 0xFFFFFFFF)
end

local function getCatalogResource()
    if GetResourceState('cm-items') == 'started' then return 'cm-items' end
    if GetResourceState('cm-item') == 'started' then return 'cm-item' end
    return nil
end

local ITEM_DEFS = {
    [Config.Items.fuelCan] = {
        name = Config.Items.fuelCan,
        label = 'Jerry Can',
        category = 'vehicle',
        itemType = 'normal',
        weight = 2000,
        stack = true,
        usable = true,
        description = 'A portable fuel can. Use it near a vehicle to add fuel.',
    },
    [Config.Items.repairKit] = {
        name = Config.Items.repairKit,
        label = 'Repair Kit',
        category = 'vehicle',
        itemType = 'normal',
        weight = 3000,
        stack = true,
        usable = true,
        description = 'Repairs body damage, tyres, windows and deformation. It does not rebuild the engine.',
    },
    [Config.Items.washKit] = {
        name = Config.Items.washKit,
        label = 'Wash Kit',
        category = 'vehicle',
        itemType = 'normal',
        weight = 1500,
        stack = true,
        usable = true,
        description = 'A sponge and bucket used to clean a nearby vehicle.',
    },
}

local function catalogItemExists(resourceName, itemName)
    for _, method in ipairs({ 'GetCatalogItem', 'GetItem' }) do
        local ok, definition = pcall(function()
            return exports[resourceName][method](itemName)
        end)
        if ok and type(definition) == 'table' and (definition.name or definition.label) then
            return true
        end
    end
    return false
end

local function saveCatalogItem(resourceName, definition)
    for _, method in ipairs({ 'SaveCatalogItem', 'RegisterItem', 'AddCatalogItem', 'CreateItem' }) do
        local ok, result = pcall(function()
            return exports[resourceName][method](definition)
        end)
        if ok and result ~= false then return true end
    end
    return false
end

CreateThread(function()
    local attempts = 0
    local resourceName = getCatalogResource()
    while not resourceName and attempts < 40 do
        Wait(500)
        attempts = attempts + 1
        resourceName = getCatalogResource()
    end

    if not resourceName then
        print('[CM-GAS] cm-items/cm-item is not running. Add the gas-station items manually.')
        return
    end

    for itemName, definition in pairs(ITEM_DEFS) do
        if catalogItemExists(resourceName, itemName) then
            dbg('catalog item already exists:', itemName)
        elseif saveCatalogItem(resourceName, definition) then
            print(('[CM-GAS] Registered catalog item: %s'):format(itemName))
        else
            print(('[CM-GAS] Could not auto-register %s. Add it manually to %s.'):format(itemName, resourceName))
        end
    end
end)

local function playerData()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function getCash(src)
    local api = playerData()
    if not api then return nil end
    local ok, amount = pcall(function() return api:GetCash(src) end)
    if ok and type(amount) == 'number' then return math.floor(amount) end
    return nil
end

local function removeCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:RemoveCash(src, math.floor(amount), reason) end)
    return ok and result == true
end

local function addCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:AddCash(src, math.floor(amount), reason) end)
    return ok and result == true
end

local function charge(src, amount, reason)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local balance = getCash(src)
    if balance == nil then return false, 'Payment system unavailable.' end
    if balance < amount then return false, ('Not enough cash. You need $%d.'):format(amount) end
    if not removeCash(src, amount, reason) then return false, 'Payment could not be completed.' end
    return true
end

local function canCarry(src, itemName, count)
    if GetResourceState('cm-inventory') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports['cm-inventory']:CanCarryItem(src, itemName, count)
    end)
    if ok and type(result) == 'boolean' then return result end
    return false
end

local function giveItem(src, itemName, count)
    if GetResourceState('cm-inventory') == 'started' then
        local ok, result = pcall(function()
            return exports['cm-inventory']:AddItem(src, itemName, count)
        end)
        if ok and result ~= false and result ~= nil then return true end
    end

    local catalog = getCatalogResource()
    if catalog then
        local ok, result = pcall(function()
            return exports[catalog]:GiveCatalogItem(src, itemName, count)
        end)
        if ok and result ~= false and result ~= nil then return true end
    end
    return false
end

local function getClosestPump(coords, maximumDistance)
    local closestIndex, closestDistance
    for index, pump in ipairs(Config.Pumps or {}) do
        local distance = #(coords - pump)
        if distance <= maximumDistance and (not closestDistance or distance < closestDistance) then
            closestIndex = index
            closestDistance = distance
        end
    end
    return closestIndex, closestDistance
end

local function getNetworkVehicle(netId)
    netId = tonumber(netId) or 0
    if netId <= 0 then return nil end
    local ok, entity = pcall(NetworkGetEntityFromNetworkId, netId)
    if not ok or not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    if GetEntityType(entity) ~= 2 then return nil end
    return entity
end

local function getEntityPlate(entity)
    local statePlate
    pcall(function() statePlate = Entity(entity).state.cmPlate end)
    if statePlate and statePlate ~= '' then return normalizePlate(statePlate) end
    local ok, nativePlate = pcall(GetVehicleNumberPlateText, entity)
    if ok then return normalizePlate(nativePlate) end
    return ''
end

local function getManagedVehicleRow(plate)
    if GetResourceState('cm-vehicles') ~= 'started' then return nil end
    local ok, row = pcall(function()
        return exports['cm-vehicles']:GetVehicleByPlate(plate)
    end)
    if ok and type(row) == 'table' then return row end
    return nil
end

local function hasVehicleAccess(src, plate)
    if Config.Security.requireVehicleAccess == false then return true end
    if GetResourceState('cm-vehicles') ~= 'started' then return false end
    local ok, allowed = pcall(function()
        return exports['cm-vehicles']:HasVehicleAccess(src, plate)
    end)
    return ok and allowed == true
end

local function getLiveFuel(entity, row)
    local stateFuel
    pcall(function() stateFuel = Entity(entity).state.cmFuel end)
    if type(stateFuel) == 'number' then return clamp(stateFuel, 0.0, 100.0) end
    return clamp(row and row.fuel or 0.0, 0.0, 100.0)
end

local function validateManagedVehicle(src, netId, suppliedPlate, options)
    options = type(options) == 'table' and options or {}
    local entity = getNetworkVehicle(netId)
    if not entity then return false, 'Vehicle is not available.' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false, 'Player is not available.' end

    local playerBucket = GetPlayerRoutingBucket(src)
    local entityBucket = GetEntityRoutingBucket(entity)
    if playerBucket ~= entityBucket then return false, 'Vehicle is in another routing instance.' end

    local playerCoords = GetEntityCoords(ped)
    local vehicleCoords = GetEntityCoords(entity)
    local maxDistance = tonumber(options.maxDistance) or tonumber(Config.Security.maxVehicleDistance) or 7.5
    if #(playerCoords - vehicleCoords) > maxDistance then return false, 'Move closer to the vehicle.' end

    local actualPlate = getEntityPlate(entity)
    local expectedPlate = normalizePlate(suppliedPlate)
    if actualPlate == '' or (expectedPlate ~= '' and actualPlate ~= expectedPlate) then
        return false, 'Vehicle plate validation failed.'
    end

    local row = getManagedVehicleRow(actualPlate)
    if Config.Security.requireManagedVehicle ~= false and not row then
        return false, 'This vehicle is not registered in CM Vehicles.'
    end

    if row then
        local rowPlate = normalizePlate(row.plate)
        if rowPlate ~= actualPlate then return false, 'Vehicle record does not match.' end

        local statePlate, stateVehicleId = '', nil
        pcall(function()
            statePlate = normalizePlate(Entity(entity).state.cmPlate)
            stateVehicleId = tonumber(Entity(entity).state.cmVehicleId)
        end)
        if Config.Security.requireManagedVehicle ~= false then
            if statePlate == '' or not stateVehicleId then
                return false, 'Vehicle network identity is not ready.'
            end
            if statePlate ~= rowPlate or tonumber(row.id) ~= stateVehicleId then
                return false, 'Vehicle network identity does not match its database record.'
            end
        end

        if row.model ~= nil then
            local expectedModel = tonumber(row.model)
            if not expectedModel then expectedModel = joaat(tostring(row.model)) end
            if expectedModel and not sameHash(expectedModel, GetEntityModel(entity)) then
                return false, 'Vehicle model validation failed.'
            end
        end
    end

    if not hasVehicleAccess(src, actualPlate) then
        return false, 'You do not have keys for this vehicle.'
    end

    local insideVehicle = 0
    pcall(function() insideVehicle = GetVehiclePedIsIn(ped, false) end)
    if insideVehicle and insideVehicle ~= 0 then
        if insideVehicle ~= entity then return false, 'You are inside another vehicle.' end
        local driver = GetPedInVehicleSeat(entity, -1)
        if driver ~= ped then return false, 'Only the driver can use the fuel pump.' end
    else
        local driver = GetPedInVehicleSeat(entity, -1)
        if driver and driver ~= 0 and driver ~= ped then
            return false, 'The vehicle driver must use the fuel pump.'
        end
    end

    if options.pumpIndex then
        local pump = Config.Pumps[tonumber(options.pumpIndex) or 0]
        if not pump then return false, 'Fuel pump session is invalid.' end
        if #(playerCoords - pump) > (tonumber(Config.Security.playerPumpTolerance) or 9.0) then
            return false, 'You moved away from the fuel pump.'
        end
        if #(vehicleCoords - pump) > (tonumber(Config.Security.vehiclePumpTolerance) or 10.0) then
            return false, 'Move the vehicle closer to the fuel pump.'
        end
    end

    return true, {
        entity = entity,
        netId = tonumber(netId),
        plate = actualPlate,
        row = row,
        fuel = getLiveFuel(entity, row),
    }
end

local function serviceVehicle(plate, patch)
    if GetResourceState('cm-vehicles') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports['cm-vehicles']:ServiceVehicle(plate, patch)
    end)
    return ok and result == true
end

local function makeSessionToken(src)
    return ('gas:%d:%d:%d'):format(src, GetGameTimer(), math.random(100000, 999999))
end

local function sendOrderResult(src, ok, message, extra)
    local result = type(extra) == 'table' and extra or {}
    result.ok = ok == true
    result.message = tostring(message or '')
    result.cash = getCash(src) or 0
    TriggerClientEvent('cm-gas:client:orderResult', src, result)
end

RegisterNetEvent('cm-gas:server:requestOpen', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local now = GetGameTimer()
    local cooldown = tonumber(Config.Security.openCooldownMs) or 700
    if now - (openCooldowns[src] or 0) < cooldown then
        return TriggerClientEvent('cm-gas:client:openDenied', src, 'Please wait a moment and try again.')
    end
    openCooldowns[src] = now

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return TriggerClientEvent('cm-gas:client:openDenied', src, 'Player is not available.')
    end

    local playerCoords = GetEntityCoords(ped)
    local pumpIndex = getClosestPump(playerCoords, tonumber(Config.Security.playerPumpTolerance) or 9.0)
    if not pumpIndex then
        return TriggerClientEvent('cm-gas:client:openDenied', src, 'You are not at a fuel pump.')
    end

    local cash = getCash(src)
    if cash == nil then
        return TriggerClientEvent('cm-gas:client:openDenied', src, 'Payment system unavailable.')
    end

    local vehicleInfo
    local netId = tonumber(data.netId) or 0
    if netId > 0 then
        local valid, result = validateManagedVehicle(src, netId, data.plate, {
            maxDistance = Config.Security.maxVehicleDistance,
            pumpIndex = pumpIndex,
        })
        if not valid then
            return TriggerClientEvent('cm-gas:client:openDenied', src, tostring(result))
        end
        vehicleInfo = result
    end

    local token = makeSessionToken(src)
    openSessions[src] = {
        token = token,
        pumpIndex = pumpIndex,
        netId = vehicleInfo and vehicleInfo.netId or 0,
        plate = vehicleInfo and vehicleInfo.plate or '',
        expiresAt = os.time() + (tonumber(Config.Security.sessionSeconds) or 45),
    }

    local row = vehicleInfo and vehicleInfo.row or nil
    TriggerClientEvent('cm-gas:client:openSession', src, {
        sessionToken = token,
        stationName = Config.stationName or 'Gas Station',
        inCar = vehicleInfo ~= nil,
        vehicle = vehicleInfo and {
            plate = vehicleInfo.plate,
            label = tostring((row and row.label) or 'Vehicle'),
            model = tostring((row and row.model) or ''),
        } or nil,
        fuel = vehicleInfo and math.floor(vehicleInfo.fuel + 0.5) or 0,
        maxFuel = tonumber(Config.Refuel.maxFuel) or 100,
        pricePerPercent = tonumber(Config.Pricing.pricePerFuelPercent) or 0,
        fuelCanPrice = tonumber(Config.Pricing.fuelCanPrice) or 0,
        repairKitPrice = tonumber(Config.Pricing.repairKitPrice) or 0,
        washKitPrice = tonumber(Config.Pricing.washKitPrice) or 0,
        maxItemQuantity = tonumber(Config.Security.maxItemQuantity) or 10,
        cash = cash,
    })
end)

RegisterNetEvent('cm-gas:server:cancelSession', function(token)
    local src = source
    local session = openSessions[src]
    if session and session.token == tostring(token or '') then
        openSessions[src] = nil
    end
end)

RegisterNetEvent('cm-gas:server:placeOrder', function(data)
    local src = source
    data = type(data) == 'table' and data or {}

    local now = GetGameTimer()
    local cooldown = tonumber(Config.Security.orderCooldownMs) or 1200
    if now - (orderCooldowns[src] or 0) < cooldown then
        sendOrderResult(src, false, 'Please wait before submitting another order.')
        return
    end
    orderCooldowns[src] = now

    if orderLocks[src] then
        sendOrderResult(src, false, 'Your previous order is still processing.')
        return
    end
    orderLocks[src] = true

    local handled = false
    local function fail(message, invalidate)
        if handled then return end
        handled = true
        if invalidate then openSessions[src] = nil end
        sendOrderResult(src, false, message, { close = invalidate == true })
    end

    local ok, traceback = xpcall(function()
        local session = openSessions[src]
        if not session or session.token ~= tostring(data.sessionToken or '') then
            fail('Fuel station session expired. Open the pump again.', true)
            return
        end
        if os.time() > (session.expiresAt or 0) then
            fail('Fuel station session expired. Open the pump again.', true)
            return
        end

        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then
            fail('Player is not available.', true)
            return
        end
        local pump = Config.Pumps[session.pumpIndex]
        if not pump or #(GetEntityCoords(ped) - pump) > (tonumber(Config.Security.playerPumpTolerance) or 9.0) then
            fail('You moved away from the fuel pump.', true)
            return
        end

        local vehicleInfo
        if session.netId and session.netId > 0 then
            local valid, result = validateManagedVehicle(src, session.netId, session.plate, {
                maxDistance = Config.Security.maxVehicleDistance,
                pumpIndex = session.pumpIndex,
            })
            if not valid then
                fail(tostring(result), true)
                return
            end
            vehicleInfo = result
        end

        local maximumQuantity = tonumber(Config.Security.maxItemQuantity) or 10
        local kits = math.floor(clamp(data.kits, 0, maximumQuantity))
        local cans = math.floor(clamp(data.cans, 0, maximumQuantity))
        local washes = math.floor(clamp(data.washes, 0, maximumQuantity))

        local currentFuel = vehicleInfo and math.floor(vehicleInfo.fuel + 0.5) or 0
        local maximumFuel = math.floor(tonumber(Config.Refuel.maxFuel) or 100)
        local requestedTarget = math.floor(clamp(data.fuelTarget, 0, maximumFuel) + 0.5)
        local targetFuel = vehicleInfo and math.max(currentFuel, requestedTarget) or 0
        local fuelUnits = vehicleInfo and math.max(0, targetFuel - currentFuel) or 0
        if fuelUnits > 0 and fuelUnits < (tonumber(Config.Refuel.minimumPurchase) or 1) then fuelUnits = 0 end
        if fuelUnits == 0 then targetFuel = currentFuel end

        if fuelUnits <= 0 and kits <= 0 and cans <= 0 and washes <= 0 then
            fail('Choose fuel or an item before placing the order.', false)
            return
        end

        if kits > 0 and not canCarry(src, Config.Items.repairKit, kits) then
            fail('You cannot carry that many repair kits.', false)
            return
        end
        if cans > 0 and not canCarry(src, Config.Items.fuelCan, cans) then
            fail('You cannot carry that many jerry cans.', false)
            return
        end
        if washes > 0 and not canCarry(src, Config.Items.washKit, washes) then
            fail('You cannot carry that many wash kits.', false)
            return
        end

        local pricing = Config.Pricing or {}
        local fuelCost = fuelUnits * math.max(0, math.floor(tonumber(pricing.pricePerFuelPercent) or 0))
        local kitCost = kits * math.max(0, math.floor(tonumber(pricing.repairKitPrice) or 0))
        local canCost = cans * math.max(0, math.floor(tonumber(pricing.fuelCanPrice) or 0))
        local washCost = washes * math.max(0, math.floor(tonumber(pricing.washKitPrice) or 0))
        local total = fuelCost + kitCost + canCost + washCost

        local paid, paymentError = charge(src, total, 'gas-station-order')
        if not paid then
            fail(paymentError or 'Payment failed.', false)
            return
        end

        local refund = 0
        local deliveredKits, deliveredCans, deliveredWashes = kits, cans, washes
        local deliveredFuel = 0

        if kits > 0 and not giveItem(src, Config.Items.repairKit, kits) then
            refund = refund + kitCost
            deliveredKits = 0
        end
        if cans > 0 and not giveItem(src, Config.Items.fuelCan, cans) then
            refund = refund + canCost
            deliveredCans = 0
        end
        if washes > 0 and not giveItem(src, Config.Items.washKit, washes) then
            refund = refund + washCost
            deliveredWashes = 0
        end

        if fuelUnits > 0 then
            if vehicleInfo and serviceVehicle(vehicleInfo.plate, { fuel = targetFuel }) then
                deliveredFuel = fuelUnits
            else
                refund = refund + fuelCost
                targetFuel = currentFuel
            end
        end

        if refund > 0 and not addCash(src, refund, 'gas-station-refund') then
            print(('[CM-GAS] CRITICAL: refund of $%d failed for source %d'):format(refund, src))
        end

        local parts = {}
        if deliveredFuel > 0 then parts[#parts + 1] = ('%d%% fuel'):format(deliveredFuel) end
        if deliveredKits > 0 then parts[#parts + 1] = ('%dx repair kit'):format(deliveredKits) end
        if deliveredCans > 0 then parts[#parts + 1] = ('%dx jerry can'):format(deliveredCans) end
        if deliveredWashes > 0 then parts[#parts + 1] = ('%dx wash kit'):format(deliveredWashes) end

        local paidTotal = total - refund
        if #parts == 0 then
            fail('Nothing could be delivered. Your payment was refunded.', false)
            return
        end

        openSessions[src] = nil
        handled = true
        local message = ('Order complete: %s — $%d.'):format(table.concat(parts, ', '), paidTotal)
        sendOrderResult(src, true, message, {
            netId = vehicleInfo and vehicleInfo.netId or 0,
            fuel = deliveredFuel > 0 and targetFuel or nil,
            paid = paidTotal,
        })
        notify(src, message, 'success')
    end, debug.traceback)

    orderLocks[src] = nil
    if not ok then
        print(('[CM-GAS] Order error for source %d:\n%s'):format(src, traceback))
        if not handled then sendOrderResult(src, false, 'The order could not be completed.') end
    end
end)

local function durationFor(kind)
    local durations = Config.ItemUse and Config.ItemUse.durationMs or {}
    return math.max(1000, math.floor(tonumber(durations[kind]) or 5000))
end

RegisterNetEvent('cm-gas:server:useResult', function(token, clientOk, message, netId, plate)
    local src = source
    local pending = pendingUse[src]
    if not pending or pending.token ~= tostring(token or '') or pending.done then return end

    if clientOk ~= true then
        pending.done = true
        pending.ok = false
        pending.message = tostring(message or 'Cancelled.')
        return
    end

    local tolerance = tonumber(Config.ItemUse.earlyFinishToleranceMs) or 750
    if GetGameTimer() + tolerance < pending.minFinishAt then
        pending.done = true
        pending.ok = false
        pending.message = 'Action finished too quickly.'
        return
    end

    local valid, vehicleInfo = validateManagedVehicle(src, netId, plate, {
        maxDistance = tonumber(Config.ItemUse.maxVehicleDistance) or 6.0,
    })
    if not valid then
        pending.done = true
        pending.ok = false
        pending.message = tostring(vehicleInfo)
        return
    end

    local row = vehicleInfo.row or {}
    local patch, preserve = {}, {
        engineHealth = tonumber(row.engine_health) or 1000.0,
        tankHealth = tonumber(row.tank_health) or 1000.0,
        dirtLevel = tonumber(row.dirt_level) or 0.0,
    }

    if pending.kind == 'fuelCan' then
        local target = math.min(
            tonumber(Config.Refuel.maxFuel) or 100.0,
            vehicleInfo.fuel + (tonumber(Config.ItemUse.fuelCanAmount) or 25.0)
        )
        if target <= vehicleInfo.fuel + 0.1 then
            pending.done = true
            pending.ok = false
            pending.message = 'The fuel tank is already full.'
            return
        end
        patch.fuel = target
    elseif pending.kind == 'repairKit' then
        local currentBody = tonumber(row.body_health) or 0.0
        patch.bodyHealth = math.min(1000.0, currentBody + (tonumber(Config.ItemUse.repairBodyAmount) or 650.0))
    elseif pending.kind == 'washKit' then
        patch.dirtLevel = tonumber(Config.ItemUse.washDirtLevel) or 0.0
    else
        pending.done = true
        pending.ok = false
        pending.message = 'Unknown vehicle item.'
        return
    end

    if not serviceVehicle(vehicleInfo.plate, patch) then
        pending.done = true
        pending.ok = false
        pending.message = 'Vehicle state could not be updated.'
        return
    end

    TriggerClientEvent('cm-gas:client:applyAuthorizedService', src, pending.kind, vehicleInfo.netId, patch, preserve)
    pending.done = true
    pending.ok = true
    pending.message = pending.kind == 'fuelCan' and 'Vehicle refuelled with the jerry can.'
        or pending.kind == 'repairKit' and 'Vehicle body repaired.'
        or 'Vehicle washed.'
end)

local function runVehicleItemUse(src, kind)
    if pendingUse[src] then
        return { success = false, remove = 0, message = 'Another vehicle action is already running.' }
    end

    local durationMs = durationFor(kind)
    local pending = {
        token = ('item:%s:%d:%d'):format(kind, src, math.random(100000, 999999)),
        kind = kind,
        done = false,
        ok = false,
        message = nil,
        minFinishAt = GetGameTimer() + durationMs,
    }
    pendingUse[src] = pending

    TriggerClientEvent('cm-gas:client:useVehicleItem', src, kind, pending.token, durationMs)

    local timeout = math.max(durationMs + 3000, tonumber(Config.ItemUse.timeoutMs) or 30000)
    local startedAt = GetGameTimer()
    while pendingUse[src] == pending and not pending.done and (GetGameTimer() - startedAt) < timeout do
        Wait(50)
    end

    if pendingUse[src] == pending then pendingUse[src] = nil end
    if not pending.done then
        return { success = false, remove = 0, message = 'Vehicle action timed out.' }
    end

    return {
        success = pending.ok,
        remove = pending.ok and 1 or 0,
        message = pending.message or (pending.ok and 'Item used.' or 'Item could not be used.'),
    }
end

exports('UseItem', function(itemName, src)
    itemName = tostring(itemName or ''):lower()
    if itemName == tostring(Config.Items.fuelCan):lower() then
        return runVehicleItemUse(src, 'fuelCan')
    elseif itemName == tostring(Config.Items.repairKit):lower() then
        return runVehicleItemUse(src, 'repairKit')
    elseif itemName == tostring(Config.Items.washKit):lower() then
        return runVehicleItemUse(src, 'washKit')
    end
    return { success = false, remove = 0, message = 'No action is registered for this item.' }
end)

CreateThread(function()
    local attempts = 0
    while GetResourceState('cm-inventory') ~= 'started' and attempts < 40 do
        Wait(500)
        attempts = attempts + 1
    end
    if GetResourceState('cm-inventory') ~= 'started' then
        print('[CM-GAS] cm-inventory is not running; usable gas-station items were not registered.')
        return
    end

    local allRegistered = true
    for _, itemName in ipairs({ Config.Items.fuelCan, Config.Items.repairKit, Config.Items.washKit }) do
        local ok = pcall(function()
            exports['cm-inventory']:RegisterUseableItem(itemName, GetCurrentResourceName(), 'UseItem')
        end)
        if not ok then allRegistered = false end
    end
    if allRegistered then print('[CM-GAS] Registered gas-station usable items with cm-inventory.') end
end)

AddEventHandler('playerDropped', function()
    local src = source
    openSessions[src] = nil
    orderLocks[src] = nil
    openCooldowns[src] = nil
    orderCooldowns[src] = nil
    pendingUse[src] = nil
end)
