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

local function safeItemCall(method, ...)
    if GetResourceState('cm-items') ~= 'started' then return nil end
    local args = { ... }
    local ok, result = pcall(function()
        if exports['cm-items'][method] then
            return exports['cm-items'][method](table.unpack(args))
        end
    end)
    if ok and result ~= nil then return result end

    ok, result = pcall(function()
        if exports['cm-items'][method] then
            return exports['cm-items'][method](exports['cm-items'], table.unpack(args))
        end
    end)
    if ok and result ~= nil then return result end
    return nil
end

local function getItemDef(itemName)
    itemName = tostring(itemName or ''):lower()
    if itemName == '' then return nil end

    local def = safeItemCall('GetItem', itemName)
    if type(def) == 'table' then
        def.name = def.name or itemName
        def.label = def.label or def.item_name or itemName
        def.category = def.category or def.type or 'misc'
        def.weight = tonumber(def.weight) or 0
        def.stack = def.stack ~= false and def.unique ~= true
        def.image = def.image or def.icon or Config.DefaultImages[itemName] or 'placeholder.png'
        def.description = def.description or ''
        return def
    end

    def = Config.FallbackItems[itemName]
    if type(def) == 'table' then
        local copy = {}
        for k, v in pairs(def) do copy[k] = v end
        copy.name = itemName
        copy.label = copy.label or itemName
        copy.category = copy.category or 'misc'
        copy.weight = tonumber(copy.weight) or 0
        copy.stack = copy.stack ~= false and copy.unique ~= true
        copy.image = copy.image or Config.DefaultImages[itemName] or 'placeholder.png'
        copy.description = copy.description or ''
        return copy
    end

    return nil
end

local function isInventoryItem(itemName)
    itemName = tostring(itemName or ''):lower()
    if itemName == '' then return false, 'Invalid item.' end
    if Config.BlockedInventoryItems[itemName] then return false, 'This item is managed by another system.' end

    local virtual = safeItemCall('IsVirtualItem', itemName)
    if virtual == true then return false, 'This item is virtual and cannot go in inventory.' end

    local allowed = safeItemCall('IsInventoryItem', itemName)
    if allowed == true then return true end
    if allowed == false then
        -- cm-items v1 had export mismatch in some installs; allow fallback physical items.
        if Config.FallbackItems[itemName] then return true end
        local def = getItemDef(itemName)
        if def and def.virtual ~= true and def.inventory ~= false then return true end
        return false, 'This item cannot go in inventory.'
    end

    local def = getItemDef(itemName)
    if not def then return false, 'Unknown item.' end
    if def.virtual == true or def.inventory == false then return false, 'This item cannot go in inventory.' end
    return true
end

