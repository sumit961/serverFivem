-- cm-police barricades. Session-only, in-memory tracking, same "transient"
-- shape server/spikes.lua uses for its own state -- there's nothing worth
-- persisting about a temporary roadblock. Unlike a spike strip, a barricade
-- is a solid prop meant to stay up until an officer clears it, so
-- LifetimeMs is a long safety-net sweep (leak prevention if an officer
-- disconnects mid-scene), not a real gameplay timer.

local ActiveBarricades = {} -- [deploymentId] = { organizationId, officerCid, netId, routingBucket, entityType, createdAt, expiresAt }
local OfficerCounts = {} -- [officerCid] = count
local NextBarricadeId = 0
local CatalogReady = false

local function deleteBarricade(netId)
    local entity = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if entity == 0 or not DoesEntityExist(entity) or Entity(entity).state.cmBarricade ~= true then return end
    for _ = 1, 3 do
        DeleteEntity(entity)
        if not DoesEntityExist(entity) then return end
        Wait(0)
    end
end

local function validPlacementNumber(value, limit)
    return value ~= nil and value == value and math.abs(value) <= limit
end

local function authorizedOfficer(src)
    local characterId = cid(tonumber(src))
    local member = characterId and memberFor(characterId)
    if member and not dbBoolean(member.is_suspended) and dbBoolean(member.on_duty) and has(member, 'police.barricade') then
        return member, tostring(characterId), 'police'
    end
    local legalState = Player(src).state.cmLegalOrg
    local orgId = type(legalState) == 'table' and (legalState.id or legalState.organizationId) or nil
    if characterId and orgId and GetResourceState('cm-law') == 'started' then
        local ok, legalMember = pcall(function() return exports['cm-law']:GetMember(characterId, orgId) end)
        if ok and legalMember and not legalMember.suspended and legalMember.onDuty
            and (legalMember.isLeader or legalMember.permissions['law.barricade'] == true) then
            return legalMember, tostring(characterId), tostring(orgId)
        end
    end
    return nil, characterId
end

lib.callback.register('cm-police:server:deployBarricade', function(src)
    if not rateLimit(src, 'police_deploy_barricade', 1500) then return false, 'Please wait.' end
    local actor, actorCid, orgId = authorizedOfficer(src)
    if not actor then return false, 'You must be an on-duty officer with barricade permission.' end
    if (OfficerCounts[actorCid] or 0) >= (Config.Barricades.MaxActive or 2) then
        return false, ('You already have the maximum of %d barricades deployed.'):format(Config.Barricades.MaxActive or 2)
    end
    NextBarricadeId = NextBarricadeId + 1
    local barricadeId = NextBarricadeId
    OfficerCounts[actorCid] = (OfficerCounts[actorCid] or 0) + 1
    -- Grace period matches Config.Barricades.PlacementTimeoutMs exactly --
    -- same reservation-vs-client-timeout reasoning as spikes.lua's own
    -- deploySpikeStrip.
    ActiveBarricades[barricadeId] = { deploymentId = barricadeId, organizationId = orgId, netId = nil,
        officerCid = actorCid, officerSource = src, routingBucket = GetPlayerRoutingBucket(src),
        entityType = 'barricade', createdAt = os.time(),
        expiresAt = os.time() + math.ceil((Config.Barricades.PlacementTimeoutMs or 45000) / 1000) }
    return true, barricadeId
end)

RegisterNetEvent('cm-police:server:barricadeDeployed')
AddEventHandler('cm-police:server:barricadeDeployed', function(barricadeId, x, y, z, heading, modelName)
    local src = source
    local actor, actorCid, orgId = authorizedOfficer(src)
    local entry = ActiveBarricades[tonumber(barricadeId)]
    x, y, z, heading = tonumber(x), tonumber(y), tonumber(z), tonumber(heading) or 0.0
    modelName = tostring(modelName or '')
    if not actor or not entry or entry.netId or entry.officerCid ~= actorCid or entry.organizationId ~= orgId then return end
    if not validPlacementNumber(x, 10000.0) or not validPlacementNumber(y, 10000.0)
        or not validPlacementNumber(z, 2500.0) or not validPlacementNumber(heading, 100000.0) then return end
    if not CatalogReady then return end
    local approved = MySQL.scalar.await('SELECT 1 FROM cm_police_barricade_catalog WHERE model_name = ? LIMIT 1', { modelName })
    if not approved then return end
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(x, y, z)) > ((Config.Placement.MaxDistance or 5.0) + 2.0) then return end
    local entity = CreateObject(GetHashKey(modelName), x, y, z, true, true, false)
    if entity == 0 or not DoesEntityExist(entity) then return end
    SetEntityHeading(entity, heading % 360.0)
    FreezeEntityPosition(entity, true)
    SetEntityRoutingBucket(entity, entry.routingBucket)
    Entity(entity).state:set('cmBarricade', true, true)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId <= 0 then DeleteEntity(entity) return end
    entry.netId = netId
    entry.expiresAt = os.time() + math.floor((Config.Barricades.LifetimeMs or 1800000) / 1000)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', src, 'Barricade deployed.', 'success')
end)

local function cleanupOfficer(characterId)
    characterId = tostring(characterId or '')
    if characterId == '' then return end
    for barricadeId, entry in pairs(ActiveBarricades) do
        if entry.officerCid == characterId then
            deleteBarricade(entry.netId)
            ActiveBarricades[barricadeId] = nil
        end
    end
    OfficerCounts[characterId] = nil
