-- ============================================================
-- cm-family | sv_raid.lua
-- Family Raid Event (Migrated to Family Event Engine v1.9.0)
-- Combat, circle boundary, eliminations, and winner resolution,
-- backed by the authoritative Event Engine (sv_events.lua).
-- ============================================================

local B = CMFamilyBridge
local ActiveRaids = {}          -- [raidId/eventUid] = raid
local ActiveRaidsByHouse = {}   -- [houseId] = raid
local ActiveRaidsByFamily = {}  -- [familyId] = raid
local PlayerRaid = {}           -- [playerSource] = raidId

local function GetRaidById(raidId)
    if not raidId then return nil end
    return ActiveRaids[tostring(raidId)]
end

local function GetRaidForHouse(houseId)
    local hid = tonumber(houseId)
    return hid and ActiveRaidsByHouse[hid] or nil
end

local function GetRaidForFamily(familyId)
    local fid = tonumber(familyId)
    return fid and ActiveRaidsByFamily[fid] or nil
end

local function GetRaidForPlayer(src)
    local sourceId = tonumber(src)
    if not sourceId then return nil end
    local raidId = PlayerRaid[sourceId]
    if raidId then
        local raid = ActiveRaids[tostring(raidId)]
        if raid then return raid end
        PlayerRaid[sourceId] = nil
    end
    for _, raid in pairs(ActiveRaids) do
        if raid.players and raid.players[sourceId] then
            PlayerRaid[sourceId] = raid.id
            return raid
        end
    end
    return nil
end

local function raidConfig(key, fallback)
    local def = GetEventDefinition and GetEventDefinition('family_raid')
    if def then
        if key == 'enabled' then return true end
        if key == 'durationSeconds' then return def.durationSeconds or fallback end
        if key == 'countdownSeconds' then return def.countdownSeconds or fallback end
        if key == 'reward' then return (def.rewards and def.rewards.treasury) or fallback end
        if def.rules and def.rules[key] ~= nil then return def.rules[key] end
    end
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
        or RankHasPermission(rank, 'family.start_events')
        or RankHasPermission(rank, 'family.raid_start')
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
        eventUid = raid.eventUid,
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

local function restorePlayer(src, raid, result)
    if not src then return end
    PlayerRaid[tonumber(src)] = nil
    if not GetPlayerName(src) then return end
    SetPlayerRoutingBucket(src, 0)
    TriggerClientEvent('cm-family:client:raidFinished', src, result)
end

local function finishRaid(raid, winnerFamilyId, reason)
    if not raid or raid.finished then return end
    raid.finished = true
    raid.phase = 'finished'

    local completeRes = nil
    if type(CompleteFamilyEvent) == 'function' then
        local okComp, res = CompleteFamilyEvent(raid.eventUid, {
            winnerFamilyId = winnerFamilyId,
            reason = reason or 'raid_complete',
            scores = familyCounts(raid),
        })
        if okComp then completeRes = res end
    end

    local actualTreasury = 0
    if completeRes and completeRes.actualDelivered and completeRes.actualDelivered.treasuryCredited then
        actualTreasury = tonumber(completeRes.actualDelivered.treasuryCredited) or 0
    elseif completeRes and completeRes.rewardOk then
        actualTreasury = tonumber(raidConfig('reward', 50000)) or 0
    end

    local balance = nil
    if winnerFamilyId then
        balance = tonumber(MySQL.scalar.await(
            'SELECT bank_balance FROM cm_families WHERE id = ?', { tonumber(winnerFamilyId) })) or 0
        local fam = GetFamilyById(winnerFamilyId)
        if fam then fam.bank_balance = balance end
    end

    local result = {
        raidId = raid.id,
        eventUid = raid.eventUid,
        winnerFamilyId = winnerFamilyId and tonumber(winnerFamilyId) or nil,
        winnerName = winnerFamilyId and familyName(winnerFamilyId) or nil,
        reward = actualTreasury,
        balance = balance,
        reason = reason or 'raid_complete',
    }

    TriggerClientEvent('cm-family:client:raidEnded', -1, result)
    for src in pairs(raid.players) do restorePlayer(src, raid, result) end

    ActiveRaids[tostring(raid.id)] = nil
    if raid.eventUid then ActiveRaids[tostring(raid.eventUid)] = nil end
    if raid.houseId then ActiveRaidsByHouse[tonumber(raid.houseId)] = nil end
    if raid.attackerFamilyId then ActiveRaidsByFamily[tonumber(raid.attackerFamilyId)] = nil end
    if raid.targetFamilyId then ActiveRaidsByFamily[tonumber(raid.targetFamilyId)] = nil end
