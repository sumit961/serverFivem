-- cm-admin/server/main.lua
-- v2.6.4: character-ID based /admin mode + F11 NUI menu + role-based map/logs/permissions/dev tools/map calibration.
-- Security rule: the client can request actions, but the server checks every permission.

local AdminMode = {}
local Cooldowns = {}
local CharacterCache = {}
local BootReady = false

local function jenc(value)
    return json.encode(value or {})
end

local function jdec(value, fallback)
    if type(value) == 'table' then return value end
    if not value or value == '' then return fallback or {} end
    local ok, decoded = pcall(json.decode, value)
    if ok and decoded then return decoded end
    return fallback or {}
end

local SavedMapBounds = nil

local function normalizeMapBounds(bounds)
    if type(bounds) ~= 'table' then return nil end
    local minX = tonumber(bounds.minX)
    local maxX = tonumber(bounds.maxX)
    local minY = tonumber(bounds.minY)
    local maxY = tonumber(bounds.maxY)
    if not minX or not maxX or not minY or not maxY then return nil end
    if maxX <= minX or maxY <= minY then return nil end
    if math.abs(minX) > 20000 or math.abs(maxX) > 20000 or math.abs(minY) > 20000 or math.abs(maxY) > 20000 then return nil end
    return {
        minX = math.floor(minX + 0.5),
        maxX = math.floor(maxX + 0.5),
        minY = math.floor(minY + 0.5),
        maxY = math.floor(maxY + 0.5)
    }
end

local function configuredMapBounds()
    return normalizeMapBounds(Config.Map and Config.Map.Bounds) or { minX = -4000, maxX = 4500, minY = -4300, maxY = 8000 }
end

local function mapBoundsFile()
    return (Config.Map and Config.Map.SavedBoundsFile) or 'data/map_bounds.json'
end

local function loadSavedMapBounds()
    if Config.Map and Config.Map.UseSavedBounds == false then
        SavedMapBounds = nil
        return nil
    end
    local raw = LoadResourceFile(GetCurrentResourceName(), mapBoundsFile())
    SavedMapBounds = normalizeMapBounds(jdec(raw, nil))
    return SavedMapBounds
end

local function effectiveMapBounds()
    if Config.Map and Config.Map.UseSavedBounds ~= false then
        if not SavedMapBounds then loadSavedMapBounds() end
        if SavedMapBounds then return SavedMapBounds, 'saved' end
    end
    return configuredMapBounds(), 'config'
end

local function saveMapBounds(bounds)
    bounds = normalizeMapBounds(bounds)
    if not bounds then return false, 'Invalid map bounds.' end
    SavedMapBounds = bounds
    local ok = SaveResourceFile(GetCurrentResourceName(), mapBoundsFile(), json.encode(bounds, { indent = true }), -1)
    return ok == true, ok == true and nil or 'Could not save map bounds file.'
end

local function notify(src, msg, msgType)
    if src and src > 0 then
        TriggerClientEvent('cm-admin:client:notify', src, msg, msgType or 'info')
    end
end

local function normalizeIdentifier(identifier)
    if not identifier then return nil end
    identifier = tostring(identifier):lower():gsub('^identifier%.', '')
    return identifier
end

local function identifierWithPrefix(identifier)
    identifier = normalizeIdentifier(identifier)
    if not identifier then return nil end
    return 'identifier.' .. identifier
end

