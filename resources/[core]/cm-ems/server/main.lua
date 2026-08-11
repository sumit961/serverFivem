local RESOURCE = GetCurrentResourceName()
local ready = false
local useLocks = {}
local leaderAssignmentBusy = false
local rankMutationBusy = false
local meetingCooldowns = {}
local MAX_OUTFIT_PRESETS_PER_SEX = 12
local MAX_FAVORITE_OUTFIT_SLOTS = 5
local EMSSettingsCache = {}

-- Not `local`: shared with server/vehicles.lua (both files share this
-- resource's server Lua state; see cm-house's sv_compat.lua GetCid for the
-- same cross-file-helper convention).
function cid(src)
    local ok, value = pcall(function()
        return exports[Config.PlayerDataResource]:GetCharacterId(tonumber(src))
    end)
    return ok and value and tostring(value) or nil
end

local function sourceFor(characterId)
    local ok, value = pcall(function()
        return exports[Config.PlayerDataResource]:GetSourceByCharId(characterId)
    end)
    return ok and tonumber(value) or nil
end

function nameFor(characterId)
    local src = sourceFor(characterId)
    if src then
        local ok, value = pcall(function()
            return exports[Config.PlayerDataResource]:GetCharacterFullName(src)
        end)
        if ok and value and value ~= '' then return value end
    end
    local row = MySQL.single.await('SELECT first_name, last_name FROM characters WHERE id = ? LIMIT 1', { characterId })
    if not row then return ('Character #%s'):format(tostring(characterId)) end
    return (('%s %s'):format(row.first_name or '', row.last_name or '')):gsub('^%s+', ''):gsub('%s+$', '')
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

function decode(value)
    if type(value) == 'table' then return value end
    local ok, result = pcall(json.decode, value or '{}')
    return ok and type(result) == 'table' and result or {}
end

-- Asks cm-admin's centralized Organizations registry whether this character
-- already belongs to a DIFFERENT registered organization. cm-admin owns the
-- cross-org policy (allowMultiOrgMembership) and honors it internally, so
-- this always returns nil once an admin has turned that setting on.
-- pcall-guarded so this degrades gracefully if cm-admin somehow isn't up.
function rivalMember(characterId)
    local ok, rival = pcall(function()
        return exports[Config.AdminResource]:FindRivalMembership(Config.OrganizationId, characterId)
    end)
    if not ok or type(rival) ~= 'table' then return nil end
    return rival
end

function emsSetting(key)
    key = tostring(key or '')
    if EMSSettingsCache[key] ~= nil then return EMSSettingsCache[key] end
    return (Config.Operations or {})[key]
end

function setEmsSetting(key, value)
    key = tostring(key or '')
    if (Config.Operations or {})[key] == nil then return false end
    EMSSettingsCache[key] = value
    MySQL.insert.await([[INSERT INTO cm_ems_settings (`setting_key`, `setting_value`, `updated_at`)
        VALUES (?, ?, CURRENT_TIMESTAMP) ON DUPLICATE KEY UPDATE `setting_value` = VALUES(`setting_value`), `updated_at` = CURRENT_TIMESTAMP]],
        { key, json.encode({ value = value }) })
    return true
end

function dbBoolean(value)
    return value == true or tonumber(value) == 1
end

local function sanitizeOutfit(raw)
    if type(raw) ~= 'table' then return nil end
    local clean = { components = {}, props = {} }
    for key, value in pairs(raw.components or {}) do
        local index = tonumber(key)
        if index and index >= 0 and index <= 11 and type(value) == 'table' then
            local drawable = math.floor(tonumber(value.drawable) or -1)
            local texture = math.floor(tonumber(value.texture) or -1)
            local palette = math.floor(tonumber(value.palette) or 0)
            if drawable >= 0 and drawable <= 1000 and texture >= 0 and texture <= 1000 and palette >= 0 and palette <= 3 then
                clean.components[tostring(index)] = { drawable = drawable, texture = texture, palette = palette }
            end
        end
    end
    for key, value in pairs(raw.props or {}) do
        local index = tonumber(key)
        if index and index >= 0 and index <= 7 and type(value) == 'table' then
            local drawable = math.floor(tonumber(value.drawable) or -1)
            local texture = math.floor(tonumber(value.texture) or 0)
            if drawable >= -1 and drawable <= 1000 and texture >= 0 and texture <= 1000 then
                clean.props[tostring(index)] = { drawable = drawable, texture = texture }
            end
        end
    end
    if next(clean.components) == nil then return nil end
    return clean
end

local function cleanPresetName(value)
    local name = tostring(value or ''):gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if #name < 2 or #name > 32 then return nil end
    return name
end

local function presetRows(outfitSex)
    local rows = MySQL.query.await('SELECT id, name, updated_at FROM cm_ems_outfit_presets WHERE sex = ? ORDER BY name ASC', { outfitSex }) or {}
    for _, row in ipairs(rows) do
        row.id = tonumber(row.id)
        row.updatedAt = tostring(row.updated_at or '')
        row.updated_at = nil
    end
    return rows
end

local function favoriteOutfitRows(characterId, outfitSex)
    local rows = MySQL.query.await([[SELECT slot, name, updated_at FROM cm_ems_favorite_outfits
        WHERE character_id = ? AND sex = ? ORDER BY slot ASC]], { characterId, outfitSex }) or {}
    for _, row in ipairs(rows) do
        row.slot = tonumber(row.slot)
        row.updatedAt = tostring(row.updated_at or '')
        row.updated_at = nil
    end
    return rows
end

-- Resolves what a member should be wearing for duty: their own chosen preset
-- (if it still exists and matches their current sex), else the oldest
-- available preset for that sex, else nil (no wardrobe configured yet).
local function resolveMemberOutfit(characterId, outfitSex)
    local favoriteSelection = MySQL.single.await([[SELECT f.outfit FROM cm_ems_favorite_outfit_selection s
        JOIN cm_ems_favorite_outfits f ON f.character_id = s.character_id AND f.slot = s.slot
        WHERE s.character_id = ? AND f.sex = ? LIMIT 1]], { characterId, outfitSex })
    if favoriteSelection then return decode(favoriteSelection.outfit), nil end
    local chosen = MySQL.single.await('SELECT preset_id FROM cm_ems_member_outfit WHERE character_id = ? LIMIT 1', { characterId })
    local presetId = chosen and tonumber(chosen.preset_id) or nil
    local row
    if presetId then
        row = MySQL.single.await('SELECT id, outfit FROM cm_ems_outfit_presets WHERE id = ? AND sex = ? LIMIT 1', { presetId, outfitSex })
    end
    if not row then
        row = MySQL.single.await('SELECT id, outfit FROM cm_ems_outfit_presets WHERE sex = ? ORDER BY id ASC LIMIT 1', { outfitSex })
    end
    if not row then return nil, nil end
    return decode(row.outfit), tonumber(row.id)
end

-- Verifies (never applies) a member's currently-worn clothing against
-- their duty outfit before letting them go on duty. Compares
-- drawable+texture per component/prop slot -- palette (a color-tint
-- nuance, not "which item this is") is deliberately not compared. Ported
-- verbatim from cm-police/server/main.lua's outfitsMatch.
local function outfitsMatch(current, duty)
    if type(current) ~= 'table' or type(duty) ~= 'table' then return false end
    for index = 0, 11 do
        local key = tostring(index)
        local a, b = (current.components or {})[key], (duty.components or {})[key]
        local aDrawable, aTexture = a and tonumber(a.drawable) or -1, a and tonumber(a.texture) or -1
        local bDrawable, bTexture = b and tonumber(b.drawable) or -1, b and tonumber(b.texture) or -1
        if aDrawable ~= bDrawable or aTexture ~= bTexture then return false end
    end
    for index = 0, 7 do
        local key = tostring(index)
        local a, b = (current.props or {})[key], (duty.props or {})[key]
        local aDrawable, aTexture = a and tonumber(a.drawable) or -1, a and tonumber(a.texture) or -1
        local bDrawable, bTexture = b and tonumber(b.drawable) or -1, b and tonumber(b.texture) or -1
        if aDrawable ~= bDrawable or aTexture ~= bTexture then return false end
    end
    return true
end

-- ============================================================
--  Wardrobe NPC -- the only way to change/wear a duty outfit (see
--  wear_favorite_outfit/choose_outfit below). Location cached from the
--  generic cm_ems_settings key/value table, same store emsSetting()/
--  setEmsSetting() use for Config.Operations overrides -- writes here go
--  straight to the table since setEmsSetting() only accepts known
--  Config.Operations keys, but the existing boot-time loader already
--  pulls every row into EMSSettingsCache regardless of key, so reads via
--  emsSetting() work unmodified.
-- ============================================================

function GetClothingNpcStatus()
    return emsSetting('clothing_npc')
end

function SetClothingNpcLocation(src, actor, payload)
    if not has(actor, 'ems.manage_outfits') then return false, 'Your rank cannot set the EMS wardrobe location.' end
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
    local location = { x = x, y = y, z = z, heading = heading }
    local actorCid = cid(src)
    EMSSettingsCache['clothing_npc'] = location
    MySQL.insert.await([[INSERT INTO cm_ems_settings (setting_key, setting_value, updated_by)
        VALUES ('clothing_npc', ?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)]],
        { json.encode({ value = location }), actorCid })
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent('cm-ems:client:clothingNpcUpdated', tonumber(playerId), location)
    end
    log(actorCid, 'clothing_npc_set', {})
    return true, 'EMS wardrobe location saved.'
end

lib.callback.register('cm-ems:server:clothingNpcLocation', function(src) return GetClothingNpcStatus() end)

local function nearClothingNpc(src)
    local location = GetClothingNpcStatus()
    if not location then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped <= 0 then return false end
    local coords = GetEntityCoords(ped)
    local distance = math.max(1.0, tonumber((Config.Wardrobe or {}).NpcInteractDistance) or 2.5)
    return #(coords - vector3(location.x, location.y, location.z)) <= distance
end

local function permissionMap(rank)
    if not rank then return {} end
    if dbBoolean(rank.is_leader) then
        local all = {}
        for key in pairs(Config.Permissions) do all[key] = true end
        return all
    end
    local raw = decode(rank.permissions)
    local out = {}
    for key, value in pairs(raw) do
        if type(key) == 'number' then out[tostring(value)] = true else out[tostring(key)] = value == true end
    end
    return out
end

function memberFor(characterId)
    return MySQL.single.await([[
        SELECT m.character_id, m.rank_id, m.on_duty, r.name AS rank_name,
               r.tier, r.is_leader, r.permissions, m.suspended_until, m.suspension_reason,
               (m.suspended_until IS NOT NULL AND m.suspended_until > NOW()) AS is_suspended
        FROM cm_ems_members m JOIN cm_ems_ranks r ON r.id = m.rank_id
        WHERE m.character_id = ? LIMIT 1
    ]], { tostring(characterId) })
