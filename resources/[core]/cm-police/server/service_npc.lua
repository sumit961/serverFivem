-- Public Police front desk. All three services re-check character, entity,
-- routing bucket and proximity here; the decorative client NPC is never an
-- authority boundary.

local ConfiscationTokens = {}

local function serviceNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function nearServiceNpc(src)
    local location = GetPoliceServiceNpcLocation()
    local ped = GetPlayerPed(src)
    if not location or not ped or ped == 0 then return false end
    if GetPlayerRoutingBucket(src) ~= (tonumber(location.bucket) or 0) then return false end
    return #(GetEntityCoords(ped) - vector3(location.x, location.y, location.z)) <= (Config.ServiceNpc.InteractDistance or 2.5) + 1.0
end

lib.callback.register('cm-police:server:serviceNpcLocation', function()
    return GetPoliceServiceNpcLocation()
end)

lib.callback.register('cm-police:server:requestNpcService', function(src)
    if not nearServiceNpc(src) then return false, 'You must be at the Police front desk.' end
    local ok, message = exports[GetCurrentResourceName()]:CreatePoliceCall(src, 'Citizen requesting Police assistance at the front desk.')
    if ok then log(cid(src), 'front_desk_service_requested', {}) end
    return ok, ok and 'On-duty Police have been notified.' or message
end)

