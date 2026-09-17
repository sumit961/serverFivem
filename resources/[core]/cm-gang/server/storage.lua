local RESOURCE, PLAYERDATA, INVENTORY = GetCurrentResourceName(), 'cm-playerdata', 'cm-inventory'
local armoryLocks, armoryLockOwners, armoryCooldowns, armoryCharactersBySource = {}, {}, {}, {}
local armorySettingsCache = {}

local function armorySettingsKey(gangId)
    return ('cm_gang:armory_settings:%s'):format(tostring(gangId):gsub('[^%w_-]', ''))
end

local function normalizeArmorySettings(value)
    value = type(value) == 'table' and value or {}
    local cooldownMinutes = tonumber(value.cooldownMinutes)
    if cooldownMinutes == nil then
        local legacySeconds = tonumber(value.cooldownSeconds)
        cooldownMinutes = legacySeconds and (legacySeconds <= 0 and 0 or math.max(1, math.ceil(legacySeconds / 60))) or 1
    end
    return {
        open = value.open ~= false,
        weaponLimit = math.max(1, math.min(10, math.floor(tonumber(value.weaponLimit) or 10))),
        ammoLimit = math.max(1, math.min(1000, math.floor(tonumber(value.ammoLimit) or 1000))),
        cooldownMinutes = math.max(0, math.min(60, math.floor(cooldownMinutes))),
    }
end

local function armorySettings(gangId)
    gangId = tostring(gangId)
    if armorySettingsCache[gangId] then return armorySettingsCache[gangId] end
    local raw = GetResourceKvpString(armorySettingsKey(gangId))
    local decoded
    if raw then
        local ok, value = pcall(json.decode, raw)
        if ok then decoded = value end
    end
    armorySettingsCache[gangId] = normalizeArmorySettings(decoded)
    return armorySettingsCache[gangId]
end

local function characterIdForSource(src)
    local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterId(tonumber(src)) end)
    value = ok and tostring(value or '') or ''
    return value:match('^%d+$') and value or nil
end

local function memberContext(src, permission)
    local characterId = characterIdForSource(src)
    if not characterId then return nil, 'character_not_loaded' end
    local member = exports[RESOURCE]:GetGangForCharacter(characterId)
    if type(member) ~= 'table' or member.enabled ~= true then return nil, 'not_in_enabled_gang' end
    if not exports[RESOURCE]:HasPermission(characterId, permission) then return nil, 'no_permission' end
    return { source = tonumber(src), characterId = characterId, member = member }
end

