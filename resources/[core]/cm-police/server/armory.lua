-- cm-police armory. Log-only, no enforced return -- a checked-out weapon
-- behaves exactly like any other owned item afterward (no auto-reclaim on
-- off-duty, no "return" action). The allowed weapon list is admin-
-- configurable (opt-in: absence of a row means NOT allowed), not a
-- hardcoded curated list and not the whole weapon/vest catalog wide open.
--
-- cm-weapons already owns the full weapon catalog (GetAllWeapons/GetCatalog
-- exports, the same ones cm-gunstore reads its own catalog through) -- this
-- file only tracks which of those are currently enabled for the armory.

local ArmoryReady = false

local function gunstoreImage(image)
    image = tostring(image or '')
    if image == '' then return nil end
    if image:find('^nui://') or image:find('^https?://') or image:find('^data:') then return image end
    if not image:find('^images/') then image = 'images/' .. image end
    return 'nui://cm-gunstore/web/' .. image
end

local function gunstoreCatalogByName()
    local map = {}
    if GetResourceState('cm-gunstore') ~= 'started' then return map end
    local ok, rows = pcall(function() return exports['cm-gunstore']:GetCatalog(true) or {} end)
    if not ok then return map end
    for _, row in ipairs(rows) do
        local itemName = tostring(row.item_name or row.itemName or '')
        if itemName ~= '' then map[itemName] = row end
    end
    return map
end

local function armoryCatalog()
    local gunstore = gunstoreCatalogByName()
    local list, seen = {}, {}
    local weapons = {}
    pcall(function() weapons = exports['cm-weapons']:GetAllWeapons(false) or {} end)
    for _, weapon in ipairs(weapons) do
        local itemName = tostring(weapon.itemName or weapon.item_name or '')
        if itemName ~= '' and not seen[itemName] then
            local shop = gunstore[itemName] or {}
            seen[itemName] = true
            list[#list + 1] = {
                itemName = itemName,
                label = weapon.label or shop.label or itemName,
                image = gunstoreImage(shop.image or weapon.image),
                itemType = 'weapon',
                category = tostring(weapon.group or weapon.group_key or 'weapon'),
                description = tostring(shop.description or weapon.description or 'Department-issued weapon'),
            }
        end
    end
    for itemName, row in pairs(gunstore) do
        local itemType = tostring(row.item_type or row.itemType)
        if (itemType == 'armor' or itemType == 'ammo') and not seen[itemName] then
            seen[itemName] = true
            list[#list + 1] = {
                itemName = itemName,
                label = row.label or itemName,
                image = gunstoreImage(row.image),
                itemType = itemType,
                category = itemType == 'armor' and 'vest' or tostring(row.ammo_key or row.group or 'ammunition'),
                armorValue = tonumber(row.armor_value or row.armorValue) or 0,
                issueAmount = itemType == 'ammo' and math.max(1, math.min(250, math.floor(tonumber(row.pack_size or row.packSize) or 1))) or 1,
                description = tostring(row.description or (itemType == 'armor' and 'Department protective vest' or 'Department ammunition pack')),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.itemType == b.itemType then return tostring(a.label) < tostring(b.label) end
        return a.itemType < b.itemType
    end)
    return list
end

local function armoryItem(itemName)
    itemName = tostring(itemName or '')
    for _, item in ipairs(armoryCatalog()) do
        if item.itemName == itemName then return item end
    end
    return nil
end

local function authorizedMember(src)
    if not PoliceDatabaseReady() then return nil, cid(src) end
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) then
        return nil, characterId
    end
    return member, characterId
end

local function enabledItemNames()
    if not ArmoryReady then return {} end
    local rows = MySQL.query.await('SELECT item_name FROM cm_legal_armory_catalog WHERE enabled = 1') or {}
    local set = {}
    for _, row in ipairs(rows) do set[tostring(row.item_name)] = true end
    return set
end

