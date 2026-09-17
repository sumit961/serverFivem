local Config = CMGas.Config
CMGas.Server = CMGas.Server or {}

local openSessions = {}
local orderLocks = {}
local openCooldowns = {}
local orderCooldowns = {}
local pendingUse = {}

local function gasPlayerData()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function characterId(src)
    local api = gasPlayerData()
    if not api then return nil end
    local ok, id = pcall(function() return api:GetCharacterId(src) end)
    return ok and tonumber(id) or nil
end

local function getBank(src)
    local api = gasPlayerData()
    if not api then return nil end
    local ok, amount = pcall(function() return api:GetBank(src) end)
    return ok and tonumber(amount) or nil
end

local function removeBank(src, amount, reason)
    local api = gasPlayerData()
    if not api then return false end
    local ok, result = pcall(function() return api:RemoveBank(src, math.floor(amount), reason) end)
    return ok and result == true
end

local function addBank(src, amount, reason)
    local api = gasPlayerData()
    if not api then return false end
    local ok, result = pcall(function() return api:AddBank(src, math.floor(amount), reason) end)
    return ok and result == true
end

local function stationRow(index)
    if not MySQL then return nil end
    return MySQL.single.await('SELECT * FROM cm_gas_stations WHERE station_id = ? LIMIT 1', { index })
end

local function stationPrice(row)
    local tiers = (Config.Ownership or {}).priceTiers or {}
    if not row or not row.owner_character_id then return tonumber(tiers.normal) or 8 end
    return tonumber(tiers[tostring(row.price_tier or 'normal')]) or tonumber(tiers.normal) or 8
end

CreateThread(function()
    Wait(1000)
    if not MySQL then
        print('[CM-GAS] oxmysql is not ready; station persistence is disabled until the next restart.')
        return
    end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_gas_stations (
        station_id INT NOT NULL PRIMARY KEY,
        owner_character_id BIGINT NULL,
        owner_name VARCHAR(120) NULL,
        price_tier VARCHAR(12) NOT NULL DEFAULT 'normal',
        stock INT NOT NULL DEFAULT 5000,
        business_balance BIGINT NOT NULL DEFAULT 0,
        daily_income BIGINT NOT NULL DEFAULT 0,
        weekly_income BIGINT NOT NULL DEFAULT 0,
        tax_due_at DATETIME NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])
    MySQL.query.await('ALTER TABLE cm_gas_stations ADD COLUMN IF NOT EXISTS daily_income BIGINT NOT NULL DEFAULT 0')
    MySQL.query.await('ALTER TABLE cm_gas_stations ADD COLUMN IF NOT EXISTS weekly_income BIGINT NOT NULL DEFAULT 0')
    for index = 1, #(Config.Stations or {}) do
        MySQL.insert.await('INSERT IGNORE INTO cm_gas_stations (station_id, stock) VALUES (?, ?)', { index, (Config.Ownership or {}).defaultStock or 5000 })
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        if not MySQL then goto continue end
        local expired = MySQL.query.await([[SELECT station_id, owner_character_id, business_balance
            FROM cm_gas_stations WHERE owner_character_id IS NOT NULL AND tax_due_at IS NOT NULL AND tax_due_at < UTC_TIMESTAMP()]]) or {}
        for _, row in ipairs(expired) do
            local refund = math.floor((tonumber(row.business_balance) or 0) * 0 + 0)
            -- Ownership security deposit is represented by the purchase price; return 20% to the former owner's bank.
            local amount = math.floor((tonumber(Config.Ownership.purchasePrice) or 0) * 0.20)
            MySQL.update.await('UPDATE cm_gas_stations SET owner_character_id = NULL, owner_name = NULL, price_tier = \'normal\', business_balance = 0, stock = ? , tax_due_at = NULL WHERE station_id = ? AND owner_character_id = ?', { Config.Ownership.defaultStock or 5000, row.station_id, row.owner_character_id })
            local target = nil
            for _, player in ipairs(GetPlayers()) do
                if characterId(tonumber(player)) == tonumber(row.owner_character_id) then target = tonumber(player); break end
            end
            if target and amount > 0 then addBank(target, amount, 'gas-station-tax-forfeiture-refund') end
        end
        ::continue::
    end
