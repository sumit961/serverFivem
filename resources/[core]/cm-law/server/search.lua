-- Server-authoritative suspect search and evidence confiscation.

local function authority(src, targetSrc)
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    local member, actorCid = activeMemberForSource(src)
    if not member or member.suspended or not member.onDuty
        or not (member.isLeader or member.permissions['law.search'] == true) then
        return nil, nil, nil, 'You must be on duty with search authority.'
    end
    local actorPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc or -1)
    if not targetSrc or targetSrc == src or actorPed == 0 or targetPed == 0 then return nil, nil, nil, 'Invalid suspect.' end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then return nil, nil, nil, 'The suspect is in another routing instance.' end
    if #(GetEntityCoords(actorPed) - GetEntityCoords(targetPed)) > 3.0 then return nil, nil, nil, 'Move closer to the suspect.' end
    if Player(targetSrc).state.cmCuffed ~= true then return nil, nil, nil, 'The suspect must be cuffed first.' end
    local targetCid = characterIdFor(targetSrc)
    if not targetCid then return nil, nil, nil, 'Suspect character unavailable.' end
    return member, actorCid, targetCid
end

local function definitions()
    local weaponMap, ammoMap, illegalMap = {}, {}, {}
    for _, row in ipairs(exports['cm-weapons']:GetAllWeapons(true) or {}) do
        local name = tostring(row.itemName or row.item_name or ''):lower()
        if name ~= '' then weaponMap[name] = tostring(row.label or name) end
    end
    for _, row in ipairs(exports['cm-weapons']:GetAllAmmo(true) or {}) do
        local name = tostring(row.itemName or row.item_name or ''):lower()
        if name ~= '' then ammoMap[name] = tostring(row.label or name) end
    end
    for name, row in pairs(exports['cm-items']:GetAllItems() or {}) do
        if type(row) == 'table' and row.illegal == true then illegalMap[tostring(name):lower()] = tostring(row.label or name) end
    end
    return weaponMap, ammoMap, illegalMap
end

