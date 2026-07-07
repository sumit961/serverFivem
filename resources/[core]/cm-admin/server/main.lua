-- cm-admin/server/main.lua
-- v2.5: character-ID based /admin mode + F11 NUI menu + DB ranks/permissions/logs + cash tools.
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

local function logAction(src, action, data, targetIdentifier, targetName)
    data = data or {}
    local identifier = 'console'
    local name = 'console'

    if src and src > 0 then
        local char = getCharacterInfo and getCharacterInfo(src) or {}
        identifier = adminKeyForCharacterId(char.id) or getPrimaryIdentifier(src) or ('server:' .. src)
        name = char.name or GetPlayerName(src) or ('Player ' .. src)
        data.actorCharacterId = data.actorCharacterId or normalizeCharacterId(char.id)
    end

    print(('[CM-ADMIN] %s (%s) -> %s %s'):format(name, src or 0, action, next(data) and jenc(data) or ''))
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
    print('[CM-ADMIN] v2.5 character-id schema ready')
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
    local charId = getStateCharacterId(src)
    local name = CharacterCache[src] and CharacterCache[src].name or nil

    -- Identity is statebag-driven (cm-characters sets it on character select).
    -- The characters table has no license column, so there is no DB fallback:
    -- if this is nil the player simply hasn't picked a character yet.

    return { id = charId, name = name }
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

local function getLogsForUi(limit)
    limit = tonumber(limit) or 80
    if limit < 1 then limit = 80 end
    if limit > 200 then limit = 200 end

    local logs = {}
    local ok, rows = safeQuery(('SELECT id, identifier, source, admin_name, action, target_identifier, target_name, details_json, created_at FROM cm_admin_logs ORDER BY id DESC LIMIT %d'):format(limit), {})
    if ok then
        for _, row in ipairs(rows) do
            logs[#logs + 1] = {
                id = row.id,
                identifier = row.identifier,
                source = row.source,
                adminName = row.admin_name,
                action = row.action,
                targetIdentifier = row.target_identifier,
                targetName = row.target_name,
                details = jdec(row.details_json, {}),
                createdAt = row.created_at
            }
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
    'logs.view',
    'noclip', 'teleport', 'tools.heal'
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
        server = {
            name = GetConvar('sv_hostname', 'CM Server'),
            maxClients = GetConvarInt('sv_maxclients', 48),
            resource = GetCurrentResourceName()
        }
    }

    if hasPermission(src, 'players.view') then payload.players = getOnlinePlayers(src) end
    if CMDevTools then payload.devTools = CMDevTools.forPlayer(src) end
    if hasPermission(src, 'admins.view') then payload.admins = getAdminsForUi() end
    if hasPermission(src, 'ranks.view') then payload.ranks = getRanksForUi() end
    if hasPermission(src, 'logs.view') then payload.logs = getLogsForUi(80) end

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
    local addQuery = bridge.AddCashQuery or 'UPDATE characters SET cash = GREATEST(0, COALESCE(cash, 0) + ?) WHERE id = ?'
    local updateOk, affected = safeUpdate(addQuery, { amount, tostring(player.characterId) })
    if not updateOk then
        print(('[CM-ADMIN] Give cash DB error: %s'):format(tostring(affected)))
        return false, 'Could not update character cash in database.'
    end
    if type(affected) == 'number' and affected < 1 then
        return false, 'No character money row was updated.'
    end

    local newCash, newBank = nil, nil
    if bridge.MoneyQuery then
        local ok, row = safeSingle(bridge.MoneyQuery, { tostring(player.characterId) })
        if ok and row then
            newCash = tonumber(row.cash)
            newBank = tonumber(row.bank)
        end
    end
    if newCash == nil then newCash = (tonumber(player.cash) or 0) + amount end

    setOnlineCashState(target, newCash, newBank)
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

    if action == 'devAction' then
        if CMDevTools then CMDevTools.invoke(src, data) end
        return
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
    -- Live map: players (and optionally spawned vehicles) with coordinates.
    -- ------------------------------------------------------------------
    if action == 'mapData' then
        if not hasPermission(src, 'players.view') then return end
        if onActionCooldown(src, 'mapData', 900) then return end

        local mapPlayers = {}
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
                    x = math.floor(coords.x), y = math.floor(coords.y),
                    self = target == src
                }
            end
        end

        local mapVehicles = nil
        if data.vehicles == true and hasPermission(src, 'vehicles.view') then
            mapVehicles = {}
            local maxVeh = (Config.Map and Config.Map.MaxVehicles) or 300
            for _, veh in ipairs(GetAllVehicles()) do
                if #mapVehicles >= maxVeh then break end
                if DoesEntityExist(veh) then
                    local coords = GetEntityCoords(veh)
                    mapVehicles[#mapVehicles + 1] = {
                        plate = GetVehicleNumberPlateText(veh),
                        x = math.floor(coords.x), y = math.floor(coords.y)
                    }
                end
            end
        end

        TriggerClientEvent('cm-admin:client:mapData', src, { players = mapPlayers, vehicles = mapVehicles })
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
        sendDetail(src, 'logs', { logs = getLogsForUi(200) })
        return
    end

    notify(src, 'Unknown admin action: ' .. action, 'error')
end)

-- Rank-based permission check for other resources (cm-chat announcements, etc).
exports('HasPermission', function(src, permission)
    return hasPermission(tonumber(src) or 0, tostring(permission or ''), true)
end)


