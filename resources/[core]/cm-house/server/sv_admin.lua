-- ============================================================
--  cm-house | sv_admin.lua
--  /cmadmin -- manage every property, layout and garage in one place.
-- ============================================================

--- /cmadminhouse -- the records office.
--- (/cmadmin kept as an alias; both open the same panel.)
local ADMIN_TABS = { houses = true, interiors = true, garages = true, recovery = true }
local ADMIN_TAB_SCOPE = {
    houses = 'properties', interiors = 'interiors', garages = 'garages', recovery = 'recovery',
}

local function hasAdminScope(src, scope)
    -- Hard local-development bypass. Keep this check here as well as in
    -- sv_compat so the panel still opens even if an ACL bridge is unavailable.
    if Config.DevelopmentPublicAdmin == true then return true end
    return HasHouseStaffPermission(src, scope or 'panel') == true
end

local function adminCapabilities(src)
    return {
        panel = hasAdminScope(src, 'panel'),
        create = hasAdminScope(src, 'create'),
        properties = hasAdminScope(src, 'properties'),
        interiors = hasAdminScope(src, 'interiors'),
        garages = hasAdminScope(src, 'garages'),
        pricing = hasAdminScope(src, 'pricing'),
        photos = hasAdminScope(src, 'photos'),
        recovery = hasAdminScope(src, 'recovery'),
    }
end

local function normalizedAdminTab(tab)
    tab = tostring(tab or 'houses')
    return ADMIN_TABS[tab] and tab or 'houses'
end

-- JSON helper must be declared before callbacks that close over it.
local function decodeAdminJson(value, fallback)
    if type(value) == 'table' then return value end
    if value == nil or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or fallback
end

local function adminInvokerAllowed()
    if Config.DevelopmentPublicAdmin == true then return true end
    local invoker = GetInvokingResource()
    if not invoker or invoker == GetCurrentResourceName() then return true end
    local configured = Config.Integration and Config.Integration.authorizedResources or {}
    local grants = configured[invoker]
    return grants == true or (type(grants) == 'table' and (grants['*'] == true or grants.admin == true))
end

local function openPanel(src, tab)
    src = tonumber(src)
    if not src or src == 0 then
        print('[cm-house] The property admin panel must be opened for an in-game player.')
        return false, 'player_required'
    end
    if not hasAdminScope(src, 'panel') then
        Notify(src, 'You cannot manage properties.', 'error')
        return false, 'not_authorized'
    end
    tab = normalizedAdminTab(tab)
    local allowedTab = hasAdminScope(src, ADMIN_TAB_SCOPE[tab])
    if not allowedTab then
        for _, candidate in ipairs({ 'houses', 'interiors', 'garages', 'recovery' }) do
            if hasAdminScope(src, ADMIN_TAB_SCOPE[candidate]) then
                tab = candidate
                allowedTab = true
                break
            end
        end
    end
    if not allowedTab then
        Notify(src, 'Your admin rank has no property-panel sections assigned.', 'error')
        return false, 'no_panel_sections'
    end
    TriggerClientEvent('cm-house:client:openAdmin', src, tab)
    return true
end

local registeredAdminCommands = {}
local function registerAdminCommand(name)
    name = tostring(name or '')
    if name == '' or registeredAdminCommands[name] then return end
    registeredAdminCommands[name] = true
    RegisterCommand(name, function(src) openPanel(src, 'houses') end, false)
end

-- /cmadmin is retained for compatibility. The unique aliases avoid command
-- collisions with cm-admin or another server resource.
registerAdminCommand('cmadmin')
for _, commandName in ipairs(Config.PublicAdminCommands or { 'cmadminhouse', 'cmhouseadmin', 'houseadmin' }) do
    registerAdminCommand(commandName)
end

-- Button-ready entry points. A UI button in cm-admin can call the client export,
-- or an authorized server resource can use these exports. Every path re-checks
-- the player's current ACL/rank before opening anything.
RegisterNetEvent('cm-house:server:requestAdminPanel', function(tab)
    openPanel(source, tab)
end)

