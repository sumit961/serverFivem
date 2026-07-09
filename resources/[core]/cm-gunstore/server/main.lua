local RESOURCE = GetCurrentResourceName()
local DB_READY = false
local syncConfigCatalog

local function dbg(msg)
    if Config.Debug then print(('[%s] %s'):format(RESOURCE, tostring(msg))) end
end

local function notify(src, msg, typ)
    if src == 0 then
        print(('[%s] %s'):format(RESOURCE, tostring(msg or '')))
        return
    end
    TriggerClientEvent('cm-hud:client:notify', src, tostring(msg or ''), typ or 'info')
end

local function weaponsResource()
    return Config.WeaponsResource or 'cm-weapons'
end

local function itemsResource()
    return Config.ItemsResource or 'cm-items'
end

local function isAdmin(src)
    if src == 0 then return true end
    -- Only the gunstore-admin ace or the specific admin command ace grant access.
    -- The bare 'command' ace is granted very broadly on many servers, so it must
    -- NOT be a fallback here or ordinary players could edit prices/stock/catalog.
    return IsPlayerAceAllowed(src, Config.AdminAce or 'cm.gunstore.admin')
        or IsPlayerAceAllowed(src, 'command.' .. (Config.AdminCommand or 'gunadmin'))
end

local function boolInt(value)
    if value == true or value == 1 or value == '1' or value == 'true' or value == 'yes' or value == 'on' then return 1 end
    return 0
end

local function normalizeItemName(value)
    value = tostring(value or ''):lower():gsub('%s+', '_'):gsub('[^a-z0-9_%-%.]', '_'):gsub('_+', '_')
    value = value:gsub('^_+', ''):gsub('_+$', '')
    return value:sub(1, 80)
end

local function configStoreEntry(itemName)
    itemName = normalizeItemName(itemName)
    if itemName == '' then return nil end
    for _, entry in ipairs(Config.StoreCatalog or {}) do
        if normalizeItemName(entry.itemName or entry.item_name) == itemName then return entry end
    end
    return nil
end

local function configPrice(itemName, fallback)
    local entry = configStoreEntry(itemName)
    if entry and entry.price ~= nil then return math.max(0, math.floor(tonumber(entry.price) or 0)) end
    return math.max(0, math.floor(tonumber(fallback) or 0))
end

local function configSortOrder(itemName, fallback)
    local entry = configStoreEntry(itemName)
    if entry and entry.sortOrder ~= nil then return math.floor(tonumber(entry.sortOrder) or 0) end
    if entry and entry.sort_order ~= nil then return math.floor(tonumber(entry.sort_order) or 0) end
    return math.floor(tonumber(fallback) or 0)
end

local function configDefaultEnabled(itemName, fallback)
    local entry = configStoreEntry(itemName)
    if entry and entry.enabled ~= nil then return boolInt(entry.enabled) == 1 end
    return fallback == true
end

local function configDefaultStock(itemName, fallback)
    local entry = configStoreEntry(itemName)
    if entry and entry.stock ~= nil then return math.floor(tonumber(entry.stock) or -1) end
    return math.floor(tonumber(fallback) or -1)
end


local allWeapons, allAmmo

local function findWeaponDefFromAll(itemName)
    itemName = normalizeItemName(itemName)
    if itemName == '' then return nil end
    for _, w in ipairs(allWeapons(true) or {}) do
        if normalizeItemName(w.itemName or w.item_name) == itemName
            or normalizeItemName(w.weaponHash or w.weapon_hash) == itemName then
            return w
        end
    end
    -- Last-resort local reference fallback. cm-weapons should still be the source of truth,
    -- but this prevents an empty player store if cm-weapons cache is still warming up.
    for _, w in ipairs(Config.WeaponCatalog or {}) do
        local hash = tostring(w.hash or w.weaponHash or w.weapon_hash or ''):upper()
        if normalizeItemName(hash) == itemName then
            return {
                itemName = itemName,
                item_name = itemName,
                label = tostring(w.label or itemName),
                weaponHash = hash,
                weapon_hash = hash,
                group = tostring(w.group or 'pistol'):lower(),
                group_key = tostring(w.group or 'pistol'):lower(),
                ammoItem = normalizeItemName(w.ammo or w.ammoItem or w.ammo_item),
                ammo_item = normalizeItemName(w.ammo or w.ammoItem or w.ammo_item),
                damage = tonumber(w.damage) or 0,
                magazineSize = tonumber(w.magazineSize or w.magazine_size) or 0,
                magazine_size = tonumber(w.magazineSize or w.magazine_size) or 0,
                weight = tonumber(w.weight) or 0,
                image = tostring(w.image or ''),
                description = tostring(w.description or '')
            }
        end
    end
    return nil
end

local function findAmmoDefFromAll(itemName)
    itemName = normalizeItemName(itemName)
    if itemName == '' then return nil end
    for _, a in ipairs(allAmmo(true) or {}) do
        if normalizeItemName(a.itemName or a.item_name) == itemName then return a end
    end
    return nil
end

local function applyConfigStore(row)
    row = row or {}
    local entry = configStoreEntry(row.item_name or row.itemName)
    if entry then
        row.price = configPrice(row.item_name, row.price)
        row.config_price = true
        row.sort_order = configSortOrder(row.item_name, row.sort_order)
    elseif Config.PriceMode == 'config' and (row.item_type == 'weapon' or row.item_type == 'ammo' or row.item_type == 'armor') then
        row.config_price = false
    end
    return row
end

local function rowToPublic(row)
    row = row or {}
    return {
        id = tonumber(row.id) or 0,
        item_name = normalizeItemName(row.item_name or row.itemName),
        item_type = tostring(row.item_type or row.itemType or 'weapon'):lower(),
        label = tostring(row.label or row.item_name or row.itemName or 'Item'),
        weapon_hash = tostring(row.weapon_hash or row.weaponHash or ''),
        ammo_item = normalizeItemName(row.ammo_item or row.ammoItem),
        ammo_key = tostring(row.ammo_key or row.ammoKey or ''),
        pickup_hash = tonumber(row.pickup_hash or row.pickupHash) or 0,
        drop_model = tostring(row.drop_model or row.dropModel or ''),
        pack_size = math.max(1, math.floor(tonumber(row.pack_size or row.packSize) or 1)),
        armor_value = tonumber(row.armor_value or row.armorValue) or 0,
        damage = tonumber(row.damage or 0) or 0,
        magazine_size = tonumber(row.magazine_size or row.magazineSize) or 0,
        stock = math.floor(tonumber(row.stock) or -1),
        price = math.max(0, math.floor(tonumber(row.price) or 0)),
        enabled = boolInt(row.enabled) == 1,
        image = tostring(row.image or ''),
        description = tostring(row.description or ''),
        sort_order = tonumber(row.sort_order or row.sortOrder) or 0,
        component_id = tonumber(row.component_id or row.componentId) or nil,
        drawable_id = tonumber(row.drawable_id or row.drawableId) or nil,
        texture_id = tonumber(row.texture_id or row.textureId) or 0,
        gender = tostring(row.gender or 'both')
    }
end

