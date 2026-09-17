-- Organization-scoped armory catalog and stock ledger.
-- cm-weapons owns weapon/ammunition definitions; cm-gunstore supplies armor
-- and artwork; cm-inventory owns delivery to the character inventory.

local ArmoryReady = false

local function createIssue(orgId, characterId, item, amount)
    local prefix = tostring(orgId or 'ORG'):upper():gsub('[^A-Z0-9]', ''):sub(1, 8)
    for _ = 1, 8 do
        local number = ('%s-%s-%08d'):format(prefix, os.date('!%Y%m%d'), math.random(0, 99999999))
        local ok, issueId = pcall(function()
            return MySQL.insert.await([[INSERT INTO cm_legal_armory_issues
                (license_number,organization_id,character_id,item_name,item_type,quantity,status)
                VALUES (?,?,?,?,?,?,'issued')]],
                { number, orgId, characterId, item.itemName, item.itemType, amount })
        end)
        if ok and issueId then return tonumber(issueId), number end
    end
    return nil, nil
end

local function imageUrl(value)
    value = tostring(value or '')
    if value == '' then return nil end
    if value:find('^nui://') or value:find('^https?://') or value:find('^data:') then return value end
    if not value:find('^images/') then value = 'images/' .. value end
    return 'nui://cm-gunstore/web/' .. value
end

local function gunstoreRows()
    local map = {}
    if GetResourceState('cm-gunstore') ~= 'started' then return map end
    local ok, rows = pcall(function() return exports['cm-gunstore']:GetCatalog(true) end)
    if not ok or type(rows) ~= 'table' then return map end
    for _, row in ipairs(rows) do
        local name = tostring(row.item_name or row.itemName or ''):lower()
        if name ~= '' then map[name] = row end
    end
    return map
end

local function baseCatalog()
    local shop, result, seen = gunstoreRows(), {}, {}
    local function add(row, kind)
        local name = tostring(row.itemName or row.item_name or ''):lower()
        if name == '' or seen[name] then return end
        seen[name] = true
        local store = shop[name] or {}
        kind = kind or row.itemType or row.item_type
        result[#result + 1] = {
            itemName = name,
            label = tostring(row.label or store.label or name),
            itemType = kind,
            image = imageUrl(row.image or store.image),
            description = tostring(row.description or store.description or ''),
            ammoItem = tostring(row.ammoItem or row.ammo_item or ''):lower(),
            defaultIssue = kind == 'ammo' and math.max(1, math.min(250,
                math.floor(tonumber(row.packSize or row.pack_size or store.pack_size) or 30))) or 1,
            -- Real protective rating from cm-gunstore's cm_gun_catalog.armor_value
            -- (0-100), not a display placeholder -- lets the armory UI show an
            -- actual "STRENGTH" stat for vests instead of a fabricated number.
            armorValue = math.max(0, math.min(100, math.floor(tonumber(store.armor_value or store.armorValue) or 0))),
        }
    end
    local okWeapons, weapons = pcall(function() return exports['cm-weapons']:GetAllWeapons(false) end)
    if okWeapons then for _, row in ipairs(weapons or {}) do add(row, 'weapon') end end
    local okAmmo, ammo = pcall(function() return exports['cm-weapons']:GetAllAmmo(false) end)
    if okAmmo then for _, row in ipairs(ammo or {}) do add(row, 'ammo') end end
    for _, row in pairs(shop) do
        if tostring(row.item_type or row.itemType):lower() == 'armor' then
            add(row, 'vest')
        end
    end
    table.sort(result, function(a, b)
        if a.itemType == b.itemType then return a.label < b.label end
        return a.itemType < b.itemType
    end)
    return result
end

local function catalogItem(itemName)
    itemName = tostring(itemName or ''):lower()
    for _, item in ipairs(baseCatalog()) do if item.itemName == itemName then return item end end
end