local function allSlots()
    local slots = {}
    for i = 1, Config.Slots.quick.count do slots[#slots + 1] = Config.Slots.quick.prefix .. i end
    for i = 1, Config.Slots.pockets.count do slots[#slots + 1] = Config.Slots.pockets.prefix .. i end
    for i = 1, Config.Slots.backpack.count do slots[#slots + 1] = Config.Slots.backpack.prefix .. i end
    for _, slot in ipairs(Config.Slots.equipment) do slots[#slots + 1] = slot end
    return slots
end

local function isValidSlot(slot)
    if type(slot) ~= 'string' or slot == '' or #slot > 50 then return false end
    for _, s in ipairs(allSlots()) do if s == slot then return true end end
    return false
end

local function isEquipmentSlot(slot)
    for _, s in ipairs(Config.Slots.equipment) do if s == slot then return true end end
    return false
end

local function canPlaceInSlot(itemName, slot)
    if not isValidSlot(slot) then return false, 'Invalid slot.' end
    if not isEquipmentSlot(slot) then return true end

    itemName = tostring(itemName or ''):lower()
    local def = getItemDef(itemName)
    if not def then return false, 'Unknown item.' end

    -- Accept multiple fields because cm-items / inventory packages may name the category differently.
    local category = tostring(def.category or ''):lower()
    local itemType = tostring(def.type or ''):lower()
    local equipSlot = tostring(def.equipmentSlot or def.equipSlot or def.slot or ''):lower()
    local rules = Config.EquipmentRules[slot]
    if not rules then return true end

    for _, allowedRaw in ipairs(rules) do
        local allowed = tostring(allowedRaw):lower()
        if category == allowed or itemType == allowed or itemName == allowed or equipSlot == allowed then
            return true
        end
    end

    -- Extra compatibility aliases.
    if itemName:find('clothing_', 1, true) == 1 then
        local suffix = itemName:gsub('^clothing_', '')
        local clothingSlots = {
            tshirt = 'shirt', torso = 'outerwear', pants = 'pants', legs = 'pants', shoes = 'shoes',
            chains = 'accessory', bags = 'bag', hat = 'headwear', glasses = 'glasses',
            earrings = 'earrings', watches = 'watch'
        }
        if clothingSlots[suffix] == slot then return true end
    end

    if slot == 'bodyarmor' and (itemName == 'armor' or itemName == 'body_armor' or itemName == 'bodyarmor' or itemName:find('armor', 1, true)) then
        return true
    end
    if slot == 'weapon' and itemName:find('weapon_', 1, true) == 1 then
        return true
    end
    if slot == 'ammo' and (itemName:find('ammo_', 1, true) == 1 or itemName:find('ammo', 1, true)) then
        return true
    end

    return false, ('%s cannot be placed in %s. category=%s type=%s'):format(def.label or itemName, slot, category, itemType)
end

local function getItemRarity(def, metadata)
    local rarity = metadata.rarity or metadata.itemType or metadata.type or def.rarity or def.itemType or def.quality or 'normal'
    rarity = tostring(rarity or 'normal'):lower()
    if rarity ~= 'rare' and rarity ~= 'unique' then rarity = 'normal' end
    return rarity
end

local function getItemDurability(def, metadata)
    local durability = metadata.durability or def.durability
    if durability == nil then return nil end
    durability = tonumber(durability)
    if not durability then return nil end
    if durability < 0 then durability = 0 end
    if durability > 100 then durability = 100 end
    return math.floor(durability)
end

local function rowToItem(row)
    local def = getItemDef(row.item_name) or { label = row.item_name, weight = 0, category = 'misc', image = 'placeholder.png', stack = true, description = '' }
    local metadata = decode(row.metadata)
    local rarity = getItemRarity(def, metadata)
    local durability = getItemDurability(def, metadata)
    return {
        id = row.id,
        slot = row.slot,
        item_name = row.item_name,
        name = row.item_name,
        label = metadata.label or def.label or row.item_name,
        category = def.category or def.type or 'misc',
        type = def.type or def.category or 'misc',
        itemType = rarity,
        rarity = rarity,
        image = metadata.image or metadata.icon or def.image or def.icon or 'placeholder.png',
        icon = metadata.icon or metadata.image or def.image or def.icon or 'placeholder.png',
        quantity = tonumber(row.quantity) or 1,
        weight = tonumber(def.weight) or 0,
        stack = def.stack ~= false and def.unique ~= true,
        usable = def.usable == true,
        description = metadata.description or def.description or '',
        durability = durability,
        metadata = metadata,
        equipmentSlot = def.equipmentSlot or def.equipSlot,
        bagLevel = tonumber(metadata.bagLevel or metadata.bag_level or metadata.level or metadata.backpackLevel or metadata.backpack_level or def.bagLevel or def.bag_level or def.level) or 0
    }
end

local function getRows(ownerType, ownerId)
    return MySQL.query.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY slot ASC', { ownerType, tostring(ownerId) }) or {}
end

local function getItemAt(ownerType, ownerId, slot)
    return MySQL.single.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? AND slot = ? LIMIT 1', {
        ownerType, tostring(ownerId), slot
    })
end

local function getUsedWeight(ownerType, ownerId)
    local rows = getRows(ownerType, ownerId)
    local weight = 0
    for _, row in ipairs(rows) do
        local def = getItemDef(row.item_name)
        weight = weight + ((def and tonumber(def.weight) or 0) * (tonumber(row.quantity) or 1))
    end
    return weight
end

local function getBagLevelFromItem(row)
    if not row then return 0 end
    local metadata = decode(row.metadata)
    local def = getItemDef(row.item_name) or {}
    local level = tonumber(
        metadata.bagLevel or metadata.bag_level or metadata.level or
        metadata.backpackLevel or metadata.backpack_level or
        def.bagLevel or def.bag_level or def.level
    )
    if level then return math.max(0, math.min(4, math.floor(level))) end

    local name = tostring(row.item_name or ''):lower()
    local fromName = name:match('bag_level(%d)') or name:match('backpack_level(%d)') or name:match('bag(%d)')
    if fromName then return math.max(0, math.min(4, tonumber(fromName) or 0)) end
    return 0
end

local function getBagInfo(ownerType, ownerId)
    local bagRow = getItemAt(ownerType, ownerId, 'bag')
    local level = getBagLevelFromItem(bagRow)
    local cfg = Config.BagLevels and Config.BagLevels[level] or nil
    if not cfg then cfg = Config.BagLevels and Config.BagLevels[0] or { label = 'No Bag', backpackSlots = 0, maxWeight = Config.Weight.max } end
    return {
        level = level,
        label = cfg.label or ('Bag Level ' .. tostring(level)),
        backpackSlots = tonumber(cfg.backpackSlots or cfg.slots) or 0,
        maxWeight = tonumber(cfg.maxWeight or cfg.weight) or (Config.Weight and Config.Weight.max) or 25000
    }
end

local function isBackpackSlot(slot)
    return type(slot) == 'string' and slot:find(Config.Slots.backpack.prefix, 1, true) == 1
end

local function backpackSlotIndex(slot)
    if not isBackpackSlot(slot) then return nil end
    return tonumber(slot:sub(#Config.Slots.backpack.prefix + 1))
end

local function isSlotUnlocked(ownerType, ownerId, slot)
    if not isBackpackSlot(slot) then return true end
    local idx = backpackSlotIndex(slot)
    if not idx then return false end
    local bag = getBagInfo(ownerType, ownerId)
    return idx <= (bag.backpackSlots or 0)
end

local function getMaxWeight(ownerType, ownerId)
    return getBagInfo(ownerType, ownerId).maxWeight
end


-- Bag transition safety:
-- Changing/removing a bag can reduce unlocked backpack slots and max weight.
-- We block the action unless every backpack slot that would become locked is empty
-- after the move/swap, and the current inventory weight fits the new capacity.
local function getBagConfigByLevel(level)
    level = math.max(0, math.min(4, tonumber(level) or 0))
    local cfg = Config.BagLevels and Config.BagLevels[level] or nil
    if not cfg then cfg = Config.BagLevels and Config.BagLevels[0] or { label = 'No Bag', backpackSlots = 0, maxWeight = Config.Weight.max } end
    return {
        level = level,
        label = cfg.label or ('Bag Level ' .. tostring(level)),
        backpackSlots = tonumber(cfg.backpackSlots or cfg.slots) or 0,
        maxWeight = tonumber(cfg.maxWeight or cfg.weight) or (Config.Weight and Config.Weight.max) or 25000
    }
end

local function rowCanActAsBag(row)
    if not row then return false end
    local name = tostring(row.item_name or ''):lower()
    -- clothing_bags carries bagLevel in its metadata and acts as a real bag.
    -- All other clothing_* items are not bags.
    if name:find('clothing_', 1, true) == 1 then
        return name == 'clothing_bags' and getBagLevelFromItem(row) > 0
    end
    if getBagLevelFromItem(row) > 0 then return true end
    local ok = false
    pcall(function()
        ok = canPlaceInSlot(row.item_name, 'bag') == true
    end)
    return ok == true
end

local function validatePostBagState(ownerType, ownerId, newLevel, sourceRow, destRow, fromSlot, toSlot)
    local cfg = getBagConfigByLevel(newLevel)
    local allowedBackpackSlots = cfg.backpackSlots or 0

    local rows = getRows(ownerType, ownerId)
    for _, row in ipairs(rows) do
        local finalSlot = row.slot

        if sourceRow and tonumber(row.id) == tonumber(sourceRow.id) then
            finalSlot = toSlot
        elseif destRow and tonumber(row.id) == tonumber(destRow.id) then
            finalSlot = fromSlot
        end

        local idx = backpackSlotIndex(finalSlot)
        if idx and idx > allowedBackpackSlots then
            local label = row.item_name or 'item'
            return false, ('Cannot change/remove bag. Empty backpack slot %s first. It contains %s and would become locked.'):format(finalSlot, label)
        end
    end

    local currentWeight = getUsedWeight(ownerType, ownerId)
    if currentWeight > (cfg.maxWeight or 25000) then
        return false, ('Cannot change/remove bag. Inventory weight %.1fkg exceeds %s capacity %.1fkg.'):format(currentWeight / 1000.0, cfg.label, (cfg.maxWeight or 0) / 1000.0)
    end

    return true
end

local function validateBagTransition(ownerType, ownerId, fromSlot, toSlot, sourceRow, destRow)
    -- Only the bag slot changes backpack limits. Normal inventory moves are unaffected.
    if fromSlot ~= 'bag' and toSlot ~= 'bag' then return true end
    if not sourceRow then return true end

    local currentBag = getBagInfo(ownerType, ownerId)
    local newLevel = currentBag.level or 0

    if toSlot == 'bag' then
        -- Equipping/replacing bag: the source item becomes the active bag.
        if not rowCanActAsBag(sourceRow) then return true end
        newLevel = getBagLevelFromItem(sourceRow)
    elseif fromSlot == 'bag' then
        -- Removing current bag, or swapping with another bag from destination.
        if destRow and rowCanActAsBag(destRow) then
            newLevel = getBagLevelFromItem(destRow)
        else
            newLevel = 0
        end
    end

    return validatePostBagState(ownerType, ownerId, newLevel, sourceRow, destRow, fromSlot, toSlot)
end

local function validateBagRemovalFromSlot(ownerType, ownerId, slot, row)
    if slot ~= 'bag' or not rowCanActAsBag(row) then return true end
    -- Dropping/giving/consuming the active bag means new level 0.
    return validatePostBagState(ownerType, ownerId, 0, row, nil, slot, nil)
end

local function buildInventoryPayload(src)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return nil, 'No character owner found.' end

    local rows = getRows(ownerType, ownerId)
    local items = {}
    for _, row in ipairs(rows) do items[#items + 1] = rowToItem(row) end

    return {
        ownerType = ownerType,
        ownerId = tostring(ownerId),
        items = items,
        weight = {
            current = getUsedWeight(ownerType, ownerId),
            max = getMaxWeight(ownerType, ownerId)
        },
        bag = getBagInfo(ownerType, ownerId),
        slots = Config.Slots
    }
end

local function sendInventory(src, forceOpen)
    local payload, err = buildInventoryPayload(src)
    if not payload then
        TriggerClientEvent('cm-inventory:client:notify', src, err or 'Could not load inventory.', 'error')
        return false
    end

    -- forceOpen=true is only used when the player explicitly opens inventory.
    -- Item add/pickup/use/drop should refresh the UI only if it is already open,
    -- not pop the inventory open by itself.
    if forceOpen == true then
        TriggerClientEvent('cm-inventory:client:open', src, payload)
    else
        TriggerClientEvent('cm-inventory:client:update', src, payload)
    end

    return true
end

local function findEmptySlot(ownerType, ownerId)
    for i = 1, Config.Slots.pockets.count do
        local slot = Config.Slots.pockets.prefix .. i
        if not getItemAt(ownerType, ownerId, slot) then return slot end
    end

    local bag = getBagInfo(ownerType, ownerId)
    for i = 1, math.min(Config.Slots.backpack.count, bag.backpackSlots or 0) do
        local slot = Config.Slots.backpack.prefix .. i
        if not getItemAt(ownerType, ownerId, slot) then return slot end
    end
    return nil
end

local function canCarry(ownerType, ownerId, itemName, amount)
    local def = getItemDef(itemName)
    if not def then return false, 'Unknown item.' end
    local addWeight = (tonumber(def.weight) or 0) * (tonumber(amount) or 1)
    if getUsedWeight(ownerType, ownerId) + addWeight > getMaxWeight(ownerType, ownerId) then
        return false, 'Inventory is too heavy. Upgrade/equip a better bag.'
    end
    return true
end

local function randomSerial(prefix)
    prefix = prefix or 'CM'
    return ('%s-%06d'):format(prefix, math.random(100000, 999999))
end

local function decorateNewItemMetadata(itemName, metadata, def, hadCustomMetadata)
    metadata = type(metadata) == 'table' and metadata or {}
    def = def or getItemDef(itemName) or {}

    local lowerName = tostring(itemName or ''):lower()
    local itemRarity = tostring(metadata.rarity or metadata.itemType or def.rarity or def.itemType or 'normal'):lower()
    if itemRarity ~= 'rare' and itemRarity ~= 'unique' then itemRarity = 'normal' end

    -- Keep normal stackable items clean so water/ammo/bandage can merge.
    local isStackable = def.stack ~= false and def.unique ~= true
    local needsMetadata = hadCustomMetadata == true
        or itemRarity ~= 'normal'
        or def.durability ~= nil
        or def.bagLevel ~= nil
        or lowerName:find('weapon_', 1, true) == 1
        or lowerName == 'armor' or lowerName == 'body_armor' or lowerName == 'bodyarmor' or lowerName:find('armor', 1, true) ~= nil

    if isStackable and not needsMetadata then
        return metadata
    end

    metadata.rarity = metadata.rarity or metadata.itemType or itemRarity
    metadata.itemType = metadata.itemType or metadata.rarity
    metadata.createdAt = metadata.createdAt or os.date('!%Y-%m-%dT%H:%M:%SZ')

    if def.durability and metadata.durability == nil then
        metadata.durability = tonumber(def.durability) or 100
    end
    if lowerName:find('weapon_', 1, true) == 1 then
        metadata.serial = metadata.serial or randomSerial('WPN')
        metadata.durability = metadata.durability or 100
    end
    if lowerName == 'armor' or lowerName == 'body_armor' or lowerName == 'bodyarmor' or lowerName:find('armor', 1, true) ~= nil then
        metadata.durability = metadata.durability or 100
    end
    if metadata.bagLevel == nil then
        local defLevel = tonumber(def.bagLevel or def.bag_level or def.level)
        if defLevel then metadata.bagLevel = math.max(1, math.min(4, math.floor(defLevel))) end
    end
    if metadata.bagLevel ~= nil then
        metadata.bagLevel = math.max(1, math.min(4, math.floor(tonumber(metadata.bagLevel) or 1)))
        metadata.bag_level = nil
        metadata.level = nil
    end

    return metadata
end

local function AddItemInternal(src, itemName, amount, metadata, reason, preferredSlot)
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return false, 'Invalid amount.' end
    itemName = tostring(itemName or ''):lower()
    metadata = type(metadata) == 'table' and metadata or {}
    local hadCustomMetadata = next(metadata) ~= nil

    local allowed, err = isInventoryItem(itemName)
    if not allowed then return false, err end

    local def = getItemDef(itemName)
    if not def then return false, 'Unknown item.' end
    metadata = decorateNewItemMetadata(itemName, metadata, def, hadCustomMetadata)
    if itemName == 'clothing_bags' then
        print(('[CM-INVENTORY] AddItem clothing_bags amount=%s metadata=%s bagLevel=%s image=%s'):format(
            tostring(amount), tostring(json.encode(metadata or {})), tostring((metadata or {}).bagLevel), tostring((metadata or {}).image or (metadata or {}).icon)
        ))
    end

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end

    local okCarry, carryErr = canCarry(ownerType, ownerId, itemName, amount)
    if not okCarry then return false, carryErr end

    local slot = preferredSlot
    if slot and not canPlaceInSlot(itemName, slot) then slot = nil end

    if def.stack ~= false and next(metadata) == nil and not slot then
        local existing = MySQL.single.await([[SELECT * FROM inventory_items
            WHERE owner_type = ? AND owner_id = ? AND item_name = ? AND (metadata IS NULL OR metadata = '' OR metadata = '{}')
            ORDER BY FIELD(SUBSTRING_INDEX(slot, '-', 1), 'pocket', 'backpack', 'quickaccess') LIMIT 1]], {
            ownerType, tostring(ownerId), itemName
        })
        if existing then
            MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { amount, existing.id })
            audit(ownerId, 'add_stack', itemName, amount, nil, existing.slot, reason, metadata)
            return true, existing.slot
        end
    end

    if not slot then slot = findEmptySlot(ownerType, ownerId) end
    if not slot then return false, 'No empty slot. Equip a better bag to unlock more backpack slots.' end
    if not isSlotUnlocked(ownerType, ownerId, slot) then return false, 'That backpack slot is locked by your bag level.' end

    local canSlot, slotErr = canPlaceInSlot(itemName, slot)
    if not canSlot then return false, slotErr end

    local existingAtSlot = getItemAt(ownerType, ownerId, slot)
    if existingAtSlot then return false, 'Slot is already occupied.' end

    MySQL.insert.await([[INSERT INTO inventory_items
        (owner_type, owner_id, slot, item_name, quantity, metadata)
        VALUES (?, ?, ?, ?, ?, ?)]], {
        ownerType, tostring(ownerId), slot, itemName, amount, encode(metadata)
    })
    audit(ownerId, 'add', itemName, amount, nil, slot, reason, metadata)
    return true, slot
end

local function RemoveItemInternal(src, itemName, amount, metadata, reason)
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return false, 'Invalid amount.' end
    itemName = tostring(itemName or ''):lower()

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end

    local rows = MySQL.query.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? AND item_name = ? ORDER BY quantity DESC', {
        ownerType, tostring(ownerId), itemName
    }) or {}

    local remaining = amount
    for _, row in ipairs(rows) do
        if remaining <= 0 then break end
        local qty = tonumber(row.quantity) or 0
        local take = math.min(qty, remaining)
        if take >= qty then
            MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { row.id })
        else
            MySQL.update.await('UPDATE inventory_items SET quantity = quantity - ? WHERE id = ?', { take, row.id })
        end
        remaining = remaining - take
    end

    if remaining > 0 then return false, 'Not enough item.' end
    audit(ownerId, 'remove', itemName, amount, nil, nil, reason, metadata)
    return true
end

local function HasItemInternal(src, itemName, amount)
    amount = tonumber(amount) or 1
    itemName = tostring(itemName or ''):lower()
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false end
    local count = MySQL.scalar.await('SELECT COALESCE(SUM(quantity), 0) FROM inventory_items WHERE owner_type = ? AND owner_id = ? AND item_name = ?', {
        ownerType, tostring(ownerId), itemName
    }) or 0
    return tonumber(count) >= amount, tonumber(count)
end


local function syncEquipmentSlot(src, slot)
    if not isEquipmentSlot(slot) then return end
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return end
    local row = getItemAt(ownerType, ownerId, slot)
    local item = row and rowToItem(row) or nil
    TriggerClientEvent('cm-inventory:client:equipmentSlot', src, slot, item)
end

local function syncAllEquipment(src)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return end
    local payload = {}
    for _, slot in ipairs(Config.Slots.equipment) do
        local row = getItemAt(ownerType, ownerId, slot)
        payload[slot] = row and rowToItem(row) or nil
    end
    TriggerClientEvent('cm-inventory:client:setEquipment', src, payload)
end

local CLOTHING_SLOT_BY_CATEGORY = {
    tshirt = 'shirt', torso = 'outerwear', pants = 'pants', legs = 'pants', shoes = 'shoes',
    chains = 'accessory', bags = 'bag', hat = 'headwear', glasses = 'glasses',
    earrings = 'earrings', watches = 'watch'
}

local function isClothingItemName(itemName)
    itemName = tostring(itemName or ''):lower()
    return itemName:find('clothing_', 1, true) == 1
end

local function getClothingCategory(itemName, metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local category = tostring(metadata.categoryType or metadata.category or ''):lower()
    if category == '' then category = tostring(itemName or ''):lower():gsub('^clothing_', '') end
    return category
end

local function getClothingEquipSlot(itemName, metadata)
    return CLOTHING_SLOT_BY_CATEGORY[getClothingCategory(itemName, metadata)]
end

local function saveAppearance(src)
    if GetResourceState('cm-characters') == 'started' then
        pcall(function() exports['cm-characters']:SaveAppearance(src) end)
    end
end

local function MoveItemInternal(src, fromSlot, toSlot)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(fromSlot) or not isValidSlot(toSlot) then return false, 'Invalid slot.' end
    if not isSlotUnlocked(ownerType, ownerId, toSlot) then return false, 'That backpack slot is locked by your bag level.' end
    if fromSlot == toSlot then return true end

    local source = getItemAt(ownerType, ownerId, fromSlot)
    if not source then return false, 'Source slot is empty.' end

    local canSlot, slotErr = canPlaceInSlot(source.item_name, toSlot)
    if not canSlot then return false, slotErr end

    local dest = getItemAt(ownerType, ownerId, toSlot)
    local sourceItem = rowToItem(source)

    local bagOk, bagErr = validateBagTransition(ownerType, ownerId, fromSlot, toSlot, source, dest)
    if not bagOk then return false, bagErr end

    if not dest then
        MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { toSlot, source.id })
        audit(ownerId, 'move', source.item_name, source.quantity, fromSlot, toSlot, 'move', {})
        syncEquipmentSlot(src, fromSlot)
        syncEquipmentSlot(src, toSlot)
        if (isEquipmentSlot(toSlot) or isEquipmentSlot(fromSlot)) and isClothingItemName(source.item_name) then
            -- syncEquipmentSlot already applied/cleared the visual clothing on the client.
            -- Save once after the DB move, not once per client-side apply event.
            saveAppearance(src)
        end
        return true
    end

    local destItem = rowToItem(dest)
    if source.item_name == dest.item_name and sourceItem.stack and destItem.stack then
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { source.quantity, dest.id })
        MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { source.id })
        audit(ownerId, 'merge', source.item_name, source.quantity, fromSlot, toSlot, 'move_merge', {})
        syncEquipmentSlot(src, fromSlot)
        syncEquipmentSlot(src, toSlot)
        if isEquipmentSlot(fromSlot) and isClothingItemName(source.item_name) then
            saveAppearance(src)
        end
        return true
    end

    local canBack, backErr = canPlaceInSlot(dest.item_name, fromSlot)
    if not canBack then return false, backErr end

    local tempSlot = ('__tmp_%s_%s'):format(source.id, math.random(1000, 9999))
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { tempSlot, source.id })
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { fromSlot, dest.id })
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { toSlot, source.id })
    audit(ownerId, 'swap', source.item_name, source.quantity, fromSlot, toSlot, 'move_swap', {})
    syncEquipmentSlot(src, fromSlot)
    syncEquipmentSlot(src, toSlot)
    if (isEquipmentSlot(toSlot) and isClothingItemName(source.item_name))
        or (isEquipmentSlot(fromSlot) and isClothingItemName(dest.item_name)) then
        saveAppearance(src)
    end
    return true
