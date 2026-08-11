local RESOURCE = GetCurrentResourceName()
local DB_READY = false
local CACHE_READY = false
local LAST_CACHE_LOAD = 0

CMWeapons = CMWeapons or {
    Ammo = {},
    Weapons = {},
    AmmoList = {},
    WeaponList = {}
}

local function log(message)
    print(('[CM-WEAPONS] %s'):format(tostring(message)))
end

local function dbg(message)
    if Config.Debug then log(message) end
end

local function notify(src, message, typ)
    if src == 0 then
        log(message)
        return
    end
    TriggerClientEvent('cm-hud:client:notify', src, tostring(message or ''), typ or 'info')
end

local function isAdmin(src)
    if src == 0 then return true end
    -- Only the weapon-admin ace or the specific admin command ace grant access.
    -- The bare 'command' ace is granted very broadly on many servers, so it must
    -- NOT be a fallback here or ordinary players could edit the weapon catalog.
    return IsPlayerAceAllowed(src, Config.AdminAce or 'cm.weapons.admin')
        or IsPlayerAceAllowed(src, 'command.' .. (Config.AdminCommand or 'cmweaponadmin'))
end

local function boolInt(value, default)
    if value == nil then return default and 1 or 0 end
    if value == true or value == 1 or value == '1' or value == 'true' or value == 'yes' or value == 'on' then return 1 end
    return 0
end

local function normalizeItemName(name)
    name = tostring(name or ''):lower():gsub('%s+', '_'):gsub('[^a-z0-9_%-%.]', '_'):gsub('_+', '_')
    name = name:gsub('^_+', ''):gsub('_+$', '')
    return name
end


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

local function safeFileSlug(value, fallback)
    value = normalizeItemName(value):gsub('%.', '_')
    if value == '' then value = fallback or ('item_' .. os.time()) end
    return value:sub(1, 80)
end

