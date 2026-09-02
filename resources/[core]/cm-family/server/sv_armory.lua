-- ============================================================
--  cm-family | sv_armory.lua
--  Stocked family quartermaster: admin/leader-curated catalog, shared stock
--  pool, rank-tier gating -- built on cm-law's shared, multi-tenant armory
--  backend (cm-law/server/armory.lua's GetExternalArmory/
--  CheckoutExternalArmoryItem/AddOrganizationArmoryStock exports), the same
--  backend cm-gang's armory now runs on. Each family is namespaced as
--  'family:<familyId>' so it can never collide with cm-law's own
--  Config.Organizations ids or with cm-gang's 'gang:<gangId>' orgs.
--
--  Distinct from cm-house's weapon_storage locker (personal/family-shared
--  deposit box, no catalog/stock/tier concept at all) -- this is a real
--  quartermaster: leadership curates what's available, stock is a shared
--  pool, and members below a configured rank tier cannot check an item out.
--
--  Catalog management is self-service (family.manage_armory), the same
--  model cm-law's own organizations already use, rather than a cm-admin
--  integration -- families are player-run the same way gangs are.
-- ============================================================

local B = CMFamilyBridge
local INVENTORY = Config.InventoryResource or 'cm-inventory'
local armoryLocks = {}
local seededFamilies = {}

local function familyOrgId(familyId) return 'family:' .. tostring(familyId) end