local function waitForDb()
    while GetResourceState('oxmysql') ~= 'started' do Wait(500) end
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
            ammo_key VARCHAR(40) NULL,
            pickup_hash BIGINT NOT NULL DEFAULT 0,
            drop_model VARCHAR(80) NULL,
            pack_size INT NOT NULL DEFAULT 1,
            armor_value INT NOT NULL DEFAULT 0,
            damage INT NOT NULL DEFAULT 0,
            magazine_size INT NOT NULL DEFAULT 0,
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
            UNIQUE KEY uq_cm_gun_catalog_item_name (item_name),
            INDEX idx_cm_gun_catalog_type (item_type),
            INDEX idx_cm_gun_catalog_enabled (enabled)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    local alters = {
        'ALTER TABLE cm_gun_catalog ADD COLUMN ammo_key VARCHAR(40) NULL AFTER ammo_item',
        'ALTER TABLE cm_gun_catalog ADD COLUMN pickup_hash BIGINT NOT NULL DEFAULT 0 AFTER ammo_key',
        'ALTER TABLE cm_gun_catalog ADD COLUMN drop_model VARCHAR(80) NULL AFTER pickup_hash',
        'ALTER TABLE cm_gun_catalog ADD COLUMN armor_value INT NOT NULL DEFAULT 0 AFTER pack_size',
        'ALTER TABLE cm_gun_catalog ADD COLUMN damage INT NOT NULL DEFAULT 0 AFTER armor_value',
        'ALTER TABLE cm_gun_catalog ADD COLUMN magazine_size INT NOT NULL DEFAULT 0 AFTER damage',
        'ALTER TABLE cm_gun_catalog ADD COLUMN stock INT NOT NULL DEFAULT -1 AFTER magazine_size',
        'ALTER TABLE cm_gun_catalog ADD COLUMN component_id INT NULL AFTER sort_order',
        'ALTER TABLE cm_gun_catalog ADD COLUMN drawable_id INT NULL AFTER component_id',
        'ALTER TABLE cm_gun_catalog ADD COLUMN texture_id INT NOT NULL DEFAULT 0 AFTER drawable_id',
        "ALTER TABLE cm_gun_catalog ADD COLUMN gender VARCHAR(12) NOT NULL DEFAULT 'both' AFTER texture_id"
    }
    for _, q in ipairs(alters) do pcall(function() MySQL.query.await(q) end) end
    pcall(function() MySQL.query.await('CREATE INDEX idx_cm_gun_catalog_type ON cm_gun_catalog (item_type)') end)
    pcall(function() MySQL.query.await('CREATE INDEX idx_cm_gun_catalog_enabled ON cm_gun_catalog (enabled)') end)

    -- v1.2: gun/ammo definitions are managed by cm-weapons. cm_gun_catalog now stores only shop price/stock/visibility.
    DB_READY = true
    print(('[%s] store catalog ready | weapon/ammo source = %s'):format(RESOURCE, weaponsResource()))
end

CreateThread(ensureDatabase)

local function weaponExport(name, ...)
    local res = weaponsResource()
    if GetResourceState(res) ~= 'started' then return nil, 'cm-weapons_not_started' end
    local args = table.pack(...)
    local ok, result, extra = pcall(function()
        return exports[res][name](table.unpack(args, 1, args.n))
    end)
    if not ok then
        dbg(('cm-weapons export %s failed: %s'):format(tostring(name), tostring(result)))
        return nil, result
    end
    return result, extra
end

local function getWeaponDef(itemNameOrHash)
    local row = weaponExport('GetWeapon', itemNameOrHash)
    return type(row) == 'table' and row or nil
end

local function getAmmoDef(itemName)
    local row = weaponExport('GetAmmo', itemName)
    return type(row) == 'table' and row or nil
end

local function fallbackWeaponDefFromPicker(data)
    data = type(data) == 'table' and data or {}
    local itemName = normalizeItemName(data.itemName or data.item_name)
    local weaponHash = tostring(data.weaponHash or data.weapon_hash or data.hash or ''):upper()
    local ammoItem = normalizeItemName(data.ammoItem or data.ammo_item or data.ammo)
    if itemName == '' or weaponHash == '' or weaponHash:sub(1, 7) ~= 'WEAPON_' or ammoItem == '' then return nil end
    return {
        itemName = itemName, item_name = itemName,
        label = tostring(data.label or itemName),
        weaponHash = weaponHash, weapon_hash = weaponHash,
        group = tostring(data.group or data.group_key or 'pistol'):lower(), group_key = tostring(data.group or data.group_key or 'pistol'):lower(),
        ammoItem = ammoItem, ammo_item = ammoItem,
        damage = math.max(0, math.floor(tonumber(data.damage) or 0)),
        magazineSize = math.max(0, math.floor(tonumber(data.magazineSize or data.magazine_size) or 0)),
        magazine_size = math.max(0, math.floor(tonumber(data.magazineSize or data.magazine_size) or 0)),
        image = tostring(data.image or ''),
        description = tostring(data.description or ''),
        source = 'cm-weapons-picker-fallback'
    }
end

local function fallbackAmmoDefFromPicker(data)
    data = type(data) == 'table' and data or {}
    local itemName = normalizeItemName(data.itemName or data.item_name)
    local ammoKey = tostring(data.ammoKey or data.ammo_key or data.group or ''):lower()
    local pickupHash = tonumber(data.pickupHash or data.pickup_hash) or 0
    if itemName == '' or ammoKey == '' then return nil end
    return {
        itemName = itemName, item_name = itemName,
        label = tostring(data.label or itemName),
        ammoKey = ammoKey, ammo_key = ammoKey,
        pickupHash = pickupHash, pickup_hash = pickupHash,
        dropModel = tostring(data.dropModel or data.drop_model or ''),
        drop_model = tostring(data.dropModel or data.drop_model or ''),
        packSize = math.max(1, math.floor(tonumber(data.packSize or data.pack_size) or 1)),
        pack_size = math.max(1, math.floor(tonumber(data.packSize or data.pack_size) or 1)),
        image = tostring(data.image or ''),
        description = tostring(data.description or ''),
        source = 'cm-weapons-picker-fallback'
    }
end

function allWeapons(includeDisabled)
    local rows = weaponExport('GetAllWeapons', includeDisabled == true)
    return type(rows) == 'table' and rows or {}
end

function allAmmo(includeDisabled)
    local rows = weaponExport('GetAllAmmo', includeDisabled == true)
    return type(rows) == 'table' and rows or {}
end

local function mapDefinitions(rows, itemKeys, hashKey)
    local map = {}
    for _, row in ipairs(rows or {}) do
        for _, keyName in ipairs(itemKeys or {}) do
            local key = normalizeItemName(row[keyName])
            if key ~= '' then map[key] = row end
        end
        if hashKey then
            local hash = tostring(row[hashKey] or ''):upper()
            if hash ~= '' then map[hash] = row end
        end
    end
    return map
end

local function buildDefinitionMaps()
    local weaponRows = allWeapons(true)
    local ammoRows = allAmmo(true)
    return {
        weapons = mapDefinitions(weaponRows, { 'itemName', 'item_name' }, 'weaponHash'),
        ammo = mapDefinitions(ammoRows, { 'itemName', 'item_name' }),
        weaponRows = weaponRows,
        ammoRows = ammoRows
    }
end

local function cmWeaponsRequired(src)
    if GetResourceState(weaponsResource()) ~= 'started' then
        notify(src, ('%s is not started. Start cm-weapons before using gun store weapon/ammo catalog.'):format(weaponsResource()), 'error')
        return false
    end
    return true
end

local function getShopRowsByName(itemType)
    if not DB_READY then ensureDatabase() end
    local rows = MySQL.query.await('SELECT * FROM cm_gun_catalog WHERE item_type = ?', { itemType }) or {}
    local map = {}
    for _, r in ipairs(rows) do map[normalizeItemName(r.item_name)] = rowToPublic(r) end
    return map
end

local function hasWeaponSnapshot(shop)
    shop = shop or {}
    return normalizeItemName(shop.item_name or shop.itemName) ~= ''
        and tostring(shop.weapon_hash or shop.weaponHash or '') ~= ''
        and normalizeItemName(shop.ammo_item or shop.ammoItem) ~= ''
end

local function hasAmmoSnapshot(shop)
    shop = shop or {}
    return normalizeItemName(shop.item_name or shop.itemName) ~= ''
        and (tostring(shop.ammo_key or shop.ammoKey or '') ~= '' or tonumber(shop.pickup_hash or shop.pickupHash) ~= nil)
