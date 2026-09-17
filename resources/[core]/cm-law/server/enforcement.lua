-- Shared non-LSPD enforcement authority. LSPD keeps its public contracts in
-- cm-police; its compatibility adapters call the same authorization model.

local citationLocks, K9, K9Threats, K9Targets = {}, {}, {}, {}
local violations = {}
for _, row in ipairs((Config.Enforcement or {}).Violations or {}) do violations[row.id] = row end

exports('ResolveCitationViolation', function(violationId)
    local row = violations[tostring(violationId or '')]
    if not row then return nil end
    return { id = row.id, label = row.label, fine = tonumber(row.fine),
        jailMinutes = tonumber(row.jailMinutes) or 0, description = row.description }
end)

local function authorize(src, capability, permission)
    return LawAuthorizeEnforcement(tonumber(src), capability, permission)
end

local function target(src, targetSrc, distance)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc == src or not GetPlayerName(targetSrc) then return nil, 'Select a valid player.' end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then return nil, 'Target is in another routing instance.' end
    local actorPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if actorPed == 0 or targetPed == 0 or not DoesEntityExist(targetPed) then return nil, 'Target is unavailable.' end
    if #(GetEntityCoords(actorPed) - GetEntityCoords(targetPed)) > distance then return nil, 'Target is too far away.' end
    local targetCid = characterIdFor(targetSrc)
    if not targetCid then return nil, 'Target character is not loaded.' end
    return { source = targetSrc, characterId = tostring(targetCid), ped = targetPed }
end

