local RESOURCE = GetCurrentResourceName()
local DB_READY = false

local function dbg(msg)
    if Config.Debug then print(('[%s] %s'):format(RESOURCE, tostring(msg))) end
end

local function notify(src, msg, typ)
    TriggerClientEvent('cm-hud:client:notify', src, tostring(msg or ''), typ or 'info')
end

local function isAdmin(src)
    if src == 0 then return true end
    return IsPlayerAceAllowed(src, Config.AdminAce or 'cm.gunstore.admin')
        or IsPlayerAceAllowed(src, 'command.' .. (Config.AdminCommand or 'gunadmin'))
        or IsPlayerAceAllowed(src, 'command')
end

local function boolInt(value)
    if value == true or value == 1 or value == '1' or value == 'true' then return 1 end
    return 0
end

local function rowToPublic(row)
    row = row or {}
    return {
        id = tonumber(row.id) or 0,
        item_name = tostring(row.item_name or ''),
        item_type = tostring(row.item_type or 'weapon'),
        label = tostring(row.label or row.item_name or 'Item'),
        weapon_hash = tostring(row.weapon_hash or ''),
        ammo_item = tostring(row.ammo_item or ''),
        pack_size = tonumber(row.pack_size) or 1,
        armor_value = tonumber(row.armor_value or row.armorValue) or 0,
        damage = tonumber(row.damage or row.per_bullet_damage or row.perBulletDamage) or 0,
        stock = tonumber(row.stock) or -1,
        price = tonumber(row.price) or 0,
        enabled = boolInt(row.enabled) == 1,
        image = tostring(row.image or ''),
        description = tostring(row.description or ''),
        sort_order = tonumber(row.sort_order) or 0,
        component_id = tonumber(row.component_id or row.componentId) or nil,
        drawable_id = tonumber(row.drawable_id or row.drawableId) or nil,
        texture_id = tonumber(row.texture_id or row.textureId) or 0,
        gender = tostring(row.gender or 'both')
    }
end

local function waitForDb()
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(500)
    end
end