RegisterNetEvent('cm-house:server:requestHouseCreator', function()
    local src = source
    if not hasAdminScope(src, 'create') then
        Notify(src, 'You cannot create properties.', 'error')
        return
    end
    TriggerClientEvent('cm-house:client:startPlacement', src)
end)

exports('OpenAdminPanel', function(src, tab)
    if not adminInvokerAllowed() then return false, 'resource_not_authorized' end
    return openPanel(src, tab)
end)

exports('OpenHouseCreator', function(src)
    if not adminInvokerAllowed() then return false, 'resource_not_authorized' end
    src = tonumber(src)
    if not src or src <= 0 then return false, 'player_required' end
    if not hasAdminScope(src, 'create') then return false, 'not_authorized' end
    TriggerClientEvent('cm-house:client:startPlacement', src)
    return true
end)

exports('GetHouseAdminPanelTabs', function()
    return {
        { id = 'houses', label = 'Properties', permission = GetHouseAdminPermissionKey('properties') },
        { id = 'interiors', label = 'Interior layouts', permission = GetHouseAdminPermissionKey('interiors') },
        { id = 'garages', label = 'Garage layouts', permission = GetHouseAdminPermissionKey('garages') },
        { id = 'recovery', label = 'Vehicle recovery', permission = GetHouseAdminPermissionKey('recovery') },
    }
end)

-- ------------------------------------------------------------
--  Everything the panel needs, in one call.
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:adminData', function(src)
    if not hasAdminScope(src, 'panel') then return nil end
    local capabilities = adminCapabilities(src)

    local houses = {}
    for id, h in pairs(Houses) do
        local tpl = InteriorTemplates[h.interior_template_id]
        local g   = h.garage_template_id and GarageTemplates[h.garage_template_id]

        houses[#houses + 1] = {
            id          = id,
            number      = h.house_number,
            label       = h.label,
            type        = h.house_type,
            stars       = h.star_rating,
            garden      = h.has_garden,
            pool        = h.has_pool,
            helipad     = h.has_helipad,

            owner       = h.owner_cid and GetCharName(h.owner_cid) or nil,
            ownerCid    = h.owner_cid,
            forSale     = h.owner_cid == nil,
            locked      = h.locked,
            status      = h.status,

            price       = h.price,
            govValue    = h.gov_value,
            dailyCost   = h.daily_cost,

            interior    = tpl and tpl.label or '(none)',
            interiorId  = h.interior_template_id,
            garage      = g and g.label or nil,
            garageId    = h.garage_template_id,
            capacity    = g and g.capacity or 0,

            image       = h.image_url,   -- nil -> the client renders it live
            photoCam    = h.photo_cam,
            door        = h.door_coords,
        }
    end
    table.sort(houses, function(a, b)
        -- House numbers may be stored as text or int and can be non-numeric
        -- labels on legacy rows. Sort numerically when both parse as numbers,
        -- otherwise fall back to a stable string compare so mixed data never
        -- throws.
        local na, nb = tonumber(a.number), tonumber(b.number)
        if na and nb then return na < nb end
        return tostring(a.number) < tostring(b.number)
    end)

    -- Read layouts from the DB, not the cache: the cache only holds ENABLED
    -- ones, and a panel that cannot see a disabled layout cannot re-enable it.
    local interiors = {}
    for _, t in ipairs(MySQL.query.await(
        'SELECT * FROM cm_house_interior_templates ORDER BY label') or {}) do
        local weaponStorages = decodeAdminJson(t.weapon_storages or t.wardrobes, {}) or {}
        local stashes   = decodeAdminJson(t.stashes, {}) or {}
        interiors[#interiors + 1] = {
            id        = t.id,
            label     = t.label,
            signature = t.signature or '',
            weaponStorages = #weaponStorages, wardrobes = #weaponStorages,
            stashes   = #stashes,
            enabled   = DbBool(t.enabled),
            usedBy    = TemplateUsage('interior', t.id),
            source    = t.source_kind,
        }
    end

    local garages = {}
    for _, t in ipairs(MySQL.query.await(
        'SELECT * FROM cm_house_garage_templates ORDER BY capacity') or {}) do
        local exits = decodeAdminJson(t.vehicle_exits, {}) or {}
        if #exits == 0 and decodeAdminJson(t.vehicle_exit, nil) then exits = { true } end
        garages[#garages + 1] = {
            id       = t.id,
            label    = t.label,
            capacity = t.capacity,
            enabled  = DbBool(t.enabled),
            usedBy   = TemplateUsage('garage', t.id),
            source   = t.source_kind,
            exits = #exits,
        }
    end

    local recovery = {}
    if capabilities.recovery and GetResourceState('cm-vehicles') == 'started' then
        local ok, rows = pcall(function()
            return exports['cm-vehicles']:ListVehicleRecoveryProblems(150)
        end)
        if ok and type(rows) == 'table' then
            for _, v in ipairs(rows) do
                recovery[#recovery + 1] = {
                    id = tonumber(v.id),
                    plate = tostring(v.plate or ''),
                    label = tostring(v.label or v.model or 'Vehicle'),
                    ownerCid = v.owner_character_id and tostring(v.owner_character_id) or nil,
                    stored = DbBool(v.is_stored),
                    garage = v.garage and tostring(v.garage) or nil,
                    locationState = tostring(v.location_state or 'UNKNOWN'),
                    locationRef = v.location_ref and tostring(v.location_ref) or nil,
                    locationSlot = tonumber(v.location_slot),
                    assignedHouseId = tonumber(v.assigned_house_id),
                    assignedSlot = tonumber(v.assigned_slot),
                    duplicateCount = tonumber(v.duplicate_count) or 0,
                }
            end
        end
    end

    if not capabilities.properties then houses = {} end
    if not capabilities.interiors then interiors = {} end
    if not capabilities.garages then garages = {} end
    if not capabilities.recovery then recovery = {} end
    return { houses = houses, interiors = interiors, garages = garages, recovery = recovery, capabilities = capabilities }