end)

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

local function stationContext(src, index)
    local row = stationRow(index)
    local charId = characterId(src)
    local owned = row and charId and tonumber(row.owner_character_id) == charId
    return row, owned, charId
end

RegisterNetEvent('cm-gas:server:buyStation', function(index)
    local src = source
    index = math.floor(tonumber(index) or 0)
    local cfg = Config.Ownership or {}
    local row, _, charId = stationContext(src, index)
    if not cfg.enabled or not row or not charId then return notify(src, 'Station ownership is unavailable.', 'error') end
    if row.owner_character_id then return notify(src, 'This station is already owned.', 'error') end
    local price = math.max(0, math.floor(tonumber(cfg.purchasePrice) or 0))
    if not removeBank(src, price, 'gas-station-purchase') then return notify(src, ('You need $%d in the bank.'):format(price), 'error') end
    local name = playerData():GetCharacterFullName(src) or ('Character %d'):format(charId)
    local due = os.date('!%Y-%m-%d %H:%M:%S', os.time() + ((tonumber(cfg.taxPeriodDays) or 7) * 86400))
    local changed = MySQL.update.await('UPDATE cm_gas_stations SET owner_character_id = ?, owner_name = ?, price_tier = \'normal\', business_balance = 0, stock = ?, tax_due_at = ? WHERE station_id = ? AND owner_character_id IS NULL', { charId, name, cfg.defaultStock or 5000, due, index })
    if changed ~= 1 then addBank(src, price, 'gas-station-purchase-refund'); return notify(src, 'The station was bought by someone else.', 'error') end
    TriggerClientEvent('cm-gas:client:stationUpdated', src, index)
    notify(src, 'Gas station purchased. Tax is due in 7 days.', 'success')
end)

RegisterNetEvent('cm-gas:server:manageStation', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local index = math.floor(tonumber(data.stationId) or 0)
    local row, owned = stationContext(src, index)
    if not row or not owned then return notify(src, 'You do not own this station.', 'error') end
    local tier = tostring(data.priceTier or 'normal'):lower()
    if not (Config.Ownership.priceTiers or {})[tier] then return notify(src, 'Invalid price tier.', 'error') end
    local maxStock = tonumber(Config.Ownership.maxStock) or 25000
    local stock = math.floor(tonumber(row.stock) or 0)
    if data.restock == true then
        local batch = tonumber(Config.Ownership.restockBatch) or 1000
        local cost = math.floor(batch * (tonumber(Config.Ownership.restockUnitPrice) or 0))
        if not removeBank(src, cost, 'gas-station-restock') then return notify(src, ('You need $%d in the bank to order stock.'):format(cost), 'error') end
        stock = math.min(maxStock, stock + batch)
    end
    if data.stock ~= nil then stock = math.floor(tonumber(data.stock) or stock) end
    if stock < 0 or stock > maxStock then return notify(src, 'Stock is outside the allowed range.', 'error') end
    MySQL.update.await('UPDATE cm_gas_stations SET price_tier = ?, stock = ? WHERE station_id = ? AND owner_character_id = ?', { tier, stock, index, characterId(src) })
    notify(src, 'Station settings saved.', 'success')
end)

RegisterNetEvent('cm-gas:server:payTax', function(index)
    local src = source
    index = math.floor(tonumber(index) or 0)
    local row, owned = stationContext(src, index)
    if not row or not owned then return notify(src, 'You do not own this station.', 'error') end
    local amount = math.max(0, math.floor(tonumber(Config.Ownership.taxAmount) or 0))
    if not removeBank(src, amount, 'gas-station-tax') then return notify(src, ('You need $%d in the bank.'):format(amount), 'error') end
    local due = os.date('!%Y-%m-%d %H:%M:%S', os.time() + ((tonumber(Config.Ownership.taxPeriodDays) or 7) * 86400))
    MySQL.update.await('UPDATE cm_gas_stations SET tax_due_at = ? WHERE station_id = ? AND owner_character_id = ?', { due, index, characterId(src) })
    notify(src, 'Station tax paid for 7 days.', 'success')
end)

