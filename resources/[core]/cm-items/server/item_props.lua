-- cm-items/server/item_props.lua
-- Per-item DROP PROP overrides: the world object (and its z-offset / heading)
-- that spawns when an item is dropped from the inventory.
--
-- Single source of truth. cm-inventory asks cm-items for an item's drop prop via
-- GetItemDropProp(name), so props are set once here (admin item preview UI) and
-- apply everywhere. Works for any item -- static or catalog -- because overrides
-- live in their own table keyed by item name.
--
-- Resolution order for GetItemDropProp(name):
--   1. per-item override row in cm_item_props
--   2. the item's own worldModel / catalog metadata.worldModel
--   3. category default from Config.WorldModels (clothing = ONE shared prop)
--   4. Config.WorldModels.default
--
-- NOTE: GTA has no reliable runtime object scale native, so there is no scale
-- field. "Size/placement" is controlled with z_offset + heading, which do work.

CMItems = CMItems or {}
CMItems.ItemProps = CMItems.ItemProps or {}

local function dbg(msg)
    if CMItems.Config and CMItems.Config.Debug then
        print(('[CM-ITEMS] %s'):format(msg))
    end
end

local function hasDB()
    return GetResourceState('oxmysql') == 'started'
end

local function normalizeName(name)
    return tostring(name or ''):lower():gsub('[^%w_]', '_'):gsub('_+', '_')
end

local function clampOffset(value)
    value = tonumber(value) or 0.0
    if value < -5.0 then return -5.0 end
    if value > 5.0 then return 5.0 end
    return math.floor(value * 100) / 100
end

local function normalizeHeading(value)
    value = tonumber(value) or 0.0
    value = value % 360.0
    if value < 0 then value = value + 360.0 end
    return math.floor(value * 100) / 100
end

local function ensurePropTable()
    if not hasDB() then return false end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_item_props (
            name VARCHAR(80) NOT NULL PRIMARY KEY,
            model VARCHAR(80) NOT NULL,
            z_offset FLOAT NOT NULL DEFAULT 0,
            heading FLOAT NOT NULL DEFAULT 0,
            updated_by VARCHAR(100) NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]])
    return true
end

local function syncItemProps(target)
    -- Send the raw overrides to clients so the preview UI can show current values.
    local payload = {}
    for name, ov in pairs(CMItems.ItemProps) do
        payload[name] = { model = ov.model, zOffset = ov.zOffset, heading = ov.heading }
    end
    if target and tonumber(target) and tonumber(target) > 0 then
        TriggerClientEvent('cm-items:client:setItemProps', tonumber(target), payload)
    else
        TriggerClientEvent('cm-items:client:setItemProps', -1, payload)
    end
end

-- ============================================================
-- Resolution
-- ============================================================
local function categoryDefaultModel(category)
    local models = (CMItems.Config and CMItems.Config.WorldModels) or {}
    category = tostring(category or ''):lower()
    return models[category] or models.default or 'prop_cs_cardbox_01'
end

-- Returns { model, zOffset, heading } for a dropped item. Never nil.
function CMItems.GetItemDropProp(name)
    name = normalizeName(name)

    local override = CMItems.ItemProps[name]
    if override and override.model and override.model ~= '' then
        return {
            model = override.model,
            zOffset = tonumber(override.zOffset) or 0.0,
            heading = tonumber(override.heading) or 0.0,
        }
    end

    -- Item-level model (from catalog metadata.worldModel or a static def).
    local item = CMItems.Items and CMItems.Items[name]
    local category = 'misc'
    if item then
        category = tostring(item.category or item.type or 'misc'):lower()
        local itemModel = item.worldModel
        if (not itemModel or itemModel == '') and type(item.catalogMeta) == 'table' then
            itemModel = item.catalogMeta.worldModel
        end
        if type(itemModel) == 'string' and itemModel ~= '' then
            return { model = itemModel, zOffset = 0.0, heading = 0.0 }
        end
    end

    -- Clothing is intentionally ONE shared prop for every clothing item, so name
    -- prefix maps straight to the clothing category default.
    if name:find('clothing_', 1, true) == 1 then category = 'clothing' end
    if name:find('weapon_', 1, true) == 1 then category = 'weapon' end
    if name:find('ammo_', 1, true) == 1 then category = 'ammo' end

    return { model = categoryDefaultModel(category), zOffset = 0.0, heading = 0.0 }
end

-- ============================================================
-- Save / delete / load
-- ============================================================
-- def: { name, model, zOffset, heading, updatedBy }
function CMItems.SaveItemProp(def)
    if type(def) ~= 'table' then return false, 'invalid_def' end
    if not ensurePropTable() then return false, 'prop_table_unavailable' end

    local name = normalizeName(def.name or def.itemName)
    if name == '' then return false, 'invalid_name' end

    local model = tostring(def.model or ''):gsub('%s+', '')
    if model == '' then return false, 'invalid_model' end
    model = model:sub(1, 80)

    local zOffset = clampOffset(def.zOffset or def.z_offset)
    local heading = normalizeHeading(def.heading)

    MySQL.query.await([[
        INSERT INTO cm_item_props (name, model, z_offset, heading, updated_by)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE model = VALUES(model), z_offset = VALUES(z_offset),
            heading = VALUES(heading), updated_by = VALUES(updated_by)
    ]], { name, model, zOffset, heading, tostring(def.updatedBy or 'system'):sub(1, 100) })

    CMItems.ItemProps[name] = { model = model, zOffset = zOffset, heading = heading }
    dbg(('SaveItemProp name=%s model=%s z=%s h=%s'):format(name, model, zOffset, heading))
    syncItemProps()
    return true, CMItems.ItemProps[name]
end

function CMItems.DeleteItemProp(name)
    name = normalizeName(name)
    if name == '' then return false, 'invalid_name' end
    if not ensurePropTable() then return false, 'prop_table_unavailable' end

    MySQL.query.await('DELETE FROM cm_item_props WHERE name = ?', { name })
    CMItems.ItemProps[name] = nil
    dbg(('DeleteItemProp name=%s'):format(name))
    syncItemProps()
    return true
end

function CMItems.ReloadItemProps()
    if not ensurePropTable() then return end
    local rows = MySQL.query.await('SELECT name, model, z_offset, heading FROM cm_item_props') or {}
    CMItems.ItemProps = {}
    for _, row in ipairs(rows) do
        CMItems.ItemProps[normalizeName(row.name)] = {
            model = row.model,
            zOffset = tonumber(row.z_offset) or 0.0,
            heading = tonumber(row.heading) or 0.0,
        }
    end
    syncItemProps()
    dbg(('ReloadItemProps loaded %s overrides'):format(#rows))
end

-- ============================================================
-- Exports
-- ============================================================
exports('GetItemDropProp', function(name) return CMItems.GetItemDropProp(name) end)
exports('SaveItemProp', function(def) return CMItems.SaveItemProp(def) end)
exports('DeleteItemProp', function(name) return CMItems.DeleteItemProp(name) end)
exports('ReloadItemProps', function() return CMItems.ReloadItemProps() end)

RegisterNetEvent('cm-items:server:requestItemPropsSync', function()
    syncItemProps(source)
end)

CreateThread(function()
    Wait(1300) -- after items_catalog load
    CMItems.ReloadItemProps()
end)
