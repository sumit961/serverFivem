local function log(message)
    print(('[CM-ITEMS] %s'):format(message))
end

local function removeFirstPackedArg(args)
    for i = 1, args.n - 1 do
        args[i] = args[i + 1]
    end
    args[args.n] = nil
    args.n = args.n - 1
    return args
end

local function normalizeExportArgs(...)
    -- table.pack preserves nil arguments by storing the real argument count in args.n.
    -- A plain { ... } + table.unpack(args) truncates everything after the first nil.
    local args = table.pack(...)

    -- FiveM Lua exports can be called as either dot or colon style.
    -- Older code removed ANY table passed as arg #1, but that breaks exports
    -- that intentionally receive a table, for example SaveClothingCatalogEntry(entry).
    -- Only strip arg #1 when it looks like the exports self-table, not a real payload.
    if type(args[1]) == 'table' and args.n > 1 then
        local first = args[1]
        local looksLikeClothingEntry = first.gender ~= nil
            or first.componentIndex ~= nil
            or first.component_index ~= nil
            or first.drawableId ~= nil
            or first.drawable_id ~= nil
            or first.category ~= nil
            or first.shop ~= nil

        local looksLikeMetadataOpts = first.label ~= nil
            or first.purchasedAt ~= nil
            or first.createdBy ~= nil
            or first.updatedBy ~= nil

        if not looksLikeClothingEntry and not looksLikeMetadataOpts then
            removeFirstPackedArg(args)
        end
    end

    return args
end

local function exportSafe(fn)
    return function(...)
        local args = normalizeExportArgs(...)
        local ok, result, extra = pcall(function()
            return fn(table.unpack(args, 1, args.n))
        end)

        if not ok then
            log(('Export error: %s'):format(tostring(result)))
            return nil
        end

        return result, extra
    end
end

CreateThread(function()
    Wait(500)
    local okDefs, defErrors = true, {}
    if CMItems.ValidateDefinitions then
        okDefs, defErrors = CMItems.ValidateDefinitions()
    end
    if okDefs ~= true and type(defErrors) == 'table' then
        for _, err in ipairs(defErrors) do log(('Definition warning: %s'):format(err)) end
    end

    local physicalCount = 0
    local virtualCount = 0

    for _ in pairs(CMItems.Items or {}) do physicalCount = physicalCount + 1 end
    for _ in pairs(CMItems.VirtualItems or {}) do virtualCount = virtualCount + 1 end

    log(('Started v1.2-cleanup-preview | physical items: %s | virtual items: %s'):format(physicalCount, virtualCount))
end)

exports('GetItem', exportSafe(function(name, includeVirtual)
    return CMItems.GetItem(name, includeVirtual)
end))

exports('GetPhysicalItem', exportSafe(function(name)
    return CMItems.GetPhysicalItem(name)
end))

exports('GetVirtualItem', exportSafe(function(name)
    return CMItems.GetVirtualItem(name)
end))

exports('Exists', exportSafe(function(name, includeVirtual)
    return CMItems.Exists(name, includeVirtual)
end))

exports('IsInventoryItem', exportSafe(function(name)
    return CMItems.IsInventoryItem(name)
end))

exports('IsVirtualItem', exportSafe(function(name)
    return CMItems.IsVirtualItem(name)
end))

exports('IsRobberyProtected', exportSafe(function(name)
    return CMItems.IsRobberyProtected(name)
end))

exports('GetAllItems', exportSafe(function()
    return CMItems.GetAllItems()
end))

exports('GetInventoryItems', exportSafe(function()
    return CMItems.GetInventoryItems()
end))

exports('GetVirtualItems', exportSafe(function()
    return CMItems.GetVirtualItems()
end))

exports('GetItemsByCategory', exportSafe(function(category, includeVirtual)
    return CMItems.GetItemsByCategory(category, includeVirtual)
end))

exports('GetWeight', exportSafe(function(name, amount)
    return CMItems.GetWeight(name, amount)
end))

exports('CanStack', exportSafe(function(name)
    return CMItems.CanStack(name)
end))

exports('ValidateMetadata', exportSafe(function(name, metadata)
    return CMItems.ValidateMetadata(name, metadata)
end))

exports('ValidateDefinitions', exportSafe(function()
    return CMItems.ValidateDefinitions()
end))

exports('GetItemWorldModel', exportSafe(function(name, metadata)
    return CMItems.GetItemWorldModel(name, metadata)
end))

exports('GetCategoryWorldModel', exportSafe(function(category)
    return CMItems.GetCategoryWorldModel(category)
end))


exports('GetClothingImage', exportSafe(function(gender, componentType, componentIndex, drawableId)
    return CMItems.GetClothingImage(gender, componentType, componentIndex, drawableId)
end))

exports('GetClothingCategoryDefinition', exportSafe(function(category)
    return CMItems.GetClothingCategoryDefinition(category)
end))

exports('GetClothingItemName', exportSafe(function(category)
    return CMItems.GetClothingItemName(category)
end))

exports('BuildClothingMetadata', exportSafe(function(categoryOrRaw, raw, opts)
    return CMItems.BuildClothingMetadata(categoryOrRaw, raw, opts)
end))


exports('ResolveTorsoFit', exportSafe(function(gender, torsoDrawable, torsoTexture, fallback)
    return CMItems.ResolveTorsoFit(gender, torsoDrawable, torsoTexture, fallback)
end))

exports('GetBestTorsoFit', exportSafe(function(gender, torsoDrawable, torsoTexture)
    return CMItems.GetBestTorsoFit(gender, torsoDrawable, torsoTexture)
end))

exports('RegisterItem', exportSafe(function(name, data)
    return CMItems.RegisterItem(name, data)
end))

exports('RegisterVirtualItem', exportSafe(function(name, data)
    return CMItems.RegisterVirtualItem(name, data)
end))

RegisterCommand('cmitem', function(src, args)
    if src ~= 0 then return end

    local name = args[1]
    if not name then
        log('Usage: cmitem <item_name>')
        return
    end

    local item, kind = CMItems.GetItem(name, true)
    if not item then
        log(('Item not found: %s'):format(name))
        return
    end

    log(('Item %s [%s] label=%s inventory=%s virtual=%s weight=%s'):format(
        item.name,
        kind,
        item.label,
        tostring(item.inventory),
        tostring(item.virtual),
        tostring(item.weight)
    ))
end, true)

--========================================================
-- SQL-backed Clothing Catalog
-- Loaded from DB so admins can manage clothes from in-game commands.
--========================================================

local ClothingCatalogReady = false

local function catalogBool(value, default)
    if value == nil then return default end
    if value == true or value == 1 or value == '1' or value == 'true' or value == 'yes' then return true end
    if value == false or value == 0 or value == '0' or value == 'false' or value == 'no' then return false end
    return default
end

