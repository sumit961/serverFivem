-- cm-characters/server/admin.lua
-- Legacy character admin bridge. Full staff UI belongs in cm-admin.
-- This file keeps safe server helpers/exports and disables the old direct panel by default.


-- Production-safe local logger wrapper.
-- When Config.Debug/Config.VerboseLogs is false, normal CM-CHARACTERS debug prints are hidden.
-- Warnings/errors still print so real problems are visible.
local __cmCharactersPrint = print
local function __cmCharactersShouldVerbose()
    return Config and (Config.Debug == true or Config.VerboseLogs == true or Config.ProductionMode == false)
end
local function print(...)
    if __cmCharactersShouldVerbose() then
        return __cmCharactersPrint(...)
    end

    local first = tostring(select(1, ...) or '')
    local isCmCharactersLog = first:find('%[CM%-CHARACTERS') ~= nil
    if not isCmCharactersLog then
        return __cmCharactersPrint(...)
    end

    local upper = first:upper()
    if upper:find('ERROR', 1, true) or upper:find('WARNING', 1, true) or upper:find('FAILED', 1, true) or upper:find('DENIED', 1, true) then
        return __cmCharactersPrint(...)
    end
end

local function adminReply(src, ok, message, extra)
    extra = type(extra) == 'table' and extra or {}
    extra.ok = ok == true
    extra.message = tostring(message or (ok and 'Done' or 'Failed'))
    TriggerClientEvent('cm-characters:client:adminStatus', src, extra)
end

local function hasCharacterAdminPermission(src, permission)
    return CMCharacters.HasPermission(src, permission or 'characters.admin')
end

local function requireAdmin(src, permission)
    if not hasCharacterAdminPermission(src, permission or 'characters.admin') then
        CMCharacters.Notify(src, 'No permission to use character admin.', 'error')
        return false
    end
    return true
end

local function legacyAdminEnabled(src)
    if Config and Config.EnableLegacyCharacterAdmin == true then return true end
    CMCharacters.Notify(src, 'Legacy cm-characters admin UI is disabled. Use cm-admin.', 'error')
    return false
end

local function findOnlineSourceByCharId(charId)
    charId = tostring(charId or '')
    if charId == '' then return nil end
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local state = Player(src).state
        if tostring(state.charId or state.characterId or '') == charId then
            return src
        end
    end
    return nil
end

local function compactChar(row)
    return {
        charId = tostring(row.id),
        id = tostring(row.id),
        accountId = tostring(row.account_id or ''),
        slot = tonumber(row.slot) or 0,
        firstName = row.first_name or '',
        lastName = row.last_name or '',
        name = CMCharacters.CharacterFullName(row),
        dob = row.dob or '',
        gender = row.gender or '',
        cash = tonumber(row.cash or 0) or 0,
        bank = tonumber(row.bank or 0) or 0,
        playtime = tonumber(row.playtime_minutes or row.playtime or 0) or 0,
        hasSpawned = tonumber(row.has_spawned or 0) == 1,
        created = row.created_at,
        lastSeen = row.last_seen,
        online = findOnlineSourceByCharId(row.id) ~= nil
    }
end

local function searchCharacters(query, limit)
    query = CMCharacters.Trim(query)
    limit = tonumber(limit) or 30
    if limit < 1 then limit = 1 end
    if limit > 100 then limit = 100 end

    local rows
    if query == '' then
        rows = CMCharacters.Query(('SELECT * FROM characters ORDER BY id DESC LIMIT %d'):format(limit), {}) or {}
    else
        local like = '%' .. query .. '%'
        rows = CMCharacters.Query(([[
            SELECT * FROM characters
            WHERE CAST(id AS CHAR) LIKE ?
               OR CAST(account_id AS CHAR) LIKE ?
               OR first_name LIKE ?
               OR last_name LIKE ?
               OR CONCAT(first_name, ' ', last_name) LIKE ?
            ORDER BY id DESC
            LIMIT %d
        ]]):format(limit), { like, like, like, like, like }) or {}
    end

    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = compactChar(row) end
    return out
end

local function sendSearchResults(src, query)
    TriggerClientEvent('cm-characters:client:adminResults', src, searchCharacters(query, 30))
end

RegisterNetEvent('cm-characters:server:requestOpenAdmin', function()
    local src = source
    if not legacyAdminEnabled(src) then return end
    if not requireAdmin(src, 'characters.admin') then return end
    TriggerClientEvent('cm-characters:client:openAdmin', src)
    sendSearchResults(src, '')
end)

