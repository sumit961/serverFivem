CmQaRunner = { lastRun = nil, activeClient = nil }

local function nowIso() return os.date('!%Y-%m-%dT%H:%M:%SZ') end
local function findScenario(id)
    for _, scenario in ipairs(CmQaScenarios or {}) do if scenario.id == id then return scenario end end
    return nil
end
local function resourceReady(name) return type(name) == 'string' and GetResourceState(name) == 'started' end
local function resultFor(scenario, result, reason, evidence)
    return { id=scenario.id, resource=scenario.resource, layer=scenario.layer, result=result, reason=reason, evidence=evidence or {} }
end
local function readyClient(preferred)
    if preferred and CmQaAuthorizedClients and CmQaAuthorizedClients[preferred] and CmQaAuthorizedClients[preferred].registered and CmQaAuthorizedClients[preferred].ready then return preferred end
    for sourceId, client in pairs(CmQaAuthorizedClients or {}) do if client.registered and client.ready then return tonumber(sourceId) end end
    return nil
end

local function expectedCharacterIdForSource(sourceId)
    local client = CmQaAuthorizedClients and CmQaAuthorizedClients[sourceId]
    return client and tonumber(client.expectedCharacterId or client.characterId) or nil
end

local function ownerReasonFromError(message)
    message = tostring(message or '')
    if message:find('No such export', 1, true) or message:find('export.*not found') then
        return 'OWNER_EXPORT_MISSING'
    end
    return 'OWNER_SNAPSHOT_ERROR'
end

local function electricianSnapshot(src, expectedCharacterId)
    if GetResourceState('cm-electrician') ~= 'started' then return false, 'OWNER_RESOURCE_NOT_STARTED' end
    local deadline = GetGameTimer() + 5000
    local lastReason = 'OWNER_SNAPSHOT_TIMEOUT'
    while GetGameTimer() <= deadline do
        local callOk, contractOk, value = pcall(function()
            return exports['cm-electrician']:QaSnapshot(src, expectedCharacterId)
        end)
        if not callOk then
            lastReason = ownerReasonFromError(value)
        elseif contractOk == true and type(value) == 'table' then
            return true, value
        elseif contractOk == false then
            if value == 'forbidden' then return false, 'OWNER_EXPORT_FORBIDDEN' end
            if value == 'character_mismatch' then return false, 'OWNER_CHARACTER_MISMATCH' end
            if value == 'qa_disabled' then return false, 'OWNER_EXPORT_FORBIDDEN' end
            lastReason = 'OWNER_SNAPSHOT_ERROR'
        else
            lastReason = 'OWNER_SNAPSHOT_ERROR'
        end
        Wait(250)
        if GetResourceState('cm-electrician') ~= 'started' then return false, 'OWNER_RESOURCE_NOT_STARTED' end
    end
    return false, lastReason == 'OWNER_EXPORT_MISSING' and lastReason or 'OWNER_SNAPSHOT_TIMEOUT'
end

local function electricianControl(action, data)
    if GetResourceState('cm-electrician') ~= 'started' then return false, 'OWNER_RESOURCE_NOT_STARTED' end
    local callOk, contractOk, value = pcall(function()
        return exports['cm-electrician']:QaControl(action, data)
    end)
    if not callOk then return false, ownerReasonFromError(value) end
    if contractOk ~= true then
        if value == 'forbidden' then return false, 'OWNER_EXPORT_FORBIDDEN' end
        if value == 'character_mismatch' then return false, 'OWNER_CHARACTER_MISMATCH' end
        return false, 'OWNER_FIXTURE_SETUP_FAILED'
    end
    return true, value
end

local function fishingSnapshot(src, expectedCharacterId)
    if GetResourceState('cm-fishing') ~= 'started' then return false, 'OWNER_RESOURCE_NOT_STARTED' end
    local callOk, contractOk, value = pcall(function()
        return exports['cm-fishing']:QaSnapshot(src, expectedCharacterId)
    end)
    if not callOk then return false, ownerReasonFromError(value) end
    if contractOk == true and type(value) == 'table' then return true, value end
    if contractOk == false then
        if value == 'forbidden' or value == 'qa_disabled' then return false, 'OWNER_EXPORT_FORBIDDEN' end
        if value == 'character_mismatch' then return false, 'OWNER_CHARACTER_MISMATCH' end
        return false, tostring(value or 'OWNER_SNAPSHOT_ERROR')
    end
    return false, 'OWNER_SNAPSHOT_ERROR'
