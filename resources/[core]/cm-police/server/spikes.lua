-- cm-police spike strips. Session-only, in-memory tracking -- there's
-- nothing worth persisting about a temporary road hazard, same "transient"
-- shape cuffs.lua uses for its own state.
--
-- Lifetime is owned by the SERVER, not the deploying officer's own client:
-- a local CreateThread timer on that client would silently stop running if
-- they disconnect before it fires, even though the networked object itself
-- safely migrates to another client via SetNetworkIdCanMigrate. The sweep
-- thread below is independent of any one player's connection, matching the
-- same reasoning booking.lua's own auto-release sweep already established.

local ActiveStrips = {} -- [stripId] = { netId, officerCid, expiresAt }
local OfficerCounts = {} -- [officerCid] = count
local NextStripId = 0

local function deleteStrip(netId)
    local entity = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if entity ~= 0 and DoesEntityExist(entity) and Entity(entity).state.cmSpikeStrip == true then DeleteEntity(entity) end
end

local function validPlacementNumber(value, limit)
    return value ~= nil and value == value and math.abs(value) <= limit
end

local function authorizedOfficer(src)
    local characterId = cid(tonumber(src))
    local member = characterId and memberFor(characterId)
    if member and not dbBoolean(member.is_suspended) and dbBoolean(member.on_duty) and has(member, 'police.spike') then
        return member, tostring(characterId)
    end
    local legalState = Player(src).state.cmLegalOrg
    local orgId = type(legalState) == 'table' and (legalState.id or legalState.organizationId) or nil
    if characterId and orgId and GetResourceState('cm-law') == 'started' then
        local ok, legalMember = pcall(function() return exports['cm-law']:GetMember(characterId, orgId) end)
        if ok and legalMember and not legalMember.suspended and legalMember.onDuty
            and (legalMember.isLeader or legalMember.permissions['law.spike'] == true) then
            return legalMember, tostring(characterId)
        end
    end
    return nil, characterId
end

lib.callback.register('cm-police:server:deploySpikeStrip', function(src)
    if not rateLimit(src, 'police_deploy_spike', 1500) then return false, 'Please wait.' end
    local actor, actorCid = authorizedOfficer(src)
    if not actor then return false, 'You must be an on-duty officer with spike strip permission.' end
    if (OfficerCounts[actorCid] or 0) >= (Config.SpikeStrips.MaxActive or 3) then
        return false, ('You already have the maximum of %d spike strips deployed.'):format(Config.SpikeStrips.MaxActive or 3)
    end
    NextStripId = NextStripId + 1
    local stripId = NextStripId
    OfficerCounts[actorCid] = (OfficerCounts[actorCid] or 0) + 1
    -- Grace period matches Config.SpikeStrips.PlacementTimeoutMs exactly --
    -- the client auto-cancels its own placement preview at that same
    -- timeout, so this reservation can never expire while a legitimate
    -- placement is still in progress. If the client never confirms at all
    -- (dropped connection, client-side error), the sweep below reclaims
    -- this slot instead of leaking it forever.
    ActiveStrips[stripId] = { netId = nil, officerCid = actorCid, officerSource = src, expiresAt = os.time() + math.ceil((Config.SpikeStrips.PlacementTimeoutMs or 45000) / 1000) }
    return true, stripId
end)

RegisterNetEvent('cm-police:server:spikeStripDeployed')
AddEventHandler('cm-police:server:spikeStripDeployed', function(stripId, x, y, z, heading)
    local src = source
    local actor, actorCid = authorizedOfficer(src)
    local entry = ActiveStrips[tonumber(stripId)]
    x, y, z, heading = tonumber(x), tonumber(y), tonumber(z), tonumber(heading) or 0.0
    if not actor or not entry or entry.netId or entry.officerCid ~= actorCid then return end
    if not validPlacementNumber(x, 10000.0) or not validPlacementNumber(y, 10000.0)
        or not validPlacementNumber(z, 2500.0) or not validPlacementNumber(heading, 100000.0) then return end
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(x, y, z)) > ((Config.Placement.MaxDistance or 5.0) + 2.0) then return end
    local entity = CreateObject(GetHashKey(Config.SpikeStrips.Model), x, y, z, true, true, false)
    if entity == 0 or not DoesEntityExist(entity) then return end
    SetEntityHeading(entity, heading % 360.0)
    FreezeEntityPosition(entity, true)
    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(src))
    Entity(entity).state:set('cmSpikeStrip', true, true)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId <= 0 then DeleteEntity(entity) return end
    entry.netId = netId
    entry.expiresAt = os.time() + math.floor((Config.SpikeStrips.LifetimeMs or 120000) / 1000)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', src, 'Spike strip deployed.', 'success')
end)

-- Fired when the client backs out of placement (Backspace) before ever
-- confirming a position -- frees the reserved slot immediately instead of
-- making the officer wait out the 10s grace period below. Guarded on netId
-- still being nil so this can never cancel an already-placed strip.
RegisterNetEvent('cm-police:server:cancelSpikeStrip')
AddEventHandler('cm-police:server:cancelSpikeStrip', function(stripId)
    local src = source
    local actorCid = cid(src)
    local entry = ActiveStrips[tonumber(stripId)]
    if not entry or not actorCid or entry.officerCid ~= actorCid or entry.netId then return end
    ActiveStrips[tonumber(stripId)] = nil
    OfficerCounts[actorCid] = math.max(0, (OfficerCounts[actorCid] or 1) - 1)
end)

lib.callback.register('cm-police:server:recallSpikeStrips', function(src)
    local actorCid = cid(src)
    if not actorCid then return 0 end
    local removed = 0
    for stripId, entry in pairs(ActiveStrips) do
        if entry.officerCid == actorCid then
            deleteStrip(entry.netId)
            ActiveStrips[stripId] = nil
            OfficerCounts[actorCid] = math.max(0, (OfficerCounts[actorCid] or 1) - 1)
            removed = removed + 1
        end
    end
    return removed
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for stripId, entry in pairs(ActiveStrips) do
            if now >= entry.expiresAt then
                deleteStrip(entry.netId)
                ActiveStrips[stripId] = nil
                OfficerCounts[entry.officerCid] = math.max(0, (OfficerCounts[entry.officerCid] or 1) - 1)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local droppedSource = source
    for stripId, entry in pairs(ActiveStrips) do
        if entry.officerSource == droppedSource then
            deleteStrip(entry.netId)
            ActiveStrips[stripId] = nil
            OfficerCounts[entry.officerCid] = nil
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entry in pairs(ActiveStrips) do deleteStrip(entry.netId) end
end)
