local PurchaseLocks = {}
local TestDriveCharges = {}
local ActiveShopPlayers = {}
local CharacterCache = {}
local RateLimits = {}
local CatalogCache = { sourceList = nil, sourceByModel = nil, adminCatalog = nil, publicCatalog = nil, shopVehicles = nil, vehicleByModel = nil, loadedAt = 0 }

local PURCHASE_LOCK_TIMEOUT_MS = 45000
local TEST_DRIVE_CHARGE_TIMEOUT_MS = 30000
local CHARACTER_CACHE_TTL_MS = 30000
local CATALOG_CACHE_TTL_MS = 15000

local function nowMs()
    return GetGameTimer and GetGameTimer() or (os.time() * 1000)
end

local function clampTrunkLevel(level)
    level = math.floor(tonumber(level) or 1)
    if level < 0 then level = 0 end
    if level > 6 then level = 6 end
    return level
end

local function hardeningCfg()
    Config.Security = Config.Security or {}
    return Config.Security
end

local function strongToken(prefix, src)
    prefix = tostring(prefix or 'tok')
    src = tonumber(src) or 0
    local n1 = math.random(100000000, 999999999)
    local n2 = math.random(100000000, 999999999)
    local n3 = math.random(100000000, 999999999)
    return ('%s:%s:%s:%s:%s:%s'):format(prefix, src, nowMs(), n1, n2, n3)
end

local function clearPurchaseLock(src)
    PurchaseLocks[tonumber(src)] = nil
end

local function acquirePurchaseLock(src)
    src = tonumber(src)
    if not src then return false end

    local now = nowMs()
    local existing = PurchaseLocks[src]
    if existing and (tonumber(existing.expiresAt) or 0) > now then
        return false
    end

    local token = strongToken('buy', src)
    PurchaseLocks[src] = { token = token, expiresAt = now + PURCHASE_LOCK_TIMEOUT_MS }

    SetTimeout(PURCHASE_LOCK_TIMEOUT_MS, function()
        local lock = PurchaseLocks[src]
        if lock and lock.token == token then
            PurchaseLocks[src] = nil
            print(('[rn-vehicleshop] Purchase lock timed out for player %s and was released.'):format(src))
        end
    end)

    return true, token
end

local function resetPlayerRuntime(src)
    src = tonumber(src)
    if not src then return end
    PurchaseLocks[src] = nil
    TestDriveCharges[src] = nil
    ActiveShopPlayers[src] = nil
    CharacterCache[src] = nil
    RateLimits[src] = nil
end

local function invalidateCatalogCache()
    CatalogCache = { sourceList = CatalogCache.sourceList, sourceByModel = CatalogCache.sourceByModel, adminCatalog = nil, publicCatalog = nil, shopVehicles = nil, vehicleByModel = nil, loadedAt = 0 }
end


local function debugPrint(...)
    if Config.Debug then print('[RN-VEHICLESHOP-CM]', ...) end
end

local function encode(value)
    local ok, result = pcall(json.encode, value or {})
    return ok and result or '{}'
end

local function decode(value)
    if type(value) == 'table' then return value end
    if not value or value == '' then return {} end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or {}
end

local function truthy(value)
    if value == true then return true end
    if value == false or value == nil then return false end
    if tonumber(value) == 1 then return true end
    local s = tostring(value):lower()
    return s == 'true' or s == 'yes' or s == 'on'
end

local function notify(src, message, kind)
    TriggerClientEvent('rn-vehicleshop:client:notify', src, message or '', kind or 'info')
end

