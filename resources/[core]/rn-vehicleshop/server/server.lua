local PurchaseLocks = {}
local TestDriveCharges = {}
local TestDriveLocks = {}
local ActiveShopPlayers = {}
local CharacterCache = {}
local RateLimits = {}
local AdminModes = {}
local CatalogCache = { sourceList = nil, sourceByModel = nil, adminCatalog = nil, publicCatalog = nil, shopVehicles = nil, vehicleByModel = nil, loadedAt = 0 }
local RuntimeVehicleCache = { list = {}, byModel = {} }

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

-- ── EMS fleet vehicle appearance (paint/livery/wheels/etc) ──────────────────
-- Same validated shape and bounds as cm-ems's fleet vehicle mods (server/
-- vehicles.lua): fail-closed, unknown/out-of-range fields dropped rather than
-- passed through. Kept here rather than shared, matching how this codebase
-- already duplicates small self-contained validation/utility helpers per
-- resource instead of introducing a shared library resource for them.
local function clampModInt(value, min, max, default)
    local n = tonumber(value)
    if n == nil then n = default or min end
    n = math.floor(n)
    if n < min then n = min end
    if n > max then n = max end
    return n
end

local function sanitizeRgbMod(raw)
    if type(raw) ~= 'table' then return nil end
    return { r = clampModInt(raw.r, 0, 255, 0), g = clampModInt(raw.g, 0, 255, 0), b = clampModInt(raw.b, 0, 255, 0) }
end

local function sanitizeVehicleMods(raw)
    if type(raw) ~= 'table' then return {} end
    local out = {}
    if raw.catalogMaxSpeedKph ~= nil then out.catalogMaxSpeedKph = clampModInt(raw.catalogMaxSpeedKph, 1, 1000, 1) end

    if raw.primaryColor ~= nil then out.primaryColor = clampModInt(raw.primaryColor, 0, 160, 0) end
    if raw.secondaryColor ~= nil then out.secondaryColor = clampModInt(raw.secondaryColor, 0, 160, 0) end
    if raw.pearlColor ~= nil then out.pearlColor = clampModInt(raw.pearlColor, 0, 160, 0) end
    if raw.wheelColor ~= nil then out.wheelColor = clampModInt(raw.wheelColor, 0, 160, 0) end
    local customPrimary = sanitizeRgbMod(raw.customPrimary)
    if customPrimary then out.customPrimary = customPrimary end
    local customSecondary = sanitizeRgbMod(raw.customSecondary)
    if customSecondary then out.customSecondary = customSecondary end

    if raw.wheelType ~= nil then out.wheelType = clampModInt(raw.wheelType, 0, 12, 0) end
    if raw.windowTint ~= nil then out.windowTint = clampModInt(raw.windowTint, 0, 4, 0) end
    if raw.plateIndex ~= nil then out.plateIndex = clampModInt(raw.plateIndex, 0, 5, 0) end
    if raw.livery ~= nil then out.livery = clampModInt(raw.livery, -1, 100, -1) end
    if raw.tyreLevel ~= nil then out.tyreLevel = clampModInt(raw.tyreLevel, 0, 4, 0) end

    out.turbo = raw.turbo == true
    out.xenon = raw.xenon == true
    out.bulletproofTyres = raw.bulletproofTyres == true
    out.customWheels = raw.customWheels == true

    if type(raw.extras) == 'table' then
        local extras = {}
        for key, value in pairs(raw.extras) do
            local id = tonumber(key)
            if id and id >= 1 and id <= 14 then extras[tostring(id)] = value == true end
        end
        out.extras = extras
    end

    if type(raw.mods) == 'table' then
        local slots, count = {}, 0
        for key, value in pairs(raw.mods) do
            local modType, idx = tonumber(key), tonumber(value)
            if modType and idx and modType >= 0 and modType <= 49 and idx >= -1 and idx <= 254 then
                slots[tostring(modType)] = idx
                count = count + 1
                if count >= 30 then break end
            end
        end
        out.mods = slots
    end

    if type(raw.neons) == 'table' then
        local neons = {}
        for i = 1, 4 do neons[i] = raw.neons[i] == true end
        out.neons = neons
    end
    local neonColor = sanitizeRgbMod(raw.neonColor)
    if neonColor then out.neonColor = neonColor end

    return out
end

-- Read-only paint/livery/wheel/tyre/neon option catalog, owned by cm-tuning
-- (server/main.lua:GetVisualCatalog). Cached since it is static reference data.
local VisualCatalogCache = nil
local function getVisualCatalog()
    if VisualCatalogCache then return VisualCatalogCache end
    local ok, catalog = pcall(function() return exports['cm-tuning']:GetVisualCatalog() end)
    VisualCatalogCache = (ok and type(catalog) == 'table') and catalog or {}
    return VisualCatalogCache
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
    TestDriveLocks[src] = nil
    ActiveShopPlayers[src] = nil
    CharacterCache[src] = nil
    RateLimits[src] = nil
    AdminModes[src] = nil
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

local function structuredAdminLog(category, action, src, data, level)
    local cfg = Config.Logging or {}
    if cfg.enabled == false then return end

    src = tonumber(src) or 0
    local payload = {
        resource = GetCurrentResourceName(),
        category = tostring(category or 'vehicleshop'),
        action = tostring(action or 'event'),
        level = tostring(level or 'info'),
        source = src,
        playerName = src > 0 and (GetPlayerName(src) or ('Player ' .. src)) or 'server',
        characterId = nil,
        timestamp = os.time(),
        data = type(data) == 'table' and data or { value = data }
    }
    if src > 0 then
        local okState, stateCharId = pcall(function()
            local state = Player(src).state
            return state.charId or state.characterId or state.character_id or state.citizenid
        end)
        if okState and stateCharId then payload.characterId = tostring(stateCharId) end
    end

    local delivered = false
    local resource = tostring(cfg.resource or 'cm-admin')
    if GetResourceState(resource) == 'started' then
        for _, method in ipairs(cfg.exportMethods or { 'AddLog', 'CreateLog', 'Log' }) do
            local ok, result = pcall(function()
                return exports[resource][method](payload)
            end)
            if ok and result ~= false then
                delivered = true
                break
            end
        end
        if not delivered and cfg.eventName and cfg.eventName ~= '' then
            TriggerEvent(cfg.eventName, payload)
            delivered = true
        end
    end

    if cfg.consoleFallback == true or not delivered then
        local okJson, jsonData = pcall(json.encode, payload.data or {})
        print(('[rn-vehicleshop][audit] %s/%s src=%s data=%s')
            :format(payload.category, payload.action, src, okJson and jsonData or '{}'))
    end
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

-- cm-playerdata is the single money authority.
local function pd()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function getMoney(src, account)
    local p = pd()
    if not p then return nil end
    account = resolveAccount(account)
    local ok, amount = pcall(function() return p:GetMoney(src, account) end)
    if ok and type(amount) == 'number' then return math.max(0, math.floor(amount)) end
    return nil
end

