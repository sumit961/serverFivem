-- cm-playerdata/server/main.lua
-- Stable v1.3-safe upgrade for your existing CM framework. No hunger/thirst/stress.
-- Uses oxmysql directly to avoid cm-core export call-style issues.

local Config = CMPlayerData.Config
local PlayerData = {}
local PendingHandshakes = {} -- [targetSrc] = { from = src, expires = ms }
local PendingTreatments = {} -- [treaterSrc] = { target = src, startedAt = ms, duration = ms }
local LastEventUse = {}

local function Debug(msg)
    if Config.Debug then
        print('[CM-PLAYERDATA] ' .. tostring(msg))
    end
end

local function Log(level, message, metadata)
    metadata = metadata or {}
    local ok = pcall(function()
        exports['cm-core']:Log('cm-playerdata', level, message, metadata)
    end)
    if not ok then
        print(('[CM-PLAYERDATA] %s: %s'):format(level or 'info', message or ''))
    end
end

local function Clamp(value, min, max)
    value = tonumber(value) or min
    if value < min then return min end
    if value > max then return max end
    return value
end

local function RateLimit(src, key, ms)
    local now = GetGameTimer()
    local id = tostring(src) .. ':' .. key
    if LastEventUse[id] and (now - LastEventUse[id]) < ms then
        return false
    end
    LastEventUse[id] = now
    return true
end

local function ClearRateLimits(src)
    local prefix = tostring(src) .. ':'
    for key in pairs(LastEventUse) do
        if key:sub(1, #prefix) == prefix then
            LastEventUse[key] = nil
        end
    end
end

local function HasAce(src, ace)
    if src <= 0 then return true end
    return IsPlayerAceAllowed(src, ace) == true
end

local function GetServerPedHealth(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local health = GetEntityHealth(ped)
    if not health or health <= 0 then return nil end
    return health
end

local function EncodeJson(value)
    if value == nil then return nil end
    local ok, encoded = pcall(json.encode, value)
    return ok and encoded or nil
end

local function DecodeJson(value)
    if not value or value == '' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or nil
end

local function BuildDisplayName(firstName, lastName)
    local first = tostring(firstName or '')
    local last = tostring(lastName or '')
    local name = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if name == '' then return 'Unknown' end
    return name
end


local function GetCharId(src)
    src = tonumber(src)
    if not src then return nil end

    local data = PlayerData[src]
    if data and data.charId then
        return tonumber(data.charId)
    end

    local ok, state = pcall(function() return Player(src).state end)
    if not ok or not state then return nil end

    return tonumber(state.charId or state.characterId or state.rpId)
end

local function SetState(src, key, value, replicated)
    Player(src).state:set(key, value, replicated ~= false)
end

local function PushUpdate(src, key, value)
    TriggerClientEvent('cm-playerdata:client:update', src, key, value)
end

local function EnsureSchema()
    local alters = {
        "ALTER TABLE characters ADD COLUMN IF NOT EXISTS health INT DEFAULT 200",
        "ALTER TABLE characters ADD COLUMN IF NOT EXISTS armor INT DEFAULT 0",
        "ALTER TABLE characters ADD COLUMN IF NOT EXISTS is_dead TINYINT(1) DEFAULT 0",
        "ALTER TABLE characters ADD COLUMN IF NOT EXISTS death_count INT DEFAULT 0",
        "ALTER TABLE characters ADD COLUMN IF NOT EXISTS last_position LONGTEXT NULL",
        "ALTER TABLE characters ADD COLUMN IF NOT EXISTS metadata LONGTEXT NULL"
    }

    for _, sql in ipairs(alters) do
        pcall(function()
            MySQL.query.await(sql)
        end)
    end

    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS playerdata_audit (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                character_id VARCHAR(64) NULL,
                action VARCHAR(64) NOT NULL,
                data LONGTEXT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_character_id (character_id),
                INDEX idx_action (action)
            )
        ]])
    end)

    Debug('Schema checked')
end

local function Audit(src, action, data)
    local charId = GetCharId(src)
    pcall(function()
        MySQL.insert.await(
            'INSERT INTO playerdata_audit (character_id, action, data) VALUES (?, ?, ?)',
            { charId, action, EncodeJson(data or {}) }
        )
    end)
end

local function ApplyState(src)
    local data = PlayerData[src]
    if not data then return end

    local charId = tonumber(data.charId)
    if charId then
        SetState(src, 'charId', charId)
        SetState(src, 'characterId', charId)
        SetState(src, 'rpId', charId)
    end
    SetState(src, 'firstName', data.firstName or '')
    SetState(src, 'lastName', data.lastName or '')
    SetState(src, 'charName', BuildDisplayName(data.firstName, data.lastName))

    SetState(src, 'cash', data.cash)
    SetState(src, 'bank', data.bank)
    SetState(src, 'health', data.health)
    SetState(src, 'armor', data.armor)
    SetState(src, 'isDead', data.isDead)
    SetState(src, 'playerDataLoaded', true)
    SetState(src, 'identityReady', true)
end

local function NotifyLoaded(src)
    local data = PlayerData[src]
    if not data then return end

    ApplyState(src)
    TriggerEvent('cm-playerdata:server:loaded', src, data)
    TriggerClientEvent('cm-playerdata:client:loaded', src, data)
    TriggerEvent('cm-playerdata:server:readyForSpawn', src, data)
end

local function LoadPlayerData(src)
    local charId = GetCharId(src)
    if not charId then
        Debug('Load skipped, charId missing for src=' .. tostring(src))
        return false
    end

    local row = MySQL.single.await([[
        SELECT first_name, last_name, cash, bank, health, armor, is_dead, death_count, last_position, metadata
        FROM characters
        WHERE id = ?
        LIMIT 1
    ]], { charId })

    if not row then
        Log('error', 'Load failed: character row not found', { src = src, charId = charId })
        return false
    end

    local defaults = Config.Defaults

    PlayerData[src] = {
        src = src,
        charId = charId,
        firstName = row.first_name or '',
        lastName = row.last_name or '',

        cash = tonumber(row.cash) or defaults.cash,
        bank = tonumber(row.bank) or defaults.bank,

        health = Clamp(row.health or defaults.health, 0, Config.Vitals.MaxHealth),
        armor = Clamp(row.armor or defaults.armor, 0, Config.Vitals.MaxArmor),

        isDead = (tonumber(row.is_dead) or 0) == 1,
        deathCount = tonumber(row.death_count) or defaults.death_count,
        lastPosition = DecodeJson(row.last_position),
        metadata = DecodeJson(row.metadata) or {},

        loaded = true,
        dirty = false,
        lastVitalsSync = GetGameTimer()
    }

    Debug(('Loaded src=%s char=%s HP=%s dead=%s'):format(
        src, charId, PlayerData[src].health, tostring(PlayerData[src].isDead)
    ))

    NotifyLoaded(src)
    return true