end

local function mergeWeaponRow(shop, def)
    shop = rowToPublic(shop or {})
    def = type(def) == 'table' and def or nil
    if def then
        shop.item_name = normalizeItemName(def.itemName or def.item_name or shop.item_name)
        shop.item_type = 'weapon'
        shop.label = tostring(def.label or shop.label or shop.item_name)
        shop.weapon_hash = tostring(def.weaponHash or def.weapon_hash or shop.weapon_hash or '')
        shop.ammo_item = normalizeItemName(def.ammoItem or def.ammo_item or shop.ammo_item)
        shop.damage = math.max(0, math.floor(tonumber(def.damage) or 0))
        shop.magazine_size = math.max(0, math.floor(tonumber(def.magazineSize or def.magazine_size) or 0))
        shop.image = shop.image ~= '' and shop.image or tostring(def.image or '')
        shop.description = shop.description ~= '' and shop.description or tostring(def.description or '')
        shop.group = tostring(def.group or def.group_key or 'pistol')
        shop.weight = tonumber(def.weight) or nil
        shop.source = 'cm-weapons'
    elseif hasWeaponSnapshot(shop) then
        -- The store row was already created from cm-weapons and contains a safe snapshot.
        -- Do not block purchases just because the export/cache lookup missed during buy.
        shop.item_type = 'weapon'
        shop.snapshot_source_missing = true
        shop.source = 'cm-gunstore_snapshot'
    else
        shop.missing_source = true
        shop.source = 'stale_shop_row'
    end
    return shop
end

local function mergeAmmoRow(shop, def)
    shop = rowToPublic(shop or {})
    def = type(def) == 'table' and def or nil
    if def then
        shop.item_name = normalizeItemName(def.itemName or def.item_name or shop.item_name)
        shop.item_type = 'ammo'
        shop.label = tostring(def.label or shop.label or shop.item_name)
        shop.ammo_key = tostring(def.ammoKey or def.ammo_key or shop.ammo_key or '')
        shop.pickup_hash = tonumber(def.pickupHash or def.pickup_hash) or shop.pickup_hash or 0
        shop.drop_model = tostring(def.dropModel or def.drop_model or shop.drop_model or '')
        shop.pack_size = math.max(1, math.floor(tonumber(def.packSize or def.pack_size) or shop.pack_size or 1))
        shop.damage = 0
        shop.image = shop.image ~= '' and shop.image or tostring(def.image or '')
        shop.description = shop.description ~= '' and shop.description or tostring(def.description or '')
        shop.weight = tonumber(def.weight) or nil
        shop.source = 'cm-weapons'
    elseif hasAmmoSnapshot(shop) then
        -- Same safe snapshot fallback for ammo already saved into the store catalog.
        shop.item_type = 'ammo'
        shop.snapshot_source_missing = true
        shop.source = 'cm-gunstore_snapshot'
    else
        shop.missing_source = true
        shop.source = 'stale_shop_row'
    end
    return shop
end