end

function has(member, permission)
    return member and (dbBoolean(member.is_leader) or permissionMap(member)[permission] == true)
end

local function stateFor(characterId)
    local member = memberFor(characterId)
    if not member then return false end
    return {
        organizationId = 1,
        name = 'Emergency Medical Services',
        rankId = tonumber(member.rank_id),
        rankName = member.rank_name,
        tier = tonumber(member.tier) or 0,
        isLeader = dbBoolean(member.is_leader),
        onDuty = dbBoolean(member.on_duty),
        suspended = dbBoolean(member.is_suspended),
        suspendedUntil = member.suspended_until and tostring(member.suspended_until) or nil,
        suspensionReason = member.suspension_reason,
        permissions = permissionMap(member),
    }
end

local function sync(characterId)
    local src = sourceFor(characterId)
    if not src then return end
    Player(src).state:set('cmEms', stateFor(characterId), true)
    if GetResourceState('cm-chat') == 'started' then
        TriggerEvent('cm-chat:server:refreshPlayerChannels', src)
    end
end

function log(characterId, action, detail)
    MySQL.insert.await('INSERT INTO cm_ems_activity (actor_cid, action, detail) VALUES (?, ?, ?)', {
        characterId and tostring(characterId) or false, tostring(action), json.encode(detail or {})
    })
end

function rateLimit(src, action, waitMs)
    local key = ('%s:%s'):format(src, action)
    local now = GetGameTimer()
    if useLocks[key] and now - useLocks[key] < (waitMs or 800) then return false end
    useLocks[key] = now
    return true
end

function EMSIsReady()
    return ready == true
end