end

local function SplitItemInternal(src, fromSlot, toSlot, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return false, 'Invalid split amount.' end
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(fromSlot) or not isValidSlot(toSlot) then return false, 'Invalid slot.' end
    if not isSlotUnlocked(ownerType, ownerId, toSlot) then return false, 'That backpack slot is locked by your bag level.' end

    local source = getItemAt(ownerType, ownerId, fromSlot)
    if not source then return false, 'Source slot is empty.' end
    if getItemAt(ownerType, ownerId, toSlot) then return false, 'Target slot is not empty.' end
    if tonumber(source.quantity) <= amount then return false, 'Split amount is too high.' end
    local def = getItemDef(source.item_name)
    if def and def.stack == false then return false, 'This item cannot be split.' end
    local canSlot, slotErr = canPlaceInSlot(source.item_name, toSlot)
    if not canSlot then return false, slotErr end

    MySQL.update.await('UPDATE inventory_items SET quantity = quantity - ? WHERE id = ?', { amount, source.id })
    MySQL.insert.await([[INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata)
        VALUES (?, ?, ?, ?, ?, ?)]], { ownerType, tostring(ownerId), toSlot, source.item_name, amount, source.metadata or '{}' })
    audit(ownerId, 'split', source.item_name, amount, fromSlot, toSlot, 'split_stack', decode(source.metadata))
    return true