local function getCatalog(includeDisabled)
    if not DB_READY then ensureDatabase() end
    if syncConfigCatalog then syncConfigCatalog(false) end
    local where = includeDisabled and '' or 'WHERE enabled = 1'
    local rows = MySQL.query.await(('SELECT * FROM cm_gun_catalog %s ORDER BY sort_order ASC, item_type ASC, label ASC'):format(where), {}) or {}
    local defs = buildDefinitionMaps()
    local result = {}
    for _, row in ipairs(rows) do
        local public = rowToPublic(row)
        if public.item_type == 'weapon' then
            local def = defs.weapons[public.item_name] or defs.weapons[tostring(public.weapon_hash or ''):upper()]
            public = mergeWeaponRow(public, def)
        elseif public.item_type == 'ammo' then
            public = mergeAmmoRow(public, defs.ammo[public.item_name])
        end
        public = applyConfigStore(public)
        result[#result + 1] = public
    end
    return result
end

local function getCatalogRowByName(itemName)
    if syncConfigCatalog then syncConfigCatalog(false) end
    itemName = normalizeItemName(itemName)
    if itemName == '' then return nil end
    local rows = MySQL.query.await('SELECT * FROM cm_gun_catalog WHERE LOWER(item_name) = ? LIMIT 1', { itemName }) or {}
    if not rows[1] then return nil end
    local public = rowToPublic(rows[1])
    if public.item_type == 'weapon' then return applyConfigStore(mergeWeaponRow(public, getWeaponDef(public.item_name ~= '' and public.item_name or public.weapon_hash))) end
    if public.item_type == 'ammo' then return applyConfigStore(mergeAmmoRow(public, getAmmoDef(public.item_name))) end
    return applyConfigStore(public)
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
    itemName = normalizeItemName(itemName)
    if itemName == '' or GetResourceState(Config.Inventory or 'cm-inventory') ~= 'started' then return end
    itemType = tostring(itemType or ''):lower()

    if itemType == 'armor' then
        pcall(function()
            exports[Config.Inventory or 'cm-inventory']:RegisterUseableItem(itemName, 'cm-gunstore', 'UseVest')
        end)
        return
    end

    -- Weapon and ammo use/equip should be handled by cm-weapons/cm-itemactions.
    pcall(function()
        exports[Config.Inventory or 'cm-inventory']:RegisterUseableItem(itemName, 'cm-itemactions', 'UseItem')
    end)
end

local function handleUseVest(source, item, ...)
    local src = tonumber(source)
    if not src then return end
    local meta = {}
    if type(item) == 'table' then meta = item.metadata or item.info or item end
    local extra = { ... }
    for _, v in ipairs(extra) do
        if type(v) == 'table' then meta = v.metadata or v.info or v break end
    end
    TriggerClientEvent('cm-gunstore:client:wearVest', src, type(meta) == 'table' and meta or {})
    return true
end
exports('UseVest', handleUseVest)

CreateThread(function()
    while not DB_READY do Wait(250) end
    Wait(500)
    local rows = MySQL.query.await('SELECT item_name, item_type FROM cm_gun_catalog', {}) or {}
    for _, row in ipairs(rows) do registerUsableThroughItemActions(row.item_name, row.item_type) end
    dbg(('registered %s usable catalog rows on start'):format(#rows))
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
        function() return inv:AddItem(src, itemName, amount, metadata, nil, 'cm_gunstore_purchase') end,
        function() return inv:AddItem(src, itemName, amount, metadata, 'cm_gunstore_purchase') end,
        function() return inv:AddItem(src, itemName, amount, metadata) end,
        function() return inv:AddItem(src, itemName, amount, false, metadata, 'cm_gunstore_purchase') end,
    }

    local lastErr = nil
    for _, fn in ipairs(attempts) do
        local ok, result, reason = pcall(fn)
        if ok and inventorySuccess(result) then return true end
        lastErr = reason or result or lastErr
    end

    return false, tostring(lastErr or 'inventory_full_or_unknown_item')
end

local function normalizeMoneyAccount(account)
    account = tostring(account or 'bank'):lower()
    if account == 'money' then account = 'cash' end
    if account ~= 'cash' and account ~= 'bank' then account = 'bank' end
    return account
end

local function playerdataMoneyAvailable()
    return GetResourceState('cm-playerdata') == 'started'
end

local function removeMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end

    account = normalizeMoneyAccount(account)
    reason = tostring(reason or 'cm_gunstore_purchase')

    if not playerdataMoneyAvailable() then
        return false, 'cm-playerdata wallet is not available.'
    end

    local pd = exports['cm-playerdata']

    -- Optional fast check. RemoveMoney is still the trusted final check.
    local canOk, canPay = pcall(function()
        return pd:CanAfford(src, account, amount)
    end)
    if canOk and canPay == false then
        return false, ('Not enough %s.'):format(account)
    end

    local ok, result = pcall(function()
        return pd:RemoveMoney(src, account, amount, reason)
    end)

    if ok and result == true then
        return true
    end

    return false, ('Not enough %s.'):format(account)
end

local function refundMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    account = normalizeMoneyAccount(account)
    reason = tostring(reason or 'cm_gunstore_refund')

    if not playerdataMoneyAvailable() then
        return false
    end

    local ok, result = pcall(function()
        return exports['cm-playerdata']:AddMoney(src, account, amount, reason)
    end)

    return ok and result == true
end

local function reserveStock(itemName, units)
    itemName = normalizeItemName(itemName)
    units = math.max(1, math.floor(tonumber(units) or 1))
    if itemName == '' then return false end
    local affected = MySQL.update.await(
        'UPDATE cm_gun_catalog SET stock = stock - ? WHERE LOWER(item_name) = ? AND stock >= ?',
        { units, itemName, units }
    )
    return affected and affected > 0
end

local function releaseStock(itemName, units)
    itemName = normalizeItemName(itemName)
    units = math.max(1, math.floor(tonumber(units) or 1))
    if itemName == '' then return false end
    MySQL.update.await(
        'UPDATE cm_gun_catalog SET stock = stock + ? WHERE LOWER(item_name) = ? AND stock >= 0',
        { units, itemName }
    )
    return true
end

-- One in-flight purchase per player. Prevents buy-spam from racing the stock
-- check against the stock decrement (buying past a limited stock) or double-
-- charging while the money/inventory exports yield.
local PurchaseLock = {}

AddEventHandler('playerDropped', function()
    if source then PurchaseLock[source] = nil end
end)

-- Require the player to actually be standing at a gun store instead of
-- triggering the buy event from anywhere on the map.
local function isNearShop(src)
    if not Config.Shops or #Config.Shops == 0 then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pcoords = GetEntityCoords(ped)
    local maxDist = tonumber(Config.PurchaseDistance) or 15.0
    for _, shop in ipairs(Config.Shops) do
        local c = shop.coords or shop.pedCoords
        if c then
            local sx = tonumber(c.x) or tonumber(c[1])
            local sy = tonumber(c.y) or tonumber(c[2])
            local sz = tonumber(c.z) or tonumber(c[3])
            if sx and sy and sz and #(pcoords - vector3(sx, sy, sz)) <= maxDist then
                return true
            end
        end
    end
    return false
end

math.randomseed(os.time())
local function makeSerial(src)
    return ('CMW-%s-%s-%04d'):format(os.date('!%Y%m%d%H%M%S'), tostring(src), math.random(0, 9999))
end

local function buildMetadata(src, row)
    row = row or {}
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
            damage = tonumber(row.damage) or 0,
            componentId = tonumber(row.component_id or row.componentId) or nil,
            drawableId = tonumber(row.drawable_id or row.drawableId) or nil,
            textureId = tonumber(row.texture_id or row.textureId) or 0,
            gender = row.gender
        }
    }

    if row.item_type == 'ammo' then
        local ammo = getAmmoDef(row.item_name)
        meta.category = 'ammo'
        meta.categoryType = 'ammo'
        meta.itemType = 'normal'
        meta.rarity = 'normal'
        meta.ammoType = row.item_name
        meta.ammoKey = row.ammo_key
        meta.pickupHash = row.pickup_hash
        meta.dropModel = row.drop_model
        meta.packSize = row.pack_size
        meta.stack = true
        if ammo then
            meta.ammoKey = ammo.ammoKey or ammo.ammo_key or meta.ammoKey
            meta.pickupHash = ammo.pickupHash or ammo.pickup_hash or meta.pickupHash
            meta.dropModel = ammo.dropModel or ammo.drop_model or meta.dropModel
        end
    elseif row.item_type == 'armor' then
        meta.category = 'armor'
        meta.categoryType = 'armor'
        meta.itemType = 'normal'
        meta.rarity = 'rare'
        meta.armorValue = tonumber(row.armor_value or row.armorValue) or 0
        meta.stack = false
        meta.usable = true
        meta.isWearableVest = tonumber(row.drawable_id or row.drawableId) ~= nil
        meta.componentType = 'component'
        meta.componentIndex = tonumber(row.component_id or row.componentId) or 9
        meta.componentId = tonumber(row.component_id or row.componentId) or 9
        meta.drawableId = tonumber(row.drawable_id or row.drawableId)
        meta.drawable = tonumber(row.drawable_id or row.drawableId)
        meta.textureId = tonumber(row.texture_id or row.textureId) or 0
        meta.texture = tonumber(row.texture_id or row.textureId) or 0
        meta.gender = row.gender or 'both'
    else
        local weapon = getWeaponDef(row.item_name ~= '' and row.item_name or row.weapon_hash)
        meta.category = 'weapon'
        meta.categoryType = 'weapon'
        meta.itemType = 'unique'
        meta.rarity = 'unique'
        meta.weaponHash = row.weapon_hash
        meta.weaponHashNumber = weapon and (weapon.weaponHashNumber or weapon.weapon_hash_number) or nil
        meta.weaponName = row.item_name
        meta.ammoType = row.ammo_item
        meta.ammoItem = row.ammo_item
        meta.damage = row.damage
        meta.magazineSize = row.magazine_size
        meta.serial = makeSerial(src)
        meta.durability = weapon and (weapon.durability or 100) or 100
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
    if not cmWeaponsRequired(src) then
        TriggerClientEvent('cm-gunstore:client:openCatalog', src, mode, getCatalog(admin))
        return
    end
    TriggerClientEvent('cm-gunstore:client:openCatalog', src, mode, getCatalog(admin))
end)

