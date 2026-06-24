-- cm-characters/server/main.lua
-- Safe exports for permanent character IDs.
-- Player(source) is only the temporary FiveM session ID; characters.id is the permanent RP ID.

local function getStateCharId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    local player = Player(src)
    if not player or not player.state then return nil end

    local charId = player.state.charId or player.state.characterId
    if not charId then return nil end

    return tostring(charId)
end

local function getCharacterByIdRaw(charId)
    if charId == nil then return nil end
    charId = tostring(charId)

    return exports['cm-core']:CacheRemember('char:' .. charId, 30, function()
        local result = exports['cm-core']:Query('SELECT * FROM characters WHERE id = ?', {charId})
        return result and result[1] or nil
    end)
end

exports('GetCurrentCharacterId', function(src)
    return getStateCharId(src)
end)

exports('GetCharacter', function(src)
    local charId = getStateCharId(src)
    if not charId then return nil end
    return getCharacterByIdRaw(charId)
end)

exports('GetCharacterById', function(charId)
    return getCharacterByIdRaw(charId)
end)

exports('GetCharactersByAccount', function(accountId)
    if accountId == nil then return {} end

    return exports['cm-core']:Query(
        'SELECT * FROM characters WHERE account_id = ? ORDER BY slot',
        {tostring(accountId)}
    ) or {}
end)

exports('GetCharacterByUniqueId', function(uniqueId)
    -- Backwards compatible alias. Your unique character ID is now characters.id.
    return getCharacterByIdRaw(uniqueId)
end)

-- Character selector scene editor persistence.
-- Saved file path: cm-characters/data/selector_scene.json
local SELECTOR_SCENE_FILE = 'data/selector_scene.json'

local function defaultSelectorScene()
    return {
        sceneId = 'fixed-night-preview',
        stream = { x = 927.4528, y = 11.8477, z = 113.5550, w = 296.7522 },
        walkStart = { x = 927.4528, y = 11.8477, z = 113.5550, w = 296.7522 },
        walkFinish = { x = 927.4528, y = 11.8477, z = 113.5550, w = 296.7522 },
        camera = { x = 931.2687, y = 14.1728, z = 114.5444, w = 296.7522 },
        camrotation = { x = -3.8893, y = 0.0000, z = 116.2193 },
        fov = 50.0,
        weather = 'CLEAR',
        time = { hours = 23, minutes = 0, seconds = 0 },
        idleDict = 'anim@heists@heist_corona@team_idles@male_a',
        idleAnim = 'idle'
    }
end

local function loadSelectorSceneConfig()
    local raw = LoadResourceFile(GetCurrentResourceName(), SELECTOR_SCENE_FILE)
    if not raw or raw == '' then return defaultSelectorScene() end

    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then return decoded end

    print('[CM-CHARACTERS] Failed to decode selector scene config, using default.')
    return defaultSelectorScene()
end

