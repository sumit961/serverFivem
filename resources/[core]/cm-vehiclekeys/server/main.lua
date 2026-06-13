local TempKeys = {}

local function normalizePlate(plate)
    return tostring(plate or ''):upper():gsub('%s+', '')
end

local function getCharacterId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    local ok, stateId = pcall(function()
        local st = Player(src).state
        return st.charId or st.characterId or st.character_id or st.citizenid
    end)
    if ok and stateId then return tostring(stateId) end

    local accountId
    pcall(function()
        local st = Player(src).state
        accountId = st.accountId or st.account_id or st.cmAccountId
    end)

    if accountId and MySQL then
        local okDb, dbCharId = pcall(function()
            return MySQL.scalar.await([[
                SELECT id FROM characters
                WHERE account_id = ?
                ORDER BY last_played DESC, updated_at DESC, created_at DESC
                LIMIT 1
            ]], { tostring(accountId) })
        end)
        if okDb and dbCharId then return tostring(dbCharId) end
    end

    return nil
end

local function notify(src, msg, msgType)
    TriggerClientEvent('cm-vehiclekeys:client:notify', src, msg or '', msgType or 'info')
end

local function hasTempKeyByChar(charId, plate)
    if not charId then return false end
    plate = normalizePlate(plate)
    return TempKeys[tostring(charId)] and TempKeys[tostring(charId)][plate] == true or false
end

local function giveTempKey(sourceSrc, targetSrc, plate)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc <= 0 or not GetPlayerName(targetSrc) then
        return false, 'Target player is not online.'
    end

    plate = normalizePlate(plate)
    if plate == '' then return false, 'Invalid plate.' end

    local targetCharId = getCharacterId(targetSrc)
    if not targetCharId then return false, 'Target character is not loaded.' end

    TempKeys[targetCharId] = TempKeys[targetCharId] or {}
    TempKeys[targetCharId][plate] = true

    notify(targetSrc, ('You received temporary keys for %s until you log out.'):format(plate), 'success')
    if sourceSrc and tonumber(sourceSrc) and tonumber(sourceSrc) > 0 then
        notify(tonumber(sourceSrc), ('Temporary key given for %s.'):format(plate), 'success')
    end

    return true
end

AddEventHandler('playerDropped', function()
    local src = source
    local charId = getCharacterId(src)
    if charId then
        TempKeys[tostring(charId)] = nil
    end
end)

RegisterNetEvent('cm-vehiclekeys:server:clearMyTempKeys', function()
    local src = source
    local charId = getCharacterId(src)
    if charId then TempKeys[tostring(charId)] = nil end
end)

exports('HasTempKey', function(src, plate)
    local charId = getCharacterId(src)
    return hasTempKeyByChar(charId, plate)
end)

exports('HasTempKeyByCharId', function(charId, plate)
    return hasTempKeyByChar(charId, plate)
end)

exports('GiveTempKey', function(sourceSrc, targetSrc, plate)
    return giveTempKey(sourceSrc, targetSrc, plate)
end)

exports('ClearTempKeys', function(src)
    local charId = getCharacterId(src)
    if charId then TempKeys[tostring(charId)] = nil end
    return true
end)

CreateThread(function()
    print('[CM-VEHICLEKEYS] Started v1.0.0')
end)
