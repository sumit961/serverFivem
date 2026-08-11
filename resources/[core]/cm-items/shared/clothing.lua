CMItems = CMItems or {}

-- Central clothing helpers for ClockMate.
-- Purpose:
--   * Keep clothing image paths in ONE resource: cm-items
--   * Build the metadata used by shop, inventory, and character starter clothes
--   * Avoid duplicating clothing metadata logic in nv_cloth / cm-characters

CMItems.Clothing = CMItems.Clothing or {}

CMItems.Clothing.AssetResource = 'cm-items'
CMItems.Clothing.ImageRoot = 'ui/images/clothing'
CMItems.Clothing.FallbackImage = 'nui://cm-items/ui/images/clothing.png'


-- Torso/clipping compatibility map.
-- GTA freemode tops (component 11) do NOT automatically choose the right arms/body mesh
-- (component 3). If arms are wrong, skin/body shows through jacket sleeves.
-- Add problem tops here after finding the correct arms with /cmarms.
-- Supports either:
--   male[drawable] = { arms = 4, armsTexture = 0, undershirt = 15, undershirtTexture = 0 }
-- or texture-specific:
--   male[drawable] = { default = { arms = 4 }, [0] = { arms = 4 }, [1] = { arms = 6 } }
CMItems.Clothing.TorsoFit = CMItems.Clothing.TorsoFit or {
    male = {
        -- Example:
        -- [5] = { arms = 5, armsTexture = 0, undershirt = 15, undershirtTexture = 0 },
    },
    female = {
        -- Example:
        -- [6] = { arms = 6, armsTexture = 0, undershirt = 14, undershirtTexture = 0 },
    }
}


-- Simple sleeve presets. For your current male freemode clothes:
--   full/long sleeve  -> arms component 3 = 6
--   half/short sleeve -> arms component 3 = 5
-- Female values can be different per clothing pack, so add them only after testing.
CMItems.Clothing.SleeveDefaults = CMItems.Clothing.SleeveDefaults or {
    male = {
        full  = { arms = 6, armsTexture = 0 },
        long  = { arms = 6, armsTexture = 0 },
        half  = { arms = 5, armsTexture = 0 },
        short = { arms = 5, armsTexture = 0 },
    },
    female = {
        -- full = { arms = 6, armsTexture = 0 },
        -- half = { arms = 5, armsTexture = 0 },
    }
}

-- Optional quick map: tag torso drawables as full/half sleeve instead of writing the whole fit.
-- Specific CMItems.Clothing.TorsoFit entries still win over this.
-- Example:
-- CMItems.Clothing.TorsoSleeveStyle.male[45] = 'full' -- uses arms 6
-- CMItems.Clothing.TorsoSleeveStyle.male[12] = 'half' -- uses arms 5
CMItems.Clothing.TorsoSleeveStyle = CMItems.Clothing.TorsoSleeveStyle or {
    male = {
        -- [45] = 'full',
        -- [12] = 'half',
    },
    female = {}
}


-- GitHub / BestTorso database.
-- Structure: top/component 11 drawable -> texture -> BestTorsoDrawable/Texture.
-- In GTA/FiveM terminology this "BestTorso" value is the matching component 3
-- arms/upper-body mesh for that top. It fixes skin/body clipping around sleeves,
-- neck, and chest without manually mapping every jacket.
CMItems.Clothing.BestTorsoFiles = CMItems.Clothing.BestTorsoFiles or {
    male = 'shared/besttorso_male.json',
    female = 'shared/besttorso_female.json',
}
CMItems.Clothing.BestTorso = CMItems.Clothing.BestTorso or {}

local bestTorsoLoaded = {}