end)

lib.callback.register('cm-house:server:adminVehicleRecovery', function(src, identity, action, data)
    if not hasAdminScope(src, 'recovery') then return false, 'Not permitted.' end
    if GetResourceState('cm-vehicles') ~= 'started' then return false, 'cm-vehicles is not running.' end
    local allowed = {
        reconcile = true, duplicates = true, recall = true, public = true,
        impound = true, clear_assignment = true, delete_entity = true, flush = true,
    }
    action = tostring(action or '')
    if not allowed[action] then return false, 'Unknown recovery action.' end
    local ok, result, detail = pcall(function()
        return exports['cm-vehicles']:RunVehicleRecoveryAction(src, identity, action, data or {})
    end)
    if not ok then return false, 'Recovery integration failed: ' .. tostring(result) end
    if result ~= true then return false, detail or 'Recovery action failed.' end
    Audit(src, 'vehicle_recovery', { identity = identity, action = action, result = detail })
    return true, detail or 'Recovery completed.'
end)

-- ------------------------------------------------------------
--  Property actions
-- ------------------------------------------------------------
-- Wipe a property's general storage inventory. Called whenever ownership is
-- cleared or transferred through the admin panel so a new owner never inherits
-- the previous owner's stored items, and a deleted house leaves no orphan rows.
-- Weapon storage is handled separately (it must be recovered before these
-- actions are even allowed).
local function wipeHouseStorage(houseId)
    houseId = tonumber(houseId)
    if not houseId then return false, 'invalid_house_id' end
    local ok, result = pcall(function()
        return MySQL.transaction.await({
            {
                query = 'DELETE FROM inventory_items WHERE owner_type = ? AND owner_id LIKE ?',
                values = { 'house_storage', ('%d:%%'):format(houseId) },
            },
            {
                query = 'DELETE FROM inventory_items WHERE owner_type = ? AND owner_id LIKE ?',
                values = { 'house_wardrobe', ('%d:%%'):format(houseId) },
            },
        })
    end)
    if not ok or result ~= true then
        print(('[cm-house] ^1could not wipe property storage for house %s: %s^7')
            :format(tostring(houseId), tostring(result)))
        return false, tostring(result or 'storage_cleanup_failed')
    end
    return true