RegisterNetEvent('cm-gas:server:withdrawBusiness', function(index)
    local src = source
    index = math.floor(tonumber(index) or 0)
    local row, owned = stationContext(src, index)
    if not row or not owned then return notify(src, 'You do not own this station.', 'error') end
    local balance = math.max(0, math.floor(tonumber(row.business_balance) or 0))
    if balance <= 0 then return notify(src, 'There is no business balance to withdraw.', 'error') end
    local changed = MySQL.update.await('UPDATE cm_gas_stations SET business_balance = 0 WHERE station_id = ? AND owner_character_id = ? AND business_balance = ?', { index, characterId(src), balance })
    if changed == 1 and addBank(src, balance, 'gas-station-business-withdrawal') then notify(src, ('$%d transferred to your bank.'):format(balance), 'success') end
end)

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

local function getClosestPump(coords, maxHorizontalDistance, minZ, maxZ)
    local maxHoriz = tonumber(maxHorizontalDistance) or tonumber(Config.Security.playerPumpTolerance) or 40.0
    local zMin = tonumber(minZ) or tonumber(Config.Security.minPumpHeightDiff) or -6.0
    local zMax = tonumber(maxZ) or tonumber(Config.Security.maxPumpHeightDiff) or 32.0

    local closestIndex, closestDistance
    for index, pump in ipairs(Config.Pumps or {}) do
        local dist2d = #(vector2(coords.x, coords.y) - vector2(pump.x, pump.y))
        local dz = coords.z - pump.z
        if dist2d <= maxHoriz and dz >= zMin and dz <= zMax then
            if not closestDistance or dist2d < closestDistance then
                closestIndex = index
                closestDistance = dist2d
            end
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

local function isHelicopterEntity(entity, row)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if type(GetVehicleType) == 'function' then
        local ok, vType = pcall(GetVehicleType, entity)
        if ok and tostring(vType):lower() == 'heli' then return true end
    end
    if row then
        local kind = tostring(row.vehicle_type or row.type or row.category or row.vehicle_category or ''):lower()
        if kind == 'heli' or kind == 'helicopter' or kind:find('heli', 1, true) then return true end
        local model = tostring(row.model or ''):lower()
        for _, token in ipairs({ 'heli', 'buzzard', 'frogger', 'maverick', 'annihilator', 'cargobob', 'polmav', 'swift', 'supervolito', 'havok', 'hunter', 'valkyrie', 'volatus', 'seasparrow', 'sparrow', 'akula', 'savage', 'conada' }) do
            if model:find(token, 1, true) then return true end
        end
    end
    return false
end

