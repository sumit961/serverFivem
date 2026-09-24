-- ============================================================
-- cm-family | sv_events.lua
-- CM Family Event Engine — Phase 1.1 Stabilization
-- Authoritative, reusable event lifecycle, state machine,
-- participant security, persistent cooldowns, and recovery.
-- ============================================================

local B = CMFamilyBridge

local EventInstances = {}          -- [eventUid] = instance
local ActiveEventsByFamily = {}     -- [familyId] = eventUid
local ActiveEventsByCharacter = {}  -- [characterId] = eventUid
local CooldownCache = {}            -- [key:familyId] = { availableAt = timestamp }
local eventSequence = 0
local eventCreateLocks = {}         -- [familyId] = true

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
-- Creation Concurrency Locks
-- ------------------------------------------------------------
local function acquireEventCreateLocks(familyIds)
    local sorted = {}
    for _, id in ipairs(familyIds) do
        local num = tonumber(id)
        if num then sorted[#sorted + 1] = num end
    end
    table.sort(sorted)

    local maxWaitMs = 500
    local elapsed = 0
    while true do
        local anyLocked = false
        for _, id in ipairs(sorted) do
            if eventCreateLocks[id] then
                anyLocked = true
                break
            end
        end
        if not anyLocked then
            break
        end
        Wait(10)
        elapsed = elapsed + 10
        if elapsed >= maxWaitMs then
            return false, 'event_creation_lock_timeout'
        end
    end

    for _, id in ipairs(sorted) do
        eventCreateLocks[id] = true
    end
    return true
end

local function releaseEventCreateLocks(familyIds)
    for _, id in ipairs(familyIds) do
        local num = tonumber(id)
        if num then eventCreateLocks[num] = nil end
    end
end

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

function EnsureFamilyEventCooldown(familyId, eventKey, targetAvailableAt, eventUid)
    familyId = tonumber(familyId)
    targetAvailableAt = tonumber(targetAvailableAt) or 0
    if not familyId or not eventKey or targetAvailableAt <= 0 then return false end

    local cacheKey = cooldownCacheKey(familyId, eventKey)
    local cached = CooldownCache[cacheKey]

    -- If memory cache already has a longer or equal cooldown, do not shorten it
    if cached and cached.availableAt and cached.availableAt >= targetAvailableAt then
        return true, cached.availableAt
    end

    -- Insert or update in database using GREATEST to never shorten a longer valid cooldown
    MySQL.query.await([[
        INSERT INTO cm_family_event_cooldowns (event_key, family_id, available_at, last_event_uid)
        VALUES (?, ?, FROM_UNIXTIME(?), ?)
        ON DUPLICATE KEY UPDATE
            available_at = GREATEST(available_at, VALUES(available_at)),
            last_event_uid = IF(VALUES(available_at) >= available_at, VALUES(last_event_uid), last_event_uid),
            updated_at = CURRENT_TIMESTAMP
    ]], { tostring(eventKey), familyId, targetAvailableAt, eventUid and tostring(eventUid) or nil })

    -- Refresh cache to reflect the greatest available_at
    local row = MySQL.single.await([[
        SELECT UNIX_TIMESTAMP(available_at) AS avail_ts
        FROM cm_family_event_cooldowns
        WHERE event_key = ? AND family_id = ?
        LIMIT 1
    ]], { tostring(eventKey), familyId })

    local finalAvail = row and tonumber(row.avail_ts) or targetAvailableAt
    CooldownCache[cacheKey] = { availableAt = finalAvail }

    return true, finalAvail
end
exports('EnsureFamilyEventCooldown', EnsureFamilyEventCooldown)

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
               result_reason, metadata, reward_state,
               UNIX_TIMESTAMP(reward_processing_at) AS reward_processing_ts,
               UNIX_TIMESTAMP(reward_delivered_at) AS reward_delivered_ts,
               reward_metadata,
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

    local rewardMetadata = {}
    if row.reward_metadata and type(row.reward_metadata) == 'string' then
        pcall(function() rewardMetadata = json.decode(row.reward_metadata) or {} end)
    elseif type(row.reward_metadata) == 'table' then
        rewardMetadata = row.reward_metadata
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
        rewardState = row.reward_state or 'not_applicable',
        rewardProcessingAt = tonumber(row.reward_processing_ts),
        rewardDeliveredAt = tonumber(row.reward_delivered_ts),
        rewardMetadata = rewardMetadata,
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
    local targetId = tonumber(payload.targetFamilyId)

    local familyIdsToLock = targetId and { initiatorId, targetId } or { initiatorId }
    local lockOk, lockErr = acquireEventCreateLocks(familyIdsToLock)
    if not lockOk then return false, lockErr end

    local ok, res, errData, extra = pcall(function()
        local canStart, errCode, errDetails = CanFamilyStartEvent(initiatorId, eventKey)
        if not canStart then return false, errCode, errDetails end

        if targetId then
            if targetId == initiatorId then
                return false, 'cannot_target_own_family'
            end
            if ActiveEventsByFamily[targetId] then
                return false, 'target_family_already_in_event'
            end
            local targetFam = GetFamilyById(targetId)
            if not targetFam then
                return false, 'target_family_not_found'
            end

            -- Target family cooldown protection: prevent attacking a cooling-down family
            local targetCooldown = GetFamilyEventCooldown(targetId, eventKey)
            if not targetCooldown.ready and targetCooldown.remaining > 0 then
                return false, 'target_event_on_cooldown', {
                    remaining = targetCooldown.remaining,
                    availableAt = targetCooldown.availableAt,
                }
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
            rewardState = 'not_applicable',
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
                 location_key, routing_bucket, ends_at, metadata, reward_state)
            VALUES (?, ?, 'forming', ?, ?, ?, ?, FROM_UNIXTIME(?), ?, 'not_applicable')
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
    end)

    releaseEventCreateLocks(familyIdsToLock)

    if not ok then return false, tostring(res) end
    return res, errData, extra
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
    src = tonumber(src)

    -- Authoritative CID resolution when source is present
    if src and src > 0 then
        local authCid = B.GetCid(src)
        if not authCid or authCid == '' then
            return false, 'character_source_mismatch'
        end
        if characterId and characterId ~= '' and tostring(characterId) ~= tostring(authCid) then
            return false, 'character_source_mismatch'
        end
        characterId = tostring(authCid)
    else
        characterId = tostring(characterId or '')
        if characterId == '' then return false, 'invalid_character_id' end
    end

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
        src = src,
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
        SetPlayerRoutingBucket(src, instance.routingBucket)
    end

    LogFamily(famId, characterId, 'family_event_joined', {
        eventUid = eventUid,
        eventKey = instance.eventKey,
    })

    return true, instance