end

local function evaluateRaid(raid)
    if not raid or raid.finished then return end
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
        finishRaid(raid, raid.attackerFamilyId, 'time_expired_no_circle_holder')
    elseif not raid.overtime then
        raid.overtime = true
        raid.phase = 'overtime'
        if type(TransitionEventState) == 'function' then
            TransitionEventState(raid.eventUid, 'overtime')
        end
        broadcastRaid(raid)
        for src, player in pairs(raid.players) do
            if player.alive == true then
                notify(src, 'Time expired. Both families still hold the circle; the raid continues until one side leaves or is eliminated.', 'warning')
            end
        end
    end
end

local function eliminate(src, reason)
    local sourceId = tonumber(src)
    local raid = GetRaidForPlayer(sourceId)
    if not raid then return end
    local player = raid.players[sourceId]
    if not player or player.alive ~= true then return end
    player.alive = false
    player.eliminatedAt = os.time()
    player.eliminationReason = reason or 'eliminated'
    PlayerRaid[sourceId] = nil

    if type(UpdateFamilyEventParticipantStatus) == 'function' and player.cid then
        UpdateFamilyEventParticipantStatus(raid.eventUid, player.cid, 'eliminated', {
            eliminationReason = player.eliminationReason,
            eliminatedAt = player.eliminatedAt,
        })
    elseif type(LeaveFamilyEvent) == 'function' and player.cid then
        LeaveFamilyEvent(raid.eventUid, player.cid, player.eliminationReason)
    end
    SetPlayerRoutingBucket(sourceId, 0)

    TriggerClientEvent('cm-family:client:raidEliminated', sourceId, { reason = player.eliminationReason })
    broadcastRaid(raid)
    evaluateRaid(raid)
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

        if type(TransitionEventState) == 'function' then
            TransitionEventState(raid.eventUid, 'countdown')
        end
    end
    if raid.players[tonumber(src)] then
        return false, 'You already joined this raid. You cannot join twice.'
    end

    -- Register with Event Engine
    if type(JoinFamilyEvent) == 'function' then
        local okJoin, joinErr = JoinFamilyEvent(raid.eventUid, context.cid, src, { allowMidJoin = true })
        if not okJoin then
            return false, tostring(joinErr or 'Failed to join event.')
        end
    end

    raid.players[tonumber(src)] = {
        src = tonumber(src), cid = context.cid, familyId = familyId, alive = true,
        outsideSince = nil,
    }
    PlayerRaid[tonumber(src)] = raid.id
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

    local activeRaidForHouse = houseId and GetRaidForHouse(tonumber(houseId))
    local activeRaidForCallerFamily = family and GetRaidForFamily(tonumber(family.id))
    local targetRaid = activeRaidForHouse or activeRaidForCallerFamily

    local raidFamilyMember = targetRaid and family and targetRaid.families[tonumber(family.id)] ~= nil
    local raidAllowedFamily = targetRaid and family and (
        tonumber(family.id) == tonumber(targetRaid.attackerFamilyId)
        or tonumber(family.id) == tonumber(targetRaid.targetFamilyId))
    local canInitiate = family ~= nil and not isMember and canStart({ rank = rank })
    local state = {
        enabled = true,
        active = activeRaidForHouse ~= nil,
        inFamily = family ~= nil,
        isMember = isMember == true,
        canStart = (not activeRaidForHouse) and (not activeRaidForCallerFamily) and canInitiate or false,
        canJoin = activeRaidForHouse ~= nil and raidAllowedFamily == true
            and (activeRaidForHouse.phase == 'forming' or raidFamilyMember),
        raidId = activeRaidForHouse and activeRaidForHouse.id or nil,
    }
    return state