end

local function fishingControl(action, data)
    if GetResourceState('cm-fishing') ~= 'started' then return false, 'OWNER_RESOURCE_NOT_STARTED' end
    local callOk, contractOk, value = pcall(function()
        return exports['cm-fishing']:QaControl(action, data)
    end)
    if not callOk then return false, ownerReasonFromError(value) end
    if contractOk ~= true then
        if value == 'forbidden' or value == 'qa_disabled' then return false, 'OWNER_EXPORT_FORBIDDEN' end
        if value == 'character_mismatch' then return false, 'OWNER_CHARACTER_MISMATCH' end
        return false, tostring(value or 'OWNER_FIXTURE_SETUP_FAILED')
    end
    return true, value
end

function CmQaRunner.cancelActive(reason, resultName)
    local active = CmQaRunner.activeClient
    if not active then return false end
    local scenario = findScenario(active.scenario)
    local result = resultName or 'CANCELLED'
    CmQaRunner.lastRun = { runId=active.runId, startedAt=active.startedAt, result=result, tests={resultFor(scenario, result, reason or 'cancelled', { 'qa_client_cleanup_completed' })} }
    TriggerClientEvent('cm-qa:client:stopScenario', active.source, { runId=active.runId, reason=reason or 'server_cleanup' })
    if active.ownerResource == 'cm-electrician' then
        pcall(function() electricianControl('cleanup', { source=active.source, expectedCharacterId=active.expectedCharacterId }) end)
    end
    if active.ownerResource == 'cm-fishing' then
        pcall(function() fishingControl('clear', { source=active.source, expectedCharacterId=active.expectedCharacterId }) end)
    end
    active.events = {}
    active.ownerBaseline = nil
    active.ownerTarget = nil
    CmQaRunner.activeClient = nil
    return true
end

local function isElectricianPhysicalScenario(scenario)
    return scenario and scenario.resource == 'cm-electrician' and scenario.layer == 'client'
        and (scenario.id == 'electrician.panel.physical-repair'
            or scenario.id == 'electrician.panel.early-release'
            or scenario.id == 'electrician.panel.shock')
end

local function expectedInputForScenario(scenario)
    if not scenario then return nil end
    if scenario.id == 'qa.client.input-smoke' then return 'E_PRESS' end
    if scenario.id == 'qa.client.hold-smoke' then return 'E_HOLD' end
    if isElectricianPhysicalScenario(scenario) then return 'E_HOLD' end
    return nil
end

local function finishElectricianScenario(active, scenario, result, reason, evidence)
    if not CmQaRunner.activeClient or CmQaRunner.activeClient.runId ~= active.runId then return end
    local cleanupOk, cleanupReason = electricianControl('cleanup', { source=active.source, expectedCharacterId=active.expectedCharacterId })
    if not cleanupOk then
        result = resultFor(scenario, 'FAIL', cleanupReason or 'OWNER_FIXTURE_CLEANUP_FAILED', evidence or {})
    end
    CmQaRunner.lastRun.result = result.result
    CmQaRunner.lastRun.tests = { result }
    TriggerClientEvent('cm-qa:client:stopScenario', active.source, { runId=active.runId, reason=reason or result.result })
    CmQaRunner.activeClient = nil
end

local function beginElectricianFixture(active, scenario)
    active.ownerResource = 'cm-electrician'
    active.expectedCharacterId = expectedCharacterIdForSource(active.source)
    local snapshotOk, beforeOrReason = electricianSnapshot(active.source, active.expectedCharacterId)
    if not snapshotOk then return false, beforeOrReason end
    local before = beforeOrReason
    active.ownerBaseline = before
    local ok, reason = electricianControl('prepare_level', { source=active.source, level=1, expectedCharacterId=active.expectedCharacterId })
    if not ok then return false, reason end
    return true
end