local function callExport(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then return false, nil end
    local args = { ... }
    local ok, result, extra = pcall(function()
        return exports[resource][method](table.unpack(args))
    end)
    if ok then return true, result, extra end
    debugPrint(('Export failed: %s.%s | %s'):format(resource, method, tostring(result)))
    return false, result
end

local function getCharacterId(src)
    src = tonumber(src)
    if not src then return nil end

    local now = nowMs()
    local cached = CharacterCache[src]
    if cached and (tonumber(cached.expiresAt) or 0) > now then
        return cached.value
    end

    local resolved = nil
    local ok, value = callExport('cm-vehicles', 'GetCharacterId', src)
    if ok and value then
        resolved = tostring(value)
    end

    if not resolved and GetResourceState('cm-core') == 'started' then
        -- cm-core character resolvers (different builds expose different names).
        for _, fnName in ipairs({ 'GetCharacterId', 'GetActiveCharacter', 'GetCharacter', 'GetPlayerCharacterId' }) do
            local okc, v = pcall(function()
                local fn = exports['cm-core'] and exports['cm-core'][fnName]
                if not fn then return nil end
                local okColon, res = pcall(function() return fn(exports['cm-core'], src) end)
                if okColon then return res end
                return fn(src)
            end)
            if okc and v then
                if type(v) == 'table' then
                    local id = v.id or v.charId or v.characterId or v.citizenid or v.character_id
                    if id then resolved = tostring(id) break end
                else
                    resolved = tostring(v)
                    break
                end
            end
        end
    end

    if not resolved then
        ok, value = pcall(function()
            local st = Player(src).state
            return st.charId or st.characterId or st.character_id or st.citizenid
        end)
        if ok and value then resolved = tostring(value) end
    end

    if resolved then
        local resolvedText = tostring(resolved)
        local cached = CharacterCache[src] or {}
        if cached.value and tostring(cached.value) ~= resolvedText then
            cached.name = nil
            cached.nameCharId = nil
            cached.nameExpiresAt = nil
        end
        cached.value = resolvedText
        cached.expiresAt = now + CHARACTER_CACHE_TTL_MS
        CharacterCache[src] = cached
    end
    return resolved
end

local function formatCharacterName(row, fallback)
    if row then
        local first = row.first_name or row.firstname or row.firstName
        local last = row.last_name or row.lastname or row.lastName
        if first or last then
            local full = (tostring(first or '') .. ' ' .. tostring(last or '')):gsub('^%s+', ''):gsub('%s+$', '')
            if full ~= '' then return full end
        end
        if row.name and row.name ~= '' then return tostring(row.name) end
    end
    return fallback
end

local function cacheCharacterName(src, charId, name)
    src = tonumber(src)
    if not src or not charId or not name then return end

    local now = nowMs()
    local cached = CharacterCache[src] or {}
    cached.value = tostring(charId)
    cached.expiresAt = now + CHARACTER_CACHE_TTL_MS
    cached.name = tostring(name)
    cached.nameCharId = tostring(charId)
    cached.nameExpiresAt = now + CHARACTER_CACHE_TTL_MS
    CharacterCache[src] = cached
end

local function getCachedCharacterName(src, charId)
    src = tonumber(src)
    if not src or not charId then return nil end

    local cached = CharacterCache[src]
    local now = nowMs()
    if cached
        and cached.name
        and cached.nameCharId == tostring(charId)
        and (tonumber(cached.nameExpiresAt) or 0) > now then
        return cached.name
    end

    return nil
end

local function getCharacterName(src)
    -- Synchronous legacy helper. It now returns cached names when possible.
    -- OpenUI uses getCharacterNameAsync below so the server thread is not blocked
    -- every time a player opens the shop.
    local fallback = GetPlayerName(src) or ('Player ' .. tostring(src))
    local charId = getCharacterId(src)
    if not charId then return fallback end

    local cachedName = getCachedCharacterName(src, charId)
    if cachedName then return cachedName end

    local row = MySQL.single.await('SELECT * FROM characters WHERE id = ? LIMIT 1', { tostring(charId) })
    local name = formatCharacterName(row, fallback)
    cacheCharacterName(src, charId, name)
    return name
end

local function getCharacterNameAsync(src, cb)
    local fallback = GetPlayerName(src) or ('Player ' .. tostring(src))
    local charId = getCharacterId(src)
    if not charId then
        cb(fallback)
        return
    end

    local cachedName = getCachedCharacterName(src, charId)
    if cachedName then
        cb(cachedName)
        return
    end

    local ok = pcall(function()
        MySQL.single('SELECT * FROM characters WHERE id = ? LIMIT 1', { tostring(charId) }, function(row)
            local name = formatCharacterName(row, fallback)
            cacheCharacterName(src, charId, name)
            cb(name)
        end)
    end)

    if not ok then
        cb(fallback)
    end
end

-- Direct fallback that mirrors cm-vehicles' CreateOwnedVehicle exactly (same table,
-- plate format, audit row). Used only if the cm-vehicles export reports the character
-- as "not loaded" even though we resolved a valid charId ourselves. This guarantees
-- the purchase succeeds and the row is identical to what cm-vehicles would have made.
local function generatePlateLikeCmVehicles()
    -- cm-vehicles uses Config.Plate {prefix, length}; default CM + 6 digits.
    local prefix = 'CM'
    local digits = 6
    for _ = 1, 50 do
        local n = math.random(0, (10 ^ digits) - 1)
        local plate = (prefix .. string.format('%0' .. digits .. 'd', n)):upper()
        local exists = MySQL.scalar.await('SELECT plate FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
        if not exists then return plate end
    end

    -- Final fallback is still verified. This avoids two same-millisecond purchases
    -- returning the same os.time-based plate.
    for _ = 1, 25 do
        local plate = (prefix .. string.format('%06d', math.random(0, 999999))):upper()
        local exists = MySQL.scalar.await('SELECT plate FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
        if not exists then return plate end
    end

    return (prefix .. tostring(os.time() % 1000000) .. tostring(math.random(10, 99))):sub(1, 8):upper()
end

local function createOwnedVehicleDirect(charId, model, label, trunkLevel, metadata)
    charId = tostring(charId)
    model = tostring(model or ''):lower()
    if model == '' then return false, 'Invalid model.' end
    label = tostring(label or model)
    trunkLevel = clampTrunkLevel(trunkLevel)
    local plate = generatePlateLikeCmVehicles()

    local ok, id = pcall(function()
        return MySQL.insert.await([[INSERT INTO cm_owned_vehicles
            (owner_character_id, model, label, plate, trunk_level, metadata)
            VALUES (?, ?, ?, ?, ?, ?)]],
            { charId, model, label, plate, trunkLevel, encode(metadata or {}) })
    end)
    if not ok or not id then return false, 'DB insert failed.' end

    -- Match cm-vehicles' audit trail so the row is indistinguishable from a normal create.
    pcall(function()
        MySQL.insert.await('INSERT INTO cm_vehicle_audit (character_id, plate, action, data) VALUES (?, ?, ?, ?)',
            { charId, plate, 'vehicle_created', encode({ model = model, label = label, trunkLevel = trunkLevel, via = 'rn-vehicleshop_direct' }) })
    end)

    return true, { id = id, owner_character_id = charId, model = model, label = label, plate = plate, trunk_level = trunkLevel, is_locked = true, fuel = 100, metadata = metadata or {} }
end

local function generatePlateLikeCmVehiclesAsync(cb, attempt)
    attempt = (attempt or 0) + 1
    local prefix, digits = 'CM', 6
    local n = math.random(0, (10 ^ digits) - 1)
    local plate = (prefix .. string.format('%0' .. digits .. 'd', n)):upper()

    local function verifiedFallback(fallbackAttempt)
        fallbackAttempt = (fallbackAttempt or 0) + 1
        local candidate = (prefix .. string.format('%06d', math.random(0, 999999))):upper()
        if fallbackAttempt > 25 then
            candidate = (prefix .. tostring(os.time() % 1000000) .. tostring(math.random(10, 99))):sub(1, 8):upper()
        end
        MySQL.scalar('SELECT plate FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { candidate }, function(exists)
            if exists and fallbackAttempt <= 25 then return verifiedFallback(fallbackAttempt) end
            cb(candidate)
        end)
    end

    if attempt > 50 then
        return verifiedFallback(0)
    end

    MySQL.scalar('SELECT plate FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate }, function(exists)
        if exists then return generatePlateLikeCmVehiclesAsync(cb, attempt) end
        cb(plate)
    end)
end

local function createOwnedVehicleDirectAsync(charId, model, label, trunkLevel, metadata, cb)
    charId = tostring(charId or '')
    model = tostring(model or ''):lower()
    if charId == '' then return cb(false, 'Character not found.') end
    if model == '' then return cb(false, 'Invalid model.') end

    label = tostring(label or model)
    trunkLevel = clampTrunkLevel(trunkLevel)

    generatePlateLikeCmVehiclesAsync(function(plate)
        MySQL.insert([[INSERT INTO cm_owned_vehicles
            (owner_character_id, model, label, plate, trunk_level, metadata)
            VALUES (?, ?, ?, ?, ?, ?)]],
            { charId, model, label, plate, trunkLevel, encode(metadata or {}) },
            function(id)
                if not id then return cb(false, 'DB insert failed.') end

                MySQL.insert('INSERT INTO cm_vehicle_audit (character_id, plate, action, data) VALUES (?, ?, ?, ?)',
                    { charId, plate, 'vehicle_created', encode({ model = model, label = label, trunkLevel = trunkLevel, via = 'rn-vehicleshop_direct_async' }) })

                cb(true, {
                    id = id, owner_character_id = charId, model = model, label = label, plate = plate,
                    trunk_level = trunkLevel, is_locked = true, fuel = 100, metadata = metadata or {}
                })
            end)
    end)
end

local function resolveAccount(account)
    account = tostring(account or Config.PaymentAccount or 'bank')
    if Config.Accounts and Config.Accounts[account] then return Config.Accounts[account] end
    return account
end

-- Indexing a non-existent export in FiveM THROWS ("No such export X in resource Y"),
-- so the export access AND the call must both live inside pcall. Otherwise a
-- framework that is missing one of the candidate export names crashes the whole
-- purchase thread (this was the RemoveAccountMoney crash).
local function callMoneyExport(method, src, account, amount)
    if GetResourceState('cm-core') ~= 'started' then return false, 'cm-core not started' end

    -- Colon style: exports['cm-core']:Method(src, account, amount)
    local ok, result = pcall(function()
        return exports['cm-core'][method](exports['cm-core'], src, account, amount)
    end)
    if ok and result ~= false then return true end

    -- Dot style: exports['cm-core'].Method(src, account, amount)
    local ok2, result2 = pcall(function()
        return exports['cm-core'][method](src, account, amount)
    end)
    if ok2 and result2 ~= false then return true end

    local why = (not ok and tostring(result)) or (not ok2 and tostring(result2)) or 'export returned false'
    return false, why
end

-- Try a list of candidate export names until one succeeds. cm-core builds differ
-- (RemoveMoney / RemoveAccountMoney / RemovePlayerMoney ...), so we probe safely.
local function tryMoneyExports(methods, src, account, amount)
    local lastWhy
    for _, method in ipairs(methods) do
        local ok, why = callMoneyExport(method, src, account, amount)
        if ok then return true, method end
        lastWhy = why
    end
    return false, lastWhy
end

local function removeMoney(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    account = resolveAccount(account)
    local ok, info = tryMoneyExports(
        { 'RemoveMoney', 'RemoveAccountMoney', 'RemovePlayerMoney', 'removeMoney', 'RemoveMoneyFromAccount' },
        src, account, amount)
    if not ok then
        debugPrint(('removeMoney: no working cm-core export (account=%s amount=%s). Last: %s')
            :format(tostring(account), tostring(amount), tostring(info)))
    end
    return ok
end

local function refundMoney(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    account = resolveAccount(account)
    local ok = tryMoneyExports(
        { 'AddMoney', 'AddAccountMoney', 'AddPlayerMoney', 'addMoney', 'AddMoneyToAccount' },
        src, account, amount)
    return ok
end


local function isAdmin(src)
    if src <= 0 then return true end
    if Config.Admin and Config.Admin.AllPlayers == true then return true end
    local perm = Config.Admin and Config.Admin.AcePermission or 'rnvehicleshop.admin'
    return IsPlayerAceAllowed(src, perm)
end

local function ensureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_vehicle_catalog (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            model VARCHAR(64) NOT NULL UNIQUE,
            label VARCHAR(100) NOT NULL,
            category VARCHAR(64) NOT NULL DEFAULT 'Custom',
            price INT NOT NULL DEFAULT 0,
            trunk_level INT NOT NULL DEFAULT 1,
            available_store TINYINT(1) NOT NULL DEFAULT 0,
            available_server TINYINT(1) NOT NULL DEFAULT 0,
            image VARCHAR(255) NULL,
            metadata LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_category (category),
            INDEX idx_available_store (available_store),
            INDEX idx_available_server (available_server)
        )
    ]])
    -- Migration for servers that created the table before image support existed.
    -- Do not use `ADD COLUMN IF NOT EXISTS` here; older MariaDB/MySQL versions do not
    -- support it and silently broke image capture on some servers. SHOW COLUMNS works
    -- on old MariaDB/MySQL and lets us add the column only when missing.
    local ok, cols = pcall(function()
        return MySQL.query.await([[SHOW COLUMNS FROM cm_vehicle_catalog LIKE 'image']])
    end)
    if ok and (not cols or not cols[1]) then
        pcall(function()
            MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD COLUMN image VARCHAR(255) NULL')
        end)
    end
end

local function normalizeModel(model)
    return tostring(model or ''):lower():gsub('%s+', '')
end


local function isValidModelName(model)
    model = normalizeModel(model)
    if model == '' or #model < 2 or #model > 48 then return false end
    if not model:match('^[%w_%-]+$') then return false end
    return true
end

local function getSourceVehicles()
    if CatalogCache.sourceList and CatalogCache.sourceByModel then
        return CatalogCache.sourceList, CatalogCache.sourceByModel
    end

    local byModel, list = {}, {}
    for _, category in ipairs(Config.Vehicles or {}) do
        local title = tostring(category.title or 'Custom')
        for _, vehicle in ipairs(category.buttons or {}) do
            local model = normalizeModel(vehicle.model)
            if isValidModelName(model) and not byModel[model] then
                local row = {
                    model = model,
                    label = tostring(vehicle.name or vehicle.label or vehicle.model),
                    category = title,
                    price = tonumber(vehicle.costs or vehicle.price) or 0,
                    trunkLevel = clampTrunkLevel(vehicle.trunkLevel or vehicle.trunk_level)
                }
                byModel[model] = row
                list[#list + 1] = row
            end
        end
    end
    table.sort(list, function(a, b)
        if a.category == b.category then return a.label < b.label end
        return a.category < b.category
    end)

    CatalogCache.sourceList = list
    CatalogCache.sourceByModel = byModel
    return list, byModel
end

local function flattenSourceVehicles()
    return getSourceVehicles()
end

local function parseCatalogRow(row)
    if not row then return nil end
    local model = normalizeModel(row.model)
    if not isValidModelName(model) then return nil end
    return {
        id = tonumber(row.id),
        model = model,
        label = tostring(row.label or row.model),
        category = tostring(row.category or 'Custom'),
        price = tonumber(row.price) or 0,
        trunkLevel = clampTrunkLevel(row.trunk_level),
        availableStore = truthy(row.available_store),
        availableServer = truthy(row.available_server),
        image = (row.image and tostring(row.image) ~= '' ) and tostring(row.image) or nil,
        metadata = decode(row.metadata)
    }
end

local function loadCatalogCache(force)
    local now = nowMs()
    if (not force) and CatalogCache.loadedAt and (now - CatalogCache.loadedAt) < CATALOG_CACHE_TTL_MS
        and CatalogCache.adminCatalog and CatalogCache.publicCatalog and CatalogCache.vehicleByModel then
        return
    end

    local rows = MySQL.query.await('SELECT * FROM cm_vehicle_catalog ORDER BY category ASC, label ASC') or {}
    local admin, public, byModel = {}, {}, {}
    for _, row in ipairs(rows) do
        local parsed = parseCatalogRow(row)
        if parsed then
            admin[#admin + 1] = parsed
            byModel[parsed.model] = parsed
            if parsed.availableStore or parsed.availableServer then
                public[#public + 1] = parsed
            end
        end
    end
    CatalogCache.adminCatalog = admin
    CatalogCache.publicCatalog = public
    CatalogCache.vehicleByModel = byModel
    CatalogCache.shopVehicles = nil
    CatalogCache.loadedAt = now
end

local function getCatalog(includeHidden)
    loadCatalogCache(false)
    return includeHidden and (CatalogCache.adminCatalog or {}) or (CatalogCache.publicCatalog or {})
end

local function isKnownOrAllowedModel(model, allowExisting)
    model = normalizeModel(model)
    if not isValidModelName(model) then return false, 'Model name can only use letters, numbers, underscore, or dash, max 48 characters.' end

    local sec = hardeningCfg()
    if sec.AllowUnknownAddonModels == true then return true end

    local _, sourceByModel = getSourceVehicles()
    if sourceByModel and sourceByModel[model] then return true end

    if allowExisting ~= false then
        loadCatalogCache(false)
        if CatalogCache.vehicleByModel and CatalogCache.vehicleByModel[model] then return true end
    end

    return false, 'Model is not in Config.Vehicles. Add it to the source list first, then save/capture it.'
end

local function getCatalogVehicle(model, requireVisible)
    model = normalizeModel(model)
    if not isValidModelName(model) then return nil end
    loadCatalogCache(false)
    local row = CatalogCache.vehicleByModel and CatalogCache.vehicleByModel[model] or nil
    if requireVisible and row and not (row.availableStore or row.availableServer) then return nil end
    return row
end

local function getCatalogVehicleAsync(model, requireVisible, cb)
    model = normalizeModel(model)
    if not isValidModelName(model) then return cb(nil) end
    local cached = getCatalogVehicle(model, requireVisible)
    if cached then return cb(cached) end
    MySQL.single('SELECT * FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { model }, function(row)
        local parsed = parseCatalogRow(row)
        if requireVisible and parsed and not (parsed.availableStore or parsed.availableServer) then parsed = nil end
        cb(parsed)
    end)
end

local function buildShopVehicles()
    loadCatalogCache(false)
    if CatalogCache.shopVehicles then return CatalogCache.shopVehicles end

    local groups = {}
    for _, vehicle in ipairs(CatalogCache.publicCatalog or {}) do
        local category = vehicle.category ~= '' and vehicle.category or 'Custom'
        groups[category] = groups[category] or { title = category, buttons = {} }
        local buyable = vehicle.availableStore == true
        local td = type(vehicle.metadata) == 'table' and type(vehicle.metadata.testDrive) == 'table' and vehicle.metadata.testDrive or {}
        local testEnabled = td.enabled
        if testEnabled == nil then testEnabled = true end
        groups[category].buttons[#groups[category].buttons + 1] = {
            name = vehicle.label,
            costs = tonumber(vehicle.price) or 0,
            model = vehicle.model,
            maxStock = buyable and 'Available' or 'Event / Task only',
            buyable = buyable,
            serverOnly = (vehicle.availableServer == true and not buyable),
            trunkLevel = vehicle.trunkLevel,
            image = vehicle.image,
            testDriveEnabled = testEnabled == true,
            testDriveTimer = tonumber(td.duration) or (Config.TestDrive and tonumber(Config.TestDrive.testDriveTimer)) or 60,
            testDriveCost = tonumber(td.cost) or (Config.TestDrive and tonumber(Config.TestDrive.testDriveCost)) or 0
        }
    end

    local list = {}
    for _, group in pairs(groups) do
        table.sort(group.buttons, function(a, b) return a.name < b.name end)
        list[#list + 1] = group
    end
    table.sort(list, function(a, b) return a.title < b.title end)
    CatalogCache.shopVehicles = list
    return list
end


local function getOwnedVehicleModels(src)
    local owned = {}
    local charId = getCharacterId(src)
    if not charId then return owned end

    local ok, rows = pcall(function()
        return MySQL.query.await('SELECT model FROM cm_owned_vehicles WHERE owner_character_id = ?', { tostring(charId) }) or {}
    end)
    if not ok or type(rows) ~= 'table' then return owned end

    for _, row in ipairs(rows) do
        local model = normalizeModel(row.model)
        if model ~= '' then owned[model] = true end
    end
    return owned
end

local function playerOwnsModel(src, model)
    model = normalizeModel(model)
    if model == '' then return false end
    local charId = getCharacterId(src)
    if not charId then return false end
    local ok, exists = pcall(function()
        return MySQL.scalar.await('SELECT id FROM cm_owned_vehicles WHERE owner_character_id = ? AND model = ? LIMIT 1', { tostring(charId), model })
    end)
    return ok and exists ~= nil
end

local function buildShopVehiclesForPlayer(src)
    local base = buildShopVehicles()
    local owned = getOwnedVehicleModels(src)
    local out = {}

    for _, group in ipairs(base or {}) do
        local g = { title = group.title, buttons = {} }
        for _, vehicle in ipairs(group.buttons or {}) do
            local v = {}
            for k, value in pairs(vehicle) do v[k] = value end
            v.owned = owned[normalizeModel(v.model)] == true
            if v.owned then
                v.ownedText = 'Owned'
            end
            g.buttons[#g.buttons + 1] = v
        end
        out[#out + 1] = g
    end
    return out
end

local function closeEnoughToShop(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local loc = Config.Location
    if not loc then return false end
    local maxDist = tonumber(hardeningCfg().ShopDistance) or 35.0
    local ok, dist = pcall(function()
        return #(GetEntityCoords(ped) - loc)
    end)
    return ok and dist and dist <= maxDist
end

local function requireShopDistance(src, action)
    if closeEnoughToShop(src) then return true end
    local msg = action == 'purchase' and 'You are too far from the dealership to buy a vehicle.' or 'You are too far from the dealership.'
    notify(src, msg, 'error')
    return false
end

local function requireShopSession(src, action)
    src = tonumber(src)
    if src and ActiveShopPlayers[src] then return true end
    notify(src, 'Open the dealership menu first.', 'error')
    if action == 'purchase' then
        TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'Open the dealership menu first.')
    end
    return false
end

-- Per-player routing bucket so previews never clash between players.
local function playerBucketId(src)
    local base = (Config.Dimension and tonumber(Config.Dimension.base)) or 700000
    return base + tonumber(src)
end

local function enterShopBucket(src)
    src = tonumber(src)
    if not src then return end
    ActiveShopPlayers[src] = true
    if not (Config.Dimension and Config.Dimension.enabled) then return end
    local bucket = playerBucketId(src)
    SetPlayerRoutingBucket(src, bucket)
    pcall(function() SetRoutingBucketPopulationEnabled(bucket, false) end)
    pcall(function() SetRoutingBucketEntityLockdownMode(bucket, (Config.Dimension.lockdownMode or 'relaxed')) end)
end

local function leaveShopBucket(src)
    src = tonumber(src)
    if not src then return end
    ActiveShopPlayers[src] = nil
    if not (Config.Dimension and Config.Dimension.enabled) then return end
    pcall(function() SetPlayerRoutingBucket(src, 0) end)
end

local function clearTestDriveCharge(src)
    TestDriveCharges[tonumber(src)] = nil
end

local function createTestDriveCharge(src, account, amount, model)
    src = tonumber(src)
    amount = math.floor(tonumber(amount) or 0)
    if not src or amount <= 0 then return nil end

    local now = GetGameTimer and GetGameTimer() or (os.time() * 1000)
    local token = strongToken('td', src)
    TestDriveCharges[src] = {
        token = token,
        account = account,
        amount = amount,
        model = tostring(model or ''),
        expiresAt = now + TEST_DRIVE_CHARGE_TIMEOUT_MS
    }

    SetTimeout(TEST_DRIVE_CHARGE_TIMEOUT_MS, function()
        local charge = TestDriveCharges[src]
        if charge and charge.token == token then
            refundMoney(src, charge.account, charge.amount)
            TestDriveCharges[src] = nil
            notify(src, 'Test drive could not start. Payment refunded.', 'error')
        end
    end)

    return token
end

-- Best-effort player balance for the Cash/Bank HUD + Insufficient-Funds gate.
-- cm-core money APIs vary between builds, so we probe safely; if nothing matches
-- the client simply hides the HUD and never blocks buying (the purchase itself
-- is still validated server-side by removeMoney).
local function tryGetMoney(method, src, account)
    if GetResourceState('cm-core') ~= 'started' then return nil end
    local ok, res = pcall(function() return exports['cm-core'][method](exports['cm-core'], src, account) end)
    if ok and type(res) == 'number' then return res end
    local ok2, res2 = pcall(function() return exports['cm-core'][method](src, account) end)
    if ok2 and type(res2) == 'number' then return res2 end
    return nil
end

local function getPlayerBalance(src)
    local methods = { 'GetMoney', 'GetAccountMoney', 'GetPlayerMoney', 'getMoney' }
    local cash, bank
    for _, m in ipairs(methods) do
        if cash == nil then cash = tryGetMoney(m, src, 'cash') or tryGetMoney(m, src, 'money') end
        if bank == nil then bank = tryGetMoney(m, src, 'bank') end
        if cash and bank then break end
    end
    if cash == nil and bank == nil then return nil end
    return { cash = cash or 0, bank = bank or 0 }
end

RegisterNetEvent('rn-vehicleshop:server:openUI', function()
    local src = source
    if not closeEnoughToShop(src) then
        TriggerClientEvent('rn-vehicleshop:client:openFailed', src, 'You are too far from the dealership.')
        return notify(src, 'You are too far from the dealership.', 'error')
    end
    enterShopBucket(src)

    -- Character name lookup is async + cached. This avoids blocking the server
    -- thread with MySQL.single.await every time the shop UI opens.
    local vehicles = buildShopVehiclesForPlayer(src)
    local daily = { balance = getPlayerBalance(src) }
    getCharacterNameAsync(src, function(buyerName)
        if not ActiveShopPlayers[src] then return end
        TriggerClientEvent('vehicles:client:openUI', src, vehicles, daily, buyerName)
    end)
end)

-- Client tells us it has fully left the showroom (closed UI, finished buy/test drive).
RegisterNetEvent('rn-vehicleshop:server:leaveShop', function()
    leaveShopBucket(source)
end)

AddEventHandler('playerDropped', function()
    leaveShopBucket(source)
    resetPlayerRuntime(source)
end)

RegisterNetEvent('rn-vehicleshop:server:buyVehicle', function(details)
    local src = source
    if not requireShopSession(src, 'purchase') then return end
    if not requireShopDistance(src, 'purchase') then
        TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'You are too far from the dealership.')
        return
    end
    local gotLock = acquirePurchaseLock(src)
    if not gotLock then
        TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'Purchase already processing. Please wait.')
        return
    end

    local finished = false
    local function finish()
        if finished then return end
        finished = true
        clearPurchaseLock(src)
    end

    details = type(details) == 'table' and details or {}
    local model = normalizeModel(details.model)

    getCatalogVehicleAsync(model, true, function(catalog)
        if not catalog then
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'Vehicle is not available.')
            finish()
            return
        end

        if catalog.availableStore ~= true then
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'Event/task only vehicle.')
            finish()
            return
        end

        local price = tonumber(catalog.price) or 0
        local account = Config.PaymentAccount or 'bank'

        local charId = getCharacterId(src)
        if not charId then
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'Character not found. Relog and try again.')
            finish()
            return
        end

        -- Players may buy duplicates of a vehicle they already own; each purchase
        -- creates a new owned vehicle row with its own plate.

        if not removeMoney(src, account, price) then
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'You do not have enough money.')
            finish()
            return
        end

        local meta = {
            boughtFrom = 'rn-vehicleshop',
            price = price,
            category = catalog.category,
            charId = charId,
            characterId = charId,
            owner = charId,
            stored = true,
            paint = {
                gtaColor = tonumber(details.gtaColor) or 111,
                r = tonumber(details.r) or 255,
                g = tonumber(details.g) or 255,
                b = tonumber(details.b) or 255,
                label = tostring(details.color or 'White')
            }
        }

        -- Leave the private showroom bucket only once the purchase is validated.
        -- If validation fails, keep the player isolated in the showroom instead of
        -- dropping them back into bucket 0 while the store UI is still open.
        leaveShopBucket(src)

        local okExport, createOk, vehicleData = callExport('cm-vehicles', 'CreateOwnedVehicle', src, catalog.model, catalog.label, catalog.trunkLevel, meta)
        if okExport and createOk == true then
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, true,
                ('Purchased %s for $%s. It is stored in your garage.'):format(catalog.label, price), vehicleData)
            finish()
            return
        end

        debugPrint(('cm-vehicles create failed (src=%s char=%s model=%s okExport=%s createOk=%s err=%s); using async direct insert')
            :format(src, tostring(charId), catalog.model, tostring(okExport), tostring(createOk), tostring(vehicleData)))

        createOwnedVehicleDirectAsync(charId, catalog.model, catalog.label, catalog.trunkLevel, meta, function(dok, dres)
            if not dok then
                refundMoney(src, account, price)
                enterShopBucket(src)
                local msg = tostring(dres or vehicleData or 'Could not register vehicle. Payment refunded.')
                TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, msg)
                finish()
                return
            end

            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, true,
                ('Purchased %s for $%s. It is stored in your garage.'):format(catalog.label, price), dres)
            finish()
        end)
    end)