local function ensureClothingCatalogTable()
    if not MySQL then
        log('MySQL not available; clothing catalog DB disabled.')
        return false
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS clothing_catalog (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            gender VARCHAR(16) NOT NULL DEFAULT 'male',
            component_type VARCHAR(16) NOT NULL DEFAULT 'component',
            component_index INT NOT NULL,
            drawable_id INT NOT NULL,
            texture_id INT NOT NULL DEFAULT -1,
            label VARCHAR(120) NULL,
            description TEXT NULL,
            price INT NOT NULL DEFAULT 0,
            category VARCHAR(80) NULL,
            shop VARCHAR(80) NULL,
            sleeve_style VARCHAR(30) NULL,
            arms INT NULL,
            arms_texture INT NOT NULL DEFAULT 0,
            undershirt INT NULL,
            undershirt_texture INT NOT NULL DEFAULT 0,
            bag_level INT NULL,
            backpack_slots INT NULL,
            max_weight INT NULL,
            armor_value INT NULL,
            -- NULL/empty = sell natively as `category`. Set to a different
            -- category name to sell/price/group/mechanic this row as that
            -- category instead (e.g. a slot-9 capture sold as 'bags'), while
            -- component_type/component_index above stay the physical truth
            -- used for identity and equip -- see sv_cloth.lua's
            -- effectiveCategoryOf() and cm-itemactions' swapClothing fix.
            sell_category VARCHAR(32) NULL,
            -- Only meaningful for category='bags' (component 5). true = a
            -- purely cosmetic alternate look for the bag slot (item
            -- clothing_bags_skin, no backpack capacity); false/default = a
            -- real functional bag (item clothing_bags, uses bag_level).
            bag_skin TINYINT(1) NOT NULL DEFAULT 0,
            -- Explicit cross-gender pairing for bags. GTA/addon bag drawables
            -- do NOT always mean the same physical bag at the same index on
            -- both freemode models, so unlike every other category, bags
            -- cannot assume "same drawable id = same item" across gender.
            -- When set, this row is understood to be the SAME logical bag as
            -- (paired_drawable_id, paired_texture_id) on the OTHER gender --
            -- price/label/level/publish/org sync across that explicit pair,
            -- but each side always keeps its OWN photographed image. NULL
            -- means unpaired (falls back to the old same-index assumption in
            -- sv_cloth.lua for rows never re-paired after this feature shipped).
            paired_drawable_id INT NULL,
            paired_texture_id INT NULL,
            image VARCHAR(255) NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            -- Distinct from `enabled`/publish state: enabled only controls
            -- whether the STORE sells new copies. temp_disabled additionally
            -- blocks equipping this exact item for players who already own
            -- it (cm-itemactions checks it before ever calling
            -- SetPedComponentVariation), for pulling a broken/exploited/
            -- under-review item out of use without deleting it outright.
            temp_disabled TINYINT(1) NOT NULL DEFAULT 0,
            job VARCHAR(80) NULL,
            gang VARCHAR(80) NULL,
            notes TEXT NULL,
            created_by VARCHAR(100) NULL,
            updated_by VARCHAR(100) NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY unique_clothing_catalog (gender, component_type, component_index, drawable_id, texture_id),
            INDEX idx_shop (shop),
            INDEX idx_category (category),
            INDEX idx_enabled (enabled),
            INDEX idx_component (gender, component_index, drawable_id)
        )
    ]])

    -- Safe migrations for older installs.
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS bag_level INT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS backpack_slots INT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS max_weight INT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS armor_value INT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS sell_category VARCHAR(32) NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS bag_skin TINYINT(1) NOT NULL DEFAULT 0') end)
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS paired_drawable_id INT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS paired_texture_id INT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS temp_disabled TINYINT(1) NOT NULL DEFAULT 0') end)
    -- Stable garment identity. drawable_id is a global index into every loaded
    -- apparel pack, so it renumbers whenever a pack is added/removed/reordered
    -- and the row silently starts describing a different garment. collection
    -- (the pack's <fullDlcName>, "" for base game) plus collection_local_id (the
    -- garment's index inside that pack) survive those changes; nv_cloth resolves
    -- the current global index from them at equip time. Rows captured before this
    -- shipped have NULL here and keep using drawable_id.
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS collection VARCHAR(64) NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS collection_local_id INT NULL') end)
    pcall(function() MySQL.query.await('CREATE INDEX idx_collection ON clothing_catalog (gender, component_index, collection, collection_local_id)') end)
    -- Server-minted id naming the folder that holds this item's captured images
    -- (ui/images/clothing/items/<asset_id>/). Unique so two rows can never share a
    -- folder, and never overwritten once set (see the upsert) so a row's images
    -- cannot be repointed at another item's folder. NULL for rows with no capture
    -- of their own, e.g. drawable-level thumbnail rows.
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS asset_id VARCHAR(48) NULL') end)
    pcall(function() MySQL.query.await('CREATE UNIQUE INDEX uniq_asset_id ON clothing_catalog (asset_id)') end)
    -- The other gender's bag, addressed the stable way. paired_drawable_id is a
    -- global index into the OTHER freemode model, and collections are per-model,
    -- so it renumbers on its own whenever an apparel pack changes -- which is what
    -- made paired bags turn into a different bag after a restart.
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS paired_collection VARCHAR(64) NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE clothing_catalog ADD COLUMN IF NOT EXISTS paired_collection_local_id INT NULL') end)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS clothing_catalog_organizations (
            clothing_id BIGINT NOT NULL,
            organization_id VARCHAR(80) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (clothing_id, organization_id),
            INDEX idx_clothing_org (organization_id, clothing_id)
        )
    ]])
    -- Preserve all existing one-organization assignments during upgrade.
    MySQL.query.await([[
        INSERT IGNORE INTO clothing_catalog_organizations (clothing_id, organization_id)
        SELECT id, LOWER(SUBSTRING(shop, 5)) FROM clothing_catalog
        WHERE LEFT(LOWER(shop), 4) = 'org_' AND LENGTH(shop) > 4
    ]])

    -- One-step undo for a bad retake: the previous image is snapshotted here
    -- (see CMItems.SaveClothingCatalogEntry) whenever a save overwrites an
    -- existing row's image, so /clothingstore can offer "revert to last photo".
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS clothing_catalog_image_history (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            clothing_id BIGINT NOT NULL,
            image VARCHAR(255) NOT NULL,
            replaced_by VARCHAR(100) NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_clothing_history (clothing_id, id)
        )
    ]])
    return true
end

local CATEGORY_TO_COMPONENT = {
    torso = { componentType = 'component', componentIndex = 11 },
    outerwear = { componentType = 'component', componentIndex = 11, category = 'torso' },
    tshirt = { componentType = 'component', componentIndex = 8 },
    shirt = { componentType = 'component', componentIndex = 8, category = 'tshirt' },
    pants = { componentType = 'component', componentIndex = 4 },
    legs = { componentType = 'component', componentIndex = 4, category = 'pants' },
    shoes = { componentType = 'component', componentIndex = 6 },
    chains = { componentType = 'component', componentIndex = 7 },
    bags = { componentType = 'component', componentIndex = 5 },
    hat = { componentType = 'prop', componentIndex = 0 },
    glasses = { componentType = 'prop', componentIndex = 1 },
    earrings = { componentType = 'prop', componentIndex = 2 },
    watches = { componentType = 'prop', componentIndex = 6 },
}

local COMPONENT_TO_CATEGORY = {
    component = { [11] = 'torso', [8] = 'tshirt', [4] = 'pants', [6] = 'shoes', [7] = 'chains', [5] = 'bags' },
    prop = { [0] = 'hat', [1] = 'glasses', [2] = 'earrings', [6] = 'watches' },
}

local function normaliseCatalogRow(row)
    if type(row) ~= 'table' then return nil end

    local gender = CMItems.NormalizeClothingGender(row.gender)
    local componentType = tostring(row.component_type or row.componentType or 'component'):lower()
    local componentIndex = tonumber(row.component_index or row.componentIndex)
    local drawableId = tonumber(row.drawable_id or row.drawableId or row.drawable)
    local textureId = tonumber(row.texture_id or row.textureId or row.texture)
    if textureId == nil then textureId = -1 end
    if not componentIndex or not drawableId then return nil end

    local category = row.category
    if not category or category == '' then
        if componentType == 'prop' then
            local propMap = { [0] = 'hat', [1] = 'glasses', [2] = 'earrings', [6] = 'watches', [7] = 'bracelet' }
            category = propMap[componentIndex]
        else
            local compMap = { [1] = 'mask', [3] = 'arms', [4] = 'pants', [5] = 'bags', [6] = 'shoes', [7] = 'chains', [8] = 'tshirt', [9] = 'armor', [10] = 'decals', [11] = 'torso' }
            category = compMap[componentIndex]
        end
    end
    category = CMItems.NormalizeClothingCategory(category) or category

    local entry = {
        id = tonumber(row.id),
        gender = gender,
        componentType = componentType,
        componentIndex = componentIndex,
        drawableId = drawableId,
        textureId = textureId,
        -- Stable identity; see the collection columns in ensureClothingCatalogTable.
        -- "" is a meaningful collection (base game), so only nil means "not recorded".
        collection = row.collection or row.collection_name or row.collectionName,
        collectionLocalId = tonumber(row.collection_local_id or row.collectionLocalId or row.collectionLocal),
        assetId = row.asset_id or row.assetId,
        label = row.label or row.name or (('%s %s'):format(tostring(category or 'clothing'), drawableId)),
        description = row.description,
        price = tonumber(row.price) or 0,
        category = category,
        shop = row.shop or 'clothes',
        sleeveStyle = row.sleeve_style or row.sleeveStyle,
        arms = row.arms ~= nil and tonumber(row.arms) or nil,
        armsTexture = tonumber(row.arms_texture or row.armsTexture) or 0,
        undershirt = row.undershirt ~= nil and tonumber(row.undershirt) or nil,
        undershirtTexture = tonumber(row.undershirt_texture or row.undershirtTexture) or 0,
        bagLevel = row.bag_level ~= nil and tonumber(row.bag_level) or tonumber(row.bagLevel or row.level),
        backpackSlots = row.backpack_slots ~= nil and tonumber(row.backpack_slots) or tonumber(row.backpackSlots or row.slots),
        maxWeight = row.max_weight ~= nil and tonumber(row.max_weight) or tonumber(row.maxWeight or row.weight),
        armorValue = row.armor_value ~= nil and tonumber(row.armor_value) or tonumber(row.armorValue),
        sellCategory = (function()
            local v = row.sell_category ~= nil and row.sell_category or row.sellCategory
            v = tostring(v or ''):lower()
            return v ~= '' and v or nil
        end)(),
        bagSkin = catalogBool(row.bag_skin ~= nil and row.bag_skin or row.bagSkin, false),
        pairedDrawableId = (row.paired_drawable_id ~= nil and tonumber(row.paired_drawable_id))
            or (row.pairedDrawableId ~= nil and tonumber(row.pairedDrawableId)) or nil,
        pairedTextureId = (row.paired_texture_id ~= nil and tonumber(row.paired_texture_id))
            or (row.pairedTextureId ~= nil and tonumber(row.pairedTextureId)) or nil,
        pairedCollection = row.paired_collection or row.pairedCollection,
        pairedCollectionLocalId = tonumber(row.paired_collection_local_id or row.pairedCollectionLocalId),
        image = row.image,
        enabled = catalogBool(row.enabled, true),
        tempDisabled = catalogBool(row.temp_disabled ~= nil and row.temp_disabled or row.tempDisabled, false),
        job = row.job,
        gang = row.gang,
        notes = row.notes,
        createdBy = row.createdBy or row.created_by,
        updatedBy = row.updatedBy or row.updated_by,
        createdAt = row.createdAt or row.created_at,
        updatedAt = row.updatedAt or row.updated_at,
    }

    if entry.category == 'bags' then
        local level = tonumber(entry.bagLevel)
        if level ~= nil then
            level = math.max(1, math.min(4, math.floor(level)))
            entry.bagLevel = level
            entry.description = entry.description or ('Level %s bag. Unlocks backpack slots.'):format(level)
        end
    end

    return entry
end

