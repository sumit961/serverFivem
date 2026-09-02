-- cm-inventory/exports.lua
-- Split from legacy server/main.lua. Loaded by server/main.lua bootloader in this exact order.

exports('AddItem', function(...)
    local src, itemName, amount, metadata, reason, slot = normalizeExportArgs(...)
    local ok, placedSlotOrReason = AddItemInternal(src, itemName, amount, metadata, reason, slot)

    -- If another resource adds directly into an equipment slot, immediately apply it
    -- and refresh the UI. This is used by starter character clothes.
    if ok and src and tonumber(src) and tonumber(src) > 0 then
        local placedSlot = tostring(placedSlotOrReason or '')
        if isEquipmentSlot(placedSlot) then
            syncEquipmentSlot(tonumber(src), placedSlot)
        end
        sendInventorySmart(tonumber(src))
    end

    return ok, placedSlotOrReason
end)

exports('RemoveItem', function(...)
    local src, itemName, amount, metadata, reason = normalizeExportArgs(...)
    return RemoveItemInternal(src, itemName, amount, metadata, reason)
end)

exports('MoveItem', function(...)
    local src, fromSlot, toSlot = normalizeExportArgs(...)
    return MoveItemInternal(src, tostring(fromSlot or ''), tostring(toSlot or ''))
end)

exports('HasItem', function(...)
    local src, itemName, amount = normalizeExportArgs(...)
    return HasItemInternal(src, itemName, amount)
end)

exports('CanCarryItem', function(...)
    local src, itemName, amount = normalizeExportArgs(...)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    return canCarry(ownerType, ownerId, itemName, amount)
end)

exports('GetInventory', function(...)
    local src = normalizeExportArgs(...)
    return buildInventoryPayload(src)
end)

-- Trusted server-resource consumable durability contract. Inventory owns the
-- exact row, metadata update and final empty-container removal.
local ConsumableDurabilityLocks = {}
local function usableDurabilityRow(src, itemName)
    src, itemName = tonumber(src), tostring(itemName or ''):lower()
    if not src or src <= 0 or itemName == '' then return nil, nil, nil, 'invalid_request' end
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return nil, nil, nil, 'character_not_loaded' end
    local rows = MySQL.query.await([[SELECT id,slot,item_name,quantity,metadata FROM inventory_items
        WHERE owner_type=? AND owner_id=? AND item_name=? ORDER BY id ASC]], { ownerType, tostring(ownerId), itemName }) or {}
    local defaultDurability = tonumber((getItemDef(itemName) or {}).durability) or 100
    for _, row in ipairs(rows) do
        local metadata = decode(row.metadata)
        local durability = math.max(0, math.min(100, tonumber(metadata.durability) or defaultDurability))
        if (tonumber(row.quantity) or 0) > 0 and durability > 0 then return row, metadata, durability, nil, ownerId end
    end
    return nil, nil, nil, 'item_empty', ownerId
end

exports('HasItemDurability', function(src, itemName)
    local row, _, durability, reason = usableDurabilityRow(src, itemName)
    return row ~= nil, durability or 0, reason
end)

exports('ConsumeItemDurability', function(src, itemName, amount, reason)
    local invoking = tostring(GetInvokingResource() or '')
    if invoking == '' or invoking == GetCurrentResourceName() then return false, 0, 'trusted_resource_required' end
    src, itemName = tonumber(src), tostring(itemName or ''):lower()
    amount = math.max(1, math.min(100, math.floor(tonumber(amount) or 1)))
    local lockKey = ('%s:%s'):format(tostring(src), itemName)
    if ConsumableDurabilityLocks[lockKey] then return false, 0, 'item_in_use' end
    ConsumableDurabilityLocks[lockKey] = true
    local function finish(ok, remaining, why) ConsumableDurabilityLocks[lockKey] = nil; return ok, remaining, why end
    local row, metadata, durability, findReason, ownerId = usableDurabilityRow(src, itemName)
    if not row then return finish(false, 0, findReason) end
    local remaining = math.max(0, durability - amount)
    local quantity = math.max(1, tonumber(row.quantity) or 1)
    local changed
    if remaining <= 0 and quantity <= 1 then
        changed = MySQL.update.await('DELETE FROM inventory_items WHERE id=? AND quantity=1', { tonumber(row.id) })
    else
        metadata.durability = remaining <= 0 and 100 or remaining
        changed = MySQL.update.await('UPDATE inventory_items SET quantity=?,metadata=? WHERE id=? AND quantity=?', {
            remaining <= 0 and quantity - 1 or quantity, encode(metadata), tonumber(row.id), quantity
        })
    end
    if tonumber(changed) ~= 1 then return finish(false, durability, 'inventory_state_changed') end
    audit(ownerId, 'consume_durability', itemName, 1, row.slot, row.slot, tostring(reason or 'durability_use'), {
        consumed = amount, durabilityBefore = durability, durabilityAfter = remaining
    })
    sendInventorySmart(src)
    return finish(true, remaining, nil)
end)