end
exports('GetFamilyRaidDoorState', GetFamilyRaidDoorState)

exports('CanStartFamilyRaid', function(characterId, familyId)
    local rank, family = GetRankForCid(characterId)
    if not family or tonumber(family.id) ~= tonumber(familyId) then return false end
    if not canStart({ rank = rank }) then return false end
    if type(CanFamilyStartEvent) == 'function' then
        return CanFamilyStartEvent(familyId, 'family_raid')
    end
    return true
end)

function StartFamilyRaid(src, houseId, center, houseFamilyId)
    if not raidConfig('enabled', true) then return false, 'Family raids are disabled.' end
    local context, why = memberContext(src)
    if not context then return false, why end
    local familyId = tonumber(context.family.id)

    local houseRaid = houseId and GetRaidForHouse(tonumber(houseId))
    if houseRaid then
        local dx = (tonumber(center and center.x) or 0.0) - (tonumber(houseRaid.center.x) or 0.0)
        local dy = (tonumber(center and center.y) or 0.0) - (tonumber(houseRaid.center.y) or 0.0)
        local dz = (tonumber(center and center.z) or 0.0) - (tonumber(houseRaid.center.z) or 0.0)
        if (dx * dx + dy * dy + dz * dz) > ((houseRaid.radius + 8.0) ^ 2) then
            return false, 'Stand inside the active raid circle to join.'
        end
        return joinRaid(src, houseRaid)
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

    -- Check event engine eligibility
    if type(CanFamilyStartEvent) == 'function' then
        local canStartEvt, evtErrCode, details = CanFamilyStartEvent(familyId, 'family_raid')
        if not canStartEvt then
            if evtErrCode == 'family_already_in_event' then
                return false, 'Your family is already participating in an active event.'
            elseif evtErrCode == 'event_on_cooldown' then
                local remainingMin = math.ceil((details and details.remaining or 0) / 60)
                return false, ('Family raid is on cooldown (%d minute%s remaining).'):format(remainingMin, remainingMin == 1 and '' or 's')
            elseif evtErrCode == 'family_level_too_low' then
                return false, ('Your family must be at least Level %d to start a raid.'):format(details and details.required or 1)
            end
            return false, tostring(evtErrCode or 'Cannot start raid.')
        end
    end

    -- Create event instance via Event Engine
    local arenaRadius = tonumber(raidConfig('arenaRadius', raidConfig('joinRadius', 4.0))) or 4.0
    local okCreate, instance = CreateFamilyEvent('family_raid', {
        initiatorFamilyId = familyId,
        targetFamilyId = targetFamilyId,
        locationKey = ('house_%s'):format(houseId),
        actorCid = context.cid,
        metadata = {
            houseId = tonumber(houseId),
            center = { x = tonumber(center and center.x) or 0.0, y = tonumber(center and center.y) or 0.0, z = tonumber(center and center.z) or 0.0 },
            radius = arenaRadius,
        }
    })

    if not okCreate or not instance then
        return false, tostring(instance or 'Failed to create raid event.')
    end

    local raid = {
        id = instance.eventUid,
        eventUid = instance.eventUid,
        houseId = tonumber(houseId),
        center = { x = tonumber(center and center.x) or 0.0, y = tonumber(center and center.y) or 0.0, z = tonumber(center and center.z) or 0.0 },
        radius = arenaRadius,
        bucket = instance.routingBucket or (700000 + math.random(1, 9999)),
        phase = 'forming',
        startedAt = os.time(),
        startsAt = nil,
        endsAt = instance.endsAt,
        families = { [familyId] = { familyId = familyId, name = familyName(familyId) } },
        players = {},
        attackerFamilyId = familyId,
        targetFamilyId = targetFamilyId,
        overtime = false,
        nearbyNoticeAt = {},
    }

    ActiveRaids[raid.id] = raid
    ActiveRaidsByHouse[tonumber(houseId)] = raid
    ActiveRaidsByFamily[familyId] = raid
    ActiveRaidsByFamily[targetFamilyId] = raid

    broadcastRaid(raid)
    notify(src, 'Family raid circle created. Your opponent must enter the circle.', 'success')
    return joinRaid(src, raid, true)
