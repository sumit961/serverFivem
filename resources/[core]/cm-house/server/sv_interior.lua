-- ============================================================
--  cm-house | sv_interior.lua   |  PHASE 1 (rewritten)
--
--  Points come from the TEMPLATE, ownership from the PROPERTY.
--  Entering also drops the player into a routing bucket, so two people in
--  two different motel rooms no longer stand in the same physical space.
-- ============================================================

local function playerNear(src, point, maxDistance)
    if type(point) ~= 'table' then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    local x, y, z = tonumber(point.x), tonumber(point.y), tonumber(point.z)
    if not x or not y or not z then return false end
    return #(coords - vector3(x, y, z)) <= (tonumber(maxDistance) or 4.0)
end

local function requireExteriorDoor(src, house)
    local insideHouse = WhereIs(src)
    if insideHouse then return false, 'You are already inside a property.' end
    if GetPlayerRoutingBucket(src) ~= 0 then return false, 'You are not in the outside world.' end
    if not playerNear(src, house and house.door_coords, math.max(4.0, tonumber(Config.Prompt.distance) or 2.0) + 2.0) then
        return false, 'Move closer to the property door.'
    end
    return true
end

lib.callback.register('cm-house:server:enterHome', function(src, houseId)
    houseId = tonumber(houseId)
    local cid = GetCid(src)
    local house = Houses[houseId]
    if not house then return false, 'That property does not exist.' end
    local atDoor, doorWhy = requireExteriorDoor(src, house)
    if not atDoor then return false, doorWhy end

    local ok, why = CanAccessProperty(cid, houseId, ACTIONS.HOUSE_ENTER)
    if not ok then return false, why end

    -- Lock state never bypasses authorization. Owner/family permission is
    -- required whether the door is currently locked or unlocked.
    if house.locked then
        local allowed = CanAccessProperty(cid, houseId, ACTIONS.HOUSE_ENTER)
        if not allowed then return false, 'The door is locked.' end
    end

    local tpl = InteriorTemplates[house.interior_template_id]
    if not tpl then return false, 'This property has no interior template.' end

    -- Wardrobe positions are only sent to someone allowed to open them, so a
    -- tampered client cannot even learn where they are.
    local canWeaponStorage = CanAccessProperty(cid, houseId, ACTIONS.WEAPON_STORAGE_USE)
    local canStorage  = CanAccessProperty(cid, houseId, ACTIONS.STORAGE_USE)

    local weaponStorages = {}
    if canWeaponStorage then
        for i, w in ipairs(tpl.weapon_storages or tpl.wardrobes or {}) do
            weaponStorages[i] = { index = i, coords = w }
        end
    end

    local stashes = {}
    if canStorage then
        for i, st in ipairs(tpl.stashes) do
            stashes[i] = { index = i, coords = st, label = st.label, slots = st.slots }
        end
    end

    SendToHouse(src, houseId)
    LogHouse(houseId, house.family_id, cid, 'house_enter', nil)

    return true, {
        houseId    = houseId,
        label      = house.label,
        familyId   = house.family_id,
        familyName = (function()
            local family = house.family_id and GetFamilyDisplay(house.family_id) or nil
            return family and tostring(family.name or family.label or '') or nil
        end)(),
        isFamilyHouse = house.family_id ~= nil,
        sourceKind = tpl.source_kind,
        sourceRef  = tpl.source_ref,
        entry      = tpl.entry,

        -- ONE door. The client shows a menu at it: "Leave", and "Go to the
        -- garage" when this property has one.
        exitPoint  = tpl.exit_point,
        hasGarage  = house.garage_template_id ~= nil,

        weaponStorages = weaponStorages,
        wardrobes  = weaponStorages, -- compatibility for older clients
        stashes    = stashes,
    }
end)

--- Walk from the house into the garage. On foot, not driving.
lib.callback.register('cm-house:server:enterGarage', function(src, houseId)
    houseId = tonumber(houseId)
    local cid = GetCid(src)
    local house = Houses[houseId]
    if not house then return false, 'That property does not exist.' end
    local atDoor, doorWhy = requireExteriorDoor(src, house)
    if not atDoor then return false, doorWhy end

    local ok, why = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_ENTER)
    if not ok then return false, why end

    local g = GarageTemplates[house.garage_template_id]
    if not g then return false, 'This property has no garage.' end

    SendToGarage(src, houseId)
    LogHouse(houseId, house.family_id, cid, 'garage_enter', nil)

    -- Slot CONTENTS come from cm-house:server:garageState, which reads
    -- cm-vehicles live. Sending them here too would mean two answers to the
    -- same question, and they would drift.
    return true, {
        houseId    = houseId,
        label      = house.label,
        familyId   = house.family_id,
        familyName = (function()
            local family = house.family_id and GetFamilyDisplay(house.family_id) or nil
            return family and tostring(family.name or family.label or '') or nil
        end)(),
        isFamilyGarage = house.family_id ~= nil,
        sourceKind = g.source_kind,
        sourceRef  = g.source_ref,

        -- The same point is where you arrive AND where you press E to go back.
        entry      = g.player_entry,
        vehicleExit = g.vehicle_exit,
        vehicleExits = g.vehicle_exits,
        capacity   = g.capacity,
    }
end)