end

local function SavePlayerData(src, reason)
    local data = PlayerData[src]
    if not data or not data.loaded then return false end

    local ok, err = pcall(function()
        MySQL.update.await([[
            UPDATE characters SET
                cash = ?,
                bank = ?,
                health = ?,
                armor = ?,
                is_dead = ?,
                death_count = ?,
                last_position = ?,
                metadata = ?
            WHERE id = ?
        ]], {
            data.cash,
            data.bank,
            data.health,
            data.armor,
            data.isDead and 1 or 0,
            data.deathCount,
            EncodeJson(data.lastPosition),
            EncodeJson(data.metadata or {}),
            data.charId
        })
    end)

    if not ok then
        Log('error', 'Save failed', { src = src, reason = reason, error = tostring(err) })
        return false
    end

    data.dirty = false
    Debug(('Saved src=%s reason=%s'):format(src, reason or 'manual'))
    return true
end

local function SavePositionOnly(src)
    local data = PlayerData[src]
    if not data or not data.loaded or not data.lastPosition then return false end

    local ok = pcall(function()
        MySQL.update.await(
            'UPDATE characters SET last_position = ? WHERE id = ?',
            { EncodeJson(data.lastPosition), data.charId }
        )
    end)

    return ok
end

local function ClearPlayerData(src)
    PlayerData[src] = nil
    pcall(function()
        local state = Player(src).state
        state:set('cash', nil, true)
        state:set('bank', nil, true)
        state:set('health', nil, true)
        state:set('armor', nil, true)
        state:set('isDead', nil, true)
        state:set('playerDataLoaded', nil, true)
        state:set('identityReady', nil, true)
        state:set('charId', nil, true)
        state:set('characterId', nil, true)
        state:set('rpId', nil, true)
        state:set('charName', nil, true)
        state:set('firstName', nil, true)
        state:set('lastName', nil, true)
    end)
    ClearRateLimits(src)
end

local function SetMoney(src, account, value, reason)
    local data = PlayerData[src]
    if not data or (account ~= 'cash' and account ~= 'bank') then return false end

    data[account] = math.max(0, math.floor(tonumber(value) or 0))
    data.dirty = true

    SetState(src, account, data[account])
    PushUpdate(src, account, data[account])
    Audit(src, 'set_' .. account, { amount = data[account], reason = reason })
    return true
end

local function AddMoney(src, account, amount, reason)
    local data = PlayerData[src]
    amount = math.floor(tonumber(amount) or 0)
    if not data or amount <= 0 then return false end
    if account ~= 'cash' and account ~= 'bank' then return false end
    return SetMoney(src, account, data[account] + amount, reason or 'add_money')
end

local function RemoveMoney(src, account, amount, reason)
    local data = PlayerData[src]
    amount = math.floor(tonumber(amount) or 0)
    if not data or amount <= 0 then return false end
    if account ~= 'cash' and account ~= 'bank' then return false end
    if data[account] < amount then return false end
    return SetMoney(src, account, data[account] - amount, reason or 'remove_money')
end

local function SetDead(src, isDead, reason)
    local data = PlayerData[src]
    if not data then return false end

    data.isDead = isDead == true
    if data.isDead then
        data.health = 0
        data.armor = 0
        data.deathCount = (data.deathCount or 0) + 1
    end
    data.dirty = true

    ApplyState(src)
    Audit(src, data.isDead and 'death' or 'revive', { reason = reason })
    SavePlayerData(src, reason or (data.isDead and 'death' or 'revive'))
    return true
end

-- ============================================================
-- Events
-- ============================================================

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(500)
    EnsureSchema()
    Log('info', 'CM PlayerData v1.6 started')

    -- Restart resilience: if this resource was live-restarted with players
    -- online, rebuild their state from the database instead of leaving them broken.
    for _, playerSrc in ipairs(GetPlayers()) do
        local src = tonumber(playerSrc)
        if src then
            SetTimeout(750, function()
                if GetPlayerName(src) then
                    LoadPlayerData(src)
                end
            end)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for src, data in pairs(PlayerData) do
        if data and data.loaded then
            SavePlayerData(src, 'resource_stop')
        end
    end
end)

AddEventHandler('cm-core:characterLoaded', function(src, charId)
    src = tonumber(src)
    if not src then return end

    charId = tonumber(charId) or GetCharId(src)
    if charId then
        local ok, state = pcall(function() return Player(src).state end)
        if ok and state then
            state:set('charId', charId, true)
            state:set('characterId', charId, true)
            state:set('rpId', charId, true)
        end
    end

    SetTimeout(500, function()
        LoadPlayerData(src)
    end)
end)

RegisterNetEvent('cm-playerdata:server:load', function()
    LoadPlayerData(source)
end)

AddEventHandler('playerDropped', function()
    local src = source
    SavePlayerData(src, 'drop')
    ClearPlayerData(src)
    PendingHandshakes[src] = nil
    PendingTreatments[src] = nil
    -- Server IDs are recycled: tell every client to forget this identity so a
    -- future player reusing the ID never inherits the old name/character ID.
    TriggerClientEvent('cm-playerdata:client:identityRemove', -1, src)
end)

