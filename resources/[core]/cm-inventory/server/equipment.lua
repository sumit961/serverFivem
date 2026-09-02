-- cm-inventory/equipment.lua
-- Split from legacy server/main.lua. Loaded by server/main.lua bootloader in this exact order.

local syncCurrentWeaponAmmo

local function findStackTarget(ownerType, ownerId, itemName, metadata, preferredSlot)
    itemName = tostring(itemName or ''):lower()
    local def = getItemDef(itemName)
    if not def then return nil end
    local clothingStack = isClothingStackCandidate(itemName)
    if not clothingStack and (def.stack == false or def.unique == true) then return nil end

    if preferredSlot then
        local existingAtPreferred = getItemAt(ownerType, ownerId, preferredSlot)
        if existingAtPreferred and rowCanStackWithMetadata(existingAtPreferred, itemName, metadata) then
            return existingAtPreferred
        end
    end

    local rows = MySQL.query.await([[SELECT * FROM inventory_items
        WHERE owner_type = ? AND owner_id = ? AND item_name = ?
        ORDER BY FIELD(SUBSTRING_INDEX(slot, '-', 1), 'pocket', 'backpack', 'quickaccess'), slot ASC, id ASC]], {
        ownerType, tostring(ownerId), itemName
    }) or {}

    for _, row in ipairs(rows) do
        if rowCanStackWithMetadata(row, itemName, metadata) then
            return row
        end
    end

    return nil
end

local function AddItemInternal(src, itemName, amount, metadata, reason, preferredSlot)
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return false, 'Invalid amount.' end
    itemName = tostring(itemName or ''):lower()
    metadata = type(metadata) == 'table' and metadata or {}
    local hadCustomMetadata = next(metadata) ~= nil

    local allowed, err = isInventoryItem(itemName)
    if not allowed then return false, err end

    local def = getItemDef(itemName)
    if not def then return false, 'Unknown item.' end
    metadata = decorateNewItemMetadata(itemName, metadata, def, hadCustomMetadata)
    if Config.Debug and itemName == 'clothing_bags' then
        print(('[CM-INVENTORY] AddItem clothing_bags amount=%s bagLevel=%s image=%s'):format(
            tostring(amount), tostring((metadata or {}).bagLevel), tostring((metadata or {}).image or (metadata or {}).icon)
        ))
    end

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end

    if def.singleton == true then
        local existingCount = tonumber(MySQL.scalar.await([[SELECT COALESCE(SUM(quantity),0)
            FROM inventory_items WHERE owner_type=? AND owner_id=? AND item_name=?]],
            { ownerType, tostring(ownerId), itemName })) or 0
        if existingCount > 0 then return false, 'You can only carry one of this item.' end
        if amount > 1 then return false, 'You can only carry one of this item.' end
    end

    local okCarry, carryErr = canCarry(ownerType, ownerId, itemName, amount)
    if not okCarry then return false, carryErr end

    local slot = preferredSlot
    if slot and not canPlaceInSlot(itemName, slot) then slot = nil end

    local stackTarget = findStackTarget(ownerType, ownerId, itemName, metadata, slot)
    if stackTarget and (not slot or stackTarget.slot == slot) then
        -- Refresh metadata on every stack, not just quantity. A stack match only
        -- guarantees the wearable APPEARANCE signature is identical (drawable/
        -- texture/component) — fields outside that signature (image path, label,
        -- price, catalogId, arms/undershirt fit) can legitimately change between
        -- additions, and a row that started with bad/incomplete metadata (e.g. an
        -- old test give) would otherwise stay corrupt forever since only quantity
        -- was ever updated.
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ?, metadata = ? WHERE id = ?', { amount, encode(metadata), stackTarget.id })
        audit(ownerId, 'add_stack', itemName, amount, nil, stackTarget.slot, reason, metadata)
        return true, stackTarget.slot
    end

    if not slot then slot = findEmptySlot(ownerType, ownerId) end
    if not slot then return false, 'No empty slot. Equip a better bag to unlock more backpack slots.' end
    if not isSlotUnlocked(ownerType, ownerId, slot) then return false, 'That backpack slot is locked by your bag level.' end

    local canSlot, slotErr = canPlaceInSlot(itemName, slot)
    if not canSlot then return false, slotErr end

    local existingAtSlot = getItemAt(ownerType, ownerId, slot)
    if existingAtSlot then
        if rowCanStackWithMetadata(existingAtSlot, itemName, metadata) then
            -- Same reasoning as the stack-target branch above: refresh metadata,
            -- not just quantity, so a stale/corrupt row can't outlive every future
            -- correct addition of the same-looking item.
            MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ?, metadata = ? WHERE id = ?', { amount, encode(metadata), existingAtSlot.id })
            audit(ownerId, 'add_stack_slot', itemName, amount, nil, existingAtSlot.slot, reason, metadata)
            return true, existingAtSlot.slot
        end
        return false, 'Slot is already occupied.'
    end

    MySQL.insert.await([[INSERT INTO inventory_items
        (owner_type, owner_id, slot, item_name, quantity, metadata)
        VALUES (?, ?, ?, ?, ?, ?)]], {
        ownerType, tostring(ownerId), slot, itemName, amount, encode(metadata)
    })
    audit(ownerId, 'add', itemName, amount, nil, slot, reason, metadata)
    return true, slot
