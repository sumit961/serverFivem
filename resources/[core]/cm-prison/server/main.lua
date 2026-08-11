local Ready = false
local Assigning = false

local function prisonLog(message)
    print(('[cm-prison] %s'):format(tostring(message)))
end

local function characterId(src)
    local ok, value = pcall(function() return exports['cm-playerdata']:GetCharacterId(tonumber(src)) end)
    return ok and value and tostring(value) or nil
end

local function sourceByCharacterId(cid)
    for _, value in ipairs(GetPlayers()) do
        if characterId(value) == tostring(cid) then return tonumber(value) end
    end
end

local function validLocation(value)
    return type(value) == 'table' and tonumber(value.x) and tonumber(value.y) and tonumber(value.z)
end

local function locationPayload(value)
    if not validLocation(value) then return nil end
    return { x = tonumber(value.x), y = tonumber(value.y), z = tonumber(value.z),
        heading = tonumber(value.heading) or 0.0, bucket = math.max(0, math.floor(tonumber(value.bucket) or 0)) }
end

local function setPrisonState(src, row)
    if not GetPlayerName(src) then return end
    if not row then return Player(src).state:set('cmPrison', false, true) end
    local spawn = type(row.spawn_data) == 'string' and json.decode(row.spawn_data) or row.spawn_data
    local release = type(row.release_data) == 'string' and json.decode(row.release_data) or row.release_data
    Player(src).state:set('cmPrison', {
        active = true, releaseAt = tonumber(row.release_epoch) or 0,
        arrestedBy = tostring(row.arrested_by_name or 'Police Department'):sub(1, 80),
        spawn = locationPayload(spawn), release = locationPayload(release),
    }, true)
end

local function movePlayerToPrison(src, location)
    location = locationPayload(location)
    if not location or not GetPlayerName(src) then return false end
    SetPlayerRoutingBucket(src, location.bucket)
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        SetEntityCoords(ped, location.x, location.y, location.z, false, false, false, false)
        SetEntityHeading(ped, location.heading)
    end
    TriggerClientEvent('cm-prison:client:enter', src, location)
    return true
end

local function releaseOnlinePlayer(src, location)
    location = locationPayload(type(location) == 'string' and json.decode(location) or location)
    setPrisonState(src, nil)
    if location then SetPlayerRoutingBucket(src, location.bucket) end
    TriggerClientEvent('cm-prison:client:release', src, location)
end

local function releaseCharacter(cid, reason)
    cid = tostring(cid or '')
    if cid == '' then return false, 'invalid_character' end
    local row = MySQL.single.await([[SELECT release_data FROM cm_prison_sentences
        WHERE character_id=? AND status='active' LIMIT 1]], { cid })
    if not row then return false, 'not_imprisoned' end
    local changed = MySQL.update.await([[UPDATE cm_prison_sentences SET status='released', released_at=NOW(), release_at=NOW()
        WHERE character_id=? AND status='active']], { cid })
    if tonumber(changed) ~= 1 then return false, 'release_conflict' end
    local src = sourceByCharacterId(cid)
    if src then releaseOnlinePlayer(src, row.release_data) end
    TriggerEvent('cm-prison:server:released', cid, tostring(reason or 'administrative_release'))
    return true
end