end

local createWorldDrop, sendDrops, cleanupDrops

local function DropItemInternal(src, slot, amount)
    amount = math.floor(tonumber(amount) or 1)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(slot) then return false, 'Invalid slot.' end

    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end

    local bagOk, bagErr = validateBagRemovalFromSlot(ownerType, ownerId, slot, row)
    if not bagOk then return false, bagErr end

    local qty = tonumber(row.quantity) or 0
    local drop = math.min(qty, amount)
    if drop < 1 then return false, 'Invalid drop amount.' end

    if drop >= qty then
        MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { row.id })
    else
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity - ? WHERE id = ?', { drop, row.id })
    end

    local dropId = createWorldDrop(src, row, drop)
    audit(ownerId, 'drop', row.item_name, drop, slot, nil, dropId and ('world_drop_' .. dropId) or 'drop_item', decode(row.metadata))
    if dropId then sendDrops(-1) end
    return true
end

local function ConsumeSlotItemInternal(src, slot, amount, reason)
    amount = math.floor(tonumber(amount) or 1)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(slot) then return false, 'Invalid slot.' end

    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end

    local bagOk, bagErr = validateBagRemovalFromSlot(ownerType, ownerId, slot, row)
    if not bagOk then return false, bagErr end

    local qty = tonumber(row.quantity) or 0
    local consume = math.min(qty, amount)
    if consume < 1 then return false, 'Invalid amount.' end

    if consume >= qty then
        MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { row.id })
    else
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity - ? WHERE id = ?', { consume, row.id })
    end
    audit(ownerId, reason or 'consume', row.item_name, consume, slot, nil, reason or 'consume_item', decode(row.metadata))
    return true
end

local function runUsableHandler(src, itemName, item, handler)
    -- Same-resource direct Lua function handler. Useful for built-in/test actions.
    if type(handler) == 'function' then
        local completed = false
        local result = { success = false, remove = 0, message = nil }

        local function done(ok, removeAmount, msg)
            completed = true
            result.success = ok == true
            result.remove = tonumber(removeAmount) or 0
            result.message = msg
        end

        local ok, retSuccess, retRemove, retMessage = pcall(handler, src, item, done)
        if not ok then return false, 0, tostring(retSuccess) end

        -- Also support: return true, 1, 'message'
        if not completed and type(retSuccess) == 'boolean' then
            done(retSuccess, retRemove, retMessage)
        end

        if not completed then return false, 0, 'Usable item handler did not call done().' end
        return result.success, result.remove, result.message
    end

    -- Cross-resource handler. This is the recommended future-proof style.
    -- handler = { resource = 'cm-itemactions', export = 'UseItem' }
    if type(handler) == 'table' then
        local resource = tostring(handler.resource or '')
        local exportName = tostring(handler.export or '')

        if resource == '' or exportName == '' then
            return false, 0, 'Usable item handler is invalid.'
        end

        if GetResourceState(resource) ~= 'started' then
            return false, 0, ('Usable item resource is not started: %s'):format(resource)
        end

        local ok, result = pcall(function()
            return exports[resource][exportName](itemName, src, item)
        end)

        if not ok then return false, 0, tostring(result) end
        if type(result) ~= 'table' then return false, 0, 'Usable item export did not return a result table.' end

        return result.success == true, tonumber(result.remove or result.removeAmount) or 0, result.message
    end

    return false, 0, 'No usable handler found.'
end

local ReloadWeaponInternal

local function isWeaponItemName(itemName)
    itemName = tostring(itemName or ''):lower()
    return itemName:find('weapon_', 1, true) == 1
end

local function isAmmoItemName(itemName)
    itemName = tostring(itemName or ''):lower()
    return itemName:find('ammo_', 1, true) == 1 or itemName:find('ammo', 1, true) ~= nil
end

local function isArmorItemName(itemName)
    itemName = tostring(itemName or ''):lower()
    return itemName == 'armor' or itemName == 'body_armor' or itemName == 'bodyarmor' or itemName:find('armor', 1, true) ~= nil
end


local function findFirstAmmoStack(ownerType, ownerId, ammoName, includeAmmoSlot)
    ammoName = tostring(ammoName or ''):lower()
    if ammoName == '' then return nil end

    local ammoSlot = (Config.Ammo and Config.Ammo.slot) or 'ammo'

    if includeAmmoSlot then
        local row = getItemAt(ownerType, ownerId, ammoSlot)
        if row and tostring(row.item_name or ''):lower() == ammoName and (tonumber(row.quantity) or 0) > 0 then
            return row
        end
    end

    -- Player inventory order: quick slots, pockets, backpack, then equipment.
    -- Skip weapon slot and optionally skip ammo slot so we can move the first normal stack into ammo slot.
    for _, slot in ipairs(allSlots()) do
        if slot ~= 'weapon' and (includeAmmoSlot or slot ~= ammoSlot) then
            local row = getItemAt(ownerType, ownerId, slot)
            if row and tostring(row.item_name or ''):lower() == ammoName and (tonumber(row.quantity) or 0) > 0 then
                return row
            end
        end
    end

    return nil
end

local function getEquippedWeaponAmmoConfig(ownerType, ownerId)
    local weaponRow = getItemAt(ownerType, ownerId, 'weapon')
    if not weaponRow then return nil, nil, 'No weapon equipped.' end

    local weaponName = tostring(weaponRow.item_name or ''):lower()
    local weaponCfg = Config.Ammo and Config.Ammo.weapons and Config.Ammo.weapons[weaponName]
    if not weaponCfg then return nil, weaponName, 'This weapon has no ammo config.' end

    return weaponCfg, weaponName, nil
end

local function EnsureAmmoSlotForWeaponInternal(src)
    if Config.Ammo and Config.Ammo.enabled == false then
        return false, 'Ammo system is disabled.'
    end

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end

    local ammoSlot = (Config.Ammo and Config.Ammo.slot) or 'ammo'
    local weaponCfg, weaponName, cfgErr = getEquippedWeaponAmmoConfig(ownerType, ownerId)
    if not weaponCfg then return false, cfgErr or 'No weapon ammo config.' end

    local requiredAmmo = tostring(weaponCfg.ammo or ''):lower()
    if requiredAmmo == '' then return false, 'Weapon ammo type is missing.' end

    local ammoAtSlot = getItemAt(ownerType, ownerId, ammoSlot)
    if ammoAtSlot and tostring(ammoAtSlot.item_name or ''):lower() == requiredAmmo and (tonumber(ammoAtSlot.quantity) or 0) > 0 then
        return true, ('%s is already in ammo slot.'):format(requiredAmmo), ammoAtSlot
    end

    local found = findFirstAmmoStack(ownerType, ownerId, requiredAmmo, false)
    if not found then
        if ammoAtSlot then
            return false, ('Ammo slot has %s, but %s is required.'):format(tostring(ammoAtSlot.item_name or 'unknown'), requiredAmmo)
        end
        return false, ('No %s found in inventory.'):format(requiredAmmo)
    end

    local fromSlot = tostring(found.slot)
    local moved, moveErr = MoveItemInternal(src, fromSlot, ammoSlot)
    if not moved then
        return false, moveErr or ('Could not move %s to ammo slot.'):format(requiredAmmo)
    end

    local newAmmoRow = getItemAt(ownerType, ownerId, ammoSlot)
    audit(ownerId, 'ammo_slot_fill', requiredAmmo, tonumber(found.quantity) or 1, fromSlot, ammoSlot, weaponName, decode(found.metadata))
    return true, ('Moved %s from %s to ammo slot.'):format(requiredAmmo, fromSlot), newAmmoRow