end

local function RemoveItemInternal(src, itemName, amount, metadata, reason)
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return false, 'Invalid amount.' end
    itemName = tostring(itemName or ''):lower()

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end

    local rows = MySQL.query.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? AND item_name = ? ORDER BY quantity DESC', {
        ownerType, tostring(ownerId), itemName
    }) or {}

    local remaining = amount
    for _, row in ipairs(rows) do
        if remaining <= 0 then break end
        local qty = tonumber(row.quantity) or 0
        local take = math.min(qty, remaining)
        if take >= qty then
            MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { row.id })
        else
            MySQL.update.await('UPDATE inventory_items SET quantity = quantity - ? WHERE id = ?', { take, row.id })
        end
        remaining = remaining - take
    end

    if remaining > 0 then return false, 'Not enough item.' end
    audit(ownerId, 'remove', itemName, amount, nil, nil, reason, metadata)
    return true
end

local function HasItemInternal(src, itemName, amount)
    amount = tonumber(amount) or 1
    itemName = tostring(itemName or ''):lower()
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false end
    local count = MySQL.scalar.await('SELECT COALESCE(SUM(quantity), 0) FROM inventory_items WHERE owner_type = ? AND owner_id = ? AND item_name = ?', {
        ownerType, tostring(ownerId), itemName
    }) or 0
    return tonumber(count) >= amount, tonumber(count)
end


local function syncEquipmentSlot(src, slot)
    if not isEquipmentSlot(slot) then return end
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return end
    local row = getItemAt(ownerType, ownerId, slot)
    local item = row and rowToItem(row) or nil
    TriggerClientEvent('cm-inventory:client:equipmentSlot', src, slot, item)

    -- Replicated so OTHER resources can cheaply check "is this player
    -- currently masked" without a DB round-trip (e.g. cm-playerdata's
    -- unmasked-kill wanted-stars check). cm-playerdata's own
    -- IsFamilySymbolMasked already reads this exact key -- it just had
    -- nothing setting it until now.
    if slot == 'mask' then
        Player(src).state:set('cm_masked', item ~= nil, true)
    end

    -- Weapon/ammo are linked: whenever either slot changes, push the real
    -- inventory ammo count to the client so GTA ammo never uses fake bullets.
    local ammoSlot = (Config.Ammo and Config.Ammo.slot) or 'ammo'
    if (slot == 'weapon' or slot == ammoSlot) and syncCurrentWeaponAmmo then
        syncCurrentWeaponAmmo(src)
    end
end

local function syncAllEquipment(src)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return end
    local payload = {}
    for _, slot in ipairs(Config.Slots.equipment) do
        local row = getItemAt(ownerType, ownerId, slot)
        payload[slot] = row and rowToItem(row) or nil
    end
    -- Same cm_masked replication as syncEquipmentSlot -- covers a player who
    -- loads in already wearing a mask, before any equip/unequip happens.
    Player(src).state:set('cm_masked', payload.mask ~= nil, true)
    TriggerClientEvent('cm-inventory:client:setEquipment', src, payload)
    if syncCurrentWeaponAmmo then syncCurrentWeaponAmmo(src) end