RegisterNetEvent('cm-playerdata:server:updatePosition', function(coords)
    local src = source
    if not RateLimit(src, 'position', 1000) then return end
    local data = PlayerData[src]
    if not data or type(coords) ~= 'table' then return end

    local x, y, z, h = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z), tonumber(coords.h)
    if not x or not y or not z then return end
    if math.abs(x) > 10000 or math.abs(y) > 10000 or z < -500 or z > 2000 then return end

    -- Movement sanity logging (log only, never auto-punish: admin teleports,
    -- respawns and lag spikes are legitimate causes of big jumps).
    local logCfg = Config.Logging or {}
    if logCfg.LogMovementAnomalies ~= false and data.lastPosSample and not data.isDead then
        local now = os.clock()
        local dt = now - (data.lastPosSampleTime or now)
        if dt > 0.5 then
            local dx = x - data.lastPosSample.x
            local dy = y - data.lastPosSample.y
            local dz = z - data.lastPosSample.z
            local dist2d = math.sqrt(dx * dx + dy * dy)
            local speed = dist2d / dt

            local inVehicle = false
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local ok, veh = pcall(GetVehiclePedIsIn, ped, false)
                inVehicle = ok and veh ~= 0
            end

            local falling = dz <= (logCfg.FallZDelta or -9.0)

            if dist2d >= (logCfg.TeleportDistance or 300.0) then
                Audit(src, 'movement_teleport', {
                    from = data.lastPosSample, to = { x = x, y = y, z = z },
                    distance = math.floor(dist2d), seconds = math.floor(dt * 10) / 10
                })
            elseif not inVehicle and not falling and speed > (logCfg.MaxOnFootSpeed or 11.0) then
                Audit(src, 'movement_speed_anomaly', {
                    speed_ms = math.floor(speed * 10) / 10,
                    distance = math.floor(dist2d * 10) / 10,
                    seconds = math.floor(dt * 10) / 10,
                    at = { x = x, y = y, z = z }
                })
            end
        end
    end

    data.lastPosSample = { x = x, y = y, z = z }
    data.lastPosSampleTime = os.clock()

    data.lastPosition = {
        x = math.floor(x * 100) / 100,
        y = math.floor(y * 100) / 100,
        z = math.floor(z * 100) / 100,
        h = math.floor((h or 0.0) * 100) / 100
    }
end)

RegisterNetEvent('cm-playerdata:server:syncVitals', function(clientHealth, clientArmor)
    local src = source
    if not RateLimit(src, 'vitals', 1000) then return end
    local data = PlayerData[src]
    if not data or not data.loaded or data.isDead then return end

    local previousHealth = tonumber(data.health) or Config.Vitals.MaxHealth
    local serverHealth = GetServerPedHealth(src)
    local nextHealth = Clamp(clientHealth or previousHealth, 0, Config.Vitals.MaxHealth)
    local nextArmor = Clamp(clientArmor or 0, 0, Config.Vitals.MaxArmor)

    -- The client may report damage quickly, but never trust a huge healing jump from the client.
    -- Healing/revive should come from server exports so jobs/admin/hospital scripts stay authoritative.
    local maxPassiveHeal = Config.Vitals.MaxPassiveHealDelta or 5
    if nextHealth > previousHealth + maxPassiveHeal then
        nextHealth = previousHealth
    end

    -- Prefer server-observed ped health when available and lower than the client value.
    if serverHealth and serverHealth < nextHealth then
        nextHealth = Clamp(serverHealth, 0, Config.Vitals.MaxHealth)
    end

    if nextHealth ~= data.health or nextArmor ~= data.armor then
        data.health = nextHealth
        data.armor = nextArmor
        data.dirty = true
        data.lastVitalsSync = GetGameTimer()

        SetState(src, 'health', data.health)
        SetState(src, 'armor', data.armor)
    end
end)

-- Weapon hash -> readable name for death logs. Built once at startup.
local WeaponNames = {}
do
    local names = {
        'WEAPON_UNARMED','WEAPON_KNIFE','WEAPON_NIGHTSTICK','WEAPON_HAMMER','WEAPON_BAT','WEAPON_CROWBAR',
        'WEAPON_GOLFCLUB','WEAPON_BOTTLE','WEAPON_DAGGER','WEAPON_HATCHET','WEAPON_MACHETE','WEAPON_SWITCHBLADE',
        'WEAPON_PISTOL','WEAPON_PISTOL_MK2','WEAPON_COMBATPISTOL','WEAPON_APPISTOL','WEAPON_PISTOL50',
        'WEAPON_SNSPISTOL','WEAPON_HEAVYPISTOL','WEAPON_VINTAGEPISTOL','WEAPON_REVOLVER','WEAPON_CERAMICPISTOL',
        'WEAPON_MICROSMG','WEAPON_SMG','WEAPON_SMG_MK2','WEAPON_ASSAULTSMG','WEAPON_MINISMG','WEAPON_MACHINEPISTOL',
        'WEAPON_PUMPSHOTGUN','WEAPON_SAWNOFFSHOTGUN','WEAPON_ASSAULTSHOTGUN','WEAPON_BULLPUPSHOTGUN',
        'WEAPON_HEAVYSHOTGUN','WEAPON_DBSHOTGUN','WEAPON_AUTOSHOTGUN','WEAPON_COMBATSHOTGUN',
        'WEAPON_ASSAULTRIFLE','WEAPON_ASSAULTRIFLE_MK2','WEAPON_CARBINERIFLE','WEAPON_CARBINERIFLE_MK2',
        'WEAPON_ADVANCEDRIFLE','WEAPON_SPECIALCARBINE','WEAPON_BULLPUPRIFLE','WEAPON_COMPACTRIFLE','WEAPON_MILITARYRIFLE',
        'WEAPON_MG','WEAPON_COMBATMG','WEAPON_GUSENBERG',
        'WEAPON_SNIPERRIFLE','WEAPON_HEAVYSNIPER','WEAPON_HEAVYSNIPER_MK2','WEAPON_MARKSMANRIFLE',
        'WEAPON_RPG','WEAPON_GRENADELAUNCHER','WEAPON_MINIGUN','WEAPON_GRENADE','WEAPON_STICKYBOMB','WEAPON_MOLOTOV',
        'WEAPON_STUNGUN','WEAPON_FLARE','WEAPON_PETROLCAN','WEAPON_FIREEXTINGUISHER',
        'WEAPON_FALL','WEAPON_DROWNING','WEAPON_DROWNING_IN_VEHICLE','WEAPON_EXPLOSION','WEAPON_FIRE',
        'WEAPON_BLEEDING','WEAPON_ELECTRIC_FENCE','WEAPON_EXHAUSTION','WEAPON_HIT_BY_WATER_CANNON',
        'WEAPON_RAMMED_BY_CAR','WEAPON_RUN_OVER_BY_CAR','WEAPON_HELI_CRASH','WEAPON_ANIMAL','WEAPON_COUGAR'
    }
    for _, name in ipairs(names) do
        WeaponNames[GetHashKey(name)] = name
    end
end

