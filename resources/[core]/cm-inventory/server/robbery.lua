-- Trusted exact-row robbery seam. cm-gang owns physical authorization; this
-- module owns inventory visibility, capacity, metadata and atomic mutation.

local ROBBERY_CALLER = 'cm-gang'
local robberyTokens, robberyLocks = {}, {}

local function trustedRobberyCaller()
    return tostring(GetInvokingResource() or '') == ROBBERY_CALLER
end

local function protectedItem(itemName)
    if GetResourceState('cm-items') ~= 'started' then return true end
    local ok, value = pcall(function() return exports['cm-items']:IsRobberyProtected(itemName) end)
    return not ok or value == true
end

local function tokenId()
    return ('%08x%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
end

local function sanitizeRobberyRow(row)
    local def = getItemDef(row.item_name) or {}
    local metadata = decode(row.metadata)
    local slot = tostring(row.slot or ''):lower()
    local sourceArea = 'Inventory'
    if slot:find('^pocket%-') then
        sourceArea = 'Pockets'
    elseif slot:find('^quickaccess%-') then
        sourceArea = 'Fast Access'
    elseif isEquipmentSlot(slot) then
        sourceArea = 'Equipment'
    elseif slot:find('^backpack%-') then
        sourceArea = 'Backpack'
    end
    local fallback = tostring(row.item_name):gsub('^weapon_', ''):gsub('^ammo_', ''):gsub('_', ' '):gsub('(%a)([%w]*)', function(first, rest) return first:upper() .. rest:lower() end)
    local label = metadata.weaponLabel or metadata.weapon_label or metadata.displayName or metadata.label or def.label
    if not label or tostring(label) == '' or tostring(label):lower() == 'weapon' then label = fallback end
    return {
        token = tokenId(),
        itemName = tostring(row.item_name),
        label = tostring(label),
        quantity = math.max(0, math.floor(tonumber(row.quantity) or 0)),
        image = tostring(def.image or 'placeholder.png'),
        protected = protectedItem(row.item_name),
        sourceArea = sourceArea,
    }
end

local function visibleInGangSearch(row)
    local itemName = tostring(row.item_name or ''):lower()
    local slot = tostring(row.slot or ''):lower()
    local metadata = decode(row.metadata)
    local metadataCategory = tostring(metadata.category or metadata.categoryType or metadata.category_type or metadata.itemType or metadata.item_type or ''):lower()
    local def = getItemDef(itemName) or {}
    local category = tostring(def.category or def.type or ''):lower()

    return def.illegal == true
        or category == 'weapon' or category == 'ammo'
        or metadata.illegal == true
        or metadataCategory == 'weapon' or metadataCategory == 'ammo'
        or itemName:find('weapon_', 1, true) == 1
        or itemName:find('ammo_', 1, true) == 1
        or tostring(metadata.weaponHash or metadata.weapon_hash or metadata.weaponName or metadata.weapon_name or '') ~= ''
        or slot == 'weapon' or slot == 'ammo'
end

exports('GetRobberyInventory', function(victimSrc, actorSrc, visibility)
    if not trustedRobberyCaller() then return false, 'untrusted_resource', {} end
    victimSrc, actorSrc = tonumber(victimSrc), tonumber(actorSrc)
    if not victimSrc or not actorSrc or victimSrc == actorSrc then return false, 'invalid_players', {} end
    local ownerType, ownerId = getOwner(victimSrc)
    local _, actorId = getOwner(actorSrc)
    if not ownerId or not actorId or tostring(ownerId) == tostring(actorId) then return false, 'character_not_loaded', {} end
    local now, result = GetGameTimer(), {}
    robberyTokens[actorId] = {}
    for _, row in ipairs(getRows(ownerType, ownerId)) do
        local public = sanitizeRobberyRow(row)
        if public.quantity > 0 and (visibility ~= 'contraband' or visibleInGangSearch(row)) then
            robberyTokens[actorId][public.token] = {
                rowId = tonumber(row.id), victimId = tostring(ownerId), victimSrc = victimSrc,
                itemName = tostring(row.item_name), expiresAt = now + 15000,
            }
            result[#result + 1] = public
        end
    end
    return true, nil, result
end)

local function finish(lockKey, ok, reason, detail)
    robberyLocks[lockKey] = nil
    return ok, reason, detail
end

exports('TransferRobberyItem', function(victimSrc, actorSrc, token, requestedAmount)
    if not trustedRobberyCaller() then return false, 'untrusted_resource' end
    victimSrc, actorSrc = tonumber(victimSrc), tonumber(actorSrc)
    token = type(token) == 'string' and token:sub(1, 32) or ''
    local amount = math.floor(tonumber(requestedAmount) or 0)
    if not victimSrc or not actorSrc or victimSrc == actorSrc or token == '' or amount < 1 then return false, 'invalid_request' end
    local victimType, victimId = getOwner(victimSrc)
    local actorType, actorId = getOwner(actorSrc)
    victimId, actorId = victimId and tostring(victimId), actorId and tostring(actorId)
    if not victimId or not actorId or victimId == actorId then return false, 'character_not_loaded' end
    local grant = robberyTokens[actorId] and robberyTokens[actorId][token]
    robberyTokens[actorId] = nil -- every view is single-use, including failure
    if not grant or grant.expiresAt < GetGameTimer() or grant.victimId ~= victimId or grant.victimSrc ~= victimSrc then
        return false, 'stale_item'
    end
    local ids = { actorId, victimId }; table.sort(ids)
    local lockKey = ids[1] .. ':' .. ids[2]
    if robberyLocks[lockKey] then return false, 'inventory_busy' end
    robberyLocks[lockKey] = true
    local executed, result, resultReason, resultDetail = xpcall(function()
    local row = MySQL.single.await([[SELECT id,slot,item_name,quantity,metadata FROM inventory_items
        WHERE id=? AND owner_type=? AND owner_id=? LIMIT 1]], { grant.rowId, victimType, victimId })
    if not row or tostring(row.item_name) ~= grant.itemName or amount > (tonumber(row.quantity) or 0) then
        return finish(lockKey, false, 'stale_item')
    end
    if protectedItem(row.item_name) then return finish(lockKey, false, 'protected_item') end
    local bagOk = validateBagRemovalFromSlot(victimType, victimId, tostring(row.slot), row)
    if bagOk ~= true then return finish(lockKey, false, 'bag_in_use') end
    local carryOk = canCarry(actorType, actorId, row.item_name, amount)
    if carryOk ~= true then return finish(lockKey, false, 'cannot_carry') end

    local metadata = decode(row.metadata)
    local destination
    for _, candidate in ipairs(getRows(actorType, actorId)) do
        if rowCanStackWithMetadata(candidate, row.item_name, metadata) then destination = candidate; break end
    end
    local targetSlot = destination and tostring(destination.slot) or findEmptySlot(actorType, actorId)
    if not targetSlot then return finish(lockKey, false, 'inventory_full') end

    local statements
    if destination then
        statements = {
            { query = [[UPDATE inventory_items d JOIN inventory_items s ON s.id=?
                SET d.quantity=d.quantity+?, s.quantity=s.quantity-?
                WHERE d.id=? AND d.owner_type=? AND d.owner_id=?
                  AND s.owner_type=? AND s.owner_id=? AND s.quantity>=?]],
                values = { row.id, amount, amount, destination.id, actorType, actorId, victimType, victimId, amount } },
            { query = 'DELETE FROM inventory_items WHERE id=? AND owner_type=? AND owner_id=? AND quantity=0',
                values = { row.id, victimType, victimId } },
        }
    else
        statements = {
            { query = [[INSERT INTO inventory_items (owner_type,owner_id,slot,item_name,quantity,metadata)
                SELECT ?,?,?,item_name,?,metadata FROM inventory_items
                WHERE id=? AND owner_type=? AND owner_id=? AND quantity>=?]],
                values = { actorType, actorId, targetSlot, amount, row.id, victimType, victimId, amount } },
            { query = [[UPDATE inventory_items s SET s.quantity=s.quantity-?
                WHERE s.id=? AND s.owner_type=? AND s.owner_id=? AND s.quantity>=?
                  AND EXISTS (SELECT 1 FROM inventory_items d WHERE d.owner_type=? AND d.owner_id=?
                    AND d.slot=? AND d.item_name=s.item_name AND d.quantity=? AND d.metadata <=> s.metadata)]],
                values = { amount, row.id, victimType, victimId, amount, actorType, actorId, targetSlot, amount } },
            { query = 'DELETE FROM inventory_items WHERE id=? AND owner_type=? AND owner_id=? AND quantity=0',
                values = { row.id, victimType, victimId } },
        }
    end
    if MySQL.transaction.await(statements) ~= true then return finish(lockKey, false, 'transfer_failed') end
    local remaining = MySQL.scalar.await('SELECT quantity FROM inventory_items WHERE id=? AND owner_type=? AND owner_id=?', { row.id, victimType, victimId })
    local expected = (tonumber(row.quantity) or 0) - amount
    local received = MySQL.scalar.await('SELECT quantity FROM inventory_items WHERE owner_type=? AND owner_id=? AND slot=?', { actorType, actorId, targetSlot })
    local expectedReceived = destination and ((tonumber(destination.quantity) or 0) + amount) or amount
    if (remaining == nil and expected ~= 0) or (remaining ~= nil and tonumber(remaining) ~= expected)
        or tonumber(received) ~= expectedReceived then
        return finish(lockKey, false, 'source_changed')
    end
    audit(victimId, 'gang_robbery_out', row.item_name, amount, row.slot, targetSlot, 'gang_item_robbery', { actorCharacterId = actorId })
    audit(actorId, 'gang_robbery_in', row.item_name, amount, row.slot, targetSlot, 'gang_item_robbery', { targetCharacterId = victimId })
    if isEquipmentSlot(row.slot) then syncEquipmentSlot(victimSrc, row.slot) end
    if isEquipmentSlot(targetSlot) then syncEquipmentSlot(actorSrc, targetSlot) end
    sendInventorySmart(victimSrc); sendInventorySmart(actorSrc)
    return finish(lockKey, true, nil, { itemName = row.item_name, label = (getItemDef(row.item_name) or {}).label or row.item_name, quantity = amount })
    end, debug.traceback)
    robberyLocks[lockKey] = nil
    if not executed then
        print(('[CM-INVENTORY] trusted robbery transfer failed: %s'):format(tostring(result)))
        return false, 'transfer_failed'
    end
    return result, resultReason, resultDetail
end)

AddEventHandler('playerDropped', function()
    local _, ownerId = getOwner(source)
    if ownerId then robberyTokens[tostring(ownerId)] = nil end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then robberyTokens, robberyLocks = {}, {} end
end)