end)

RegisterNetEvent('rn-vehicleshop:server:testDriveRequest', function(details)
    local src = source
    if not requireShopSession(src, 'test_drive') then return end
    if not requireShopDistance(src, 'test_drive') then return end
    details = type(details) == 'table' and details or {}
    local model = normalizeModel(details.model)

    getCatalogVehicleAsync(model, true, function(catalog)
        if not catalog then return notify(src, 'This vehicle is not available.', 'error') end
        if not (Config.TestDrive and Config.TestDrive.enabled) then return notify(src, 'Test drive is disabled.', 'error') end

        local td = type(catalog.metadata) == 'table' and type(catalog.metadata.testDrive) == 'table' and catalog.metadata.testDrive or {}
        if td.enabled == false then return notify(src, 'Test drive is disabled for this vehicle.', 'error') end

        local cost = tonumber(td.cost) or tonumber(Config.TestDrive.testDriveCost) or 0
        local duration = tonumber(td.duration) or tonumber(Config.TestDrive.testDriveTimer) or 60
        local account = Config.PaymentAccount or 'bank'
        if not removeMoney(src, account, cost) then return notify(src, 'You do not have enough money for the test drive.', 'error') end
        local chargeToken = createTestDriveCharge(src, account, cost, model)

        -- Keep the player in their private showroom bucket while they test drive at the airport.
        enterShopBucket(src)
        TriggerClientEvent('rn-vehicleshop:client:startTestDrive', src, details, duration, chargeToken)
    end)
end)