local function ResolveWeaponName(hash)
    hash = tonumber(hash)
    if not hash then return 'unknown' end
    return WeaponNames[hash] or ('hash_%s'):format(hash)
end

-- Who killed you, from the victim's point of view: real name only if the victim
-- already knows the killer (handshake/org/family/ID). Otherwise Stranger + char ID.
local function GetKilledByInfo(victimSrc, killerSrc)
    killerSrc = tonumber(killerSrc)
    if not killerSrc then return nil end

    local victimData = PlayerData[victimSrc]
    local killerData = PlayerData[killerSrc]
    if not victimData or not killerData or not killerData.charId then return nil end

    local stranger = (Config.Interactions and Config.Interactions.StrangerName) or 'Stranger'
    local label = stranger

    local privacyMode = not (Config.Interactions and Config.Interactions.PrivacyMode == false)
    if not privacyMode then
        label = ('%s %s'):format(killerData.firstName or '', killerData.lastName or '')
    else
        victimData.metadata = victimData.metadata or {}
        local known = victimData.metadata.knownIdentities or {}
        local entry = known[tostring(killerData.charId)]
        if entry and entry.name then
            label = entry.name
        end
    end

    return { label = label, charId = tonumber(killerData.charId) }
end

-- Bleed-out: when the deadline passes and the player is still dead, they respawn
-- at the hospital automatically. Calling an ambulance pushes the deadline back.
local function ScheduleBleedOut(src)
    local data = PlayerData[src]
    if not data or not data.deathDeadline then return end

    local remaining = data.deathDeadline - GetGameTimer()
    if remaining < 0 then remaining = 0 end

    SetTimeout(remaining + 100, function()
        local current = PlayerData[src]
        if not current or not current.isDead then return end
        if not current.deathDeadline then return end
        -- An ambulance call may have moved the deadline; only respawn if passed.
        if GetGameTimer() >= current.deathDeadline then
            current.deathDeadline = nil
            exports['cm-playerdata']:Respawn(src)
        end
    end)
end

RegisterNetEvent('cm-playerdata:server:playerDied', function(killerSrc, weaponHash, killerType)
    local src = source
    if not RateLimit(src, 'death', 1000) then return end

    local data = PlayerData[src]
    if not data or not data.loaded or data.isDead then return end

    local serverHealth = GetServerPedHealth(src)
    local reportedHealth = tonumber(data.health) or Config.Vitals.MaxHealth

    -- Server-side sanity check. This is not a full anticheat, but blocks easy fake death events.
    if serverHealth and serverHealth > Config.Vitals.DamageThreshold and reportedHealth > Config.Vitals.DamageThreshold then
        Log('warn', 'Rejected suspicious death event', { src = src, serverHealth = serverHealth, storedHealth = reportedHealth })
        return
    end

    -- Validate the client-reported killer against server state; never trust it blindly.
    local killerRecord = nil
    killerSrc = tonumber(killerSrc)
    if killerSrc and killerSrc > 0 and killerSrc ~= src and GetPlayerName(killerSrc) then
        local dist = nil
        local myPed = GetPlayerPed(src)
        local killerPed = GetPlayerPed(killerSrc)
        if myPed ~= 0 and killerPed ~= 0 then
            local ok, d = pcall(function()
                return #(GetEntityCoords(myPed) - GetEntityCoords(killerPed))
            end)
            if ok then dist = d end
        end
        killerRecord = {
            character_id = GetCharId(killerSrc),
            distance = dist and math.floor(dist * 10) / 10 or nil,
            plausible = dist ~= nil and dist <= 400.0 -- beyond sniper range = flagged, still logged
        }
    end

    SetDead(src, true, 'death')

    -- Bleed-out clock: base window, extendable once by calling an ambulance.
    local bleedMs = (Config.Respawn and Config.Respawn.BleedOutTime) or 120000
    data.deathDeadline = GetGameTimer() + bleedMs
    data.ambulanceCalled = false
    ScheduleBleedOut(src)

    local killedBy = GetKilledByInfo(src, killerSrc)

    if (Config.Logging and Config.Logging.LogDeaths) ~= false then
        local pos = data.lastPosition or {}
        Audit(src, 'death_detail', {
            killer = killerRecord,
            killer_type = tostring(killerType or 'unknown'),
            weapon = ResolveWeaponName(weaponHash),
            coords = { x = pos.x, y = pos.y, z = pos.z },
            death_count = data.deathCount
        })
        if killerRecord and killerRecord.character_id then
            Audit(killerSrc, 'kill_detail', {
                victim_character_id = GetCharId(src),
                weapon = ResolveWeaponName(weaponHash),
                distance = killerRecord.distance
            })
        end
    end

    TriggerClientEvent('cm-playerdata:client:playerDied', src, killerSrc, weaponHash, killedBy, bleedMs)
end)

RegisterNetEvent('cm-playerdata:server:callAmbulance', function()
    local src = source
    if not RateLimit(src, 'ambulance', 2000) then return end

    local data = PlayerData[src]
    if not data or not data.isDead or not data.deathDeadline then return end
    if data.ambulanceCalled then return end

    data.ambulanceCalled = true
    local extra = (Config.Respawn and Config.Respawn.AmbulanceExtraTime) or 120000
    data.deathDeadline = data.deathDeadline + extra
    ScheduleBleedOut(src)

    Audit(src, 'ambulance_called', { extra_ms = extra })
    -- Bridge for the future EMS resource: dispatch, blips, job notifications.
    TriggerEvent('cm-playerdata:server:ambulanceCalled', src, data.lastPosition)

    local remaining = data.deathDeadline - GetGameTimer()
    TriggerClientEvent('cm-playerdata:client:ambulanceConfirmed', src, remaining)
end)

RegisterNetEvent('cm-playerdata:server:chooseDie', function()
    local src = source
    if not RateLimit(src, 'choose_die', 2000) then return end

    local data = PlayerData[src]
    if not data or not data.isDead then return end

    -- Per design: no time change, the death screen stays until bleed-out ends.
    data.dieChosen = true
    Audit(src, 'death_give_up', {})
end)

RegisterNetEvent('cm-playerdata:server:requestRespawn', function()
    local src = source
    if not RateLimit(src, 'respawn', 2000) then return end
    local data = PlayerData[src]
    if not data or not data.isDead then return end
    exports['cm-playerdata']:Respawn(src)
end)



-- ============================================================
-- Player Identity + Interaction Events
-- ============================================================