RegisterNetEvent('cm-characters:server:adminSearch', function(query)
    local src = source
    if not legacyAdminEnabled(src) then return end
    if not requireAdmin(src, 'characters.view') then return end
    sendSearchResults(src, query)
end)

RegisterNetEvent('cm-characters:server:adminAction', function(action, payload)
    local src = source
    if not legacyAdminEnabled(src) then return end
    if not requireAdmin(src, 'characters.admin') then return end

    action = tostring(action or '')
    payload = type(payload) == 'table' and payload or {}
    local charId = tostring(payload.charId or payload.id or '')

    if action == 'rename' then
        local char = CMCharacters.GetCharacterById(charId)
        if not char then adminReply(src, false, 'Character not found') return end

        local okFirst, firstOrErr = CMCharacters.ValidateName(payload.firstName, 'First name')
        if not okFirst then adminReply(src, false, firstOrErr) return end
        local okLast, lastOrErr = CMCharacters.ValidateName(payload.lastName, 'Last name')
        if not okLast then adminReply(src, false, lastOrErr) return end

        local taken = CMCharacters.Query(
            'SELECT id FROM characters WHERE LOWER(first_name) = LOWER(?) AND LOWER(last_name) = LOWER(?) AND id <> ? LIMIT 1',
            { firstOrErr, lastOrErr, charId }
        )
        if taken and #taken > 0 then adminReply(src, false, 'Name already taken') return end

        CMCharacters.Query('UPDATE characters SET first_name = ?, last_name = ? WHERE id = ?', { firstOrErr, lastOrErr, charId })
        exports['cm-core']:CacheInvalidate('char:' .. charId)

        local target = findOnlineSourceByCharId(charId)
        if target then
            local updated = CMCharacters.GetCharacterById(charId)
            CMCharacters.SetCharacterState(target, updated)
        end

        CMCharacters.LogAdmin(src, 'admin_rename_character', { char_id = charId, first_name = firstOrErr, last_name = lastOrErr })
        adminReply(src, true, 'Character renamed')
        sendSearchResults(src, charId)

    elseif action == 'setSlot' then
        local char = CMCharacters.GetCharacterById(charId)
        if not char then adminReply(src, false, 'Character not found') return end

        local newSlot = tonumber(payload.slot)
        if not newSlot or newSlot < 1 or newSlot > 20 or math.floor(newSlot) ~= newSlot then
            adminReply(src, false, 'Invalid slot')
            return
        end

        local maxSlots = CMCharacters.GetMaxCharacters(char.account_id)
        if newSlot > maxSlots then
            adminReply(src, false, 'Account only has ' .. tostring(maxSlots) .. ' slots')
            return
        end

        local existing = CMCharacters.Query(
            'SELECT id FROM characters WHERE account_id = ? AND slot = ? AND id <> ? LIMIT 1',
            { tostring(char.account_id), newSlot, charId }
        )
        if existing and #existing > 0 then adminReply(src, false, 'That slot is already used') return end

        CMCharacters.Query('UPDATE characters SET slot = ? WHERE id = ?', { newSlot, charId })
        CMCharacters.LogAdmin(src, 'admin_set_character_slot', { char_id = charId, slot = newSlot })
        adminReply(src, true, 'Character slot updated')
        sendSearchResults(src, charId)

    elseif action == 'resetAppearance' then
        local char = CMCharacters.GetCharacterById(charId)
        if not char then adminReply(src, false, 'Character not found') return end

        CMCharacters.Query('UPDATE characters SET appearance_json = ?, has_spawned = 0 WHERE id = ?', { '{}', charId })
        exports['cm-core']:CacheInvalidate('char:' .. charId)

        local target = findOnlineSourceByCharId(charId)
        if target then
            TriggerClientEvent('cm-characters:client:error', target, 'Your appearance was reset by admin. Reconnect or open creator again.')
        end

        CMCharacters.LogAdmin(src, 'admin_reset_appearance', { char_id = charId })
        adminReply(src, true, 'Appearance reset')
        sendSearchResults(src, charId)

    elseif action == 'giveStarterClothes' then
        local target = findOnlineSourceByCharId(charId)
        if not target then adminReply(src, false, 'Character must be online to receive starter clothes') return end

        local char = CMCharacters.GetCharacterById(charId)
        if not char then adminReply(src, false, 'Character not found') return end

        local appearance = {}
        if char.appearance_json and char.appearance_json ~= '' and char.appearance_json ~= 'null' then
            local ok, decoded = pcall(json.decode, char.appearance_json)
            if ok and type(decoded) == 'table' then appearance = decoded end
        end

        if type(CMCharacters.GiveStarterClothes) ~= 'function' then
            adminReply(src, false, 'Starter clothes helper is not loaded')
            return
        end

        CMCharacters.GiveStarterClothes(target, appearance)
        TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', target)
        CMCharacters.LogAdmin(src, 'admin_give_starter_clothes', { char_id = charId, target = target })
        adminReply(src, true, 'Starter clothes sent to online character')

    elseif action == 'refreshState' then
        local target = findOnlineSourceByCharId(charId)
        if not target then adminReply(src, false, 'Character is not online') return end
        local char = CMCharacters.GetCharacterById(charId)
        if not char then adminReply(src, false, 'Character not found') return end
        CMCharacters.SetCharacterState(target, char)
        TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', target)
        adminReply(src, true, 'Online character state refreshed')

    elseif action == 'setAccountSlots' then
        local accountId = CMCharacters.Trim(payload.accountId)
        local slots = tonumber(payload.maxSlots)
        if accountId == '' or not slots or slots < 1 or slots > 20 or math.floor(slots) ~= slots then
            adminReply(src, false, 'Invalid account or slot count')
            return
        end
        CMCharacters.Query([[
            INSERT INTO character_slot_limits (account_id, max_slots, reason, updated_by)
            VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE max_slots = VALUES(max_slots), reason = VALUES(reason), updated_by = VALUES(updated_by)
        ]], { accountId, slots, tostring(payload.reason or 'admin'), tostring(src) })
        CMCharacters.LogAdmin(src, 'admin_set_account_slots', { account_id = accountId, max_slots = slots })
        adminReply(src, true, 'Account slot limit updated')
        sendSearchResults(src, accountId)

    else
        adminReply(src, false, 'Unknown admin action')
    end
end)

