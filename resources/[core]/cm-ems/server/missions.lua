-- EMS mission board v5: persistent admin-created routes, co-op crews and
-- automatically generated public NPC emergencies.

local ActiveRuns = {} -- [runId] = runtime mission
local PlayerRuns = {} -- [characterId] = runId
local CustomDefinitions = {}

local function missionNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function missionMember(src)
    src = tonumber(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) then
        return nil, characterId
    end
    local isDead = false
    pcall(function() isDead = exports[Config.PlayerDataResource]:IsDead(src) == true end)
    if isDead then return nil, characterId end
    return member, tostring(characterId)
end

local function isAdmin(src)
    local ok, allowed = pcall(function()
        return exports[Config.AdminResource]:HasPermission(tonumber(src), Config.AdminPermission)
    end)
    return ok and allowed == true
end

local function copy(value)
    local ok, encoded = pcall(json.encode, value)
    if not ok then return nil end
    local decodedOk, decoded = pcall(json.decode, encoded)
    return decodedOk and decoded or nil
end

local function cleanText(value, maximum, fallback)
    local text = tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if text == '' then text = fallback or '' end
    return text:sub(1, maximum)
end

local function loadCustomDefinitions()
    CustomDefinitions = {}
    local rows = MySQL.query.await([[SELECT id, mission_key, label, category, description, reward, xp,
        time_limit_seconds, patient, automatic_emergency, enabled, stages
        FROM cm_ems_mission_definitions WHERE enabled = 1 ORDER BY label]]) or {}
    for _, row in ipairs(rows) do
        local stages = decode(row.stages)
        if type(stages) == 'table' and #stages > 0 then
            CustomDefinitions[#CustomDefinitions + 1] = {
                databaseId = tonumber(row.id), id = tostring(row.mission_key),
                label = tostring(row.label), category = tostring(row.category),
                description = tostring(row.description), reward = tonumber(row.reward) or 0,
                xp = tonumber(row.xp) or 0, timeLimitSeconds = tonumber(row.time_limit_seconds),
                automaticEmergency = dbBoolean(row.automatic_emergency),
                custom = true, routes = { { patient = dbBoolean(row.patient), stages = stages } },
            }
        end
    end
end

