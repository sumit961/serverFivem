-- cm-items/server/items_catalog.lua
-- Generic item catalog: the single source of truth for runtime-created items.
-- Other resources (cm-gunstore, events, future stores) call SaveCatalogItem to
-- create an item definition (+ its PNG), then reference it everywhere by name.
-- Loaded catalog rows are merged into CMItems.Items so GetItem() / cm-inventory
-- resolve them like any built-in item.

local CATALOG_IMAGE_DIR = 'ui/images/catalog'

CMItems = CMItems or {}
CMItems.CatalogItems = CMItems.CatalogItems or {}

local function dbg(msg)
    if CMItems.Config and CMItems.Config.Debug then
        print(('[CM-ITEMS] %s'):format(msg))
    end
end

local function hasDB()
    return GetResourceState('oxmysql') == 'started'
end

local function ensureCatalogTable()
    if not hasDB() then return false end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_items_catalog (
            name VARCHAR(80) NOT NULL PRIMARY KEY,
            label VARCHAR(120) NOT NULL,
            category VARCHAR(60) NOT NULL DEFAULT 'misc',
            item_type VARCHAR(40) NOT NULL DEFAULT 'normal',
            image VARCHAR(255) NULL,
            weight INT NOT NULL DEFAULT 0,
            stack TINYINT(1) NOT NULL DEFAULT 1,
            usable TINYINT(1) NOT NULL DEFAULT 1,
            equipment_slot VARCHAR(40) NULL,
            armor_value INT NULL,
            description TEXT NULL,
            metadata LONGTEXT NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            created_by VARCHAR(100) NULL,
            updated_by VARCHAR(100) NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_category (category),
            INDEX idx_enabled (enabled)
        )
    ]])
    return true
end

local function normalizeName(name)
    name = tostring(name or ''):lower():gsub('[^%w_]', '_'):gsub('_+', '_')
    return name
end

local function decodeMeta(value)
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then return decoded end
    return {}
end

-- Convert a catalog DB row into the in-memory item def shape cm-inventory expects.
local function rowToDef(row)
    local meta = decodeMeta(row.metadata)
    return {
        name = row.name,
        label = row.label or row.name,
        category = row.category or 'misc',
        itemType = row.item_type or 'normal',
        type = row.item_type or 'normal',
        image = row.image or 'placeholder.png',
        icon = row.image or 'placeholder.png',
        weight = tonumber(row.weight) or 0,
        stack = tonumber(row.stack) == 1,
        unique = tonumber(row.stack) ~= 1,
        usable = tonumber(row.usable) == 1,
        equipmentSlot = row.equipment_slot,
        armorValue = tonumber(row.armor_value),
        description = row.description or '',
        inventory = true,
        virtual = false,
        catalogMeta = meta, -- type-specific extras (component/drawable/texture, weaponHash, ...)
    }
end

