-- ============================================================
-- cm-family | sv_events.lua
-- CM Family Event Engine — Phase 1
-- Authoritative, reusable event lifecycle, state machine,
-- participant security, persistent cooldowns, and recovery.
-- ============================================================

local B = CMFamilyBridge

local EventInstances = {}          -- [eventUid] = instance
local ActiveEventsByFamily = {}     -- [familyId] = eventUid
local ActiveEventsByCharacter = {}  -- [characterId] = eventUid
local CooldownCache = {}            -- [key:familyId] = { availableAt = timestamp }
local eventSequence = 0

-- Valid state machine transitions
local ALLOWED_TRANSITIONS = {
    ['scheduled'] = { ['available'] = true, ['cancelled'] = true },
    ['available'] = { ['forming'] = true, ['cancelled'] = true, ['expired'] = true },
    ['forming']   = { ['countdown'] = true, ['active'] = true, ['cancelled'] = true, ['failed'] = true, ['expired'] = true },
    ['countdown'] = { ['active'] = true, ['cancelled'] = true, ['failed'] = true },
    ['active']    = { ['overtime'] = true, ['completed'] = true, ['failed'] = true, ['cancelled'] = true, ['expired'] = true },
    ['overtime']  = { ['completed'] = true, ['failed'] = true, ['cancelled'] = true },
}

local TERMINAL_STATES = {
    ['completed'] = true,
    ['failed']    = true,
    ['cancelled'] = true,
    ['expired']   = true,
}

local function generateEventUid(eventKey)
    eventSequence = eventSequence + 1
    local dateStr = os.date('%Y%m%d')
    local randSuffix = math.random(1000, 9999)
    return ('fam_evt_%s_%s_%04d_%04d'):format(dateStr, tostring(eventKey or 'evt'), eventSequence % 10000, randSuffix)
end

function GetEventDefinition(eventKey)
    if not eventKey or not Config.FamilyEvents then return nil end
    return Config.FamilyEvents[eventKey]
end
exports('GetEventDefinition', GetEventDefinition)

-- ------------------------------------------------------------
-- Cooldown System
-- ------------------------------------------------------------
local function cooldownCacheKey(familyId, eventKey)
    return ('%s:%s'):format(tostring(familyId), tostring(eventKey))
end

function GetFamilyEventCooldown(familyId, eventKey)
    familyId = tonumber(familyId)
    if not familyId or not eventKey then
        return { ready = false, remaining = 0, availableAt = 0 }
    end

    local cacheKey = cooldownCacheKey(familyId, eventKey)
    local now = os.time()

    local cached = CooldownCache[cacheKey]
    if cached and cached.availableAt then
        if now < cached.availableAt then
            return {
                ready = false,
                remaining = cached.availableAt - now,
                availableAt = cached.availableAt,
            }
        else
            CooldownCache[cacheKey] = nil
        end
    end

    -- Query durable cooldown from DB
    local row = MySQL.single.await([[
        SELECT UNIX_TIMESTAMP(available_at) AS available_at_ts, last_event_uid
        FROM cm_family_event_cooldowns
        WHERE event_key = ? AND family_id = ?
        LIMIT 1
    ]], { tostring(eventKey), familyId })

    if row and row.available_at_ts then
        local availTs = tonumber(row.available_at_ts) or 0
        if now < availTs then
            CooldownCache[cacheKey] = { availableAt = availTs }
            return {
                ready = false,
                remaining = availTs - now,
                availableAt = availTs,
            }
        end
    end

    return { ready = true, remaining = 0, availableAt = 0 }
end
exports('GetFamilyEventCooldown', GetFamilyEventCooldown)