end

local CLOTHING_SLOT_BY_CATEGORY = {
    tshirt = 'shirt', torso = 'outerwear', pants = 'pants', legs = 'pants', shoes = 'shoes',
    chains = 'accessory', bags = 'bag', hat = 'headwear', glasses = 'glasses',
    earrings = 'earrings', watches = 'watch'
}

local function isClothingItemName(itemName)
    itemName = tostring(itemName or ''):lower()
    return itemName:find('clothing_', 1, true) == 1
end

local function getClothingCategory(itemName, metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local category = tostring(metadata.categoryType or metadata.category or ''):lower()
    if category == '' then category = tostring(itemName or ''):lower():gsub('^clothing_', '') end
    return category
end

local function getClothingEquipSlot(itemName, metadata)
    return CLOTHING_SLOT_BY_CATEGORY[getClothingCategory(itemName, metadata)]
end

local function saveAppearance(src)
    if GetResourceState('cm-characters') == 'started' then
        pcall(function() exports['cm-characters']:SaveAppearance(src) end)
    end
end


local function normalizeGender(value)
    if value == nil or value == '' then return nil end
    local raw = tostring(value):lower()
    if raw == '0' or raw == 'm' or raw == 'male' or raw == 'man' or raw == 'mp_m_freemode_01' then return 'male' end
    if raw == '1' or raw == 'f' or raw == 'female' or raw == 'woman' or raw == 'mp_f_freemode_01' then return 'female' end
    if raw == 'any' or raw == 'all' or raw == 'unisex' or raw == 'both' then return nil end
    return nil
end

local function getPlayerGender(src)
    local stateGender = nil
    pcall(function()
        local st = Player(src).state
        stateGender = st.gender or st.sex or st.characterGender or st.character_gender or st.cmGender
    end)
    local normalized = normalizeGender(stateGender)
    if normalized then return normalized end

    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local model = GetEntityModel(ped)
        if model == GetHashKey('mp_f_freemode_01') then return 'female' end
        if model == GetHashKey('mp_m_freemode_01') then return 'male' end
    end

    return nil
end

local function getItemGenderFromRow(row)
    if not row then return nil end
    local metadata = decode(row.metadata)
    local def = getItemDef(row.item_name) or {}
    return normalizeGender(metadata.gender or metadata.sex or metadata.pedGender or metadata.ped_gender or metadata.model or def.gender or def.sex)
end

local function validateWearableGender(src, row)
    local requiredGender = getItemGenderFromRow(row)
    if not requiredGender then return true end
    local playerGender = getPlayerGender(src)
    if not playerGender then return true end
    if playerGender ~= requiredGender then
        return false, ('This item is for %s characters only.'):format(requiredGender)
    end
    return true
end

local function validateEquipmentGender(src, slot, row)
    if not row or not isEquipmentSlot(slot) then return true end
    if not (isClothingItemName(row.item_name) or tostring(row.item_name or ''):lower():find('armor', 1, true)) then
        return true
    end
    return validateWearableGender(src, row)
end

local function MoveItemInternal(src, fromSlot, toSlot)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(fromSlot) or not isValidSlot(toSlot) then return false, 'Invalid slot.' end
    if not isSlotUnlocked(ownerType, ownerId, toSlot) then return false, 'That backpack slot is locked by your bag level.' end
    if fromSlot == toSlot then return true end

    local source = getItemAt(ownerType, ownerId, fromSlot)
    if not source then return false, 'Source slot is empty.' end

    local genderOk, genderErr = validateEquipmentGender(src, toSlot, source)
    if not genderOk then return false, genderErr end

    local canSlot, slotErr = canPlaceInSlot(source.item_name, toSlot)
    if not canSlot then return false, slotErr end

    local dest = getItemAt(ownerType, ownerId, toSlot)
    local sourceItem = rowToItem(source)

    local bagOk, bagErr = validateBagTransition(ownerType, ownerId, fromSlot, toSlot, source, dest)
    if not bagOk then return false, bagErr end

    if not dest then
        -- Clothing stacks are allowed in backpack/pocket slots, but equipment slots must
        -- only ever hold one physical clothing item. When equipping from a stack, split
        -- one item into the target equipment slot and keep the rest in the source slot.
        if isEquipmentSlot(toSlot) and isClothingItemName(source.item_name) and (tonumber(source.quantity) or 1) > 1 then
            MySQL.update.await('UPDATE inventory_items SET quantity = quantity - 1 WHERE id = ?', { source.id })
            MySQL.insert.await([[INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata)
                VALUES (?, ?, ?, ?, ?, ?)]], { ownerType, tostring(ownerId), toSlot, source.item_name, 1, source.metadata or '{}' })
            audit(ownerId, 'equip_split_clothing', source.item_name, 1, fromSlot, toSlot, 'move_split_to_equipment', decode(source.metadata))
            syncEquipmentSlot(src, fromSlot)
            syncEquipmentSlot(src, toSlot)
            saveAppearance(src)
            return true
        end

        MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { toSlot, source.id })
        audit(ownerId, 'move', source.item_name, source.quantity, fromSlot, toSlot, 'move', {})
        syncEquipmentSlot(src, fromSlot)
        syncEquipmentSlot(src, toSlot)
        if (isEquipmentSlot(toSlot) or isEquipmentSlot(fromSlot)) and isClothingItemName(source.item_name) then
            -- syncEquipmentSlot already applied/cleared the visual clothing on the client.
            -- Save once after the DB move, not once per client-side apply event.
            saveAppearance(src)
        end
        return true
    end

    if isEquipmentSlot(toSlot) and isClothingItemName(source.item_name) and (tonumber(source.quantity) or 1) > 1 then
        return false, 'Remove the equipped clothing first, then equip one item from this stack.'
    end

    local destItem = rowToItem(dest)
    if rowsCanStack(source, dest) then
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { source.quantity, dest.id })
        MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { source.id })
        audit(ownerId, 'merge', source.item_name, source.quantity, fromSlot, toSlot, 'move_merge', {})
        syncEquipmentSlot(src, fromSlot)
        syncEquipmentSlot(src, toSlot)
        if isEquipmentSlot(fromSlot) and isClothingItemName(source.item_name) then
            saveAppearance(src)
        end
        return true
    end

    local canBack, backErr = canPlaceInSlot(dest.item_name, fromSlot)
    if not canBack then return false, backErr end

    local backGenderOk, backGenderErr = validateEquipmentGender(src, fromSlot, dest)
    if not backGenderOk then return false, backGenderErr end

    local tempSlot = ('__tmp_%s_%s'):format(source.id, math.random(1000, 9999))
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { tempSlot, source.id })
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { fromSlot, dest.id })
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { toSlot, source.id })
    audit(ownerId, 'swap', source.item_name, source.quantity, fromSlot, toSlot, 'move_swap', {})
    syncEquipmentSlot(src, fromSlot)
    syncEquipmentSlot(src, toSlot)
    if (isEquipmentSlot(toSlot) and isClothingItemName(source.item_name))
        or (isEquipmentSlot(fromSlot) and isClothingItemName(dest.item_name)) then
        saveAppearance(src)
    end
    return true