RegisterNetEvent('rn-vehicleshop:server:testDriveStarted', function(token)
    local src = source
    local charge = TestDriveCharges[tonumber(src)]
    if charge and charge.token == token then
        clearTestDriveCharge(src)
    end
end)

RegisterNetEvent('rn-vehicleshop:server:testDriveStartFailed', function(token, reason)
    local src = source
    local charge = TestDriveCharges[tonumber(src)]
    if not charge or charge.token ~= token then return end
    clearTestDriveCharge(src)
    refundMoney(src, charge.account, charge.amount)
    notify(src, ('Test drive could not start (%s). Payment refunded.'):format(tostring(reason or 'failed')), 'error')
end)


local function checkRateLimit(src, key, cooldownMs)
    src = tonumber(src)
    if not src then return false end
    cooldownMs = tonumber(cooldownMs) or 1000
    local now = nowMs()
    RateLimits[src] = RateLimits[src] or {}
    local last = tonumber(RateLimits[src][key]) or 0
    if (now - last) < cooldownMs then
        return false
    end
    RateLimits[src][key] = now
    return true
end

RegisterNetEvent('rn-vehicleshop:server:openAdmin', function()
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have vehicle admin permission.', 'error') end
    if not checkRateLimit(src, 'openAdmin', tonumber(hardeningCfg().AdminOpenCooldownMs) or 750) then return end
    enterShopBucket(src)
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:openAdmin', src, sourceList, getCatalog(true))
end)

