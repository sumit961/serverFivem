-- cm-spawn/server/main.lua
-- Production-ready spawn selector for CM Framework.
-- Owns spawn selection and spawn completion only. Character data belongs to
-- cm-playerdata, climate/time belongs to cm-climatime, admin tools belong to cm-admin.

local PendingSpawns = {}
local SelectRate = {}
local RESOURCE = 'CM-SPAWN'

local function cfg(key, fallback)
    if Config and Config[key] ~= nil then return Config[key] end
    return fallback
end

local function dprint(message)
    if cfg('Debug', false) or cfg('VerboseLogs', false) then
        print(('[%s] %s'):format(RESOURCE, tostring(message)))
    end
end

local function warn(message)
    print(('[%s] WARNING: %s'):format(RESOURCE, tostring(message)))
end

local function err(message)
    print(('[%s] ERROR: %s'):format(RESOURCE, tostring(message)))
end

local function notify(src, message, nType)
    if not src or src <= 0 then return end
    if GetResourceState('cm-core') == 'started' then
        local ok = pcall(function()
            exports['cm-core']:Notify(src, message, nType or 'error', 5000)
        end)
        if ok then return end
    end
    TriggerClientEvent('chat:addMessage', src, { args = { RESOURCE, message } })
end

local function getSpawnByKey(key)
    for _, spawn in ipairs(SpawnPoints or {}) do
        if spawn.key == key then return spawn end
    end
    return nil
end

local function clonePublicSpawn(spawn)
    return {
        key = spawn.key,
        label = spawn.label,
        description = spawn.description,
        icon = spawn.icon,
        locked = spawn.locked == true,
        lockedReason = spawn.lockedReason,
        color = spawn.color or 'blue',
        image = spawn.image,
        groupType = spawn.groupType,
        orgType = spawn.orgType,
        dynamic = spawn.dynamic
        -- Do not send coordinates to NUI. Server resolves selected coords again.
    }
end

local function isHasSpawned(value)
    if value == true then return true end
    if value == false or value == nil then return false end
    local n = tonumber(value)
    if n ~= nil then return n == 1 end
    local text = tostring(value):lower()
    return text == '1' or text == 'true' or text == 'yes'
end

local function decodeCoords(value)
    if not value then return nil end
    if type(value) == 'string' then
        if value == '' or value == '{}' or value == '[]' or value == 'null' then return nil end
        local ok, decoded = pcall(json.decode, value)
        if not ok then return nil end
        value = decoded
    end
    if type(value) ~= 'table' then return nil end

    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    local h = tonumber(value.h or value.heading or value.w or value[4]) or 0.0
    if not x or not y or not z then return nil end
    return vector4(x, y, z, h)
end

local function defaultDeadFallbackCoords()
    local respawn = Config and Config.DeadFallbackSpawn or nil
    if type(respawn) == 'table' then
        local c = decodeCoords(respawn)
        if c then return c end
    end
    return vector4(298.2, -584.1, 43.3, 70.0)
end

local function resolveDeadCoords(rowLastPosition, rowDeathLocation)
    return decodeCoords(rowDeathLocation) or decodeCoords(rowLastPosition) or defaultDeadFallbackCoords()
end

local function getCharacterId(src)
    if GetResourceState('cm-playerdata') == 'started' then
        local ok, charId = pcall(function()
            return exports['cm-playerdata']:GetCharacterId(src)
        end)
        if ok and charId then return tonumber(charId) end
    end

    local ply = Player(src)
    if ply and ply.state then
        return tonumber(ply.state.charId or ply.state.characterId)
    end
    return nil
end

local function isCharacterLoaded(src)
    if GetResourceState('cm-playerdata') ~= 'started' then return false end

    local ok, loaded = pcall(function()
        return exports['cm-playerdata']:IsCharacterLoaded(src)
    end)
    if ok and loaded ~= nil then return loaded == true end

    ok, loaded = pcall(function()
        return exports['cm-playerdata']:IsLoaded(src)
    end)
    return ok and loaded == true
end