-- Trusted organization lifecycle cleanup. Removes only items whose stored
-- metadata identifies them as an armory issue from the requested issuer; it
-- never removes an identically named personal weapon or ammunition stack.
local function reclaimArmoryIssues(ownerId, issuer, reason, src)
    issuer = tostring(issuer or ''):lower()
    ownerId = ownerId and tostring(ownerId) or nil
    if not ownerId or ownerId == '' or issuer == '' then return false, 'invalid_request', {} end
    local ownerType = Config.OwnerType or 'character'

    local rows = MySQL.query.await([[SELECT id,slot,item_name,quantity,metadata FROM inventory_items
        WHERE owner_type=? AND owner_id=?]], { ownerType, tostring(ownerId) }) or {}
    local statements, removed = {}, {}
    for _, row in ipairs(rows) do
        local metadata = decode(row.metadata)
        local metadataIssuer = tostring(metadata.licenseIssuer or metadata.issuedBy or ''):lower()
        if metadata.armoryIssue == true and metadataIssuer == issuer then
            statements[#statements + 1] = { query = 'DELETE FROM inventory_items WHERE id=?', values = { tonumber(row.id) } }
            removed[#removed + 1] = {
                itemName = tostring(row.item_name), quantity = tonumber(row.quantity) or 1,
                issueId = tonumber(metadata.issueId), licenseNumber = tostring(metadata.issueLicenseNumber or metadata.licenseNumber or ''),
            }
        end
    end
    if #statements == 0 then return true, nil, removed end
    if MySQL.transaction.await(statements) ~= true then return false, 'inventory_transaction_failed', {} end
    for _, item in ipairs(removed) do
        audit(ownerId, 'organization_issue_reclaimed', item.itemName, item.quantity, nil, nil,
            tostring(reason or 'organization_duty_cleanup'), { issuer = issuer, issueId = item.issueId, licenseNumber = item.licenseNumber })
    end
    if src and GetPlayerName(src) then
        sendInventorySmart(src)
        TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src)
    end
    return true, nil, removed
end

exports('ReclaimArmoryIssues', function(src, issuer, reason)
    src = tonumber(src)
    if not src or src <= 0 then return false, 'invalid_source', {} end
    local _, ownerId = getOwner(src)
    if not ownerId then return false, 'character_not_loaded', {} end
    return reclaimArmoryIssues(ownerId, issuer, reason, src)
end)

exports('ReclaimArmoryIssuesForCharacter', function(characterId, issuer, reason)
    return reclaimArmoryIssues(characterId, issuer, reason, nil)
end)

