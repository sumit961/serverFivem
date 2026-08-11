-- Server-authoritative suspect inventory search. Only classification labels
-- are returned; metadata, slots and internal inventory identifiers stay private.

local function searchAuthority(src, targetSrc)
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    local actorCid = src and cid(src)
    local actor = actorCid and memberFor(actorCid)
    if not actor or dbBoolean(actor.is_suspended) or not dbBoolean(actor.on_duty) or not has(actor, 'police.cuff') then
        return nil, 'You must be an on-duty officer with search authority.'
    end
    local officerPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc or -1)
    if not targetSrc or targetSrc == src or not targetPed or targetPed == 0 or not officerPed or officerPed == 0 then return nil, 'Invalid suspect.' end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then return nil, 'The suspect is in another routing instance.' end
    if #(GetEntityCoords(officerPed) - GetEntityCoords(targetPed)) > 3.0 then return nil, 'Move closer to the suspect.' end
    if Player(targetSrc).state.cmCuffed ~= true then return nil, 'The suspect must be cuffed before a search.' end
    return cid(targetSrc)
end

local function addFound(output, label, quantity)
    if #output >= 24 then return end
    output[#output + 1] = quantity > 1 and ('%s x%d'):format(label, quantity) or label
end

lib.callback.register('cm-police:server:searchPlayer', function(src, targetSrc)
    if not rateLimit(src, 'police_search_player', 1000) then return nil, 'Please wait.' end
    local targetCid, failure = searchAuthority(src, targetSrc)
    if not targetCid then return nil, failure end
    if GetResourceState('cm-inventory') ~= 'started' or GetResourceState('cm-weapons') ~= 'started' or GetResourceState('cm-items') ~= 'started' then
        return nil, 'Inventory search services are unavailable.'
    end
    local inventory = exports['cm-inventory']:GetInventory(targetSrc)
    local weapons = exports['cm-weapons']:GetAllWeapons(true) or {}
    local ammo = exports['cm-weapons']:GetAllAmmo(true) or {}
    local definitions = exports['cm-items']:GetAllItems() or {}
    if type(inventory) ~= 'table' then return nil, 'The suspect inventory could not be read.' end
    local weaponMap, ammoMap, illegalMap = {}, {}, {}
    for _, row in ipairs(weapons) do
        local name = tostring(row.itemName or row.item_name or ''):lower()
        if name ~= '' then weaponMap[name] = tostring(row.label or name) end
    end
    for _, row in ipairs(ammo) do
        local name = tostring(row.itemName or row.item_name or ''):lower()
        if name ~= '' then ammoMap[name] = tostring(row.label or name) end
    end
    for name, row in pairs(definitions) do
        if type(row) == 'table' and row.illegal == true then illegalMap[tostring(name):lower()] = tostring(row.label or name) end
    end
    local licensed = HasValidLicense(targetCid, 'firearms')
    local result = { firearmsLicensed = licensed, licensedWeapons = {}, unlicensedWeapons = {}, ammunition = {}, illegalItems = {} }
    for _, row in ipairs(inventory.items or {}) do
        local name = tostring(row.item_name or row.itemName or ''):lower()
        local quantity = math.max(0, math.floor(tonumber(row.quantity) or 0))
        if quantity > 0 then
            if weaponMap[name] then addFound(licensed and result.licensedWeapons or result.unlicensedWeapons, weaponMap[name], quantity) end
            if ammoMap[name] then addFound(result.ammunition, ammoMap[name], quantity) end
            if illegalMap[name] then addFound(result.illegalItems, illegalMap[name], quantity) end
        end
    end
    log(cid(src), 'suspect_inventory_searched', { targetCid = tostring(targetCid) })
    return result
end)