local function insertCatalogEntry(catalog, entry)
    if type(entry) ~= 'table' then return end
    local gender = CMItems.NormalizeClothingGender(entry.gender)
    local comp = tonumber(entry.componentIndex)
    local drawable = tonumber(entry.drawableId)
    local texture = tonumber(entry.textureId)
    if not comp or not drawable then return end
    if texture == nil then texture = -1 end

    catalog[gender] = catalog[gender] or {}
    catalog[gender][comp] = catalog[gender][comp] or {}
    catalog[gender][comp][drawable] = catalog[gender][comp][drawable] or {}

    local byDrawable = catalog[gender][comp][drawable]
    local payload = {
        id = entry.id,
        componentType = entry.componentType or 'component',
        label = entry.label,
        description = entry.description,
        price = tonumber(entry.price) or 0,
        category = entry.category,
        shop = entry.shop,
        sleeveStyle = entry.sleeveStyle,
        arms = entry.arms,
        armsTexture = entry.armsTexture,
        undershirt = entry.undershirt,
        undershirtTexture = entry.undershirtTexture,
        bagLevel = entry.bagLevel,
        backpackSlots = entry.backpackSlots,
        maxWeight = entry.maxWeight,
        armorValue = entry.armorValue,
        sellCategory = entry.sellCategory,
        bagSkin = entry.bagSkin,
        pairedDrawableId = entry.pairedDrawableId,
        pairedTextureId = entry.pairedTextureId,
        image = entry.image,
        -- Identity fields. These were missing here, so every consumer that
        -- reads the catalog through this payload -- the purchase path included
        -- -- saw nil and fell back to the raw drawable index, which is exactly
        -- the drift the collection columns exist to prevent.
        collection = entry.collection,
        collectionLocalId = entry.collectionLocalId,
        pairedCollection = entry.pairedCollection,
        pairedCollectionLocalId = entry.pairedCollectionLocalId,
        assetId = entry.assetId,
        enabled = entry.enabled ~= false,
        tempDisabled = entry.tempDisabled == true,
        job = entry.job,
        gang = entry.gang,
        notes = entry.notes,
        createdBy = entry.createdBy,
        updatedBy = entry.updatedBy,
        createdAt = entry.createdAt,
        updatedAt = entry.updatedAt,
    }

    if texture < 0 then
        byDrawable.default = payload
    else
        byDrawable.textures = byDrawable.textures or {}
        byDrawable.textures[texture] = payload
        byDrawable[texture] = payload
    end
end

local function syncCatalog(target)
    if not ClothingCatalogReady then return end
    if target and tonumber(target) and tonumber(target) > 0 then
        TriggerClientEvent('cm-items:client:setClothingCatalog', tonumber(target), CMItems.Clothing.Catalog or { male = {}, female = {} })
    else
        TriggerClientEvent('cm-items:client:setClothingCatalog', -1, CMItems.Clothing.Catalog or { male = {}, female = {} })
    end
end

-- ---------------------------------------------------------------------------
-- Live catalog linkage
--
-- A purchased clothing item used to be a frozen copy of its catalog row, so
-- renaming an item, retaking its photo or swapping the garment behind it only
-- ever affected the shop -- every copy already in a player's inventory kept the
-- old values forever.
--
-- Instead, an owned item carries asset_id, a permanent pointer to its catalog
-- row, and the presentation/appearance fields are read back from the live row
-- every time the item is loaded. Editing the row updates every copy that
-- exists, including for offline players, with no migration to run.
--
-- asset_id is the ONLY field that must never change once minted: it is the
-- link. Everything else about a row is free to be edited or replaced.
-- ---------------------------------------------------------------------------

local function newCatalogAssetId()
    return ('ci_%x_%06x%06x%06x'):format(
        os.time(), math.random(0, 0xFFFFFF), math.random(0, 0xFFFFFF), math.random(0, 0xFFFFFF))
end

-- Keyed exactly as an owned item addresses itself, so the legacy lookup below
-- (items bought before asset_id existed) can find its row.
local function catalogIdentityKey(gender, componentType, componentIndex, drawableId, textureId)
    return ('%s|%s|%s|%s|%s'):format(
        tostring(gender or ''):lower(),
        tostring(componentType or 'component'):lower(),
        tonumber(componentIndex) or -1,
        tonumber(drawableId) or -1,
        tonumber(textureId) or -1)
end

local function rebuildCatalogIndexes(flatRows)
    local byAssetId, byIdentity = {}, {}
    for _, entry in ipairs(flatRows) do
        if entry.assetId and entry.assetId ~= '' then
            byAssetId[entry.assetId] = entry
        end
        byIdentity[catalogIdentityKey(entry.gender, entry.componentType, entry.componentIndex,
            entry.drawableId, entry.textureId)] = entry
    end
    CMItems.Clothing.ByAssetId = byAssetId
    CMItems.Clothing.ByIdentity = byIdentity
end

-- Fills in asset_id for rows that predate it. Only ever touches rows where it
-- IS NULL, so an id is minted once and then never moves.
local function backfillCatalogAssetIds(flatRows)
    local minted = 0
    for _, entry in ipairs(flatRows) do
        if (not entry.assetId or entry.assetId == '') and entry.id then
            local assetId = newCatalogAssetId()
            local ok, affected = pcall(function()
                return MySQL.update.await(
                    'UPDATE clothing_catalog SET asset_id = ? WHERE id = ? AND asset_id IS NULL',
                    { assetId, entry.id })
            end)
            if ok and (tonumber(affected) or 0) > 0 then
                entry.assetId = assetId
                minted = minted + 1
            end
        end
    end
    return minted
end

-- The live row behind an owned item.
--   1. asset_id -- the permanent link. Survives renames, retakes and garment
--      swaps, because none of those change it.
--   2. the drawable tuple -- for items bought before asset_id existed. Tries
--      the exact texture first, then the drawable-level (texture -1) row that
--      /clothingstore groups captures under.
-- Returns the row plus whether it was found by the stable link, so callers can
-- tell a real match from a best-effort legacy one.
function CMItems.ResolveOwnedClothingRow(metadata)
    if type(metadata) ~= 'table' then return nil end
    if not ClothingCatalogReady then return nil end

    local assetId = metadata.assetId or metadata.asset_id
    if assetId and assetId ~= '' then
        local row = (CMItems.Clothing.ByAssetId or {})[assetId]
        if row then return row, true end
        -- An asset_id that no longer resolves means the row was deleted. Do NOT
        -- fall through to the tuple: a deleted row's drawable index may since
        -- have been reused by a different item, and silently rebinding an owned
        -- item to an unrelated garment is the exact failure this design exists
        -- to prevent. Keep the item's own snapshot instead.
        return nil, false
    end

    local byIdentity = CMItems.Clothing.ByIdentity or {}
    local gender = tostring(metadata.gender or ''):lower()
    local componentType = metadata.componentType or metadata.component_type or 'component'
    local componentIndex = tonumber(metadata.componentIndex or metadata.component_index)
    local drawableId = tonumber(metadata.drawableId or metadata.drawable)
    local textureId = tonumber(metadata.textureId or metadata.texture)
    if not componentIndex or not drawableId then return nil, false end

    -- gender 'both' (shared-gender bags) has no single row; try male then female.
    local genders = (gender == 'both' or gender == '') and { 'male', 'female' } or { gender }
    for _, g in ipairs(genders) do
        local exact = textureId and byIdentity[catalogIdentityKey(g, componentType, componentIndex, drawableId, textureId)]
        if exact then return exact, false end
        local drawableLevel = byIdentity[catalogIdentityKey(g, componentType, componentIndex, drawableId, -1)]
        if drawableLevel then return drawableLevel, false end
    end

    return nil, false
end

-- Fields the catalog owns. Everything not listed here belongs to the individual
-- item (when it was bought, what it cost at the time, durability, serials) and
-- is never overwritten by a catalog edit.
--
-- 'price' is included deliberately: nv_cloth's priceFor() values a sell-back
-- from metadata.price, so leaving it frozen would make the shop and the
-- sell-back price disagree after any price edit. Owned items are therefore
-- worth what the item is worth today, not what the player happened to pay.
--
-- 'category' and 'bagSkin' are deliberately NOT live. Both decide which
-- inventory item a garment is (clothing_tshirt vs clothing_torso vs
-- clothing_bags_skin) and which equipment slot it occupies, but the item's
-- item_name column is already written and is not rewritten here. Refreshing
-- them would leave rows whose category and item_name disagree. Re-categorising
-- an existing item is a rename, not a refresh, and belongs in the migration
-- path (RetagClothingItems) that already exists for it.
local LIVE_CLOTHING_FIELDS = {
    'label', 'description', 'image', 'price',
    'drawableId', 'textureId', 'collection', 'collectionLocalId',
    'pairedDrawableId', 'pairedTextureId', 'pairedCollection', 'pairedCollectionLocalId',
    'componentType', 'componentIndex',
    'sleeveStyle', 'arms', 'armsTexture', 'undershirt', 'undershirtTexture',
    'bagLevel', 'backpackSlots', 'maxWeight', 'armorValue',
}