end

local function SplitItemInternal(src, fromSlot, toSlot, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return false, 'Invalid split amount.' end
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(fromSlot) or not isValidSlot(toSlot) then return false, 'Invalid slot.' end
    if not isSlotUnlocked(ownerType, ownerId, toSlot) then return false, 'That backpack slot is locked by your bag level.' end

    local source = getItemAt(ownerType, ownerId, fromSlot)
    if not source then return false, 'Source slot is empty.' end
    if getItemAt(ownerType, ownerId, toSlot) then return false, 'Target slot is not empty.' end
    if tonumber(source.quantity) <= amount then return false, 'Split amount is too high.' end
    local def = getItemDef(source.item_name)
    if def and def.stack == false then return false, 'This item cannot be split.' end
    local canSlot, slotErr = canPlaceInSlot(source.item_name, toSlot)
    if not canSlot then return false, slotErr end

    MySQL.update.await('UPDATE inventory_items SET quantity = quantity - ? WHERE id = ?', { amount, source.id })
    MySQL.insert.await([[INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata)
        VALUES (?, ?, ?, ?, ?, ?)]], { ownerType, tostring(ownerId), toSlot, source.item_name, amount, source.metadata or '{}' })
    audit(ownerId, 'split', source.item_name, amount, fromSlot, toSlot, 'split_stack', decode(source.metadata))
    return true