local function setupDatabase()
    local statements = {
        [[CREATE TABLE IF NOT EXISTS cm_ems_organization (id TINYINT UNSIGNED NOT NULL DEFAULT 1, name VARCHAR(64) NOT NULL DEFAULT 'Emergency Medical Services', leader_cid VARCHAR(64) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_ranks (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, name VARCHAR(48) NOT NULL, tier SMALLINT UNSIGNED NOT NULL, is_leader TINYINT(1) NOT NULL DEFAULT 0, permissions LONGTEXT NOT NULL, PRIMARY KEY (id), UNIQUE KEY uniq_cm_ems_rank_tier (tier)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_members (character_id VARCHAR(64) NOT NULL, rank_id BIGINT UNSIGNED NOT NULL, on_duty TINYINT(1) NOT NULL DEFAULT 0, joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (character_id), KEY idx_cm_ems_member_rank (rank_id), CONSTRAINT fk_cm_ems_member_rank FOREIGN KEY (rank_id) REFERENCES cm_ems_ranks(id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_invites (character_id VARCHAR(64) NOT NULL, invited_by VARCHAR(64) NOT NULL, expires_at TIMESTAMP NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (character_id), KEY idx_cm_ems_invite_expiry (expires_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        -- Superseded by cm_ems_outfit_presets below (a member now picks from a
        -- named wardrobe instead of one shared uniform per sex) -- left in
        -- place rather than dropped, and copied from once at migration time.
        [[CREATE TABLE IF NOT EXISTS cm_ems_outfits (sex ENUM('male','female') NOT NULL, outfit LONGTEXT NOT NULL, updated_by VARCHAR(64) NOT NULL, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (sex)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_outfit_presets (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, sex ENUM('male','female') NOT NULL, name VARCHAR(32) NOT NULL, outfit LONGTEXT NOT NULL, created_by VARCHAR(64) NULL, updated_by VARCHAR(64) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (id), UNIQUE KEY uniq_cm_ems_outfit_preset (sex, name)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        -- What each EMS member currently has picked from the wardrobe.
        -- Not a persistent inventory item: this only ever drives the
        -- on-duty appearance swap in client/main.lua, and is reverted to the
        -- member's own civilian clothes the moment they go off duty.
        [[CREATE TABLE IF NOT EXISTS cm_ems_member_outfit (character_id VARCHAR(64) NOT NULL, preset_id BIGINT UNSIGNED NULL, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (character_id), CONSTRAINT fk_cm_ems_member_outfit_preset FOREIGN KEY (preset_id) REFERENCES cm_ems_outfit_presets(id) ON DELETE SET NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_favorite_outfits (character_id VARCHAR(64) NOT NULL, slot TINYINT UNSIGNED NOT NULL, sex ENUM('male','female') NOT NULL, name VARCHAR(32) NOT NULL, outfit LONGTEXT NOT NULL, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (character_id, slot), KEY idx_cm_ems_favorite_outfits_character_sex (character_id, sex)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_favorite_outfit_selection (character_id VARCHAR(64) NOT NULL, slot TINYINT UNSIGNED NOT NULL, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (character_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_activity (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, actor_cid VARCHAR(64) NULL, action VARCHAR(64) NOT NULL, detail LONGTEXT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (id), KEY idx_cm_ems_activity_created (created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_settings (setting_key VARCHAR(64) NOT NULL, setting_value LONGTEXT NOT NULL, updated_by VARCHAR(64) NULL, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (setting_key)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_medical_reports (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, incident_id BIGINT UNSIGNED NULL, patient_cid VARCHAR(64) NOT NULL, patient_name VARCHAR(96) NOT NULL, medic_cid VARCHAR(64) NULL, medic_name VARCHAR(96) NOT NULL, hospital_id VARCHAR(48) NULL, location VARCHAR(160) NULL, injuries LONGTEXT NULL, treatment LONGTEXT NULL, medications LONGTEXT NULL, vitals LONGTEXT NULL, outcome VARCHAR(48) NOT NULL DEFAULT 'treated', billing INT NOT NULL DEFAULT 0, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (id), KEY idx_cm_ems_report_patient (patient_cid, created_at), KEY idx_cm_ems_report_incident (incident_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_incidents (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, incident_number VARCHAR(32) NOT NULL, caller_cid VARCHAR(64) NULL, caller_name VARCHAR(96) NOT NULL DEFAULT 'Unknown caller', emergency_type VARCHAR(48) NOT NULL DEFAULT 'medical', priority TINYINT UNSIGNED NOT NULL DEFAULT 2, patient_count SMALLINT UNSIGNED NOT NULL DEFAULT 1, coords LONGTEXT NOT NULL, postal VARCHAR(24) NULL, details VARCHAR(255) NULL, status VARCHAR(32) NOT NULL DEFAULT 'waiting', responders LONGTEXT NOT NULL, resolution VARCHAR(96) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, resolved_at TIMESTAMP NULL, PRIMARY KEY (id), UNIQUE KEY uniq_cm_ems_incident_number (incident_number), KEY idx_cm_ems_incident_status (status, created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_reward_claims (claim_key VARCHAR(128) NOT NULL, medic_cid VARCHAR(64) NOT NULL, patient_cid VARCHAR(64) NOT NULL, amount INT NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (claim_key), KEY idx_cm_ems_reward_medic (medic_cid, created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_task_progress (character_id VARCHAR(64) NOT NULL, period_type ENUM('daily','weekly') NOT NULL, period_key VARCHAR(24) NOT NULL, task_id VARCHAR(64) NOT NULL, progress INT UNSIGNED NOT NULL DEFAULT 0, claimed TINYINT(1) NOT NULL DEFAULT 0, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (character_id, period_type, period_key, task_id), KEY idx_cm_ems_tasks_period (period_type, period_key)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_task_events (event_key VARCHAR(160) NOT NULL, character_id VARCHAR(64) NOT NULL, metric VARCHAR(48) NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (event_key), KEY idx_cm_ems_task_events_member (character_id, created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_employee_progress (character_id VARCHAR(64) NOT NULL, xp INT UNSIGNED NOT NULL DEFAULT 0, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (character_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_incident_events (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, incident_id BIGINT UNSIGNED NOT NULL, actor_cid VARCHAR(64) NULL, actor_name VARCHAR(96) NULL, event_type VARCHAR(48) NOT NULL, detail LONGTEXT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (id), KEY idx_cm_ems_incident_events_incident (incident_id, created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_mission_runs (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, character_id VARCHAR(64) NOT NULL, mission_id VARCHAR(64) NOT NULL, status ENUM('active','completed','cancelled','failed') NOT NULL DEFAULT 'active', route LONGTEXT NOT NULL, reward INT UNSIGNED NOT NULL DEFAULT 0, xp INT UNSIGNED NOT NULL DEFAULT 0, started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, completed_at TIMESTAMP NULL, PRIMARY KEY (id), KEY idx_cm_ems_mission_member (character_id, status, started_at), KEY idx_cm_ems_mission_cooldown (character_id, mission_id, completed_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_mission_definitions (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, mission_key VARCHAR(64) NOT NULL, label VARCHAR(64) NOT NULL, category VARCHAR(32) NOT NULL DEFAULT 'EMS', description VARCHAR(255) NOT NULL, reward INT UNSIGNED NOT NULL DEFAULT 0, xp INT UNSIGNED NOT NULL DEFAULT 0, time_limit_seconds INT UNSIGNED NULL, patient TINYINT(1) NOT NULL DEFAULT 1, automatic_emergency TINYINT(1) NOT NULL DEFAULT 0, enabled TINYINT(1) NOT NULL DEFAULT 1, stages LONGTEXT NOT NULL, created_by VARCHAR(64) NULL, updated_by VARCHAR(64) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (id), UNIQUE KEY uniq_cm_ems_mission_key (mission_key), KEY idx_cm_ems_mission_enabled (enabled, automatic_emergency)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_mission_participants (run_id BIGINT UNSIGNED NOT NULL, character_id VARCHAR(64) NOT NULL, role ENUM('leader','member') NOT NULL DEFAULT 'member', contributed_stages INT UNSIGNED NOT NULL DEFAULT 0, reward_paid TINYINT(1) NOT NULL DEFAULT 0, joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (run_id, character_id), KEY idx_cm_ems_participant_member (character_id, joined_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_public_incidents (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, mission_id VARCHAR(64) NOT NULL, label VARCHAR(64) NOT NULL, category VARCHAR(32) NOT NULL, description VARCHAR(255) NOT NULL, route LONGTEXT NOT NULL, reward INT UNSIGNED NOT NULL DEFAULT 0, xp INT UNSIGNED NOT NULL DEFAULT 0, time_limit_seconds INT UNSIGNED NULL, status ENUM('open','assigned','completed','expired','cancelled') NOT NULL DEFAULT 'open', run_id BIGINT UNSIGNED NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, expires_at DATETIME NOT NULL, assigned_at TIMESTAMP NULL, completed_at TIMESTAMP NULL, PRIMARY KEY (id), KEY idx_cm_ems_public_status (status, expires_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_ems_migrations (migration_key VARCHAR(64) NOT NULL, applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (migration_key)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        -- One random mission per character per real calendar day, assigned
        -- by the daily mission NPC (server/missions.lua) at a boosted
        -- reward. period_key is a plain 'YYYY-MM-DD' string, not a stored
        -- DATE compared against NOW() -- same convention as
        -- cm_ems_task_progress, so a new day is just a new row.
        [[CREATE TABLE IF NOT EXISTS cm_ems_daily_mission (character_id VARCHAR(64) NOT NULL, period_key VARCHAR(16) NOT NULL, mission_id VARCHAR(64) NOT NULL, run_id BIGINT UNSIGNED NULL, reward INT UNSIGNED NOT NULL DEFAULT 0, status ENUM('assigned','completed') NOT NULL DEFAULT 'assigned', assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, completed_at TIMESTAMP NULL, PRIMARY KEY (character_id, period_key)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        -- Superseded by cm_ems_fleet_vehicles below (appearance now lives in
        -- rn-vehicleshop's catalog) -- left in place rather than dropped since
        -- it may hold data on servers that used the old configurator.
        [[CREATE TABLE IF NOT EXISTS cm_ems_vehicles (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, label VARCHAR(48) NOT NULL, model VARCHAR(64) NOT NULL, kind ENUM('car','helicopter') NOT NULL DEFAULT 'car', mods LONGTEXT NOT NULL, image VARCHAR(255) NULL, spawn_x FLOAT NOT NULL, spawn_y FLOAT NOT NULL, spawn_z FLOAT NOT NULL, spawn_h FLOAT NOT NULL DEFAULT 0, enabled TINYINT(1) NOT NULL DEFAULT 1, created_by VARCHAR(64) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        -- Model, appearance and image now come live from rn-vehicleshop's
        -- catalog (GetEmsCatalog export) -- this table only owns what's
        -- EMS-specific: where a vehicle spawns, whether it's a car or
        -- helicopter (for cm-vehicles' trusted-placement path), the minimum
        -- rank tier required to spawn it, and whether it's currently enabled.
        [[CREATE TABLE IF NOT EXISTS cm_ems_fleet_vehicles (model VARCHAR(64) NOT NULL, kind ENUM('car','helicopter') NOT NULL DEFAULT 'car', min_tier SMALLINT UNSIGNED NOT NULL DEFAULT 0, enabled TINYINT(1) NOT NULL DEFAULT 1, spawn_x FLOAT NOT NULL, spawn_y FLOAT NOT NULL, spawn_z FLOAT NOT NULL, spawn_h FLOAT NOT NULL DEFAULT 0, updated_by VARCHAR(64) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (model)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    }
    for _, query in ipairs(statements) do MySQL.query.await(query) end
    for _, column in ipairs({
        { name = 'suspended_until', sql = 'ALTER TABLE cm_ems_members ADD COLUMN suspended_until DATETIME NULL AFTER on_duty' },
        { name = 'suspension_reason', sql = 'ALTER TABLE cm_ems_members ADD COLUMN suspension_reason VARCHAR(160) NULL AFTER suspended_until' },
        { name = 'suspended_by', sql = 'ALTER TABLE cm_ems_members ADD COLUMN suspended_by VARCHAR(64) NULL AFTER suspension_reason' },
    }) do
        if not MySQL.scalar.await([[SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_ems_members' AND COLUMN_NAME = ? LIMIT 1]], { column.name }) then
            MySQL.query.await(column.sql)
        end
    end
    if not MySQL.scalar.await([[SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_ems_fleet_vehicles' AND COLUMN_NAME = 'vehicle_id' LIMIT 1]]) then
        MySQL.query.await('ALTER TABLE cm_ems_fleet_vehicles ADD COLUMN vehicle_id BIGINT UNSIGNED NULL AFTER model, ADD UNIQUE KEY uniq_cm_ems_fleet_vehicle_id (vehicle_id)')
    end
    if not MySQL.scalar.await([[SELECT INDEX_NAME FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_ems_fleet_vehicles' AND INDEX_NAME = 'uniq_cm_ems_fleet_vehicle_id' LIMIT 1]]) then
        MySQL.query.await('CREATE UNIQUE INDEX uniq_cm_ems_fleet_vehicle_id ON cm_ems_fleet_vehicles (vehicle_id)')
    end
    MySQL.insert.await([[INSERT INTO cm_ems_organization (id, name) VALUES (1, 'Emergency Medical Services') ON DUPLICATE KEY UPDATE name = VALUES(name)]])
    for _, row in ipairs(MySQL.query.await('SELECT setting_key, setting_value FROM cm_ems_settings') or {}) do
        local decoded = decode(row.setting_value)
        EMSSettingsCache[tostring(row.setting_key)] = decoded.value ~= nil and decoded.value or decoded[1]
    end
    local existingRankCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_ems_ranks')) or 0
    if existingRankCount == 0 then
        for _, rank in ipairs(Config.Ranks) do
            local permissions = rank.permissions == 'ALL' and '{}' or json.encode(rank.permissions or {})
            MySQL.insert.await('INSERT INTO cm_ems_ranks (name, tier, is_leader, permissions) VALUES (?, ?, ?, ?)',
                { rank.name, rank.tier, rank.leader and 1 or 0, permissions })
        end
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_ems_migrations WHERE migration_key = ? LIMIT 1', { 'v1.1_chief_rank_management' }) then
        local chief = MySQL.single.await('SELECT id, permissions FROM cm_ems_ranks WHERE name = ? AND is_leader = 0 LIMIT 1', { 'Chief Paramedic' })
        if chief then
            local stored, seen, permissions = decode(chief.permissions), {}, {}
            for key, value in pairs(stored) do
                local permission = type(key) == 'number' and tostring(value) or tostring(key)
                local enabled = type(key) == 'number' or value == true
                if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
            end
            if not seen['ems.manage_ranks'] then permissions[#permissions + 1] = 'ems.manage_ranks' end
            if not seen['ems.manage_permissions'] then permissions[#permissions + 1] = 'ems.manage_permissions' end
            table.sort(permissions)
            MySQL.update.await('UPDATE cm_ems_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), chief.id })
        end
        MySQL.insert.await('INSERT INTO cm_ems_migrations (migration_key) VALUES (?)', { 'v1.1_chief_rank_management' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_ems_migrations WHERE migration_key = ? LIMIT 1', { 'v1.4_fleet_vehicle_permission' }) then
        for _, rankName in ipairs({ 'Chief Paramedic', 'Paramedic' }) do
            local rank = MySQL.single.await('SELECT id, permissions FROM cm_ems_ranks WHERE name = ? AND is_leader = 0 LIMIT 1', { rankName })
            if rank then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['ems.spawn_vehicles'] then permissions[#permissions + 1] = 'ems.spawn_vehicles' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_ems_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_ems_migrations (migration_key) VALUES (?)', { 'v1.4_fleet_vehicle_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_ems_migrations WHERE migration_key = ? LIMIT 1', { 'v2.1_dispatch_permissions' }) then
        local grants = {
            ['Chief Paramedic'] = { 'ems.receive_dispatch', 'ems.manage_dispatch' },
            ['Paramedic'] = { 'ems.receive_dispatch' },
        }
        for rankName, additions in pairs(grants) do
            local rank = MySQL.single.await('SELECT id, permissions FROM cm_ems_ranks WHERE name = ? AND is_leader = 0 LIMIT 1', { rankName })
            if rank then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then
                        seen[permission] = true
                        permissions[#permissions + 1] = permission
                    end
                end
                for _, permission in ipairs(additions) do
                    if not seen[permission] then permissions[#permissions + 1] = permission end
                end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_ems_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_ems_migrations (migration_key) VALUES (?)', { 'v2.1_dispatch_permissions' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_ems_migrations WHERE migration_key = ? LIMIT 1', { 'v2.2_government_doctor_permission' }) then
        for _, rankName in ipairs({ 'Chief Paramedic', 'Paramedic' }) do
            local rank = MySQL.single.await('SELECT id, permissions FROM cm_ems_ranks WHERE name = ? AND is_leader = 0 LIMIT 1', { rankName })
            if rank then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['ems.send_gov_doctor'] then permissions[#permissions + 1] = 'ems.send_gov_doctor' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_ems_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_ems_migrations (migration_key) VALUES (?)', { 'v2.2_government_doctor_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_ems_migrations WHERE migration_key = ? LIMIT 1', { 'v2.4_treat_player_permission' }) then
        for _, rankName in ipairs({ 'Chief Paramedic', 'Paramedic' }) do
            local rank = MySQL.single.await('SELECT id, permissions FROM cm_ems_ranks WHERE name = ? AND is_leader = 0 LIMIT 1', { rankName })
            if rank then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['ems.treat_player'] then permissions[#permissions + 1] = 'ems.treat_player' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_ems_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_ems_migrations (migration_key) VALUES (?)', { 'v2.4_treat_player_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_ems_migrations WHERE migration_key = ? LIMIT 1', { 'v1.8_outfit_presets' }) then
        local legacy = MySQL.query.await('SELECT sex, outfit, updated_by FROM cm_ems_outfits') or {}
        for _, row in ipairs(legacy) do
            MySQL.insert.await([[INSERT INTO cm_ems_outfit_presets (sex, name, outfit, created_by, updated_by) VALUES (?, 'Default', ?, ?, ?) ON DUPLICATE KEY UPDATE outfit = outfit]],
                { row.sex, row.outfit, row.updated_by, row.updated_by })
        end
        MySQL.insert.await('INSERT INTO cm_ems_migrations (migration_key) VALUES (?)', { 'v1.8_outfit_presets' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_ems_migrations WHERE migration_key = ? LIMIT 1', { 'v4_operations_permissions' }) then
        local grants = {
            ['Chief Paramedic'] = {
                'ems.use_wardrobe', 'ems.use_storage', 'ems.drive_ambulance', 'ems.fly_helicopter',
                'ems.administer_medication', 'ems.write_medical_reports', 'ems.view_medical_reports',
                'ems.request_backup', 'ems.use_panic', 'ems.manage_hospital', 'ems.manage_billing', 'ems.suspend_members',
            },
            ['Paramedic'] = {
                'ems.use_wardrobe', 'ems.use_storage', 'ems.drive_ambulance', 'ems.fly_helicopter',
                'ems.administer_medication', 'ems.write_medical_reports', 'ems.view_medical_reports',
                'ems.request_backup', 'ems.use_panic',
            },
            ['Trainee'] = { 'ems.use_wardrobe' },
        }
        for rankName, additions in pairs(grants) do
            local rank = MySQL.single.await('SELECT id, permissions FROM cm_ems_ranks WHERE name = ? AND is_leader = 0 LIMIT 1', { rankName })
            if rank then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    if (type(key) == 'number' or value == true) and Config.Permissions[permission] and not seen[permission] then
                        seen[permission] = true; permissions[#permissions + 1] = permission
                    end
                end
                for _, permission in ipairs(additions) do if not seen[permission] then permissions[#permissions + 1] = permission end end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_ems_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        if not MySQL.scalar.await('SELECT id FROM cm_ems_ranks WHERE name = ? LIMIT 1', { 'Recruit' }) then
            MySQL.update.await("UPDATE cm_ems_ranks SET name = 'Recruit' WHERE name = 'Trainee' AND is_leader = 0")
        end
        MySQL.insert.await('INSERT INTO cm_ems_migrations (migration_key) VALUES (?)', { 'v4_operations_permissions' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_ems_migrations WHERE migration_key = ? LIMIT 1', { 'v5.1_medicine_sale_permission' }) then
        for _, rankName in ipairs({ 'Chief Paramedic', 'Paramedic' }) do
            local rank = MySQL.single.await('SELECT id, permissions FROM cm_ems_ranks WHERE name = ? AND is_leader = 0 LIMIT 1', { rankName })
            if rank then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['ems.sell_medicine'] then permissions[#permissions + 1] = 'ems.sell_medicine' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_ems_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_ems_migrations (migration_key) VALUES (?)', { 'v5.1_medicine_sale_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_ems_migrations WHERE migration_key = ? LIMIT 1', { 'v5.1_shared_stock_sales_permissions' }) then
        for _, rankName in ipairs({ 'Chief Paramedic', 'EMS Supervisor', 'Paramedic', 'EMT' }) do
            local rank = MySQL.single.await('SELECT id, permissions FROM cm_ems_ranks WHERE name = ? AND is_leader = 0 LIMIT 1', { rankName })
            if rank then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then
                        seen[permission] = true
                        permissions[#permissions + 1] = permission
                    end
                end
                if not seen['ems.sell_medicine'] then permissions[#permissions + 1] = 'ems.sell_medicine' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_ems_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_ems_migrations (migration_key) VALUES (?)', { 'v5.1_shared_stock_sales_permissions' })
    end
    local organizationLeader = MySQL.scalar.await('SELECT leader_cid FROM cm_ems_organization WHERE id = 1 LIMIT 1')
    if organizationLeader then
        organizationLeader = tostring(organizationLeader)
        local leaderRank = MySQL.single.await('SELECT id FROM cm_ems_ranks WHERE is_leader = 1 LIMIT 1')
        local chiefRank = MySQL.single.await('SELECT id FROM cm_ems_ranks WHERE is_leader = 0 ORDER BY tier DESC LIMIT 1')
        if leaderRank and chiefRank then
            local reconciled = MySQL.transaction.await({
                { query = 'UPDATE cm_ems_members SET rank_id = ?, on_duty = 0 WHERE rank_id = ? AND character_id <> ?', values = { chiefRank.id, leaderRank.id, organizationLeader } },
                { query = [[INSERT INTO cm_ems_members (character_id, rank_id, on_duty) VALUES (?, ?, 0) ON DUPLICATE KEY UPDATE rank_id = VALUES(rank_id)]], values = { organizationLeader, leaderRank.id } },
            })
            if reconciled ~= true then error('EMS leader membership reconciliation failed') end
        end
    end
    -- Active mission stages are restored by server/missions.lua after all
    -- definitions and online character sources are available.
    ready = true
    for _, player in ipairs(GetPlayers()) do
        local characterId = cid(player)
        if characterId then sync(characterId) end
    end
    print('[cm-ems] single EMS organization ready')
end

local function rankRows()
    local rows = MySQL.query.await('SELECT id, name, tier, is_leader, permissions FROM cm_ems_ranks ORDER BY tier DESC') or {}
    for _, rank in ipairs(rows) do
        rank.id, rank.tier = tonumber(rank.id), tonumber(rank.tier)
        rank.isLeader = dbBoolean(rank.is_leader)
        rank.permissions = permissionMap(rank)
        rank.is_leader = nil
    end
    return rows
end

local function roster()
    local rows = MySQL.query.await([[
        SELECT m.character_id, m.on_duty, m.joined_at, m.suspended_until, m.suspension_reason,
               (m.suspended_until IS NOT NULL AND m.suspended_until > NOW()) AS is_suspended,
               r.id AS rank_id, r.name AS rank_name, r.tier, r.is_leader
        FROM cm_ems_members m JOIN cm_ems_ranks r ON r.id = m.rank_id ORDER BY r.tier DESC, m.joined_at ASC
    ]]) or {}
    for _, row in ipairs(rows) do
        row.characterId = tostring(row.character_id)
        row.name = nameFor(row.character_id)
        row.rankName = tostring(row.rank_name or 'EMS Member')
        row.rankId, row.tier = tonumber(row.rank_id), tonumber(row.tier)
        row.onDuty = dbBoolean(row.on_duty)
        row.isLeader = dbBoolean(row.is_leader)
        row.suspended = dbBoolean(row.is_suspended)
        row.suspendedUntil = row.suspended_until and tostring(row.suspended_until) or nil
        row.suspensionReason = row.suspension_reason
        row.online = sourceFor(row.character_id) ~= nil
        row.character_id, row.rank_id, row.rank_name, row.on_duty, row.is_leader = nil, nil, nil, nil, nil
        row.suspended_until, row.suspension_reason, row.is_suspended = nil, nil, nil
    end
    return rows
end

local function medicStatistics(characterId)
    if not characterId then
        return { patientsTreated = 0, patientsRevived = 0, callsCompleted = 0, averageResponseSeconds = 0 }
    end
    local patientCounts = MySQL.single.await([[SELECT
            COUNT(*) AS treated,
            SUM(outcome = 'revived_on_scene') AS revived
        FROM cm_ems_medical_reports
        WHERE medic_cid = ?
          AND outcome IN ('revived_on_scene', 'treated_on_scene', 'treated', 'transported', 'admitted')]],
        { tostring(characterId) }) or {}
    local calls = tonumber(MySQL.scalar.await([[SELECT COUNT(DISTINCT i.id)
        FROM cm_ems_incidents i
        JOIN cm_ems_incident_events accepted ON accepted.incident_id = i.id
            AND accepted.event_type = 'accepted' AND accepted.actor_cid = ?
        WHERE i.resolved_at IS NOT NULL]], { tostring(characterId) })) or 0
    local average = tonumber(MySQL.scalar.await([[SELECT AVG(TIMESTAMPDIFF(SECOND, i.created_at, scene.first_scene))
        FROM cm_ems_incidents i
        JOIN (
            SELECT incident_id, MIN(created_at) AS first_scene
            FROM cm_ems_incident_events
            WHERE event_type = 'on_scene' AND actor_cid = ?
            GROUP BY incident_id
        ) scene ON scene.incident_id = i.id]], { tostring(characterId) })) or 0
    return {
        patientsTreated = math.max(0, math.floor(tonumber(patientCounts.treated) or 0)),
        patientsRevived = math.max(0, math.floor(tonumber(patientCounts.revived) or 0)),
        callsCompleted = math.max(0, math.floor(calls)),
        averageResponseSeconds = math.max(0, math.floor(average + 0.5)),
    }
end

local function dashboard(src, adminMode, requestedSex)
    if not ready then return nil, 'EMS database is not ready.' end
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    local isAdmin = adminMode == true and exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission)
    if not member and not isAdmin then return nil, 'You are not an EMS member.' end
    -- Repair a missing/stale replicated membership state whenever a valid
    -- organization member opens the dashboard.
    if member and characterId then sync(characterId) end
    local org = MySQL.single.await('SELECT leader_cid FROM cm_ems_organization WHERE id = 1') or {}
    local outfitSex = requestedSex == 'female' and 'female' or 'male'
    local outfitPresets = presetRows(outfitSex)
    local favoriteOutfits = characterId and favoriteOutfitRows(characterId, outfitSex) or {}
    local selectedFavoriteSlot = characterId and tonumber(MySQL.scalar.await(
        'SELECT slot FROM cm_ems_favorite_outfit_selection WHERE character_id = ? LIMIT 1', { characterId })) or nil
    local chosenOutfitPresetId
    if characterId then
        local chosen = MySQL.single.await('SELECT preset_id FROM cm_ems_member_outfit WHERE character_id = ? LIMIT 1', { characterId })
        chosenOutfitPresetId = chosen and tonumber(chosen.preset_id) or nil
    end
    local canViewLogs = isAdmin or has(member, 'ems.view_logs')
    local logs = {}
    if canViewLogs then
        local limit = math.max(1, math.min(tonumber(Config.LogLimit) or 100, 250))
        logs = MySQL.query.await(([=[
            SELECT a.id, a.actor_cid, a.action, a.detail, a.created_at,
                   TRIM(CONCAT(COALESCE(c.first_name, ''), ' ', COALESCE(c.last_name, ''))) AS actor_name
            FROM cm_ems_activity a
            LEFT JOIN characters c ON c.id = a.actor_cid
            ORDER BY a.id DESC LIMIT %d
        ]=]):format(limit)) or {}
        for _, row in ipairs(logs) do
            row.id = tonumber(row.id)
            row.actorCid = row.actor_cid and tostring(row.actor_cid) or nil
            row.actorName = not row.actor_cid and 'System'
                or (row.actor_name and row.actor_name ~= '' and row.actor_name)
                or ('Character #%s'):format(tostring(row.actor_cid))
            row.detail = decode(row.detail)
            row.createdAt = tostring(row.created_at or '')
            row.actor_cid, row.actor_name, row.created_at = nil, nil, nil
        end
    end
    local operations = {}
    if canViewLogs or isAdmin or has(member, 'ems.manage_hospital') then
        operations.activeCalls = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM cm_ems_incidents
            WHERE status NOT IN ('resolved','removed','expired')]])) or 0
        operations.waitingTooLong = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM cm_ems_incidents
            WHERE status = 'waiting' AND created_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 2 MINUTE)]])) or 0
        operations.onDutyMedics = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_ems_members WHERE on_duty = 1')) or 0
        local pending = 0
        pcall(function()
            pending = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM cm_ems_medicine_sales
                WHERE status = 'refund_pending']])) or 0
        end)
        operations.pendingReconciliations = pending
        local stock = type(EMSGetMedicineStockForSource) == 'function' and EMSGetMedicineStockForSource(src) or {}
        operations.medicineStockPercent = tonumber(stock and stock.percent) or 0
    end
    return {
        organization = { name = 'Emergency Medical Services', leaderCid = org.leader_cid and tostring(org.leader_cid) or nil, leaderName = org.leader_cid and nameFor(org.leader_cid) or 'Not assigned' },
        self = member and stateFor(characterId) or nil,
        statistics = medicStatistics(characterId),
        operations = operations,
        members = roster(), ranks = rankRows(),
        outfitSex = outfitSex, outfitPresets = outfitPresets, chosenOutfitPresetId = chosenOutfitPresetId,
        favoriteOutfits = favoriteOutfits, maxFavoriteOutfitSlots = MAX_FAVORITE_OUTFIT_SLOTS,
        selectedFavoriteOutfitSlot = selectedFavoriteSlot,
        permissions = Config.Permissions, adminMode = isAdmin,
        capabilities = {
            manageRanks = isAdmin or has(member, 'ems.manage_ranks'),
            managePermissions = isAdmin or has(member, 'ems.manage_permissions'),
            manageOutfits = isAdmin or has(member, 'ems.manage_outfits'),
            manageVehicles = isAdmin or has(member, 'ems.manage_vehicles'),
            spawnVehicles = isAdmin or has(member, 'ems.spawn_vehicles'),
            viewMemberMap = has(member, 'ems.view_member_map'),
            setMeeting = has(member, 'ems.set_meeting'),
            viewMedicalReports = isAdmin or has(member, 'ems.view_medical_reports'),
            writeMedicalReports = has(member, 'ems.write_medical_reports'),
            manageHospital = isAdmin or has(member, 'ems.manage_hospital'),
            manageBilling = isAdmin or has(member, 'ems.manage_billing'),
            suspendMembers = isAdmin or has(member, 'ems.suspend_members'),
            manageMissions = isAdmin or has(member, 'ems.manage_missions'),
        },
        dailyMissionNpc = GetDailyMissionNpcStatus and GetDailyMissionNpcStatus() or nil,
        clothingNpc = GetClothingNpcStatus(),
        settings = {
            treatmentPrice = emsSetting('treatmentPrice'), deathRespawnPrice = emsSetting('deathRespawnPrice'),
            medicReward = emsSetting('medicReward'), aiArrivalMs = emsSetting('aiArrivalMs'),
            sharedResponseRadius = emsSetting('sharedResponseRadius'), hospitalEnabled = emsSetting('hospitalEnabled'),
            autoDispatchEnabled = emsSetting('autoDispatchEnabled'),
        },
        canViewLogs = canViewLogs, logs = logs,
    }
end

local function targetChange(actorCid, targetCid, direction)
    local actor, target = memberFor(actorCid), memberFor(targetCid)
    if not actor or not target then return false, 'EMS member not found.' end
    if tostring(actorCid) == tostring(targetCid) then return false, 'You cannot change your own rank.' end
    if dbBoolean(target.is_leader) then return false, 'The EMS leader rank is admin-managed.' end
    if tonumber(actor.tier) <= tonumber(target.tier) then return false, 'You can only manage lower ranks.' end
    local permission = direction == 'up' and 'ems.promote' or 'ems.demote'
    if not has(actor, permission) then return false, 'Your rank does not have permission.' end
    local op = direction == 'up' and '>' or '<'
    local order = direction == 'up' and 'ASC' or 'DESC'
    local rank = MySQL.single.await(('SELECT id, name, tier FROM cm_ems_ranks WHERE is_leader = 0 AND tier %s ? AND tier < ? ORDER BY tier %s LIMIT 1'):format(op, order), { target.tier, actor.tier })
    if not rank then return false, direction == 'up' and 'No available promotion rank.' or 'No available demotion rank.' end
    MySQL.update.await('UPDATE cm_ems_members SET rank_id = ? WHERE character_id = ?', { rank.id, targetCid })
    sync(targetCid)
    log(actorCid, direction == 'up' and 'member_promoted' or 'member_demoted', { targetCid = targetCid, rank = rank.name })
    return true, ('%s is now %s.'):format(nameFor(targetCid), rank.name)
end

local function cleanRankName(value)
    local name = tostring(value or ''):gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if #name < 3 or #name > 32 then return nil end
    return name
end

local function requestedPermissions(raw, actor)
    local requested, clean = {}, {}
    if type(raw) == 'table' then
        for key, value in pairs(raw) do
            local permission = type(key) == 'number' and tostring(value) or tostring(key)
            local enabled = type(key) == 'number' or value == true
            if enabled and Config.Permissions[permission] then requested[permission] = true end
        end
    end
    for permission in pairs(requested) do
        if not has(actor, permission) then return nil, ('You cannot grant %s.'):format(permission) end
        clean[#clean + 1] = permission
    end
    table.sort(clean)
    return clean
end

local function syncRankMembers(rankId)
    local rows = MySQL.query.await('SELECT character_id FROM cm_ems_members WHERE rank_id = ?', { rankId }) or {}
    for _, row in ipairs(rows) do sync(tostring(row.character_id)) end
end

lib.callback.register('cm-ems:server:dashboard', function(src, adminMode, requestedSex)
    return dashboard(src, adminMode == true, requestedSex)
end)

lib.callback.register('cm-ems:server:dutyOutfit', function(src, requestedSex)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or not dbBoolean(member.on_duty) then return nil end
    local outfitSex = requestedSex == 'female' and 'female' or 'male'
    local outfit = resolveMemberOutfit(characterId, outfitSex)
    return outfit
end)

lib.callback.register('cm-ems:server:emsWardrobeCatalog', function(src, requestedSex)
    local characterId = cid(src)
    if not characterId or not memberFor(characterId) then return {} end
    local gender = requestedSex == 'female' and 'female' or 'male'
    local rows = {}
    pcall(function()
        rows = exports['cm-items']:GetClothingCatalogRows({
            gender = gender, shop = 'org_ems', includeDisabled = true,
        }) or {}
    end)
    local catalog = {}
    for _, row in ipairs(rows) do
        catalog[#catalog + 1] = {
            id = tonumber(row.id),
            componentType = tostring(row.componentType or 'component'),
            componentIndex = tonumber(row.componentIndex) or 0,
            drawableId = tonumber(row.drawableId) or 0,
            textureId = math.max(0, tonumber(row.textureId) or 0),
            label = tostring(row.label or 'Item'),
            category = tostring(row.category or 'other'),
            image = row.image,
        }
    end
    return catalog
end)

local function endDuty(src, characterId, reason)
    src = tonumber(src)
    characterId = characterId and tostring(characterId) or (src and cid(src))
    local member = characterId and memberFor(characterId)
    if not member or not dbBoolean(member.on_duty) then return false end

    MySQL.update.await('UPDATE cm_ems_members SET on_duty = 0 WHERE character_id = ?', { characterId })
    TriggerEvent('cm-ems:server:memberWentOffDuty', src, characterId, tostring(reason or 'off_duty'))
    if src and GetPlayerName(src) then
        TriggerClientEvent('cm-ems:client:forceDutyCleanup', src, tostring(reason or 'off_duty'))
    end
    sync(characterId)
    log(characterId, 'duty_ended', { reason = tostring(reason or 'manual') })
    return true
end

lib.callback.register('cm-ems:server:action', function(src, action, payload)
    if not rateLimit(src, tostring(action), 650) then return false, 'Please wait.' end
    payload = type(payload) == 'table' and payload or {}
    local actorCid = cid(src)
    if not actorCid then return false, 'Character is not loaded.' end
    local actor = memberFor(actorCid)
    local isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true
    if not actor and isAdmin then actor = { tier = 101, is_leader = 1, permissions = '{}' } end
    if not actor then return false, 'You are not an EMS member.' end

    if action == 'toggle_duty' then
        if dbBoolean(actor.is_suspended) then return false, ('You are suspended until %s.'):format(tostring(actor.suspended_until or 'further notice')) end
        local nextDuty = not dbBoolean(actor.on_duty)
        if nextDuty then
            local outfitSex = payload.sex == 'female' and 'female' or 'male'
            local dutyOutfit = resolveMemberOutfit(actorCid, outfitSex)
            -- No favorite selected yet is not an error: with nothing to
            -- verify against, duty starts in whatever they're wearing,
            -- same allowance cm-police's wardrobe NPC uses.
            if dutyOutfit and not outfitsMatch(sanitizeOutfit(payload.currentOutfit), dutyOutfit) then
                return false, 'You must be wearing your duty outfit to go on duty. Visit the EMS wardrobe first.'
            end
            MySQL.update.await('UPDATE cm_ems_members SET on_duty = 1 WHERE character_id = ?', { actorCid })
            sync(actorCid)
            log(actorCid, 'duty_started', {})
        else
            endDuty(src, actorCid, 'manual')
        end
        return true, nextDuty and 'You are now on duty.' or 'You are now off duty.', { onDuty = nextDuty }
    elseif action == 'save_outfit_preset' then
        if not has(actor, 'ems.manage_outfits') then return false, 'Your rank cannot manage EMS clothing.' end
        local sex = payload.sex == 'female' and 'female' or payload.sex == 'male' and 'male' or nil
        local name = cleanPresetName(payload.name)
        local outfit = sanitizeOutfit(payload.outfit)
        if not sex or not name or not outfit then return false, 'Invalid clothing preset.' end
        local encoded = json.encode(outfit)
        if #encoded > 16000 then return false, 'Outfit data is too large.' end
        local presetId = tonumber(payload.presetId)
        local existing = presetId and MySQL.single.await('SELECT id FROM cm_ems_outfit_presets WHERE id = ? AND sex = ? LIMIT 1', { presetId, sex })
        if presetId and not existing then return false, 'That clothing preset no longer exists.' end
        local duplicate = MySQL.single.await('SELECT id FROM cm_ems_outfit_presets WHERE sex = ? AND LOWER(name) = LOWER(?) AND id <> ? LIMIT 1', { sex, name, presetId or 0 })
        if duplicate then return false, 'Another EMS clothing preset already uses that name.' end
        if not existing then
            local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_ems_outfit_presets WHERE sex = ?', { sex })) or 0
            if count >= MAX_OUTFIT_PRESETS_PER_SEX then return false, ('EMS can have at most %d %s clothing presets.'):format(MAX_OUTFIT_PRESETS_PER_SEX, sex) end
        end
        if existing then
            MySQL.update.await('UPDATE cm_ems_outfit_presets SET name = ?, outfit = ?, updated_by = ? WHERE id = ?', { name, encoded, actorCid, presetId })
        else
            MySQL.insert.await('INSERT INTO cm_ems_outfit_presets (sex, name, outfit, created_by, updated_by) VALUES (?, ?, ?, ?, ?)', { sex, name, encoded, actorCid, actorCid })
        end
        log(actorCid, existing and 'outfit_preset_updated' or 'outfit_preset_created', { sex = sex, name = name })
        return true, ('%s clothing preset "%s" saved from your current clothing.'):format(sex == 'female' and 'Female' or 'Male', name)
    elseif action == 'delete_outfit_preset' then
        if not has(actor, 'ems.manage_outfits') then return false, 'Your rank cannot manage EMS clothing.' end
        local presetId = tonumber(payload.presetId)
        local preset = presetId and MySQL.single.await('SELECT id, sex, name FROM cm_ems_outfit_presets WHERE id = ? LIMIT 1', { presetId })
        if not preset then return false, 'That clothing preset no longer exists.' end
        MySQL.update.await('DELETE FROM cm_ems_outfit_presets WHERE id = ?', { presetId })
        log(actorCid, 'outfit_preset_deleted', { sex = preset.sex, name = preset.name })
        return true, ('Deleted "%s".'):format(preset.name)
    elseif action == 'choose_outfit' then
        if not has(actor, 'ems.use_wardrobe') then return false, 'Your rank cannot use the EMS wardrobe.' end
        if not nearClothingNpc(src) then return false, 'You must be at the EMS wardrobe to change your duty outfit.' end
        local sex = payload.sex == 'female' and 'female' or 'male'
        local presetId = tonumber(payload.presetId)
        local preset = presetId and MySQL.single.await('SELECT id, outfit FROM cm_ems_outfit_presets WHERE id = ? AND sex = ? LIMIT 1', { presetId, sex })
        if not preset then return false, 'That EMS clothing preset is unavailable.' end
        MySQL.insert.await('INSERT INTO cm_ems_member_outfit (character_id, preset_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE preset_id = VALUES(preset_id)', { actorCid, presetId })
        MySQL.update.await('DELETE FROM cm_ems_favorite_outfit_selection WHERE character_id = ?', { actorCid })
        log(actorCid, 'outfit_chosen', { presetId = presetId })
        local outfit = dbBoolean(actor.on_duty) and decode(preset.outfit) or nil
        return true, 'EMS clothing updated.', { outfit = outfit }
    elseif action == 'save_favorite_outfit' then
        if not has(actor, 'ems.use_wardrobe') then return false, 'Your rank cannot use the EMS wardrobe.' end
        local slot = math.floor(tonumber(payload.slot) or 0)
        local outfitSex = payload.sex == 'female' and 'female' or payload.sex == 'male' and 'male' or nil
        local outfit = sanitizeOutfit(payload.outfit)
        local name = cleanPresetName(payload.name or ('Favorite %d'):format(slot))
        if slot < 1 or slot > MAX_FAVORITE_OUTFIT_SLOTS or not outfitSex or not outfit or not name then
            return false, 'Invalid favorite outfit slot.'
        end
        local encoded = json.encode(outfit)
        if #encoded > 16000 then return false, 'Favorite outfit data is too large.' end
        MySQL.insert.await([[INSERT INTO cm_ems_favorite_outfits (character_id, slot, sex, name, outfit)
            VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE sex = VALUES(sex), name = VALUES(name),
            outfit = VALUES(outfit), updated_at = CURRENT_TIMESTAMP]], { actorCid, slot, outfitSex, name, encoded })
        log(actorCid, 'favorite_outfit_saved', { slot = slot, sex = outfitSex })
        return true, ('Favorite outfit %d saved.'):format(slot)
    elseif action == 'wear_favorite_outfit' then
        if not has(actor, 'ems.use_wardrobe') then return false, 'Your rank cannot use the EMS wardrobe.' end
        if not nearClothingNpc(src) then return false, 'You must be at the EMS wardrobe to change your duty outfit.' end
        local slot = math.floor(tonumber(payload.slot) or 0)
        local outfitSex = payload.sex == 'female' and 'female' or 'male'
        local favorite = slot >= 1 and slot <= MAX_FAVORITE_OUTFIT_SLOTS and MySQL.single.await(
            'SELECT outfit FROM cm_ems_favorite_outfits WHERE character_id = ? AND slot = ? AND sex = ? LIMIT 1',
            { actorCid, slot, outfitSex }) or nil
        if not favorite then return false, 'That favorite outfit slot is empty or for another body type.' end
        MySQL.insert.await([[INSERT INTO cm_ems_favorite_outfit_selection (character_id, slot) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE slot = VALUES(slot), updated_at = CURRENT_TIMESTAMP]], { actorCid, slot })
        return true, ('Favorite outfit %d equipped.'):format(slot), { outfit = decode(favorite.outfit) }
    elseif action == 'delete_favorite_outfit' then
        if not has(actor, 'ems.use_wardrobe') then return false, 'Your rank cannot use the EMS wardrobe.' end
        local slot = math.floor(tonumber(payload.slot) or 0)
        if slot < 1 or slot > MAX_FAVORITE_OUTFIT_SLOTS then return false, 'Invalid favorite outfit slot.' end
        MySQL.update.await('DELETE FROM cm_ems_favorite_outfits WHERE character_id = ? AND slot = ?', { actorCid, slot })
        MySQL.update.await('DELETE FROM cm_ems_favorite_outfit_selection WHERE character_id = ? AND slot = ?', { actorCid, slot })
        log(actorCid, 'favorite_outfit_deleted', { slot = slot })
        return true, ('Favorite outfit %d cleared.'):format(slot)
    elseif action == 'set_meeting' then
        if not has(actor, 'ems.set_meeting') then return false, 'Your rank cannot set EMS meeting points.' end
        local now = GetGameTimer()
        if now < (meetingCooldowns[src] or 0) then return false, 'Please wait before setting another meeting point.' end
        local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
        if not x or not y or not z or math.abs(x) > 10000.0 or math.abs(y) > 10000.0 or math.abs(z) > 2500.0 then
            return false, 'Invalid meeting point.'
        end
        local ped = GetPlayerPed(src)
        if ped and ped > 0 then
            local serverCoords = GetEntityCoords(ped)
            if serverCoords and #(serverCoords - vector3(x, y, z)) > 25.0 then return false, 'Meeting point location mismatch.' end
        end
        meetingCooldowns[src] = now + 10000
        local recipients = 0
        local setterName = nameFor(actorCid)
        for _, player in ipairs(GetPlayers()) do
            local memberCid = cid(player)
            if memberCid and memberFor(memberCid) then
                TriggerClientEvent('cm-ems:client:setMeetingPoint', tonumber(player), { x = x, y = y, z = z, setterName = setterName })
                recipients = recipients + 1
            end
        end
        log(actorCid, 'meeting_point_set', { recipients = recipients })
        return true, ('Meeting point sent to %d online EMS members.'):format(recipients)
    elseif action == 'set_daily_mission_npc' then
        return SetDailyMissionNpcLocation(src, actor, payload)
    elseif action == 'set_clothing_npc' then
        return SetClothingNpcLocation(src, actor, payload)
    elseif action == 'save_rank' then
        if not has(actor, 'ems.manage_ranks') then return false, 'Your rank cannot manage ranks.' end
        if rankMutationBusy then return false, 'Another rank update is in progress.' end
        local rankId = tonumber(payload.rankId)
        local name = cleanRankName(payload.name)
        local tier = math.floor(tonumber(payload.tier) or 0)
        if not name then return false, 'Rank name must be between 3 and 32 characters.' end
        if tier < 1 or tier >= tonumber(actor.tier) or tier >= 100 then return false, 'Rank tier must be below your own tier and between 1 and 99.' end
        local existing
        if rankId then
            existing = MySQL.single.await('SELECT id, name, tier, is_leader, permissions FROM cm_ems_ranks WHERE id = ? LIMIT 1', { rankId })
            if not existing then return false, 'Rank not found.' end
            if dbBoolean(existing.is_leader) then return false, 'The EMS leader rank is protected.' end
            if tonumber(existing.tier) >= tonumber(actor.tier) then return false, 'You cannot edit a rank at or above your tier.' end
        else
            local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_ems_ranks')) or 0
            if count >= 15 then return false, 'EMS can have at most 15 ranks.' end
        end
        local duplicate = MySQL.single.await('SELECT id FROM cm_ems_ranks WHERE (tier = ? OR LOWER(name) = LOWER(?)) AND id <> ? LIMIT 1', { tier, name, rankId or 0 })
        if duplicate then return false, 'Another EMS rank already uses that name or tier.' end
        local permissions
        if has(actor, 'ems.manage_permissions') then
            local reason
            permissions, reason = requestedPermissions(payload.permissions, actor)
            if not permissions then return false, reason end
        elseif existing then permissions = decode(existing.permissions)
        else permissions = {} end
        rankMutationBusy = true
        local called, result = pcall(function()
            if existing then
                return MySQL.update.await('UPDATE cm_ems_ranks SET name = ?, tier = ?, permissions = ? WHERE id = ? AND is_leader = 0', { name, tier, json.encode(permissions), rankId })
            end
            return MySQL.insert.await('INSERT INTO cm_ems_ranks (name, tier, is_leader, permissions) VALUES (?, ?, 0, ?)', { name, tier, json.encode(permissions) })
        end)
        rankMutationBusy = false
        if not called or not result then return false, 'Rank update failed safely.' end
        local changedId = rankId or tonumber(result)
        if rankId then syncRankMembers(rankId) end
        log(actorCid, existing and 'rank_updated' or 'rank_created', { rankId = changedId, name = name, tier = tier, permissions = permissions })
        return true, existing and 'EMS rank updated.' or 'EMS rank created.'
    elseif action == 'delete_rank' then
        if not has(actor, 'ems.manage_ranks') then return false, 'Your rank cannot manage ranks.' end
        if rankMutationBusy then return false, 'Another rank update is in progress.' end
        local rankId = tonumber(payload.rankId)
        local rank = rankId and MySQL.single.await('SELECT id, name, tier, is_leader FROM cm_ems_ranks WHERE id = ? LIMIT 1', { rankId })
        if not rank then return false, 'Rank not found.' end
        if dbBoolean(rank.is_leader) then return false, 'The EMS leader rank cannot be deleted.' end
        if tonumber(rank.tier) >= tonumber(actor.tier) then return false, 'You cannot delete a rank at or above your tier.' end
        local members = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_ems_members WHERE rank_id = ?', { rankId })) or 0
        if members > 0 then return false, ('Move %d member(s) out of this rank before deleting it.'):format(members) end
        local remaining = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_ems_ranks WHERE is_leader = 0')) or 0
        if remaining <= 1 then return false, 'EMS must keep at least one non-leader rank.' end
        rankMutationBusy = true
        local called, deleted = pcall(function() return MySQL.update.await('DELETE FROM cm_ems_ranks WHERE id = ? AND is_leader = 0', { rankId }) end)
        rankMutationBusy = false
        if not called or tonumber(deleted) ~= 1 then return false, 'Rank deletion failed safely.' end
        log(actorCid, 'rank_deleted', { rankId = rankId, name = rank.name, tier = rank.tier })
        return true, 'EMS rank deleted.'
    elseif action == 'promote' or action == 'demote' then
        return targetChange(actorCid, tostring(payload.characterId or ''), action == 'promote' and 'up' or 'down')
    elseif action == 'kick' then
        if not has(actor, 'ems.kick') then return false, 'Your rank cannot remove members.' end
        local targetCid = tostring(payload.characterId or '')
        local target = memberFor(targetCid)
        if not target or dbBoolean(target.is_leader) or tonumber(actor.tier) <= tonumber(target.tier) then return false, 'You can only remove lower-ranked members.' end
        MySQL.update.await('DELETE FROM cm_ems_members WHERE character_id = ?', { targetCid })
        sync(targetCid)
        log(actorCid, 'member_removed', { targetCid = targetCid })
        return true, ('%s was removed from EMS.'):format(nameFor(targetCid))
    end
    return false, 'Unknown EMS action.'
end)

-- Shared by both cm-ems's own admin dashboard (via the lib.callback below,
-- used by its client NUI) and cm-admin's centralized Organizations tab (via
-- the plain export below, called server-side with no client round-trip) --
-- one leader-assignment transaction, two callers.
function doAssignLeader(src, targetCid)
    if not exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) then return false, 'Permission denied.' end
    if leaderAssignmentBusy then return false, 'Another EMS leader assignment is already running.' end
    targetCid = tostring(targetCid or '')
    if targetCid == '' or not MySQL.scalar.await('SELECT id FROM characters WHERE id = ? LIMIT 1', { targetCid }) then return false, 'Character ID does not exist.' end
    local rival = rivalMember(targetCid)
    if rival then
        local allowSameLeader = false
        pcall(function() allowSameLeader = exports[Config.AdminResource]:GetOrgPolicySetting('allowSameLeaderAcrossOrgs') == true end)
        if not (allowSameLeader and rival.isLeader) then
            return false, ('That character is already a member of %s.'):format(rival.orgLabel)
        end
    end
    local leaderRank = MySQL.single.await('SELECT id FROM cm_ems_ranks WHERE is_leader = 1 LIMIT 1')
    local chiefRank = MySQL.single.await('SELECT id FROM cm_ems_ranks WHERE is_leader = 0 ORDER BY tier DESC LIMIT 1')
    if not leaderRank or not chiefRank then return false, 'EMS rank configuration is incomplete.' end
    local org = MySQL.single.await('SELECT leader_cid FROM cm_ems_organization WHERE id = 1') or {}
    local formerLeaders = MySQL.query.await('SELECT character_id FROM cm_ems_members WHERE rank_id = ?', { leaderRank.id }) or {}
    local queries = {
        { query = 'UPDATE cm_ems_members SET rank_id = ?, on_duty = 0 WHERE rank_id = ? AND character_id <> ?', values = { chiefRank.id, leaderRank.id, targetCid } },
    }
    queries[#queries + 1] = { query = [[INSERT INTO cm_ems_members (character_id, rank_id, on_duty) VALUES (?, ?, 0) ON DUPLICATE KEY UPDATE rank_id = VALUES(rank_id), on_duty = 0]], values = { targetCid, leaderRank.id } }
    queries[#queries + 1] = { query = 'UPDATE cm_ems_organization SET leader_cid = ? WHERE id = 1', values = { targetCid } }
    leaderAssignmentBusy = true
    local called, ok = pcall(function() return MySQL.transaction.await(queries) end)
    leaderAssignmentBusy = false
    if not called or ok ~= true then return false, 'Leader assignment transaction failed safely.' end
    for _, former in ipairs(formerLeaders) do sync(tostring(former.character_id)) end
    if org.leader_cid then sync(tostring(org.leader_cid)) end
    sync(targetCid)
    log(cid(src), 'leader_assigned', { targetCid = targetCid })
    TriggerEvent('cm-admin:server:addLog', src, 'ems_leader_assigned', { category = 'ems', characterId = targetCid })
    return true, ('%s is now the EMS leader.'):format(nameFor(targetCid))
end

lib.callback.register('cm-ems:server:adminAssignLeader', doAssignLeader)
exports('AdminAssignLeader', doAssignLeader)

local function doRemoveLeader(src)
    if not exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) then return false, 'Permission denied.' end
    if leaderAssignmentBusy then return false, 'Another EMS leader change is already running.' end
    local org = MySQL.single.await('SELECT leader_cid FROM cm_ems_organization WHERE id = 1') or {}
    local leaderCid = org.leader_cid and tostring(org.leader_cid) or nil
    if not leaderCid then return false, 'EMS does not have a leader.' end

    leaderAssignmentBusy = true
    local called, ok = pcall(function()
        return MySQL.transaction.await({
            { query = 'UPDATE cm_ems_organization SET leader_cid = NULL WHERE id = 1 AND leader_cid = ?', values = { leaderCid } },
            { query = 'DELETE FROM cm_ems_members WHERE character_id = ?', values = { leaderCid } },
        })
    end)
    leaderAssignmentBusy = false
    if not called or ok ~= true then return false, 'Leader removal transaction failed safely.' end
    sync(leaderCid)
    log(cid(src), 'leader_removed', { formerLeaderCid = leaderCid })
    TriggerEvent('cm-admin:server:addLog', src, 'ems_leader_removed', { category = 'ems', characterId = leaderCid })
    return true, ('Removed %s as EMS leader.'):format(nameFor(leaderCid) or leaderCid)
end

exports('AdminRemoveLeader', doRemoveLeader)

local function isEmsAdmin(src)
    local ok, allowed = pcall(function() return exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) end)
    return ok and allowed == true
end

lib.callback.register('cm-ems:server:adminStaffAction', function(src, action, payload)
    if not isEmsAdmin(src) or not rateLimit(src, 'ems_admin_staff', 800) then return false, 'Permission denied.' end
    payload = type(payload) == 'table' and payload or {}
    action = tostring(action or '')
    local targetCid = tostring(payload.characterId or '')
    if targetCid == '' or not MySQL.scalar.await('SELECT id FROM characters WHERE id = ? LIMIT 1', { targetCid }) then
        return false, 'Character ID does not exist.'
    end
    local target = memberFor(targetCid)
    if action == 'hire' then
        if target then return false, 'That character is already an EMS member.' end
        local rival = rivalMember(targetCid)
        if rival then return false, ('That character is already a member of %s.'):format(rival.orgLabel) end
        local rankId = tonumber(payload.rankId)
        local rank = rankId and MySQL.single.await('SELECT id, name FROM cm_ems_ranks WHERE id = ? AND is_leader = 0 LIMIT 1', { rankId })
            or MySQL.single.await('SELECT id, name FROM cm_ems_ranks WHERE is_leader = 0 ORDER BY tier ASC LIMIT 1')
        if not rank then return false, 'No recruit rank is configured.' end
        MySQL.insert.await('INSERT INTO cm_ems_members (character_id, rank_id, on_duty) VALUES (?, ?, 0)', { targetCid, rank.id })
        sync(targetCid); log(cid(src), 'admin_member_hired', { targetCid = targetCid, rank = rank.name })
        TriggerEvent('cm-admin:server:addLog', src, 'ems_member_hired', { category = 'ems', characterId = targetCid, rank = rank.name })
        return true, ('%s was hired as %s.'):format(nameFor(targetCid), rank.name)
    end
    if not target then return false, 'That character is not an EMS member.' end
    if dbBoolean(target.is_leader) then return false, 'Assign a new leader before changing the current leader.' end
    if action == 'fire' then
        endDuty(sourceFor(targetCid), targetCid, 'removed')
        MySQL.update.await('DELETE FROM cm_ems_members WHERE character_id = ?', { targetCid })
        sync(targetCid); log(cid(src), 'admin_member_fired', { targetCid = targetCid })
        TriggerEvent('cm-admin:server:addLog', src, 'ems_member_fired', { category = 'ems', characterId = targetCid })
        return true, ('%s was removed from EMS.'):format(nameFor(targetCid))
    elseif action == 'suspend' then
        local minutes = math.max(5, math.min(math.floor(tonumber(payload.minutes) or 60), 43200))
        local reason = tostring(payload.reason or 'Administrative suspension'):gsub('[%c]', ' '):sub(1, 160)
        endDuty(sourceFor(targetCid), targetCid, 'suspended')
        MySQL.update.await([[UPDATE cm_ems_members SET on_duty = 0,
            suspended_until = DATE_ADD(NOW(), INTERVAL ? MINUTE), suspension_reason = ?, suspended_by = ?
            WHERE character_id = ?]], { minutes, reason, tostring(cid(src) or 'admin'), targetCid })
        sync(targetCid); log(cid(src), 'member_suspended', { targetCid = targetCid, minutes = minutes, reason = reason })
        TriggerEvent('cm-admin:server:addLog', src, 'ems_member_suspended', { category = 'ems', characterId = targetCid, minutes = minutes })
        return true, ('%s was suspended for %d minutes.'):format(nameFor(targetCid), minutes)
    elseif action == 'reinstate' then
        MySQL.update.await('UPDATE cm_ems_members SET suspended_until = NULL, suspension_reason = NULL, suspended_by = NULL WHERE character_id = ?', { targetCid })
        sync(targetCid); log(cid(src), 'member_reinstated', { targetCid = targetCid })
        TriggerEvent('cm-admin:server:addLog', src, 'ems_member_reinstated', { category = 'ems', characterId = targetCid })
        return true, ('%s was reinstated.'):format(nameFor(targetCid))
    end
    return false, 'Unknown staffing action.'
end)

lib.callback.register('cm-ems:server:adminSaveSettings', function(src, raw)
    if not isEmsAdmin(src) or not rateLimit(src, 'ems_admin_settings', 1000) then return false, 'Permission denied.' end
    raw = type(raw) == 'table' and raw or {}
    local clean = {
        treatmentPrice = math.max(0, math.min(math.floor(tonumber(raw.treatmentPrice) or 250), 100000)),
        deathRespawnPrice = math.max(0, math.min(math.floor(tonumber(raw.deathRespawnPrice) or 500), 100000)),
        medicReward = math.max(0, math.min(math.floor(tonumber(raw.medicReward) or 100), 10000)),
        aiArrivalMs = math.max(15000, math.min(math.floor(tonumber(raw.aiArrivalMs) or 120000), 600000)),
        sharedResponseRadius = math.max(10, math.min(tonumber(raw.sharedResponseRadius) or 40, 150)),
        hospitalEnabled = raw.hospitalEnabled == true,
        autoDispatchEnabled = raw.autoDispatchEnabled == true,
    }
    for key, value in pairs(clean) do setEmsSetting(key, value) end
    log(cid(src), 'operations_settings_updated', clean)
    TriggerEvent('cm-admin:server:addLog', src, 'ems_settings_updated', { category = 'ems', settings = clean })
    return true, 'EMS hospital, billing and dispatch settings were saved.', clean
end)

exports('GetSetting', emsSetting)
exports('AwardMedicReward', function(medicSrc, patientSrc, reason)
    medicSrc, patientSrc = tonumber(medicSrc), tonumber(patientSrc)
    local medicCid, patientCid = medicSrc and cid(medicSrc), patientSrc and cid(patientSrc)
    local medic = medicCid and memberFor(medicCid)
    if not medic or not dbBoolean(medic.on_duty) or not has(medic, 'ems.treat_player') or not patientCid then return false end
    local info
    pcall(function() info = exports[Config.PlayerDataResource]:GetDeathInfo(patientSrc) end)
    local deathCount = tonumber(info and info.deathCount) or 0
    local claimKey = ('patient:%s:death:%d'):format(patientCid, deathCount)
    local amount = math.max(0, math.floor(tonumber(emsSetting('medicReward')) or 0))
    if amount <= 0 then return true, 0 end
    local inserted = MySQL.update.await('INSERT IGNORE INTO cm_ems_reward_claims (claim_key, medic_cid, patient_cid, amount) VALUES (?, ?, ?, ?)',
        { claimKey, medicCid, patientCid, amount })
    if not inserted or tonumber(inserted) == 0 then return false end
    local paid = false
    pcall(function() paid = exports[Config.PlayerDataResource]:AddMoney(medicSrc, 'bank', amount, reason or 'ems_treatment_reward') == true end)
    if not paid then MySQL.update.await('DELETE FROM cm_ems_reward_claims WHERE claim_key = ?', { claimKey }); return false end
    log(medicCid, 'medic_reward_paid', { patientCid = patientCid, amount = amount })
    notify(medicSrc, ('EMS treatment reward: $%d deposited to bank.'):format(amount), 'success')
    return true, amount
end)

local function medicineSaleActions()
    local actions = {}
    for _, entry in ipairs((Config.MedicineSales or {}).catalog or {}) do
        actions[#actions + 1] = 'ems_sell_' .. tostring(entry.item)
    end
    return actions
end

local function registerGMenu()
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return end
    for _, action in ipairs({ 'ems_invite', 'ems_promote', 'ems_demote', 'ems_kick' }) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', { id = action, event = 'cm-ems:server:gMenuAction', resource = RESOURCE, allowDeadTarget = false })
    end
    for _, action in ipairs({ 'ems_stretcher_place', 'ems_stretcher_remove', 'ems_ambulance_load', 'ems_safe_treatment' }) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', {
            id = action, event = 'cm-ems:server:stretcherAction', resource = RESOURCE,
            allowDeadTarget = true, deadOnly = true,
        })
    end
    for _, action in ipairs(medicineSaleActions()) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', {
            id = action, event = 'cm-ems:server:medicineSaleAction', resource = RESOURCE, allowDeadTarget = false,
        })
    end
end

AddEventHandler('cm-ems:server:gMenuAction', function(src, targetSrc, action, _, context)
    if not ready or not rateLimit(src, 'gmenu', 900) then return end
    local actorCid = context and context.sourceCharacterId and tostring(context.sourceCharacterId) or cid(src)
    local targetCid = context and context.targetCharacterId and tostring(context.targetCharacterId) or cid(targetSrc)
    local actor = actorCid and memberFor(actorCid)
    if not actor or not targetCid or actorCid == targetCid then return end
    if action == 'ems_invite' then
        if not has(actor, 'ems.invite') then return notify(src, 'Your rank cannot invite EMS members.', 'error') end
        if memberFor(targetCid) then return notify(src, 'That character is already in EMS.', 'error') end
        MySQL.insert.await([[INSERT INTO cm_ems_invites (character_id, invited_by, expires_at) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND)) ON DUPLICATE KEY UPDATE invited_by = VALUES(invited_by), expires_at = VALUES(expires_at)]], { targetCid, actorCid, Config.InviteSeconds })
        TriggerClientEvent('cm-ems:client:invite', targetSrc, { inviter = nameFor(actorCid), expires = Config.InviteSeconds })
        log(actorCid, 'invite_sent', { targetCid = targetCid })
        return notify(src, ('EMS invitation sent to %s.'):format(nameFor(targetCid)), 'success')
    end
    local ok, message
    if action == 'ems_promote' then ok, message = targetChange(actorCid, targetCid, 'up')
    elseif action == 'ems_demote' then ok, message = targetChange(actorCid, targetCid, 'down')
    elseif action == 'ems_kick' then
        if not has(actor, 'ems.kick') then ok, message = false, 'Your rank cannot remove members.'
        else
            local target = memberFor(targetCid)
            if not target or dbBoolean(target.is_leader) or tonumber(actor.tier) <= tonumber(target.tier) then ok, message = false, 'You can only remove lower-ranked members.'
            else MySQL.update.await('DELETE FROM cm_ems_members WHERE character_id = ?', { targetCid }); sync(targetCid); log(actorCid, 'member_removed', { targetCid = targetCid }); ok, message = true, ('%s was removed from EMS.'):format(nameFor(targetCid)) end
        end
    end
    notify(src, message or 'EMS action failed.', ok and 'success' or 'error')
end)

lib.callback.register('cm-ems:server:respondInvite', function(src, accept)
    local characterId = cid(src)
    if not characterId then return false, 'Character is not loaded.' end
    local invite = MySQL.single.await('SELECT invited_by FROM cm_ems_invites WHERE character_id = ? AND expires_at > NOW() LIMIT 1', { characterId })
    if not invite then return false, 'This EMS invitation expired.' end
    if not accept then MySQL.update.await('DELETE FROM cm_ems_invites WHERE character_id = ?', { characterId }); return true, 'EMS invitation declined.' end
    local rival = rivalMember(characterId)
    if rival then return false, ('You are already a member of %s. Leave that organization before joining EMS.'):format(rival.orgLabel) end
    local recruit = MySQL.single.await('SELECT id FROM cm_ems_ranks WHERE is_leader = 0 ORDER BY tier ASC LIMIT 1')
    local ok = MySQL.transaction.await({
        { query = 'INSERT INTO cm_ems_members (character_id, rank_id) VALUES (?, ?)', values = { characterId, recruit.id } },
        { query = 'DELETE FROM cm_ems_invites WHERE character_id = ?', values = { characterId } },
    })
    if not ok then return false, 'Could not join EMS.' end
    sync(characterId)
    log(characterId, 'invite_accepted', { invitedBy = invite.invited_by })
    return true, 'You joined EMS as a Recruit.'
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    CreateThread(function() Wait(500); local characterId = cid(src); if characterId and ready then sync(characterId) end end)
end)
AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    local characterId = cid(src)
    if characterId then endDuty(src, characterId, 'character_unloaded') end
    if GetPlayerName(src) then
        Player(src).state:set('cmEms', false, true)
        if GetResourceState('cm-chat') == 'started' then
            TriggerEvent('cm-chat:server:refreshPlayerChannels', src)
        end
    end
end)
AddEventHandler('cm-playerdata:server:deathStateChanged', function(src, isDead)
    if isDead ~= true then return end
    local characterId = cid(src)
    if endDuty(src, characterId, 'incapacitated') and GetPlayerName(src) then
        TriggerClientEvent('cm-playerdata:client:interactionNotify', src,
            'You became incapacitated and were taken off EMS duty. Active EMS tasks were cleared.', 'error')
    end
end)
AddEventHandler('playerDropped', function()
    local src = source
    local characterId = cid(src)
    if characterId then endDuty(src, characterId, 'disconnected') end
    useLocks[src] = nil
    meetingCooldowns[src] = nil
end)

AddEventHandler('cm-ems:dev:openAdmin', function(src)
    if exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) then TriggerClientEvent('cm-ems:client:open', src, true) end
end)

CreateThread(function()
    setupDatabase()
    Wait(300)
    registerGMenu()
    while GetResourceState(Config.AdminResource) ~= 'started' do Wait(2000) end
    exports[Config.AdminResource]:RegisterDevTool({
        id = 'ems', label = 'EMS Administration', category = 'Organizations', icon = 'briefcase-medical', permission = Config.AdminPermission,
        actions = {{ id = 'open', label = 'Open EMS Administration', type = 'launcher', realm = 'server', event = 'cm-ems:dev:openAdmin', hint = 'Assign the EMS leader and inspect the organization.' }},
    })
    pcall(function()
        exports[Config.AdminResource]:RegisterOrganization({
            id = Config.OrganizationId, label = 'Emergency Medical Services',
            resource = GetCurrentResourceName(), icon = 'briefcase-medical', canRemoveLeader = true,
        })
    end)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == Config.PlayerDataResource then Wait(500); registerGMenu() end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    local actions = { 'ems_invite', 'ems_promote', 'ems_demote', 'ems_kick', 'ems_stretcher_place', 'ems_stretcher_remove', 'ems_ambulance_load', 'ems_safe_treatment', 'ems_hospital_admit' }
    for _, action in ipairs(medicineSaleActions()) do actions[#actions + 1] = action end
    for _, action in ipairs(actions) do TriggerEvent('cm-playerdata:server:unregisterInteractionAction', action) end
end)

exports('GetMember', function(characterId) return stateFor(tostring(characterId)) end)
exports('HasPermission', function(characterId, permission) local member = memberFor(tostring(characterId)); return has(member, tostring(permission)) end)
exports('IsOnDuty', function(characterId) local member = memberFor(tostring(characterId)); return member and dbBoolean(member.on_duty) or false end)
-- For cm-admin's centralized Organizations tab (CMOrganizations.forAdminPayload).
exports('GetOrganizationSummary', function()
    local org = MySQL.single.await('SELECT leader_cid FROM cm_ems_organization WHERE id = 1') or {}
    local memberCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_ems_members')) or 0
    local onDutyCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_ems_members WHERE on_duty = 1')) or 0
    return {
        leaderCid = org.leader_cid and tostring(org.leader_cid) or nil,
        leaderName = org.leader_cid and nameFor(org.leader_cid) or nil,
        memberCount = memberCount, onDutyCount = onDutyCount,
    }
end)
exports('GetVehicleAccessDecision', function(characterId, vehicleId, action)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'not_ems_vehicle' end
    if not MySQL.scalar.await('SELECT vehicle_id FROM cm_ems_fleet_vehicles WHERE vehicle_id = ? AND enabled = 1 LIMIT 1', { vehicleId }) then return false, 'not_ems_vehicle' end
    local member = characterId and memberFor(tostring(characterId))
    if not member then return false, 'not_ems_member' end
    action = tostring(action or 'vehicle.drive')
    if action == 'vehicle.sell' or action == 'vehicle.delete' or action == 'vehicle.keys.manage' or action == 'vehicle.family.share' then return false, 'ems_fleet_protected' end
    if not dbBoolean(member.on_duty) then return false, 'ems_not_on_duty' end
    local required = tonumber(MySQL.scalar.await('SELECT min_tier FROM cm_ems_fleet_vehicles WHERE vehicle_id = ? LIMIT 1', { vehicleId })) or 0
    if not dbBoolean(member.is_leader) and (tonumber(member.tier) or 0) < required then return false, 'ems_rank_too_low' end
    return true, 'ems_fleet', { organization = 'ems', vehicleId = vehicleId, requiredTier = required }
end)