-- Overlays the live catalog row onto an owned item's metadata, in place.
-- Returns the metadata plus whether anything was resolved.
--
-- When the row is gone (item deleted from the catalog) the stored snapshot is
-- left untouched, so deleting an item from the shop never breaks or blanks the
-- copies players already own.
function CMItems.ApplyLiveClothingMetadata(metadata)
    if type(metadata) ~= 'table' then return metadata, false end

    local row, viaAssetId = CMItems.ResolveOwnedClothingRow(metadata)
    if not row then return metadata, false end

    -- Stamp the link onto legacy items so every later lookup is O(1) and, more
    -- importantly, survives the garment behind the item being swapped out.
    if not viaAssetId and row.assetId and row.assetId ~= '' then
        metadata.assetId = row.assetId
        metadata.asset_id = row.assetId
    end

    for _, field in ipairs(LIVE_CLOTHING_FIELDS) do
        local value = row[field]
        if value ~= nil then metadata[field] = value end
    end

    -- Keep the aliases the rest of the stack reads by other names in step.
    metadata.icon = metadata.image
    metadata.drawable = metadata.drawableId
    metadata.texture = metadata.textureId

    -- A shared-gender bag stores the wearer's own side under maleDrawableId /
    -- femaleDrawableId; refresh whichever side this row represents so a swapped
    -- or re-paired bag follows too.
    if metadata.maleDrawableId ~= nil or metadata.femaleDrawableId ~= nil then
        if tostring(row.gender):lower() == 'female' then
            metadata.femaleDrawableId = row.drawableId
            metadata.femaleTextureId = row.textureId
            if row.pairedDrawableId ~= nil then
                metadata.maleDrawableId = row.pairedDrawableId
                metadata.maleTextureId = row.pairedTextureId or 0
            end
        else
            metadata.maleDrawableId = row.drawableId
            metadata.maleTextureId = row.textureId
            if row.pairedDrawableId ~= nil then
                metadata.femaleDrawableId = row.pairedDrawableId
                metadata.femaleTextureId = row.pairedTextureId or 0
            end
        end
    end

    return metadata, true
end

-- Tells cm-inventory to re-send inventories so players see edited clothing
-- without relogging. Coalesces bursts of saves into one refresh.
local ownedRefreshQueued = false
local function requestOwnedClothingRefresh()
    if ownedRefreshQueued then return end
    ownedRefreshQueued = true
    CreateThread(function()
        Wait(2000)
        ownedRefreshQueued = false
        if GetResourceState('cm-inventory') ~= 'started' then return end
        pcall(function() return exports['cm-inventory']:RefreshClothingDisplays() end)
    end)
end