local function facilityFor(context, facilityType)
    local row = MySQL.single.await([[SELECT enabled,x,y,z,routing_bucket,display_name,role_label
        FROM cm_gang_facilities WHERE gang_id=? AND facility_type=? LIMIT 1]],
        { context.member.gangId, facilityType })
    if not row or not CMGangDbTrue(row.enabled) then return nil, 'facility_disabled' end
    local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
    if not x or not y or not z then return nil, 'facility_not_configured' end
    if GetPlayerRoutingBucket(context.source) ~= (tonumber(row.routing_bucket) or 0) then return nil, 'wrong_routing_bucket' end
    local ped = GetPlayerPed(context.source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil, 'player_entity_unavailable' end
    if #(GetEntityCoords(ped) - vector3(x, y, z)) > (Config.Storage.facilityDistance or 3.0) then return nil, 'too_far_away' end
    return row
end

local function logActivity(context, action, detail)
    MySQL.insert.await([[INSERT INTO cm_gang_activity
        (event_uid,gang_id,action,actor_character_id,detail) VALUES (?,?,?,?,?)]], {
        ('%s:%s:%d:%d'):format(RESOURCE, action, os.time(), math.random(100000, 999999)),
        context.member.gangId, action, context.characterId, json.encode(detail or {}),
    })
end

exports('ValidateGangStashAccess', function(src, ownerType, ownerId)
    local context, reason = memberContext(src, 'gang.stash')
    if not context then return false, reason end
    if tostring(ownerType) ~= 'gang_stash' or tostring(ownerId) ~= context.member.gangId then
        return false, 'stash_identity_mismatch'
    end
    local facility, facilityReason = facilityFor(context, 'headquarters')
    if not facility then return false, facilityReason end
    return true
end)

exports('RecordGangStashMovement', function(src, ownerType, ownerId, movement, itemId, quantity)
    local context = memberContext(src, 'gang.stash')
    if not context or tostring(ownerType) ~= 'gang_stash' or tostring(ownerId) ~= context.member.gangId then return false end
    if not facilityFor(context, 'headquarters') then return false end
    movement = movement == 'deposit' and 'stash_deposit' or movement == 'withdraw' and 'stash_withdraw' or nil
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    itemId = tostring(itemId or ''):lower():sub(1, 96)
    if not movement or itemId == '' then return false end
    logActivity(context, movement, { itemId = itemId, quantity = quantity })
    return true
end)

lib.callback.register('cm-gang:server:openStash', function(src)
    local context, reason = memberContext(src, 'gang.stash')
    if not context then return { ok = false, reason = reason } end
    local facility, facilityReason = facilityFor(context, 'headquarters')
    if not facility then return { ok = false, reason = facilityReason } end
    if GetResourceState(INVENTORY) ~= 'started' then return { ok = false, reason = 'inventory_unavailable' } end
    local ok, opened, openReason = pcall(function()
        return exports[INVENTORY]:OpenExternalInventory(src, {
            ownerType = 'gang_stash', ownerId = context.member.gangId,
            slots = Config.Storage.stashSlots or 60, displaySlots = 30, slotPrefix = 'gang-',
            label = tostring(facility.display_name or context.member.displayName) .. ' Stash',
            subtitle = tostring(facility.role_label or 'Shared gang storage'), kind = 'gang_stash',
            accessExport = 'ValidateGangStashAccess', data = { gangId = context.member.gangId },
            activityExport = 'RecordGangStashMovement',
        })
    end)
    if not ok or opened ~= true then return { ok = false, reason = openReason or 'stash_open_failed' } end
    return { ok = true }
end)

-- Armory backend moved onto the shared, multi-tenant cm-law/cm_legal_armory_*
-- schema (see cm-law/server/armory.lua's GetExternalArmory/
-- CheckoutExternalArmoryItem exports). cm-gang still owns membership,
-- rank-tier, and facility-proximity checks -- it just no longer keeps its
-- own catalog/stock/issue tables. Each of the five fixed gangs is namespaced
-- as 'gang:<gangId>' so it can never collide with cm-law's own
-- Config.Organizations ids or with cm-family's 'family:<id>' orgs.
local function gangOrgId(gangId) return 'gang:' .. tostring(gangId) end

local function memberArmoryContext(context)
    return {
        characterId = context.characterId,
        tier = tonumber(context.member.tier) or 0,
        isLeader = context.member.isLeader == true,
        canManage = context.member.isLeader == true or context.member.permissions['gang.manage_armory'] == true,
    }
end

lib.callback.register('cm-gang:server:getArmory', function(src)
    local characterId = characterIdForSource(src)
    local member = characterId and exports[RESOURCE]:GetGangForCharacter(characterId) or nil
    local canUse = characterId and exports[RESOURCE]:HasPermission(characterId, 'gang.armory') == true
    local canManage = characterId and exports[RESOURCE]:HasPermission(characterId, 'gang.manage_armory') == true
    local context = member and member.enabled == true and (canUse or canManage) and { source=tonumber(src), characterId=characterId, member=member } or nil
    local reason = not characterId and 'character_not_loaded' or not member and 'not_in_enabled_gang' or 'no_permission'
    if not context then return { ok = false, reason = reason } end
    local facility, facilityReason = facilityFor(context, 'headquarters')
    if not facility then return { ok = false, reason = facilityReason } end
    local settings = armorySettings(context.member.gangId)
    if not settings.open and not canManage then return { ok = false, reason = 'armory_closed' } end
    local ok, result = pcall(function()
        return exports['cm-law']:GetExternalArmory(gangOrgId(context.member.gangId), memberArmoryContext(context))
    end)
    if not ok or not result or result.ok ~= true then return { ok = false, reason = 'armory_unavailable' } end
    local items = {}
    for _, item in ipairs(result.items or {}) do
        items[#items + 1] = {
            itemId = item.itemName, label = item.label,
            itemType = item.itemType == 'vest' and 'armor' or item.itemType,
            quantity = tonumber(item.issueAmount) or 1, limit = 0,
            stockQuantity = tonumber(item.stock) or 0, minimumTier = tonumber(item.minTier) or 0,
            image = item.image, group = tostring(item.itemType == 'vest' and 'armor' or item.itemType),
            ammoItem = (item.ammoItem and item.ammoItem ~= '') and item.ammoItem or nil,
            armorValue = tonumber(item.armorValue) or 0,
            description = item.description,
        }
    end
    return { ok = true, items = items, settings = settings, canManage = canManage }
end)

lib.callback.register('cm-gang:server:saveArmorySettings', function(src, request)
    local context, reason = memberContext(src, 'gang.manage_armory')
    if not context then return { ok = false, reason = reason } end
    local _, facilityReason = facilityFor(context, 'headquarters')
    if facilityReason then return { ok = false, reason = facilityReason } end
    request = type(request) == 'table' and request or {}
    if type(request.open) ~= 'boolean' then return { ok = false, reason = 'invalid_armory_state' } end
    local weaponLimit, ammoLimit, cooldownMinutes = tonumber(request.weaponLimit), tonumber(request.ammoLimit), tonumber(request.cooldownMinutes)
    if not weaponLimit or weaponLimit ~= math.floor(weaponLimit) or weaponLimit < 1 or weaponLimit > 10 then return { ok=false, reason='weapon_limit_must_be_1_to_10' } end
    if not ammoLimit or ammoLimit ~= math.floor(ammoLimit) or ammoLimit < 1 or ammoLimit > 1000 then return { ok=false, reason='ammo_limit_must_be_1_to_1000' } end
    if not cooldownMinutes or cooldownMinutes ~= math.floor(cooldownMinutes) or cooldownMinutes < 0 or cooldownMinutes > 60 then return { ok=false, reason='cooldown_must_be_0_to_60_minutes' } end
    local settings = normalizeArmorySettings({ open=request.open, weaponLimit=weaponLimit, ammoLimit=ammoLimit, cooldownMinutes=cooldownMinutes })
    SetResourceKvp(armorySettingsKey(context.member.gangId), json.encode(settings))
    armorySettingsCache[tostring(context.member.gangId)] = settings
    logActivity(context, 'armory_settings_updated', settings)
    return { ok = true, settings = settings }
end)

lib.callback.register('cm-gang:server:armoryCheckout', function(src, rawRequest)
    local context, reason = memberContext(src, 'gang.armory')
    if not context then return { ok = false, reason = reason } end
    local _, facilityReason = facilityFor(context, 'headquarters')
    if facilityReason then return { ok = false, reason = facilityReason } end
    local request = type(rawRequest) == 'table' and rawRequest or { itemId = rawRequest }
    local now, itemId = GetGameTimer(), tostring(request.itemId or ''):lower()
    local quantity = tonumber(request.quantity)
    if itemId == '' or #itemId > 96 then return { ok = false, reason = 'invalid_item' } end
    if not quantity or quantity ~= math.floor(quantity) or quantity < 1 then
        return { ok = false, reason = 'invalid_quantity' }
    end
    local settings = armorySettings(context.member.gangId)
    if not settings.open then return { ok = false, reason = 'armory_closed' } end
    local itemOk, catalogItem = pcall(function() return exports['cm-law']:GetArmoryCatalogItem(itemId) end)
    if not itemOk or type(catalogItem) ~= 'table' then return { ok=false, reason='invalid_item' } end
    local limit = catalogItem.itemType == 'weapon' and settings.weaponLimit or settings.ammoLimit
    if quantity > limit then return { ok=false, reason=('maximum_%s_per_checkout_is_%d'):format(catalogItem.itemType == 'weapon' and 'guns' or 'items', limit) } end
    armoryCharactersBySource[tostring(context.source)] = context.characterId
    if (armoryCooldowns[context.characterId] or 0) > now then return { ok = false, reason = 'rate_limited' } end
    armoryCooldowns[context.characterId] = now + (settings.cooldownMinutes * 60 * 1000)
    -- Stock decrement/issue-ledger/inventory-delivery atomicity, and its
    -- rollback-on-any-failure symmetry, now live in cm-law's
    -- performArmoryCheckout -- gang only needs its own membership/facility
    -- re-check plus a per-character request lock here.
    local lockKey = context.member.gangId .. ':' .. context.characterId .. ':' .. itemId
    if armoryLocks[lockKey] then return { ok = false, reason = 'request_busy' } end
    armoryLocks[lockKey] = true
    local ok, result = xpcall(function()
        return exports['cm-law']:CheckoutExternalArmoryItem(src, gangOrgId(context.member.gangId), itemId, memberArmoryContext(context), quantity)
    end, debug.traceback)
    armoryLocks[lockKey] = nil
    if not ok or not result then
        print(('[%s] armory checkout failed unexpectedly: %s'):format(RESOURCE, tostring(result)))
        return { ok = false, reason = 'armory_checkout_failed' }
    end
    if result.ok ~= true then return { ok = false, reason = result.error or 'armory_checkout_failed' } end
    return { ok = true, amount = result.amount, message = result.message }
end)

AddEventHandler('playerDropped', function()
    local droppedSource = tonumber(source)
    local sourceKey = tostring(droppedSource)
    local characterId = armoryCharactersBySource[sourceKey] or characterIdForSource(droppedSource)
    if characterId then armoryCooldowns[characterId] = nil end
    armoryCharactersBySource[sourceKey] = nil
    for lockKey, owner in pairs(armoryLockOwners) do
        if owner.source == droppedSource or (characterId and owner.characterId == characterId) then
            armoryLocks[lockKey] = nil
            armoryLockOwners[lockKey] = nil
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == RESOURCE then
        armoryLocks, armoryLockOwners, armoryCooldowns, armoryCharactersBySource, armorySettingsCache = {}, {}, {}, {}, {}
    end
end)

local function adminAllowed(src)
    if GetInvokingResource() ~= 'cm-admin' then return false end
    local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(tonumber(src), 'gang.admin.manage') end)
    return ok and allowed == true