end

local function saveRowMetadata(rowId, metadata)
    MySQL.update.await('UPDATE inventory_items SET metadata = ? WHERE id = ?', { encode(metadata), rowId })
end

local function setSlotDurability(ownerType, ownerId, slot, durability)
    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false end
    local metadata = decode(row.metadata)
    durability = math.max(0, math.min(100, math.floor(tonumber(durability) or 0)))
    metadata.durability = durability
    saveRowMetadata(row.id, metadata)
    return true, durability
end

local function reduceSlotDurability(ownerType, ownerId, slot, amount)
    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end
    local metadata = decode(row.metadata)
    local current = tonumber(metadata.durability)
    if current == nil then current = tonumber((getItemDef(row.item_name) or {}).durability) or 100 end
    current = math.max(0, current - (tonumber(amount) or 1))
    metadata.durability = math.floor(current)
    saveRowMetadata(row.id, metadata)
    return true, current
end

local function isBagItemName(itemName)
    itemName = tostring(itemName or ''):lower()
    if itemName:find('bag_level', 1, true) == 1 or itemName:find('backpack', 1, true) ~= nil then return true end
    local def = getItemDef(itemName) or {}
    local category = tostring(def.category or ''):lower()
    local equipSlot = tostring(def.equipmentSlot or def.equipSlot or ''):lower()
    return category == 'bag' or equipSlot == 'bag' or tonumber(def.bagLevel) ~= nil
end

local function UseItemInternal(src, slot)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(slot) then return false, 'Invalid slot.' end

    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end

    local item = rowToItem(row)
    local itemName = tostring(item.item_name or ''):lower()
    local ammoSlot = (Config.Ammo and Config.Ammo.slot) or 'ammo'

    -- USE bag first. `clothing_bags` is both clothing and a real backpack, so bag capacity
    -- must be resolved before the generic clothing branch catches it.
    if isBagItemName(itemName) then
        if slot ~= 'bag' then
            local moved, moveErr = MoveItemInternal(src, slot, 'bag')
            if not moved then return false, moveErr or 'Could not equip bag.' end
        else
            syncEquipmentSlot(src, 'bag')
            saveAppearance(src)
        end
        local bag = getBagInfo(ownerType, ownerId)
        notify(src, ('%s equipped. Backpack slots: %s / %s'):format(bag.label, bag.backpackSlots, Config.Slots.backpack.count), 'success')
        audit(ownerId, 'use_bag', itemName, 1, slot, 'bag', 'equip_bag', item.metadata)
        return true
    end

    -- USE clothing = move it to the matching clothing/equipment slot. Dragging to that slot uses the same visual equip logic.
    if isClothingItemName(itemName) then
        local targetSlot = getClothingEquipSlot(itemName, item.metadata)
        if not targetSlot then return false, 'This clothing category has no inventory slot.' end

        if slot ~= targetSlot then
            local moved, moveErr = MoveItemInternal(src, slot, targetSlot)
            if not moved then return false, moveErr or 'Could not equip clothing.' end
        else
            TriggerClientEvent('cm-inventory:client:equipClothingFromItem', src, targetSlot, item)
            saveAppearance(src)
        end

        notify(src, ('Equipped %s.'):format(item.label or itemName), 'success')
        audit(ownerId, 'use_clothing', itemName, 1, slot, targetSlot, 'equip_clothing_slot', item.metadata)
        return true
    end

    -- USE weapon = equip weapon slot, then move the first matching ammo stack into ammo slot.
    -- Ammo is NOT consumed on use/reload. It is consumed only from inventory when the player shoots.
    if isWeaponItemName(itemName) then
        local moved, moveErr = MoveItemInternal(src, slot, 'weapon')
        if not moved then return false, moveErr or 'Could not equip weapon.' end
        syncEquipmentSlot(src, 'weapon')

        local ammoReady, ammoMsg = EnsureAmmoSlotForWeaponInternal(src)
        if ammoReady then
            notify(src, ('Weapon equipped. %s'):format(ammoMsg or ''), 'success')
        else
            notify(src, ('Weapon equipped. %s'):format(ammoMsg or 'No ammo moved.'), 'info')
        end

        audit(ownerId, 'use_weapon', itemName, 1, slot, 'weapon', 'use_weapon_inventory_ammo', item.metadata)
        return true
    end

    -- USE armor = equip into the body armor slot and apply armor on the character.
    -- Armor item is not deleted; it becomes equipped in the bodyarmor slot.
    if isArmorItemName(itemName) then
        if slot ~= 'bodyarmor' then
            local moved, moveErr = MoveItemInternal(src, slot, 'bodyarmor')
            if not moved then return false, moveErr or 'Could not equip armor.' end
        end

        syncEquipmentSlot(src, 'bodyarmor')
        notify(src, 'Body armor equipped.', 'success')
        audit(ownerId, 'use_armor', itemName, 1, slot, 'bodyarmor', 'use_armor_equip', item.metadata)
        return true
    end

    -- USE ammo = move ammo to ammo slot only. It does not reload or consume ammo.
    if isAmmoItemName(itemName) then
        if slot ~= ammoSlot then
            local moved, moveErr = MoveItemInternal(src, slot, ammoSlot)
            if not moved then return false, moveErr or 'Could not move ammo to ammo slot.' end
            notify(src, ('Moved %s to ammo slot.'):format(item.label or itemName), 'success')
            audit(ownerId, 'use_ammo_move_to_slot', itemName, tonumber(row.quantity) or 1, slot, ammoSlot, 'use_ammo', item.metadata)
            return true
        end

        notify(src, 'Ammo is ready in ammo slot. It will be used from inventory when you shoot.', 'info')
        return true
    end

    local handler = UseableItems[itemName]

    if item.usable ~= true and not handler then
        return false, 'Item is not usable.'
    end

    if not handler then
        notify(src, (item.label or itemName) .. ' has no use effect registered yet.', 'info')
        return true
    end

    local success, consumeAmount, message = runUsableHandler(src, itemName, item, handler)

    if not success then
        return false, message or 'Item use failed.'
    end

    consumeAmount = tonumber(consumeAmount) or 0
    if consumeAmount > 0 then
        local consumed, consumeErr = ConsumeSlotItemInternal(src, slot, consumeAmount, 'use_consume')
        if not consumed then return false, consumeErr or 'Could not consume item.' end
    end

    audit(ownerId, 'use', itemName, consumeAmount > 0 and consumeAmount or 1, slot, nil, 'use_item', item.metadata)
    TriggerEvent('cm-inventory:server:itemUsed', src, item, consumeAmount)

    if message and message ~= '' then
        notify(src, message, 'success')
    end

    return true
end

ReloadWeaponInternal = function(src)
    -- Reload key is intentionally disabled for this RP inventory system.
    -- Ammo is kept in inventory and consumed one-by-one when the player shoots.
    return false, 'Manual reload is disabled. Ammo is used from inventory while shooting.'
end

local function ConsumeEquippedWeaponAmmoInternal(src)
    if Config.Ammo and Config.Ammo.enabled == false then
        return false, 'Ammo system is disabled.'
    end

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end

    local ammoSlot = (Config.Ammo and Config.Ammo.slot) or 'ammo'
    local weaponCfg, weaponName, cfgErr = getEquippedWeaponAmmoConfig(ownerType, ownerId)
    if not weaponCfg then return false, cfgErr or 'No weapon ammo config.' end

    local requiredAmmo = tostring(weaponCfg.ammo or ''):lower()
    if requiredAmmo == '' then return false, 'Weapon ammo type is missing.' end

    local ammoRow = getItemAt(ownerType, ownerId, ammoSlot)
    if not ammoRow or tostring(ammoRow.item_name or ''):lower() ~= requiredAmmo then
        return false, ('%s is not in ammo slot.'):format(requiredAmmo)
    end

    local available = tonumber(ammoRow.quantity) or 0
    if available <= 0 then return false, 'No ammo available.' end

    local weaponRow = getItemAt(ownerType, ownerId, 'weapon')
    if weaponRow then
        local wmeta = decode(weaponRow.metadata)
        local durability = tonumber(wmeta.durability) or tonumber((getItemDef(weaponRow.item_name) or {}).durability) or 100
        if durability <= 0 then return false, 'Weapon durability is 0%.' end
    end

    local consumed, consumeErr = ConsumeSlotItemInternal(src, ammoSlot, 1, 'weapon_shot')
    if not consumed then return false, consumeErr or 'Could not consume ammo.' end

    reduceSlotDurability(ownerType, ownerId, 'weapon', 1)
    audit(ownerId, 'weapon_shot', requiredAmmo, 1, ammoSlot, 'weapon', weaponName, {})
    return true, 'Ammo consumed from inventory.'
end