function SetFamilyEventCooldown(familyId, eventKey, seconds, eventUid)
    familyId = tonumber(familyId)
    seconds = math.max(0, tonumber(seconds) or 0)
    if not familyId or not eventKey then return false end

    local now = os.time()
    local cacheKey = cooldownCacheKey(familyId, eventKey)
    if seconds <= 0 then
        CooldownCache[cacheKey] = nil
        MySQL.query.await([[
            DELETE FROM cm_family_event_cooldowns WHERE event_key = ? AND family_id = ?
        ]], { tostring(eventKey), familyId })
        return true
    end

    local availableAt = now + seconds
    CooldownCache[cacheKey] = { availableAt = availableAt }

    MySQL.query.await([[
        INSERT INTO cm_family_event_cooldowns (event_key, family_id, available_at, last_event_uid)
        VALUES (?, ?, FROM_UNIXTIME(?), ?)
        ON DUPLICATE KEY UPDATE
            available_at = VALUES(available_at),
            last_event_uid = VALUES(last_event_uid),
            updated_at = CURRENT_TIMESTAMP
    ]], { tostring(eventKey), familyId, availableAt, eventUid and tostring(eventUid) or nil })

    return true
end
exports('SetFamilyEventCooldown', SetFamilyEventCooldown)

function ClearFamilyEventCooldown(familyId, eventKey)
    return SetFamilyEventCooldown(familyId, eventKey, 0)
end
exports('ClearFamilyEventCooldown', ClearFamilyEventCooldown)

-- ------------------------------------------------------------
-- Eligibility Check
-- ------------------------------------------------------------
function CanFamilyStartEvent(familyId, eventKey)
    familyId = tonumber(familyId)
    if not familyId then return false, 'invalid_family_id' end

    local def = GetEventDefinition(eventKey)
    if not def then return false, 'unknown_event_key' end

    local family = GetFamilyById(familyId)
    if not family then return false, 'family_not_found' end

    -- Check progression level requirement
    local level = 1
    if type(GetFamilyProgression) == 'function' then
        local prog = GetFamilyProgression(familyId)
        if prog and prog.level then level = tonumber(prog.level) or 1 end
    end
    local reqLevel = tonumber(def.minFamilyLevel) or 1
    if level < reqLevel then
        return false, 'family_level_too_low', { required = reqLevel, current = level }
    end

    -- Rule: One active major event per family
    if ActiveEventsByFamily[familyId] then
        return false, 'family_already_in_event', { activeEventUid = ActiveEventsByFamily[familyId] }
    end

    -- Check cooldown
    local cooldown = GetFamilyEventCooldown(familyId, eventKey)
    if not cooldown.ready then
        return false, 'event_on_cooldown', { remaining = cooldown.remaining, availableAt = cooldown.availableAt }
    end

    return true
end
exports('CanFamilyStartEvent', CanFamilyStartEvent)

-- ------------------------------------------------------------
-- Event Instance Management
-- ------------------------------------------------------------
function GetFamilyEvent(eventUid)
    if not eventUid then return nil end
    local uid = tostring(eventUid)
    if EventInstances[uid] then return EventInstances[uid] end

    -- Fallback to database lookup
    local row = MySQL.single.await([[
        SELECT id, event_uid, event_key, state, initiator_family_id, target_family_id,
               winner_family_id, location_key, routing_bucket,
               UNIX_TIMESTAMP(started_at) AS started_at_ts,
               UNIX_TIMESTAMP(ends_at) AS ends_at_ts,
               UNIX_TIMESTAMP(completed_at) AS completed_at_ts,
               result_reason, metadata,
               UNIX_TIMESTAMP(created_at) AS created_at_ts
        FROM cm_family_event_instances
        WHERE event_uid = ?
        LIMIT 1
    ]], { uid })

    if not row then return nil end

    local metadata = {}
    if row.metadata and type(row.metadata) == 'string' then
        pcall(function() metadata = json.decode(row.metadata) or {} end)
    elseif type(row.metadata) == 'table' then
        metadata = row.metadata
    end

    local instance = {
        id = row.id,
        eventUid = row.event_uid,
        eventKey = row.event_key,
        state = row.state,
        initiatorFamilyId = tonumber(row.initiator_family_id),
        targetFamilyId = tonumber(row.target_family_id),
        winnerFamilyId = tonumber(row.winner_family_id),
        locationKey = row.location_key,
        routingBucket = tonumber(row.routing_bucket),
        startedAt = tonumber(row.started_at_ts),
        endsAt = tonumber(row.ends_at_ts),
        completedAt = tonumber(row.completed_at_ts),
        resultReason = row.result_reason,
        metadata = metadata,
        createdAt = tonumber(row.created_at_ts),
        participants = {},
    }

    if not TERMINAL_STATES[instance.state] then
        EventInstances[uid] = instance
    end
    return instance