local function copyForClient(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copyForClient(v) end
    return out
end

local function syncItemsCatalog(target)
    local payload = {}
    for name, def in pairs(CMItems.CatalogItems or {}) do
        payload[name] = copyForClient(def)
    end

    if target and tonumber(target) and tonumber(target) > 0 then
        TriggerClientEvent('cm-items:client:setItemsCatalog', tonumber(target), payload)
    else
        TriggerClientEvent('cm-items:client:setItemsCatalog', -1, payload)
    end
end

-- ============================================================
-- Image save (base64 dataURL -> cm-items/ui/images/catalog/<name>.png)
-- Returns the nui path so it can be stored in the catalog row.
-- ============================================================
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64lookup = {}
for i = 1, #b64chars do b64lookup[b64chars:sub(i, i)] = i - 1 end

local function base64Decode(data)
    data = tostring(data or ''):gsub('%s', ''):gsub('^data:image/%w+;base64,', '')
    local out, buffer, bits = {}, 0, 0
    for i = 1, #data do
        local c = data:sub(i, i)
        if c ~= '=' then
            local v = b64lookup[c]
            if v ~= nil then
                buffer = buffer * 64 + v
                bits = bits + 6
                if bits >= 8 then
                    bits = bits - 8
                    out[#out + 1] = string.char(math.floor(buffer / (2 ^ bits)) % 256)
                    buffer = buffer % (2 ^ bits)
                end
            end
        end
    end
    return table.concat(out)
end

-- Save a base64 PNG into cm-items. dataUri may be a data URL or raw base64.
function CMItems.SaveCatalogImage(name, dataUri)
    name = normalizeName(name)
    if name == '' then return nil, 'bad_name' end
    local bytes = base64Decode(dataUri)
    if not bytes or #bytes < 64 then return nil, 'bad_image_data' end
    local fileName = ('%s.png'):format(name)
    local relPath = ('%s/%s'):format(CATALOG_IMAGE_DIR, fileName)
    local ok = SaveResourceFile(GetCurrentResourceName(), relPath, bytes, #bytes)
    if not ok then return nil, 'save_failed' end
    return ('nui://%s/%s'):format(GetCurrentResourceName(), relPath)
end

-- ============================================================
-- Save / Get / Delete catalog items
-- ============================================================
-- def fields: name, label, category, itemType, image OR imageData (base64),
--   weight, stack, usable, equipmentSlot, armorValue, description, metadata(table),
--   enabled, createdBy
function CMItems.SaveCatalogItem(def)
    if type(def) ~= 'table' then return false, 'invalid_def' end
    if not ensureCatalogTable() then return false, 'catalog_table_unavailable' end

    local name = normalizeName(def.name or def.itemName)
    if name == '' then return false, 'invalid_name' end
    -- Protect built-in static items from being shadowed by accident.
    if CMItems.Items and CMItems.Items[name] and not def.allowOverrideStatic then
        -- allow if it's already a catalog item (update), else block
        if not CMItems.CatalogItems[name] then
            return false, 'name_used_by_static_item'
        end
    end

    -- Resolve image: explicit path wins; else save provided base64.
    local image = def.image
    if (not image or image == '') and def.imageData and def.imageData ~= '' then
        local saved, err = CMItems.SaveCatalogImage(name, def.imageData)
        if not saved then return false, ('image_'..tostring(err)) end
        image = saved
    end

    local meta = type(def.metadata) == 'table' and def.metadata or {}
    local metaJson = json.encode(meta)

    local row = {
        name = name,
        label = tostring(def.label or name):sub(1, 120),
        category = tostring(def.category or 'misc'):lower():sub(1, 60),
        item_type = tostring(def.itemType or def.item_type or 'normal'):lower():sub(1, 40),
        image = image,
        weight = math.max(0, math.floor(tonumber(def.weight) or 0)),
        stack = (def.stack == false) and 0 or 1,
        usable = (def.usable == false) and 0 or 1,
        equipment_slot = def.equipmentSlot or def.equipment_slot,
        armor_value = tonumber(def.armorValue or def.armor_value),
        description = tostring(def.description or ''):sub(1, 1000),
        metadata = metaJson,
        enabled = (def.enabled == false) and 0 or 1,
        created_by = tostring(def.createdBy or def.created_by or 'system'):sub(1, 100),
    }

    MySQL.query.await([[
        INSERT INTO cm_items_catalog
            (name, label, category, item_type, image, weight, stack, usable, equipment_slot, armor_value, description, metadata, enabled, created_by, updated_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label), category = VALUES(category), item_type = VALUES(item_type),
            image = VALUES(image), weight = VALUES(weight), stack = VALUES(stack), usable = VALUES(usable),
            equipment_slot = VALUES(equipment_slot), armor_value = VALUES(armor_value),
            description = VALUES(description), metadata = VALUES(metadata), enabled = VALUES(enabled),
            updated_by = VALUES(created_by)
    ]], {
        row.name, row.label, row.category, row.item_type, row.image, row.weight, row.stack, row.usable,
        row.equipment_slot, row.armor_value, row.description, row.metadata, row.enabled, row.created_by, row.created_by,
    })

    -- Merge into in-memory registry immediately so GetItem/inventory see it now.
    row.metadata = meta
    local def2 = rowToDef(row)
    CMItems.CatalogItems[name] = def2
    CMItems.Items = CMItems.Items or {}
    CMItems.Items[name] = def2

    dbg(('SaveCatalogItem name=%s category=%s image=%s'):format(name, row.category, tostring(image)))
    syncItemsCatalog()
    return true, { name = name, image = image }
end

function CMItems.GetCatalogItem(name)
    name = normalizeName(name)
    return CMItems.CatalogItems[name]
end

function CMItems.GetCatalogByCategory(category)
    category = tostring(category or ''):lower()
    local out = {}
    for _, def in pairs(CMItems.CatalogItems) do
        if category == '' or def.category == category then
            out[#out + 1] = def
        end
    end
    return out
end

function CMItems.DeleteCatalogItem(name)
    name = normalizeName(name)
    if name == '' then return false, 'invalid_name' end
    if not ensureCatalogTable() then return false, 'catalog_table_unavailable' end

    local rows = MySQL.query.await('SELECT name FROM cm_items_catalog WHERE name = ? LIMIT 1', { name }) or {}
    if #rows == 0 then
        return false, 'catalog_item_not_found_or_static_item'
    end

    MySQL.query.await('DELETE FROM cm_items_catalog WHERE name = ?', { name })
    CMItems.CatalogItems[name] = nil

    -- Only remove SQL-backed runtime items here. Static shared/items.lua definitions
    -- must be removed from code and reloaded, not deleted from the UI/export.
    if CMItems.Items and (not CMItems.Items[name] or CMItems.Items[name].catalogMeta ~= nil) then
        CMItems.Items[name] = nil
    end

    syncItemsCatalog()
    return true
end

-- ============================================================
-- Loader: pull all catalog rows into memory on start.
-- ============================================================
function CMItems.ReloadItemsCatalog()
    if not ensureCatalogTable() then return end
    local rows = MySQL.query.await('SELECT * FROM cm_items_catalog WHERE enabled = 1') or {}
    CMItems.Items = CMItems.Items or {}
    for name in pairs(CMItems.CatalogItems or {}) do
        if CMItems.Items[name] and CMItems.Items[name].catalogMeta ~= nil then
            CMItems.Items[name] = nil
        end
    end
    CMItems.CatalogItems = {}
    for _, row in ipairs(rows) do
        local def = rowToDef(row)
        CMItems.CatalogItems[def.name] = def
        CMItems.Items[def.name] = def
    end
    syncItemsCatalog()
    dbg(('ReloadItemsCatalog loaded %s catalog items'):format(#rows))
end

-- ============================================================
-- Universal give: any event/store/admin uses this one call.
-- ============================================================
function CMItems.GiveCatalogItem(src, name, amount, metaOverride)
    src = tonumber(src)
    name = normalizeName(name)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if not src or name == '' then return false, 'invalid_args' end

    local def = CMItems.CatalogItems[name] or (CMItems.Items and CMItems.Items[name])
    if not def then return false, 'unknown_item' end

    -- Build metadata from the catalog definition so the item carries its identity
    -- (image, label, and type-specific data like vest component/drawable).
    local meta = {}
    local base = def.catalogMeta or {}
    for k, v in pairs(base) do meta[k] = v end
    meta.label = def.label
    meta.image = def.image
    meta.icon = def.image
    meta.description = def.description
    meta.itemType = def.itemType
    meta.categoryType = def.category
    meta.category = def.category
    if def.armorValue then meta.armorValue = def.armorValue end
    if def.equipmentSlot then meta.equipmentSlot = def.equipmentSlot end
    if type(metaOverride) == 'table' then
        for k, v in pairs(metaOverride) do meta[k] = v end
    end

    if GetResourceState('cm-inventory') ~= 'started' then return false, 'inventory_not_started' end

    local inv = exports['cm-inventory']
    local attempts = {
        function() return inv['AddItem'](src, name, amount, meta, nil, 'cm_items_give') end,
        function() return inv['AddItem'](src, name, amount, meta, 'cm_items_give') end,
        function() return inv['addItem'] and inv['addItem'](src, name, amount, meta, nil, 'cm_items_give') end,
    }
    for _, fn in ipairs(attempts) do
        local ok, result = pcall(fn)
        if ok and (result == true or (type(result) == 'table' and (result.success or result.ok)) or (type(result) == 'number' and result > 0)) then
            return true
        end
    end
    return false, 'add_failed'
end

RegisterNetEvent('cm-items:server:requestItemsCatalogSync', function()
    syncItemsCatalog(source)
end)

-- ============================================================
-- Exports
-- ============================================================
exports('SaveCatalogItem', function(def) return CMItems.SaveCatalogItem(def) end)
exports('GetCatalogItem', function(name) return CMItems.GetCatalogItem(name) end)
exports('GetCatalogByCategory', function(cat) return CMItems.GetCatalogByCategory(cat) end)
exports('DeleteCatalogItem', function(name) return CMItems.DeleteCatalogItem(name) end)
exports('SaveCatalogImage', function(name, dataUri) return CMItems.SaveCatalogImage(name, dataUri) end)
exports('ReloadItemsCatalog', function() return CMItems.ReloadItemsCatalog() end)
exports('GiveCatalogItem', function(src, name, amount, metaOverride)
    return CMItems.GiveCatalogItem(src, name, amount, metaOverride)
end)

-- Admin give command: /giveitem <playerId> <itemName> [amount]
RegisterCommand('giveitem', function(src, args)
    if src ~= 0 then
        if not (IsPlayerAceAllowed(src, 'cm.items.admin') or IsPlayerAceAllowed(src, 'command.giveitem') or IsPlayerAceAllowed(src, 'command')) then
            TriggerClientEvent('cm-hud:client:notify', src, 'No permission.', 'error')
            return
        end
    end
    local target = tonumber(args[1])
    local itemName = args[2]
    local amount = tonumber(args[3]) or 1
    if not target or not itemName then
        local msg = 'Usage: /giveitem <playerId> <itemName> [amount]'
        if src == 0 then print(msg) else TriggerClientEvent('cm-hud:client:notify', src, msg, 'info') end
        return
    end
    local ok, err = CMItems.GiveCatalogItem(target, itemName, amount)
    local msg = ok and ('Gave %sx %s to %s'):format(amount, itemName, target) or ('Give failed: %s'):format(tostring(err))
    if src == 0 then print(msg) else TriggerClientEvent('cm-hud:client:notify', src, msg, ok and 'success' or 'error') end
end, false)

CreateThread(function()
    Wait(1200)
    CMItems.ReloadItemsCatalog()
end)