-- Trusted-resource evidence transfer. Moves one exact inventory row into an
-- external container atomically, preserving serial/licence metadata. The
-- caller supplies the player's server source only as a session lookup; the
-- authoritative owner and row are resolved here.
local EvidenceTransferLocks = {}
exports('TransferItemToContainer', function(...)
    local args = { ... }
    if type(args[1]) == 'table' then table.remove(args, 1) end
    local src, sourceSlot = tonumber(args[1]), tostring(args[2] or '')
    local targetType, targetId = tostring(args[3] or ''), tostring(args[4] or '')
    local prefix = tostring(args[5] or 'evidence-'):sub(1, 35)
    local slotCount = math.max(1, math.min(200, math.floor(tonumber(args[6]) or 100)))
    local reason = tostring(args[7] or 'trusted_container_transfer'):sub(1, 100)
    local expectedItem = tostring(args[8] or ''):lower()
    local invoking = tostring(GetInvokingResource() or '')
    if invoking == '' or invoking == GetCurrentResourceName() then return false, 'External trusted resource required.' end
    if not src or sourceSlot == '' or targetType == '' or targetId == '' or prefix == '' then return false, 'Invalid transfer.' end
    local lockKey = ('%s:%s'):format(src, sourceSlot)
    if EvidenceTransferLocks[lockKey] then return false, 'That item is already being transferred.' end
    EvidenceTransferLocks[lockKey] = true
    local function finish(ok, message) EvidenceTransferLocks[lockKey] = nil; return ok, message end
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return finish(false, 'No character owner found.') end
    local row = getItemAt(ownerType, ownerId, sourceSlot)
    if not row or (tonumber(row.quantity) or 0) < 1 then return finish(false, 'The source item no longer exists.') end
    if expectedItem~='' and tostring(row.item_name):lower()~=expectedItem then return finish(false,'The source item does not match the requested stock item.') end
    local targetSlot
    for index = 1, slotCount do
        local candidate = prefix .. index
        if not getItemAt(targetType, targetId, candidate) then targetSlot = candidate; break end
    end
    if not targetSlot then return finish(false, 'The evidence container is full.') end
    local quantity = math.max(1, tonumber(row.quantity) or 1)
    local ok = MySQL.transaction.await({
        { query = [[INSERT INTO inventory_items (owner_type,owner_id,slot,item_name,quantity,metadata)
            SELECT ?,?,?,item_name,quantity,metadata FROM inventory_items
            WHERE id=? AND owner_type=? AND owner_id=? AND slot=?]],
            values = { targetType, targetId, targetSlot, row.id, ownerType, tostring(ownerId), sourceSlot } },
        { query = 'DELETE FROM inventory_items WHERE id = ? AND owner_type = ? AND owner_id = ? AND slot = ?',
            values = { row.id, ownerType, tostring(ownerId), sourceSlot } },
    })
    if not ok then return finish(false, 'Evidence transfer failed safely.') end
    if not getItemAt(targetType, targetId, targetSlot) then return finish(false, 'The source item changed before transfer.') end
    audit(ownerId, 'evidence_transfer_out', row.item_name, quantity, sourceSlot, targetSlot, reason,
        { evidenceOwnerType = targetType, evidenceOwnerId = targetId, invokingResource = invoking })
    if isEquipmentSlot(sourceSlot) then syncEquipmentSlot(src, sourceSlot) end
    sendInventorySmart(src)
    return finish(true, { itemName = row.item_name, quantity = quantity, metadata = decode(row.metadata), targetSlot = targetSlot })
end)

exports('GetEquippedWeaponState',function(src)
    if GetInvokingResource()~='cm-playerdata'then return nil,'untrusted_resource'end
    src=tonumber(src);local ownerType,ownerId=getOwner(src);if not ownerId then return nil,'character_not_loaded'end
    local weapon=getItemAt(ownerType,ownerId,'weapon');local ammoSlot=(Config.Ammo and Config.Ammo.slot)or'ammo';local ammo=getItemAt(ownerType,ownerId,ammoSlot)
    return{weapon=weapon and tostring(weapon.item_name):lower()or nil,weaponMetadata=weapon and decode(weapon.metadata)or nil,ammo=ammo and tostring(ammo.item_name):lower()or nil,ammoQuantity=ammo and math.max(0,tonumber(ammo.quantity)or 0)or 0}
end)

exports('ResyncAuthoritativeEquipment',function(src)
    if GetInvokingResource()~='cm-playerdata'then return false,'untrusted_resource'end
    src=tonumber(src);if not src or not GetPlayerName(src)then return false,'player_unavailable'end
    local _,ownerId=getOwner(src);if not ownerId then return false,'character_not_loaded'end
    syncAllEquipment(src);return true
end)

-- Trusted reverse of TransferItemToContainer. Used by stock-backed organization
-- armories to return the exact stored row (serial/durability/metadata intact).
local ContainerReturnLocks={}
exports('TransferContainerItemToPlayer',function(src,targetType,targetId,sourceSlot)
    if GetInvokingResource()~='cm-gang' then return false,'Untrusted resource.' end
    src,targetType,targetId,sourceSlot=tonumber(src),tostring(targetType or ''),tostring(targetId or ''),tostring(sourceSlot or '')
    if not src or targetType=='' or targetId=='' or sourceSlot=='' then return false,'Invalid transfer.' end
    local key=targetType..':'..targetId..':'..sourceSlot; if ContainerReturnLocks[key] then return false,'Transfer busy.' end; ContainerReturnLocks[key]=true
    local function done(ok,value) ContainerReturnLocks[key]=nil; return ok,value end
    local playerType,playerId=getOwner(src); if not playerId then return done(false,'Character not loaded.') end
    local row=getItemAt(targetType,targetId,sourceSlot); if not row then return done(false,'Stock row missing.') end
    local amount=math.max(1,tonumber(row.quantity) or 1); local carry,carryReason=canCarry(playerType,playerId,row.item_name,amount); if not carry then return done(false,carryReason) end
    local metadata=decode(row.metadata); local destination=findStackTarget(playerType,playerId,row.item_name,metadata,nil); local slot=destination and destination.slot or findEmptySlot(playerType,playerId)
    if not slot then return done(false,'No empty inventory slot.') end
    local statements
    if destination then statements={{query='UPDATE inventory_items SET quantity=quantity+? WHERE id=?',values={amount,destination.id}},{query='DELETE FROM inventory_items WHERE id=? AND owner_type=? AND owner_id=? AND slot=?',values={row.id,targetType,targetId,sourceSlot}}}
    else statements={{query=[[INSERT INTO inventory_items(owner_type,owner_id,slot,item_name,quantity,metadata) SELECT ?,?,?,item_name,quantity,metadata FROM inventory_items WHERE id=? AND owner_type=? AND owner_id=? AND slot=?]],values={playerType,tostring(playerId),slot,row.id,targetType,targetId,sourceSlot}},{query='DELETE FROM inventory_items WHERE id=? AND owner_type=? AND owner_id=? AND slot=?',values={row.id,targetType,targetId,sourceSlot}}} end
    if MySQL.transaction.await(statements)~=true then return done(false,'Inventory transaction failed.') end
    audit(playerId,'organization_stock_withdraw',row.item_name,amount,sourceSlot,slot,'gang_armory_withdraw',{containerType=targetType,containerId=targetId}); sendInventorySmart(src)
    return done(true,{itemName=tostring(row.item_name),quantity=amount,metadata=metadata})
end)