local function armoryMember(src, orgId, management)
    orgId = validOrgId(orgId)
    local characterId = characterIdFor(src)
    local member = orgId and characterId and memberFor(characterId, orgId) or nil
    if not member then return nil, characterId, 'You are not a member of this organization.' end
    if member.suspended then return nil, characterId, 'Your organization access is suspended.' end
    if not member.onDuty then return nil, characterId, 'You must be on duty to use the armory.' end
    if not member.isLeader and member.permissions['law.armory'] ~= true then
        return nil, characterId, 'Your rank cannot access the armory.'
    end
    if management and not member.isLeader and member.permissions['law.manage_armory'] ~= true then
        return nil, characterId, 'Your rank cannot manage armory stock.'
    end
    if not nearFacility(src, orgId, 'armory') then return nil, characterId, 'You must remain at your armory NPC.' end
    return member, characterId
end

local function rowsFor(orgId)
    local rows = MySQL.query.await([[SELECT item_name, enabled, stock, max_stock, issue_amount, min_tier
        FROM cm_legal_armory_stock WHERE organization_id = ?]], { orgId }) or {}
    local map = {}
    for _, row in ipairs(rows) do map[tostring(row.item_name)] = row end
    return map
end

local function enabledItemNames(orgId)
    local rows = MySQL.query.await([[SELECT item_name FROM cm_legal_armory_stock
        WHERE organization_id = ? AND enabled = 1]], { orgId }) or {}
    local enabled = {}
    for _, row in ipairs(rows) do enabled[tostring(row.item_name)] = true end
    return enabled
end

-- Accepts either a Config.Organizations id (sahp/sheriff/fib/army/police) or
-- an externally-namespaced id owned by another resource (e.g. 'gang:bloods',
-- 'family:42') so cm-admin's generic org-armory screen, and the shared
-- catalog/stock/issue mechanics below, work for both without cm-law needing
-- to know anything about gang or family membership.
local function resolveAnyOrgId(value)
    value = tostring(value or '')
    if value == '' then return nil end
    if Config.Organizations[value] then return value end
    if value:find(':', 1, true) then return value end
    return nil
end