end
exports('JoinFamilyEvent', JoinFamilyEvent)

function UpdateFamilyEventParticipantStatus(eventUid, characterId, status, metadata)
    local instance = GetFamilyEvent(eventUid)
    characterId = tostring(characterId or '')
    if not instance or characterId == '' then return false, 'invalid_arguments' end

    status = tostring(status or 'left')
    local metaJson = metadata and json.encode(metadata) or nil

    if instance.participants and instance.participants[characterId] then
        local p = instance.participants[characterId]
        p.status = status
        p.leftAt = os.time()
        if metadata then p.metadata = metadata end
    end

    if status ~= 'active' then
        ActiveEventsByCharacter[characterId] = nil
    end

    MySQL.query.await([[
        UPDATE cm_family_event_participants
        SET status = ?, left_at = COALESCE(left_at, CURRENT_TIMESTAMP), metadata = COALESCE(?, metadata)
        WHERE event_uid = ? AND character_id = ?
    ]], { status, metaJson, tostring(eventUid), characterId })

    return true
end
exports('UpdateFamilyEventParticipantStatus', UpdateFamilyEventParticipantStatus)

function LeaveFamilyEvent(eventUid, characterId, reason)
    return UpdateFamilyEventParticipantStatus(eventUid, characterId, reason or 'left', { reason = reason })
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
    local now = os.time()

    local hasReward = winnerId and def and def.rewards
    local initialRewardState = hasReward and 'processing' or 'not_applicable'

    -- 1. Persist completed state in DB, keeping family locks HELD during finalization!
    instance.state = 'completed'
    instance.completedAt = now
    instance.resultReason = reason
    instance.winnerFamilyId = winnerId
    instance.rewardState = initialRewardState
    if result.scores or result.stats then
        instance.metadata = instance.metadata or {}
        if result.scores then instance.metadata.scores = result.scores end
        if result.stats then instance.metadata.stats = result.stats end
    end

    local metaJson = json.encode(instance.metadata or {})
    MySQL.update.await([[
        UPDATE cm_family_event_instances
        SET state = 'completed',
            completed_at = FROM_UNIXTIME(?),
            result_reason = ?,
            winner_family_id = ?,
            reward_state = ?,
            reward_processing_at = CASE WHEN ? = 'processing' THEN FROM_UNIXTIME(?) ELSE NULL END,
            metadata = ?
        WHERE event_uid = ?
    ]], {
        now, reason, winnerId, initialRewardState,
        initialRewardState, now, metaJson, eventUid
    })

    -- 2. Finalize participants in DB
    -- Active/joined participants become completed; eliminated/left remain untouched
    MySQL.query.await([[
        UPDATE cm_family_event_participants
        SET status = 'completed', left_at = COALESCE(left_at, FROM_UNIXTIME(?))
        WHERE event_uid = ? AND status IN ('active', 'joined')
    ]], { now, eventUid })

    if instance.participants then
        for cid, p in pairs(instance.participants) do
            if p.status == 'active' or p.status == 'joined' then
                p.status = 'completed'
                p.leftAt = now
            end
        end
    end

    -- 3. Apply durable cooldown in DB & memory
    local cdSeconds = tonumber(def and def.cooldownSeconds or 10800) or 10800
    local targetAvailAt = now + cdSeconds
    if instance.initiatorFamilyId then
        EnsureFamilyEventCooldown(instance.initiatorFamilyId, instance.eventKey, targetAvailAt, eventUid)
    end
    if instance.targetFamilyId then
        EnsureFamilyEventCooldown(instance.targetFamilyId, instance.eventKey, targetAvailAt, eventUid)
    end

    -- 4. Reward settlement
    local rewardOk, rewardRes = false, nil
    if hasReward then
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
                eventUid = eventUid,
                eventKey = instance.eventKey,
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

        local deliveredRewardMeta = {}
        if rewardOk and type(rewardRes) == 'table' then
            deliveredRewardMeta = {
                treasuryRequested = treasury,
                treasuryCredited = tonumber(rewardRes.treasuryCredited or rewardRes.actualTreasuryCredited or 0) or 0,
                reputation = tonumber(rewardRes.reputation or rep) or 0,
                memberContribution = tonumber(rewardRes.memberContribution or contrib) or 0,
                participantCount = #winnerParticipants,
            }
            instance.rewardState = 'delivered'
            instance.rewardDeliveredAt = now
            instance.rewardMetadata = deliveredRewardMeta

            MySQL.update.await([[
                UPDATE cm_family_event_instances
                SET reward_state = 'delivered',
                    reward_delivered_at = FROM_UNIXTIME(?),
                    reward_metadata = ?
                WHERE event_uid = ?
            ]], { now, json.encode(deliveredRewardMeta), eventUid })
        else
            instance.rewardState = 'failed'
            instance.rewardMetadata = { error = tostring(rewardRes or 'reward_award_failed') }

            MySQL.update.await([[
                UPDATE cm_family_event_instances
                SET reward_state = 'failed',
                    reward_metadata = ?
                WHERE event_uid = ?
            ]], { json.encode(instance.rewardMetadata), eventUid })
        end
    end

    -- 5. Audit log
    LogFamily(instance.initiatorFamilyId, nil, 'family_event_completed', {
        eventUid = eventUid,
        eventKey = instance.eventKey,
        winnerFamilyId = winnerId,
        reason = reason,
        rewardState = instance.rewardState,
    })

    -- 6. Cleanup: Reset routing buckets and release family locks
    CleanupFamilyEvent(eventUid, reason)

    return true, {
        eventUid = eventUid,
        winnerFamilyId = winnerId,
        rewardOk = rewardOk,
        rewardRes = rewardRes,
        rewardState = instance.rewardState,
        actualDelivered = instance.rewardMetadata,
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
    local now = os.time()

    instance.state = 'cancelled'
    instance.completedAt = now
    instance.resultReason = reason

    MySQL.update.await([[
        UPDATE cm_family_event_instances
        SET state = 'cancelled',
            completed_at = FROM_UNIXTIME(?),
            result_reason = ?,
            reward_state = 'not_applicable'
        WHERE event_uid = ?
    ]], { now, reason, eventUid })

    MySQL.update.await([[
        UPDATE cm_family_event_participants
        SET status = 'cancelled', left_at = COALESCE(left_at, FROM_UNIXTIME(?))
        WHERE event_uid = ? AND status = 'active'
    ]], { now, eventUid })

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
               winner_family_id, result_reason, metadata, reward_state, reward_metadata,
               UNIX_TIMESTAMP(started_at) AS started_ts,
               UNIX_TIMESTAMP(completed_at) AS completed_ts,
               UNIX_TIMESTAMP(created_at) AS created_ts
        FROM cm_family_event_instances
        WHERE (initiator_family_id = ? OR target_family_id = ?)
          AND state IN ('completed', 'failed', 'cancelled', 'expired')
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
        local durationSeconds = 0
        if r.started_ts and r.completed_ts and r.completed_ts > r.started_ts then
            durationSeconds = r.completed_ts - r.started_ts
            durationMinutes = math.ceil(durationSeconds / 60)
        end

        local rewardMeta = {}
        if r.reward_metadata and type(r.reward_metadata) == 'string' then
            pcall(function() rewardMeta = json.decode(r.reward_metadata) or {} end)
        elseif type(r.reward_metadata) == 'table' then
            rewardMeta = r.reward_metadata
        end

        local treasuryCredited = 0
        local repAwarded = 0
        local contribAwarded = 0
        if won then
            treasuryCredited = tonumber(rewardMeta.treasuryCredited or (def and def.rewards and def.rewards.treasury) or 0) or 0
            repAwarded = tonumber(rewardMeta.reputation or (def and def.rewards and def.rewards.reputation) or 0) or 0
            contribAwarded = tonumber(rewardMeta.memberContribution or (def and def.rewards and def.rewards.contribution) or 0) or 0
        end

        out[#out + 1] = {
            eventUid = r.event_uid,
            eventKey = r.event_key,
            label = def and def.label or r.event_key,
            state = r.state,
            won = (r.state == 'completed') and won or nil,
            opponentName = oppFamily and oppFamily.name or 'Opposing Family',
            resultReason = r.result_reason,
            completedAt = r.completed_ts or r.created_ts,
            duration = durationSeconds,
            durationMinutes = durationMinutes,
            treasuryCredited = treasuryCredited,
            rewardCredited = treasuryCredited,
            reputationAwarded = repAwarded,
            contributionAwarded = contribAwarded,
            rewardState = r.reward_state,
        }
    end
    return out
end
exports('GetRecentFamilyOperations', GetRecentFamilyOperations)

-- ------------------------------------------------------------
-- Resource Restart Recovery & Live Player Cleanup
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

        -- Load participant character IDs
        local parts = MySQL.query.await([[
            SELECT character_id, family_id, status
            FROM cm_family_event_participants
            WHERE event_uid = ?
        ]], { uid }) or {}

        for _, p in ipairs(parts) do
            local cid = p.character_id
            local src = nil
            if type(B.GetSourceFromCid) == 'function' then
                src = B.GetSourceFromCid(cid)
            end
            if not src then
                for _, s in ipairs(GetPlayers()) do
                    local playerSrc = tonumber(s)
                    if playerSrc and B.GetCid(playerSrc) == cid then
                        src = playerSrc
                        break
                    end
                end
            end

            if src and GetPlayerName(src) then
                SetPlayerRoutingBucket(src, 0)
                TriggerClientEvent('cm-family:client:raidFinished', src, {
                    cancelled = true,
                    reason = 'resource_restart_recovery',
                })
            end
        end

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

        -- Do not apply competitive cooldown; set cooldown to 0 or recovery cooldown
        local recoveryCd = tonumber(Config.FamilyEvents and Config.FamilyEvents.family_raid and Config.FamilyEvents.family_raid.restartRecoveryCooldown or 0) or 0
        if row.initiator_family_id then
            if recoveryCd > 0 then
                SetFamilyEventCooldown(row.initiator_family_id, 'family_raid', recoveryCd, uid)
            else
                ClearFamilyEventCooldown(row.initiator_family_id, 'family_raid')
            end
        end
        if row.target_family_id then
            if recoveryCd > 0 then
                SetFamilyEventCooldown(row.target_family_id, 'family_raid', recoveryCd, uid)
            else
                ClearFamilyEventCooldown(row.target_family_id, 'family_raid')
            end
        end

        if row.initiator_family_id then
            LogFamily(row.initiator_family_id, nil, 'family_event_cancelled', {
                eventUid = uid,
                reason = 'resource_restart_recovery',
            })
        end
        print(('^2[cm-family] recovered and safely cancelled stale event %s (no ghost cooldown)^7'):format(uid))
    end
end

local function recoverPendingEventSettlements()
    local pendingRows = MySQL.query.await([[
        SELECT event_uid, event_key, initiator_family_id, target_family_id, winner_family_id,
               reward_state, metadata, UNIX_TIMESTAMP(completed_at) AS completed_at_ts
        FROM cm_family_event_instances
        WHERE state = 'completed'
          AND reward_state IN ('processing', 'failed', 'unclaimed')
          AND winner_family_id IS NOT NULL
    ]]) or {}

    if #pendingRows == 0 then return end
    print(('^3[cm-family] recovering %d pending event finalization/settlement(s)...^7'):format(#pendingRows))

    for _, r in ipairs(pendingRows) do
        local uid = r.event_uid
        local winnerId = tonumber(r.winner_family_id)
        local completedAtTs = tonumber(r.completed_at_ts) or os.time()
        local def = GetEventDefinition(r.event_key)
        local cdSeconds = tonumber(def and def.cooldownSeconds or 10800) or 10800
        local targetAvailAt = completedAtTs + cdSeconds

        -- 1. PARTICIPANT FINALIZATION RECOVERY:
        -- Idempotently update active/joined participants to completed.
        -- DO NOT overwrite eliminated, left, or cancelled.
        MySQL.query.await([[
            UPDATE cm_family_event_participants
            SET status = 'completed', left_at = COALESCE(left_at, FROM_UNIXTIME(?))
            WHERE event_uid = ? AND status IN ('active', 'joined')
        ]], { completedAtTs, uid })

        if EventInstances[uid] and EventInstances[uid].participants then
            for cid, p in pairs(EventInstances[uid].participants) do
                if p.status == 'active' or p.status == 'joined' then
                    p.status = 'completed'
                    p.leftAt = completedAtTs
                end
            end
        end

        -- 2. COOLDOWN RECOVERY:
        -- Ensure cooldown exists for BOTH families based on completed_at + cooldownSeconds
        if r.initiator_family_id then
            EnsureFamilyEventCooldown(r.initiator_family_id, r.event_key, targetAvailAt, uid)
        end
        if r.target_family_id then
            EnsureFamilyEventCooldown(r.target_family_id, r.event_key, targetAvailAt, uid)
        end

        -- 3. REWARD SETTLEMENT & RECOVERY FROM ROOT METADATA:
        local uniqueRewardId = ('family_event:%s:winner:%s'):format(uid, winnerId)
        local existingRoot = MySQL.single.await([[
            SELECT id, amount, metadata FROM cm_family_reward_history
            WHERE unique_id = ? LIMIT 1
        ]], { uniqueRewardId })

        if existingRoot then
            -- Already paid! Parse root authoritative envelope so actual credited values are preserved
            local rootMeta = {}
            if existingRoot.metadata and type(existingRoot.metadata) == 'string' then
                pcall(function() rootMeta = json.decode(existingRoot.metadata) or {} end)
            elseif type(existingRoot.metadata) == 'table' then
                rootMeta = existingRoot.metadata
            end

            local deliveredMeta = {
                treasuryRequested = tonumber(rootMeta.treasuryRequested) or tonumber(def and def.rewards and def.rewards.treasury) or 0,
                treasuryCredited = (rootMeta.treasuryCredited ~= nil and tonumber(rootMeta.treasuryCredited)) or 'unknown_legacy',
                reputation = tonumber(rootMeta.reputation) or tonumber(existingRoot.amount) or 0,
                memberContribution = tonumber(rootMeta.memberContribution) or 0,
                participantCount = tonumber(rootMeta.participantCount) or 0,
                recovered = true,
                recoveredAt = os.time(),
            }

            MySQL.update.await([[
                UPDATE cm_family_event_instances
                SET reward_state = 'delivered',
                    reward_delivered_at = COALESCE(reward_delivered_at, CURRENT_TIMESTAMP),
                    reward_metadata = ?
                WHERE event_uid = ?
            ]], { json.encode(deliveredMeta), uid })

            if EventInstances[uid] then
                EventInstances[uid].rewardState = 'delivered'
                EventInstances[uid].rewardMetadata = deliveredMeta
            end

            print(('^2[cm-family] finalization & settlement for event %s recovered from root metadata (treasuryCredited=%s)^7'):format(
                uid, tostring(deliveredMeta.treasuryCredited)))
        else
            -- Not paid yet! Attempt retry safely using AwardFamilyActivityReward
            if def and def.rewards and type(AwardFamilyActivityReward) == 'function' then
                local rep = tonumber(def.rewards.reputation) or 0
                local treasury = tonumber(def.rewards.treasury) or 0
                local contrib = tonumber(def.rewards.contribution) or 0

                local winnerParticipants = {}
                local partRows = MySQL.query.await([[
                    SELECT character_id FROM cm_family_event_participants
                    WHERE event_uid = ? AND family_id = ?
                ]], { uid, winnerId }) or {}
                for _, pr in ipairs(partRows) do
                    winnerParticipants[#winnerParticipants + 1] = pr.character_id
                end

                local okRew, resRew = AwardFamilyActivityReward({
                    familyId = winnerId,
                    uniqueId = uniqueRewardId,
                    eventType = r.event_key,
                    eventUid = uid,
                    eventKey = r.event_key,
                    reputation = rep,
                    treasuryAmount = treasury,
                    memberContribution = contrib,
                    participants = winnerParticipants,
                    metadata = {
                        eventUid = uid,
                        recovered = true,
                    }
                })

                if okRew and type(resRew) == 'table' then
                    local deliveredMeta = {
                        treasuryRequested = treasury,
                        treasuryCredited = tonumber(resRew.treasuryCredited or resRew.actualTreasuryCredited or 0) or 0,
                        reputation = tonumber(resRew.reputation or rep) or 0,
                        memberContribution = tonumber(resRew.memberContribution or contrib) or 0,
                        participantCount = #winnerParticipants,
                        recovered = true,
                        recoveredAt = os.time(),
                    }

                    MySQL.update.await([[
                        UPDATE cm_family_event_instances
                        SET reward_state = 'delivered',
                            reward_delivered_at = CURRENT_TIMESTAMP,
                            reward_metadata = ?
                        WHERE event_uid = ?
                    ]], { json.encode(deliveredMeta), uid })

                    if EventInstances[uid] then
                        EventInstances[uid].rewardState = 'delivered'
                        EventInstances[uid].rewardMetadata = deliveredMeta
                    end

                    print(('^2[cm-family] successfully recovered and paid reward for event %s (treasuryCredited=%d)^7'):format(
                        uid, deliveredMeta.treasuryCredited))
                else
                    MySQL.update.await([[
                        UPDATE cm_family_event_instances
                        SET reward_state = 'failed',
                            reward_metadata = ?
                        WHERE event_uid = ?
                    ]], { json.encode({ error = tostring(resRew or 'retry_failed') }), uid })
                    print(('^1[cm-family] reward retry failed for event %s: %s^7'):format(uid, tostring(resRew)))
                end
            end
        end
    end
end

-- Export settlement recovery so tests/commands can trigger it
RecoverPendingEventSettlements = recoverPendingEventSettlements
RecoverStaleEvents = recoverStaleEvents
exports('RecoverPendingEventSettlements', recoverPendingEventSettlements)
exports('RecoverStaleEvents', recoverStaleEvents)

-- ------------------------------------------------------------
-- Resource Stop Safety
-- ------------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for uid, inst in pairs(EventInstances) do
        if inst.participants then
            for cid, p in pairs(inst.participants) do
                if p.src and GetPlayerName(p.src) then
                    SetPlayerRoutingBucket(p.src, 0)
                    TriggerClientEvent('cm-family:client:raidFinished', p.src, {
                        cancelled = true,
                        reason = 'server_resource_stop',
                    })
                end
            end
        end
    end
end)

-- ------------------------------------------------------------
-- Admin / Debug Console Commands (Console Only)
-- ------------------------------------------------------------
FamilyEventCommands = {
    list = function(src, args, raw)
        if src ~= 0 then
            TriggerClientEvent('cm-hud:client:notify', src, 'Command is server console only.', 'error')
            return false, 'console_only'
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
        return true
    end,

    cancel = function(src, args, raw)
        if src ~= 0 then
            TriggerClientEvent('cm-hud:client:notify', src, 'Command is server console only.', 'error')
            return false, 'console_only'
        end

        local uid = args and args[1]
        if not uid then
            print('Usage: family_event_cancel <eventUid>')
            return false, 'missing_argument'
        end

        local ok, err = CancelFamilyEvent(uid, 'admin_cancelled')
        if ok then
            print(('^2Cancelled family event %s^7'):format(uid))
            return true
        else
            print(('^1Failed to cancel family event %s: %s^7'):format(uid, tostring(err)))
            return false, err
        end
    end,

    recover = function(src, args, raw)
        if src ~= 0 then
            TriggerClientEvent('cm-hud:client:notify', src, 'Command is server console only.', 'error')
            return false, 'console_only'
        end

        print('^3[cm-family] Manual event recovery initiated via console...^7')
        recoverStaleEvents()
        recoverPendingEventSettlements()
        print('^2[cm-family] Event recovery complete.^7')
        return true
    end,
}

RegisterCommand('family_event_list', FamilyEventCommands.list, false)
RegisterCommand('family_event_cancel', FamilyEventCommands.cancel, false)
RegisterCommand('family_event_recover', FamilyEventCommands.recover, false)

-- Run recovery once DB is ready
CreateThread(function()
    while not CMFamilyDatabaseReady do Wait(100) end
    recoverStaleEvents()
    recoverPendingEventSettlements()
end)