local function safeUtf8Sub(value, maxChars, fallback)
    value = tostring(value or fallback or '')
    maxChars = tonumber(maxChars) or 64
    value = value:gsub('%c', '')

    if utf8 and utf8.len and utf8.offset then
        local okLen, len = pcall(utf8.len, value)
        if okLen and len then
            if len <= maxChars then return value end
            local okOff, offset = pcall(utf8.offset, value, maxChars + 1)
            if okOff and offset then return value:sub(1, offset - 1) end
        end
    end

    -- Malformed UTF-8 fallback: keep safe ASCII only so DB strings cannot contain
    -- invalid byte sequences or split multibyte data.
    value = value:gsub('[\128-\255]', '')
    return value:sub(1, maxChars)
end

RegisterNetEvent('rn-vehicleshop:server:saveAdminVehicle', function(data)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    if not checkRateLimit(src, 'saveAdminVehicle', tonumber(hardeningCfg().AdminSaveCooldownMs) or 1500) then
        return notify(src, 'Slow down before saving another vehicle.', 'error')
    end
    data = type(data) == 'table' and data or {}

    local model = normalizeModel(data.model)
    local modelOk, modelErr = isKnownOrAllowedModel(model, true)
    if not modelOk then return notify(src, modelErr or 'Invalid model.', 'error') end

    local label = safeUtf8Sub(data.label, 100, model)
    local category = safeUtf8Sub(data.category, 64, 'Custom')
    local price = math.floor(tonumber(data.price) or 0)
    if price < 0 then price = 0 end
    local trunkLevel = clampTrunkLevel(data.trunkLevel or data.trunk_level)

    local availableStore = truthy(data.availableStore or data.available_store)
    local availableServer = truthy(data.availableServer or data.available_server)
    if availableStore then availableServer = true end

    local testDriveCfg = Config.TestDrive or {}
    local testDriveEnabled = data.testDriveEnabled
    if testDriveEnabled == nil then testDriveEnabled = data.test_drive_enabled end
    if testDriveEnabled == nil then testDriveEnabled = true end
    testDriveEnabled = truthy(testDriveEnabled)
    local testDriveTimer = math.floor(tonumber(data.testDriveTimer or data.test_drive_timer) or tonumber(testDriveCfg.testDriveTimer) or 60)
    if testDriveTimer < 10 then testDriveTimer = 10 end
    if testDriveTimer > 600 then testDriveTimer = 600 end
    local testDriveCost = math.floor(tonumber(data.testDriveCost or data.test_drive_cost) or tonumber(testDriveCfg.testDriveCost) or 0)
    if testDriveCost < 0 then testDriveCost = 0 end

    -- Keep any previously captured image unless this save provides a new path.
    local image = data.image and tostring(data.image) ~= '' and safeUtf8Sub(data.image, 255) or nil
    if not image then
        local existing = MySQL.scalar.await('SELECT image FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { model })
        if existing and tostring(existing) ~= '' then image = tostring(existing) end
    end

    -- A car can only be enabled (store or server) once it has a captured image.
    if (availableStore or availableServer) and (not image or image == '') then
        notify(src, 'Capture an image first. A vehicle cannot be enabled without an image.', 'error')
        TriggerClientEvent('rn-vehicleshop:client:adminNeedsImage', src, model, {
            label = label, category = category, price = price, trunkLevel = trunkLevel,
            availableStore = availableStore, availableServer = availableServer,
            testDriveEnabled = testDriveEnabled, testDriveTimer = testDriveTimer, testDriveCost = testDriveCost
        })
        return
    end

    MySQL.insert.await([[
        INSERT INTO cm_vehicle_catalog (model, label, category, price, trunk_level, available_store, available_server, image, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label),
            category = VALUES(category),
            price = VALUES(price),
            trunk_level = VALUES(trunk_level),
            available_store = VALUES(available_store),
            available_server = VALUES(available_server),
            image = VALUES(image),
            metadata = VALUES(metadata)
    ]], { model, label, category, price, trunkLevel, availableStore and 1 or 0, availableServer and 1 or 0, image, encode({
        savedBy = GetPlayerName(src),
        savedAt = os.time(),
        testDrive = {
            enabled = testDriveEnabled,
            duration = testDriveTimer,
            cost = testDriveCost
        }
    }) })

    invalidateCatalogCache()
    notify(src, ('Saved %s.'):format(label), 'success')
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true))
end)

