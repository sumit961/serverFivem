-- cm-hud/server/main.lua

-- ============================================================
-- CHARACTER HUD DATABASE SYNC
-- Pulls ID/cash/bank from characters table so HUD matches DB in real time.
-- Supports oxmysql exports without making oxmysql a hard manifest dependency.
-- ============================================================
local HUD_DEBUG = false
local function hudDebug(message)
    if HUD_DEBUG then print(message) end
end
local ActiveHudCharacters = {}
local LastHudPayload = {}

local function trimText(value)
    value = tostring(value or '')
    value = value:gsub('[\r\n\t]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, 180)
end


dbFetchOne = function(query, params, cb)
    params = params or {}

    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:single(query, params, cb)
        return true
    end

    if MySQL and MySQL.single then
        MySQL.single(query, params, cb)
        return true
    end

    hudDebug('[CM-HUD] No SQL resource found. Start oxmysql before cm-hud for DB money sync.')
    cb(nil)
    return false
end

cleanCharacterId = function(value)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    return value:sub(1, 50)
end

local function sendCharacterHud(src, charId)
    
    if type(charId) == 'table' then charId = charId.id end
    local active = ActiveHudCharacters[src]
    if not charId and type(active) == 'table' then charId = active.id end
    charId = cleanCharacterId(charId or (active and active.id))
    if not charId then return end

    dbFetchOne('SELECT id, first_name, last_name, cash, bank FROM characters WHERE id = ? LIMIT 1', { charId }, function(row)
        if not row then return end
        local fullName = trimText((row.first_name or '') .. ' ' .. (row.last_name or ''))
        if fullName == '' then fullName = 'Unknown' end
        local payload = {
            id = tostring(row.id),
            name = fullName,
            cash = tonumber(row.cash) or 0,
            bank = tonumber(row.bank) or 0
        }
        ActiveHudCharacters[src] = { id = tostring(row.id), name = fullName }
        local encoded = json.encode(payload)
        if LastHudPayload[src] ~= encoded then
            LastHudPayload[src] = encoded
            TriggerClientEvent('cm-hud:client:updateCharacterHud', src, payload)
        end
    end)
end



local function readStateValue(src, keys)
    if not Player then return nil end
    local ok, state = pcall(function() return Player(src).state end)
    if not ok or not state then return nil end
    for _, key in ipairs(keys) do
        local okValue, value = pcall(function() return state[key] end)
        if okValue and value ~= nil and tostring(value) ~= '' then
            return value
        end
    end
    return nil
end

local function extractCharacterIdFromAny(...)
    local args = { ... }
    for _, value in ipairs(args) do
        if type(value) == 'table' then
            local found = value.id or value.characterId or value.charId or value.charid or value.char_id or value.citizenid
            if found then return cleanCharacterId(found) end
            if type(value.character) == 'table' then
                found = value.character.id or value.character.characterId or value.character.charId or value.character.char_id
                if found then return cleanCharacterId(found) end
            end
        else
            local cleaned = cleanCharacterId(value)
            if cleaned then return cleaned end
        end
    end
    return nil
end

local function setActiveCharacterForSource(src, charId)
    src = tonumber(src)
    charId = cleanCharacterId(charId)
    if not src or not charId then return false end
    ActiveHudCharacters[src] = { id = charId, name = nil }
    sendCharacterHud(src, charId)
    return true
end

local function handleCharacterLoadedEvent(a, b, c)
    local src = source
    local charId

    -- Server-to-server style: TriggerEvent(eventName, src, charIdOrData)
    if tonumber(a) and tonumber(a) > 0 and tostring(a) ~= tostring(b) then
        src = tonumber(a)
        charId = extractCharacterIdFromAny(b, c)
    else
        -- Client-to-server style: TriggerServerEvent(eventName, charIdOrData)
        charId = extractCharacterIdFromAny(a, b, c)
    end

    if src and tonumber(src) and charId then
        setActiveCharacterForSource(src, charId)
    end
end

for _, eventName in ipairs({
    'cm-hud:server:setCharacter',
    'cm-hud:server:setTrustedCharacter',
    'cm-characters:server:characterLoaded',
    'cm-characters:server:characterSelected',
    'cm-characters:server:selectedCharacter',
    'cm-characters:server:selectCharacter',
    'cm-spawn:server:characterLoaded',
    'cm-spawn:characterLoaded',
    'cm-core:server:characterLoaded'
}) do
    RegisterNetEvent(eventName, handleCharacterLoadedEvent)
end

local function resolveCharacterByHints(src, hints, cb)
    hints = hints or {}
    local charId = cleanCharacterId(hints.id or hints.characterId or hints.charid or hints.char_id or hints.citizenid)
    if charId then cb(charId) return end

    charId = extractCharacterIdFromAny(readStateValue(src, { 'characterId', 'charId', 'charid', 'char_id', 'citizenid', 'currentCharacterId' }))
    if charId then cb(charId) return end

    local accountId = cleanCharacterId(hints.account_id or hints.accountId or hints.account or hints.accountid) or cleanCharacterId(readStateValue(src, { 'account_id', 'accountId', 'account', 'accountid' }))
    local slot = tonumber(hints.slot or hints.charSlot or hints.character_slot)

    if accountId and slot then
        dbFetchOne('SELECT id FROM characters WHERE account_id = ? AND slot = ? LIMIT 1', { accountId, slot }, function(row)
            cb(row and row.id or nil)
        end)
        return
    end

    if accountId then
        dbFetchOne('SELECT id FROM characters WHERE account_id = ? ORDER BY has_spawned DESC, last_played DESC, created_at DESC LIMIT 1', { accountId }, function(row)
            cb(row and row.id or nil)
        end)
        return
    end

    -- Last safe fallback: if the client did not provide any character/account id, do not use FiveM server id.
    -- The HUD will keep ID blank until cm-playerdata/cm-characters sends the real character id.
    cb(nil)
end


RegisterNetEvent('cm-hud:server:requestCharacterHud', function(charId, hints)
    local src = source
    if type(charId) == 'table' and hints == nil then
        hints = charId
        charId = nil
    end
    hints = hints or {}
    hints.id = hints.id or charId

    resolveCharacterByHints(src, hints, function(resolvedId)
        resolvedId = cleanCharacterId(resolvedId)
        if not resolvedId then
            TriggerClientEvent('cm-hud:client:updateCharacterHud', src, { id = '', name = 'Unknown', cash = 0, bank = 0 })
            hudDebug(('[CM-HUD] Could not resolve DB character for player %s. Send character id/account_id from cm-playerdata.'):format(src))
            return
        end
        ActiveHudCharacters[src] = { id = resolvedId, name = nil }
        sendCharacterHud(src, resolvedId)
    end)
end)

-- Optional export for cm-playerdata/cm-characters after saving money:
-- exports['cm-hud']:RefreshCharacterHud(source, characterId)
exports('RefreshCharacterHud', function(src, charId)
    src = tonumber(src)
    if not src then return end
    if charId then ActiveHudCharacters[src] = { id = cleanCharacterId(charId), name = nil } end
    sendCharacterHud(src, ActiveHudCharacters[src])
end)

-- DB polling removed in v2.8.0. Money HUD refresh is event/export driven only.

AddEventHandler('playerDropped', function()
    ActiveHudCharacters[source] = nil
    LastHudPayload[source] = nil
end)
