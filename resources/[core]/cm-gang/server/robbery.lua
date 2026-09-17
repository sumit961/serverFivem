local RESOURCE = GetCurrentResourceName()
local PLAYERDATA = 'cm-playerdata'
local INVENTORY = 'cm-inventory'
local robberyLocks, robberyCooldowns, searchCooldowns, sourceCharacters = {}, {}, {}, {}

local function characterId(src)
    src = tonumber(src)
    if not src then return nil end
    local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterId(src) end)
    value = ok and tostring(value or '') or ''
    local id = value ~= '' and value:match('^%d+$') and value or nil
    if id then sourceCharacters[src] = id end
    return id
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-gang:client:notify', src, message, kind or 'error')
end

local function validate(actorSrc, targetSrc, permission)
    actorSrc, targetSrc = tonumber(actorSrc), tonumber(targetSrc)
    if not actorSrc or not targetSrc or actorSrc == targetSrc then return nil, 'invalid_target' end
    if not GetPlayerName(actorSrc) or not GetPlayerName(targetSrc) then return nil, 'player_offline' end
    local actorId, targetId = characterId(actorSrc), characterId(targetSrc)
    if not actorId or not targetId or actorId == targetId then return nil, 'character_not_loaded' end
    local decision = exports[RESOURCE]:GetPermissionDecision(actorId, permission)
    if type(decision) ~= 'table' or decision.allowed ~= true then return nil, 'not_authorized' end
    local membership = exports[RESOURCE]:GetGangForCharacter(actorId)
    if not membership or membership.enabled ~= true then return nil, 'gang_disabled' end
    if GetPlayerRoutingBucket(actorSrc) ~= GetPlayerRoutingBucket(targetSrc) then return nil, 'different_bucket' end
    local actorPed, targetPed = GetPlayerPed(actorSrc), GetPlayerPed(targetSrc)
    if actorPed == 0 or targetPed == 0 or not DoesEntityExist(actorPed) or not DoesEntityExist(targetPed) then
        return nil, 'entity_unavailable'
    end
    if #(GetEntityCoords(actorPed) - GetEntityCoords(targetPed)) > (tonumber(Config.Security.interactionDistance) or 3.0) then
        return nil, 'too_far'
    end
    return { actorSrc = actorSrc, targetSrc = targetSrc, actorId = actorId, targetId = targetId, gangId = membership.gangId }
end

exports('ValidateRobberyTarget', function(actorSrc, targetSrc, permission)
    if permission ~= 'gang.search' and permission ~= 'gang.rob_cash' and permission ~= 'gang.rob_items' then
        return nil, 'invalid_permission'
    end
    return validate(actorSrc, targetSrc, permission)
end)

local friendly = {
    invalid_target = 'That player is not a valid target.', player_offline = 'That player is no longer online.',
    character_not_loaded = 'Character data is not loaded.', not_authorized = 'Your rank cannot perform that gang action.',
    no_permission = 'Your rank cannot perform that gang action.', gang_disabled = 'Your gang is disabled.',
    different_bucket = 'That player is in another instance.', entity_unavailable = 'That player is unavailable.',
    too_far = 'That player is too far away.',
    rate_limited = 'Please wait before trying again.', robbery_busy = 'That player is already being searched or robbed.',
    invalid_amount = 'Enter a valid cash amount.', insufficient_funds = 'That player does not have that much cash.',
    money_busy = 'Cash balances are busy. Try again.', balance_changed = 'Cash balance changed. Try again.',
    inventory_unavailable = 'Inventory service is unavailable.', stale_item = 'That item is no longer available.',
    protected_item = 'That item cannot be stolen.', cannot_carry = 'You cannot carry that item.',
    inventory_full = 'Your inventory is full.', inventory_busy = 'Those inventories are busy. Try again.',
    bag_in_use = 'That equipped bag cannot be taken while it is in use.', source_changed = 'That item changed. Try again.',
    transfer_failed = 'Item transfer failed safely.', invalid_request = 'Invalid item request.',
    character_changed = 'Character changed during the robbery. Try again.',
}