local function loadBestTorsoMap(gender)
    gender = CMItems.NormalizeClothingGender(gender)
    CMItems.Clothing.BestTorso = CMItems.Clothing.BestTorso or {}

    if bestTorsoLoaded[gender] then
        return CMItems.Clothing.BestTorso[gender]
    end

    bestTorsoLoaded[gender] = true

    if type(CMItems.Clothing.BestTorso[gender]) == 'table' then
        return CMItems.Clothing.BestTorso[gender]
    end

    if type(LoadResourceFile) ~= 'function' or type(json) ~= 'table' or type(json.decode) ~= 'function' then
        CMItems.Clothing.BestTorso[gender] = nil
        return nil
    end

    local file = CMItems.Clothing.BestTorsoFiles and CMItems.Clothing.BestTorsoFiles[gender]
    if not file then return nil end

    local raw = LoadResourceFile(CMItems.Clothing.AssetResource or 'cm-items', file)
    if not raw or raw == '' then
        CMItems.Clothing.BestTorso[gender] = nil
        return nil
    end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        print(('[CM-ITEMS] Failed to decode %s BestTorso map: %s'):format(gender, tostring(decoded)))
        CMItems.Clothing.BestTorso[gender] = nil
        return nil
    end

    CMItems.Clothing.BestTorso[gender] = decoded
    return decoded
end

function CMItems.GetBestTorsoFit(gender, torsoDrawable, torsoTexture)
    gender = CMItems.NormalizeClothingGender(gender)
    local drawable = tonumber(torsoDrawable)
    local texture = tonumber(torsoTexture) or 0
    if not drawable then return nil end

    local map = loadBestTorsoMap(gender)
    if type(map) ~= 'table' then return nil end

    local drawableEntry = map[tostring(drawable)] or map[drawable]
    if type(drawableEntry) ~= 'table' then return nil end

    local fit = drawableEntry[tostring(texture)] or drawableEntry[texture]

    -- Safe fallback: if the exact texture is not present, use texture 0 for that top.
    -- This is better than falling back to bare/default arms and causing clipping.
    if type(fit) ~= 'table' then
        fit = drawableEntry['0'] or drawableEntry[0]
    end
    if type(fit) ~= 'table' then return nil end

    local arms = tonumber(fit.BestTorsoDrawable or fit.bestTorsoDrawable or fit.arms)
    local armsTexture = tonumber(fit.BestTorsoTexture or fit.bestTorsoTexture or fit.armsTexture) or 0
    if not arms or arms < 0 then return nil end

    return {
        arms = arms,
        armsTexture = armsTexture,
        bestTorsoResolved = true,
        torsoFitSource = 'besttorso',
    }
end

local function isFitPayload(value)
    return type(value) == 'table' and (
        value.arms ~= nil or value.armsTexture ~= nil or value.undershirt ~= nil or value.undershirtTexture ~= nil
    )
end

local function normalizeSleeveStyle(style)
    local value = tostring(style or ''):lower()
    if value == '' then return nil end
    if value == 'full' or value == 'long' or value == 'longsleeve' or value == 'long_sleeve' or value == 'fullsleeve' or value == 'full_sleeve' then
        return 'full'
    end
    if value == 'half' or value == 'short' or value == 'shortsleeve' or value == 'short_sleeve' or value == 'halfsleeve' or value == 'half_sleeve' then
        return 'half'
    end
    return value
end

local function getSleeveStyleFromMap(gender, drawable, texture)
    local byGender = CMItems.Clothing.TorsoSleeveStyle and CMItems.Clothing.TorsoSleeveStyle[gender]
    local entry = byGender and drawable and byGender[drawable] or nil
    if type(entry) == 'table' then
        return normalizeSleeveStyle(entry[texture] or entry[tostring(texture)] or entry.default or entry.style)
    end
    return normalizeSleeveStyle(entry)
end

local function getSleeveDefault(gender, style)
    style = normalizeSleeveStyle(style)
    local byGender = CMItems.Clothing.SleeveDefaults and CMItems.Clothing.SleeveDefaults[gender]
    local value = byGender and style and byGender[style] or nil
    return type(value) == 'table' and value or {}
end