local function getCharacterData(src)
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    local ok, data = pcall(function()
        return exports['cm-playerdata']:GetCharacterData(src)
    end)
    if ok and type(data) == 'table' then return data end
    return nil
end

local function decodeAppearance(value)
    if not value or value == '' or value == 'null' then return nil end
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' then return nil end

    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then return decoded end
    return nil
end


local function getPlayerdataSpawnOverride(src, requestedKey, rowLastPosition, rowDeathLocation)
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end

    local ok, override = pcall(function()
        return exports['cm-playerdata']:GetSpawnOverride(src, requestedKey)
    end)

    if ok and type(override) == 'table' and override.coords then
        local coords = decodeCoords(override.coords)
        if coords then
            override.coords = coords
            return override
        end
    end

    -- Compatibility fallback for older cm-playerdata versions.
    local isDead = false
    ok, isDead = pcall(function()
        return exports['cm-playerdata']:IsDead(src)
    end)
    if not ok or isDead ~= true then return nil end

    local data = getCharacterData(src) or {}
    local coords = decodeCoords(data.deathLocation) or resolveDeadCoords(rowLastPosition, rowDeathLocation)
    if not coords then return nil end

    return {
        forced = true,
        reason = 'dead_character',
        key = 'dead_location',
        requestedKey = requestedKey,
        label = 'LAST BODY LOCATION',
        description = 'You are still down. You will return to where you died.',
        coords = coords,
        isDead = true
    }
end

local function getMetadata(src, key)
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    local ok, value = pcall(function()
        return exports['cm-playerdata']:GetMetadata(src, key)
    end)
    if ok then return value end
    return nil
end

local function ensureHasSpawnedColumn()
    if cfg('AutoEnsureHasSpawnedColumn', true) == false then return end
    if GetResourceState('cm-core') ~= 'started' then return end
    pcall(function()
        exports['cm-core']:Update('ALTER TABLE characters ADD COLUMN IF NOT EXISTS has_spawned TINYINT(1) NOT NULL DEFAULT 0', {})
    end)
end

CreateThread(function()
    ensureHasSpawnedColumn()
end)

local function markSpawned(charId)
    if not charId then return end
    pcall(function()
        exports['cm-core']:Update('UPDATE characters SET has_spawned = 1 WHERE id = ?', { charId })
    end)
end

local function resetPlayerWorldState(src, complete)
    src = tonumber(src)
    if not src or src <= 0 then return end

    SetPlayerRoutingBucket(src, 0)

    local ply = Player(src)
    if ply and ply.state then
        ply.state:set('selectorBucket', 0, true)
        ply.state:set('isInCharacterSelector', false, true)
        ply.state:set('isInSpawnSelector', false, true)
        ply.state:set('spawnSelectorOpen', false, true)
        ply.state:set('cmSpawnOpen', false, true)
        ply.state:set('cmSpawnActive', complete ~= true, true)
        ply.state:set('characterFullySpawned', complete == true, true)
        ply.state:set('cmSpawned', complete == true, true)
        ply.state:set('isSpawned', complete == true, true)
        ply.state:set('skipPositionSave', complete ~= true, true)
    end
end

local function setSpawnSelectorState(src, open)
    src = tonumber(src)
    if not src or src <= 0 then return end
    local ply = Player(src)
    if ply and ply.state then
        ply.state:set('isInSpawnSelector', open == true, true)
        ply.state:set('spawnSelectorOpen', open == true, true)
        ply.state:set('cmSpawnOpen', open == true, true)
        ply.state:set('cmSpawnActive', open == true, true)
        ply.state:set('characterFullySpawned', false, true)
        ply.state:set('cmSpawned', false, true)
        ply.state:set('isSpawned', false, true)
        ply.state:set('skipPositionSave', true, true)
    end
end