lib.callback.register('cm-gang:server:getRobberyInventory', function(actorSrc, targetSrc, mode)
    local permission = mode == 'take' and 'gang.rob_items' or 'gang.search'
    local context, validationReason = validate(actorSrc, targetSrc, permission)
    if not context then return { ok = false, reason = validationReason or 'not_authorized' } end
    if GetResourceState(INVENTORY) ~= 'started' then return { ok = false, reason = 'inventory_unavailable' } end
    local now = GetGameTimer()
    if (searchCooldowns[context.actorId] or 0) > now then return { ok = false, reason = 'rate_limited' } end
    searchCooldowns[context.actorId] = now + ((tonumber(Config.Security.robberyCooldownSeconds) or 3) * 1000)
    local called, ok, reason, items = pcall(function()
        return exports[INVENTORY]:GetRobberyInventory(context.targetSrc, context.actorSrc, mode == 'search' and 'contraband' or nil)
    end)
    if not called then
        print(('[cm-gang] robbery inventory read failed: %s'):format(tostring(ok)))
        return { ok = false, reason = 'inventory_unavailable' }
    end
    if ok == true then
        MySQL.insert.await([[INSERT INTO cm_gang_activity
            (event_uid,gang_id,action,actor_character_id,target_character_id,detail)
            VALUES (?,?,'player_searched',?,?,?)]], {
            ('%s:player_searched:%d:%d'):format(RESOURCE, os.time(), math.random(100000, 999999)),
            context.gangId, context.actorId, context.targetId, json.encode({ mode = mode == 'take' and 'rob_items' or 'search' }),
        })
    end
    return { ok = ok == true, reason = reason, items = ok and items or {} }
end)

RegisterNetEvent('cm-gang:server:robItem', function(payload)
    local actorSrc = source
    notify(actorSrc, 'Direct item selection is disabled. Use Steal Item lottery.', 'error')
end)

RegisterNetEvent('cm-gang:server:robCash', function(payload)
    local actorSrc = source
    payload = type(payload) == 'table' and payload or {}
    local targetSrc = tonumber(payload.target)
    local context, reason = validate(actorSrc, targetSrc, 'gang.rob_cash')
    if not context then return notify(actorSrc, friendly[reason] or 'Cash robbery failed.') end
    local now = GetGameTimer()
    if (robberyCooldowns[context.actorId] or 0) > now then return notify(actorSrc, friendly.rate_limited) end
    if robberyLocks[context.targetId] then return notify(actorSrc, friendly.robbery_busy) end
    local balanceOk, cash = pcall(function() return exports[PLAYERDATA]:GetCash(targetSrc) end)
    local amount = balanceOk and math.floor(math.max(0, tonumber(cash) or 0) * 0.10) or 0
    if amount < 1 then return notify(actorSrc, 'That player does not have enough cash to steal 10%.') end
    robberyCooldowns[context.actorId] = now + ((tonumber(Config.Security.robberyCashCooldownSeconds) or 30) * 1000)
    robberyLocks[context.targetId] = true
    local ok, moved, transferReason = xpcall(function()
        local current, revalidateReason = validate(actorSrc, targetSrc, 'gang.rob_cash')
        if not current then return false, revalidateReason end
        if current.actorId ~= context.actorId or current.targetId ~= context.targetId or current.gangId ~= context.gangId then
            return false, 'character_changed'
        end
        return exports[PLAYERDATA]:TransferCashBetweenCharactersAtomic(targetSrc, actorSrc, amount, 'gang_cash_robbery', {
            gang_id = current.gangId, actor_character_id = current.actorId, target_character_id = current.targetId,
        })
    end, debug.traceback)
    robberyLocks[context.targetId] = nil
    if not ok then
        print(('[cm-gang] cash robbery failed: %s'):format(tostring(moved)))
        return notify(actorSrc, 'Cash robbery failed.')
    end
    if moved ~= true then return notify(actorSrc, friendly[transferReason] or 'Cash robbery failed.') end
    MySQL.insert.await([[
        INSERT INTO cm_gang_activity (event_uid, gang_id, action, actor_character_id, target_character_id, detail)
        VALUES (?, ?, 'cash_stolen', ?, ?, ?)
    ]], {
        ('%s:cash_stolen:%d:%d'):format(RESOURCE, os.time(), math.random(100000, 999999)),
        context.gangId, context.actorId, context.targetId, json.encode({ amount = amount }),
    })
    notify(actorSrc, ('You took $%d cash.'):format(amount), 'success')
    notify(targetSrc, ('$%d cash was taken from you.'):format(amount), 'error')
end)