lib.callback.register('cm-law:server:citationCatalog', function(src)
    if not authorize(src, 'citations', 'law.cite') then return {} end
    local out = {}
    for _, row in ipairs((Config.Enforcement or {}).Violations or {}) do
        out[#out + 1] = { id = row.id, label = row.label, fine = row.fine, description = row.description }
    end
    return out
end)

lib.callback.register('cm-law:server:issueCitation', function(src, targetSrc, violationId)
    local context, failure = authorize(src, 'citations', 'law.cite')
    if not context then return false, failure end
    if not rateLimit(src, 'law_citation', (Config.Enforcement or {}).CitationCooldownMs or 1500) then return false, 'Please wait.' end
    local suspect, targetFailure = target(src, targetSrc, (Config.Enforcement or {}).DirectDistance or 4.0)
    if not suspect then return false, targetFailure end
    local violation = violations[tostring(violationId or '')]
    if not violation then return false, 'Unknown citation violation.' end
    local lockKey = context.organizationId .. ':' .. suspect.characterId
    if citationLocks[lockKey] then return false, 'A citation for this citizen is already processing.' end
    citationLocks[lockKey] = true
    local removed = false
    local called = pcall(function()
        removed = exports[Config.PlayerDataResource]:RemoveMoney(suspect.source, 'bank', tonumber(violation.fine),
            'legal_citation', { organizationId = context.organizationId, violationId = violation.id }) == true
    end)
    if not called or not removed then citationLocks[lockKey] = nil; return false, 'Citizen does not have enough bank funds.' end
    local citationId = MySQL.insert.await([[INSERT INTO cm_legal_citations
        (organization_id, officer_cid, target_cid, violation_id, violation_label, amount, status)
        VALUES (?, ?, ?, ?, ?, ?, 'paid')]], {
        context.organizationId, context.characterId, suspect.characterId,
        violation.id, violation.label, tonumber(violation.fine),
    })
    if not citationId then
        pcall(function() exports[Config.PlayerDataResource]:AddMoney(suspect.source, 'bank', tonumber(violation.fine),
            'legal_citation_refund', { organizationId = context.organizationId, violationId = violation.id }) end)
        citationLocks[lockKey] = nil
        return false, 'Citation storage failed; the fine was refunded.'
    end
    citationLocks[lockKey] = nil
    logActivity(context.organizationId, context.characterId, 'citation_issued', {
        citationId = citationId, targetCid = suspect.characterId, violationId = violation.id, amount = violation.fine,
    })
    TriggerClientEvent('cm-hud:client:notify', suspect.source,
        ('You were fined $%d for %s by %s.'):format(violation.fine, violation.label, context.organizationId:upper()), 'error')
    return true, ('Issued a $%d citation for %s.'):format(violation.fine, violation.label)
end)

lib.callback.register('cm-law:server:toggleClamp', function(src, netId)
    local context, failure = authorize(src, 'clamp', 'law.clamp')
    if not context then return false, failure end
    if not rateLimit(src, 'law_clamp', 1000) then return false, 'Please wait.' end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return false, 'Select a valid vehicle.' end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityRoutingBucket(ped) ~= GetEntityRoutingBucket(vehicle) then return false, 'Vehicle is in another routing instance.' end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > ((Config.Enforcement or {}).ClampDistance or 3.0) then return false, 'Vehicle is too far away.' end
    local state, clamped = Entity(vehicle).state, Entity(vehicle).state.cmWheelClamped == true
    local persistentId = tonumber(state.cmVehicleId)
    state:set('cmWheelClamped', not clamped, true)
    state:set('cmWheelClampAuthority', not clamped and {
        organizationId = context.organizationId, officerCid = context.characterId,
        vehicleId = persistentId, timestamp = os.time(),
    } or false, true)
    logActivity(context.organizationId, context.characterId, clamped and 'vehicle_unclamped' or 'vehicle_clamped', { vehicleId = persistentId })
    return true, clamped and 'Wheel clamp removed.' or 'Wheel clamp applied.'
end)

local function removeK9(src)
    local row = K9[src]; K9[src], K9Threats[src], K9Targets[src] = nil, nil, nil
    if row and row.entity and DoesEntityExist(row.entity) then DeleteEntity(row.entity) end
end

local function liveK9(src)
    local context, failure = authorize(src, 'k9', 'law.k9')
    local row = K9[src]
    if not context then removeK9(src); return nil, nil, failure end
    if not row or not row.entity or not DoesEntityExist(row.entity) then return nil, nil, 'Deploy your K9 first.' end
    return row, context
end

local function wantedStars(targetSrc)
    local stars = 0; pcall(function() stars = tonumber(exports[Config.PlayerDataResource]:GetWantedStars(targetSrc)) or 0 end)
    return stars
end

local function validateK9Target(src, targetSrc, maxDistance)
    local row, context, failure = liveK9(src)
    if not row then return nil, nil, nil, failure end
    local suspect, targetFailure = target(src, targetSrc, maxDistance)
    if not suspect then return nil, nil, nil, targetFailure end
    return row, context, suspect
end

lib.callback.register('cm-law:server:deployK9', function(src)
    local context, failure = authorize(src, 'k9', 'law.k9')
    if not context then return false, failure end
    if not rateLimit(src, 'law_k9_deploy', 1500) then return false, 'Please wait.' end
    if K9[src] and DoesEntityExist(K9[src].entity) then return false, 'Your K9 is already deployed.', K9[src].netId end
    local ped = GetPlayerPed(src); if ped == 0 then return false, 'Character is unavailable.' end
    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local dog = CreatePed(28, GetHashKey(((Config.Enforcement or {}).K9 or {}).Model or 'a_c_shepherd'), coords.x + 1.0, coords.y + 1.0, coords.z, heading, true, true)
    if dog == 0 then return false, 'K9 entity creation failed.' end
    SetEntityRoutingBucket(dog, GetPlayerRoutingBucket(src))
    local netId = NetworkGetNetworkIdFromEntity(dog)
    K9[src] = { entity = dog, netId = netId, organizationId = context.organizationId }
    Entity(dog).state:set('cmPoliceK9Handler', src, true)
    logActivity(context.organizationId, context.characterId, 'k9_deployed', {})
    return true, 'K9 unit deployed.', netId
end)

lib.callback.register('cm-law:server:recallK9', function(src)
    local row, context, failure = liveK9(src)
    if not row then return false, failure end
    removeK9(src); logActivity(context.organizationId, context.characterId, 'k9_recalled', {})
    return true, 'K9 unit recalled.'
end)

lib.callback.register('cm-law:server:k9Track', function(src)
    local row, context, failure = liveK9(src); if not row then return false, failure end
    if not rateLimit(src, 'law_k9_track', 1000) then return false, 'Please wait.' end
    local ped, radius = GetPlayerPed(src), (((Config.Enforcement or {}).K9 or {}).TrackRadius or 150.0)
    local origin, nearest, nearestCoords, nearestDistance = GetEntityCoords(ped), nil, nil, radius
    for _, id in ipairs(GetPlayers()) do
        local candidate = tonumber(id)
        if candidate ~= src and GetPlayerRoutingBucket(candidate) == GetPlayerRoutingBucket(src) and wantedStars(candidate) > 0 then
            local targetPed = GetPlayerPed(candidate)
            local distance = targetPed ~= 0 and #(origin - GetEntityCoords(targetPed)) or radius + 1
            if distance <= nearestDistance then nearest, nearestCoords, nearestDistance = candidate, GetEntityCoords(targetPed), distance end
        end
    end
    if not nearest then return false, 'No wanted suspects detected nearby.' end
    logActivity(context.organizationId, context.characterId, 'k9_track_started', { targetCid = characterIdFor(nearest) })
    return true, 'Scent picked up.', nearest, { x = nearestCoords.x, y = nearestCoords.y, z = nearestCoords.z }
end)

lib.callback.register('cm-law:server:k9TrackUpdate', function(src, targetSrc)
    if not rateLimit(src, 'law_k9_track_update', 750) then return false end
    local _, _, suspect, failure = validateK9Target(src, targetSrc, (((Config.Enforcement or {}).K9 or {}).TrackRadius or 150.0))
    if not suspect or wantedStars(suspect.source) < 1 then return false, failure or 'The scent trail has gone cold.' end
    local coords = GetEntityCoords(suspect.ped); return true, nil, { x = coords.x, y = coords.y, z = coords.z }
end)

lib.callback.register('cm-law:server:k9CommandTarget', function(src, action, targetSrc)
    if not rateLimit(src, 'law_k9_command', 500) then return false, 'Please wait.' end
    action = tostring(action or '')
    if action ~= 'follow' and action ~= 'chase' and action ~= 'attack' then return false, 'Invalid K9 command.' end
    local k9cfg = (Config.Enforcement or {}).K9 or {}
    local _, context, suspect, failure = validateK9Target(src, targetSrc, action == 'attack' and (k9cfg.AttackDistance or 20.0) or (k9cfg.ChaseDistance or 75.0))
    if not suspect then return false, failure end
    local recentThreat = K9Threats[src] and (K9Threats[src][suspect.source] or 0) > GetGameTimer()
    if action == 'attack' and not recentThreat then return false, 'K9 attack denied: that player has not recently attacked you.' end
    if action ~= 'attack' and wantedStars(suspect.source) < 1 and not recentThreat then return false, 'K9 can only pursue a wanted suspect or your recent attacker.' end
    K9Targets[src] = action == 'attack' and suspect.source or nil
    logActivity(context.organizationId, context.characterId, 'k9_' .. action, { targetCid = suspect.characterId })
    return true, action == 'attack' and 'K9 attack authorized.' or ('K9 %s command accepted.'):format(action), suspect.source
end)

lib.callback.register('cm-law:server:k9StopAttack', function(src)
    local _, context, failure = liveK9(src); if not context then return false, failure end
    K9Targets[src] = nil; logActivity(context.organizationId, context.characterId, 'k9_attack_stopped', {})
    return true, 'K9 stopped and returned to heel.'
end)

lib.callback.register('cm-law:server:k9SearchPlayer', function(src, targetSrc)
    if not rateLimit(src, 'law_k9_search_player', 1500) then return false, 'Please wait.' end
    local _, context, suspect, failure = validateK9Target(src, targetSrc, (((Config.Enforcement or {}).K9 or {}).SearchDistance or 4.0))
    if not suspect then return false, failure end
    if wantedStars(suspect.source) < 1 and Player(suspect.source).state.cmCuffed ~= true then return false, 'The player must be wanted or restrained.' end
    local inventory; pcall(function() inventory = exports['cm-inventory']:GetInventory(suspect.source) end)
    if not inventory then return false, 'Could not inspect the player inventory.' end
    local alert = false
    for _, item in ipairs(inventory.items or {}) do
        local definition; pcall(function() definition = exports['cm-items']:GetItem(item.item_name, true) end)
        if definition and definition.illegal == true and (tonumber(item.quantity) or 0) > 0 then alert = true break end
    end
    logActivity(context.organizationId, context.characterId, 'k9_player_search', { targetCid = suspect.characterId, alert = alert })
    return true, alert and 'K9 alerted to a suspicious scent.' or 'K9 found no suspicious scent.', alert
end)

lib.callback.register('cm-law:server:k9SearchVehicle', function(src, netId)
    if not rateLimit(src, 'law_k9_search_vehicle', 1500) then return false, 'Please wait.' end
    local _, context, failure = liveK9(src); if not context then return false, failure end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return false, 'Select a valid vehicle.' end
    if GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src) then return false, 'Vehicle is in another routing instance.' end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(vehicle)) > (((Config.Enforcement or {}).K9 or {}).SearchDistance or 4.0) then return false, 'Vehicle is too far away.' end
    local vehicleId = tonumber(Entity(vehicle).state.cmVehicleId)
    if not vehicleId then return false, 'This vehicle has no persistent vehicle identity.' end
    local rows = MySQL.query.await('SELECT item_name, quantity FROM inventory_items WHERE owner_type = ? AND owner_id = ?', { 'vehicle_trunk', tostring(vehicleId) }) or {}
    local alert = false
    for _, item in ipairs(rows) do
        local definition; pcall(function() definition = exports['cm-items']:GetItem(item.item_name, true) end)
        if definition and definition.illegal == true and (tonumber(item.quantity) or 0) > 0 then alert = true break end
    end
    logActivity(context.organizationId, context.characterId, 'k9_vehicle_search', { vehicleId = vehicleId, alert = alert })
    return true, alert and 'K9 alerted to a suspicious scent.' or 'K9 found no suspicious scent.', alert
