local Config = CMTuning.Config

local Sessions = {}
local VehicleLocks = {}
local Cooldowns = {}

math.randomseed(os.time() + GetGameTimer())

local function dprint(...)
    if Config.Debug then
        print('[cm-tuning]', ...)
    end
end

local function notify(src, msg, kind)
    TriggerClientEvent('cm-tuning:client:notify', src, tostring(msg or ''), kind or 'info')
end

local function normalizePlate(plate)
    return tostring(plate or ''):upper():gsub('%s+', ''):sub(1, 12)
end

local function deepCopy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepCopy(v) end
    return out
end

local function decodeTable(value)
    if type(value) == 'table' then return deepCopy(value) end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or {}
end

local function playerdata()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function getMoney(src, account)
    local pd = playerdata()
    if not pd then return nil end
    local ok, value = pcall(function() return pd:GetMoney(src, account) end)
    if not ok then return nil end
    return tonumber(value)
end

local function getBalances(src)
    return {
        cash = getMoney(src, 'cash') or 0,
        bank = getMoney(src, 'bank') or 0,
    }
end

local function resolveAccount(account)
    account = tostring(account or '')
    if account == 'cash' and Config.allowCash ~= false then return 'cash' end
    if account == 'bank' and Config.allowBank ~= false then return 'bank' end
    local fallback = tostring(Config.defaultAccount or 'cash')
    if fallback == 'bank' and Config.allowBank ~= false then return 'bank' end
    return 'cash'
end

local function charge(src, amount, account, reason)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    account = resolveAccount(account)
    if amount == 0 then return true, account end

    local pd = playerdata()
    if not pd then return false, 'Payment system unavailable.' end

    local balance = getMoney(src, account)
    if type(balance) ~= 'number' or balance < amount then
        return false, ('Not enough %s. You need $%d.'):format(account, amount)
    end

    local ok, result = pcall(function()
        return pd:RemoveMoney(src, account, amount, reason or 'cm_tuning')
    end)
    if ok and result == true then return true, account end
    return false, ('Could not take $%d from %s.'):format(amount, account)
end

local function refund(src, amount, account, reason)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local pd = playerdata()
    if not pd then return false end
    local ok, result = pcall(function()
        return pd:AddMoney(src, resolveAccount(account), amount, reason or 'cm_tuning_refund')
    end)
    return ok and result == true
end

local function cooldown(src, key, duration)
    local now = GetGameTimer()
    Cooldowns[src] = Cooldowns[src] or {}
    local expires = tonumber(Cooldowns[src][key]) or 0
    if expires > now then return false end
    Cooldowns[src][key] = now + math.max(0, tonumber(duration) or 0)
    return true
end

local function getVehicleRow(plate)
    if GetResourceState('cm-vehicles') ~= 'started' then return nil end
    local ok, row = pcall(function()
        return exports['cm-vehicles']:GetVehicleByPlate(plate)
    end)
    return ok and type(row) == 'table' and row or nil
end

local function hasAccess(src, plate)
    if Config.requireOwnership == false then return true end
    if GetResourceState('cm-vehicles') ~= 'started' then return false end
    local ok, allowed = pcall(function()
        return exports['cm-vehicles']:HasVehicleAccess(src, plate)
    end)
    return ok and allowed == true
end

local function sameBucket(src, entity)
    local ok, result = pcall(function()
        return GetPlayerRoutingBucket(src) == GetEntityRoutingBucket(entity)
    end)
    return ok and result == true
end

local function entityPlate(vehicle)
    local plate = ''
    pcall(function() plate = normalizePlate(Entity(vehicle).state.cmPlate) end)
    return plate
end