local function uniqueAppend(list, seen, value)
    value = tostring(value or ''):lower()
    if value == '' or seen[value] then return end
    seen[value] = true
    list[#list + 1] = value
end

local function buildWeaponPicker()
    local shopRows = getShopRowsByName('weapon')
    local list, groupList, seenGroups = {}, {}, {}
    for _, w in ipairs(allWeapons(true)) do
        local itemName = normalizeItemName(w.itemName or w.item_name)
        local shop = shopRows[itemName]
        local group = tostring(w.group or w.group_key or 'pistol'):lower()
        uniqueAppend(groupList, seenGroups, group)
        local status = shop and (shop.enabled and 'store' or 'hidden') or 'made'
        list[#list + 1] = {
            hash = tostring(w.weaponHash or w.weapon_hash or ''),
            weapon_hash = tostring(w.weaponHash or w.weapon_hash or ''),
            item_name = itemName,
            label = tostring(w.label or itemName),
            group = group,
            ammo = normalizeItemName(w.ammoItem or w.ammo_item),
            ammo_item = normalizeItemName(w.ammoItem or w.ammo_item),
            image = (shop and shop.image ~= '' and shop.image) or tostring(w.image or ''),
            price = configPrice(itemName, shop and tonumber(shop.price) or 0),
            damage = tonumber(w.damage) or 0,
            magazine_size = tonumber(w.magazineSize or w.magazine_size) or 0,
            stock = shop and tonumber(shop.stock) or -1,
            enabled = shop and shop.enabled or false,
            description = (shop and shop.description ~= '' and shop.description) or tostring(w.description or ''),
            status = status,
        }
    end
    table.sort(groupList)
    if #groupList == 0 then groupList = Config.WeaponGroups or { 'pistol', 'smg', 'rifle', 'shotgun', 'sniper', 'heavy' } end
    return list, groupList
end

local function buildAmmoPicker()
    local shopRows = getShopRowsByName('ammo')
    local list, groupList, seenGroups = {}, {}, {}
    for _, a in ipairs(allAmmo(true)) do
        local itemName = normalizeItemName(a.itemName or a.item_name)
        local shop = shopRows[itemName]
        local group = tostring(a.ammoKey or a.ammo_key or 'ammo'):lower()
        uniqueAppend(groupList, seenGroups, group)
        local status = shop and (shop.enabled and 'store' or 'hidden') or 'made'
        list[#list + 1] = {
            item_name = itemName,
            label = tostring(a.label or itemName),
            group = group,
            ammo_key = group,
            pickup_hash = tonumber(a.pickupHash or a.pickup_hash) or 0,
            drop_model = tostring(a.dropModel or a.drop_model or ''),
            pack_size = tonumber(a.packSize or a.pack_size) or 1,
            image = (shop and shop.image ~= '' and shop.image) or tostring(a.image or ''),
            price = configPrice(itemName, shop and tonumber(shop.price) or 0),
            stock = shop and tonumber(shop.stock) or -1,
            enabled = shop and shop.enabled or false,
            description = (shop and shop.description ~= '' and shop.description) or tostring(a.description or ''),
            status = status,
        }
    end
    table.sort(groupList)
    if #groupList == 0 then groupList = { 'pistol', 'smg', 'rifle', 'mg', 'shotgun', 'sniper', 'heavy' } end
    return list, groupList
end

RegisterNetEvent('cm-gunstore:server:requestWeaponPicker', function()
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have permission.', 'error') end
    if not cmWeaponsRequired(src) then return end
    local list, groups = buildWeaponPicker()
    TriggerClientEvent('cm-gunstore:client:weaponPicker', src, list, groups)
end)

RegisterNetEvent('cm-gunstore:server:requestAmmoPicker', function()
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have permission.', 'error') end
    if not cmWeaponsRequired(src) then return end
    local list, groups = buildAmmoPicker()
    TriggerClientEvent('cm-gunstore:client:ammoPicker', src, list, groups)
end)

local function saveStoreEntry(src, itemType, sourceRow, data)
    data = type(data) == 'table' and data or {}
    itemType = tostring(itemType or ''):lower()
    local itemName = normalizeItemName(sourceRow.itemName or sourceRow.item_name)
    if itemName == '' then return false, 'bad_item_name' end

    local cfg = configStoreEntry(itemName)
    if Config.RequireStoreConfigPrice == true and not cfg then
        return false, 'missing_config_price_add_item_to_Config.StoreCatalog'
    end
    local price = configPrice(itemName, data.price)
    local stock = math.floor(tonumber(data.stock) or configDefaultStock(itemName, -1))
    local enabled = data.enabled ~= nil and boolInt(data.enabled) or boolInt(configDefaultEnabled(itemName, false))
    local image = tostring(data.image or sourceRow.image or ''):sub(1, 255)
    local description = tostring(data.description or sourceRow.description or ''):sub(1, 255)
    local label = tostring(sourceRow.label or itemName):sub(1, 120)
    local weaponHash = ''
    local ammoItem = ''
    local ammoKey = ''
    local pickupHash = 0
    local dropModel = ''
    local packSize = 1
    local damage = 0
    local magazineSize = 0

    if itemType == 'weapon' then
        weaponHash = tostring(sourceRow.weaponHash or sourceRow.weapon_hash or ''):upper():sub(1, 80)
        ammoItem = normalizeItemName(sourceRow.ammoItem or sourceRow.ammo_item)
        damage = math.max(0, math.floor(tonumber(sourceRow.damage) or 0))
        magazineSize = math.max(0, math.floor(tonumber(sourceRow.magazineSize or sourceRow.magazine_size) or 0))
    elseif itemType == 'ammo' then
        ammoKey = tostring(sourceRow.ammoKey or sourceRow.ammo_key or ''):lower():sub(1, 40)
        pickupHash = tonumber(sourceRow.pickupHash or sourceRow.pickup_hash) or 0
        dropModel = tostring(sourceRow.dropModel or sourceRow.drop_model or ''):sub(1, 80)
        packSize = math.max(1, math.floor(tonumber(sourceRow.packSize or sourceRow.pack_size) or 1))
    else
        return false, 'unsupported_store_item_type'
    end

    MySQL.insert.await([[
        INSERT INTO cm_gun_catalog
            (item_name, item_type, label, weapon_hash, ammo_item, ammo_key, pickup_hash, drop_model, pack_size, armor_value, damage, magazine_size, stock, price, enabled, image, description, sort_order)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, 999)
        ON DUPLICATE KEY UPDATE
            item_type = VALUES(item_type), label = VALUES(label), weapon_hash = VALUES(weapon_hash), ammo_item = VALUES(ammo_item),
            ammo_key = VALUES(ammo_key), pickup_hash = VALUES(pickup_hash), drop_model = VALUES(drop_model), pack_size = VALUES(pack_size),
            damage = VALUES(damage), magazine_size = VALUES(magazine_size), stock = VALUES(stock), price = VALUES(price), enabled = VALUES(enabled),
            image = VALUES(image), description = VALUES(description)
    ]], { itemName, itemType, label, weaponHash, ammoItem, ammoKey, pickupHash, dropModel, packSize, damage, magazineSize, stock, price, enabled, image, description })

    registerUsableThroughItemActions(itemName, itemType)
    return true
end

RegisterNetEvent('cm-gunstore:server:createWeaponFromPicker', function(data)
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have permission.', 'error') end
    if not cmWeaponsRequired(src) then return end
    data = type(data) == 'table' and data or {}
    local key = data.item_name or data.itemName or data.hash or data.weapon_hash or data.weaponHash
    local def = getWeaponDef(key) or getWeaponDef(data.weapon_hash or data.weaponHash or data.hash) or fallbackWeaponDefFromPicker(data)
    if not def then
        return notify(src, 'Weapon was not found in cm-weapons list. Open /cmweaponadmin, save the weapon once, then restart cm-weapons + cm-gunstore.', 'error')
    end
    local ok, err = saveStoreEntry(src, 'weapon', def, data)
    notify(src, ok and 'Weapon added/updated in gun store.' or ('Weapon store save failed: ' .. tostring(err)), ok and 'success' or 'error')
    TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', getCatalog(true))
    local list, groups = buildWeaponPicker()
    TriggerClientEvent('cm-gunstore:client:weaponPicker', src, list, groups)
end)

RegisterNetEvent('cm-gunstore:server:createAmmoFromPicker', function(data)
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have permission.', 'error') end
    if not cmWeaponsRequired(src) then return end
    data = type(data) == 'table' and data or {}
    local key = data.item_name or data.itemName
    local def = getAmmoDef(key) or fallbackAmmoDefFromPicker(data)
    if not def then
        return notify(src, 'Ammo was not found in cm-weapons list. Open /cmweaponadmin, save the ammo once, then restart cm-weapons + cm-gunstore.', 'error')
    end
    local ok, err = saveStoreEntry(src, 'ammo', def, data)
    notify(src, ok and 'Ammo added/updated in gun store.' or ('Ammo store save failed: ' .. tostring(err)), ok and 'success' or 'error')
    TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', getCatalog(true))
    local list, groups = buildAmmoPicker()
    TriggerClientEvent('cm-gunstore:client:ammoPicker', src, list, groups)
end)

