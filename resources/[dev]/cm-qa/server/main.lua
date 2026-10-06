local authorizedClients = {}
local lastClientSnapshot = {}
local qaState = false
local function setQaConvar(enabled)
    ExecuteCommand(('set cm_qa_enabled %d'):format(enabled and 1 or 0))
end
local function newPairingState()
    return {
        configuredCharacterId = nil,
        pairedCharacterId = nil,
        connected = false,
        paired = false,
        ready = false,
        state = 'not_configured',
    }
end
local pairing = newPairingState()
CmQaAuthorizedClients = authorizedClients

local function developmentEnvironment() return GetConvar('cm_environment', 'production') == 'development' end
local function qaEnabled() return developmentEnvironment() and (qaState or GetConvarInt('cm_qa_enabled', 0) == 1) end
local function consoleOnly(source) return tonumber(source) == 0 end
local function printJson(label, payload) print(('[CM-QA] %s %s'):format(label, json.encode(payload or {}))) end
local function authorizedClientCount() local count=0; for _ in pairs(authorizedClients) do count=count+1 end; return count end
local function registeredClientCount() local count=0; for _, client in pairs(authorizedClients) do if client.registered then count=count+1 end end; return count end
local function readyClientCount() local count=0; for _, client in pairs(authorizedClients) do if client.registered and client.ready then count=count+1 end end; return count end
local function deny(source, reason) printJson('DENIED', { source=tonumber(source) or -1, reason=reason }) end
local function commandAllowed(source, requiresEnabled)
    if not consoleOnly(source) then deny(source, 'console_only'); return false end
    if requiresEnabled and not qaEnabled() then deny(source, 'qa_disabled_or_non_development'); return false end
    return true
end

local function resetPairingState()
    pairing = newPairingState()
end

local function setPairingState(state, connected, paired, ready)
    pairing.state = state
    pairing.connected = connected == true
    pairing.paired = paired == true
    pairing.ready = ready == true
end

local function pairingStatus()
    return {
        configuredCharacterId = pairing.configuredCharacterId,
        pairedCharacterId = pairing.pairedCharacterId,
        connected = pairing.connected,
        paired = pairing.paired,
        ready = pairing.ready,
        state = pairing.state,
    }
end

local function revokeClient(sourceId, reason)
    local client = authorizedClients[sourceId]
    if not client then return end
    if CmQaRunner.activeClient and tonumber(CmQaRunner.activeClient.source) == tonumber(sourceId) then CmQaRunner.cancelActive(reason or 'registration_revoked', 'CANCELLED') end
    TriggerClientEvent('cm-qa:client:registrationState', sourceId, false, { reason=reason or 'registration_revoked' })
    authorizedClients[sourceId] = nil
    lastClientSnapshot[sourceId] = nil
    if client.expectedCharacterId and pairing.pairedCharacterId == tonumber(client.expectedCharacterId) then
        pairing.pairedCharacterId = nil
        setPairingState(reason == 'character_mismatch' and 'character_mismatch' or 'not_connected', false, false, false)
    end
end