local function canAfford(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local p = pd()
    if not p then return false end
    account = resolveAccount(account)
    local ok, res = pcall(function() return p:CanAfford(src, account, amount) end)
    if ok and type(res) == 'boolean' then return res end
    local bal = getMoney(src, account)
    return type(bal) == 'number' and bal >= amount
end

local function removeMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local p = pd()
    if not p then return false, 'playerdata_unavailable' end
    account = resolveAccount(account)
    if not canAfford(src, account, amount) then return false, 'not_enough' end
    local ok, result = pcall(function()
        return p:RemoveMoney(src, account, amount, reason or 'vehicleshop_payment')
    end)
    if ok and result == true then return true end
    return false, 'charge_failed'
end

local function refundMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local p = pd()
    if not p then return false end
    account = resolveAccount(account)
    local ok, result = pcall(function()
        return p:AddMoney(src, account, amount, reason or 'vehicleshop_refund')
    end)
    return ok and result == true
end

local function paymentPriority()
    local configured = Config.Payment and Config.Payment.Priority
    local out, seen = {}, {}
    for _, account in ipairs(type(configured) == 'table' and configured or { 'cash', 'bank' }) do
        account = resolveAccount(account)
        if (account == 'cash' or account == 'bank') and not seen[account] then
            out[#out + 1] = account
            seen[account] = true
        end
    end
    if #out == 0 then out = { resolveAccount(Config.PaymentAccount or 'bank') } end
    return out
end

local function getCombinedAvailable(src)
    local total, balances = 0, {}
    for _, account in ipairs(paymentPriority()) do
        local amount = getMoney(src, account) or 0
        balances[account] = amount
        total = total + amount
    end
    return total, balances
end

-- Debits cash first and bank second by default. If a later debit fails, every
-- earlier debit is refunded before the function returns.
local function removeCombinedMoney(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true, {}, nil end

    if not (Config.Payment and Config.Payment.UseCombinedFunds ~= false) then
        local account = resolveAccount(Config.PaymentAccount or 'bank')
        local ok, err = removeMoney(src, account, amount, reason)
        return ok, ok and { { account = account, amount = amount } } or nil, err
    end

    local available, balances = getCombinedAvailable(src)
    if available < amount then return false, nil, 'not_enough', available end

    local remaining, debits = amount, {}
    for _, account in ipairs(paymentPriority()) do
        if remaining <= 0 then break end
        local take = math.min(remaining, balances[account] or 0)
        if take > 0 then
            local ok, err = removeMoney(src, account, take, reason)
            if not ok then
                for i = #debits, 1, -1 do
                    refundMoney(src, debits[i].account, debits[i].amount, 'vehicleshop_payment_rollback')
                end
                return false, nil, err or 'charge_failed', available
            end
            debits[#debits + 1] = { account = account, amount = take }
            remaining = remaining - take
        end
    end

    if remaining > 0 then
        for i = #debits, 1, -1 do
            refundMoney(src, debits[i].account, debits[i].amount, 'vehicleshop_payment_rollback')
        end
        return false, nil, 'charge_failed', available
    end
    return true, debits, nil, available
end

local function refundCombinedMoney(src, debits, reason)
    if type(debits) ~= 'table' then return false end
    local allOk = true
    for i = #debits, 1, -1 do
        local row = debits[i]
        if row and not refundMoney(src, row.account, row.amount, reason or 'vehicleshop_refund') then
            allOk = false
        end
    end
    return allOk
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
            speed_kph INT NULL,
            trunk_level INT NOT NULL DEFAULT 1,
            available_store TINYINT(1) NOT NULL DEFAULT 0,
            available_server TINYINT(1) NOT NULL DEFAULT 0,
            available_ems TINYINT(1) NOT NULL DEFAULT 0,
            available_police TINYINT(1) NOT NULL DEFAULT 0,
            image VARCHAR(255) NULL,
            metadata LONGTEXT NULL,
            mods LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_category (category),
            INDEX idx_available_store (available_store),
            INDEX idx_available_server (available_server),
            INDEX idx_available_ems (available_ems),
            INDEX idx_available_police (available_police)
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

    -- Same migration pattern for the EMS fleet destination: a mutually-exclusive
    -- 4th catalog status (hidden/server/store/ems) plus a saved appearance
    -- (paint/livery/wheels/etc, same shape cm-ems's fleet vehicles use).
    local okEms, colsEms = pcall(function()
        return MySQL.query.await([[SHOW COLUMNS FROM cm_vehicle_catalog LIKE 'available_ems']])
    end)
    if okEms and (not colsEms or not colsEms[1]) then
        pcall(function()
            MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD COLUMN available_ems TINYINT(1) NOT NULL DEFAULT 0')
        end)
        pcall(function()
            MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD INDEX idx_available_ems (available_ems)')
        end)
    end
    local okMods, colsMods = pcall(function()
        return MySQL.query.await([[SHOW COLUMNS FROM cm_vehicle_catalog LIKE 'mods']])
    end)
    if okMods and (not colsMods or not colsMods[1]) then
        pcall(function()
            MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD COLUMN mods LONGTEXT NULL')
        end)
    end

    -- Same migration pattern again for the Police fleet destination: a 5th
    -- mutually-exclusive catalog status alongside hidden/server/store/ems.
    local okPolice, colsPolice = pcall(function()
        return MySQL.query.await([[SHOW COLUMNS FROM cm_vehicle_catalog LIKE 'available_police']])
    end)
    if okPolice and (not colsPolice or not colsPolice[1]) then
        pcall(function()
            MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD COLUMN available_police TINYINT(1) NOT NULL DEFAULT 0')
        end)
        pcall(function()
            MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD INDEX idx_available_police (available_police)')
        end)
    end
    local okSpeed, colsSpeed = pcall(function()
        return MySQL.query.await([[SHOW COLUMNS FROM cm_vehicle_catalog LIKE 'speed_kph']])
    end)
    if okSpeed and (not colsSpeed or not colsSpeed[1]) then
        pcall(function() MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD COLUMN speed_kph INT NULL AFTER price') end)
    end

    -- Generic legal-org fleet destination: unlike available_ems/available_police
    -- (one hardcoded column each), this is a single nullable column holding
    -- whichever org id (e.g. 'sahp', 'fib') the vehicle is tagged for, so any
    -- number of cm-law organizations can use the same mutually-exclusive
    -- catalog-status pattern without a new column per org.
    local okLegal, colsLegal = pcall(function()
        return MySQL.query.await([[SHOW COLUMNS FROM cm_vehicle_catalog LIKE 'legal_org']])
    end)
    if okLegal and (not colsLegal or not colsLegal[1]) then
        pcall(function()
            MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD COLUMN legal_org VARCHAR(32) NULL')
        end)
        pcall(function()
            MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD INDEX idx_legal_org (legal_org)')
        end)
    end

    -- Discovery used to publish class-priced GTA models immediately. Keep every
    -- discovered model available to Manage Vehicles, but fail closed for every
    -- destination until an admin has captured an image and deliberately saved a
    -- status. Existing photographed/configured rows are left untouched.
    MySQL.update.await([[
        UPDATE cm_vehicle_catalog
        SET available_store = 0,
            available_server = 0,
            available_ems = 0,
            available_police = 0
        WHERE image IS NULL OR TRIM(image) = ''
    ]])
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

-- ============================================================================
-- Automatic add-on vehicle discovery
-- Scans started resources for vehicles.meta files using CfxLua's sandboxed
-- io.readdir API. Results are cached and merged with Config.Vehicles.
-- ============================================================================
local VehicleDiscoveryCache = { list = nil, byModel = nil, scannedAt = 0, resources = 0, metaFiles = 0 }

-- Soft integration: the admin catalog's status dropdown offers one option
-- per cm-law organization (alongside the fixed EMS/Police options) so a
-- vehicle can be tagged for any of them without rn-vehicleshop hardcoding
-- org names. Works fine with cm-law absent -- the dropdown just won't
-- offer legal-org options.
local function legalOrgOptions()
    if GetResourceState('cm-law') ~= 'started' then return {} end
    local ok, organizations = pcall(function() return exports['cm-law']:GetOrganizations() end)
    if not ok or type(organizations) ~= 'table' then return {} end
    local out = {}
    for _, org in ipairs(organizations) do
        out[#out + 1] = { id = org.id, label = org.shortLabel or org.label }
    end
    return out
end

-- Shared metadata table sent alongside every rn-vehicleshop:client:adminData
-- push -- factored out so legalOrganizations doesn't need repeating at each
-- of this file's several call sites. Must be declared after
-- VehicleDiscoveryCache above (it reads that local).
local function adminMeta(extra)
    local meta = {
        autoDiscovered = #(VehicleDiscoveryCache.list or {}),
        scannedResources = VehicleDiscoveryCache.resources or 0,
        metaFiles = VehicleDiscoveryCache.metaFiles or 0,
        visualCatalog = getVisualCatalog(),
        legalOrganizations = legalOrgOptions(),
    }
    if type(extra) == 'table' then for key, value in pairs(extra) do meta[key] = value end end
    return meta
end

local function discoveryCfg()
    return type(Config.AutoDiscoverVehicles) == 'table' and Config.AutoDiscoverVehicles or {}
end

local function clearVehicleDiscoveryCache()
    VehicleDiscoveryCache = { list = nil, byModel = nil, scannedAt = 0, resources = 0, metaFiles = 0 }
    CatalogCache.sourceList = nil
    CatalogCache.sourceByModel = nil
end

local function resourceNameMatches(name, patterns)
    if type(patterns) ~= 'table' or #patterns == 0 then return false end
    name = tostring(name or ''):lower()
    for _, pattern in ipairs(patterns) do
        pattern = tostring(pattern or ''):lower()
        if pattern ~= '' and name:find(pattern, 1, true) then return true end
    end
    return false
end

local function shouldScanResource(resourceName)
    local cfg = discoveryCfg()
    if resourceName == '' or resourceName == GetCurrentResourceName() then return false end
    if GetResourceState(resourceName) ~= 'started' then return false end
    if resourceNameMatches(resourceName, cfg.excludeResources) then return false end
    if type(cfg.includeResources) == 'table' and #cfg.includeResources > 0
        and not resourceNameMatches(resourceName, cfg.includeResources) then
        return false
    end

    -- Avoid walking every unrelated script/UI/map resource. Vehicle packs that
    -- register vehicles.meta declare VEHICLE_METADATA_FILE in their manifest.
    local manifest = LoadResourceFile(resourceName, 'fxmanifest.lua')
        or LoadResourceFile(resourceName, '__resource.lua')
    if manifest and manifest ~= '' then
        local upper = manifest:upper()
        local lower = manifest:lower()
        if not upper:find('VEHICLE_METADATA_FILE', 1, true)
            and not lower:find('vehicles.meta', 1, true) then
            return false
        end
    end
    return true
end

local function readDir(path)
    if not io or type(io.readdir) ~= 'function' then return nil end
    local ok, handle = pcall(io.readdir, path)
    if not ok or not handle then return nil end
    local out = {}
    local iterOk, iterErr = pcall(function()
        for name in handle:lines() do
            if name and name ~= '' and name ~= '.' and name ~= '..' then
                out[#out + 1] = tostring(name)
            end
        end
    end)
    pcall(function() handle:close() end)
    if not iterOk then
        debugPrint(('Vehicle discovery could not read %s: %s'):format(path, tostring(iterErr)))
        return nil
    end
    return out
end

local function findVehicleMetaFiles(resourceName)
    local cfg = discoveryCfg()
    local maxDepth = math.max(1, math.min(12, tonumber(cfg.maxDepth) or 7))
    -- Hard ceiling raised from 250 to 1000: large multi-vehicle packs that
    -- organise as stream/[Brand]/[Model]/vehicles.meta per car (a very common
    -- convention -- e.g. 600-DebadgedCars ships 600+ of them) legitimately
    -- exceed the old cap, which silently truncated discovery well before any
    -- "not all visible" symptom was otherwise explained.
    local maxFiles = math.max(1, math.min(1000, tonumber(cfg.maxMetaFilesPerResource) or 80))
    local found, visited = {}, {}

    local function walk(relative, depth)
        if #found >= maxFiles or depth > maxDepth then return end
        local mount = ('@%s/%s'):format(resourceName, relative or '')
        if visited[mount] then return end
        visited[mount] = true
        local entries = readDir(mount)
        if not entries then return end
        table.sort(entries)
        for _, name in ipairs(entries) do
            if #found >= maxFiles then break end
            local rel = (relative and relative ~= '') and (relative .. '/' .. name) or name
            local lower = name:lower()
            if lower == 'vehicles.meta' then
                found[#found + 1] = rel
            elseif depth < maxDepth then
                -- Never traverse large UI/script folders; they never contain
                -- vehicles.meta. NOTE: 'stream' is deliberately NOT skipped --
                -- that is exactly where per-car vehicles.meta commonly lives
                -- (stream/[Brand]/[Model]/vehicles.meta). A flat binary-only
                -- stream/ folder just costs one extra readdir() call; its loose
                -- .ytd/.yft files all have extensions so they never recurse.
                local skipDirectory = lower == 'ui' or lower == 'html'
                    or lower == 'web' or lower == 'client' or lower == 'server'
                    or lower == 'locales' or lower == 'audio' or lower == 'sounds'
                local likelyDirectory = not skipDirectory and (not name:match('%.%w+$')
                    or lower == 'data' or lower == 'common' or lower == 'dlc')
                if likelyDirectory then walk(rel, depth + 1) end
            end
        end
    end

    walk('', 0)
    return found
end

local xmlEntities = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'" }
local function xmlText(value)
    value = tostring(value or '')
    value = value:gsub('&(%a+);', function(entity) return xmlEntities[entity] or ('&' .. entity .. ';') end)
    return value:gsub('^%s+', ''):gsub('%s+$', '')
end

local vehicleClassNames = {
    VC_COMPACT = 'Compacts', VC_SEDAN = 'Sedans', VC_SUV = 'SUV', VC_COUPE = 'Coupes',
    VC_MUSCLE = 'Muscle', VC_SPORT_CLASSIC = 'Sports Classics', VC_SPORT = 'Sports',
    VC_SUPER = 'Super', VC_MOTORCYCLE = 'Motorcycles', VC_OFF_ROAD = 'Off Road',
    VC_INDUSTRIAL = 'Industrial', VC_UTILITY = 'Utility', VC_VAN = 'Vans',
    VC_CYCLE = 'Bicycles', VC_BOAT = 'Boats', VC_HELICOPTER = 'Helicopters',
    VC_PLANE = 'Planes', VC_SERVICE = 'Service', VC_EMERGENCY = 'Emergency',
    VC_MILITARY = 'Military', VC_COMMERCIAL = 'Commercial', VC_RAIL = 'Rail'
}

local function humanizeModel(model)
    local value = tostring(model or ''):gsub('[_%-]+', ' ')
    value = value:gsub('(%l)(%u)', '%1 %2')
    value = value:gsub('(%a)(%d)', '%1 %2'):gsub('(%d)(%a)', '%1 %2')
    value = value:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return (value:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b:lower() end))
end

local function parseVehicleMeta(resourceName, relativePath)
    local content = LoadResourceFile(resourceName, relativePath)
    if not content or content == '' then return {} end
    content = content:gsub('<!%-%-.-%-%->', '')
    local rows, seen = {}, {}

    local function addBlock(block)
        local model = normalizeModel(block:match('<modelName>%s*([^<]-)%s*</modelName>'))
        if not isValidModelName(model) or seen[model] then return end
        local gameName = xmlText(block:match('<gameName>%s*([^<]-)%s*</gameName>'))
        local classCode = xmlText(block:match('<vehicleClass>%s*([^<]-)%s*</vehicleClass>')):upper()
        local txdName = xmlText(block:match('<txdName>%s*([^<]-)%s*</txdName>'))
        local handlingId = xmlText(block:match('<handlingId>%s*([^<]-)%s*</handlingId>'))
        seen[model] = true
        rows[#rows + 1] = {
            model = model,
            label = humanizeModel(model),
            gameName = gameName ~= '' and gameName or nil,
            category = vehicleClassNames[classCode] or 'Custom',
            classCode = classCode ~= '' and classCode or nil,
            txdName = txdName ~= '' and txdName or nil,
            handlingId = handlingId ~= '' and handlingId or nil,
            resource = resourceName,
            metaFile = relativePath,
            autoDiscovered = true,
            price = 0,
            trunkLevel = 1
        }
    end

    for block in content:gmatch('<Item[^>]*>(.-)</Item>') do addBlock(block) end
    -- Some packs use a non-standard root without Item wrappers.
    if #rows == 0 then addBlock(content) end
    return rows
end

local function discoverAddonVehicles(force)
    local cfg = discoveryCfg()
    if cfg.enabled == false then return {}, {} end
    local now = os.time()
    local ttl = math.max(5, tonumber(cfg.cacheSeconds) or 60)
    if not force and VehicleDiscoveryCache.list and (now - VehicleDiscoveryCache.scannedAt) < ttl then
        return VehicleDiscoveryCache.list, VehicleDiscoveryCache.byModel
    end

    local list, byModel = {}, {}
    local resourceCount, metaCount = 0, 0
    local maxVehicles = math.max(100, math.min(20000, tonumber(cfg.maxVehicles) or 5000))
    local total = GetNumResources()
    for index = 0, total - 1 do
        if #list >= maxVehicles then break end
        local resourceName = GetResourceByFindIndex(index)
        if resourceName and shouldScanResource(resourceName) then
            local metaFiles = findVehicleMetaFiles(resourceName)
            if #metaFiles > 0 then resourceCount = resourceCount + 1 end
            for _, relativePath in ipairs(metaFiles) do
                if #list >= maxVehicles then break end
                metaCount = metaCount + 1
                for _, row in ipairs(parseVehicleMeta(resourceName, relativePath)) do
                    if #list >= maxVehicles then break end
                    if not byModel[row.model] then
                        byModel[row.model] = row
                        list[#list + 1] = row
                    end
                end
                if metaCount % 20 == 0 then Wait(0) end
            end
        end
        if index % 30 == 0 then Wait(0) end
    end

    table.sort(list, function(a, b)
        if a.category == b.category then return a.label < b.label end
        return a.category < b.category
    end)
    VehicleDiscoveryCache = {
        list = list, byModel = byModel, scannedAt = now,
        resources = resourceCount, metaFiles = metaCount
    }
    debugPrint(('Auto-discovered %d vehicles from %d started resources (%d vehicles.meta files).')
        :format(#list, resourceCount, metaCount))
    return list, byModel
end

local function getSourceVehicles(forceDiscovery)
    if not forceDiscovery and CatalogCache.sourceList and CatalogCache.sourceByModel then
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
                    trunkLevel = clampTrunkLevel(vehicle.trunkLevel or vehicle.trunk_level),
                    source = 'config',
                    autoDiscovered = false
                }
                byModel[model] = row
                list[#list + 1] = row
            end
        end
    end

    local discovered = discoverAddonVehicles(forceDiscovery == true)
    for _, row in ipairs(discovered or {}) do
        local existing = byModel[row.model]
        if existing then
            existing.resource = row.resource
            existing.metaFile = row.metaFile
            existing.gameName = row.gameName
            existing.handlingId = row.handlingId
            existing.txdName = row.txdName
        else
            byModel[row.model] = row
            list[#list + 1] = row
        end
    end

    -- Base-game GTA models are reported by an authorised admin client because
    -- FiveM exposes GetAllVehicleModels client-side. They belong in the Manage
    -- Vehicles discovery list, not in the persistent/published catalog.
    for _, row in ipairs(RuntimeVehicleCache.list or {}) do
        if not byModel[row.model] then
            byModel[row.model] = row
            list[#list + 1] = row
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

local function flattenSourceVehicles(forceDiscovery)
    local list = getSourceVehicles(forceDiscovery == true)
    return list
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
        speedKph = tonumber(row.speed_kph),
        trunkLevel = clampTrunkLevel(row.trunk_level),
        availableStore = truthy(row.available_store),
        availableServer = truthy(row.available_server),
        availableEms = truthy(row.available_ems),
        availablePolice = truthy(row.available_police),
        legalOrg = (row.legal_org and tostring(row.legal_org) ~= '') and tostring(row.legal_org) or nil,
        image = (row.image and tostring(row.image) ~= '' ) and tostring(row.image) or nil,
        metadata = decode(row.metadata),
        mods = decode(row.mods)
    }
end

local function loadCatalogCache(force)
    local now = nowMs()
    if (not force) and CatalogCache.loadedAt and (now - CatalogCache.loadedAt) < CATALOG_CACHE_TTL_MS
        and CatalogCache.adminCatalog and CatalogCache.publicCatalog and CatalogCache.vehicleByModel then
        return
    end

    local rows = MySQL.query.await([[
        SELECT id, model, label, category, price, speed_kph, trunk_level,
               available_store, available_server, available_ems, available_police,
               legal_org, image, metadata, mods
        FROM cm_vehicle_catalog
        WHERE (image IS NOT NULL AND TRIM(image) <> '')
           OR available_store = 1
           OR available_server = 1
           OR available_ems = 1
           OR available_police = 1
           OR legal_org IS NOT NULL
        ORDER BY category ASC, label ASC
    ]]) or {}
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

    return false, 'Model was not found in Config.Vehicles or any started resource vehicles.meta file. Start the vehicle pack, rescan, then try again.'
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

local function enterShopBucket(src, mode)
    src = tonumber(src)
    if not src then return end
    local session = ActiveShopPlayers[src]
    if type(session) ~= 'table' then
        session = {
            originalBucket = GetPlayerRoutingBucket(src),
            enteredAt = nowMs(),
            mode = mode or 'store'
        }
        ActiveShopPlayers[src] = session
    else
        session.mode = mode or session.mode or 'store'
    end

    if not (Config.Dimension and Config.Dimension.enabled) then return end
    local bucket = playerBucketId(src)
    session.shopBucket = bucket
    SetPlayerRoutingBucket(src, bucket)
    pcall(function() SetRoutingBucketPopulationEnabled(bucket, false) end)
    pcall(function() SetRoutingBucketEntityLockdownMode(bucket, (Config.Dimension.lockdownMode or 'relaxed')) end)
end

local function leaveShopBucket(src)
    src = tonumber(src)
    if not src then return end
    local session = ActiveShopPlayers[src]
    ActiveShopPlayers[src] = nil
    if not (Config.Dimension and Config.Dimension.enabled) then return end
    local originalBucket = type(session) == 'table' and tonumber(session.originalBucket) or 0
    pcall(function() SetPlayerRoutingBucket(src, originalBucket or 0) end)
end

local function clearTestDriveCharge(src)
    TestDriveCharges[tonumber(src)] = nil
end

local pushBalance

local function createTestDriveCharge(src, debits, amount, model)
    src = tonumber(src)
    amount = math.floor(tonumber(amount) or 0)
    if not src or amount <= 0 then return nil end

    local now = GetGameTimer and GetGameTimer() or (os.time() * 1000)
    local token = strongToken('td', src)
    TestDriveCharges[src] = {
        token = token,
        debits = debits or {},
        amount = amount,
        model = tostring(model or ''),
        expiresAt = now + TEST_DRIVE_CHARGE_TIMEOUT_MS
    }

    SetTimeout(TEST_DRIVE_CHARGE_TIMEOUT_MS, function()
        local charge = TestDriveCharges[src]
        if charge and charge.token == token then
            refundCombinedMoney(src, charge.debits, 'vehicleshop_testdrive_timeout_refund')
            TestDriveCharges[src] = nil
            TestDriveLocks[src] = nil
            if pushBalance then pushBalance(src, 'testdrive_timeout_refunded') end
            TriggerClientEvent('rn-vehicleshop:client:testDriveResult', src, false, 'start_timeout', 'Test drive could not start. Payment refunded.', { model = charge.model, refunded = true })
            notify(src, 'Test drive could not start. Payment refunded.', 'error')
            structuredAdminLog('test_drive', 'start_timeout', src, { model = charge.model, amount = charge.amount, refunded = true }, 'error')
        end
    end)

    return token
end

-- Player balance for the Cash/Bank HUD + Insufficient-Funds gate.
-- cm-playerdata exposes GetAccounts(src) -> { cash = n, bank = n } directly.
local function getPlayerBalance(src)
    local p = pd()
    if not p then return nil end

    local ok, accounts = pcall(function() return p:GetAccounts(src) end)
    if ok and type(accounts) == 'table' then
        return {
            cash = tonumber(accounts.cash) or 0,
            bank = tonumber(accounts.bank) or 0,
        }
    end

    -- Fallback: query each account individually.
    local cash = getMoney(src, 'cash')
    local bank = getMoney(src, 'bank')
    if cash == nil and bank == nil then return nil end
    return { cash = cash or 0, bank = bank or 0 }
end

pushBalance = function(src, reason)
    TriggerClientEvent('rn-vehicleshop:client:balanceUpdate', src, getPlayerBalance(src) or { cash = 0, bank = 0 }, reason or 'update')
end

local function rejectTestDrive(src, code, message, extra)
    message = tostring(message or 'Test drive request rejected.')
    TriggerClientEvent('rn-vehicleshop:client:testDriveResult', src, false, tostring(code or 'rejected'), message, extra or {})
    notify(src, message, 'error')
    structuredAdminLog('test_drive', 'rejected', src, { code = code, message = message, extra = extra }, 'warning')
end

RegisterNetEvent('rn-vehicleshop:server:openUI', function()
    local src = source
    if not closeEnoughToShop(src) then
        TriggerClientEvent('rn-vehicleshop:client:openFailed', src, 'You are too far from the dealership.')
        return notify(src, 'You are too far from the dealership.', 'error')
    end
    enterShopBucket(src, 'store')

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
    local src = source
    local charge = TestDriveCharges[tonumber(src)]
    if charge then
        refundCombinedMoney(src, charge.debits, 'vehicleshop_testdrive_disconnect_refund')
        structuredAdminLog('test_drive', 'disconnect_refund', src, { model = charge.model, amount = charge.amount }, 'warning')
    end
    leaveShopBucket(src)
    resetPlayerRuntime(src)
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
        if not catalog or catalog.availableStore ~= true then
            local msg = catalog and 'Event/task only vehicle.' or 'Vehicle is not available.'
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, msg)
            structuredAdminLog('purchase', 'rejected', src, { model = model, reason = msg }, 'warning')
            finish()
            return
        end

        local price = math.floor(tonumber(catalog.price) or 0)
        local maxPrice = math.floor(tonumber(hardeningCfg().MaxVehiclePrice) or 250000000)
        if price < 0 or price > maxPrice then
            local msg = 'Vehicle price is outside the allowed range.'
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, msg)
            structuredAdminLog('purchase', 'invalid_price', src, { model = model, price = price, maxPrice = maxPrice }, 'error')
            finish()
            return
        end

        local charId = getCharacterId(src)
        if not charId then
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'Character not found. Relog and try again.')
            finish()
            return
        end

        local paid, debits, payErr, available = removeCombinedMoney(src, price, 'vehicleshop_purchase')
        if not paid then
            local msg = payErr == 'not_enough'
                and ('Not enough money. This costs $%s and your combined cash + bank is $%s.')
                    :format(price, math.floor(tonumber(available) or 0))
                or 'Payment failed. Please try again.'
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, msg)
            pushBalance(src, 'purchase_rejected')
            structuredAdminLog('purchase', 'payment_failed', src, { model = model, price = price, available = available, error = payErr }, 'warning')
            finish()
            return
        end
        pushBalance(src, 'purchase_charged')

        local function clampInt(value, minValue, maxValue, fallback)
            value = math.floor(tonumber(value) or fallback)
            if value < minValue then value = minValue end
            if value > maxValue then value = maxValue end
            return value
        end
        local meta = {
            boughtFrom = 'rn-vehicleshop', price = price, category = catalog.category,
            catalogMaxSpeedKph = catalog.speedKph,
            charId = charId, characterId = charId, owner = charId, stored = true,
            payment = { total = price, debits = debits },
            paint = {
                gtaColor = clampInt(details.gtaColor, 0, 160, 111),
                r = clampInt(details.r, 0, 255, 255),
                g = clampInt(details.g, 0, 255, 255),
                b = clampInt(details.b, 0, 255, 255),
                label = tostring(details.color or 'White'):gsub('%c', ''):sub(1, 64)
            }
        }

        leaveShopBucket(src)
        local okExport, createOk, vehicleData = callExport('cm-vehicles', 'CreateOwnedVehicle', src, catalog.model, catalog.label, catalog.trunkLevel, meta)
        if okExport and createOk == true then
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, true,
                ('Purchased %s for $%s. It is stored in your garage.'):format(catalog.label, price), vehicleData)
            structuredAdminLog('purchase', 'completed', src, { model = catalog.model, label = catalog.label, price = price, payment = debits, vehicle = vehicleData }, 'success')
            finish()
            return
        end

        createOwnedVehicleDirectAsync(charId, catalog.model, catalog.label, catalog.trunkLevel, meta, function(dok, dres)
            if not dok then
                refundCombinedMoney(src, debits, 'vehicleshop_purchase_refund')
                pushBalance(src, 'purchase_refunded')
                enterShopBucket(src, 'store')
                local msg = tostring(dres or vehicleData or 'Could not register vehicle. Payment refunded.')
                TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, msg)
                structuredAdminLog('purchase', 'refunded', src, { model = catalog.model, price = price, payment = debits, error = msg }, 'error')
                finish()
                return
            end
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, true,
                ('Purchased %s for $%s. It is stored in your garage.'):format(catalog.label, price), dres)
            structuredAdminLog('purchase', 'completed_fallback', src, { model = catalog.model, label = catalog.label, price = price, payment = debits, vehicle = dres }, 'success')
            finish()
        end)
    end)
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

RegisterNetEvent('rn-vehicleshop:server:testDriveRequest', function(details)
    local src = source
    if not requireShopSession(src, 'test_drive') then return rejectTestDrive(src, 'no_session', 'Open the dealership menu first.') end
    if not requireShopDistance(src, 'test_drive') then return rejectTestDrive(src, 'too_far', 'You are too far from the dealership.') end
    if TestDriveLocks[src] then return rejectTestDrive(src, 'already_pending', 'A test drive is already active or starting.') end
    if not checkRateLimit(src, 'testDriveRequest', tonumber(hardeningCfg().TestDriveRequestCooldownMs) or 1500) then
        return rejectTestDrive(src, 'rate_limited', 'Please wait before requesting another test drive.')
    end

    details = type(details) == 'table' and details or {}
    local model = normalizeModel(details.model)
    TestDriveLocks[src] = { model = model, requestedAt = nowMs(), mode = 'store' }

    getCatalogVehicleAsync(model, true, function(catalog)
        if not catalog then TestDriveLocks[src] = nil return rejectTestDrive(src, 'not_available', 'This vehicle is not available.') end
        if not (Config.TestDrive and Config.TestDrive.enabled) then TestDriveLocks[src] = nil return rejectTestDrive(src, 'disabled', 'Test drive is disabled.') end
        local td = type(catalog.metadata) == 'table' and type(catalog.metadata.testDrive) == 'table' and catalog.metadata.testDrive or {}
        if td.enabled == false then TestDriveLocks[src] = nil return rejectTestDrive(src, 'vehicle_disabled', 'Test drive is disabled for this vehicle.') end

        local cost = math.max(0, math.floor(tonumber(td.cost) or tonumber(Config.TestDrive.testDriveCost) or 0))
        local duration = math.max(10, math.min(600, math.floor(tonumber(td.duration) or tonumber(Config.TestDrive.testDriveTimer) or 60)))
        local paid, debits, payErr, available = removeCombinedMoney(src, cost, 'vehicleshop_testdrive')
        if not paid then
            TestDriveLocks[src] = nil
            pushBalance(src, 'testdrive_rejected')
            return rejectTestDrive(src, payErr == 'not_enough' and 'insufficient_funds' or 'payment_failed',
                payErr == 'not_enough'
                    and ('You need $%s. Combined cash + bank: $%s.'):format(cost, math.floor(tonumber(available) or 0))
                    or 'Test-drive payment failed.',
                { model = model, cost = cost, available = available })
        end

        local chargeToken = createTestDriveCharge(src, debits, cost, model)
        pushBalance(src, 'testdrive_charged')
        enterShopBucket(src, 'test_drive')
        TriggerClientEvent('rn-vehicleshop:client:testDriveResult', src, true, 'approved', 'Test drive approved.', { model = model, cost = cost, duration = duration })
        TriggerClientEvent('rn-vehicleshop:client:startTestDrive', src, details, duration, chargeToken, 'store')
        structuredAdminLog('test_drive', 'approved', src, { model = model, cost = cost, duration = duration, payment = debits }, 'success')
    end)
end)

RegisterNetEvent('rn-vehicleshop:server:adminTestDriveRequest', function(details)
    local src = source
    if not isAdmin(src) then return rejectTestDrive(src, 'no_permission', 'You do not have vehicle admin permission.') end
    if not (Config.AdminTestDrive and Config.AdminTestDrive.enabled ~= false) then return rejectTestDrive(src, 'admin_disabled', 'Admin test drive is disabled.') end
    if TestDriveLocks[src] then return rejectTestDrive(src, 'already_pending', 'A test drive is already active or starting.') end
    if not checkRateLimit(src, 'adminTestDriveRequest', tonumber(hardeningCfg().TestDriveRequestCooldownMs) or 1500) then
        return rejectTestDrive(src, 'rate_limited', 'Please wait before testing another vehicle.')
    end

    details = type(details) == 'table' and details or {}
    local model = normalizeModel(details.model)
    local modelOk, modelErr = isKnownOrAllowedModel(model, true)
    if not modelOk then return rejectTestDrive(src, 'invalid_model', modelErr or 'Invalid vehicle model.') end

    local duration = math.max(10, math.min(600, math.floor(tonumber(details.testDriveTimer) or tonumber(Config.AdminTestDrive.defaultDuration) or 60)))
    TestDriveLocks[src] = { model = model, requestedAt = nowMs(), mode = 'admin' }
    enterShopBucket(src, 'admin_test_drive')
    details.model = model
    details.vehicle = tostring(details.vehicle or details.label or model)
    details.testDriveCost = 0
    TriggerClientEvent('rn-vehicleshop:client:testDriveResult', src, true, 'admin_approved', 'Admin test drive approved.', { model = model, cost = 0, duration = duration, admin = true })
    TriggerClientEvent('rn-vehicleshop:client:startTestDrive', src, details, duration, nil, 'admin')
    structuredAdminLog('test_drive', 'admin_started', src, { model = model, duration = duration }, 'info')
end)

RegisterNetEvent('rn-vehicleshop:server:testDriveStarted', function(token)
    local src = source
    local charge = TestDriveCharges[tonumber(src)]
    if token and charge and charge.token == token then clearTestDriveCharge(src) end
    TestDriveLocks[src] = { startedAt = nowMs(), mode = (TestDriveLocks[src] and TestDriveLocks[src].mode) or 'store' }
    structuredAdminLog('test_drive', 'started', src, { token = token and true or false, mode = TestDriveLocks[src].mode }, 'info')
end)

RegisterNetEvent('rn-vehicleshop:server:testDriveEnded', function(reason, mode)
    local src = source
    TestDriveLocks[src] = nil
    pushBalance(src, 'testdrive_ended')
    structuredAdminLog('test_drive', 'ended', src, { reason = tostring(reason or 'finished'), mode = tostring(mode or 'store') }, 'info')
end)

RegisterNetEvent('rn-vehicleshop:server:testDriveStartFailed', function(token, reason)
    local src = source
    local charge = TestDriveCharges[tonumber(src)]
    if charge and (not token or charge.token == token) then
        clearTestDriveCharge(src)
        refundCombinedMoney(src, charge.debits, 'vehicleshop_testdrive_refund')
        pushBalance(src, 'testdrive_refunded')
    end
    TestDriveLocks[src] = nil
    local refunded = charge ~= nil
    local msg = refunded
        and ('Test drive could not start (%s). Payment refunded.'):format(tostring(reason or 'failed'))
        or ('Test drive could not start (%s).'):format(tostring(reason or 'failed'))
    TriggerClientEvent('rn-vehicleshop:client:testDriveResult', src, false, 'start_failed', msg, { reason = reason, refunded = refunded })
    notify(src, msg, 'error')
    structuredAdminLog('test_drive', 'start_failed', src, { reason = reason, refunded = refunded }, 'error')
end)

RegisterNetEvent('rn-vehicleshop:server:openAdmin', function(requestedMode)
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have vehicle admin permission.', 'error') end
    if not checkRateLimit(src, 'openAdmin', tonumber(hardeningCfg().AdminOpenCooldownMs) or 750) then return end
    local mode = requestedMode == 'capture' and 'capture' or 'manage'
    AdminModes[src] = mode
    enterShopBucket(src, 'admin')
    local sourceList = flattenSourceVehicles(false)
    TriggerClientEvent('rn-vehicleshop:client:openAdmin', src, sourceList, getCatalog(true), adminMeta(), mode)
end)

RegisterNetEvent('rn-vehicleshop:server:rescanVehicles', function()
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    if not checkRateLimit(src, 'rescanVehicles', 3000) then
        return notify(src, 'Please wait before scanning vehicle resources again.', 'error')
    end
    clearVehicleDiscoveryCache()
    local sourceList = flattenSourceVehicles(true)
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true), adminMeta())
    notify(src, ('Detected %d vehicle models from started resources.'):format(#(VehicleDiscoveryCache.list or {})), 'success')
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
    if AdminModes[src] ~= 'manage' then return notify(src, 'Use /managevehicle to configure photographed vehicles.', 'error') end
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
    local maxPrice = math.floor(tonumber(hardeningCfg().MaxVehiclePrice) or 250000000)
    if price < 0 or price > maxPrice then
        return notify(src, ('Price must be between $0 and $%s.'):format(maxPrice), 'error')
    end
    local speedKph = math.floor(tonumber(data.speedKph or data.speed_kph) or 0)
    if speedKph < 0 or speedKph > 1000 then return notify(src, 'Top speed must be between 0 and 1000 km/h.', 'error') end
    if speedKph == 0 then speedKph = nil end
    local trunkLevel = clampTrunkLevel(data.trunkLevel or data.trunk_level)

    local availableStore = truthy(data.availableStore or data.available_store)
    local availableServer = truthy(data.availableServer or data.available_server)
    local availableEms = truthy(data.availableEms or data.available_ems)
    local availablePolice = truthy(data.availablePolice or data.available_police)
    local legalOrg = tostring(data.legalOrg or data.legal_org or ''):lower():gsub('[^a-z0-9_]', '')
    if legalOrg == '' then legalOrg = nil end
    if availableStore then availableServer = true end
    -- EMS, Police, and any cm-law organization are each their own
    -- mutually-exclusive catalog status (hidden/server/store/ems/police/
    -- legal:<org>), matching the single #admin-status-mode select in the
    -- NUI -- never let a vehicle be both a public store item and a fleet
    -- vehicle, and never assigned to more than one fleet at once.
    if availableEms then availableStore = false; availableServer = false; availablePolice = false; legalOrg = nil end
    if availablePolice then availableStore = false; availableServer = false; availableEms = false; legalOrg = nil end
    if legalOrg then availableStore = false; availableServer = false; availableEms = false; availablePolice = false end

    local vehicleMods = sanitizeVehicleMods(data.mods)
    if speedKph then vehicleMods.catalogMaxSpeedKph = speedKph end

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

    -- A car can only be enabled (store, server, ems, police, or a legal org) once it has a captured image.
    if (availableStore or availableServer or availableEms or availablePolice or legalOrg ~= nil) and (not image or image == '') then
        notify(src, 'Capture an image first. A vehicle cannot be enabled without an image.', 'error')
        TriggerClientEvent('rn-vehicleshop:client:adminNeedsImage', src, model, {
            label = label, category = category, price = price, speedKph = speedKph, trunkLevel = trunkLevel,
            availableStore = availableStore, availableServer = availableServer, availableEms = availableEms, availablePolice = availablePolice, legalOrg = legalOrg,
            testDriveEnabled = testDriveEnabled, testDriveTimer = testDriveTimer, testDriveCost = testDriveCost
        })
        return
    end

    MySQL.insert.await([[
        INSERT INTO cm_vehicle_catalog (model, label, category, price, speed_kph, trunk_level, available_store, available_server, available_ems, available_police, legal_org, image, metadata, mods)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label),
            category = VALUES(category),
            price = VALUES(price),
            speed_kph = VALUES(speed_kph),
            trunk_level = VALUES(trunk_level),
            available_store = VALUES(available_store),
            available_server = VALUES(available_server),
            available_ems = VALUES(available_ems),
            available_police = VALUES(available_police),
            legal_org = VALUES(legal_org),
            image = VALUES(image),
            metadata = VALUES(metadata),
            mods = VALUES(mods)
    ]], { model, label, category, price, speedKph, trunkLevel, availableStore and 1 or 0, availableServer and 1 or 0, availableEms and 1 or 0, availablePolice and 1 or 0, legalOrg, image, encode({
        savedBy = GetPlayerName(src),
        savedAt = os.time(),
        testDrive = {
            enabled = testDriveEnabled,
            duration = testDriveTimer,
            cost = testDriveCost
        }
    }), (availableEms or availablePolice or legalOrg ~= nil) and encode(vehicleMods) or nil })

    invalidateCatalogCache()
    notify(src, ('Saved %s.'):format(label), 'success')
    structuredAdminLog('catalog', 'saved', src, { model = model, label = label, category = category, price = price, trunkLevel = trunkLevel, availableStore = availableStore, availableServer = availableServer, availableEms = availableEms, availablePolice = availablePolice, legalOrg = legalOrg, testDrive = { enabled = testDriveEnabled, duration = testDriveTimer, cost = testDriveCost } }, 'success')
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true), adminMeta())
end)

local RuntimeModelBatches = {}
local vehicleClassCategories = {
    [0] = 'Compacts', [1] = 'Sedans', [2] = 'SUVs', [3] = 'Coupes', [4] = 'Muscle',
    [5] = 'Sports Classics', [6] = 'Sports', [7] = 'Super', [8] = 'Motorcycles',
    [9] = 'Off Road', [10] = 'Industrial', [11] = 'Utility', [12] = 'Vans',
    [13] = 'Bicycles', [14] = 'Boats', [15] = 'Helicopters', [16] = 'Planes',
    [17] = 'Service', [18] = 'Emergency', [19] = 'Military', [20] = 'Commercial', [21] = 'Rail'
}

RegisterNetEvent('rn-vehicleshop:server:runtimeVehicleModels')
AddEventHandler('rn-vehicleshop:server:runtimeVehicleModels', function(rows, finalBatch)
    local src = source
    local seed = Config.RuntimeCatalogSeed or {}
    if not isAdmin(src) or seed.enabled ~= true or type(rows) ~= 'table' or #rows > 200 then return end
    local batch = RuntimeModelBatches[src] or { rows = {}, seen = {}, count = 0 }
    RuntimeModelBatches[src] = batch
    for _, raw in ipairs(rows) do
        if type(raw) == 'table' and batch.count < 2000 then
            local model = normalizeModel(raw.model)
            local classId = math.floor(tonumber(raw.classId) or -1)
            if isValidModelName(model) and vehicleClassCategories[classId] and not batch.seen[model] then
                batch.seen[model] = true
                batch.count = batch.count + 1
                batch.rows[#batch.rows + 1] = {
                    model = model, label = safeUtf8Sub(raw.label, 100, model), classId = classId,
                    speedKph = math.max(1, math.min(1000, math.floor(tonumber(raw.speedKph) or 1)))
                }
            end
        end
    end
    if finalBatch ~= true then return end
    RuntimeModelBatches[src] = nil
    local runtimeList, runtimeByModel = {}, {}
    for _, row in ipairs(batch.rows) do
        local price = tonumber(seed.classPrices and seed.classPrices[row.classId])
        local sourceRow = {
            model = row.model,
            label = row.label,
            category = vehicleClassCategories[row.classId],
            price = price or 0,
            speedKph = row.speedKph,
            trunkLevel = math.max(0, math.min(6, math.floor(tonumber(seed.defaultTrunkLevel) or 1))),
            source = 'runtime',
            autoDiscovered = true
        }
        runtimeByModel[row.model] = sourceRow
        runtimeList[#runtimeList + 1] = sourceRow
    end
    RuntimeVehicleCache = { list = runtimeList, byModel = runtimeByModel }
    CatalogCache.sourceList, CatalogCache.sourceByModel = nil, nil
    structuredAdminLog('catalog', 'runtime_discovery', src, { discovered = batch.count }, 'success')
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true), adminMeta({ runtimeModels = batch.count }))
end)

AddEventHandler('playerDropped', function() RuntimeModelBatches[source] = nil end)

RegisterNetEvent('rn-vehicleshop:server:disableAdminVehicle', function(model)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    if AdminModes[src] ~= 'manage' then return notify(src, 'Use /managevehicle to change vehicle availability.', 'error') end
    if not checkRateLimit(src, 'disableAdminVehicle', tonumber(hardeningCfg().AdminDisableCooldownMs) or 1000) then return end
    model = normalizeModel(model)
    if not isValidModelName(model) then return notify(src, 'Invalid model.', 'error') end
    local changed = MySQL.update.await('UPDATE cm_vehicle_catalog SET available_store = 0, available_server = 0, available_ems = 0, available_police = 0 WHERE model = ?', { model })
    if not tonumber(changed) or tonumber(changed) <= 0 then
        MySQL.insert.await('INSERT IGNORE INTO cm_vehicle_catalog (model, label, category, price, trunk_level, available_store, available_server) VALUES (?, ?, ?, 0, 1, 0, 0)', { model, model, 'Custom' })
    end
    invalidateCatalogCache()
    notify(src, ('Disabled %s.'):format(model), 'success')
    structuredAdminLog('catalog', 'disabled', src, { model = model }, 'warning')
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true), adminMeta())
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
    if AdminModes[src] ~= 'capture' then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'wrong_admin_mode')
        return notify(src, 'Use /vehicleadmin to capture vehicle images.', 'error')
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
    structuredAdminLog('image_capture', 'saved', src, { model = model, image = nuiPath, bytes = #bytes, extension = ext }, 'success')
    TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, true, nuiPath, model)
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true), adminMeta())
end)