--- Leaving. The exit point is read from the record, never from the client,
--- so a tampered client cannot teleport itself anywhere it likes.
lib.callback.register('cm-house:server:leaveProperty', function(src, houseId, exitIndex)
    houseId = tonumber(houseId)
    local house = Houses[houseId]
    if not house then return nil end
    local insideHouse, insideKind = WhereIs(src)
    if tonumber(insideHouse) ~= houseId then return nil end

    -- House interiors leave through their configured interior door. Garage
    -- interiors must leave at one of the exact admin-captured exits, so a
    -- modified client cannot teleport out from anywhere in the garage.
    if insideKind == 'garage' then
        local garage = GarageTemplates[tonumber(house.garage_template_id)]
        local exits = garage and (garage.vehicle_exits or {}) or {}
        if #exits == 0 and garage and garage.vehicle_exit then exits = { garage.vehicle_exit } end
        local chosen = exits[tonumber(exitIndex) or 0]
        if not chosen then return nil end
        local useDistance = tonumber(Config.GarageTemplate and Config.GarageTemplate.exitUseDistance) or 1.35
        if not playerNear(src, chosen, useDistance + 0.75) then return nil end
    end

    SendToWorld(src)
    return house.door_coords
end)

--- House -> garage and garage -> house, on foot.
lib.callback.register('cm-house:server:houseToGarage', function(src, houseId)
    houseId = tonumber(houseId)
    local insideHouse, insideKind = WhereIs(src)
    if tonumber(insideHouse) ~= houseId or insideKind ~= 'house' then
        return false, 'You must be inside this house.'
    end
    local cid = GetCid(src)
    local ok, why = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_ENTER)
    if not ok then return false, why end

    local house = Houses[houseId]
    local g = house and GarageTemplates[house.garage_template_id]
    if not g then return false, 'This property has no garage.' end

    SendToGarage(src, houseId)
    return true, {
        houseId = houseId,
        label = house.label,
        familyId = house.family_id,
        familyName = (function()
            local family = house.family_id and GetFamilyDisplay(house.family_id) or nil
            return family and tostring(family.name or family.label or '') or nil
        end)(),
        isFamilyGarage = house.family_id ~= nil,
        sourceKind = g.source_kind,
        sourceRef = g.source_ref,
        entry = g.player_entry,
        vehicleExit = g.vehicle_exit,
        vehicleExits = g.vehicle_exits,
        capacity = g.capacity,
    }
end)

lib.callback.register('cm-house:server:garageToHouse', function(src, houseId)
    houseId = tonumber(houseId)
    local insideHouse, insideKind = WhereIs(src)
    if tonumber(insideHouse) ~= houseId or insideKind ~= 'garage' then
        return false, 'You must be inside this garage.'
    end
    local cid = GetCid(src)
    local ok, why = CanAccessProperty(cid, houseId, ACTIONS.HOUSE_ENTER)
    if not ok then return false, why end

    local house = Houses[houseId]
    local tpl = house and InteriorTemplates[house.interior_template_id]
    if not tpl then return false, 'This property has no interior.' end

    local canWeaponStorage = CanAccessProperty(cid, houseId, ACTIONS.WEAPON_STORAGE_USE)
    local canStorage = CanAccessProperty(cid, houseId, ACTIONS.STORAGE_USE)
    local weaponStorages, stashes = {}, {}
    if canWeaponStorage then
        for i, w in ipairs(tpl.weapon_storages or tpl.wardrobes or {}) do
            weaponStorages[i] = { index = i, coords = w }
        end
    end
    if canStorage then
        for i, st in ipairs(tpl.stashes or {}) do
            stashes[i] = { index = i, coords = st, label = st.label, slots = st.slots }
        end
    end

    SendToHouse(src, houseId)
    -- Arrive AT the door you walked through, not at the spawn point -- you
    -- came in from the garage, you did not teleport in from the street.
    return true, {
        houseId = houseId,
        label = house.label,
        familyId = house.family_id,
        familyName = (function()
            local family = house.family_id and GetFamilyDisplay(house.family_id) or nil
            return family and tostring(family.name or family.label or '') or nil
        end)(),
        isFamilyHouse = house.family_id ~= nil,
        sourceKind = tpl.source_kind,
        sourceRef = tpl.source_ref,
        entry = tpl.exit_point,
        exitPoint = tpl.exit_point,
        hasGarage = house.garage_template_id ~= nil,
        weaponStorages = weaponStorages,
        wardrobes = weaponStorages,
        stashes = stashes,
    }
end)

-- ------------------------------------------------------------
--  Weapon storage and general storage
--  cm-house owns authorization; cm-inventory remains the item authority.
-- ------------------------------------------------------------
RegisterNetEvent('cm-house:server:openWardrobe', function(houseId, index)
    TriggerClientEvent('cm-house:client:openWeaponStorageRequested', source, tonumber(houseId), tonumber(index))
end)

RegisterNetEvent('cm-house:server:openStash', function(houseId, index)
    local src = source
    local cid = GetCid(src)

    houseId = tonumber(houseId)
    index = tonumber(index)
    local insideHouse, insideKind = WhereIs(src)
    if tonumber(insideHouse) ~= houseId or insideKind ~= 'house' then
        Notify(src, 'You must be inside this house to use its storage.', 'error')
        return
    end

    local ok, why = CanAccessProperty(cid, houseId, ACTIONS.STORAGE_USE)
    if not ok then
        Notify(src, why, 'error')
        return
    end

    local house = Houses[houseId]
    local tpl   = InteriorTemplates[house.interior_template_id]
    local def   = tpl and tpl.stashes[index]
    if not def then
        Notify(src, 'That storage does not exist.', 'error')
        return
    end

    -- Spec 4.2: the storage identity comes from the PROPERTY, not the
    -- template. Two houses using the same layout must not share a fridge.
    LogHouse(houseId, house.family_id, cid, 'storage_open', { point = index })

    OpenPropertyStash(src, houseId, index, def)
end)