exports('GiveItemToNearby', function(...)
    local src, slot, amount = normalizeExportArgs(...)
    return GiveItemInternal(src, tostring(slot or ''), tonumber(amount) or 1)
end)

exports('CreateUseableItem', function(...)
    -- Same-resource/local function support only. Cross-resource Lua callbacks are unreliable in FiveM exports.
    local itemName, cb = normalizeExportArgs(...)

    if type(itemName) == 'string' and type(cb) == 'function' then
        UseableItems[itemName:lower()] = cb
        print(('[CM-INVENTORY] Usable item registered with function: %s'):format(itemName:lower()))
        return true
    end

    print(('[CM-INVENTORY] CreateUseableItem failed. Use RegisterUseableItem(resource, export) for cross-resource items. itemName=%s cbType=%s'):format(tostring(itemName), type(cb)))
    return false
end)

exports('ReloadWeapon', function(...)
    local src = normalizeExportArgs(...)
    return ReloadWeaponInternal(src)
end)

exports('RegisterUseableItem', function(...)
    -- Recommended cross-resource registration:
    -- exports['cm-inventory'].RegisterUseableItem('bandage', 'cm-itemactions', 'UseItem')
    -- exports['cm-inventory']:RegisterUseableItem('bandage', 'cm-itemactions', 'UseItem')
    local itemName, resourceName, exportName = normalizeExportArgs(...)

    if type(itemName) ~= 'string' or itemName == '' then
        print('[CM-INVENTORY] RegisterUseableItem failed: invalid itemName')
        return false
    end

    if type(resourceName) ~= 'string' or resourceName == '' then
        print(('[CM-INVENTORY] RegisterUseableItem failed for %s: invalid resourceName'):format(itemName))
        return false
    end

    if type(exportName) ~= 'string' or exportName == '' then
        print(('[CM-INVENTORY] RegisterUseableItem failed for %s: invalid exportName'):format(itemName))
        return false
    end

    UseableItems[itemName:lower()] = {
        resource = resourceName,
        export = exportName
    }

    print(('[CM-INVENTORY] Usable item registered: %s -> %s.%s'):format(itemName:lower(), resourceName, exportName))
    return true
end)

CreateThread(function()
    math.randomseed(os.time())
    ensureTables()
    cleanupDrops()
    sendDrops(-1)
    print('[CM-INVENTORY] Started v4.0-exportfix')
end)

exports('OpenExternalInventory', function(...)
    local args = { ... }
    if type(args[1]) == 'table' and args[2] ~= nil then table.remove(args, 1) end
    return OpenExternalInventoryInternal(tonumber(args[1]), args[2] or {})
end)

exports('CloseExternalInventory', function(...)
    local args = { ... }
    if type(args[1]) == 'table' and args[2] ~= nil then table.remove(args, 1) end
    return CloseExternalInventoryInternal(tonumber(args[1]))
end)

exports('GetOpenExternalInventory', function(...)
    local args = { ... }
    if type(args[1]) == 'table' and args[2] ~= nil then table.remove(args, 1) end
    local ctx = ActiveExternalInventories[tonumber(args[1])]
    if not ctx then return nil end
    return {
        ownerType = ctx.ownerType,
        ownerId = ctx.ownerId,
        kind = ctx.kind,
        label = ctx.label,
        slots = ctx.slots,
        slotPrefix = ctx.slotPrefix,
        data = ctx.data
    }
end)