RegisterCommand('vehicleadmin', function(src)
    if src <= 0 then return end
    if not isAdmin(src) then return notify(src, 'You do not have vehicle admin permission.', 'error') end
    TriggerClientEvent('rn-vehicleshop:client:requestAdmin', src, 'capture')
end, false)

RegisterCommand('managevehicle', function(src)
    if src <= 0 then return end
    if not isAdmin(src) then return notify(src, 'You do not have vehicle admin permission.', 'error') end
    TriggerClientEvent('rn-vehicleshop:client:requestAdmin', src, 'manage')
end, false)

AddEventHandler('rn-vehicleshop:dev:openAdmin', function(src)
    src = tonumber(src)
    if not src or src <= 0 or not isAdmin(src) then return end
    TriggerClientEvent('rn-vehicleshop:client:requestAdmin', src, 'manage')
end)

RegisterNetEvent('rn-vehicleshop:server:adminClosed', function()
    AdminModes[source] = nil
end)

CreateThread(function()
    while GetResourceState('cm-admin') ~= 'started' do Wait(5000) end
    pcall(function()
        exports['cm-admin']:RegisterDevTool({
            id = 'vehicles', label = 'Vehicle Catalog Admin', category = 'Catalogs', icon = 'car',
            permission = 'dev.vehicles',
            actions = {
                { id = 'open', label = 'Open Vehicle Admin', type = 'launcher', realm = 'server',
                  event = 'rn-vehicleshop:dev:openAdmin' }
            }
        })
    end)
end)

