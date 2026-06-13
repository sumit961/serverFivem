local Config = CMVehicleStore.Config
local purchaseLocks = {}

local function dprint(...)
    if Config.Debug then print('[CM-VEHICLESTORE]', ...) end
end

local function notify(src, msg, typeName)
    TriggerClientEvent('cm-vehiclestore:client:notify', src, msg or '', typeName or 'info')
end

local function callExport(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then return false, nil end
    local args = { ... }
    local ok, result, extra = pcall(function()
        return exports[resource][method](table.unpack(args))
    end)
    if ok then return true, result, extra end
    print(('[CM-VEHICLESTORE] Export failed: %s.%s | %s'):format(resource, method, tostring(result)))
    return false, result
end

local function getCharacterId(src)
    local ok, charId = callExport('cm-vehicles', 'GetCharacterId', src)
    if ok and charId then return tostring(charId) end
    local st = Player(src).state
    return st.charId or st.characterId or st.character_id or st.citizenid
end

local function getDealership(id)
    for _, dealer in ipairs(Config.Dealerships or {}) do
        if dealer.id == id then return dealer end
    end
    return nil
end

local function getVehicleConfig(dealer, model)
    model = tostring(model or ''):lower()
    for _, veh in ipairs(dealer.vehicles or {}) do
        if tostring(veh.model):lower() == model then return veh end
    end
    return nil
end

local function pushCashUpdate(src, cash)
    cash = tonumber(cash) or 0
    pcall(function() Player(src).state:set('cash', cash, true) end)
    TriggerClientEvent('cm-playerdata:client:update', src, 'cash', cash)
end

local function getMoney(src, account)
    account = account or Config.PaymentAccount or 'cash'
    local ok, value = callExport('cm-playerdata', 'GetMoney', src, account)
    if ok and tonumber(value) ~= nil then return tonumber(value) end

    if account == 'cash' then
        ok, value = callExport('cm-playerdata', 'GetCash', src)
        if ok and tonumber(value) ~= nil then return tonumber(value) end
    elseif account == 'bank' then
        ok, value = callExport('cm-playerdata', 'GetBank', src)
        if ok and tonumber(value) ~= nil then return tonumber(value) end
    end

    local charId = getCharacterId(src)
    if not charId then return 0 end
    local column = account == 'bank' and 'bank' or 'cash'
    local dbValue = MySQL.scalar.await(('SELECT %s FROM characters WHERE id = ? LIMIT 1'):format(column), { tostring(charId) })
    return tonumber(dbValue) or 0
end

local function removeMoney(src, account, amount, reason)
    account = account or Config.PaymentAccount or 'cash'
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end

    local ok, result = callExport('cm-playerdata', 'RemoveMoney', src, account, amount, reason or 'vehicle_purchase')
    if ok and result == true then return true end

    if account == 'cash' then
        ok, result = callExport('cm-playerdata', 'RemoveCash', src, amount, reason or 'vehicle_purchase')
        if ok and result == true then return true end
    elseif account == 'bank' then
        ok, result = callExport('cm-playerdata', 'RemoveBank', src, amount, reason or 'vehicle_purchase')
        if ok and result == true then return true end
    end

    local charId = getCharacterId(src)
    if not charId then return false end
    local column = account == 'bank' and 'bank' or 'cash'
    local changed = MySQL.update.await(('UPDATE characters SET %s = %s - ? WHERE id = ? AND %s >= ?'):format(column, column, column), { amount, tostring(charId), amount })
    if tonumber(changed) and tonumber(changed) > 0 then
        local newValue = MySQL.scalar.await(('SELECT %s FROM characters WHERE id = ? LIMIT 1'):format(column), { tostring(charId) }) or 0
        if column == 'cash' then pushCashUpdate(src, newValue) end
        return true
    end
    return false
end

local function addMoney(src, account, amount, reason)
    account = account or Config.PaymentAccount or 'cash'
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end

    local ok, result = callExport('cm-playerdata', 'AddMoney', src, account, amount, reason or 'vehicle_refund')
    if ok and result == true then return true end

    if account == 'cash' then
        ok, result = callExport('cm-playerdata', 'AddCash', src, amount, reason or 'vehicle_refund')
        if ok and result == true then return true end
    elseif account == 'bank' then
        ok, result = callExport('cm-playerdata', 'AddBank', src, amount, reason or 'vehicle_refund')
        if ok and result == true then return true end
    end

    local charId = getCharacterId(src)
    if not charId then return false end
    local column = account == 'bank' and 'bank' or 'cash'
    local changed = MySQL.update.await(('UPDATE characters SET %s = %s + ? WHERE id = ?'):format(column, column), { amount, tostring(charId) })
    if tonumber(changed) and tonumber(changed) > 0 then
        local newValue = MySQL.scalar.await(('SELECT %s FROM characters WHERE id = ? LIMIT 1'):format(column), { tostring(charId) }) or 0
        if column == 'cash' then pushCashUpdate(src, newValue) end
        return true
    end
    return false
end

local function closeEnoughToDealer(src, dealer)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    local dist = #(GetEntityCoords(ped) - vector3(dealer.coords.x, dealer.coords.y, dealer.coords.z))
    return dist <= 8.0
end

RegisterNetEvent('cm-vehiclestore:server:buyVehicle', function(dealerId, model)
    local src = source
    if purchaseLocks[src] then return end
    purchaseLocks[src] = true

    local function finish()
        purchaseLocks[src] = nil
    end

    local dealer = getDealership(dealerId)
    if not dealer then notify(src, 'Dealership not found.', 'error') finish() return end
    if not closeEnoughToDealer(src, dealer) then notify(src, 'You are too far from the dealership.', 'error') finish() return end

    local cfg = getVehicleConfig(dealer, model)
    if not cfg then notify(src, 'Vehicle not found.', 'error') finish() return end

    local price = tonumber(cfg.price) or 0
    local account = Config.PaymentAccount or 'cash'
    if getMoney(src, account) < price then
        notify(src, ('Not enough %s. Need $%s.'):format(account, price), 'error')
        finish()
        return
    end

    if not removeMoney(src, account, price, 'vehicle_purchase') then
        notify(src, 'Payment failed.', 'error')
        finish()
        return
    end

    local ok, createOk, vehicleData = callExport('cm-vehicles', 'CreateOwnedVehicle', src, cfg.model, cfg.label, cfg.trunkLevel, {
        boughtFrom = dealer.id,
        price = price,
        category = cfg.category
    })

    if not ok or createOk ~= true or type(vehicleData) ~= 'table' then
        addMoney(src, account, price, 'vehicle_purchase_refund')
        notify(src, tostring(vehicleData or createOk or 'Could not create vehicle. Refunded.'), 'error')
        finish()
        return
    end

    vehicleData.spawnCoords = { x = dealer.spawn.x, y = dealer.spawn.y, z = dealer.spawn.z }
    vehicleData.heading = dealer.spawn.w
    vehicleData.price = price

    TriggerClientEvent('cm-vehicles:client:spawnPurchasedVehicle', src, vehicleData)
    notify(src, ('Purchased %s for $%s.'):format(cfg.label, price), 'success')
    finish()
end)

CreateThread(function()
    print('[CM-VEHICLESTORE] Started v1.0.0')
end)