end

AddEventHandler('cm-police:server:memberWentOffDuty', function(_, characterId) cleanupOfficer(characterId) end)
AddEventHandler('cm-law:server:memberWentOffDuty', function(_, characterId) cleanupOfficer(characterId) end)

RegisterNetEvent('cm-police:server:cancelBarricade')
AddEventHandler('cm-police:server:cancelBarricade', function(barricadeId)
    local src = source
    local actorCid = cid(src)
    local entry = ActiveBarricades[tonumber(barricadeId)]
    if not entry or not actorCid or entry.officerCid ~= actorCid or entry.netId then return end
    ActiveBarricades[tonumber(barricadeId)] = nil
    OfficerCounts[actorCid] = math.max(0, (OfficerCounts[actorCid] or 1) - 1)
end)

lib.callback.register('cm-police:server:recallBarricades', function(src)
    local actorCid = cid(src)
    if not actorCid then return 0 end
    local removed = 0
    for barricadeId, entry in pairs(ActiveBarricades) do
        if entry.officerCid == actorCid then
            deleteBarricade(entry.netId)
            ActiveBarricades[barricadeId] = nil
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
        for barricadeId, entry in pairs(ActiveBarricades) do
            if now >= entry.expiresAt then
                deleteBarricade(entry.netId)
                ActiveBarricades[barricadeId] = nil
                OfficerCounts[entry.officerCid] = math.max(0, (OfficerCounts[entry.officerCid] or 1) - 1)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local droppedSource = source
    for barricadeId, entry in pairs(ActiveBarricades) do
        if entry.officerSource == droppedSource then
            deleteBarricade(entry.netId)
            ActiveBarricades[barricadeId] = nil
            OfficerCounts[entry.officerCid] = nil
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entry in pairs(ActiveBarricades) do deleteBarricade(entry.netId) end
end)

-- Admin-managed catalog of barricade prop models -- mirrors
-- server/alpr.lua's camera-list shape exactly (list/add/remove, no
-- generic-dispatcher involvement). Deploy can happen before the F7
-- dashboard has ever been opened, so the list callback below has no
-- permission gate -- same reasoning as the impound kiosk location's own
-- public pull callback.
local function authorizedManager(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    local isAdmin = false
    pcall(function() isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if isAdmin then return { tier = 101, is_leader = 1, permissions = '{}' }, characterId end
    if not member or dbBoolean(member.is_suspended) or not has(member, 'police.manage_barricades') then
        return nil, characterId
    end
    return member, characterId
end

local function publicCatalog()
    local deadline = GetGameTimer() + 5000
    while not CatalogReady and GetGameTimer() < deadline do Wait(25) end
    if not CatalogReady then return {} end
    local rows = MySQL.query.await('SELECT id, model_name FROM cm_police_barricade_catalog ORDER BY id ASC') or {}
    local list = {}
    for _, row in ipairs(rows) do
        list[#list + 1] = { id = tonumber(row.id), modelName = row.model_name }
    end
    return list
end

local function broadcastCatalog()
    local list = publicCatalog()
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent('cm-police:client:barricadeCatalogUpdated', tonumber(playerId), list)
    end
end

lib.callback.register('cm-police:server:barricadeCatalogList', function(src)
    return publicCatalog()
end)

-- There's no reliable server-side "does this prop exist" check -- same as
-- Config.SpikeStrips.Model today, which also isn't validated beyond the
-- client's own RequestModel/HasModelLoaded failure path -- so this only
-- guards against obviously-malformed input.
lib.callback.register('cm-police:server:addBarricadeModel', function(src, modelName)
    local member, actorCid = authorizedManager(src)
    if not member then return false, 'Your rank cannot manage barricade models.' end
    local clean = tostring(modelName or ''):gsub('%s+', '')
    if clean == '' or #clean > 64 or not clean:match('^[%a_][%w_]*$') then
        return false, 'Invalid model name.'
    end
    MySQL.insert.await('INSERT INTO cm_police_barricade_catalog (model_name, added_by) VALUES (?, ?)', { clean, actorCid })
    log(actorCid, 'barricade_model_added', { model = clean })
    broadcastCatalog()
    return true, 'Barricade model added.'
end)

lib.callback.register('cm-police:server:removeBarricadeModel', function(src, catalogId)
    local member, actorCid = authorizedManager(src)
    if not member then return false, 'Your rank cannot manage barricade models.' end
    catalogId = tonumber(catalogId)
    if not catalogId then return false, 'Invalid model.' end
    MySQL.update.await('DELETE FROM cm_police_barricade_catalog WHERE id = ?', { catalogId })
    log(actorCid, 'barricade_model_removed', { catalogId = catalogId })
    broadcastCatalog()
    return true, 'Barricade model removed.'
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_barricade_catalog (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        model_name VARCHAR(64) NOT NULL,
        added_by VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Seed fresh installs only -- same "never touch existing rows" spirit
    -- as Config.Ranks' own seeding (server/main.lua's setupDatabase()).
    local existingCount = MySQL.scalar.await('SELECT COUNT(*) FROM cm_police_barricade_catalog') or 0
    if tonumber(existingCount) == 0 then
        for _, modelName in ipairs(Config.Barricades.DefaultModels or {}) do
            MySQL.insert.await('INSERT INTO cm_police_barricade_catalog (model_name, added_by) VALUES (?, ?)', { modelName, nil })
        end
    end
    CatalogReady = true
    PoliceSchemaMarkReady('barricades')
end)