exports('GetCatalogVehicle', function(model)
    return getCatalogVehicle(model, true)
end)

exports('GetVehicleImage', function(model)
    local vehicle = getCatalogVehicle(model, false)
    return vehicle and vehicle.image or nil
end)

-- Read-only: every catalog vehicle currently tagged "EMS fleet vehicle" in
-- /vehicleadmin, with its captured image (already a full nui://rn-vehicleshop/...
-- URL, usable directly as an <img src>) and saved appearance. This is the
-- single source of truth cm-ems's Fleet tab reads from -- it never stores its
-- own copy of model/image/mods, only where each one spawns and which EMS
-- rank tier may spawn it.
exports('GetEmsCatalog', function()
    loadCatalogCache(false)
    local out = {}
    for _, row in ipairs(CatalogCache.adminCatalog or {}) do
        if row.availableEms then
            out[#out + 1] = {
                model = row.model,
                label = row.label,
                category = row.category,
                image = row.image,
                mods = row.mods or {},
            }
        end
    end
    return out
end)

-- Read-only: every catalog vehicle currently tagged "Police fleet vehicle" in
-- /vehicleadmin, with its captured image and saved appearance. Same contract
-- as GetEmsCatalog above -- cm-police's Fleet tab reads from this and never
-- stores its own copy of model/image/mods.
exports('GetPoliceCatalog', function()
    loadCatalogCache(false)
    local out = {}
    for _, row in ipairs(CatalogCache.adminCatalog or {}) do
        if row.availablePolice then
            out[#out + 1] = {
                model = row.model,
                label = row.label,
                category = row.category,
                image = row.image,
                mods = row.mods or {},
            }
        end
    end
    return out
end)