local function getClosestPlayer(src, maxDistance)
    maxDistance = tonumber(maxDistance) or 3.0
    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return nil, nil end

    local srcCoords = GetEntityCoords(srcPed)
    local closest, closestDist = nil, maxDistance + 0.01

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and target ~= tonumber(src) then
            local targetPed = GetPlayerPed(target)
            if targetPed and targetPed ~= 0 then
                local targetCoords = GetEntityCoords(targetPed)
                local dx = srcCoords.x - targetCoords.x
                local dy = srcCoords.y - targetCoords.y
                local dz = srcCoords.z - targetCoords.z
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist < closestDist then
                    closest = target
                    closestDist = dist
                end
            end
        end
    end

    return closest, closestDist
end

local function GiveItemInternal(src, slot, amount)
    if Config.Give and Config.Give.enabled == false then return false, 'Giving items is disabled.' end

    amount = tonumber(amount) or 1
    if amount < 1 then return false, 'Invalid amount.' end

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(slot) then return false, 'Invalid slot.' end

    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end

    local available = tonumber(row.quantity) or 1
    if amount > available then return false, 'Not enough items.' end

    local target, distance = getClosestPlayer(src, (Config.Give and Config.Give.distance) or 3.0)
    if not target then return false, 'No nearby player found.' end

    local metadata = decode(row.metadata)
    local targetOwnerType, targetOwnerId = getOwner(target)
    if not targetOwnerId then return false, 'Nearby player has no active character.' end

    local carryOk, carryReason = canCarry(targetOwnerType, targetOwnerId, row.item_name, amount)
    if not carryOk then return false, 'Receiver cannot carry item: ' .. tostring(carryReason) end

    local consumed, consumeErr = ConsumeSlotItemInternal(src, slot, amount, 'give_item')
    if not consumed then return false, consumeErr or 'Could not remove item.' end

    local added, addReason = AddItemInternal(target, row.item_name, amount, metadata, 'received_from_player')
    if not added then
        -- rollback to sender where possible
        AddItemInternal(src, row.item_name, amount, metadata, 'give_rollback')
        return false, addReason or 'Could not give item.'
    end

    audit(ownerId, 'give_item', row.item_name, amount, slot, nil, ('to_player_%s'):format(target), metadata)
    audit(targetOwnerId, 'receive_item', row.item_name, amount, nil, nil, ('from_player_%s'):format(src), metadata)

    notify(src, ('Gave %sx %s.'):format(amount, row.item_name), 'success')
    notify(target, ('Received %sx %s.'):format(amount, row.item_name), 'success')
    sendInventory(src)
    sendInventory(target)
    return true
end



-- =========================================================
-- Dev give-transfer self-test helpers
-- Lets one developer test the same remove/add transfer logic
-- without needing a second player online.
-- =========================================================
local function AddItemToOwnerContainer(ownerType, ownerId, itemName, amount, metadata, reason, preferredSlot)
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return false, 'Invalid amount.' end

    ownerType = tostring(ownerType or '')
    ownerId = tostring(ownerId or '')
    itemName = tostring(itemName or ''):lower()
    metadata = type(metadata) == 'table' and metadata or {}

    if ownerType == '' or ownerId == '' then return false, 'Invalid target container.' end

    local allowed, err = isInventoryItem(itemName)
    if not allowed then return false, err end

    local def = getItemDef(itemName)
    if not def then return false, 'Unknown item.' end

    local okCarry, carryErr = canCarry(ownerType, ownerId, itemName, amount)
    if not okCarry then return false, carryErr end

    local slot = preferredSlot
    if slot and not canPlaceInSlot(itemName, slot) then slot = nil end

    if def.stack ~= false and next(metadata) == nil and not slot then
        local existing = MySQL.single.await([[SELECT * FROM inventory_items
            WHERE owner_type = ? AND owner_id = ? AND item_name = ? AND (metadata IS NULL OR metadata = '' OR metadata = '{}')
            ORDER BY FIELD(SUBSTRING_INDEX(slot, '-', 1), 'pocket', 'backpack', 'quickaccess') LIMIT 1]], {
            ownerType, ownerId, itemName
        })
        if existing then
            MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { amount, existing.id })
            audit(ownerId, 'dev_add_stack', itemName, amount, nil, existing.slot, reason or 'dev_test_add', metadata)
            return true, existing.slot
        end
    end

    if not slot then slot = findEmptySlot(ownerType, ownerId) end
    if not slot then return false, 'No empty slot in test receiver.' end

    local canSlot, slotErr = canPlaceInSlot(itemName, slot)
    if not canSlot then return false, slotErr end

    local existingAtSlot = getItemAt(ownerType, ownerId, slot)
    if existingAtSlot then return false, 'Slot is already occupied.' end

    MySQL.insert.await([[INSERT INTO inventory_items
        (owner_type, owner_id, slot, item_name, quantity, metadata)
        VALUES (?, ?, ?, ?, ?, ?)]], {
        ownerType, ownerId, slot, itemName, amount, encode(metadata)
    })
    audit(ownerId, 'dev_add', itemName, amount, nil, slot, reason or 'dev_test_add', metadata)
    return true, slot
end

local function GetFirstPlayerItemByName(src, itemName)
    itemName = tostring(itemName or ''):lower()
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return nil, 'No character owner found.' end

    local row = MySQL.single.await([[SELECT * FROM inventory_items
        WHERE owner_type = ? AND owner_id = ? AND item_name = ?
        ORDER BY quantity DESC, id ASC LIMIT 1]], {
        ownerType, tostring(ownerId), itemName
    })

    if not row then return nil, 'You do not have ' .. itemName end
    return row, ownerId
end

local function DevGiveTestInternal(src, itemName, amount)
    if not src or src <= 0 then return false, 'Use this in-game from F8.' end
    itemName = tostring(itemName or 'water'):lower()
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return false, 'Invalid amount.' end

    local row, ownerIdOrReason = GetFirstPlayerItemByName(src, itemName)
    if not row then return false, ownerIdOrReason end

    local available = tonumber(row.quantity) or 0
    if available < amount then return false, ('You only have %sx %s.'):format(available, itemName) end

    local metadata = decode(row.metadata)
    local removed, removeReason = RemoveItemInternal(src, itemName, amount, metadata, 'dev_givetest_remove')
    if not removed then return false, removeReason or 'Could not remove item from player.' end

    local testOwnerType = 'test_receiver'
    local testOwnerId = 'dev_receiver_1'
    local added, addReason = AddItemToOwnerContainer(testOwnerType, testOwnerId, itemName, amount, metadata, 'dev_givetest_add')
    if not added then
        AddItemInternal(src, itemName, amount, metadata, 'dev_givetest_refund')
        return false, 'Test receiver add failed, item refunded: ' .. tostring(addReason)
    end

    audit(ownerIdOrReason, 'dev_give_test_out', itemName, amount, nil, nil, testOwnerType .. '/' .. testOwnerId, metadata)
    audit(testOwnerId, 'dev_give_test_in', itemName, amount, nil, nil, 'from_player_' .. tostring(src), metadata)
    return true, ('Give test success: moved %sx %s to test_receiver/dev_receiver_1.'):format(amount, itemName)
end

local function ShowTestReceiverInternal(src)
    local rows = MySQL.query.await([[SELECT slot, item_name, quantity, metadata FROM inventory_items
        WHERE owner_type = ? AND owner_id = ? ORDER BY slot ASC]], { 'test_receiver', 'dev_receiver_1' }) or {}

    if #rows == 0 then
        local msg = 'Test receiver is empty.'
        if src and src > 0 then notify(src, msg, 'info') end
        print('[CM-INVENTORY] ' .. msg)
        return rows
    end

    print('[CM-INVENTORY] Test receiver contents:')
    local brief = {}
    for _, row in ipairs(rows) do
        local line = ('%s: %sx %s'):format(row.slot, tonumber(row.quantity) or 0, row.item_name)
        print('[CM-INVENTORY]   ' .. line)
        brief[#brief + 1] = line
    end

    if src and src > 0 then
        notify(src, ('Test receiver: %s'):format(table.concat(brief, ' | ')), 'info')
    end
    return rows
end

local function ClearTestReceiverInternal(src)
    local affected = MySQL.update.await('DELETE FROM inventory_items WHERE owner_type = ? AND owner_id = ?', {
        'test_receiver', 'dev_receiver_1'
    }) or 0
    local msg = ('Cleared test receiver. Removed %s rows.'):format(tostring(affected))
    print('[CM-INVENTORY] ' .. msg)
    if src and src > 0 then notify(src, msg, 'success') end
    return true
end

local function dropToPayload(row)
    local def = getItemDef(row.item_name) or { label = row.item_name, image = 'placeholder.png', weight = 0, category = 'misc' }
    local metadata = decode(row.metadata)
    return {
        id = tonumber(row.id),
        item_name = row.item_name,
        name = row.item_name,
        label = def.label or row.item_name,
        image = metadata.image or metadata.icon or def.image or def.icon or 'placeholder.png',
        icon = metadata.icon or metadata.image or def.image or def.icon or 'placeholder.png',
        quantity = tonumber(row.quantity) or 1,
        weight = tonumber(def.weight) or 0,
        category = def.category or def.type or 'misc',
        metadata = metadata,
        coords = { x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) }
    }
