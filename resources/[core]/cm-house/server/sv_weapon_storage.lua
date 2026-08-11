-- ============================================================
-- cm-house | secure property weapon storage
--
-- The house owns authorization and the storage address. cm-inventory remains
-- the player-inventory authority. Only weapon and ammunition item definitions
-- supplied by cm-weapons / cm-gunstore are accepted.
-- ============================================================

CMHouseWeaponStorage = CMHouseWeaponStorage or {}
local WS = CMHouseWeaponStorage
local INV = tostring(Config.WeaponStorage and Config.WeaponStorage.inventoryResource or 'cm-inventory')
local WEAPONS = tostring(Config.WeaponStorage and Config.WeaponStorage.weaponsResource or 'cm-weapons')
local GUNSTORE = tostring(Config.WeaponStorage and Config.WeaponStorage.gunstoreResource or 'cm-gunstore')
local OWNER_TYPE = tostring(Config.WeaponStorage and Config.WeaponStorage.ownerType or 'house_weapon_storage')
local PLAYER_OWNER_TYPE = tostring(Config.WeaponStorage and Config.WeaponStorage.playerOwnerType or 'character')
local SLOT_PREFIX = tostring(Config.WeaponStorage and Config.WeaponStorage.slotPrefix or 'weapon-')
local MAX_SLOTS = math.max(1, math.min(120, tonumber(Config.WeaponStorage and Config.WeaponStorage.slots) or 60))
local ALLOW_WEAPONS = not Config.WeaponStorage or Config.WeaponStorage.allowWeapons ~= false
local ALLOW_AMMO = not Config.WeaponStorage or Config.WeaponStorage.allowAmmo ~= false
local locks = {}
local catalog = { expires = 0, byName = {}, rows = {} }

local REQUIRED_DURABILITY = math.max(1, math.min(100,
    tonumber(Config.WeaponStorage and Config.WeaponStorage.fullWeaponDurability) or 100))
local REQUIRE_FULL_DURABILITY = not Config.WeaponStorage
    or Config.WeaponStorage.requireFullWeaponDurability ~= false
local STRIP_SERIAL = not Config.WeaponStorage
    or Config.WeaponStorage.stripWeaponSerialOnDeposit ~= false

local function weaponDurability(metadata, row)
    metadata = type(metadata) == 'table' and metadata or {}
    row = type(row) == 'table' and row or {}
    local snapshot = type(metadata.snapshot) == 'table' and metadata.snapshot or {}
    local value = row.durability
        or metadata.durability or metadata.weaponDurability or metadata.weapon_durability
        or metadata.condition or metadata.health
        or snapshot.durability or snapshot.weaponDurability or snapshot.condition or snapshot.health
    local number = tonumber(value)
    if not number then return nil end
    return math.max(0, math.min(100, number))
end


local function decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, data = pcall(json.decode, value)
    return ok and type(data) == 'table' and data or {}
end

local function encode(value)
    local ok, data = pcall(json.encode, type(value) == 'table' and value or {})
    return ok and data or '{}'
end

local SERIAL_KEYS = {
    serial = true, weaponSerial = true, weapon_serial = true,
    serialNumber = true, serial_number = true, registeredSerial = true,
}

local function stripSerialRecursive(value, depth)
    if type(value) ~= 'table' or (depth or 0) > 6 then return end
    for key, child in pairs(value) do
        if SERIAL_KEYS[key] then
            value[key] = nil
        elseif type(child) == 'table' then
            stripSerialRecursive(child, (depth or 0) + 1)
        end
    end
end

local function containsSerialRecursive(value, depth)
    if type(value) ~= 'table' or (depth or 0) > 6 then return false end
    for key, child in pairs(value) do
        if SERIAL_KEYS[key] and child ~= nil and tostring(child) ~= '' then return true end
        if type(child) == 'table' and containsSerialRecursive(child, (depth or 0) + 1) then return true end
    end
    return false
end

local function stripWeaponIdentity(metadata)
    local out = decode(encode(metadata))
    if not STRIP_SERIAL then return out end
    stripSerialRecursive(out, 0)
    -- cm-inventory normally assigns every weapon a serial on AddItem. Keep an
    -- explicit server-owned marker so a weapon withdrawn from this locker
    -- remains unregistered instead of receiving a replacement serial.
    out.serialRequired = false
    out.serialRemovedByHouseStorage = true
    return out
end