local function definitions()
    local rows = {}
    for _, definition in ipairs(((Config.EMSMissions or {}).definitions) or {}) do rows[#rows + 1] = definition end
    for _, definition in ipairs(CustomDefinitions) do rows[#rows + 1] = definition end
    return rows
end

local function findDefinition(missionId)
    for _, definition in ipairs(definitions()) do
        if tostring(definition.id) == tostring(missionId) then return definition end
    end
end

local function participantCount(active)
    local count = 0
    for _ in pairs(active.participants or {}) do count = count + 1 end
    return count
end

local function publicParticipants(active)
    local rows = {}
    for characterId, item in pairs(active.participants or {}) do
        rows[#rows + 1] = {
            characterId = characterId, name = nameFor(characterId), role = item.role,
            contributedStages = tonumber(item.contributedStages) or 0,
        }
    end
    table.sort(rows, function(a, b)
        if a.role ~= b.role then return a.role == 'leader' end
        return tostring(a.name) < tostring(b.name)
    end)
    return rows
end

local function missionCondition(active)
    local fixed = {
        cardiac_arrest = 'cardiac_arrest', overdose_response = 'overdose',
        urgent_medicine = 'breathing_difficulty', hospital_transfer = 'stable_transport',
        water_rescue = 'cardiac_arrest',
    }
    if fixed[tostring(active and active.missionId)] then return fixed[tostring(active.missionId)] end
    local options = { 'unconscious', 'bleeding', 'breathing_difficulty', 'stable_transport' }
    return options[((tonumber(active and active.runId) or 1) % #options) + 1]
end

local function publicMission(active, viewerCid)
    if not active then return nil end
    local stage = active.route.stages[active.stageIndex]
    local participant = active.participants and active.participants[tostring(viewerCid)]
    return {
        runId = active.runId, missionId = active.missionId, label = active.label,
        category = active.category, description = active.description,
        reward = active.reward, xp = active.xp, stageIndex = active.stageIndex,
        stageCount = #active.route.stages, stage = stage, route = active.route,
        startedAt = active.startedAt, expiresAt = active.expiresAt,
        condition = missionCondition(active),
        publicIncidentId = active.publicIncidentId, participants = publicParticipants(active),
        participantCount = participantCount(active), maximumMedics = math.max(1, tonumber(((Config.EMSMissions or {}).coOp or {}).maximumMedics) or 6),
        isLeader = participant and participant.role == 'leader' or false,
        contributedStages = participant and participant.contributedStages or 0,
    }
end

local function activeFor(characterId)
    local runId = PlayerRuns[tostring(characterId)]
    return runId and ActiveRuns[runId] or nil
end

local function clearStageAction(active)
    if not active then return end
    active.actionToken = nil
    active.actionStartedAt = nil
    active.actionCharacterId = nil
end

local function stageActionExpired(active)
    if not active or not active.actionToken then return false end
    local stage = active.route and active.route.stages and active.route.stages[active.stageIndex] or nil
    local duration = math.max(0, math.floor(tonumber(stage and stage.duration) or 0))
    local grace = math.max(5000, math.floor(tonumber((Config.EMSMissions or {}).actionLockGraceMs) or 15000))
    local startedAt = tonumber(active.actionStartedAt) or 0
    return startedAt <= 0 or (GetGameTimer() - startedAt) > (duration + grace)
end

local function sendMission(active, eventName, reason, skipSource)
    for characterId, participant in pairs(active.participants or {}) do
        local src = tonumber(participant.source)
        if src and GetPlayerName(src) and src ~= tonumber(skipSource) then
            if eventName == 'cm-ems:client:missionEnded' then
                TriggerClientEvent(eventName, src, active.runId, reason)
            else
                TriggerClientEvent(eventName, src, publicMission(active, characterId))
            end
        end
    end
end

local function distanceToStage(src, stage)
    local ped = GetPlayerPed(tonumber(src))
    local coords = stage and stage.coords
    if not ped or ped == 0 or type(coords) ~= 'table' then return math.huge end
    return #(GetEntityCoords(ped) - vector3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0))
end

local function distanceBetweenPlayers(first, second)
    local firstPed, secondPed = GetPlayerPed(tonumber(first)), GetPlayerPed(tonumber(second))
    if not firstPed or firstPed == 0 or not secondPed or secondPed == 0 then return math.huge end
    return #(GetEntityCoords(firstPed) - GetEntityCoords(secondPed))
end

local function isAuthorizedTransportVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local fleet = Entity(vehicle).state.cmEmsFleet
    -- cmEmsFleet is replicated only by cm-ems's server-owned fleet spawn
    -- path, so custom catalog ambulances remain authoritative without
    -- trusting a client-supplied model or plate.
    if type(fleet) == 'table' and fleet.placement ~= true and fleet.model then return true end
    local model = GetEntityModel(vehicle)
    for _, allowed in ipairs((Config.EMSMissions or {}).allowedTransportVehicles or { 'ambulance', 'polmav' }) do
        if model == joaat(tostring(allowed)) then return true end
    end
    return false
end

local function transportVehicleForStage(src, stageType)
    local ped = GetPlayerPed(tonumber(src))
    if not ped or ped == 0 then return nil end
    local occupied = GetVehiclePedIsIn(ped, false)
    if stageType == 'transport' then
        -- A co-op medic may be driver or passenger.
        return isAuthorizedTransportVehicle(occupied) and occupied or nil
    end
    if occupied and occupied ~= 0 then return nil end
    local playerCoords = GetEntityCoords(ped)
    local closest, closestDistance
    for _, vehicle in ipairs(GetAllVehicles()) do
        if isAuthorizedTransportVehicle(vehicle) then
            local distance = #(playerCoords - GetEntityCoords(vehicle))
            if distance <= 12.0 and (not closestDistance or distance < closestDistance) then
                closest, closestDistance = vehicle, distance
            end
        end
    end
    return closest
end

local function validateStage(src, active)
    local stage = active and active.route.stages[active.stageIndex]
    if not stage then return false, 'Mission stage is unavailable.' end
    local radius = math.max(3.0, tonumber(stage.radius) or tonumber((Config.EMSMissions or {}).stageRadius) or 18.0)
    if distanceToStage(src, stage) > radius then return false, 'Move closer to the mission objective.' end
    local ped = GetPlayerPed(tonumber(src))
    local occupied = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if (stage.type == 'treat' or stage.type == 'recover' or stage.type == 'pickup_patient'
        or stage.type == 'escort_patient' or stage.type == 'unload_patient' or stage.type == 'deliver_patient'
        or stage.type == 'hospital_handoff') and occupied ~= 0 then
        return false, 'Exit the vehicle and move beside the patient before providing care.'
    end
    if stage.type == 'board_vehicle' and not transportVehicleForStage(src, 'board_vehicle') then
        return false, occupied ~= 0
            and 'Exit the vehicle and stand beside the patient to load them.'
            or 'Park an authorized EMS vehicle nearby before loading the patient.'
    end
    if stage.requireTransportVehicle == true and stage.type ~= 'board_vehicle'
        and not transportVehicleForStage(src, 'transport') then
        return false, 'You must be inside an authorized EMS ambulance or helicopter.'
    end
    if stage.type == 'unload_patient' and not transportVehicleForStage(src, 'board_vehicle') then
        return false, 'Exit beside the authorized EMS vehicle to unload the patient.'
    end
    if stage.type == 'hospital_handoff' and not transportVehicleForStage(src, 'board_vehicle') then
        return false, 'Exit beside the authorized EMS vehicle in the ambulance bay.'
    end
    return true, nil, stage
end

local function deleteParticipant(active, characterId, reason)
    characterId = tostring(characterId)
    local participant = active.participants[characterId]
    if not participant then return end
    active.participants[characterId] = nil
    PlayerRuns[characterId] = nil
    if active.actionCharacterId == characterId then clearStageAction(active) end
    MySQL.update.await('DELETE FROM cm_ems_mission_participants WHERE run_id = ? AND character_id = ?', { active.runId, characterId })
    if participant.source and GetPlayerName(participant.source) then
        TriggerClientEvent('cm-ems:client:missionEnded', participant.source, active.runId, reason or 'You left the EMS mission.')
    end
end

local function cancelRun(active, status, reason)
    if not active or not ActiveRuns[active.runId] then return end
    status = status == 'failed' and 'failed' or 'cancelled'
    ActiveRuns[active.runId] = nil
    MySQL.update.await([[UPDATE cm_ems_mission_runs SET status = ?, completed_at = CURRENT_TIMESTAMP
        WHERE id = ? AND status = 'active']], { status, active.runId })
    if active.publicIncidentId then
        MySQL.update.await([[UPDATE cm_ems_public_incidents SET status = 'cancelled', completed_at = CURRENT_TIMESTAMP
            WHERE id = ? AND status = 'assigned']], { active.publicIncidentId })
    end
    for characterId in pairs(active.participants or {}) do PlayerRuns[characterId] = nil end
    sendMission(active, 'cm-ems:client:missionEnded', reason or 'Mission cancelled.')
    log(active.leaderCid, 'ems_mission_cancelled', { runId = active.runId, missionId = active.missionId, reason = reason })
end

local function openRunsFor(characterId)
    local rows = {}
    local maximum = math.max(1, tonumber(((Config.EMSMissions or {}).coOp or {}).maximumMedics) or 6)
    for _, active in pairs(ActiveRuns) do
        if not active.participants[tostring(characterId)] and participantCount(active) < maximum then
            local leader = active.participants[active.leaderCid]
            rows[#rows + 1] = {
                runId = active.runId, label = active.label, category = active.category,
                leaderName = nameFor(active.leaderCid), participantCount = participantCount(active),
                maximumMedics = maximum, stageIndex = active.stageIndex, stageCount = #active.route.stages,
                leaderSource = leader and leader.source or nil,
            }
        end
    end
    table.sort(rows, function(a, b) return a.runId > b.runId end)
    return rows
end

local function publicCalls()
    local rows = MySQL.query.await([[SELECT id, mission_id, label, category, description, reward, xp,
        UNIX_TIMESTAMP(created_at) AS created_at, UNIX_TIMESTAMP(expires_at) AS expires_at
        FROM cm_ems_public_incidents WHERE status = 'open' AND expires_at > CURRENT_TIMESTAMP ORDER BY id]]) or {}
    for _, row in ipairs(rows) do
        row.id, row.reward, row.xp = tonumber(row.id), tonumber(row.reward) or 0, tonumber(row.xp) or 0
        row.createdAt, row.expiresAt = tonumber(row.created_at), tonumber(row.expires_at)
        row.missionId, row.created_at, row.expires_at = tostring(row.mission_id), nil, nil
        row.mission_id = nil
    end
    return rows
end

local function missionBoard(characterId)
    local cooldown = math.max(0, math.floor(tonumber((Config.EMSMissions or {}).cooldownSeconds) or 900))
    local rows = MySQL.query.await([[SELECT r.mission_id, UNIX_TIMESTAMP(MAX(r.completed_at)) AS completed_at
        FROM cm_ems_mission_runs r
        LEFT JOIN cm_ems_mission_participants p ON p.run_id = r.id AND p.character_id = ?
        WHERE (p.character_id IS NOT NULL OR r.character_id = ?) AND r.status = 'completed'
        GROUP BY r.mission_id]], { tostring(characterId), tostring(characterId) }) or {}
    local lastCompleted = {}
    for _, row in ipairs(rows) do lastCompleted[tostring(row.mission_id)] = tonumber(row.completed_at) or 0 end
    local missions = {}
    for _, definition in ipairs(definitions()) do
        local remaining = math.max(0, (lastCompleted[tostring(definition.id)] or 0) + cooldown - os.time())
        missions[#missions + 1] = {
            id = tostring(definition.id), label = tostring(definition.label or definition.id),
            category = tostring(definition.category or 'EMS'), description = tostring(definition.description or ''),
            reward = math.max(0, math.floor(tonumber(definition.reward) or 0)),
            xp = math.max(0, math.floor(tonumber(definition.xp) or 0)), cooldownRemaining = remaining,
            stageCount = type(definition.routes) == 'table' and type(definition.routes[1]) == 'table'
                and #(definition.routes[1].stages or {}) or 0, custom = definition.custom == true,
        }
    end
    return {
        missions = missions, active = publicMission(activeFor(characterId), characterId),
        openCrews = openRunsFor(characterId), publicCalls = publicCalls(),
        coOpEnabled = ((Config.EMSMissions or {}).coOp or {}).enabled ~= false,
    }
end

local function buildRun(src, characterId, definition, route, publicIncidentId)
    local reward = math.max(0, math.floor(tonumber(definition.reward) or 0))
    local xp = math.max(0, math.floor(tonumber(definition.xp) or 0))
    local expiresAt = definition.timeLimitSeconds and (os.time() + math.max(60, tonumber(definition.timeLimitSeconds) or 600)) or nil
    local runId = tonumber(MySQL.insert.await([[INSERT INTO cm_ems_mission_runs
        (character_id, mission_id, status, route, reward, xp, stage_index, expires_at)
        VALUES (?, ?, 'active', ?, ?, ?, 1, IF(? > 0, FROM_UNIXTIME(?), NULL))]],
        { characterId, tostring(definition.id), json.encode(route), reward, xp, expiresAt or 0, expiresAt or 0 }))
    if not runId then return nil, 'The mission could not be created.' end
    MySQL.insert.await([[INSERT INTO cm_ems_mission_participants
        (run_id, character_id, role) VALUES (?, ?, 'leader')]], { runId, characterId })
    local active = {
        runId = runId, leaderCid = characterId, missionId = tostring(definition.id),
        label = tostring(definition.label or definition.id), category = tostring(definition.category or 'EMS'),
        description = tostring(definition.description or ''), route = route, reward = reward, xp = xp,
        stageIndex = 1, startedAt = os.time(), publicIncidentId = publicIncidentId,
        expiresAt = expiresAt,
        participants = { [characterId] = { source = tonumber(src), role = 'leader', contributedStages = 0 } },
    }
    ActiveRuns[runId], PlayerRuns[characterId] = active, runId
    log(characterId, 'ems_mission_started', { runId = runId, missionId = active.missionId, publicIncidentId = publicIncidentId })
    return active
end

lib.callback.register('cm-ems:server:missionBoard', function(src)
    local member, characterId = missionMember(src)
    if not member or not characterId then return nil, 'You must be a conscious, on-duty EMS employee.' end
    return missionBoard(characterId)
end)

lib.callback.register('cm-ems:server:startMission', function(src, missionId)
    if not rateLimit(src, 'start_ems_mission', 1200) then return false, 'Please wait.' end
    local member, characterId = missionMember(src)
    if not member or not characterId then return false, 'You must be a conscious, on-duty EMS employee.' end
    if activeFor(characterId) then return false, 'Finish or leave your active EMS mission first.' end
    local definition = findDefinition(missionId)
    if not definition or type(definition.routes) ~= 'table' or #definition.routes == 0 then return false, 'That mission is unavailable.' end
    local retrySeconds = math.max(0, math.floor(tonumber((Config.EMSMissions or {}).cancelledRetrySeconds) or 60))
    local interrupted = tonumber(MySQL.scalar.await([[SELECT UNIX_TIMESTAMP(MAX(started_at)) FROM cm_ems_mission_runs
        WHERE character_id = ? AND status IN ('cancelled','failed')]], { characterId })) or 0
    if interrupted + retrySeconds > os.time() then
        return false, ('Wait %d second(s) before starting another mission.'):format(interrupted + retrySeconds - os.time())
    end
    local cooldown = math.max(0, math.floor(tonumber((Config.EMSMissions or {}).cooldownSeconds) or 900))
    local last = tonumber(MySQL.scalar.await([[SELECT UNIX_TIMESTAMP(MAX(r.completed_at))
        FROM cm_ems_mission_runs r
        LEFT JOIN cm_ems_mission_participants p ON p.run_id = r.id AND p.character_id = ?
        WHERE (p.character_id IS NOT NULL OR r.character_id = ?) AND r.mission_id = ? AND r.status = 'completed']],
        { characterId, characterId, tostring(definition.id) })) or 0
    local remaining = math.max(0, last + cooldown - os.time())
    if remaining > 0 then return false, ('That mission is available again in %d minute(s).'):format(math.ceil(remaining / 60)) end
    local route = copy(definition.routes[math.random(1, #definition.routes)])
    if not route or type(route.stages) ~= 'table' or #route.stages == 0 then return false, 'That mission route is invalid.' end
    local active, reason = buildRun(src, characterId, definition, route)
    if not active then return false, reason end
    return true, ('Mission started: %s'):format(active.label), publicMission(active, characterId), missionBoard(characterId)
end)

lib.callback.register('cm-ems:server:acceptPublicIncident', function(src, incidentId)
    if not rateLimit(src, 'accept_public_ems_incident', 1200) then return false, 'Please wait.' end
    local member, characterId = missionMember(src)
    if not member or not characterId then return false, 'You must be a conscious, on-duty EMS employee.' end
    if activeFor(characterId) then return false, 'Finish or leave your active EMS mission first.' end
    incidentId = tonumber(incidentId)
    local incident = incidentId and MySQL.single.await([[SELECT id, mission_id, label, category, description,
        route, reward, xp, time_limit_seconds FROM cm_ems_public_incidents
        WHERE id = ? AND status = 'open' AND expires_at > CURRENT_TIMESTAMP LIMIT 1]], { incidentId })
    if not incident then return false, 'That public emergency is no longer available.' end
    local route = decode(incident.route)
    if type(route) ~= 'table' or type(route.stages) ~= 'table' or #route.stages == 0 then return false, 'That emergency route is invalid.' end
    local definition = {
        id = tostring(incident.mission_id), label = incident.label, category = incident.category,
        description = incident.description, reward = incident.reward, xp = incident.xp,
        timeLimitSeconds = incident.time_limit_seconds,
    }
    local active, reason = buildRun(src, characterId, definition, route, incidentId)
    if not active then return false, reason end
    local claimed = MySQL.update.await([[UPDATE cm_ems_public_incidents SET status = 'assigned',
        run_id = ?, assigned_at = CURRENT_TIMESTAMP WHERE id = ? AND status = 'open']], { active.runId, incidentId })
    if not claimed or tonumber(claimed) == 0 then cancelRun(active, 'cancelled', 'Another EMS crew accepted this call.'); return false, 'Another EMS crew accepted this call.' end
    return true, ('Emergency accepted: %s'):format(active.label), publicMission(active, characterId), missionBoard(characterId)
end)

lib.callback.register('cm-ems:server:joinMission', function(src, runId)
    if not rateLimit(src, 'join_ems_mission', 1200) then return false, 'Please wait.' end
    local member, characterId = missionMember(src)
    if not member or not characterId then return false, 'You must be a conscious, on-duty EMS employee.' end
    if activeFor(characterId) then return false, 'Finish or leave your active EMS mission first.' end
    if ((Config.EMSMissions or {}).coOp or {}).enabled == false then return false, 'Co-op missions are disabled.' end
    local active = ActiveRuns[tonumber(runId)]
    if not active then return false, 'That EMS crew is no longer active.' end
    if MySQL.scalar.await([[SELECT 1 FROM cm_ems_daily_mission WHERE run_id = ? AND status = 'assigned' LIMIT 1]], { active.runId }) then
        return false, 'That is a personal daily mission and cannot be joined.'
    end
    local maximum = math.max(1, tonumber(((Config.EMSMissions or {}).coOp or {}).maximumMedics) or 6)
    if participantCount(active) >= maximum then return false, 'That EMS crew is full.' end
    local leader = active.participants[active.leaderCid]
    local joinRadius = math.max(20.0, tonumber(((Config.EMSMissions or {}).coOp or {}).joinRadius) or 300.0)
    if not leader or distanceBetweenPlayers(src, leader.source) > joinRadius then
        return false, ('Move within %d metres of the mission leader to join.'):format(math.floor(joinRadius))
    end
    active.participants[characterId] = { source = tonumber(src), role = 'member', contributedStages = 0 }
    PlayerRuns[characterId] = active.runId
    MySQL.insert.await([[INSERT INTO cm_ems_mission_participants
        (run_id, character_id, role) VALUES (?, ?, 'member')]], { active.runId, characterId })
    sendMission(active, 'cm-ems:client:missionUpdated')
    log(characterId, 'ems_mission_joined', { runId = active.runId, missionId = active.missionId })
    return true, ('Joined %s with %s.'):format(active.label, nameFor(active.leaderCid)), publicMission(active, characterId), missionBoard(characterId)
end)

lib.callback.register('cm-ems:server:beginMissionStage', function(src, runId, stageIndex)
    if not rateLimit(src, 'begin_ems_mission_stage', 500) then return false, 'Please wait.' end
    local member, characterId = missionMember(src)
    local active = member and characterId and activeFor(characterId)
    if not active or tonumber(runId) ~= active.runId or tonumber(stageIndex) ~= active.stageIndex then return false, 'That mission objective is no longer active.' end
    if active.actionToken then
        if stageActionExpired(active) or not active.participants[tostring(active.actionCharacterId or '')] then
            clearStageAction(active)
        else
            return false, 'A teammate is already completing this objective.'
        end
    end
    if active.expiresAt and os.time() >= active.expiresAt then cancelRun(active, 'failed', 'The timed mission expired.'); return false, 'The mission expired.' end
    local valid, reason, stage = validateStage(src, active)
    if not valid then return false, reason end
    active.actionToken = ('%d:%d:%d'):format(active.runId, active.stageIndex, math.random(100000, 999999))
    active.actionStartedAt, active.actionCharacterId = GetGameTimer(), characterId
    return true, nil, { token = active.actionToken, duration = math.max(0, math.floor(tonumber(stage.duration) or 0)), stage = stage }
end)

local function rewardParticipants(active)
    local requireContribution = ((Config.EMSMissions or {}).coOp or {}).requireContributionForReward ~= false
    local rewarded = 0
    for characterId, participant in pairs(active.participants) do
        local eligible = not requireContribution or (tonumber(participant.contributedStages) or 0) > 0
        local src = tonumber(participant.source)
        if eligible and src and GetPlayerName(src) then
            local paid = active.reward == 0
            if active.reward > 0 then
                pcall(function() paid = exports[Config.PlayerDataResource]:AddMoney(src, 'bank', active.reward, 'ems_coop_mission_reward') == true end)
            end
            if paid then
                rewarded = rewarded + 1
                MySQL.update.await([[UPDATE cm_ems_mission_participants SET reward_paid = 1
                    WHERE run_id = ? AND character_id = ?]], { active.runId, characterId })
                if EMSAwardEmployeeXP then EMSAwardEmployeeXP(characterId, active.xp) end
                if EMSAddTaskProgress then EMSAddTaskProgress(characterId, 'missions_completed', 1, ('mission_run:%s:%s'):format(active.runId, characterId)) end
                missionNotify(src, ('Mission reward: $%d and %d EMS XP.'):format(active.reward, active.xp), 'success')
            else
                missionNotify(src, 'Mission completed, but your payment failed safely. Contact an administrator.', 'error')
            end
        elseif src and GetPlayerName(src) then
            missionNotify(src, 'Mission complete. No reward because you did not complete an objective.', 'inform')
        end
    end
    return rewarded
end

local function missionRating(active)
    local elapsed = math.max(1, os.time() - (tonumber(active.startedAt) or os.time()))
    local target
    if active.expiresAt and active.startedAt then
        target = math.max(60, tonumber(active.expiresAt) - tonumber(active.startedAt))
    else
        local actionSeconds = 0
        for _, stage in ipairs((active.route and active.route.stages) or {}) do
            actionSeconds = actionSeconds + (math.max(0, tonumber(stage.duration) or 0) / 1000)
        end
        target = math.max(180, actionSeconds + (#((active.route and active.route.stages) or {}) * 60))
    end
    local ratio = elapsed / target
    local grade = ratio <= 0.50 and 'S' or ratio <= 0.70 and 'A' or ratio <= 0.90 and 'B' or 'C'
    return { grade = grade, elapsedSeconds = elapsed, targetSeconds = math.floor(target) }
end

lib.callback.register('cm-ems:server:cancelMissionStage', function(src, runId, stageIndex, token)
    local member, characterId = missionMember(src)
    local active = member and characterId and activeFor(characterId)
    if not active or tonumber(runId) ~= active.runId then return false end
    if tonumber(stageIndex) ~= active.stageIndex or active.actionCharacterId ~= characterId
        or tostring(token or '') ~= tostring(active.actionToken or '') then return false end
    clearStageAction(active)
    return true
end)

lib.callback.register('cm-ems:server:completeMissionStage', function(src, runId, stageIndex, token)
    if not rateLimit(src, 'complete_ems_mission_stage', 500) then return false, 'Please wait.' end
    local member, characterId = missionMember(src)
    local active = member and characterId and activeFor(characterId)
    if not active or tonumber(runId) ~= active.runId then return false, 'That mission action is invalid.' end
    if tonumber(stageIndex) ~= active.stageIndex or tostring(token or '') ~= tostring(active.actionToken or '')
        or active.actionCharacterId ~= characterId then
        return false, 'That mission action is invalid.'
    end
    if stageActionExpired(active) then
        clearStageAction(active)
        return false, 'That mission action expired. Try the objective again.'
    end
    local valid, reason, stage = validateStage(src, active)
    if not valid then clearStageAction(active); return false, reason end
    local duration = math.max(0, math.floor(tonumber(stage.duration) or 0))
    if GetGameTimer() - (active.actionStartedAt or GetGameTimer()) < math.floor(duration * 0.85) then
        clearStageAction(active)
        return false, 'Mission action finished too quickly. Try again.'
    end
    local participant = active.participants[characterId]
    participant.contributedStages = (tonumber(participant.contributedStages) or 0) + 1
    MySQL.update.await([[UPDATE cm_ems_mission_participants SET contributed_stages = contributed_stages + 1
        WHERE run_id = ? AND character_id = ?]], { active.runId, characterId })
    active.stageIndex = active.stageIndex + 1
    MySQL.update.await('UPDATE cm_ems_mission_runs SET stage_index = ? WHERE id = ? AND status = ?', {
        active.stageIndex, active.runId, 'active',
    })
    clearStageAction(active)
    if active.stageIndex <= #active.route.stages then
        sendMission(active, 'cm-ems:client:missionUpdated', nil, src)
        return true, 'Objective complete. Your crew can continue to the next location.',
            publicMission(active, characterId), false, missionBoard(characterId)
    end
    local changed = MySQL.update.await([[UPDATE cm_ems_mission_runs SET status = 'completed', completed_at = CURRENT_TIMESTAMP
        WHERE id = ? AND status = 'active']], { active.runId })
    if not changed or tonumber(changed) == 0 then return false, 'The mission completion could not be confirmed.' end
    if active.publicIncidentId then
        MySQL.update.await([[UPDATE cm_ems_public_incidents SET status = 'completed', completed_at = CURRENT_TIMESTAMP
            WHERE id = ?]], { active.publicIncidentId })
    end
    local rewarded = rewardParticipants(active)
    -- Harmless no-op for a normal (non-daily) run: only matches a row when
    -- this run was assigned by the daily mission NPC.
    MySQL.update.await([[UPDATE cm_ems_daily_mission SET status = 'completed', completed_at = CURRENT_TIMESTAMP
        WHERE run_id = ? AND status = 'assigned']], { active.runId })
    local rating = missionRating(active)
    ActiveRuns[active.runId] = nil
    for participantCid in pairs(active.participants) do PlayerRuns[participantCid] = nil end
    local completionMessage = ('Mission complete · Grade %s · %dm %02ds · %d contributing medic(s) rewarded.'):format(
        rating.grade, math.floor(rating.elapsedSeconds / 60), rating.elapsedSeconds % 60, rewarded)
    sendMission(active, 'cm-ems:client:missionEnded', completionMessage)
    log(characterId, 'ems_mission_completed', {
        runId = active.runId, missionId = active.missionId, reward = active.reward,
        xp = active.xp, participants = participantCount(active), rewarded = rewarded,
        grade = rating.grade, elapsedSeconds = rating.elapsedSeconds, targetSeconds = rating.targetSeconds,
    })
    return true, completionMessage, nil, true, missionBoard(characterId)
end)

lib.callback.register('cm-ems:server:cancelMission', function(src)
    if not rateLimit(src, 'cancel_ems_mission', 1200) then return false, 'Please wait.' end
    local member, characterId = missionMember(src)
    local active = member and characterId and activeFor(characterId)
    if not active then return false, 'You do not have an active EMS mission.' end
    local participant = active.participants[characterId]
    if participant.role ~= 'leader' then
        deleteParticipant(active, characterId, 'You left the EMS crew.')
        sendMission(active, 'cm-ems:client:missionUpdated')
        log(characterId, 'ems_mission_left', { runId = active.runId, missionId = active.missionId })
        return true, 'You left the EMS crew.', missionBoard(characterId)
    end
    local replacementCid
    for otherCid in pairs(active.participants) do if otherCid ~= characterId then replacementCid = otherCid break end end
    if replacementCid then
        deleteParticipant(active, characterId, 'You left the EMS crew.')
        active.leaderCid = replacementCid
        active.participants[replacementCid].role = 'leader'
        MySQL.update.await([[UPDATE cm_ems_mission_participants SET role = 'leader'
            WHERE run_id = ? AND character_id = ?]], { active.runId, replacementCid })
        sendMission(active, 'cm-ems:client:missionUpdated')
        missionNotify(active.participants[replacementCid].source, 'You are now the EMS mission leader.', 'inform')
        return true, 'You left the mission; leadership transferred safely.', missionBoard(characterId)
    end
    cancelRun(active, 'cancelled', 'The mission leader cancelled the EMS mission.')
    return true, 'EMS mission cancelled.', missionBoard(characterId)
end)

-- ============================================================
--  Daily NPC mission -- one admin-placed dispatcher NPC hands out a
--  single high-reward mission per character per calendar day, reusing
--  definitions()/buildRun()/rewardParticipants() above so stage
--  execution, blips and payment are identical to a board-picked mission.
--  The daily cap is entirely DB-driven (cm_ems_daily_mission, keyed by
--  character_id + period_key) rather than an in-memory flag, so it stays
--  correct across resource restarts (see the two hooks above, in
--  joinMission and completeMissionStage).
-- ============================================================

local function todayKey() return os.date('%Y-%m-%d') end

local NpcLocation

function GetDailyMissionNpcStatus() return NpcLocation end

function SetDailyMissionNpcLocation(src, actor, payload)
    if not has(actor, 'ems.manage_missions') then return false, 'Your rank cannot set the daily mission NPC.' end
    payload = type(payload) == 'table' and payload or {}
    local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
    local heading = tonumber(payload.heading) or 0.0
    if not x or not y or not z or math.abs(x) > 10000.0 or math.abs(y) > 10000.0 or math.abs(z) > 2500.0 then
        return false, 'Invalid location.'
    end
    local ped = GetPlayerPed(src)
    if ped and ped > 0 then
        local serverCoords = GetEntityCoords(ped)
        if serverCoords and #(serverCoords - vector3(x, y, z)) > 25.0 then return false, 'Location mismatch.' end
    end
    NpcLocation = { x = x, y = y, z = z, heading = heading }
    local actorCid = cid(src)
    MySQL.insert.await([[INSERT INTO cm_ems_settings (setting_key, setting_value, updated_by)
        VALUES ('daily_mission_npc', ?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)]],
        { json.encode(NpcLocation), actorCid })
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent('cm-ems:client:dailyMissionNpcUpdated', tonumber(playerId), NpcLocation)
    end
    log(actorCid, 'daily_mission_npc_set', {})
    return true, 'Daily mission NPC location saved.'
end

lib.callback.register('cm-ems:server:dailyMissionNpcLocation', function(src) return NpcLocation end)

local function nearDailyMissionNpc(src)
    if not NpcLocation then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped <= 0 then return false end
    local coords = GetEntityCoords(ped)
    local distance = math.max(1.0, tonumber(((Config.EMSMissions or {}).dailyNpcMission or {}).interactDistance) or 2.5)
    return #(coords - vector3(NpcLocation.x, NpcLocation.y, NpcLocation.z)) <= distance
end

local function assignDailyMission(src, characterId, key, definition)
    local route = copy(definition.routes[math.random(1, #definition.routes)])
    if not route or type(route.stages) ~= 'table' or #route.stages == 0 then return false, 'That mission route is invalid.' end
    local multiplier = math.max(1, tonumber(((Config.EMSMissions or {}).dailyNpcMission or {}).rewardMultiplier) or 3)
    local boosted = copy(definition)
    boosted.reward = math.floor((tonumber(definition.reward) or 0) * multiplier)
    boosted.xp = math.floor((tonumber(definition.xp) or 0) * multiplier)
    local active, reason = buildRun(src, characterId, boosted, route)
    if not active then return false, reason end
    MySQL.insert.await([[INSERT INTO cm_ems_daily_mission (character_id, period_key, mission_id, run_id, reward, status)
        VALUES (?, ?, ?, ?, ?, 'assigned') ON DUPLICATE KEY UPDATE run_id = VALUES(run_id), reward = VALUES(reward)]],
        { characterId, key, active.missionId, active.runId, active.reward })
    log(characterId, 'ems_daily_mission_assigned', { runId = active.runId, missionId = active.missionId, reward = active.reward })
    return true, ('Daily mission assigned: %s'):format(active.label), publicMission(active, characterId)
end

lib.callback.register('cm-ems:server:requestDailyMission', function(src)
    if not rateLimit(src, 'request_ems_daily_mission', 1200) then return false, 'Please wait.' end
    local member, characterId = missionMember(src)
    if not member or not characterId then return false, 'You must be a conscious, on-duty EMS employee.' end
    if not nearDailyMissionNpc(src) then return false, 'Get closer to the dispatch coordinator.' end

    local key = todayKey()
    local row = MySQL.single.await('SELECT mission_id, run_id, status FROM cm_ems_daily_mission WHERE character_id = ? AND period_key = ?', { characterId, key })
    if row and row.status == 'completed' then
        return false, 'You already completed your daily mission. Come back tomorrow.'
    end
    if row and row.status == 'assigned' then
        local active = activeFor(characterId)
        if active and active.runId == tonumber(row.run_id) then
            return true, 'Continuing your daily mission.', publicMission(active, characterId)
        end
        if active then return false, 'Finish or leave your active EMS mission first.' end
        local definition = findDefinition(row.mission_id)
        if not definition then return false, 'Your assigned mission is no longer available. Contact an administrator.' end
        return assignDailyMission(src, characterId, key, definition)
    end

    if activeFor(characterId) then return false, 'Finish or leave your active EMS mission first.' end
    local pool = definitions()
    if #pool == 0 then return false, 'No missions are configured.' end
    local definition = pool[math.random(1, #pool)]
    if type(definition.routes) ~= 'table' or #definition.routes == 0 then return false, 'That mission is unavailable.' end
    return assignDailyMission(src, characterId, key, definition)
end)

local allowedStageTypes = {
    pickup = true, deliver = true, treat = true, recover = true,
    board_vehicle = true, transport = true, pickup_patient = true, repair = true,
    escort_patient = true, unload_patient = true, deliver_patient = true, hospital_handoff = true,
}

local function validateAdminMission(payload)
    payload = type(payload) == 'table' and payload or {}
    local stages = type(payload.stages) == 'table' and payload.stages or {}
    if #stages < 1 or #stages > 12 then return nil, 'Add between 1 and 12 mission stages.' end
    local cleanedStages = {}
    for index, stage in ipairs(stages) do
        local stageType = tostring(stage.type or '')
        if not allowedStageTypes[stageType] then return nil, ('Stage %d has an invalid type.'):format(index) end
        local x, y, z = tonumber(stage.x or stage.coords and stage.coords.x), tonumber(stage.y or stage.coords and stage.coords.y), tonumber(stage.z or stage.coords and stage.coords.z)
        if not x or not y or not z or math.abs(x) > 10000 or math.abs(y) > 10000 or z < -300 or z > 2000 then
            return nil, ('Stage %d needs valid coordinates.'):format(index)
        end
        cleanedStages[#cleanedStages + 1] = {
            type = stageType, label = cleanText(stage.label, 96, ('Complete stage %d'):format(index)),
            location = cleanText(stage.location, 96, 'Mission location'),
            coords = { x = x, y = y, z = z },
            duration = math.max(0, math.min(60000, math.floor(tonumber(stage.duration) or 5000))),
            radius = math.max(3.0, math.min(50.0, tonumber(stage.radius) or 18.0)),
            requireTransportVehicle = stage.requireTransportVehicle == true,
            spawnVehicle = stageType == 'repair' and cleanText(stage.spawnVehicle, 48, 'ambulance') or nil,
            vehicleHeading = stageType == 'repair' and tonumber(stage.vehicleHeading) or nil,
            heading = stageType == 'deliver_patient' and tonumber(stage.heading or stage.vehicleHeading) or nil,
        }
    end
    local label = cleanText(payload.label, 64)
    if #label < 3 then return nil, 'Mission name must be at least 3 characters.' end
    return {
        databaseId = tonumber(payload.databaseId), label = label,
        category = cleanText(payload.category, 32, 'EMS'), description = cleanText(payload.description, 255, 'EMS response mission.'),
        reward = math.max(0, math.min(100000, math.floor(tonumber(payload.reward) or 0))),
        xp = math.max(0, math.min(10000, math.floor(tonumber(payload.xp) or 0))),
        timeLimitSeconds = math.max(0, math.min(7200, math.floor(tonumber(payload.timeLimitSeconds) or 0))),
        patient = payload.patient == true, automaticEmergency = payload.automaticEmergency == true,
        enabled = payload.enabled ~= false, stages = cleanedStages,
    }
end

lib.callback.register('cm-ems:server:missionAdminList', function(src)
    if not isAdmin(src) then return nil, 'You do not have EMS administration permission.' end
    local rows = MySQL.query.await([[SELECT id, mission_key, label, category, description, reward, xp,
        time_limit_seconds, patient, automatic_emergency, enabled, stages, updated_at
        FROM cm_ems_mission_definitions ORDER BY label]]) or {}
    for _, row in ipairs(rows) do
        row.databaseId, row.missionKey = tonumber(row.id), tostring(row.mission_key)
        row.reward, row.xp, row.timeLimitSeconds = tonumber(row.reward) or 0, tonumber(row.xp) or 0, tonumber(row.time_limit_seconds) or 0
        row.patient, row.automaticEmergency, row.enabled = dbBoolean(row.patient), dbBoolean(row.automatic_emergency), dbBoolean(row.enabled)
        row.stages, row.updatedAt = decode(row.stages), tostring(row.updated_at or '')
        row.id, row.mission_key, row.time_limit_seconds, row.automatic_emergency, row.updated_at = nil, nil, nil, nil, nil
    end
    return rows
end)

lib.callback.register('cm-ems:server:saveAdminMission', function(src, payload)
    if not isAdmin(src) then return false, 'You do not have EMS administration permission.' end
    if not rateLimit(src, 'save_ems_admin_mission', 1200) then return false, 'Please wait.' end
    local mission, reason = validateAdminMission(payload)
    if not mission then return false, reason end
    local actorCid = cid(src)
    if mission.databaseId then
        local changed = MySQL.update.await([[UPDATE cm_ems_mission_definitions SET label = ?, category = ?,
            description = ?, reward = ?, xp = ?, time_limit_seconds = ?, patient = ?, automatic_emergency = ?,
            enabled = ?, stages = ?, updated_by = ? WHERE id = ?]], {
            mission.label, mission.category, mission.description, mission.reward, mission.xp,
            mission.timeLimitSeconds > 0 and mission.timeLimitSeconds or false, mission.patient and 1 or 0,
            mission.automaticEmergency and 1 or 0, mission.enabled and 1 or 0, json.encode(mission.stages),
            actorCid, mission.databaseId,
        })
        if not changed or tonumber(changed) == 0 then return false, 'Custom mission was not found.' end
    else
        local missionKey = ('custom_%d_%d'):format(os.time(), math.random(1000, 9999))
        mission.databaseId = tonumber(MySQL.insert.await([[INSERT INTO cm_ems_mission_definitions
            (mission_key, label, category, description, reward, xp, time_limit_seconds, patient,
             automatic_emergency, enabled, stages, created_by, updated_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            missionKey, mission.label, mission.category, mission.description, mission.reward, mission.xp,
            mission.timeLimitSeconds > 0 and mission.timeLimitSeconds or false, mission.patient and 1 or 0,
            mission.automaticEmergency and 1 or 0, mission.enabled and 1 or 0, json.encode(mission.stages),
            actorCid, actorCid,
        }))
        if not mission.databaseId then return false, 'Custom mission could not be saved.' end
    end
    loadCustomDefinitions()
    log(actorCid, 'ems_mission_definition_saved', { databaseId = mission.databaseId, label = mission.label })
    return true, 'EMS mission saved and available immediately.'
end)

lib.callback.register('cm-ems:server:deleteAdminMission', function(src, databaseId)
    if not isAdmin(src) then return false, 'You do not have EMS administration permission.' end
    if not rateLimit(src, 'delete_ems_admin_mission', 1200) then return false, 'Please wait.' end
    databaseId = tonumber(databaseId)
    if not databaseId then return false, 'Custom mission was not found.' end
    local changed = MySQL.update.await('DELETE FROM cm_ems_mission_definitions WHERE id = ?', { databaseId })
    if not changed or tonumber(changed) == 0 then return false, 'Custom mission was not found.' end
    loadCustomDefinitions()
    log(cid(src), 'ems_mission_definition_deleted', { databaseId = databaseId })
    return true, 'Custom EMS mission deleted.'
end)

local function onDutySources()
    local rows = {}
    for _, player in ipairs(GetPlayers()) do
        local member = missionMember(player)
        if member then rows[#rows + 1] = tonumber(player) end
    end
    return rows
end

local function generatePublicIncident()
    local settings = ((Config.EMSMissions or {}).automaticEmergencies) or {}
    if settings.enabled == false then return end
    local sources = onDutySources()
    if settings.requireOnDutyEMS ~= false and #sources == 0 then return end
    local openCount = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM cm_ems_public_incidents
        WHERE status = 'open' AND expires_at > CURRENT_TIMESTAMP]])) or 0
    if openCount >= math.max(1, tonumber(settings.maximumOpenCalls) or 3) then return end
    local eligible = {}
    for _, definition in ipairs(definitions()) do
        if definition.automaticEmergency == true and type(definition.routes) == 'table' and #definition.routes > 0 then
            eligible[#eligible + 1] = definition
        end
    end
    if #eligible == 0 then return end
    local definition = eligible[math.random(1, #eligible)]
    local route = copy(definition.routes[math.random(1, #definition.routes)])
    if not route or type(route.stages) ~= 'table' or #route.stages == 0 then return end
    local lifetime = math.max(120, tonumber(settings.lifetimeSeconds) or 1200)
    local incidentId = tonumber(MySQL.insert.await([[INSERT INTO cm_ems_public_incidents
        (mission_id, label, category, description, route, reward, xp, time_limit_seconds, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND))]], {
        tostring(definition.id), tostring(definition.label), tostring(definition.category or 'EMS'),
        tostring(definition.description or ''), json.encode(route), math.max(0, tonumber(definition.reward) or 0),
        math.max(0, tonumber(definition.xp) or 0), definition.timeLimitSeconds or false, lifetime,
    }))
    if not incidentId then return end
    local firstStage = route.stages[1] or {}
    for _, src in ipairs(sources) do
        TriggerClientEvent('cm-ems:client:npcEmergency', src, {
            id = incidentId, label = definition.label, category = definition.category,
            location = firstStage.location or firstStage.label, expiresAt = os.time() + lifetime,
            notificationSeconds = tonumber(settings.notificationSeconds) or 20,
        })
    end
    log(nil, 'ems_public_emergency_created', { incidentId = incidentId, missionId = definition.id })
end

AddEventHandler('playerDropped', function()
    local characterId = cid(source)
    local active = characterId and activeFor(tostring(characterId))
    if not active then return end
    if active.participants[tostring(characterId)].role == 'leader' and participantCount(active) == 1 then
        cancelRun(active, 'cancelled', 'Mission cancelled because the only medic disconnected.')
    else
        deleteParticipant(active, tostring(characterId), 'You left the EMS mission.')
        if active.leaderCid == tostring(characterId) then
            for replacementCid, participant in pairs(active.participants) do
                active.leaderCid, participant.role = replacementCid, 'leader'
                MySQL.update.await([[UPDATE cm_ems_mission_participants SET role = 'leader'
                    WHERE run_id = ? AND character_id = ?]], { active.runId, replacementCid })
                break
            end
        end
        sendMission(active, 'cm-ems:client:missionUpdated')
    end
end)

AddEventHandler('cm-ems:server:memberWentOffDuty', function(_, characterId, reason)
    characterId = tostring(characterId or '')
    local active = characterId ~= '' and activeFor(characterId)
    if not active or not active.participants[characterId] then return end
    local message = reason == 'incapacitated'
        and 'You were removed from the EMS mission after becoming incapacitated.'
        or 'You left EMS duty and were removed from the mission.'
    if active.leaderCid == characterId and participantCount(active) == 1 then
        cancelRun(active, 'cancelled', 'EMS mission cancelled because no on-duty crew remained.')
        return
    end
    deleteParticipant(active, characterId, message)
    if active.leaderCid == characterId then
        for replacementCid, participant in pairs(active.participants) do
            active.leaderCid, participant.role = replacementCid, 'leader'
            MySQL.update.await([[UPDATE cm_ems_mission_participants SET role = 'leader'
                WHERE run_id = ? AND character_id = ?]], { active.runId, replacementCid })
            missionNotify(participant.source, 'You are now the EMS mission leader.', 'inform')
            break
        end
    end
    sendMission(active, 'cm-ems:client:missionUpdated')
end)

CreateThread(function()
    while not (EMSIsReady and EMSIsReady()) do Wait(500) end
    pcall(function() MySQL.query.await('ALTER TABLE cm_ems_mission_runs ADD COLUMN stage_index INT UNSIGNED NOT NULL DEFAULT 1') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_ems_mission_runs ADD COLUMN expires_at DATETIME NULL') end)
    loadCustomDefinitions()
    do
        local settingRow = MySQL.single.await([[SELECT setting_value FROM cm_ems_settings WHERE setting_key = 'daily_mission_npc']])
        if settingRow then
            local decoded = decode(settingRow.setting_value)
            if type(decoded) == 'table' and decoded.x then NpcLocation = decoded end
        end
    end
    local rows = MySQL.query.await([[SELECT r.id, r.character_id, r.mission_id, r.route, r.reward, r.xp,
            r.stage_index, UNIX_TIMESTAMP(r.started_at) AS started_at, UNIX_TIMESTAMP(r.expires_at) AS expires_at,
            p.id AS public_incident_id
        FROM cm_ems_mission_runs r
        LEFT JOIN cm_ems_public_incidents p ON p.run_id = r.id AND p.status = 'assigned'
        WHERE r.status = 'active']]) or {}
    for _, row in ipairs(rows) do
        local route, definition = decode(row.route), findDefinition(row.mission_id)
        local stageIndex, expiresAt = math.max(1, tonumber(row.stage_index) or 1), tonumber(row.expires_at)
        if type(route) ~= 'table' or type(route.stages) ~= 'table' or stageIndex > #route.stages
            or (expiresAt and os.time() >= expiresAt) then
            MySQL.update.await([[UPDATE cm_ems_mission_runs SET status = 'failed', completed_at = CURRENT_TIMESTAMP
                WHERE id = ? AND status = 'active']], { row.id })
        else
            local participants = {}
            local participantRows = MySQL.query.await([[SELECT character_id, role, contributed_stages
                FROM cm_ems_mission_participants WHERE run_id = ?]], { row.id }) or {}
            for _, participant in ipairs(participantRows) do
                local participantCid = tostring(participant.character_id)
                local participantSrc = sourceFor(participantCid)
                local member = memberFor(participantCid)
                if member and dbBoolean(member.on_duty) and not dbBoolean(member.is_suspended) then
                    participants[participantCid] = {
                        source = participantSrc and tonumber(participantSrc) or nil, role = tostring(participant.role),
                        contributedStages = tonumber(participant.contributed_stages) or 0,
                    }
                    PlayerRuns[participantCid] = tonumber(row.id)
                end
            end
            if next(participants) then
                local leaderCid = tostring(row.character_id)
                if not participants[leaderCid] then
                    leaderCid = next(participants)
                    participants[leaderCid].role = 'leader'
                    MySQL.update.await([[UPDATE cm_ems_mission_participants SET role = 'leader'
                        WHERE run_id = ? AND character_id = ?]], { row.id, leaderCid })
                end
                ActiveRuns[tonumber(row.id)] = {
                    runId = tonumber(row.id), leaderCid = leaderCid, missionId = tostring(row.mission_id),
                    label = tostring(definition and definition.label or row.mission_id),
                    category = tostring(definition and definition.category or 'EMS'),
                    description = tostring(definition and definition.description or ''),
                    route = route, reward = tonumber(row.reward) or 0, xp = tonumber(row.xp) or 0,
                    stageIndex = stageIndex, startedAt = tonumber(row.started_at) or os.time(),
                    expiresAt = expiresAt, publicIncidentId = tonumber(row.public_incident_id),
                    participants = participants, restoredUntil = os.time() + 120,
                }
                sendMission(ActiveRuns[tonumber(row.id)], 'cm-ems:client:missionUpdated')
            end
        end
    end
    MySQL.update.await([[UPDATE cm_ems_public_incidents SET status = 'expired'
        WHERE status = 'open' AND expires_at <= CURRENT_TIMESTAMP]])
    while true do
        local settings = ((Config.EMSMissions or {}).automaticEmergencies) or {}
        local minimum = math.max(60, tonumber(settings.minimumIntervalSeconds) or 480)
        local maximum = math.max(minimum, tonumber(settings.maximumIntervalSeconds) or 900)
        Wait(math.random(minimum, maximum) * 1000)
        MySQL.update.await([[UPDATE cm_ems_public_incidents SET status = 'expired'
            WHERE status = 'open' AND expires_at <= CURRENT_TIMESTAMP]])
        generatePublicIncident()
    end
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    CreateThread(function()
        Wait(750)
        local characterId = cid(src)
        local active = characterId and activeFor(tostring(characterId))
        if not active or not active.participants[tostring(characterId)] then return end
        active.participants[tostring(characterId)].source = tonumber(src)
        TriggerClientEvent('cm-ems:client:missionUpdated', tonumber(src), publicMission(active, tostring(characterId)))
    end)
end)

CreateThread(function()
    while true do
        Wait(10000)
        for _, active in pairs(ActiveRuns) do
            if active.actionToken and (stageActionExpired(active)
                or not active.participants[tostring(active.actionCharacterId or '')]) then
                clearStageAction(active)
            end
            local removals = {}
            for characterId, participant in pairs(active.participants) do
                if participant.source or os.time() >= (tonumber(active.restoredUntil) or 0) then
                    local currentMember, currentCid = missionMember(participant.source)
                    if not currentMember or tostring(currentCid or '') ~= characterId then removals[#removals + 1] = characterId end
                end
            end
            for _, characterId in ipairs(removals) do deleteParticipant(active, characterId, 'You left EMS duty or became unconscious.') end
            if participantCount(active) == 0 then
                cancelRun(active, 'cancelled', 'Mission cancelled because no EMS crew remained.')
            elseif not active.participants[active.leaderCid] then
                for replacementCid, participant in pairs(active.participants) do
                    active.leaderCid, participant.role = replacementCid, 'leader'
                    MySQL.update.await([[UPDATE cm_ems_mission_participants SET role = 'leader'
                        WHERE run_id = ? AND character_id = ?]], { active.runId, replacementCid })
                    break
                end
                sendMission(active, 'cm-ems:client:missionUpdated')
            elseif active.expiresAt and os.time() >= active.expiresAt then
                cancelRun(active, 'failed', 'The timed EMS mission expired.')
            end
        end
    end
end)