end

cleanupDrops = function()
    MySQL.update.await('DELETE FROM inventory_drops WHERE expires_at IS NOT NULL AND expires_at <= NOW()', {})
end

local function getActiveDrops()
    cleanupDrops()
    local rows = MySQL.query.await('SELECT * FROM inventory_drops WHERE expires_at IS NULL OR expires_at > NOW() ORDER BY id DESC LIMIT 250', {}) or {}
    local drops = {}
    for _, row in ipairs(rows) do drops[#drops + 1] = dropToPayload(row) end
    return drops
end

sendDrops = function(target)
    TriggerClientEvent('cm-inventory:client:updateDrops', target or -1, getActiveDrops())
end

createWorldDrop = function(src, row, amount)
    if not Config.Drops or Config.Drops.enabled == false then return nil end
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local ownerType, ownerId = getOwner(src)
    local expireMinutes = tonumber(Config.Drops.expireMinutes) or 10
    local id = MySQL.insert.await([[INSERT INTO inventory_drops
        (item_name, quantity, metadata, x, y, z, created_by, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? MINUTE))]], {
        row.item_name,
        amount,
        row.metadata or '{}',
        coords.x,
        coords.y,
        coords.z - 0.9,
        tostring(ownerId or ownerType or src),
        expireMinutes
    })
    return id
end

local function PickupDropInternal(src, dropId)
    dropId = tonumber(dropId)
    if not dropId then return false, 'Invalid drop.' end

    cleanupDrops()
    local row = MySQL.single.await('SELECT * FROM inventory_drops WHERE id = ? AND (expires_at IS NULL OR expires_at > NOW()) LIMIT 1', { dropId })
    if not row then return false, 'Drop no longer exists.' end

    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local dx, dy, dz = coords.x - tonumber(row.x), coords.y - tonumber(row.y), coords.z - tonumber(row.z)
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > (tonumber(Config.Drops.pickupDistance) or 2.0) + 1.0 then
        return false, 'You are too far from the drop.'
    end

    local metadata = decode(row.metadata)
    local ok, reason = AddItemInternal(src, row.item_name, tonumber(row.quantity) or 1, metadata, 'pickup_drop')
    if not ok then return false, reason end

    MySQL.update.await('DELETE FROM inventory_drops WHERE id = ?', { dropId })
    local _, ownerId = getOwner(src)
    audit(ownerId, 'pickup_drop', row.item_name, tonumber(row.quantity) or 1, nil, nil, 'pickup_drop', metadata)
    sendDrops(-1)
    return true
end

notify = function(src, message, typeName)
    TriggerClientEvent('cm-inventory:client:notify', src, tostring(message or ''), typeName or 'info')
end

RegisterNetEvent('cm-inventory:server:openInventory', function()
    local src = source
    sendInventory(src, true)
end)

RegisterNetEvent('cm-inventory:server:debugPing', function()
    dprint(('debugPing received from player %s'):format(source))
end)

RegisterNetEvent('cm-inventory:server:requestDrops', function()
    sendDrops(source)
end)

RegisterNetEvent('cm-inventory:server:requestEquipment', function()
    syncAllEquipment(source)
end)

RegisterNetEvent('cm-inventory:server:pickupDrop', function(dropId)
    local src = source
    local ok, reason = PickupDropInternal(src, dropId)
    if ok then
        notify(src, 'Picked up item.', 'success')
        sendInventory(src)
    else
        notify(src, reason or 'Could not pick up drop.', 'error')
        sendDrops(src)
    end
end)


RegisterNetEvent('cm-inventory:server:armorChanged', function(armorValue)
    local src = source
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return end
    local ok, newDur = setSlotDurability(ownerType, ownerId, 'bodyarmor', tonumber(armorValue) or 0)
    if ok then
        audit(ownerId, 'armor_durability_update', 'armor', 1, 'bodyarmor', 'bodyarmor', tostring(newDur), { durability = newDur })
        sendInventory(src)
    end
end)

RegisterNetEvent('cm-inventory:server:debugGiveItem', function(itemName, amount)
    local src = source
    amount = tonumber(amount) or 1
    itemName = tostring(itemName or 'water'):lower()
    dprint(('debugGiveItem called by player %s: %sx %s'):format(src, amount, itemName))
    local ok, reason = AddItemInternal(src, itemName, amount, {}, 'debug_testgive')
    if ok then
        dprint(('debugGiveItem added %sx %s to player %s'):format(amount, itemName, src))
        notify(src, ('Added %sx %s'):format(amount, itemName), 'success')
        sendInventory(src)
    else
        dprint(('debugGiveItem failed for player %s item=%s reason=%s'):format(src, itemName, tostring(reason)))
        notify(src, 'Failed: ' .. tostring(reason), 'error')
    end
end)

RegisterNetEvent('cm-inventory:server:moveItem', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local fromSlot = tostring(data.fromSlot or '')
    local toSlot = tostring(data.toSlot or '')
    dprint(('moveItem requested by player %s: %s -> %s'):format(src, fromSlot, toSlot))
    local ok, reason = MoveItemInternal(src, fromSlot, toSlot)
    if ok then
        dprint(('moveItem success for player %s: %s -> %s'):format(src, fromSlot, toSlot))
        notify(src, 'Item moved.', 'success')
    else
        dprint(('moveItem failed for player %s: %s -> %s reason=%s'):format(src, fromSlot, toSlot, tostring(reason)))
        notify(src, reason or 'Move failed.', 'error')
    end
    sendInventory(src)
end)

RegisterNetEvent('cm-inventory:server:splitItem', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local ok, reason = SplitItemInternal(src, tostring(data.fromSlot or ''), tostring(data.toSlot or ''), tonumber(data.amount) or 0)
    if not ok then notify(src, reason or 'Split failed.', 'error') end
    sendInventory(src)
end)

RegisterNetEvent('cm-inventory:server:dropItem', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local ok, reason = DropItemInternal(src, tostring(data.slot or ''), tonumber(data.amount) or 1)
    if not ok then notify(src, reason or 'Drop failed.', 'error') end
    sendInventory(src)
end)

local UseCooldowns = {}

local function getUseProgress(itemName)
    itemName = tostring(itemName or ''):lower()
    local cfg = Config.Use or {}
    local progress = cfg.progress and cfg.progress[itemName]
    if type(progress) == 'table' then
        return tonumber(progress.ms) or 0, progress.label or 'Using item...'
    end
    return tonumber(cfg.defaultProgressMs) or 0, 'Using item...'
end

local function checkUseCooldown(src, itemName)
    itemName = tostring(itemName or ''):lower()
    local cfg = Config.Use or {}
    local cooldown = cfg.cooldowns and cfg.cooldowns[itemName] or cfg.defaultCooldownMs or 0
    cooldown = tonumber(cooldown) or 0
    if cooldown <= 0 then return true end

    local key = tostring(src) .. ':' .. itemName
    local now = GetGameTimer()
    local untilTime = UseCooldowns[key] or 0
    if untilTime > now then
        return false, ('Wait %.1fs before using this again.'):format((untilTime - now) / 1000)
    end
    UseCooldowns[key] = now + cooldown
    return true
end

local function UseItemWithProgress(src, slot)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(slot) then return false, 'Invalid slot.' end
    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end
    local itemName = tostring(row.item_name or ''):lower()

    local cdOk, cdMsg = checkUseCooldown(src, itemName)
    if not cdOk then return false, cdMsg end

    local progressMs, progressLabel = getUseProgress(itemName)
    if progressMs > 0 then
        TriggerClientEvent('cm-inventory:client:useProgress', src, progressLabel, progressMs)
        Wait(progressMs)
    end

    return UseItemInternal(src, slot)
end

RegisterNetEvent('cm-inventory:server:useItem', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local ok, reason = UseItemWithProgress(src, tostring(data.slot or ''))
    if not ok then notify(src, reason or 'Use failed.', 'error') end
    sendInventory(src)
end)

RegisterNetEvent('cm-inventory:server:reloadWeapon', function()
    local src = source
    local ok, reason = ReloadWeaponInternal(src)
    if ok then
        notify(src, reason or 'Weapon reloaded.', 'success')
    else
        notify(src, reason or 'Reload failed.', 'error')
    end
    sendInventory(src)
end)

RegisterNetEvent('cm-inventory:server:weaponShot', function()
    local src = source
    local ok, reason = ConsumeEquippedWeaponAmmoInternal(src)
    if not ok then
        TriggerClientEvent('cm-inventory:client:noInventoryAmmo', src, reason or 'No ammo available.')
        return
    end
    sendInventory(src)
end)

RegisterNetEvent('cm-inventory:server:giveItem', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local ok, reason = GiveItemInternal(src, tostring(data.slot or ''), tonumber(data.amount) or 1)
    if not ok then
        notify(src, reason or 'Give failed.', 'error')
        sendInventory(src)
    end
end)