end

local createWorldDrop, sendDrops, cleanupDrops

local function DropItemInternal(src, slot, amount)
    amount = math.floor(tonumber(amount) or 1)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(slot) then return false, 'Invalid slot.' end

    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end

    local bagOk, bagErr = validateBagRemovalFromSlot(ownerType, ownerId, slot, row)
    if not bagOk then return false, bagErr end

    local qty = tonumber(row.quantity) or 0
    local drop = math.min(qty, amount)
    if drop < 1 then return false, 'Invalid drop amount.' end

    if drop >= qty then
        MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { row.id })
    else
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity - ? WHERE id = ?', { drop, row.id })
    end

    local dropId = createWorldDrop(src, row, drop)
    local droppedMetadata = decode(row.metadata)
    audit(ownerId, 'drop', row.item_name, drop, slot, nil, dropId and ('world_drop_' .. dropId) or 'drop_item', droppedMetadata)
    if dropId then
        -- Local server contract emitted only after the authoritative inventory
        -- row has been removed and the world drop has been created.
        TriggerEvent('cm-inventory:server:itemDropped', src, tostring(ownerId), row.item_name, drop, droppedMetadata, dropId)
    end
    if dropId then sendDrops(-1) end
    return true
end

local function ConsumeSlotItemInternal(src, slot, amount, reason)
    amount = math.floor(tonumber(amount) or 1)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(slot) then return false, 'Invalid slot.' end

    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end

    local bagOk, bagErr = validateBagRemovalFromSlot(ownerType, ownerId, slot, row)
    if not bagOk then return false, bagErr end

    local qty = tonumber(row.quantity) or 0
    local consume = math.min(qty, amount)
    if consume < 1 then return false, 'Invalid amount.' end

    if consume >= qty then
        MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { row.id })
    else
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity - ? WHERE id = ?', { consume, row.id })
    end
    audit(ownerId, reason or 'consume', row.item_name, consume, slot, nil, reason or 'consume_item', decode(row.metadata))
    return true
end

local function runUsableHandler(src, itemName, item, handler)
    -- Same-resource direct Lua function handler. Useful for built-in/test actions.
    if type(handler) == 'function' then
        local completed = false
        local result = { success = false, remove = 0, message = nil }

        local function done(ok, removeAmount, msg)
            completed = true
            result.success = ok == true
            result.remove = tonumber(removeAmount) or 0
            result.message = msg
        end

        local ok, retSuccess, retRemove, retMessage = pcall(handler, src, item, done)
        if not ok then return false, 0, tostring(retSuccess) end

        -- Also support: return true, 1, 'message'
        if not completed and type(retSuccess) == 'boolean' then
            done(retSuccess, retRemove, retMessage)
        end

        if not completed then return false, 0, 'Usable item handler did not call done().' end
        return result.success, result.remove, result.message
    end

    -- Cross-resource handler. This is the recommended future-proof style.
    -- handler = { resource = 'cm-itemactions', export = 'UseItem' }
    if type(handler) == 'table' then
        local resource = tostring(handler.resource or '')
        local exportName = tostring(handler.export or '')

        if resource == '' or exportName == '' then
            return false, 0, 'Usable item handler is invalid.'
        end

        if GetResourceState(resource) ~= 'started' then
            return false, 0, ('Usable item resource is not started: %s'):format(resource)
        end

        local ok, result = pcall(function()
            return exports[resource][exportName](itemName, src, item)
        end)

        if not ok then return false, 0, tostring(result) end
        if type(result) ~= 'table' then return false, 0, 'Usable item export did not return a result table.' end

        return result.success == true, tonumber(result.remove or result.removeAmount) or 0, result.message
    end

    return false, 0, 'No usable handler found.'