local function GetPlayerDistance(src, targetSrc)
    src = tonumber(src)
    targetSrc = tonumber(targetSrc)
    if not src or not targetSrc then return nil end

    local ped = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    if not ped or ped == 0 or not targetPed or targetPed == 0 then return nil end

    local coords = GetEntityCoords(ped)
    local targetCoords = GetEntityCoords(targetPed)
    if not coords or not targetCoords then return nil end

    return #(coords - targetCoords)
end

local function NotifyPlayer(src, message, msgType)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', src, message, msgType or 'inform')
end

local function GetFullName(data)
    if not data then return 'Unknown' end
    return BuildDisplayName(data.firstName or data.first_name, data.lastName or data.last_name)
end

local function CleanTag(value)
    if value == nil then return nil end
    value = tostring(value)
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    local lower = value:lower()
    if lower == 'none' or lower == 'nil' or lower == 'false' or lower == '0' or lower == 'unemployed' then
        return nil
    end
    return lower
end

local function GetNestedValue(root, path)
    if type(root) ~= 'table' then return nil end
    local current = root
    for part in tostring(path):gmatch('[^%.]+') do
        if type(current) ~= 'table' then return nil end
        current = current[part]
        if current == nil then return nil end
    end
    return current
end

local function GetStateValue(src, keys)
    local ok, state = pcall(function() return Player(src).state end)
    if not ok or not state then return nil end

    for _, key in ipairs(keys) do
        local value = state[key]
        local tag = CleanTag(value)
        if tag then return tag end
    end

    return nil
end

local function GetMetadataValue(data, keys)
    local metadata = data and data.metadata or {}
    for _, key in ipairs(keys) do
        local value = GetNestedValue(metadata, key)
        if type(value) == 'table' then
            value = value.id or value.name or value.label
        end
        local tag = CleanTag(value)
        if tag then return tag end
    end
    return nil
end

local OrgKeys = {
    'organization_id', 'organizationId', 'organization', 'org_id', 'orgId', 'org',
    'faction_id', 'factionId', 'faction', 'business_id', 'businessId', 'business'
}

local FamilyKeys = {
    'family_id', 'familyId', 'family', 'family.name', 'family.id'
}

local function GetOrgTag(src, data)
    return GetMetadataValue(data, OrgKeys) or GetStateValue(src, OrgKeys)
end

local function GetFamilyTag(src, data)
    return GetMetadataValue(data, FamilyKeys) or GetStateValue(src, FamilyKeys)
end

local function IsKnownByMemory(viewerData, targetData)
    if not viewerData or not targetData then return false end
    local metadata = viewerData.metadata or {}
    local known = metadata.knownIdentities or metadata.knownPlayers or {}
    local targetCharId = tostring(targetData.charId or '')
    if targetCharId == '' then return false end
    return known[targetCharId] ~= nil or known[tonumber(targetCharId)] ~= nil
end

local function EnsureKnownTable(data)
    data.metadata = data.metadata or {}
    data.metadata.knownIdentities = data.metadata.knownIdentities or {}
    return data.metadata.knownIdentities
end

local function MarkIdentityKnown(viewerSrc, targetSrc, reason)
    viewerSrc = tonumber(viewerSrc)
    targetSrc = tonumber(targetSrc)
    if not viewerSrc or not targetSrc then return false end

    local viewerData = PlayerData[viewerSrc]
    local targetData = PlayerData[targetSrc]
    if not viewerData or not targetData then return false end

    local known = EnsureKnownTable(viewerData)
    known[tostring(targetData.charId)] = {
        characterId = tonumber(targetData.charId),
        name = GetFullName(targetData),
        reason = reason or 'known',
        time = os.time()
    }

    viewerData.dirty = true
    return true
end

local function BuildIdentityForViewer(viewerSrc, targetSrc)
    viewerSrc = tonumber(viewerSrc)
    targetSrc = tonumber(targetSrc)

    local targetData = PlayerData[targetSrc]
    local viewerData = PlayerData[viewerSrc]
    local stranger = (Config.Interactions and Config.Interactions.StrangerName) or 'Stranger'

    if not targetData then
        return {
            id = targetSrc or 0,       -- internal cache key only
            serverId = targetSrc or 0, -- internal event target only, never shown in UI
            displayName = stranger,
            known = false,
            reason = 'not_loaded',
            identityId = nil,
            characterId = nil
        }
    end

    local privacyMode = not (Config.Interactions and Config.Interactions.PrivacyMode == false)
    local known = false
    local reason = 'stranger'

    if not privacyMode then
        known = true
        reason = 'privacy_disabled'
    elseif viewerSrc == targetSrc and (Config.Interactions and Config.Interactions.ShowRealNameToSelf ~= false) then
        known = true
        reason = 'self'
    elseif viewerData and targetData then
        local viewerOrg = GetOrgTag(viewerSrc, viewerData)
        local targetOrg = GetOrgTag(targetSrc, targetData)
        if viewerOrg and targetOrg and viewerOrg == targetOrg then
            known = true
            reason = 'same_org'
        end

        local viewerFamily = GetFamilyTag(viewerSrc, viewerData)
        local targetFamily = GetFamilyTag(targetSrc, targetData)
        if not known and viewerFamily and targetFamily and viewerFamily == targetFamily then
            known = true
            reason = 'same_family'
        end

        if not known and IsKnownByMemory(viewerData, targetData) then
            known = true
            reason = 'known_identity'
        end
    end

    return {
        id = targetSrc,       -- internal cache key only
        serverId = targetSrc, -- internal event target only, never shown in UI
        displayName = known and GetFullName(targetData) or stranger,
        known = known,
        reason = reason,
        identityId = tonumber(targetData.charId),
        characterId = tonumber(targetData.charId)
    }
end

local function PushIdentityUpdate(viewerSrc, targetSrc)
    TriggerClientEvent('cm-playerdata:client:identityUpdate', viewerSrc, BuildIdentityForViewer(viewerSrc, targetSrc))
end