end

lib.callback.register('cm-house:server:adminAction', function(src, action, houseId, arg)
    local requiredScope = tostring(action or '') == 'setPrice' and 'pricing' or 'properties'
    if not hasAdminScope(src, requiredScope) then return false, 'Not permitted.' end

    local h = Houses[houseId]
    if not h then return false, 'That property does not exist.' end

    local adminCid = GetCid(src)
    local securedWeaponCount = HouseWeaponStorageCount and HouseWeaponStorageCount(houseId) or 0

    if action == 'evict' then
        if securedWeaponCount > 0 then
            return false, ('Empty or recover the family weapon storage first (%d stack%s remain).')
                :format(securedWeaponCount, securedWeaponCount == 1 and '' or 's')
        end
        if not h.owner_cid then return false, 'Nobody owns it.' end
        local was = h.owner_cid

        local familyOk, familyContext = CMHouseFamilyLifecycle.GetContext(h, {})
        if not familyOk then
            return false, ('The linked family could not be prepared for eviction: %s')
                :format(tostring(familyContext))
        end

        -- Cars are released before ownership changes. If any active vehicle
        -- cannot be saved/deleted safely, keep the property and family intact.
        local vehiclesReleased, releaseInfo = EvictVehicles(houseId, 'admin_evict_family_house', adminCid)
        if not vehiclesReleased then
            return false, 'Vehicle release failed: ' .. tostring(releaseInfo)
        end

        local statements = {
            {
                query = 'DELETE FROM inventory_items WHERE owner_type = ? AND owner_id LIKE ?',
                values = { 'house_storage', ('%d:%%'):format(houseId) },
            },
            {
                query = 'DELETE FROM inventory_items WHERE owner_type = ? AND owner_id LIKE ?',
                values = { 'house_wardrobe', ('%d:%%'):format(houseId) },
            },
            {
                query = 'DELETE FROM cm_house_access WHERE house_id = ?',
                values = { houseId },
            },
        }
        CMHouseFamilyLifecycle.AppendDeleteStatements(
            statements, familyContext and familyContext.id or nil, houseId)
        statements[#statements + 1] = {
            query = [[
                UPDATE cm_houses
                SET owner_cid = NULL, family_id = NULL, for_sale = 1,
                    paid_until = NULL, locked = 1
                WHERE id = ?
            ]],
            values = { houseId },
        }

        local committed = MySQL.transaction.await(statements)
        if committed ~= true then
            return false, 'The eviction transaction failed. The property and family were not changed.'
        end

        local oldFamily = familyContext and familyContext.id or nil
        h.owner_cid, h.family_id = nil, nil
        h.for_sale, h.paid_until, h.locked = true, nil, true
        for _, set in pairs(Access) do set[houseId] = nil end

        CMHouseFamilyLifecycle.FinalizeDeletedFamily(familyContext, houseId, 'evicted', adminCid)
        LogHouse(houseId, oldFamily, adminCid, 'admin_evict_family_house', {
            was = was,
            familyDeleted = oldFamily ~= nil,
            discardedFamilyBank = familyContext and familyContext.bankBalance or 0,
        })
        Audit(src, 'admin_evict', {
            houseId = houseId,
            was = was,
            familyDeleted = oldFamily,
        })
        TriggerClientEvent('cm-house:client:syncHouse', -1, BuildClientHouse(h))
        PushOwnership(was)

        local suffix = oldFamily and ' The linked family was disbanded.' or ''
        return true, ('Evicted %s.%s'):format(GetCharName(was), suffix)
    end

    if action == 'delete' then
        if securedWeaponCount > 0 then
            return false, ('This family property still contains %d secured weapon stack%s and cannot be deleted.')
                :format(securedWeaponCount, securedWeaponCount == 1 and '' or 's')
        end
        if h.owner_cid then
            return false, 'Evict the owner first -- eviction will also disband the linked family.'
        end

        local familyOk, familyContext = CMHouseFamilyLifecycle.GetContext(h, {})
        if not familyOk then
            return false, ('The linked family could not be prepared for deletion: %s')
                :format(tostring(familyContext))
        end

        local vehiclesReleased, releaseInfo = EvictVehicles(houseId, 'admin_delete_family_house', adminCid)
        if not vehiclesReleased then
            return false, 'Vehicle release failed: ' .. tostring(releaseInfo)
        end

        local statements = {
            {
                query = 'DELETE FROM inventory_items WHERE owner_type = ? AND owner_id LIKE ?',
                values = { 'house_storage', ('%d:%%'):format(houseId) },
            },
            {
                query = 'DELETE FROM inventory_items WHERE owner_type = ? AND owner_id LIKE ?',
                values = { 'house_wardrobe', ('%d:%%'):format(houseId) },
            },
            {
                query = 'DELETE FROM cm_house_access WHERE house_id = ?',
                values = { houseId },
            },
        }
        CMHouseFamilyLifecycle.AppendDeleteStatements(
            statements, familyContext and familyContext.id or nil, houseId)
        statements[#statements + 1] = {
            query = 'DELETE FROM cm_houses WHERE id = ?',
            values = { houseId },
        }

        local committed = MySQL.transaction.await(statements)
        if committed ~= true then
            return false, 'The property deletion transaction failed. Nothing was deleted.'
        end

        local oldFamily = familyContext and familyContext.id or nil
        CMHouseFamilyLifecycle.FinalizeDeletedFamily(familyContext, houseId, 'deleted', adminCid)
        if DeleteHousePhoto then
            local removed, photoWhy = DeleteHousePhoto(houseId)
            if not removed then
                print(('[cm-house] could not delete photo for removed house %s: %s')
                    :format(tostring(houseId), tostring(photoWhy)))
            end
        end
        LogHouse(houseId, oldFamily, adminCid, 'admin_delete_family_house', {
            number = h.house_number,
            label = h.label,
            familyDeleted = oldFamily ~= nil,
            discardedFamilyBank = familyContext and familyContext.bankBalance or 0,
        })
        Houses[houseId] = nil
        for _, set in pairs(Access) do set[houseId] = nil end

        Audit(src, 'admin_delete', {
            houseId = houseId,
            number = h.house_number,
            familyDeleted = oldFamily,
        })
        TriggerClientEvent('cm-house:client:removeHouse', -1, houseId)
        local suffix = oldFamily and ' The linked family was disbanded.' or ''
        return true, ('Deleted %s.%s'):format(h.label, suffix)
    end

    if action == 'setPrice' then
        local price = math.max(0, math.min(2000000000, math.floor(tonumber(arg) or 0)))
        MySQL.update.await([[
            UPDATE cm_houses SET price = ?, gov_value = ?, insurance = ?, daily_cost = ?
            WHERE id = ?
        ]], { price, math.floor(price * 0.8), math.floor(price * 0.03),
              math.floor(price * 0.001), houseId })

        h.price     = price
        h.gov_value = math.floor(price * 0.8)
        h.insurance = math.floor(price * 0.03)
        h.daily_cost = math.floor(price * 0.001)

        Audit(src, 'admin_price', { houseId = houseId, price = price })
        return true, ('Price set to $%s.'):format(price)
    end

    if action == 'giveTo' then
        if securedWeaponCount > 0 then
            return false, 'Recover the existing weapon storage before assigning a new owner.'
        end
        local cid = tonumber(arg)
        if not cid then return false, 'Give a character id.' end

        local exists = MySQL.scalar.await('SELECT id FROM characters WHERE id = ?', { cid })
        if not exists then return false, ('No character #%d.'):format(cid) end
        if h.owner_cid then return false, 'Someone already owns it. Evict them first.' end

        -- Clear any leftover storage rows before the new owner takes possession,
        -- so they never inherit a previous occupant's items.
        local storageCleared, storageWhy = wipeHouseStorage(houseId)
        if not storageCleared then
            return false, 'Could not clear the previous property storage: ' .. tostring(storageWhy)
        end

        local paidUntil = os.date('%Y-%m-%d', os.time() + (7 * 86400))
        MySQL.update.await(
            'UPDATE cm_houses SET owner_cid = ?, for_sale = 0, paid_until = ? WHERE id = ?',
            { cid, paidUntil, houseId })

        h.owner_cid, h.for_sale, h.paid_until = cid, false, paidUntil

        LogHouse(houseId, nil, adminCid, 'admin_give', { to = cid })
        Audit(src, 'admin_give', { houseId = houseId, to = cid })
        TriggerClientEvent('cm-house:client:syncHouse', -1, BuildClientHouse(h))
        PushOwnership(cid)
        return true, ('Given to %s.'):format(GetCharName(cid))
    end

    if action == 'goto' then
        return true, h.door_coords
    end

    return false, 'Unknown action.'
end)