RegisterNetEvent('cm-gang:server:robRandomItem', function(payload)
    local actorSrc = source
    payload = type(payload) == 'table' and payload or {}
    local targetSrc = tonumber(payload.target)
    local context, reason = validate(actorSrc, targetSrc, 'gang.rob_items')
    if not context then return notify(actorSrc, friendly[reason] or 'Item robbery failed.') end
    local now = GetGameTimer()
    if (robberyCooldowns[context.actorId] or 0) > now then return notify(actorSrc, friendly.rate_limited) end
    local chance = math.max(1, math.min(100, math.floor(tonumber(Config.Security.robberyLotteryChancePercent) or 15)))
    robberyCooldowns[context.actorId] = now + ((tonumber(Config.Security.robberyLotteryCooldownSeconds) or 60) * 1000)
    if math.random(1, 100) > chance then return notify(actorSrc, 'You searched their pockets but found nothing.', 'inform') end
    local called, ok, inventoryReason, items = pcall(function()
        return exports[INVENTORY]:GetRobberyInventory(context.targetSrc, context.actorSrc)
    end)
    if not called or ok ~= true then return notify(actorSrc, friendly[inventoryReason] or 'Item robbery failed.') end
    local candidates = {}
    for _, item in ipairs(items or {}) do
        if item.protected ~= true and (tonumber(item.quantity) or 0) > 0 then candidates[#candidates + 1] = item end
    end
    if #candidates == 0 then return notify(actorSrc, 'You searched their pockets but found nothing.', 'inform') end
    local selected = candidates[math.random(1, #candidates)]
    local current, revalidateReason = validate(actorSrc, targetSrc, 'gang.rob_items')
    if not current or current.actorId ~= context.actorId or current.targetId ~= context.targetId then
        return notify(actorSrc, friendly[revalidateReason] or friendly.character_changed)
    end
    local transferOk, moved, transferReason, detail = pcall(function()
        return exports[INVENTORY]:TransferRobberyItem(targetSrc, actorSrc, selected.token, 1)
    end)
    if not transferOk or moved ~= true then return notify(actorSrc, friendly[transferReason] or 'Item robbery failed.') end
    detail = type(detail) == 'table' and detail or {}
    MySQL.insert.await([[INSERT INTO cm_gang_activity
        (event_uid,gang_id,action,actor_character_id,target_character_id,detail)
        VALUES (?,?,'lottery_item_stolen',?,?,?)]], {
        ('%s:lottery_item_stolen:%d:%d'):format(RESOURCE, os.time(), math.random(100000, 999999)),
        context.gangId, context.actorId, context.targetId,
        json.encode({ item = tostring(detail.itemName or selected.itemName or 'unknown'), quantity = 1, chance = chance }),
    })
    notify(actorSrc, ('Lucky find: you stole 1x %s.'):format(tostring(detail.label or selected.label or selected.itemName)), 'success')
    notify(targetSrc, ('1x %s was stolen from you.'):format(tostring(detail.label or selected.label or selected.itemName)), 'error')
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    local id = data and tostring(data.charId or data.characterId or '') or ''
    if id:match('^%d+$') then sourceCharacters[tonumber(src)] = id end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    local id = sourceCharacters[src] or characterId(src)
    sourceCharacters[src] = nil
    if id then robberyLocks[id], robberyCooldowns[id], searchCooldowns[id] = nil, nil, nil end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == RESOURCE then robberyLocks, robberyCooldowns, searchCooldowns, sourceCharacters = {}, {}, {}, {} end
end)
