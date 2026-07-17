-- cm-inventory/items.lua
-- Split from legacy server/main.lua. Loaded by server/main.lua bootloader in this exact order.

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

    -- Dynamic items (e.g. cm-gunstore armor_xxx / weapon_xxx): resolve by prefix.
    for _, rule in ipairs(Config.DynamicItemPatterns or {}) do
        if rule.prefix and itemName:sub(1, #rule.prefix) == rule.prefix then
            local copy = {}
            for k, v in pairs(rule.def or {}) do copy[k] = v end
            copy.name = itemName
            copy.label = copy.label or itemName
            copy.category = copy.category or 'misc'
            copy.weight = tonumber(copy.weight) or 0
            copy.stack = copy.stack ~= false and copy.unique ~= true
            copy.image = copy.image or Config.DefaultImages[itemName] or 'placeholder.png'
            copy.description = copy.description or ''
            copy.dynamic = true
            return copy
        end
    end

    return nil
end



local function stableEncode(value)
    local t = type(value)
    if t == 'nil' then return 'null' end
    if t == 'number' or t == 'boolean' then return tostring(value) end
    if t == 'string' then return string.format('%q', value) end
    if t ~= 'table' then return string.format('%q', tostring(value)) end

    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    local parts = {}
    for _, k in ipairs(keys) do
        local v = value[k]
        if v ~= nil then
            parts[#parts + 1] = stableEncode(tostring(k)) .. ':' .. stableEncode(v)
        end
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function normalizeStackMetadata(metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local normalized = {}

    -- These fields are generated only for display/default bookkeeping and should not split
    -- normal stackable items into separate slots. Real unique fields such as serial,
    -- durability, drawableId, textureId, gender, bagLevel, etc. are intentionally kept.
    local ignoredDefaults = {
        -- Generated/display-only fields. These should not stop normal stackable
        -- items like ammo, water, food, and materials from merging.
        createdAt = true,
        created_at = true,
        updatedAt = true,
        updated_at = true,
        itemType = true,
        item_type = true,
        rarity = true,
        quality = true,
        type = true,
        category = true,
        categoryType = true,
        category_type = true,
        label = true,
        description = true,
        image = true,
        icon = true
    }

    for k, v in pairs(metadata) do
        if v ~= nil and v ~= '' then
            local key = tostring(k)
            -- Keep real unique gameplay metadata such as serial, durability, tint,
            -- components, drawable/texture, gender, bagLevel, ammo, etc. Only remove
            -- fields that are safe display/bookkeeping fields for stack comparison.
            if not ignoredDefaults[key] then
                normalized[key] = v
            end
        end
    end

    return normalized
end

local function isClothingStackCandidate(itemName)
    itemName = tostring(itemName or ''):lower()
    -- Bags can change capacity, so keep bag items one-per-slot. Normal clothing can stack
    -- only when the actual wearable appearance is identical.
    return itemName:find('clothing_', 1, true) == 1 and itemName ~= 'clothing_bags'
end

local function stackSlotIsEquipment(slot)
    for _, s in ipairs(Config.Slots.equipment or {}) do
        if tostring(s) == tostring(slot) then return true end
    end
    return false
end

local function normalizeComparableValue(value)
    if type(value) == 'number' then return value end
    if type(value) == 'string' then
        local n = tonumber(value)
        if n ~= nil then return n end
        return value:lower()
    end
    return value
end

local function firstMetadataValue(metadata, keys)
    for _, key in ipairs(keys) do
        local value = metadata[key]
        if value ~= nil and value ~= '' then
            return normalizeComparableValue(value)
        end
    end
    return nil
end

local function normalizeClothingStackMetadata(itemName, metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local normalized = {}

    local category = firstMetadataValue(metadata, {
        'categoryType', 'category_type', 'category', 'clothingCategory', 'clothing_category', 'slot', 'equipSlot', 'equipmentSlot'
    })
    if not category or category == '' or category == 'clothing' then
        category = tostring(itemName or ''):lower():gsub('^clothing_', '')
    end
    normalized.category = category

    -- IMPORTANT: only the keys that actually define the wearable appearance are
    -- compared. Two clothing items that look identical must merge, so incidental
    -- fields (gender/model, dlc/collection, undershirt/arms/torso linkage, and
    -- nested appearance tables that can carry capture time / row ids / ordering
    -- noise) are deliberately EXCLUDED from the stack signature. What defines
    -- "the same wearable" is: category + component/prop + drawable + texture.
    local groups = {
        component = { 'component', 'componentId', 'component_id', 'componentIndex', 'component_index', 'comp', 'compId' },
        prop = { 'prop', 'propId', 'prop_id', 'propIndex', 'prop_index', 'isProp', 'is_prop' },
        drawable = { 'drawable', 'drawableId', 'drawable_id', 'drawableIndex', 'drawable_index' },
        texture = { 'texture', 'textureId', 'texture_id', 'textureIndex', 'texture_index' },
    }

    local hasAppearanceKey = false
    for canonical, keys in pairs(groups) do
        local value = firstMetadataValue(metadata, keys)
        if value ~= nil then
            normalized[canonical] = value
            hasAppearanceKey = true
        end
    end

    -- If this is a clothing item but has no wearable metadata, fall back to the normal
    -- stack signature so unusual custom items do not merge incorrectly.
    if not hasAppearanceKey then
        return normalizeStackMetadata(metadata)
    end

    return normalized
end

local function stackMetadataSignature(itemName, metadata)
    if isClothingStackCandidate(itemName) then
        return stableEncode(normalizeClothingStackMetadata(itemName, metadata))
    end
    return stableEncode(normalizeStackMetadata(metadata))
end

local function rowsCanStack(a, b)
    if not a or not b then return false end

    local itemName = tostring(a.item_name or ''):lower()
    if itemName ~= tostring(b.item_name or ''):lower() then return false end

    local clothingStack = isClothingStackCandidate(itemName)
    if clothingStack and (stackSlotIsEquipment(a.slot) or stackSlotIsEquipment(b.slot)) then return false end

    local def = getItemDef(itemName)
    if not def then return false end
    if not clothingStack and (def.stack == false or def.unique == true) then return false end

    return stackMetadataSignature(itemName, decode(a.metadata)) == stackMetadataSignature(itemName, decode(b.metadata))
end

local function rowCanStackWithMetadata(row, itemName, metadata)
    if not row then return false end
    itemName = tostring(itemName or ''):lower()
    if tostring(row.item_name or ''):lower() ~= itemName then return false end

    local clothingStack = isClothingStackCandidate(itemName)
    if clothingStack and stackSlotIsEquipment(row.slot) then return false end

    local def = getItemDef(itemName)
    if not def then return false end
    if not clothingStack and (def.stack == false or def.unique == true) then return false end

    return stackMetadataSignature(itemName, decode(row.metadata)) == stackMetadataSignature(itemName, metadata)
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

local function isClothingItemName(itemName)
    local name = tostring(itemName or ''):lower()
    return name:find('clothing_', 1, true) == 1 or name == 'clothing_bags'
end

local function normalizeBagLevel(value)
    local level = tonumber(value)
    if not level then return nil end
    return math.max(1, math.min(4, math.floor(level)))
end

local function getDisplayLabel(itemName, def, metadata)
    local name = tostring(itemName or ''):lower()
    local bagLevel = normalizeBagLevel(metadata.bagLevel or metadata.bag_level or metadata.level or metadata.backpackLevel or metadata.backpack_level or def.bagLevel or def.bag_level or def.level)

    if name == 'clothing_bags' and bagLevel then
        local metaLabel = tostring(metadata.label or '')
        if metaLabel ~= '' and metaLabel ~= 'Bag' and metaLabel ~= 'Clothing Bag' and metaLabel ~= 'clothing_bags' then
            return metaLabel
        end
        return ('Level %s Bag'):format(bagLevel)
    end

    return metadata.label or def.label or itemName
end

local function getDisplayDescription(itemName, def, metadata)
    local name = tostring(itemName or ''):lower()
    local bagLevel = normalizeBagLevel(metadata.bagLevel or metadata.bag_level or metadata.level or metadata.backpackLevel or metadata.backpack_level or def.bagLevel or def.bag_level or def.level)

    if name == 'clothing_bags' and bagLevel and (not metadata.description or metadata.description == '') then
        local cfg = Config.BagLevels and Config.BagLevels[bagLevel] or nil
        if cfg then
            return ('Unlocks %s backpack slots and %.1f KG carry weight.'):format(tonumber(cfg.backpackSlots) or 0, (tonumber(cfg.maxWeight) or 0) / 1000)
        end
    end

    return metadata.description or def.description or ''
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
        label = getDisplayLabel(row.item_name, def, metadata),
        category = metadata.categoryType or metadata.category or def.category or def.type or 'misc',
        type = metadata.categoryType or metadata.category or def.type or def.category or 'misc',
        itemType = metadata.itemType or def.itemType or rarity,
        rarity = rarity,
        image = metadata.image or metadata.icon or def.image or def.icon or 'placeholder.png',
        icon = metadata.icon or metadata.image or def.image or def.icon or 'placeholder.png',
        quantity = tonumber(row.quantity) or 1,
        weight = tonumber(def.weight) or 0,
        stack = def.stack ~= false and def.unique ~= true,
        usable = def.usable == true,
        description = getDisplayDescription(row.item_name, def, metadata),
        durability = durability,
        metadata = metadata,
        equipmentSlot = def.equipmentSlot or def.equipSlot,
        isClothing = isClothingItemName(row.item_name),
        isBag = row.item_name == 'clothing_bags' or (metadata.categoryType == 'bags' or metadata.category == 'bags'),
        bagLevel = normalizeBagLevel(metadata.bagLevel or metadata.bag_level or metadata.level or metadata.backpackLevel or metadata.backpack_level or def.bagLevel or def.bag_level or def.level) or 0
    }
end