end

-- Admin exports below write cm-law's shared cm_legal_armory_stock table
-- directly (same upsert shape cm-law itself uses) rather than calling
-- exports['cm-law']:AdminConfigureArmory/AdminGetArmory: those cm-law
-- exports independently re-check the *player's* cm-admin 'orgs.manage'
-- permission, which is a different grant than cm-gang's own
-- 'gang.admin.manage' -- delegating to them would silently require admins
-- to hold both. adminAllowed() below (GetInvokingResource()=='cm-admin'
-- plus 'gang.admin.manage') stays cm-gang's sole gate, unchanged from
-- before this migration. Catalog validation still goes through cm-law's
-- exported, read-only GetArmoryCatalogItem so gang never re-implements its
-- own weapons/gunstore glue.
local function catalogItem(itemId)
    local ok, item = pcall(function() return exports['cm-law']:GetArmoryCatalogItem(itemId) end)
    if not ok or type(item) ~= 'table' then return nil end
    return item, item.itemType == 'vest' and 'armor' or item.itemType
end

exports('AdminGetArmory', function(src, gangId)
    if not adminAllowed(src) or not Config.IsFixedGangId(gangId) then return { ok=false,error='permission_denied' } end
    local rows = MySQL.query.await([[SELECT item_name AS item_id, enabled, min_tier AS minimum_tier,
        issue_amount AS issue_quantity, stock AS stock_quantity FROM cm_legal_armory_stock
        WHERE organization_id=? ORDER BY item_name]], { gangOrgId(gangId) }) or {}
    for _, row in ipairs(rows) do
        row.enabled = row.enabled == 1 or row.enabled == true
        row.issue_limit = 0
        local _, itemType = catalogItem(row.item_id)
        if itemType == 'weapon' then row.issue_quantity = 1 end
    end
    return { ok = true, items = rows }
end)