-- ------------------------------------------------------------
--  Layout actions
-- ------------------------------------------------------------
-- Admin management must be able to read disabled templates. The runtime caches
-- intentionally contain enabled templates only, so using those caches here made
-- the "Enable" button fail with "layout does not exist".
local function loadAdminTemplate(kind, id)
    id = tonumber(id)
    if not id then return nil end

    if kind == 'garage' then
        local t = MySQL.single.await(
            'SELECT * FROM cm_house_garage_templates WHERE id = ? LIMIT 1', { id })
        if not t then return nil end
        t.id = tonumber(t.id)
        t.capacity = tonumber(t.capacity) or 0
        t.enabled = DbBool(t.enabled)
        t.player_entry = decodeAdminJson(t.player_entry, nil)
        t.vehicle_exit = decodeAdminJson(t.vehicle_exit, nil)
        t.vehicle_exits = decodeAdminJson(t.vehicle_exits, {})
        if #t.vehicle_exits == 0 and t.vehicle_exit then t.vehicle_exits = { t.vehicle_exit } end
        t.vehicle_exit = t.vehicle_exits[1] or t.vehicle_exit
        t.slots = {}
        for _, row in ipairs(MySQL.query.await([[
            SELECT slot_index, coords, icon
            FROM cm_house_garage_slots
            WHERE template_id = ?
            ORDER BY slot_index
        ]], { id }) or {}) do
            local index = tonumber(row.slot_index)
            if index then
                t.slots[index] = {
                    coords = decodeAdminJson(row.coords, nil),
                    icon = decodeAdminJson(row.icon, nil),
                }
            end
        end
        return t
    end

    if kind == 'interior' then
        local t = MySQL.single.await(
            'SELECT * FROM cm_house_interior_templates WHERE id = ? LIMIT 1', { id })
        if not t then return nil end
        t.id = tonumber(t.id)
        t.enabled = DbBool(t.enabled)
        t.entry = decodeAdminJson(t.entry, nil)
        t.exit_point = decodeAdminJson(t.exit_point, nil)
        t.wardrobes = decodeAdminJson(t.wardrobes, {})
        t.weapon_storages = decodeAdminJson(t.weapon_storages, t.wardrobes)
        t.stashes = decodeAdminJson(t.stashes, {})
        t.allowed_types = decodeAdminJson(t.allowed_types, {})
        return t
    end

    return nil