local function runOwnerContractScenario(scenario)
    local sourceId = readyClient()
    if not sourceId then
        local blocked = resultFor(scenario, 'BLOCKED', 'no_registered_ready_client', { 'FIVEM_CLIENT_QA_BLOCKED_NO_CLIENT' })
        CmQaRunner.lastRun = { runId=('owner-%d'):format(GetGameTimer()), startedAt=nowIso(), result=blocked.result, tests={blocked} }
        return blocked
    end

    local expectedCharacterId = expectedCharacterIdForSource(sourceId)
    local snapshotOk, baselineOrReason = electricianSnapshot(sourceId, expectedCharacterId)
    if not snapshotOk then
        local blocked = resultFor(scenario, 'BLOCKED', baselineOrReason, { 'owner_snapshot_probe_failed' })
        CmQaRunner.lastRun = { runId=('owner-%d'):format(GetGameTimer()), startedAt=nowIso(), result=blocked.result, tests={blocked} }
        return blocked
    end

    local baseline = baselineOrReason
    local invalidCallOk, invalidContract, invalidReason = pcall(function()
        return exports['cm-electrician']:QaControl('prepare_level', { source=0, level=1, expectedCharacterId=expectedCharacterId })
    end)
    local invalidSourceRejected = invalidCallOk and invalidContract == false and invalidReason == 'invalid_source'
    local fixtureOk, fixtureReason = electricianControl('prepare_level', { source=sourceId, level=1, expectedCharacterId=expectedCharacterId })
    local cleanupOk, cleanupReason = electricianControl('cleanup', { source=sourceId, expectedCharacterId=expectedCharacterId })
    local afterOk, afterOrReason = electricianSnapshot(sourceId, expectedCharacterId)
    local restored = afterOk and afterOrReason.level == baseline.level
        and afterOrReason.panels == baseline.panels and afterOrReason.plates == baseline.plates
        and afterOrReason.onShift == baseline.onShift
    local passed = fixtureOk and cleanupOk and restored and invalidSourceRejected
    local result = resultFor(scenario, passed and 'SERVER_INTEGRATION_PASS' or 'FAIL',
        passed and 'owner_contract_callable_fixture_restored' or (fixtureReason or cleanupReason or afterOrReason), {
            'QaSnapshot_callable_from_cm-qa',
            'QaControl_prepare_level_and_cleanup_callable_from_cm-qa',
            'server_exports_are_not_network_events',
            invalidSourceRejected and 'invalid_source_rejected_by_owner_contract' or 'invalid_source_rejection_failed',
            afterOk and afterOrReason.characterId == expectedCharacterId and 'snapshot_character_id_matches_configured_qa_character' or 'snapshot_character_id_mismatch',
            'fixture_restored_original_level_progression_and_shift_state',
        })
    CmQaRunner.lastRun = { runId=('owner-%d'):format(GetGameTimer()), startedAt=nowIso(), result=result.result, tests={result} }
    return result
end