local function validateManagedVehicle(src, netId, suppliedPlate, options)
    options = type(options) == 'table' and options or {}
    local entity = getNetworkVehicle(netId)
    if entity and Entity(entity).state.cmLicenseTest == true then
        return false, 'License examination vehicles cannot use fuel stations.'
    end
    if not entity then return false, 'Vehicle is not available.' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false, 'Player is not available.' end

    local playerBucket = GetPlayerRoutingBucket(src)
    local entityBucket = GetEntityRoutingBucket(entity)
    if playerBucket ~= entityBucket then return false, 'Vehicle is in another routing instance.' end

    local actualPlate = getEntityPlate(entity)
    local expectedPlate = normalizePlate(suppliedPlate)
    if actualPlate == '' or (expectedPlate ~= '' and actualPlate ~= expectedPlate) then
        return false, 'Vehicle plate validation failed.'
    end

    local row = getManagedVehicleRow(actualPlate)
    if Config.Security.requireManagedVehicle ~= false and not row then
        return false, 'This vehicle is not registered in CM Vehicles.'
    end

    local isHeli = isHelicopterEntity(entity, row)

    local playerCoords = GetEntityCoords(ped)
    local vehicleCoords = GetEntityCoords(entity)
    local maxDistance = isHeli and 15.0 or (tonumber(options.maxDistance) or tonumber(Config.Security.maxVehicleDistance) or 6.0)
    local maxZ = isHeli and 6.0 or 3.0
    local p2vDist2d = #(vector2(playerCoords.x, playerCoords.y) - vector2(vehicleCoords.x, vehicleCoords.y))
    local p2vDz = math.abs(playerCoords.z - vehicleCoords.z)
    if p2vDist2d > maxDistance or p2vDz > maxZ then return false, 'Move closer to the vehicle.' end

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

        local playerDist2d = #(vector2(playerCoords.x, playerCoords.y) - vector2(pump.x, pump.y))
        local playerDz = playerCoords.z - pump.z
        local vehDist2d = #(vector2(vehicleCoords.x, vehicleCoords.y) - vector2(pump.x, pump.y))
        local vehDz = vehicleCoords.z - pump.z

        if isHeli then
            local heliRadius = tonumber(Config.Security.heliRooftopRadius) or 30.0
            local heliMinZ = tonumber(Config.Security.heliMinHeight) or 4.0
            local heliMaxZ = tonumber(Config.Security.heliMaxHeight) or 32.0

            if vehDist2d > heliRadius or vehDz < heliMinZ or vehDz > heliMaxZ then
                return false, 'Helicopters must be landed on the station roof to refuel.'
            end
            if playerDist2d > heliRadius or playerDz < heliMinZ or playerDz > heliMaxZ then
                return false, 'You must be on the roof with the helicopter.'
            end
        else
            local vehTol = tonumber(Config.Security.vehiclePumpTolerance) or 25.0
            local playerTol = tonumber(Config.Security.playerPumpTolerance) or 22.0
            local minZ = tonumber(Config.Security.groundMinHeightDiff) or -4.0
            local maxZ = tonumber(Config.Security.groundMaxHeightDiff) or 4.5

            if vehDist2d > vehTol or vehDz < minZ or vehDz > maxZ then
                return false, 'Move the vehicle closer to the fuel pumps.'
            end
            if playerDist2d > playerTol or playerDz < minZ or playerDz > maxZ then
                return false, 'You moved away from the fuel station.'
            end
        end
    end

    return true, {
        entity = entity,
        netId = tonumber(netId),
        plate = actualPlate,
        row = row,
        fuel = getLiveFuel(entity, row),
        isHeli = isHeli,
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
    local netId = tonumber(data.netId) or 0
    local searchRadius = netId > 0 and (Config.Security.heliRooftopRadius or 30.0) or (Config.Security.playerPumpTolerance or 22.0)
    local searchMinZ = Config.Security.groundMinHeightDiff or -4.0
    local searchMaxZ = netId > 0 and (Config.Security.heliMaxHeight or 32.0) or (Config.Security.groundMaxHeightDiff or 4.5)

    local requestedIndex = tonumber(data.pumpIndex)
    local pumpIndex
    if requestedIndex and Config.Pumps[requestedIndex] then
        local pCoords = Config.Pumps[requestedIndex]
        local dist2d = #(vector2(playerCoords.x, playerCoords.y) - vector2(pCoords.x, pCoords.y))
        local dz = playerCoords.z - pCoords.z
        if dist2d <= searchRadius and dz >= searchMinZ and dz <= searchMaxZ then
            pumpIndex = requestedIndex
        end
    end

    if not pumpIndex then
        pumpIndex = getClosestPump(playerCoords, searchRadius, searchMinZ, searchMaxZ)
    end

    if not pumpIndex then
        return TriggerClientEvent('cm-gas:client:openDenied', src, 'You are not at a fuel station.')
    end

    local cash = getCash(src)
    if cash == nil then
        return TriggerClientEvent('cm-gas:client:openDenied', src, 'Payment system unavailable.')
    end

    local station = stationRow(pumpIndex)
    local stationOwner = characterId(src)
    local isOwner = station and stationOwner and tonumber(station.owner_character_id) == stationOwner

    local vehicleInfo
    if netId > 0 then
        local valid, result = validateManagedVehicle(src, netId, data.plate, {
            maxDistance = Config.Security.maxVehicleDistance,
            pumpIndex = pumpIndex,
        })
        if not valid then
            if result == 'License examination vehicles cannot use fuel stations.' then
                return TriggerClientEvent('cm-gas:client:openDenied', src, tostring(result))
            end
            -- If player walked away from vehicle or vehicle is not in immediate range,
            -- simply open the station menu without a vehicle attached instead of denying access.
            vehicleInfo = nil
        else
            vehicleInfo = result
        end
    end

    local token = makeSessionToken(src)
    openSessions[src] = {
        token = token,
        pumpIndex = pumpIndex,
        netId = vehicleInfo and vehicleInfo.netId or 0,
        plate = vehicleInfo and vehicleInfo.plate or '',
        isHeli = vehicleInfo and vehicleInfo.isHeli == true or false,
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
        pricePerPercent = stationPrice(station),
        fuelCanPrice = tonumber(Config.Pricing.fuelCanPrice) or 0,
        repairKitPrice = tonumber(Config.Pricing.repairKitPrice) or 0,
        washKitPrice = tonumber(Config.Pricing.washKitPrice) or 0,
        maxItemQuantity = tonumber(Config.Security.maxItemQuantity) or 10,
        cash = cash,
        bank = getBank(src) or 0,
        station = {
            id = pumpIndex,
            owned = isOwner == true,
            ownerName = station and station.owner_name or nil,
            priceTier = station and station.price_tier or 'normal',
            priceTiers = (Config.Ownership or {}).priceTiers or {},
            stock = station and tonumber(station.stock) or 0,
            businessBalance = isOwner and tonumber(station.business_balance) or 0,
            dailyIncome = isOwner and tonumber(station.daily_income) or 0,
            weeklyIncome = isOwner and tonumber(station.weekly_income) or 0,
            taxAmount = (Config.Ownership or {}).taxAmount or 0,
            taxDueAt = isOwner and station.tax_due_at or nil,
            purchasePrice = (Config.Ownership or {}).purchasePrice or 0,
        },
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
        if not pump then
            fail('Fuel station session is invalid.', true)
            return
        end
        local playerCoords = GetEntityCoords(ped)
        local dist2d = #(vector2(playerCoords.x, playerCoords.y) - vector2(pump.x, pump.y))
        local dz = playerCoords.z - pump.z

        local isHeliSession = session.isHeli == true
        if not isHeliSession and session.netId and session.netId > 0 then
            local entity = getNetworkVehicle(session.netId)
            if entity and isHelicopterEntity(entity) then
                isHeliSession = true
            end
        end

        if isHeliSession then
            local heliRadius = tonumber(Config.Security.heliRooftopRadius) or 30.0
            local heliMinZ = tonumber(Config.Security.heliMinHeight) or 4.0
            local heliMaxZ = tonumber(Config.Security.heliMaxHeight) or 32.0
            if dist2d > heliRadius or dz < heliMinZ or dz > heliMaxZ then
                fail('You moved away from the rooftop fuel area.', true)
                return
            end
        else
            local playerTol = tonumber(Config.Security.playerPumpTolerance) or 22.0
            local minZ = tonumber(Config.Security.groundMinHeightDiff) or -4.0
            local maxZ = tonumber(Config.Security.groundMaxHeightDiff) or 4.5
            if dist2d > playerTol or dz < minZ or dz > maxZ then
                fail('You moved away from the fuel station.', true)
                return
            end
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
        local station = stationRow(session.pumpIndex)
        local fuelUnitPrice = stationPrice(station)
        if fuelUnits > 0 and station and tonumber(station.stock or 0) < fuelUnits then
            fail('This station is out of fuel. The owner needs to restock it.', false)
            return
        end
        local fuelCost = fuelUnits * math.max(0, math.floor(fuelUnitPrice))
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
        if station and station.owner_character_id and paidTotal > 0 then
            local ownerShare = math.floor(paidTotal * ((tonumber(Config.Ownership.ownerRevenuePercent) or 80) / 100))
            MySQL.update.await('UPDATE cm_gas_stations SET business_balance = business_balance + ?, daily_income = daily_income + ?, weekly_income = weekly_income + ?, stock = GREATEST(stock - ?, 0) WHERE station_id = ? AND owner_character_id IS NOT NULL', { ownerShare, ownerShare, ownerShare, deliveredFuel, session.pumpIndex })
        end
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
