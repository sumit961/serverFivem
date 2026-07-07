-- cm-characters/server/slots.lua
-- Character slot list + secure selection. Uses server-side account state only.

local function safeDecode(jsonText)
    if not jsonText or jsonText == '' then return {} end
    local ok, decoded = pcall(json.decode, jsonText)
    if ok and type(decoded) == 'table' then return decoded end
    return {}
end

local function getCharacterLevel(char)
    return tonumber(char.level or char.character_level or char.current_level or char.xp_level or char.current_rank_id or 1) or 1
end

local function getCharacterRank(char)
    return char.rank_name or char.rank or char.current_rank_id or 'Civilian'
end

local EQUIPMENT_SLOTS = {
    'mask', 'glasses', 'headwear', 'earrings',
    'shirt', 'outerwear', 'bodyarmor', 'bag',
    'accessory', 'weapon', 'ammo', 'watch', 'pants', 'shoes'
}

local function rowToEquipmentItem(row)
    local metadata = safeDecode(row.metadata)
    return {
        id = row.id,
        slot = row.slot,
        item_name = row.item_name,
        name = row.item_name,
        label = metadata.label or row.item_name,
        quantity = tonumber(row.quantity) or 1,
        metadata = metadata
    }
end

local function getCharacterEquipment(characterId)
    local placeholders = {}
    for _ = 1, #EQUIPMENT_SLOTS do placeholders[#placeholders + 1] = '?' end

    local params = { 'character', tostring(characterId) }
    for _, slot in ipairs(EQUIPMENT_SLOTS) do params[#params + 1] = slot end

    local rows = CMCharacters.Query(([[
        SELECT id, slot, item_name, quantity, metadata
        FROM inventory_items
        WHERE owner_type = ?
          AND owner_id = ?
          AND slot IN (%s)
    ]]):format(table.concat(placeholders, ',')), params) or {}

    local equipment = {}
    for _, row in ipairs(rows) do
        if row.slot then
            equipment[tostring(row.slot)] = rowToEquipmentItem(row)
        end
    end

    return equipment
end

RegisterNetEvent('cm-characters:server:getSlots', function(_clientAccountId)
    local src = source
    local accountId = CMCharacters.RequireAccount(src)
    if not accountId then
        TriggerClientEvent('cm-characters:client:error', src, 'Not logged in')
        return
    end

    local maxCharacters = CMCharacters.GetMaxCharacters(accountId)
    print('[CM-CHARACTERS] getSlots secure accountId="' .. accountId .. '" max=' .. tostring(maxCharacters))

    local chars = CMCharacters.Query(
        'SELECT * FROM characters WHERE account_id = ? ORDER BY slot',
        { accountId }
    ) or {}

    local slots = {}
    for i = 1, maxCharacters do slots[tostring(i)] = nil end

    for _, char in ipairs(chars) do
        local slotNum = tonumber(char.slot)
        if slotNum and slotNum >= 1 and slotNum <= maxCharacters then
            local appearance = safeDecode(char.appearance_json)
            local gender = char.gender or ((tonumber(appearance.sex) == 1) and 'female' or 'male')
            local playtime = tonumber(char.playtime_minutes or char.playtime or 0) or 0

            slots[tostring(slotNum)] = {
                slot = slotNum,
                uniqueId = tostring(char.id),
                charId = tostring(char.id),
                name = CMCharacters.CharacterFullName(char),
                firstName = char.first_name or '',
                lastName = char.last_name or '',
                dob = char.dob or '',
                gender = gender,
                cash = tonumber(char.cash or 0) or 0,
                bank = tonumber(char.bank or 0) or 0,
                level = getCharacterLevel(char),
                rank = getCharacterRank(char),
                playtime = playtime,
                created = char.created_at,
                lastSeen = char.last_seen,
                permanent = true,
                equipment = getCharacterEquipment(char.id),
                appearance = appearance
            }
        end
    end

    TriggerClientEvent('cm-characters:client:showSlots', src, slots, accountId, maxCharacters)
end)

RegisterNetEvent('cm-characters:server:selectCharacter', function(charId)
    local src = source
    pcall(function() SetPlayerRoutingBucket(src, 0) end)
    pcall(function() Player(src).state:set('selectorBucket', 0, true) end)

    charId = tostring(charId or '')
    if charId == '' then
        TriggerClientEvent('cm-characters:client:error', src, 'Invalid character ID')
        return
    end

    local char, accountId, err = CMCharacters.GetOwnedCharacter(src, charId)
    if not char then
        TriggerClientEvent('cm-characters:client:error', src, err or 'Character not found')
        return
    end

    CMCharacters.SetCharacterState(src, char)
    Player(src).state:set('isInCharacterSelector', false, true)
    Player(src).state:set('characterFullySpawned', false, true)
    Player(src).state:set('skipPositionSave', true, true)

    CMCharacters.Query('UPDATE characters SET last_seen = CURRENT_TIMESTAMP WHERE id = ?', { tostring(char.id) })
    exports['cm-core']:CacheInvalidate('char:' .. tostring(char.id))

    TriggerEvent('cm-core:characterLoaded', src, tostring(char.id))

    TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src)
    SetTimeout(1000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)
    SetTimeout(3000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)

    exports['cm-core']:Log('cm-characters', 'info', 'Character selected', {
        player_src = src,
        account_id = accountId,
        player_char_id = tostring(char.id),
        name = CMCharacters.CharacterFullName(char)
    })
end)