local function getIdentifiers(src)
    local ids = {}
    if not src or src <= 0 then return ids end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        local clean = normalizeIdentifier(id)
        if clean then ids[#ids + 1] = clean end
    end
    return ids
end

local function hasIdentifier(src, wanted)
    wanted = normalizeIdentifier(wanted)
    if not wanted then return false end
    for _, id in ipairs(getIdentifiers(src)) do
        if id == wanted then return true end
    end
    return false
end

local function getPrimaryIdentifier(src)
    local ids = getIdentifiers(src)
    local fallback = ids[1]
    for _, id in ipairs(ids) do
        if id:find('^license:') then return id end
    end
    for _, id in ipairs(ids) do
        if id:find('^fivem:') then return id end
    end
    return fallback
end

local function normalizeCharacterId(value)
    if value == nil then return nil end
    local charId = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
    if charId == '' then return nil end
    return charId
end

local function adminKeyForCharacterId(charId)
    charId = normalizeCharacterId(charId)
    if not charId then return nil end
    return 'char:' .. charId
end

local function isConfiguredOwnerCharacter(charId)
    charId = normalizeCharacterId(charId)
    if not charId then return false end
    for _, ownerCharId in ipairs(Config.OwnerCharacterIds or {}) do
        if normalizeCharacterId(ownerCharId) == charId then return true end
    end
    return false
end

local function hasAceBootstrap(src)
    if src <= 0 then return true end
    if not Config.AllowAceAdminBootstrap then return false end
    local ace = Config.AdminAce or 'cm.admin'
    return IsPlayerAceAllowed(src, ace) or IsPlayerAceAllowed(src, 'cm.admin')
end

local function safeQuery(sql, params)
    if not MySQL or not MySQL.query or not MySQL.query.await then return false, {} end
    local ok, result = pcall(MySQL.query.await, sql, params or {})
    if not ok then
        return false, result
    end
    return true, result or {}
end

local function safeSingle(sql, params)
    if not MySQL or not MySQL.single or not MySQL.single.await then
        local ok, rows = safeQuery(sql, params)
        return ok, rows and rows[1] or nil
    end
    local ok, result = pcall(MySQL.single.await, sql, params or {})
    if not ok then return false, result end
    return true, result
end

local function safeUpdate(sql, params)
    if not MySQL or not MySQL.update or not MySQL.update.await then
        return safeQuery(sql, params)
    end
    local ok, result = pcall(MySQL.update.await, sql, params or {})
    if not ok then return false, result end
    return true, result
end

local function getRank(rankName)
    rankName = tostring(rankName or 'moderator'):lower()
    local ok, row = safeSingle('SELECT rank_name, label, level, permissions_json FROM cm_admin_ranks WHERE rank_name = ? LIMIT 1', { rankName })
    if ok and row then
        return {
            name = row.rank_name,
            label = row.label,
            level = tonumber(row.level) or 0,
            permissions = jdec(row.permissions_json, {})
        }
    end

    local fallback = Config.DefaultRanks and Config.DefaultRanks[rankName]
    if fallback then
        return {
            name = rankName,
            label = fallback.label or rankName,
            level = tonumber(fallback.level) or 0,
            permissions = fallback.permissions or {}
        }
    end

    return nil
end

local function activeBool(value)
    return value == true or value == 1 or value == '1' or value == 'true'
end

local function permissionListAllows(list, permission)
    if not list then return false end
    for _, p in ipairs(list) do
        if p == '*' or p == permission then return true end
    end
    return false
end

local getStateCharacterId
local getCharacterInfo

local function getAdminRowByIdentifier(identifier)
    identifier = normalizeIdentifier(identifier)
    if not identifier then return nil end
    local ok, row = safeSingle([[SELECT identifier, character_id, account_identifier, name, rank_name, active, added_by, created_at
        FROM cm_admins WHERE identifier = ? LIMIT 1]], { identifier })
    if ok and row then return row end
    return nil
end

local function getAdminRowByCharacterId(charId)
    charId = normalizeCharacterId(charId)
    if not charId then return nil end
    local key = adminKeyForCharacterId(charId)
    local ok, row = safeSingle([[SELECT identifier, character_id, account_identifier, name, rank_name, active, added_by, created_at
        FROM cm_admins WHERE character_id = ? OR identifier = ? LIMIT 1]], { charId, key })
    if ok and row then return row end
    return nil
end

local function getAdminRowForSource(src)
    if src <= 0 then
        return { identifier = 'console', character_id = 'console', account_identifier = 'console', name = 'console', rank_name = 'owner', active = 1 }
    end

    local charId = getStateCharacterId and normalizeCharacterId(getStateCharacterId(src)) or nil
    local char = { id = charId, name = CharacterCache[src] and CharacterCache[src].name or nil }

    -- IMPORTANT: admin access is based on the selected character id, not account/license.
    if not charId then
        return nil
    end

    local row = getAdminRowByCharacterId(charId)
    if row then return row end

    if isConfiguredOwnerCharacter(charId) then
        return {
            identifier = adminKeyForCharacterId(charId),
            character_id = charId,
            account_identifier = getPrimaryIdentifier(src),
            name = char.name or GetPlayerName(src) or ('Character ' .. charId),
            rank_name = 'owner',
            active = 1,
            bootstrap = true
        }
    end

    -- Optional development fallback. If enabled, ACE grants admin to the current character only.
    if hasAceBootstrap(src) then
        return {
            identifier = adminKeyForCharacterId(charId),
            character_id = charId,
            account_identifier = getPrimaryIdentifier(src),
            name = char.name or GetPlayerName(src) or ('Character ' .. charId),
            rank_name = 'headadmin',
            active = 1,
            bootstrap = true
        }
    end

    return nil
end

local function getAdminProfile(src)
    local row = getAdminRowForSource(src)
    if not row or not activeBool(row.active) then return nil end
    local rank = getRank(row.rank_name)
    if not rank then return nil end
    return {
        identifier = normalizeIdentifier(row.identifier),
        characterId = normalizeCharacterId(row.character_id),
        accountIdentifier = normalizeIdentifier(row.account_identifier),
        name = row.name or GetPlayerName(src) or 'Admin',
        rank = rank,
        bootstrap = row.bootstrap == true
    }
end

local function hasPermission(src, permission, allowWithoutAdminMode)
    if src <= 0 then return true end
    if not allowWithoutAdminMode and not AdminMode[src] then return false end
    local profile = getAdminProfile(src)
    if not profile then return false end
    return permissionListAllows(profile.rank.permissions, permission)
end

local function actorLevel(src)
    local profile = getAdminProfile(src)
    return profile and profile.rank and profile.rank.level or 0
end

local function hasAnyPermission(src, permissions)
    for _, permission in ipairs(permissions or {}) do
        if hasPermission(src, permission) then return true end
    end
    return false
end

local function moneyAmountLimit()
    local limit = Config.AdminMoney and tonumber(Config.AdminMoney.MaxGiveCash) or 1000000
    if not limit or limit < 1 then limit = 1000000 end
    return math.floor(limit)
end

local function setOnlineCashState(target, cash, bank)
    local p = Player(target)
    if not p or not p.state then return end
    if cash ~= nil then pcall(function() p.state:set('cash', tonumber(cash) or 0, true) end) end
    if bank ~= nil then pcall(function() p.state:set('bank', tonumber(bank) or 0, true) end) end
end

local function formatMoney(amount)
    amount = tonumber(amount) or 0
    local left, num, right = tostring(math.floor(amount)):match('^([^%d]*%d)(%d*)(.-)$')
    return left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
end

local giveCashToOnlinePlayer

local function inferLogCategory(action, details)
    if type(details) == 'table' and details.category then return tostring(details.category) end
    action = tostring(action or ''):lower()
    if action:find('money') or action:find('cash') or action:find('bank') or action:find('economy') then return 'economy' end
    if action:find('inventory') or action:find('item') then return 'inventory' end
    if action:find('vehicle') or action:find('car') or action:find('plate') then return 'vehicles' end
    if action:find('dev') or action:find('tool') or action:find('climatime') then return 'dev' end
    if action:find('player') or action:find('freeze') or action:find('heal') or action:find('kick') or action:find('teleport') or action:find('noclip') or action:find('unstuck') then return 'players' end
    if action:find('rank') or action:find('admin') or action:find('menu') then return 'admin' end
    return 'system'
end

local function canViewLogCategory(src, category)
    category = tostring(category or 'system')
    if src <= 0 then return true end
    if not hasPermission(src, 'logs.view') then return false end
    if hasPermission(src, 'logs.all') then return true end
    return hasPermission(src, 'logs.' .. category)
end

local function getLogCategoriesForUi(src)
    local out = {}
    for _, category in ipairs(Config.LogCategories or {}) do
        if canViewLogCategory(src, category.id) then
            out[#out + 1] = { id = category.id, label = category.label or category.id, permission = category.permission }
        end
    end
    return out
end

local function logAction(src, action, data, targetIdentifier, targetName)
    data = data or {}
    local category = inferLogCategory(action, data)
    data.category = data.category or category
    local identifier = 'console'
    local name = 'console'

    if src and src > 0 then
        local char = getCharacterInfo and getCharacterInfo(src) or {}
        identifier = adminKeyForCharacterId(char.id) or getPrimaryIdentifier(src) or ('server:' .. src)
        name = char.name or GetPlayerName(src) or ('Player ' .. src)
        data.actorCharacterId = data.actorCharacterId or normalizeCharacterId(char.id)
    end

    if Config.QuietConsoleLogs ~= true then
        print(('[CM-ADMIN] %s (%s) -> %s %s'):format(name, src or 0, action, next(data) and jenc(data) or ''))
    end
    TriggerEvent('cm-admin:server:actionLogged', src, action, data)

    safeUpdate([[INSERT INTO cm_admin_logs (identifier, source, admin_name, action, target_identifier, target_name, details_json)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], {
        identifier,
        src,
        name,
        action,
        targetIdentifier or nil,
        targetName or nil,
        jenc(data)
    })
end

local function ensureSchema()
    safeUpdate([[CREATE TABLE IF NOT EXISTS cm_admin_ranks (
        rank_name VARCHAR(64) NOT NULL PRIMARY KEY,
        label VARCHAR(100) NOT NULL,
        level INT NOT NULL DEFAULT 0,
        permissions_json LONGTEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    safeUpdate([[CREATE TABLE IF NOT EXISTS cm_admins (
        identifier VARCHAR(128) NOT NULL PRIMARY KEY,
        character_id VARCHAR(64) NULL,
        account_identifier VARCHAR(128) NULL,
        name VARCHAR(100) NULL,
        rank_name VARCHAR(64) NOT NULL DEFAULT 'moderator',
        active TINYINT(1) NOT NULL DEFAULT 1,
        added_by VARCHAR(128) NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_character_id (character_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    -- Migration support if you already tested v2.0 before this character-id version.
    safeUpdate('ALTER TABLE cm_admins ADD COLUMN character_id VARCHAR(64) NULL AFTER identifier', {})
    safeUpdate('ALTER TABLE cm_admins ADD COLUMN account_identifier VARCHAR(128) NULL AFTER character_id', {})
    safeUpdate('ALTER TABLE cm_admins ADD INDEX idx_character_id (character_id)', {})

    safeUpdate([[CREATE TABLE IF NOT EXISTS cm_admin_logs (
        id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        identifier VARCHAR(128) NULL,
        source INT NULL,
        admin_name VARCHAR(100) NULL,
        action VARCHAR(128) NOT NULL,
        target_identifier VARCHAR(128) NULL,
        target_name VARCHAR(100) NULL,
        details_json LONGTEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_created_at (created_at),
        INDEX idx_action (action)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    for rankName, rank in pairs(Config.DefaultRanks or {}) do
        safeUpdate([[INSERT IGNORE INTO cm_admin_ranks (rank_name, label, level, permissions_json)
            VALUES (?, ?, ?, ?)]], {
            tostring(rankName):lower(),
            rank.label or rankName,
            tonumber(rank.level) or 0,
            jenc(rank.permissions or {})
        })
    end

    for _, ownerCharId in ipairs(Config.OwnerCharacterIds or {}) do
        local charId = normalizeCharacterId(ownerCharId)
        local key = adminKeyForCharacterId(charId)
        if key then
            safeUpdate([[INSERT INTO cm_admins (identifier, character_id, name, rank_name, active, added_by)
                VALUES (?, ?, ?, 'owner', 1, 'config')
                ON DUPLICATE KEY UPDATE character_id = VALUES(character_id), rank_name = 'owner', active = 1]], {
                key, charId, 'Bootstrap Owner Char ' .. charId
            })
        end
    end

    if Config.DisableLegacyIdentifierAdmins then
        safeUpdate([[UPDATE cm_admins SET active = 0
            WHERE (character_id IS NULL OR character_id = '') AND identifier NOT LIKE 'char:%']], {})
    end

    BootReady = true
    if Config.QuietConsoleLogs ~= true then print('[CM-ADMIN] v2.6 character-id schema ready') end
end

CreateThread(function()
    Wait(1000)
    ensureSchema()
end)

local function onCooldown(src, key, ms)
    local now = os.clock() * 1000
    Cooldowns[src] = Cooldowns[src] or {}
    if Cooldowns[src][key] and now - Cooldowns[src][key] < ms then return true end
    Cooldowns[src][key] = now
    return false
end

AddEventHandler('playerDropped', function()
    AdminMode[source] = nil
    Cooldowns[source] = nil
    CharacterCache[source] = nil
end)

local function ensureBootstrapAdmin(src)
    if src <= 0 then return end
    local profile = getAdminProfile(src)
    if profile and profile.bootstrap then
        safeUpdate([[INSERT INTO cm_admins (identifier, character_id, account_identifier, name, rank_name, active, added_by)
            VALUES (?, ?, ?, ?, ?, 1, 'bootstrap')
            ON DUPLICATE KEY UPDATE character_id = VALUES(character_id), account_identifier = VALUES(account_identifier), name = VALUES(name), active = 1]], {
            profile.identifier,
            profile.characterId,
            profile.accountIdentifier or getPrimaryIdentifier(src),
            profile.name,
            profile.rank.name
        })
    end
end

getStateCharacterId = function(src)
    local state = Player(src).state
    local candidates = {}
    local function add(value)
        if value and tostring(value) ~= '' then candidates[#candidates + 1] = value end
    end

    if CharacterCache[src] then
        add(CharacterCache[src].id)
    end

    add(state.charId)
    add(state.characterId)
    add(state.character_id)
    add(state.cid)
    add(state.citizenid)
    add(state.cm_charId)
    add(state.cmCharacterId)

    if type(state.character) == 'table' then
        add(state.character.id)
        add(state.character.charId)
        add(state.character.characterId)
    end

    if type(state.PlayerData) == 'table' then
        add(state.PlayerData.charId)
        add(state.PlayerData.characterId)
        add(state.PlayerData.citizenid)
    end

    for _, value in ipairs(candidates) do
        return value
    end
    return nil
end

getCharacterInfo = function(src)
    local charId = nil
    local name = nil

    -- Prefer cm-playerdata because it owns the selected character state and the
    -- same first/last name used by normal overhead player labels.
    if GetResourceState('cm-playerdata') == 'started' then
        pcall(function()
            if exports['cm-playerdata'] and exports['cm-playerdata'].GetCharacterId then
                charId = exports['cm-playerdata']:GetCharacterId(src)
            end
        end)
        pcall(function()
            if exports['cm-playerdata'] and exports['cm-playerdata'].GetCharacterFullName then
                name = exports['cm-playerdata']:GetCharacterFullName(src)
            end
        end)
    end

    charId = charId or getStateCharacterId(src)
    name = name or (CharacterCache[src] and CharacterCache[src].name or nil)

    -- Identity is statebag-driven/playerdata-driven. If this is nil the player
    -- simply has not fully selected/loaded a character yet.
    return { id = charId, name = name }
end

local function setAdminState(src, enabled, profile)
    if not src or src <= 0 then return end
    local p = Player(src)
    if not p or not p.state then return end

    if enabled then
        local char = getCharacterInfo(src)
        local rank = profile and profile.rank or nil
        local displayName = char.name or (profile and profile.name) or GetPlayerName(src) or ('Character ' .. tostring(char.id or '?'))
        local tag = {
            active = true,
            name = displayName,
            characterId = normalizeCharacterId(char.id or (profile and profile.characterId)),
            rank = rank and (rank.label or rank.name) or 'Admin',
            noclip = false
        }
        pcall(function() p.state:set('cm_admin_mode', true, true) end)
        pcall(function() p.state:set('cm_admin_noclip', false, true) end)
        pcall(function() p.state:set('cm_admin_tag', tag, true) end)
    else
        pcall(function() p.state:set('cm_admin_mode', false, true) end)
        pcall(function() p.state:set('cm_admin_noclip', false, true) end)
        pcall(function() p.state:set('cm_admin_tag', nil, true) end)
    end
end

local function cacheSelectedCharacter(src, payload, maybeName)
    src = tonumber(src)
    if not src or src <= 0 then return end

    local charId = nil
    local charName = maybeName

    if type(payload) == 'table' then
        charId = payload.id or payload.character_id or payload.charId or payload.characterId or payload.cid or payload.citizenid
        local first = payload.first_name or payload.firstname or payload.firstName
        local last = payload.last_name or payload.lastname or payload.lastName
        if not charName and (first or last) then
            charName = ((first or '') .. ' ' .. (last or '')):gsub('^%s+', ''):gsub('%s+$', '')
        end
        charName = charName or payload.name or payload.fullname
    else
        charId = payload
    end

    charId = normalizeCharacterId(charId)
    if not charId then return end

    CharacterCache[src] = { id = charId, name = charName }
    pcall(function() Player(src).state:set('cm_admin_charId', charId, true) end)
    if AdminMode[src] then
        setAdminState(src, true, getAdminProfile(src))
    end
end

-- Optional bridge event for your cm-characters/cm-spawn resource.
-- You can trigger this after character select: TriggerEvent('cm-admin:server:setCharacterId', source, charId, characterData)
RegisterNetEvent('cm-admin:server:setCharacterId', function(srcOrCharId, charData, extraCharData)
    local src = source
    local payload = srcOrCharId
    if (not src or src == 0) and tonumber(srcOrCharId) and tonumber(srcOrCharId) > 0 and charData ~= nil then
        src = tonumber(srcOrCharId)
        payload = charData
        if type(extraCharData) == 'table' then
            extraCharData.id = extraCharData.id or extraCharData.character_id or extraCharData.charId or charData
            payload = extraCharData
        end
    end
    cacheSelectedCharacter(src, payload)
end)

for _, eventName in ipairs(Config.CharacterLoadedEvents or {}) do
    AddEventHandler(eventName, function(a, b, c)
        local src = source
        local payload = a
        if (not src or src == 0) and tonumber(a) and tonumber(a) > 0 and b ~= nil then
            src = tonumber(a)
            payload = b
            if type(c) == 'table' then
                c.id = c.id or c.character_id or c.charId or b
                payload = c
            end
        end
        cacheSelectedCharacter(src, payload)
    end)
end

local function publicIdentifiers(src)
    local out = {}
    for _, id in ipairs(getIdentifiers(src)) do
        if id:find('^license:') or id:find('^fivem:') or id:find('^discord:') then
            out[#out + 1] = id
        end
    end
    return out
end

local function getPlayerSummary(target)
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return nil end
    local ped = GetPlayerPed(target)
    local coords = ped and ped ~= 0 and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
    local char = getCharacterInfo(target)
    -- Money: cm-playerdata replicates cash/bank statebags; DB fallback covers
    -- the window before first sync.
    local pstate = Player(target).state
    local cash, bank = pstate.cash, pstate.bank
    if (cash == nil or bank == nil) and char.id and Config.DatabaseBridge and Config.DatabaseBridge.MoneyQuery then
        local ok, row = safeSingle(Config.DatabaseBridge.MoneyQuery, { tostring(char.id) })
        if ok and row then
            cash = cash or row.cash
            bank = bank or row.bank
        end
    end

    local adminProfile = AdminMode[target] and getAdminProfile(target) or nil

    return {
        id = target,
        name = GetPlayerName(target),
        ping = GetPlayerPing(target),
        identifier = getPrimaryIdentifier(target),
        identifiers = publicIdentifiers(target),
        characterId = char.id,
        characterName = char.name,
        cash = tonumber(cash),
        bank = tonumber(bank),
        adminMode = AdminMode[target] == true,
        adminRank = adminProfile and adminProfile.rank and (adminProfile.rank.label or adminProfile.rank.name) or nil,
        coords = { x = math.floor(coords.x * 100) / 100, y = math.floor(coords.y * 100) / 100, z = math.floor(coords.z * 100) / 100 }
    }
end

local function getOnlinePlayers(viewerSrc)
    local players = {}

    -- Distance from the admin who is viewing: nearby players sort first.
    local viewerCoords = nil
    if viewerSrc then
        local viewerPed = GetPlayerPed(viewerSrc)
        if viewerPed and viewerPed ~= 0 then
            viewerCoords = GetEntityCoords(viewerPed)
        end
    end

    for _, src in ipairs(GetPlayers()) do
        local row = getPlayerSummary(tonumber(src))
        if row then
            if viewerCoords and row.coords and tonumber(src) ~= viewerSrc then
                local dx = row.coords.x - viewerCoords.x
                local dy = row.coords.y - viewerCoords.y
                local dz = row.coords.z - viewerCoords.z
                row.distance = math.floor(math.sqrt(dx * dx + dy * dy + dz * dz))
            elseif tonumber(src) == viewerSrc then
                row.distance = 0
                row.isSelf = true
            end
            players[#players + 1] = row
        end
    end

    table.sort(players, function(a, b)
        local da = a.distance or 999999
        local db = b.distance or 999999
        if da ~= db then return da < db end
        return a.id < b.id
    end)

    return players
end

local function getRanksForUi()
    local ranks = {}
    local ok, rows = safeQuery('SELECT rank_name, label, level, permissions_json FROM cm_admin_ranks ORDER BY level DESC, rank_name ASC', {})
    if ok then
        for _, row in ipairs(rows) do
            ranks[#ranks + 1] = {
                name = row.rank_name,
                label = row.label,
                level = tonumber(row.level) or 0,
                permissions = jdec(row.permissions_json, {})
            }
        end
    end
    return ranks
end

local function getAdminsForUi()
    local admins = {}
    local ok, rows = safeQuery([[SELECT identifier, character_id, account_identifier, name, rank_name, active, added_by, created_at
        FROM cm_admins ORDER BY created_at DESC]], {})
    if ok then
        for _, row in ipairs(rows) do
            admins[#admins + 1] = {
                identifier = row.identifier,
                characterId = row.character_id,
                accountIdentifier = row.account_identifier,
                name = row.name,
                rank = row.rank_name,
                active = activeBool(row.active),
                addedBy = row.added_by,
                createdAt = row.created_at
            }
        end
    end
    return admins
end

local function getLogsForUi(limit, viewerSrc)
    limit = tonumber(limit) or 80
    if limit < 1 then limit = 80 end
    if limit > 300 then limit = 300 end

    local logs = {}
    local fetchLimit = math.min(limit * 3, 600)
    local ok, rows = safeQuery(('SELECT id, identifier, source, admin_name, action, target_identifier, target_name, details_json, created_at FROM cm_admin_logs ORDER BY id DESC LIMIT %d'):format(fetchLimit), {})
    if ok then
        for _, row in ipairs(rows) do
            local details = jdec(row.details_json, {})
            local category = inferLogCategory(row.action, details)
            if canViewLogCategory(viewerSrc or 0, category) then
                logs[#logs + 1] = {
                    id = row.id,
                    identifier = row.identifier,
                    source = row.source,
                    adminName = row.admin_name,
                    action = row.action,
                    category = category,
                    targetIdentifier = row.target_identifier,
                    targetName = row.target_name,
                    details = details,
                    createdAt = row.created_at
                }
                if #logs >= limit then break end
            end
        end
    end
    return logs
end

local AllPermissions = {
    'menu.open',
    'players.view', 'players.manage', 'players.teleport', 'players.freeze', 'players.kick', 'money.manage',
    'inventory.view',
    'vehicles.view', 'vehicles.manage', 'vehicle_inventory.view',
    'admins.view', 'admins.manage',
    'ranks.view', 'ranks.manage',
    'logs.view', 'logs.all', 'logs.admin', 'logs.players', 'logs.economy', 'logs.inventory', 'logs.vehicles', 'logs.dev', 'logs.system',
    'map.view', 'map.vehicles', 'map.admins', 'map.teleport', 'map.calibrate', 'gps.teleport',
    'noclip', 'teleport', 'tools.heal',
    'dev.view', 'dev.tools', 'dev.clothing', 'dev.vehicles', 'dev.weapons', 'dev.climatime', 'dev.hud',
    'house.admin.open', 'house.create', 'house.admin.properties', 'house.admin.interiors',
    'house.admin.garages', 'house.admin.pricing', 'house.admin.photos', 'house.admin.recovery'
    ,'gang.admin.view', 'gang.admin.manage'
}

local function currentAdminUi(src)
    local profile = getAdminProfile(src)
    if not profile then return nil end
    return {
        source = src,
        name = GetPlayerName(src) or profile.name,
        identifier = profile.identifier,
        characterId = profile.characterId,
        accountIdentifier = profile.accountIdentifier,
        rank = profile.rank.name,
        rankLabel = profile.rank.label,
        level = profile.rank.level,
        permissions = profile.rank.permissions,
        adminMode = AdminMode[src] == true
    }
end

local function buildMenuPayload(src)
    local payload = {
        me = currentAdminUi(src),
        permissions = AllPermissions,
        players = {},
        admins = {},
        ranks = {},
        logs = {},
        logCategories = {},
        server = {
            name = GetConvar('sv_hostname', 'CM Server'),
            maxClients = GetConvarInt('sv_maxclients', 48),
            resource = GetCurrentResourceName(),
            mapBounds = effectiveMapBounds(),
            mapBoundsSource = select(2, effectiveMapBounds()),
            mapConfigBounds = configuredMapBounds(),
            mapAllowUiSave = Config.Map and Config.Map.AllowUiBoundsSave ~= false or false
        }
    }

    if hasPermission(src, 'players.view') then payload.players = getOnlinePlayers(src) end
    if CMDevTools then payload.devTools = CMDevTools.forPlayer(src) end
    if hasPermission(src, 'admins.view') then payload.admins = getAdminsForUi() end
    if hasPermission(src, 'ranks.view') then payload.ranks = getRanksForUi() end
    if hasPermission(src, 'logs.view') then payload.logs = getLogsForUi(80, src); payload.logCategories = getLogCategoriesForUi(src) end
    if hasPermission(src, 'orgs.view') and CMOrganizations then payload.orgs = CMOrganizations.forAdminPayload(src) end
    if hasPermission(src, 'gang.admin.view') and CMGangs then payload.gangs = CMGangs.payload(src) end

    return payload
end

local function refreshMenu(src)
    if src <= 0 then return end
    if not AdminMode[src] then return end
    TriggerClientEvent('cm-admin:client:updateMenu', src, buildMenuPayload(src))
end

-- ------------------------------------------------------------------
-- /admin mode and F11 menu
-- ------------------------------------------------------------------
RegisterCommand(Config.AdminToggleCommand or 'admin', function(src)
    if src <= 0 then
        print('[CM-ADMIN] Console is always admin.')
        return
    end

    if not BootReady then
        notify(src, 'Admin system is still loading. Try again in a moment.', 'error')
        return
    end

    local profile = getAdminProfile(src)
    if not profile then
        notify(src, 'This character is not an admin.', 'error')
        logAction(src, 'admin_mode_denied')
        return
    end

    ensureBootstrapAdmin(src)
    AdminMode[src] = not AdminMode[src]

    setAdminState(src, AdminMode[src], profile)

    if AdminMode[src] then
        notify(src, ('Admin mode enabled: %s'):format(profile.rank.label), 'success')
        logAction(src, 'admin_mode_on', { rank = profile.rank.name, characterId = profile.characterId })
    else
        notify(src, 'Admin mode disabled. You are now normal player again.', 'info')
        TriggerClientEvent('cm-admin:client:forceClose', src)
        TriggerClientEvent('cm-admin:client:disableNoclip', src)
        logAction(src, 'admin_mode_off')
    end
end, false)

RegisterNetEvent('cm-admin:server:requestOpenMenu', function()
    local src = source
    if not AdminMode[src] then
        notify(src, 'Type /admin first, then press F11.', 'error')
        return
    end
    if not hasPermission(src, 'menu.open') then
        notify(src, 'Your rank cannot open the admin menu.', 'error')
        logAction(src, 'menu_denied')
        return
    end
    TriggerClientEvent('cm-admin:client:openMenu', src, buildMenuPayload(src))
    logAction(src, 'menu_open')
end)

-- ------------------------------------------------------------------
-- Existing noclip / utility commands, now protected by admin mode/rank.
-- ------------------------------------------------------------------
local function requestToggle(src)
    if not hasPermission(src, 'noclip') then
        notify(src, 'Type /admin first or your rank has no noclip permission.', 'error')
        logAction(src, 'noclip_denied')
        return
    end
    logAction(src, 'noclip_toggle')
    TriggerClientEvent('cm-admin:client:toggleNoclip', src)
end

CreateThread(function()
    for _, commandName in ipairs(Config.Commands or {}) do
        RegisterCommand(commandName, function(src)
            requestToggle(src)
        end, false)
    end
end)

RegisterNetEvent('cm-admin:server:requestNoclipToggle', function()
    requestToggle(source)
end)

RegisterNetEvent('cm-admin:server:setNoclipState', function(enabled)
    local src = source
    enabled = enabled == true
    if not AdminMode[src] then enabled = false end
    if enabled and not hasPermission(src, 'noclip') then enabled = false end

    local p = Player(src)
    if not p or not p.state then return end

    pcall(function() p.state:set('cm_admin_noclip', enabled, true) end)

    local tag = p.state.cm_admin_tag
    if type(tag) == 'table' then
        tag.noclip = enabled
        if AdminMode[src] and tag.active == true then
            -- Refresh name/id from cm-playerdata in case the admin tag was created
            -- before playerdata finished hydrating the selected character.
            local char = getCharacterInfo(src)
            if char and char.name and char.name ~= '' and char.name ~= 'Unknown' then
                tag.name = char.name
            end
            if char and char.id then
                tag.characterId = normalizeCharacterId(char.id)
            end
            pcall(function() p.state:set('cm_admin_tag', tag, true) end)
        end
    end
end)

RegisterCommand('cmgivecash', function(src, args)
    if src <= 0 then return end
    if not AdminMode[src] then
        notify(src, 'Type /admin first before giving cash.', 'error')
        return
    end
    if not hasAnyPermission(src, { 'money.manage', 'players.manage' }) then
        notify(src, 'No permission: money.manage', 'error')
        return
    end

    local target = tonumber(args[1])
    local amount = tonumber(args[2])
    local reason = table.concat(args or {}, ' ', 3)
    local ok, message = giveCashToOnlinePlayer(src, target, amount, reason ~= '' and reason or 'Admin command cash grant')
    notify(src, message, ok and 'success' or 'error')
    if ok then refreshMenu(src) end
end, false)

RegisterCommand('cmtp', function(src)
    if src <= 0 then return end
    if not hasAnyPermission(src, { 'gps.teleport', 'teleport', 'players.teleport' }) then
        notify(src, 'Type /admin first or your rank has no GPS teleport permission.', 'error')
        logAction(src, 'gps_teleport_denied')
        return
    end
    if onCooldown(src, 'gpsTeleportCommand', 2000) then return end
    logAction(src, 'gps_teleport_command', { category = 'players' })
    TriggerClientEvent('cm-admin:client:teleportToWaypoint', src)
end, false)

RegisterCommand('kill', function(src)
    if src <= 0 then return end
    if not hasPermission(src, 'tools.kill') then
        notify(src, 'No permission: tools.kill', 'error')
        return
    end
    if onCooldown(src, 'selfKillCommand', 3000) then return end
    logAction(src, 'self_kill_test')
    TriggerClientEvent('cm-admin:client:kill', src)
end, false)

RegisterCommand('cmunstuck', function(src)
    if src <= 0 then return end
    local isAdmin = hasPermission(src, 'teleport')
    if not isAdmin then
        if not Config.AllowPlayerUnstuck then
            notify(src, 'You do not have permission to use this.', 'error')
            return
        end
        if onCooldown(src, 'unstuck', Config.UnstuckCooldown or 60000) then
            notify(src, 'Please wait before using unstuck again.', 'error')
            return
        end
    end
    logAction(src, 'unstuck')
    TriggerClientEvent('cm-admin:client:unstuck', src)
end, false)

local adminOnly = {
    cmstand = 'stand',
    cmup = 'moveUp',
    cmsafe = 'safeTeleport'
}

for command, clientAction in pairs(adminOnly) do
    RegisterCommand(command, function(src, args)
        if src <= 0 then return end
        if not hasPermission(src, 'teleport') then
            notify(src, 'Type /admin first or your rank has no teleport permission.', 'error')
            logAction(src, command .. '_denied')
            return
        end
        logAction(src, command, { args = args })
        TriggerClientEvent('cm-admin:client:' .. clientAction, src, args)
    end, false)
end

-- ------------------------------------------------------------------
-- Data bridge helpers
-- ------------------------------------------------------------------
local function paramsForMode(mode, playerInfo, extra)
    local charId = playerInfo and playerInfo.characterId
    local identifier = playerInfo and playerInfo.identifier
    if mode == 'charId' then return { charId or -1 } end
    if mode == 'identifier' then return { identifier or '' } end
    if mode == 'identifier2' then return { identifier or '', identifier or '' } end
    if mode == 'plate' then return { extra and extra.plate or '' } end
    if mode == 'plate2' then
        local plate = extra and extra.plate or ''
        return { 'vehicle:' .. plate, plate }
    end
    return {}
end

local function runBridgeQueries(queryList, playerInfo, extra)
    local result = { ok = false, source = nil, rows = {}, tried = {} }
    for _, item in ipairs(queryList or {}) do
        local ok, rows = safeQuery(item.sql, paramsForMode(item.mode, playerInfo, extra))
        result.tried[#result.tried + 1] = { label = item.label, ok = ok }
        if ok then
            result.ok = true
            result.source = item.label
            result.rows = rows or {}
            return result
        end
    end
    return result
end

local function targetInfoBySource(target)
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return nil end
    return getPlayerSummary(target)
end

local function sendDetail(src, detailType, data)
    TriggerClientEvent('cm-admin:client:detailResult', src, { type = detailType, data = data })
end

giveCashToOnlinePlayer = function(src, target, amount, reason)
    target = tonumber(target)
    amount = math.floor(tonumber(amount) or 0)
    reason = tostring(reason or 'Admin cash grant'):sub(1, 120)

    if not target or not GetPlayerName(target) then return false, 'Target player not found.' end
    if amount < 1 then return false, 'Cash amount must be more than 0.' end
    if amount > moneyAmountLimit() then
        return false, ('Max cash amount is $%s.'):format(formatMoney(moneyAmountLimit()))
    end
    if target == src and Config.AdminMoney and Config.AdminMoney.AllowSelfGiveCash == false then
        return false, 'Self cash grant is disabled in config.'
    end

    local player = getPlayerSummary(target)
    if not player or not player.characterId then
        return false, 'Target player has no selected character ID yet.'
    end

    local bridge = Config.DatabaseBridge or {}

    -- cm-playerdata is the authoritative owner of cash/bank for ONLINE players.
    -- It keeps an in-memory cache and periodically saves it to the DB, so writing
    -- straight to the DB here would be silently overwritten by that save loop and
    -- would never update the HUD. Always go through its export when it can serve
    -- this player; only fall back to a raw DB write when it cannot (offline/edge).
    local newCash, newBank = nil, nil
    local usedExport = false
    if GetResourceState('cm-playerdata') == 'started' then
        local ok, applied = pcall(function()
            return exports['cm-playerdata']:AddCash(target, amount, reason)
        end)
        if ok and applied == true then
            usedExport = true
            local okC, cash = pcall(function() return exports['cm-playerdata']:GetCash(target) end)
            local okB, bank = pcall(function() return exports['cm-playerdata']:GetBank(target) end)
            if okC then newCash = tonumber(cash) end
            if okB then newBank = tonumber(bank) end
        end
    end

    if not usedExport then
        -- Fallback: player not loaded in cm-playerdata. Write the DB directly.
        local addQuery = bridge.AddCashQuery or 'UPDATE characters SET cash = GREATEST(0, COALESCE(cash, 0) + ?) WHERE id = ?'
        local updateOk, affected = safeUpdate(addQuery, { amount, tostring(player.characterId) })
        if not updateOk then
            print(('[CM-ADMIN] Give cash DB error: %s'):format(tostring(affected)))
            return false, 'Could not update character cash in database.'
        end
        if type(affected) == 'number' and affected < 1 then
            return false, 'No character money row was updated.'
        end

        if bridge.MoneyQuery then
            local ok, row = safeSingle(bridge.MoneyQuery, { tostring(player.characterId) })
            if ok and row then
                newCash = tonumber(row.cash)
                newBank = tonumber(row.bank)
            end
        end
        setOnlineCashState(target, newCash, newBank)
    end

    if newCash == nil then newCash = (tonumber(player.cash) or 0) + amount end
    TriggerClientEvent('cm-admin:client:notify', target, ('You received $%s cash from admin.'):format(formatMoney(amount)), 'success')

    logAction(src, 'money_give_cash', {
        target = target,
        characterId = player.characterId,
        amount = amount,
        newCash = newCash,
        reason = reason
    }, player.identifier, player.name)

    return true, ('Gave $%s cash to %s. New cash: $%s'):format(formatMoney(amount), player.name or ('ID ' .. target), formatMoney(newCash))
end

-- ------------------------------------------------------------------
-- NUI actions
-- ------------------------------------------------------------------
local ActionCooldowns = {}
local function onActionCooldown(src, key, ms)
    local now = os.clock() * 1000
    ActionCooldowns[src] = ActionCooldowns[src] or {}
    if ActionCooldowns[src][key] and now - ActionCooldowns[src][key] < ms then return true end
    ActionCooldowns[src][key] = now
    return false
end

AddEventHandler('playerDropped', function()
    ActionCooldowns[source] = nil
end)

RegisterNetEvent('cm-admin:server:nuiAction', function(payload)
    local src = source
    payload = type(payload) == 'table' and payload or {}
    local action = tostring(payload.action or '')
    local data = type(payload.data) == 'table' and payload.data or {}

    if not AdminMode[src] then
        notify(src, 'Admin mode is not enabled.', 'error')
        TriggerClientEvent('cm-admin:client:forceClose', src)
        return
    end

    if action == 'refresh' then
        if hasPermission(src, 'menu.open') then refreshMenu(src) end
        return
    end

    if action == 'openEmsManagement' then
        if not hasPermission(src, 'ems.admin.manage') then
            return notify(src, 'No permission: ems.admin.manage', 'error')
        end
        if GetResourceState('cm-ems') ~= 'started' then
            return notify(src, 'cm-ems is not running.', 'error')
        end
        TriggerClientEvent('cm-admin:client:forceClose', src)
        TriggerClientEvent('cm-ems:client:open', src, true)
        logAction(src, 'ems_management_open', { category = 'ems' })
        return
    end

    if action == 'devAction' then
        if CMDevTools then CMDevTools.invoke(src, data) end
        return
    end

    if action == 'orgsAssignLeader' then
        if not CMOrganizations then return notify(src, 'Organizations registry is unavailable.', 'error') end
        local ok, message = CMOrganizations.assignLeader(src, data.orgId, data.characterId)
        notify(src, message or (ok and 'Leader assigned.' or 'Assignment failed.'), ok and 'success' or 'error')
        if ok then refreshMenu(src) end
        return
    end

    if action == 'orgsRemoveLeader' then
        if not CMOrganizations then return notify(src, 'Organizations registry is unavailable.', 'error') end
        local ok, message = CMOrganizations.removeLeader(src, data.orgId)
        notify(src, message or (ok and 'Leader removed.' or 'Removal failed.'), ok and 'success' or 'error')
        if ok then refreshMenu(src) end
        return
    end

    if action == 'orgsSetFacility' then
        if not CMOrganizations then return notify(src, 'Organizations registry is unavailable.', 'error') end
        if data.reset ~= true then TriggerClientEvent('cm-admin:client:forceClose', src) end
        local ok, message = CMOrganizations.setFacility(src, data.orgId, data.facilityType, data.reset == true)
        notify(src, message or (ok and 'Facility updated.' or 'Facility update failed.'), ok and 'success' or 'error')
        if ok then refreshMenu(src) end
        return
    end

    if action == 'orgsSavePolicy' then
        if not CMOrganizations then return notify(src, 'Organizations registry is unavailable.', 'error') end
        local ok, message = CMOrganizations.savePolicy(src, data)
        notify(src, message or (ok and 'Saved.' or 'Save failed.'), ok and 'success' or 'error')
        if ok then refreshMenu(src) end
        return
    end

    if action == 'gangAdminAction' then
        if not CMGangs then return notify(src,'Gang administration is unavailable.','error') end
        if onActionCooldown(src, 'gang_admin', 500) then return notify(src, 'Please wait before another gang action.', 'error') end
        local ok,message=CMGangs.invoke(src,tostring(data.operation or ''),data)
        notify(src,message or (ok and 'Gang updated.' or 'Gang update failed.'),ok and 'success' or 'error')
        if ok and tostring(data.operation or '')~='fleetBegin' then refreshMenu(src) end
        return
    end

    if action == 'orgsGetArmory' then
        if not CMOrganizations then return notify(src, 'Organizations registry is unavailable.', 'error') end
        TriggerClientEvent('cm-admin:client:detailResult', src, {
            type = 'orgArmory', orgId = data.orgId, data = CMOrganizations.getArmory(src, data.orgId),
        })
        return
    end

    if action == 'orgsConfigureArmory' then
        if not CMOrganizations then return notify(src, 'Organizations registry is unavailable.', 'error') end
        local ok, message = CMOrganizations.configureArmory(src, data.orgId, data)
        notify(src, message or (ok and 'Armory saved.' or 'Armory update failed.'), ok and 'success' or 'error')
        if ok then refreshMenu(src) end
        return
    end

    if action == 'orgsGetCapabilities' then
        if not CMOrganizations then return notify(src, 'Organizations registry is unavailable.', 'error') end
        TriggerClientEvent('cm-admin:client:detailResult', src, {
            type = 'orgCapabilities', orgId = data.orgId, data = CMOrganizations.getCapabilities(src, data.orgId),
        })
        return
    end

    if action == 'orgsConfigureCapability' then
        if not CMOrganizations then return notify(src, 'Organizations registry is unavailable.', 'error') end
        local ok, message = CMOrganizations.configureCapability(src, data.orgId, data.capability, data.enabled == true)
        notify(src, message or (ok and 'Capability saved.' or 'Capability update failed.'), ok and 'success' or 'error')
        return
    end
    if action == 'orgsGetFleet' then
        TriggerClientEvent('cm-admin:client:detailResult', src, { type='orgFleet', orgId=data.orgId, data=CMOrganizations.getFleet(src,data.orgId) })
        return
    end
    if action == 'orgsBeginFleetPlacement' then
        local ok,message=CMOrganizations.beginFleetPlacement(src,data.orgId,data.model)
        notify(src,message or 'Fleet placement failed.',ok and 'success' or 'error'); return
    end
    if action == 'orgsConfigureFleet' then
        local ok,message=CMOrganizations.configureFleet(src,data.orgId,data)
        notify(src,message or 'Fleet update failed.',ok and 'success' or 'error'); return
    end
    if action == 'orgsResetFleet' then
        local ok,message=CMOrganizations.resetFleet(src,data.orgId,data.model)
        notify(src,message or 'Fleet reset failed.',ok and 'success' or 'error'); return
    end
    if action == 'orgsGetNpcs' then
        TriggerClientEvent('cm-admin:client:detailResult', src, { type='orgNpcs', orgId=data.orgId, data=CMOrganizations.getNpcs(src,data.orgId) })
        return
    end
    if action == 'orgsConfigureNpc' then
        local ok,message=CMOrganizations.configureNpc(src,data.orgId,data)
        notify(src,message or 'NPC update failed.',ok and 'success' or 'error')
        if ok then TriggerClientEvent('cm-admin:client:detailResult', src, { type='orgNpcs', orgId=data.orgId, data=CMOrganizations.getNpcs(src,data.orgId) }) end
        return
    end
    if action == 'orgsGetAlpr' then TriggerClientEvent('cm-admin:client:detailResult',src,{type='orgAlpr',orgId=data.orgId,data=CMOrganizations.getAlpr(src,data.orgId)}); return end
    if action == 'orgsConfigureAlpr' then
        local ok,message=CMOrganizations.configureAlpr(src,data.orgId,data); notify(src,message or 'ALPR update failed.',ok and 'success' or 'error')
        if ok then TriggerClientEvent('cm-admin:client:detailResult',src,{type='orgAlpr',orgId=data.orgId,data=CMOrganizations.getAlpr(src,data.orgId)}) end; return
    end
    if action == 'orgsGetBarricades' then TriggerClientEvent('cm-admin:client:detailResult',src,{type='orgBarricades',orgId=data.orgId,data=CMOrganizations.getBarricades(src,data.orgId)}); return end
    if action == 'orgsConfigureBarricade' then
        local ok,message=CMOrganizations.configureBarricade(src,data.orgId,data); notify(src,message or 'Barricade update failed.',ok and 'success' or 'error')
        if ok then TriggerClientEvent('cm-admin:client:detailResult',src,{type='orgBarricades',orgId=data.orgId,data=CMOrganizations.getBarricades(src,data.orgId)}) end; return
    end

    -- ------------------------------------------------------------------
    -- Offline characters: search + inventory/vehicles through the DB bridge.
    -- ------------------------------------------------------------------
    if action == 'offlineSearch' then
        if not hasPermission(src, 'players.view') then return notify(src, 'No permission: players.view', 'error') end
        local query = tostring(data.query or ''):sub(1, 60)
        if #query < 1 then return notify(src, 'Type a character ID or name to search.', 'error') end

        local rows = {}
        for _, item in ipairs(Config.OfflineSearchQueries or {}) do
            local params = nil
            if item.mode == 'id' then params = { query }              -- ids are VARCHAR
            elseif item.mode == 'name' then params = { '%' .. query .. '%' } end
            if params then
                local ok, res = safeQuery(item.sql, params)
                if ok and res and #res > 0 then rows = res break end
            end
        end

        local results = {}
        for _, row in ipairs(rows) do
            results[#results + 1] = {
                characterId = row.id,
                name = ('%s %s'):format(row.first_name or '?', row.last_name or ''),
                dob = row.dob,
                cash = tonumber(row.cash),
                bank = tonumber(row.bank)
            }
        end
        sendDetail(src, 'offlineSearch', { results = results, query = query })
        return
    end

    if action == 'offlineInventory' or action == 'offlineVehicles' then
        local perm = action == 'offlineInventory' and 'inventory.view' or 'vehicles.view'
        if not hasPermission(src, perm) then return notify(src, 'No permission: ' .. perm, 'error') end
        local characterId = tostring(data.characterId or '')
        if characterId == '' then return notify(src, 'Character ID required.', 'error') end

        local playerInfo = {
            characterId = characterId,
            identifier = tostring(data.identifier or ''),
            name = ('Offline #%s'):format(characterId)
        }

        if action == 'offlineInventory' then
            local result = runBridgeQueries(Config.DatabaseBridge.InventoryQueries, playerInfo, {})
            sendDetail(src, 'inventory', { player = playerInfo, result = result, offline = true })
        else
            local result = runBridgeQueries(Config.DatabaseBridge.VehicleQueries, playerInfo, {})
            sendDetail(src, 'vehicles', { player = playerInfo, result = result, offline = true })
        end
        logAction(src, action, { characterId = characterId })
        return
    end

    -- ------------------------------------------------------------------
    -- Live map calibration. Lets owner/admin tune map bounds from UI, preview
    -- immediately, then save the same values to data/map_bounds.json.
    -- ------------------------------------------------------------------
    if action == 'saveMapBounds' then
        if not hasAnyPermission(src, { 'map.calibrate', 'ranks.manage', 'dev.tools', '*' }) then
            return notify(src, 'No permission: map.calibrate', 'error')
        end
        if Config.Map and Config.Map.AllowUiBoundsSave == false then
            return notify(src, 'UI map bounds saving is disabled in config.', 'error')
        end
        if onActionCooldown(src, 'saveMapBounds', 1500) then return end
        local ok, err = saveMapBounds(data.bounds or data)
        if not ok then return notify(src, err or 'Could not save map bounds.', 'error') end
        notify(src, 'Admin map bounds saved.', 'success')
        logAction(src, 'map_bounds_save', { category = 'system', bounds = SavedMapBounds })
        refreshMenu(src)
        return
    end

    if action == 'resetMapBounds' then
        if not hasAnyPermission(src, { 'map.calibrate', 'ranks.manage', 'dev.tools', '*' }) then
            return notify(src, 'No permission: map.calibrate', 'error')
        end
        if onActionCooldown(src, 'resetMapBounds', 1500) then return end
        local defaults = configuredMapBounds()
        local ok, err = saveMapBounds(defaults)
        if not ok then return notify(src, err or 'Could not reset map bounds.', 'error') end
        notify(src, 'Admin map bounds reset to config values.', 'success')
        logAction(src, 'map_bounds_reset', { category = 'system', bounds = defaults })
        refreshMenu(src)
        return
    end

    -- ------------------------------------------------------------------
    -- Live map: players (and optionally spawned vehicles) with coordinates.
    -- ------------------------------------------------------------------
    if action == 'mapData' then
        if not (hasPermission(src, 'map.view') or hasPermission(src, 'players.view')) then return end
        local refreshMs = (Config.Map and tonumber(Config.Map.RefreshMs)) or 1500
        if onActionCooldown(src, 'mapData', math.max(900, refreshMs - 100)) then return end

        local mapPlayers = {}
        local canSeeAdminsOnMap = hasPermission(src, 'map.admins') or hasPermission(src, 'admins.view')
        for _, playerSrc in ipairs(GetPlayers()) do
            local target = tonumber(playerSrc)
            local ped = GetPlayerPed(target)
            if ped and ped ~= 0 then
                local coords = GetEntityCoords(ped)
                local char = getCharacterInfo(target)
                mapPlayers[#mapPlayers + 1] = {
                    id = target,
                    name = GetPlayerName(target),
                    characterId = char.id,
                    characterName = char.name,
                    adminMode = canSeeAdminsOnMap and AdminMode[target] == true or false,
                    x = math.floor(coords.x), y = math.floor(coords.y), z = math.floor(coords.z),
                    self = target == src
                }
            end
        end

        local mapVehicles = nil
        if data.vehicles == true and (hasPermission(src, 'map.vehicles') or hasPermission(src, 'vehicles.view')) then
            mapVehicles = {}
            local maxVeh = (Config.Map and Config.Map.MaxVehicles) or 300
            for _, veh in ipairs(GetAllVehicles()) do
                if #mapVehicles >= maxVeh then break end
                if DoesEntityExist(veh) then
                    local coords = GetEntityCoords(veh)
                    local netId = 0
                    pcall(function() netId = NetworkGetNetworkIdFromEntity(veh) end)
                    mapVehicles[#mapVehicles + 1] = {
                        netId = netId,
                        plate = GetVehicleNumberPlateText(veh),
                        model = GetEntityModel(veh),
                        x = math.floor(coords.x), y = math.floor(coords.y), z = math.floor(coords.z)
                    }
                end
            end
        end

        TriggerClientEvent('cm-admin:client:mapData', src, { players = mapPlayers, vehicles = mapVehicles })
        return
    end


    if action == 'mapTeleportToCoords' then
        if not hasAnyPermission(src, { 'map.teleport', 'gps.teleport', 'teleport', 'players.teleport' }) then
            return notify(src, 'No permission: map.teleport', 'error')
        end
        if onActionCooldown(src, 'mapTeleportToCoords', 1200) then return end
        local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
        if not x or not y then return notify(src, 'Invalid map coordinates.', 'error') end
        z = tonumber(z) or 40.0
        if math.abs(x) > 10000 or math.abs(y) > 10000 or z < -300 or z > 2000 then
            return notify(src, 'Map coordinates out of range.', 'error')
        end
        TriggerClientEvent('cm-admin:client:teleportToCoords', src, { x = x, y = y, z = z + 1.0 })
        logAction(src, 'map_teleport', { category = 'players', x = x, y = y, z = z })
        return
    end

    if action == 'vehicleMapAction' then
        local vehicleAction = tostring(data.vehicleAction or '')
        local netId = tonumber(data.netId) or 0
        local plate = tostring(data.plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
        local veh = 0
        if netId > 0 then
            pcall(function() veh = NetworkGetEntityFromNetworkId(netId) end)
        end
        if (not veh or veh == 0 or not DoesEntityExist(veh)) and plate ~= '' then
            for _, candidate in ipairs(GetAllVehicles()) do
                if DoesEntityExist(candidate) and tostring(GetVehicleNumberPlateText(candidate) or ''):upper():gsub('^%s+', ''):gsub('%s+$', '') == plate then
                    veh = candidate
                    break
                end
            end
        end
        if not veh or veh == 0 or not DoesEntityExist(veh) then return notify(src, 'Vehicle not found/streamed.', 'error') end
        local coords = GetEntityCoords(veh)

        if vehicleAction == 'goto' then
            if not hasAnyPermission(src, { 'map.teleport', 'vehicles.view', 'players.teleport' }) then return notify(src, 'No permission: map.teleport', 'error') end
            TriggerClientEvent('cm-admin:client:teleportToCoords', src, { x = coords.x, y = coords.y, z = coords.z + 1.0 })
        elseif vehicleAction == 'delete' then
            if not hasPermission(src, 'vehicles.manage') then return notify(src, 'No permission: vehicles.manage', 'error') end
            DeleteEntity(veh)
            notify(src, 'Vehicle deleted.', 'success')
        elseif vehicleAction == 'repair' then
            if not hasPermission(src, 'vehicles.manage') then return notify(src, 'No permission: vehicles.manage', 'error') end
            TriggerClientEvent('cm-admin:client:repairVehicleNet', src, netId, plate)
            notify(src, 'Repair request sent. Vehicle must be streamed on your client.', 'info')
        else
            return notify(src, 'Unknown vehicle map action.', 'error')
        end
        logAction(src, 'map_vehicle_' .. vehicleAction, { category = 'vehicles', netId = netId, plate = plate, x = coords.x, y = coords.y, z = coords.z }, plate ~= '' and ('vehicle:' .. plate) or nil, plate ~= '' and plate or nil)
        return
    end

    if action == 'gpsTeleport' then
        if not hasAnyPermission(src, { 'gps.teleport', 'teleport', 'players.teleport' }) then
            return notify(src, 'No permission: gps.teleport', 'error')
        end
        if onActionCooldown(src, 'gpsTeleport', 2000) then return end
        logAction(src, 'gps_teleport_request', { category = 'players' })
        TriggerClientEvent('cm-admin:client:teleportToWaypoint', src)
        return
    end

    if action == 'addAdmin' then
        if not hasPermission(src, 'admins.manage') then return notify(src, 'No permission: admins.manage', 'error') end
        local characterId = normalizeCharacterId(data.characterId or data.identifier)
        local identifier = adminKeyForCharacterId(characterId)
        local rank = tostring(data.rank or 'moderator'):lower()
        local name = tostring(data.name or ('Character ' .. tostring(characterId or 'Admin')))
        if not characterId or not identifier then return notify(src, 'Character ID is required.', 'error') end
        local rankInfo = getRank(rank)
        if not rankInfo then return notify(src, 'Rank does not exist.', 'error') end
        if rankInfo.level >= actorLevel(src) and actorLevel(src) < 100 then
            return notify(src, 'You cannot add an admin with same/higher rank.', 'error')
        end
        safeUpdate([[INSERT INTO cm_admins (identifier, character_id, name, rank_name, active, added_by)
            VALUES (?, ?, ?, ?, 1, ?)
            ON DUPLICATE KEY UPDATE character_id = VALUES(character_id), name = VALUES(name), rank_name = VALUES(rank_name), active = 1]], {
            identifier, characterId, name, rank, getAdminProfile(src) and getAdminProfile(src).identifier or getPrimaryIdentifier(src)
        })
        logAction(src, 'admin_added', { rank = rank, name = name, characterId = characterId }, identifier, name)
        notify(src, 'Admin character saved.', 'success')
        refreshMenu(src)
        return
    end

    if action == 'removeAdmin' then
        if not hasPermission(src, 'admins.manage') then return notify(src, 'No permission: admins.manage', 'error') end
        local identifier = normalizeIdentifier(data.identifier)
        if not identifier then return notify(src, 'Admin character key is required.', 'error') end
        local row = getAdminRowByIdentifier(identifier)
        local rank = row and getRank(row.rank_name)
        if rank and rank.level >= actorLevel(src) and actorLevel(src) < 100 then
            return notify(src, 'You cannot remove same/higher rank admin.', 'error')
        end
        safeUpdate('UPDATE cm_admins SET active = 0 WHERE identifier = ?', { identifier })
        logAction(src, 'admin_removed', {}, identifier, row and row.name or nil)
        notify(src, 'Admin disabled.', 'success')
        refreshMenu(src)
        return
    end

    if action == 'setAdminRank' then
        if not hasPermission(src, 'admins.manage') then return notify(src, 'No permission: admins.manage', 'error') end
        local identifier = normalizeIdentifier(data.identifier)
        local rank = tostring(data.rank or ''):lower()
        local rankInfo = getRank(rank)
        if not identifier or not rankInfo then return notify(src, 'Admin character/rank invalid.', 'error') end
        if rankInfo.level >= actorLevel(src) and actorLevel(src) < 100 then
            return notify(src, 'You cannot assign same/higher rank.', 'error')
        end
        safeUpdate('UPDATE cm_admins SET rank_name = ?, active = 1 WHERE identifier = ?', { rank, identifier })
        logAction(src, 'admin_rank_changed', { rank = rank }, identifier, nil)
        notify(src, 'Admin rank updated.', 'success')
        refreshMenu(src)
        return
    end

    if action == 'saveRank' then
        if not hasPermission(src, 'ranks.manage') then return notify(src, 'No permission: ranks.manage', 'error') end
        local rankName = tostring(data.name or ''):lower():gsub('%s+', '')
        local label = tostring(data.label or rankName)
        local level = tonumber(data.level) or 0
        local permissions = type(data.permissions) == 'table' and data.permissions or {}
        if rankName == '' then return notify(src, 'Rank name is required.', 'error') end
        if level >= actorLevel(src) and actorLevel(src) < 100 then
            return notify(src, 'You cannot create/edit same/higher level rank.', 'error')
        end
        safeUpdate([[INSERT INTO cm_admin_ranks (rank_name, label, level, permissions_json)
            VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE label = VALUES(label), level = VALUES(level), permissions_json = VALUES(permissions_json)]], {
            rankName, label, level, jenc(permissions)
        })
        logAction(src, 'rank_saved', { rank = rankName, level = level, permissions = permissions })
        notify(src, 'Rank saved.', 'success')
        refreshMenu(src)
        return
    end

    if action == 'deleteRank' then
        if not hasPermission(src, 'ranks.manage') then return notify(src, 'No permission: ranks.manage', 'error') end
        local rankName = tostring(data.name or ''):lower()
        if rankName == 'owner' then return notify(src, 'Owner rank cannot be deleted.', 'error') end
        local rank = getRank(rankName)
        if rank and rank.level >= actorLevel(src) and actorLevel(src) < 100 then
            return notify(src, 'You cannot delete same/higher level rank.', 'error')
        end
        safeUpdate('DELETE FROM cm_admin_ranks WHERE rank_name = ?', { rankName })
        logAction(src, 'rank_deleted', { rank = rankName })
        notify(src, 'Rank deleted.', 'success')
        refreshMenu(src)
        return
    end

    if action == 'playerAction' then
        local target = tonumber(data.target)
        local player = target and getPlayerSummary(target)
        if not player then return notify(src, 'Target player not found.', 'error') end
        local playerAction = tostring(data.playerAction or '')

        if playerAction == 'goto' then
            if not hasPermission(src, 'players.teleport') then return notify(src, 'No permission: players.teleport', 'error') end
            local ped = GetPlayerPed(target)
            local coords = GetEntityCoords(ped)
            TriggerClientEvent('cm-admin:client:teleportToCoords', src, { x = coords.x, y = coords.y, z = coords.z + 1.0 })
        elseif playerAction == 'bring' then
            if not hasPermission(src, 'players.teleport') then return notify(src, 'No permission: players.teleport', 'error') end
            local ped = GetPlayerPed(src)
            local coords = GetEntityCoords(ped)
            TriggerClientEvent('cm-admin:client:teleportToCoords', target, { x = coords.x, y = coords.y, z = coords.z + 1.0 })
        elseif playerAction == 'freeze' then
            if not hasPermission(src, 'players.freeze') then return notify(src, 'No permission: players.freeze', 'error') end
            TriggerClientEvent('cm-admin:client:setFrozen', target, true)
        elseif playerAction == 'unfreeze' then
            if not hasPermission(src, 'players.freeze') then return notify(src, 'No permission: players.freeze', 'error') end
            TriggerClientEvent('cm-admin:client:setFrozen', target, false)
        elseif playerAction == 'heal' then
            if not hasPermission(src, 'tools.heal') then return notify(src, 'No permission: tools.heal', 'error') end
            TriggerClientEvent('cm-admin:client:heal', target)
        elseif playerAction == 'armor' then
            if not hasPermission(src, 'tools.heal') then return notify(src, 'No permission: tools.heal', 'error') end
            TriggerClientEvent('cm-admin:client:armor', target)
        elseif playerAction == 'give_cash' then
            if not hasAnyPermission(src, { 'money.manage', 'players.manage' }) then return notify(src, 'No permission: money.manage', 'error') end
            local ok, message = giveCashToOnlinePlayer(src, target, data.amount, data.reason)
            notify(src, message, ok and 'success' or 'error')
            if ok then refreshMenu(src) end
            return
        elseif playerAction == 'kick' then
            if not hasPermission(src, 'players.kick') then return notify(src, 'No permission: players.kick', 'error') end
            DropPlayer(target, data.reason or 'Kicked by admin')
        elseif playerAction == 'repair_vehicle' then
            if not hasPermission(src, 'vehicles.manage') then return notify(src, 'No permission: vehicles.manage', 'error') end
            TriggerClientEvent('cm-admin:client:repairCurrentVehicle', target)
        elseif playerAction == 'delete_vehicle' then
            if not hasPermission(src, 'vehicles.manage') then return notify(src, 'No permission: vehicles.manage', 'error') end
            TriggerClientEvent('cm-admin:client:deleteCurrentVehicle', target)
        else
            return notify(src, 'Unknown player action.', 'error')
        end

        logAction(src, 'player_' .. playerAction, { target = target, reason = data.reason }, player.identifier, player.name)
        refreshMenu(src)
        return
    end

    if action == 'viewInventory' then
        if not hasPermission(src, 'inventory.view') then return notify(src, 'No permission: inventory.view', 'error') end
        local target = tonumber(data.target)
        local player = targetInfoBySource(target)
        if not player then return notify(src, 'Target player not found.', 'error') end
        local result = runBridgeQueries(Config.DatabaseBridge.InventoryQueries, player, {})
        logAction(src, 'inventory_view', { target = target, source = result.source, count = #(result.rows or {}) }, player.identifier, player.name)
        sendDetail(src, 'inventory', { player = player, result = result })
        return
    end

    if action == 'viewVehicles' then
        if not hasPermission(src, 'vehicles.view') then return notify(src, 'No permission: vehicles.view', 'error') end
        local target = tonumber(data.target)
        local player = targetInfoBySource(target)
        if not player then return notify(src, 'Target player not found.', 'error') end
        local result = runBridgeQueries(Config.DatabaseBridge.VehicleQueries, player, {})
        logAction(src, 'vehicles_view', { target = target, source = result.source, count = #(result.rows or {}) }, player.identifier, player.name)
        sendDetail(src, 'vehicles', { player = player, result = result })
        return
    end

    if action == 'viewVehicleInventory' then
        if not hasPermission(src, 'vehicle_inventory.view') then return notify(src, 'No permission: vehicle_inventory.view', 'error') end
        local plate = tostring(data.plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
        if plate == '' then return notify(src, 'Plate is required.', 'error') end
        local result = runBridgeQueries(Config.DatabaseBridge.VehicleInventoryQueries, {}, { plate = plate })
        logAction(src, 'vehicle_inventory_view', { plate = plate, source = result.source, count = #(result.rows or {}) }, 'vehicle:' .. plate, plate)
        sendDetail(src, 'vehicleInventory', { plate = plate, result = result })
        return
    end

    if action == 'viewLogs' then
        if not hasPermission(src, 'logs.view') then return notify(src, 'No permission: logs.view', 'error') end
        sendDetail(src, 'logs', { logs = getLogsForUi(200, src), categories = getLogCategoriesForUi(src) })
        return
    end

    notify(src, 'Unknown admin action: ' .. action, 'error')
end)

-- Rank-based permission check for other resources (cm-chat announcements, etc).
exports('HasPermission', function(src, permission)
    return hasPermission(tonumber(src) or 0, tostring(permission or ''), true)
end)




-- Generic audit log bridge for future resources.
-- Server-side usage:
--   exports['cm-admin']:AddLog(source, 'family_invite', { category = 'players', familyId = 1 }, targetIdentifier, targetName)
-- or:
--   TriggerEvent('cm-admin:server:addLog', source, 'org_created', { category = 'system' })
exports('AddLog', function(src, action, data, targetIdentifier, targetName)
    logAction(tonumber(src) or 0, tostring(action or 'external_log'), type(data) == 'table' and data or {}, targetIdentifier, targetName)
    return true
end)

AddEventHandler('cm-admin:server:addLog', function(src, action, data, targetIdentifier, targetName)
    logAction(tonumber(src) or 0, tostring(action or 'external_log'), type(data) == 'table' and data or {}, targetIdentifier, targetName)
end)