local function normaliseName(value)
    local normalized = tostring(value or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    return normalized
end

local function inventorySuccess(result)
    if result == true then return true end
    if type(result) == 'number' then return result > 0 end
    if type(result) == 'table' then
        return result.success == true or result.ok == true or result.added == true or result.removed == true or result[1] == true
    end
    return false
end

local function imageInfo(value, itemType, weaponHash)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local gunstoreLocal = value:match('^images/(.+)$')
        or value:match('^nui://cm%-gunstore/web/images/(.+)$')
        or value:match('^https://cfx%-nui%-cm%-gunstore/web/images/(.+)$')
    if gunstoreLocal then
        -- Read the live cm-gunstore file first. The local copy in cm-house is a
        -- fallback so default icons still work when cm-gunstore is restarted.
        return ('https://cfx-nui-%s/web/images/%s'):format(GUNSTORE, gunstoreLocal),
            'img/weapons/' .. gunstoreLocal
    end
    if value ~= '' then
        return value, itemType == 'ammo'
            and 'img/weapons/ammo_default.svg'
            or 'img/weapons/weapon_default.svg'
    end
    if itemType == 'weapon' and tostring(weaponHash or '') ~= '' then
        return ('https://docs-backend.fivem.net/weapons/%s.png'):format(tostring(weaponHash):upper()),
            'img/weapons/weapon_default.svg'
    end
    return itemType == 'ammo'
        and 'img/weapons/ammo_default.svg'
        or 'img/weapons/weapon_default.svg', nil
end

local function localImage(value, itemType, weaponHash)
    local image = imageInfo(value, itemType, weaponHash)
    return image
end

local function mergeCatalogRow(target, row, forcedType)
    if type(row) ~= 'table' then return end
    local itemName = normaliseName(row.item_name or row.itemName or row.name)
    if itemName == '' then return end
    local itemType = tostring(forcedType or row.item_type or row.itemType or row.category or ''):lower()
    if itemType ~= 'weapon' and itemType ~= 'ammo' then
        if itemName:sub(1, 7) == 'weapon_' then itemType = 'weapon'
        elseif itemName:sub(1, 5) == 'ammo_' then itemType = 'ammo'
        else return end
    end
    if (itemType == 'weapon' and not ALLOW_WEAPONS) or (itemType == 'ammo' and not ALLOW_AMMO) then return end
    local previous = target[itemName] or {}
    local hash = tostring(row.weapon_hash or row.weaponHash or row.hash or previous.weaponHash or ''):upper()
    target[itemName] = {
        itemName = itemName,
        itemType = itemType,
        label = tostring(row.label or previous.label or itemName),
        image = localImage(row.image or row.icon or previous.image, itemType, hash),
        description = tostring(row.description or previous.description or ''),
        group = tostring(row.group or row.group_key or row.ammo_key or previous.group or itemType),
        weaponHash = hash,
        ammoItem = normaliseName(row.ammo_item or row.ammoItem or row.ammo or previous.ammoItem),
    }
end

function WS.RefreshCatalog(force)
    if not force and catalog.expires > os.time() then return catalog end
    local byName = {}

    if GetResourceState(WEAPONS) == 'started' then
        local okWeapons, weapons = pcall(function() return exports[WEAPONS]:GetAllWeapons(true) end)
        if okWeapons and type(weapons) == 'table' then
            for _, row in ipairs(weapons) do mergeCatalogRow(byName, row, 'weapon') end
        end
        local okAmmo, ammo = pcall(function() return exports[WEAPONS]:GetAllAmmo(true) end)
        if okAmmo and type(ammo) == 'table' then
            for _, row in ipairs(ammo) do mergeCatalogRow(byName, row, 'ammo') end
        end
    end

    if GetResourceState(GUNSTORE) == 'started' then
        local okStore, rows = pcall(function() return exports[GUNSTORE]:GetCatalog(true) end)
        if okStore and type(rows) == 'table' then
            for _, row in ipairs(rows) do mergeCatalogRow(byName, row) end
        end
    end

    local rows = {}
    for _, row in pairs(byName) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b)
        if a.itemType ~= b.itemType then return a.itemType < b.itemType end
        return a.label:lower() < b.label:lower()
    end)
    catalog = { expires = os.time() + 60, byName = byName, rows = rows }
    return catalog
end

local function itemDefinition(itemName, metadata)
    itemName = normaliseName(itemName)
    local cat = WS.RefreshCatalog(false)
    local def = cat.byName[itemName]
    if def then return def end
    metadata = type(metadata) == 'table' and metadata or {}
    local metaType = tostring(metadata.categoryType or metadata.category or metadata.itemType or ''):lower()
    if ALLOW_WEAPONS and (itemName:sub(1, 7) == 'weapon_' or metaType == 'weapon' or tostring(metadata.weaponHash or '') ~= '') then
        local hash = tostring(metadata.weaponHash or itemName:gsub('^weapon_', 'WEAPON_')):upper()
        return { itemName = itemName, itemType = 'weapon', label = metadata.label or itemName,
            image = localImage(metadata.image or metadata.icon or metadata.img, 'weapon', hash), weaponHash = hash }
    end
    if ALLOW_AMMO and (itemName:sub(1, 5) == 'ammo_' or metaType == 'ammo') then
        return { itemName = itemName, itemType = 'ammo', label = metadata.label or itemName,
            image = localImage(metadata.image or metadata.icon or metadata.img, 'ammo'), group = metadata.ammoKey or 'ammo' }
    end
    return nil