local function resolveVehicle(src, netId, claimedPlate)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return false, 'Vehicle network ID is missing.' end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false, 'Vehicle entity is no longer available.'
    end

    local okType, entityType = pcall(GetEntityType, vehicle)
    if okType and entityType ~= 2 then return false, 'Selected entity is not a vehicle.' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false, 'Player entity is unavailable.' end
    if not sameBucket(src, vehicle) then return false, 'Vehicle is in another routing bucket.' end

    local maxDistance = tonumber(Config.Security and Config.Security.maxVehicleDistance) or 8.0
    local okDistance, distance = pcall(function()
        return #(GetEntityCoords(ped) - GetEntityCoords(vehicle))
    end)
    if not okDistance or distance > maxDistance then return false, 'You are too far from the vehicle.' end

    if Config.requireDriver ~= false then
        if GetVehiclePedIsIn(ped, false) ~= vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then
            return false, 'You must remain in the driver seat.'
        end
    end

    local statePlate = entityPlate(vehicle)
    local plate = normalizePlate(claimedPlate)
    if statePlate == '' or plate == '' or statePlate ~= plate then
        return false, 'Vehicle plate could not be verified.'
    end

    local row = getVehicleRow(plate)
    if not row then return false, 'This vehicle is not registered in CM Vehicles.' end

    local stateId
    pcall(function() stateId = tonumber(Entity(vehicle).state.cmVehicleId) end)
    if stateId and tonumber(row.id) ~= stateId then
        return false, 'Vehicle database identity does not match.'
    end

    local okModel, model = pcall(GetEntityModel, vehicle)
    if okModel and model and model ~= 0 and row.model and joaat(tostring(row.model)) ~= model then
        return false, 'Vehicle model does not match its database record.'
    end

    if not hasAccess(src, plate) then return false, 'You do not have access to modify this vehicle.' end
    return true, vehicle, row
end

local function shopLocation(shopKey, coords)
    local shop = Config.Shops and Config.Shops[shopKey]
    if not shop or coords == nil then return nil end
    local distanceLimit = (tonumber(Config.interactDistance) or 6.0) + 2.0
    for index, point in ipairs(shop.Locations or {}) do
        if #(coords - point) <= distanceLimit then return index, point end
    end
    return nil
end