exports('AdminConfigureArmory', function(src, gangId, data)
    if not adminAllowed(src) or not Config.IsFixedGangId(gangId) or type(data)~='table' then return false,'permission_denied' end
    local itemId=tostring(data.itemId or ''):lower(); local item=catalogItem(itemId)
    if itemId=='' or #itemId>96 or not item then return false,'unknown_weapon_catalog_item' end
    local orgId = gangOrgId(gangId)
    local tier=math.max(1,math.min(100,math.floor(tonumber(data.minimumTier) or 1)))
    local _,itemType=catalogItem(itemId)
    local quantity=itemType == 'weapon' and 1 or math.max(1,math.min(1000,math.floor(tonumber(data.issueQuantity) or 1)))
    local cidOk,cid=pcall(function() return exports['cm-playerdata']:GetCharacterId(tonumber(src)) end); if not cidOk or not cid then return false,'character_not_loaded' end
    -- stock is intentionally absent from the UPDATE clause: it is only
    -- initialized (to 0) on first insert and is otherwise adjusted
    -- exclusively through AdminAdjustArmoryStock/checkout/deposit, never
    -- silently reset by an unrelated config save.
    MySQL.insert.await([[INSERT INTO cm_legal_armory_stock
      (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by) VALUES (?,?,?,0,100,?,?,?)
      ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),min_tier=VALUES(min_tier),issue_amount=VALUES(issue_amount),updated_by=VALUES(updated_by)]],
      {orgId,itemId,data.enabled==true and 1 or 0,quantity,tier,tostring(cid)})
    if itemType=='weapon' and item.ammoItem and item.ammoItem ~= '' then
        local ammoId=tostring(item.ammoItem):lower(); local ammo=catalogItem(ammoId)
        if ammo then MySQL.insert.await([[INSERT INTO cm_legal_armory_stock
          (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by) VALUES (?,?,?,0,100,100,?,?)
          ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),min_tier=VALUES(min_tier),updated_by=VALUES(updated_by)]],
          {orgId,ammoId,data.enabled==true and 1 or 0,tier,tostring(cid)}) end
    end
    return true,'Armory item saved.'