end

local function storageOwnerId(houseId, index)
    houseId, index = tonumber(houseId), tonumber(index)
    if not houseId or not index or index < 1 then return nil end
    return ('%d:%d'):format(houseId, index)
end

local function storagePoint(houseId, index)
    local house = Houses[tonumber(houseId)]
    local tpl = house and InteriorTemplates[tonumber(house.interior_template_id)]
    local points = tpl and (tpl.weapon_storages or tpl.wardrobes) or nil
    return points and points[tonumber(index)] or nil, house
end

local function playerNear(src, point, maxDistance)
    if type(point) ~= 'table' then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    return #(coords - vector3(tonumber(point.x) or 0.0, tonumber(point.y) or 0.0, tonumber(point.z) or 0.0))
        <= (tonumber(maxDistance) or 3.0)
end

local function requireAccess(src, houseId, index, action)
    houseId, index = tonumber(houseId), tonumber(index)
    if not houseId or not index then return false, 'Invalid weapon storage.' end
    local point, house = storagePoint(houseId, index)
    if not house or not point then return false, 'That weapon storage point does not exist.' end
    local insideHouse, kind = WhereIs(src)
    if tonumber(insideHouse) ~= houseId or kind ~= 'house' then
        return false, 'You must be inside this house.'
    end
    if not playerNear(src, point, (Config.WeaponStorage and Config.WeaponStorage.interactionDistance or 2.0) + 2.0) then
        return false, 'Move closer to the weapon storage.'
    end
    local cid = GetCid(src)
    local allowed, reason = CanAccessProperty(cid, houseId, action or ACTIONS.WEAPON_STORAGE_USE)
    if not allowed then return false, reason end
    return true, { cid = cid, house = house, point = point, ownerId = storageOwnerId(houseId, index) }
end

local function rowToPublic(row)
    local metadata = decode(row.metadata)
    local def = itemDefinition(row.item_name, metadata)
    if not def then return nil end
    local image, fallbackImage = imageInfo(metadata.image or metadata.icon or metadata.img or metadata.imageUrl
        or (metadata.snapshot and metadata.snapshot.image) or def.image, def.itemType, def.weaponHash)
    return {
        id = tonumber(row.id),
        slot = tostring(row.slot or ''),
        itemName = normaliseName(row.item_name),
        itemType = def.itemType,
        label = tostring(metadata.label or (metadata.snapshot and metadata.snapshot.label) or def.label or row.item_name),
        image = image,
        fallbackImage = fallbackImage,
        description = tostring(metadata.description or (metadata.snapshot and metadata.snapshot.description) or def.description or ''),
        group = tostring(def.group or metadata.ammoKey or def.itemType),
        quantity = math.max(1, tonumber(row.quantity) or 1),
        metadata = metadata,
        serial = tostring(metadata.serial or ''),
        durability = weaponDurability(metadata, row),
        canStore = def.itemType ~= 'weapon' or (not REQUIRE_FULL_DURABILITY) or (weaponDurability(metadata, row) or -1) >= (REQUIRED_DURABILITY - 0.001),
        weaponHash = tostring(def.weaponHash or metadata.weaponHash or ''),
    }
end

local function rowsFor(ownerType, ownerId)
    return MySQL.query.await([[
        SELECT id, owner_type, owner_id, slot, item_name, quantity, metadata
        FROM inventory_items
        WHERE owner_type = ? AND owner_id = ?
        ORDER BY slot ASC
    ]], { ownerType, tostring(ownerId) }) or {}
end

