local PurchaseLocks = {}
local TestDriveCharges = {}
local TestDriveLocks = {}
local ActiveShopPlayers = {}
local CharacterCache = {}
local RateLimits = {}
local AdminModes = {}
local PendingOrganizationGrants = {}
local ConsumedOrganizationGrants = {}
local CatalogCache = { sourceList = nil, sourceByModel = nil, adminCatalog = nil, publicCatalog = nil, shopVehicles = nil, vehicleByModel = nil, loadedAt = 0 }
local RuntimeVehicleCache = { list = {}, byModel = {} }

local PURCHASE_LOCK_TIMEOUT_MS = 45000
local TEST_DRIVE_CHARGE_TIMEOUT_MS = 30000
local CHARACTER_CACHE_TTL_MS = 30000
local CATALOG_CACHE_TTL_MS = 15000
local OwnedVehicleHasStoredColumn = false
local ReplacementPollStarted = false
local PendingReplacementResolveLocks = {}
local AutomaticFallbackLocks = {}
local ImageCaptureSequence = 0

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

local function adminRequestId(value)
    value = tostring(value or ''):gsub('[^%w_:%-]', '')
    return value:sub(1, 80)
end

local function sendAdminActionResult(src, action, requestId, success, message, extra)
    local result = {
        action = tostring(action or 'admin'),
        requestId = adminRequestId(requestId),
        success = success == true,
        message = tostring(message or '')
    }
    if type(extra) == 'table' then
        for key, value in pairs(extra) do result[key] = value end
    end
    TriggerClientEvent('rn-vehicleshop:client:adminActionResult', src, result)
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
    local args = table.pack(...)
    local ok, result, extra = pcall(function()
        -- FiveM Lua exports use method/colon calling semantics. Passing the
        -- proxy explicitly is the dynamic equivalent of
        -- exports['resource']:ExportName(...). The previous dot-style call
        -- caused the first real argument (the player source) to be consumed as
        -- the receiver, shifting every CreateOwnedVehicle argument left.
        local resourceExports = exports[resource]
        local exportMethod = resourceExports and resourceExports[method]
        if not exportMethod then
            error(('Missing export: %s.%s'):format(resource, method))
        end
        return exportMethod(resourceExports, table.unpack(args, 1, args.n))
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
    local resolved = nil

    -- cm-playerdata owns the authoritative loaded-character cache. Prefer its
    -- export before compatibility state/core fallbacks so purchases cannot be
    -- rejected merely because a legacy resource has not mirrored the state bag
    -- yet.
    if GetResourceState('cm-playerdata') == 'started' then
        local ok, value = pcall(function()
            return exports['cm-playerdata']:GetCharacterId(src)
        end)
        if ok and value then
            resolved = tostring(value)
        end
    end

    -- Only use the short compatibility cache when the authoritative owner is
    -- unavailable. This prevents a character switch on the same server source
    -- from purchasing for the previous character for up to the cache TTL.
    if not resolved and cached and (tonumber(cached.expiresAt) or 0) > now then
        return cached.value
    end

    local ok, value = callExport('cm-vehicles', 'GetCharacterId', src)
    if not resolved and ok and value then
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
    if IsPlayerAceAllowed(src, perm) then return true end
    -- CM Admin is the authoritative permission service when it is running.
    -- Keep this fail-closed and require the dedicated vehicle developer/admin
    -- permission rather than accepting a generic player/admin flag.
    if GetResourceState('cm-admin') == 'started' then
        for _, cmPermission in ipairs({ 'dev.vehicles', 'vehicles.manage' }) do
            local ok, allowed = pcall(function()
                return exports['cm-admin']:HasPermission(src, cmPermission)
            end)
            if ok and allowed == true then return true end
        end
    end
    return false
end

local function ensureColumn(tableName, columnName, definition)
    -- Every identifier passed here is a hard-coded resource schema name. Keep
    -- this helper separate from user input so migrations remain safe on older
    -- MariaDB/MySQL versions that do not support ADD COLUMN IF NOT EXISTS.
    local ok, cols = pcall(function()
        return MySQL.query.await(('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName), { columnName })
    end)
    if ok and (not cols or not cols[1]) then
        pcall(function()
            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tableName, definition))
        end)
    end
    local verifyOk, verify = pcall(function()
        return MySQL.query.await(('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName), { columnName })
    end)
    return verifyOk and verify and verify[1] ~= nil
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
            legal_org VARCHAR(32) NULL,
            gang_id VARCHAR(16) NULL,
            image VARCHAR(255) NULL,
            metadata LONGTEXT NULL,
            mods LONGTEXT NULL,
            retired TINYINT(1) NOT NULL DEFAULT 0,
            replacement_model VARCHAR(64) NULL,
            has_carplay TINYINT(1) NOT NULL DEFAULT 0,
            vehicle_type VARCHAR(8) NOT NULL DEFAULT 'land',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_category (category),
            INDEX idx_available_store (available_store),
            INDEX idx_available_server (available_server),
            INDEX idx_available_ems (available_ems),
            INDEX idx_available_police (available_police),
            INDEX idx_has_carplay (has_carplay),
            INDEX idx_vehicle_type (vehicle_type)
        )
    ]])

    ensureColumn('cm_vehicle_catalog', 'image', 'image VARCHAR(255) NULL')
    ensureColumn('cm_vehicle_catalog', 'available_ems', 'available_ems TINYINT(1) NOT NULL DEFAULT 0')
    ensureColumn('cm_vehicle_catalog', 'available_police', 'available_police TINYINT(1) NOT NULL DEFAULT 0')
    ensureColumn('cm_vehicle_catalog', 'speed_kph', 'speed_kph INT NULL AFTER price')
    ensureColumn('cm_vehicle_catalog', 'mods', 'mods LONGTEXT NULL')
    ensureColumn('cm_vehicle_catalog', 'legal_org', 'legal_org VARCHAR(32) NULL')
    ensureColumn('cm_vehicle_catalog', 'gang_id', 'gang_id VARCHAR(16) NULL')
    ensureColumn('cm_vehicle_catalog', 'retired', 'retired TINYINT(1) NOT NULL DEFAULT 0')
    ensureColumn('cm_vehicle_catalog', 'replacement_model', 'replacement_model VARCHAR(64) NULL')
    ensureColumn('cm_vehicle_catalog', 'has_carplay', 'has_carplay TINYINT(1) NOT NULL DEFAULT 0')
    pcall(function() MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD INDEX idx_has_carplay (has_carplay)') end)
    ensureColumn('cm_vehicle_catalog', 'vehicle_type', "vehicle_type VARCHAR(8) NOT NULL DEFAULT 'land'")
    pcall(function() MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD INDEX idx_vehicle_type (vehicle_type)') end)

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_vehicle_replacements (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            old_model VARCHAR(64) NOT NULL UNIQUE,
            new_model VARCHAR(64) NOT NULL,
            old_catalog LONGTEXT NULL,
            old_image VARCHAR(255) NULL,
            new_image VARCHAR(255) NULL,
            status VARCHAR(16) NOT NULL DEFAULT 'applied',
            created_by VARCHAR(128) NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            applied_at TIMESTAMP NULL,
            INDEX idx_replacement_new_model (new_model),
            INDEX idx_replacement_status (status)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_vehicle_replacement_pending (
            vehicle_id BIGINT PRIMARY KEY,
            replacement_id BIGINT NOT NULL,
            old_model VARCHAR(64) NOT NULL,
            new_model VARCHAR(64) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_pending_replacement (replacement_id),
            INDEX idx_pending_old_model (old_model)
        )
    ]])

    local storedOk, storedCols = pcall(function()
        return MySQL.query.await([[SHOW COLUMNS FROM cm_owned_vehicles LIKE 'is_stored']])
    end)
    OwnedVehicleHasStoredColumn = storedOk and storedCols and storedCols[1] ~= nil

    -- Migration for servers that created the table before image support existed.
    -- Do not use `ADD COLUMN IF NOT EXISTS` here; older MariaDB/MySQL versions do not
    -- support it and silently broke image capture on some servers. SHOW COLUMNS works
    -- on old MariaDB/MySQL and lets us add the column only when missing.
    -- The idempotent migrations above cover older installations too.

    -- Same migration pattern for the EMS fleet destination: a mutually-exclusive
    -- 4th catalog status (hidden/server/store/ems) plus a saved appearance
    -- (paint/livery/wheels/etc, same shape cm-ems's fleet vehicles use).
    pcall(function() MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD INDEX idx_available_ems (available_ems)') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD INDEX idx_available_police (available_police)') end)

    -- Same migration pattern again for the Police fleet destination: a 5th
    -- mutually-exclusive catalog status alongside hidden/server/store/ems.

    -- Generic legal-org fleet destination: unlike available_ems/available_police
    -- (one hardcoded column each), this is a single nullable column holding
    -- whichever org id (e.g. 'sahp', 'fib') the vehicle is tagged for, so any
    -- number of cm-law organizations can use the same mutually-exclusive
    -- catalog-status pattern without a new column per org.
    pcall(function() MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD INDEX idx_legal_org (legal_org)') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD INDEX idx_gang_id (gang_id)') end)

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

-- Catalog vehicle type ('land'/'boat'/'air'). Auto-detected from the vehicle's
-- GTA class on the client (14 = boat, 15/16 = aircraft) and stored at save time.
local function normalizeVehicleType(value)
    value = tostring(value or ''):lower()
    if value == 'boat' then return 'boat' end
    if value == 'air' then return 'air' end
    return 'land'
end

-- Which storefront a request targets ('store' = cars, 'boat', 'air').
local function normalizeShopType(value)
    value = tostring(value or ''):lower()
    if value == 'boat' then return 'boat' end
    if value == 'air' then return 'air' end
    return 'store'
end

-- Storefront session names are ('store'/'boat'/'air'), while catalog rows use
-- ('land'/'boat'/'air'). Keep those contracts separate at the comparison edge.
local function catalogTypeForShop(shopType)
    shopType = normalizeShopType(shopType)
    return shopType == 'store' and 'land' or shopType
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

local function gangOptions()
    return {
        {id='marabunta',label='Marabunta'}, {id='bloods',label='Bloods'},
        {id='ballas',label='Ballas'}, {id='families',label='Families'}, {id='vagos',label='Vagos'}
    }
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
        gangs = gangOptions(),
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
        gangId = (row.gang_id and tostring(row.gang_id) ~= '') and tostring(row.gang_id) or nil,
        retired = truthy(row.retired),
        replacementModel = (row.replacement_model and tostring(row.replacement_model) ~= '') and tostring(row.replacement_model) or nil,
        hasCarplay = truthy(row.has_carplay),
        vehicleType = normalizeVehicleType(row.vehicle_type),
        image = (row.image and tostring(row.image) ~= '' ) and tostring(row.image) or nil,
        metadata = decode(row.metadata),
        mods = decode(row.mods)
    }
end