end
exports('StartFamilyRaid', StartFamilyRaid)

lib.callback.register('cm-family:server:joinRaid', function(src, raidId)
    local raid = raidId and GetRaidById(raidId) or GetRaidForPlayer(src)
    if not raid or raid.finished then return false, 'That raid is no longer active.' end
    return joinRaid(src, raid)
end)

lib.callback.register('cm-family:server:getActiveRaid', function(src)
    local raid = GetRaidForPlayer(src)
    if not raid then
        local context = memberContext(src)
        local familyId = context and context.family and tonumber(context.family.id)
        if familyId then raid = GetRaidForFamily(familyId) end
    end
    return raid and isRaidEligibleViewer(src, raid) and raidPayload(raid) or false
end)

lib.callback.register('cm-family:server:leaveRaid', function(src)
    local raid = GetRaidForPlayer(src)
    if not raid or not raid.players[tonumber(src)] then return false, 'You are not in a raid.' end
    eliminate(src, 'left_raid')
    return true
end)

CreateThread(function()
    while true do
        Wait(500)
        local activeList = {}
        for _, raid in pairs(ActiveRaids) do activeList[#activeList + 1] = raid end
        for _, raid in ipairs(activeList) do
            if raid and not raid.finished then
                local now = os.time()
                if raid.phase == 'countdown' and raid.startsAt and now >= raid.startsAt then
                    local okTrans = true
                    if type(TransitionEventState) == 'function' then
                        local success, errTrans = TransitionEventState(raid.eventUid, 'active', { durationSeconds = tonumber(raidConfig('durationSeconds', 900)) or 900 })
                        if not success then
                            okTrans = false
                            print(('^1[cm-family:raid] Failed to transition raid %s to active: %s. Aborting raid.^7'):format(tostring(raid.eventUid), tostring(errTrans)))
                            finishRaid(raid, nil, 'transition_failed')
                        end
                    end
                    if okTrans and not raid.finished then
                        raid.phase = 'active'
                        raid.startedAt = now
                        raid.endsAt = now + (tonumber(raidConfig('durationSeconds', 900)) or 900)
                        broadcastRaid(raid)
                        for src in pairs(raid.players) do notify(src, 'Raid started. Last family standing wins.', 'inform') end
                    end
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
                -- Nearby warning for third-party players
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
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local raid = GetRaidForPlayer(src)
    if raid and raid.players[tonumber(src)] then eliminate(src, 'disconnected') end
end)

AddEventHandler('playerJoining', function()
    local src = source
    local context = memberContext(src)
    local familyId = context and context.family and tonumber(context.family.id)
    if familyId then
        local raid = GetRaidForFamily(familyId)
        if raid and isRaidEligibleViewer(src, raid) then
            TriggerClientEvent('cm-family:client:raidCircle', src, raidPayload(raid))
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, raid in pairs(ActiveRaids) do
        for src in pairs(raid.players) do
            if GetPlayerName(src) then SetPlayerRoutingBucket(src, 0) end
        end
    end
end)