local function firearmInventory(src)
    if not PoliceDatabaseReady() then return nil, false, 'Police services are still starting.' end
    if GetResourceState('cm-weapons') ~= 'started' or GetResourceState('cm-inventory') ~= 'started' then
        return nil, false, 'Weapon confiscation is temporarily unavailable.'
    end
    local licensed = HasValidLicense(cid(src), 'firearms')
    if licensed then return {}, true end
    local catalogOk, catalog = pcall(function() return exports['cm-weapons']:GetAllWeapons(true) end)
    if not catalogOk or type(catalog) ~= 'table' then return nil, false, 'Weapon records are temporarily unavailable.' end
    local firearms = {}
    for _, weapon in ipairs(catalog) do
        local itemName = tostring(weapon.itemName or weapon.item_name or ''):lower()
        local group = tostring(weapon.group or weapon.group_key or ''):lower()
        if itemName ~= '' and group ~= 'melee' and group ~= 'unarmed' then
            firearms[itemName] = tostring(weapon.label or itemName)
        end
    end
    local inventoryOk, inventory = pcall(function() return exports['cm-inventory']:GetInventory(src) end)
    if not inventoryOk or type(inventory) ~= 'table' then return nil, false, 'Your inventory could not be verified.' end
    local found = {}
    for _, item in ipairs(inventory and inventory.items or {}) do
        local itemName = tostring(item.item_name or item.itemName or ''):lower()
        local quantity = math.max(0, math.floor(tonumber(item.quantity) or 0))
        if firearms[itemName] and quantity > 0 then
            local current = found[itemName]
            if not current then current = { itemName = itemName, label = firearms[itemName], quantity = 0 }; found[itemName] = current end
            current.quantity = current.quantity + quantity
        end
    end
    local list = {}
    for _, row in pairs(found) do list[#list + 1] = row end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list, false
end

lib.callback.register('cm-police:server:confiscationPreview', function(src)
    if not nearServiceNpc(src) or not rateLimit(src, 'police_confiscation_preview', 700) then return nil, 'You must be at the Police front desk.' end
    local weapons, licensed, failure = firearmInventory(src)
    if not weapons then return nil, failure end
    if licensed then return { licensed = true, weapons = {}, total = 0 } end
    local total, labels = 0, {}
    for _, weapon in ipairs(weapons) do total = total + weapon.quantity; labels[#labels + 1] = ('%s x%d'):format(weapon.label, weapon.quantity) end
    local token = ('%d:%d:%d'):format(src, os.time(), math.random(100000, 999999))
    ConfiscationTokens[src] = { token = token, expires = GetGameTimer() + 15000 }
    return { licensed = false, weapons = labels, total = total, token = token }
end)

lib.callback.register('cm-police:server:confiscateIllegalWeapons', function(src, token)
    local pending = ConfiscationTokens[src]
    ConfiscationTokens[src] = nil
    if not pending or pending.token ~= tostring(token or '') or GetGameTimer() > pending.expires then return false, 'Confiscation confirmation expired.' end
    if not nearServiceNpc(src) or not rateLimit(src, 'police_confiscation_execute', 1000) then return false, 'You must be at the Police front desk.' end
    local weapons, licensed, failure = firearmInventory(src)
    if not weapons then return false, failure end
    if licensed then return false, 'Your firearms license is active; no weapons were confiscated.' end
    if #weapons == 0 then return false, 'No unlicensed firearms were found.' end
    local characterId = cid(src)
    local operationId = BeginPoliceOperation('voluntary_weapon_confiscation', characterId, nil, 0, { weaponTypes = #weapons })
    if not operationId then return false, 'Could not start a safe confiscation operation.' end
    local removed, failed = {}, nil
    for _, weapon in ipairs(weapons) do
        local ok, reason = exports['cm-inventory']:RemoveItem(src, weapon.itemName, weapon.quantity, nil, 'police_voluntary_confiscation')
        if not ok then failed = { itemName = weapon.itemName, reason = reason }; break end
        removed[#removed + 1] = { itemName = weapon.itemName, quantity = weapon.quantity }
    end
    if failed then
        FinishPoliceOperation(operationId, 'reconciliation_required', { removed = removed, failed = failed })
        log(characterId, 'illegal_weapon_confiscation_partial', { removed = removed, failed = failed })
        return false, 'Some weapons were removed, but the operation requires administrator reconciliation.'
    end
    FinishPoliceOperation(operationId, 'completed', { removed = removed })
    log(characterId, 'illegal_weapons_confiscated', { removed = removed })
    return true, ('Confiscated %d unlicensed firearm type(s).'):format(#removed)
end)

lib.callback.register('cm-police:server:surrenderPreview', function(src)
    if not nearServiceNpc(src) or not rateLimit(src, 'police_surrender_preview', 700) then return nil, 'You must be at the Police front desk.' end
    local characterId = cid(src)
    local status = characterId and MySQL.single.await('SELECT stars, wanted FROM cm_police_criminal_status WHERE character_id = ? LIMIT 1', { characterId })
    local stars = status and math.max(0, math.min(6, math.floor(tonumber(status.stars) or 0))) or 0
    if stars < 1 or not dbBoolean(status and status.wanted) then return nil, 'You do not have an active wanted level.' end
    local rules = GetPoliceBookingRules()
    return { stars = stars, minutes = stars * rules.minutesPerStar }
end)

lib.callback.register('cm-police:server:surrenderAtNpc', function(src)
    if not nearServiceNpc(src) or not rateLimit(src, 'police_surrender_execute', 1500) then return false, 'You must be at the Police front desk.' end
    local characterId = cid(src)
    local status = characterId and MySQL.single.await('SELECT stars, wanted FROM cm_police_criminal_status WHERE character_id = ? LIMIT 1', { characterId })
    local stars = status and math.max(0, math.min(6, math.floor(tonumber(status.stars) or 0))) or 0
    if stars < 1 or not dbBoolean(status and status.wanted) then return false, 'You do not have an active wanted level.' end
    local existing = MySQL.single.await("SELECT status FROM cm_police_custody WHERE character_id = ? AND status IN ('cuffed', 'processing', 'jailed') LIMIT 1", { characterId })
    if existing then return false, 'You already have active Police custody.' end
    local rules = GetPoliceBookingRules()
    local minutes = stars * rules.minutesPerStar
    local releaseEpoch = os.time() + minutes * 60
    local bookingId = MySQL.insert.await([[INSERT INTO cm_police_bookings
        (character_id, officer_cid, reason, charges, wanted_stars, sentence_minutes, handoff_status, release_at)
        VALUES (?, NULL, 'Voluntary surrender', 'Active wanted level', ?, ?, 'processing', FROM_UNIXTIME(?))]],
        { characterId, stars, minutes, releaseEpoch })
    if not bookingId then return false, 'Could not journal the surrender safely.' end
    MySQL.insert.await([[INSERT INTO cm_police_custody (character_id, status, custody_mode, reason, charges, booking_minutes)
        VALUES (?, 'processing', 'surrender', 'Voluntary surrender', 'Active wanted level', ?)
        ON DUPLICATE KEY UPDATE status = 'processing', custody_mode = 'surrender', reason = VALUES(reason), charges = VALUES(charges), booking_minutes = VALUES(booking_minutes), updated_at = NOW()]],
        { characterId, minutes })
    local jailed, failure = exports['cm-prison']:JailSelf(src, minutes, 'Voluntary surrender', rules.handoffTimeoutMs, {
        spawns = GetPoliceJailSpawns(), release = GetPoliceJailLocation(), reason = 'Voluntary surrender',
        arrestedBy = 'Police Department',
    })
    if not jailed then
        if failure ~= 'target_disconnected' and failure ~= 'prison_unavailable' then
            MySQL.transaction.await({
                { query = "UPDATE cm_police_custody SET status = 'released', updated_at = NOW() WHERE character_id = ? AND custody_mode = 'surrender'", values = { characterId } },
                { query = "UPDATE cm_police_bookings SET handoff_status = 'failed' WHERE id = ? AND handoff_status = 'processing'", values = { bookingId } },
            })
        end
        local uncertain = failure == 'target_disconnected' or failure == 'prison_unavailable'
        return false, uncertain and 'Surrender was interrupted and will reconcile automatically.' or 'Prison did not accept the surrender.'
    end
    local finalized = MySQL.transaction.await({
        { query = "UPDATE cm_police_custody SET status = 'jailed', updated_at = NOW() WHERE character_id = ? AND custody_mode = 'surrender'", values = { characterId } },
        { query = "UPDATE cm_police_bookings SET handoff_status = 'confirmed' WHERE id = ? AND handoff_status = 'processing'", values = { bookingId } },
    })
    pcall(function() exports[Config.PlayerDataResource]:ClearWantedStars(src) end)
    log(characterId, finalized and 'wanted_surrendered' or 'surrender_reconciliation_required', { stars = stars, minutes = minutes, bookingId = bookingId })
    return true, finalized and ('Surrender accepted. Sentence: %d minutes.'):format(minutes) or 'Prison accepted surrender; Police records will reconcile automatically.'
end)

AddEventHandler('playerDropped', function() ConfiscationTokens[source] = nil end)
