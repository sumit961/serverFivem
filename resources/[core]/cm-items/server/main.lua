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
            image VARCHAR(255) NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
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
            local compMap = { [1] = 'mask', [3] = 'arms', [4] = 'pants', [5] = 'bags', [6] = 'shoes', [7] = 'chains', [8] = 'tshirt', [10] = 'decals', [11] = 'torso' }
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
        image = row.image,
        enabled = catalogBool(row.enabled, true),
        job = row.job,
        gang = row.gang,
        notes = row.notes,
        createdBy = row.createdBy or row.created_by,
        updatedBy = row.updatedBy or row.updated_by,
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
        image = entry.image,
        enabled = entry.enabled ~= false,
        job = entry.job,
        gang = entry.gang,
        notes = entry.notes,
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
    ClothingCatalogReady = true
    syncCatalog()
    log(('Loaded clothing catalog rows: %s'):format(count))
    return true, count
end

function CMItems.SaveClothingCatalogEntry(entry)
    if not ensureClothingCatalogTable() then return false, 'catalog_table_unavailable' end
    entry = normaliseCatalogRow(entry)
    if not entry then return false, 'invalid_catalog_entry' end

    if CMItems.Config and CMItems.Config.Debug then
        print(('[CM-ITEMS] SaveCatalog category=%s gender=%s drawable=%s texture=%s image=%s bagLevel=%s enabled=%s'):format(
            tostring(entry.category), tostring(entry.gender), tostring(entry.drawableId), tostring(entry.textureId), tostring(entry.image), tostring(entry.bagLevel), tostring(entry.enabled)))
    end

    MySQL.query.await([[
        INSERT INTO clothing_catalog
        (gender, component_type, component_index, drawable_id, texture_id, label, description, price, category, shop,
         sleeve_style, arms, arms_texture, undershirt, undershirt_texture, bag_level, backpack_slots, max_weight, image, enabled, job, gang, notes, created_by, updated_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            image = VALUES(image),
            enabled = VALUES(enabled),
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
        entry.image,
        entry.enabled ~= false and 1 or 0,
        entry.job,
        entry.gang,
        entry.notes,
        entry.createdBy,
        entry.updatedBy or entry.createdBy,
    })

    CMItems.ReloadClothingCatalog()
    return true
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

    MySQL.query.await([[DELETE FROM clothing_catalog WHERE gender = ? AND component_type = ? AND component_index = ? AND drawable_id = ? AND texture_id = ?]], {
        gender, componentType, componentIndex, drawableId, textureId
    })
    CMItems.ReloadClothingCatalog()
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
                image = row.image,
                enabled = row.enabled ~= false,
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

    -- IMPORTANT:
    -- cm-inventory AddItem signature is:
    --   AddItem(source, itemName, amount, metadata, reason, slot)
    -- The older fallback calls below used to pass metadata as the 5th argument
    -- (reason), so the item was created as a plain/default bag even though
    -- cm-items had correctly built bagLevel/image metadata.
    local meta = metadata or {}
    local ok, result, extra = pcall(function()
        -- Metadata belongs in arg #4 only. Arg #5 is slot/reason in many inventories;
        -- passing a table there breaks strict inventory systems like ox_inventory.
        return exports[resourceName][exportName](src, itemName, amount, meta, nil, 'cm-items_preview_give')
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

    return existingCategory == requestedCategory
        and existingType == requestedType
        and existingIndex == requestedIndex
        and existingDrawable == requestedDrawable
        and existingTexture == requestedTexture
        and existingGender == requestedGender
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

        local level = tonumber(row.bagLevel or row.bag_level or row.level)
        if clothingCategory == 'bags' and level ~= nil then
            level = math.max(1, math.min(4, math.floor(level)))
        end

        metadata = CMItems.BuildClothingMetadata(clothingCategory, {
            gender = row.gender,
            componentType = row.componentType,
            componentIndex = row.componentIndex,
            drawableId = row.drawableId,
            textureId = tonumber(row.textureId) and tonumber(row.textureId) >= 0 and tonumber(row.textureId) or 0,
            label = row.label,
            description = (clothingCategory == 'bags' and level ~= nil) and (('Level %s bag. Unlocks backpack slots.'):format(level)) or row.description,
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
        }, { createdBy = ('preview:%s'):format(src) })

        if type(metadata) == 'table' and clothingCategory == 'bags' then
            if not metadata.bagLevel and level then metadata.bagLevel = level end
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
            print(('[CM-ITEMS] previewGive bag item=%s drawable=%s texture=%s image=%s bagLevel=%s'):format(
                tostring(itemName), tostring(metadata.drawableId), tostring(metadata.textureId), tostring(metadata.image), tostring(metadata.bagLevel)))
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