function CMItems.ResolveTorsoFit(gender, torsoDrawable, torsoTexture, fallback)
    gender = CMItems.NormalizeClothingGender(gender)
    local drawable = tonumber(torsoDrawable)
    local texture = tonumber(torsoTexture) or 0
    fallback = type(fallback) == 'table' and fallback or {}

    local byGender = CMItems.Clothing.TorsoFit and CMItems.Clothing.TorsoFit[gender]
    local entry = byGender and drawable and byGender[drawable] or nil
    local resolved = nil

    if isFitPayload(entry) then
        resolved = entry
    elseif type(entry) == 'table' then
        resolved = entry[texture] or entry[tostring(texture)] or entry.default
    end

    local out = {}
    if type(resolved) == 'table' then
        for k, v in pairs(resolved) do out[k] = v end
        out.torsoFitSource = out.torsoFitSource or 'manual'
    end

    local bestTorso = nil
    if out.arms == nil or tonumber(out.arms) == nil or tonumber(out.arms) < 0 then
        bestTorso = CMItems.GetBestTorsoFit(gender, drawable, texture)
        if type(bestTorso) == 'table' then
            out.arms = bestTorso.arms
            out.armsTexture = bestTorso.armsTexture or 0
            out.bestTorsoResolved = true
            out.torsoFitSource = out.torsoFitSource or 'besttorso'
        end
    end

    local sleeveStyle = normalizeSleeveStyle(
        fallback.sleeveStyle or fallback.sleeve or fallback.sleeveType or getSleeveStyleFromMap(gender, drawable, texture)
    )
    local sleeveDefault = getSleeveDefault(gender, sleeveStyle)

    -- Sleeve preset applies only when a specific TorsoFit entry did not set arms.
    -- Full sleeve = arms 6, half sleeve = arms 5 for male freemode by default.
    if out.arms == nil and sleeveDefault.arms ~= nil then
        out.arms = sleeveDefault.arms
        out.torsoFitSource = out.torsoFitSource or 'sleeve_default'
    end
    if out.armsTexture == nil and sleeveDefault.armsTexture ~= nil then out.armsTexture = sleeveDefault.armsTexture end
    if out.undershirt == nil and sleeveDefault.undershirt ~= nil then out.undershirt = sleeveDefault.undershirt end
    if out.undershirtTexture == nil and sleeveDefault.undershirtTexture ~= nil then out.undershirtTexture = sleeveDefault.undershirtTexture end
    if out.sleeveStyle == nil and sleeveStyle then out.sleeveStyle = sleeveStyle end

    -- Keep caller/fallback values when the map/default does not override them.
    if out.arms == nil then
        out.arms = fallback.arms
        if out.arms ~= nil then out.torsoFitSource = out.torsoFitSource or 'fallback' end
    end
    if out.armsTexture == nil then out.armsTexture = fallback.armsTexture or fallback.arms_2 end
    if out.undershirt == nil then out.undershirt = fallback.undershirt or fallback.tshirt_1 end
    if out.undershirtTexture == nil then out.undershirtTexture = fallback.undershirtTexture or fallback.tshirt_2 end

    out.arms = tonumber(out.arms)
    out.armsTexture = tonumber(out.armsTexture) or 0
    out.undershirt = tonumber(out.undershirt)
    out.undershirtTexture = tonumber(out.undershirtTexture) or 0
    return out
end