end)

exports('AdminAddArmoryBundleStock',function(src,gangId,weaponItemId)
    if not adminAllowed(src) or not Config.IsFixedGangId(gangId) then return false,'permission_denied' end
    weaponItemId=tostring(weaponItemId or ''):lower()
    local weapon,itemType=catalogItem(weaponItemId)
    if not weapon or itemType~='weapon' or not weapon.ammoItem or weapon.ammoItem == '' then return false,'weapon_or_ammo_unavailable' end
    local ammoItemId=tostring(weapon.ammoItem):lower()
    local orgId = gangOrgId(gangId)
    local weaponRow=MySQL.single.await('SELECT enabled FROM cm_legal_armory_stock WHERE organization_id=? AND item_name=? LIMIT 1',{orgId,weaponItemId})
    local ammoRow=MySQL.single.await('SELECT enabled FROM cm_legal_armory_stock WHERE organization_id=? AND item_name=? LIMIT 1',{orgId,ammoItemId})
    if not weaponRow or not ammoRow or not (weaponRow.enabled==1 or weaponRow.enabled==true) or not (ammoRow.enabled==1 or ammoRow.enabled==true) then return false,'enable_weapon_first' end
    local ok=MySQL.transaction.await({
        {query='UPDATE cm_legal_armory_stock SET stock=LEAST(max_stock,stock+5) WHERE organization_id=? AND item_name=? AND enabled=1',values={orgId,weaponItemId}},
        {query='UPDATE cm_legal_armory_stock SET stock=LEAST(max_stock,stock+1000) WHERE organization_id=? AND item_name=? AND enabled=1',values={orgId,ammoItemId}},
    })
    if not ok then return false,'stock_transaction_failed' end
    local cidOk,cid=pcall(function() return exports['cm-playerdata']:GetCharacterId(tonumber(src)) end)
    MySQL.insert.await([[INSERT INTO cm_gang_activity(event_uid,gang_id,action,actor_character_id,detail) VALUES(?,?,?,?,?)]],
        {('admin-stock:%s:%d:%d'):format(gangId,os.time(),math.random(100000,999999)),gangId,'admin_armory_bundle_stocked',cidOk and tostring(cid) or nil,json.encode({weapon=weaponItemId,weaponQuantity=5,ammo=ammoItemId,ammoQuantity=1000})})
    return true,'Added 5 weapons and 1,000 linked rounds.'
end)

exports('AdminAdjustArmoryStock', function(src, gangId, itemId, delta)
    if not adminAllowed(src) or not Config.IsFixedGangId(gangId) then return false,'permission_denied' end
    itemId = tostring(itemId or ''):lower()
    delta = math.floor(tonumber(delta) or 0)
    if itemId == '' or delta == 0 then return false, 'invalid_request' end
    local changed = MySQL.update.await([[UPDATE cm_legal_armory_stock SET stock=GREATEST(0,LEAST(max_stock,stock+?))
        WHERE organization_id=? AND item_name=?]], { delta, gangOrgId(gangId), itemId })
    if tonumber(changed) ~= 1 then return false, 'item_not_configured' end
    return true, 'Armory stock adjusted.'
end)

