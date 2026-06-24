-- cm-characters/server/slots.lua
-- Character slot list + selection. Sends character stats and appearance preview data to the UI/client.

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

    local rows = exports['cm-core']:Query(([[
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

RegisterNetEvent('cm-characters:server:getSlots', function(accountId)
    local src = source
    -- Always use the server-authoritative account ID to prevent spoofing.
    local stateAccountId = tostring(Player(src).state.accountId or '')
    if stateAccountId ~= '' then
        accountId = stateAccountId
    else
        accountId = tostring(accountId or '')
    end

    print('[CM-CHARACTERS] getSlots called for accountId="' .. accountId .. '"')

    local chars = exports['cm-core']:Query(
        'SELECT * FROM characters WHERE account_id = ? ORDER BY slot',
        {accountId}
    ) or {}

    print('[CM-CHARACTERS] Query returned ' .. tostring(#chars) .. ' rows')

    local maxCharacters = tonumber(Config and Config.MaxCharacters) or 2

    -- Object keys are more reliable for NUI than sparse Lua arrays with nil holes.
    local slots = {}
    for i = 1, maxCharacters do
        slots[tostring(i)] = nil
    end

    for _, char in ipairs(chars) do
        local slotNum = tonumber(char.slot)
        if slotNum and slotNum >= 1 and slotNum <= maxCharacters then
            local appearance = safeDecode(char.appearance_json)
            local gender = char.gender or ((tonumber(appearance.sex) == 1) and 'female' or 'male')
            local playtime = tonumber(char.playtime_minutes or char.playtime or 0) or 0

            slots[tostring(slotNum)] = {
                slot = slotNum,
                uniqueId = tostring(char.id),
                name = ((char.first_name or '') .. ' ' .. (char.last_name or '')):gsub('^%s+', ''):gsub('%s+$', ''),
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
                permanent = true,
                equipment = getCharacterEquipment(char.id),
                appearance = appearance
            }
            print('[CM-CHARACTERS] Added to slot ' .. slotNum .. ': ' .. slots[tostring(slotNum)].name)
        end
    end

    TriggerClientEvent('cm-characters:client:showSlots', src, slots, accountId, maxCharacters)
end)

RegisterNetEvent('cm-characters:server:selectCharacter', function(charId)
    local src = source
    -- Always return to public world before loading the real playable character.
    pcall(function() SetPlayerRoutingBucket(src, 0) end)
    pcall(function() Player(src).state:set('selectorBucket', 0, true) end)
    print('[CM-CHARACTERS] selectCharacter: ' .. tostring(charId))

    charId = tostring(charId)
    local char = exports['cm-core']:Query('SELECT * FROM characters WHERE id = ?', {charId})
    if not char or #char == 0 then
        TriggerClientEvent('cm-characters:client:error', src, 'Character not found')
        return
    end

    char = char[1]

    local accountId = tostring(Player(src).state.accountId or '')
    if accountId ~= '' and tostring(char.account_id) ~= accountId then
        TriggerClientEvent('cm-characters:client:error', src, 'This character does not belong to your account')
        return
    end

    local fixedCharId = tostring(char.id)
    Player(src).state:set('charId', fixedCharId, true)
    Player(src).state:set('characterId', fixedCharId, true)
    Player(src).state:set('isLoggedIn', true, true)
    Player(src).state:set('isInCharacterSelector', false, true)
    Player(src).state:set('characterFullySpawned', false, true)
    Player(src).state:set('skipPositionSave', true, true)

    TriggerEvent('cm-core:characterLoaded', src, fixedCharId)

    TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src)
    SetTimeout(1000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)
    SetTimeout(3000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)

    exports['cm-core']:Log('cm-characters', 'info', 'Character selected', {
        player_src = src,
        player_char_id = fixedCharId,
        name = (char.first_name or '') .. ' ' .. (char.last_name or '')
    })
end)