local function armoryManager(src)
    local member, characterId = authorizedMember(src)
    if member and has(member, 'police.manage_armory') then return member, characterId end
    local isAdmin = false
    pcall(function() isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if isAdmin then return { tier = 101, is_leader = 1, permissions = '{}' }, cid(src) end
    return nil, characterId
end

lib.callback.register('cm-police:server:armoryManageList', function(src)
    local member = armoryManager(src)
    if not member then return {} end
    local enabled = enabledItemNames()
    local list = armoryCatalog()
    for _, item in ipairs(list) do
        item.enabled = enabled[item.itemName] == true
    end
    return list
end)

lib.callback.register('cm-police:server:setArmoryWeapon', function(src, itemName, enabled)
    local member, characterId = armoryManager(src)
    if not member then return false, 'Your rank cannot manage the armory.' end
    itemName = tostring(itemName or '')
    local item = armoryItem(itemName)
    if not item then return false, 'That item is not in the Police equipment catalog.' end
    MySQL.insert.await(
        'INSERT INTO cm_legal_armory_catalog (item_name, enabled, set_by) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE enabled = VALUES(enabled), set_by = VALUES(set_by)',
        { itemName, enabled == true and 1 or 0, characterId }
    )
    local linkedAmmoName
    if enabled == true and item.itemType == 'weapon' and GetResourceState('cm-gunstore') == 'started' then
        local ok, ammo = pcall(function() return exports['cm-gunstore']:GetWeaponAmmo(itemName) end)
        linkedAmmoName = ok and type(ammo) == 'table' and tostring(ammo.item_name or ammo.itemName or '') or nil
        local linkedItem = linkedAmmoName and linkedAmmoName ~= '' and armoryItem(linkedAmmoName) or nil
        if linkedItem and linkedItem.itemType == 'ammo' then
            MySQL.insert.await(
                'INSERT INTO cm_legal_armory_catalog (item_name, enabled, set_by) VALUES (?, 1, ?) ON DUPLICATE KEY UPDATE enabled = 1, set_by = VALUES(set_by)',
                { linkedAmmoName, characterId }
            )
        else
            linkedAmmoName = nil
        end
    end
    log(characterId, 'armory_equipment_toggled', { itemName = itemName, enabled = enabled == true, linkedAmmo = linkedAmmoName })
    local message = ('%s %s the armory.'):format(itemName, enabled == true and 'added to' or 'removed from')
    if linkedAmmoName then message = message .. (' Linked ammunition %s was enabled automatically.'):format(linkedAmmoName) end
    return true, message
end)

lib.callback.register('cm-police:server:armoryAvailable', function(src)
    local member = authorizedMember(src)
    if not member then return {} end
    local enabled = enabledItemNames()
    local stockRows = MySQL.query.await([[SELECT item_name,stock,max_stock,issue_amount
        FROM cm_legal_armory_stock WHERE organization_id='police']]) or {}
    local stock = {}
    for _, row in ipairs(stockRows) do stock[tostring(row.item_name)] = row end
    local list = {}
    for _, item in ipairs(armoryCatalog()) do
        if enabled[item.itemName] then
            local row = stock[item.itemName]
            item.stock = row and math.max(0, tonumber(row.stock) or 0) or 0
            item.maxStock = row and math.max(1, tonumber(row.max_stock) or 10) or 10
            item.issueAmount = row and math.max(1, tonumber(row.issue_amount) or item.issueAmount or 1) or (item.issueAmount or 1)
            item.available = item.stock >= item.issueAmount
            list[#list + 1] = item
        end
    end
    return list
end)

lib.callback.register('cm-police:server:loadArmoryStock', function(src)
    local member, characterId = armoryManager(src)
    if not member then return false, 'Your rank cannot load armory stock.' end
    if not rateLimit(src, 'police_armory_load_stock', 2000) then return false, 'Please wait.' end
    local enabled, loaded = enabledItemNames(), { weapons = 0, ammunition = 0, armor = 0 }
    for _, item in ipairs(armoryCatalog()) do
        if enabled[item.itemName] then
            local amount = item.itemType == 'ammo' and 1000 or 10
            local issueAmount = math.max(1, tonumber(item.issueAmount) or 1)
            MySQL.insert.await([[INSERT INTO cm_legal_armory_stock
                (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
                VALUES ('police',?,1,?,?,?,0,?) ON DUPLICATE KEY UPDATE enabled=1,
                max_stock=GREATEST(max_stock,stock+VALUES(stock)),stock=stock+VALUES(stock),
                issue_amount=VALUES(issue_amount),updated_by=VALUES(updated_by)]],
                { item.itemName, amount, amount, issueAmount, characterId })
            if item.itemType == 'ammo' then loaded.ammunition = loaded.ammunition + amount
            elseif item.itemType == 'weapon' then loaded.weapons = loaded.weapons + amount
            else loaded.armor = loaded.armor + amount end
        end
    end
    log(characterId, 'armory_stock_loaded', loaded)
    return true, ('Stock loaded: +%d guns, +%d ammunition, +%d vests.'):format(loaded.weapons, loaded.ammunition, loaded.armor)
end)

-- Same defensive multi-attempt AddItem shape cm-gunstore's own
-- addInventoryItem already uses -- the export's exact call signature has
-- drifted across cm-inventory versions, so try each in turn rather than
-- guess one.
local function createPoliceIssue(characterId, itemName, itemType, amount)
    for _ = 1, 8 do
        local number = ('POLICE-%s-%08d'):format(os.date('!%Y%m%d'), math.random(0, 99999999))
        local ok, issueId = pcall(function()
            return MySQL.insert.await([[INSERT INTO cm_legal_armory_issues
                (license_number,organization_id,character_id,item_name,item_type,quantity,status)
                VALUES (?,'police',?,?,?,?, 'issued')]], { number, characterId, itemName, itemType, amount })
        end)
        if ok and issueId then return tonumber(issueId), number end
    end
end

local function grantArmoryWeapon(src, characterId, itemName, itemType, amount)
    if GetResourceState('cm-inventory') ~= 'started' then return false, 'Inventory is not available.' end
    amount = math.max(1, math.min(250, math.floor(tonumber(amount) or 1)))
    local issueId, licenseNumber = createPoliceIssue(characterId, itemName, itemType, amount)
    if not issueId then return false, 'issue_licence_failed' end
    local metadata = { issuedBy = 'police', licenseIssuer = 'police', licenseNumber = licenseNumber,
        issueLicenseNumber = licenseNumber, serial = licenseNumber, issueId = issueId,
        issueType = itemType, issuedToCid = characterId, issuedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'), armoryIssue = true }
    local called, added, reason = pcall(function()
        return exports['cm-inventory']:AddItem(src, itemName, amount, metadata, 'cm_police_armory')
    end)
    if not called or added ~= true then
        MySQL.update.await("UPDATE cm_legal_armory_issues SET status='void' WHERE id=?", { issueId })
    end
    if not called then return false, 'inventory_export_failed' end
    return added == true, reason or 'inventory_full_or_unknown_item'
end

lib.callback.register('cm-police:server:armoryCheckout', function(src, itemName)
    local member, characterId = authorizedMember(src)
    if not member then return false, 'You must be an on-duty officer.' end
    if not IsNearPoliceFacilityNpc(src, 'armory_npc') then return false, 'You must be at the Police armory NPC.' end
    if not rateLimit(src, 'police_armory_checkout', 1000) then return false, 'Please wait.' end
    itemName = tostring(itemName or '')
    local lockKey = ('armory:%s:%s'):format(characterId, itemName)
    if not AcquirePoliceOperationLock(lockKey, src, 10000) then return false, 'That checkout is already being processed.' end
    local function finish(ok, message)
        ReleasePoliceOperationLock(lockKey, src)
        return ok, message
    end
    local enabled = enabledItemNames()
    if not enabled[itemName] then return finish(false, 'That weapon is not available in the armory.') end
    local item = armoryItem(itemName)
    if not item then return finish(false, 'That item is no longer available from the equipment catalog.') end
    local stock = MySQL.single.await([[SELECT stock,issue_amount FROM cm_legal_armory_stock
        WHERE organization_id='police' AND item_name=? LIMIT 1]], { itemName })
    local issueAmount = stock and math.max(1, tonumber(stock.issue_amount) or item.issueAmount or 1) or (item.issueAmount or 1)
    if not stock or tonumber(stock.stock) < issueAmount then return finish(false, 'That equipment is out of stock.') end
    local operationId = BeginPoliceOperation('armory_checkout', characterId, nil, 0, { itemName = itemName })
    if not operationId then return finish(false, 'Could not start the checkout operation.') end
    local changed = MySQL.update.await([[UPDATE cm_legal_armory_stock SET stock=stock-?
        WHERE organization_id='police' AND item_name=? AND stock>=?]], { issueAmount, itemName, issueAmount })
    if tonumber(changed) ~= 1 then
        FinishPoliceOperation(operationId, 'refunded', { reason = 'out_of_stock', itemGranted = false })
        return finish(false, 'That equipment is out of stock.')
    end
    local ok, err = grantArmoryWeapon(src, characterId, itemName, item.itemType, issueAmount)
    if not ok then
        MySQL.update.await([[UPDATE cm_legal_armory_stock SET stock=stock+?,max_stock=GREATEST(max_stock,stock)
            WHERE organization_id='police' AND item_name=?]], { issueAmount, itemName })
        FinishPoliceOperation(operationId, 'refunded', { reason = tostring(err), itemGranted = false })
        return finish(false, ('Could not issue that weapon (%s).'):format(tostring(err)))
    end
    -- The accountability log the whole feature is for -- already visible in
    -- the existing F7 Activity Logs tab, no separate armory-log UI needed.
    log(characterId, 'armory_checkout', { itemName = itemName, amount = issueAmount, itemType = item.itemType })
    FinishPoliceOperation(operationId, 'completed', { itemName = itemName, amount = issueAmount, itemType = item.itemType, itemGranted = true })
    return finish(true, 'Department equipment checked out.')
end)

AddEventHandler('cm-police:server:memberWentOffDuty', function(src, characterId, reason)
    src = tonumber(src)
    if GetResourceState('cm-inventory') ~= 'started' then return end
    local ok, _, removed
    if src and src > 0 and GetPlayerName(src) then
        ok, _, removed = exports['cm-inventory']:ReclaimArmoryIssues(src, 'police', reason or 'police_off_duty')
    else
        ok, _, removed = exports['cm-inventory']:ReclaimArmoryIssuesForCharacter(characterId, 'police', reason or 'police_off_duty')
    end
    if ok ~= true then
        print(('[cm-police] failed to reclaim department equipment for character %s'):format(tostring(characterId)))
        return
    end
    for _, item in ipairs(type(removed) == 'table' and removed or {}) do
        if item.issueId then
            MySQL.update.await([[UPDATE cm_legal_armory_issues SET status='returned'
                WHERE id=? AND organization_id='police' AND character_id=? AND status='issued']],
                { item.issueId, tostring(characterId) })
            MySQL.update.await([[UPDATE cm_legal_armory_stock SET stock=stock+?,max_stock=GREATEST(max_stock,stock)
                WHERE organization_id='police' AND item_name=?]], { item.quantity, item.itemName })
        end
    end
    if #removed > 0 then log(characterId, 'armory_automatic_return', { reason = reason, items = removed }) end
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_armory_catalog (
        item_name VARCHAR(64) NOT NULL, enabled TINYINT(1) NOT NULL DEFAULT 0,
        set_by VARCHAR(64) NULL, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (item_name), KEY idx_cm_legal_armory_catalog_enabled (enabled)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_armory_stock (
        organization_id VARCHAR(32) NOT NULL, item_name VARCHAR(64) NOT NULL,
        enabled TINYINT(1) NOT NULL DEFAULT 0, stock INT UNSIGNED NOT NULL DEFAULT 0,
        max_stock INT UNSIGNED NOT NULL DEFAULT 100, issue_amount SMALLINT UNSIGNED NOT NULL DEFAULT 1,
        min_tier SMALLINT UNSIGNED NOT NULL DEFAULT 0, updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (organization_id,item_name), KEY idx_cm_legal_armory_enabled (organization_id,enabled)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_armory_issues (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, license_number VARCHAR(40) NOT NULL,
        organization_id VARCHAR(32) NOT NULL, character_id VARCHAR(64) NOT NULL,
        item_name VARCHAR(64) NOT NULL, item_type VARCHAR(16) NOT NULL,
        quantity SMALLINT UNSIGNED NOT NULL DEFAULT 1,
        status ENUM('issued','confiscated','returned','void') NOT NULL DEFAULT 'issued',
        issued_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id), UNIQUE KEY uq_cm_legal_armory_license (license_number),
        KEY idx_cm_legal_armory_issue_character (character_id), KEY idx_cm_legal_armory_issue_org (organization_id,status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_armory_catalog (
        item_name VARCHAR(64) NOT NULL,
        enabled TINYINT(1) NOT NULL DEFAULT 1,
        set_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (item_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[INSERT IGNORE INTO cm_legal_armory_catalog (item_name,enabled,set_by)
        SELECT item_name,enabled,set_by FROM cm_police_armory_catalog WHERE enabled=1]])
    ArmoryReady = true
    PoliceSchemaMarkReady('armory')
end)