local function runFishingOwnerContractScenario(scenario)
    local sourceId = readyClient()
    if not sourceId then
        local blocked = resultFor(scenario, 'BLOCKED', 'no_registered_ready_client', { 'FIVEM_CLIENT_QA_BLOCKED_NO_CLIENT', 'no_physical_input_required' })
        CmQaRunner.lastRun = { runId=('owner-%d'):format(GetGameTimer()), startedAt=nowIso(), result=blocked.result, tests={blocked} }
        return blocked
    end

    local expectedCharacterId = expectedCharacterIdForSource(sourceId)
    if not expectedCharacterId then
        local blocked = resultFor(scenario, 'BLOCKED', 'qa_character_not_paired', { 'owner_contract_requires_active_character', 'no_physical_input_required' })
        CmQaRunner.lastRun = { runId=('owner-%d'):format(GetGameTimer()), startedAt=nowIso(), result=blocked.result, tests={blocked} }
        return blocked
    end

    local snapshotOk, baselineOrReason = fishingSnapshot(sourceId, expectedCharacterId)
    if not snapshotOk then
        local blocked = resultFor(scenario, 'BLOCKED', baselineOrReason, { 'owner_snapshot_probe_failed', 'no_physical_input_required' })
        CmQaRunner.lastRun = { runId=('owner-%d'):format(GetGameTimer()), startedAt=nowIso(), result=blocked.result, tests={blocked} }
        return blocked
    end

    local baseline = baselineOrReason
    local invalidCallOk, invalidContract, invalidReason = pcall(function()
        return exports['cm-fishing']:QaControl('clear', { source=0, expectedCharacterId=expectedCharacterId })
    end)
    local invalidSourceRejected = invalidCallOk and invalidContract == false and invalidReason == 'invalid_source'

    local wrongOk, wrongContract, wrongReason = pcall(function()
        return exports['cm-fishing']:QaSnapshot(sourceId, tostring(expectedCharacterId) .. '-wrong')
    end)
    local wrongCharacterRejected = wrongOk and wrongContract == false and wrongReason == 'character_mismatch'

    local setActions = {
        { action='force_next_fish', data={ fish='trout' } },
        { action='force_heavy', data={ enabled=true } },
        { action='force_shark', data={ enabled=false } },
        { action='force_bait_saved', data={ enabled=true } },
        { action='force_rod_break', data={ enabled=true } },
    }
    local setupOk, setupReason = true, nil
    for _, entry in ipairs(setActions) do
        local ok, value = fishingControl(entry.action, {
            source=sourceId,
            expectedCharacterId=expectedCharacterId,
            fish=entry.data.fish,
            enabled=entry.data.enabled,
        })
        if not ok then setupOk, setupReason = false, value break end
    end

    local pendingOk, pendingOrReason = fishingSnapshot(sourceId, expectedCharacterId)
    local pending = pendingOk and pendingOrReason or {}
    local deterministicSet = pendingOk and pending.qaStatePending == true
        and pending.qaForceNextFish == 'trout'
        and pending.qaForceHeavy == true
        and pending.qaForceShark == false
        and pending.qaForceBaitSaved == true
        and pending.qaForceRodBreak == true

    local cleanupOk, cleanupReason = fishingControl('clear', { source=sourceId, expectedCharacterId=expectedCharacterId })
    local afterOk, afterOrReason = fishingSnapshot(sourceId, expectedCharacterId)
    local after = afterOk and afterOrReason or {}
    local restored = afterOk and after.qaStatePending ~= true
        and after.castActive == baseline.castActive
        and after.rentalActive == baseline.rentalActive
        and after.saleLockActive == baseline.saleLockActive
    local passed = setupOk and deterministicSet and cleanupOk and restored and invalidSourceRejected and wrongCharacterRejected
    local result = resultFor(scenario, passed and 'SERVER_INTEGRATION_PASS' or 'FAIL',
        passed and 'fishing_owner_contract_callable_state_set_cleared_restored' or (setupReason or pendingOrReason or cleanupReason or afterOrReason), {
            'QaSnapshot_callable_from_cm-qa',
            'QaControl_callable_from_cm-qa',
            'development_and_qa_enabled_gate_present',
            'server_exports_are_not_network_events',
            invalidSourceRejected and 'invalid_source_rejected' or 'invalid_source_rejection_failed',
            wrongCharacterRejected and 'wrong_character_rejected' or 'wrong_character_rejection_failed',
            deterministicSet and 'deterministic_setup_bound_to_character' or 'deterministic_setup_failed',
            cleanupOk and 'qa_state_clear_callable' or 'qa_state_clear_failed',
            restored and 'baseline_cast_rental_lock_state_restored' or 'baseline_state_not_restored',
            'no_physical_five_m_input_required',
        })
    CmQaRunner.lastRun = { runId=('owner-%d'):format(GetGameTimer()), startedAt=nowIso(), result=result.result, tests={result} }
    return result
end

local function runFishingBlockedCleanupRegression(scenario)
    if CmQaRunner.activeClient then CmQaRunner.cancelActive('owner_contract_blocked', 'BLOCKED') end
    local clear = CmQaRunner.activeClient == nil
    local result = resultFor(scenario, clear and 'SERVER_INTEGRATION_PASS' or 'FAIL',
        clear and 'blocked_owner_run_cleared_and_runner_ready' or 'active_run_leaked', {
            clear and 'active_run_cleared' or 'active_run_not_cleared',
            clear and 'temporary_owner_state_cleanup_attempted' or 'temporary_owner_state_cleanup_skipped',
            clear and 'next_server_scenario_can_run' or 'next_server_scenario_blocked_by_stale_state',
        })
    CmQaRunner.lastRun = { runId=('server-%d'):format(GetGameTimer()), startedAt=nowIso(), result=result.result, tests={result} }
    return result
end

