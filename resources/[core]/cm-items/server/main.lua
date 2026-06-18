local function log(message)
    print(('[CM-ITEMS] %s'):format(message))
end

local function normalizeExportArgs(...)
    local args = { ... }

    -- FiveM Lua exports can be called as either:
    -- exports['cm-items'].IsInventoryItem('water')
    -- exports['cm-items']:IsInventoryItem('water')
    -- In some runtimes, colon-style passes the exports table as arg #1.
    -- This removes that extra table so the real first argument is always the item name.
    if type(args[1]) == 'table' then
        table.remove(args, 1)
    end

    return args
end

local function exportSafe(fn)
    return function(...)
        local args = normalizeExportArgs(...)
        local ok, result, extra = pcall(function()
            return fn(table.unpack(args))
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
    local physicalCount = 0
    local virtualCount = 0

    for _ in pairs(CMItems.Items or {}) do physicalCount = physicalCount + 1 end
    for _ in pairs(CMItems.VirtualItems or {}) do virtualCount = virtualCount + 1 end

    log(('Started v1.1-export-fix | physical items: %s | virtual items: %s'):format(physicalCount, virtualCount))
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
    return true
end

local function normaliseCatalogRow(row)
    if type(row) ~= 'table' then return nil end
    local gender = CMItems.NormalizeClothingGender(row.gender)
    local componentType = tostring(row.component_type or row.componentType or 'component'):lower()
    local componentIndex = tonumber(row.component_index or row.componentIndex)
    local drawableId = tonumber(row.drawable_id or row.drawableId)
    local textureId = tonumber(row.texture_id or row.textureId)
    if not componentIndex or not drawableId then return nil end
    if textureId == nil then textureId = -1 end

    return {
        id = tonumber(row.id),
        gender = gender,
        componentType = componentType,
        componentIndex = componentIndex,
        drawableId = drawableId,
        textureId = textureId,
        label = row.label,
        description = row.description,
        price = tonumber(row.price) or 0,
        category = row.category,
        shop = row.shop,
        sleeveStyle = row.sleeve_style or row.sleeveStyle,
        arms = row.arms ~= nil and tonumber(row.arms) or nil,
        armsTexture = tonumber(row.arms_texture or row.armsTexture) or 0,
        undershirt = row.undershirt ~= nil and tonumber(row.undershirt) or nil,
        undershirtTexture = tonumber(row.undershirt_texture or row.undershirtTexture) or 0,
        image = row.image,
        enabled = catalogBool(row.enabled, true),
        job = row.job,
        gang = row.gang,
        notes = row.notes,
        createdBy = row.createdBy or row.created_by,
        updatedBy = row.updatedBy or row.updated_by,
    }
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
    local flatRows = {}
    local count = 0

    for _, row in ipairs(rows) do
        local entry = normaliseCatalogRow(row)
        if entry then
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

    MySQL.query.await([[
        INSERT INTO clothing_catalog
        (gender, component_type, component_index, drawable_id, texture_id, label, description, price, category, shop,
         sleeve_style, arms, arms_texture, undershirt, undershirt_texture, image, enabled, job, gang, notes, created_by, updated_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        if filterShop and tostring(row.shop or ''):lower() ~= filterShop then ok = false end
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
                shop = row.shop,
                sleeveStyle = row.sleeveStyle,
                arms = row.arms,
                armsTexture = tonumber(row.armsTexture) or 0,
                undershirt = row.undershirt,
                undershirtTexture = tonumber(row.undershirtTexture) or 0,
                image = row.image,
                enabled = row.enabled ~= false,
                job = row.job,
                gang = row.gang,
                notes = row.notes,
                createdBy = row.createdBy,
                updatedBy = row.updatedBy,
            }
        end
    end

    return out
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

exports('DeleteClothingCatalogEntry', exportSafe(function(gender, componentType, componentIndex, drawableId, textureId)
    return CMItems.DeleteClothingCatalogEntry(gender, componentType, componentIndex, drawableId, textureId)
end))