end

lib.callback.register('cm-house:server:adminTemplate', function(src, action, kind, id, arg)
    if kind ~= 'interior' and kind ~= 'garage' then return false, 'Unknown layout kind.' end
    local scope = kind == 'garage' and 'garages' or 'interiors'
    if not hasAdminScope(src, scope) then return false, 'Not permitted.' end

    -- Standalone creation: no property wizard and no dummy property. The admin
    -- walks every coordinate directly in the intended MLO/shell/world space.
    if action == 'create' then
        TriggerClientEvent('cm-house:client:adminCaptureTemplate', src, kind, nil)
        return true, 'Walk the points where the reusable layout should live.'
    end

    id = tonumber(id)
    local t = loadAdminTemplate(kind, id)
    if not t then return false, 'That layout does not exist.' end
    local tbl = kind == 'garage' and 'cm_house_garage_templates' or 'cm_house_interior_templates'

    -- Re-walk every point of an existing layout. This also works for disabled
    -- templates because it reads directly from the database rather than cache.
    if action == 'rewalk' then
        TriggerClientEvent('cm-house:client:adminCaptureTemplate', src, kind, id)
        return true, ('Re-walking "%s". Set every point again.'):format(t.label)
    end

    if action == 'rename' then
        local label = tostring(arg or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 64)
        if label == '' then return false, 'Give it a name.' end
        local affected = MySQL.update.await(
            ('UPDATE %s SET label = ? WHERE id = ?'):format(tbl), { label, id })
        if affected == nil then return false, 'The layout was not renamed.' end
        LoadTemplates()
        Audit(src, 'template_rename', { kind = kind, id = id, label = label })
        return true, 'Renamed.'
    end

    if action == 'disable' or action == 'delete' then
        local used = tonumber(TemplateUsage(kind, id)) or 0
        if used > 0 then
            return false, ('%d propert%s still use this layout. Move or delete those properties first.')
                :format(used, used == 1 and 'y' or 'ies')
        end

        if action == 'delete' then
            -- The usage check above is repeated atomically in SQL. This closes
            -- the race where another admin assigns the template between the
            -- count and the DELETE, while the database FK remains a final guard.
            local houseColumn = kind == 'garage' and 'garage_template_id' or 'interior_template_id'
            local deleteSql = ('DELETE FROM %s WHERE id = ? AND NOT EXISTS '
                .. '(SELECT 1 FROM cm_houses WHERE %s = ? LIMIT 1)'):format(tbl, houseColumn)
            local called, affected = pcall(function()
                return MySQL.update.await(deleteSql, { id, id })
            end)
            if not called then
                return false, 'The layout is still referenced by a property and cannot be deleted.'
            end
            if not affected or tonumber(affected) <= 0 then
                return false, 'The layout is in use or was already removed. It was not deleted.'
            end
            LoadTemplates()
            Audit(src, 'template_delete', { kind = kind, id = id, label = t.label })
            return true, ('Deleted "%s".'):format(t.label)
        end

        if t.enabled ~= true then return false, 'That layout is already disabled.' end
        local affected = MySQL.update.await(
            ('UPDATE %s SET enabled = 0 WHERE id = ? AND enabled = 1'):format(tbl), { id })
        if not affected or tonumber(affected) <= 0 then return false, 'The layout was not disabled.' end
        LoadTemplates()
        Audit(src, 'template_disable', { kind = kind, id = id })
        return true, 'Layout disabled. It remains available in this admin panel.'
    end

    if action == 'enable' then
        if t.enabled == true then return false, 'That layout is already enabled.' end
        local affected = MySQL.update.await(
            ('UPDATE %s SET enabled = 1 WHERE id = ? AND enabled = 0'):format(tbl), { id })
        if not affected or tonumber(affected) <= 0 then return false, 'The layout was not enabled.' end
        LoadTemplates()
        Audit(src, 'template_enable', { kind = kind, id = id })
        return true, 'Layout re-enabled.'
    end

    if action == 'preview' then
        if kind == 'garage' then
            local slots = {}
            for i = 1, tonumber(t.capacity) or 0 do
                if t.slots[i] and t.slots[i].coords then slots[i] = t.slots[i].coords end
            end
            return true, {
                kind = 'garage',
                sourceKind = t.source_kind, sourceRef = t.source_ref,
                entry = t.player_entry,
                vehicleExit = t.vehicle_exit, vehicleExits = t.vehicle_exits,
            slots = slots,
            }
        end
        return true, {
            kind = 'interior',
            sourceKind = t.source_kind, sourceRef = t.source_ref,
            entry = t.entry, exitPoint = t.exit_point,
            weaponStorages = t.weapon_storages or t.wardrobes, wardrobes = t.weapon_storages or t.wardrobes, stashes = t.stashes,
        }
    end

    return false, 'Unknown action.'
end)