-- Read-only, generic equivalent of GetEmsCatalog/GetPoliceCatalog for any
-- cm-law organization: every catalog vehicle tagged with that org's id in
-- /vehicleadmin (legal_org column), same row shape as the two exports
-- above. Unlike EMS/Police, this isn't a fixed column per job -- any
-- number of organizations can share this one mechanism.
exports('GetOrgCatalog', function(organizationId)
    organizationId = tostring(organizationId or ''):lower()
    if organizationId == '' then return {} end
    loadCatalogCache(false)
    local out = {}
    for _, row in ipairs(CatalogCache.adminCatalog or {}) do
        if row.legalOrg == organizationId then
            out[#out + 1] = {
                model = row.model,
                label = row.label,
                category = row.category,
                image = row.image,
                mods = row.mods or {},
            }
        end
    end
    return out
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

    for src, charge in pairs(TestDriveCharges) do
        if charge and charge.debits then
            refundCombinedMoney(src, charge.debits, 'vehicleshop_testdrive_resource_stop_refund')
        end
    end

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
    TestDriveLocks = {}
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
    if Config.Security.MaxVehiclePrice == nil then Config.Security.MaxVehiclePrice = 250000000 end
    if Config.Security.TestDriveRequestCooldownMs == nil then Config.Security.TestDriveRequestCooldownMs = 1500 end

    if not Config.Location then
        print('[rn-vehicleshop] WARNING: Config.Location is missing. Store distance checks will fail.')
    end
    if not Config.TestVehicleSpawnLocation or not Config.TestVehicleSpawnLocation.coords then
        print('[rn-vehicleshop] WARNING: Config.TestVehicleSpawnLocation.coords is missing. Test drives will be disabled by client error.')
    end
    local configuredModels = 0
    for _, category in ipairs(Config.Vehicles or {}) do
        configuredModels = configuredModels + #(category.buttons or {})
    end
    print(('[rn-vehicleshop] Started v%s | configured models=%s | automatic vehicle discovery=%s | max image bytes=%s')
        :format(GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown', configuredModels,
            tostring(discoveryCfg().enabled ~= false), tostring(Config.Security.MaxImageBase64Bytes)))
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


-- Invalidate only the lightweight discovery/source cache when vehicle packs are
-- started or stopped. The next admin open/refresh rebuilds it safely.
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then clearVehicleDiscoveryCache() end
end)
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then clearVehicleDiscoveryCache() end
end)


CreateThread(function()
    Wait(8000)
    if discoveryCfg().enabled ~= false then
        clearVehicleDiscoveryCache()
        getSourceVehicles(true)
    end
end)