RegisterNetEvent('rn-vehicleshop:server:disableAdminVehicle', function(model)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    if not checkRateLimit(src, 'disableAdminVehicle', tonumber(hardeningCfg().AdminDisableCooldownMs) or 1000) then return end
    model = normalizeModel(model)
    if not isValidModelName(model) then return notify(src, 'Invalid model.', 'error') end
    local changed = MySQL.update.await('UPDATE cm_vehicle_catalog SET available_store = 0, available_server = 0 WHERE model = ?', { model })
    if not tonumber(changed) or tonumber(changed) <= 0 then
        MySQL.insert.await('INSERT IGNORE INTO cm_vehicle_catalog (model, label, category, price, trunk_level, available_store, available_server) VALUES (?, ?, ?, 0, 1, 0, 0)', { model, model, 'Custom' })
    end
    invalidateCatalogCache()
    notify(src, ('Disabled %s.'):format(model), 'success')
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true))
end)

-- ============================================================================
-- Transparent vehicle image capture (admin). Mirrors nv_cloth: NUI sends a
-- background-removed PNG (base64), we save it into this resource and store the
-- nui:// path in cm_vehicle_catalog.image so the admin list + store can show it.
-- ============================================================================
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64lookup = {}
for i = 1, #b64chars do b64lookup[b64chars:sub(i, i)] = i - 1 end