local function ValidatePlayerInteraction(src, targetSrc, rateKey)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc <= 0 or src == targetSrc then
        return false, nil, 'Invalid target.'
    end

    if not RateLimit(src, rateKey or 'player_interaction', 750) then
        return false, targetSrc, 'Please slow down.'
    end

    if not PlayerData[src] or not PlayerData[src].loaded then
        return false, targetSrc, 'Your player data is not loaded yet.'
    end

    if PlayerData[src].isDead then
        return false, targetSrc, 'You cannot do this while unconscious.'
    end

    if not GetPlayerName(targetSrc) then
        return false, targetSrc, 'Target player is no longer online.'
    end

    if not PlayerData[targetSrc] or not PlayerData[targetSrc].loaded then
        return false, targetSrc, 'Target player data is not loaded yet.'
    end

    local dist = GetPlayerDistance(src, targetSrc)
    local maxDistance = (Config.Interactions and Config.Interactions.ServerMaxDistance) or 5.0
    if not dist or dist > maxDistance then
        return false, targetSrc, 'Target player is too far away.'
    end

    return true, targetSrc, nil
end

local function GetPublicCharacterId(src)
    local data = PlayerData[tonumber(src)]
    return data and tonumber(data.charId) or nil
end

local function GetPublicPlayerLabel(src)
    local charId = GetPublicCharacterId(src)
    if charId then
        return ('Character ID %s'):format(charId)
    end
    return 'Character ID Loading'
end