local function publicRows(ownerType, ownerId)
    local out = {}
    for _, row in ipairs(rowsFor(ownerType, ownerId)) do
        local item = rowToPublic(row)
        if item then out[#out + 1] = item end
    end
    return out
end

function WS.BuildPayload(src, houseId, index)
    local ok, ctx = requireAccess(src, houseId, index, ACTIONS.WEAPON_STORAGE_USE)
    if not ok then return false, ctx end
    local canDeposit = CanAccessProperty(ctx.cid, houseId, ACTIONS.WEAPON_STORAGE_DEPOSIT)
    local canWithdraw = CanAccessProperty(ctx.cid, houseId, ACTIONS.WEAPON_STORAGE_WITHDRAW)
    local family = ctx.house.family_id and GetFamilyDisplay(ctx.house.family_id) or nil
    local familyName = family and tostring(family.name or family.label or '') or nil
    return true, {
        houseId = tonumber(houseId),
        familyId = ctx.house.family_id,
        storageIndex = tonumber(index),
        title = familyName and familyName ~= '' and 'Family Weapon Storage' or 'Weapon Storage',
        subtitle = familyName and familyName ~= ''
            and ('%s · %s'):format(familyName, tostring(ctx.house.label or ('Property #' .. tostring(houseId))))
            or tostring(ctx.house.label or ('Property #' .. tostring(houseId))),
        player = publicRows(PLAYER_OWNER_TYPE, ctx.cid),
        storage = publicRows(OWNER_TYPE, ctx.ownerId),
        capacity = MAX_SLOTS,
        canDeposit = canDeposit == true,
        canWithdraw = canWithdraw == true,
    }
end

local function findEmptySlot(ownerId)
    local occupied = {}
    for _, row in ipairs(rowsFor(OWNER_TYPE, ownerId)) do occupied[tostring(row.slot)] = true end
    for i = 1, MAX_SLOTS do
        local slot = SLOT_PREFIX .. i
        if not occupied[slot] then return slot end
    end
    return nil
end

local function findStackRow(ownerId, itemName)
    return MySQL.single.await([[
        SELECT id, slot FROM inventory_items
        WHERE owner_type = ? AND owner_id = ? AND LOWER(item_name) = ?
        ORDER BY id LIMIT 1
    ]], { OWNER_TYPE, ownerId, normaliseName(itemName) })
end

local function inventoryRemove(src, itemName, amount, metadata, itemType)
    if GetResourceState(INV) ~= 'started' then return false, 'Inventory is not running.' end
    local inv = exports[INV]
    local attempts = {
        function() return inv:RemoveItem(src, itemName, amount, metadata, 'cm_house_weapon_deposit') end,
        function() return inv:RemoveItem(src, itemName, amount, metadata) end,
    }
    -- Ammo is stackable and safe to remove by name if the installed inventory
    -- does not support metadata matching. Unique weapons never use this fallback.
    if itemType == 'ammo' then
        attempts[#attempts + 1] = function() return inv:RemoveItem(src, itemName, amount, nil, 'cm_house_weapon_deposit') end
        attempts[#attempts + 1] = function() return inv:RemoveItem(src, itemName, amount) end
    end
    local last
    for _, fn in ipairs(attempts) do
        local called, result, reason = pcall(fn)
        if called and inventorySuccess(result) then return true end
        last = reason or result or last
    end
    return false, tostring(last or 'The inventory refused the item transfer.')
end

local function inventoryAdd(src, itemName, amount, metadata)
    if GetResourceState(INV) ~= 'started' then return false, 'Inventory is not running.' end
    metadata = type(metadata) == 'table' and metadata or {}
    metadata.inventoryOnly = true
    metadata.equipped = false
    metadata.autoEquip = false
    local inv = exports[INV]
    local attempts = {
        function() return inv:AddItem(src, itemName, amount, metadata, nil, 'cm_house_weapon_withdraw') end,
        function() return inv:AddItem(src, itemName, amount, metadata, 'cm_house_weapon_withdraw') end,
        function() return inv:AddItem(src, itemName, amount, metadata) end,
        function() return inv:AddItem(src, itemName, amount, false, metadata, 'cm_house_weapon_withdraw') end,
    }
    local last
    for _, fn in ipairs(attempts) do
        local called, result, reason = pcall(fn)
        if called and inventorySuccess(result) then return true end
        last = reason or result or last
    end
    return false, tostring(last or 'Your inventory is full or does not recognise this item.')
end

local function addLockerItem(ownerId, row, amount, def)
    local existing = findStackRow(ownerId, row.item_name)
    if existing then
        local changed = MySQL.update.await([[
            UPDATE inventory_items SET quantity = quantity + ?
            WHERE id = ? AND owner_type = ? AND owner_id = ?
        ]], { amount, existing.id, OWNER_TYPE, ownerId })
        local updated = changed and changed > 0
        return updated, updated and nil or 'The stored weapon stack changed. Refresh and try again.'
    end
    local slot = findEmptySlot(ownerId)
    if not slot then return false, 'Weapon storage is full.' end
    local id = MySQL.insert.await([[
        INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { OWNER_TYPE, ownerId, slot, normaliseName(row.item_name), amount, row.metadata or '{}' })
    return id ~= nil, id and nil or 'The storage database rejected the item.'
end

local function logTransfer(houseId, index, cid, direction, itemName, quantity, details)
    pcall(function()
        MySQL.insert.await([[
            INSERT INTO cm_house_weapon_transfers
                (house_id, storage_index, character_id, direction, item_name, quantity, status, details)
            VALUES (?, ?, ?, ?, ?, ?, 'completed', ?)
        ]], { houseId, index, tostring(cid), direction, itemName, quantity, encode(details) })
    end)
end

local function withLock(key, fn)
    if locks[key] then return false, 'Another weapon-storage transfer is already running.' end
    locks[key] = true
    local called, a, b = pcall(fn)
    locks[key] = nil
    if not called then
        print(('[cm-house] ^1weapon storage transfer error: %s^7'):format(tostring(a)))
        return false, 'The transfer failed. Nothing else was moved.'
    end
    return a, b
end

lib.callback.register('cm-house:server:openWeaponStorage', function(src, houseId, index)
    return WS.BuildPayload(src, houseId, index)
end)

lib.callback.register('cm-house:server:weaponStorageTransfer', function(src, houseId, index, direction, rowId, amount)
    houseId, index, rowId = tonumber(houseId), tonumber(index), tonumber(rowId)
    direction = tostring(direction or ''):lower()
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if direction ~= 'deposit' and direction ~= 'withdraw' then return false, 'Unknown transfer direction.' end

    local action = direction == 'deposit' and ACTIONS.WEAPON_STORAGE_DEPOSIT or ACTIONS.WEAPON_STORAGE_WITHDRAW
    local access, ctx = requireAccess(src, houseId, index, action)
    if not access then return false, ctx end
    local key = ('%s:%s'):format(houseId, index)

    local ok, reason = withLock(key, function()
        if direction == 'deposit' then
            local row = MySQL.single.await([[
                SELECT * FROM inventory_items
                WHERE id = ? AND owner_type = ? AND owner_id = ? LIMIT 1
            ]], { rowId, PLAYER_OWNER_TYPE, tostring(ctx.cid) })
            if not row then return false, 'That item is no longer in your inventory.' end
            local meta = decode(row.metadata)
            local def = itemDefinition(row.item_name, meta)
            if not def then return false, 'Only weapons and ammunition can be stored here.' end
            if def.itemType == 'weapon' and REQUIRE_FULL_DURABILITY then
                local durability = weaponDurability(meta, row)
                if durability == nil then
                    return false, 'This weapon has no durability value. Only confirmed 100% condition weapons can be stored.'
                end
                if durability < (REQUIRED_DURABILITY - 0.001) then
                    return false, ('Only fully healthy weapons can be stored. This weapon is %.0f%%.'):format(durability)
                end
            end
            local available = math.max(1, tonumber(row.quantity) or 1)
            if def.itemType == 'weapon' then amount = 1 else amount = math.min(amount, available) end
            -- Existing weapon/ammo rows consume no new slot. This also permits
            -- adding to a stack when every physical locker slot is occupied.
            local hasStack = findStackRow(ctx.ownerId, row.item_name) ~= nil
            if not hasStack and not findEmptySlot(ctx.ownerId) then
                return false, 'Weapon storage is full.'
            end

            local removed, removeWhy = inventoryRemove(src, normaliseName(row.item_name), amount, meta, def.itemType)
            if not removed then return false, removeWhy end
            local lockerRow = row
            if def.itemType == 'weapon' then
                local lockerMeta = stripWeaponIdentity(meta)
                lockerMeta.durability = REQUIRED_DURABILITY
                lockerRow = {}
                for key, value in pairs(row) do lockerRow[key] = value end
                lockerRow.metadata = encode(lockerMeta)
            end
            local stored, storeWhy = addLockerItem(ctx.ownerId, lockerRow, amount, def)
            if not stored then
                -- The locker insert failed. Return the item to the player and
                -- VERIFY the return actually succeeded. If it did not, the item
                -- would be lost, so write a durable recovery row an admin can
                -- restore from instead of silently telling the player it is safe.
                local returned, returnWhy = inventoryAdd(src, normaliseName(row.item_name), amount, meta)
                if not returned then
                    pcall(function()
                        MySQL.insert('INSERT INTO cm_house_weapon_recovery '
                            .. '(house_id, point_index, character_id, src_player, item_name, amount, metadata, reason) '
                            .. 'VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
                                houseId, index, ctx.cid and tostring(ctx.cid) or nil, tonumber(src),
                                normaliseName(row.item_name), amount, encode(meta or {}),
                                ('deposit_rollback_failed: %s / %s'):format(
                                    tostring(storeWhy or 'store_failed'), tostring(returnWhy or 'return_failed')),
                            })
                    end)
                    print(('[cm-house] ^1weapon-storage rollback FAILED for %s (player %s) -- recovery row written^7')
                        :format(normaliseName(row.item_name), tostring(src)))
                    return false, 'Storage failed and the weapon could not be returned automatically. '
                        .. 'It has been logged for admin recovery -- contact staff.'
                end
                return false, storeWhy or 'The item was returned because storage failed.'
            end
            logTransfer(houseId, index, ctx.cid, direction, normaliseName(row.item_name), amount, { type = def.itemType, serialRemoved = def.itemType == 'weapon' and STRIP_SERIAL or false })
            LogHouse(houseId, ctx.house.family_id, ctx.cid, 'weapon_storage_deposit', {
                point = index, item = normaliseName(row.item_name), quantity = amount,
            })
            return true
        end

        local row = MySQL.single.await([[
            SELECT * FROM inventory_items
            WHERE id = ? AND owner_type = ? AND owner_id = ? LIMIT 1
        ]], { rowId, OWNER_TYPE, ctx.ownerId })
        if not row then return false, 'That stored item no longer exists.' end
        local meta = decode(row.metadata)
        local def = itemDefinition(row.item_name, meta)
        if not def then return false, 'That row is not a valid weapon or ammunition item.' end
        local available = math.max(1, tonumber(row.quantity) or 1)
        if def.itemType == 'weapon' then amount = 1 else amount = math.min(amount, available) end

        -- Legacy locker rows may predate the startup serial cleanup or may have
        -- been stored while an older cm-house version was running. Sanitize at
        -- the authoritative withdrawal boundary as well, so every withdrawn
        -- weapon is serial-free regardless of when it entered storage. Keep
        -- row.metadata unchanged below so a failed inventory add restores the
        -- exact original locker row.
        local withdrawMeta = def.itemType == 'weapon' and stripWeaponIdentity(meta) or meta

        -- Reserve/remove from the locker first. If the inventory rejects the
        -- item, restore the exact locker row. This ordering prevents a failed
        -- database finalization from duplicating a gun in the player's bag.
        local changed
        if amount >= available then
            changed = MySQL.update.await([[
                DELETE FROM inventory_items
                WHERE id = ? AND owner_type = ? AND owner_id = ? AND quantity = ?
            ]], { rowId, OWNER_TYPE, ctx.ownerId, available })
        else
            changed = MySQL.update.await([[
                UPDATE inventory_items SET quantity = quantity - ?
                WHERE id = ? AND owner_type = ? AND owner_id = ? AND quantity >= ?
            ]], { amount, rowId, OWNER_TYPE, ctx.ownerId, amount })
        end
        if not changed or changed <= 0 then
            return false, 'That locker item changed. Refresh the storage and try again.'
        end

        local added, addWhy = inventoryAdd(src, normaliseName(row.item_name), amount, withdrawMeta)
        if not added then
            local restored
            if amount >= available then
                restored = MySQL.insert.await([[
                    INSERT INTO inventory_items
                        (owner_type, owner_id, slot, item_name, quantity, metadata)
                    VALUES (?, ?, ?, ?, ?, ?)
                ]], { OWNER_TYPE, ctx.ownerId, row.slot, normaliseName(row.item_name), available, row.metadata or '{}' })
            else
                restored = MySQL.update.await([[
                    UPDATE inventory_items SET quantity = quantity + ?
                    WHERE id = ? AND owner_type = ? AND owner_id = ?
                ]], { amount, rowId, OWNER_TYPE, ctx.ownerId })
            end
            if not restored or (type(restored) == 'number' and restored <= 0) then
                pcall(function()
                    MySQL.insert.await([[
                        INSERT INTO cm_house_weapon_transfers
                            (house_id, storage_index, character_id, direction, item_name, quantity, status, details)
                        VALUES (?, ?, ?, 'withdraw', ?, ?, 'review_required', ?)
                    ]], { houseId, index, tostring(ctx.cid), normaliseName(row.item_name), amount,
                        encode({ rowId = rowId, slot = row.slot, reason = 'inventory_add_failed_and_restore_failed' }) })
                end)
                return false, 'Inventory rejected the item and the locker restore needs admin review.'
            end
            return false, addWhy
        end
        logTransfer(houseId, index, ctx.cid, direction, normaliseName(row.item_name), amount, { type = def.itemType })
        LogHouse(houseId, ctx.house.family_id, ctx.cid, 'weapon_storage_withdraw', {
            point = index, item = normaliseName(row.item_name), quantity = amount,
        })
        return true
    end)

    if not ok then return false, reason end
    return WS.BuildPayload(src, houseId, index)
end)


local function sanitizeExistingLockerSerials()
    if not STRIP_SERIAL then return 0 end
    local changed = 0
    local rows = MySQL.query.await([[
        SELECT id, item_name, metadata
        FROM inventory_items
        WHERE owner_type = ?
    ]], { OWNER_TYPE }) or {}
    for _, row in ipairs(rows) do
        local metadata = decode(row.metadata)
        local def = itemDefinition(row.item_name, metadata)
        if def and def.itemType == 'weapon'
            and (containsSerialRecursive(metadata, 0) or metadata.serialRequired ~= false) then
            local before = encode(metadata)
            local cleaned = stripWeaponIdentity(metadata)
            local after = encode(cleaned)
            if before ~= after then
                local updated = MySQL.update.await(
                    'UPDATE inventory_items SET metadata = ? WHERE id = ? AND owner_type = ?',
                    { after, row.id, OWNER_TYPE })
                if updated and updated > 0 then changed = changed + 1 end
            end
        end
    end
    return changed
end

function HouseWeaponStorageCount(houseId)
    return tonumber(MySQL.scalar.await([[
        SELECT COUNT(*) FROM inventory_items
        WHERE owner_type = ? AND owner_id LIKE ?
    ]], { OWNER_TYPE, ('%d:%%'):format(tonumber(houseId) or 0) })) or 0
end


local function integrationAllowed(scope)
    if type(CMHouseIntegrationAllowed) == 'function' then
        return CMHouseIntegrationAllowed(scope)
    end
    local invoker = GetInvokingResource()
    return not invoker or invoker == GetCurrentResourceName()
end

local function requireIntegration(scope)
    if integrationAllowed(scope) or integrationAllowed('admin') or integrationAllowed('family') then
        return true
    end
    return false, 'resource_not_authorized'
end

exports('GetWeaponStorageCatalog', function(force)
    return WS.RefreshCatalog(force == true).rows
end)
exports('GetHouseWeaponStorage', function(houseId, index)
    local allowed, reason = requireIntegration('weaponStorage')
    if not allowed then return false, reason end
    local ownerId = storageOwnerId(houseId, index)
    if not ownerId then return {} end
    return publicRows(OWNER_TYPE, ownerId)
end)
exports('GetHouseWeaponStorageCount', function(houseId)
    local allowed, reason = requireIntegration('weaponStorage')
    if not allowed then return false, reason end
    return HouseWeaponStorageCount(houseId)
end)
exports('GetHouseWeaponStorageTransfers', function(houseId, limit)
    local allowed, reason = requireIntegration('weaponStorage')
    if not allowed then return false, reason end
    limit = math.max(1, math.min(250, tonumber(limit) or 50))
    return MySQL.query.await(([=[
        SELECT id, house_id, storage_index, character_id, direction,
               item_name, quantity, status, details, created_at
        FROM cm_house_weapon_transfers
        WHERE house_id = ?
        ORDER BY id DESC LIMIT %d
    ]=]):format(limit), { tonumber(houseId) }) or {}
end)
exports('GetHouseWeaponStoragePointCount', function(houseId)
    local house = Houses[tonumber(houseId)]
    local tpl = house and InteriorTemplates[tonumber(house.interior_template_id)]
    return tpl and #(tpl.weapon_storages or tpl.wardrobes or {}) or 0
end)
exports('RefreshWeaponStorageCatalog', function()
    local allowed, reason = requireIntegration('weaponStorage')
    if not allowed then return false, reason end
    WS.RefreshCatalog(true)
    return true
end)
exports('CanUseHouseWeaponStorage', function(characterId, houseId, action)
    local internal = tostring(action or ACTIONS.WEAPON_STORAGE_USE)
    if internal == 'access' then internal = ACTIONS.WEAPON_STORAGE_USE end
    if internal == 'deposit' then internal = ACTIONS.WEAPON_STORAGE_DEPOSIT end
    if internal == 'withdraw' then internal = ACTIONS.WEAPON_STORAGE_WITHDRAW end
    return CanAccessProperty(characterId, tonumber(houseId), internal)
end)
exports('OpenHouseWeaponStorageForPlayer', function(src, houseId, index)
    local allowed, reason = requireIntegration('weaponStorage')
    if not allowed then return false, reason end
    src = tonumber(src)
    if not src then return false, 'invalid_player' end
    local ok, payload = WS.BuildPayload(src, houseId, index)
    if not ok then return false, payload end
    TriggerClientEvent('cm-house:client:openWeaponStorage', src, payload)
    return true
end)

exports('GetHouseWeaponStorageContract', function()
    return {
        version = '1.3.0',
        authority = { access = 'cm-house', playerInventory = INV, catalog = WEAPONS, shopImages = GUNSTORE },
        ownerType = OWNER_TYPE,
        playerOwnerType = PLAYER_OWNER_TYPE,
        maxSlots = MAX_SLOTS,
        accepts = { weapons = ALLOW_WEAPONS, ammunition = ALLOW_AMMO },
        requiresFullWeaponDurability = REQUIRE_FULL_DURABILITY,
        fullWeaponDurability = REQUIRED_DURABILITY,
        stripsWeaponSerialOnDeposit = STRIP_SERIAL,
        actions = {
            access = ACTIONS.WEAPON_STORAGE_USE,
            deposit = ACTIONS.WEAPON_STORAGE_DEPOSIT,
            withdraw = ACTIONS.WEAPON_STORAGE_WITHDRAW,
        },
        exports = {
            'GetWeaponStorageCatalog', 'GetHouseWeaponStorage',
            'GetHouseWeaponStorageCount', 'GetHouseWeaponStoragePointCount',
            'GetHouseWeaponStorageTransfers', 'RefreshWeaponStorageCatalog',
            'CanUseHouseWeaponStorage', 'OpenHouseWeaponStorageForPlayer',
            'GetHouseWeaponStorageContract',
        },
        familyPermissionKeys = {
            access = 'weapon_storage.access',
            deposit = 'weapon_storage.deposit',
            withdraw = 'weapon_storage.withdraw',
        },
    }
end)

CreateThread(function()
    Wait(1500)
    WS.RefreshCatalog(true)
    local cleaned = sanitizeExistingLockerSerials()
    if cleaned > 0 then
        print(('[cm-house] removed serial metadata from %d existing stored weapon%s.'):format(cleaned, cleaned == 1 and '' or 's'))
    end
end)

-- ------------------------------------------------------------
--  Admin recovery for failed weapon-storage transfers (v1.7.4).
--  Rows are written only when a deposit removed the weapon from the player
--  but neither the locker insert nor the automatic return succeeded.
-- ------------------------------------------------------------
exports('ListWeaponStorageRecovery', function(limit)
    limit = math.max(1, math.min(200, tonumber(limit) or 50))
    return MySQL.query.await(
        'SELECT * FROM cm_house_weapon_recovery ORDER BY created_at DESC LIMIT ?',
        { limit }) or {}
end)

-- Restore a pending recovery row to a currently-connected player. Returns
-- (ok, reason). The row is marked resolved only after the item is confirmed
-- back in the player's inventory, so a failure here is safe to retry.
exports('RestoreWeaponStorageRecovery', function(recoveryId, targetSrc)
    recoveryId = tonumber(recoveryId)
    targetSrc = tonumber(targetSrc)
    if not recoveryId or not targetSrc then return false, 'invalid_arguments' end

    local row = MySQL.single.await(
        'SELECT * FROM cm_house_weapon_recovery WHERE id = ? AND resolved = 0 LIMIT 1', { recoveryId })
    if not row then return false, 'No open recovery row with that id.' end

    local targetCid = GetCid(targetSrc)
    if not targetCid then return false, 'The selected character is not online.' end
    if tostring(targetCid) ~= tostring(row.character_id or '') then
        return false, 'The recovery row belongs to a different character.'
    end

    local token = ('weapon-recovery:%d:%d:%d'):format(recoveryId, targetCid, os.time())
    local claimed = tonumber(MySQL.update.await([[
        UPDATE cm_house_weapon_recovery
        SET status = 'processing', processing_token = ?, processing_by = ?,
            processing_started_at = NOW(), last_error = NULL
        WHERE id = ? AND resolved = 0 AND status IN ('pending', 'failed')
    ]], { token, targetCid, recoveryId })) or 0
    if claimed ~= 1 then return false, 'That row is already resolved or being restored.' end

    local meta = decode(row.metadata) or {}
    local ok, why = inventoryAdd(targetSrc, normaliseName(row.item_name), tonumber(row.amount) or 1, meta)
    if not ok then
        local reason = tostring(why or 'Could not add the item to that player.')
        MySQL.update.await([[
            UPDATE cm_house_weapon_recovery
            SET status = 'failed', processing_token = NULL, processing_by = NULL,
                processing_started_at = NULL, last_error = ?
            WHERE id = ? AND processing_token = ?
        ]], { reason:sub(1, 255), recoveryId, token })
        return false, reason
    end

    local marked = tonumber(MySQL.update.await([[
        UPDATE cm_house_weapon_recovery
        SET resolved = 1, status = 'resolved', restored_to_cid = ?, restored_to_src = ?,
            resolved_at = NOW(), processing_token = NULL, last_error = NULL
        WHERE id = ? AND processing_token = ? AND resolved = 0
    ]], { tostring(targetCid), targetSrc, recoveryId, token })) or 0
    if marked ~= 1 then
        print(('[cm-house] ^1CRITICAL: weapon recovery %d restored to CID %s but could not be marked resolved.^7')
            :format(recoveryId, tostring(targetCid)))
        return true, 'Weapon restored; journal status requires administrator review.'
    end
    return true, 'Weapon restored to the online character.'
end)