-- ------------------------------------------------------------
--  Pricing
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:adminPricing', function(src, changes)
    if not hasAdminScope(src, 'pricing') then return false, 'Not permitted.' end

    for key, v in pairs(changes or {}) do
        local price = math.max(0, math.floor(tonumber(v.priceAdd) or 0))
        local star  = math.max(0, math.min(5, math.floor(tonumber(v.starAdd) or 0)))
        MySQL.update.await(
            'UPDATE cm_house_pricing SET price_add = ?, star_add = ? WHERE feature_key = ?',
            { price, star, key })
    end

    LoadPricing()
    Audit(src, 'admin_pricing', changes)
    return true, 'Pricing updated. New properties use it immediately.'
end)

--- The records-office Add button always requires real staff. The separate
--- /cmhouse command may be relaxed only in deliberate development mode.
RegisterNetEvent('cm-house:server:startWizard', function()
    local src = source
    if not hasAdminScope(src, 'create') then
        Notify(src, 'You cannot create properties.', 'error')
        return
    end
    TriggerClientEvent('cm-house:client:startPlacement', src)
end)

--- /cmhousecheck -- what is actually wired up.
--- The "no SpawnAdminVehicle export" message could mean cm-vehicles is old, or
--- not started, or that its admin.lua failed to load. Say which.
RegisterCommand('cmhousecheck', function(src)
    if src ~= 0 and not hasAdminScope(src, 'panel') then return end

    local function line(s) 
        print(s)
        if src ~= 0 then TriggerClientEvent('cm-house:client:printLines', src, { s }) end
    end

    line('[cm-house] ─── dependency check ───')

    for _, res in ipairs({ 'oxmysql', 'ox_lib', 'cm-playerdata', 'cm-inventory',
                           'cm-vehicles', 'cm-core', 'screenshot-basic' }) do
        local state = GetResourceState(res)
        line(('  %-18s %s'):format(res, state))
    end

    line('[cm-house] ─── cm-vehicles exports ───')

    if GetResourceState('cm-vehicles') ~= 'started' then
        line('  cm-vehicles is not started. Garage car placement will use the fallback.')
    else
        -- CALL each export to test it. `type(exports['x'].Fn) == 'function'`
        -- does NOT work: FiveM hands back a callable PROXY TABLE, not a
        -- function, so that check reports every export as missing.
        --
        -- Only "No such export" means absent. Any other error means the export
        -- is there and simply objected to the nonsense arguments we passed it.
        local function exportExists(fn)
            local ok, err = pcall(function()
                return exports['cm-vehicles'][fn]()
            end)
            if ok then return true end
            return not tostring(err):find('No such export')
        end

        local hasAdmin = false

        for _, fn in ipairs({ 'SpawnAdminVehicle', 'DeleteAdminVehicle',
                              'SpawnVehicleFromParking', 'DeleteSpawnedVehicle',
                              'GetVehicleByPlate', 'HasVehicleAccess' }) do
            local present = exportExists(fn)
            if fn == 'SpawnAdminVehicle' then hasAdmin = present end
            line(('  %-24s %s'):format(fn, present and 'ok' or 'MISSING'))
        end

        if not hasAdmin then
            line('')
            line('  SpawnAdminVehicle is missing. cm-vehicles needs server/admin.lua,')
            line('  AND that file must be in its fxmanifest server_scripts.')
            line('  Garage placement still works -- with a car you nudge, not drive.')
        end
    end

    line('[cm-house] ─── templates ───')
    local ni, ng = 0, 0
    for _ in pairs(InteriorTemplates) do ni = ni + 1 end
    for _ in pairs(GarageTemplates) do ng = ng + 1 end
    line(('  %d interior layouts, %d garage layouts'):format(ni, ng))

    local nsel = 0
    for _, g in pairs(GarageSizes) do
        if g.selectable then nsel = nsel + 1 end
    end
    line(('  %d selectable garage sizes'):format(nsel))
    if nsel == 0 then
        line('  ^1No garage sizes! Run sql/005_features.sql^7')
    end
end, false)