RegisterNetEvent('cm-playerdata:server:requestIdentityBatch', function(ids)
    local src = source
    if not RateLimit(src, 'identity_batch', 900) then return end
    if type(ids) ~= 'table' then return end

    local items = {}
    local used = {}

    for _, rawId in ipairs(ids) do
        local target = tonumber(rawId)
        if target and target > 0 and target ~= src and GetPlayerName(target) and not used[target] then
            used[target] = true
            items[#items + 1] = BuildIdentityForViewer(src, target)
            if #items >= 32 then break end
        end
    end

    if #items > 0 then
        TriggerClientEvent('cm-playerdata:client:identityBatch', src, items)
    end
end)

RegisterNetEvent('cm-playerdata:server:giveCashToPlayer', function(targetSrc, amount)
    local src = source
    local ok, target, errorMessage = ValidatePlayerInteraction(src, targetSrc, 'give_cash')
    if not ok then
        NotifyPlayer(src, errorMessage or 'Cash transfer failed.', 'error')
        return
    end

    amount = math.floor(tonumber(amount) or 0)
    local maxGift = (Config.Interactions and Config.Interactions.MaxCashGift) or 1000
    if amount <= 0 or amount > maxGift then
        NotifyPlayer(src, ('Cash gift must be between $1 and $%s.'):format(maxGift), 'error')
        return
    end

    if not RemoveMoney(src, 'cash', amount, 'player_give_cash') then
        NotifyPlayer(src, 'You do not have enough cash.', 'error')
        return
    end

    AddMoney(target, 'cash', amount, 'player_receive_cash')
    Audit(src, 'give_cash_to_player', { target_character_id = GetPublicCharacterId(target), amount = amount })
    Audit(target, 'receive_cash_from_player', { from_character_id = GetPublicCharacterId(src), amount = amount })

    NotifyPlayer(src, ('You gave $%s cash to %s.'):format(amount, GetPublicPlayerLabel(target)), 'success')
    NotifyPlayer(target, ('%s gave you $%s cash.'):format(GetPublicPlayerLabel(src), amount), 'success')
end)

RegisterNetEvent('cm-playerdata:server:playerInteraction', function(targetSrc, action)
    local src = source
    action = tostring(action or 'unknown')

    local ok, target, errorMessage = ValidatePlayerInteraction(src, targetSrc, 'interaction_' .. action)
    if not ok then
        NotifyPlayer(src, errorMessage or 'Interaction failed.', 'error')
        return
    end

    -- Dead targets: only treatment-type actions are allowed on a body.
    local DeadAllowedActions = { treat_player = true }
    if PlayerData[target].isDead and not DeadAllowedActions[action] then
        NotifyPlayer(src, 'That player is unconscious. You can only treat them.', 'error')
        return
    end

    if action == 'treat_player' then
        local medCfg = Config.Medical or {}

        -- One treatment at a time per treater.
        if PendingTreatments[src] then
            NotifyPlayer(src, 'You are already treating someone.', 'error')
            return
        end

        -- Bandage requirement via cm-inventory (graceful: skipped if the
        -- inventory resource or export is unavailable).
        if medCfg.RequireBandage ~= false then
            local hasItem = nil
            local ok = pcall(function()
                hasItem = exports['cm-inventory']:HasItem(src, medCfg.BandageItem or 'bandage', 1)
            end)
            if ok and hasItem == false then
                NotifyPlayer(src, ('You need a %s to patch someone up.'):format(medCfg.BandageItem or 'bandage'), 'error')
                return
            end
        end

        local duration = medCfg.TreatDuration or 8000
        PendingTreatments[src] = {
            target = target,
            startedAt = GetGameTimer(),
            duration = duration
        }

        NotifyPlayer(src, ('You are patching up %s.'):format(GetPublicPlayerLabel(target)), 'inform')
        NotifyPlayer(target, ('%s is patching you up.'):format(GetPublicPlayerLabel(src)), 'inform')
        TriggerClientEvent('cm-playerdata:client:startTreatment', src, duration)
        -- Bridge for the future EMS/medic resource (full revive, items, payouts).
        TriggerEvent('cm-playerdata:server:treatRequested', src, target)
    elseif action == 'handshake' then
        -- Consent flow: the target must accept before names are exchanged.
        PendingHandshakes[target] = {
            from = src,
            expires = GetGameTimer() + ((Config.Interactions and Config.Interactions.HandshakeTimeout) or 15000)
        }
        NotifyPlayer(src, ('You offered a handshake to %s.'):format(GetPublicPlayerLabel(target)), 'inform')
        TriggerClientEvent('cm-playerdata:client:handshakeRequest', target,
            GetPublicPlayerLabel(src),
            (Config.Interactions and Config.Interactions.HandshakeTimeout) or 15000)
    elseif action == 'share_id' then
        MarkIdentityKnown(target, src, 'shared_id')
        SavePlayerData(target, 'identity_shared_id')
        PushIdentityUpdate(target, src)
        NotifyPlayer(src, ('You showed your ID to %s.'):format(GetPublicPlayerLabel(target)), 'success')

        -- Passport-style ID card on the target's screen. DOB/licenses read from
        -- metadata when present (cm-characters can set these later).
        local srcData = PlayerData[src]
        local meta = srcData.metadata or {}
        TriggerClientEvent('cm-playerdata:client:showIdCard', target, {
            name = GetFullName(srcData),
            charId = tonumber(srcData.charId),
            dob = meta.dob or srcData.dob or nil,
            licenses = meta.licenses or nil
        })
    elseif action == 'greet' then
        NotifyPlayer(src, ('You greeted %s.'):format(GetPublicPlayerLabel(target)), 'success')
        NotifyPlayer(target, ('%s greeted you.'):format(GetPublicPlayerLabel(src)), 'inform')
        TriggerClientEvent('cm-playerdata:client:interactionAnim', src, 'greet', target)
    elseif action == 'show_license' then
        NotifyPlayer(src, 'License sharing selected. Connect this to your license/document system when ready.', 'inform')
        NotifyPlayer(target, ('%s wants to show a license.'):format(GetPublicPlayerLabel(src)), 'inform')
    elseif action == 'show_documents' then
        NotifyPlayer(src, 'Document sharing selected. Connect this to your document system when ready.', 'inform')
        NotifyPlayer(target, ('%s wants to show documents.'):format(GetPublicPlayerLabel(src)), 'inform')
    elseif action == 'search_player' then
        NotifyPlayer(src, 'Search action selected. Connect this event to your inventory/police script when ready.', 'inform')
        NotifyPlayer(target, ('%s is trying to search/interact with you.'):format(GetPublicPlayerLabel(src)), 'inform')
        TriggerClientEvent('cm-playerdata:client:interactionAnim', src, 'frisk', target)
    elseif action == 'escort_player' then
        NotifyPlayer(src, 'Escort/carry action selected. Connect this event to your carry/escort script when ready.', 'inform')
        NotifyPlayer(target, ('%s selected escort/carry interaction.'):format(GetPublicPlayerLabel(src)), 'inform')
    elseif action == 'org_invite' or action == 'org_rank' then
        NotifyPlayer(src, 'Organization action selected. Connect this to your organization resource when ready.', 'inform')
    elseif action == 'family_invite' or action == 'family_info' then
        NotifyPlayer(src, 'Family action selected. Connect this to your family resource when ready.', 'inform')
    else
        NotifyPlayer(src, ('Selected %s on %s.'):format(action, GetPublicPlayerLabel(target)), 'inform')
    end

    -- Bridge event for future resources: inventory, police, carry, animations, org/family, documents, etc.
    TriggerEvent('cm-playerdata:server:interactionSelected', src, target, action)
end)

RegisterNetEvent('cm-playerdata:server:treatComplete', function(finished)
    local src = source
    local pending = PendingTreatments[src]
    PendingTreatments[src] = nil
    if not pending then return end

    if finished ~= true then
        NotifyPlayer(src, 'Treatment cancelled.', 'error')
        return
    end

    -- The progress bar cannot legitimately finish early.
    local elapsed = GetGameTimer() - pending.startedAt
    if elapsed < math.floor(pending.duration * 0.85) then
        Log('warn', 'Rejected suspicious treatComplete (too fast)', { src = src, elapsed = elapsed })
        return
    end

    local target = pending.target
    local targetData = PlayerData[target]
    if not targetData or not targetData.loaded or not targetData.isDead then
        NotifyPlayer(src, 'They no longer need treatment.', 'error')
        return
    end

    -- Both must still be next to each other.
    local dist = GetPlayerDistance(src, target)
    local maxDistance = ((Config.Interactions and Config.Interactions.ServerMaxDistance) or 5.0) + 2.0
    if not dist or dist > maxDistance then
        NotifyPlayer(src, 'You moved too far away from them.', 'error')
        return
    end

    local medCfg = Config.Medical or {}

    -- Consume the bandage now, at success time (never on a cancelled attempt).
    if medCfg.RequireBandage ~= false then
        pcall(function()
            exports['cm-inventory']:RemoveItem(src, medCfg.BandageItem or 'bandage', 1)
        end)
    end

    -- Street patch: back up at partial health. Full revive stays EMS/admin only.
    local percent = medCfg.StreetPatchHealthPercent or 30
    local health = math.floor(Config.Vitals.MaxHealth * (percent / 100))

    targetData.isDead = false
    targetData.health = health
    targetData.armor = 0
    targetData.deathDeadline = nil
    targetData.ambulanceCalled = false
    targetData.dirty = true

    ApplyState(target)
    SavePlayerData(target, 'street_patch')
    TriggerClientEvent('cm-playerdata:client:revivePartial', target, health)

    NotifyPlayer(src, ('You patched up %s.'):format(GetPublicPlayerLabel(target)), 'success')
    NotifyPlayer(target, ('%s patched you up. You are weak: find proper medical care.'):format(GetPublicPlayerLabel(src)), 'success')
    Audit(src, 'treat_success', { target_character_id = GetPublicCharacterId(target), health = health })
end)

RegisterNetEvent('cm-playerdata:server:handshakeResponse', function(accepted)
    local src = source -- src is the player who RECEIVED the handshake offer
    if not RateLimit(src, 'handshake_response', 1000) then return end

    local pending = PendingHandshakes[src]
    PendingHandshakes[src] = nil
    if not pending then return end

    if GetGameTimer() > pending.expires then
        NotifyPlayer(src, 'That handshake offer has expired.', 'error')
        return
    end

    local from = pending.from
    if not GetPlayerName(from) or not PlayerData[from] or not PlayerData[from].loaded then
        NotifyPlayer(src, 'That player is no longer online.', 'error')
        return
    end

    if accepted ~= true then
        NotifyPlayer(from, ('%s declined your handshake.'):format(GetPublicPlayerLabel(src)), 'error')
        return
    end

    -- Re-check distance at accept time: they must still be next to each other.
    local dist = GetPlayerDistance(src, from)
    local maxDistance = ((Config.Interactions and Config.Interactions.ServerMaxDistance) or 5.0) + 2.0
    if not dist or dist > maxDistance then
        NotifyPlayer(src, 'You are too far away to shake hands now.', 'error')
        NotifyPlayer(from, 'Handshake failed: target moved away.', 'error')
        return
    end

    MarkIdentityKnown(src, from, 'handshake')
    MarkIdentityKnown(from, src, 'handshake')
    SavePlayerData(src, 'identity_handshake')
    SavePlayerData(from, 'identity_handshake')
    PushIdentityUpdate(src, from)
    PushIdentityUpdate(from, src)
    NotifyPlayer(src, ('You shook hands with %s. Their name is now visible to you.'):format(GetFullName(PlayerData[from])), 'success')
    NotifyPlayer(from, ('You shook hands with %s. Their name is now visible to you.'):format(GetFullName(PlayerData[src])), 'success')
    -- Paired handshake emote, each facing the other.
    TriggerClientEvent('cm-playerdata:client:interactionAnim', from, 'handshake', src)
    TriggerClientEvent('cm-playerdata:client:interactionAnim', src, 'handshake_b', from)
    Audit(src, 'handshake_accept', { with_character_id = GetPublicCharacterId(from) })
end)

exports('KnowPlayerIdentity', function(viewerSrc, targetSrc, reason)
    local ok = MarkIdentityKnown(viewerSrc, targetSrc, reason or 'export')
    if ok then
        SavePlayerData(viewerSrc, 'identity_export')
        PushIdentityUpdate(viewerSrc, targetSrc)
    end
    return ok
end)

exports('SetOrganization', function(src, orgId, orgName)
    local data = PlayerData[src]
    if not data then return false end
    data.metadata = data.metadata or {}
    data.metadata.organization_id = orgId
    data.metadata.organization = orgName or orgId
    data.dirty = true
    return true
end)

exports('SetFamily', function(src, familyId, familyName)
    local data = PlayerData[src]
    if not data then return false end
    data.metadata = data.metadata or {}
    data.metadata.family_id = familyId
    data.metadata.family = familyName or familyId
    data.dirty = true
    return true
end)

-- ============================================================
-- Exports
-- ============================================================

exports('Load', LoadPlayerData)
exports('Save', SavePlayerData)

exports('GetPlayerData', function(src)
    return PlayerData[src]
end)

exports('GetCharId', function(src)
    return GetCharId(src)
end)

exports('GetSourceByCharId', function(charId)
    charId = tonumber(charId)
    if not charId then return nil end
    for src, data in pairs(PlayerData) do
        if data and tonumber(data.charId) == charId then
            return src
        end
    end
    return nil
end)

exports('IsLoaded', function(src)
    return PlayerData[src] and PlayerData[src].loaded == true or false
end)

exports('GetCash', function(src)
    return PlayerData[src] and PlayerData[src].cash or 0
end)

exports('GetBank', function(src)
    return PlayerData[src] and PlayerData[src].bank or 0
end)

exports('GetMoney', function(src, account)
    if not PlayerData[src] then return 0 end
    return PlayerData[src][account] or 0
end)

exports('SetMoney', SetMoney)
exports('AddMoney', AddMoney)
exports('RemoveMoney', RemoveMoney)

exports('AddCash', function(src, amount, reason)
    return AddMoney(src, 'cash', amount, reason or 'add_cash')
end)

exports('RemoveCash', function(src, amount, reason)
    return RemoveMoney(src, 'cash', amount, reason or 'remove_cash')
end)

exports('AddBank', function(src, amount, reason)
    return AddMoney(src, 'bank', amount, reason or 'add_bank')
end)

exports('RemoveBank', function(src, amount, reason)
    return RemoveMoney(src, 'bank', amount, reason or 'remove_bank')
end)

exports('SetMetadata', function(src, key, value)
    local data = PlayerData[src]
    if not data then return false end
    data.metadata = data.metadata or {}
    data.metadata[key] = value
    data.dirty = true
    return true
end)

exports('GetMetadata', function(src, key)
    local data = PlayerData[src]
    if not data or not data.metadata then return nil end
    if key == nil then return data.metadata end
    return data.metadata[key]
end)

exports('IsDead', function(src)
    return PlayerData[src] and PlayerData[src].isDead or false
end)

exports('GetDeathCount', function(src)
    return PlayerData[src] and PlayerData[src].deathCount or 0
end)

exports('SetDead', SetDead)

exports('Revive', function(src)
    local data = PlayerData[src]
    if not data then return false end

    data.isDead = false
    data.health = Config.Vitals.MaxHealth
    data.armor = 0
    data.dirty = true

    ApplyState(src)
    SavePlayerData(src, 'revive')
    TriggerClientEvent('cm-playerdata:client:revive', src)
    return true
end)

exports('Respawn', function(src, spawnCoords, cost)
    local data = PlayerData[src]
    if not data then return false end

    spawnCoords = spawnCoords or Config.Respawn.HospitalSpawn
    cost = tonumber(cost or Config.Respawn.Cost) or 0

    if cost > 0 then
        if data.bank >= cost then
            RemoveMoney(src, 'bank', cost, 'hospital_respawn')
        else
            local remaining = cost - data.bank
            if data.bank > 0 then RemoveMoney(src, 'bank', data.bank, 'hospital_respawn') end
            if remaining > 0 then
                data.cash = math.max(0, data.cash - remaining)
                data.dirty = true
                SetState(src, 'cash', data.cash)
                PushUpdate(src, 'cash', data.cash)
                Audit(src, 'remove_cash', { amount = remaining, reason = 'hospital_respawn' })
            end
        end
    end

    data.isDead = false
    data.health = Config.Vitals.MaxHealth
    data.armor = 0
    data.dirty = true

    ApplyState(src)
    SavePlayerData(src, 'respawn')
    TriggerClientEvent('cm-playerdata:client:respawn', src, spawnCoords)
    return true
end)

-- ============================================================
-- Loops
-- ============================================================

CreateThread(function()
    while true do
        Wait(Config.Save.FullSaveInterval)
        for src, data in pairs(PlayerData) do
            if data.loaded and data.dirty then
                SavePlayerData(src, 'auto')
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(Config.Save.PositionSaveInterval)
        for src, data in pairs(PlayerData) do
            if data.loaded and data.lastPosition then
                SavePositionOnly(src)
            end
        end
    end
end)

RegisterCommand('cash', function(src, args)
    if src <= 0 then
        print('[CM-PLAYERDATA] Use in F8: cash 5000')
        return
    end

    if not HasAce(src, 'cm-playerdata.cash') then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            description = 'You do not have permission to use this command.'
        })
        return
    end

    local amount = tonumber(args[1]) or 5000
    local ok = exports['cm-playerdata']:AddCash(src, amount, 'dev_cash_command')

    if ok then
        print(('[CM-PLAYERDATA] Added $%s cash to player %s'):format(amount, src))
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'success',
            description = ('Added $%s cash'):format(amount)
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            description = 'Cash add failed. PlayerData not loaded.'
        })
    end
end, false)