local function issueFor(issueMap, metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local number = tostring(metadata.issueLicenseNumber or metadata.licenseNumber or '')
    if number == '' then return false, nil end
    local row = issueMap[number]
    return row and row.status == 'issued', row and { number = number, issuer = row.organization_id } or nil
end

local function add(list, label, quantity, license)
    if #list >= 32 then return end
    local suffix = license and (' · Licence %s (%s)'):format(license.number, tostring(license.issuer):upper()) or ''
    list[#list + 1] = ('%s%s%s'):format(label, quantity > 1 and (' x' .. quantity) or '', suffix)
end

local function search(src, targetSrc)
    local member, actorCid, targetCid, failure = authority(src, targetSrc)
    if not member then return nil, failure end
    if GetResourceState('cm-inventory') ~= 'started' or GetResourceState('cm-weapons') ~= 'started'
        or GetResourceState('cm-items') ~= 'started' then return nil, 'Search services are unavailable.' end
    local inventory = exports['cm-inventory']:GetInventory(targetSrc)
    if type(inventory) ~= 'table' then return nil, 'Suspect inventory could not be read.' end
    local personalLicensed, personalNumber = false, nil
    if GetResourceState('cm-police') == 'started' then
        pcall(function()
            personalLicensed = exports['cm-police']:HasValidLicense(targetSrc, 'firearms') == true
            personalNumber = exports['cm-police']:GetLicenseNumber(targetSrc, 'firearms')
        end)
    end
    local weaponMap, ammoMap, illegalMap = definitions()
    local issueMap = {}
    for _, issue in ipairs(MySQL.query.await([[SELECT license_number,organization_id,status
        FROM cm_legal_armory_issues WHERE character_id=?]], { targetCid }) or {}) do
        issueMap[tostring(issue.license_number)] = issue
    end
    local result = { firearmsLicensed = personalLicensed, firearmsLicenseNumber = personalNumber,
        licensedWeapons = {}, unlicensedWeapons = {}, licensedAmmunition = {}, unlicensedAmmunition = {},
        illegalItems = {}, confiscatable = {} }
    for _, row in ipairs(inventory.items or {}) do
        local name, quantity = tostring(row.item_name or row.name or ''):lower(), math.max(0, math.floor(tonumber(row.quantity) or 0))
        if name ~= '' and quantity > 0 then
            local issued, issue = issueFor(issueMap, row.metadata)
            if weaponMap[name] then
                add((personalLicensed or issued) and result.licensedWeapons or result.unlicensedWeapons, weaponMap[name], quantity, issue)
                if not personalLicensed and not issued then result.confiscatable[#result.confiscatable + 1] = { slot = row.slot, reason = 'unlicensed_weapon' } end
            elseif ammoMap[name] then
                add((personalLicensed or issued) and result.licensedAmmunition or result.unlicensedAmmunition, ammoMap[name], quantity, issue)
                if not personalLicensed and not issued then result.confiscatable[#result.confiscatable + 1] = { slot = row.slot, reason = 'unlicensed_ammunition' } end
            end
            if illegalMap[name] then
                add(result.illegalItems, illegalMap[name], quantity)
                result.confiscatable[#result.confiscatable + 1] = { slot = row.slot, reason = 'illegal_item' }
            end
        end
    end
    -- Slots are needed only by the subsequent server callback and never shown.
    logActivity(member.organizationId, actorCid, 'suspect_inventory_searched', { targetCid = targetCid })
    return result
end

local function publicResult(result)
    if type(result) ~= 'table' then return result end
    local copy = {}
    for key, value in pairs(result) do if key ~= 'confiscatable' then copy[key] = value end end
    copy.confiscatableCount = #(result.confiscatable or {})
    return copy
end

lib.callback.register('cm-law:server:searchPlayer', function(src, targetSrc)
    if not rateLimit(src, 'law_search_player', 900) then return nil, 'Please wait.' end
    local result, failure = search(src, tonumber(targetSrc))
    return publicResult(result), failure
end)

lib.callback.register('cm-law:server:confiscatePlayer', function(src, targetSrc)
    if not rateLimit(src, 'law_confiscate_player', 1200) then return { ok = false, error = 'Please wait.' } end
    local member, actorCid, targetCid, failure = authority(src, targetSrc)
    if not member then return { ok = false, error = failure } end
    local result, searchFailure = search(src, tonumber(targetSrc))
    if not result then return { ok = false, error = searchFailure } end
    local unique, moved, failed = {}, {}, {}
    for _, entry in ipairs(result.confiscatable or {}) do
        local slot = tostring(entry.slot or '')
        if slot ~= '' and not unique[slot] then
            unique[slot] = true
            local ok, transfer = exports['cm-inventory']:TransferItemToContainer(tonumber(targetSrc), slot,
                'legal_org_evidence', member.organizationId, member.organizationId .. '-evidence-', 100,
                ('cm_law_confiscation:%s:%s'):format(actorCid, targetCid))
            if ok then
                moved[#moved + 1] = { itemName = transfer.itemName, quantity = transfer.quantity,
                    licenseNumber = transfer.metadata and (transfer.metadata.issueLicenseNumber or transfer.metadata.licenseNumber) }
                if transfer.metadata and transfer.metadata.issueId then
                    MySQL.update.await("UPDATE cm_legal_armory_issues SET status='confiscated' WHERE id=? AND character_id=?",
                        { tonumber(transfer.metadata.issueId), targetCid })
                end
            else failed[#failed + 1] = { slot = slot, reason = tostring(transfer) } end
        end
    end
    logActivity(member.organizationId, actorCid, 'suspect_items_confiscated', {
        targetCid = targetCid, moved = moved, failedCount = #failed,
    })
    local refreshed = search(src, tonumber(targetSrc))
    return { ok = #moved > 0, message = #moved > 0 and ('Confiscated %d evidence stack(s).'):format(#moved) or nil,
        error = #moved == 0 and (#failed > 0 and failed[1].reason or 'No confiscatable items were found.') or nil,
        result = publicResult(refreshed), moved = moved, failed = failed }
end)