end

local ReloadWeaponInternal

local function isWeaponItemName(itemName)
    itemName = tostring(itemName or ''):lower()
    return itemName:find('weapon_', 1, true) == 1
end

local function isAmmoItemName(itemName)
    itemName = tostring(itemName or ''):lower()
    return itemName:find('ammo_', 1, true) == 1 or itemName:find('ammo', 1, true) ~= nil
end

local function isArmorItemName(itemName)
    itemName = tostring(itemName or ''):lower()
    return itemName == 'armor' or itemName == 'body_armor' or itemName == 'bodyarmor' or itemName:find('armor', 1, true) ~= nil
end


local canonicalAmmoItem

local function findFirstAmmoStack(ownerType, ownerId, ammoName, includeAmmoSlot)
    ammoName = tostring(ammoName or ''):lower()
    if ammoName == '' then return nil end
    local requiredCanonical = canonicalAmmoItem and canonicalAmmoItem(ammoName) or ammoName

    local ammoSlot = (Config.Ammo and Config.Ammo.slot) or 'ammo'

    if includeAmmoSlot then
        local row = getItemAt(ownerType, ownerId, ammoSlot)
        if row and (canonicalAmmoItem and canonicalAmmoItem(row.item_name) or tostring(row.item_name or ''):lower()) == requiredCanonical and (tonumber(row.quantity) or 0) > 0 then
            return row
        end
    end

    -- Player inventory order: quick slots, pockets, backpack, then equipment.
    -- Skip weapon slot and optionally skip ammo slot so we can move the first normal stack into ammo slot.
    for _, slot in ipairs(allSlots()) do
        if slot ~= 'weapon' and (includeAmmoSlot or slot ~= ammoSlot) then
            local row = getItemAt(ownerType, ownerId, slot)
            if row and (canonicalAmmoItem and canonicalAmmoItem(row.item_name) or tostring(row.item_name or ''):lower()) == requiredCanonical and (tonumber(row.quantity) or 0) > 0 then
                return row
            end
        end
    end

    return nil
end

canonicalAmmoItem = function(ammoName)
    ammoName = tostring(ammoName or ''):lower()
    if ammoName == '' then return '' end
    local aliases = Config.Ammo and Config.Ammo.LegacyAliases or {}
    return aliases[ammoName] or ammoName
end