local function ensureDatabase()
    waitForDb()

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_gun_catalog (
            id INT NOT NULL AUTO_INCREMENT,
            item_name VARCHAR(80) NOT NULL,
            item_type VARCHAR(20) NOT NULL DEFAULT 'weapon',
            label VARCHAR(120) NOT NULL,
            weapon_hash VARCHAR(80) NULL,
            ammo_item VARCHAR(80) NULL,
            pack_size INT NOT NULL DEFAULT 1,
            armor_value INT NOT NULL DEFAULT 0,
            damage INT NOT NULL DEFAULT 0,
            stock INT NOT NULL DEFAULT -1,
            price INT NOT NULL DEFAULT 0,
            enabled TINYINT(1) NOT NULL DEFAULT 0,
            image VARCHAR(255) NULL,
            description VARCHAR(255) NULL,
            sort_order INT NOT NULL DEFAULT 0,
            component_id INT NULL,
            drawable_id INT NULL,
            texture_id INT NOT NULL DEFAULT 0,
            gender VARCHAR(12) NOT NULL DEFAULT 'both',
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_cm_gun_catalog_item_name (item_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- Existing installs from v1.0 did not have armor_value. Keep upgrade safe.
    pcall(function()
        MySQL.query.await('ALTER TABLE cm_gun_catalog ADD COLUMN armor_value INT NOT NULL DEFAULT 0 AFTER pack_size')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE cm_gun_catalog ADD COLUMN damage INT NOT NULL DEFAULT 0 AFTER armor_value')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE cm_gun_catalog ADD COLUMN stock INT NOT NULL DEFAULT -1 AFTER damage')
    end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_gun_catalog ADD COLUMN component_id INT NULL AFTER sort_order') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_gun_catalog ADD COLUMN drawable_id INT NULL AFTER component_id') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_gun_catalog ADD COLUMN texture_id INT NOT NULL DEFAULT 0 AFTER drawable_id') end)
    pcall(function() MySQL.query.await("ALTER TABLE cm_gun_catalog ADD COLUMN gender VARCHAR(12) NOT NULL DEFAULT 'both' AFTER texture_id") end)

    -- One-time cleanup: remove the old seeded default store items and DO NOT re-seed.
    -- The store now starts empty; admins create everything via /gunadmin.
    for _, item in ipairs(Config.DefaultCatalog or {}) do
        local name = tostring(item.item_name or ''):lower()
        if name ~= '' then
            pcall(function()
                MySQL.query.await('DELETE FROM cm_gun_catalog WHERE LOWER(item_name) = ?', { name })
            end)
        end
    end

    DB_READY = true
    print(('[%s] catalog ready (seed disabled, store starts empty)'):format(RESOURCE))
end

CreateThread(ensureDatabase)

local function getCatalog(includeDisabled)
    if not DB_READY then ensureDatabase() end
    local where = includeDisabled and '' or 'WHERE enabled = 1'
    local rows = MySQL.query.await(('SELECT * FROM cm_gun_catalog %s ORDER BY sort_order ASC, item_type ASC, label ASC'):format(where), {}) or {}
    local result = {}
    for _, row in ipairs(rows) do
        result[#result + 1] = rowToPublic(row)
    end
    return result
end

local function getCatalogRowByName(itemName)
    itemName = tostring(itemName or ''):lower()
    if itemName == '' then return nil end
    local rows = MySQL.query.await('SELECT * FROM cm_gun_catalog WHERE LOWER(item_name) = ? LIMIT 1', { itemName }) or {}
    return rows[1] and rowToPublic(rows[1]) or nil
end

local function inventorySuccess(result)
    if result == true then return true end
    if type(result) == 'number' then return result > 0 end
    if type(result) == 'table' then
        if result.success == true or result.ok == true or result.added == true then return true end
        if result[1] == true then return true end
    end
    return false
end


local function registerUsableThroughItemActions(itemName, itemType)
    itemName = tostring(itemName or ''):lower()
    if itemName == '' or GetResourceState(Config.Inventory or 'cm-inventory') ~= 'started' then return end
    itemType = tostring(itemType or ''):lower()

    if itemType == 'armor' then
        -- Wearable vest: apply component 9 + armor on the using player.
        -- cm-inventory's RegisterUseableItem expects (item, resourceName, exportName),
        -- so we register a cm-gunstore export rather than an inline function.
        pcall(function()
            exports[Config.Inventory or 'cm-inventory']:RegisterUseableItem(itemName, 'cm-gunstore', 'UseVest')
        end)
        return
    end

    pcall(function()
        exports[Config.Inventory or 'cm-inventory']:RegisterUseableItem(itemName, 'cm-itemactions', 'UseItem')
    end)
end

-- Export called by cm-inventory when a player uses an armor (vest) item.
-- Signature mirrors cm-itemactions:UseItem so the inventory can call it the same way.
local function handleUseVest(source, item, ...)
    local src = tonumber(source)
    if not src then return end
    local meta = {}
    if type(item) == 'table' then
        meta = item.metadata or item.info or item
    end
    -- Some inventories pass (src, itemName, slot, metadata) instead of an item table.
    local extra = { ... }
    for _, v in ipairs(extra) do
        if type(v) == 'table' then meta = v.metadata or v.info or v break end
    end
    TriggerClientEvent('cm-gunstore:client:wearVest', src, type(meta) == 'table' and meta or {})
    return true
end
exports('UseVest', handleUseVest)

-- On resource start, register every existing catalog item as usable so vests
-- (and weapons/ammo) work after a restart, not only when freshly created.
CreateThread(function()
    while not DB_READY do Wait(250) end
    Wait(500)
    local rows = MySQL.query.await('SELECT item_name, item_type FROM cm_gun_catalog', {}) or {}
    for _, row in ipairs(rows) do
        registerUsableThroughItemActions(row.item_name, row.item_type)
    end
    dbg(('registered %s usable catalog items on start'):format(#rows))
end)

local function addInventoryItem(src, itemName, amount, metadata)
    if GetResourceState(Config.Inventory or 'cm-inventory') ~= 'started' then
        return false, 'Inventory is not available.'
    end

    metadata = type(metadata) == 'table' and metadata or {}
    metadata.inventoryOnly = true
    metadata.equipped = false
    metadata.autoEquip = false
    metadata.preferredContainer = 'pockets'
    metadata.preferredStorage = 'pockets'
    metadata.inventoryTarget = 'pockets'
    metadata.slotGroup = 'pockets'

    local inv = exports[Config.Inventory or 'cm-inventory']
    local attempts = {
        function() return inv:AddItem(src, itemName, amount, metadata, 'cm_gunstore_purchase') end,
        function() return inv:AddItem(src, itemName, amount, metadata) end,
        function() return inv:AddItem(src, itemName, amount, false, metadata, 'cm_gunstore_purchase') end,
        function() return inv:AddItem(src, itemName, amount, metadata, 'cm_gunstore_purchase', 'pockets') end,
        function() return inv:AddItem(src, itemName, amount, metadata, 'cm_gunstore_purchase', 'fastaccess') end,
    }

    local lastErr = nil
    for _, fn in ipairs(attempts) do
        local ok, result, reason = pcall(fn)
        if ok and inventorySuccess(result) then
            dbg(('AddItem success src=%s item=%s amount=%s'):format(src, itemName, amount))
            return true
        end
        lastErr = reason or result or lastErr
    end

    return false, tostring(lastErr or 'inventory_full_or_unknown_item')
end

local function removeMoney(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    account = tostring(account or 'bank')
    local ok, result = pcall(function()
        return exports['cm-core']:RemoveMoney(src, account, amount)
    end)
    return ok and result == true
end

local function refundMoney(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    account = tostring(account or 'bank')
    pcall(function() exports['cm-core']:AddMoney(src, account, amount) end)
    pcall(function() exports['cm-core']:AddAccountMoney(src, account, amount) end)
end

math.randomseed(os.time())

local function makeSerial(src)
    return ('CMW-%s-%s-%04d'):format(os.date('!%Y%m%d%H%M%S'), tostring(src), math.random(0, 9999))
end

local function buildMetadata(src, row)
    local now = os.date('!%Y-%m-%dT%H:%M:%SZ')
    local meta = {
        label = row.label,
        image = row.image,
        icon = row.image,
        description = row.description,
        purchasedAt = now,
        boughtFrom = 'cm-gunstore',
        catalogId = tonumber(row.id) or nil,
        snapshot = {
            label = row.label,
            image = row.image,
            description = row.description,
            itemType = row.item_type,
            armorValue = tonumber(row.armor_value or row.armorValue) or nil,
            damage = tonumber(row.damage) or nil,
            componentId = tonumber(row.component_id or row.componentId) or nil,
            drawableId = tonumber(row.drawable_id or row.drawableId) or nil,
            textureId = tonumber(row.texture_id or row.textureId) or 0,
            gender = row.gender
        }
    }

    if row.item_type == 'ammo' then
        meta.category = 'ammo'
        meta.categoryType = 'ammo'
        meta.itemType = 'normal'
        meta.rarity = 'normal'
        meta.ammoType = row.item_name
        meta.packSize = row.pack_size
        meta.stack = true
    elseif row.item_type == 'armor' then
        meta.category = 'armor'
        meta.categoryType = 'armor'
        meta.itemType = 'normal'
        meta.rarity = 'rare'
        meta.armorValue = tonumber(row.armor_value or row.armorValue) or 0
        meta.stack = false
        meta.usable = true
        meta.isWearableVest = tonumber(row.drawable_id or row.drawableId) ~= nil
        meta.category = 'armor'
        meta.categoryType = 'armor'
        meta.componentType = 'component'
        meta.componentIndex = tonumber(row.component_id or row.componentId) or 9
        meta.componentId = tonumber(row.component_id or row.componentId) or 9
        meta.drawableId = tonumber(row.drawable_id or row.drawableId)
        meta.drawable = tonumber(row.drawable_id or row.drawableId)
        meta.textureId = tonumber(row.texture_id or row.textureId) or 0
        meta.texture = tonumber(row.texture_id or row.textureId) or 0
        meta.gender = row.gender or 'both'
    else
        meta.category = 'weapon'
        meta.categoryType = 'weapon'
        meta.itemType = 'unique'
        meta.rarity = 'unique'
        meta.weaponHash = row.weapon_hash
        meta.weaponName = row.item_name
        meta.ammoType = row.ammo_item
        meta.perBulletDamage = tonumber(row.damage) or 0
        meta.damage = tonumber(row.damage) or 0
        meta.serial = makeSerial(src)
        meta.durability = 100
        meta.stack = false
    end

    return meta
end

RegisterNetEvent('cm-gunstore:server:requestCatalog', function(mode)
    local src = source
    mode = tostring(mode or 'store')
    local admin = mode == 'admin'

    if admin and not isAdmin(src) then
        notify(src, 'You do not have permission to manage gun store catalog.', 'error')
        return
    end

    TriggerClientEvent('cm-gunstore:client:openCatalog', src, mode, getCatalog(admin))
end)

-- Build the admin weapon picker: the full firearm reference list, each annotated
-- with its current server status (created in cm-items? in this shop? price/damage?).
local function weaponItemName(hash)
    -- WEAPON_CARBINERIFLE -> weapon_carbinerifle
    return tostring(hash or ''):lower()
end

local function buildWeaponPicker()
    -- Gather existing shop rows by item_name for quick lookup.
    local shopRows = {}
    local rows = MySQL.query.await('SELECT item_name, price, damage, enabled, stock, image FROM cm_gun_catalog WHERE item_type = ?', { 'weapon' }) or {}
    for _, r in ipairs(rows) do shopRows[tostring(r.item_name):lower()] = r end

    local list = {}
    for _, w in ipairs(Config.WeaponCatalog or {}) do
        local itemName = weaponItemName(w.hash)
        local shop = shopRows[itemName]
        -- Definition exists in cm-items?
        local existsInItems = false
        if GetResourceState('cm-items') == 'started' then
            local def = exports['cm-items']:GetCatalogItem(itemName)
            existsInItems = def ~= nil
        end
        local status = 'new'
        if shop then
            status = (tonumber(shop.enabled) == 1) and 'store' or 'hidden'
        elseif existsInItems then
            status = 'made' -- defined on server but not in this shop
        end
        list[#list + 1] = {
            hash = w.hash,
            item_name = itemName,
            label = w.label,
            group = w.group,
            ammo = w.ammo,
            weight = w.weight,
            image = (shop and shop.image and shop.image ~= '' and shop.image) or w.image,
            price = shop and tonumber(shop.price) or 0,
            damage = shop and tonumber(shop.damage) or 0,
            stock = shop and tonumber(shop.stock) or -1,
            status = status,
        }
    end
    return list
end

RegisterNetEvent('cm-gunstore:server:requestWeaponPicker', function()
    local src = source
    if not isAdmin(src) then
        notify(src, 'You do not have permission.', 'error')
        return
    end
    TriggerClientEvent('cm-gunstore:client:weaponPicker', src, buildWeaponPicker(), Config.WeaponGroups or {})
end)

-- Create/update a weapon from the picker. Maps the picker row to the standard
-- create flow (definition -> cm-items, price/stock -> cm_gun_catalog).
RegisterNetEvent('cm-gunstore:server:createWeaponFromPicker', function(data)
    local src = source
    if not isAdmin(src) then
        notify(src, 'You do not have permission.', 'error')
        return
    end
    data = type(data) == 'table' and data or {}
    local hash = tostring(data.hash or ''):upper()
    if hash == '' or not hash:find('^WEAPON_') then
        notify(src, 'Invalid weapon.', 'error')
        return
    end
    -- Find the reference entry for defaults (label, ammo, weight, image).
    local ref
    for _, w in ipairs(Config.WeaponCatalog or {}) do
        if w.hash == hash then ref = w break end
    end
    if not ref then
        notify(src, 'Unknown weapon hash.', 'error')
        return
    end

    local payload = {
        item_type = 'weapon',
        item_name = hash:lower(),               -- weapon_carbinerifle
        label = (data.label ~= nil and tostring(data.label) ~= '' and data.label) or ref.label,
        weapon_hash = hash,
        ammo_item = data.ammo_item or ref.ammo,
        damage = tonumber(data.damage) or 0,
        price = tonumber(data.price) or 0,
        stock = tonumber(data.stock) or -1,
        enabled = data.enabled == true or data.enabled == 1,
        description = data.description or (ref.label .. '.'),
        image = (data.image ~= nil and tostring(data.image) ~= '' and data.image) or ref.image,
        imageData = data.imageData, -- optional uploaded PNG overrides the doc image
    }
    -- Reuse the standard create handler by triggering its logic directly.
    TriggerEvent('cm-gunstore:server:adminCreateItem', payload, src)
    -- Refresh picker so the status badge updates.
    TriggerClientEvent('cm-gunstore:client:weaponPicker', src, buildWeaponPicker(), Config.WeaponGroups or {})
end)

RegisterNetEvent('cm-gunstore:server:buyItem', function(data)
    local src = source
    data = type(data) == 'table' and data or {}

    local itemName = tostring(data.item_name or ''):lower()
    local method = tostring(data.method or 'bank'):lower() == 'cash' and 'cash' or 'bank'
    local account = Config.Accounts and Config.Accounts[method] or method

    local row = getCatalogRowByName(itemName)
    if not row then
        notify(src, 'This item does not exist.', 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end

    if row.enabled ~= true then
        notify(src, 'This item is not available.', 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end

    local amount = row.item_type == 'ammo' and math.max(1, tonumber(row.pack_size) or 1) or 1
    if tonumber(row.stock) and tonumber(row.stock) == 0 then
        notify(src, 'This item is out of stock.', 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end
    local total = math.max(0, math.floor(tonumber(row.price) or 0))

    if not removeMoney(src, account, total) then
        notify(src, 'You do not have enough money.', 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end

    local metadata = buildMetadata(src, row)
    local added, err = addInventoryItem(src, row.item_name, amount, metadata)
    if not added then
        refundMoney(src, account, total)
        notify(src, ('Could not add item to inventory: %s'):format(tostring(err)), 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end

    if tonumber(row.stock) and tonumber(row.stock) > 0 then
        MySQL.update.await('UPDATE cm_gun_catalog SET stock = GREATEST(stock - ?, 0) WHERE LOWER(item_name) = ?', { amount, itemName })
    end

    notify(src, ('Purchased %s. Check your inventory.'):format(row.label), 'success')
    TriggerClientEvent('cm-gunstore:client:purchaseResult', src, true)
end)


local function slug(value, fallback)
    value = tostring(value or ''):lower():gsub('[^%w_%-]+', '_'):gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if value == '' then value = fallback or ('item_' .. os.time()) end
    return value:sub(1, 80)
end

local base64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64Decode(data)
    data = tostring(data or ''):gsub('[^' .. base64chars .. '=]', '')
    return (data:gsub('.', function(x)
        if x == '=' then return '' end
        local r, f = '', (base64chars:find(x, 1, true) or 1) - 1
        for i = 6, 1, -1 do r = r .. (f % 2^i - f % 2^(i-1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x ~= 8 then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i,i) == '1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

local function saveDataImage(dataUri, itemName)
    dataUri = tostring(dataUri or '')
    if dataUri == '' then return nil end
    local mime, encoded = dataUri:match('^data:(image/%w+);base64,(.+)$')
    if not encoded then return nil, 'bad_image_data' end
    local ext = (mime == 'image/jpeg' or mime == 'image/jpg') and 'jpg' or 'png'
    local safe = slug(itemName, 'item')
    local file = ('web/images/custom/%s_%s.%s'):format(safe, os.time(), ext)
    local decoded = base64Decode(encoded)
    if not decoded or #decoded < 32 then return nil, 'empty_image_data' end
    SaveResourceFile(RESOURCE, file, decoded, #decoded)
    return ('nui://%s/%s'):format(RESOURCE, file)
end

RegisterNetEvent('cm-gunstore:server:adminCreateItem', function(data, explicitSrc)
    local src = explicitSrc or source
    if not isAdmin(src) then
        notify(src, 'You do not have permission to create gun store items.', 'error')
        return
    end

    data = type(data) == 'table' and data or {}
    local itemType = tostring(data.item_type or data.itemType or 'weapon'):lower()
    if itemType ~= 'weapon' and itemType ~= 'ammo' and itemType ~= 'armor' then itemType = 'weapon' end

    local label = tostring(data.label or ''):sub(1, 120)
    local itemName = slug(data.item_name or data.itemName or label, itemType .. '_' .. os.time())
    if itemType == 'weapon' and not itemName:find('^weapon_') then itemName = ('weapon_%s'):format(itemName) end
    if itemType == 'armor' and not itemName:find('^armor_') then itemName = ('armor_%s'):format(itemName) end
    if itemType == 'ammo' and not itemName:find('^ammo_') then itemName = ('ammo_%s'):format(itemName) end
    if label == '' then label = itemName:gsub('_', ' '):gsub('^%l', string.upper) end

    local image = tostring(data.image or ''):sub(1, 255)
    if tostring(data.imageData or '') ~= '' then
        local saved, err = saveDataImage(data.imageData, itemName)
        if saved then image = saved else dbg(('image save failed: %s'):format(tostring(err))) end
    end

    local weaponHash = tostring(data.weapon_hash or data.weaponHash or ''):upper():sub(1, 80)
    local ammoItem = tostring(data.ammo_item or data.ammoItem or ''):lower():sub(1, 80)
    local packSize = math.max(1, math.floor(tonumber(data.pack_size or data.packSize) or 1))
    local armorValue = math.max(0, math.min(100, math.floor(tonumber(data.armor_value or data.armorValue) or 0)))
    local damage = math.max(0, math.floor(tonumber(data.damage or data.per_bullet_damage or data.perBulletDamage) or 0))
    local price = math.max(0, math.floor(tonumber(data.price) or 0))
    local stock = math.floor(tonumber(data.stock) or -1)
    local enabled = boolInt(data.enabled)
    local description = tostring(data.description or ''):sub(1, 255)
    local sortOrder = math.floor(tonumber(data.sort_order or data.sortOrder) or 999)
    local componentId = math.floor(tonumber(data.component_id or data.componentId) or (itemType == 'armor' and 9 or 0))
    local drawableId = data.drawable_id or data.drawableId
    drawableId = drawableId ~= nil and math.floor(tonumber(drawableId) or -1) or nil
    if drawableId and drawableId < 0 then drawableId = nil end
    local textureId = math.max(0, math.floor(tonumber(data.texture_id or data.textureId) or 0))
    local gender = tostring(data.gender or 'both'):lower():sub(1, 12)
    if gender ~= 'male' and gender ~= 'female' and gender ~= 'both' then gender = 'both' end

    -- ============================================================
    -- DEFINITION LIVES IN cm-items (single source of truth).
    -- We push the item definition + image into cm-items. The local
    -- cm_gun_catalog row below only stores SHOP data (price/stock/enabled).
    -- ============================================================
    if GetResourceState('cm-items') == 'started' then
        local equipmentSlot = (itemType == 'armor' and 'bodyarmor')
            or (itemType == 'weapon' and 'weapon')
            or (itemType == 'ammo' and 'ammo') or nil
        local catMeta = {
            gender = gender,
        }
        if itemType == 'armor' then
            catMeta.componentIndex = componentId
            catMeta.componentId = componentId
            catMeta.drawableId = drawableId
            catMeta.textureId = textureId
            catMeta.armorValue = armorValue
        elseif itemType == 'weapon' then
            catMeta.weaponHash = weaponHash
            catMeta.ammoType = ammoItem
            catMeta.damage = damage
        elseif itemType == 'ammo' then
            catMeta.ammoType = itemName
            catMeta.packSize = packSize
        end

        local def = {
            name = itemName,
            label = label,
            category = itemType, -- armor / weapon / ammo
            itemType = (itemType == 'armor' and 'rare') or (itemType == 'weapon' and 'unique') or 'normal',
            equipmentSlot = equipmentSlot,
            armorValue = (itemType == 'armor') and armorValue or nil,
            weight = (itemType == 'armor' and 2500) or (itemType == 'weapon' and 1500) or 15,
            stack = (itemType == 'ammo'),
            usable = true,
            description = description,
            metadata = catMeta,
            enabled = (enabled == 1),
            createdBy = ('player:%s'):format(src),
        }
        -- Pass the captured/uploaded base64 so cm-items saves the PNG itself,
        -- unless an explicit image path was already provided.
        if (not image or image == '') and tostring(data.imageData or '') ~= '' then
            def.imageData = data.imageData
        elseif image and image ~= '' then
            def.image = image
        end

        local okDef, resOrErr = exports['cm-items']:SaveCatalogItem(def)
        if okDef then
            -- Use the image cm-items stored (its nui path) so the shop row matches.
            if type(resOrErr) == 'table' and resOrErr.image then
                image = resOrErr.image
            end
        else
            dbg(('cm-items SaveCatalogItem failed: %s'):format(tostring(resOrErr)))
            notify(src, ('Warning: could not register item in cm-items (%s). Saved to shop only.'):format(tostring(resOrErr)), 'error')
        end
    end

    local ok, err = pcall(function()
        MySQL.insert.await([[
            INSERT INTO cm_gun_catalog
                (item_name, item_type, label, weapon_hash, ammo_item, pack_size, armor_value, damage, stock, price, enabled, image, description, sort_order, component_id, drawable_id, texture_id, gender)
            VALUES
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                item_type = VALUES(item_type), label = VALUES(label), weapon_hash = VALUES(weapon_hash), ammo_item = VALUES(ammo_item),
                pack_size = VALUES(pack_size), armor_value = VALUES(armor_value), damage = VALUES(damage), stock = VALUES(stock),
                price = VALUES(price), enabled = VALUES(enabled), image = VALUES(image), description = VALUES(description), sort_order = VALUES(sort_order),
                component_id = VALUES(component_id), drawable_id = VALUES(drawable_id), texture_id = VALUES(texture_id), gender = VALUES(gender)
        ]], { itemName, itemType, label, weaponHash, ammoItem, packSize, armorValue, damage, stock, price, enabled, image, description, sortOrder, componentId, drawableId, textureId, gender })
    end)

    if not ok then
        notify(src, ('Could not create item: %s'):format(tostring(err)), 'error')
        return
    end

    if itemType == 'armor' or itemType == 'weapon' or itemType == 'ammo' then
        registerUsableThroughItemActions(itemName, itemType)
    end

    notify(src, ('Created %s.'):format(label), 'success')
    TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', getCatalog(true))
end)

RegisterNetEvent('cm-gunstore:server:adminSaveImage', function(data)
    local src = source
    if not isAdmin(src) then return end
    data = type(data) == 'table' and data or {}
    local itemName = tostring(data.item_name or ''):lower()
    if itemName == '' then return end
    local saved, err = saveDataImage(data.imageData, itemName)
    if not saved then
        notify(src, ('Image save failed: %s'):format(tostring(err or 'unknown')), 'error')
        return
    end
    MySQL.update.await('UPDATE cm_gun_catalog SET image = ? WHERE LOWER(item_name) = ?', { saved, itemName })
    notify(src, 'Image saved.', 'success')
    TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', getCatalog(true))
end)

RegisterNetEvent('cm-gunstore:server:adminSaveItem', function(data)
    local src = source
    if not isAdmin(src) then
        notify(src, 'You do not have permission to edit gun store catalog.', 'error')
        return
    end

    data = type(data) == 'table' and data or {}
    local itemName = tostring(data.item_name or ''):lower()
    if itemName == '' then
        notify(src, 'Invalid item.', 'error')
        return
    end

    local price = math.max(0, math.floor(tonumber(data.price) or 0))
    local enabled = boolInt(data.enabled)
    local label = tostring(data.label or ''):sub(1, 120)
    local image = tostring(data.image or ''):sub(1, 255)
    local description = tostring(data.description or ''):sub(1, 255)
    local armorValue = math.max(0, math.floor(tonumber(data.armor_value or data.armorValue) or 0))
    local damage = math.max(0, math.floor(tonumber(data.damage or data.per_bullet_damage or data.perBulletDamage) or 0))
    local stock = math.floor(tonumber(data.stock) or -1)
    local weaponHash = tostring(data.weapon_hash or data.weaponHash or ''):upper():sub(1, 80)
    local ammoItem = tostring(data.ammo_item or data.ammoItem or ''):lower():sub(1, 80)
    local packSize = math.max(1, math.floor(tonumber(data.pack_size or data.packSize) or 1))
    local componentId = math.floor(tonumber(data.component_id or data.componentId) or 9)
    local drawableId = data.drawable_id or data.drawableId
    drawableId = drawableId ~= nil and math.floor(tonumber(drawableId) or -1) or nil
    if drawableId and drawableId < 0 then drawableId = nil end
    local textureId = math.max(0, math.floor(tonumber(data.texture_id or data.textureId) or 0))
    local gender = tostring(data.gender or 'both'):lower():sub(1, 12)
    if gender ~= 'male' and gender ~= 'female' and gender ~= 'both' then gender = 'both' end

    local affected = MySQL.update.await([[
        UPDATE cm_gun_catalog
        SET label = ?, price = ?, enabled = ?, image = ?, description = ?, armor_value = ?, damage = ?, stock = ?, weapon_hash = ?, ammo_item = ?, pack_size = ?, component_id = ?, drawable_id = ?, texture_id = ?, gender = ?
        WHERE LOWER(item_name) = ?
    ]], { label, price, enabled, image, description, armorValue, damage, stock, weaponHash, ammoItem, packSize, componentId, drawableId, textureId, gender, itemName })

    if not affected or affected < 1 then
        notify(src, 'Catalog item not found.', 'error')
        return
    end

    notify(src, ('Saved %s.'):format(label ~= '' and label or itemName), 'success')
    TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', getCatalog(true))
end)

RegisterCommand(Config.AdminCommand or 'gunadmin', function(src)
    if src == 0 then
        print('[cm-gunstore] /gunadmin can only be used in-game.')
        return
    end

    if not isAdmin(src) then
        notify(src, 'You do not have permission to use gun admin.', 'error')
        return
    end

    TriggerClientEvent('cm-gunstore:client:openAdmin', src)
end, false)

exports('GetCatalog', function(includeDisabled)
    return getCatalog(includeDisabled == true)
end)

exports('IsItemEnabled', function(itemName)
    local row = getCatalogRowByName(itemName)
    return row and row.enabled == true or false
end)


--========================================================
-- WEARABLE VEST INTEGRATION WITH nv_cloth (model b)
-- nv_cloth captures the transparent vest PNG, saves it into cm-gunstore,
-- then calls this export. We forward the image + drawable/texture to the
-- admin's gun create-form so they can set name/price/armor and click Create.
--========================================================
exports('ReceiveArmorImage', function(src, payload)
    src = tonumber(src)
    payload = type(payload) == 'table' and payload or {}
    if not src or not isAdmin(src) then return false end
    TriggerClientEvent('cm-gunstore:client:prefillArmor', src, payload)
    return true
end)

-- Fallback event path (used if the export call is unavailable).
RegisterNetEvent('cm-gunstore:server:armorImageReady', function(src, payload)
    -- When called server-to-server, source is passed explicitly.
    src = tonumber(src) or source
    payload = type(payload) == 'table' and payload or {}
    if not src or not isAdmin(src) then return end
    TriggerClientEvent('cm-gunstore:client:prefillArmor', src, payload)
end)

-- Admin clicked "Capture Vest (Clothing Studio)" in the gun panel.
-- Hand off to nv_cloth's armor-only admin panel.
RegisterNetEvent('cm-gunstore:server:openArmorCapture', function()
    local src = source
    if not isAdmin(src) then
        notify(src, 'You do not have permission to capture vests.', 'error')
        return
    end
    if GetResourceState('nv_cloth') ~= 'started' then
        notify(src, 'nv_cloth is not started; cannot open the vest capture studio.', 'error')
        return
    end
    TriggerClientEvent('nvCloth:client:openArmorAdminPanel', src)
end)

--========================================================
-- Wear-on-use for vests (armor items).
-- cm-gunstore applies component 9 + armor itself, so it does not need
-- cm-itemactions to understand clothing components.
--========================================================
RegisterNetEvent('cm-gunstore:server:vestUsed', function()
    -- placeholder for future server-side validation/logging
end)