CMItems.Clothing.Categories = {
    mask     = { type = 'component', index = 1,  label = 'Mask',        itemName = 'clothing_mask',     equipmentSlot = 'mask' },
    arms     = { type = 'component', index = 3,  label = 'Arms/Gloves', itemName = 'clothing_arms',     equipmentSlot = 'arms' },
    pants    = { type = 'component', index = 4,  label = 'Pants',       itemName = 'clothing_pants',    equipmentSlot = 'pants' },
    bags     = { type = 'component', index = 5,  label = 'Bag',         itemName = 'clothing_bags',     equipmentSlot = 'bag' },
    shoes    = { type = 'component', index = 6,  label = 'Shoes',       itemName = 'clothing_shoes',    equipmentSlot = 'shoes' },
    chains   = { type = 'component', index = 7,  label = 'Chain',       itemName = 'clothing_chains',   equipmentSlot = 'accessory' },
    tshirt   = { type = 'component', index = 8,  label = 'T-Shirt',     itemName = 'clothing_tshirt',   equipmentSlot = 'shirt' },
    decals   = { type = 'component', index = 10, label = 'Decals',      itemName = 'clothing_decals',   equipmentSlot = 'decals' },
    torso    = { type = 'component', index = 11, label = 'Top',         itemName = 'clothing_torso',    equipmentSlot = 'outerwear' },
    hat      = { type = 'prop',      index = 0,  label = 'Hat',         itemName = 'clothing_hat',      equipmentSlot = 'headwear' },
    glasses  = { type = 'prop',      index = 1,  label = 'Glasses',     itemName = 'clothing_glasses',  equipmentSlot = 'glasses' },
    earrings = { type = 'prop',      index = 2,  label = 'Earrings',    itemName = 'clothing_earrings', equipmentSlot = 'earrings' },
    watches  = { type = 'prop',      index = 6,  label = 'Watch',       itemName = 'clothing_watches',  equipmentSlot = 'watch' },
    bracelet = { type = 'prop',      index = 7,  label = 'Bracelet',    itemName = 'clothing_bracelet', equipmentSlot = 'bracelet' },
}

CMItems.Clothing.Aliases = {
    shirt = 'tshirt', undershirt = 'tshirt', top = 'torso', jacket = 'torso', outerwear = 'torso',
    trouser = 'pants', trousers = 'pants', pant = 'pants', legs = 'pants', leg = 'pants',
    glove = 'arms', gloves = 'arms', hand = 'arms', hands = 'arms',
    chain = 'chains', accessory = 'chains', accessories = 'chains',
    bag = 'bags', backpack = 'bags', headwear = 'hat', cap = 'hat',
    watch = 'watches', earring = 'earrings', bracelets = 'bracelet'
}