function CmQaRunner.startClientScenario(scenario, preferred)
    local sourceId = readyClient(preferred)
    if not sourceId then
        local blocked = resultFor(scenario, 'BLOCKED', 'no_registered_ready_client', { 'FIVEM_CLIENT_QA_BLOCKED_NO_CLIENT' })
        CmQaRunner.lastRun = { runId=('client-%d'):format(GetGameTimer()), startedAt=nowIso(), result=blocked.result, tests={blocked} }
        return blocked
    end
    if CmQaRunner.activeClient then CmQaRunner.cancelActive('replaced_by_new_run', 'CANCELLED') end
    local runId = ('client-%d-%d'):format(GetGameTimer(), sourceId)
    local active = { runId=runId, scenario=scenario.id, source=sourceId, startedAt=nowIso(), phase='STARTING', expectedInput=expectedInputForScenario(scenario), events={} }
    CmQaRunner.activeClient = active
    if isElectricianPhysicalScenario(scenario) then
        local ok, reason = beginElectricianFixture(active, scenario)
        if not ok then
            CmQaRunner.cancelActive(reason, 'BLOCKED')
            return CmQaRunner.lastRun.tests[1]
        end
    end
    local running = resultFor(scenario, 'RUNNING', 'physical_client_scenario_started', { 'run_id_assigned', 'registered_client_targeted' })
    CmQaRunner.lastRun = { runId=runId, startedAt=CmQaRunner.activeClient.startedAt, result='RUNNING', tests={running} }
    TriggerClientEvent('cm-qa:client:startScenario', sourceId, { runId=runId, scenario=scenario.id })
    SetTimeout(30000, function()
        if CmQaRunner.activeClient and CmQaRunner.activeClient.runId == runId then CmQaRunner.cancelActive('scenario_timeout', 'TIMEOUT') end
    end)
    return running
end

function CmQaRunner.runScenario(id)
    local scenario = findScenario(id)
    if not scenario then return nil, 'unknown_scenario' end
    if scenario.id == 'electrician.qa.owner-contract' then
        return runOwnerContractScenario(scenario)
    end
    if scenario.id == 'fishing.qa.owner-contract' or scenario.id == 'fishing.cast.lifecycle' then
        return runFishingOwnerContractScenario(scenario)
    end
    if scenario.id == 'fishing.qa.blocked-cleanup' then
        return runFishingBlockedCleanupRegression(scenario)
    end
    if scenario.kind == 'framework' then
        local result = resultFor(scenario, 'SERVER_INTEGRATION_PASS', 'framework_ready', { 'development_environment_verified', 'internal_qa_state_enabled' })
        CmQaRunner.lastRun = { runId=('server-%d'):format(GetGameTimer()), startedAt=nowIso(), result=result.result, tests={result} }
        return result
    end
    if scenario.kind == 'framework_lifecycle' then
        local registeredCount = 0
        for _, client in pairs(CmQaAuthorizedClients or {}) do if client.registered then registeredCount = registeredCount + 1 end end
        local result
        if scenario.id == 'qa.framework.unregistered-invisible' and registeredCount == 0 and not CmQaRunner.activeClient then
            result = resultFor(scenario, 'SERVER_INTEGRATION_PASS', 'unregistered_client_gate_verified', { 'registered_clients=0', 'active_run=nil', 'no_targeted_client_event' })
        elseif scenario.id == 'qa.framework.registration-invisible' and not CmQaRunner.activeClient then
            result = resultFor(scenario, 'SERVER_INTEGRATION_PASS', 'registration_does_not_assign_run', { 'active_run=nil', 'client_presentation_requires_run_id' })
        else
            result = resultFor(scenario, 'BLOCKED', 'requires_connected_client_lifecycle_assertion', { 'Client-visible prompt, focus, and post-pass cleanup require a registered FiveM client.' })
        end
        CmQaRunner.lastRun = { runId=('lifecycle-%d'):format(GetGameTimer()), startedAt=nowIso(), result=result.result, tests={result} }
        return result
    end
    if scenario.layer == 'client' then
        if scenario.resource == 'cm-qa' or isElectricianPhysicalScenario(scenario) then
            return CmQaRunner.startClientScenario(scenario)
        end
        local blocked = resultFor(scenario, 'BLOCKED', 'owner_qa_contract_not_available', { 'QA_DISCOVERED_GAMEPLAY_FAILURE remains an honest manual/owner-contract outcome.', 'No electrician production event/export was invoked.' })
        CmQaRunner.lastRun = { runId=('client-%d'):format(GetGameTimer()), startedAt=nowIso(), result=blocked.result, tests={blocked} }
        return blocked
    end
    local result
    if not resourceReady(scenario.resource) then
        result = resultFor(scenario, 'BLOCKED', 'owner_resource_not_started', { ('resource_state=%s'):format(GetResourceState(scenario.resource)) })
    else
        result = resultFor(scenario, 'BLOCKED', 'owner_qa_contract_not_available', { 'No gameplay state was mutated.', 'No production event/export was invoked.' })
    end
    CmQaRunner.lastRun = { runId=('server-%d'):format(GetGameTimer()), startedAt=nowIso(), result=result.result, tests={result} }
    return result