lib.callback.register('cm-gang:server:getArmoryReturnOptions', function(src, rawItemId)
    local context, reason = memberContext(src, 'gang.armory_deposit')
    if not context then return { ok=false, reason=reason } end
    local _, facilityReason = facilityFor(context, 'headquarters')
    if facilityReason then return { ok=false, reason=facilityReason } end
    if GetResourceState(INVENTORY) ~= 'started' then return { ok=false, reason='inventory_unavailable' } end
    local itemId = tostring(rawItemId or ''):lower()
    if itemId == '' or #itemId > 96 then return { ok=false, reason='invalid_item' } end
    local catalogOk, selected = pcall(function() return exports['cm-law']:GetArmoryCatalogItem(itemId) end)
    if not catalogOk or type(selected) ~= 'table' then return { ok=false, reason='invalid_item' } end
    local candidates = { selected }
    if selected.itemType == 'weapon' and selected.ammoItem and selected.ammoItem ~= '' then
        local ammoOk, ammo = pcall(function() return exports['cm-law']:GetArmoryCatalogItem(selected.ammoItem) end)
        if ammoOk and type(ammo) == 'table' then candidates[#candidates + 1] = ammo end
    end
    local options, orgId = {}, gangOrgId(context.member.gangId)
    for _, item in ipairs(candidates) do
        local enabled = MySQL.scalar.await([[SELECT enabled FROM cm_legal_armory_stock
            WHERE organization_id=? AND item_name=? LIMIT 1]], { orgId, item.itemName })
        if CMGangDbTrue(enabled) then
            local countOk, _, total = pcall(function() return exports[INVENTORY]:HasItem(src, item.itemName, 1) end)
            options[#options + 1] = {
                itemId = item.itemName, label = item.label,
                itemType = item.itemType == 'weapon' and 'gun' or item.itemType == 'ammo' and 'ammo' or 'armor',
                inventoryCount = countOk and math.max(0, tonumber(total) or 0) or 0,
            }
        end
    end
    return { ok=true, options=options }
end)

-- Deposit: gang.armory_deposit lets a member return an allowlisted item
-- from their own inventory into the shared gang stock pool. The exact
-- inventory row (serial/durability) is destroyed rather than preserved --
-- checkout always synthesizes a fresh item on withdrawal now, matching how
-- cm-law/cm-police's armories already work, so nothing needs to remember
-- the original row. This also drops the dependency on cm-inventory's
-- TransferContainerItemToPlayer export, which only ever trusted 'cm-gang'.
lib.callback.register('cm-gang:server:armoryDeposit', function(src, request)
    request = type(request) == 'table' and request or {}
    local context, reason = memberContext(src, 'gang.armory_deposit')
    if not context then return { ok = false, reason = reason } end
    local _, facilityReason = facilityFor(context, 'headquarters')
    if facilityReason then return { ok = false, reason = facilityReason } end
    local itemId = tostring(request.itemId or ''):lower()
    local quantity = math.max(1, math.min(1000, math.floor(tonumber(request.quantity) or 1)))
    if itemId == '' or #itemId > 96 then return { ok = false, reason = 'invalid_item' } end
    if GetResourceState(INVENTORY) ~= 'started' then return { ok = false, reason = 'inventory_unavailable' } end

    local orgId = gangOrgId(context.member.gangId)
    local lockKey = context.member.gangId .. ':' .. context.characterId .. ':deposit:' .. itemId
    if armoryLocks[lockKey] then return { ok = false, reason = 'request_busy' } end
    armoryLocks[lockKey] = true
    local ok, result = xpcall(function()
        local enabled = MySQL.scalar.await([[SELECT enabled FROM cm_legal_armory_stock
            WHERE organization_id=? AND item_name=? LIMIT 1]], { orgId, itemId })
        if not CMGangDbTrue(enabled) then return { ok = false, reason = 'item_not_enabled' } end
        local removeCalled, removed, removeReason = pcall(function()
            return exports[INVENTORY]:RemoveItem(src, itemId, quantity, nil, 'cm_gang_armory_deposit')
        end)
        if not removeCalled or removed ~= true then
            return { ok = false, reason = (removeCalled and removeReason) or 'item_not_held' }
        end
        local operationId = ('gang-deposit:%s:%s:%s:%d:%d'):format(context.member.gangId, context.characterId, itemId, os.time(), math.random(100000, 999999))
        local added = exports['cm-law']:AddOrganizationArmoryStock(orgId, itemId, quantity, {
            operationId = operationId, actorCid = context.characterId, reason = 'gang_armory_deposit',
        })
        if added ~= true then
            -- Stock could not be credited; refund the item rather than lose it.
            pcall(function() exports[INVENTORY]:AddItem(src, itemId, quantity, nil, 'cm_gang_armory_deposit_refund') end)
            return { ok = false, reason = 'stock_update_failed_item_returned' }
        end
        logActivity(context, 'armory_deposit', { itemId = itemId, quantity = quantity })
        return { ok = true }
    end, debug.traceback)
    armoryLocks[lockKey] = nil
    if not ok then
        print(('[cm-gang] armory deposit failed unexpectedly: %s'):format(tostring(result)))
        return { ok = false, reason = 'armory_deposit_failed' }
    end
    return result
end)

-- Future gang-events/missions seam named in the spec. Server-only, no
-- caller trust assumed beyond a normal export call; validates gang/item
-- and never creates negative stock.
exports('AddGangArmoryStock', function(gangId, itemId, quantity, metadata)
    gangId = tostring(gangId or '')
    itemId = tostring(itemId or ''):lower()
    quantity = math.floor(tonumber(quantity) or 0)
    if not Config.IsFixedGangId(gangId) or itemId == '' or quantity <= 0 or quantity > 100000 then
        return false, 'invalid_request'
    end
    if not catalogItem(itemId) then return false, 'unknown_weapon_catalog_item' end
    local operationId = type(metadata) == 'table' and tostring(metadata.operationId or '') or ''
    if operationId == '' then operationId = ('event-reward:%s:%s:%d:%d'):format(gangId, itemId, os.time(), math.random(100000, 999999)) end
    local added, addResult = exports['cm-law']:AddOrganizationArmoryStock(gangOrgId(gangId), itemId, quantity, {
        operationId = operationId, reason = 'gang_event_reward',
    })
    if added ~= true then return false, type(addResult) == 'string' and addResult or 'stock_transaction_failed' end
    return true
end)

-- One-time, idempotent carry-over from the old cm_gang_armory_config table
-- into the shared cm_legal_armory_stock schema, then seeds every current
-- cm-law armory catalog entry (weapons + ammo + armor/vests) as
-- enabled-but-zero-stock for every gang, exactly like cm-law's own
-- baseCatalog seeding -- INSERT IGNORE never overwrites an existing row, so
-- re-running this on every boot is always safe and never clobbers admin
-- choices made after migration.
local function migrateAndSyncGangArmories()
    if not CMGangDatabaseReady or GetResourceState('cm-law') ~= 'started' then return false end
    local okCatalog, catalog = pcall(function() return exports['cm-law']:GetArmoryCatalog() end)
    if not okCatalog or type(catalog) ~= 'table' then return false end
    local legacyRows = MySQL.query.await([[SELECT gang_id,item_id,enabled,minimum_tier,issue_quantity,stock_quantity
        FROM cm_gang_armory_config]]) or {}
    for _, row in ipairs(legacyRows) do
        MySQL.insert.await([[INSERT IGNORE INTO cm_legal_armory_stock
            (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
            VALUES (?,?,?,?,?,?,?,?)]], {
            gangOrgId(row.gang_id), row.item_id, (row.enabled == 1 or row.enabled == true) and 1 or 0,
            math.max(0, tonumber(row.stock_quantity) or 0), math.max(100, tonumber(row.stock_quantity) or 0),
            math.max(1, tonumber(row.issue_quantity) or 1), math.max(0, (tonumber(row.minimum_tier) or 1) - 1),
            'legacy_migration',
        })
    end
    local inserted = 0
    for _, gangId in ipairs(Config.GangIds) do
        local orgId = gangOrgId(gangId)
        for _, item in ipairs(catalog) do
            local changed = MySQL.insert.await([[INSERT IGNORE INTO cm_legal_armory_stock
                (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
                VALUES (?,?,1,0,100,?,0,'system_default')]], { orgId, item.itemName, item.defaultIssue })
            if tonumber(changed) and tonumber(changed) > 0 then inserted = inserted + 1 end
        end
    end
    if GetConvar('cm_environment', 'production') == 'development' then
        print(('[cm-gang] shared armory catalog sync complete inserted=%d (existing admin choices preserved)'):format(inserted))
    end
    return true
end

CreateThread(function()
    local deadline = GetGameTimer() + 30000
    while GetGameTimer() < deadline do
        if migrateAndSyncGangArmories() then return end
        Wait(1000)
    end
    print('[cm-gang] shared armory catalog sync deferred: database or cm-law unavailable')
end)
