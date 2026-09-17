-- ============================================================
-- cm-family | family raid event
-- A raid is an in-memory, server-authoritative two-family match. The public
-- house door is the join circle; participants are isolated in a private bucket.
-- ============================================================

local B = CMFamilyBridge
local ActiveRaid = nil
local raidSequence = 0

local function raidConfig(key, fallback)
    local value = Config.Raid and Config.Raid[key]
    return value ~= nil and value or fallback
end

local function familyName(familyId)
    local family = GetFamilyById(tonumber(familyId))
    return family and tostring(family.name or 'Family') or 'Family'
end

local function memberContext(src)
    local cid = B.GetCid(src)
    if not cid then return nil, 'character_unavailable' end
    local rank, family = GetRankForCid(cid)
    if not rank or not family then return nil, 'not_in_family' end
    return { src = tonumber(src), cid = tostring(cid), rank = rank, family = family }
end

local function canStart(context)
    if not context then return false end
    local rank = context.rank
    return rank.is_founder == true or tonumber(rank.is_founder) == 1
        or RankHasPermission(rank, 'family.raid_start')
        or RankHasPermission(rank, 'family.manage_vehicles')
end

local function familyCounts(raid)
    local counts = {}
    for familyId in pairs(raid.families) do
        counts[tostring(familyId)] = { familyId = tonumber(familyId), name = familyName(familyId), alive = 0, total = 0 }
    end
    for _, player in pairs(raid.players) do
        local key = tostring(player.familyId)
        counts[key] = counts[key] or { familyId = player.familyId, name = familyName(player.familyId), alive = 0, total = 0 }
        counts[key].total = counts[key].total + 1
        if player.alive == true then counts[key].alive = counts[key].alive + 1 end
    end
    local out = {}
    for _, row in pairs(counts) do out[#out + 1] = row end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out
end

local function raidPayload(raid)
    local counts = familyCounts(raid)
    return {
        raidId = raid.id,
        houseId = raid.houseId,
        center = raid.center,
        radius = raid.radius,
        phase = raid.phase,
        startedAt = raid.startedAt,
        startsAt = raid.startsAt,
        endsAt = raid.endsAt,
        families = counts,
    }
end

local function isRaidEligibleViewer(src, raid)
    if not raid then return false end
    local sourceId = tonumber(src)
    if raid.players[sourceId] then return true end
    local context = memberContext(sourceId)
    local familyId = context and context.family and tonumber(context.family.id)
    return familyId ~= nil and (
        familyId == tonumber(raid.attackerFamilyId)
        or familyId == tonumber(raid.targetFamilyId))
end

local function broadcastRaid(raid)
    if not raid then return end
    local payload = raidPayload(raid)
    for _, playerSource in ipairs(GetPlayers()) do
        if isRaidEligibleViewer(playerSource, raid) then
            TriggerClientEvent('cm-family:client:raidUpdate', tonumber(playerSource), payload)
        end
    end
end

local function isNearRaidCircle(src, raid, padding)
    if not raid or not raid.center then return false end
    local ped = GetPlayerPed(tonumber(src) or -1)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    local dx = (tonumber(coords.x) or 0.0) - (tonumber(raid.center.x) or 0.0)
    local dy = (tonumber(coords.y) or 0.0) - (tonumber(raid.center.y) or 0.0)
    local dz = (tonumber(coords.z) or 0.0) - (tonumber(raid.center.z) or 0.0)
    local radius = math.max(0.0, (tonumber(raid.radius) or 4.0) + (tonumber(padding) or 0.0))
    return (dx * dx + dy * dy + dz * dz) <= (radius * radius)
end

local function isAtRaidJoinEdge(src, raid)
    if not raid or not raid.center then return false end
    local ped = GetPlayerPed(tonumber(src) or -1)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    local dx = (tonumber(coords.x) or 0.0) - (tonumber(raid.center.x) or 0.0)
    local dy = (tonumber(coords.y) or 0.0) - (tonumber(raid.center.y) or 0.0)
    local distance = math.sqrt(dx * dx + dy * dy)
    local radius = tonumber(raid.radius) or 4.0
    local band = tonumber(raidConfig('joinEdgeBand', 3.0)) or 3.0
    return distance >= math.max(0.0, radius - band) and distance <= radius + band
end

local function playerInVehicle(src)
    local ped = GetPlayerPed(tonumber(src) or -1)
    if not ped or ped == 0 then return false end
    local ok, vehicle = pcall(GetVehiclePedIsIn, ped, false)
    return ok and tonumber(vehicle or 0) ~= 0
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-hud:client:notify', tonumber(src), tostring(message), kind or 'inform')
end

local function awardFamily(familyId, raidId)
    local amount = math.floor(tonumber(raidConfig('reward', 50000)) or 50000)
    local maxBalance = tonumber(Config.Bank and Config.Bank.maxBalance) or 2000000000
    local affected = MySQL.update.await(
        'UPDATE cm_families SET bank_balance = LEAST(bank_balance + ?, ?) WHERE id = ?',
        { amount, maxBalance, tonumber(familyId) })
    if not affected or tonumber(affected) < 1 then return false, 'family_bank_update_failed' end

    local balance = tonumber(MySQL.scalar.await(
        'SELECT bank_balance FROM cm_families WHERE id = ?', { tonumber(familyId) })) or 0
    MySQL.insert.await([[INSERT INTO cm_family_bank_log
        (family_id, character_id, direction, amount, balance_after, reason)
        VALUES (?, NULL, 'deposit', ?, ?, ?)]],
        { tonumber(familyId), amount, balance, ('family_raid_win:%s'):format(tostring(raidId)) })
    local family = GetFamilyById(familyId)
    if family then family.bank_balance = balance end
    LogFamily(familyId, nil, 'raid_reward', { raidId = raidId, amount = amount, balance = balance })
    return true, balance
end

local function restorePlayer(src, raid, result)
    if not src or not GetPlayerName(src) then return end
    SetPlayerRoutingBucket(src, 0)
    TriggerClientEvent('cm-family:client:raidFinished', src, result)
end

local function finishRaid(raid, winnerFamilyId, reason)
    if not raid or raid.finished then return end
    raid.finished = true
    raid.phase = 'finished'
    local rewardOk, balance = false, nil
    if winnerFamilyId then rewardOk, balance = awardFamily(winnerFamilyId, raid.id) end

    local result = {
        raidId = raid.id,
        winnerFamilyId = winnerFamilyId and tonumber(winnerFamilyId) or nil,
        winnerName = winnerFamilyId and familyName(winnerFamilyId) or nil,
        reward = rewardOk and tonumber(raidConfig('reward', 50000)) or 0,
        balance = rewardOk and balance or nil,
        reason = reason or 'raid_complete',
    }
    TriggerClientEvent('cm-family:client:raidEnded', -1, result)
    for src in pairs(raid.players) do restorePlayer(src, raid, result) end
    ActiveRaid = nil
end

local function evaluateRaid(raid)
    if not raid or raid.finished then return end
    -- Eliminations never decide a winner early. The clock must expire first;
    -- after that, the family still holding the circle wins. If both families
    -- are still holding it, keep the raid in overtime until one leaves/dies.
    if not raid.endsAt or os.time() < raid.endsAt then return end

    local holdingFamilies = {}
    for _, player in pairs(raid.players) do
        if player.alive == true and isNearRaidCircle(player.src, raid) then
            holdingFamilies[player.familyId] = true
        end
    end
    local remaining = {}
    for familyId in pairs(holdingFamilies) do remaining[#remaining + 1] = familyId end
    if #remaining == 1 then
        finishRaid(raid, remaining[1], 'time_expired_circle_holder')
    elseif #remaining == 0 then
        -- No one is holding the circle at the deadline: the attacking family
        -- receives the result by default, as the raid owner/initiator.
        finishRaid(raid, raid.attackerFamilyId, 'time_expired_no_circle_holder')
    elseif not raid.overtime then
        raid.overtime = true
        raid.phase = 'overtime'
        broadcastRaid(raid)
        for src, player in pairs(raid.players) do
            if player.alive == true then
                notify(src, 'Time expired. Both families still hold the circle; the raid continues until one side leaves or is eliminated.', 'warning')
            end
        end
    end
end

local function eliminate(src, reason)
    if not ActiveRaid then return end
    local player = ActiveRaid.players[tonumber(src)]
    if not player or player.alive ~= true then return end
    player.alive = false
    player.eliminatedAt = os.time()
    player.eliminationReason = reason or 'eliminated'
    SetPlayerRoutingBucket(tonumber(src), 0)
    TriggerClientEvent('cm-family:client:raidEliminated', tonumber(src), { reason = player.eliminationReason })
    broadcastRaid(ActiveRaid)
    evaluateRaid(ActiveRaid)
end

local function joinRaid(src, raid, skipProximity)
    local context, why = memberContext(src)
    if not context then return false, why end
    if playerInVehicle(src) then
        return false, 'Leave your vehicle before joining the family raid.'
    end
    if not skipProximity and not isAtRaidJoinEdge(src, raid) then
        return false, 'Join from the edge of the raid circle, not the centre.'
    end
    local familyId = tonumber(context.family.id)
    if raid.attackerFamilyId and familyId ~= tonumber(raid.attackerFamilyId)
       and familyId ~= tonumber(raid.targetFamilyId) then
        return false, 'Only the two families in this raid may join.'
    end
    local existing = raid.families[familyId]
    if raid.phase == 'finished' then return false, 'This raid has ended.' end
    if raid.phase == 'active' and not existing then
        return false, 'The raid already has its two families.'
    end
    if not existing then
        local familyCount = 0
        for _ in pairs(raid.families) do familyCount = familyCount + 1 end
        if familyCount >= tonumber(raidConfig('maxFamilies', 2)) then
            return false, 'This raid already has its two families.'
        end
        if raid.phase ~= 'forming' then return false, 'The raid has already started.' end
        raid.families[familyId] = { familyId = familyId, name = familyName(familyId) }
        raid.opponentFamilyId = familyId
        raid.phase = 'countdown'
        raid.startsAt = os.time() + math.max(3, tonumber(raidConfig('countdownSeconds', 10)) or 10)
    end
    if raid.players[tonumber(src)] then
        return false, 'You already joined this raid. You cannot join twice.'
    end

    raid.players[tonumber(src)] = {
        src = tonumber(src), cid = context.cid, familyId = familyId, alive = true,
        outsideSince = nil,
    }
    SetPlayerRoutingBucket(tonumber(src), tonumber(raid.bucket))
    TriggerClientEvent('cm-family:client:raidJoined', tonumber(src), raidPayload(raid))
    notify(src, raid.phase == 'countdown' and 'Raid locked. Prepare for the countdown.' or 'You joined the family raid.', 'success')
    broadcastRaid(raid)
    return true, raidPayload(raid)
end

function GetFamilyRaidDoorState(characterId, familyId, houseId)
    if not raidConfig('enabled', true) then return { enabled = false } end
    local rank, family = GetRankForCid(characterId)
    local sameFamily = family and tonumber(family.id) == tonumber(familyId)
    local ownLinkedHouse = family and houseId and family.house_id
        and tonumber(family.house_id) == tonumber(houseId)
    local isMember = sameFamily or ownLinkedHouse
    local raidFamilyMember = ActiveRaid and family and ActiveRaid.families[tonumber(family.id)] ~= nil
    local raidAllowedFamily = ActiveRaid and family and (
        tonumber(family.id) == tonumber(ActiveRaid.attackerFamilyId)
        or tonumber(family.id) == tonumber(ActiveRaid.targetFamilyId))
    local canInitiate = family ~= nil and not isMember and canStart({ rank = rank })
    local state = {
        enabled = true,
        active = ActiveRaid ~= nil,
        inFamily = family ~= nil,
        isMember = isMember == true,
        -- A raid is launched by an eligible member of the attacking family
        -- at the opposing family house.  The target family must not be the
        -- initiating family, but its members can still join to defend.
        canStart = (not ActiveRaid) and canInitiate or false,
        canJoin = ActiveRaid ~= nil and raidAllowedFamily == true
            and (ActiveRaid.phase == 'forming' or raidFamilyMember),
        raidId = ActiveRaid and ActiveRaid.id or nil,
    }
    return state
end
exports('GetFamilyRaidDoorState', GetFamilyRaidDoorState)
exports('CanStartFamilyRaid', function(characterId, familyId)
    local rank, family = GetRankForCid(characterId)
    return family and tonumber(family.id) == tonumber(familyId) and canStart({ rank = rank }) or false
end)

function StartFamilyRaid(src, houseId, center, houseFamilyId)
    if not raidConfig('enabled', true) then return false, 'Family raids are disabled.' end
    local context, why = memberContext(src)
    if not context then return false, why end
    local familyId = tonumber(context.family.id)
    if ActiveRaid then
        local dx = (tonumber(center and center.x) or 0.0) - (tonumber(ActiveRaid.center.x) or 0.0)
        local dy = (tonumber(center and center.y) or 0.0) - (tonumber(ActiveRaid.center.y) or 0.0)
        local dz = (tonumber(center and center.z) or 0.0) - (tonumber(ActiveRaid.center.z) or 0.0)
        if (dx * dx + dy * dy + dz * dz) > ((ActiveRaid.radius + 8.0) ^ 2) then
            return false, 'Stand inside the active raid circle to join.'
        end
        return joinRaid(src, ActiveRaid)
    end
    if tonumber(context.family.id) == tonumber(houseFamilyId)
        or (context.family.house_id and tonumber(context.family.house_id) == tonumber(houseId)) then
        return false, 'You cannot raid your own family house.'
    end
    local targetFamilyId = tonumber(houseFamilyId)
    if not targetFamilyId then
        return false, 'This house is not assigned to a family.'
    end
    if not canStart(context) then return false, 'Your rank cannot start a family raid.' end
    raidSequence = raidSequence + 1
    local now = os.time()
    ActiveRaid = {
        id = ('raid-%s-%s'):format(now, raidSequence),
        houseId = tonumber(houseId),
        center = { x = tonumber(center and center.x) or 0.0, y = tonumber(center and center.y) or 0.0, z = tonumber(center and center.z) or 0.0 },
        radius = tonumber(raidConfig('arenaRadius', raidConfig('joinRadius', 4.0))) or 4.0,
        bucket = (tonumber(raidConfig('bucketBase', 700000)) or 700000) + raidSequence,
        phase = 'forming',
        startedAt = now,
        startsAt = nil,
        endsAt = now + (tonumber(raidConfig('durationSeconds', 900)) or 900),
        families = { [familyId] = { familyId = familyId, name = familyName(familyId) } },
        players = {},
        attackerFamilyId = familyId,
        targetFamilyId = targetFamilyId,
        overtime = false,
        nearbyNoticeAt = {},
    }
    broadcastRaid(ActiveRaid)
    notify(src, 'Family raid circle created. Your opponent must enter the circle.', 'success')
    return joinRaid(src, ActiveRaid, true)
end
exports('StartFamilyRaid', StartFamilyRaid)

lib.callback.register('cm-family:server:joinRaid', function(src, raidId)
    if not ActiveRaid or tostring(ActiveRaid.id) ~= tostring(raidId) then return false, 'That raid is no longer active.' end
    return joinRaid(src, ActiveRaid)
end)

-- Client fallback for event loss/resource reloads. This is read-only and
-- returns the same sanitized payload broadcast by raidCircle/raidUpdate.
lib.callback.register('cm-family:server:getActiveRaid', function(src)
    return ActiveRaid and isRaidEligibleViewer(src, ActiveRaid) and raidPayload(ActiveRaid) or false
end)

lib.callback.register('cm-family:server:leaveRaid', function(src)
    if not ActiveRaid or not ActiveRaid.players[tonumber(src)] then return false, 'You are not in a raid.' end
    eliminate(src, 'left_raid')
    return true
end)

CreateThread(function()
    while true do
        Wait(500)
        local raid = ActiveRaid
        if raid and not raid.finished then
            local now = os.time()
            if raid.phase == 'countdown' and raid.startsAt and now >= raid.startsAt then
                raid.phase = 'active'
                raid.startedAt = now
                raid.endsAt = now + (tonumber(raidConfig('durationSeconds', 900)) or 900)
                broadcastRaid(raid)
                for src in pairs(raid.players) do notify(src, 'Raid started. Last family standing wins.', 'inform') end
            end
            for src, player in pairs(raid.players) do
                if player.alive == true then
                    local ped = GetPlayerPed(src)
                    if not GetPlayerName(src) or GetPlayerRoutingBucket(src) ~= raid.bucket then
                        eliminate(src, 'left_raid')
                    elseif playerInVehicle(src) then
                        eliminate(src, 'vehicle_in_raid')
                    elseif raid.phase ~= 'finished' and not isNearRaidCircle(src, raid) then
                        local grace = math.max(1, tonumber(raidConfig('boundaryGraceSeconds', 5)) or 5)
                        if not player.outsideSince then
                            player.outsideSince = now
                            TriggerClientEvent('cm-family:client:raidBoundaryWarning', src, {
                                seconds = grace,
                                deadline = now + grace,
                            })
                        elseif now - player.outsideSince >= grace then
                            eliminate(src, 'left_circle')
                        end
                    else
                        if player.outsideSince then
                            player.outsideSince = nil
                            TriggerClientEvent('cm-family:client:raidBoundaryReturned', src)
                        end
                        if ped and ped ~= 0 and GetEntityHealth(ped) <= 0 then eliminate(src, 'eliminated') end
                    end
                end
            end
            -- Players outside the two participating families cannot see the
            -- circle, but should receive a nearby warning when they enter its
            -- public-world range. Rate-limit it so it is not spammed.
            raid.nearbyNoticeAt = raid.nearbyNoticeAt or {}
            for _, viewerSource in ipairs(GetPlayers()) do
                local viewer = tonumber(viewerSource)
                if viewer and GetPlayerRoutingBucket(viewer) == 0
                   and not isRaidEligibleViewer(viewer, raid)
                   and isNearRaidCircle(viewer, raid) then
                    local lastNotice = tonumber(raid.nearbyNoticeAt[viewer]) or 0
                    if now - lastNotice >= 15 then
                        raid.nearbyNoticeAt[viewer] = now
                        notify(viewer, 'A family raid is taking place nearby.', 'warning')
                    end
                end
            end
            evaluateRaid(raid)
        end
    end
end)

AddEventHandler('playerDropped', function()
    if ActiveRaid and ActiveRaid.players[tonumber(source)] then eliminate(source, 'disconnected') end
end)

AddEventHandler('playerJoining', function()
    if ActiveRaid and isRaidEligibleViewer(source, ActiveRaid) then
        TriggerClientEvent('cm-family:client:raidCircle', source, raidPayload(ActiveRaid))
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not ActiveRaid then return end
    for src in pairs(ActiveRaid.players) do if GetPlayerName(src) then SetPlayerRoutingBucket(src, 0) end end
end)