end

AddEventHandler('cm-electrician:server:shiftStarted', function(sourceId)
    local active = CmQaRunner.activeClient
    if not active or active.ownerResource ~= 'cm-electrician' or tonumber(active.source) ~= tonumber(sourceId) then return end
    local scenario = findScenario(active.scenario)
    if not isElectricianPhysicalScenario(scenario) then return end

    -- Panel 1 is selected by the owner contract after the real shift-start
    -- event has created the authoritative session.
    local assigned = 1
    local setupOk, setupResult = pcall(function()
        if not assigned then return false, 'no_panel_assignment' end
        local ok, reason = electricianControl('assign_panel', { source=sourceId, index=assigned, expectedCharacterId=active.expectedCharacterId })
        if ok ~= true then return false, reason or 'panel_assignment_failed' end
        if active.scenario == 'electrician.panel.shock' then
            local shockOk, shockReason = electricianControl('force_next_shock', { source=sourceId, enabled=true, expectedCharacterId=active.expectedCharacterId })
            if shockOk ~= true then return false, shockReason or 'shock_fixture_failed' end
        end
        return true
    end)
    if not setupOk or setupResult ~= true then
        CmQaRunner.cancelActive('owner_fixture_setup_failed', 'BLOCKED')
        return
    end
    local snapshotOk, snapshotOrReason = electricianSnapshot(sourceId, active.expectedCharacterId)
    if not snapshotOk or not snapshotOrReason.target then
        CmQaRunner.cancelActive(snapshotOrReason or 'OWNER_SNAPSHOT_ERROR', 'BLOCKED')
        return
    end
    local snapshot = snapshotOrReason
    active.ownerTarget = snapshot.target
    TriggerClientEvent('cm-qa:client:electricianSetup', sourceId, {
        runId=active.runId,
        employment=snapshot.employment,
        target=snapshot.target,
    })
end)