local function requestClientRegistration(sourceId, expectedCharacterId)
    sourceId = tonumber(sourceId)
    if not sourceId or not GetPlayerName(sourceId) then return false end
    if authorizedClients[sourceId] then revokeClient(sourceId, 'registration_replaced') end
    authorizedClients[sourceId] = {
        source = sourceId,
        ready = false,
        registered = false,
        expectedCharacterId = expectedCharacterId and tonumber(expectedCharacterId) or nil,
        registeredAt = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    if expectedCharacterId then
        pairing.pairedCharacterId = tonumber(expectedCharacterId)
        setPairingState('paired_waiting_ready', true, true, false)
    end
    TriggerClientEvent('cm-qa:client:register', sourceId)
    return true
end

local function connectedSourcesForCharacter(characterId)
    local matches = {}
    if GetResourceState('cm-playerdata') ~= 'started' then return matches, 'playerdata_not_started' end
    local api = exports['cm-playerdata']
    for _, playerId in ipairs(GetPlayers()) do
        local sourceId = tonumber(playerId)
        local ok, activeCharacterId = pcall(function() return api:GetCharacterId(sourceId) end)
        if ok and tonumber(activeCharacterId) == characterId then
            matches[#matches + 1] = sourceId
        end
    end
    return matches
end

RegisterCommand('cm_qa_enable', function(source)
    if not commandAllowed(source, false) then return end
    if not developmentEnvironment() then return deny(source, 'cm_environment_must_be_development') end
    qaState=true; setQaConvar(true); printJson('QA_ENABLED', { enabled=true, environment='development', resource=GetCurrentResourceName() })
end, false)

RegisterCommand('cm_qa_disable', function(source)
    if not commandAllowed(source, false) then return end
    local sources={}; for sourceId in pairs(authorizedClients) do sources[#sources+1]=sourceId end
    for _, sourceId in ipairs(sources) do revokeClient(sourceId, 'qa_disabled') end
    qaState=false; setQaConvar(false); authorizedClients={}; CmQaAuthorizedClients=authorizedClients; lastClientSnapshot={}; CmQaRunner.activeClient=nil; CmQaRunner.lastRun=nil; resetPairingState()
    printJson('QA_DISABLED', { enabled=false, cleanup='all_registered_clients_revoked' })
end, false)

RegisterCommand('cm_qa_status', function(source)
    if not commandAllowed(source, false) then return end
    printJson('STATUS', { enabled=qaEnabled(), environment=GetConvar('cm_environment','production'), resource=GetResourceState(GetCurrentResourceName()), authorizedClients=authorizedClientCount(), registeredClients=registeredClientCount(), readyClients=readyClientCount(), pairing=pairingStatus(), activeClient=CmQaRunner.activeClient, lastRun=CmQaRunner.lastRun })
end, false)
RegisterCommand('cm_qa_list', function(source) if commandAllowed(source,true) then printJson('SCENARIOS',CmQaRunner.list()) end end, false)
RegisterCommand('cm_qa_run', function(source,args)
    if not commandAllowed(source,true) then return end
    local result,err=CmQaRunner.runScenario(table.concat(args or {},' ')); if not result then return printJson('ERROR',{reason=err}) end; printJson('RESULT',result)
end,false)
RegisterCommand('cm_qa_run_resource', function(source,args)
    if not commandAllowed(source,true) then return end
    local results,err=CmQaRunner.runResource(args and args[1]); if not results then return printJson('ERROR',{reason=err}) end; printJson('RESULTS',results)
end,false)
RegisterCommand('cm_qa_run_changed', function(source) if commandAllowed(source,true) then printJson('RESULT',{result='BLOCKED',reason='changed_resource_selection_is_owned_by_tools_cm_qa'}) end end,false)
RegisterCommand('cm_qa_cancel', function(source)
    if not commandAllowed(source,true) then return end
    CmQaRunner.cancelActive('console_cancelled', 'CANCELLED'); printJson('CANCELLED',{cleanup='active_run_cleared'})
end,false)
RegisterCommand('cm_qa_report', function(source) if commandAllowed(source,true) then printJson('REPORT',CmQaRunner.lastRun or {result='BLOCKED',reason='no_run'}) end end,false)
RegisterCommand('cm_qa_register', function(source,args)
    if not commandAllowed(source,true) then return end
    local target=tonumber(args and args[1]); if not target or not GetPlayerName(target) then return printJson('ERROR',{reason='invalid_or_offline_player'}) end
    requestClientRegistration(target)
    printJson('CLIENT_REGISTRATION_REQUESTED',{source=target})
end,false)
RegisterCommand('cm_qa_pair_character', function(source,args)
    if not commandAllowed(source,true) then return end
    if type(args) ~= 'table' or #args ~= 1 or not tostring(args[1]):match('^%d+$') then
        return printJson('ERROR',{reason='invalid_character_id'})
    end
    local characterId = tonumber(args[1])
    if not characterId or characterId < 1 or characterId > 2147483647 then
        return printJson('ERROR',{reason='invalid_character_id'})
    end

    pairing.configuredCharacterId = characterId
    pairing.pairedCharacterId = nil
    setPairingState('searching', false, false, false)
    local matches, lookupError = connectedSourcesForCharacter(characterId)
    if lookupError then
        setPairingState('not_connected', false, false, false)
        return printJson('QA_CLIENT_CHARACTER_NOT_CONNECTED',{characterId=characterId, reason=lookupError})
    end
    if #matches == 0 then
        setPairingState('not_connected', false, false, false)
        return printJson('QA_CLIENT_CHARACTER_NOT_CONNECTED',{characterId=characterId})
    end
    if #matches > 1 then
        setPairingState('ambiguous', true, false, false)
        return printJson('QA_CLIENT_PAIR_AMBIGUOUS',{characterId=characterId, matchCount=#matches})
    end

    local sourcesToRevoke = {}
    for sourceId in pairs(authorizedClients) do
        if tonumber(sourceId) ~= matches[1] then sourcesToRevoke[#sourcesToRevoke + 1] = sourceId end
    end
    for _, sourceId in ipairs(sourcesToRevoke) do revokeClient(sourceId, 'pairing_replaced') end
    requestClientRegistration(matches[1], characterId)
    printJson('QA_CLIENT_PAIR_REQUESTED',{characterId=characterId, connected=true, paired=true, ready=false})
end,false)
RegisterCommand('cm_qa_clients', function(source) if commandAllowed(source,true) then printJson('CLIENTS',authorizedClients) end end,false)

RegisterNetEvent('cm-qa:server:ready',function(snapshot)
    local sourceId=source; local client=authorizedClients[sourceId]
    if not qaEnabled() or not client or type(snapshot)~='table' then return end
    local characterId=tonumber(snapshot.characterId)
    if snapshot.ready ~= true or not characterId then
        return TriggerClientEvent('cm-qa:client:registrationState', sourceId, false, { reason='character_not_ready' })
    end
    if client.expectedCharacterId and characterId ~= tonumber(client.expectedCharacterId) then
        local expected = tonumber(client.expectedCharacterId)
        authorizedClients[sourceId] = nil
        lastClientSnapshot[sourceId] = nil
        if pairing.configuredCharacterId == expected then
            pairing.pairedCharacterId = nil
            setPairingState('character_mismatch', true, false, false)
        end
        TriggerClientEvent('cm-qa:client:registrationState', sourceId, false, { reason='character_mismatch' })
        printJson('QA_CLIENT_CHARACTER_MISMATCH',{characterId=expected})
        return
    end
    client.ready=true; client.registered=true; client.characterId=characterId; client.snapshot={screen=snapshot.screen,resource=snapshot.resource,ready=true}
    if client.expectedCharacterId and pairing.configuredCharacterId == tonumber(client.expectedCharacterId) then
        pairing.pairedCharacterId = tonumber(client.expectedCharacterId)
        setPairingState('ready', true, true, true)
    end
    TriggerClientEvent('cm-qa:client:registrationState', sourceId, true, { characterId=characterId })
end)
RegisterNetEvent('cm-qa:server:clientSnapshot',function(snapshot)
    local sourceId=source; local client=authorizedClients[sourceId]; if not client or not client.registered or type(snapshot)~='table' then return end
    if client.characterId and tonumber(snapshot.characterId) ~= tonumber(client.characterId) then return revokeClient(sourceId, 'character_changed') end
    lastClientSnapshot[sourceId]={coords=snapshot.coords,routingBucket=tonumber(snapshot.routingBucket),nuiFocused=snapshot.nuiFocused==true,characterId=tonumber(snapshot.characterId),capturedAt=os.date('!%Y-%m-%dT%H:%M:%SZ')}
end)
RegisterNetEvent('cm-qa:server:characterChanged',function()
    if authorizedClients[source] then revokeClient(source, 'character_changed') end
end)
RegisterNetEvent('cm-qa:server:clientEvent',function(payload)
    if qaEnabled() and authorizedClients[source] and authorizedClients[source].registered then CmQaRunner.recordClientEvent(source,payload) end
end)
AddEventHandler('playerDropped',function()
    if CmQaRunner.activeClient and tonumber(CmQaRunner.activeClient.source)==tonumber(source) then CmQaRunner.cancelActive('client_disconnected','CANCELLED') end
    local client = authorizedClients[source]
    if client and client.expectedCharacterId and pairing.configuredCharacterId == tonumber(client.expectedCharacterId) then
        pairing.pairedCharacterId = nil
        setPairingState('not_connected', false, false, false)
    end
    authorizedClients[source]=nil; lastClientSnapshot[source]=nil
end)
AddEventHandler('onResourceStop',function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local sources={}; for sourceId in pairs(authorizedClients) do sources[#sources+1]=sourceId end
    for _, sourceId in ipairs(sources) do revokeClient(sourceId, 'resource_stop') end
    CmQaRunner.cancelActive('resource_stop','CANCELLED'); authorizedClients={}; CmQaAuthorizedClients=authorizedClients; lastClientSnapshot={}; qaState=false; setQaConvar(false); CmQaRunner.lastRun=nil; resetPairingState()
end)
print('[CM-QA] development-only resource loaded; use console-only cm_qa_enable to activate QA.')