local function saveDataImage(dataUri, itemName, folder)
    dataUri = tostring(dataUri or '')
    if dataUri == '' then return nil, 'no_image_data' end
    local mime, encoded = dataUri:match('^data:(image/%w+);base64,(.+)$')
    if not encoded or encoded == '' then return nil, 'bad_image_data' end
    local ext = (mime == 'image/jpeg' or mime == 'image/jpg') and 'jpg' or (mime == 'image/webp' and 'webp' or 'png')
    local safe = safeFileSlug(itemName, 'weapon_item')
    folder = tostring(folder or 'custom'):gsub('[^a-z0-9_%-]', '')
    if folder == '' then folder = 'custom' end
    local file = ('web/images/custom/%s_%s_%s.%s'):format(folder, safe, os.time(), ext)
    local decoded = base64Decode(encoded)
    if not decoded or #decoded < 32 then return nil, 'empty_image_data' end
    local ok = SaveResourceFile(RESOURCE, file, decoded, #decoded)
    if not ok then return nil, 'save_failed' end
    return ('nui://%s/%s'):format(RESOURCE, file)
end

local function getPickupHashForAmmoKey(ammoKey)
    ammoKey = tostring(ammoKey or ''):lower()
    return tonumber(Config.AmmoPickupHashes and Config.AmmoPickupHashes[ammoKey]) or 0
end

local function getDropModelForAmmoKey(ammoKey)
    ammoKey = tostring(ammoKey or ''):lower()
    return (Config.AmmoDropModels and Config.AmmoDropModels[ammoKey]) or 'prop_ld_ammo_pack_01'
end

local function weaponHashNumber(hashName)
    hashName = tostring(hashName or '')
    if hashName == '' then return 0 end
    local ok, value = pcall(function()
        if GetHashKey then return GetHashKey(hashName) end
        if joaat then return joaat(hashName) end
        return 0
    end)
    return ok and tonumber(value) or 0
end

local function rowToAmmo(row)
    row = row or {}
    local ammoKey = tostring(row.ammo_key or row.ammoKey or 'pistol'):lower()
    local pickupHash = tonumber(row.pickup_hash or row.pickupHash) or getPickupHashForAmmoKey(ammoKey)
    return {
        itemName = normalizeItemName(row.item_name or row.itemName),
        item_name = normalizeItemName(row.item_name or row.itemName),
        label = tostring(row.label or row.item_name or 'Ammo'),
        ammoKey = ammoKey,
        ammo_key = ammoKey,
        pickupHash = pickupHash,
        pickup_hash = pickupHash,
        dropModel = tostring(row.drop_model or row.dropModel or getDropModelForAmmoKey(ammoKey)),
        drop_model = tostring(row.drop_model or row.dropModel or getDropModelForAmmoKey(ammoKey)),
        packSize = math.max(1, math.floor(tonumber(row.pack_size or row.packSize) or 1)),
        pack_size = math.max(1, math.floor(tonumber(row.pack_size or row.packSize) or 1)),
        price = math.max(0, math.floor(tonumber(row.price) or 0)),
        weight = math.max(0, math.floor(tonumber(row.weight) or 0)),
        stack = boolInt(row.stack, true) == 1,
        enabled = boolInt(row.enabled, true) == 1,
        image = tostring(row.image or ''),
        description = tostring(row.description or ''),
        sortOrder = math.floor(tonumber(row.sort_order or row.sortOrder) or 0),
        sort_order = math.floor(tonumber(row.sort_order or row.sortOrder) or 0)
    }
end

local function rowToWeapon(row)
    row = row or {}
    local weaponHash = tostring(row.weapon_hash or row.weaponHash or ''):upper()
    return {
        itemName = normalizeItemName(row.item_name or row.itemName),
        item_name = normalizeItemName(row.item_name or row.itemName),
        label = tostring(row.label or row.item_name or 'Weapon'),
        weaponHash = weaponHash,
        weapon_hash = weaponHash,
        weaponHashNumber = tonumber(row.weapon_hash_number or row.weaponHashNumber) or weaponHashNumber(weaponHash),
        weapon_hash_number = tonumber(row.weapon_hash_number or row.weaponHashNumber) or weaponHashNumber(weaponHash),
        group = tostring(row.group_key or row.group or 'pistol'):lower(),
        group_key = tostring(row.group_key or row.group or 'pistol'):lower(),
        ammoItem = normalizeItemName(row.ammo_item or row.ammoItem),
        ammo_item = normalizeItemName(row.ammo_item or row.ammoItem),
        damage = math.max(0, math.floor(tonumber(row.damage) or 0)),
        magazineSize = math.max(0, math.floor(tonumber(row.magazine_size or row.magazineSize) or 0)),
        magazine_size = math.max(0, math.floor(tonumber(row.magazine_size or row.magazineSize) or 0)),
        recoil = tonumber(row.recoil) or 0.0,
        durability = math.max(0, math.floor(tonumber(row.durability) or 100)),
        price = math.max(0, math.floor(tonumber(row.price) or 0)),
        weight = math.max(0, math.floor(tonumber(row.weight) or 0)),
        enabled = boolInt(row.enabled, true) == 1,
        image = tostring(row.image or ''),
        description = tostring(row.description or ''),
        sortOrder = math.floor(tonumber(row.sort_order or row.sortOrder) or 0),
        sort_order = math.floor(tonumber(row.sort_order or row.sortOrder) or 0)
    }
end

local function waitForDb()
    while GetResourceState('oxmysql') ~= 'started' do Wait(500) end
end

local function ensureDatabase()
    waitForDb()

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_weapon_ammo (
            item_name VARCHAR(80) NOT NULL PRIMARY KEY,
            label VARCHAR(120) NOT NULL,
            ammo_key VARCHAR(40) NOT NULL DEFAULT 'pistol',
            pickup_hash BIGINT NOT NULL DEFAULT 0,
            drop_model VARCHAR(80) NULL,
            pack_size INT NOT NULL DEFAULT 1,
            price INT NOT NULL DEFAULT 0,
            weight INT NOT NULL DEFAULT 0,
            stack TINYINT(1) NOT NULL DEFAULT 1,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            image VARCHAR(255) NULL,
            description TEXT NULL,
            sort_order INT NOT NULL DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_ammo_key (ammo_key),
            INDEX idx_enabled (enabled)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_weapon_catalog (
            item_name VARCHAR(80) NOT NULL PRIMARY KEY,
            label VARCHAR(120) NOT NULL,
            weapon_hash VARCHAR(80) NOT NULL,
            weapon_hash_number BIGINT NOT NULL DEFAULT 0,
            group_key VARCHAR(40) NOT NULL DEFAULT 'pistol',
            ammo_item VARCHAR(80) NOT NULL,
            damage INT NOT NULL DEFAULT 0,
            magazine_size INT NOT NULL DEFAULT 0,
            recoil DECIMAL(10,3) NOT NULL DEFAULT 0.000,
            durability INT NOT NULL DEFAULT 100,
            price INT NOT NULL DEFAULT 0,
            weight INT NOT NULL DEFAULT 0,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            image VARCHAR(255) NULL,
            description TEXT NULL,
            sort_order INT NOT NULL DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_group_key (group_key),
            INDEX idx_ammo_item (ammo_item),
            INDEX idx_enabled (enabled)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- Upgrade-safe columns for older installs. Duplicate-column errors are ignored.
    local alters = {
        'ALTER TABLE cm_weapon_ammo ADD COLUMN pickup_hash BIGINT NOT NULL DEFAULT 0 AFTER ammo_key',
        'ALTER TABLE cm_weapon_ammo ADD COLUMN drop_model VARCHAR(80) NULL AFTER pickup_hash',
        'ALTER TABLE cm_weapon_ammo ADD COLUMN pack_size INT NOT NULL DEFAULT 1 AFTER drop_model',
        'ALTER TABLE cm_weapon_ammo ADD COLUMN price INT NOT NULL DEFAULT 0 AFTER pack_size', -- legacy/unused by store
        'ALTER TABLE cm_weapon_ammo ADD COLUMN weight INT NOT NULL DEFAULT 0 AFTER price',
        'ALTER TABLE cm_weapon_ammo ADD COLUMN stack TINYINT(1) NOT NULL DEFAULT 1 AFTER weight',
        'ALTER TABLE cm_weapon_ammo ADD COLUMN enabled TINYINT(1) NOT NULL DEFAULT 1 AFTER stack',
        'ALTER TABLE cm_weapon_ammo ADD COLUMN image VARCHAR(255) NULL AFTER enabled',
        'ALTER TABLE cm_weapon_ammo ADD COLUMN description TEXT NULL AFTER image',
        'ALTER TABLE cm_weapon_ammo ADD COLUMN sort_order INT NOT NULL DEFAULT 0 AFTER description',
        'ALTER TABLE cm_weapon_catalog ADD COLUMN weapon_hash_number BIGINT NOT NULL DEFAULT 0 AFTER weapon_hash',
        "ALTER TABLE cm_weapon_catalog ADD COLUMN group_key VARCHAR(40) NOT NULL DEFAULT 'pistol' AFTER weapon_hash_number",
        "ALTER TABLE cm_weapon_catalog ADD COLUMN ammo_item VARCHAR(80) NOT NULL DEFAULT '' AFTER group_key",
        'ALTER TABLE cm_weapon_catalog ADD COLUMN damage INT NOT NULL DEFAULT 0 AFTER ammo_item',
        'ALTER TABLE cm_weapon_catalog ADD COLUMN magazine_size INT NOT NULL DEFAULT 0 AFTER damage',
        'ALTER TABLE cm_weapon_catalog ADD COLUMN recoil DECIMAL(10,3) NOT NULL DEFAULT 0.000 AFTER magazine_size',
        'ALTER TABLE cm_weapon_catalog ADD COLUMN durability INT NOT NULL DEFAULT 100 AFTER recoil',
        'ALTER TABLE cm_weapon_catalog ADD COLUMN price INT NOT NULL DEFAULT 0 AFTER durability', -- legacy/unused by store
        'ALTER TABLE cm_weapon_catalog ADD COLUMN weight INT NOT NULL DEFAULT 0 AFTER price',
        'ALTER TABLE cm_weapon_catalog ADD COLUMN enabled TINYINT(1) NOT NULL DEFAULT 1 AFTER weight',
        'ALTER TABLE cm_weapon_catalog ADD COLUMN image VARCHAR(255) NULL AFTER enabled',
        'ALTER TABLE cm_weapon_catalog ADD COLUMN description TEXT NULL AFTER image',
        'ALTER TABLE cm_weapon_catalog ADD COLUMN sort_order INT NOT NULL DEFAULT 0 AFTER description'
    }
    for _, query in ipairs(alters) do pcall(function() MySQL.query.await(query) end) end
    pcall(function() MySQL.query.await('CREATE INDEX idx_cm_weapon_ammo_key ON cm_weapon_ammo (ammo_key)') end)
    pcall(function() MySQL.query.await('CREATE INDEX idx_cm_weapon_ammo_enabled ON cm_weapon_ammo (enabled)') end)
    pcall(function() MySQL.query.await('CREATE INDEX idx_cm_weapon_catalog_group ON cm_weapon_catalog (group_key)') end)
    pcall(function() MySQL.query.await('CREATE INDEX idx_cm_weapon_catalog_ammo ON cm_weapon_catalog (ammo_item)') end)
    pcall(function() MySQL.query.await('CREATE INDEX idx_cm_weapon_catalog_enabled ON cm_weapon_catalog (enabled)') end)

    DB_READY = true
end

local function fixedAmmoMap()
    local map = {}
    for _, ammo in ipairs(Config.DefaultAmmo or {}) do
        local name = normalizeItemName(ammo.itemName or ammo.item_name)
        if name ~= '' then map[name] = ammo end
    end
    return map
end

local function fixedWeaponMap()
    local map = {}
    for _, weapon in ipairs(Config.DefaultWeapons or {}) do
        local name = normalizeItemName(weapon.itemName or weapon.item_name)
        if name ~= '' then map[name] = weapon end
    end
    return map
end

local function insertDefaultAmmo(ammo, index)
    local row = rowToAmmo({
        itemName = ammo.itemName,
        label = ammo.label,
        ammoKey = ammo.ammoKey,
        pickupHash = ammo.pickupHash or getPickupHashForAmmoKey(ammo.ammoKey),
        dropModel = ammo.dropModel or getDropModelForAmmoKey(ammo.ammoKey),
        packSize = ammo.packSize,
        price = ammo.price,
        weight = ammo.weight,
        stack = ammo.stack ~= false,
        enabled = ammo.enabled ~= false,
        image = ammo.image or '',
        description = ammo.description or '',
        sortOrder = ammo.sortOrder or index or 0
    })
    if row.itemName == '' then return end
    MySQL.query.await([[
        INSERT INTO cm_weapon_ammo
            (item_name, label, ammo_key, pickup_hash, drop_model, pack_size, price, weight, stack, enabled, image, description, sort_order)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label),
            ammo_key = VALUES(ammo_key),
            pickup_hash = VALUES(pickup_hash),
            drop_model = VALUES(drop_model),
            pack_size = VALUES(pack_size),
            price = 0,
            weight = VALUES(weight),
            stack = VALUES(stack),
            enabled = VALUES(enabled),
            image = CASE WHEN image IS NULL OR image = '' THEN VALUES(image) ELSE image END,
            description = VALUES(description),
            sort_order = VALUES(sort_order)
    ]], { row.itemName, row.label, row.ammoKey, row.pickupHash, row.dropModel, row.packSize, 0, row.weight, boolInt(row.stack, true), boolInt(row.enabled, true), row.image, row.description, row.sortOrder })
end

local function insertDefaultWeapon(weapon, index)
    local row = rowToWeapon({
        itemName = weapon.itemName,
        label = weapon.label,
        weaponHash = weapon.weaponHash,
        group = weapon.group,
        ammoItem = weapon.ammoItem,
        damage = weapon.damage,
        magazineSize = weapon.magazineSize,
        recoil = weapon.recoil,
        durability = weapon.durability or 100,
        price = 0,
        weight = weapon.weight,
        enabled = weapon.enabled ~= false,
        image = weapon.image or '',
        description = weapon.description or '',
        sortOrder = weapon.sortOrder or index or 0
    })
    if row.itemName == '' or row.weaponHash == '' then return end
    MySQL.query.await([[
        INSERT INTO cm_weapon_catalog
            (item_name, label, weapon_hash, weapon_hash_number, group_key, ammo_item, damage, magazine_size, recoil, durability, price, weight, enabled, image, description, sort_order)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label),
            weapon_hash = VALUES(weapon_hash),
            weapon_hash_number = VALUES(weapon_hash_number),
            group_key = VALUES(group_key),
            ammo_item = VALUES(ammo_item),
            damage = VALUES(damage),
            magazine_size = VALUES(magazine_size),
            recoil = VALUES(recoil),
            durability = VALUES(durability),
            price = 0,
            weight = VALUES(weight),
            enabled = VALUES(enabled),
            image = CASE WHEN image IS NULL OR image = '' THEN VALUES(image) ELSE image END,
            description = VALUES(description),
            sort_order = VALUES(sort_order)
    ]], { row.itemName, row.label, row.weaponHash, row.weaponHashNumber, row.group, row.ammoItem, row.damage, row.magazineSize, row.recoil, row.durability, 0, row.weight, boolInt(row.enabled, true), row.image, row.description, row.sortOrder })
end

local function seedDefaults()
    if not Config.SeedDefaults then return end
    for i, ammo in ipairs(Config.DefaultAmmo or {}) do insertDefaultAmmo(ammo, i) end
    for i, weapon in ipairs(Config.DefaultWeapons or {}) do insertDefaultWeapon(weapon, i) end

    -- Keep old/deprecated rows out of exports and admin pickers without deleting player items.
    if Config.StrictFixedCatalog == true then
        local ammoNames, weaponNames = {}, {}
        for _, ammo in ipairs(Config.DefaultAmmo or {}) do ammoNames[#ammoNames + 1] = normalizeItemName(ammo.itemName) end
        for _, weapon in ipairs(Config.DefaultWeapons or {}) do weaponNames[#weaponNames + 1] = normalizeItemName(weapon.itemName) end
        if #ammoNames > 0 then
            local qs = {}; for _ = 1, #ammoNames do qs[#qs + 1] = '?' end
            MySQL.update.await(('UPDATE cm_weapon_ammo SET enabled = 0 WHERE item_name NOT IN (%s)'):format(table.concat(qs, ',')), ammoNames)
        end
        if #weaponNames > 0 then
            local qs = {}; for _ = 1, #weaponNames do qs[#qs + 1] = '?' end
            MySQL.update.await(('UPDATE cm_weapon_catalog SET enabled = 0 WHERE item_name NOT IN (%s)'):format(table.concat(qs, ',')), weaponNames)
        end
    end
end

local function sortByOrderLabel(a, b)
    local ao, bo = tonumber(a.sortOrder or a.sort_order) or 0, tonumber(b.sortOrder or b.sort_order) or 0
    if ao ~= bo then return ao < bo end
    return tostring(a.label or '') < tostring(b.label or '')
end

local function loadAll()
    if not DB_READY then ensureDatabase() end
    CMWeapons.Ammo = {}
    CMWeapons.Weapons = {}
    CMWeapons.AmmoList = {}
    CMWeapons.WeaponList = {}

    local fixedAmmo = fixedAmmoMap()
    local fixedWeapons = fixedWeaponMap()

    local ammoRows = MySQL.query.await('SELECT * FROM cm_weapon_ammo ORDER BY sort_order ASC, label ASC', {}) or {}
    for _, dbRow in ipairs(ammoRows) do
        local row = rowToAmmo(dbRow)
        if row.itemName ~= '' and (Config.StrictFixedCatalog ~= true or fixedAmmo[row.itemName] ~= nil) then
            CMWeapons.Ammo[row.itemName] = row
            CMWeapons.AmmoList[#CMWeapons.AmmoList + 1] = row
        end
    end

    local weaponRows = MySQL.query.await('SELECT * FROM cm_weapon_catalog ORDER BY sort_order ASC, group_key ASC, label ASC', {}) or {}
    for _, dbRow in ipairs(weaponRows) do
        local row = rowToWeapon(dbRow)
        if row.itemName ~= '' and (Config.StrictFixedCatalog ~= true or fixedWeapons[row.itemName] ~= nil) then
            CMWeapons.Weapons[row.itemName] = row
            CMWeapons.WeaponList[#CMWeapons.WeaponList + 1] = row
        end
    end

    -- Self-heal the export cache from shared/defaults.lua if DB rows are missing.
    -- This prevents dependent resources from seeing an ammo-only catalog during a warm-up
    -- or after an older DB migration failed to seed weapon rows.
    if Config.StrictFixedCatalog == true then
        for i, ammo in ipairs(Config.DefaultAmmo or {}) do
            local row = rowToAmmo({
                itemName = ammo.itemName,
                label = ammo.label,
                ammoKey = ammo.ammoKey,
                pickupHash = ammo.pickupHash or getPickupHashForAmmoKey(ammo.ammoKey),
                dropModel = ammo.dropModel or getDropModelForAmmoKey(ammo.ammoKey),
                packSize = ammo.packSize,
                price = 0,
                weight = ammo.weight,
                stack = ammo.stack ~= false,
                enabled = ammo.enabled ~= false,
                image = ammo.image or '',
                description = ammo.description or '',
                sortOrder = ammo.sortOrder or i
            })
            if row.itemName ~= '' and not CMWeapons.Ammo[row.itemName] then
                CMWeapons.Ammo[row.itemName] = row
                CMWeapons.AmmoList[#CMWeapons.AmmoList + 1] = row
            end
        end
        for i, weapon in ipairs(Config.DefaultWeapons or {}) do
            local row = rowToWeapon({
                itemName = weapon.itemName,
                label = weapon.label,
                weaponHash = weapon.weaponHash,
                group = weapon.group,
                ammoItem = weapon.ammoItem,
                damage = weapon.damage,
                magazineSize = weapon.magazineSize,
                recoil = weapon.recoil,
                durability = weapon.durability or 100,
                price = 0,
                weight = weapon.weight,
                enabled = weapon.enabled ~= false,
                image = weapon.image or '',
                description = weapon.description or '',
                sortOrder = weapon.sortOrder or i
            })
            if row.itemName ~= '' and not CMWeapons.Weapons[row.itemName] then
                CMWeapons.Weapons[row.itemName] = row
                CMWeapons.WeaponList[#CMWeapons.WeaponList + 1] = row
            end
        end
    end

    table.sort(CMWeapons.AmmoList, sortByOrderLabel)
    table.sort(CMWeapons.WeaponList, sortByOrderLabel)
    CACHE_READY = true
    LAST_CACHE_LOAD = GetGameTimer and GetGameTimer() or os.time() * 1000
    return CMWeapons.AmmoList, CMWeapons.WeaponList
end

local function cmItemsReady()
    return GetResourceState(Config.ItemsResource or 'cm-items') == 'started'
end

local function syncAmmoToCmItems(row)
    row = rowToAmmo(row)
    if row.itemName == '' or not cmItemsReady() then return false, 'cm_items_not_started' end
    local ok, result, err = pcall(function()
        return exports[Config.ItemsResource or 'cm-items']:SaveCatalogItem({
            name = row.itemName,
            label = row.label,
            category = 'ammo',
            itemType = 'ammo',
            image = row.image ~= '' and row.image or nil,
            weight = row.weight,
            stack = true,
            usable = true,
            description = row.description ~= '' and row.description or ('Ammo pack: ' .. row.label),
            metadata = {
                source = RESOURCE,
                weaponSystem = 'cm-weapons',
                itemType = 'ammo',
                ammoKey = row.ammoKey,
                pickupHash = row.pickupHash,
                pickupName = ('PICKUP_AMMO_%s'):format(row.ammoKey:upper()),
                dropModel = row.dropModel,
                packSize = row.packSize,
                enabled = row.enabled
            },
            createdBy = RESOURCE
        })
    end)
    if not ok then return false, result end
    return result == true, err or result
end

local function syncWeaponToCmItems(row)
    row = rowToWeapon(row)
    if row.itemName == '' or not cmItemsReady() then return false, 'cm_items_not_started' end
    local ammo = CMWeapons.Ammo[row.ammoItem]
    local ok, result, err = pcall(function()
        return exports[Config.ItemsResource or 'cm-items']:SaveCatalogItem({
            name = row.itemName,
            label = row.label,
            category = 'weapon',
            itemType = 'weapon',
            image = row.image ~= '' and row.image or nil,
            weight = row.weight,
            stack = false,
            usable = true,
            equipmentSlot = 'weapon',
            description = row.description ~= '' and row.description or ('Weapon: ' .. row.label),
            metadata = {
                source = RESOURCE,
                weaponSystem = 'cm-weapons',
                itemType = 'weapon',
                weaponHash = row.weaponHash,
                weaponHashNumber = row.weaponHashNumber,
                group = row.group,
                ammoItem = row.ammoItem,
                ammoKey = ammo and ammo.ammoKey or nil,
                pickupHash = ammo and ammo.pickupHash or nil,
                damage = row.damage,
                magazineSize = row.magazineSize,
                recoil = row.recoil,
                durability = row.durability,
                serialRequired = true,
                equipped = false,
                enabled = row.enabled
            },
            createdBy = RESOURCE
        })
    end)
    if not ok then return false, result end
    return result == true, err or result
end

local function syncAllToCmItems()
    if not cmItemsReady() then
        dbg('cm-items not started, skip sync')
        return false
    end
    local ammoCount, weaponCount = 0, 0
    for _, row in ipairs(CMWeapons.AmmoList or {}) do
        local ok = syncAmmoToCmItems(row)
        if ok then ammoCount = ammoCount + 1 end
    end
    for _, row in ipairs(CMWeapons.WeaponList or {}) do
        local ok = syncWeaponToCmItems(row)
        if ok then weaponCount = weaponCount + 1 end
    end
    log(('synced to cm-items | ammo=%s | weapons=%s'):format(ammoCount, weaponCount))
    return true
end

local function broadcastAdminData(target)
    local payload = {
        ammo = CMWeapons.AmmoList or {},
        weapons = CMWeapons.WeaponList or {},
        ammoGroups = Config.AmmoGroups or {},
        defaultAmmo = Config.DefaultAmmo or {},
        defaultWeapons = Config.DefaultWeapons or {},
        pickupHashes = Config.AmmoPickupHashes or {}
    }
    TriggerClientEvent('cm-weapons:client:adminData', target or -1, payload)
end

local function getFixedAmmoDefault(itemName)
    itemName = normalizeItemName(itemName)
    if itemName == '' then return nil end
    for _, ammo in ipairs(Config.DefaultAmmo or {}) do
        if normalizeItemName(ammo.itemName or ammo.item_name) == itemName then return ammo end
    end
    return nil
end

local function getFixedWeaponDefault(itemName)
    itemName = normalizeItemName(itemName)
    if itemName == '' then return nil end
    for _, weapon in ipairs(Config.DefaultWeapons or {}) do
        if normalizeItemName(weapon.itemName or weapon.item_name) == itemName then return weapon end
    end
    return nil
end

local function updateImageOnly(kind, itemName, image, imageData, src)
    itemName = normalizeItemName(itemName)
    if itemName == '' then return false, 'bad_item_name' end

    local savedImage = nil
    if tostring(imageData or '') ~= '' then
        local folder = kind == 'ammo' and 'ammo' or 'weapon'
        local err
        savedImage, err = saveDataImage(imageData, itemName, folder)
        if not savedImage then return false, err or 'image_save_failed' end
    elseif Config.AllowAdminImagePath == true and tostring(image or '') ~= '' then
        savedImage = tostring(image or ''):sub(1, 255)
    else
        return false, 'no_image_selected'
    end

    if kind == 'ammo' then
        if not getFixedAmmoDefault(itemName) then return false, 'fixed_ammo_only_edit_config_first' end
        MySQL.update.await('UPDATE cm_weapon_ammo SET image = ? WHERE item_name = ?', { savedImage, itemName })
    else
        if not getFixedWeaponDefault(itemName) then return false, 'fixed_weapon_only_edit_config_first' end
        MySQL.update.await('UPDATE cm_weapon_catalog SET image = ? WHERE item_name = ?', { savedImage, itemName })
    end

    loadAll()
    if kind == 'ammo' and CMWeapons.Ammo[itemName] then
        syncAmmoToCmItems(CMWeapons.Ammo[itemName])
        for _, weapon in ipairs(CMWeapons.WeaponList or {}) do
            if weapon.ammoItem == itemName then syncWeaponToCmItems(weapon) end
        end
    elseif kind == 'weapon' and CMWeapons.Weapons[itemName] then
        syncWeaponToCmItems(CMWeapons.Weapons[itemName])
    end
    broadcastAdminData(src or -1)
    return true
end

local function saveAmmo(data, src)
    data = type(data) == 'table' and data or {}
    local itemName = normalizeItemName(data.itemName or data.item_name)
    if not getFixedAmmoDefault(itemName) then return false, 'fixed_ammo_only_edit_shared_defaults' end
    return updateImageOnly('ammo', itemName, data.image, data.imageData or data.image_data, src)
end

local function saveWeapon(data, src)
    data = type(data) == 'table' and data or {}
    local itemName = normalizeItemName(data.itemName or data.item_name)
    if not getFixedWeaponDefault(itemName) then return false, 'fixed_weapon_only_edit_shared_defaults' end
    return updateImageOnly('weapon', itemName, data.image, data.imageData or data.image_data, src)
end

local function deleteFromCmItems(itemName)
    itemName = normalizeItemName(itemName)
    if itemName == '' or not cmItemsReady() then return end
    pcall(function()
        exports[Config.ItemsResource or 'cm-items']:DeleteCatalogItem(itemName)
    end)
end

local function deleteWeapon(itemName)
    itemName = normalizeItemName(itemName)
    if itemName == '' then return false, 'bad_item_name' end
    if Config.FixedCatalogOnly == true then return false, 'fixed_catalog_delete_disabled_edit_config' end
    MySQL.query.await('DELETE FROM cm_weapon_catalog WHERE item_name = ?', { itemName })
    deleteFromCmItems(itemName)
    loadAll()
    return true
end

local function deleteAmmo(itemName, force)
    itemName = normalizeItemName(itemName)
    if itemName == '' then return false, 'bad_item_name' end
    if Config.FixedCatalogOnly == true then return false, 'fixed_catalog_delete_disabled_edit_config' end
    local users = MySQL.query.await('SELECT item_name, label FROM cm_weapon_catalog WHERE ammo_item = ? LIMIT 10', { itemName }) or {}
    if #users > 0 and not force then
        return false, ('ammo_is_used_by_%s_weapon(s)'):format(#users)
    end
    if #users > 0 and force then
        MySQL.query.await('UPDATE cm_weapon_catalog SET ammo_item = ? WHERE ammo_item = ?', { '', itemName })
    end
    MySQL.query.await('DELETE FROM cm_weapon_ammo WHERE item_name = ?', { itemName })
    deleteFromCmItems(itemName)
    loadAll()
    return true
end

local function publicCatalog(includeDisabled)
    local ammo, weapons = {}, {}
    for _, row in ipairs(CMWeapons.AmmoList or {}) do
        if includeDisabled or row.enabled then ammo[#ammo + 1] = row end
    end
    for _, row in ipairs(CMWeapons.WeaponList or {}) do
        if includeDisabled or row.enabled then weapons[#weapons + 1] = row end
    end
    return { ammo = ammo, weapons = weapons }
end

CreateThread(function()
    ensureDatabase()
    seedDefaults()
    loadAll()
    log(('started | ammo=%s | weapons=%s'):format(#CMWeapons.AmmoList, #CMWeapons.WeaponList))
    if Config.SyncDbRowsToCmItemsOnStart then
        Wait(1000)
        syncAllToCmItems()
    end
end)

RegisterNetEvent('cm-weapons:server:requestAdminData', function()
    local src = source
    if not isAdmin(src) then
        notify(src, 'No permission. Add ACE: add_ace group.admin cm.weapons.admin allow', 'error')
        return
    end
    loadAll()
    TriggerClientEvent('cm-weapons:client:openAdmin', src)
    broadcastAdminData(src)
end)

AddEventHandler('cm-weapons:dev:openAdmin', function(src)
    src = tonumber(src)
    if not src or not isAdmin(src) then return end
    loadAll()
    TriggerClientEvent('cm-weapons:client:openAdmin', src)
    broadcastAdminData(src)
end)

CreateThread(function()
    while GetResourceState('cm-admin') ~= 'started' do Wait(5000) end
    pcall(function()
        exports['cm-admin']:RegisterDevTool({
            id = 'weapons', label = 'Weapon Admin', category = 'Catalogs', icon = 'gun',
            permission = 'dev.weapons',
            actions = {
                { id = 'open', label = 'Open Weapon Admin', type = 'launcher', realm = 'server',
                  event = 'cm-weapons:dev:openAdmin' }
            }
        })
    end)
end)

RegisterNetEvent('cm-weapons:server:saveAmmo', function(data)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    local ok, err = saveAmmo(data, src)
    notify(src, ok and 'Ammo image updated and synced to cm-items.' or ('Ammo save failed: ' .. tostring(err)), ok and 'success' or 'error')
end)

RegisterNetEvent('cm-weapons:server:saveWeapon', function(data)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    local ok, err = saveWeapon(data, src)
    notify(src, ok and 'Weapon image updated and synced to cm-items.' or ('Weapon save failed: ' .. tostring(err)), ok and 'success' or 'error')
end)

RegisterNetEvent('cm-weapons:server:deleteAmmo', function(itemName, force)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    local ok, err = deleteAmmo(itemName, force == true)
    if ok then
        broadcastAdminData(src)
        notify(src, 'Ammo deleted.', 'success')
    else
        notify(src, 'Delete failed: ' .. tostring(err), 'error')
    end
end)

RegisterNetEvent('cm-weapons:server:deleteWeapon', function(itemName)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    local ok, err = deleteWeapon(itemName)
    if ok then
        broadcastAdminData(src)
        notify(src, 'Weapon deleted.', 'success')
    else
        notify(src, 'Delete failed: ' .. tostring(err), 'error')
    end
end)


RegisterNetEvent('cm-weapons:server:saveImage', function(data)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    data = type(data) == 'table' and data or {}
    local itemName = normalizeItemName(data.itemName or data.item_name)
    local kind = tostring(data.kind or data.itemType or data.item_type or ''):lower()
    if itemName == '' then return notify(src, 'Select an item first.', 'error') end
    if kind ~= 'ammo' and kind ~= 'weapon' then
        if CMWeapons.Ammo[itemName] then kind = 'ammo' elseif CMWeapons.Weapons[itemName] then kind = 'weapon' end
    end
    if kind ~= 'ammo' and kind ~= 'weapon' then return notify(src, 'Item not found in fixed cm-weapons catalog.', 'error') end
    local ok, err = updateImageOnly(kind, itemName, data.image, data.imageData or data.image_data, src)
    notify(src, ok and 'Image updated and synced to cm-items.' or ('Image update failed: ' .. tostring(err)), ok and 'success' or 'error')
end)

RegisterNetEvent('cm-weapons:server:syncAllToCmItems', function()
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    loadAll()
    local ok = syncAllToCmItems()
    notify(src, ok and 'Synced all weapons/ammo to cm-items.' or 'Sync failed. Check cm-items.', ok and 'success' or 'error')
end)

RegisterCommand(Config.AdminCommand or 'cmweaponadmin', function(src)
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    if src == 0 then
        log('This admin panel is in-game only. Use /cmweaponadmin as player.')
        return
    end
    loadAll()
    TriggerClientEvent('cm-weapons:client:openAdmin', src)
    broadcastAdminData(src)
end, false)

RegisterCommand('cmweaponsync', function(src)
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    loadAll()
    local ok = syncAllToCmItems()
    notify(src, ok and 'Synced weapons/ammo to cm-items.' or 'Sync failed. Check cm-items.', ok and 'success' or 'error')
end, false)

-- Exports for cm-gunstore, cm-inventory, cm-itemactions, police evidence, black market, etc.
-- Keep these fresh because /gunadmin can call immediately after /cmweaponadmin saves a new row.
local function refreshForExport(force)
    if not DB_READY then
        ensureDatabase()
        if Config.SeedDefaults then seedDefaults() end
        loadAll()
        return
    end

    local now = GetGameTimer and GetGameTimer() or os.time() * 1000
    local maxAge = tonumber(Config.ExportCacheMs) or 2500
    if force == true or CACHE_READY ~= true or (now - (LAST_CACHE_LOAD or 0)) >= maxAge then
        loadAll()
    end
end

exports('GetAllAmmo', function(includeDisabled)
    refreshForExport()
    if includeDisabled then return CMWeapons.AmmoList end
    return publicCatalog(false).ammo
end)

exports('GetAllWeapons', function(includeDisabled)
    refreshForExport()
    if includeDisabled then return CMWeapons.WeaponList end
    return publicCatalog(false).weapons
end)

exports('GetCatalog', function(includeDisabled)
    refreshForExport()
    return publicCatalog(includeDisabled == true)
end)

local function findAmmo(itemName)
    local key = normalizeItemName(itemName)
    if key == '' then return nil end
    if CMWeapons.Ammo[key] then return CMWeapons.Ammo[key] end

    -- Hard DB fallback for other resources that call immediately after admin saves/restarts.
    -- This avoids false "not found" responses if the in-memory table missed a row.
    local rows = MySQL.query.await('SELECT * FROM cm_weapon_ammo WHERE LOWER(item_name) = ? LIMIT 1', { key }) or {}
    if rows[1] then return rowToAmmo(rows[1]) end
    return nil
end

exports('GetAmmo', function(itemName)
    refreshForExport()
    return findAmmo(itemName)
end)

local function findWeapon(itemNameOrHash)
    local key = normalizeItemName(itemNameOrHash)
    if key ~= '' and CMWeapons.Weapons[key] then return CMWeapons.Weapons[key] end

    local hash = tostring(itemNameOrHash or ''):upper()
    for _, row in ipairs(CMWeapons.WeaponList or {}) do
        if row.weaponHash == hash then return row end
    end

    -- Hard DB fallback: find by item_name OR weapon_hash. This is the important fix for
    -- cm-gunstore buy flow, where a saved store row can call GetWeapon during a cache miss.
    local rows = MySQL.query.await([[
        SELECT * FROM cm_weapon_catalog
        WHERE LOWER(item_name) = ? OR UPPER(weapon_hash) = ?
        LIMIT 1
    ]], { key, hash }) or {}
    if rows[1] then return rowToWeapon(rows[1]) end
    return nil
end

exports('GetWeapon', function(itemNameOrHash)
    refreshForExport()
    return findWeapon(itemNameOrHash)
end)

exports('DoesAmmoExist', function(itemName, includeDisabled)
    refreshForExport()
    local ammo = findAmmo(itemName)
    if not ammo then return false end
    if includeDisabled == false and ammo.enabled ~= true then return false end
    return true
end)

exports('DoesWeaponExist', function(itemNameOrHash, includeDisabled)
    refreshForExport()
    local weapon = findWeapon(itemNameOrHash)
    if not weapon then return false end
    if includeDisabled == false and weapon.enabled ~= true then return false end
    return true
end)

exports('IsAmmoItem', function(itemName)
    refreshForExport()
    return findAmmo(itemName) ~= nil
end)

exports('IsWeaponItem', function(itemNameOrHash)
    refreshForExport()
    return findWeapon(itemNameOrHash) ~= nil
end)

exports('GetAmmoPickupHash', function(itemName)
    refreshForExport()
    local ammo = findAmmo(itemName)
    return ammo and ammo.pickupHash or nil
end)

exports('GetAmmoDropData', function(itemName)
    refreshForExport()
    local ammo = findAmmo(itemName)
    if not ammo then return nil end
    return { pickupHash = ammo.pickupHash, ammoKey = ammo.ammoKey, dropModel = ammo.dropModel, packSize = ammo.packSize }
end)

exports('GetWeaponAmmoItem', function(itemNameOrHash)
    refreshForExport()
    local weapon = findWeapon(itemNameOrHash)
    return weapon and weapon.ammoItem or nil
end)

exports('GetWeaponDamage', function(itemNameOrHash)
    refreshForExport()
    local weapon = findWeapon(itemNameOrHash)
    return weapon and weapon.damage or nil
end)

exports('SaveAmmo', function(data)
    if not DB_READY then ensureDatabase(); loadAll() end
    local ok, err = saveAmmo(data, 0)
    return ok, err
end)

exports('SaveWeapon', function(data)
    if not DB_READY then ensureDatabase(); loadAll() end
    local ok, err = saveWeapon(data, 0)
    return ok, err
end)

exports('DeleteAmmo', function(itemName, force)
    local ok, err = deleteAmmo(itemName, force == true)
    return ok, err
end)

exports('DeleteWeapon', function(itemName)
    local ok, err = deleteWeapon(itemName)
    return ok, err
end)

exports('SyncAllToCmItems', function()
    refreshForExport(true)
    return syncAllToCmItems()
end)

-- Inventory integration helper: when cm-inventory drops an ammo item, it can ask cm-weapons for pickup data
-- then trigger this to nearby clients. Example is in docs/INVENTORY_DROP_INTEGRATION.md.
-- Rate limit so a client cannot flood the server (and every other client) with
-- ammo pickup broadcasts.
local lastAmmoPickup = {}

AddEventHandler('playerDropped', function()
    if source then lastAmmoPickup[source] = nil end
end)

RegisterNetEvent('cm-weapons:server:spawnAmmoPickup', function(itemName, coords, amount)
    local src = source
    local ammo = CMWeapons.Ammo[normalizeItemName(itemName)]
    if not ammo or type(coords) ~= 'table' then return end

    -- Rate limit: at most one drop per second per player.
    local now = GetGameTimer()
    if lastAmmoPickup[src] and (now - lastAmmoPickup[src]) < 1000 then return end

    -- Never trust client coords. A drop must happen at the caller's own feet;
    -- otherwise this event lets any player spawn ammo pickups anywhere on the
    -- map for everyone (free-ammo / grief exploit).
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pcoords = GetEntityCoords(ped)
    local x = tonumber(coords.x or coords[1])
    local y = tonumber(coords.y or coords[2])
    local z = tonumber(coords.z or coords[3])
    if not x or not y or not z then return end
    if #(pcoords - vector3(x, y, z)) > 5.0 then return end

    -- Clamp the amount to the ammo pack size so it cannot be inflated.
    local maxAmount = tonumber(ammo.packSize) or 1
    if maxAmount < 1 then maxAmount = 1 end
    local reqAmount = math.floor(tonumber(amount) or maxAmount)
    if reqAmount < 1 then reqAmount = 1 end
    if reqAmount > maxAmount then reqAmount = maxAmount end

    lastAmmoPickup[src] = now

    TriggerClientEvent('cm-weapons:client:spawnAmmoPickup', -1, {
        itemName = ammo.itemName,
        label = ammo.label,
        pickupHash = ammo.pickupHash,
        ammoKey = ammo.ammoKey,
        amount = reqAmount,
        coords = { x = x, y = y, z = z }
    })
end)