-- Membership-agnostic core: everything below this point operates on an
-- already-resolved {orgId, characterId, tier, isLeader, canManage} instead
-- of looking membership up itself, so it can serve both cm-law's own
-- Config.Organizations members (via armoryMember() above) and external
-- resources with their own rank systems (via the caller-supplied
-- memberContext accepted by GetExternalArmory/CheckoutExternalArmoryItem).
local function buildArmoryPayload(orgId, tier, isLeader, canManage)
    local stored, enabled, items = rowsFor(orgId), enabledItemNames(orgId), {}
    for _, item in ipairs(baseCatalog()) do
        local row = stored[item.itemName]
        if enabled[item.itemName] then
            item.stock = row and math.max(0, tonumber(row.stock) or 0) or 0
            item.maxStock = row and math.max(1, tonumber(row.max_stock) or 100) or 100
            item.issueAmount = row and math.max(1, tonumber(row.issue_amount) or item.defaultIssue) or item.defaultIssue
            item.minTier = row and math.max(0, tonumber(row.min_tier) or 0) or 0
            item.available = item.stock >= item.issueAmount and (isLeader or tier >= item.minTier)
            items[#items + 1] = item
        end
    end
    return { ok = true, organizationId = orgId, items = items, canManage = canManage == true }
end

local function performArmoryCheckout(src, orgId, characterId, tier, isLeader, itemName, requestedAmount, skipRateLimit)
    if not skipRateLimit and not rateLimit(src, 'law_armory_checkout', 900) then return { ok = false, error = 'Please wait.' } end
    local item = catalogItem(itemName)
    if not item then return { ok = false, error = 'That equipment no longer exists.' } end
    if not enabledItemNames(orgId)[item.itemName] then return { ok = false, error = 'That equipment is not enabled.' } end
    local row = MySQL.single.await([[SELECT stock,max_stock,issue_amount,min_tier FROM cm_legal_armory_stock
        WHERE organization_id=? AND item_name=? LIMIT 1]], { orgId, item.itemName })
    if not row then return { ok = false, error = 'That equipment is out of stock.' } end
    local amount = requestedAmount == nil and math.max(1, tonumber(row.issue_amount) or item.defaultIssue)
        or math.floor(tonumber(requestedAmount) or 0)
    local maximum = item.itemType == 'weapon' and 10 or 1000
    if amount < 1 or amount > maximum then
        return { ok = false, error = ('Choose between 1 and %d %s.'):format(maximum, item.itemType == 'ammo' and 'rounds' or 'items') }
    end
    if not isLeader and tier < (tonumber(row.min_tier) or 0) then return { ok = false, error = 'Your rank cannot issue this equipment.' } end
    local carryOk, carryReason = exports['cm-inventory']:CanCarryItem(src, item.itemName, amount)
    if carryOk ~= true then return { ok = false, error = carryReason or 'Your inventory is full.' } end
    local changed
    local locked = LawWithStockLock({ orgId .. ':' .. item.itemName }, function()
        changed = MySQL.update.await([[UPDATE cm_legal_armory_stock SET stock=stock-?
            WHERE organization_id=? AND item_name=? AND stock>=?]], { amount, orgId, item.itemName, amount })
    end)
    if locked ~= true then return { ok = false, error = 'Armory stock is busy. Please try again.' } end
    if tonumber(changed) ~= 1 then return { ok = false, error = 'That equipment is out of stock.' } end
    local issueId, licenseNumber = createIssue(orgId, characterId, item, amount)
    if not issueId then
        MySQL.update.await('UPDATE cm_legal_armory_stock SET stock=LEAST(max_stock,stock+?) WHERE organization_id=? AND item_name=?',
            { amount, orgId, item.itemName })
        return { ok = false, error = 'Could not create a unique organization issue licence; stock was restored.' }
    end
    local added, addReason = exports['cm-inventory']:AddItem(src, item.itemName, amount,
        { issuedBy = orgId, licenseIssuer = orgId, licenseNumber = licenseNumber,
            issueLicenseNumber = licenseNumber, serial = licenseNumber,
            issueId = issueId, issueType = item.itemType, issuedToCid = characterId,
            issuedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'), armoryIssue = true }, 'cm_law_armory')
    if added ~= true then
        MySQL.update.await('UPDATE cm_legal_armory_stock SET stock=LEAST(max_stock,stock+?) WHERE organization_id=? AND item_name=?',
            { amount, orgId, item.itemName })
        MySQL.update.await("UPDATE cm_legal_armory_issues SET status='void' WHERE id=?", { issueId })
        return { ok = false, error = addReason or 'Equipment delivery failed; stock was restored.' }
    end
    logActivity(orgId, characterId, 'armory_checkout', { itemName = item.itemName, amount = amount, itemType = item.itemType })
    return { ok = true, message = ('Issued %dx %s.'):format(amount, item.label), amount = amount, itemName = item.itemName }
end

local function performRequestedCheckout(src, orgId, characterId, tier, isLeader, itemName, requestedAmount)
    local item = catalogItem(itemName)
    if not item then return { ok = false, error = 'That equipment no longer exists.' } end
    local amount = requestedAmount == nil and nil or math.floor(tonumber(requestedAmount) or 0)
    if item.itemType ~= 'weapon' or amount == nil or amount <= 1 then
        return performArmoryCheckout(src, orgId, characterId, tier, isLeader, itemName, amount)
    end
    if amount > 10 then return { ok = false, error = 'Choose between 1 and 10 guns.' } end
    if not rateLimit(src, 'law_armory_checkout', 900) then return { ok = false, error = 'Please wait.' } end
    local issued, lastError = 0, nil
    for _ = 1, amount do
        local result = performArmoryCheckout(src, orgId, characterId, tier, isLeader, itemName, 1, true)
        if result.ok ~= true then lastError = result.error break end
        issued = issued + 1
    end
    if issued == 0 then return { ok = false, error = lastError or 'No weapons were issued.' } end
    local message = ('Issued %dx %s.'):format(issued, item.label)
    if issued < amount then message = message .. (' Requested %d; remaining delivery stopped: %s'):format(amount, lastError or 'inventory unavailable') end
    return { ok = true, message = message, amount = issued, itemName = item.itemName, partial = issued < amount }
end

local function externalMemberContext(memberContext)
    if type(memberContext) ~= 'table' then return nil, 'Membership context is required.' end
    local characterId = memberContext.characterId and tostring(memberContext.characterId) or nil
    if not characterId or characterId == '' then return nil, 'Membership context is required.' end
    local isLeader = memberContext.isLeader == true
    return {
        characterId = characterId,
        tier = tonumber(memberContext.tier) or 0,
        isLeader = isLeader,
        canManage = isLeader or memberContext.canManage == true,
    }
end

local function adminArmoryPayload(orgId)
    orgId = resolveAnyOrgId(orgId)
    if not orgId then return { ok = false, error = 'Unknown organization.' } end
    local stored, enabled, items = rowsFor(orgId), enabledItemNames(orgId), baseCatalog()
    for _, item in ipairs(items) do
        local row = stored[item.itemName]
        item.enabled = enabled[item.itemName] == true
        item.stock = row and math.max(0, tonumber(row.stock) or 0) or 0
        item.issueAmount = row and math.max(1, tonumber(row.issue_amount) or item.defaultIssue) or item.defaultIssue
        item.minTier = row and math.max(0, tonumber(row.min_tier) or 0) or 0
    end
    return { ok = true, organizationId = orgId, items = items }
end

local function payload(src, orgId)
    if not LawCapabilityEnabled(orgId, 'armory') then return { ok = false, error = 'Armory is disabled for this organization.' } end
    local member, _, reason = armoryMember(src, orgId, false)
    if not member then return { ok = false, error = reason } end
    return buildArmoryPayload(orgId, member.tier, member.isLeader,
        member.isLeader or member.permissions['law.manage_armory'] == true)
end

lib.callback.register('cm-law:server:armory', function(src, orgId)
    if not ArmoryReady then return { ok = false, error = 'Armory stock is still loading.' } end
    return payload(src, validOrgId(orgId))
end)

lib.callback.register('cm-law:server:armoryManagement', function(src, orgId)
    orgId = validOrgId(orgId)
    if not orgId or not LawCapabilityEnabled(orgId, 'armory') then return { ok = false, error = 'Armory is disabled for this organization.' } end
    local member, _, reason = armoryMember(src, orgId, true)
    if not member then return { ok = false, error = reason } end
    local stored, enabled, items = rowsFor(orgId), enabledItemNames(orgId), baseCatalog()
    for _, item in ipairs(items) do
        local row = stored[item.itemName]
        item.enabled = enabled[item.itemName] == true
        item.stock = row and math.max(0, tonumber(row.stock) or 0) or 0
        item.maxStock = row and math.max(1, tonumber(row.max_stock) or 100) or 100
        item.issueAmount = row and math.max(1, tonumber(row.issue_amount) or item.defaultIssue) or item.defaultIssue
        item.minTier = row and math.max(0, tonumber(row.min_tier) or 0) or 0
    end
    return { ok = true, items = items }
end)

exports('AdminGetArmory', function(src, orgId)
    if not ArmoryReady then return { ok = false, error = 'Armory stock is still loading.' } end
    if not adminAllowed(tonumber(src)) then return { ok = false, error = 'Permission denied.' } end
    return adminArmoryPayload(orgId)
end)

exports('AdminConfigureArmory', function(src, orgId, data)
    src, orgId, data = tonumber(src), resolveAnyOrgId(orgId), type(data) == 'table' and data or {}
    if not ArmoryReady then return false, 'Armory stock is still loading.' end
    if not adminAllowed(src) then return false, 'Permission denied.' end
    local characterId = characterIdFor(src)
    local item = catalogItem(data.itemName)
    if not orgId or not item then return false, 'Unknown organization equipment.' end
    local minTier = math.max(0, math.min(1000, math.floor(tonumber(data.minTier) or 0)))
    local issueAmount = math.max(1, math.min(item.itemType == 'ammo' and 1000 or 25,
        math.floor(tonumber(data.issueAmount) or item.defaultIssue)))
    MySQL.insert.await([[INSERT INTO cm_legal_armory_stock
        (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
        VALUES (?,?,?,0,100,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),
        issue_amount=VALUES(issue_amount),min_tier=VALUES(min_tier),updated_by=VALUES(updated_by)]],
        { orgId, item.itemName, data.enabled == true and 1 or 0, issueAmount, minTier, characterId })
    logActivity(orgId, characterId, 'admin_armory_configured', {
        itemName = item.itemName, enabled = data.enabled == true, minTier = minTier, issueAmount = issueAmount,
    })
    return true, 'Organization armory equipment saved.'
end)

lib.callback.register('cm-law:server:saveArmoryItem', function(src, orgId, data)
    if not rateLimit(src, 'law_armory_manage', 500) then return { ok = false, error = 'Please wait.' } end
    orgId = validOrgId(orgId)
    local member, characterId, reason = armoryMember(src, orgId, true)
    if not member then return { ok = false, error = reason } end
    data = type(data) == 'table' and data or {}
    local item = catalogItem(data.itemName)
    if not item then return { ok = false, error = 'That equipment is not in the authoritative catalog.' } end
    local minTier = math.max(0, math.min(1000, math.floor(tonumber(data.minTier) or 0)))
    local issueAmount = math.max(1, math.min(item.itemType == 'ammo' and 1000 or 25,
        math.floor(tonumber(data.issueAmount) or item.defaultIssue)))
    MySQL.insert.await([[INSERT INTO cm_legal_armory_stock
        (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
        VALUES (?,?,?,0,100,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),
        issue_amount=VALUES(issue_amount),min_tier=VALUES(min_tier),updated_by=VALUES(updated_by)]],
        { orgId, item.itemName, data.enabled == true and 1 or 0, issueAmount, minTier, characterId })
    local linkedAmmo
    if data.enabled == true and item.itemType == 'weapon' and item.ammoItem ~= '' then
        local ammo = catalogItem(item.ammoItem)
        if ammo and ammo.itemType == 'ammo' then
            linkedAmmo = ammo.itemName
            MySQL.insert.await([[INSERT INTO cm_legal_armory_stock
                (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
                VALUES (?,?,1,0,100,?,0,?) ON DUPLICATE KEY UPDATE enabled=1,updated_by=VALUES(updated_by)]],
                { orgId, linkedAmmo, ammo.defaultIssue, characterId })
        end
    end
    logActivity(orgId, characterId, 'shared_armory_catalog_configured', {
        itemName = item.itemName, enabled = data.enabled == true, linkedAmmo = linkedAmmo,
    })
    return { ok = true, message = linkedAmmo and ('Saved for this organization. Matching ammunition ' .. linkedAmmo .. ' was enabled.') or 'Organization armory item saved.' }
end)

lib.callback.register('cm-law:server:loadArmoryStock', function(src, orgId)
    if not rateLimit(src, 'law_armory_load_stock', 2000) then return { ok = false, error = 'Please wait.' } end
    orgId = validOrgId(orgId)
    local member, characterId, reason = armoryMember(src, orgId, true)
    if not member then return { ok = false, error = reason } end
    local enabled, loaded = enabledItemNames(orgId), { weapons = 0, ammunition = 0, vests = 0 }
    for _, item in ipairs(baseCatalog()) do
        if enabled[item.itemName] then
            local amount = item.itemType == 'ammo' and 1000 or 10
            local capacity = item.itemType == 'ammo' and 1000 or 10
            MySQL.insert.await([[INSERT INTO cm_legal_armory_stock
                (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
                VALUES (?,?,1,?,?,?,0,?) ON DUPLICATE KEY UPDATE enabled=1,
                max_stock=GREATEST(max_stock,stock+VALUES(stock)),stock=stock+VALUES(stock),
                issue_amount=VALUES(issue_amount),updated_by=VALUES(updated_by)]],
                { orgId, item.itemName, amount, capacity, item.defaultIssue, characterId })
            if item.itemType == 'ammo' then loaded.ammunition = loaded.ammunition + amount
            elseif item.itemType == 'weapon' then loaded.weapons = loaded.weapons + amount
            else loaded.vests = loaded.vests + amount end
        end
    end
    logActivity(orgId, characterId, 'armory_stock_loaded', loaded)
    return { ok = true, message = ('Stock loaded: +%d guns, +%d ammunition, +%d vests.'):format(loaded.weapons, loaded.ammunition, loaded.vests) }
end)

local function checkoutOrganizationArmory(src, orgId, itemName)
    orgId = validOrgId(orgId)
    local member, characterId, reason = armoryMember(src, orgId, false)
    if not member then return { ok = false, error = reason } end
    local result = performRequestedCheckout(src, orgId, characterId, member.tier, member.isLeader, itemName)
    if result.ok then result.armory = payload(src, orgId) end
    return result
end

lib.callback.register('cm-law:server:armoryCheckout', checkoutOrganizationArmory)
exports('CheckoutOrganizationArmoryItem', checkoutOrganizationArmory)
exports('CheckoutOrganisationArmoryItem', function(src, orgId, itemName)
   return checkoutOrganizationArmory(src, orgId, itemName)
end)

-- ---------------------------------------------------------------------------
-- Generic (external-caller) armory API.
-- For resources with their own membership/rank system -- cm-gang, cm-family,
-- and any future org that isn't one of cm-law's own Config.Organizations.
-- The caller resolves membership/rank/facility-proximity itself and passes
-- an explicit memberContext = { characterId, tier, isLeader, canManage };
-- this module only owns the shared catalog, stock, and issue ledger. orgId
-- must be a globally-unique namespaced string (e.g. 'gang:bloods',
-- 'family:42') so it never collides with a Config.Organizations key.
-- ---------------------------------------------------------------------------
-- Read-only catalog access for external resources that need to validate an
-- item id or resolve its itemType/ammoItem before writing their own admin
-- rows into cm_legal_armory_stock directly (see cm-gang/server/storage.lua).
-- Kept separate from GetExternalArmory/CheckoutExternalArmoryItem because
-- catalog lookups carry no membership/permission gate at all -- it is the
-- same authoritative weapon/ammo/armor list every organization sees.
exports('GetArmoryCatalog', function() return baseCatalog() end)
exports('GetArmoryCatalogItem', function(itemName) return catalogItem(itemName) end)

exports('GetExternalArmory', function(orgId, memberContext)
    if not ArmoryReady then return { ok = false, error = 'Armory stock is still loading.' } end
    orgId = resolveAnyOrgId(orgId)
    if not orgId then return { ok = false, error = 'Unknown organization.' } end
    local ctx, err = externalMemberContext(memberContext)
    if not ctx then return { ok = false, error = err } end
    return buildArmoryPayload(orgId, ctx.tier, ctx.isLeader, ctx.canManage)
end)

exports('CheckoutExternalArmoryItem', function(src, orgId, itemName, memberContext, requestedAmount)
    if not ArmoryReady then return { ok = false, error = 'Armory stock is still loading.' } end
    src, orgId = tonumber(src), resolveAnyOrgId(orgId)
    if not orgId then return { ok = false, error = 'Unknown organization.' } end
    local ctx, err = externalMemberContext(memberContext)
    if not ctx then return { ok = false, error = err } end
    local result = performRequestedCheckout(src, orgId, ctx.characterId, ctx.tier, ctx.isLeader, itemName, requestedAmount)
    if result.ok then result.armory = buildArmoryPayload(orgId, ctx.tier, ctx.isLeader, ctx.canManage) end
    return result
end)

local function stockOperationContext(context)
    if type(context) ~= 'table' then return nil, 'Operation context is required.' end
    local operationId = tostring(context.operationId or ''):gsub('[^%w:_.-]', '')
    if #operationId < 1 or #operationId > 128 then return nil, 'A valid operation ID is required.' end
    local reason = tostring(context.reason or 'unspecified'):gsub('[%c]', ' '):sub(1, 160)
    local actorCid = context.actorCid and tostring(context.actorCid):sub(1, 64) or nil
    return { operationId = operationId, reason = reason, actorCid = actorCid }
end

local function mutateOrganizationArmoryStock(orgId, itemName, amount, direction, context)
    orgId, itemName = resolveAnyOrgId(orgId), tostring(itemName or ''):lower()
    amount = tonumber(amount)
    local item = catalogItem(itemName)
    local operation, contextError = stockOperationContext(context)
    if not orgId or not item then return false, 'Unknown organization equipment.' end
    if not amount or amount ~= math.floor(amount) or amount < 1 or amount > 1000000 then
        return false, 'Stock amount must be a positive integer.'
    end
    if not operation then return false, contextError end
    if direction ~= 'add' and direction ~= 'remove' then return false, 'Unknown stock operation.' end

    local statements = {
        { query = [[INSERT IGNORE INTO cm_legal_armory_operations
            (operation_id, organization_id, item_name, amount, direction, actor_cid, reason, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'pending')]],
            values = { operation.operationId, orgId, item.itemName, amount, direction, operation.actorCid, operation.reason } },
    }
    if direction == 'add' then
        statements[#statements + 1] = {
            query = [[INSERT INTO cm_legal_armory_stock
                (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
                VALUES (?, ?, 1, 0, 100, ?, 0, ?)
                ON DUPLICATE KEY UPDATE item_name=item_name]],
            values = { orgId, item.itemName, item.defaultIssue, operation.actorCid },
        }
        statements[#statements + 1] = {
            query = [[UPDATE cm_legal_armory_stock s
                SET s.stock = s.stock + ?
                WHERE s.organization_id = ? AND s.item_name = ?
                  AND s.stock + ? <= s.max_stock
                  AND EXISTS (SELECT 1 FROM cm_legal_armory_operations o
                    WHERE o.operation_id = ? AND o.status = 'pending')]],
            values = { amount, orgId, item.itemName, amount, operation.operationId },
        }
    else
        statements[#statements + 1] = {
            query = [[UPDATE cm_legal_armory_stock s
                SET s.stock = s.stock - ?
                WHERE s.organization_id = ? AND s.item_name = ?
                  AND s.stock >= ?
                  AND EXISTS (SELECT 1 FROM cm_legal_armory_operations o
                    WHERE o.operation_id = ? AND o.status = 'pending')]],
            values = { amount, orgId, item.itemName, amount, operation.operationId },
        }
    end
    statements[#statements + 1] = {
        query = [[UPDATE cm_legal_armory_operations
            SET status = IF(ROW_COUNT() = 1, 'completed', 'rejected'),
                result = IF(ROW_COUNT() = 1, 'applied', 'not_applied'),
                completed_at = CURRENT_TIMESTAMP
            WHERE operation_id = ? AND status = 'pending']],
        values = { operation.operationId },
    }
    if MySQL.transaction.await(statements) ~= true then return false, 'Stock operation failed safely.' end
    local result = MySQL.single.await([[SELECT status, result FROM cm_legal_armory_operations
        WHERE operation_id = ? LIMIT 1]], { operation.operationId })
    if not result then return false, 'Stock operation result was not recorded.' end
    if tostring(result.status) ~= 'completed' then return false, 'Stock operation was not applied.' end
    logActivity(orgId, operation.actorCid, direction == 'add' and 'armory_stock_added' or 'armory_stock_removed', {
        operationId = operation.operationId, itemName = item.itemName, amount = amount, reason = operation.reason,
    })
    return true, { operationId = operation.operationId, organizationId = orgId, itemName = item.itemName, amount = amount }
end

exports('GetOrganizationArmoryStock', function(orgId)
    orgId = resolveAnyOrgId(orgId)
    if not orgId then return {} end
    return MySQL.query.await([[SELECT organization_id AS organizationId, item_name AS itemId,
        enabled, stock AS amount, max_stock AS maxAmount, issue_amount AS issueAmount, min_tier AS minTier
        FROM cm_legal_armory_stock WHERE organization_id = ? ORDER BY item_name]], { orgId }) or {}
end)
exports('GetOrganisationArmoryStock', function(orgId)
    return exports[RESOURCE]:GetOrganizationArmoryStock(orgId)
end)
exports('GetOrganizationArmoryItem', function(orgId, itemId)
    for _, row in ipairs(exports[RESOURCE]:GetOrganizationArmoryStock(orgId)) do
        if tostring(row.itemId) == tostring(itemId) then return row end
    end
    return nil
end)
exports('GetOrganisationArmoryItem', function(orgId, itemId)
    return exports[RESOURCE]:GetOrganizationArmoryItem(orgId, itemId)
end)
exports('CanAccessOrganizationArmory', function(src, orgId)
    orgId = validOrgId(orgId)
    if not orgId or not LawCapabilityEnabled(orgId, 'armory') then return false end
    return armoryMember(tonumber(src), orgId, false) ~= nil
end)
exports('CanAccessOrganisationArmory', function(src, orgId)
    return exports[RESOURCE]:CanAccessOrganizationArmory(src, orgId)
end)
exports('AddOrganizationArmoryStock', function(orgId, itemId, amount, context)
    return mutateOrganizationArmoryStock(orgId, itemId, amount, 'add', context)
end)
exports('AddOrganisationArmoryStock', function(orgId, itemId, amount, context)
    return exports[RESOURCE]:AddOrganizationArmoryStock(orgId, itemId, amount, context)
end)
exports('RemoveOrganizationArmoryStock', function(orgId, itemId, amount, context)
    return mutateOrganizationArmoryStock(orgId, itemId, amount, 'remove', context)
end)
exports('RemoveOrganisationArmoryStock', function(orgId, itemId, amount, context)
    return exports[RESOURCE]:RemoveOrganizationArmoryStock(orgId, itemId, amount, context)
end)

AddEventHandler('cm-law:server:memberWentOffDuty', function(src, characterId, orgId, reason)
    src, orgId = tonumber(src), validOrgId(orgId)
    if not orgId or GetResourceState('cm-inventory') ~= 'started' then return end
    local ok, _, removed
    if src and src > 0 and GetPlayerName(src) then
        ok, _, removed = exports['cm-inventory']:ReclaimArmoryIssues(src, orgId, reason or 'legal_org_off_duty')
    else
        ok, _, removed = exports['cm-inventory']:ReclaimArmoryIssuesForCharacter(characterId, orgId, reason or 'legal_org_off_duty')
    end
    if ok ~= true then
        print(('[cm-law] failed to reclaim %s equipment for character %s'):format(orgId, tostring(characterId)))
        return
    end
    removed = type(removed) == 'table' and removed or {}
    for _, item in ipairs(removed) do
        if item.issueId then
            local changed = MySQL.update.await([[UPDATE cm_legal_armory_issues SET status='returned'
                WHERE id=? AND organization_id=? AND character_id=? AND status='issued']],
                { item.issueId, orgId, tostring(characterId) })
            if tonumber(changed) == 1 then
                MySQL.update.await([[UPDATE cm_legal_armory_stock SET stock=LEAST(max_stock,stock+?)
                    WHERE organization_id=? AND item_name=?]], { item.quantity, orgId, item.itemName })
            end
        end
    end
    if #removed > 0 then logActivity(orgId, characterId, 'armory_automatic_return', { reason = reason, items = removed }) end
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_armory_catalog (
        item_name VARCHAR(64) NOT NULL,
        enabled TINYINT(1) NOT NULL DEFAULT 0,
        set_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (item_name), KEY idx_cm_legal_armory_catalog_enabled (enabled)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_armory_stock (
        organization_id VARCHAR(32) NOT NULL,
        item_name VARCHAR(64) NOT NULL,
        enabled TINYINT(1) NOT NULL DEFAULT 0,
        stock INT UNSIGNED NOT NULL DEFAULT 0,
        max_stock INT UNSIGNED NOT NULL DEFAULT 100,
        issue_amount SMALLINT UNSIGNED NOT NULL DEFAULT 1,
        min_tier SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (organization_id,item_name), KEY idx_cm_legal_armory_enabled (organization_id,enabled)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[INSERT IGNORE INTO cm_legal_armory_catalog (item_name,enabled,set_by)
        SELECT item_name,1,MAX(updated_by) FROM cm_legal_armory_stock WHERE enabled=1 GROUP BY item_name]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_armory_issues (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        license_number VARCHAR(40) NOT NULL,
        organization_id VARCHAR(32) NOT NULL,
        character_id VARCHAR(64) NOT NULL,
        item_name VARCHAR(64) NOT NULL,
        item_type VARCHAR(16) NOT NULL,
        quantity SMALLINT UNSIGNED NOT NULL DEFAULT 1,
        status ENUM('issued','confiscated','returned','void') NOT NULL DEFAULT 'issued',
        issued_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id), UNIQUE KEY uq_cm_legal_armory_license (license_number),
        KEY idx_cm_legal_armory_issue_character (character_id),
        KEY idx_cm_legal_armory_issue_org (organization_id,status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_armory_operations (
        operation_id VARCHAR(128) NOT NULL, organization_id VARCHAR(32) NOT NULL,
        item_name VARCHAR(64) NOT NULL, amount INT UNSIGNED NOT NULL,
        direction ENUM('add','remove') NOT NULL, actor_cid VARCHAR(64) NULL,
        reason VARCHAR(160) NOT NULL, status ENUM('pending','completed','rejected') NOT NULL DEFAULT 'pending',
        result VARCHAR(32) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        completed_at TIMESTAMP NULL, PRIMARY KEY (operation_id),
        KEY idx_cm_legal_armory_ops_org (organization_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    ArmoryReady = true
end)