local function stripBase64Header(data)
    return tostring(data or ''):gsub('%s', ''):gsub('^data:image/%w+;base64,', '')
end

local function estimatedBase64Bytes(data)
    data = stripBase64Header(data)
    return math.floor((#data * 3) / 4)
end

local function base64Decode(data)
    data = stripBase64Header(data)
    local out, buffer, bits = {}, 0, 0
    for i = 1, #data do
        local c = data:sub(i, i)
        if c ~= '=' then
            local val = b64lookup[c]
            if val ~= nil then
                buffer = buffer * 64 + val
                bits = bits + 6
                if bits >= 8 then
                    bits = bits - 8
                    out[#out + 1] = string.char(math.floor(buffer / (2 ^ bits)) % 256)
                    buffer = buffer % (2 ^ bits)
                end
            end
        end
    end
    return table.concat(out)
end

local function safeFilePart(value)
    value = tostring(value or ''):lower():gsub('[^%w_%-%.]', '_'):gsub('_+', '_')
    return value
end


RegisterNetEvent('rn-vehicleshop:server:saveVehicleImage', function(data)
    local src = source
    if not checkRateLimit(src, 'saveVehicleImage', tonumber(hardeningCfg().ImageSaveCooldownMs) or 5000) then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'rate_limited')
        return notify(src, 'Slow down before saving another vehicle image.', 'error')
    end
    if not isAdmin(src) then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'no_permission')
        return notify(src, 'No permission to capture vehicle images.', 'error')
    end
    if not (Config.ImageCapture and Config.ImageCapture.enabled) then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'capture_disabled')
        return
    end

    data = type(data) == 'table' and data or {}
    local model = normalizeModel(data.model)
    local modelOk, modelErr = isKnownOrAllowedModel(model, true)
    if not modelOk then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'invalid_model')
        return notify(src, modelErr or 'Invalid model.', 'error')
    end

    local raw = data.imageBase64 or data.dataUrl
    if not raw or raw == '' then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'empty_image')
        return
    end

    local maxBytes = tonumber(hardeningCfg().MaxImageBase64Bytes) or 2500000
    if estimatedBase64Bytes(raw) > maxBytes then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'image_too_large')
        return notify(src, 'Vehicle image is too large. Reduce capture size and try again.', 'error')
    end

    local bytes = base64Decode(raw)
    if not bytes or #bytes < 100 or #bytes > maxBytes then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'decode_failed')
        return notify(src, 'Vehicle image decode failed or image exceeds max size.', 'error')
    end

    local folder = (Config.ImageCapture.folder or 'ui/images/vehicles'):gsub('^/', ''):gsub('/$', '')
    local ext = tostring(data.ext or ''):lower():gsub('[^%w]', '')
    local mime = tostring(data.mime or ''):lower()
    if ext == '' then
        ext = mime:find('webp', 1, true) and 'webp' or 'png'
    end
    if ext ~= 'webp' and ext ~= 'png' then ext = 'png' end
    local fileName = ('%s_%s.%s'):format(safeFilePart(model), os.time(), ext)
    local savePath = ('%s/%s'):format(folder, fileName)
    if not SaveResourceFile(GetCurrentResourceName(), savePath, bytes, #bytes) then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'save_file_failed')
        return notify(src, 'Could not save vehicle image. Create the ui/images/vehicles folder and check write permission.', 'error')
    end

    -- nui path the UI can load directly: nui://<resource>/<folder>/<file>
    local nuiPath = ('nui://%s/%s/%s'):format(GetCurrentResourceName(), folder, fileName)

    -- Upsert the image onto the catalog row (create a hidden row if it does not exist yet).
    local changed = MySQL.update.await('UPDATE cm_vehicle_catalog SET image = ? WHERE model = ?', { nuiPath, model })
    if not tonumber(changed) or tonumber(changed) <= 0 then
        MySQL.insert.await([[
            INSERT INTO cm_vehicle_catalog (model, label, category, price, trunk_level, available_store, available_server, image)
            VALUES (?, ?, ?, 0, 1, 0, 0, ?)
            ON DUPLICATE KEY UPDATE image = VALUES(image)
        ]], { model, tostring(data.label or model), tostring(data.category or 'Custom'), nuiPath })
    end

    invalidateCatalogCache()
    TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, true, nuiPath, model)
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true))
end)