RegisterCommand('charadmin', function(src)
    if not legacyAdminEnabled(src) then return end
    if not requireAdmin(src, 'characters.admin') then return end
    TriggerClientEvent('cm-characters:client:openAdmin', src)
    sendSearchResults(src, '')
end, false)


-- Safe exports for cm-admin. These keep staff UI ownership in cm-admin while
-- cm-characters owns the actual character database operations.
exports('AdminSearchCharacters', function(adminSource, query, limit)
    adminSource = tonumber(adminSource)
    if not hasCharacterAdminPermission(adminSource, 'characters.view') then return false, 'No permission' end
    return true, searchCharacters(query, limit)
end)

exports('AdminRefreshCharacterState', function(adminSource, charId)
    adminSource = tonumber(adminSource)
    if not hasCharacterAdminPermission(adminSource, 'characters.refresh') then return false, 'No permission' end
    charId = tostring(charId or '')
    local target = findOnlineSourceByCharId(charId)
    if not target then return false, 'Character is not online' end
    local char = CMCharacters.GetCharacterById(charId)
    if not char then return false, 'Character not found' end
    CMCharacters.SetCharacterState(target, char)
    CMCharacters.SyncWithPlayerData(target, tostring(char.id), 'admin_refresh_state')
    TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', target)
    CMCharacters.LogAdmin(adminSource, 'admin_refresh_character_state', { char_id = charId, target = target })
    return true, 'Character state refreshed'
end)

exports('AdminSetAccountSlots', function(adminSource, accountId, maxSlots, reason)
    adminSource = tonumber(adminSource)
    if not hasCharacterAdminPermission(adminSource, 'characters.slots') then return false, 'No permission' end
    accountId = CMCharacters.Trim(accountId)
    local slots = tonumber(maxSlots)
    if accountId == '' or not slots or slots < 1 or slots > 20 or math.floor(slots) ~= slots then
        return false, 'Invalid account or slot count'
    end
    CMCharacters.Query([[
        INSERT INTO character_slot_limits (account_id, max_slots, reason, updated_by)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE max_slots = VALUES(max_slots), reason = VALUES(reason), updated_by = VALUES(updated_by)
    ]], { accountId, slots, tostring(reason or 'cm-admin'), tostring(adminSource) })
    CMCharacters.LogAdmin(adminSource, 'admin_set_account_slots', { account_id = accountId, max_slots = slots })
    exports['cm-core']:CacheInvalidate('chars:' .. accountId)
    return true, 'Account slot limit updated'
end)