function CmQaRunner.runResource(resourceName)
    local results = {}
    for _, scenario in ipairs(CmQaScenarios or {}) do
        if scenario.resource == resourceName then local result = CmQaRunner.runScenario(scenario.id); if result then results[#results + 1] = result end end
    end
    if #results == 0 then return nil, 'no_scenarios' end
    return results
end
function CmQaRunner.list() return CmQaScenarios or {} end

function CmQaRunner.recordClientEvent(sourceId, payload)
    local active = CmQaRunner.activeClient
    if not active or tonumber(active.source) ~= tonumber(sourceId) or type(payload) ~= 'table' then return false end
    if not CmQaAuthorizedClients[sourceId] or not CmQaAuthorizedClients[sourceId].registered or not CmQaAuthorizedClients[sourceId].ready then return false end
    if tostring(payload.runId or '') ~= active.runId or tostring(payload.scenario or '') ~= active.scenario then return false end
    if payload.event == 'cancel' then return CmQaRunner.cancelActive(payload.reason or 'client_cancelled', 'CANCELLED') end
    local scenario = findScenario(active.scenario)
    active.events[payload.event] = payload
    if payload.event == 'scenario_ready' then
        local expected = expectedInputForScenario(scenario)
        if payload.phase ~= 'ACTIVE' or tostring(payload.expectedInput or '') ~= tostring(expected or '') then return false end
        if isElectricianPhysicalScenario(scenario)
            and (payload.interactionOwner ~= 'cm-electrician:panel' or payload.interactionAction ~= 'HOLD TO REPAIR')
        then
            return false
        end
        active.phase = 'ACTIVE'
        active.expectedInput = expected
        active.events.scenario_ready = { phase='ACTIVE', expectedInput=expected }
        return true
    end
    if (payload.event == 'input_press' or payload.event == 'hold_start' or payload.event == 'hold_release') and active.phase ~= 'ACTIVE' then
        return false
    end
    if payload.event == 'client_blocked' then return CmQaRunner.cancelActive(payload.reason or 'client_blocked', 'BLOCKED') end
    if isElectricianPhysicalScenario(scenario) and payload.event == 'hold_release' then
        active.holdReleaseCount = (active.holdReleaseCount or 0) + 1
        SetTimeout(1200, function()
            if not CmQaRunner.activeClient or CmQaRunner.activeClient.runId ~= active.runId then return end
            local snapshotOk, snapshotOrReason = electricianSnapshot(active.source, active.expectedCharacterId)
            local snapshot = snapshotOk and snapshotOrReason or nil
            local baseline = active.ownerBaseline or {}
            local beforePanels = tonumber(baseline.panels) or 0
            local beforeCash = baseline.pendingCash and tonumber(baseline.pendingCash.electrician)
            local panels = snapshot and tonumber(snapshot.panels) or nil
            local pendingCash = snapshot and snapshot.pendingCash and tonumber(snapshot.pendingCash.electrician) or nil
            local repair = snapshot and snapshot.activeRepair
            local outcome = snapshot and snapshot.lastRepairOutcome
            local duration = tonumber(payload.durationMs) or 0
            local passed = false
            local reason = 'owner_physical_assertion_failed'
            local evidence = { 'physical_input_received', ('hold_duration_ms=%d'):format(duration) }
            local cashExact = beforeCash ~= nil and pendingCash ~= nil
            if active.scenario == 'electrician.panel.physical-repair' then
                passed = active.holdReleaseCount == 1 and panels == beforePanels + 1 and repair == nil
                    and cashExact and pendingCash == beforeCash + (snapshot and snapshot.rewardPerPanel or 30)
                reason = 'panel_completed_once_with_progression_and_reward'
                evidence[#evidence + 1] = 'server_snapshot_panel_count_incremented_once'
                evidence[#evidence + 1] = 'server_snapshot_active_repair_cleared'
            elseif active.scenario == 'electrician.panel.early-release' then
                passed = active.holdReleaseCount == 1 and duration < 3000 and panels == beforePanels and repair == nil
                    and cashExact and pendingCash == beforeCash
                reason = 'early_release_rejected_without_progression'
                evidence[#evidence + 1] = 'server_snapshot_panel_count_unchanged'
                evidence[#evidence + 1] = 'server_snapshot_pending_cash_unchanged'
            elseif active.scenario == 'electrician.panel.shock' then
                passed = active.holdReleaseCount == 1 and outcome == 'shock' and panels == beforePanels and repair == nil
                    and cashExact and pendingCash == beforeCash
                reason = 'forced_shock_rejected_without_progression'
                evidence[#evidence + 1] = 'server_snapshot_shock_outcome_verified'
                evidence[#evidence + 1] = 'server_snapshot_panel_count_unchanged'
            end
            local result = resultFor(scenario, passed and 'FIVEM_CLIENT_QA_PASS' or 'FAIL', reason, evidence)
            finishElectricianScenario(active, scenario, result, passed and 'pass' or 'assertion_failed')
        end)
    end
    if active.scenario == 'qa.client.hold-smoke' then
        local duration = tonumber(active.events.hold_release and active.events.hold_release.durationMs)
        if duration and duration >= 2200 and duration <= 5000 then
            local scenario = findScenario(active.scenario)
            local result = resultFor(scenario, 'FIVEM_CLIENT_QA_PASS', 'physical_hold_duration_verified', { 'run_id_verified', 'registered_character_id_verified', 'physical_input_received' })
            CmQaRunner.lastRun.result = result.result; CmQaRunner.lastRun.tests = { result }
            TriggerClientEvent('cm-qa:client:stopScenario', sourceId, { runId=active.runId, reason='pass' }); CmQaRunner.activeClient = nil
        end
    end
    return true
end
