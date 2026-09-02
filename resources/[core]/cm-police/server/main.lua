local RESOURCE = GetCurrentResourceName()
local ready = false
local useLocks = {}
local leaderAssignmentBusy = false
local rankMutationBusy = false
local meetingCooldowns = {}
local inviteCooldowns = {}
local MAX_OUTFIT_PRESETS_PER_SEX = 12

-- Not `local`: shared with server/vehicles.lua (both files share this
-- resource's server Lua state; same cross-file-helper convention cm-ems
-- already uses).
function cid(src)
    local ok, value = pcall(function()
        return exports[Config.PlayerDataResource]:GetCharacterId(tonumber(src))
    end)
    return ok and value and tostring(value) or nil
end

-- Global (not local): server/mdt.lua's mdtIssueFine also calls this
-- (resolving whether an offline-looked-up citizen is actually online) --
-- it was declared local here despite that cross-file call already existing,
-- which means every call to mdtIssueFine was throwing a hard Lua error
-- ("attempt to call a nil value") instead of ever completing. Same
-- cross-file-global convention as cid/memberFor/has/log/rateLimit/nameFor.
function sourceFor(characterId)
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

function dbBoolean(value)
    return value == true or tonumber(value) == 1
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
            -- GetPedPropTextureIndex returns -1 for an empty prop slot, same
            -- as drawable's own "nothing worn" sentinel -- texture's bound
            -- must allow -1 too, or an empty slot (a real, non-nil -1, not
            -- absent data) fails this check and gets dropped from the table
            -- entirely instead of kept as an explicit "clear this slot"
            -- instruction, which is exactly what silently left a duty hat
            -- on after reverting to civilian clothes.
            local texture = math.floor(tonumber(value.texture) or -1)
            if drawable >= -1 and drawable <= 1000 and texture >= -1 and texture <= 1000 then
                clean.props[tostring(index)] = { drawable = drawable, texture = texture }
            end
        end
    end
    if next(clean.components) == nil and next(clean.props) == nil then return nil end
    return clean
end

local function cleanPresetName(value)
    local name = tostring(value or ''):gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if #name < 2 or #name > 32 then return nil end
    return name
end

local function presetRows(outfitSex)
    local rows = MySQL.query.await('SELECT id, name, updated_at FROM cm_police_outfit_presets WHERE sex = ? ORDER BY name ASC', { outfitSex }) or {}
    for _, row in ipairs(rows) do
        row.id = tonumber(row.id)
        row.updatedAt = tostring(row.updated_at or '')
        row.updated_at = nil
    end
    return rows
end

-- Resolves what a member should be wearing for duty: their own chosen preset
-- (if it still exists and matches their current sex), else the oldest
-- available preset for that sex, else nil (no wardrobe configured yet).
local function resolveMemberOutfit(characterId, outfitSex)
    local favorite = MySQL.single.await('SELECT outfit FROM cm_police_active_favorite_outfit WHERE character_id = ? LIMIT 1', { characterId })
    if favorite and favorite.outfit then
        local decoded = decode(favorite.outfit)
        if type(decoded) == 'table' then return decoded end
    end
    local chosen = MySQL.single.await('SELECT preset_id FROM cm_police_member_outfit WHERE character_id = ? LIMIT 1', { characterId })
    local presetId = chosen and tonumber(chosen.preset_id) or nil
    local row
    if presetId then
        row = MySQL.single.await('SELECT id, outfit FROM cm_police_outfit_presets WHERE id = ? AND sex = ? LIMIT 1', { presetId, outfitSex })
    end
    if not row then
        row = MySQL.single.await('SELECT id, outfit FROM cm_police_outfit_presets WHERE sex = ? ORDER BY id ASC LIMIT 1', { outfitSex })
    end
    if not row then return nil, nil end
    return decode(row.outfit), tonumber(row.id)
end

-- Forward declaration: PoliceBeginDutyWithOutfit is defined before the
-- state synchronization implementation but executes after initialization.
-- Without this declaration Lua resolves `sync` as a global at compile time.
local sync