local function getOrgFromState(src)
    local ply = Player(src)
    if not ply or not ply.state then return nil end

    local org = ply.state.organization or ply.state.org
    if type(org) == 'table' then return org end

    local orgId = ply.state.organizationId or ply.state.orgId
    local orgName = ply.state.organizationName or ply.state.orgName
    local orgType = ply.state.organizationType or ply.state.orgType
    local orgSpawn = ply.state.organizationSpawn or ply.state.orgSpawn
    if orgId or orgName or orgSpawn then
        return {
            id = orgId,
            name = orgName,
            type = orgType,
            spawn = orgSpawn,
            coords = orgSpawn
        }
    end
    return nil
end

local function getOrgFromPlayerdata(src)
    local data = getCharacterData(src) or {}
    local meta = data.metadata
    if type(meta) == 'string' then
        local ok, decoded = pcall(json.decode, meta)
        if ok and type(decoded) == 'table' then meta = decoded end
    end
    if type(meta) ~= 'table' then meta = {} end

    local org = data.organization or data.org or meta.organization or meta.org or getMetadata(src, 'organization') or getMetadata(src, 'org')
    if type(org) == 'table' then return org end

    local orgId = data.organization_id or data.org_id or data.organizationId or data.orgId or meta.organization_id or meta.org_id or getMetadata(src, 'organization_id') or getMetadata(src, 'org_id')
    local orgName = data.organization_name or data.org_name or data.organizationName or data.orgName or meta.organization_name or meta.org_name or getMetadata(src, 'organization_name') or getMetadata(src, 'org_name')
    local orgType = data.organization_type or data.org_type or data.organizationType or data.orgType or meta.organization_type or meta.org_type or getMetadata(src, 'organization_type') or getMetadata(src, 'org_type')
    local orgSpawn = data.organization_spawn or data.org_spawn or data.organizationSpawn or data.orgSpawn or meta.organization_spawn or meta.org_spawn or getMetadata(src, 'organization_spawn') or getMetadata(src, 'org_spawn')

    if orgId or orgName or orgSpawn then
        return {
            id = orgId,
            name = orgName,
            type = orgType,
            spawn = orgSpawn,
            coords = orgSpawn
        }
    end
    return nil
end

local function getOrgFromFutureResource(src, charId)
    local settings = Config and Config.OrganizationSpawn or {}
    local resourceName = settings.resource or 'cm-organizations'
    if GetResourceState(resourceName) ~= 'started' then return nil end

    local attempts = {
        function() return exports[resourceName]:GetSpawnForCharacter(charId) end,
        function() return exports[resourceName]:GetCharacterSpawn(charId) end,
        function() return exports[resourceName]:GetMemberSpawn(src) end,
        function() return exports[resourceName]:GetMemberOrganization(src) end,
        function() return exports[resourceName]:GetCharacterOrganization(charId) end,
    }

    for _, fn in ipairs(attempts) do
        local ok, result = pcall(fn)
        if ok and result then return result end
    end
    return nil
end

local function normalizeOrganizationSpawn(src, charId)
    local settings = Config and Config.OrganizationSpawn or {}
    if settings.enabled == false then return nil end

    local org = getOrgFromFutureResource(src, charId) or getOrgFromState(src) or getOrgFromPlayerdata(src)
    if not org or type(org) ~= 'table' then return nil end

    local spawn = org.spawn or org.spawnPoint or org.spawn_point or org.coords or org.location or org.base
    if type(spawn) == 'table' and (spawn.coords or spawn.spawn) then
        if spawn.coords then org.spawn = spawn.coords end
        if spawn.spawn then org.spawn = spawn.spawn end
        org.name = org.name or spawn.name or spawn.label
        org.type = org.type or spawn.type or spawn.orgType
        org.icon = org.icon or spawn.icon
        org.color = org.color or spawn.color
        org.image = org.image or spawn.image
    end

    local coords = decodeCoords(org.spawn or org.coords or org.location or org.base)
    if not coords then return nil end

    local orgType = tostring(org.type or org.orgType or org.category or 'organization')
    local orgName = tostring(org.name or org.label or org.title or settings.defaultLabel or 'Organization')

    return {
        key = 'organization',
        label = string.upper(orgName),
        description = ('Spawn at your %s base.'):format(orgType),
        coords = coords,
        locked = false,
        icon = org.icon or settings.defaultIcon or 'fa-building-shield',
        color = org.color or settings.defaultColor or 'cyan',
        image = org.image or settings.defaultImage or 'assets/organization.svg',
        groupType = 'organization',
        orgType = orgType,
        orgId = org.id or org.orgId or org.organizationId
    }