local function asNumber(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0.0 end
    return value
end

local function cleanVec4(v, fallback)
    fallback = type(fallback) == 'table' and fallback or {}
    v = type(v) == 'table' and v or {}
    return {
        x = asNumber(v.x, fallback.x),
        y = asNumber(v.y, fallback.y),
        z = asNumber(v.z, fallback.z),
        w = asNumber(v.w or v.h or v.heading, fallback.w or fallback.h or fallback.heading)
    }
end

local function cleanSceneConfig(data)
    local default = defaultSelectorScene()
    data = type(data) == 'table' and data or {}

    local config = {
        sceneId = tostring(data.sceneId or default.sceneId),
        stream = cleanVec4(data.stream, default.stream),
        walkStart = cleanVec4(data.walkStart, default.walkStart),
        walkFinish = cleanVec4(data.walkFinish, default.walkFinish),
        camera = cleanVec4(data.camera, default.camera),
        fov = math.max(10.0, math.min(90.0, asNumber(data.fov, default.fov))),
        weather = tostring(data.weather or default.weather):upper(),
        time = {
            hours = math.max(0, math.min(23, math.floor(asNumber(data.time and data.time.hours, default.time.hours)))),
            minutes = math.max(0, math.min(59, math.floor(asNumber(data.time and data.time.minutes, default.time.minutes)))),
            seconds = math.max(0, math.min(59, math.floor(asNumber(data.time and data.time.seconds, default.time.seconds))))
        },
        idleDict = tostring(data.idleDict or data.dict or default.idleDict),
        idleAnim = tostring(data.idleAnim or data.anim or default.idleAnim)
    }

    if type(data.camrotation) == 'table' then
        config.camrotation = {
            x = asNumber(data.camrotation.x, 0.0),
            y = asNumber(data.camrotation.y, 0.0),
            z = asNumber(data.camrotation.z, 0.0)
        }
    end

    return config
end

local function canEditSelectorScene(src)
    if src == 0 then return true end

    local okPerm, allowed = pcall(function()
        if GetResourceState('cm-auth') == 'started' then
            return exports['cm-auth']:HasPermission(src, 'characters.selector.edit')
        end
        return false
    end)
    if okPerm and allowed == true then return true end

    if IsPlayerAceAllowed(src, 'command.charselectedit') or IsPlayerAceAllowed(src, 'characters.selector.edit') then return true end

    return false
end

RegisterNetEvent('cm-characters:server:requestSelectorSceneConfig', function()
    local src = source
    TriggerClientEvent('cm-characters:client:selectorSceneConfig', src, loadSelectorSceneConfig())
end)

RegisterNetEvent('cm-characters:server:saveSelectorSceneConfig', function(data)
    local src = source
    if not canEditSelectorScene(src) then
        TriggerClientEvent('cm-characters:client:selectorSceneSaved', src, false, 'No permission to save selector scene.')
        return
    end

    local config = cleanSceneConfig(data)
    local encoded = json.encode(config)
    local ok = SaveResourceFile(GetCurrentResourceName(), SELECTOR_SCENE_FILE, encoded, -1)

    if ok then
        print(('[CM-CHARACTERS] Selector scene saved by %s to %s'):format(tostring(src), SELECTOR_SCENE_FILE))
        TriggerClientEvent('cm-characters:client:selectorSceneSaved', src, true, 'Selector scene saved. Restart/reopen selector to use it everywhere.', config)
    else
        TriggerClientEvent('cm-characters:client:selectorSceneSaved', src, false, 'Save failed. Check resource file permissions.')
    end
end)

RegisterCommand('charselectscene', function(src)
    TriggerClientEvent('cm-characters:client:selectorSceneConfig', src, loadSelectorSceneConfig())
end, false)

-- Selector private dimension/routing bucket.
-- During character selection the player is moved to a private bucket equal to their server ID.
-- This prevents other players/NPC previews from sharing the same selector scene.
RegisterNetEvent('cm-characters:server:enterSelectorBucket', function()
    local src = source
    local bucket = tonumber(src) or 0
    if bucket < 1 then bucket = 0 end
    SetPlayerRoutingBucket(src, bucket)
    Player(src).state:set('selectorBucket', bucket, true)
    Player(src).state:set('isInCharacterSelector', true, true)
    Player(src).state:set('characterFullySpawned', false, true)
    Player(src).state:set('skipPositionSave', true, true)
    print(('[CM-CHARACTERS] selector bucket set: src=%s bucket=%s'):format(src, bucket))
end)

RegisterNetEvent('cm-characters:server:leaveSelectorBucket', function()
    local src = source
    SetPlayerRoutingBucket(src, 0)
    Player(src).state:set('selectorBucket', 0, true)
    Player(src).state:set('isInCharacterSelector', false, true)
    print(('[CM-CHARACTERS] selector bucket reset: src=%s bucket=0'):format(src))
end)

AddEventHandler('playerDropped', function()
    local src = source
    if src then
        pcall(function() SetPlayerRoutingBucket(src, 0) end)
    end
end)