local function getCMWeaponAmmoItem(weaponName, metadata)
    if GetResourceState('cm-weapons') ~= 'started' then return nil end

    local candidates = {}
    local function addCandidate(v)
        v = tostring(v or '')
        if v ~= '' then candidates[#candidates + 1] = v end
    end

    addCandidate(weaponName)
    metadata = type(metadata) == 'table' and metadata or {}
    addCandidate(metadata.weaponHash or metadata.weapon_hash)
    addCandidate(metadata.weaponName or metadata.weapon_name)

    for _, candidate in ipairs(candidates) do
        local ok, ammo = pcall(function()
            return exports['cm-weapons']:GetWeaponAmmoItem(candidate)
        end)
        if ok and ammo and tostring(ammo) ~= '' then
            return canonicalAmmoItem(ammo)
        end

        ok, ammo = pcall(function()
            return exports['cm-weapons'].GetWeaponAmmoItem(candidate)
        end)
        if ok and ammo and tostring(ammo) ~= '' then
            return canonicalAmmoItem(ammo)
        end
    end

    return nil
end

local function inferAmmoForWeapon(weaponName, metadata)
    weaponName = tostring(weaponName or ''):lower()
    metadata = type(metadata) == 'table' and metadata or {}

    -- cm-weapons is the single source of truth. This prevents stale metadata or old
    -- inventory config from making guns request ammo_556/ammo_762/ammo_shotgun.
    local cmAmmo = getCMWeaponAmmoItem(weaponName, metadata)
    if cmAmmo and cmAmmo ~= '' then return cmAmmo end

    local explicit = metadata.ammo or metadata.ammoItem or metadata.ammo_item or metadata.ammoType or metadata.ammo_type or metadata.caliber
    explicit = explicit and tostring(explicit):lower() or ''
    if explicit ~= '' then
        if explicit:find('^ammo_') then return canonicalAmmoItem(explicit) end
        explicit = explicit:gsub('%s+', '_'):gsub('[^%w_]', '')
        if explicit ~= '' then return canonicalAmmoItem('ammo_' .. explicit) end
    end

    -- Safe fallbacks matching the fixed 7-ammo cm-weapons design.
    if weaponName:find('revolver', 1, true) or weaponName:find('doubleaction', 1, true) or weaponName:find('navyrevolver', 1, true) then return 'ammo_44magnum' end
    if weaponName:find('shotgun', 1, true) then return 'ammo_12gauge' end
    if weaponName:find('sniper', 1, true) or weaponName:find('marksman', 1, true) or weaponName:find('precisionrifle', 1, true) then return 'ammo_308win' end
    if weaponName:find('combatmg', 1, true) or weaponName:find('weapon_mg', 1, true) or weaponName:find('gusenberg', 1, true) or weaponName:find('minigun', 1, true) then return 'ammo_762nato' end
    if weaponName:find('smg', 1, true) or weaponName:find('combatpdw', 1, true) or weaponName:find('machinepistol', 1, true) or weaponName:find('tecpistol', 1, true) then return 'ammo_9x19_smg' end
    if weaponName:find('rifle', 1, true) or weaponName:find('carbine', 1, true) or weaponName:find('bullpup', 1, true) or weaponName:find('compactrifle', 1, true) then return 'ammo_556nato' end
    if weaponName:find('pistol', 1, true) then return 'ammo_9mm' end
    return 'ammo_9mm'
end

local function getEquippedWeaponAmmoConfig(ownerType, ownerId)
    local weaponRow = getItemAt(ownerType, ownerId, 'weapon')
    if not weaponRow then return nil, nil, 'No weapon equipped.' end

    local weaponName = tostring(weaponRow.item_name or ''):lower()
    local metadata = decode(weaponRow.metadata)

    local cmAmmo = getCMWeaponAmmoItem(weaponName, metadata)
    if cmAmmo and cmAmmo ~= '' then return { ammo = cmAmmo }, weaponName, nil end

    local weaponCfg = Config.Ammo and Config.Ammo.weapons and Config.Ammo.weapons[weaponName]
    if weaponCfg then
        weaponCfg.ammo = canonicalAmmoItem(weaponCfg.ammo)
        return weaponCfg, weaponName, nil
    end

    local inferredAmmo = inferAmmoForWeapon(weaponName, metadata)
    if inferredAmmo and inferredAmmo ~= '' then
        return { ammo = canonicalAmmoItem(inferredAmmo) }, weaponName, nil
    end

    return nil, weaponName, 'This weapon has no ammo config.'
end

syncCurrentWeaponAmmo = function(src)
    if Config.Ammo and Config.Ammo.enabled == false then return end

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return end

    local weaponRow = getItemAt(ownerType, ownerId, 'weapon')
    if not weaponRow then
        TriggerClientEvent('cm-inventory:client:setWeaponAmmo', src, nil, 0, nil)
        return
    end

    local weaponCfg, weaponName = getEquippedWeaponAmmoConfig(ownerType, ownerId)
    local requiredAmmo = weaponCfg and tostring(weaponCfg.ammo or ''):lower() or ''
    local ammoSlot = (Config.Ammo and Config.Ammo.slot) or 'ammo'
    local ammoRow = getItemAt(ownerType, ownerId, ammoSlot)
    local count = 0

    if requiredAmmo ~= '' and ammoRow and canonicalAmmoItem(ammoRow.item_name) == canonicalAmmoItem(requiredAmmo) then
        count = math.max(0, tonumber(ammoRow.quantity) or 0)
    end

    TriggerClientEvent('cm-inventory:client:setWeaponAmmo', src, weaponName, count, requiredAmmo)
end

local function EnsureAmmoSlotForWeaponInternal(src)
    if Config.Ammo and Config.Ammo.enabled == false then
        return false, 'Ammo system is disabled.'
    end

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end

    local ammoSlot = (Config.Ammo and Config.Ammo.slot) or 'ammo'
    local weaponCfg, weaponName, cfgErr = getEquippedWeaponAmmoConfig(ownerType, ownerId)
    if not weaponCfg then return false, cfgErr or 'No weapon ammo config.' end

    local requiredAmmo = tostring(weaponCfg.ammo or ''):lower()
    if requiredAmmo == '' then return false, 'Weapon ammo type is missing.' end

    local ammoAtSlot = getItemAt(ownerType, ownerId, ammoSlot)
    if ammoAtSlot and canonicalAmmoItem(ammoAtSlot.item_name) == canonicalAmmoItem(requiredAmmo) and (tonumber(ammoAtSlot.quantity) or 0) > 0 then
        if syncCurrentWeaponAmmo then syncCurrentWeaponAmmo(src) end
        return true, ('%s is already in ammo slot.'):format(tostring(ammoAtSlot.item_name or requiredAmmo)), ammoAtSlot
    end

    local found = findFirstAmmoStack(ownerType, ownerId, requiredAmmo, false)
    if not found then
        if syncCurrentWeaponAmmo then syncCurrentWeaponAmmo(src) end
        if ammoAtSlot then
            return false, ('Ammo slot has %s, but %s is required. Put %s in your bag to auto-swap.'):format(tostring(ammoAtSlot.item_name or 'unknown'), requiredAmmo, requiredAmmo)
        end
        return false, ('No %s found in inventory.'):format(requiredAmmo)
    end

    local fromSlot = tostring(found.slot)
    local moved, moveErr = MoveItemInternal(src, fromSlot, ammoSlot)
    if not moved then
        if syncCurrentWeaponAmmo then syncCurrentWeaponAmmo(src) end
        return false, moveErr or ('Could not move %s to ammo slot.'):format(requiredAmmo)
    end

    local newAmmoRow = getItemAt(ownerType, ownerId, ammoSlot)
    audit(ownerId, 'ammo_slot_fill', requiredAmmo, tonumber(found.quantity) or 1, fromSlot, ammoSlot, weaponName, decode(found.metadata))
    if syncCurrentWeaponAmmo then syncCurrentWeaponAmmo(src) end
    return true, ('Loaded %s for this weapon.'):format(requiredAmmo), newAmmoRow
end

local function saveRowMetadata(rowId, metadata)
    MySQL.update.await('UPDATE inventory_items SET metadata = ? WHERE id = ?', { encode(metadata), rowId })
end

local function setSlotDurability(ownerType, ownerId, slot, durability)
    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false end
    local metadata = decode(row.metadata)
    durability = math.max(0, math.min(100, math.floor(tonumber(durability) or 0)))
    metadata.durability = durability
    saveRowMetadata(row.id, metadata)
    return true, durability
end

local function reduceSlotDurability(ownerType, ownerId, slot, amount)
    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end
    local metadata = decode(row.metadata)
    local current = tonumber(metadata.durability)
    if current == nil then current = tonumber((getItemDef(row.item_name) or {}).durability) or 100 end
    current = math.max(0, current - (tonumber(amount) or 1))
    metadata.durability = math.floor(current)
    saveRowMetadata(row.id, metadata)
    return true, current
end

local function isBagItemName(itemName)
    itemName = tostring(itemName or ''):lower()
    if itemName:find('bag_level', 1, true) == 1 or itemName:find('backpack', 1, true) ~= nil then return true end
    local def = getItemDef(itemName) or {}
    local category = tostring(def.category or ''):lower()
    local equipSlot = tostring(def.equipmentSlot or def.equipSlot or ''):lower()
    return category == 'bag' or equipSlot == 'bag' or tonumber(def.bagLevel) ~= nil
end