-- Wardrobe-owned duty entry point. The outfit passed here has already been
-- loaded from a Police preset/favorite by server/wardrobe.lua; clients cannot
-- use this function or supply an arbitrary outfit to start a shift.
function PoliceBeginDutyWithOutfit(characterId, outfit, detail)
    local member = characterId and memberFor(characterId)
    if not member then return false, 'You are not a Police member.' end
    if dbBoolean(member.is_suspended) then
        return false, ('You are suspended until %s.'):format(tostring(member.suspended_until or 'further notice'))
    end

    local clean = sanitizeOutfit(outfit)
    local components = clean and clean.components or {}
    local missing = {}
    if not components['11'] then missing[#missing + 1] = 'outerwear' end
    if not components['4'] then missing[#missing + 1] = 'pants' end
    if not components['6'] then missing[#missing + 1] = 'shoes' end
    if #missing > 0 then
        return false, ('This outfit cannot start duty. Add %s.'):format(table.concat(missing, ', '))
    end

    if not dbBoolean(member.on_duty) then
        local changed = MySQL.update.await('UPDATE cm_police_members SET on_duty = 1 WHERE character_id = ? AND on_duty = 0', { characterId })
        if not changed or changed < 1 then return false, 'Could not start duty. Please try again.' end
        sync(characterId)
        log(characterId, 'duty_started', detail or { source = 'wardrobe' })
    end
    return true, dbBoolean(member.on_duty) and 'Police clothing applied.' or 'Police clothing applied. You are now on duty.', clean
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
    if not PoliceDatabaseReady() then return nil end
    return MySQL.single.await([[
        SELECT m.character_id, m.rank_id, m.on_duty, r.name AS rank_name,
               r.tier, r.is_leader, r.permissions, m.suspended_until, m.suspension_reason,
               (m.suspended_until IS NOT NULL AND m.suspended_until > NOW()) AS is_suspended,
               m.fto_signed_off
        FROM cm_police_members m JOIN cm_police_ranks r ON r.id = m.rank_id
        WHERE m.character_id = ? LIMIT 1
    ]], { tostring(characterId) })
end

function has(member, permission)
    return member and (dbBoolean(member.is_leader) or permissionMap(member)[permission] == true)
end

-- FTO/cadet mode: a brand-new Cadet (Config.Fto.RestrictedTier) is blocked
-- from the higher-stakes tools (fines/booking/impound) until a Captain+
-- signs them off. Every caller of this already has a `member` row from
-- memberFor(), which now includes fto_signed_off.
function isFtoRestricted(member)
    return member ~= nil and tonumber(member.tier) == (Config.Fto.RestrictedTier or 1) and not dbBoolean(member.fto_signed_off)
end

-- Officer radio status (10-8 Available / 10-6 Busy) -- session-only,
-- in-memory, same transience class as server/cuffs.lua's Cuffed table or
-- server/spikes.lua's ActiveStrips (not worth persisting across a
-- restart). Cleared when duty ends, see the toggle_duty action below.
local OfficerRadioStatus = {} -- [characterId] = '10-8' | '10-6'
function radioStatusFor(characterId)
    return OfficerRadioStatus[tostring(characterId)] or '10-8'
end

local function stateFor(characterId)
    local member = memberFor(characterId)
    if not member then return false end
    return {
        organizationId = 1,
        characterId = tostring(characterId),
        name = 'Police Department',
        rankId = tonumber(member.rank_id),
        rankName = member.rank_name,
        tier = tonumber(member.tier) or 0,
        isLeader = dbBoolean(member.is_leader),
        onDuty = dbBoolean(member.on_duty),
        suspended = dbBoolean(member.is_suspended),
        suspendedUntil = member.suspended_until and tostring(member.suspended_until) or nil,
        suspensionReason = member.suspension_reason,
        permissions = permissionMap(member),
        radioStatus = radioStatusFor(characterId),
    }
end

sync = function(characterId)
    local src = sourceFor(characterId)
    if not src then return end
    local state = stateFor(characterId)
    Player(src).state:set('cmPolice', state, true)
    if GetResourceState('cm-chat') == 'started' then
        TriggerEvent('cm-chat:server:refreshPlayerChannels', src)
    end
    -- Registers/clears this player's organization tag with cm-playerdata's
    -- own name-privacy system (Config.Interactions.PrivacyMode, config.lua)
    -- -- two players who share an org tag see each other's real name
    -- instead of "Stranger" (server/main.lua's BuildIdentityForViewer ->
    -- GetOrgTag). Without this call, Police members show up as complete
    -- strangers to one another even while on duty together. Covers every
    -- membership change (hire/kick/promote/demote/duty toggle/sign-off/
    -- initial character load) since every one of those already calls
    -- this one function.
    pcall(function()
        if state then
            exports[Config.PlayerDataResource]:SetOrganization(src, Config.OrganizationId, 'Police Department')
        else
            exports[Config.PlayerDataResource]:SetOrganization(src, nil, nil)
        end
    end)
end

function log(characterId, action, detail)
    MySQL.insert.await('INSERT INTO cm_police_activity (actor_cid, action, detail) VALUES (?, ?, ?)', {
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

local function invitePlayersNearby(actorSrc, targetSrc)
    actorSrc, targetSrc = tonumber(actorSrc), tonumber(targetSrc)
    if not actorSrc or not targetSrc or actorSrc == targetSrc or not GetPlayerName(actorSrc) or not GetPlayerName(targetSrc) then return false end
    if GetPlayerRoutingBucket(actorSrc) ~= GetPlayerRoutingBucket(targetSrc) then return false end
    local actorPed, targetPed = GetPlayerPed(actorSrc), GetPlayerPed(targetSrc)
    if actorPed <= 0 or targetPed <= 0 then return false end
    return #(GetEntityCoords(actorPed) - GetEntityCoords(targetPed)) <= 4.0
end

local function inviteThrottled(actorCid, targetCid)
    local key, now = ('%s:%s'):format(actorCid, targetCid), GetGameTimer()
    if inviteCooldowns[key] and now - inviteCooldowns[key] < 10000 then return true end
    inviteCooldowns[key] = now
    return false
end

local function setupDatabase()
    local statements = {
        [[CREATE TABLE IF NOT EXISTS cm_police_organization (id TINYINT UNSIGNED NOT NULL DEFAULT 1, name VARCHAR(64) NOT NULL DEFAULT 'Police Department', leader_cid VARCHAR(64) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_police_ranks (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, name VARCHAR(48) NOT NULL, tier SMALLINT UNSIGNED NOT NULL, is_leader TINYINT(1) NOT NULL DEFAULT 0, permissions LONGTEXT NOT NULL, PRIMARY KEY (id), UNIQUE KEY uniq_cm_police_rank_tier (tier)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_police_members (character_id VARCHAR(64) NOT NULL, rank_id BIGINT UNSIGNED NOT NULL, on_duty TINYINT(1) NOT NULL DEFAULT 0, suspended_until DATETIME NULL, suspension_reason VARCHAR(160) NULL, suspended_by VARCHAR(64) NULL, joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (character_id), KEY idx_cm_police_member_rank (rank_id), CONSTRAINT fk_cm_police_member_rank FOREIGN KEY (rank_id) REFERENCES cm_police_ranks(id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        -- expires_at needs an explicit DEFAULT for the same reason
        -- cm_police_bookings.release_at does (see server/booking.lua) --
        -- MySQL 8's explicit_defaults_for_timestamp rejects a NOT NULL
        -- TIMESTAMP column with no DEFAULT clause, even though the
        -- application always supplies a real value on INSERT.
        [[CREATE TABLE IF NOT EXISTS cm_police_invites (character_id VARCHAR(64) NOT NULL, invited_by VARCHAR(64) NOT NULL, expires_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (character_id), KEY idx_cm_police_invite_expiry (expires_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_police_outfit_presets (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, sex ENUM('male','female') NOT NULL, name VARCHAR(32) NOT NULL, outfit LONGTEXT NOT NULL, created_by VARCHAR(64) NULL, updated_by VARCHAR(64) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (id), UNIQUE KEY uniq_cm_police_outfit_preset (sex, name)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        -- What each Police member currently has picked from the wardrobe.
        -- Not a persistent inventory item: this only ever drives the on-duty
        -- appearance swap in client/main.lua, and is reverted to the member's
        -- own civilian clothes the moment they go off duty.
        [[CREATE TABLE IF NOT EXISTS cm_police_member_outfit (character_id VARCHAR(64) NOT NULL, preset_id BIGINT UNSIGNED NULL, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (character_id), CONSTRAINT fk_cm_police_member_outfit_preset FOREIGN KEY (preset_id) REFERENCES cm_police_outfit_presets(id) ON DELETE SET NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        -- What a member was wearing the moment they went ON duty, so going
        -- OFF duty can restore it even if the client's own in-memory copy
        -- was lost to a resource restart or reconnect mid-shift. Deleted the
        -- moment duty ends -- this is a one-shift snapshot, not a wardrobe.
        [[CREATE TABLE IF NOT EXISTS cm_police_duty_snapshot (character_id VARCHAR(64) NOT NULL, outfit LONGTEXT NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (character_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS cm_police_activity (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, actor_cid VARCHAR(64) NULL, action VARCHAR(64) NOT NULL, detail LONGTEXT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (id), KEY idx_cm_police_activity_created (created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        -- Model, appearance and image come live from rn-vehicleshop's catalog
        -- (GetPoliceCatalog export) -- this table only owns what's
        -- Police-specific: where a vehicle spawns, whether it's a car or
        -- helicopter (for cm-vehicles' trusted-placement path), the minimum
        -- rank tier required to spawn it, and whether it's currently enabled.
        [[CREATE TABLE IF NOT EXISTS cm_police_fleet_vehicles (model VARCHAR(64) NOT NULL, vehicle_id BIGINT UNSIGNED NULL, kind ENUM('car','helicopter') NOT NULL DEFAULT 'car', min_tier SMALLINT UNSIGNED NOT NULL DEFAULT 0, enabled TINYINT(1) NOT NULL DEFAULT 1, location_configured TINYINT(1) NOT NULL DEFAULT 1, spawn_x FLOAT NOT NULL, spawn_y FLOAT NOT NULL, spawn_z FLOAT NOT NULL, spawn_h FLOAT NOT NULL DEFAULT 0, updated_by VARCHAR(64) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (model), UNIQUE KEY uniq_cm_police_fleet_vehicle_id (vehicle_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        -- Reserved for future rank/permission migrations as new features are
        -- added (same convention cm-ems uses) -- empty on a fresh install.
        [[CREATE TABLE IF NOT EXISTS cm_police_migrations (migration_key VARCHAR(64) NOT NULL, applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (migration_key)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    }
    for _, query in ipairs(statements) do MySQL.query.await(query) end
    -- Column add for servers upgrading from an older schema. Wrapped in
    -- pcall (same idempotent-alter pattern cm-gunstore uses) so re-running
    -- on an already-migrated install is a silent no-op.
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_organization ADD COLUMN fund_balance BIGINT NOT NULL DEFAULT 0') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_fleet_vehicles ADD COLUMN location_configured TINYINT(1) NOT NULL DEFAULT 1 AFTER enabled') end)
    -- FTO/cadet mode. Defaults to 0 (restricted) so EXISTING cadets on an
    -- already-running server don't suddenly gain unrestricted access on
    -- upgrade -- a Captain+ has to explicitly sign each of them off, same
    -- as a brand-new hire would.
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_members ADD COLUMN fto_signed_off TINYINT(1) NOT NULL DEFAULT 0') end)
    MySQL.insert.await([[INSERT INTO cm_police_organization (id, name) VALUES (1, 'Police Department') ON DUPLICATE KEY UPDATE name = VALUES(name)]])
    local existingRankCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_police_ranks')) or 0
    if existingRankCount == 0 then
        for _, rank in ipairs(Config.Ranks) do
            local permissions = rank.permissions == 'ALL' and '{}' or json.encode(rank.permissions or {})
            MySQL.insert.await('INSERT INTO cm_police_ranks (name, tier, is_leader, permissions) VALUES (?, ?, ?, ?)',
                { rank.name, rank.tier, rank.leader and 1 or 0, permissions })
        end
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.1_cuff_permission' }) then
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.cuff'] then permissions[#permissions + 1] = 'police.cuff' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.1_cuff_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.2_booking_permission' }) then
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.book'] then permissions[#permissions + 1] = 'police.book' end
                -- police.manage_booking is admin-tier, not a baseline grant
                -- (unlike police.book/police.cuff above) -- only extend it to
                -- ranks that already hold another management-tier permission,
                -- since rank names/tiers are fully admin-editable and cannot
                -- be matched by name (e.g. "Captain").
                if not seen['police.manage_booking'] and (seen['police.manage_ranks'] or seen['police.manage_vehicles']) then
                    permissions[#permissions + 1] = 'police.manage_booking'
                end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.2_booking_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.3_citation_permission' }) then
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.cite'] then permissions[#permissions + 1] = 'police.cite' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.3_citation_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.4_impound_permission' }) then
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.impound'] then permissions[#permissions + 1] = 'police.impound' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.4_impound_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.5_radar_permission' }) then
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.radar'] then permissions[#permissions + 1] = 'police.radar' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.5_radar_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.6_spike_permission' }) then
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.spike'] then permissions[#permissions + 1] = 'police.spike' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.6_spike_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.7_mdt_permission' }) then
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.mdt'] then permissions[#permissions + 1] = 'police.mdt' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.7_mdt_permission' })
    end
    -- police.manage_armory/police.manage_alpr/police.k9 were added to
    -- Config.Ranks earlier this session, but editing that file alone never
    -- reaches an already-running server's existing rank rows (only a
    -- completely empty cm_police_ranks table gets seeded from Config.Ranks
    -- at all -- see `if existingRankCount == 0` above). Every previous new
    -- permission shipped with a matching migration like this one; these
    -- three were missed when they were added, so no existing rank actually
    -- had them until now.
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.8_armory_permission' }) then
        -- Unlike the migrations above (which grant to every non-leader
        -- rank, matching Config.Ranks' own intent for those permissions),
        -- manage_armory/manage_alpr were only ever meant for Captain+ in
        -- the fresh-install config -- so this checks tier too instead of
        -- blanket-granting to every rank.
        local rows = MySQL.query.await('SELECT id, tier, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) and tonumber(rank.tier) and tonumber(rank.tier) >= 80 then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.manage_armory'] then permissions[#permissions + 1] = 'police.manage_armory' end
                if not seen['police.manage_alpr'] then permissions[#permissions + 1] = 'police.manage_alpr' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.8_armory_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.9_k9_permission' }) then
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.k9'] then permissions[#permissions + 1] = 'police.k9' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.9_k9_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.10_sign_off_cadets_permission' }) then
        -- police.sign_off_cadets is Captain+ only, same tier check as
        -- v1.8_armory_permission above.
        local rows = MySQL.query.await('SELECT id, tier, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) and tonumber(rank.tier) and tonumber(rank.tier) >= 80 then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.sign_off_cadets'] then permissions[#permissions + 1] = 'police.sign_off_cadets' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.10_sign_off_cadets_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.11_manage_impound_permission' }) then
        -- police.manage_impound is Captain+ only, same tier check as
        -- v1.8_armory_permission above.
        local rows = MySQL.query.await('SELECT id, tier, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) and tonumber(rank.tier) and tonumber(rank.tier) >= 80 then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.manage_impound'] then permissions[#permissions + 1] = 'police.manage_impound' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.11_manage_impound_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.12_barricade_permission' }) then
        -- police.barricade is granted to every rank, same tier as
        -- police.spike -- mirrors v1.9_k9_permission's unconditional grant.
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.barricade'] then permissions[#permissions + 1] = 'police.barricade' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.12_barricade_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.13_manage_barricades_permission' }) then
        -- police.manage_barricades is Captain+ only, same tier check as
        -- v1.8_armory_permission above.
        local rows = MySQL.query.await('SELECT id, tier, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) and tonumber(rank.tier) and tonumber(rank.tier) >= 80 then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.manage_barricades'] then permissions[#permissions + 1] = 'police.manage_barricades' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.13_manage_barricades_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.14_receive_dispatch_permission' }) then
        -- police.receive_dispatch is granted to every rank, same tier as
        -- police.spike -- mirrors v1.9_k9_permission's unconditional grant.
        -- Shipped with the dispatch feature but never got a migration of
        -- its own, so no already-seeded rank ever actually gained it --
        -- same bug class as v1.8-v1.13 above.
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.receive_dispatch'] then permissions[#permissions + 1] = 'police.receive_dispatch' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.14_receive_dispatch_permission' })
    end
    if not MySQL.scalar.await('SELECT migration_key FROM cm_police_migrations WHERE migration_key = ? LIMIT 1', { 'v1.15_clamp_permission' }) then
        -- police.clamp is granted to every rank, same tier as police.spike/
        -- police.barricade -- mirrors v1.9_k9_permission's unconditional grant.
        local rows = MySQL.query.await('SELECT id, is_leader, permissions FROM cm_police_ranks') or {}
        for _, rank in ipairs(rows) do
            if not dbBoolean(rank.is_leader) then
                local stored, seen, permissions = decode(rank.permissions), {}, {}
                for key, value in pairs(stored) do
                    local permission = type(key) == 'number' and tostring(value) or tostring(key)
                    local enabled = type(key) == 'number' or value == true
                    if enabled and Config.Permissions[permission] and not seen[permission] then seen[permission] = true; permissions[#permissions + 1] = permission end
                end
                if not seen['police.clamp'] then permissions[#permissions + 1] = 'police.clamp' end
                table.sort(permissions)
                MySQL.update.await('UPDATE cm_police_ranks SET permissions = ? WHERE id = ?', { json.encode(permissions), rank.id })
            end
        end
        MySQL.insert.await('INSERT INTO cm_police_migrations (migration_key) VALUES (?)', { 'v1.15_clamp_permission' })
    end
    local organizationLeader = MySQL.scalar.await('SELECT leader_cid FROM cm_police_organization WHERE id = 1 LIMIT 1')
    if organizationLeader then
        organizationLeader = tostring(organizationLeader)
        local leaderRank = MySQL.single.await('SELECT id FROM cm_police_ranks WHERE is_leader = 1 LIMIT 1')
        local chiefRank = MySQL.single.await('SELECT id FROM cm_police_ranks WHERE is_leader = 0 ORDER BY tier DESC LIMIT 1')
        if leaderRank and chiefRank then
            local reconciled = MySQL.transaction.await({
                { query = 'UPDATE cm_police_members SET rank_id = ?, on_duty = 0 WHERE rank_id = ? AND character_id <> ?', values = { chiefRank.id, leaderRank.id, organizationLeader } },
                { query = [[INSERT INTO cm_police_members (character_id, rank_id, on_duty) VALUES (?, ?, 0) ON DUPLICATE KEY UPDATE rank_id = VALUES(rank_id)]], values = { organizationLeader, leaderRank.id } },
            })
            if reconciled ~= true then error('Police leader membership reconciliation failed') end
        end
    end
    PoliceSchemaMarkReady('core')
end

local function rankRows()
    local rows = MySQL.query.await('SELECT id, name, tier, is_leader, permissions FROM cm_police_ranks ORDER BY tier DESC') or {}
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
               m.fto_signed_off,
               r.id AS rank_id, r.name AS rank_name, r.tier, r.is_leader
        FROM cm_police_members m JOIN cm_police_ranks r ON r.id = m.rank_id ORDER BY r.tier DESC, m.joined_at ASC
    ]]) or {}
    for _, row in ipairs(rows) do
        row.characterId = tostring(row.character_id)
        row.name = nameFor(row.character_id)
        row.rankName = tostring(row.rank_name or 'Police Member')
        row.rankId, row.tier = tonumber(row.rank_id), tonumber(row.tier)
        row.onDuty = dbBoolean(row.on_duty)
        row.isLeader = dbBoolean(row.is_leader)
        row.suspended = dbBoolean(row.is_suspended)
        row.suspendedUntil = row.suspended_until and tostring(row.suspended_until) or nil
        row.suspensionReason = row.suspension_reason
        row.online = sourceFor(row.character_id) ~= nil
        row.radioStatus = radioStatusFor(row.character_id)
        row.ftoSignedOff = dbBoolean(row.fto_signed_off)
        row.character_id, row.rank_id, row.rank_name, row.on_duty, row.is_leader = nil, nil, nil, nil, nil
        row.suspended_until, row.suspension_reason, row.is_suspended, row.fto_signed_off = nil, nil, nil, nil
    end
    return rows
end

local function dashboard(src, adminMode, requestedSex)
    if not ready then return nil, 'Police database is not ready.' end
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    local isAdmin = adminMode == true and exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission)
    if not member and not isAdmin then return nil, 'You are not a Police member.' end
    -- Repair a missing/stale replicated membership state whenever a valid
    -- organization member opens the dashboard.
    if member and characterId then sync(characterId) end
    local org = MySQL.single.await('SELECT leader_cid, fund_balance FROM cm_police_organization WHERE id = 1') or {}
    local outfitSex = requestedSex == 'female' and 'female' or 'male'
    local outfitPresets = presetRows(outfitSex)
    local memberSuspended = member and dbBoolean(member.is_suspended) or false
    local activeMember = member and not memberSuspended and member or nil
    local canViewLogs = isAdmin or has(activeMember, 'police.view_logs')
    local logs = {}
    if canViewLogs then
        local limit = math.max(1, math.min(tonumber(Config.LogLimit) or 100, 250))
        logs = MySQL.query.await(([=[
            SELECT a.id, a.actor_cid, a.action, a.detail, a.created_at,
                   TRIM(CONCAT(COALESCE(c.first_name, ''), ' ', COALESCE(c.last_name, ''))) AS actor_name
            FROM cm_police_activity a
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
    local dashboardSelf = member and stateFor(characterId) or nil
    if isAdmin and not dashboardSelf then
        local adminPermissions = {}
        for permission in pairs(Config.Permissions) do adminPermissions[permission] = true end
        dashboardSelf = {
            characterId = tostring(characterId or 'admin'), rankName = 'Administrator', tier = 101,
            isLeader = true, onDuty = false, suspended = false, permissions = adminPermissions,
        }
    end
    local summary = MySQL.single.await([[SELECT COUNT(*) AS member_count,
        SUM(CASE WHEN on_duty = 1 AND (suspended_until IS NULL OR suspended_until <= NOW()) THEN 1 ELSE 0 END) AS on_duty_count
        FROM cm_police_members]]) or {}
    local fleetSummary = MySQL.single.await([[
        SELECT
            SUM(CASE WHEN enabled = 1 AND location_configured = 1 THEN 1 ELSE 0 END) AS configured_count,
            SUM(CASE WHEN enabled = 1 AND location_configured = 1 AND min_tier <= ? THEN 1 ELSE 0 END) AS available_count
        FROM cm_police_fleet_vehicles
    ]], { tonumber(dashboardSelf and dashboardSelf.tier) or 0 }) or {}
    local featureCapabilities = {}
    for _, capability in ipairs({ 'citations','impound','radar','spikes','barricades','clamp','k9','alpr','armory' }) do
        featureCapabilities[capability] = type(PoliceCapabilityEnabled) ~= 'function' or PoliceCapabilityEnabled(capability)
    end

    return {
        organization = { name = 'Police Department', leaderCid = org.leader_cid and tostring(org.leader_cid) or nil, leaderName = org.leader_cid and nameFor(org.leader_cid) or 'Not assigned' },
        summary = { memberCount = tonumber(summary.member_count) or 0, onDutyCount = tonumber(summary.on_duty_count) or 0, fleetConfigured = tonumber(fleetSummary.configured_count) or 0, fleetAvailable = tonumber(fleetSummary.available_count) or 0 },
        featureCapabilities = featureCapabilities,
        self = dashboardSelf,
        -- police.view_members was declared/grantable in Ranks & Permissions
        -- but the roster used to be returned unconditionally regardless of
        -- it -- every default rank happens to already have this permission,
        -- so this changes nothing out of the box, but it makes the toggle
        -- meaningful for a custom rank an admin creates without it.
        members = (isAdmin or has(activeMember, 'police.view_members')) and roster() or {},
        ranks = rankRows(),
        outfitSex = outfitSex, outfitPresets = outfitPresets,
        permissions = Config.Permissions, adminMode = isAdmin,
        -- Same official amounts the G-menu citation flow uses (server/
        -- citations.lua) -- exposed here so the MDT tab's "Issue Fine"
        -- picker never needs a separate fetch and can't drift out of sync.
        violations = (function()
            local list = {}
            for _, violation in ipairs(Config.Citations.Violations) do
                list[#list + 1] = { id = violation.id, label = violation.label, fine = violation.fine, jailMinutes = tonumber(violation.jailMinutes) or 0 }
            end
            return list
        end)(),
        -- Same "static officer-facing list, no dedicated fetch" pattern as
        -- violations above -- lets the Use-of-Force tab's force-type picker
        -- render immediately from the dashboard payload.
        useOfForceTypes = Config.Mdt.UseOfForceTypes,
        capabilities = {
            manageRanks = isAdmin or has(activeMember, 'police.manage_ranks'),
            managePermissions = isAdmin or has(activeMember, 'police.manage_permissions'),
            manageOutfits = isAdmin or has(activeMember, 'police.manage_outfits'),
            manageVehicles = isAdmin or has(activeMember, 'police.manage_vehicles'),
            spawnVehicles = isAdmin or has(activeMember, 'police.spawn_vehicles'),
            viewMemberMap = has(activeMember, 'police.view_member_map'),
            setMeeting = has(activeMember, 'police.set_meeting'),
            suspendMembers = isAdmin or has(activeMember, 'police.suspend_members'),
            viewFund = canViewLogs,
            useMdt = isAdmin or has(activeMember, 'police.mdt'),
            receiveDispatch = isAdmin or has(activeMember, 'police.receive_dispatch'),
            -- Any real member can check out an enabled armory weapon (no
            -- special permission needed, same baseline as radio status) --
            -- manageArmory gates the separate enable/disable weapon list.
            useArmory = isAdmin or activeMember ~= nil,
            manageArmory = isAdmin or has(activeMember, 'police.manage_armory'),
            manageAlpr = isAdmin or has(activeMember, 'police.manage_alpr'),
            signOffCadets = isAdmin or has(activeMember, 'police.sign_off_cadets'),
            manageImpound = isAdmin or has(activeMember, 'police.manage_impound'),
            manageBarricades = isAdmin or has(activeMember, 'police.manage_barricades'),
        },
        canViewLogs = canViewLogs, logs = logs,
        impoundKiosk = GetImpoundKioskStatus(),
        wardrobeNpc = GetWardrobeNpcStatus(),
        fund = { balance = tonumber(org.fund_balance) or 0 },
    }
end

local function targetChange(actorCid, targetCid, direction)
    local actor, target = memberFor(actorCid), memberFor(targetCid)
    if not actor or not target then return false, 'Police member not found.' end
    if tostring(actorCid) == tostring(targetCid) then return false, 'You cannot change your own rank.' end
    if dbBoolean(target.is_leader) then return false, 'The Police leader rank is admin-managed.' end
    if tonumber(actor.tier) <= tonumber(target.tier) then return false, 'You can only manage lower ranks.' end
    local permission = direction == 'up' and 'police.promote' or 'police.demote'
    if not has(actor, permission) then return false, 'Your rank does not have permission.' end
    local op = direction == 'up' and '>' or '<'
    local order = direction == 'up' and 'ASC' or 'DESC'
    local rank = MySQL.single.await(('SELECT id, name, tier FROM cm_police_ranks WHERE is_leader = 0 AND tier %s ? AND tier < ? ORDER BY tier %s LIMIT 1'):format(op, order), { target.tier, actor.tier })
    if not rank then return false, direction == 'up' and 'No available promotion rank.' or 'No available demotion rank.' end
    MySQL.update.await('UPDATE cm_police_members SET rank_id = ? WHERE character_id = ?', { rank.id, targetCid })
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
    local rows = MySQL.query.await('SELECT character_id FROM cm_police_members WHERE rank_id = ?', { rankId }) or {}
    for _, row in ipairs(rows) do sync(tostring(row.character_id)) end
end

lib.callback.register('cm-police:server:dashboard', function(src, adminMode, requestedSex)
    return dashboard(src, adminMode == true, requestedSex)
end)

lib.callback.register('cm-police:server:diagnostics', function(src)
    local allowed = false
    pcall(function() allowed = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if not allowed then return nil end
    return BuildPoliceDiagnostics()
end)

-- Networked K9 lifecycle lives in main.lua so its callbacks are registered
-- with the same guaranteed server entry point as the rest of Police.
local policeK9Member
local PoliceK9BySource = {}
local PoliceK9Threats = {}
local PoliceK9AttackTargets = {}

local function removePoliceK9(src)
    local record = PoliceK9BySource[src]
    PoliceK9BySource[src] = nil
    PoliceK9Threats[src] = nil
    PoliceK9AttackTargets[src] = nil
    if record and record.entity and DoesEntityExist(record.entity) then DeleteEntity(record.entity) end
end

local function livePoliceK9(src)
    local member = policeK9Member(src)
    local record = PoliceK9BySource[src]
    if not member or not record or not record.entity or not DoesEntityExist(record.entity) then
        return nil, 'Deploy your K9 first.'
    end
    return record
end

local function wantedStars(targetSrc)
    local stars = 0
    pcall(function() stars = tonumber(exports['cm-playerdata']:GetWantedStars(targetSrc)) or 0 end)
    return stars
end

local function validateK9PlayerTarget(src, targetSrc, maxDistance)
    targetSrc = tonumber(targetSrc)
    local record, err = livePoliceK9(src)
    if not record then return nil, nil, err end
    if not targetSrc or targetSrc == src or not GetPlayerName(targetSrc) then return nil, nil, 'Select a valid player.' end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then return nil, nil, 'Target is not in your routing bucket.' end
    local handlerPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if not handlerPed or handlerPed == 0 or not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) then
        return nil, nil, 'Target is unavailable.'
    end
    if #(GetEntityCoords(handlerPed) - GetEntityCoords(targetPed)) > maxDistance then return nil, nil, 'Target is too far away.' end
    return record, targetPed
end

local function hasIllegalItems(items)
    for _, item in ipairs(items or {}) do
        local definition
        pcall(function() definition = exports['cm-items']:GetItem(item.item_name, true) end)
        if definition and definition.illegal == true and (tonumber(item.quantity) or 0) > 0 then return true end
    end
    return false
end

policeK9Member = function(src)
    if type(PoliceCapabilityEnabled) == 'function' and not PoliceCapabilityEnabled('k9') then return nil, cid(src) end
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) or not has(member, 'police.k9') then
        return nil, characterId
    end
    return member, characterId
end

lib.callback.register('cm-police:server:deployK9', function(src)
    if type(PoliceCapabilityEnabled)=='function' and not PoliceCapabilityEnabled('k9') then return false,'Police K9 is disabled.' end
    local member, characterId = policeK9Member(src)
    if not member then return false, 'You must be an on-duty officer with K9 permission.' end
    if PoliceK9BySource[src] and DoesEntityExist(PoliceK9BySource[src].entity) then
        return false, 'Your K9 is already deployed.', PoliceK9BySource[src].netId
    end

    local ok, message, netId = xpcall(function()
        removePoliceK9(src)
        local handlerPed = GetPlayerPed(src)
        if not handlerPed or handlerPed == 0 then return 'Your character is not ready.' end
        local coords, heading = GetEntityCoords(handlerPed), GetEntityHeading(handlerPed)
        local radians = math.rad(heading)
        local spawnX = coords.x + math.cos(radians) + math.sin(radians)
        local spawnY = coords.y + math.sin(radians) - math.cos(radians)
        local dog = CreatePed(28, GetHashKey(Config.K9.Model or 'a_c_shepherd'), spawnX, spawnY, coords.z, heading, true, true)
        if not dog or dog == 0 then return 'FiveM could not create the K9 entity.' end
        SetEntityRoutingBucket(dog, GetPlayerRoutingBucket(src))
        local createdNetId = NetworkGetNetworkIdFromEntity(dog)
        PoliceK9BySource[src] = { entity = dog, netId = createdNetId }
        Entity(dog).state:set('cmPoliceK9Handler', src, true)
        log(characterId, 'k9_deployed', {})
        return nil, createdNetId
    end, debug.traceback)

    if not ok then
        print(('[cm-police] K9 deployment error for source %s:\n%s'):format(tostring(src), tostring(message)))
        return false, 'K9 entity creation failed. Check the server console.'
    end
    if message then return false, message end
    return true, 'K9 unit deployed.', netId
end)

lib.callback.register('cm-police:server:recallK9', function(src)
    if not PoliceK9BySource[src] then return false, 'You have no K9 deployed.' end
    removePoliceK9(src)
    log(cid(src), 'k9_recalled', {})
    return true, 'K9 unit recalled.'
end)

AddEventHandler('playerDropped', function() removePoliceK9(source) end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(PoliceK9BySource) do removePoliceK9(src) end
end)

CreateThread(function()
    while true do
        Wait(5000)
        for src, record in pairs(PoliceK9BySource) do
            local member = GetPlayerName(src) and policeK9Member(src)
            local handlerPed = member and GetPlayerPed(src) or 0
            if not member or not handlerPed or handlerPed == 0 or not DoesEntityExist(record.entity) then
                removePoliceK9(src)
            elseif GetEntityRoutingBucket(record.entity) ~= GetPlayerRoutingBucket(src) then
                SetEntityRoutingBucket(record.entity, GetPlayerRoutingBucket(src))
            end
        end
    end
end)

-- Officer stats / leaderboard (Stats tab). Purely an aggregation over
-- cm_police_activity -- every arrest/citation/backup/BOLO already gets
-- logged there via the shared log(...) helper, so this needs no new
-- tracking table. Same permission tier as Activity Logs (police.view_logs)
-- since it's the same "who gets to see performance numbers" trust level.
lib.callback.register('cm-police:server:officerStats', function(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    local isAdmin = false
    pcall(function() isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if not isAdmin and not (member and has(member, 'police.view_logs')) then return {} end

    local rows = MySQL.query.await([[
        SELECT actor_cid,
            SUM(action = 'suspect_booked') AS arrests,
            SUM(action = 'citation_issued') AS citations,
            SUM(action = 'backup_requested') AS backup_calls,
            SUM(action = 'bolo_issued') AS bolos,
            SUM(action = 'dispatch_call_resolved') AS calls_completed,
            SUM(action = 'vehicle_impounded') AS impounds,
            SUM(action = 'uof_report_filed') AS use_of_force,
            SUM(action = 'panic_activated') AS panic_activations,
            ROUND(AVG(CASE WHEN action = 'dispatch_call_resolved'
                THEN CAST(JSON_UNQUOTE(JSON_EXTRACT(detail, '$.responseMs')) AS UNSIGNED) END)) AS average_response_ms
        FROM cm_police_activity
        WHERE actor_cid IS NOT NULL
        GROUP BY actor_cid
    ]]) or {}
    local list = {}
    for _, row in ipairs(rows) do
        local arrests, citations, backupCalls, bolos =
            tonumber(row.arrests) or 0, tonumber(row.citations) or 0,
            tonumber(row.backup_calls) or 0, tonumber(row.bolos) or 0
        list[#list + 1] = {
            characterId = tostring(row.actor_cid), name = nameFor(row.actor_cid),
            arrests = arrests, citations = citations, backupCalls = backupCalls, bolos = bolos,
            callsCompleted = tonumber(row.calls_completed) or 0,
            impounds = tonumber(row.impounds) or 0,
            useOfForce = tonumber(row.use_of_force) or 0,
            panicActivations = tonumber(row.panic_activations) or 0,
            averageResponseMs = tonumber(row.average_response_ms) or 0,
            total = arrests + citations + backupCalls + bolos + (tonumber(row.calls_completed) or 0),
        }
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    return list
end)

-- K9 tracking and commands. Client-selected entities are hints only; every
-- operation is revalidated against the server-owned dog, duty permission,
-- routing bucket and server entity distance before any client task is allowed.
lib.callback.register('cm-police:server:k9Track', function(src)
    if not rateLimit(src, 'k9_track', 1000) then return false, 'Please wait.' end
    local record, err = livePoliceK9(src)
    if not record then return false, err end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Unable to resolve your location.' end
    local myCoords = GetEntityCoords(ped)
    local nearestSrc, nearestCoords, nearestDist = nil, nil, Config.K9.TrackRadius or 150.0
    for _, rawSrc in ipairs(GetPlayers()) do
        local targetSrc = tonumber(rawSrc)
        if targetSrc and targetSrc ~= src and GetPlayerRoutingBucket(targetSrc) == GetPlayerRoutingBucket(src) then
            if wantedStars(targetSrc) > 0 then
                local targetPed = GetPlayerPed(targetSrc)
                if targetPed and targetPed ~= 0 then
                    local dist = #(myCoords - GetEntityCoords(targetPed))
                    if dist <= nearestDist then nearestSrc, nearestCoords, nearestDist = targetSrc, GetEntityCoords(targetPed), dist end
                end
            end
        end
    end
    if not nearestSrc then return false, 'No wanted suspects detected nearby.' end
    log(cid(src), 'k9_track_started', { targetCid = cid(nearestSrc) })
    return true, 'Scent picked up.', nearestSrc, { x = nearestCoords.x, y = nearestCoords.y, z = nearestCoords.z }
end)

lib.callback.register('cm-police:server:k9TrackUpdate', function(src, targetSrc)
    if not rateLimit(src, 'k9_track_update', 750) then return false end
    local _, targetPed, err = validateK9PlayerTarget(src, targetSrc, Config.K9.TrackRadius or 150.0)
    if not targetPed or wantedStars(tonumber(targetSrc)) < 1 then return false, err or 'The scent trail has gone cold.' end
    local coords = GetEntityCoords(targetPed)
    return true, nil, { x = coords.x, y = coords.y, z = coords.z }
end)

lib.callback.register('cm-police:server:k9CommandTarget', function(src, action, targetSrc)
    if not rateLimit(src, 'k9_command', 500) then return false, 'Please wait.' end
    action = tostring(action or '')
    if action ~= 'follow' and action ~= 'chase' and action ~= 'attack' then return false, 'Invalid K9 command.' end
    local maxDistance = action == 'attack' and (Config.K9.AttackDistance or 20.0) or (Config.K9.ChaseDistance or 75.0)
    local _, _, err = validateK9PlayerTarget(src, targetSrc, maxDistance)
    if err then return false, err end
    targetSrc = tonumber(targetSrc)
    local recentThreat = PoliceK9Threats[src] and (PoliceK9Threats[src][targetSrc] or 0) > GetGameTimer()
    if action == 'attack' and not recentThreat then
        return false, 'K9 attack denied: that player has not recently attacked you.'
    end
    if action ~= 'attack' and wantedStars(targetSrc) < 1 and not recentThreat then
        return false, 'K9 can only pursue a wanted suspect or your recent attacker.'
    end
    PoliceK9AttackTargets[src] = action == 'attack' and targetSrc or nil
    log(cid(src), 'k9_' .. action, { targetCid = cid(targetSrc) })
    return true, action == 'attack' and 'K9 attack authorized.' or ('K9 %s command accepted.'):format(action), targetSrc
end)

lib.callback.register('cm-police:server:k9StopAttack', function(src)
    local record, err = livePoliceK9(src)
    if not record then return false, err end
    PoliceK9AttackTargets[src] = nil
    log(cid(src), 'k9_attack_stopped', {})
    return true, 'K9 stopped and returned to heel.'
end)

lib.callback.register('cm-police:server:k9SearchPlayer', function(src, targetSrc)
    if not rateLimit(src, 'k9_search_player', 1500) then return false, 'Please wait.' end
    local _, _, err = validateK9PlayerTarget(src, targetSrc, Config.K9.SearchDistance or 4.0)
    if err then return false, err end
    targetSrc = tonumber(targetSrc)
    local targetState = Player(targetSrc).state
    if wantedStars(targetSrc) < 1 and not (targetState and targetState.cmCuffed == true) then
        return false, 'The player must be wanted or restrained for a K9 search.'
    end
    local inventory
    pcall(function() inventory = exports['cm-inventory']:GetInventory(targetSrc) end)
    if not inventory then return false, 'Could not inspect the player inventory.' end
    local alert = hasIllegalItems(inventory.items)
    log(cid(src), 'k9_player_search', { targetCid = cid(targetSrc), alert = alert })
    return true, alert and 'K9 alerted to a suspicious scent.' or 'K9 found no suspicious scent.', alert
end)

lib.callback.register('cm-police:server:k9SearchVehicle', function(src, netId)
    if not rateLimit(src, 'k9_search_vehicle', 1500) then return false, 'Please wait.' end
    local record, err = livePoliceK9(src)
    if not record then return false, err end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return false, 'Select a valid vehicle.' end
    if GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src) then return false, 'Vehicle is not in your routing bucket.' end
    local handlerPed = GetPlayerPed(src)
    if #(GetEntityCoords(handlerPed) - GetEntityCoords(vehicle)) > (Config.K9.SearchDistance or 4.0) then return false, 'Vehicle is too far away.' end
    local vehicleId = tonumber(Entity(vehicle).state.cmVehicleId)
    if not vehicleId then return false, 'This vehicle has no persistent vehicle identity.' end
    local rows = MySQL.query.await('SELECT item_name, quantity FROM inventory_items WHERE owner_type = ? AND owner_id = ?', {
        'vehicle_trunk', tostring(vehicleId)
    }) or {}
    local alert = hasIllegalItems(rows)
    log(cid(src), 'k9_vehicle_search', { vehicleId = vehicleId, alert = alert })
    return true, alert and 'K9 alerted to a suspicious scent.' or 'K9 found no suspicious scent.', alert
end)

AddEventHandler('weaponDamageEvent', function(sender, data)
    sender = tonumber(sender)
    local victimNetId = type(data) == 'table' and tonumber(data.hitGlobalId) or nil
    if not sender or not victimNetId then return end
    local victim = NetworkGetEntityFromNetworkId(victimNetId)
    if not victim or victim == 0 then return end
    for handlerSrc in pairs(PoliceK9BySource) do
        if sender ~= handlerSrc and victim == GetPlayerPed(handlerSrc)
                and GetPlayerRoutingBucket(sender) == GetPlayerRoutingBucket(handlerSrc) then
            PoliceK9Threats[handlerSrc] = PoliceK9Threats[handlerSrc] or {}
            PoliceK9Threats[handlerSrc][sender] = GetGameTimer() + (Config.K9.ThreatMemoryMs or 120000)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        for handlerSrc, targetSrc in pairs(PoliceK9AttackTargets) do
            local _, _, err = validateK9PlayerTarget(handlerSrc, targetSrc, Config.K9.AttackDistance or 20.0)
            local threatExpires = PoliceK9Threats[handlerSrc] and PoliceK9Threats[handlerSrc][targetSrc] or 0
            if err or threatExpires <= GetGameTimer() then
                PoliceK9AttackTargets[handlerSrc] = nil
                TriggerClientEvent('cm-police:client:k9ForceStop', handlerSrc)
            end
        end
    end
end)

-- FTO/cadet mode: a Captain+ signs a restricted Cadet off, lifting the
-- isFtoRestricted() gate on fines/booking/impound for them from then on.
-- Officer radio status (J-key quick menu, client/quickmenu.lua). Requires a
-- REAL on-duty member, since a synthetic admin actor has no on_duty field
-- to check against.
lib.callback.register('cm-police:server:setRadioStatus', function(src, status)
    local actorCid = cid(src)
    local actor = actorCid and memberFor(actorCid)
    if not actor or dbBoolean(actor.is_suspended) or not dbBoolean(actor.on_duty) then
        return false, 'You must be an on-duty officer.'
    end
    if status ~= '10-8' and status ~= '10-6' then return false, 'Invalid status.' end
    OfficerRadioStatus[tostring(actorCid)] = status
    sync(actorCid)
    return true, ('Status set to %s.'):format(status)
end)

-- Manual duty entry was removed: wearing a complete server-owned Police
-- outfit at the wardrobe is now the only way to begin a shift. Keep this
-- callback as the compatible, explicit way to end a shift.
local function endPoliceDuty(src, characterId, reason)
    src = tonumber(src)
    characterId = characterId and tostring(characterId) or (src and cid(src))
    local member = characterId and memberFor(characterId)
    if not member or not dbBoolean(member.on_duty) then return false end
    MySQL.update.await('UPDATE cm_police_members SET on_duty = 0 WHERE character_id = ?', { characterId })
    OfficerRadioStatus[tostring(characterId)] = nil
    TriggerEvent('cm-police:server:memberWentOffDuty', src, characterId, tostring(reason or 'off_duty'))
    if src and GetPlayerName(src) then
        TriggerClientEvent('cm-police:client:forceDutyCleanup', src, tostring(reason or 'off_duty'))
    end
    sync(characterId)
    log(characterId, 'duty_ended', { reason = tostring(reason or 'manual') })
    return true
end

lib.callback.register('cm-police:server:toggleDuty', function(src)
    if not rateLimit(src, 'toggle_duty', 650) then return false, 'Please wait.' end
    local actorCid = cid(src)
    if not actorCid then return false, 'Character is not loaded.' end
    local actor = memberFor(actorCid)
    if not actor then return false, 'You are not a Police member.' end
    if dbBoolean(actor.is_suspended) then return false, ('You are suspended until %s.'):format(tostring(actor.suspended_until or 'further notice')) end

    if not dbBoolean(actor.on_duty) then
        return false, 'Wear a complete Police outfit at the wardrobe to start duty.'
    end

    endPoliceDuty(src, actorCid, 'manual')
    return true, 'You are now off duty.'
end)

RegisterNetEvent('cm-police:server:endDutyOnDeath', function()
    local src = source
    if not rateLimit(src, 'death_end_duty', 2000) then return end
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or not dbBoolean(member.on_duty) then return end
    endPoliceDuty(src, characterId, 'death')
end)

-- Reconciliation callback: if a member's client (re)loads while they are
-- already flagged on_duty in the database (e.g. after a resource restart
-- mid-shift), this returns their resolved duty outfit so the client can
-- reapply it. Returns nil if they are not currently on duty.
lib.callback.register('cm-police:server:dutyOutfit', function(src, requestedSex)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or not dbBoolean(member.on_duty) then return nil end
    local outfitSex = requestedSex == 'female' and 'female' or 'male'
    local outfit = resolveMemberOutfit(characterId, outfitSex)
    return outfit
end)

-- Police-tagged wardrobe catalog (items an admin assigned to the "police"
-- job through nv_cloth's /clothingstore management panel, stored in
-- cm-items' own clothing catalog, not anything cm-police owns). Purely a
-- preset-creation aid for managers -- trying a piece on applies it directly
-- to the manager's own ped client-side, then the existing "Save current
-- clothing" flow (save_outfit_preset above) captures it exactly like any
-- other currently-worn outfit. No item/inventory involvement at any point.
lib.callback.register('cm-police:server:policeWardrobeCatalog', function(src, requestedSex)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    local isAdmin = false
    pcall(function() isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if not isAdmin and (not member or dbBoolean(member.is_suspended)) then return {} end
    local gender = requestedSex == 'female' and 'female' or 'male'
    local rows = {}
    -- /clothingstore's "assign to Police" action never populates cm-items'
    -- `job` column (a requiredJob/job naming mismatch between nv_cloth and
    -- cm-items -- traced directly, not guessed) -- the field that's
    -- actually reliable is `shop = 'org_police'`, which the export itself
    -- can filter on directly.
    -- includeDisabled = true: nv_cloth's own "publish" toggle gates whether
    -- an item is available for PURCHASE in the general/real in-game shop
    -- (confirmed against nv_cloth's own shop-catalog loader) -- this picker
    -- is already gated behind police.manage_outfits and involves no
    -- purchase at all, so requiring publish on top of that would be a
    -- pointless double gate for an internal duty tool.
    pcall(function() rows = exports['cm-items']:GetClothingCatalogRows({ gender = gender, shop = 'org_police', includeDisabled = true }) or {} end)
    local catalog = {}
    for _, row in ipairs(rows) do
        catalog[#catalog + 1] = {
            id = tonumber(row.id),
            componentType = tostring(row.componentType or 'component'),
            componentIndex = tonumber(row.componentIndex) or 0,
            drawableId = tonumber(row.drawableId) or 0,
            -- nv_cloth stores -1 as a "no specific texture" sentinel for some
            -- catalog rows; `or 0` alone doesn't catch it since -1 is a valid
            -- non-nil number. SetPedComponentVariation/SetPedPropIndex both
            -- read a negative texture id as a huge unsigned value and reject
            -- it outright, so it must be clamped up to 0 here.
            textureId = math.max(0, tonumber(row.textureId) or 0),
            label = tostring(row.label or 'Item'),
            category = tostring(row.category or 'other'),
            image = row.image,
        }
    end
    return catalog
end)

lib.callback.register('cm-police:server:action', function(src, action, payload)
    if not rateLimit(src, tostring(action), 650) then return false, 'Please wait.' end
    payload = type(payload) == 'table' and payload or {}
    local actorCid = cid(src)
    if not actorCid then return false, 'Character is not loaded.' end
    local actor = memberFor(actorCid)
    local isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true
    if not actor and isAdmin then actor = { tier = 101, is_leader = 1, permissions = '{}' } end
    if not actor then return false, 'You are not a Police member.' end
    if not isAdmin and dbBoolean(actor.is_suspended) then
        return false, 'Your Police organization access is suspended.'
    end

    if action == 'save_outfit_preset' then
        if not has(actor, 'police.manage_outfits') then return false, 'Your rank cannot manage Police clothing.' end
        local sex = payload.sex == 'female' and 'female' or payload.sex == 'male' and 'male' or nil
        local name = cleanPresetName(payload.name)
        local outfit = sanitizeOutfit(payload.outfit)
        if not sex or not name or not outfit then return false, 'Invalid clothing preset.' end
        local encoded = json.encode(outfit)
        if #encoded > 16000 then return false, 'Outfit data is too large.' end
        local presetId = tonumber(payload.presetId)
        local existing = presetId and MySQL.single.await('SELECT id FROM cm_police_outfit_presets WHERE id = ? AND sex = ? LIMIT 1', { presetId, sex })
        if presetId and not existing then return false, 'That clothing preset no longer exists.' end
        local duplicate = MySQL.single.await('SELECT id FROM cm_police_outfit_presets WHERE sex = ? AND LOWER(name) = LOWER(?) AND id <> ? LIMIT 1', { sex, name, presetId or 0 })
        if duplicate then return false, 'Another Police clothing preset already uses that name.' end
        if not existing then
            local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_police_outfit_presets WHERE sex = ?', { sex })) or 0
            if count >= MAX_OUTFIT_PRESETS_PER_SEX then return false, ('Police can have at most %d %s clothing presets.'):format(MAX_OUTFIT_PRESETS_PER_SEX, sex) end
        end
        if existing then
            MySQL.update.await('UPDATE cm_police_outfit_presets SET name = ?, outfit = ?, updated_by = ? WHERE id = ?', { name, encoded, actorCid, presetId })
        else
            MySQL.insert.await('INSERT INTO cm_police_outfit_presets (sex, name, outfit, created_by, updated_by) VALUES (?, ?, ?, ?, ?)', { sex, name, encoded, actorCid, actorCid })
        end
        log(actorCid, existing and 'outfit_preset_updated' or 'outfit_preset_created', { sex = sex, name = name })
        return true, ('%s clothing preset "%s" saved from your current clothing.'):format(sex == 'female' and 'Female' or 'Male', name)
    elseif action == 'delete_outfit_preset' then
        if not has(actor, 'police.manage_outfits') then return false, 'Your rank cannot manage Police clothing.' end
        local presetId = tonumber(payload.presetId)
        local preset = presetId and MySQL.single.await('SELECT id, sex, name FROM cm_police_outfit_presets WHERE id = ? LIMIT 1', { presetId })
        if not preset then return false, 'That clothing preset no longer exists.' end
        MySQL.update.await('DELETE FROM cm_police_outfit_presets WHERE id = ?', { presetId })
        log(actorCid, 'outfit_preset_deleted', { sex = preset.sex, name = preset.name })
        return true, ('Deleted "%s".'):format(preset.name)
    elseif action == 'set_wardrobe_npc' then
        return SetWardrobeNpcLocation(src, actor, payload)
    elseif action == 'set_meeting' then
        if not has(actor, 'police.set_meeting') then return false, 'Your rank cannot set Police meeting points.' end
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
                TriggerClientEvent('cm-police:client:setMeetingPoint', tonumber(player), { x = x, y = y, z = z, setterName = setterName })
                recipients = recipients + 1
            end
        end
        log(actorCid, 'meeting_point_set', { recipients = recipients })
        return true, ('Meeting point sent to %d online Police members.'):format(recipients)
    elseif action == 'clear_meeting' then
        -- The meeting blip used to live until the resource restarted: there
        -- was no way to take it down once the callout was over, only to
        -- overwrite it with a new one. Same permission as setting it.
        if not has(actor, 'police.set_meeting') then return false, 'Your rank cannot clear Police meeting points.' end
        local cleared = 0
        for _, player in ipairs(GetPlayers()) do
            local memberCid = cid(player)
            if memberCid and memberFor(memberCid) then
                TriggerClientEvent('cm-police:client:clearMeetingPoint', tonumber(player))
                cleared = cleared + 1
            end
        end
        log(actorCid, 'meeting_point_cleared', { recipients = cleared })
        return true, ('Meeting point cleared for %d online Police members.'):format(cleared)
    elseif action == 'set_impound_kiosk' then
        return SetImpoundKioskLocation(src, actor, payload)
    elseif action == 'reset_impound_kiosks' then
        return ResetImpoundKioskLocations(src, actor)
    elseif action == 'save_rank' then
        if not has(actor, 'police.manage_ranks') then return false, 'Your rank cannot manage ranks.' end
        if rankMutationBusy then return false, 'Another rank update is in progress.' end
        local rankId = tonumber(payload.rankId)
        local name = cleanRankName(payload.name)
        local tier = math.floor(tonumber(payload.tier) or 0)
        if not name then return false, 'Rank name must be between 3 and 32 characters.' end
        if tier < 1 or tier >= tonumber(actor.tier) or tier >= 100 then return false, 'Rank tier must be below your own tier and between 1 and 99.' end
        local existing
        if rankId then
            existing = MySQL.single.await('SELECT id, name, tier, is_leader, permissions FROM cm_police_ranks WHERE id = ? LIMIT 1', { rankId })
            if not existing then return false, 'Rank not found.' end
            if dbBoolean(existing.is_leader) then return false, 'The Police leader rank is protected.' end
            if tonumber(existing.tier) >= tonumber(actor.tier) then return false, 'You cannot edit a rank at or above your tier.' end
        else
            local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_police_ranks')) or 0
            if count >= 15 then return false, 'Police can have at most 15 ranks.' end
        end
        local duplicate = MySQL.single.await('SELECT id FROM cm_police_ranks WHERE (tier = ? OR LOWER(name) = LOWER(?)) AND id <> ? LIMIT 1', { tier, name, rankId or 0 })
        if duplicate then return false, 'Another Police rank already uses that name or tier.' end
        local permissions
        if has(actor, 'police.manage_permissions') then
            local reason
            permissions, reason = requestedPermissions(payload.permissions, actor)
            if not permissions then return false, reason end
        elseif existing then permissions = decode(existing.permissions)
        else permissions = {} end
        rankMutationBusy = true
        local called, result = pcall(function()
            if existing then
                return MySQL.update.await('UPDATE cm_police_ranks SET name = ?, tier = ?, permissions = ? WHERE id = ? AND is_leader = 0', { name, tier, json.encode(permissions), rankId })
            end
            return MySQL.insert.await('INSERT INTO cm_police_ranks (name, tier, is_leader, permissions) VALUES (?, ?, 0, ?)', { name, tier, json.encode(permissions) })
        end)
        rankMutationBusy = false
        if not called or not result then return false, 'Rank update failed safely.' end
        local changedId = rankId or tonumber(result)
        if rankId then syncRankMembers(rankId) end
        log(actorCid, existing and 'rank_updated' or 'rank_created', { rankId = changedId, name = name, tier = tier, permissions = permissions })
        return true, existing and 'Police rank updated.' or 'Police rank created.'
    elseif action == 'delete_rank' then
        if not has(actor, 'police.manage_ranks') then return false, 'Your rank cannot manage ranks.' end
        if rankMutationBusy then return false, 'Another rank update is in progress.' end
        local rankId = tonumber(payload.rankId)
        local rank = rankId and MySQL.single.await('SELECT id, name, tier, is_leader FROM cm_police_ranks WHERE id = ? LIMIT 1', { rankId })
        if not rank then return false, 'Rank not found.' end
        if dbBoolean(rank.is_leader) then return false, 'The Police leader rank cannot be deleted.' end
        if tonumber(rank.tier) >= tonumber(actor.tier) then return false, 'You cannot delete a rank at or above your tier.' end
        local members = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_police_members WHERE rank_id = ?', { rankId })) or 0
        if members > 0 then return false, ('Move %d member(s) out of this rank before deleting it.'):format(members) end
        local remaining = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_police_ranks WHERE is_leader = 0')) or 0
        if remaining <= 1 then return false, 'Police must keep at least one non-leader rank.' end
        rankMutationBusy = true
        local called, deleted = pcall(function() return MySQL.update.await('DELETE FROM cm_police_ranks WHERE id = ? AND is_leader = 0', { rankId }) end)
        rankMutationBusy = false
        if not called or tonumber(deleted) ~= 1 then return false, 'Rank deletion failed safely.' end
        log(actorCid, 'rank_deleted', { rankId = rankId, name = rank.name, tier = rank.tier })
        return true, 'Police rank deleted.'
    elseif action == 'promote' or action == 'demote' then
        return targetChange(actorCid, tostring(payload.characterId or ''), action == 'promote' and 'up' or 'down')
    elseif action == 'kick' then
        if not has(actor, 'police.kick') then return false, 'Your rank cannot remove members.' end
        local targetCid = tostring(payload.characterId or '')
        local target = memberFor(targetCid)
        if not target or dbBoolean(target.is_leader) or tonumber(actor.tier) <= tonumber(target.tier) then return false, 'You can only remove lower-ranked members.' end
        endPoliceDuty(sourceFor(targetCid), targetCid, 'removed')
        MySQL.update.await('DELETE FROM cm_police_members WHERE character_id = ?', { targetCid })
        sync(targetCid)
        log(actorCid, 'member_removed', { targetCid = targetCid })
        return true, ('%s was removed from Police.'):format(nameFor(targetCid))
    -- police.suspend_members was declared and grantable in Ranks &
    -- Permissions but had no actual action wired to it anywhere -- the only
    -- suspend/reinstate that existed was adminStaffAction, gated purely by
    -- cm-admin's separate police.admin.manage permission, so granting this
    -- permission to e.g. a Captain did nothing. This is the org-internal
    -- equivalent, same tier-check shape as promote/demote/kick above.
    elseif action == 'suspend_member' then
        if not has(actor, 'police.suspend_members') then return false, 'Your rank cannot suspend members.' end
        local targetCid = tostring(payload.characterId or '')
        local target = memberFor(targetCid)
        if not target or dbBoolean(target.is_leader) or tonumber(actor.tier) <= tonumber(target.tier) then return false, 'You can only suspend lower-ranked members.' end
        local minutes = math.max(5, math.min(math.floor(tonumber(payload.minutes) or 60), 43200))
        local reason = tostring(payload.reason or 'Suspended by Police leadership'):gsub('[%c]', ' '):sub(1, 160)
        endPoliceDuty(sourceFor(targetCid), targetCid, 'suspended')
        MySQL.update.await([[UPDATE cm_police_members SET on_duty = 0,
            suspended_until = DATE_ADD(NOW(), INTERVAL ? MINUTE), suspension_reason = ?, suspended_by = ?
            WHERE character_id = ?]], { minutes, reason, actorCid, targetCid })
        sync(targetCid)
        log(actorCid, 'member_suspended', { targetCid = targetCid, minutes = minutes, reason = reason })
        return true, ('%s was suspended for %d minutes.'):format(nameFor(targetCid), minutes)
    elseif action == 'reinstate_member' then
        if not has(actor, 'police.suspend_members') then return false, 'Your rank cannot reinstate members.' end
        local targetCid = tostring(payload.characterId or '')
        local target = memberFor(targetCid)
        if not target or dbBoolean(target.is_leader) or tonumber(actor.tier) <= tonumber(target.tier) then return false, 'You can only reinstate lower-ranked members.' end
        MySQL.update.await('UPDATE cm_police_members SET suspended_until = NULL, suspension_reason = NULL, suspended_by = NULL WHERE character_id = ?', { targetCid })
        sync(targetCid)
        log(actorCid, 'member_reinstated', { targetCid = targetCid })
        return true, ('%s was reinstated.'):format(nameFor(targetCid))
    elseif action == 'sign_off_cadet' then
        if not has(actor, 'police.sign_off_cadets') then return false, 'Your rank cannot sign off cadets.' end
        local targetCid = tostring(payload.characterId or '')
        local target = memberFor(targetCid)
        if not target then return false, 'That member does not exist.' end
        MySQL.update.await('UPDATE cm_police_members SET fto_signed_off = 1 WHERE character_id = ?', { targetCid })
        sync(targetCid)
        log(actorCid, 'cadet_signed_off', { targetCid = targetCid })
        return true, ('%s is signed off.'):format(nameFor(targetCid))
    end
    return false, 'Unknown Police action.'
end)

local function registerGMenu()
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return end
    for _, action in ipairs({ 'police_invite', 'police_promote', 'police_demote', 'police_kick' }) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', { id = action, event = 'cm-police:server:gMenuAction', resource = RESOURCE, allowDeadTarget = false })
    end
    -- Cuffing must work on a suspect an officer just knocked unconscious, so
    -- allowDeadTarget = true (unlike the org actions above). Handled in
    -- server/cuffs.lua, not here -- this file only owns registration.
    for _, action in ipairs({ 'police_cuff', 'police_uncuff', 'police_escort_grab', 'police_escort_release', 'police_put_in_vehicle' }) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', { id = action, event = 'cm-police:server:cuffAction', resource = RESOURCE, allowDeadTarget = true })
    end
    -- allowVehicleTarget = true: this action's entire purpose is acting on a
    -- suspect who IS currently seated in a vehicle -- cm-playerdata's generic
    -- "use the vehicle interaction menu instead" block would otherwise
    -- reject it unconditionally, making the action permanently unusable.
    TriggerEvent('cm-playerdata:server:registerInteractionAction', { id = 'police_take_out_vehicle', event = 'cm-police:server:cuffAction', resource = RESOURCE, allowDeadTarget = true, allowVehicleTarget = true })
    -- Booking actions, same allowDeadTarget = true reasoning as cuffing --
    -- an officer must be able to book a suspect still unconscious from the
    -- arrest. Handled in server/booking.lua.
    for _, action in ipairs(BookingActionIds()) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', { id = action, event = 'cm-police:server:bookingAction', resource = RESOURCE, allowDeadTarget = true })
    end
end

AddEventHandler('cm-police:server:gMenuAction', function(src, targetSrc, action, _, context)
    if not ready or not rateLimit(src, 'gmenu', 900) then return end
    local actorCid = context and context.sourceCharacterId and tostring(context.sourceCharacterId) or cid(src)
    local targetCid = context and context.targetCharacterId and tostring(context.targetCharacterId) or cid(targetSrc)
    local actor = actorCid and memberFor(actorCid)
    if not actor or not targetCid or actorCid == targetCid then return end
    if action == 'police_invite' then
        if not has(actor, 'police.invite') then return notify(src, 'Your rank cannot invite Police members.', 'error') end
        if dbBoolean(actor.is_suspended) then return notify(src, 'Suspended members cannot invite recruits.', 'error') end
        if cid(src) ~= actorCid or cid(targetSrc) ~= targetCid or not invitePlayersNearby(src, targetSrc) then return notify(src, 'That player is no longer nearby.', 'error') end
        if inviteThrottled(actorCid, targetCid) then return notify(src, 'Please wait before inviting that player again.', 'error') end
        if memberFor(targetCid) then return notify(src, 'That character is already in Police.', 'error') end
        local rival = rivalMember(targetCid)
        if rival then return notify(src, ('That character is already a member of %s.'):format(rival.orgLabel), 'error') end
        local recruit = MySQL.single.await('SELECT name FROM cm_police_ranks WHERE is_leader = 0 ORDER BY tier ASC LIMIT 1')
        if not recruit then return notify(src, 'Police has no entry rank configured.', 'error') end
        MySQL.insert.await([[INSERT INTO cm_police_invites (character_id, invited_by, expires_at) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND)) ON DUPLICATE KEY UPDATE invited_by = VALUES(invited_by), expires_at = VALUES(expires_at)]], { targetCid, actorCid, Config.InviteSeconds })
        TriggerClientEvent('cm-police:client:invite', targetSrc, { inviter = nameFor(actorCid), rank = recruit.name, expires = Config.InviteSeconds })
        log(actorCid, 'invite_sent', { targetCid = targetCid })
        return notify(src, ('Police invitation sent to %s.'):format(nameFor(targetCid)), 'success')
    end
    local ok, message
    if action == 'police_promote' then ok, message = targetChange(actorCid, targetCid, 'up')
    elseif action == 'police_demote' then ok, message = targetChange(actorCid, targetCid, 'down')
    elseif action == 'police_kick' then
        if not has(actor, 'police.kick') then ok, message = false, 'Your rank cannot remove members.'
        else
            local target = memberFor(targetCid)
            if not target or dbBoolean(target.is_leader) or tonumber(actor.tier) <= tonumber(target.tier) then ok, message = false, 'You can only remove lower-ranked members.'
            else MySQL.update.await('DELETE FROM cm_police_members WHERE character_id = ?', { targetCid }); sync(targetCid); log(actorCid, 'member_removed', { targetCid = targetCid }); ok, message = true, ('%s was removed from Police.'):format(nameFor(targetCid)) end
        end
    end
    notify(src, message or 'Police action failed.', ok and 'success' or 'error')
end)

lib.callback.register('cm-police:server:respondInvite', function(src, accept)
    local characterId = cid(src)
    if not characterId then return false, 'Character is not loaded.' end
    local invite = MySQL.single.await('SELECT invited_by FROM cm_police_invites WHERE character_id = ? AND expires_at > NOW() LIMIT 1', { characterId })
    if not invite then return false, 'This Police invitation expired.' end
    if not accept then MySQL.update.await('DELETE FROM cm_police_invites WHERE character_id = ?', { characterId }); return true, 'Police invitation declined.' end
    local inviterSrc = sourceFor(invite.invited_by)
    local inviter = inviterSrc and memberFor(invite.invited_by) or nil
    if not inviterSrc or not inviter or dbBoolean(inviter.is_suspended) or not has(inviter, 'police.invite') then
        MySQL.update.await('DELETE FROM cm_police_invites WHERE character_id = ?', { characterId })
        return false, 'This Police invitation is no longer valid.'
    end
    if not invitePlayersNearby(inviterSrc, src) then return false, 'Return to the inviting officer before accepting.' end
    if memberFor(characterId) then return false, 'You are already a Police member.' end
    local rival = rivalMember(characterId)
    if rival then return false, ('You are already a member of %s. Leave that organization before joining Police.'):format(rival.orgLabel) end
    local recruit = MySQL.single.await('SELECT id, name FROM cm_police_ranks WHERE is_leader = 0 ORDER BY tier ASC LIMIT 1')
    if not recruit then return false, 'Police has no entry rank configured.' end
    local ok = MySQL.transaction.await({
        { query = 'INSERT INTO cm_police_members (character_id, rank_id) VALUES (?, ?)', values = { characterId, recruit.id } },
        { query = 'DELETE FROM cm_police_invites WHERE character_id = ?', values = { characterId } },
    })
    if not ok then return false, 'Could not join Police.' end
    sync(characterId)
    log(characterId, 'invite_accepted', { invitedBy = invite.invited_by })
    return true, ('You joined Police as a %s.'):format(recruit.name or 'Cadet')
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    CreateThread(function() Wait(500); local characterId = cid(src); if characterId and ready then sync(characterId) end end)
end)
AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    local characterId = cid(src)
    if characterId then endPoliceDuty(src, characterId, 'character_unloaded') end
    if GetPlayerName(src) then
        Player(src).state:set('cmPolice', false, true)
        if GetResourceState('cm-chat') == 'started' then
            TriggerEvent('cm-chat:server:refreshPlayerChannels', src)
        end
    end
end)
AddEventHandler('playerDropped', function()
    local src = source
    local characterId = cid(src)
    if characterId then endPoliceDuty(src, characterId, 'disconnected') end
    useLocks[src] = nil; meetingCooldowns[src] = nil
end)

AddEventHandler('cm-police:dev:openAdmin', function(src)
    if exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) then
        TriggerClientEvent('cm-police:client:open', src, true)
    end
end)

RegisterCommand(Config.AdminMenuCommand or 'policeadmin', function(src)
    src = tonumber(src)
    if not src or src <= 0 then return end
    local allowed = false
    pcall(function() allowed = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if not allowed then
        TriggerClientEvent('cm-playerdata:client:interactionNotify', src, 'You do not have permission to manage Police.', 'error')
        log(cid(src), 'police_admin_menu_denied', {})
        return
    end
    log(cid(src), 'police_admin_menu_opened', {})
    TriggerClientEvent('cm-police:client:open', src, true)
end, false)

lib.callback.register('cm-police:server:openClothingAdmin', function(src)
    local allowed = false
    pcall(function() allowed = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if not allowed then return false, 'Permission denied.' end
    if GetResourceState('nv_cloth') ~= 'started' then return false, 'Clothing management is unavailable.' end
    SetTimeout(300, function()
        if GetPlayerName(src) and GetResourceState('nv_cloth') == 'started' then TriggerEvent('nvCloth:dev:openManage', src) end
    end)
    log(cid(src), 'police_clothing_admin_opened', {})
    return true
end)

CreateThread(function()
    setupDatabase()
    local databaseReady, databaseReason = AwaitPoliceDatabase(30000)
    if not databaseReady then
        PoliceSchemaMarkFailed('coordinator', databaseReason)
        return
    end
    ready = true
    for _, player in ipairs(GetPlayers()) do
        local characterId = cid(player)
        if characterId then sync(characterId) end
    end
    print('[cm-police] all Police schemas ready')
    registerGMenu()
    while GetResourceState(Config.AdminResource) ~= 'started' do Wait(2000) end
    exports[Config.AdminResource]:RegisterDevTool({
        id = 'police', label = 'Police Administration', category = 'Organizations', icon = 'shield-alt', permission = Config.AdminPermission,
        actions = {{ id = 'open', label = 'Open Police Administration', type = 'launcher', realm = 'server', event = 'cm-police:dev:openAdmin', hint = 'Open the dedicated Police management workspace.' }},
    })
    pcall(function()
        exports[Config.AdminResource]:RegisterOrganization({
            id = Config.OrganizationId, label = 'Police Department',
            resource = GetCurrentResourceName(), icon = 'shield-alt', canRemoveLeader = true,
            canManageFacilities = true,
            canManageNpcs = true, canManageFleet = true, canManageCapabilities = true, canManageArmory = true, canManageAlpr = true,
            canManageBarricades = true,
            facilityTypes = {
                { id = 'front_desk', label = 'Front desk NPC' },
                { id = 'armory', label = 'Armory NPC' },
                { id = 'storage', label = 'Storage NPC' },
                { id = 'intake', label = 'Prison intake NPC' },
            },
        })
    end)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == Config.PlayerDataResource then Wait(500); registerGMenu() end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    local actions = { 'police_invite', 'police_promote', 'police_demote', 'police_kick', 'police_cuff', 'police_uncuff', 'police_escort_grab', 'police_escort_release', 'police_put_in_vehicle', 'police_take_out_vehicle' }
    for _, action in ipairs(BookingActionIds()) do actions[#actions + 1] = action end
    for _, action in ipairs(actions) do TriggerEvent('cm-playerdata:server:unregisterInteractionAction', action) end
end)

exports('GetMember', function(characterId) return stateFor(tostring(characterId)) end)
exports('HasPermission', function(characterId, permission) local member = memberFor(tostring(characterId)); return has(member, tostring(permission)) end)
exports('IsOnDuty', function(characterId) local member = memberFor(tostring(characterId)); return member and dbBoolean(member.on_duty) or false end)
-- Called by cm-vehicles/server/api.lua's own CanUseVehicle as a fallback
-- once owner/family access has already been denied -- was already wired up
-- on the cm-vehicles side (pcall-guarded, so a missing export just fails
-- closed) but this export never actually existed, so the police branch of
-- vehicle access could never grant anything. Deliberately narrow: only the
-- read-only lookup/track actions are granted (matches the MDT's own
-- vehicle-search tier, police.mdt) -- drive/lock/engine/store etc. are NOT
-- granted here, since cm-police has no existing feature that needs an
-- on-duty officer to actually take control of a vehicle they don't own
-- through this hook (impound goes through server/impound.lua's own direct
-- path instead, never through this export).
local vehicleOverrideActions = { ['vehicle.info'] = true, ['vehicle.track'] = true }
exports('CanUseVehicle', function(src, vehicleId, action)
    src = tonumber(src)
    if not src or not vehicleOverrideActions[tostring(action or '')] then return false end
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    return member ~= nil and not dbBoolean(member.is_suspended) and dbBoolean(member.on_duty) and has(member, 'police.mdt')
end)
-- For cm-admin's centralized Organizations tab (CMOrganizations.forAdminPayload).
exports('GetOrganizationSummary', function()
    local org = MySQL.single.await('SELECT leader_cid FROM cm_police_organization WHERE id = 1') or {}
    local memberCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_police_members')) or 0
    local onDutyCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_police_members WHERE on_duty = 1')) or 0
    return {
        leaderCid = org.leader_cid and tostring(org.leader_cid) or nil,
        leaderName = org.leader_cid and nameFor(org.leader_cid) or nil,
        memberCount = memberCount, onDutyCount = onDutyCount,
    }
end)

-- Shared by both cm-police's own admin dashboard (via the lib.callback below,
-- used by its client NUI) and cm-admin's centralized Organizations tab (via
-- the plain export below, called server-side with no client round-trip) --
-- one leader-assignment transaction, two callers.
function doAssignLeader(src, targetCid)
    if not exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) then return false, 'Permission denied.' end
    if leaderAssignmentBusy then return false, 'Another Police leader assignment is already running.' end
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
    local leaderRank = MySQL.single.await('SELECT id FROM cm_police_ranks WHERE is_leader = 1 LIMIT 1')
    local chiefRank = MySQL.single.await('SELECT id FROM cm_police_ranks WHERE is_leader = 0 ORDER BY tier DESC LIMIT 1')
    if not leaderRank or not chiefRank then return false, 'Police rank configuration is incomplete.' end
    local org = MySQL.single.await('SELECT leader_cid FROM cm_police_organization WHERE id = 1') or {}
    local formerLeaders = MySQL.query.await('SELECT character_id FROM cm_police_members WHERE rank_id = ?', { leaderRank.id }) or {}
    local queries = {
        { query = 'UPDATE cm_police_members SET rank_id = ?, on_duty = 0 WHERE rank_id = ? AND character_id <> ?', values = { chiefRank.id, leaderRank.id, targetCid } },
    }
    queries[#queries + 1] = { query = [[INSERT INTO cm_police_members (character_id, rank_id, on_duty) VALUES (?, ?, 0) ON DUPLICATE KEY UPDATE rank_id = VALUES(rank_id), on_duty = 0]], values = { targetCid, leaderRank.id } }
    queries[#queries + 1] = { query = 'UPDATE cm_police_organization SET leader_cid = ? WHERE id = 1', values = { targetCid } }
    leaderAssignmentBusy = true
    local called, ok = pcall(function() return MySQL.transaction.await(queries) end)
    leaderAssignmentBusy = false
    if not called or ok ~= true then return false, 'Leader assignment transaction failed safely.' end
    for _, former in ipairs(formerLeaders) do sync(tostring(former.character_id)) end
    if org.leader_cid then sync(tostring(org.leader_cid)) end
    sync(targetCid)
    log(cid(src), 'leader_assigned', { targetCid = targetCid })
    TriggerEvent('cm-admin:server:addLog', src, 'police_leader_assigned', { category = 'police', characterId = targetCid })
    return true, ('%s is now the Police leader.'):format(nameFor(targetCid))
end

lib.callback.register('cm-police:server:adminAssignLeader', doAssignLeader)
exports('AdminAssignLeader', doAssignLeader)

local function doRemoveLeader(src)
    if not exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) then return false, 'Permission denied.' end
    if leaderAssignmentBusy then return false, 'Another Police leader change is already running.' end
    local org = MySQL.single.await('SELECT leader_cid FROM cm_police_organization WHERE id = 1') or {}
    local leaderCid = org.leader_cid and tostring(org.leader_cid) or nil
    if not leaderCid then return false, 'Police does not have a leader.' end

    leaderAssignmentBusy = true
    local called, ok = pcall(function()
        return MySQL.transaction.await({
            { query = 'UPDATE cm_police_organization SET leader_cid = NULL WHERE id = 1 AND leader_cid = ?', values = { leaderCid } },
            { query = 'DELETE FROM cm_police_members WHERE character_id = ?', values = { leaderCid } },
        })
    end)
    leaderAssignmentBusy = false
    if not called or ok ~= true then return false, 'Leader removal transaction failed safely.' end
    sync(leaderCid)
    log(cid(src), 'leader_removed', { formerLeaderCid = leaderCid })
    TriggerEvent('cm-admin:server:addLog', src, 'police_leader_removed', { category = 'police', characterId = leaderCid })
    return true, ('Removed %s as Police leader.'):format(nameFor(leaderCid) or leaderCid)
end

exports('AdminRemoveLeader', doRemoveLeader)

local function isPoliceAdmin(src)
    local ok, allowed = pcall(function() return exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) end)
    return ok and allowed == true
end

lib.callback.register('cm-police:server:adminStaffAction', function(src, action, payload)
    if not isPoliceAdmin(src) or not rateLimit(src, 'police_admin_staff', 800) then return false, 'Permission denied.' end
    payload = type(payload) == 'table' and payload or {}
    action = tostring(action or '')
    local targetCid = tostring(payload.characterId or '')
    if targetCid == '' or not MySQL.scalar.await('SELECT id FROM characters WHERE id = ? LIMIT 1', { targetCid }) then
        return false, 'Character ID does not exist.'
    end
    local target = memberFor(targetCid)
    if action == 'hire' then
        if target then return false, 'That character is already a Police member.' end
        local rival = rivalMember(targetCid)
        if rival then return false, ('That character is already a member of %s.'):format(rival.orgLabel) end
        local rankId = tonumber(payload.rankId)
        local rank = rankId and MySQL.single.await('SELECT id, name FROM cm_police_ranks WHERE id = ? AND is_leader = 0 LIMIT 1', { rankId })
            or MySQL.single.await('SELECT id, name FROM cm_police_ranks WHERE is_leader = 0 ORDER BY tier ASC LIMIT 1')
        if not rank then return false, 'No recruit rank is configured.' end
        MySQL.insert.await('INSERT INTO cm_police_members (character_id, rank_id, on_duty) VALUES (?, ?, 0)', { targetCid, rank.id })
        sync(targetCid); log(cid(src), 'admin_member_hired', { targetCid = targetCid, rank = rank.name })
        TriggerEvent('cm-admin:server:addLog', src, 'police_member_hired', { category = 'police', characterId = targetCid, rank = rank.name })
        return true, ('%s was hired as %s.'):format(nameFor(targetCid), rank.name)
    end
    if not target then return false, 'That character is not a Police member.' end
    if dbBoolean(target.is_leader) then return false, 'Assign a new leader before changing the current leader.' end
    if action == 'fire' then
        MySQL.update.await('DELETE FROM cm_police_members WHERE character_id = ?', { targetCid })
        sync(targetCid); log(cid(src), 'admin_member_fired', { targetCid = targetCid })
        TriggerEvent('cm-admin:server:addLog', src, 'police_member_fired', { category = 'police', characterId = targetCid })
        return true, ('%s was removed from Police.'):format(nameFor(targetCid))
    elseif action == 'suspend' then
        local minutes = math.max(5, math.min(math.floor(tonumber(payload.minutes) or 60), 43200))
        local reason = tostring(payload.reason or 'Administrative suspension'):gsub('[%c]', ' '):sub(1, 160)
        MySQL.update.await([[UPDATE cm_police_members SET on_duty = 0,
            suspended_until = DATE_ADD(NOW(), INTERVAL ? MINUTE), suspension_reason = ?, suspended_by = ?
            WHERE character_id = ?]], { minutes, reason, tostring(cid(src) or 'admin'), targetCid })
        sync(targetCid); log(cid(src), 'member_suspended', { targetCid = targetCid, minutes = minutes, reason = reason })
        TriggerEvent('cm-admin:server:addLog', src, 'police_member_suspended', { category = 'police', characterId = targetCid, minutes = minutes })
        return true, ('%s was suspended for %d minutes.'):format(nameFor(targetCid), minutes)
    elseif action == 'reinstate' then
        MySQL.update.await('UPDATE cm_police_members SET suspended_until = NULL, suspension_reason = NULL, suspended_by = NULL WHERE character_id = ?', { targetCid })
        sync(targetCid); log(cid(src), 'member_reinstated', { targetCid = targetCid })
        TriggerEvent('cm-admin:server:addLog', src, 'police_member_reinstated', { category = 'police', characterId = targetCid })
        return true, ('%s was reinstated.'):format(nameFor(targetCid))
    end
    return false, 'Unknown staffing action.'
end)