-- FiveM hash natives can surface the same 32-bit model hash as either a
-- signed or unsigned Lua number depending on the native/runtime boundary.
-- Canonicalise both forms before using model hashes as table keys so the
-- catalog flag also matches server-side GetEntityModel() results.
local function normalizeModelHash(modelHash)
    modelHash = tonumber(modelHash)
    if not modelHash then return nil end
    return math.floor(modelHash) % 4294967296
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
               legal_org, gang_id, image, metadata, mods, retired, replacement_model, has_carplay, vehicle_type
        FROM cm_vehicle_catalog
        WHERE (image IS NOT NULL AND TRIM(image) <> '')
           OR available_store = 1
           OR available_server = 1
           OR available_ems = 1
           OR available_police = 1
           OR legal_org IS NOT NULL
           OR gang_id IS NOT NULL
           OR has_carplay = 1
        ORDER BY category ASC, label ASC
    ]]) or {}
    local admin, public, byModel, carplayHashes = {}, {}, {}, {}
    for _, row in ipairs(rows) do
        local parsed = parseCatalogRow(row)
        if parsed then
            admin[#admin + 1] = parsed
            byModel[parsed.model] = parsed
            if not parsed.retired and (parsed.availableStore or parsed.availableServer) then
                public[#public + 1] = parsed
            end
            -- Keyed by model hash (not just the string) so CarPlay can check
            -- ANY vehicle of a flagged model -- test drives, showroom
            -- previews, admin/trainer spawns -- not only ones with a
            -- cm_owned_vehicles row (i.e. not only purchased vehicles).
            if parsed.hasCarplay then
                carplayHashes[normalizeModelHash(GetHashKey(parsed.model))] = true
            end
        end
    end
    CatalogCache.adminCatalog = admin
    CatalogCache.publicCatalog = public
    CatalogCache.vehicleByModel = byModel
    CatalogCache.carplayModelHashes = carplayHashes
    CatalogCache.shopVehicles = nil
    CatalogCache.loadedAt = now
end

local function getCatalog(includeHidden)
    loadCatalogCache(false)
    local rows = includeHidden and (CatalogCache.adminCatalog or {}) or (CatalogCache.publicCatalog or {})
    if includeHidden then
        local counts = {}
        for _, row in ipairs(MySQL.query.await('SELECT model, metadata FROM cm_owned_vehicles') or {}) do
            local metadata = decode(row.metadata)
            local replacementType = tostring(metadata.replacementType or '')
            local originalModel = normalizeModel(metadata.replacementOriginalModel)
            local countModel = ((replacementType == 'temporary' or replacementType == 'restoring' or replacementType == 'permanent')
                and isValidModelName(originalModel)) and originalModel or normalizeModel(row.model)
            if isValidModelName(countModel) then counts[countModel] = (counts[countModel] or 0) + 1 end
        end
        for _, row in ipairs(rows) do row.ownerCount = counts[normalizeModel(row.model)] or 0 end
    end
    return rows
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
    if requireVisible and row and (row.retired or not (row.availableStore or row.availableServer)) then return nil end
    return row
end

local function getCatalogVehicleAsync(model, requireVisible, cb)
    model = normalizeModel(model)
    if not isValidModelName(model) then return cb(nil) end
    local cached = getCatalogVehicle(model, requireVisible)
    if cached then return cb(cached) end
    MySQL.single('SELECT * FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { model }, function(row)
        local parsed = parseCatalogRow(row)
        if requireVisible and parsed and (parsed.retired or not (parsed.availableStore or parsed.availableServer)) then parsed = nil end
        cb(parsed)
    end)
end

local function buildShopVehicles(shopType)
    shopType = normalizeShopType(shopType)
    local catalogType = catalogTypeForShop(shopType)
    loadCatalogCache(false)
    if CatalogCache.shopVehicles and CatalogCache.shopVehiclesType == shopType then
        return CatalogCache.shopVehicles
    end

    local groups = {}
    for _, vehicle in ipairs(CatalogCache.publicCatalog or {}) do
        if vehicle.vehicleType ~= catalogType then goto continue end
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
            testDriveTimer = (Config.TestDrive and tonumber(Config.TestDrive.testDriveTimer)) or 300,
            testDriveCost = tonumber(td.cost) or (Config.TestDrive and tonumber(Config.TestDrive.testDriveCost)) or 0
        }
        ::continue::
    end

    local list = {}
    for _, group in pairs(groups) do
        table.sort(group.buttons, function(a, b) return a.name < b.name end)
        list[#list + 1] = group
    end
    table.sort(list, function(a, b) return a.title < b.title end)
    CatalogCache.shopVehicles = list
    CatalogCache.shopVehiclesType = shopType
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

local function buildShopVehiclesForPlayer(src, shopType)
    local base = buildShopVehicles(shopType)
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

local function shopDealerLocation(shopType)
    shopType = normalizeShopType(shopType)
    local dealer = nil
    if shopType == 'boat' then dealer = Config.BoatDealer
    elseif shopType == 'air' then dealer = Config.AirDealer
    else dealer = Config.Dealer end
    local loc = dealer and dealer.coords
    if loc and loc.x then return loc end
    return Config.Location
end

local function closeEnoughToShop(src, shopType)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local loc = shopDealerLocation(shopType)
    if not loc then return false end
    local maxDist = tonumber(hardeningCfg().ShopDistance) or 35.0
    local ok, dist = pcall(function()
        return #(GetEntityCoords(ped) - vector3(loc.x, loc.y, loc.z))
    end)
    return ok and dist and dist <= maxDist
end

local function requireShopDistance(src, action)
    local session = ActiveShopPlayers[src]
    local shopType = type(session) == 'table' and session.mode or nil
    if closeEnoughToShop(src, shopType) then return true end
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

-- cm-house owns garage assignments and cm-vehicles owns the persistent row.
-- Use the house API rather than writing cm_house_vehicle_slots directly. Only
-- houses owned by the purchasing character are eligible; family-access houses
-- are intentionally excluded from automatic personal assignment.
local function assignVehicleToFirstOwnedHouseGarage(vehicleData, charId)
    local vehicleId = type(vehicleData) == 'table' and tonumber(vehicleData.id) or nil
    charId = tonumber(charId) or charId
    if not vehicleId or not charId then return false, 'invalid_assignment_context' end
    if GetResourceState('cm-house') ~= 'started' then return false, 'house_unavailable' end

    local housesOk, houses = pcall(function()
        return exports['cm-house']:GetHousesForCharacter(charId)
    end)
    if not housesOk or type(houses) ~= 'table' then return false, 'house_lookup_failed' end

    for _, house in ipairs(houses) do
        local houseId = tonumber(house and house.id)
        local ownerCid = tonumber(house and house.owner_cid)
        if houseId and ownerCid and ownerCid == tonumber(charId) then
            local stateOk, garage = pcall(function()
                return exports['cm-house']:GetGarageState(houseId)
            end)
            local slots = stateOk and type(garage) == 'table' and garage.slots or nil
            if type(slots) == 'table' then
                for _, slot in ipairs(slots) do
                    local slotIndex = tonumber(slot and slot.index)
                    if slotIndex and slot.empty == true then
                        local moveOk, assigned, result = pcall(function()
                            return exports['cm-house']:MoveVehicleAssignment(
                                vehicleId, houseId, slotIndex, charId, 'personal'
                            )
                        end)
                        if moveOk and assigned == true then
                            return true, {
                                houseId = houseId,
                                slotIndex = slotIndex,
                                houseLabel = house.label or house.house_number,
                                result = result,
                            }
                        end
                    end
                end
            end
        end
    end

    return false, 'no_available_owned_house_slot'
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

local function restoreTestDriveShopMode(src, lock)
    src = tonumber(src)
    if not src or type(lock) ~= 'table' then return end
    local session = ActiveShopPlayers[src]
    if type(session) == 'table' and lock.previousMode then
        session.mode = lock.previousMode
    end
end

local function clearTestDriveLock(src, expectedToken)
    src = tonumber(src)
    if not src then return nil end
    local lock = TestDriveLocks[src]
    if not lock then return nil end
    if expectedToken ~= nil and lock.token ~= expectedToken then return nil end
    TestDriveLocks[src] = nil
    restoreTestDriveShopMode(src, lock)
    return lock
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
            clearTestDriveLock(src, token)
            if pushBalance then pushBalance(src, 'testdrive_timeout_refunded') end
            TriggerClientEvent('rn-vehicleshop:client:testDriveResult', src, false, 'start_timeout', 'Test drive could not start. Payment refunded.', { model = charge.model, refunded = true })
            notify(src, 'Test drive could not start. Payment refunded.', 'error')
            structuredAdminLog('test_drive', 'start_timeout', src, { model = charge.model, amount = charge.amount, refunded = true }, 'error')
        end
    end)

    return token
end

local function scheduleTestDriveApprovalTimeout(src, token)
    src = tonumber(src)
    if not src or type(token) ~= 'string' or token == '' then return end
    SetTimeout(TEST_DRIVE_CHARGE_TIMEOUT_MS, function()
        local lock = TestDriveLocks[src]
        if type(lock) ~= 'table' or lock.token ~= token or lock.phase ~= 'approved' then return end
        clearTestDriveLock(src, token)
        TriggerClientEvent('rn-vehicleshop:client:testDriveResult', src, false, 'start_timeout', 'Test drive could not start.', { refunded = false })
        notify(src, 'Test drive could not start.', 'error')
        structuredAdminLog('test_drive', 'start_timeout', src, { model = lock.model, refunded = false }, 'warning')
    end)
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

RegisterNetEvent('rn-vehicleshop:server:openUI', function(shopType)
    local src = source
    shopType = normalizeShopType(shopType)
    if not closeEnoughToShop(src, shopType) then
        TriggerClientEvent('rn-vehicleshop:client:openFailed', src, 'You are too far from the dealership.')
        return notify(src, 'You are too far from the dealership.', 'error')
    end
    enterShopBucket(src, shopType)

    -- Character name lookup is async + cached. This avoids blocking the server
    -- thread with MySQL.single.await every time the shop UI opens.
    local vehicles = buildShopVehiclesForPlayer(src, shopType)
    local daily = { balance = getPlayerBalance(src) }
    getCharacterNameAsync(src, function(buyerName)
        if not ActiveShopPlayers[src] then return end
        TriggerClientEvent('vehicles:client:openUI', src, vehicles, daily, buyerName, shopType)
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
        local session = ActiveShopPlayers[src]
        local shopType = normalizeShopType(session and session.mode)
        if not session then
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'The dealership session expired. Please reopen the showroom.')
            finish()
            return
        end
        if not catalog or catalog.availableStore ~= true then
            local msg = catalog and 'Event/task only vehicle.' or 'Vehicle is not available.'
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, msg)
            structuredAdminLog('purchase', 'rejected', src, { model = model, reason = msg }, 'warning')
            finish()
            return
        end

        if normalizeVehicleType(catalog.vehicleType) ~= catalogTypeForShop(shopType) then
            local msg = 'This vehicle belongs to a different dealership.'
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, msg)
            structuredAdminLog('purchase', 'wrong_storefront', src, {
                model = model, requestedShop = shopType, catalogType = catalog.vehicleType
            }, 'warning')
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

        -- Resolve and validate the permanent database identity before taking
        -- money. Server source/state aliases are never valid ownership keys.
        local identityOk, storedCharId = pcall(function()
            return MySQL.scalar.await('SELECT id FROM characters WHERE id = ? LIMIT 1', { tostring(charId) })
        end)
        if not identityOk or not storedCharId then
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false,
                'Your character session is not ready. Relog and try again.')
            structuredAdminLog('purchase', 'character_validation_failed', src, {
                model = model,
                reason = identityOk and 'character_row_missing' or 'character_lookup_failed'
            }, 'error')
            finish()
            return
        end
        charId = tostring(storedCharId)

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

        -- Purchases keep only the paint colour chosen in the showroom preview.
        -- Catalog speed and any other client-provided upgrade values must
        -- never become persistent appearance/performance state.
        local chosenColor = details.r ~= nil and details.g ~= nil and details.b ~= nil
            and sanitizeRgbMod({ r = details.r, g = details.g, b = details.b }) or nil
        local meta = {
            boughtFrom = 'rn-vehicleshop', source = 'rn-vehicleshop', price = price, category = catalog.category,
            charId = charId, characterId = charId, owner = charId,
            payment = { total = price, debits = debits },
        }
        if chosenColor then
            meta.mods = { customPrimary = chosenColor, customSecondary = chosenColor }
        end

        leaveShopBucket(src)
        local okExport, createOk, vehicleData = callExport('cm-vehicles', 'CreateOwnedVehicle', src, catalog.model, catalog.label, catalog.trunkLevel, meta)
        if okExport and createOk == true then
            local assigned, assignment = assignVehicleToFirstOwnedHouseGarage(vehicleData, charId)
            if type(vehicleData) == 'table' then
                vehicleData.garageAssignment = assigned and assignment or nil
            end
            local purchaseMessage = assigned
                and ('Purchased %s for $%s. It is parked in your house garage.'):format(catalog.label, price)
                or ('Purchased %s for $%s. It is registered but has no available house garage slot yet.'):format(catalog.label, price)
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, true,
                purchaseMessage, vehicleData)
            structuredAdminLog('purchase', 'completed', src, {
                model = catalog.model, label = catalog.label, price = price, payment = debits,
                vehicle = vehicleData, garageAssigned = assigned, garageAssignment = assignment
            }, 'success')
            finish()
            return
        end

        refundCombinedMoney(src, debits, 'vehicleshop_purchase_refund')
        pushBalance(src, 'purchase_refunded')
        enterShopBucket(src, shopType)
        local msg = tostring(vehicleData or createOk or 'Could not register vehicle. Payment refunded.')
        TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, msg)
        structuredAdminLog('purchase', 'refunded', src, {
            model = catalog.model, price = price, payment = debits, error = msg
        }, 'error')
        finish()
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
    local session = ActiveShopPlayers[src]
    local shopType = normalizeShopType(session and session.mode)
    TestDriveLocks[src] = {
        model = model, requestedAt = nowMs(), mode = shopType,
        previousMode = shopType, phase = 'requested'
    }

    getCatalogVehicleAsync(model, true, function(catalog)
        if not catalog then clearTestDriveLock(src) return rejectTestDrive(src, 'not_available', 'This vehicle is not available.') end
        if normalizeVehicleType(catalog.vehicleType) ~= catalogTypeForShop(shopType) then
            clearTestDriveLock(src)
            return rejectTestDrive(src, 'wrong_storefront', 'This vehicle belongs to a different dealership.')
        end
        if not (Config.TestDrive and Config.TestDrive.enabled) then clearTestDriveLock(src) return rejectTestDrive(src, 'disabled', 'Test drive is disabled.') end
        local td = type(catalog.metadata) == 'table' and type(catalog.metadata.testDrive) == 'table' and catalog.metadata.testDrive or {}
        if td.enabled == false then clearTestDriveLock(src) return rejectTestDrive(src, 'vehicle_disabled', 'Test drive is disabled for this vehicle.') end

        local cost = math.max(0, math.floor(tonumber(td.cost) or tonumber(Config.TestDrive.testDriveCost) or 0))
        local duration = math.max(10, math.min(600, math.floor(tonumber(Config.TestDrive and Config.TestDrive.testDriveTimer) or 300)))
        local paid, debits, payErr, available = removeCombinedMoney(src, cost, 'vehicleshop_testdrive')
        if not paid then
            clearTestDriveLock(src)
            pushBalance(src, 'testdrive_rejected')
            return rejectTestDrive(src, payErr == 'not_enough' and 'insufficient_funds' or 'payment_failed',
                payErr == 'not_enough'
                    and ('You need $%s. Combined cash + bank: $%s.'):format(cost, math.floor(tonumber(available) or 0))
                    or 'Test-drive payment failed.',
                { model = model, cost = cost, available = available })
        end

        local chargeToken = createTestDriveCharge(src, debits, cost, model) or strongToken('td', src)
        local lock = TestDriveLocks[src]
        if not lock then
            refundCombinedMoney(src, debits, 'vehicleshop_testdrive_lost_session_refund')
            pushBalance(src, 'testdrive_refunded')
            return rejectTestDrive(src, 'session_expired', 'The dealership session expired. Please try again.')
        end
        lock.token = chargeToken
        lock.phase = 'approved'
        if cost <= 0 then scheduleTestDriveApprovalTimeout(src, chargeToken) end
        details.model = model
        details.vehicleType = normalizeVehicleType(catalog.vehicleType)
        details.vehicle = catalog.label
        pushBalance(src, 'testdrive_charged')
        enterShopBucket(src, 'test_drive')
        TriggerClientEvent('rn-vehicleshop:client:testDriveResult', src, true, 'approved', 'Test drive approved.', { model = model, cost = cost, duration = duration })
        TriggerClientEvent('rn-vehicleshop:client:startTestDrive', src, details, duration, chargeToken, shopType)
        structuredAdminLog('test_drive', 'approved', src, { model = model, cost = cost, duration = duration, payment = debits }, 'success')
    end)