end
exports('GetFamilyEvent', GetFamilyEvent)

function GetActiveFamilyEventForFamily(familyId)
    familyId = tonumber(familyId)
    if not familyId then return nil end
    local uid = ActiveEventsByFamily[familyId]
    if not uid then return nil end
    return GetFamilyEvent(uid)
end
exports('GetActiveFamilyEventForFamily', GetActiveFamilyEventForFamily)

function CreateFamilyEvent(eventKey, payload)
    payload = type(payload) == 'table' and payload or {}
    local def = GetEventDefinition(eventKey)
    if not def then return false, 'unknown_event_key' end

    local initiatorId = tonumber(payload.initiatorFamilyId)
    if not initiatorId then return false, 'missing_initiator_family' end

    local canStart, errCode, errDetails = CanFamilyStartEvent(initiatorId, eventKey)
    if not canStart then return false, errCode, errDetails end

    local targetId = tonumber(payload.targetFamilyId)
    if targetId then
        if targetId == initiatorId then
            return false, 'cannot_target_own_family'
        end
        if ActiveEventsByFamily[targetId] then
            return false, 'target_family_already_in_event'
        end
    end

    local eventUid = generateEventUid(eventKey)
    local routingBucket = nil
    if def.rules and def.rules.routingBucket then
        local bucketBase = tonumber(def.rules.bucketBase or 700000) or 700000
        routingBucket = bucketBase + (eventSequence % 50000)
    end

    local metadata = type(payload.metadata) == 'table' and payload.metadata or {}
    metadata.label = def.label
    metadata.category = def.category

    local initialEndsAt = os.time() + (tonumber(def.durationSeconds) or 900)

    local instance = {
        eventUid = eventUid,
        eventKey = eventKey,
        state = 'forming',
        initiatorFamilyId = initiatorId,
        targetFamilyId = targetId,
        winnerFamilyId = nil,
        locationKey = payload.locationKey and tostring(payload.locationKey) or nil,
        routingBucket = routingBucket,
        startedAt = nil,
        endsAt = initialEndsAt,
        completedAt = nil,
        resultReason = nil,
        metadata = metadata,
        createdAt = os.time(),
        participants = {},
        families = {
            [initiatorId] = { familyId = initiatorId, role = 'initiator' },
        },
    }
    if targetId then
        instance.families[targetId] = { familyId = targetId, role = 'target' }
    end

    local metaJson = json.encode(metadata)
    MySQL.insert.await([[
        INSERT INTO cm_family_event_instances
            (event_uid, event_key, state, initiator_family_id, target_family_id,
             location_key, routing_bucket, ends_at, metadata)
        VALUES (?, ?, 'forming', ?, ?, ?, ?, FROM_UNIXTIME(?), ?)
    ]], {
        eventUid, eventKey, initiatorId, targetId,
        instance.locationKey, routingBucket, initialEndsAt, metaJson
    })

    EventInstances[eventUid] = instance
    ActiveEventsByFamily[initiatorId] = eventUid
    if targetId then
        ActiveEventsByFamily[targetId] = eventUid
    end

    LogFamily(initiatorId, payload.actorCid, 'family_event_created', {
        eventUid = eventUid,
        eventKey = eventKey,
        targetFamilyId = targetId,
    })

    return true, instance
end
exports('CreateFamilyEvent', CreateFamilyEvent)

