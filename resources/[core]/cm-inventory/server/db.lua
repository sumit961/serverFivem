-- cm-inventory/db.lua
-- Split from legacy server/main.lua. Loaded by server/main.lua bootloader in this exact order.

local Config = CMInventory.Config
local UseableItems = {}
local notify

local function dprint(...)
    if not Config.Debug then return end
    print('[CM-INVENTORY]', ...)
end

local function toNumber(value, default)
    local n = tonumber(value)
    if not n then return default end
    return n
end

local function encode(value)
    return json.encode(value or {})
end

local function decode(value)
    if type(value) == 'table' then return value end
    if not value or value == '' then return {} end
    local ok, result = pcall(json.decode, value)
    if ok and type(result) == 'table' then return result end
    return {}
end

local function normalizeExportArgs(...)
    -- Supports both export call styles:
    --   exports['cm-inventory'].AddItem(src, item, amount, metadata, reason, slot)
    --   exports['cm-inventory']:AddItem(src, item, amount, metadata, reason, slot)
    -- The colon style passes a hidden `self` as arg #1. The old normalizer only accepted
    -- six parameters, so the preferred equipment slot (`outerwear`, `pants`, `shoes`)
    -- was dropped and starter clothes fell into normal inventory instead of being worn.
    local args = { ... }

    if type(args[1]) == 'table' and args[2] ~= nil then
        table.remove(args, 1)
    end

    if type(args[1]) ~= 'number' and type(args[2]) == 'number' then
        -- itemName, src, amount, metadata, reason, slot -> src, itemName, amount, metadata, reason, slot
        return args[2], args[1], args[3], args[4], args[5], args[6]
    end

    if type(args[1]) ~= 'number' and type(args[3]) == 'number' then
        -- itemName, amount, src, metadata, reason, slot -> src, itemName, amount, metadata, reason, slot
        return args[3], args[1], args[2], args[4], args[5], args[6]
    end

    -- Compatibility guard for old/bad callers:
    -- AddItem(src, item, amount, nil, metadata)
    -- or AddItem(src, item, amount, metadata, metadata, reason).
    -- Metadata must always end up in arg #4, otherwise bags are saved as plain/default bags.
    if args[4] == nil and type(args[5]) == 'table' then
        args[4] = args[5]
        args[5] = 'metadata_arg5_compat'
    elseif type(args[4]) == 'table' and type(args[5]) == 'table' then
        -- cm-items intentionally duplicates metadata into arg #5 for compatibility.
        -- Keep arg #4 as metadata and move reason to arg #6 when present.
        args[5] = type(args[6]) == 'string' and args[6] or 'metadata_arg4_arg5_compat'
        args[6] = args[7]
    end

    return args[1], args[2], args[3], args[4], args[5], args[6]
end

local function ensureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS inventory_items (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            owner_type VARCHAR(50) NOT NULL DEFAULT 'character',
            owner_id VARCHAR(100) NOT NULL,
            slot VARCHAR(50) NOT NULL,
            item_name VARCHAR(100) NOT NULL,
            quantity INT NOT NULL DEFAULT 1,
            metadata LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY unique_owner_slot (owner_type, owner_id, slot),
            INDEX idx_owner (owner_type, owner_id),
            INDEX idx_item_name (item_name)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS inventory_audit (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            character_id VARCHAR(100) NULL,
            action VARCHAR(50) NOT NULL,
            item_name VARCHAR(100) NULL,
            quantity INT NULL,
            from_slot VARCHAR(50) NULL,
            to_slot VARCHAR(50) NULL,
            reason VARCHAR(100) NULL,
            metadata LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_character (character_id),
            INDEX idx_action (action),
            INDEX idx_item_name (item_name)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS inventory_drops (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            item_name VARCHAR(100) NOT NULL,
            quantity INT NOT NULL DEFAULT 1,
            metadata LONGTEXT NULL,
            x DOUBLE NOT NULL,
            y DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            created_by VARCHAR(100) NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP NULL,
            INDEX idx_expires (expires_at),
            INDEX idx_item_name (item_name)
        )
    ]])
end

local function audit(ownerId, action, itemName, qty, fromSlot, toSlot, reason, metadata)
    pcall(function()
        MySQL.insert.await([[INSERT INTO inventory_audit
            (character_id, action, item_name, quantity, from_slot, to_slot, reason, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)]], {
            tostring(ownerId or ''), action, itemName, qty, fromSlot, toSlot, reason, encode(metadata)
        })
    end)
end

local function getIdentifier(src, prefix)
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if not prefix or identifier:sub(1, #prefix + 1) == prefix .. ':' then
            return identifier
        end
    end
    return nil
end

local function getOwnerId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    local pState = Player(src).state
    local stateId = pState.charId or pState.characterId or pState.citizenid or pState.character_id
    if stateId then return tostring(stateId) end

    local ok, player = pcall(function()
        if GetResourceState('cm-core') == 'started' and exports['cm-core'].GetPlayer then
            return exports['cm-core'].GetPlayer(src)
        end
    end)
    if ok and type(player) == 'table' then
        if player.CharacterId then return tostring(player.CharacterId) end
        if player.charId then return tostring(player.charId) end
        if player.Character and player.Character.id then return tostring(player.Character.id) end
        if player.character and player.character.id then return tostring(player.character.id) end
        if player.Data and player.Data.character_id then return tostring(player.Data.character_id) end
    end

    -- Do NOT call cm-characters export here. Some older cm-characters exports
    -- are colon-style only and can throw when called by another resource.
    -- Instead, resolve from player/account state or database.
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

    -- Last fallback for dev/testing. This keeps inventory working even if
    -- character state is missing, but real servers should ensure charId is set.
    return getIdentifier(src, 'license') or ('src_' .. tostring(src))
end

local function getOwner(src)
    return Config.OwnerType or 'character', getOwnerId(src)
end