local function processPurchase(src, data)
    local itemName = normalizeItemName(data.item_name)
    local method = tostring(data.method or 'bank'):lower() == 'cash' and 'cash' or 'bank'
    local account = normalizeMoneyAccount(Config.Accounts and Config.Accounts[method] or method)

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
    if row.missing_source == true and (row.item_type == 'weapon' or row.item_type == 'ammo') then
        notify(src, ('%s has no valid weapon/ammo snapshot. Add it from /cmweaponadmin, then set it in store again from /gunadmin.'):format(row.label or itemName), 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end

    local quantity = math.max(1, math.floor(tonumber(data.quantity or data.amount) or 1))
    if row.item_type == 'ammo' then
        local qCfg = Config.AmmoQuantity or {}
        quantity = math.max(tonumber(qCfg.min) or 1, math.min(tonumber(qCfg.max) or 999, quantity))
    else
        quantity = 1
    end

    -- Ammo amount is rounds added to inventory. Because cm-weapons ammo packSize is 1,
    -- players can buy exactly 1 round or any quantity up to Config.AmmoQuantity.max.
    local inventoryAmount = row.item_type == 'ammo' and (math.max(1, tonumber(row.pack_size) or 1) * quantity) or 1
    local stockUnits = row.item_type == 'ammo' and quantity or 1
    local limitedStock = tonumber(row.stock) and tonumber(row.stock) >= 0

    if limitedStock and tonumber(row.stock) == 0 then
        notify(src, 'This item is out of stock.', 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end

    local reserved = false
    if limitedStock then
        reserved = reserveStock(itemName, stockUnits)
        if not reserved then
            notify(src, 'This item is out of stock.', 'error')
            TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
            return
        end
    end

    local unitPrice = configPrice(itemName, row.price)
    local total = math.max(0, math.floor(unitPrice * quantity))
    local paid, payErr = removeMoney(src, account, total, 'gunstore_buy_' .. itemName)
    if not paid then
        if reserved then releaseStock(itemName, stockUnits) end
        notify(src, tostring(payErr or 'You do not have enough money.'), 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end

    local metadata = buildMetadata(src, row)
    local added, err = addInventoryItem(src, row.item_name, inventoryAmount, metadata)
    if not added then
        refundMoney(src, account, total, 'gunstore_refund_' .. itemName)
        if reserved then releaseStock(itemName, stockUnits) end
        notify(src, ('Could not add item to inventory: %s. Money refunded.'):format(tostring(err)), 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end

    notify(src, ('Purchased %s%s. Check your inventory.'):format(row.label, quantity > 1 and (' x' .. quantity) or ''), 'success')
    TriggerClientEvent('cm-gunstore:client:purchaseResult', src, true)
end

RegisterNetEvent('cm-gunstore:server:buyItem', function(data)
    local src = source
    data = type(data) == 'table' and data or {}

    if PurchaseLock[src] then
        notify(src, 'Please wait for your previous purchase to finish.', 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end
    if not isNearShop(src) then
        notify(src, 'You are too far from a gun store.', 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
        return
    end

    PurchaseLock[src] = true
    local ok, err = pcall(processPurchase, src, data)
    PurchaseLock[src] = nil

    if not ok then
        print(('[%s] buyItem error: %s'):format(RESOURCE, tostring(err)))
        notify(src, 'Purchase failed due to a server error.', 'error')
        TriggerClientEvent('cm-gunstore:client:purchaseResult', src, false)
    end
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
    local ok = SaveResourceFile(RESOURCE, file, decoded, #decoded)
    if not ok then return nil, 'save_failed' end
    return ('nui://%s/%s'):format(RESOURCE, file)
end

local function syncArmorToCmItems(src, itemName, label, image, description, armorValue, componentId, drawableId, textureId, gender, imageData)
    if GetResourceState(itemsResource()) ~= 'started' then
        if tonumber(src or 0) > 0 then
            notify(src, 'Warning: cm-items is not started, so armor was saved only in gun store.', 'error')
        else
            dbg('cm-items is not started; skipped armor sync during config catalog sync')
        end
        return image
    end

    local metadata = {
        gender = gender,
        componentIndex = componentId,
        componentId = componentId,
        drawableId = drawableId,
        textureId = textureId,
        armorValue = armorValue
    }
    local def = {
        name = itemName,
        label = label,
        category = 'armor',
        itemType = 'rare',
        equipmentSlot = 'bodyarmor',
        armorValue = armorValue,
        weight = 2500,
        stack = false,
        usable = true,
        description = description,
        metadata = metadata,
        enabled = true,
        createdBy = ('cm-gunstore:%s'):format(src),
    }
    if (not image or image == '') and tostring(imageData or '') ~= '' then def.imageData = imageData
    elseif image and image ~= '' then def.image = image end

    local okCall, okDef, resOrErr = pcall(function()
        return exports[itemsResource()]:SaveCatalogItem(def)
    end)
    if okCall and okDef and type(resOrErr) == 'table' and resOrErr.image then
        image = resOrErr.image
    elseif not okCall or not okDef then
        local err = okCall and resOrErr or okDef
        dbg(('cm-items SaveCatalogItem armor failed: %s'):format(tostring(err)))
        notify(src, ('Warning: could not register armor in cm-items (%s).'):format(tostring(err)), 'error')
    end
    return image
end


local SyncCatalogBusy = false
local LastConfigSync = 0

syncConfigCatalog = function(force)
    if not DB_READY then return false end
    local now = os.time()
    if force ~= true and (now - LastConfigSync) < 5 then return true end
    if SyncCatalogBusy then return false end
    SyncCatalogBusy = true

    local ok, err = pcall(function()
        for _, entry in ipairs(Config.StoreCatalog or {}) do
            local itemName = normalizeItemName(entry.itemName or entry.item_name)
            if itemName ~= '' then
                local itemType = tostring(entry.itemType or entry.item_type or ''):lower()
                local def = nil
                if itemType == 'ammo' then
                    def = getAmmoDef(itemName) or findAmmoDefFromAll(itemName)
                elseif itemType == 'weapon' then
                    def = getWeaponDef(itemName) or findWeaponDefFromAll(itemName)
                elseif itemType == 'armor' then
                    -- handled below
                else
                    def = getAmmoDef(itemName) or findAmmoDefFromAll(itemName)
                    if def then
                        itemType = 'ammo'
                    else
                        def = getWeaponDef(itemName) or findWeaponDefFromAll(itemName)
                        if def then itemType = 'weapon' end
                    end
                    if itemName == normalizeItemName((Config.DefaultArmor or {}).itemName) then itemType = 'armor' end
                end

                local price = configPrice(itemName, entry.price)
                local stock = math.floor(tonumber(entry.stock) or -1)
                local enabled = boolInt(entry.enabled ~= nil and entry.enabled or false)
                local sortOrder = configSortOrder(itemName, entry.sortOrder or entry.sort_order or 999)

                if itemType == 'weapon' and def then
                    MySQL.insert.await([[
                        INSERT INTO cm_gun_catalog
                            (item_name, item_type, label, weapon_hash, ammo_item, ammo_key, pickup_hash, drop_model, pack_size, armor_value, damage, magazine_size, stock, price, enabled, image, description, sort_order)
                        VALUES (?, 'weapon', ?, ?, ?, '', 0, '', 1, 0, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON DUPLICATE KEY UPDATE
                            item_type = 'weapon', label = VALUES(label), weapon_hash = VALUES(weapon_hash), ammo_item = VALUES(ammo_item),
                            damage = VALUES(damage), magazine_size = VALUES(magazine_size), stock = VALUES(stock), enabled = VALUES(enabled), price = VALUES(price), sort_order = VALUES(sort_order),
                            image = CASE WHEN image IS NULL OR image = '' THEN VALUES(image) ELSE image END,
                            description = VALUES(description)
                    ]], { itemName, tostring(def.label or itemName), tostring(def.weaponHash or def.weapon_hash or ''), normalizeItemName(def.ammoItem or def.ammo_item), tonumber(def.damage) or 0, tonumber(def.magazineSize or def.magazine_size) or 0, stock, price, enabled, tostring(def.image or ''), tostring(def.description or ''), sortOrder })
                elseif itemType == 'ammo' and def then
                    MySQL.insert.await([[
                        INSERT INTO cm_gun_catalog
                            (item_name, item_type, label, weapon_hash, ammo_item, ammo_key, pickup_hash, drop_model, pack_size, armor_value, damage, magazine_size, stock, price, enabled, image, description, sort_order)
                        VALUES (?, 'ammo', ?, '', '', ?, ?, ?, ?, 0, 0, 0, ?, ?, ?, ?, ?, ?)
                        ON DUPLICATE KEY UPDATE
                            item_type = 'ammo', label = VALUES(label), ammo_key = VALUES(ammo_key), pickup_hash = VALUES(pickup_hash),
                            drop_model = VALUES(drop_model), pack_size = VALUES(pack_size), stock = VALUES(stock), enabled = VALUES(enabled), price = VALUES(price), sort_order = VALUES(sort_order),
                            image = CASE WHEN image IS NULL OR image = '' THEN VALUES(image) ELSE image END,
                            description = VALUES(description)
                    ]], { itemName, tostring(def.label or itemName), tostring(def.ammoKey or def.ammo_key or ''), tonumber(def.pickupHash or def.pickup_hash) or 0, tostring(def.dropModel or def.drop_model or ''), math.max(1, tonumber(def.packSize or def.pack_size) or 1), stock, price, enabled, tostring(def.image or ''), tostring(def.description or ''), sortOrder })
                elseif itemType == 'armor' then
                    local armor = Config.DefaultArmor or {}
                    local label = tostring(armor.label or entry.label or 'Armor Vest')
                    local armorValue = math.max(0, math.min(100, math.floor(tonumber(armor.armorValue or armor.armor_value) or 50)))
                    local image = tostring(armor.image or entry.image or 'images/armor_light.svg')
                    local description = tostring(armor.description or entry.description or 'Standard body armor vest.')
                    local componentId = math.floor(tonumber(armor.componentId or armor.component_id) or 9)
                    local drawableId = armor.drawableId or armor.drawable_id
                    drawableId = drawableId ~= nil and math.floor(tonumber(drawableId) or -1) or nil
                    if drawableId and drawableId < 0 then drawableId = nil end
                    local textureId = math.max(0, math.floor(tonumber(armor.textureId or armor.texture_id) or 0))
                    local gender = tostring(armor.gender or 'both'):lower():sub(1, 12)
                    if gender ~= 'male' and gender ~= 'female' and gender ~= 'both' then gender = 'both' end

                    image = syncArmorToCmItems(0, itemName, label, image, description, armorValue, componentId, drawableId, textureId, gender, nil)
                    MySQL.insert.await([[
                        INSERT INTO cm_gun_catalog
                            (item_name, item_type, label, weapon_hash, ammo_item, pack_size, armor_value, damage, magazine_size, stock, price, enabled, image, description, sort_order, component_id, drawable_id, texture_id, gender)
                        VALUES (?, 'armor', ?, '', '', 1, ?, 0, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON DUPLICATE KEY UPDATE
                            item_type = 'armor', label = VALUES(label), armor_value = VALUES(armor_value), stock = VALUES(stock), enabled = VALUES(enabled), price = VALUES(price), sort_order = VALUES(sort_order),
                            image = CASE WHEN image IS NULL OR image = '' THEN VALUES(image) ELSE image END,
                            description = VALUES(description), component_id = VALUES(component_id), drawable_id = VALUES(drawable_id), texture_id = VALUES(texture_id), gender = VALUES(gender)
                    ]], { itemName, label, armorValue, stock, price, enabled, image, description, sortOrder, componentId, drawableId, textureId, gender })
                    registerUsableThroughItemActions(itemName, 'armor')
                end
            end
        end

        if Config.StrictStoreCatalog == true then
            local names = {}
            for _, entry in ipairs(Config.StoreCatalog or {}) do
                local n = normalizeItemName(entry.itemName or entry.item_name)
                if n ~= '' then names[#names + 1] = n end
            end
            if #names > 0 then
                local qs = {}
                for _ = 1, #names do qs[#qs + 1] = '?' end
                MySQL.update.await(('UPDATE cm_gun_catalog SET enabled = 0 WHERE item_name NOT IN (%s)'):format(table.concat(qs, ',')), names)
            end
        end
    end)

    LastConfigSync = now
    SyncCatalogBusy = false
    if not ok then print(('[%s] config catalog sync failed: %s'):format(RESOURCE, tostring(err))) end
    return ok
end

CreateThread(function()
    while not DB_READY do Wait(250) end
    if Config.SyncConfigCatalogOnStart ~= false then
        for _ = 1, 20 do
            if GetResourceState(weaponsResource()) == 'started' then break end
            Wait(500)
        end
        syncConfigCatalog(true)
    end
end)

RegisterNetEvent('cm-gunstore:server:adminCreateItem', function(data, explicitSrc)
    local src = explicitSrc or source
    if not isAdmin(src) then return notify(src, 'You do not have permission to create gun store items.', 'error') end
    data = type(data) == 'table' and data or {}
    local itemType = tostring(data.item_type or data.itemType or 'armor'):lower()
    if itemType == 'weapon' or itemType == 'ammo' then
        notify(src, 'Gun and ammo creation is now managed in /cmweaponadmin. Gun store only sells them.', 'error')
        return
    end
    if itemType ~= 'armor' then itemType = 'armor' end

    local label = tostring(data.label or ''):sub(1, 120)
    local itemName = normalizeItemName(data.item_name or data.itemName or label)
    if itemName == '' then itemName = 'armor_' .. os.time() end
    if not itemName:find('^armor_') then itemName = ('armor_%s'):format(itemName) end
    if label == '' then label = itemName:gsub('_', ' '):gsub('^%l', string.upper) end

    local image = tostring(data.image or ''):sub(1, 255)
    if tostring(data.imageData or '') ~= '' then
        local saved, err = saveDataImage(data.imageData, itemName)
        if saved then image = saved else dbg(('image save failed: %s'):format(tostring(err))) end
    end

    local price = math.max(0, math.floor(tonumber(data.price) or 0))
    local stock = math.floor(tonumber(data.stock) or -1)
    local enabled = boolInt(data.enabled)
    local description = tostring(data.description or ''):sub(1, 255)
    local sortOrder = math.floor(tonumber(data.sort_order or data.sortOrder) or 999)
    local armorValue = math.max(0, math.min(100, math.floor(tonumber(data.armor_value or data.armorValue) or 0)))
    local componentId = math.floor(tonumber(data.component_id or data.componentId) or 9)
    local drawableId = data.drawable_id or data.drawableId
    drawableId = drawableId ~= nil and math.floor(tonumber(drawableId) or -1) or nil
    if drawableId and drawableId < 0 then drawableId = nil end
    local textureId = math.max(0, math.floor(tonumber(data.texture_id or data.textureId) or 0))
    local gender = tostring(data.gender or 'both'):lower():sub(1, 12)
    if gender ~= 'male' and gender ~= 'female' and gender ~= 'both' then gender = 'both' end

    image = syncArmorToCmItems(src, itemName, label, image, description, armorValue, componentId, drawableId, textureId, gender, data.imageData)

    MySQL.insert.await([[
        INSERT INTO cm_gun_catalog
            (item_name, item_type, label, weapon_hash, ammo_item, pack_size, armor_value, damage, magazine_size, stock, price, enabled, image, description, sort_order, component_id, drawable_id, texture_id, gender)
        VALUES
            (?, 'armor', ?, '', '', 1, ?, 0, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            item_type = 'armor', label = VALUES(label), armor_value = VALUES(armor_value), stock = VALUES(stock), price = VALUES(price),
            enabled = VALUES(enabled), image = VALUES(image), description = VALUES(description), sort_order = VALUES(sort_order),
            component_id = VALUES(component_id), drawable_id = VALUES(drawable_id), texture_id = VALUES(texture_id), gender = VALUES(gender)
    ]], { itemName, label, armorValue, stock, price, enabled, image, description, sortOrder, componentId, drawableId, textureId, gender })

    registerUsableThroughItemActions(itemName, 'armor')
    notify(src, ('Created %s.'):format(label), 'success')
    TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', getCatalog(true))
end)

RegisterNetEvent('cm-gunstore:server:adminSaveImage', function(data)
    local src = source
    if not isAdmin(src) then return end
    data = type(data) == 'table' and data or {}
    local itemName = normalizeItemName(data.item_name)
    if itemName == '' then return end
    local saved, err = saveDataImage(data.imageData, itemName)
    if not saved then return notify(src, ('Image save failed: %s'):format(tostring(err or 'unknown')), 'error') end
    MySQL.update.await('UPDATE cm_gun_catalog SET image = ? WHERE LOWER(item_name) = ?', { saved, itemName })
    local row = getCatalogRowByName(itemName)
    if row and row.item_type == 'armor' then
        syncArmorToCmItems(src, row.item_name, row.label, saved, row.description, row.armor_value, row.component_id, row.drawable_id, row.texture_id, row.gender, nil)
    else
        notify(src, 'Image saved to gun store only. Weapon/ammo base images are managed in /cmweaponadmin.', 'info')
    end
    TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', getCatalog(true))
end)

RegisterNetEvent('cm-gunstore:server:adminDeleteItem', function(data)
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have permission to delete gun store items.', 'error') end
    data = type(data) == 'table' and data or {}
    local itemName = normalizeItemName(data.item_name or data.itemName)
    if itemName == '' then return notify(src, 'Invalid item.', 'error') end
    local row = getCatalogRowByName(itemName)
    if not row then return notify(src, 'Catalog item not found.', 'error') end

    local affected = MySQL.update.await('DELETE FROM cm_gun_catalog WHERE LOWER(item_name) = ?', { itemName })
    if not affected or affected < 1 then return notify(src, 'Delete failed. Item was not removed.', 'error') end

    if row.item_type == 'armor' and GetResourceState(itemsResource()) == 'started' then
        pcall(function() exports[itemsResource()]:DeleteCatalogItem(itemName) end)
        notify(src, ('Deleted %s from gun store and cm-items armor catalog.'):format(row.label or itemName), 'success')
    else
        notify(src, ('Removed %s from gun store only. Weapon/ammo definition remains in cm-weapons.'):format(row.label or itemName), 'success')
    end

    TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', getCatalog(true))
    local weapons, weaponGroups = buildWeaponPicker()
    TriggerClientEvent('cm-gunstore:client:weaponPicker', src, weapons, weaponGroups)
    local ammo, ammoGroups = buildAmmoPicker()
    TriggerClientEvent('cm-gunstore:client:ammoPicker', src, ammo, ammoGroups)
end)

RegisterNetEvent('cm-gunstore:server:adminSaveItem', function(data)
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have permission to edit gun store catalog.', 'error') end
    data = type(data) == 'table' and data or {}
    local itemName = normalizeItemName(data.item_name)
    if itemName == '' then return notify(src, 'Invalid item.', 'error') end

    local existing = getCatalogRowByName(itemName)
    if not existing then return notify(src, 'Catalog item not found.', 'error') end
    local itemType = tostring(existing.item_type or 'weapon'):lower()
    local price = math.max(0, math.floor(tonumber(data.price) or existing.price or 0))
    local enabled = boolInt(data.enabled)
    local stock = math.floor(tonumber(data.stock) or existing.stock or -1)
    local image = tostring(data.image or existing.image or ''):sub(1, 255)
    local description = tostring(data.description or existing.description or ''):sub(1, 255)

    if itemType == 'weapon' or itemType == 'ammo' then
        -- Price/image/description are config/cm-weapons owned. Gun admin can only set store visibility and stock.
        price = configPrice(itemName, existing.price)
        MySQL.update.await('UPDATE cm_gun_catalog SET price = ?, enabled = ?, stock = ? WHERE LOWER(item_name) = ?', {
            price, enabled, stock, itemName
        })
        notify(src, ('Saved stock/visibility for %s. Price is loaded from config.'):format(existing.label or itemName), 'success')
        TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', getCatalog(true))
        return
    end

    local label = tostring(data.label or existing.label or ''):sub(1, 120)
    if label == '' then label = itemName end
    local armorValue = math.max(0, math.min(100, math.floor(tonumber(data.armor_value or data.armorValue) or 0)))
    local componentId = math.floor(tonumber(data.component_id or data.componentId) or 9)
    local drawableId = data.drawable_id or data.drawableId
    drawableId = drawableId ~= nil and math.floor(tonumber(drawableId) or -1) or nil
    if drawableId and drawableId < 0 then drawableId = nil end
    local textureId = math.max(0, math.floor(tonumber(data.texture_id or data.textureId) or 0))
    local gender = tostring(data.gender or 'both'):lower():sub(1, 12)
    if gender ~= 'male' and gender ~= 'female' and gender ~= 'both' then gender = 'both' end

    image = syncArmorToCmItems(src, itemName, label, image, description, armorValue, componentId, drawableId, textureId, gender, nil)
    MySQL.update.await([[
        UPDATE cm_gun_catalog
        SET label = ?, price = ?, enabled = ?, image = ?, description = ?, armor_value = ?, stock = ?, component_id = ?, drawable_id = ?, texture_id = ?, gender = ?
        WHERE LOWER(item_name) = ?
    ]], { label, price, enabled, image, description, armorValue, stock, componentId, drawableId, textureId, gender, itemName })

    notify(src, ('Saved %s.'):format(label), 'success')
    TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', getCatalog(true))
end)


RegisterCommand('gunstoresync', function(src)
    if src ~= 0 and not isAdmin(src) then return notify(src, 'You do not have permission to sync gun store.', 'error') end
    local ok = syncConfigCatalog(true)
    local rows = getCatalog(true)
    local counts = { weapon = 0, ammo = 0, armor = 0, enabled = 0 }
    for _, row in ipairs(rows or {}) do
        local t = tostring(row.item_type or ''):lower()
        if counts[t] ~= nil then counts[t] = counts[t] + 1 end
        if row.enabled == true then counts.enabled = counts.enabled + 1 end
    end
    notify(src, ok and ('Gun store synced from config | weapons=%s ammo=%s armor=%s enabled=%s'):format(counts.weapon, counts.ammo, counts.armor, counts.enabled) or 'Gun store sync failed. Check server console.', ok and 'success' or 'error')
    if src ~= 0 then TriggerClientEvent('cm-gunstore:client:openCatalog', src, 'admin', rows) end
end, false)

RegisterCommand(Config.AdminCommand or 'gunadmin', function(src)
    if src == 0 then
        print('[cm-gunstore] /gunadmin can only be used in-game.')
        return
    end
    if not isAdmin(src) then return notify(src, 'You do not have permission to use gun admin.', 'error') end
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
-- WEARABLE VEST INTEGRATION WITH nv_cloth
--========================================================
exports('ReceiveArmorImage', function(src, payload)
    src = tonumber(src)
    payload = type(payload) == 'table' and payload or {}
    if not src or not isAdmin(src) then return false end
    TriggerClientEvent('cm-gunstore:client:prefillArmor', src, payload)
    return true
end)

RegisterNetEvent('cm-gunstore:server:armorImageReady', function(src, payload)
    src = tonumber(src) or source
    payload = type(payload) == 'table' and payload or {}
    if not src or not isAdmin(src) then return end
    TriggerClientEvent('cm-gunstore:client:prefillArmor', src, payload)
end)

RegisterNetEvent('cm-gunstore:server:openArmorCapture', function()
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have permission to capture vests.', 'error') end
    if GetResourceState('nv_cloth') ~= 'started' then
        notify(src, 'nv_cloth is not started; cannot open the vest capture studio.', 'error')
        return
    end
    TriggerClientEvent('nvCloth:client:openArmorAdminPanel', src)
end)

RegisterNetEvent('cm-gunstore:server:vestUsed', function()
    -- placeholder for future server-side validation/logging
end)
