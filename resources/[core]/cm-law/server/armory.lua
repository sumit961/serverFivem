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

local function adminArmoryPayload(orgId)
    orgId = validOrgId(orgId)
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
    local stored, enabled, items = rowsFor(orgId), enabledItemNames(orgId), {}
    for _, item in ipairs(baseCatalog()) do
        local row = stored[item.itemName]
        if enabled[item.itemName] then
            item.stock = row and math.max(0, tonumber(row.stock) or 0) or 0
            item.maxStock = row and math.max(1, tonumber(row.max_stock) or 100) or 100
            item.issueAmount = row and math.max(1, tonumber(row.issue_amount) or item.defaultIssue) or item.defaultIssue
            item.minTier = row and math.max(0, tonumber(row.min_tier) or 0) or 0
            item.available = item.stock >= item.issueAmount and (member.isLeader or member.tier >= item.minTier)
            items[#items + 1] = item
        end
    end
    return { ok = true, organizationId = orgId, items = items,
        canManage = member.isLeader or member.permissions['law.manage_armory'] == true }
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
    src, orgId, data = tonumber(src), validOrgId(orgId), type(data) == 'table' and data or {}
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

lib.callback.register('cm-law:server:armoryCheckout', function(src, orgId, itemName)
    if not rateLimit(src, 'law_armory_checkout', 900) then return { ok = false, error = 'Please wait.' } end
    orgId = validOrgId(orgId)
    local member, characterId, reason = armoryMember(src, orgId, false)
    if not member then return { ok = false, error = reason } end
    local item = catalogItem(itemName)
    if not item then return { ok = false, error = 'That equipment no longer exists.' } end
    if not enabledItemNames(orgId)[item.itemName] then return { ok = false, error = 'That equipment is not enabled.' } end
    local row = MySQL.single.await([[SELECT stock,max_stock,issue_amount,min_tier FROM cm_legal_armory_stock
        WHERE organization_id=? AND item_name=? LIMIT 1]], { orgId, item.itemName })
    if not row then return { ok = false, error = 'That equipment is out of stock.' } end
    local amount = math.max(1, tonumber(row.issue_amount) or item.defaultIssue)
    if not member.isLeader and member.tier < (tonumber(row.min_tier) or 0) then return { ok = false, error = 'Your rank cannot issue this equipment.' } end
    local carryOk, carryReason = exports['cm-inventory']:CanCarryItem(src, item.itemName, amount)
    if carryOk ~= true then return { ok = false, error = carryReason or 'Your inventory is full.' } end
    local changed = MySQL.update.await([[UPDATE cm_legal_armory_stock SET stock=stock-?
        WHERE organization_id=? AND item_name=? AND stock>=?]], { amount, orgId, item.itemName, amount })
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
    return { ok = true, message = ('Issued %dx %s.'):format(amount, item.label), armory = payload(src, orgId) }
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
    ArmoryReady = true
end)