end)

AddEventHandler('weaponDamageEvent', function(sender, data)
    local victim = NetworkGetEntityFromNetworkId(type(data) == 'table' and tonumber(data.hitGlobalId) or 0)
    if victim == 0 then return end
    for handlerSrc in pairs(K9) do
        if tonumber(sender) ~= handlerSrc and victim == GetPlayerPed(handlerSrc)
            and GetPlayerRoutingBucket(sender) == GetPlayerRoutingBucket(handlerSrc) then
            K9Threats[handlerSrc] = K9Threats[handlerSrc] or {}
            K9Threats[handlerSrc][tonumber(sender)] = GetGameTimer() + ((((Config.Enforcement or {}).K9 or {}).ThreatMemoryMs) or 120000)
        end
    end
end)

AddEventHandler('playerDropped', function() removeK9(source) end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then for src in pairs(K9) do removeK9(src) end end
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_citations (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, organization_id VARCHAR(32) NOT NULL,
        officer_cid VARCHAR(64) NOT NULL, target_cid VARCHAR(64) NOT NULL,
        violation_id VARCHAR(64) NOT NULL, violation_label VARCHAR(120) NOT NULL,
        amount BIGINT NOT NULL, status VARCHAR(24) NOT NULL DEFAULT 'paid',
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, paid_at TIMESTAMP NULL,
        voided_at TIMESTAMP NULL, PRIMARY KEY (id),
        KEY idx_cm_legal_citation_target (target_cid, created_at),
        KEY idx_cm_legal_citation_org (organization_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end)

CreateThread(function()
    while true do
        Wait(5000)
        for src, row in pairs(K9) do
            local context = GetPlayerName(src) and authorize(src, 'k9', 'law.k9')
            if not context or not DoesEntityExist(row.entity) then removeK9(src)
            elseif GetEntityRoutingBucket(row.entity) ~= GetPlayerRoutingBucket(src) then SetEntityRoutingBucket(row.entity, GetPlayerRoutingBucket(src)) end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        for handlerSrc, targetSrc in pairs(K9Targets) do
            local k9cfg = (Config.Enforcement or {}).K9 or {}
            local _, _, _, failure = validateK9Target(handlerSrc, targetSrc, k9cfg.AttackDistance or 20.0)
            local expires = K9Threats[handlerSrc] and K9Threats[handlerSrc][targetSrc] or 0
            if failure or expires <= GetGameTimer() then
                K9Targets[handlerSrc] = nil
                TriggerClientEvent('cm-law:client:k9ForceStop', handlerSrc)
            end
        end
    end
end)