end

local function resolveSpawnForKey(src, charId, spawnKey, lastPosition, hasSpawned)
    if spawnKey == 'organization' then
        local orgSpawn = normalizeOrganizationSpawn(src, charId)
        if orgSpawn then return orgSpawn end
        local base = getSpawnByKey('organization') or {}
        local copy = clonePublicSpawn(base)
        copy.locked = true
        copy.lockedReason = (Config.OrganizationSpawn and Config.OrganizationSpawn.fallbackLockedReason) or 'Organization spawn unavailable'
        return copy
    end

    local base = getSpawnByKey(spawnKey)
    if not base then return nil end

    local spawn = clonePublicSpawn(base)
    spawn.coords = base.coords

    if spawnKey == 'last' then
        if not isHasSpawned(hasSpawned) then
            spawn.locked = true
            spawn.lockedReason = 'Available after first spawn'
            return spawn
        end
        local coords = decodeCoords(lastPosition)
        if coords then
            spawn.coords = coords
            spawn.locked = false
        else
            spawn.locked = true
            spawn.lockedReason = 'No saved position'
        end
    end

    return spawn
end

function BuildSpawnList(src, lastPos, hasSpawned, charId)
    local isFirstTime = not isHasSpawned(hasSpawned)
    local spawns = {}

    for _, spawn in ipairs(SpawnPoints or {}) do
        local available = resolveSpawnForKey(src, charId, spawn.key, lastPos, hasSpawned)
        if available then
            available.coords = nil -- never expose final coords to browser UI
            table.insert(spawns, available)
        end
    end

    dprint(('BuildSpawnList src=%s firstTime=%s count=%s'):format(src, tostring(isFirstTime), #spawns))
    return spawns, isFirstTime
end

local function getAppearance(charId)
    local row = exports['cm-core']:Single('SELECT appearance_json FROM characters WHERE id = ? LIMIT 1', { charId })
    return row and decodeAppearance(row.appearance_json) or nil
end

function DoSpawn(src, charId)
    if not PendingSpawns[src] then return end
    PendingSpawns[src] = nil

    src = tonumber(src)
    charId = tonumber(charId) or getCharacterId(src)
    if not src or not charId then
        err('DoSpawn missing source or character ID')
        return
    end

    local char = exports['cm-core']:Single(
        'SELECT first_name, last_name, cash, bank, is_dead, death_location, last_position, appearance_json, tutorial_completed, tutorial_step, has_spawned FROM characters WHERE id = ? LIMIT 1',
        { charId }
    )

    if not char then
        err('Character not found: ' .. tostring(charId))
        return
    end

    local appearance = decodeAppearance(char.appearance_json)

    local spawns, isFirstTime = BuildSpawnList(src, char.last_position, char.has_spawned, charId)
    local deadOverride = getPlayerdataSpawnOverride(src, 'selector', char.last_position, char.death_location)
        or ((tonumber(char.is_dead) or 0) == 1 and {
            forced = true,
            reason = 'dead_character',
            key = 'dead_location',
            requestedKey = 'selector',
            label = 'LAST BODY LOCATION',
            description = 'You are still down. You will return to where you died.',
            coords = resolveDeadCoords(char.last_position, char.death_location),
            isDead = true
        } or nil)

    -- Dead characters are still allowed to see the spawn page, but any selected
    -- card will be forced server-side to their last/death location. This keeps
    -- the RP body location correct after reconnect and lets cm-playerdata show
    -- the deathscreen only after the spawn page closes.
    if deadOverride and deadOverride.coords then
        setSpawnSelectorState(src, true)
        TriggerClientEvent('cm-spawn:client:openSelector', src, spawns, appearance, {
            name = ((char.first_name or '') .. ' ' .. (char.last_name or '')):gsub('^%s+', ''):gsub('%s+$', ''),
            cash = char.cash or 0,
            bank = char.bank or 0,
            deadMode = true,
            deadNotice = 'You are still down. Any spawn choice will return you to your last body location.'
        })
        return
    end

    if isFirstTime then
        local defaultKey = cfg('DefaultFirstSpawn', 'hotel')
        local default = resolveSpawnForKey(src, charId, defaultKey, char.last_position, char.has_spawned)
        if not default or default.locked or not default.coords then
            default = resolveSpawnForKey(src, charId, 'hotel', char.last_position, char.has_spawned)
        end
        if not default or not default.coords then
            err('No valid first spawn found')
            return
        end
        resetPlayerWorldState(src, false)
        TriggerClientEvent('cm-spawn:client:spawn', src, default.key or 'hotel', true, default.coords, appearance)
    else
        local orgSpawn = normalizeOrganizationSpawn(src, charId)
        setSpawnSelectorState(src, true)
        TriggerClientEvent('cm-spawn:client:openSelector', src, spawns, appearance, {
            name = ((char.first_name or '') .. ' ' .. (char.last_name or '')):gsub('^%s+', ''):gsub('%s+$', ''),
            cash = char.cash or 0,
            bank = char.bank or 0,
            organization = orgSpawn and {
                label = orgSpawn.label,
                type = orgSpawn.orgType,
                id = orgSpawn.orgId
            } or nil
        })
    end
end

AddEventHandler('cm-core:characterLoaded', function(src, charId)
    src = tonumber(src)
    if not src then return end
    PendingSpawns[src] = { charId = charId, ready = false, createdAt = os.time() }

    CreateThread(function()
        local attempts = 0
        while attempts < 60 do
            Wait(100)
            attempts = attempts + 1
            if isCharacterLoaded(src) then
                if PendingSpawns[src] and not PendingSpawns[src].ready then
                    PendingSpawns[src].ready = true
                    DoSpawn(src, charId)
                end
                return
            end
        end

        if PendingSpawns[src] and not PendingSpawns[src].ready then
            warn('Timeout waiting for cm-playerdata; continuing spawn for src=' .. tostring(src))
            PendingSpawns[src].ready = true
            DoSpawn(src, charId)
        end
    end)
end)

AddEventHandler('cm-playerdata:server:readyForSpawn', function(src, data)
    src = tonumber(src)
    if not src then return end
    if PendingSpawns[src] and not PendingSpawns[src].ready then
        PendingSpawns[src].ready = true
        DoSpawn(src, (data and (data.charId or data.id)) or PendingSpawns[src].charId)
    end
end)

AddEventHandler('playerDropped', function()
    PendingSpawns[source] = nil
    SelectRate[source] = nil
end)

local function isSelectRateLimited(src)
    local now = GetGameTimer and GetGameTimer() or math.floor(os.clock() * 1000)
    local last = SelectRate[src] or 0
    if now - last < 1200 then return true end
    SelectRate[src] = now
    return false
end

RegisterNetEvent('cm-spawn:server:selectSpawn', function(spawnKey)
    local src = source
    if isSelectRateLimited(src) then return end

    if type(spawnKey) ~= 'string' or #spawnKey > 40 then
        warn('Invalid spawn key payload from src=' .. tostring(src))
        return
    end

    local charId = getCharacterId(src)
    if not charId then
        err('No charId for player ' .. tostring(src))
        return
    end

    local row = exports['cm-core']:Single('SELECT is_dead, death_location, last_position, has_spawned, appearance_json FROM characters WHERE id = ? LIMIT 1', { charId })
    if not row then
        err('No character row for spawn select: ' .. tostring(charId))
        return
    end

    local deadOverride = getPlayerdataSpawnOverride(src, spawnKey, row.last_position, row.death_location)
        or ((tonumber(row.is_dead) or 0) == 1 and {
            forced = true,
            reason = 'dead_character',
            key = 'dead_location',
            requestedKey = spawnKey,
            coords = resolveDeadCoords(row.last_position, row.death_location),
            isDead = true
        } or nil)

    if deadOverride and deadOverride.coords then
        resetPlayerWorldState(src, false)
        TriggerClientEvent('cm-spawn:client:spawn', src, 'dead_location', false, deadOverride.coords, decodeAppearance(row.appearance_json))
        return
    end

    local spawnData = resolveSpawnForKey(src, charId, spawnKey, row.last_position, row.has_spawned)
    if not spawnData then
        warn('Invalid spawn key from src=' .. tostring(src) .. ' spawn=' .. tostring(spawnKey))
        notify(src, 'Invalid spawn location.', 'error')
        return
    end

    if spawnData.locked then
        warn('Blocked locked spawn src=' .. tostring(src) .. ' spawn=' .. tostring(spawnKey))
        notify(src, spawnData.lockedReason or 'This spawn is locked.', 'error')
        return
    end

    local coords = spawnData.coords
    if not coords then
        local fallback = resolveSpawnForKey(src, charId, 'hotel', row.last_position, row.has_spawned)
        coords = fallback and fallback.coords or vector4(324.0, -212.0, 54.0, 0.0)
        spawnKey = 'hotel'
    end

    resetPlayerWorldState(src, false)
    TriggerClientEvent('cm-spawn:client:spawn', src, spawnKey, false, coords, decodeAppearance(row.appearance_json))
end)

RegisterNetEvent('cm-spawn:server:resetWorldState', function(complete)
    resetPlayerWorldState(source, complete == true)
end)

RegisterNetEvent('cm-spawn:server:spawnComplete', function()
    local src = source
    resetPlayerWorldState(src, true)

    local charId = getCharacterId(src)
    if not charId then return end
    markSpawned(charId)

    -- Net-safe client confirmation. cm-playerdata waits for this before
    -- showing a restored deathscreen, so it never appears over the spawn UI.
    TriggerClientEvent('cm-spawn:client:spawnComplete', src, charId)

    TriggerEvent('cm-spawn:server:spawned', src, charId)
    if GetResourceState('cm-playerdata') == 'started' then
        pcall(function()
            TriggerEvent('cm-playerdata:server:spawned', src, charId)
        end)
    end
end)

RegisterNetEvent('cm-spawn:server:tutorialComplete', function()
    local src = source
    local charId = getCharacterId(src)
    if not charId then return end
    exports['cm-core']:Update('UPDATE characters SET tutorial_completed = 1, tutorial_step = 999 WHERE id = ?', { charId })
    dprint('Tutorial complete char=' .. tostring(charId))
end)

if cfg('EnableDevCommands', false) then
    local function sendCommandLine(src, msg)
        print(msg)
        if src and src > 0 then
            TriggerClientEvent('chat:addMessage', src, { args = { RESOURCE, msg } })
        end
    end

    RegisterCommand('checkbuckets', function(src)
        if src and src > 0 and GetResourceState('cm-admin') == 'started' then
            local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(src, 'spawn.debug') end)
            if not ok or not allowed then return end
        end
        for _, id in ipairs(GetPlayers()) do
            sendCommandLine(src, ('[bucket] player=%s bucket=%s'):format(id, GetPlayerRoutingBucket(tonumber(id))))
        end
    end, false)

    RegisterCommand('fixbucket', function(src, args)
        if src and src > 0 and GetResourceState('cm-admin') == 'started' then
            local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(src, 'spawn.debug') end)
            if not ok or not allowed then return end
        end
        local target = tonumber(args and args[1]) or src
        if not target or target <= 0 then
            sendCommandLine(src, '[fixbucket] Usage from console: fixbucket PLAYER_ID')
            return
        end

        resetPlayerWorldState(target, true)
        sendCommandLine(src, ('[fixbucket] Player %s moved to bucket 0 and spawn state reset'):format(target))
    end, false)
end

exports('BuildSpawnList', BuildSpawnList)
exports('ResolveOrganizationSpawn', normalizeOrganizationSpawn)
exports('GetSpawnByKey', getSpawnByKey)