end)

RegisterNetEvent('rn-vehicleshop:server:adminTestDriveRequest', function(details)
    local src = source
    if not isAdmin(src) then return rejectTestDrive(src, 'no_permission', 'You do not have vehicle admin permission.') end
    local session = ActiveShopPlayers[src]
    if AdminModes[src] ~= 'manage' or type(session) ~= 'table' or session.mode ~= 'admin' then
        return rejectTestDrive(src, 'admin_session_required', 'Open Manage Vehicles before starting an admin test drive.')
    end
    if not (Config.AdminTestDrive and Config.AdminTestDrive.enabled ~= false) then return rejectTestDrive(src, 'admin_disabled', 'Admin test drive is disabled.') end
    if TestDriveLocks[src] then return rejectTestDrive(src, 'already_pending', 'A test drive is already active or starting.') end
    if not checkRateLimit(src, 'adminTestDriveRequest', tonumber(hardeningCfg().TestDriveRequestCooldownMs) or 1500) then
        return rejectTestDrive(src, 'rate_limited', 'Please wait before testing another vehicle.')
    end

    details = type(details) == 'table' and details or {}
    local model = normalizeModel(details.model)
    local modelOk, modelErr = isKnownOrAllowedModel(model, true)
    if not modelOk then return rejectTestDrive(src, 'invalid_model', modelErr or 'Invalid vehicle model.') end

    local duration = math.max(10, math.min(600, math.floor(tonumber(Config.TestDrive and Config.TestDrive.testDriveTimer) or 300)))
    local chargeToken = strongToken('td-admin', src)
    TestDriveLocks[src] = {
        model = model, requestedAt = nowMs(), mode = 'admin',
        previousMode = 'admin', token = chargeToken, phase = 'approved'
    }
    scheduleTestDriveApprovalTimeout(src, chargeToken)
    enterShopBucket(src, 'admin_test_drive')
    details.model = model
    details.vehicle = tostring(details.vehicle or details.label or model)
    details.testDriveCost = 0
    TriggerClientEvent('rn-vehicleshop:client:testDriveResult', src, true, 'admin_approved', 'Admin test drive approved.', { model = model, cost = 0, duration = duration, admin = true })
    TriggerClientEvent('rn-vehicleshop:client:startTestDrive', src, details, duration, chargeToken, 'admin')
    structuredAdminLog('test_drive', 'admin_started', src, { model = model, duration = duration }, 'info')
end)

RegisterNetEvent('rn-vehicleshop:server:testDriveStarted', function(token)
    local src = source
    local lock = TestDriveLocks[src]
    if type(lock) ~= 'table' or lock.phase ~= 'approved' or type(token) ~= 'string' or token == '' or token ~= lock.token then
        structuredAdminLog('test_drive', 'start_rejected', src, { reason = 'invalid_token' }, 'warning')
        return
    end
    local charge = TestDriveCharges[tonumber(src)]
    if charge and charge.token ~= token then
        structuredAdminLog('test_drive', 'start_rejected', src, { reason = 'charge_token_mismatch' }, 'warning')
        return
    end
    if charge then clearTestDriveCharge(src) end
    lock.phase = 'active'
    lock.startedAt = nowMs()
    structuredAdminLog('test_drive', 'started', src, { token = true, mode = lock.mode }, 'info')
end)

RegisterNetEvent('rn-vehicleshop:server:testDriveEnded', function(reason, mode, token)
    local src = source
    local lock = TestDriveLocks[src]
    if type(lock) ~= 'table' or lock.phase ~= 'active' or type(token) ~= 'string' or token ~= lock.token then
        structuredAdminLog('test_drive', 'end_rejected', src, { reason = 'invalid_token' }, 'warning')
        return
    end
    clearTestDriveLock(src, token)
    pushBalance(src, 'testdrive_ended')
    structuredAdminLog('test_drive', 'ended', src, { reason = tostring(reason or 'finished'), mode = lock.mode }, 'info')
end)

RegisterNetEvent('rn-vehicleshop:server:testDriveStartFailed', function(token, reason)
    local src = source
    local lock = TestDriveLocks[src]
    if type(lock) ~= 'table' or lock.phase ~= 'approved' or type(token) ~= 'string' or token ~= lock.token then
        structuredAdminLog('test_drive', 'start_failed_rejected', src, { reason = 'invalid_token' }, 'warning')
        return
    end
    local charge = TestDriveCharges[tonumber(src)]
    if charge and charge.token == token then
        clearTestDriveCharge(src)
        refundCombinedMoney(src, charge.debits, 'vehicleshop_testdrive_refund')
        pushBalance(src, 'testdrive_refunded')
    end
    clearTestDriveLock(src, token)
    local refunded = charge ~= nil
    local msg = refunded
        and ('Test drive could not start (%s). Payment refunded.'):format(tostring(reason or 'failed'))
        or ('Test drive could not start (%s).'):format(tostring(reason or 'failed'))
    TriggerClientEvent('rn-vehicleshop:client:testDriveResult', src, false, 'start_failed', msg, { reason = reason, refunded = refunded })
    notify(src, msg, 'error')
    structuredAdminLog('test_drive', 'start_failed', src, { reason = reason, refunded = refunded }, 'error')
end)