local function confiscatePrisonItems(src, cid)
    if GetResourceState('cm-inventory') ~= 'started' or GetResourceState('cm-weapons') ~= 'started'
        or GetResourceState('cm-items') ~= 'started' then
        prisonLog(('confiscation delayed for character %s: inventory catalogs are unavailable'):format(cid))
        return false
    end
    local inventoryOk, inventory = pcall(function() return exports['cm-inventory']:GetInventory(src) end)
    local weaponsOk, weapons = pcall(function() return exports['cm-weapons']:GetAllWeapons(true) end)
    local ammoOk, ammo = pcall(function() return exports['cm-weapons']:GetAllAmmo(true) end)
    local itemsOk, itemDefinitions = pcall(function() return exports['cm-items']:GetAllItems() end)
    if not inventoryOk or not weaponsOk or not ammoOk or not itemsOk or type(inventory) ~= 'table'
        or type(weapons) ~= 'table' or type(ammo) ~= 'table' or type(itemDefinitions) ~= 'table' then
        prisonLog(('confiscation delayed for character %s: an authoritative catalog could not be read'):format(cid))
        return false
    end
    local prohibited = {}
    for _, row in ipairs(weapons) do prohibited[tostring(row.itemName or row.item_name or ''):lower()] = 'weapon' end
    for _, row in ipairs(ammo) do prohibited[tostring(row.itemName or row.item_name or ''):lower()] = 'ammo' end
    for name, definition in pairs(itemDefinitions) do
        if type(definition) == 'table' and definition.illegal == true then prohibited[tostring(name):lower()] = 'illegal' end
    end
    prohibited[''] = nil
    local totals = {}
    for _, row in ipairs(inventory.items or {}) do
        local name = tostring(row.item_name or row.itemName or ''):lower()
        local quantity = math.max(0, math.floor(tonumber(row.quantity) or 0))
        if prohibited[name] and quantity > 0 then totals[name] = (totals[name] or 0) + quantity end
    end
    local removed, failed = {}, {}
    for name, quantity in pairs(totals) do
        local ok, reason = exports['cm-inventory']:RemoveItem(src, name, quantity, nil, 'prison_intake_confiscation')
        if ok then removed[#removed + 1] = { item = name, quantity = quantity, category = prohibited[name] }
        else failed[#failed + 1] = { item = name, quantity = quantity, reason = tostring(reason) } end
    end
    prisonLog(('intake confiscation for character %s: removed=%d failed=%d'):format(cid, #removed, #failed))
    return #failed == 0
end

local function restore(src)
    local cid = characterId(src)
    if not Ready or not cid then return end
    local row = MySQL.single.await([[SELECT *, UNIX_TIMESTAMP(release_at) AS release_epoch
        FROM cm_prison_sentences WHERE character_id = ? AND status = 'active' LIMIT 1]], { cid })
    if row and (tonumber(row.release_epoch) or 0) > os.time() then
        if tonumber(row.items_confiscated) ~= 1 and confiscatePrisonItems(src, cid) then
            MySQL.update.await('UPDATE cm_prison_sentences SET items_confiscated=1 WHERE character_id=?', { cid })
        end
        setPrisonState(src, row)
        movePlayerToPrison(src, row.spawn_data)
    elseif row then
        MySQL.update.await("UPDATE cm_prison_sentences SET status='released', released_at=NOW() WHERE character_id=? AND status='active'", { cid })
        setPrisonState(src, nil)
    end
end

local function chooseSpawn(spawns)
    local best, bestCount
    for index, raw in ipairs(spawns or {}) do
        local spawn = locationPayload(raw)
        if spawn then
            local count = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_prison_sentences WHERE status='active' AND spawn_index=? AND release_at>NOW()", { index })) or 0
            if count < 2 and (not bestCount or count < bestCount) then best, bestCount = { index = index, location = spawn }, count end
        end
    end
    return best
end

exports('JailSuspect', function(officerSrc, targetSrc, minutes, _, config)
    officerSrc, targetSrc, minutes = tonumber(officerSrc), tonumber(targetSrc), math.floor(tonumber(minutes) or 0)
    if not Ready then return false, 'prison_unavailable' end
    if not officerSrc or not targetSrc or minutes < 1 or not GetPlayerName(officerSrc) or not GetPlayerName(targetSrc) then return false, 'target_disconnected' end
    local cid = characterId(targetSrc)
    if not cid then return false, 'target_disconnected' end
    config = type(config) == 'table' and config or {}
    while Assigning do Wait(0) end
    Assigning = true
    local selected = chooseSpawn(config.spawns)
    if not selected then Assigning = false return false, 'prison_full' end
    local release = locationPayload(config.release or config.intake)
    local arrestedBy = tostring(config.arrestedBy or 'Police Department'):gsub('[%c~]+', ' '):sub(1, 80)
    if arrestedBy == '' then arrestedBy = 'Police Department' end
    local releaseEpoch = os.time() + (minutes * 60)
    local ok, databaseError = pcall(function()
        MySQL.insert.await([[INSERT INTO cm_prison_sentences
            (character_id, officer_cid, arrested_by_name, reason, sentence_minutes, release_at, spawn_index, spawn_data, release_data, status)
            VALUES (?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?, ?, ?, 'active')
            ON DUPLICATE KEY UPDATE officer_cid=VALUES(officer_cid), arrested_by_name=VALUES(arrested_by_name), reason=VALUES(reason), sentence_minutes=VALUES(sentence_minutes),
            release_at=VALUES(release_at), spawn_index=VALUES(spawn_index), spawn_data=VALUES(spawn_data), release_data=VALUES(release_data),
            items_confiscated=0, status='active', released_at=NULL]],
            { cid, characterId(officerSrc), arrestedBy, tostring(config.reason or 'Police booking'), minutes, releaseEpoch,
                selected.index, json.encode(selected.location), release and json.encode(release) or nil })
    end)
    Assigning = false
    if not ok then
        prisonLog(('sentence insert failed for character %s: %s'):format(cid, tostring(databaseError)))
        return false, 'database_error'
    end
    local confiscated = confiscatePrisonItems(targetSrc, cid)
    if confiscated then MySQL.update.await('UPDATE cm_prison_sentences SET items_confiscated=1 WHERE character_id=?', { cid }) end
    setPrisonState(targetSrc, { release_epoch = releaseEpoch, arrested_by_name = arrestedBy,
        spawn_data = selected.location, release_data = release })
    if not movePlayerToPrison(targetSrc, selected.location) then
        prisonLog(('sentence persisted but player %s could not be moved; reconnect restore will retry'):format(targetSrc))
        return false, 'target_disconnected'
    end
    TriggerClientEvent('cm-playerdata:client:interactionNotify', targetSrc,
        ('You have been jailed for %d minutes.'):format(minutes), 'inform')
    return true
end)

exports('JailSelf', function(targetSrc, minutes, reason, timeoutMs, config)
    config = type(config) == 'table' and config or {}
    config.reason = reason or config.reason
    return exports['cm-prison']:JailSuspect(targetSrc, targetSrc, minutes, timeoutMs, config)
end)

exports('IsPrisoner', function(src)
    local state = Player(tonumber(src) or -1).state.cmPrison
    return type(state) == 'table' and state.active == true
end)

exports('GetActiveSentences', function()
    if not Ready then return nil, 'prison_unavailable' end
    return MySQL.query.await([[SELECT character_id, arrested_by_name, reason, sentence_minutes,
        UNIX_TIMESTAMP(release_at) AS release_epoch,
        GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), release_at)) AS remaining_seconds
        FROM cm_prison_sentences WHERE status='active' AND release_at>NOW() ORDER BY release_at ASC]]) or {}
end)

exports('ReduceSentence', function(cid, minutes)
    if not Ready then return false, 'prison_unavailable' end
    cid, minutes = tostring(cid or ''), math.floor(tonumber(minutes) or 0)
    if cid == '' or minutes < 1 or minutes > 43200 then return false, 'invalid_reduction' end
    local row = MySQL.single.await([[SELECT UNIX_TIMESTAMP(release_at) AS release_epoch
        FROM cm_prison_sentences WHERE character_id=? AND status='active' LIMIT 1]], { cid })
    if not row then return false, 'not_imprisoned' end
    local nextRelease = (tonumber(row.release_epoch) or os.time()) - (minutes * 60)
    if nextRelease <= os.time() then return releaseCharacter(cid, 'administrative_sentence_reduction') end
    local changed = MySQL.update.await([[UPDATE cm_prison_sentences SET release_at=FROM_UNIXTIME(?)
        WHERE character_id=? AND status='active']], { nextRelease, cid })
    local src = sourceByCharacterId(cid)
    if tonumber(changed) == 1 and src then
        local state = Player(src).state.cmPrison
        if type(state) == 'table' then
            state.releaseAt = nextRelease
            Player(src).state:set('cmPrison', state, true)
        end
    end
    return tonumber(changed) == 1, tonumber(changed) == 1 and nil or 'update_conflict'
end)

exports('ReleasePrisoner', function(cid)
    if not Ready then return false, 'prison_unavailable' end
    return releaseCharacter(cid, 'administrative_release')
end)

CreateThread(function()
    local schemaOk, schemaError = pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_prison_sentences (
        character_id VARCHAR(64) NOT NULL, officer_cid VARCHAR(64) NULL, arrested_by_name VARCHAR(80) NULL, reason VARCHAR(160) NULL,
        sentence_minutes INT UNSIGNED NOT NULL, release_at DATETIME NOT NULL, spawn_index INT UNSIGNED NOT NULL,
        spawn_data LONGTEXT NOT NULL, release_data LONGTEXT NULL, items_confiscated TINYINT(1) NOT NULL DEFAULT 0,
        status VARCHAR(16) NOT NULL DEFAULT 'active',
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, released_at DATETIME NULL,
        PRIMARY KEY(character_id), KEY idx_cm_prison_active(status, release_at), KEY idx_cm_prison_spawn(spawn_index, status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        local hasArrestedBy = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_prison_sentences' AND COLUMN_NAME = 'arrested_by_name']])) or 0
        if hasArrestedBy == 0 then
            MySQL.query.await("ALTER TABLE cm_prison_sentences ADD COLUMN arrested_by_name VARCHAR(80) NULL AFTER officer_cid")
        end
        local hasConfiscated = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_prison_sentences' AND COLUMN_NAME = 'items_confiscated']])) or 0
        if hasConfiscated == 0 then
            MySQL.query.await("ALTER TABLE cm_prison_sentences ADD COLUMN items_confiscated TINYINT(1) NOT NULL DEFAULT 0 AFTER release_data")
        end
    end)
    if not schemaOk then
        prisonLog(('database initialization failed; booking is disabled: %s'):format(tostring(schemaError)))
        return
    end
    Ready = true
    prisonLog('database ready')
    for _, value in ipairs(GetPlayers()) do restore(tonumber(value)) end
    while true do
        Wait(5000)
        local rows = MySQL.query.await("SELECT character_id, release_data FROM cm_prison_sentences WHERE status='active' AND release_at<=NOW()") or {}
        for _, row in ipairs(rows) do
            MySQL.update.await("UPDATE cm_prison_sentences SET status='released', released_at=NOW() WHERE character_id=? AND status='active'", { row.character_id })
            local src = sourceByCharacterId(row.character_id)
            if src then releaseOnlinePlayer(src, row.release_data) end
            TriggerEvent('cm-prison:server:released', tostring(row.character_id), 'sentence_complete')
        end
    end
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src) CreateThread(function() Wait(500); restore(tonumber(src)) end) end)