-- ------------------------------------------------------------
-- State Machine Transitions
-- ------------------------------------------------------------
function TransitionEventState(eventUid, targetState, payload)
    local instance = GetFamilyEvent(eventUid)
    if not instance then return false, 'event_not_found' end

    local currentState = instance.state
    if currentState == targetState then return true, instance end

    local allowedMap = ALLOWED_TRANSITIONS[currentState]
    if not allowedMap or not allowedMap[targetState] then
        return false, 'invalid_state_transition', { current = currentState, target = targetState }
    end

    payload = type(payload) == 'table' and payload or {}
    instance.state = targetState

    local now = os.time()
    local setClauses = { 'state = ?' }
    local setParams = { targetState }

    if targetState == 'active' then
        instance.startedAt = now
        local def = GetEventDefinition(instance.eventKey)
        local duration = tonumber(payload.durationSeconds or (def and def.durationSeconds) or 900)
        instance.endsAt = now + duration
        setClauses[#setClauses + 1] = 'started_at = FROM_UNIXTIME(?)'
        setParams[#setParams + 1] = now
        setClauses[#setClauses + 1] = 'ends_at = FROM_UNIXTIME(?)'
        setParams[#setParams + 1] = instance.endsAt
    elseif targetState == 'overtime' then
        instance.metadata = instance.metadata or {}
        instance.metadata.overtime = true
    elseif TERMINAL_STATES[targetState] then
        instance.completedAt = now
        instance.resultReason = payload.reason or targetState
        setClauses[#setClauses + 1] = 'completed_at = FROM_UNIXTIME(?)'
        setParams[#setParams + 1] = now
        setClauses[#setClauses + 1] = 'result_reason = ?'
        setParams[#setParams + 1] = instance.resultReason
        if payload.winnerFamilyId then
            instance.winnerFamilyId = tonumber(payload.winnerFamilyId)
            setClauses[#setClauses + 1] = 'winner_family_id = ?'
            setParams[#setParams + 1] = instance.winnerFamilyId
        end
    end

    if payload.metadataUpdate then
        instance.metadata = instance.metadata or {}
        for k, v in pairs(payload.metadataUpdate) do instance.metadata[k] = v end
        setClauses[#setClauses + 1] = 'metadata = ?'
        setParams[#setParams + 1] = json.encode(instance.metadata)
    end

    setParams[#setParams + 1] = eventUid
    local sql = ('UPDATE cm_family_event_instances SET %s WHERE event_uid = ?'):format(table.concat(setClauses, ', '))
    MySQL.update.await(sql, setParams)

    if TERMINAL_STATES[targetState] then
        -- Clear active family locks
        if instance.initiatorFamilyId then ActiveEventsByFamily[instance.initiatorFamilyId] = nil end
        if instance.targetFamilyId then ActiveEventsByFamily[instance.targetFamilyId] = nil end
        EventInstances[eventUid] = nil
    end

    return true, instance
end
exports('TransitionEventState', TransitionEventState)

-- ------------------------------------------------------------
-- Participant Management
-- ------------------------------------------------------------
function JoinFamilyEvent(eventUid, characterId, src, opts)
    local instance = GetFamilyEvent(eventUid)
    if not instance then return false, 'event_not_found' end

    opts = type(opts) == 'table' and opts or {}
    characterId = tostring(characterId or '')
    if characterId == '' then return false, 'invalid_character_id' end

    -- Verify state allows joining
    if instance.state ~= 'forming' and instance.state ~= 'countdown' and not opts.allowMidJoin then
        return false, 'event_not_open_for_joining'
    end

    -- Verify character family membership
    local rank, family = GetRankForCid(characterId)
    if not rank or not family then return false, 'character_not_in_family' end
    local famId = tonumber(family.id)

    if famId ~= instance.initiatorFamilyId and famId ~= instance.targetFamilyId then
        return false, 'unrelated_family_cannot_join'
    end

    -- Check character not in another active event
    local existingEvent = ActiveEventsByCharacter[characterId]
    if existingEvent and existingEvent ~= eventUid then
        return false, 'character_already_in_event'
    end

    -- Check participant limits
    local def = GetEventDefinition(instance.eventKey)
    local maxParts = tonumber(def and def.maxParticipants or 8) or 8
    local familyPartCount = 0
    for _, p in pairs(instance.participants) do
        if p.familyId == famId and p.status == 'active' then
            familyPartCount = familyPartCount + 1
        end
    end
    if familyPartCount >= maxParts and not instance.participants[characterId] then
        return false, 'participant_limit_reached'
    end

    local part = {
        cid = characterId,
        familyId = famId,
        src = tonumber(src),
        joinedAt = os.time(),
        status = 'active',
        score = 0,
        contribution = 0,
    }
    instance.participants[characterId] = part
    ActiveEventsByCharacter[characterId] = eventUid

    -- Persist participant
    MySQL.query.await([[
        INSERT INTO cm_family_event_participants (event_uid, family_id, character_id, status)
        VALUES (?, ?, ?, 'active')
        ON DUPLICATE KEY UPDATE
            status = 'active',
            left_at = NULL
    ]], { eventUid, famId, characterId })

    if src and instance.routingBucket and def and def.rules and def.rules.routingBucket then
        SetPlayerRoutingBucket(tonumber(src), instance.routingBucket)
    end

    LogFamily(famId, characterId, 'family_event_joined', {
        eventUid = eventUid,
        eventKey = instance.eventKey,
    })

    return true, instance
end
exports('JoinFamilyEvent', JoinFamilyEvent)

function LeaveFamilyEvent(eventUid, characterId, reason)
    local instance = GetFamilyEvent(eventUid)
    characterId = tostring(characterId or '')
    if not instance or not instance.participants[characterId] then
        ActiveEventsByCharacter[characterId] = nil
        return true
    end

    local p = instance.participants[characterId]
    p.status = reason or 'left'
    p.leftAt = os.time()
    ActiveEventsByCharacter[characterId] = nil

    MySQL.query.await([[
        UPDATE cm_family_event_participants
        SET status = ?, left_at = CURRENT_TIMESTAMP
        WHERE event_uid = ? AND character_id = ?
    ]], { p.status, eventUid, characterId })

    if p.src and GetPlayerName(p.src) then
        SetPlayerRoutingBucket(p.src, 0)
    end

    return true
end
exports('LeaveFamilyEvent', LeaveFamilyEvent)

-- ------------------------------------------------------------
-- Event Completion & Idempotent Cleanup
-- ------------------------------------------------------------
local cleanupRunning = {}

function CleanupFamilyEvent(eventUid, reason)
    local uid = tostring(eventUid or '')
    if uid == '' or cleanupRunning[uid] then return end
    cleanupRunning[uid] = true

    local instance = GetFamilyEvent(uid)
    if instance and instance.participants then
        for cid, p in pairs(instance.participants) do
            ActiveEventsByCharacter[cid] = nil
            if p.src and GetPlayerName(p.src) then
                SetPlayerRoutingBucket(p.src, 0)
            end
        end
    end

    if instance then
        if instance.initiatorFamilyId then ActiveEventsByFamily[instance.initiatorFamilyId] = nil end
        if instance.targetFamilyId then ActiveEventsByFamily[instance.targetFamilyId] = nil end
    end

    EventInstances[uid] = nil
    cleanupRunning[uid] = nil
    return true
end
exports('CleanupFamilyEvent', CleanupFamilyEvent)

function CompleteFamilyEvent(eventUid, result)
    result = type(result) == 'table' and result or {}
    local instance = GetFamilyEvent(eventUid)
    if not instance then return false, 'event_not_found' end

    if TERMINAL_STATES[instance.state] then
        return false, 'event_already_terminated'
    end

    local winnerId = tonumber(result.winnerFamilyId)
    local def = GetEventDefinition(instance.eventKey)
    local reason = result.reason or 'completed'

    -- Transition state machine to completed
    local okTrans, transErr = TransitionEventState(eventUid, 'completed', {
        winnerFamilyId = winnerId,
        reason = reason,
        metadataUpdate = {
            scores = result.scores,
            stats = result.stats,
        },
    })
    if not okTrans then return false, transErr end

    -- Award rewards if winner exists
    local rewardOk, rewardRes = false, nil
    if winnerId and def and def.rewards then
        local rep = tonumber(def.rewards.reputation) or 0
        local treasury = tonumber(def.rewards.treasury) or 0
        local contrib = tonumber(def.rewards.contribution) or 0

        local winnerParticipants = {}
        for cid, p in pairs(instance.participants) do
            if p.familyId == winnerId then
                winnerParticipants[#winnerParticipants + 1] = cid
            end
        end

        local uniqueRewardId = ('family_event:%s:winner:%s'):format(eventUid, winnerId)
        if type(AwardFamilyActivityReward) == 'function' then
            rewardOk, rewardRes = AwardFamilyActivityReward({
                familyId = winnerId,
                uniqueId = uniqueRewardId,
                eventType = instance.eventKey,
                reputation = rep,
                treasuryAmount = treasury,
                memberContribution = contrib,
                participants = winnerParticipants,
                metadata = {
                    eventUid = eventUid,
                    eventKey = instance.eventKey,
                    targetFamilyId = instance.targetFamilyId,
                    resultReason = reason,
                }
            })
        end
    end

    -- Apply cooldown to participating families
    local cdSeconds = tonumber(def and def.cooldownSeconds or 10800) or 10800
    if instance.initiatorFamilyId then
        SetFamilyEventCooldown(instance.initiatorFamilyId, instance.eventKey, cdSeconds, eventUid)
    end
    if instance.targetFamilyId then
        SetFamilyEventCooldown(instance.targetFamilyId, instance.eventKey, cdSeconds, eventUid)
    end

    -- Audit log
    LogFamily(instance.initiatorFamilyId, nil, 'family_event_completed', {
        eventUid = eventUid,
        eventKey = instance.eventKey,
        winnerFamilyId = winnerId,
        reason = reason,
    })

    -- Cleanup
    CleanupFamilyEvent(eventUid, reason)

    return true, {
        eventUid = eventUid,
        winnerFamilyId = winnerId,
        rewardOk = rewardOk,
        rewardRes = rewardRes,
    }
end
exports('CompleteFamilyEvent', CompleteFamilyEvent)

function CancelFamilyEvent(eventUid, reason)
    local instance = GetFamilyEvent(eventUid)
    if not instance then return false, 'event_not_found' end

    if TERMINAL_STATES[instance.state] then
        return false, 'event_already_terminated'
    end

    reason = reason or 'cancelled'
    TransitionEventState(eventUid, 'cancelled', { reason = reason })

    -- Audit log
    if instance.initiatorFamilyId then
        LogFamily(instance.initiatorFamilyId, nil, 'family_event_cancelled', {
            eventUid = eventUid,
            eventKey = instance.eventKey,
            reason = reason,
        })
    end

    CleanupFamilyEvent(eventUid, reason)
    return true
end
exports('CancelFamilyEvent', CancelFamilyEvent)

-- ------------------------------------------------------------
-- UI Operations Data Fetcher
-- ------------------------------------------------------------
function GetRecentFamilyOperations(familyId, limit)
    familyId = tonumber(familyId)
    if not familyId then return {} end
    limit = math.min(50, math.max(1, tonumber(limit) or 10))

    local rows = MySQL.query.await([[
        SELECT event_uid, event_key, state, initiator_family_id, target_family_id,
               winner_family_id, result_reason, metadata,
               UNIX_TIMESTAMP(started_at) AS started_ts,
               UNIX_TIMESTAMP(completed_at) AS completed_ts,
               UNIX_TIMESTAMP(created_at) AS created_ts
        FROM cm_family_event_instances
        WHERE initiator_family_id = ? OR target_family_id = ?
        ORDER BY id DESC
        LIMIT ?
    ]], { familyId, familyId, limit }) or {}

    local out = {}
    for _, r in ipairs(rows) do
        local def = GetEventDefinition(r.event_key)
        local isInitiator = tonumber(r.initiator_family_id) == familyId
        local oppId = isInitiator and tonumber(r.target_family_id) or tonumber(r.initiator_family_id)
        local oppFamily = oppId and GetFamilyById(oppId)
        local won = tonumber(r.winner_family_id) == familyId

        local durationMinutes = 0
        if r.started_ts and r.completed_ts and r.completed_ts > r.started_ts then
            durationMinutes = math.ceil((r.completed_ts - r.started_ts) / 60)
        end

        local rewardAmount = 0
        if won and def and def.rewards then
            rewardAmount = tonumber(def.rewards.treasury) or 0
        end

        out[#out + 1] = {
            eventUid = r.event_uid,
            eventKey = r.event_key,
            label = def and def.label or r.event_key,
            state = r.state,
            won = won,
            opponentName = oppFamily and oppFamily.name or 'Opposing Family',
            resultReason = r.result_reason,
            completedAt = r.completed_ts or r.created_ts,
            durationMinutes = durationMinutes,
            rewardCredited = rewardAmount,
        }
    end
    return out
end
exports('GetRecentFamilyOperations', GetRecentFamilyOperations)

-- ------------------------------------------------------------
-- Resource Restart Recovery
-- ------------------------------------------------------------
local function recoverStaleEvents()
    local staleRows = MySQL.query.await([[
        SELECT event_uid, initiator_family_id, target_family_id, routing_bucket
        FROM cm_family_event_instances
        WHERE state IN ('forming', 'countdown', 'active', 'overtime')
    ]]) or {}

    if #staleRows == 0 then return end

    print(('^3[cm-family] recovering %d stale active event(s) from previous server execution...^7'):format(#staleRows))
    for _, row in ipairs(staleRows) do
        local uid = row.event_uid
        MySQL.update.await([[
            UPDATE cm_family_event_instances
            SET state = 'cancelled', result_reason = 'resource_restart_recovery', completed_at = CURRENT_TIMESTAMP
            WHERE event_uid = ?
        ]], { uid })

        MySQL.update.await([[
            UPDATE cm_family_event_participants
            SET status = 'cancelled', left_at = CURRENT_TIMESTAMP
            WHERE event_uid = ? AND status = 'active'
        ]], { uid })

        if row.initiator_family_id then
            LogFamily(row.initiator_family_id, nil, 'family_event_cancelled', {
                eventUid = uid,
                reason = 'resource_restart_recovery',
            })
        end
        print(('^2[cm-family] recovered and safely cancelled stale event %s^7'):format(uid))
    end
end

-- ------------------------------------------------------------
-- Admin / Debug Console Commands
-- ------------------------------------------------------------
RegisterCommand('family_event_list', function(src, args, raw)
    if src ~= 0 then
        -- Check admin if in-game
        local cid = B.GetCid(src)
        if not cid then return end
        local rank, fam = GetRankForCid(cid)
        if not rank or not rank.is_founder then
            TriggerClientEvent('cm-hud:client:notify', src, 'Unauthorized.', 'error')
            return
        end
    end

    local activeCount = 0
    print('^6--- ACTIVE FAMILY EVENTS ---^7')
    for uid, inst in pairs(EventInstances) do
        activeCount = activeCount + 1
        print(('  [%s] Key: %s | State: %s | Initiator: %s | Target: %s | Bucket: %s'):format(
            uid, inst.eventKey, inst.state, tostring(inst.initiatorFamilyId), tostring(inst.targetFamilyId), tostring(inst.routingBucket)
        ))
    end
    if activeCount == 0 then
        print('  No active family events running.')
    end
    print('^6-----------------------------^7')
end, false)

RegisterCommand('family_event_cancel', function(src, args, raw)
    if src ~= 0 then
        local cid = B.GetCid(src)
        if not cid then return end
        local rank, fam = GetRankForCid(cid)
        if not rank or not rank.is_founder then
            TriggerClientEvent('cm-hud:client:notify', src, 'Unauthorized.', 'error')
            return
        end
    end

    local uid = args[1]
    if not uid then
        print('Usage: family_event_cancel <eventUid>')
        return
    end

    local ok, err = CancelFamilyEvent(uid, 'admin_cancelled')
    if ok then
        print(('^2Cancelled family event %s^7'):format(uid))
    else
        print(('^1Failed to cancel family event %s: %s^7'):format(uid, tostring(err)))
    end
end, false)

-- Run recovery once DB is ready
CreateThread(function()
    while not CMFamilyDatabaseReady do Wait(100) end
    recoverStaleEvents()
end)