RegisterNetEvent('cm-inventory:server:devGiveTest', function(itemName, amount)
    local src = source
    local ok, message = DevGiveTestInternal(src, itemName, amount)
    if ok then
        dprint(message)
        notify(src, message, 'success')
        sendInventory(src)
    else
        dprint(('givetest failed for player %s item=%s reason=%s'):format(src, tostring(itemName), tostring(message)))
        notify(src, 'Give test failed: ' .. tostring(message), 'error')
    end
end)

RegisterNetEvent('cm-inventory:server:showTestReceiver', function()
    ShowTestReceiverInternal(source)
end)

RegisterNetEvent('cm-inventory:server:clearTestReceiver', function()
    ClearTestReceiverInternal(source)
end)

RegisterCommand('giveitem', function(src, args)
    if src <= 0 then print('[CM-INVENTORY] Use invgive from server console.') return end
    local itemName = tostring(args[1] or 'water'):lower()
    local amount = tonumber(args[2]) or 1
    local ok, reason = AddItemInternal(src, itemName, amount, {}, 'command_giveitem')
    if ok then
        dprint(('/giveitem added %sx %s to player %s'):format(amount, itemName, src))
        notify(src, ('Added %sx %s'):format(amount, itemName), 'success')
        sendInventory(src)
    else
        dprint(('/giveitem failed for player %s item=%s reason=%s'):format(src, itemName, tostring(reason)))
        notify(src, 'Failed: ' .. tostring(reason), 'error')
    end
end, false)

RegisterCommand('invgive', function(src, args)
    if src ~= 0 then return end
    local target = tonumber(args[1])
    local itemName = tostring(args[2] or 'water'):lower()
    local amount = tonumber(args[3]) or 1
    if not target then print('Usage: invgive <serverId> <item> <amount>') return end
    local ok, reason = AddItemInternal(target, itemName, amount, {}, 'console_invgive')
    if ok then
        print(('[CM-INVENTORY] Console gave %sx %s to %s'):format(amount, itemName, target))
        notify(target, ('Added %sx %s'):format(amount, itemName), 'success')
        sendInventory(target)
    else
        print(('[CM-INVENTORY] invgive failed: %s'):format(tostring(reason)))
    end
end, true)



RegisterCommand('givebag', function(src, args)
    if src <= 0 then print('[CM-INVENTORY] Use invgivebag from server console.') return end
    local level = math.max(1, math.min(4, math.floor(tonumber(args[1]) or 1)))
    local itemName = tostring(args[2] or 'clothing_bags'):lower()
    local metadata = { bagLevel = level, categoryType = 'bags', itemType = 'clothing', label = ('Level %s Bag'):format(level) }
    local ok, reason = AddItemInternal(src, itemName, 1, metadata, 'command_givebag')
    if ok then
        print(('[CM-INVENTORY] /givebag added %s with bagLevel=%s to player %s'):format(itemName, level, src))
        notify(src, ('Added Level %s bag'):format(level), 'success')
        sendInventory(src)
    else
        print(('[CM-INVENTORY] /givebag failed player=%s item=%s level=%s reason=%s'):format(src, itemName, level, tostring(reason)))
        notify(src, 'Failed: ' .. tostring(reason), 'error')
    end
end, false)

RegisterCommand('invgivebag', function(src, args)
    if src ~= 0 then return end
    local target = tonumber(args[1])
    local level = math.max(1, math.min(4, math.floor(tonumber(args[2]) or 1)))
    local itemName = tostring(args[3] or 'clothing_bags'):lower()
    if not target then print('Usage: invgivebag <serverId> <bagLevel 1-4> [itemName]') return end
    local metadata = { bagLevel = level, categoryType = 'bags', itemType = 'clothing', label = ('Level %s Bag'):format(level) }
    local ok, reason = AddItemInternal(target, itemName, 1, metadata, 'console_invgivebag')
    if ok then
        print(('[CM-INVENTORY] invgivebag gave %s level=%s to %s'):format(itemName, level, target))
        notify(target, ('Added Level %s bag'):format(level), 'success')
        sendInventory(target)
    else
        print(('[CM-INVENTORY] invgivebag failed: %s'):format(tostring(reason)))
    end
end, true)

RegisterCommand('invgivetest', function(src, args)
    if src ~= 0 then return end
    local target = tonumber(args[1])
    local itemName = tostring(args[2] or 'water'):lower()
    local amount = tonumber(args[3]) or 1
    if not target then
        print('Usage: invgivetest <serverId> <item> <amount>')
        return
    end
    local ok, message = DevGiveTestInternal(target, itemName, amount)
    print(('[CM-INVENTORY] invgivetest result: %s | %s'):format(tostring(ok), tostring(message)))
    if target > 0 then sendInventory(target) end
end, true)

RegisterCommand('invshowtest', function(src)
    if src ~= 0 then return end
    ShowTestReceiverInternal(0)
end, true)

RegisterCommand('invcleartest', function(src)
    if src ~= 0 then return end
    ClearTestReceiverInternal(0)
end, true)

RegisterCommand('refreshgear', function(src)
    if src <= 0 then return end
    syncAllEquipment(src)
    notify(src, 'Equipment refreshed.', 'success')
end, false)

exports('AddItem', function(...)
    local src, itemName, amount, metadata, reason, slot = normalizeExportArgs(...)
    local ok, placedSlotOrReason = AddItemInternal(src, itemName, amount, metadata, reason, slot)

    -- If another resource adds directly into an equipment slot, immediately apply it
    -- and refresh the UI. This is used by starter character clothes.
    if ok and src and tonumber(src) and tonumber(src) > 0 then
        local placedSlot = tostring(placedSlotOrReason or '')
        if isEquipmentSlot(placedSlot) then
            syncEquipmentSlot(tonumber(src), placedSlot)
        end
        sendInventory(tonumber(src))
    end

    return ok, placedSlotOrReason
end)

exports('RemoveItem', function(...)
    local src, itemName, amount, metadata, reason = normalizeExportArgs(...)
    return RemoveItemInternal(src, itemName, amount, metadata, reason)
end)

exports('MoveItem', function(...)
    local src, fromSlot, toSlot = normalizeExportArgs(...)
    return MoveItemInternal(src, tostring(fromSlot or ''), tostring(toSlot or ''))
end)

exports('HasItem', function(...)
    local src, itemName, amount = normalizeExportArgs(...)
    return HasItemInternal(src, itemName, amount)
end)

exports('CanCarryItem', function(...)
    local src, itemName, amount = normalizeExportArgs(...)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    return canCarry(ownerType, ownerId, itemName, amount)
end)

exports('GetInventory', function(...)
    local src = normalizeExportArgs(...)
    return buildInventoryPayload(src)
end)


exports('GiveItemToNearby', function(...)
    local src, slot, amount = normalizeExportArgs(...)
    return GiveItemInternal(src, tostring(slot or ''), tonumber(amount) or 1)
end)

exports('CreateUseableItem', function(...)
    -- Same-resource/local function support only. Cross-resource Lua callbacks are unreliable in FiveM exports.
    local itemName, cb = normalizeExportArgs(...)

    if type(itemName) == 'string' and type(cb) == 'function' then
        UseableItems[itemName:lower()] = cb
        print(('[CM-INVENTORY] Usable item registered with function: %s'):format(itemName:lower()))
        return true
    end

    print(('[CM-INVENTORY] CreateUseableItem failed. Use RegisterUseableItem(resource, export) for cross-resource items. itemName=%s cbType=%s'):format(tostring(itemName), type(cb)))
    return false
end)

exports('ReloadWeapon', function(...)
    local src = normalizeExportArgs(...)
    return ReloadWeaponInternal(src)
end)

exports('RegisterUseableItem', function(...)
    -- Recommended cross-resource registration:
    -- exports['cm-inventory'].RegisterUseableItem('bandage', 'cm-itemactions', 'UseItem')
    -- exports['cm-inventory']:RegisterUseableItem('bandage', 'cm-itemactions', 'UseItem')
    local itemName, resourceName, exportName = normalizeExportArgs(...)

    if type(itemName) ~= 'string' or itemName == '' then
        print('[CM-INVENTORY] RegisterUseableItem failed: invalid itemName')
        return false
    end

    if type(resourceName) ~= 'string' or resourceName == '' then
        print(('[CM-INVENTORY] RegisterUseableItem failed for %s: invalid resourceName'):format(itemName))
        return false
    end

    if type(exportName) ~= 'string' or exportName == '' then
        print(('[CM-INVENTORY] RegisterUseableItem failed for %s: invalid exportName'):format(itemName))
        return false
    end

    UseableItems[itemName:lower()] = {
        resource = resourceName,
        export = exportName
    }

    print(('[CM-INVENTORY] Usable item registered: %s -> %s.%s'):format(itemName:lower(), resourceName, exportName))
    return true
end)

CreateThread(function()
    math.randomseed(os.time())
    ensureTables()
    cleanupDrops()
    sendDrops(-1)
    print('[CM-INVENTORY] Started v4.0-exportfix')
end)
