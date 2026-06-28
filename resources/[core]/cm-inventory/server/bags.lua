-- cm-inventory/bags.lua
-- Split from legacy server/main.lua. Loaded by server/main.lua bootloader in this exact order.

local function randomSerial(prefix)
    prefix = prefix or 'CM'
    return ('%s-%06d'):format(prefix, math.random(100000, 999999))
end

local function cleanNormalMetadata(metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local cleaned = {}
    local defaultOnly = true

    local ignoredDefaults = {
        rarity = true,
        itemType = true,
        type = true,
        createdAt = true,
    }

    for k, v in pairs(metadata) do
        if v ~= nil and v ~= '' then
            local isDefaultValue = ignoredDefaults[k] and (
                tostring(v):lower() == 'normal' or
                tostring(v):lower() == 'misc' or
                tostring(v):match('^%d%d%d%d%-%d%d%-%d%dT') ~= nil
            )
            if not isDefaultValue then
                defaultOnly = false
                cleaned[k] = v
            end
        end
    end

    if defaultOnly then return {} end
    return cleaned
end

local function decorateNewItemMetadata(itemName, metadata, def, hadCustomMetadata)
    metadata = type(metadata) == 'table' and metadata or {}
    def = def or getItemDef(itemName) or {}

    local lowerName = tostring(itemName or ''):lower()
    local isWeapon = lowerName:find('weapon_', 1, true) == 1
    local isArmor = lowerName == 'armor' or lowerName == 'body_armor' or lowerName == 'bodyarmor' or lowerName:find('armor', 1, true) ~= nil
    local isClothing = isClothingItemName(lowerName)

    -- Normalize common aliases before saving. This avoids duplicate bag_level/level fields in DB.
    metadata.bagLevel = normalizeBagLevel(metadata.bagLevel or metadata.bag_level or metadata.level or metadata.backpackLevel or metadata.backpack_level or def.bagLevel or def.bag_level or def.level)
    metadata.bag_level = nil
    metadata.level = nil
    metadata.backpackLevel = nil
    metadata.backpack_level = nil

    if metadata.drawable ~= nil and metadata.drawableId == nil then metadata.drawableId = metadata.drawable end
    if metadata.texture ~= nil and metadata.textureId == nil then metadata.textureId = metadata.texture end
    metadata.drawable = nil
    metadata.texture = nil

    local itemRarity = tostring(metadata.rarity or metadata.itemType or def.rarity or def.quality or 'normal'):lower()
    if itemRarity ~= 'rare' and itemRarity ~= 'unique' then itemRarity = 'normal' end

    local isStackable = def.stack ~= false and def.unique ~= true
    local needsMetadata = isClothing
        or isWeapon
        or isArmor
        or itemRarity ~= 'normal'
        or def.durability ~= nil
        or metadata.bagLevel ~= nil
        or metadata.serial ~= nil
        or metadata.durability ~= nil
        or metadata.image ~= nil
        or metadata.icon ~= nil
        or metadata.categoryType ~= nil
        or metadata.drawableId ~= nil
        or metadata.textureId ~= nil
        or metadata.gender ~= nil

    if isStackable and not needsMetadata then
        return cleanNormalMetadata(metadata)
    end

    if isClothing then
        metadata.itemType = metadata.itemType or 'clothing'
        metadata.categoryType = metadata.categoryType or metadata.category
        if lowerName == 'clothing_bags' then
            metadata.categoryType = 'bags'
            if metadata.bagLevel then
                metadata.label = metadata.label or ('Level %s Bag'):format(metadata.bagLevel)
            end
        end
    else
        metadata.rarity = metadata.rarity or itemRarity
        metadata.itemType = metadata.itemType or metadata.rarity
    end

    if not isClothing then
        metadata.createdAt = metadata.createdAt or os.date('!%Y-%m-%dT%H:%M:%SZ')
    end

    if def.durability and metadata.durability == nil then
        metadata.durability = tonumber(def.durability) or 100
    end
    if isWeapon then
        metadata.serial = metadata.serial or randomSerial('WPN')
        metadata.durability = metadata.durability or 100
    end
    if isArmor then
        metadata.durability = metadata.durability or 100
    end

    return metadata
end