-- One-time-per-boot, idempotent (INSERT IGNORE) catalog seed for a family
-- the first time its armory is touched. Unlike cm-gang's migration seed,
-- everything starts disabled -- a brand-new family armory should be empty
-- until leadership actively curates it, not instantly expose every weapon.
local function ensureFamilyArmorySeeded(familyId)
    if seededFamilies[familyId] then return end
    seededFamilies[familyId] = true
    local okCatalog, catalog = pcall(function() return exports['cm-law']:GetArmoryCatalog() end)
    if not okCatalog or type(catalog) ~= 'table' then seededFamilies[familyId] = nil; return end
    local orgId = familyOrgId(familyId)
    for _, item in ipairs(catalog) do
        MySQL.insert.await([[INSERT IGNORE INTO cm_legal_armory_stock
            (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
            VALUES (?,?,0,0,100,?,0,'system_default')]], { orgId, item.itemName, item.defaultIssue })
    end
end

-- Mirrors cm-gang's memberContext(): resolve rank + baseline permission once.
local function armoryMember(src, permission)
    local characterId = B.GetCid(src)
    if not characterId then return nil, nil, 'character_not_loaded' end
    local rank, family = GetRankForCid(characterId)
    if not rank or not family then return nil, nil, 'not_in_family' end
    if not RankHasPermission(rank, permission) then return nil, nil, 'no_permission' end
    ensureFamilyArmorySeeded(family.id)
    return {
        characterId = characterId, tier = tonumber(rank.tier) or 0, isLeader = rank.is_founder == true,
        canManage = rank.is_founder == true or RankHasPermission(rank, 'family.manage_armory'),
    }, family, nil
end

-- Same proximity-gate shape as cm-gang's facilityFor(): the family armory
-- lives at the linked house's own front door, reusing the same entrance
-- point 'door.enter' already gates -- no new cm-house interior point needed.
local function nearFamilyHouse(src, family)
    if not family or not family.house_id then return false end
    local house = B.GetHouse(family.house_id)
    local doorCoords = house and house.door_coords
    if not doorCoords or not doorCoords.x then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    return #(GetEntityCoords(ped) - vector3(doorCoords.x, doorCoords.y, doorCoords.z)) <= 8.0
end

local function toArmoryContext(context)
    return { characterId = context.characterId, tier = context.tier, isLeader = context.isLeader, canManage = context.canManage }
end

local function mapArmoryItems(rawItems)
    local items = {}
    for _, item in ipairs(rawItems or {}) do
        items[#items + 1] = {
            itemId = item.itemName, label = item.label,
            itemType = item.itemType == 'vest' and 'armor' or item.itemType,
            quantity = tonumber(item.issueAmount) or 1,
            stockQuantity = tonumber(item.stock) or 0, minimumTier = tonumber(item.minTier) or 0,
            image = item.image, group = tostring(item.itemType == 'vest' and 'armor' or item.itemType),
            ammoItem = (item.ammoItem and item.ammoItem ~= '') and item.ammoItem or nil,
            armorValue = tonumber(item.armorValue) or 0,
            description = item.description,
        }
    end
    return items
end

lib.callback.register('cm-family:server:getArmory', function(src)
    local context, family, reason = armoryMember(src, 'family.armory')
    if not context then return { ok = false, reason = reason } end
    if not nearFamilyHouse(src, family) then return { ok = false, reason = 'too_far_from_house' } end
    local ok, result = pcall(function()
        return exports['cm-law']:GetExternalArmory(familyOrgId(family.id), toArmoryContext(context))
    end)
    if not ok or not result or result.ok ~= true then return { ok = false, reason = 'armory_unavailable' } end
    return { ok = true, items = mapArmoryItems(result.items), canManage = context.canManage }
end)

lib.callback.register('cm-family:server:armoryCheckout', function(src, rawItemId)
    local context, family, reason = armoryMember(src, 'family.armory')
    if not context then return { ok = false, reason = reason } end
    if not nearFamilyHouse(src, family) then return { ok = false, reason = 'too_far_from_house' } end
    local itemId = tostring(rawItemId or ''):lower()
    if itemId == '' or #itemId > 96 then return { ok = false, reason = 'invalid_item' } end
    local lockKey = tostring(family.id) .. ':' .. context.characterId .. ':' .. itemId
    if armoryLocks[lockKey] then return { ok = false, reason = 'request_busy' } end
    armoryLocks[lockKey] = true
    local ok, result = xpcall(function()
        return exports['cm-law']:CheckoutExternalArmoryItem(src, familyOrgId(family.id), itemId, toArmoryContext(context))
    end, debug.traceback)
    armoryLocks[lockKey] = nil
    if not ok or not result then
        print(('[cm-family] armory checkout failed unexpectedly: %s'):format(tostring(result)))
        return { ok = false, reason = 'armory_checkout_failed' }
    end
    if result.ok ~= true then return { ok = false, reason = result.error or 'armory_checkout_failed' } end
    return { ok = true }
end)

-- Deposit destroys the exact inventory item and credits the shared stock
-- pool by the same amount -- see cm-gang/server/storage.lua's deposit for
-- why this doesn't try to preserve the original serial/durability.
lib.callback.register('cm-family:server:armoryDeposit', function(src, request)
    request = type(request) == 'table' and request or {}
    local context, family, reason = armoryMember(src, 'family.armory_deposit')
    if not context then return { ok = false, reason = reason } end
    if not nearFamilyHouse(src, family) then return { ok = false, reason = 'too_far_from_house' } end
    local itemId = tostring(request.itemId or ''):lower()
    local quantity = math.max(1, math.min(1000, math.floor(tonumber(request.quantity) or 1)))
    if itemId == '' or #itemId > 96 then return { ok = false, reason = 'invalid_item' } end
    if GetResourceState(INVENTORY) ~= 'started' then return { ok = false, reason = 'inventory_unavailable' } end
    local orgId = familyOrgId(family.id)
    local lockKey = tostring(family.id) .. ':' .. context.characterId .. ':deposit:' .. itemId
    if armoryLocks[lockKey] then return { ok = false, reason = 'request_busy' } end
    armoryLocks[lockKey] = true
    local ok, result = xpcall(function()
        local existing = exports['cm-law']:GetOrganizationArmoryItem(orgId, itemId)
        if not existing or existing.enabled ~= true then return { ok = false, reason = 'item_not_enabled' } end
        local removeCalled, removed, removeReason = pcall(function()
            return exports[INVENTORY]:RemoveItem(src, itemId, quantity, nil, 'cm_family_armory_deposit')
        end)
        if not removeCalled or removed ~= true then
            return { ok = false, reason = (removeCalled and removeReason) or 'item_not_held' }
        end
        local operationId = ('family-deposit:%s:%s:%s:%d:%d'):format(family.id, context.characterId, itemId, os.time(), math.random(100000, 999999))
        local added = exports['cm-law']:AddOrganizationArmoryStock(orgId, itemId, quantity, {
            operationId = operationId, actorCid = context.characterId, reason = 'family_armory_deposit',
        })
        if added ~= true then
            pcall(function() exports[INVENTORY]:AddItem(src, itemId, quantity, nil, 'cm_family_armory_deposit_refund') end)
            return { ok = false, reason = 'stock_update_failed_item_returned' }
        end
        LogFamily(family.id, context.characterId, 'armory_deposit', { itemId = itemId, quantity = quantity })
        return { ok = true }
    end, debug.traceback)
    armoryLocks[lockKey] = nil
    if not ok then
        print(('[cm-family] armory deposit failed unexpectedly: %s'):format(tostring(result)))
        return { ok = false, reason = 'armory_deposit_failed' }
    end
    return result
end)

-- ---------- self-service catalog management (family.manage_armory) ----------

lib.callback.register('cm-family:server:armoryManagement', function(src)
    local context, family, reason = armoryMember(src, 'family.manage_armory')
    if not context then return { ok = false, reason = reason } end
    if not context.canManage then return { ok = false, reason = 'no_permission' } end
    local okCatalog, catalog = pcall(function() return exports['cm-law']:GetArmoryCatalog() end)
    if not okCatalog or type(catalog) ~= 'table' then return { ok = false, reason = 'armory_unavailable' } end
    local orgId = familyOrgId(family.id)
    local rows = MySQL.query.await([[SELECT item_name,enabled,stock,issue_amount,min_tier
        FROM cm_legal_armory_stock WHERE organization_id=?]], { orgId }) or {}
    local byName = {}
    for _, row in ipairs(rows) do byName[tostring(row.item_name)] = row end
    local items = {}
    for _, item in ipairs(catalog) do
        local row = byName[item.itemName]
        items[#items + 1] = {
            itemId = item.itemName, label = item.label,
            itemType = item.itemType == 'vest' and 'armor' or item.itemType,
            enabled = row ~= nil and (row.enabled == 1 or row.enabled == true),
            stock = row and tonumber(row.stock) or 0,
            issueAmount = row and tonumber(row.issue_amount) or item.defaultIssue,
            minTier = row and tonumber(row.min_tier) or 0,
        }
    end
    return { ok = true, items = items }
end)

lib.callback.register('cm-family:server:armorySave', function(src, data)
    local context, family, reason = armoryMember(src, 'family.manage_armory')
    if not context then return { ok = false, reason = reason } end
    if not context.canManage then return { ok = false, reason = 'no_permission' } end
    data = type(data) == 'table' and data or {}
    local itemId = tostring(data.itemId or ''):lower()
    local okItem, item = pcall(function() return exports['cm-law']:GetArmoryCatalogItem(itemId) end)
    if not okItem or type(item) ~= 'table' then return { ok = false, reason = 'unknown_catalog_item' } end
    local itemType = item.itemType == 'vest' and 'armor' or item.itemType
    local tier = math.max(0, math.min(1000, math.floor(tonumber(data.minTier) or 0)))
    local issueAmount = math.max(1, math.min(itemType == 'ammo' and 1000 or 25,
        math.floor(tonumber(data.issueAmount) or item.defaultIssue or 1)))
    MySQL.insert.await([[INSERT INTO cm_legal_armory_stock
        (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
        VALUES (?,?,?,0,100,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),
        issue_amount=VALUES(issue_amount),min_tier=VALUES(min_tier),updated_by=VALUES(updated_by)]],
        { familyOrgId(family.id), item.itemName, data.enabled == true and 1 or 0, issueAmount, tier, context.characterId })
    LogFamily(family.id, context.characterId, 'armory_catalog_configured', {
        itemId = item.itemName, enabled = data.enabled == true, minTier = tier, issueAmount = issueAmount,
    })
    return { ok = true, message = 'Armory item saved.' }
end)

lib.callback.register('cm-family:server:armoryLoadStock', function(src)
    local context, family, reason = armoryMember(src, 'family.manage_armory')
    if not context then return { ok = false, reason = reason } end
    if not context.canManage then return { ok = false, reason = 'no_permission' } end
    local okCatalog, catalog = pcall(function() return exports['cm-law']:GetArmoryCatalog() end)
    if not okCatalog or type(catalog) ~= 'table' then return { ok = false, reason = 'armory_unavailable' } end
    local byName = {}
    for _, item in ipairs(catalog) do byName[item.itemName] = item end
    local orgId = familyOrgId(family.id)
    local enabledRows = MySQL.query.await([[SELECT item_name FROM cm_legal_armory_stock
        WHERE organization_id=? AND enabled=1]], { orgId }) or {}
    local loaded = { weapons = 0, ammunition = 0, vests = 0 }
    for _, row in ipairs(enabledRows) do
        local item = byName[tostring(row.item_name)]
        if item then
            local amount = item.itemType == 'ammo' and 1000 or 10
            local operationId = ('family-load:%s:%s:%d:%d'):format(family.id, row.item_name, os.time(), math.random(100000, 999999))
            local added = exports['cm-law']:AddOrganizationArmoryStock(orgId, row.item_name, amount, {
                operationId = operationId, actorCid = context.characterId, reason = 'family_armory_load_stock',
            })
            if added == true then
                if item.itemType == 'ammo' then loaded.ammunition = loaded.ammunition + amount
                elseif item.itemType == 'weapon' then loaded.weapons = loaded.weapons + amount
                else loaded.vests = loaded.vests + amount end
            end
        end
    end
    LogFamily(family.id, context.characterId, 'armory_stock_loaded', loaded)
    return { ok = true, message = ('Stock loaded: +%d guns, +%d ammunition, +%d vests.'):format(loaded.weapons, loaded.ammunition, loaded.vests) }
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then armoryLocks, seededFamilies = {}, {} end
end)