RegisterCommand('vehicleadmin', function(src)
    if src <= 0 then return end
    if not isAdmin(src) then return notify(src, 'You do not have vehicle admin permission.', 'error') end
    TriggerClientEvent('rn-vehicleshop:client:requestAdmin', src)
end, false)

exports('GetCatalogVehicle', function(model)
    return getCatalogVehicle(model, true)
end)

exports('GiveCatalogVehicle', function(src, model, metadata)
    local catalog = getCatalogVehicle(model, true)
    if not catalog then return false, 'Vehicle is not enabled in catalog.' end
    local okExport, createOk, vehicleData = callExport('cm-vehicles', 'CreateOwnedVehicle', src, catalog.model, catalog.label, catalog.trunkLevel, metadata or { source = 'catalog_export' })
    if not okExport or createOk ~= true then
        local charId = getCharacterId(src)
        if charId then
            local dok, dres = createOwnedVehicleDirect(charId, catalog.model, catalog.label, catalog.trunkLevel, metadata or { source = 'catalog_export' })
            if dok then return true, dres end
        end
        return false, vehicleData or createOk or 'CreateOwnedVehicle failed.'
    end
    return true, vehicleData
end)


AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local active = {}
    for src in pairs(ActiveShopPlayers) do active[#active + 1] = src end
    for _, src in ipairs(active) do
        leaveShopBucket(src)
    end

    if Config.Dimension and Config.Dimension.enabled then
        local base = tonumber(Config.Dimension.base) or 700000
        local maxBucket = base + 100000
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            if src then
                local bucket = GetPlayerRoutingBucket(src)
                if bucket and bucket >= base and bucket < maxBucket then
                    SetPlayerRoutingBucket(src, 0)
                end
                resetPlayerRuntime(src)
            end
        end
    end

    PurchaseLocks = {}
    TestDriveCharges = {}
    ActiveShopPlayers = {}
    CharacterCache = {}
    RateLimits = {}
end)

local function validateConfig()
    Config.Security = Config.Security or {}
    if Config.Security.ShopDistance == nil then Config.Security.ShopDistance = 35.0 end
    if Config.Security.MaxImageBase64Bytes == nil then Config.Security.MaxImageBase64Bytes = 2500000 end
    if Config.Security.AdminSaveCooldownMs == nil then Config.Security.AdminSaveCooldownMs = 1500 end
    if Config.Security.ImageSaveCooldownMs == nil then Config.Security.ImageSaveCooldownMs = 5000 end
    if Config.Security.AdminDisableCooldownMs == nil then Config.Security.AdminDisableCooldownMs = 1000 end
    if Config.Security.AllowUnknownAddonModels == nil then Config.Security.AllowUnknownAddonModels = false end

    if not Config.Location then
        print('[rn-vehicleshop] WARNING: Config.Location is missing. Store distance checks will fail.')
    end
    if not Config.TestVehicleSpawnLocation or not Config.TestVehicleSpawnLocation.coords then
        print('[rn-vehicleshop] WARNING: Config.TestVehicleSpawnLocation.coords is missing. Test drives will be disabled by client error.')
    end
    getSourceVehicles()
    print(('[rn-vehicleshop] Started v%s | source models=%s | max image bytes=%s')
        :format(GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown', #(CatalogCache.sourceList or {}), tostring(Config.Security.MaxImageBase64Bytes)))
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    math.randomseed(os.time() + nowMs())
    validateConfig()
    ensureTables()
    invalidateCatalogCache()
    loadCatalogCache(true)
    debugPrint('Vehicles must be enabled with /vehicleadmin before they appear.')
end)