local function copyTable(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copyTable(v) end
    return out
end

function CMItems.NormalizeClothingCategory(category)
    category = tostring(category or ''):lower()
    category = category:gsub('%s+', '_')
    return CMItems.Clothing.Aliases[category] or category
end

function CMItems.GetClothingCategoryDefinition(category)
    category = CMItems.NormalizeClothingCategory(category)
    local def = CMItems.Clothing.Categories[category]
    if not def then return nil end
    local out = copyTable(def)
    out.category = category
    return out
end

function CMItems.GetClothingItemName(category)
    local def = CMItems.GetClothingCategoryDefinition(category)
    return def and def.itemName or nil
end

function CMItems.NormalizeClothingGender(gender)
    if gender == true then return 'female' end
    local g = tostring(gender or ''):lower()
    if g == 'female' or g == 'f' or g == 'woman' or g == 'mp_f_freemode_01' or g == '1' then
        return 'female'
    end
    return 'male'
end

function CMItems.GetClothingImage(gender, componentType, componentIndex, drawableId)
    local drawable = tonumber(drawableId)
    if not drawable or drawable < 0 then
        return CMItems.Clothing.FallbackImage
    end

    gender = CMItems.NormalizeClothingGender(gender)
    componentType = tostring(componentType or 'component'):lower()
    local propPrefix = componentType == 'prop' and 'prop_' or ''

    return ('nui://%s/%s/%s_%s%s_%s.png'):format(
        CMItems.Clothing.AssetResource,
        CMItems.Clothing.ImageRoot,
        gender,
        propPrefix,
        tostring(componentIndex or 0),
        tostring(drawable)
    )
end

local function readRaw(raw, metadata, key, altKey)
    if raw and raw[key] ~= nil then return raw[key] end
    if altKey and raw and raw[altKey] ~= nil then return raw[altKey] end
    if metadata and metadata[key] ~= nil then return metadata[key] end
    if altKey and metadata and metadata[altKey] ~= nil then return metadata[altKey] end
    return nil
end

-- Build the exact metadata for one clothing item.
-- raw can be shop data, starter-character data, or admin-give data.
function CMItems.BuildClothingMetadata(categoryOrRaw, raw, opts)
    if type(categoryOrRaw) == 'table' then
        opts = raw
        raw = categoryOrRaw
        categoryOrRaw = raw.category or raw.type or raw.categoryType or raw.clothingCategory
    end

    raw = type(raw) == 'table' and raw or {}
    opts = type(opts) == 'table' and opts or {}

    local incoming = type(raw.metadata) == 'table' and raw.metadata or raw
    local category = CMItems.NormalizeClothingCategory(categoryOrRaw or incoming.categoryType or incoming.category or raw.type)
    local def = CMItems.GetClothingCategoryDefinition(category)
    if not def then return nil, 'Invalid clothing category.' end

    local drawable = tonumber(
        readRaw(raw, incoming, 'drawableId') or
        readRaw(raw, incoming, 'drawable') or
        readRaw(raw, incoming, 'component') or
        readRaw(raw, incoming, 'componentId')
    )
    local texture = tonumber(readRaw(raw, incoming, 'textureId') or readRaw(raw, incoming, 'texture')) or 0
    if drawable == nil then return nil, 'Invalid clothing drawable.' end

    local gender = CMItems.NormalizeClothingGender(
        opts.gender or incoming.gender or raw.gender or raw.sex or raw.pedGender or raw.modelGender
    )

    local image = incoming.image or incoming.icon or CMItems.GetClothingImage(gender, def.type, def.index, drawable)
    if type(image) == 'string' and image ~= '' and not image:find('^nui://') and not image:find('^https?://') then
        if image:find('^clothing/') then
            image = ('nui://cm-items/ui/images/%s'):format(image)
        else
            image = ('nui://cm-items/ui/images/clothing/%s'):format(image)
        end
    end
    local label = incoming.label or raw.label or raw.name or opts.label or ('%s %s/%s'):format(def.label, drawable, texture)

    local metadata = {
        categoryType = category,
        componentType = def.type,
        componentIndex = def.index,
        drawableId = drawable,
        textureId = texture,
        gender = gender,
        image = image,
        icon = image,
        label = label,
        description = incoming.description or opts.description or ('%s clothing item'):format(def.label),
        itemType = 'clothing',
        rarity = incoming.rarity or opts.rarity or 'normal',
        equipmentSlot = def.equipmentSlot,
    }

    if category == 'bags' then
        local bagLevel = tonumber(
            incoming.bagLevel or incoming.bag_level or incoming.level or
            raw.bagLevel or raw.bag_level or raw.level or
            opts.bagLevel or opts.bag_level or opts.level
        )
        if bagLevel ~= nil then
            bagLevel = math.max(1, math.min(4, math.floor(bagLevel)))
            -- Keep bag metadata minimal for cm-inventory: only bagLevel is required.
            -- Slot count and carry weight should come from the inventory BagLevels config.
            metadata.bagLevel = bagLevel
            if not incoming.description and not opts.description then
                metadata.description = ('Level %s bag. Unlocks backpack slots.'):format(bagLevel)
            end
        end
    end

    if category == 'torso' then
        local fit = CMItems.ResolveTorsoFit(gender, drawable, texture, {
            arms = incoming.arms,
            armsTexture = incoming.armsTexture or incoming.arms_2,
            undershirt = incoming.undershirt or incoming.tshirt_1,
            undershirtTexture = incoming.undershirtTexture or incoming.tshirt_2,
            sleeveStyle = incoming.sleeveStyle or incoming.sleeve or incoming.sleeveType or raw.sleeveStyle or raw.sleeve or raw.sleeveType,
        })
        metadata.arms = fit.arms
        metadata.armsTexture = fit.armsTexture or 0
        metadata.undershirt = fit.undershirt
        metadata.undershirtTexture = fit.undershirtTexture or 0
        metadata.sleeveStyle = fit.sleeveStyle or incoming.sleeveStyle or incoming.sleeve or incoming.sleeveType
        metadata.fitResolved = ((CMItems.Clothing.TorsoFit and CMItems.Clothing.TorsoFit[gender] and CMItems.Clothing.TorsoFit[gender][drawable]) ~= nil) or fit.bestTorsoResolved == true
        metadata.bestTorsoResolved = fit.bestTorsoResolved == true
        metadata.torsoFitSource = fit.torsoFitSource
        metadata.sleeveResolved = metadata.sleeveStyle ~= nil
    end

    -- Preserve safe custom keys without allowing callers to override core values accidentally.
    for k, v in pairs(incoming) do
        if metadata[k] == nil and type(v) ~= 'function' then
            metadata[k] = v
        end
    end

    if category == 'bags' then
        -- Do not leak catalog/admin helper values into inventory tooltip metadata.
        metadata.level = nil
        metadata.bag_level = nil
        metadata.backpackSlots = nil
        metadata.backpack_slots = nil
        metadata.maxWeight = nil
        metadata.max_weight = nil
        metadata.slots = nil
        metadata.weight = nil
    end

    metadata.itemName = opts.itemName or incoming.itemName or raw.itemName or def.itemName
    metadata.purchasedAt = incoming.purchasedAt or opts.purchasedAt

    return metadata
end

--========================================================
-- SQL-backed clothing catalog support
-- This lets admins manage custom clothing names/prices/fit from in-game commands.
-- The server loads DB rows into CMItems.Clothing.Catalog and syncs them to clients.
--========================================================

CMItems.Clothing.Catalog = CMItems.Clothing.Catalog or { male = {}, female = {} }

local function cmCatalogKey(value)
    local n = tonumber(value)
    if n ~= nil then return n end
    return tostring(value or '')
end

local function cmDeepMerge(base, override)
    local out = {}
    if type(base) == 'table' then
        for k, v in pairs(base) do out[k] = copyTable(v) end
    end
    if type(override) == 'table' then
        for k, v in pairs(override) do
            if type(v) == 'table' and type(out[k]) == 'table' then
                out[k] = cmDeepMerge(out[k], v)
            else
                out[k] = copyTable(v)
            end
        end
    end
    return out
end

function CMItems.SetClothingCatalog(catalog)
    CMItems.Clothing.Catalog = type(catalog) == 'table' and catalog or { male = {}, female = {} }
    CMItems.Clothing.Catalog.male = CMItems.Clothing.Catalog.male or {}
    CMItems.Clothing.Catalog.female = CMItems.Clothing.Catalog.female or {}
    return true
end

-- Supports both layouts:
-- Catalog[gender][componentIndex][drawable].default
-- Catalog[gender][componentIndex][drawable][texture]
function CMItems.GetClothingCatalogEntry(gender, componentTypeOrIndex, componentIndex, drawableId, textureId)
    gender = CMItems.NormalizeClothingGender(gender)

    local index = tonumber(componentIndex)
    if index == nil and tonumber(componentTypeOrIndex) ~= nil then
        index = tonumber(componentTypeOrIndex)
    end
    if not index then return nil end

    local drawable = tonumber(drawableId)
    if not drawable then return nil end
    local texture = tonumber(textureId) or 0

    local byGender = CMItems.Clothing.Catalog and CMItems.Clothing.Catalog[gender]
    if type(byGender) ~= 'table' then return nil end

    local byComponent = byGender[index] or byGender[tostring(index)]
    if type(byComponent) ~= 'table' then return nil end

    local byDrawable = byComponent[drawable] or byComponent[tostring(drawable)]
    if type(byDrawable) ~= 'table' then return nil end

    local base = nil
    if byDrawable.default and type(byDrawable.default) == 'table' then
        base = byDrawable.default
    elseif byDrawable['default'] and type(byDrawable['default']) == 'table' then
        base = byDrawable['default']
    elseif byDrawable.label or byDrawable.price or byDrawable.arms or byDrawable.enabled ~= nil then
        base = byDrawable
    end

    -- textureId < 0 means "any texture" (the default/all-textures catalog entry).
    -- Those entries are stored under byDrawable.default, so return it directly.
    if texture < 0 then
        return base
    end

    local textureEntry = nil
    if byDrawable.textures and type(byDrawable.textures) == 'table' then
        textureEntry = byDrawable.textures[texture] or byDrawable.textures[tostring(texture)]
    end
    if type(textureEntry) ~= 'table' then
        textureEntry = byDrawable[texture] or byDrawable[tostring(texture)]
    end

    if type(base) == 'table' and type(textureEntry) == 'table' and textureEntry ~= base then
        local merged = cmDeepMerge(base, textureEntry)
        -- The drawable-level (texture = -1) "default" row is the authoritative
        -- /clothingstore manager row for publish state, price and shop/org
        -- assignment; the exact-texture row only owns the captured image. A
        -- plain override-merge let an unpublished/disabled texture row (still
        -- awaiting a photo) silently disable an otherwise-published drawable,
        -- so these management fields are always taken from the base row.
        merged.enabled = base.enabled
        merged.price = base.price
        merged.shop = base.shop
        merged.job = base.job
        merged.gang = base.gang
        return merged
    end
    return type(textureEntry) == 'table' and textureEntry or base
end

local _CMItemsBaseResolveTorsoFit = CMItems.ResolveTorsoFit
function CMItems.ResolveTorsoFit(gender, torsoDrawable, torsoTexture, fallback)
    fallback = type(fallback) == 'table' and fallback or {}
    gender = CMItems.NormalizeClothingGender(gender)
    local catalog = CMItems.GetClothingCatalogEntry(gender, 'component', 11, torsoDrawable, torsoTexture)

    local mergedFallback = copyTable(fallback) or {}
    if type(catalog) == 'table' then
        if catalog.sleeveStyle ~= nil and mergedFallback.sleeveStyle == nil then mergedFallback.sleeveStyle = catalog.sleeveStyle end
        if catalog.sleeve ~= nil and mergedFallback.sleeve == nil then mergedFallback.sleeve = catalog.sleeve end
        if catalog.sleeve_type ~= nil and mergedFallback.sleeveType == nil then mergedFallback.sleeveType = catalog.sleeve_type end
        if catalog.arms ~= nil then mergedFallback.arms = catalog.arms end
        if catalog.armsTexture ~= nil then mergedFallback.armsTexture = catalog.armsTexture end
        if catalog.arms_texture ~= nil then mergedFallback.armsTexture = catalog.arms_texture end
        if catalog.undershirt ~= nil then mergedFallback.undershirt = catalog.undershirt end
        if catalog.undershirtTexture ~= nil then mergedFallback.undershirtTexture = catalog.undershirtTexture end
        if catalog.undershirt_texture ~= nil then mergedFallback.undershirtTexture = catalog.undershirt_texture end
    end

    local fit = _CMItemsBaseResolveTorsoFit(gender, torsoDrawable, torsoTexture, mergedFallback) or {}

    -- Catalog always wins when it contains explicit fit values.
    if type(catalog) == 'table' then
        if catalog.arms ~= nil then fit.arms = tonumber(catalog.arms) end
        if catalog.armsTexture ~= nil or catalog.arms_texture ~= nil then fit.armsTexture = tonumber(catalog.armsTexture or catalog.arms_texture) or 0 end
        if catalog.undershirt ~= nil then fit.undershirt = tonumber(catalog.undershirt) end
        if catalog.undershirtTexture ~= nil or catalog.undershirt_texture ~= nil then fit.undershirtTexture = tonumber(catalog.undershirtTexture or catalog.undershirt_texture) or 0 end
        if catalog.sleeveStyle or catalog.sleeve then fit.sleeveStyle = catalog.sleeveStyle or catalog.sleeve end
        if catalog.arms ~= nil or catalog.undershirt ~= nil then fit.torsoFitSource = 'catalog' end
    end

    return fit
end

local _CMItemsBaseBuildClothingMetadata = CMItems.BuildClothingMetadata
function CMItems.BuildClothingMetadata(categoryOrRaw, raw, opts)
    local metadata, err = _CMItemsBaseBuildClothingMetadata(categoryOrRaw, raw, opts)
    if type(metadata) ~= 'table' then return metadata, err end

    local catalog = CMItems.GetClothingCatalogEntry(
        metadata.gender,
        metadata.componentType,
        metadata.componentIndex,
        metadata.drawableId,
        metadata.textureId
    )

    if type(catalog) ~= 'table' then
        return metadata
    end

    if catalog.enabled ~= nil and catalog.enabled == false then
        metadata.catalogDisabled = true
    end

    metadata.catalogId = catalog.id or metadata.catalogId
    metadata.catalogManaged = true
    metadata.label = catalog.label or metadata.label
    metadata.description = catalog.description or metadata.description
    metadata.price = tonumber(catalog.price) or tonumber(metadata.price)
    metadata.shop = catalog.shop or metadata.shop
    metadata.displayCategory = catalog.displayCategory or catalog.category or metadata.displayCategory
    metadata.catalogCategory = catalog.category or metadata.catalogCategory
    metadata.job = catalog.job or metadata.job
    metadata.gang = catalog.gang or metadata.gang
    metadata.sleeveStyle = catalog.sleeveStyle or catalog.sleeve or metadata.sleeveStyle

    if catalog.image and catalog.image ~= '' then
        if tostring(catalog.image):find('^nui://') or tostring(catalog.image):find('^https?://') then
            metadata.image = catalog.image
        else
            metadata.image = ('nui://cm-items/ui/images/clothing/%s'):format(tostring(catalog.image))
        end
        metadata.icon = metadata.image
    end

    if metadata.categoryType == 'bags' then
        local catalogLevel = tonumber(catalog.bagLevel or catalog.bag_level or catalog.level)
        local incomingLevel = tonumber(metadata.bagLevel or metadata.bag_level or metadata.level)
        local finalLevel = catalogLevel or incomingLevel
        if finalLevel ~= nil then
            finalLevel = math.max(1, math.min(4, math.floor(finalLevel)))
            metadata.bagLevel = finalLevel
            if catalog.description and tostring(catalog.description) ~= '' then
                metadata.description = catalog.description
            else
                metadata.description = ('Level %s bag. Unlocks backpack slots.'):format(finalLevel)
            end
        end
        metadata.bag_level = nil
        metadata.level = nil
        metadata.backpackSlots = nil
        metadata.backpack_slots = nil
        metadata.maxWeight = nil
        metadata.max_weight = nil
        metadata.slots = nil
        metadata.weight = nil
        if CMItems.Config and CMItems.Config.Debug then
            print(('[CM-ITEMS] BuildClothingMetadata bag drawable=%s texture=%s image=%s bagLevel=%s'):format(
                tostring(metadata.drawableId), tostring(metadata.textureId), tostring(metadata.image), tostring(metadata.bagLevel)))
        end
    end

    if metadata.categoryType == 'torso' then
        local fit = CMItems.ResolveTorsoFit(metadata.gender, metadata.drawableId, metadata.textureId, {
            arms = metadata.arms,
            armsTexture = metadata.armsTexture,
            undershirt = metadata.undershirt,
            undershirtTexture = metadata.undershirtTexture,
            sleeveStyle = metadata.sleeveStyle,
        })
        metadata.arms = fit.arms
        metadata.armsTexture = fit.armsTexture or 0
        metadata.undershirt = fit.undershirt
        metadata.undershirtTexture = fit.undershirtTexture or 0
        metadata.torsoFitSource = fit.torsoFitSource or metadata.torsoFitSource
        metadata.fitResolved = metadata.fitResolved or fit.torsoFitSource == 'catalog'
    end

    return metadata
end