RegisterNetEvent('rn-vehicleshop:server:openAdmin', function(requestedMode, requestedFleetModel)
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have vehicle admin permission.', 'error') end
    if not checkRateLimit(src, 'openAdmin', tonumber(hardeningCfg().AdminOpenCooldownMs) or 750) then return end
    local mode = requestedMode == 'capture' and 'capture' or 'manage'
    local fleetModel = normalizeModel(requestedFleetModel)
    if mode ~= 'manage' or not isKnownOrAllowedModel(fleetModel, true) then fleetModel = nil end
    AdminModes[src] = mode
    enterShopBucket(src, 'admin')
    local sourceList = flattenSourceVehicles(false)
    TriggerClientEvent('rn-vehicleshop:client:openAdmin', src, sourceList, getCatalog(true), adminMeta(), mode, fleetModel)
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
    data = type(data) == 'table' and data or {}
    local requestId = adminRequestId(data.requestId)
    local function reject(message, code)
        sendAdminActionResult(src, 'save', requestId, false, message, { code = code or 'rejected' })
        notify(src, message, 'error')
        return false
    end
    if not isAdmin(src) then return reject('No permission.', 'permission_denied') end
    if AdminModes[src] ~= 'manage' then return reject('Use /managevehicle to configure photographed vehicles.', 'wrong_admin_mode') end
    if not checkRateLimit(src, 'saveAdminVehicle', tonumber(hardeningCfg().AdminSaveCooldownMs) or 1500) then
        return reject('Slow down before saving another vehicle.', 'rate_limited')
    end

    local model = normalizeModel(data.model)
    local modelOk, modelErr = isKnownOrAllowedModel(model, true)
    if not modelOk then return reject(modelErr or 'Invalid model.', 'invalid_model') end

    local existingCatalog = MySQL.single.await('SELECT retired, replacement_model, image, metadata, mods FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { model })
    if existingCatalog then
        local activeReplacement = MySQL.single.await([[
            SELECT status FROM cm_vehicle_replacements
            WHERE old_model = ? AND status <> 'restored'
            LIMIT 1
        ]], { model })
        if activeReplacement then
            local status = tostring(activeReplacement.status or 'replacement')
            local message = status == 'permanent'
                and 'This vehicle was permanently removed. Save cannot enable or modify it.'
                or 'This vehicle has an active replacement. Use Retake image & enable to restore it safely.'
            return reject(message, 'replacement_active')
        end
    end

    local label = safeUtf8Sub(data.label, 100, model)
    local category = safeUtf8Sub(data.category, 64, 'Custom')
    local price = math.floor(tonumber(data.price) or 0)
    local maxPrice = math.floor(tonumber(hardeningCfg().MaxVehiclePrice) or 250000000)
    if price < 0 or price > maxPrice then
        return reject(('Price must be between $0 and $%s.'):format(maxPrice), 'invalid_price')
    end
    local speedKph = math.floor(tonumber(data.speedKph or data.speed_kph) or 0)
    if speedKph < 0 or speedKph > 1000 then return reject('Top speed must be between 0 and 1000 km/h.', 'invalid_speed') end
    if speedKph == 0 then speedKph = nil end
    local trunkLevel = clampTrunkLevel(data.trunkLevel or data.trunk_level)

    local hasCarplay = truthy(data.hasCarplay or data.has_carplay)
    local vehicleType = normalizeVehicleType(data.vehicleType or data.vehicle_type)
    local availableStore = truthy(data.availableStore or data.available_store)
    local availableServer = truthy(data.availableServer or data.available_server)
    local availableEms = truthy(data.availableEms or data.available_ems)
    local availablePolice = truthy(data.availablePolice or data.available_police)
    local requestedLegalOrg = tostring(data.legalOrg or data.legal_org or ''):lower()
    local legalOrg = requestedLegalOrg:gsub('[^a-z0-9_]', '')
    if legalOrg == '' then legalOrg = nil end
    local requestedGangId=tostring(data.gangId or ''):lower()
    local gangId=requestedGangId:gsub('[^a-z0-9_]', '')
    local validGangs={marabunta=true,bloods=true,ballas=true,families=true,vagos=true}
    if gangId ~= '' and not validGangs[gangId] then return reject('Invalid gang organization.', 'invalid_organization') end
    if gangId == '' then gangId=nil end
    if legalOrg then
        local validLegalOrg = false
        for _, org in ipairs(legalOrgOptions()) do
            if tostring(org.id or ''):lower() == legalOrg then validLegalOrg = true; break end
        end
        if not validLegalOrg then return reject('Invalid legal organization.', 'invalid_organization') end
    end
    if requestedLegalOrg ~= '' and requestedLegalOrg ~= tostring(legalOrg or '') then
        return reject('Invalid legal organization.', 'invalid_organization')
    end
    if requestedGangId ~= '' and requestedGangId ~= tostring(gangId or '') then
        return reject('Invalid gang organization.', 'invalid_organization')
    end
    if legalOrg and gangId then return reject('Select only one organization destination.', 'ambiguous_organization') end
    if availableStore then availableServer = true end
    -- EMS, Police, and any cm-law organization are each their own
    -- mutually-exclusive catalog status (hidden/server/store/ems/police/
    -- legal:<org>), matching the single #admin-status-mode select in the
    -- NUI -- never let a vehicle be both a public store item and a fleet
    -- vehicle, and never assigned to more than one fleet at once.
    if availableEms then availableStore=false; availableServer=false; availablePolice=false; legalOrg=nil; gangId=nil end
    if availablePolice then availableStore=false; availableServer=false; availableEms=false; legalOrg=nil; gangId=nil end
    if legalOrg then availableStore=false; availableServer=false; availableEms=false; availablePolice=false; gangId=nil end
    if gangId then availableStore=false; availableServer=false; availableEms=false; availablePolice=false; legalOrg=nil end

    local vehicleMods = sanitizeVehicleMods(data.mods)
    if speedKph then vehicleMods.catalogMaxSpeedKph = speedKph end
    local fleetAppearanceEnabled = availableEms or availablePolice or legalOrg ~= nil or gangId ~= nil
    -- Non-fleet availability changes do not carry an authoritative vehicle
    -- appearance from the client. Preserve the last saved catalog mods rather
    -- than replacing them with NULL when moving between store/server/hidden.
    local savedMods = fleetAppearanceEnabled and encode(vehicleMods)
        or (existingCatalog and existingCatalog.mods or nil)

    local testDriveCfg = Config.TestDrive or {}
    local testDriveEnabled = data.testDriveEnabled
    if testDriveEnabled == nil then testDriveEnabled = data.test_drive_enabled end
    if testDriveEnabled == nil then testDriveEnabled = true end
    testDriveEnabled = truthy(testDriveEnabled)
    local testDriveTimer = math.floor(tonumber(testDriveCfg.testDriveTimer) or 300)
    if testDriveTimer < 10 then testDriveTimer = 10 end
    if testDriveTimer > 600 then testDriveTimer = 600 end
    local testDriveCost = math.floor(tonumber(data.testDriveCost or data.test_drive_cost) or tonumber(testDriveCfg.testDriveCost) or 0)
    if testDriveCost < 0 then testDriveCost = 0 end
    local replacementNotice = safeUtf8Sub(data.replacementNotice or data.replacement_notice, 240, '')

    -- Keep any previously captured image unless this save provides a new path.
    local image = data.image and tostring(data.image) ~= '' and safeUtf8Sub(data.image, 255) or nil
    if not image then
        local existing = existingCatalog and existingCatalog.image or nil
        if existing and tostring(existing) ~= '' then image = tostring(existing) end
    end

    -- A car can only be enabled (store, server, ems, police, or a legal org) once it has a captured image.
    if (availableStore or availableServer or availableEms or availablePolice or legalOrg ~= nil or gangId ~= nil) and (not image or image == '') then
        notify(src, 'Capture an image first. A vehicle cannot be enabled without an image.', 'error')
        sendAdminActionResult(src, 'save', requestId, false, 'Capture an image before this vehicle can be enabled.', {
            code = 'image_required', pending = true
        })
        TriggerClientEvent('rn-vehicleshop:client:adminNeedsImage', src, model, {
            label = label, category = category, price = price, speedKph = speedKph, trunkLevel = trunkLevel,
            availableStore = availableStore, availableServer = availableServer, availableEms = availableEms, availablePolice = availablePolice, legalOrg = legalOrg, gangId = gangId,
            hasCarplay = hasCarplay,
            replacementNotice = replacementNotice,
            testDriveEnabled = testDriveEnabled, testDriveTimer = testDriveTimer, testDriveCost = testDriveCost, requestId = requestId
        })
        return
    end

    local saveQuery = [[
        INSERT INTO cm_vehicle_catalog (model, label, category, price, speed_kph, trunk_level, available_store, available_server, available_ems, available_police, legal_org, gang_id, image, metadata, mods, has_carplay, vehicle_type, retired, replacement_model)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL)
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
            gang_id = VALUES(gang_id),
            image = VALUES(image),
            metadata = VALUES(metadata),
            mods = VALUES(mods),
            has_carplay = VALUES(has_carplay),
            vehicle_type = VALUES(vehicle_type),
            retired = 0,
            replacement_model = NULL
    ]]
    local catalogMetadata = decode(existingCatalog and existingCatalog.metadata)
    catalogMetadata.savedBy = GetPlayerName(src)
    catalogMetadata.savedAt = os.time()
    catalogMetadata.replacementNotice = replacementNotice ~= '' and replacementNotice or nil
    catalogMetadata.testDrive = {
        enabled = testDriveEnabled,
        duration = testDriveTimer,
        cost = testDriveCost
    }
    local saveValues = { model, label, category, price, speedKph, trunkLevel, availableStore and 1 or 0, availableServer and 1 or 0, availableEms and 1 or 0, availablePolice and 1 or 0, legalOrg, gangId, image, encode(catalogMetadata), savedMods, hasCarplay and 1 or 0, vehicleType }
    local writeOk, committed = pcall(function()
        return MySQL.transaction.await({ { query = saveQuery, values = saveValues } })
    end)
    if not writeOk or committed ~= true then
        structuredAdminLog('catalog', 'save_failed', src, { model=model, requestId=requestId, stage='database' }, 'error')
        return reject('Vehicle save failed. No catalog changes were committed.', 'database_write_failed')
    end

    invalidateCatalogCache()
    if GetResourceState('cm-gang')=='started' then pcall(function() exports['cm-gang']:AssignCatalogVehicle(src,model,gangId) end) end
    if fleetAppearanceEnabled and tostring(data.fleetTuneModel or ''):lower() == model and GetResourceState('cm-law') == 'started' then
        local synced, syncOk, syncMessage = pcall(function() return exports['cm-law']:SyncFleetCatalogMods(src, model, vehicleMods) end)
        if not synced or syncOk ~= true then
            structuredAdminLog('organization_vehicle', 'fleet_mod_sync_failed', src, { model = model, reason = tostring(syncMessage or syncOk) }, 'error')
        end
    end
    local successMessage = ('Saved %s.'):format(label)
    notify(src, successMessage, 'success')
    sendAdminActionResult(src, 'save', requestId, true, successMessage, { model=model })
    structuredAdminLog('catalog', 'saved', src, { model = model, label = label, category = category, price = price, trunkLevel = trunkLevel, availableStore = availableStore, availableServer = availableServer, availableEms = availableEms, availablePolice = availablePolice, legalOrg = legalOrg, hasCarplay = hasCarplay, replacementNoticeConfigured = replacementNotice ~= '', testDrive = { enabled = testDriveEnabled, duration = testDriveTimer, cost = testDriveCost } }, 'success')
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

local function modelReplacementCfg()
    return type(Config.ModelReplacement) == 'table' and Config.ModelReplacement or {}
end

local function catalogSnapshot(row)
    if type(row) ~= 'table' then return {} end
    return {
        model = row.model,
        label = row.label,
        category = row.category,
        price = row.price,
        speed_kph = row.speed_kph,
        trunk_level = row.trunk_level,
        available_store = row.available_store,
        available_server = row.available_server,
        available_ems = row.available_ems,
        available_police = row.available_police,
        legal_org = row.legal_org,
        gang_id = row.gang_id,
        image = row.image,
        metadata = decode(row.metadata),
        mods = decode(row.mods),
        has_carplay = row.has_carplay,
        retired = row.retired,
        replacement_model = row.replacement_model
    }
end

local function cleanupCompletedReplacementRecords()
    local ok, result = pcall(function()
        return MySQL.update.await([[
            DELETE FROM cm_vehicle_replacements
            WHERE status = 'restored'
              AND NOT EXISTS (
                  SELECT 1 FROM cm_vehicle_replacement_pending p
                  WHERE p.replacement_id = cm_vehicle_replacements.id
              )
        ]])
    end)
    if not ok then debugPrint('Could not clean completed vehicle replacement records: ' .. tostring(result)) end
    return ok and (tonumber(result) or 0) or 0
end

local function cleanupOrphanedPendingReplacementRecords()
    local ok, result = pcall(function()
        return MySQL.update.await([[
            DELETE pending
            FROM cm_vehicle_replacement_pending pending
            LEFT JOIN cm_owned_vehicles vehicle ON vehicle.id = pending.vehicle_id
            WHERE vehicle.id IS NULL
        ]])
    end)
    if not ok then
        debugPrint('Could not clean orphaned pending vehicle replacements: ' .. tostring(result))
        return 0
    end
    local removed = tonumber(result) or 0
    if removed > 0 then debugPrint(('Removed %d orphaned pending vehicle replacement record(s).'):format(removed)) end
    return removed
end

-- Finalize one already-authorized replacement immediately before cm-vehicles
-- creates a new entity. This closes the recovery gap where an old streamed
-- model is missing while its database row is still marked outside, so it can
-- never be stored to satisfy the normal replacement poller.
local function resolvePendingModelReplacementForSpawn(vehicleId)
    vehicleId = tonumber(vehicleId)
    if not vehicleId or vehicleId <= 0 then return false, 'invalid_vehicle_id' end
    if PendingReplacementResolveLocks[vehicleId] then return false, 'replacement_busy' end
    PendingReplacementResolveLocks[vehicleId] = true

    local callOk, applied, result = pcall(function()
        local row = MySQL.single.await([[
            SELECT p.vehicle_id, p.old_model, p.new_model,
                   v.model AS current_model, v.metadata,
                   r.old_model AS replacement_old_model,
                   r.new_model AS replacement_new_model,
                   r.status AS replacement_status
            FROM cm_vehicle_replacement_pending p
            INNER JOIN cm_owned_vehicles v ON v.id = p.vehicle_id
            INNER JOIN cm_vehicle_replacements r ON r.id = p.replacement_id
            WHERE p.vehicle_id = ?
            LIMIT 1
        ]], { vehicleId })
        if not row then return false, 'not_pending' end

        local oldModel = normalizeModel(row.old_model)
        local newModel = normalizeModel(row.new_model)
        local currentModel = normalizeModel(row.current_model)
        local replacementOld = normalizeModel(row.replacement_old_model)
        local replacementNew = normalizeModel(row.replacement_new_model)
        local replacementStatus = tostring(row.replacement_status or '')
        local metadata = decode(row.metadata)
        local restoring = tostring(metadata.replacementType or '') == 'restoring'
            and normalizeModel(metadata.replacementOriginalModel) == newModel
        local validForward = replacementOld == oldModel and replacementNew == newModel
            and (replacementStatus == 'temporary' or replacementStatus == 'permanent')
        local validRestore = replacementOld == newModel and replacementNew == oldModel
            and replacementStatus == 'restored' and restoring

        if not isValidModelName(oldModel) or not isValidModelName(newModel)
            or (not validForward and not validRestore) then
            return false, 'invalid_replacement_record'
        end

        if currentModel ~= newModel then
            if currentModel ~= oldModel then return false, 'vehicle_model_changed' end
            local updated = MySQL.update.await(
                'UPDATE cm_owned_vehicles SET model = ? WHERE id = ? AND model = ?',
                { newModel, vehicleId, oldModel }
            )
            if not updated or tonumber(updated) <= 0 then
                local confirmed = normalizeModel(MySQL.scalar.await(
                    'SELECT model FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { vehicleId }
                ))
                if confirmed ~= newModel then return false, 'model_update_failed' end
            end
        end

        if restoring then
            MySQL.update.await([[
                UPDATE cm_owned_vehicles
                SET metadata = JSON_REMOVE(COALESCE(metadata, '{}'),
                    '$.vehicleNotice', '$.replacementType', '$.permanentlyRemoved',
                    '$.replacementOriginalModel', '$.replacementOriginalImage')
                WHERE id = ?
            ]], { vehicleId })
        end

        MySQL.update.await([[
            DELETE FROM cm_vehicle_replacement_pending
            WHERE vehicle_id = ? AND old_model = ? AND new_model = ?
        ]], { vehicleId, oldModel, newModel })
        cleanupCompletedReplacementRecords()
        return true, newModel
    end)

    PendingReplacementResolveLocks[vehicleId] = nil
    if not callOk then
        debugPrint(('Could not resolve pending replacement for vehicle %s: %s')
            :format(tostring(vehicleId), tostring(applied)))
        return false, 'replacement_database_error'
    end
    return applied, result
end

-- Server-only compatibility contract for cm-vehicles. The caller supplies
-- only the persistent vehicle ID; the target model is resolved from the
-- authoritative replacement journal and is never accepted from a client.
exports('ResolvePendingModelReplacement', function(vehicleId)
    if GetInvokingResource() ~= 'cm-vehicles' then return false, 'not_allowed' end
    return resolvePendingModelReplacementForSpawn(vehicleId)
end)

local DEFAULT_TEMPORARY_REPLACEMENT_NOTICE =
    'This vehicle is temporarily using a Komoda because its original model is unavailable. It will be fixed soon.'

local function temporaryReplacementNotice(catalogRow, requestedNotice)
    local requested = safeUtf8Sub(requestedNotice, 240, '')
    if requested ~= '' then return requested end
    local metadata = decode(catalogRow and catalogRow.metadata)
    local configured = safeUtf8Sub(metadata.replacementNotice, 240, '')
    return configured ~= '' and configured or DEFAULT_TEMPORARY_REPLACEMENT_NOTICE
end

-- Server-only recovery contract used after cm-vehicles has failed to create an
-- owned model. The persistent vehicle ID, owner, value, condition and plate do
-- not change; only its model is conditionally moved to the known Komoda
-- fallback. The original model remains in metadata and the existing restore
-- workflow can move it back after the stream files are repaired.
local function applyMissingModelFallback(vehicleId, reasonCode)
    vehicleId = tonumber(vehicleId)
    if not vehicleId or vehicleId <= 0 then return false, 'invalid_vehicle_id' end
    if modelReplacementCfg().enabled == false then return false, 'replacement_disabled' end
    if AutomaticFallbackLocks[vehicleId] or PendingReplacementResolveLocks[vehicleId] then
        return false, 'replacement_busy'
    end
    AutomaticFallbackLocks[vehicleId] = true

    local callOk, applied, result, notice = pcall(function()
        local vehicle = MySQL.single.await(
            'SELECT id, model, label, metadata FROM cm_owned_vehicles WHERE id = ? LIMIT 1',
            { vehicleId }
        )
        if not vehicle then return false, 'vehicle_not_found' end

        local currentModel = normalizeModel(vehicle.model)
        local currentMetadata = decode(vehicle.metadata)
        if currentModel == 'komoda' then
            local originalModel = normalizeModel(currentMetadata.replacementOriginalModel)
            if originalModel ~= '' and tostring(currentMetadata.replacementType or '') == 'temporary' then
                return true, 'komoda', safeUtf8Sub(currentMetadata.vehicleNotice, 240,
                    DEFAULT_TEMPORARY_REPLACEMENT_NOTICE)
            end
            return false, 'fallback_model_unavailable'
        end
        if not isValidModelName(currentModel) then return false, 'invalid_original_model' end

        local komoda = MySQL.single.await(
            'SELECT * FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { 'komoda' })
        if not komoda then return false, 'komoda_not_in_catalog' end

        local oldCatalog = MySQL.single.await(
            'SELECT * FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { currentModel })
        local replacement = MySQL.single.await(
            'SELECT id, new_model, status FROM cm_vehicle_replacements WHERE old_model = ? LIMIT 1',
            { currentModel }
        )
        if replacement and tostring(replacement.status or '') == 'permanent' then
            return false, 'permanent_replacement_exists'
        end
        if replacement and tostring(replacement.status or '') == 'restored' then
            local pendingRestores = tonumber(MySQL.scalar.await(
                'SELECT COUNT(*) FROM cm_vehicle_replacement_pending WHERE replacement_id = ?',
                { tonumber(replacement.id) }
            )) or 0
            if pendingRestores > 0 then return false, 'restore_in_progress' end
        end
        if replacement and tostring(replacement.status or '') ~= 'restored'
            and normalizeModel(replacement.new_model) ~= 'komoda' then
            return false, 'different_replacement_exists'
        end

        local fallbackNotice = temporaryReplacementNotice(oldCatalog)
        local oldSnapshot = encode(oldCatalog and catalogSnapshot(oldCatalog) or {
            model = currentModel,
            label = vehicle.label,
        })
        local createdBy = 'system:' .. safeUtf8Sub(reasonCode, 48, 'model_unavailable')
        local committed = MySQL.transaction.await({
            {
                query = [[
                    INSERT INTO cm_vehicle_replacements
                        (old_model, new_model, old_catalog, old_image, new_image, status, created_by, applied_at)
                    VALUES (?, 'komoda', ?, ?, ?, 'temporary', ?, CURRENT_TIMESTAMP)
                    ON DUPLICATE KEY UPDATE
                        new_model = VALUES(new_model), old_catalog = VALUES(old_catalog),
                        old_image = VALUES(old_image), new_image = VALUES(new_image),
                        status = 'temporary', created_by = VALUES(created_by), applied_at = CURRENT_TIMESTAMP
                ]],
                values = {
                    currentModel, oldSnapshot, oldCatalog and oldCatalog.image or nil,
                    komoda.image, createdBy
                }
            },
            {
                query = [[
                    UPDATE cm_owned_vehicles
                    SET model = 'komoda',
                        metadata = JSON_SET(COALESCE(metadata, '{}'),
                            '$.vehicleNotice', ?, '$.replacementType', 'temporary',
                            '$.permanentlyRemoved', false,
                            '$.replacementOriginalModel', ?, '$.replacementOriginalImage', ?)
                    WHERE id = ? AND model = ?
                ]],
                values = {
                    fallbackNotice, currentModel,
                    oldCatalog and tostring(oldCatalog.image or '') or '',
                    vehicleId, currentModel
                }
            }
        })
        if committed ~= true then return false, 'fallback_transaction_failed' end

        local confirmed = MySQL.single.await(
            'SELECT model, metadata FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { vehicleId })
        local confirmedMetadata = decode(confirmed and confirmed.metadata)
        if normalizeModel(confirmed and confirmed.model) ~= 'komoda'
            or normalizeModel(confirmedMetadata.replacementOriginalModel) ~= currentModel then
            return false, 'fallback_update_not_confirmed'
        end

        structuredAdminLog('catalog', 'automatic_missing_model_fallback', 0, {
            vehicleId = vehicleId,
            oldModel = currentModel,
            newModel = 'komoda',
            reason = safeUtf8Sub(reasonCode, 48, 'model_unavailable'),
            preservedVehicleId = true,
        }, 'warning')
        return true, 'komoda', fallbackNotice
    end)

    AutomaticFallbackLocks[vehicleId] = nil
    if not callOk then
        debugPrint(('Automatic Komoda fallback failed for vehicle %s: %s')
            :format(tostring(vehicleId), tostring(applied)))
        return false, 'fallback_database_error'
    end
    return applied, result, notice
end

exports('ApplyMissingModelFallback', function(vehicleId, reasonCode)
    if GetInvokingResource() ~= 'cm-vehicles' then return false, 'not_allowed' end
    local allowedReasons = {
        model_unavailable = true,
        server_create_failed = true,
    }
    reasonCode = tostring(reasonCode or '')
    if not allowedReasons[reasonCode] then return false, 'invalid_reason' end
    return applyMissingModelFallback(vehicleId, reasonCode)
end)

local function processPendingModelReplacements()
    cleanupOrphanedPendingReplacementRecords()
    if not OwnedVehicleHasStoredColumn then return 0 end
    local rows = MySQL.query.await([[
        SELECT p.vehicle_id, p.old_model, p.new_model, v.metadata
        FROM cm_vehicle_replacement_pending p
        INNER JOIN cm_owned_vehicles v ON v.id = p.vehicle_id
        WHERE v.is_stored = 1
    ]]) or {}
    local completed = 0
    for _, row in ipairs(rows) do
        local updated = MySQL.update.await(
            'UPDATE cm_owned_vehicles SET model = ? WHERE id = ? AND model = ? AND is_stored = 1',
            { normalizeModel(row.new_model), tonumber(row.vehicle_id), normalizeModel(row.old_model) }
        )
        if tonumber(updated) and tonumber(updated) > 0 then
            local metadata = decode(row.metadata)
            if metadata.replacementType == 'restoring'
                and normalizeModel(metadata.replacementOriginalModel) == normalizeModel(row.new_model) then
                MySQL.update.await([[
                    UPDATE cm_owned_vehicles
                    SET metadata = JSON_REMOVE(COALESCE(metadata, '{}'),
                        '$.vehicleNotice', '$.replacementType', '$.permanentlyRemoved',
                        '$.replacementOriginalModel', '$.replacementOriginalImage')
                    WHERE id = ?
                ]], { tonumber(row.vehicle_id) })
            end
            MySQL.update.await('DELETE FROM cm_vehicle_replacement_pending WHERE vehicle_id = ?', { tonumber(row.vehicle_id) })
            completed = completed + 1
        elseif tonumber(updated) == 0 then
            -- The row may have been migrated by another recovery pass. Never
            -- delete a pending record unless the persisted model is confirmed.
            local current = MySQL.scalar.await('SELECT model FROM cm_owned_vehicles WHERE id = ?', { tonumber(row.vehicle_id) })
            if normalizeModel(current) == normalizeModel(row.new_model) then
                local metadata = decode(row.metadata)
                if metadata.replacementType == 'restoring'
                    and normalizeModel(metadata.replacementOriginalModel) == normalizeModel(row.new_model) then
                    MySQL.update.await([[
                        UPDATE cm_owned_vehicles
                        SET metadata = JSON_REMOVE(COALESCE(metadata, '{}'),
                            '$.vehicleNotice', '$.replacementType', '$.permanentlyRemoved',
                            '$.replacementOriginalModel', '$.replacementOriginalImage')
                        WHERE id = ?
                    ]], { tonumber(row.vehicle_id) })
                end
                MySQL.update.await('DELETE FROM cm_vehicle_replacement_pending WHERE vehicle_id = ?', { tonumber(row.vehicle_id) })
                completed = completed + 1
            end
        end
    end
    cleanupCompletedReplacementRecords()
    return completed
end

local function startReplacementPoller()
    if ReplacementPollStarted then return end
    ReplacementPollStarted = true
    CreateThread(function()
        while GetResourceState(GetCurrentResourceName()) == 'started' do
            Wait(math.max(5000, tonumber(modelReplacementCfg().pendingPollMs) or 15000))
            local ok, count = pcall(processPendingModelReplacements)
            if ok and tonumber(count) and count > 0 then
                debugPrint(('Applied %d pending vehicle model replacement(s) after storage.'):format(count))
            end
        end
        ReplacementPollStarted = false
    end)
end

local function safeApplyModelReplacement(src, data)
    local cfg = modelReplacementCfg()
    if cfg.enabled == false then return false, 'Safe model replacement is disabled.' end
    data = type(data) == 'table' and data or {}

    local oldModel = normalizeModel(data.oldModel)
    local permanent = data.permanent == true
    local newModel = permanent and 'komoda' or 'komoda'
    if not isValidModelName(oldModel) or not isValidModelName(newModel) or oldModel == newModel then
        return false, 'Choose two valid, different vehicle models.'
    end
    local newKnown, newErr = isKnownOrAllowedModel(newModel, true)
    if not newKnown then return false, newErr or 'Replacement model is not available.' end

    local oldRow = MySQL.single.await('SELECT * FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { oldModel })
    if not oldRow then return false, 'The old model is not saved in the vehicle catalog.' end
    if tonumber(oldRow.retired) == 1 then return false, 'This model has already been retired or replaced.' end

    local existingReplacement = MySQL.single.await('SELECT id, status, new_model FROM cm_vehicle_replacements WHERE old_model = ? LIMIT 1', { oldModel })
    if existingReplacement and tostring(existingReplacement.status or '') ~= 'restored' then
        return false, ('A replacement for %s already exists (%s).'):format(oldModel, tostring(existingReplacement.new_model or existingReplacement.status))
    end
    if existingReplacement then
        local pendingRestores = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM cm_vehicle_replacement_pending WHERE replacement_id = ?',
            { tonumber(existingReplacement.id) }
        )) or 0
        if pendingRestores > 0 then
            return false, ('%d vehicle(s) are still waiting to finish restoring %s. Store them before replacing this model again.'):format(pendingRestores, oldModel)
        end
    end

    local newRow = MySQL.single.await('SELECT * FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { newModel })
    if not newRow then return false, 'The Komoda model is not saved in the vehicle catalog.' end
    if newModel ~= 'komoda' and cfg.rejectTargetWithExistingOwners ~= false then
        local targetOwners = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_owned_vehicles WHERE model = ?', { newModel })) or 0
        if targetOwners > 0 then
            return false, ('The replacement model already has %d owned vehicle(s). Choose an unused model.'):format(targetOwners)
        end
    end
    if newModel ~= 'komoda' and cfg.rejectTargetAlreadyPublished ~= false then
        local targetPublished = truthy(newRow.available_store) or truthy(newRow.available_server)
            or truthy(newRow.available_ems) or truthy(newRow.available_police)
            or (newRow.legal_org and tostring(newRow.legal_org) ~= '')
            or (newRow.gang_id and tostring(newRow.gang_id) ~= '')
        if targetPublished then
            return false, 'The replacement model is already published. Keep it hidden, capture its image, then apply the replacement.'
        end
    end

    local ownedRows = MySQL.query.await([[SELECT id, model, is_stored FROM cm_owned_vehicles WHERE model = ? ORDER BY id ASC]], { oldModel }) or {}
    if #ownedRows > 0 and not OwnedVehicleHasStoredColumn then
        return false, 'cm_owned_vehicles.is_stored is required for safe live replacement. Update cm-vehicles first.'
    end

    local oldSnapshot = encode(catalogSnapshot(oldRow))
    local notice = permanent
        and 'This vehicle model was permanently removed. Sell this vehicle to the state to receive a full refund.'
        or temporaryReplacementNotice(oldRow, data.notice)
    local replacementStatus = permanent and 'permanent' or 'temporary'
    local createdBy = GetPlayerName(src) or ('source:' .. tostring(src))
    local operations = {
        {
            query = [[
                INSERT INTO cm_vehicle_replacements
                    (old_model, new_model, old_catalog, old_image, new_image, status, created_by, applied_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                ON DUPLICATE KEY UPDATE
                    new_model = VALUES(new_model), old_catalog = VALUES(old_catalog),
                    old_image = VALUES(old_image), new_image = VALUES(new_image),
                    status = VALUES(status), created_by = VALUES(created_by), applied_at = CURRENT_TIMESTAMP
            ]],
            values = { oldModel, newModel, oldSnapshot, oldRow.image, newRow.image, replacementStatus, createdBy }
        },
        {
            query = [[
                UPDATE cm_vehicle_catalog
                SET available_store = 0, available_server = 0, available_ems = 0, available_police = 0,
                    legal_org = NULL, gang_id = NULL, retired = 1, replacement_model = ?
                WHERE model = ? AND retired = 0
            ]],
            values = { newModel, oldModel }
        }
    }

    local immediate = 0
    local pending = 0
    for _, row in ipairs(ownedRows) do
        operations[#operations + 1] = {
            query = "UPDATE cm_owned_vehicles SET metadata = JSON_SET(COALESCE(metadata, '{}'), '$.vehicleNotice', ?, '$.replacementType', ?, '$.permanentlyRemoved', ?, '$.replacementOriginalModel', ?, '$.replacementOriginalImage', ?) WHERE id = ? AND model = ?",
            values = { notice, replacementStatus, permanent, oldModel, tostring(oldRow.image or ''), tonumber(row.id), oldModel }
        }
        local stored = tonumber(row.is_stored) == 1 or row.is_stored == true
        if stored then
            operations[#operations + 1] = {
                query = 'UPDATE cm_owned_vehicles SET model = ? WHERE id = ? AND model = ? AND is_stored = 1',
                values = { newModel, tonumber(row.id), oldModel }
            }
            immediate = immediate + 1
        else
            operations[#operations + 1] = {
                query = [[
                    INSERT INTO cm_vehicle_replacement_pending (vehicle_id, replacement_id, old_model, new_model)
                    VALUES (?, (SELECT id FROM cm_vehicle_replacements WHERE old_model = ?), ?, ?)
                    ON DUPLICATE KEY UPDATE replacement_id = VALUES(replacement_id), old_model = VALUES(old_model), new_model = VALUES(new_model)
                ]],
                values = { tonumber(row.id), oldModel, oldModel, newModel }
            }
            pending = pending + 1
        end
    end

    local ok, result = pcall(function() return MySQL.transaction.await(operations) end)
    if not ok or result ~= true then
        return false, 'Replacement was not applied. No vehicle or catalog data was changed.'
    end

    invalidateCatalogCache()
    if #ownedRows == 0 then
        local emptyMessage = permanent
            and ('Permanently removed %s. Its catalog configuration was retained for audit history.'):format(oldModel)
            or ('Temporarily replaced %s with %s. Its catalog configuration was retained and can be restored.'):format(oldModel, newModel)
        structuredAdminLog('catalog', permanent and 'permanently_removed_empty' or 'temporarily_replaced_empty', src, {
            oldModel = oldModel, newModel = newModel, catalogPreserved = true
        }, 'warning')
        return true, emptyMessage
    end
    local message = ('Replacement applied: %s → %s. %d vehicle(s) migrated, %d active vehicle(s) waiting for storage.')
        :format(oldModel, newModel, immediate, pending)
    structuredAdminLog('catalog', 'safe_model_replacement', src, {
        oldModel = oldModel, newModel = newModel, immediate = immediate, pending = pending,
        replacementType = replacementStatus, preservedVehicleIds = true, oldImage = oldRow.image, newImage = newRow.image
    }, 'warning')
    return true, message
end

RegisterNetEvent('rn-vehicleshop:server:replaceAdminVehicle', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local requestId = adminRequestId(data.requestId)
    local function reject(message, code)
        sendAdminActionResult(src, 'replace', requestId, false, message, { code=code or 'rejected' })
        notify(src, message, 'error')
        return false
    end
    if not isAdmin(src) then return reject('No permission.', 'permission_denied') end
    if AdminModes[src] ~= 'manage' then return reject('Use /managevehicle first.', 'wrong_admin_mode') end
    if not checkRateLimit(src, 'safeModelReplacement', 2000) then return reject('Please wait before applying another model replacement.', 'rate_limited') end
    local success, message = safeApplyModelReplacement(src, data)
    notify(src, message, success and 'success' or 'error')
    sendAdminActionResult(src, 'replace', requestId, success, message, {
        model=normalizeModel(data.oldModel), permanent=data.permanent == true
    })
    if success then
        TriggerClientEvent('rn-vehicleshop:client:adminData', src, flattenSourceVehicles(), getCatalog(true), adminMeta())
    end
end)

RegisterNetEvent('rn-vehicleshop:server:updateReplacementNotice', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local requestId = adminRequestId(data.requestId)
    local function reject(message, code)
        sendAdminActionResult(src, 'notice', requestId, false, message, { code = code or 'rejected' })
        notify(src, message, 'error')
        return false
    end
    if not isAdmin(src) then return reject('No permission.', 'permission_denied') end
    if AdminModes[src] ~= 'manage' then return reject('Use /managevehicle first.', 'wrong_admin_mode') end
    if not checkRateLimit(src, 'replacementNotice', 1000) then
        return reject('Please wait before updating the message again.', 'rate_limited')
    end

    local model = normalizeModel(data.model)
    if not isValidModelName(model) then return reject('Invalid model.', 'invalid_model') end
    local catalog = MySQL.single.await(
        'SELECT model, metadata FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { model })
    if not catalog then return reject('Vehicle was not found in the catalog.', 'catalog_missing') end

    local configuredNotice = safeUtf8Sub(data.notice, 240, '')
    local effectiveNotice = configuredNotice ~= ''
        and configuredNotice or DEFAULT_TEMPORARY_REPLACEMENT_NOTICE
    local catalogQuery
    local catalogValues
    if configuredNotice ~= '' then
        catalogQuery = [[
            UPDATE cm_vehicle_catalog
            SET metadata = JSON_SET(COALESCE(metadata, '{}'), '$.replacementNotice', ?)
            WHERE model = ?
        ]]
        catalogValues = { configuredNotice, model }
    else
        catalogQuery = [[
            UPDATE cm_vehicle_catalog
            SET metadata = JSON_REMOVE(COALESCE(metadata, '{}'), '$.replacementNotice')
            WHERE model = ?
        ]]
        catalogValues = { model }
    end

    local writeOk, committed = pcall(function()
        return MySQL.transaction.await({
            { query = catalogQuery, values = catalogValues },
            {
                query = [[
                    UPDATE cm_owned_vehicles
                    SET metadata = JSON_SET(COALESCE(metadata, '{}'), '$.vehicleNotice', ?)
                    WHERE JSON_VALID(metadata)
                      AND LOWER(JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.replacementOriginalModel'))) = ?
                      AND JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.replacementType')) IN ('temporary', 'restoring')
                ]],
                values = { effectiveNotice, model }
            }
        })
    end)
    if not writeOk or committed ~= true then
        return reject('The fallback message was not updated.', 'database_write_failed')
    end

    invalidateCatalogCache()
    structuredAdminLog('catalog', 'replacement_notice_updated', src, {
        model = model,
        custom = configuredNotice ~= '',
    }, 'success')
    local message = configuredNotice ~= ''
        and 'Fallback message updated.' or 'Fallback message reset to the default.'
    notify(src, message, 'success')
    sendAdminActionResult(src, 'notice', requestId, true, message, { model = model })
    TriggerClientEvent('rn-vehicleshop:client:adminData', src,
        flattenSourceVehicles(), getCatalog(true), adminMeta())
end)

RegisterNetEvent('rn-vehicleshop:server:disableAdminVehicle', function(model)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    if AdminModes[src] ~= 'manage' then return notify(src, 'Use /managevehicle to change vehicle availability.', 'error') end
    if not checkRateLimit(src, 'disableAdminVehicle', tonumber(hardeningCfg().AdminDisableCooldownMs) or 1000) then return end
    model = normalizeModel(model)
    if not isValidModelName(model) then return notify(src, 'Invalid model.', 'error') end
    local owners = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_owned_vehicles WHERE model = ?', { model })) or 0
    if owners > 0 then return notify(src, ('Cannot remove %s directly: %d vehicle(s) still use it. Use Safe Model Replacement first.'):format(model, owners), 'error') end
    local changed = MySQL.update.await([[
        UPDATE cm_vehicle_catalog
        SET available_store = 0, available_server = 0, available_ems = 0, available_police = 0,
            legal_org = NULL, gang_id = NULL, retired = 1, replacement_model = NULL
        WHERE model = ?
    ]], { model })
    if not tonumber(changed) or tonumber(changed) <= 0 then
        MySQL.insert.await('INSERT IGNORE INTO cm_vehicle_catalog (model, label, category, price, trunk_level, available_store, available_server, retired) VALUES (?, ?, ?, 0, 1, 0, 0, 1)', { model, model, 'Custom' })
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

local function resourceImagePathFromNui(nuiPath, folder, model)
    nuiPath = tostring(nuiPath or '')
    local prefix = ('nui://%s/%s/'):format(GetCurrentResourceName(), folder)
    if nuiPath:sub(1, #prefix) ~= prefix then return nil end
    local fileName = nuiPath:sub(#prefix + 1)
    if fileName == '' or fileName:find('[/\\]') then return nil end
    local safeModel = safeFilePart(model)
    local escapedModel = safeModel:gsub('([^%w])', '%%%1')
    local stem, extension = fileName:match('^(.+)%.([^.]+)$')
    if (extension ~= 'png' and extension ~= 'webp')
        or (stem ~= safeModel and not tostring(stem):match('^' .. escapedModel .. '_%d+_%d+$')) then
        return nil
    end
    return ('%s/%s'):format(folder, fileName)
end

local function removeResourceImage(relativePath)
    if not relativePath or relativePath == '' then return false end
    local fullPath = ('%s/%s'):format(GetResourcePath(GetCurrentResourceName()), relativePath)
    local ok, removed = pcall(os.remove, fullPath)
    return ok and removed == true
end

local function removeUnreferencedVehicleImage(nuiPath, folder, model)
    local relativePath = resourceImagePathFromNui(nuiPath, folder, model)
    if not relativePath then return false end
    local lookupOk, result = pcall(function()
        return MySQL.scalar.await('SELECT COUNT(*) FROM cm_vehicle_catalog WHERE image = ? AND model <> ?', { nuiPath, model })
    end)
    if not lookupOk then return false end
    local references = tonumber(result) or 0
    if references > 0 then return false end
    return removeResourceImage(relativePath)
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
    if AdminModes[src] ~= 'capture' and AdminModes[src] ~= 'manage' then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'wrong_admin_mode')
        return notify(src, 'Open vehicle admin or manage vehicle to capture images.', 'error')
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
    local lookupOk, existingCatalog = pcall(function()
        return MySQL.single.await('SELECT image FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { model })
    end)
    if not lookupOk then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'database_read_failed')
        return notify(src, 'Could not read the current vehicle image. No file was written.', 'error')
    end

    -- Stage every capture under a unique name. The database transaction either
    -- adopts this exact path or the staged file is removed immediately.
    ImageCaptureSequence = (ImageCaptureSequence + 1) % 1000000
    local fileName = ('%s_%d_%06d.%s'):format(safeFilePart(model), os.time(), ImageCaptureSequence, ext)
    local savePath = ('%s/%s'):format(folder, fileName)
    if not SaveResourceFile(GetCurrentResourceName(), savePath, bytes, #bytes) then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'save_file_failed')
        return notify(src, 'Could not save vehicle image. Create the ui/images/vehicles folder and check write permission.', 'error')
    end

    -- nui path the UI can load directly: nui://<resource>/<folder>/<file>
    local nuiPath = ('nui://%s/%s/%s'):format(GetCurrentResourceName(), folder, fileName)

    -- Adopt the staged path atomically in the catalog (creating a hidden row
    -- when required). A failed transaction cannot leave an orphaned new file.
    local dbOk, committed = pcall(function()
        return MySQL.transaction.await({ {
            query = [[
            INSERT INTO cm_vehicle_catalog (model, label, category, price, trunk_level, available_store, available_server, image, vehicle_type)
            VALUES (?, ?, ?, 0, 1, 0, 0, ?, ?)
            ON DUPLICATE KEY UPDATE image = VALUES(image), vehicle_type = VALUES(vehicle_type)
            ]],
            values = { model, safeUtf8Sub(data.label, 100, model), safeUtf8Sub(data.category, 64, 'Custom'), nuiPath, normalizeVehicleType(data.vehicleType or data.vehicle_type) }
        } })
    end)
    if not dbOk or committed ~= true then
        local stagedFileRemoved = removeResourceImage(savePath)
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'database_write_failed')
        structuredAdminLog('image_capture', 'save_failed', src, { model=model, stage='database', stagedFileRemoved=stagedFileRemoved }, 'error')
        return notify(src, 'Vehicle image database update failed. The staged file was removed.', 'error')
    end

    local previousImage = existingCatalog and existingCatalog.image or nil
    if previousImage and tostring(previousImage) ~= nuiPath then
        removeUnreferencedVehicleImage(previousImage, folder, model)
    end
    -- Clean legacy canonical files left by the previous model.ext writer when
    -- their format differs from the newly committed capture.
    for _, legacyExt in ipairs({ 'png', 'webp' }) do
        local legacyName = ('%s.%s'):format(safeFilePart(model), legacyExt)
        if legacyName ~= fileName then
            local legacyNuiPath = ('nui://%s/%s/%s'):format(GetCurrentResourceName(), folder, legacyName)
            removeUnreferencedVehicleImage(legacyNuiPath, folder, model)
        end
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

-- Not gated by store/server visibility: an EMS, police, org, or otherwise
-- non-public catalog entry can still be flagged for CarPlay by an admin in
-- Manage Vehicles, and owned/spawned instances of it should still qualify.
exports('IsCarplayModel', function(model)
    local row = getCatalogVehicle(model, false)
    return row ~= nil and row.hasCarplay == true
end)

-- Same check by model HASH instead of a DB-owned vehicle's model string --
-- works for ANY vehicle of a flagged model (test drives, showroom previews,
-- admin/trainer spawns), not just ones with a cm_owned_vehicles row.
exports('IsCarplayModelHash', function(modelHash)
    modelHash = normalizeModelHash(modelHash)
    if not modelHash then return false end
    loadCatalogCache(false)
    return CatalogCache.carplayModelHashes and CatalogCache.carplayModelHashes[modelHash] == true
end)

local function restoreTemporaryModelReplacement(src, model, catalogRow, replacement)
    if tostring(replacement.status or '') ~= 'temporary' then
        if tostring(replacement.status or '') == 'permanent' then
            return false, 'This model was permanently removed and cannot be restored from Manage Vehicles.'
        end
        return false, 'This is a legacy replacement with no safe owner mapping. It was not changed.'
    end
    if not OwnedVehicleHasStoredColumn then
        return false, 'cm_owned_vehicles.is_stored is required for safe model restoration. Update cm-vehicles first.'
    end

    local oldModel = normalizeModel(model)
    local newModel = normalizeModel(replacement.new_model)
    if not truthy(catalogRow.retired) or normalizeModel(catalogRow.replacement_model) ~= newModel then
        return false, 'The catalog replacement state changed. Refresh Manage Vehicles and try again.'
    end
    local snapshot = decode(replacement.old_catalog)
    local ownedRows = MySQL.query.await([[
        SELECT id, model, is_stored, metadata
        FROM cm_owned_vehicles
        WHERE model IN (?, ?)
        ORDER BY id ASC
    ]], { oldModel, newModel }) or {}
    local operations = {
        {
            query = [[
                UPDATE cm_vehicle_catalog
                SET available_store = ?, available_server = ?, available_ems = ?, available_police = ?,
                    legal_org = ?, gang_id = ?, has_carplay = ?, retired = 0, replacement_model = NULL
                WHERE model = ? AND retired = 1 AND replacement_model = ?
            ]],
            values = {
                truthy(snapshot.available_store) and 1 or 0,
                truthy(snapshot.available_server) and 1 or 0,
                truthy(snapshot.available_ems) and 1 or 0,
                truthy(snapshot.available_police) and 1 or 0,
                snapshot.legal_org, snapshot.gang_id, truthy(snapshot.has_carplay) and 1 or 0, oldModel, newModel
            }
        },
        {
            -- Cancel every forward migration for this replacement first. Active
            -- Komoda instances that genuinely need a reverse migration are
            -- inserted again below with the direction swapped.
            query = 'DELETE FROM cm_vehicle_replacement_pending WHERE replacement_id = ?',
            values = { tonumber(replacement.id) }
        }
    }
    local restoredNow = 0
    local restorePending = 0
    local cancelledForward = 0

    for _, row in ipairs(ownedRows) do
        local metadata = decode(row.metadata)
        local originalModel = normalizeModel(metadata.replacementOriginalModel)
        if originalModel == oldModel and metadata.replacementType == 'temporary' then
            local vehicleId = tonumber(row.id)
            local currentModel = normalizeModel(row.model)
            if currentModel == oldModel then
                operations[#operations + 1] = {
                    query = [[
                        UPDATE cm_owned_vehicles
                        SET metadata = JSON_REMOVE(COALESCE(metadata, '{}'),
                            '$.vehicleNotice', '$.replacementType', '$.permanentlyRemoved',
                            '$.replacementOriginalModel', '$.replacementOriginalImage')
                        WHERE id = ? AND model = ?
                    ]],
                    values = { vehicleId, oldModel }
                }
                operations[#operations + 1] = {
                    query = 'DELETE FROM cm_vehicle_replacement_pending WHERE vehicle_id = ?',
                    values = { vehicleId }
                }
                cancelledForward = cancelledForward + 1
            elseif currentModel == newModel then
                local stored = tonumber(row.is_stored) == 1 or row.is_stored == true
                if stored then
                    operations[#operations + 1] = {
                        query = [[
                            UPDATE cm_owned_vehicles
                            SET model = ?, metadata = JSON_REMOVE(COALESCE(metadata, '{}'),
                                '$.vehicleNotice', '$.replacementType', '$.permanentlyRemoved',
                                '$.replacementOriginalModel', '$.replacementOriginalImage')
                            WHERE id = ? AND model = ? AND is_stored = 1
                        ]],
                        values = { oldModel, vehicleId, newModel }
                    }
                    operations[#operations + 1] = {
                        query = 'DELETE FROM cm_vehicle_replacement_pending WHERE vehicle_id = ?',
                        values = { vehicleId }
                    }
                    restoredNow = restoredNow + 1
                else
                    operations[#operations + 1] = {
                        query = [[
                            UPDATE cm_owned_vehicles
                            SET metadata = JSON_SET(COALESCE(metadata, '{}'),
                                '$.vehicleNotice', ?, '$.replacementType', 'restoring', '$.permanentlyRemoved', false)
                            WHERE id = ? AND model = ?
                        ]],
                        values = { 'The original vehicle model is restored. Store this vehicle once to finish the update.', vehicleId, newModel }
                    }
                    operations[#operations + 1] = {
                        query = [[
                            INSERT INTO cm_vehicle_replacement_pending (vehicle_id, replacement_id, old_model, new_model)
                            VALUES (?, ?, ?, ?)
                            ON DUPLICATE KEY UPDATE replacement_id = VALUES(replacement_id), old_model = VALUES(old_model), new_model = VALUES(new_model)
                        ]],
                        values = { vehicleId, tonumber(replacement.id), newModel, oldModel }
                    }
                    restorePending = restorePending + 1
                end
            end
        end
    end

    operations[#operations + 1] = {
        query = "UPDATE cm_vehicle_replacements SET status = 'restored' WHERE id = ? AND status = 'temporary'",
        values = { tonumber(replacement.id) }
    }
    local ok, result = pcall(function() return MySQL.transaction.await(operations) end)
    if not ok or result ~= true then
        return false, 'Restore was not applied. No catalog or vehicle data was changed.'
    end
    cleanupCompletedReplacementRecords()

    structuredAdminLog('catalog', 'temporary_model_restored', src, {
        oldModel = oldModel, replacementModel = newModel, restoredNow = restoredNow,
        restorePending = restorePending, cancelledForward = cancelledForward,
        capturedImage = catalogRow.image
    }, 'success')
    return true, ('Restored %s. %d vehicle(s) restored now, %d waiting to be stored.'):format(oldModel, restoredNow, restorePending)
end

RegisterNetEvent('rn-vehicleshop:server:enableAdminVehicle', function(model)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    if AdminModes[src] ~= 'manage' then return notify(src, 'Use /managevehicle first.', 'error') end
    if not checkRateLimit(src, 'enableAdminVehicle', tonumber(hardeningCfg().AdminSaveCooldownMs) or 1500) then
        return notify(src, 'Please wait before restoring another vehicle.', 'error')
    end
    model = normalizeModel(model)
    if not isValidModelName(model) then return notify(src, 'Invalid model.', 'error') end

    local catalogRow = MySQL.single.await('SELECT * FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { model })
    if not catalogRow then return notify(src, 'Vehicle was not found in the catalog.', 'error') end
    if not catalogRow.image or tostring(catalogRow.image):match('^%s*$') then
        return notify(src, 'Capture a valid vehicle image before enabling this model.', 'error')
    end

    local replacement = MySQL.single.await([[
        SELECT id, new_model, old_catalog, status
        FROM cm_vehicle_replacements
        WHERE old_model = ? AND status <> 'restored'
        LIMIT 1
    ]], { model })
    local success
    local message
    if replacement then
        success, message = restoreTemporaryModelReplacement(src, model, catalogRow, replacement)
    else
        MySQL.update.await('UPDATE cm_vehicle_catalog SET retired = 0, replacement_model = NULL, available_server = 1 WHERE model = ?', { model })
        structuredAdminLog('catalog', 'vehicle_enabled', src, { model = model, capturedImage = catalogRow.image }, 'success')
        success, message = true, ('Enabled %s with its new image.'):format(model)
    end
    notify(src, message, success and 'success' or 'error')
    if not success then return end

    invalidateCatalogCache()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, flattenSourceVehicles(), getCatalog(true), adminMeta())
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

-- Read-only, tag-agnostic catalog lookup: appearance (label/category/image/
-- mods) for ANY saved catalog vehicle, regardless of its current Store/
-- Server/EMS/Police/legal-org/gang status. Fleet-tab consumers (cm-law's
-- police and generic legal-org modules) use this as a fallback so a vehicle
-- granted straight to an organization (never tag-toggled in /vehicleadmin)
-- can still render in that org's Fleet/Motor Pool list -- a model's public
-- Store/Server availability is intentionally untouched by an org grant, so
-- the Fleet list can no longer assume every one of its vehicles is tagged.
exports('GetVehicleCatalogInfo', function(model)
    local row = getCatalogVehicle(model, false)
    if not row then return nil end
    return { model = row.model, label = row.label, category = row.category, image = row.image, mods = row.mods or {} }
end)

exports('GiveCatalogVehicle', function(src, model, metadata)
    local catalog = getCatalogVehicle(model, true)
    if not catalog then return false, 'Vehicle is not enabled in catalog.' end
    local okExport, createOk, vehicleData = callExport('cm-vehicles', 'CreateOwnedVehicle', src, catalog.model, catalog.label, catalog.trunkLevel, metadata or { source = 'catalog_export' })
    if not okExport or createOk ~= true then
        return false, vehicleData or createOk or 'CreateOwnedVehicle failed.'
    end
    return true, vehicleData
end)

exports('ConsumeOrganizationVehicleGrant', function(src, model, organization)
    src, model, organization = tonumber(src), normalizeModel(model), tostring(organization or ''):lower()
    if not src or src <= 0 then return false, 'invalid_actor_source' end
    local pending = PendingOrganizationGrants[src]
    if not pending then
        local consumedAt = ConsumedOrganizationGrants[src]
        if consumedAt and consumedAt >= os.time() then return false, 'authorization_already_consumed' end
        return false, 'authorization_missing'
    end
    if pending.expiresAt < os.time() then
        PendingOrganizationGrants[src] = nil
        return false, 'authorization_expired'
    end
    if pending.model ~= model or pending.organization ~= organization then
        PendingOrganizationGrants[src] = nil
        return false, 'authorization_mismatch'
    end
    PendingOrganizationGrants[src] = nil
    ConsumedOrganizationGrants[src] = os.time() + 5
    return true
end)

RegisterNetEvent('rn-vehicleshop:server:grantOrganizationVehicle', function(model, organization, minimumTier, trunkMinimumTier, requestId)
    local src = source
    requestId = adminRequestId(requestId)
    local function grantResult(result, message, kind)
        result = type(result) == 'table' and result or { ok=false, reason='unknown_error' }
        result.requestId = requestId
        result.message = tostring(message or '')
        TriggerClientEvent('rn-vehicleshop:client:organizationGrantResult', src, result)
        if message and message ~= '' then notify(src, message, kind or (result.ok and 'success' or 'error')) end
        return result.ok == true
    end
    if not isAdmin(src) then return grantResult({ok=false,stage='permission',reason='permission_denied'}, 'No permission.', 'error') end
    if AdminModes[src] ~= 'manage' then return grantResult({ok=false,stage='validation',reason='wrong_admin_mode'}, 'Use /managevehicle to give organization vehicles.', 'error') end
    if not checkRateLimit(src, 'grantOrganizationVehicle', 1500) then return grantResult({ok=false,stage='validation',reason='rate_limited'}, 'Please wait before giving another vehicle.', 'error') end
    model, organization = normalizeModel(model), tostring(organization or ''):lower():gsub('[^a-z0-9_]', '')
    minimumTier = math.max(1, math.min(100, math.floor(tonumber(minimumTier) or 1)))
    trunkMinimumTier = math.max(1, math.min(100, math.floor(tonumber(trunkMinimumTier) or minimumTier)))
    local allowed = { police=true, ems=true, marabunta=true, bloods=true, ballas=true, families=true, vagos=true }
    for _, org in ipairs(legalOrgOptions()) do allowed[tostring(org.id)] = true end
    if not allowed[organization] then return grantResult({ok=false,stage='validation',reason='invalid_organization'}, 'Invalid organization.', 'error') end
    local vehicle = getCatalogVehicle(model, false)
    if not vehicle then return grantResult({ok=false,stage='validation',reason='vehicle_not_saved'}, 'Vehicle is not saved in Vehicle Manage.', 'error') end
    local activeReplacement = MySQL.scalar.await([[
        SELECT 1 FROM cm_vehicle_replacements
        WHERE old_model = ? AND status <> 'restored'
        LIMIT 1
    ]], { model })
    if vehicle.retired == true or activeReplacement then
        return grantResult({ok=false,stage='validation',reason='vehicle_retired'}, 'Retired or replaced vehicles cannot be granted to an organization.', 'error')
    end
    if GetResourceState('cm-vehicles') ~= 'started' then
        return grantResult({ok=false,stage='persistent_preflight',reason='vehicle_owner_unavailable'}, 'Vehicle owner service is unavailable.', 'error')
    end
    local gangTargets={marabunta=true,bloods=true,ballas=true,families=true,vagos=true}
    local legalOrgTargets={}
    for _, org in ipairs(legalOrgOptions()) do legalOrgTargets[tostring(org.id)] = true end
    if gangTargets[organization] and GetResourceState('cm-gang') ~= 'started' then
        structuredAdminLog('organization_vehicle', 'grant_failed', src, {
            model=model,organization=organization,stage='fleet_preflight',error='fleet_owner_unavailable'
        }, 'error')
        return grantResult({ok=false,stage='fleet_preflight',reason='fleet_owner_unavailable'},
            'Gang fleet service is unavailable. No vehicle was created.', 'error')
    end
    structuredAdminLog('organization_vehicle', 'grant_requested', src, {model=model,organization=organization,stage='authorization'}, 'info')
    PendingOrganizationGrants[src] = { model=vehicle.model, organization=organization, expiresAt=os.time()+5 }
    structuredAdminLog('organization_vehicle', 'authorization_granted', src, {model=model,organization=organization,stage='authorization'}, 'success')
    local request = {
        actorSource=tonumber(src), organizationId=organization, model=vehicle.model,
        label=vehicle.label or vehicle.model, trunkLevel=tonumber(vehicle.trunkLevel) or 1,
        metadata={catalogModel=vehicle.model}
    }
    structuredAdminLog('organization_vehicle', 'persistent_request', src, {
        actorSource=request.actorSource, model=request.model, organization=request.organizationId,
        trunkLevel=request.trunkLevel, metadataType=type(request.metadata), stage='persistent_validation'
    }, 'info')
    local called, created, result = pcall(function()
        return exports['cm-vehicles']:CreateOrganizationVehicle(request)
    end)
    PendingOrganizationGrants[src] = nil
    if not called or created ~= true or type(result) ~= 'table' or not tonumber(result.id) then
        local reason = not called and ('export_error:' .. tostring(created)) or tostring(result or created)
        local stage = reason:find('authorization_', 1, true) == 1 and 'authorization' or 'persistent_validation'
        if reason == 'database_insert_failed' then stage = 'persistent_creation' end
        structuredAdminLog('organization_vehicle', 'grant_failed', src, {model=model,organization=organization,stage=stage,error=reason}, 'error')
        return grantResult({ok=false,stage=stage,reason=reason}, 'Organization vehicle creation failed.', 'error')
    end
    local vehicleId=tonumber(result.id)
    structuredAdminLog('organization_vehicle', 'persistent_created', src, {model=model,organization=organization,vehicleId=vehicleId}, 'success')
    local fleetStatus='not_applicable'
    if gangTargets[organization] then
        local linkCalled,linked,linkResult=pcall(function()
            return exports['cm-gang']:LinkGrantedOrganizationVehicle(src,organization,model,vehicleId,minimumTier,trunkMinimumTier)
        end)
        if not linkCalled or linked~=true then
            fleetStatus=tostring(linkResult or linked or 'fleet_link_failed')
            local rollbackCalled,rolledBack,rollbackReason=pcall(function()
                return exports['cm-gang']:RollbackGrantedOrganizationVehicle(src,organization,model,vehicleId)
            end)
            local rollbackOk=rollbackCalled and rolledBack==true
            local rollbackError=rollbackOk and nil or tostring(rollbackReason or rolledBack or 'rollback_failed')
            structuredAdminLog('organization_vehicle','fleet_link_failed',src,{
                model=model,organization=organization,vehicleId=vehicleId,stage='fleet_link',error=fleetStatus,
                rolledBack=rollbackOk,rollbackError=rollbackError
            },rollbackOk and 'warning' or 'error')
            local failureResult={
                ok=false,partial=not rollbackOk,organization=organization,model=model,label=vehicle.label,
                vehicleId=rollbackOk and nil or vehicleId,stage='fleet_link',reason=fleetStatus,
                rolledBack=rollbackOk,rollbackError=rollbackError,recoveryRequired=not rollbackOk
            }
            if rollbackOk then
                return grantResult(failureResult, ('Gang fleet link failed (%s). The new vehicle was rolled back.'):format(fleetStatus), 'error')
            end
            return grantResult(failureResult, ('Gang fleet link and rollback failed for vehicle ID %d. Manual recovery is required.'):format(vehicleId), 'error')
        end
        fleetStatus=type(linkResult)=='table' and linkResult.status or 'needs_home_location'
        structuredAdminLog('organization_vehicle','fleet_linked',src,{model=model,organization=organization,vehicleId=vehicleId,status=fleetStatus},'success')
    elseif organization=='police' then
        -- No rollback path exists for Police (DeleteOrganizationVehicle is
        -- cm-gang-only), so a link failure here is reported as a warning,
        -- not an error: the grant already succeeded and the vehicle is a
        -- normal Police-owned vehicle either way, just not in the Fleet tab.
        local linkCalled,linked,linkResult=pcall(function()
            return exports['cm-law']:LinkGrantedPoliceFleetVehicle(src,model,vehicleId,minimumTier)
        end)
        if not linkCalled or linked~=true then
            fleetStatus=tostring(linkResult or linked or 'fleet_link_failed')
            structuredAdminLog('organization_vehicle','fleet_link_failed',src,{
                model=model,organization=organization,vehicleId=vehicleId,stage='fleet_link',error=fleetStatus
            },'warning')
            return grantResult({ok=true,partial=true,organization=organization,model=model,label=vehicle.label,
                vehicleId=vehicleId,stage='fleet_link',reason=fleetStatus},
                ('Gave %s to police (vehicle ID %d), but it could not be linked into the Fleet tab (%s). Configure it manually from the Fleet tab or /vehicleadmin.'):format(vehicle.label or model, vehicleId, fleetStatus), 'warning')
        end
        fleetStatus='linked'
        structuredAdminLog('organization_vehicle','fleet_linked',src,{model=model,organization=organization,vehicleId=vehicleId},'success')
    elseif legalOrgTargets[organization] then
        -- Same no-rollback tradeoff as the Police branch above: the grant
        -- already succeeded, so a link failure is a warning, not an error.
        local linkCalled,linked,linkResult=pcall(function()
            return exports['cm-law']:LinkGrantedFleetVehicle(src,organization,model,vehicleId,minimumTier)
        end)
        if not linkCalled or linked~=true then
            fleetStatus=tostring(linkResult or linked or 'fleet_link_failed')
            structuredAdminLog('organization_vehicle','fleet_link_failed',src,{
                model=model,organization=organization,vehicleId=vehicleId,stage='fleet_link',error=fleetStatus
            },'warning')
            return grantResult({ok=true,partial=true,organization=organization,model=model,label=vehicle.label,
                vehicleId=vehicleId,stage='fleet_link',reason=fleetStatus},
                ('Gave %s to %s (vehicle ID %d), but it could not be linked into the Motor Pool (%s). Configure it manually from Fleet Vehicles or /vehicleadmin.'):format(vehicle.label or model, organization, vehicleId, fleetStatus), 'warning')
        end
        fleetStatus='linked'
        structuredAdminLog('organization_vehicle','fleet_linked',src,{model=model,organization=organization,vehicleId=vehicleId},'success')
    end
    structuredAdminLog('organization_vehicle', 'granted', src, {model=model,organization=organization,vehicleId=vehicleId,plate=result.plate}, 'success')
    grantResult({ok=true,organization=organization,model=model,label=vehicle.label,vehicleId=vehicleId,status=fleetStatus},
        ('Gave %s to %s. Vehicle ID: %d'):format(vehicle.label or model, organization, vehicleId), 'success')
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
    ReplacementPollStarted = false
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
    processPendingModelReplacements()
    startReplacementPoller()
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