local function validateAtShop(vehicle, shopKey, locationIndex)
    local shop = Config.Shops and Config.Shops[shopKey]
    local point = shop and shop.Locations and shop.Locations[tonumber(locationIndex) or 0]
    if not point then return false end
    local ok, distance = pcall(function() return #(GetEntityCoords(vehicle) - point) end)
    return ok and distance <= ((tonumber(Config.interactDistance) or 6.0) + 3.0)
end

local function defaultMods(raw)
    local mods = decodeTable(raw)
    mods.mods = type(mods.mods) == 'table' and mods.mods or {}
    mods.extras = type(mods.extras) == 'table' and mods.extras or {}
    local oldNeons = type(mods.neons) == 'table' and mods.neons or {}
    mods.neons = {
        oldNeons[1] == true or oldNeons['1'] == true,
        oldNeons[2] == true or oldNeons['2'] == true,
        oldNeons[3] == true or oldNeons['3'] == true,
        oldNeons[4] == true or oldNeons['4'] == true,
    }
    mods.neonColor = type(mods.neonColor) == 'table' and mods.neonColor or { r = 255, g = 255, b = 255 }

    if mods.primaryColor == nil then mods.primaryColor = 111 end
    if mods.secondaryColor == nil then mods.secondaryColor = 111 end
    if mods.pearlColor == nil then mods.pearlColor = 111 end
    if mods.wheelColor == nil then mods.wheelColor = 111 end
    if mods.wheelType == nil then mods.wheelType = 0 end
    if mods.windowTint == nil then mods.windowTint = 0 end
    if mods.plateIndex == nil then mods.plateIndex = 0 end
    if mods.livery == nil then mods.livery = -1 end
    if mods.tyreLevel == nil then mods.tyreLevel = 0 end
    if mods.headlightColor == nil then mods.headlightColor = -1 end
    mods.turbo = mods.turbo == true
    mods.xenon = mods.xenon == true
    mods.bulletproofTyres = mods.bulletproofTyres == true
    mods.customWheels = mods.customWheels == true
    return mods
end

local function createToken(src, netId)
    return ('%x%x%x%x'):format(
        os.time(),
        tonumber(src) or 0,
        tonumber(netId) or 0,
        math.random(0x100000, 0xFFFFFF)
    )
end

local function releaseSession(src, reason)
    local session = Sessions[src]
    if not session then return end
    if VehicleLocks[session.plate] == src then VehicleLocks[session.plate] = nil end
    Sessions[src] = nil
    dprint(('session closed src=%s plate=%s reason=%s'):format(src, session.plate, reason or 'unknown'))
end

local function cleanCaps(caps, shop)
    caps = type(caps) == 'table' and caps or {}
    local allowed = {}
    local defs = shop == 'chip' and (Config.Performance or {}) or (Config.Visual or {})
    for _, def in ipairs(defs) do
        local hardMax
        if shop == 'chip' then hardMax = math.max(-1, (tonumber(def.maxLevel) or 4) - 1)
        else hardMax = math.max(-1, tonumber(def.maxIndex) or 100) end
        local raw = caps[def.key]
        local supplied = raw == nil and -1 or math.floor(tonumber(raw) or -1)
        allowed[def.key] = math.max(-1, math.min(hardMax, supplied))
    end
    return allowed
end

local function sendDenied(src, eventName, message)
    TriggerClientEvent(eventName, src, tostring(message or 'Request denied.'))
end

local function validateSession(src, token, requiredShop)
    local session = Sessions[src]
    if not session or tostring(session.token) ~= tostring(token or '') then
        return false, 'Your tuning session is no longer valid.'
    end
    if session.expiresAt < GetGameTimer() then
        releaseSession(src, 'expired')
        return false, 'Your tuning session expired.'
    end
    if requiredShop and session.shop ~= requiredShop then return false, 'This service is not available at this shop.' end

    local ok, vehicle, row = resolveVehicle(src, session.netId, session.plate)
    if not ok then return false, vehicle end
    if not validateAtShop(vehicle, session.shop, session.locationIndex) then
        return false, 'Vehicle is no longer inside the tuning bay.'
    end
    if normalizePlate(row.plate) ~= session.plate or tonumber(row.id) ~= tonumber(session.vehicleId) then
        return false, 'Vehicle identity changed during the session.'
    end
    session.expiresAt = GetGameTimer() + (tonumber(Config.Security and Config.Security.sessionTimeoutMs) or 120000)
    return true, session, vehicle, row
end

local function makeSet(list, keyIndex)
    local out = {}
    for _, item in ipairs(list or {}) do
        local key = item[keyIndex or 1]
        out[tostring(key)] = item
    end
    return out
end

local ColorSet = makeSet(Config.Colors, 1)
local TintSet = makeSet(Config.WindowTints, 1)
local PlateSet = makeSet(Config.PlateStyles, 1)
local HeadlightSet = makeSet(Config.HeadlightColors, 1)
local NeonSet = {}
for _, item in ipairs(Config.NeonColors or {}) do
    NeonSet[('%d:%d:%d'):format(tonumber(item[2]) or 0, tonumber(item[3]) or 0, tonumber(item[4]) or 0)] = true
end

local function integer(value)
    local number = tonumber(value)
    if not number or number ~= number then return nil end
    return math.floor(number)
end

local function countChanges(changes)
    local count = 0
    for _, key in ipairs({ 'slots', 'toggles' }) do
        if type(changes[key]) == 'table' then
            for _ in pairs(changes[key]) do count = count + 1 end
        end
    end
    for _, key in ipairs({ 'tyres', 'color', 'color2', 'wheelcol', 'headlight', 'tint', 'plate', 'neon', 'neonColor' }) do
        if changes[key] ~= nil then count = count + 1 end
    end
    return count
end

local function calculatePurchase(session, changes)
    if type(changes) ~= 'table' then return nil, nil, 'Invalid modification request.' end
    local maxChanges = tonumber(Config.Security and Config.Security.maxChangesPerPurchase) or 32
    if countChanges(changes) > maxChanges then return nil, nil, 'Too many modifications were submitted at once.' end

    local approved = defaultMods(session.baseMods)
    local total = 0
    local changed = false
    local slotDefs = {}
    local definitions = session.shop == 'chip' and (Config.Performance or {}) or (Config.Visual or {})
    for _, def in ipairs(definitions) do slotDefs[def.key] = def end

    if type(changes.slots) == 'table' then
        for key, rawIndex in pairs(changes.slots) do
            local def = slotDefs[tostring(key)]
            if not def then return nil, nil, 'Unknown vehicle modification.' end
            local selected = integer(rawIndex)
            local maxIndex = tonumber(session.caps[key]) or -1
            if not selected or selected < -1 or selected > maxIndex then
                return nil, nil, ('Invalid %s option.'):format(def.label or key)
            end

            local modKey = tostring(math.floor(tonumber(def.modType) or -1))
            local current = integer(approved.mods[modKey]) or -1
            if selected ~= current then
                changed = true
                approved.mods[modKey] = selected
                if selected >= 0 then
                    total = total + math.max(0, math.floor((tonumber(def.pricePerLevel) or 0) * (selected + 1)))
                end
                if tonumber(def.modType) == 48 then approved.livery = selected end
            end
        end
    end

    if session.shop == 'chip' then
        if changes.tyres ~= nil then
            local tc = Config.Tyres or {}
            if tc.enabled == false then return nil, nil, 'Tyre tuning is disabled.' end
            local level = integer(changes.tyres)
            local maxLevel = tonumber(tc.maxLevel) or 4
            if not level or level < 0 or level > maxLevel then return nil, nil, 'Invalid tyre level.' end
            local current = integer(approved.tyreLevel) or 0
            if level ~= current then
                changed = true
                approved.tyreLevel = level
                approved.bulletproofTyres = level >= (tonumber(tc.bulletproofFromLevel) or 3)
                if level > 0 then total = total + math.floor((tonumber(tc.pricePerLevel) or 0) * level) end
            end
        end

        if type(changes.toggles) == 'table' then
            for key, value in pairs(changes.toggles) do
                if key ~= 'turbo' then return nil, nil, 'Unknown performance toggle.' end
                local selected = value == true
                if selected ~= (approved.turbo == true) then
                    changed = true
                    approved.turbo = selected
                    if selected then total = total + math.max(0, math.floor(tonumber(Config.Turbo and Config.Turbo.price) or 0)) end
                end
            end
        end
    else
        if type(changes.toggles) == 'table' then
            for key, value in pairs(changes.toggles) do
                if key ~= 'xenon' then return nil, nil, 'Unknown visual toggle.' end
                local selected = value == true
                if selected ~= (approved.xenon == true) then
                    changed = true
                    approved.xenon = selected
                    if selected then total = total + math.max(0, math.floor(tonumber(Config.Xenon and Config.Xenon.price) or 0)) end
                end
            end
        end

        local function applyListed(field, targetField, allowed, price)
            if changes[field] == nil then return true end
            local value = integer(changes[field])
            if value == nil or not allowed[tostring(value)] then return false end
            if integer(approved[targetField]) ~= value then
                changed = true
                approved[targetField] = value
                total = total + math.max(0, math.floor(tonumber(price) or 0))
            end
            return true
        end

        if not applyListed('color', 'primaryColor', ColorSet, Config.resprayPrice) then return nil, nil, 'Invalid primary colour.' end
        if not applyListed('color2', 'secondaryColor', ColorSet, Config.resprayPrice) then return nil, nil, 'Invalid secondary colour.' end
        if not applyListed('wheelcol', 'wheelColor', ColorSet, Config.wheelColorPrice) then return nil, nil, 'Invalid wheel colour.' end

        if changes.headlight ~= nil then
            local value = integer(changes.headlight)
            if value == nil or not HeadlightSet[tostring(value)] then return nil, nil, 'Invalid headlight colour.' end
            if value >= 0 and type(changes.toggles) == 'table' and changes.toggles.xenon == false then
                return nil, nil, 'Coloured headlights require xenon lights to remain enabled.'
            end
            if integer(approved.headlightColor) ~= value then
                changed = true
                approved.headlightColor = value
                total = total + math.max(0, math.floor(tonumber(Config.headlightColorPrice) or 0))
            end
            if value >= 0 and approved.xenon ~= true then
                approved.xenon = true
                total = total + math.max(0, math.floor(tonumber(Config.Xenon and Config.Xenon.price) or 0))
            end
        end

        if not applyListed('tint', 'windowTint', TintSet, Config.windowTintPrice) then return nil, nil, 'Invalid window tint.' end
        if not applyListed('plate', 'plateIndex', PlateSet, Config.plateStylePrice) then return nil, nil, 'Invalid plate style.' end

        if changes.neon ~= nil then
            local selected = changes.neon == true
            local current = false
            for i = 1, 4 do if approved.neons[i] == true then current = true break end end
            if selected ~= current then
                changed = true
                approved.neons = { selected, selected, selected, selected }
                if selected then total = total + math.max(0, math.floor(tonumber(Config.neonPrice) or 0)) end
            end
        end

        if changes.neonColor ~= nil then
            if type(changes.neonColor) ~= 'table' then return nil, nil, 'Invalid neon colour.' end
            local r = math.max(0, math.min(255, integer(changes.neonColor.r) or -1))
            local g = math.max(0, math.min(255, integer(changes.neonColor.g) or -1))
            local b = math.max(0, math.min(255, integer(changes.neonColor.b) or -1))
            if not NeonSet[('%d:%d:%d'):format(r, g, b)] then return nil, nil, 'Invalid neon colour.' end
            local old = approved.neonColor or {}
            if integer(old.r) ~= r or integer(old.g) ~= g or integer(old.b) ~= b then
                changed = true
                approved.neonColor = { r = r, g = g, b = b }
            end
        end
    end

    if not changed then return nil, nil, 'No changes selected.' end
    return approved, math.max(0, math.floor(total))
end

local function persistApproved(src, session, row, approved)
    local ok, result, message = pcall(function()
        return exports['cm-vehicles']:SaveVehicleModsAuthorized(src, session.plate, session.netId, approved)
    end)
    if not ok or result ~= true then
        return false, tostring(message or result or 'CM Vehicles rejected the modifications.')
    end

    -- CM Vehicles v3.1 validates and writes the standard fields. Its current
    -- sanitizer intentionally omits extended visual fields (neon colour,
    -- headlight colour and custom-wheel flag), so this resource writes the same
    -- already-authorised payload back to the exact validated row. This does not
    -- trust the client: `approved` was built entirely from server config + DB.
    local encoded = json.encode(approved)
    local dbOk, affected = pcall(function()
        return MySQL.update.await('UPDATE cm_owned_vehicles SET mods = ? WHERE id = ? AND plate = ?', {
            encoded, tonumber(row.id), session.plate
        })
    end)
    if not dbOk or tonumber(affected) == 0 then
        pcall(function()
            exports['cm-vehicles']:SaveVehicleModsAuthorized(src, session.plate, session.netId, session.baseMods)
        end)
        return false, 'Could not persist the full tuning configuration.'
    end
    return true
end

RegisterNetEvent('cm-tuning:server:requestOpen', function(data)
    local src = source
    data = type(data) == 'table' and data or {}

    if not cooldown(src, 'open', tonumber(Config.Security and Config.Security.requestCooldownMs) or 1500) then return end
    releaseSession(src, 'new_request')

    local shop = tostring(data.shop or '')
    if not (Config.Shops and Config.Shops[shop]) then
        return sendDenied(src, 'cm-tuning:client:denied', 'Unknown tuning shop.')
    end

    local ok, vehicle, row = resolveVehicle(src, data.netId, data.plate)
    if not ok then return sendDenied(src, 'cm-tuning:client:denied', vehicle) end

    local locationIndex = shopLocation(shop, GetEntityCoords(vehicle))
    if not locationIndex then return sendDenied(src, 'cm-tuning:client:denied', 'Drive fully into the tuning bay.') end

    local plate = normalizePlate(row.plate)
    local lockedBy = VehicleLocks[plate]
    if lockedBy and lockedBy ~= src then
        return sendDenied(src, 'cm-tuning:client:denied', 'This vehicle is already being customised.')
    end

    local token = createToken(src, data.netId)
    local savedMods = defaultMods(row.mods)
    local timeout = tonumber(Config.Security and Config.Security.sessionTimeoutMs) or 120000

    Sessions[src] = {
        token = token,
        plate = plate,
        netId = tonumber(data.netId),
        vehicleId = tonumber(row.id),
        model = tostring(row.model or ''),
        shop = shop,
        locationIndex = locationIndex,
        caps = cleanCaps(data.caps, shop),
        baseMods = savedMods,
        expiresAt = GetGameTimer() + timeout,
        busy = false,
    }
    VehicleLocks[plate] = src

    TriggerClientEvent('cm-tuning:client:open', src, {
        token = token,
        balances = getBalances(src),
        savedMods = savedMods,
    })
end)

RegisterNetEvent('cm-tuning:server:cancelSession', function(token)
    local src = source
    local session = Sessions[src]
    if session and (token == nil or tostring(token) == tostring(session.token)) then
        releaseSession(src, 'client_cancel')
    end
end)

RegisterNetEvent('cm-tuning:server:purchase', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    if not cooldown(src, 'purchase', tonumber(Config.Security and Config.Security.purchaseCooldownMs) or 2000) then
        return sendDenied(src, 'cm-tuning:client:purchaseDenied', 'Please wait before submitting another purchase.')
    end

    local ok, session, vehicle, row = validateSession(src, data.token)
    if not ok then return sendDenied(src, 'cm-tuning:client:purchaseDenied', session) end
    if session.busy then return sendDenied(src, 'cm-tuning:client:purchaseDenied', 'A purchase is already processing.') end
    session.busy = true

    local approved, price, err = calculatePurchase(session, data.changes)
    if not approved then
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:purchaseDenied', err)
    end

    local paid, accountOrMessage = charge(src, price, data.account, 'cm_tuning_' .. session.shop)
    if not paid then
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:purchaseDenied', accountOrMessage)
    end
    local account = accountOrMessage

    local saved, saveError = persistApproved(src, session, row, approved)
    if not saved then
        refund(src, price, account, 'cm_tuning_save_refund')
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:purchaseDenied', (saveError or 'Could not save modifications.') .. ' Payment refunded.')
    end

    local netId = session.netId
    releaseSession(src, 'purchase_complete')
    TriggerClientEvent('cm-tuning:client:purchaseApproved', src, {
        netId = netId,
        mods = approved,
        price = price,
        account = account,
        balances = getBalances(src),
    })
end)

RegisterNetEvent('cm-tuning:server:installHarness', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local ok, session = validateSession(src, data.token, 'chip')
    if not ok then return sendDenied(src, 'cm-tuning:client:specialDenied', session) end
    if session.busy then return sendDenied(src, 'cm-tuning:client:specialDenied', 'A service is already processing.') end
    session.busy = true

    local cfg = Config.Harness or {}
    if cfg.enabled == false then
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:specialDenied', 'Racing harness installation is disabled.')
    end

    local already = false
    pcall(function() already = exports['cm-vehicles']:HasRacingHarness(session.plate) == true end)
    if already then
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:specialDenied', 'This vehicle already has a racing harness.')
    end

    local price = math.max(0, math.floor(tonumber(cfg.price) or 0))
    local paid, accountOrMessage = charge(src, price, data.account, 'cm_tuning_harness')
    if not paid then
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:specialDenied', accountOrMessage)
    end
    local account = accountOrMessage

    local installOk, installed, installMessage = pcall(function()
        return exports['cm-vehicles']:InstallRacingHarness(src, session.plate, session.netId)
    end)
    if not installOk or installed ~= true then
        refund(src, price, account, 'cm_tuning_harness_refund')
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:specialDenied', tostring(installMessage or 'Harness installation failed. Payment refunded.'))
    end

    local netId = session.netId
    releaseSession(src, 'harness_complete')
    TriggerClientEvent('cm-tuning:client:harnessInstalled', src, {
        netId = netId,
        price = price,
        account = account,
        balances = getBalances(src),
    })
end)

RegisterNetEvent('cm-tuning:server:repairEngine', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local ok, session, vehicle = validateSession(src, data.token, 'chip')
    if not ok then return sendDenied(src, 'cm-tuning:client:specialDenied', session) end
    if session.busy then return sendDenied(src, 'cm-tuning:client:specialDenied', 'A service is already processing.') end
    session.busy = true

    local cfg = Config.EngineRepair or {}
    if cfg.enabled == false then
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:specialDenied', 'Engine rebuilding is disabled.')
    end

    local health = 1000.0
    local healthOk, liveHealth = pcall(GetVehicleEngineHealth, vehicle)
    if healthOk and type(liveHealth) == 'number' then health = liveHealth end
    local missing = math.max(0, 1000 - math.floor(health))
    if missing <= 0 then
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:specialDenied', 'The engine is already in perfect condition.')
    end

    local price = math.min(
        tonumber(cfg.maxPrice) or 25000,
        (tonumber(cfg.basePrice) or 0) + missing * (tonumber(cfg.pricePerHealthPoint) or 0)
    )
    price = math.max(0, math.floor(price))

    local paid, accountOrMessage = charge(src, price, data.account, 'cm_tuning_engine_rebuild')
    if not paid then
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:specialDenied', accountOrMessage)
    end
    local account = accountOrMessage

    local patch = { engineHealth = 1000.0 }
    if cfg.fullRebuild ~= false then
        patch.bodyHealth = 1000.0
        patch.tankHealth = 1000.0
    end

    local serviceOk, persisted = pcall(function()
        return exports['cm-vehicles']:ServiceVehicle(session.plate, patch)
    end)
    if not serviceOk or persisted ~= true then
        refund(src, price, account, 'cm_tuning_engine_refund')
        session.busy = false
        return sendDenied(src, 'cm-tuning:client:specialDenied', 'Engine rebuild could not be saved. Payment refunded.')
    end

    local netId = session.netId
    releaseSession(src, 'engine_rebuild')
    TriggerClientEvent('cm-tuning:client:engineApproved', src, {
        netId = netId,
        durationMs = tonumber(cfg.durationMs) or 15000,
        full = cfg.fullRebuild ~= false,
        price = price,
        account = account,
        balances = getBalances(src),
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    releaseSession(src, 'disconnect')
    Cooldowns[src] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Sessions = {}
    VehicleLocks = {}
    Cooldowns = {}
end)

CreateThread(function()
    while true do
        Wait(15000)
        local now = GetGameTimer()
        for src, session in pairs(Sessions) do
            if session.expiresAt < now or not GetPlayerName(src) then
                releaseSession(src, 'timeout_cleanup')
                if GetPlayerName(src) then TriggerClientEvent('cm-tuning:client:sessionExpired', src) end
            end
        end
    end
end)