function CMItems.ReloadClothingCatalog()
    if not ensureClothingCatalogTable() then return false end
    local rows = MySQL.query.await('SELECT * FROM clothing_catalog WHERE enabled = 1 OR enabled = 0 ORDER BY gender, component_index, drawable_id, texture_id') or {}
    local catalog = { male = {}, female = {} }
    local organizationRows = MySQL.query.await('SELECT clothing_id, organization_id FROM clothing_catalog_organizations') or {}
    local organizationsById = {}
    for _, assignment in ipairs(organizationRows) do
        local clothingId = tonumber(assignment.clothing_id)
        local organizationId = tostring(assignment.organization_id or ''):lower()
        if clothingId and organizationId ~= '' then
            organizationsById[clothingId] = organizationsById[clothingId] or {}
            organizationsById[clothingId][organizationId] = true
        end
    end
    local flatRows = {}
    local count = 0

    for _, row in ipairs(rows) do
        local entry = normaliseCatalogRow(row)
        if entry then
            entry.organizations = organizationsById[entry.id] or {}
            insertCatalogEntry(catalog, entry)
            flatRows[#flatRows + 1] = entry
            count = count + 1
        end
    end

    CMItems.SetClothingCatalog(catalog)
    CMItems.Clothing.CatalogRows = flatRows

    -- Every row must own an asset_id before the indexes are built: it is the
    -- link owned items resolve through. A no-op once each row has one.
    local minted = backfillCatalogAssetIds(flatRows)
    rebuildCatalogIndexes(flatRows)

    -- A reload after the first one means the catalog actually changed, so push
    -- the new values to anyone holding an affected item. Debounced because a
    -- single admin action can save several rows (a shared-gender capture saves
    -- two, plus a drawable-level thumbnail) and each one reloads.
    local wasReady = ClothingCatalogReady
    ClothingCatalogReady = true
    syncCatalog()
    if wasReady then requestOwnedClothingRefresh() end
    if minted > 0 then
        log(('Minted asset ids for %s catalog rows that had none'):format(minted))
    end
    log(('Loaded clothing catalog rows: %s'):format(count))
    return true, count
end

-- Points an existing catalog row at a different garment WITHOUT changing its
-- identity, so every copy players already own becomes the new garment.
--
-- The ordinary save path keys on (gender, component_type, component_index,
-- drawable_id, texture_id), so changing the drawable there inserts a SECOND row
-- and leaves owned items pointing at the original. This moves the row instead:
-- same database id, same asset_id, new appearance.
--
-- Deliberately a separate function rather than a branch inside
-- SaveClothingCatalogEntry: several callers build an entry by copying an
-- existing row and then changing its drawable (mirror rows, drawable-level
-- thumbnails, bag pairing). If the ordinary save treated a carried-over
-- asset_id as "move this row", those callers would silently relocate the
-- original item instead of creating a new one. Replacing has to be something a
-- caller asks for explicitly.
function CMItems.ReplaceClothingCatalogGarment(assetId, spec)
    if not ensureClothingCatalogTable() then return false, 'catalog_table_unavailable' end
    assetId = tostring(assetId or '')
    if assetId == '' then return false, 'missing_asset_id' end
    spec = type(spec) == 'table' and spec or {}

    local current = (CMItems.Clothing.ByAssetId or {})[assetId]
    if not current then return false, 'unknown_asset_id' end

    local drawableId = tonumber(spec.drawableId or spec.drawable)
    if not drawableId then return false, 'missing_drawable' end
    local textureId = tonumber(spec.textureId or spec.texture) or 0
    local componentType = tostring(spec.componentType or current.componentType or 'component'):lower()
    local componentIndex = tonumber(spec.componentIndex) or tonumber(current.componentIndex)
    if not componentIndex then return false, 'missing_component' end

    -- The target address must be free. Moving onto a tuple another row already
    -- occupies would violate the catalog's unique key, and silently merging two
    -- distinct items into one is never what the admin meant.
    local occupant = (CMItems.Clothing.ByIdentity or {})[catalogIdentityKey(
        current.gender, componentType, componentIndex, drawableId, textureId)]
    if occupant and occupant.assetId ~= assetId then
        return false, ('target_in_use_by:%s'):format(tostring(occupant.label or occupant.id))
    end

    -- An item's photo must always show the garment the item actually is.
    --
    -- Enforced here rather than trusted to callers, because this is the only
    -- function that can move a row onto a different garment. Changing the
    -- drawable without supplying a photo of it leaves the old picture
    -- describing clothing the item no longer wears, and there is no way to tell
    -- afterwards which of the two is wrong.
    --
    -- Both legitimate callers satisfy this naturally: a capture photographs the
    -- garment it is pointing at, and a revert restores the previous photo
    -- alongside the previous drawable.
    local movingGarment = drawableId ~= tonumber(current.drawableId)
        or textureId ~= tonumber(current.textureId)
    if movingGarment and (not spec.image or spec.image == '') then
        return false, 'image_required_for_garment_change'
    end

    -- collection is written unconditionally, so a caller that supplies none
    -- CLEARS it. That is intentional and both callers depend on it:
    --   * a photo-capture replace supplies the new garment's collection;
    --   * a manual drawable reassign has none to supply, and the old value now
    --     describes a different garment. Keeping it would win over the new
    --     drawable at equip time (collection addressing takes priority) and the
    --     item would still render as the garment it was moved away from.
    local ok, err = pcall(function()
        MySQL.update.await([[
            UPDATE clothing_catalog
            SET component_type = ?, component_index = ?, drawable_id = ?, texture_id = ?,
                collection = ?, collection_local_id = ?, updated_by = ?
            WHERE asset_id = ?
        ]], {
            componentType, componentIndex, drawableId, textureId,
            spec.collection, spec.collectionLocalId ~= nil and tonumber(spec.collectionLocalId) or nil,
            spec.updatedBy or current.updatedBy, assetId
        })
    end)
    if not ok then return false, tostring(err) end

    -- Optional presentation changes in the same operation, so a replacement can
    -- carry its own name and photo.
    if spec.label and spec.label ~= '' then
        pcall(function()
            MySQL.update.await('UPDATE clothing_catalog SET label = ? WHERE asset_id = ?', { tostring(spec.label), assetId })
        end)
    end
    if spec.image and spec.image ~= '' then
        pcall(function()
            MySQL.update.await('UPDATE clothing_catalog SET image = ? WHERE asset_id = ?', { tostring(spec.image), assetId })
        end)
    end

    CMItems.ReloadClothingCatalog()
    return true, (CMItems.Clothing.ByAssetId or {})[assetId]
end

function CMItems.SaveClothingCatalogEntry(entry)
    if not ensureClothingCatalogTable() then return false, 'catalog_table_unavailable' end
    entry = normaliseCatalogRow(entry)
    if not entry then return false, 'invalid_catalog_entry' end

    if CMItems.Config and CMItems.Config.Debug then
        print(('[CM-ITEMS] SaveCatalog category=%s gender=%s drawable=%s texture=%s image=%s bagLevel=%s enabled=%s'):format(
            tostring(entry.category), tostring(entry.gender), tostring(entry.drawableId), tostring(entry.textureId), tostring(entry.image), tostring(entry.bagLevel), tostring(entry.enabled)))
    end

    -- Snapshot the outgoing image before it's overwritten (retake undo). Only
    -- when the image is actually changing -- a price/publish-only edit isn't a
    -- "revision" and shouldn't push a history entry.
    if entry.image and entry.image ~= '' then
        local ok, existingRows = pcall(function()
            return MySQL.query.await(
                'SELECT id, image FROM clothing_catalog WHERE gender = ? AND component_type = ? AND component_index = ? AND drawable_id = ? AND texture_id = ?',
                { entry.gender, entry.componentType, entry.componentIndex, entry.drawableId, entry.textureId })
        end)
        local existingRow = ok and type(existingRows) == 'table' and existingRows[1] or nil
        if existingRow and existingRow.image and existingRow.image ~= '' and existingRow.image ~= entry.image then
            pcall(function()
                MySQL.insert.await(
                    'INSERT INTO clothing_catalog_image_history (clothing_id, image, replaced_by) VALUES (?, ?, ?)',
                    { existingRow.id, existingRow.image, entry.updatedBy or entry.createdBy })
                -- Keep only the last 5 revisions per item so this never grows unbounded.
                MySQL.query.await([[
                    DELETE FROM clothing_catalog_image_history
                    WHERE clothing_id = ? AND id NOT IN (
                        SELECT id FROM (
                            SELECT id FROM clothing_catalog_image_history WHERE clothing_id = ? ORDER BY id DESC LIMIT 5
                        ) keep_ids
                    )
                ]], { existingRow.id, existingRow.id })
            end)
        end
    end

    MySQL.query.await([[
        INSERT INTO clothing_catalog
        (gender, component_type, component_index, drawable_id, texture_id, label, description, price, category, shop,
         sleeve_style, arms, arms_texture, undershirt, undershirt_texture, bag_level, backpack_slots, max_weight, armor_value, sell_category, bag_skin, paired_drawable_id, paired_texture_id, image, enabled, temp_disabled, job, gang, notes, created_by, updated_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label),
            description = VALUES(description),
            price = VALUES(price),
            category = VALUES(category),
            shop = VALUES(shop),
            sleeve_style = VALUES(sleeve_style),
            arms = VALUES(arms),
            arms_texture = VALUES(arms_texture),
            undershirt = VALUES(undershirt),
            undershirt_texture = VALUES(undershirt_texture),
            bag_level = VALUES(bag_level),
            backpack_slots = VALUES(backpack_slots),
            max_weight = VALUES(max_weight),
            armor_value = VALUES(armor_value),
            sell_category = VALUES(sell_category),
            bag_skin = VALUES(bag_skin),
            paired_drawable_id = VALUES(paired_drawable_id),
            paired_texture_id = VALUES(paired_texture_id),
            image = VALUES(image),
            enabled = VALUES(enabled),
            temp_disabled = VALUES(temp_disabled),
            job = VALUES(job),
            gang = VALUES(gang),
            notes = VALUES(notes),
            updated_by = VALUES(updated_by)
    ]], {
        entry.gender,
        entry.componentType,
        entry.componentIndex,
        entry.drawableId,
        entry.textureId,
        entry.label,
        entry.description,
        entry.price,
        entry.category,
        entry.shop,
        entry.sleeveStyle,
        entry.arms,
        entry.armsTexture or 0,
        entry.undershirt,
        entry.undershirtTexture or 0,
        entry.bagLevel,
        entry.backpackSlots,
        entry.maxWeight,
        entry.armorValue,
        (entry.sellCategory and entry.sellCategory ~= '' and tostring(entry.sellCategory):lower()) or nil,
        entry.bagSkin == true and 1 or 0,
        entry.pairedDrawableId,
        entry.pairedTextureId,
        entry.image,
        entry.enabled ~= false and 1 or 0,
        entry.tempDisabled == true and 1 or 0,
        entry.job,
        entry.gang,
        entry.notes,
        entry.createdBy,
        entry.updatedBy or entry.createdBy,
    })

    -- collection/asset_id are written separately rather than as three more
    -- columns on the statement above. That statement already passes 31 values,
    -- many of them nil, and adding to it produced parameters that reached the
    -- driver misaligned by one -- gender arrived NULL and updated_by fell off
    -- the end. These two statements pass no nils at all, so there is no hole for
    -- the ordering to slip through, and each only runs when it has something to
    -- record.
    local identityWhere = 'WHERE gender = ? AND component_type = ? AND component_index = ? AND drawable_id = ? AND texture_id = ?'
    local identityArgs = { entry.gender, entry.componentType, entry.componentIndex, entry.drawableId, entry.textureId }

    if entry.collection ~= nil and entry.collectionLocalId ~= nil then
        pcall(function()
            MySQL.query.await(
                'UPDATE clothing_catalog SET collection = ?, collection_local_id = ? ' .. identityWhere,
                { entry.collection, entry.collectionLocalId,
                  identityArgs[1], identityArgs[2], identityArgs[3], identityArgs[4], identityArgs[5] })
        end)
    end

    if entry.pairedCollection ~= nil and entry.pairedCollectionLocalId ~= nil then
        pcall(function()
            MySQL.query.await(
                'UPDATE clothing_catalog SET paired_collection = ?, paired_collection_local_id = ? ' .. identityWhere,
                { entry.pairedCollection, entry.pairedCollectionLocalId,
                  identityArgs[1], identityArgs[2], identityArgs[3], identityArgs[4], identityArgs[5] })
        end)
    end

    -- COALESCE keeps the stored id: once a row owns an image folder, no later
    -- save can point it at another item's folder.
    if entry.assetId ~= nil then
        pcall(function()
            MySQL.query.await(
                'UPDATE clothing_catalog SET asset_id = COALESCE(asset_id, ?) ' .. identityWhere,
                { entry.assetId,
                  identityArgs[1], identityArgs[2], identityArgs[3], identityArgs[4], identityArgs[5] })
        end)
    end

    if entry.textureId < 0 then
        pcall(function()
            MySQL.query.await([[
                UPDATE clothing_catalog SET
                    label = ?,
                    description = ?,
                    price = ?,
                    category = ?,
                    shop = ?,
                    sleeve_style = ?,
                    arms = ?,
                    arms_texture = ?,
                    undershirt = ?,
                    undershirt_texture = ?,
                    bag_level = ?,
                    backpack_slots = ?,
                    max_weight = ?,
                    armor_value = ?,
                    sell_category = ?,
                    bag_skin = ?,
                    paired_drawable_id = ?,
                    paired_texture_id = ?,
                    enabled = ?,
                    temp_disabled = ?,
                    job = ?,
                    gang = ?,
                    notes = ?,
                    updated_by = ?
                WHERE gender = ? AND component_type = ? AND component_index = ? AND drawable_id = ? AND texture_id >= 0
            ]], {
                entry.label,
                entry.description,
                entry.price,
                entry.category,
                entry.shop,
                entry.sleeveStyle,
                entry.arms,
                entry.armsTexture or 0,
                entry.undershirt,
                entry.undershirtTexture or 0,
                entry.bagLevel,
                entry.backpackSlots,
                entry.maxWeight,
                entry.armorValue,
                (entry.sellCategory and entry.sellCategory ~= '' and tostring(entry.sellCategory):lower()) or nil,
                entry.bagSkin == true and 1 or 0,
                entry.pairedDrawableId,
                entry.pairedTextureId,
                entry.enabled ~= false and 1 or 0,
                entry.tempDisabled == true and 1 or 0,
                entry.job,
                entry.gang,
                entry.notes,
                entry.updatedBy or entry.createdBy,
                entry.gender,
                entry.componentType,
                entry.componentIndex,
                entry.drawableId,
            })
        end)
    end

    CMItems.ReloadClothingCatalog()
    return true
end

-- Most recent revisions first, for a small "revision history" list in the UI.
function CMItems.GetClothingImageHistory(clothingId, limit)
    clothingId = tonumber(clothingId)
    if not clothingId then return {} end
    limit = math.max(1, math.min(20, math.floor(tonumber(limit) or 5)))
    local rows = MySQL.query.await(
        'SELECT id, image, replaced_by, created_at FROM clothing_catalog_image_history WHERE clothing_id = ? ORDER BY id DESC LIMIT ' .. limit,
        { clothingId }) or {}
    return rows
end

-- One-step undo: swap the row's current image back to its most recent history
-- entry, and push the image being replaced into history in its place so the
-- admin can flip back and forth if they change their mind again.
function CMItems.RevertClothingImage(clothingId, actorLabel)
    clothingId = tonumber(clothingId)
    if not clothingId then return false, 'invalid_id' end
    if not ensureClothingCatalogTable() then return false, 'catalog_table_unavailable' end

    local histRows = MySQL.query.await(
        'SELECT id, image FROM clothing_catalog_image_history WHERE clothing_id = ? ORDER BY id DESC LIMIT 1',
        { clothingId }) or {}
    local hist = histRows[1]
    if not hist then return false, 'no_history' end

    local curRows = MySQL.query.await('SELECT image FROM clothing_catalog WHERE id = ?', { clothingId }) or {}
    local current = curRows[1]
    if not current then return false, 'row_not_found' end

    MySQL.update.await('UPDATE clothing_catalog SET image = ?, updated_by = ? WHERE id = ?',
        { hist.image, actorLabel, clothingId })
    MySQL.query.await('DELETE FROM clothing_catalog_image_history WHERE id = ?', { hist.id })

    if current.image and current.image ~= '' and current.image ~= hist.image then
        pcall(function()
            MySQL.insert.await(
                'INSERT INTO clothing_catalog_image_history (clothing_id, image, replaced_by) VALUES (?, ?, ?)',
                { clothingId, current.image, actorLabel })
        end)
    end

    CMItems.ReloadClothingCatalog()
    return true, hist.image
end

-- Fast in-memory check (no DB hit) for cm-itemactions to gate equipping an
-- already-owned item -- exact texture row wins, falling back to the
-- drawable-level master row so disabling "the whole item" from its master
-- also blocks every one of its color variants, matching how temp_disabled
-- is propagated to every texture row in SaveClothingCatalogEntry.
function CMItems.IsClothingTempDisabled(gender, componentIndex, drawableId, textureId)
    gender = CMItems.NormalizeClothingGender(gender)
    componentIndex = tonumber(componentIndex)
    drawableId = tonumber(drawableId)
    textureId = tonumber(textureId)
    local byDrawable = CMItems.Clothing.Catalog
        and CMItems.Clothing.Catalog[gender]
        and CMItems.Clothing.Catalog[gender][componentIndex]
        and CMItems.Clothing.Catalog[gender][componentIndex][drawableId]
    if not byDrawable then return false end

    if textureId ~= nil and textureId >= 0 and byDrawable.textures and byDrawable.textures[textureId] then
        return byDrawable.textures[textureId].tempDisabled == true
    end
    return byDrawable.default and byDrawable.default.tempDisabled == true or false
end

function CMItems.DeleteClothingCatalogEntry(gender, componentType, componentIndex, drawableId, textureId)
    if not ensureClothingCatalogTable() then return false, 'catalog_table_unavailable' end
    gender = CMItems.NormalizeClothingGender(gender)
    componentType = tostring(componentType or 'component'):lower()
    componentIndex = tonumber(componentIndex)
    drawableId = tonumber(drawableId)
    textureId = tonumber(textureId)
    if textureId == nil then textureId = -1 end
    if not componentIndex or not drawableId then return false, 'invalid_catalog_key' end

    -- Rows only ever exist per gender. 'both' is a DISPLAY state for an item that
    -- exists as a male row AND a female row (shared-gender bags), so deleting one
    -- has to remove both. Deleting WHERE gender = 'both' matched nothing, and this
    -- returned true regardless, so the panel reported success and the card came
    -- back on the next refresh.
    local genders = gender == 'both' and { 'male', 'female' } or { gender }
    local removed = 0

    for _, forGender in ipairs(genders) do
        local affected
        local ok = pcall(function()
            affected = MySQL.update.await(
                'DELETE FROM clothing_catalog WHERE gender = ? AND component_type = ? AND component_index = ? AND drawable_id = ? AND texture_id = ?',
                { forGender, componentType, componentIndex, drawableId, textureId })
        end)
        if ok then
            removed = removed + (tonumber(affected) or 0)
        end
    end

    -- Organisation assignments reference the row by id, so drop any that no
    -- longer point at a live catalog row.
    if removed > 0 then
        pcall(function()
            MySQL.query.await(
                'DELETE FROM clothing_catalog_organizations WHERE clothing_id NOT IN (SELECT id FROM clothing_catalog)')
        end)
    end

    CMItems.ReloadClothingCatalog()
    if removed == 0 then return false, 'catalog_row_not_found' end
    return true
end

CreateThread(function()
    Wait(1000)
    CMItems.ReloadClothingCatalog()
end)

AddEventHandler('playerJoining', function()
    local src = source
    CreateThread(function()
        Wait(2500)
        syncCatalog(src)
    end)
end)

RegisterNetEvent('cm-items:server:requestCatalogSync', function()
    syncCatalog(source)
end)


function CMItems.GetClothingCatalogRows(filters)
    filters = type(filters) == 'table' and filters or {}
    local rows = CMItems.Clothing.CatalogRows or {}
    local out = {}

    local filterGender = filters.gender and CMItems.NormalizeClothingGender(filters.gender) or nil
    local filterShop = filters.shop and tostring(filters.shop):lower() or nil
    local filterCategory = filters.category and tostring(filters.category):lower() or nil
    local filterComponent = tonumber(filters.componentIndex)
    local includeDisabled = filters.includeDisabled ~= false

    for _, row in ipairs(rows) do
        local ok = true
        if filterGender and row.gender ~= filterGender then ok = false end
        local filterOrg = filterShop and filterShop:match('^org_(.+)$') or nil
        local assignedToOrg = filterOrg and type(row.organizations) == 'table' and row.organizations[filterOrg] == true
        if filterShop and tostring(row.shop or ''):lower() ~= filterShop and not assignedToOrg then ok = false end
        if filterCategory and tostring(row.category or ''):lower() ~= filterCategory then ok = false end
        if filterComponent and tonumber(row.componentIndex) ~= filterComponent then ok = false end
        if not includeDisabled and row.enabled == false then ok = false end

        if ok then
            out[#out + 1] = {
                id = row.id,
                gender = row.gender,
                componentType = row.componentType or 'component',
                componentIndex = tonumber(row.componentIndex),
                drawableId = tonumber(row.drawableId),
                textureId = tonumber(row.textureId) or -1,
                label = row.label,
                description = row.description,
                price = tonumber(row.price) or 0,
                category = row.category,
                shop = assignedToOrg and filterShop or row.shop,
                sleeveStyle = row.sleeveStyle,
                arms = row.arms,
                armsTexture = tonumber(row.armsTexture) or 0,
                undershirt = row.undershirt,
                undershirtTexture = tonumber(row.undershirtTexture) or 0,
                bagLevel = row.bagLevel,
                backpackSlots = row.backpackSlots,
                maxWeight = row.maxWeight,
                armorValue = row.armorValue,
                sellCategory = row.sellCategory,
                bagSkin = row.bagSkin == true,
                pairedDrawableId = row.pairedDrawableId,
                pairedTextureId = row.pairedTextureId,
                image = row.image,
                -- See insertCatalogEntry: identity fields must survive this
                -- projection or callers silently fall back to raw indices.
                collection = row.collection,
                collectionLocalId = row.collectionLocalId,
                pairedCollection = row.pairedCollection,
                pairedCollectionLocalId = row.pairedCollectionLocalId,
                assetId = row.assetId,
                enabled = row.enabled ~= false,
                tempDisabled = row.tempDisabled == true,
                job = assignedToOrg and filterOrg or row.job,
                organizations = (function()
                    local list = {}
                    for organizationId, assigned in pairs(row.organizations or {}) do
                        if assigned == true then list[#list + 1] = organizationId end
                    end
                    table.sort(list)
                    return list
                end)(),
                gang = row.gang,
                notes = row.notes,
                createdBy = row.createdBy,
                updatedBy = row.updatedBy,
                createdAt = row.createdAt,
                updatedAt = row.updatedAt,
            }
        end
    end

    return out
end

function CMItems.SetClothingCatalogOrganizations(identity, organizations)
    if not ensureClothingCatalogTable() then return false, 'catalog_table_unavailable' end
    identity = type(identity) == 'table' and identity or {}
    local gender = CMItems.NormalizeClothingGender(identity.gender)
    local componentType = tostring(identity.componentType or identity.component_type or 'component'):lower()
    local componentIndex = tonumber(identity.componentIndex or identity.component_index)
    local drawableId = tonumber(identity.drawableId or identity.drawable_id or identity.drawable)
    local textureId = tonumber(identity.textureId or identity.texture_id or identity.texture)
    if textureId == nil then textureId = -1 end
    if not componentIndex or not drawableId then return false, 'invalid_catalog_key' end

    local clothingId = MySQL.scalar.await([[SELECT id FROM clothing_catalog
        WHERE gender = ? AND component_type = ? AND component_index = ? AND drawable_id = ? AND texture_id = ? LIMIT 1]],
        { gender, componentType, componentIndex, drawableId, textureId })
    clothingId = tonumber(clothingId)
    if not clothingId then return false, 'catalog_entry_not_found' end

    local clean, seen = {}, {}
    for _, value in ipairs(type(organizations) == 'table' and organizations or {}) do
        local organizationId = tostring(value or ''):lower():gsub('[^%w_%-]', '')
        if organizationId ~= '' and not seen[organizationId] then
            seen[organizationId] = true
            clean[#clean + 1] = organizationId
        end
    end
    local queries = {{ query = 'DELETE FROM clothing_catalog_organizations WHERE clothing_id = ?', values = { clothingId } }}
    for _, organizationId in ipairs(clean) do
        queries[#queries + 1] = { query = 'INSERT INTO clothing_catalog_organizations (clothing_id, organization_id) VALUES (?, ?)', values = { clothingId, organizationId } }
    end
    if MySQL.transaction.await(queries) ~= true then return false, 'organization_assignment_failed' end
    CMItems.ReloadClothingCatalog()
    return true
end

function CMItems.GetShopClothingCatalog(shopName, gender)
    return CMItems.GetClothingCatalogRows({
        shop = shopName,
        gender = gender,
        includeDisabled = false,
    })
end

exports('ReloadClothingCatalog', exportSafe(function()
    return CMItems.ReloadClothingCatalog()
end))

exports('SetClothingCatalog', exportSafe(function(catalog)
    CMItems.SetClothingCatalog(catalog)
    syncCatalog()
    return true
end))

exports('GetClothingCatalog', exportSafe(function()
    return CMItems.Clothing.Catalog or { male = {}, female = {} }
end))

-- Used by cm-inventory to refresh an owned item from its catalog row every time
-- it is read out of the database. See CMItems.ApplyLiveClothingMetadata.
exports('ApplyLiveClothingMetadata', exportSafe(function(metadata)
    return CMItems.ApplyLiveClothingMetadata(metadata)
end))

exports('ResolveOwnedClothingRow', exportSafe(function(metadata)
    return CMItems.ResolveOwnedClothingRow(metadata)
end))

exports('ReplaceClothingCatalogGarment', exportSafe(function(assetId, spec)
    return CMItems.ReplaceClothingCatalogGarment(assetId, spec)
end))

exports('GetClothingCatalogByAssetId', exportSafe(function(assetId)
    if not assetId or assetId == '' then return nil end
    return (CMItems.Clothing.ByAssetId or {})[assetId]
end))

exports('GetClothingCatalogEntry', exportSafe(function(gender, componentType, componentIndex, drawableId, textureId)
    return CMItems.GetClothingCatalogEntry(gender, componentType, componentIndex, drawableId, textureId)
end))

exports('GetClothingCatalogRows', exportSafe(function(filters)
    return CMItems.GetClothingCatalogRows(filters)
end))

exports('GetShopClothingCatalog', exportSafe(function(shopName, gender)
    return CMItems.GetShopClothingCatalog(shopName, gender)
end))

exports('SaveClothingCatalogEntry', exportSafe(function(entry)
    return CMItems.SaveClothingCatalogEntry(entry)
end))

exports('SetClothingCatalogOrganizations', exportSafe(function(identity, organizations)
    return CMItems.SetClothingCatalogOrganizations(identity, organizations)
end))

exports('DeleteClothingCatalogEntry', exportSafe(function(gender, componentType, componentIndex, drawableId, textureId)
    return CMItems.DeleteClothingCatalogEntry(gender, componentType, componentIndex, drawableId, textureId)
end))

exports('IsClothingTempDisabled', exportSafe(function(gender, componentIndex, drawableId, textureId)
    return CMItems.IsClothingTempDisabled(gender, componentIndex, drawableId, textureId)
end))

exports('GetClothingImageHistory', exportSafe(function(clothingId, limit)
    return CMItems.GetClothingImageHistory(clothingId, limit)
end))

exports('RevertClothingImage', exportSafe(function(clothingId, actorLabel)
    return CMItems.RevertClothingImage(clothingId, actorLabel)
end))

--========================================================
-- Admin preview helpers
--========================================================
local function hasItemsAdminPermission(src)
    src = tonumber(src) or 0
    if src == 0 then return true end
    return IsPlayerAceAllowed(src, 'cm.items.admin')
        or IsPlayerAceAllowed(src, 'command.cmitempreview')
        or IsPlayerAceAllowed(src, 'command.cmitemsui')
        or IsPlayerAceAllowed(src, 'command.giveitem')
end

--========================================================
-- Admin preview: give selected item to inventory for testing
-- All users can use this while admin system is not implemented yet.
--========================================================
local function tryInventoryExport(resourceName, exportName, src, itemName, amount, metadata)
    if GetResourceState(resourceName) ~= 'started' then return false, 'resource_not_started' end

    -- IMPORTANT -- FXServer Lua export gotcha:
    -- exports[resourceName][exportName](...) is a DOT call. The function value
    -- returned by indexing exports[resourceName] still expects to be invoked
    -- the way FXServer's own docs always show it -- with COLON syntax
    -- (exports.resource:func(...)), which Lua sugars into func(selfTable, ...).
    -- Calling it with dot instead never supplies that leading self, so the
    -- FIRST real argument we pass (src) silently takes its place and gets
    -- dropped, shifting itemName/amount/metadata/reason all one slot to the
    -- left before they ever reach cm-inventory's normalizeExportArgs. This is
    -- exactly what was producing blank clothing metadata: confirmed via raw
    -- argc logging on the cm-inventory side (argc=4 instead of 5, with
    -- itemName in position 1 instead of src).
    -- Fix: pass the exports interface table itself as the explicit first
    -- argument, replicating what colon-call syntax does automatically, so
    -- normalizeExportArgs's own "strip a leading self table" branch handles
    -- it correctly and every real argument lands in its right slot.
    local iface = exports[resourceName]
    local fn = iface and iface[exportName]
    if type(fn) ~= 'function' then return false, 'export_not_found' end

    local meta = metadata or {}
    local ok, result, extra = pcall(function()
        return fn(iface, src, itemName, amount, meta, 'cm-items_preview_give')
    end)
    if ok and result ~= false and result ~= nil then
        if itemName == 'clothing_bags' or (CMItems.Config and CMItems.Config.Debug) then
            print(('[CM-ITEMS] inventory export success item=%s resource=%s export=%s bagLevel=%s image=%s'):format(
                tostring(itemName), tostring(resourceName), tostring(exportName), tostring((metadata or {}).bagLevel), tostring((metadata or {}).image or (metadata or {}).icon)
            ))
        end
        return true
    end

    -- Was previously logged only for clothing_bags; every clothing give/purchase
    -- that fails needs this to see the real pcall error instead of only the
    -- generic "no compatible export" fallback further down.
    if itemName == 'clothing_bags' or tostring(itemName or ''):find('^clothing_') or (CMItems.Config and CMItems.Config.Debug) then
        print(('[CM-ITEMS] inventory export failed item=%s resource=%s export=%s ok=%s err=%s extra=%s'):format(
            tostring(itemName), tostring(resourceName), tostring(exportName), tostring(ok), tostring(result), tostring(extra)
        ))
    end

    return false, result or 'export_failed'
end

local function addPreviewItemToInventory(src, itemName, amount, metadata)
    amount = tonumber(amount) or 1
    if amount < 1 then amount = 1 end
    if amount > 50 then amount = 50 end

    local item = CMItems.GetPhysicalItem(itemName)
    if not item then return false, 'unknown_item' end
    if item.inventory == false or item.virtual == true then return false, 'not_inventory_item' end

    local valid, err = CMItems.ValidateMetadata(itemName, metadata or {})
    if not valid then return false, err or 'invalid_metadata' end

    local attempts = {
        { 'cm-inventory', 'AddItem' },
        { 'cm-inventory', 'addItem' },
        { 'cm-inventory', 'AddPlayerItem' },
        { 'cm_inventory', 'AddItem' },
        { 'ox_inventory', 'AddItem' },
    }

    for _, attempt in ipairs(attempts) do
        local ok = tryInventoryExport(attempt[1], attempt[2], src, itemName, amount, metadata or {})
        if ok then return true end
    end

    return false, 'No compatible inventory export found. Add AddItem(source, item, amount, metadata) export in cm-inventory.'
end


local function getCategoryFromPreviewRow(row)
    local category = row.categoryType or row.clothingCategory or row.category
    if CMItems.GetClothingCategoryDefinition(category) then return category end

    local ctype = tostring(row.componentType or 'component'):lower()
    local idx = tonumber(row.componentIndex)
    if ctype == 'prop' then
        local propMap = { [0] = 'hat', [1] = 'glasses', [2] = 'earrings', [6] = 'watches', [7] = 'bracelet' }
        return propMap[idx]
    end

    local compMap = { [1] = 'mask', [3] = 'arms', [4] = 'pants', [5] = 'bags', [6] = 'shoes', [7] = 'chains', [8] = 'tshirt', [10] = 'decals', [11] = 'torso' }
    return compMap[idx]
end

local function sameClothingIdentity(itemName, existingMetadata, requestedMetadata)
    if tostring(itemName or ''):find('^clothing_') == nil then return false end
    existingMetadata = type(existingMetadata) == 'table' and existingMetadata or {}
    requestedMetadata = type(requestedMetadata) == 'table' and requestedMetadata or {}

    local function normalizedText(metadata, ...)
        for i = 1, select('#', ...) do
            local value = metadata[select(i, ...)]
            if value ~= nil and value ~= '' then return tostring(value):lower() end
        end
        return nil
    end

    local function normalizedNumber(metadata, ...)
        for i = 1, select('#', ...) do
            local value = tonumber(metadata[select(i, ...)])
            if value ~= nil then return value end
        end
        return nil
    end

    local existingCategory = normalizedText(existingMetadata, 'categoryType', 'category_type', 'clothingCategory', 'category')
    local requestedCategory = normalizedText(requestedMetadata, 'categoryType', 'category_type', 'clothingCategory', 'category')
    local existingType = normalizedText(existingMetadata, 'componentType', 'component_type')
    local requestedType = normalizedText(requestedMetadata, 'componentType', 'component_type')
    local existingIndex = normalizedNumber(existingMetadata, 'componentIndex', 'component_index', 'componentId', 'component_id', 'propIndex', 'prop_index')
    local requestedIndex = normalizedNumber(requestedMetadata, 'componentIndex', 'component_index', 'componentId', 'component_id', 'propIndex', 'prop_index')
    local existingDrawable = normalizedNumber(existingMetadata, 'drawableId', 'drawable_id', 'drawable')
    local requestedDrawable = normalizedNumber(requestedMetadata, 'drawableId', 'drawable_id', 'drawable')
    local existingTexture = normalizedNumber(existingMetadata, 'textureId', 'texture_id', 'texture') or 0
    local requestedTexture = normalizedNumber(requestedMetadata, 'textureId', 'texture_id', 'texture') or 0
    local existingGender = normalizedText(existingMetadata, 'gender', 'sex', 'pedGender') or 'male'
    local requestedGender = normalizedText(requestedMetadata, 'gender', 'sex', 'pedGender') or 'male'
    local genderMatches = (existingGender == requestedGender)
        or (existingGender == 'both' or requestedGender == 'both')

    return existingCategory == requestedCategory
        and existingType == requestedType
        and existingIndex == requestedIndex
        and existingDrawable == requestedDrawable
        and existingTexture == requestedTexture
        and genderMatches
end

local function alreadyHasPreviewClothing(src, itemName, metadata)
    if GetResourceState('cm-inventory') ~= 'started' then return false end

    local ok, payload = pcall(function()
        return exports['cm-inventory']:GetInventory(src)
    end)
    if not ok or type(payload) ~= 'table' or type(payload.items) ~= 'table' then return false end

    local slots = type(payload.slots) == 'table' and payload.slots or {}
    local pocketPrefix = type(slots.pockets) == 'table' and tostring(slots.pockets.prefix or 'pocket-') or 'pocket-'
    local backpackPrefix = type(slots.backpack) == 'table' and tostring(slots.backpack.prefix or 'backpack-') or 'backpack-'

    itemName = tostring(itemName or ''):lower()
    for _, item in ipairs(payload.items) do
        local itemSlot = type(item) == 'table' and tostring(item.slot or '') or ''
        local isStoredItem = itemSlot:find(pocketPrefix, 1, true) == 1
            or itemSlot:find(backpackPrefix, 1, true) == 1
        if isStoredItem
            and tostring(item.item_name or item.name or ''):lower() == itemName
            and sameClothingIdentity(itemName, item.metadata, metadata) then
            return true
        end
    end

    return false
end

RegisterNetEvent('cm-items:server:previewGiveItem', function(requestId, row)
    local src = source
    row = type(row) == 'table' and row or {}
    local itemName = row.name
    local metadata = row.metadata

    if row.kind == 'catalog' then
        local clothingCategory = getCategoryFromPreviewRow(row)
        itemName = CMItems.GetClothingItemName(clothingCategory)
        local isBagSkin = (clothingCategory == 'bags') and (row.bagSkin == true or row.bag_skin == true)
        if isBagSkin then
            itemName = 'clothing_bags_skin'
        end

        local level = tonumber(row.bagLevel or row.bag_level or row.level)
        if clothingCategory == 'bags' and not isBagSkin and level ~= nil then
            level = math.max(1, math.min(4, math.floor(level)))
        elseif isBagSkin then
            level = nil
        end

        local baseGender = row.sourceGender or (row.gender == 'both' and 'male' or row.gender)
        metadata = CMItems.BuildClothingMetadata(clothingCategory, {
            gender = baseGender,
            componentType = row.componentType,
            componentIndex = row.componentIndex,
            drawableId = row.drawableId,
            textureId = tonumber(row.textureId) and tonumber(row.textureId) >= 0 and tonumber(row.textureId) or 0,
            label = row.label,
            description = (clothingCategory == 'bags' and not isBagSkin and level ~= nil) and (('Level %s bag. Unlocks backpack slots.'):format(level)) or (isBagSkin and 'Cosmetic bag-slot clothing item.' or row.description),
            image = row.image,
            icon = row.image,
            price = row.price,
            shop = row.shop,
            arms = row.arms,
            armsTexture = row.armsTexture,
            undershirt = row.undershirt,
            undershirtTexture = row.undershirtTexture,
            sleeveStyle = row.sleeveStyle,
            bagLevel = level or row.bagLevel,
            bagSkin = isBagSkin,
            pairedDrawableId = row.pairedDrawableId,
            pairedTextureId = row.pairedTextureId,
            sellCategory = row.sellCategory,
            armorValue = row.armorValue,
        }, { createdBy = ('preview:%s'):format(src) })

        if type(metadata) == 'table' and clothingCategory == 'bags' then
            if not metadata.bagSkin and not metadata.bagLevel and level then metadata.bagLevel = level end
            if metadata.bagSkin then metadata.bagLevel = nil end
            if metadata.bagLevel then metadata.description = ('Level %s bag. Unlocks backpack slots.'):format(metadata.bagLevel) end
            if row.image and row.image ~= '' then
                local img = tostring(row.image)
                if not img:find('^nui://') and not img:find('^https?://') then
                    if img:find('^clothing/') then img = ('nui://cm-items/ui/images/%s'):format(img)
                    else img = ('nui://cm-items/ui/images/clothing/%s'):format(img) end
                end
                metadata.image = img
                metadata.icon = img
            end
            print(('[CM-ITEMS] previewGive bag item=%s drawable=%s texture=%s image=%s bagLevel=%s bagSkin=%s'):format(
                tostring(itemName), tostring(metadata.drawableId), tostring(metadata.textureId), tostring(metadata.image), tostring(metadata.bagLevel), tostring(metadata.bagSkin)))
        end
    end

    -- Guard against giving a generic item card (kind ~= 'catalog', e.g. the
    -- bare "Bag"/clothing_bags entry in the item list) for something that
    -- actually needs per-instance metadata (drawable/texture/gender/etc) to
    -- mean anything. That metadata only ever gets built above for kind ==
    -- 'catalog' rows -- giving the generic card produced a silently blank,
    -- non-functional item (no level, no gender, doesn't unlock backpack
    -- slots for bags) instead of a clear error. Right the specific
    -- clothing/catalog tile (e.g. "Bags 86") for these, not the plain item card.
    if row.kind ~= 'catalog' then
        local requiredOk, requiredFields = CMItems.RequiresMetadata(itemName)
        if requiredOk then
            local missing = nil
            for _, field in ipairs(requiredFields) do
                if type(metadata) ~= 'table' or metadata[field] == nil or metadata[field] == '' then
                    missing = field
                    break
                end
            end
            if missing then
                TriggerClientEvent('cm-items:client:previewGiveResult', src, requestId, false,
                    ('This item needs a specific catalog entry (missing %s) -- use its tile in the catalog tab, not this generic card.'):format(missing), itemName)
                return
            end
        end
    end

    -- VN cloth retakes overwrite a stable PNG path. If this exact wearable is
    -- already in the admin's inventory, reuse it instead of increasing its
    -- quantity or creating a second slot; the existing item now reads the
    -- replaced image from that same path.
    local ok, err
    if alreadyHasPreviewClothing(src, itemName, metadata) then
        ok = true
        err = 'existing_item_reused'
    else
        ok, err = addPreviewItemToInventory(src, itemName, 1, metadata or {})
    end
    TriggerClientEvent('cm-items:client:previewGiveResult', src, requestId, ok == true, err, itemName)
end)

RegisterNetEvent('cm-items:server:previewDeleteItem', function(requestId, row)
    local src = source
    row = type(row) == 'table' and row or {}

    if not hasItemsAdminPermission(src) then
        TriggerClientEvent('cm-items:client:previewDeleteResult', src, requestId, false, 'No permission. Add ACE: add_ace group.admin cm.items.admin allow')
        return
    end

    local ok, err = false, 'unsupported_row'
    local deletedName = row.name

    if row.kind == 'catalog' then
        ok, err = CMItems.DeleteClothingCatalogEntry(
            row.gender,
            row.componentType or row.component_type or 'component',
            row.componentIndex or row.component_index,
            row.drawableId or row.drawable_id,
            row.textureId or row.texture_id
        )
        deletedName = row.label or row.name or 'clothing catalog item'
        if ok then syncCatalog() end
    elseif row.kind == 'item' then
        local name = CMItems.NormalizeName and CMItems.NormalizeName(row.name) or tostring(row.name or '')
        if name == '' then
            ok, err = false, 'invalid_name'
        elseif CMItems.CatalogItems and CMItems.CatalogItems[name] and CMItems.DeleteCatalogItem then
            ok, err = CMItems.DeleteCatalogItem(name)
            deletedName = name
        else
            ok, err = false, 'static_item_not_deleted_remove_from_shared_items_lua'
        end
    end

    TriggerClientEvent('cm-items:client:previewDeleteResult', src, requestId, ok == true, ok and 'deleted' or err, deletedName)
end)

--========================================================
-- Admin preview: set / clear the DROP PROP for an item.
-- Prop overrides live in cm-items (item_props.lua) and apply to any item.
--========================================================
RegisterNetEvent('cm-items:server:previewSetProp', function(requestId, data)
    local src = source
    data = type(data) == 'table' and data or {}

    if not hasItemsAdminPermission(src) then
        TriggerClientEvent('cm-items:client:previewPropResult', src, requestId, false, 'No permission. Add ACE: add_ace group.admin cm.items.admin allow')
        return
    end

    local name = CMItems.NormalizeName and CMItems.NormalizeName(data.name) or tostring(data.name or '')
    if name == '' then
        TriggerClientEvent('cm-items:client:previewPropResult', src, requestId, false, 'Invalid item name.')
        return
    end

    local ok, err = CMItems.SaveItemProp({
        name = name,
        model = data.model,
        zOffset = data.zOffset,
        heading = data.heading,
        updatedBy = ('preview:%s'):format(src),
    })

    TriggerClientEvent('cm-items:client:previewPropResult', src, requestId, ok == true, ok and 'Prop saved' or ('Could not save prop: ' .. tostring(err)), name)
end)

RegisterNetEvent('cm-items:server:previewClearProp', function(requestId, data)
    local src = source
    data = type(data) == 'table' and data or {}

    if not hasItemsAdminPermission(src) then
        TriggerClientEvent('cm-items:client:previewPropResult', src, requestId, false, 'No permission.')
        return
    end

    local name = CMItems.NormalizeName and CMItems.NormalizeName(data.name) or tostring(data.name or '')
    if name == '' then
        TriggerClientEvent('cm-items:client:previewPropResult', src, requestId, false, 'Invalid item name.')
        return
    end

    local ok, err = CMItems.DeleteItemProp(name)
    TriggerClientEvent('cm-items:client:previewPropResult', src, requestId, ok == true, ok and 'Prop reset to default' or ('Could not reset prop: ' .. tostring(err)), name)
end)

--========================================================
-- Admin preview: set the IMAGE for an item (used everywhere).
--========================================================
RegisterNetEvent('cm-items:server:previewSetImage', function(requestId, data)
    local src = source
    data = type(data) == 'table' and data or {}

    if not hasItemsAdminPermission(src) then
        TriggerClientEvent('cm-items:client:previewImageResult', src, requestId, false, 'No permission. Add ACE: add_ace group.admin cm.items.admin allow')
        return
    end

    local name = CMItems.NormalizeName and CMItems.NormalizeName(data.name) or tostring(data.name or '')
    if name == '' or type(data.imageData) ~= 'string' or data.imageData == '' then
        TriggerClientEvent('cm-items:client:previewImageResult', src, requestId, false, 'Invalid item or image.')
        return
    end

    local ok, res = CMItems.SetItemImage(name, data.imageData, ('preview:%s'):format(src))
    TriggerClientEvent('cm-items:client:previewImageResult', src, requestId, ok == true,
        ok and 'Image updated' or ('Could not save image: ' .. tostring(res)), name)
end)
