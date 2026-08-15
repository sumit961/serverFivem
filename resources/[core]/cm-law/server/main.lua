local RESOURCE = GetCurrentResourceName()
local ready = false
local leaderLocks = {}
local useLocks = {}

-- Bare global: server/cuffs.lua/booking.lua are separate chunks and can't
-- see this file's own `ready` local directly.
function LawIsReady() return ready end

-- Bare global: server/cuffs.lua/booking.lua need the same per-src/action
-- debounce every other CM resource uses this exact shape for.
function rateLimit(src, action, waitMs)
    local key = ('%s:%s'):format(src, action)
    local now = GetGameTimer()
    if useLocks[key] and now - useLocks[key] < (waitMs or 800) then return false end
    useLocks[key] = now
    return true
end

-- Bare globals below (not local): server/vehicles.lua is a separate
-- server_scripts chunk and needs these same membership/facility helpers
-- rather than duplicating them.
function validOrgId(value)
    value = tostring(value or ''):lower()
    return Config.Organizations[value] and value or nil
end

function nameFor(characterId)
    local row = MySQL.single.await('SELECT first_name, last_name FROM characters WHERE id = ? LIMIT 1', { characterId })
    if not row then return nil end
    local name = (('%s %s'):format(row.first_name or '', row.last_name or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or tostring(characterId)
end

function adminAllowed(src)
    local ok, allowed = pcall(function()
        return exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission)
    end)
    return ok and allowed == true
end

function characterIdFor(src)
    local ok, characterId = pcall(function()
        return exports[Config.PlayerDataResource]:GetCharacterId(tonumber(src))
    end)
    return ok and characterId and tostring(characterId) or nil
end

-- oxmysql/mysql2 on this server returns some TINYINT(1) columns (on_duty,
-- is_leader, etc.) as a Lua boolean rather than 0/1 -- `tonumber(true)` is
-- nil, so a bare `tonumber(x) == 1` silently reads a genuinely-true value
-- as false. Accept either representation everywhere a duty/flag column is
-- read back. (cm-ems/cm-police hit this same thing; same fix.) Bare global:
-- server/vehicles.lua reads cm_legal_fleet_vehicles.enabled the same way.
function dbBoolean(value)
    return value == true or tonumber(value) == 1
end

local function permissionsFor(rank)
    if not rank then return {} end
    local decoded = type(rank.permissions) == 'table' and rank.permissions or json.decode(rank.permissions or '[]') or {}
    local out = {}
    for key, value in pairs(decoded) do
        if type(key) == 'number' then out[tostring(value)] = true else out[tostring(key)] = value == true end
    end
    return out
end

function memberFor(characterId, orgId)
    if not ready then return nil end
    orgId = validOrgId(orgId)
    if not orgId then return nil end
    local row = MySQL.single.await([[
        SELECT m.character_id, m.organization_id, m.on_duty, m.suspended_until,
               r.id AS rank_id, r.name AS rank_name, r.tier, r.is_leader, r.permissions
        FROM cm_legal_members m
        JOIN cm_legal_ranks r ON r.id = m.rank_id AND r.organization_id = m.organization_id
        WHERE m.character_id = ? AND m.organization_id = ? LIMIT 1
    ]], { tostring(characterId), orgId })
    if not row then return nil end
    return {
        characterId = tostring(row.character_id), organizationId = orgId,
        rankId = tonumber(row.rank_id), rankName = row.rank_name,
        tier = tonumber(row.tier) or 0, isLeader = dbBoolean(row.is_leader),
        onDuty = dbBoolean(row.on_duty),
        suspended = row.suspended_until ~= nil and tostring(row.suspended_until) ~= '',
        permissions = permissionsFor(row),
    }
end

function sourceFor(characterId)
    local ok, src = pcall(function()
        return exports[Config.PlayerDataResource]:GetSourceByCharId(tostring(characterId))
    end)
    return ok and tonumber(src) or nil
end

local function activeUniform(characterId, orgId)
    if not characterId or not orgId then return nil end
    local row = MySQL.single.await([[SELECT sex, outfit FROM cm_legal_active_outfits
        WHERE organization_id = ? AND character_id = ? LIMIT 1]], { orgId, tostring(characterId) })
    if not row or type(row.outfit) ~= 'string' then return nil end
    local ok, outfit = pcall(json.decode, row.outfit)
    if not ok or type(outfit) ~= 'table' or type(outfit.components) ~= 'table' or type(outfit.props) ~= 'table' then return nil end
    return { organizationId = orgId, sex = row.sex == 'female' and 'female' or 'male', outfit = outfit }
end

local CapabilityCache = {}

function LawCapabilityEnabled(orgId, capability)
    orgId, capability = validOrgId(orgId), tostring(capability or '')
    if not orgId or capability == '' then return false end
    local orgCache = CapabilityCache[orgId]
    if orgCache and orgCache[capability] ~= nil then return orgCache[capability] end
    local value = MySQL.scalar.await([[SELECT enabled FROM cm_legal_capabilities
        WHERE organization_id = ? AND capability = ? LIMIT 1]], { orgId, capability })
    CapabilityCache[orgId] = CapabilityCache[orgId] or {}
    -- Missing rows preserve the pre-capability behavior during upgrades.
    CapabilityCache[orgId][capability] = value == nil or dbBoolean(value)
    return CapabilityCache[orgId][capability]
end

exports('HasOrganizationCapability', function(orgId, capability)
    return LawCapabilityEnabled(orgId, capability)
end)

local function statePayload(member, uniformIsActive)
    if not member then return false end
    local org = Config.Organizations[member.organizationId]
    local capabilities = {}
    for _, capability in ipairs(Config.Capabilities or {}) do
        capabilities[capability] = LawCapabilityEnabled(member.organizationId, capability)
    end
    return {
        id = member.organizationId, label = org.label, shortLabel = org.shortLabel,
        rankId = member.rankId, rankName = member.rankName, tier = member.tier,
        isLeader = member.isLeader, onDuty = member.onDuty,
        uniformActive = member.onDuty and uniformIsActive == true,
        suspended = member.suspended, permissions = member.permissions,
        capabilities = capabilities,
        canStartPlainclothes = tonumber(org.plainclothesMinTier) ~= nil
            and member.tier >= tonumber(org.plainclothesMinTier),
    }
end

local function syncCharacter(characterId)
    if not ready or not characterId then return end
    local row = MySQL.single.await([[
        SELECT m.organization_id FROM cm_legal_members m
        JOIN cm_legal_ranks r ON r.id = m.rank_id AND r.organization_id = m.organization_id
        WHERE m.character_id = ? ORDER BY m.on_duty DESC, r.tier DESC LIMIT 1
    ]], { tostring(characterId) })
    local member = row and memberFor(characterId, row.organization_id) or nil
    local uniform = member and member.onDuty and activeUniform(characterId, member.organizationId) or nil
    local src = sourceFor(characterId)
    if src and GetPlayerName(src) then
        local payload = statePayload(member, uniform ~= nil)
        Player(src).state:set('cmLegalOrg', payload, true)
        TriggerClientEvent('cm-law:client:membershipChanged', src, payload)
        TriggerClientEvent('cm-law:client:dutyUniformState', src, uniform or false)
        if GetResourceState('cm-chat') == 'started' then
            TriggerEvent('cm-chat:server:refreshPlayerChannels', src)
        end
    end
end

local function syncOrganization(orgId)
    local rows = MySQL.query.await('SELECT character_id FROM cm_legal_members WHERE organization_id = ?', { orgId }) or {}
    for _, row in ipairs(rows) do syncCharacter(row.character_id) end
end

function activeMemberForSource(src)
    local characterId = characterIdFor(src)
    if not characterId then return nil, nil end
    local row = MySQL.single.await([[
        SELECT m.organization_id FROM cm_legal_members m
        JOIN cm_legal_ranks r ON r.id = m.rank_id AND r.organization_id = m.organization_id
        WHERE m.character_id = ? ORDER BY m.on_duty DESC, r.tier DESC LIMIT 1
    ]], { characterId })
    return row and memberFor(characterId, row.organization_id) or nil, characterId
end

function canManage(member)
    return member and (member.isLeader or member.permissions['law.manage_members'] == true)
end

function logActivity(orgId, actorCid, action, detail)
    MySQL.insert.await('INSERT INTO cm_legal_activity_logs (organization_id, actor_cid, action, detail) VALUES (?, ?, ?, ?)',
        { orgId, actorCid, action, json.encode(detail or {}) })
end

local function facilityRows(orgId)
    local rows = MySQL.query.await([[
        SELECT facility_type, x, y, z, heading, routing_bucket
        FROM cm_legal_facilities WHERE organization_id = ?
    ]], { orgId }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        out[tostring(row.facility_type)] = {
            x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
            heading = tonumber(row.heading) or 0.0, bucket = tonumber(row.routing_bucket) or 0,
        }
    end
    return out
end

-- Shared server-script helper used by booking.lua. Returns only the saved
-- organization facility record; callers still enforce access and distance.
function LawFacilityLocation(orgId, facilityType)
    return facilityRows(orgId)[tostring(facilityType or '')]
end

local function dashboardFor(src)
    local member = activeMemberForSource(src)
    if not member then return { ok = false, error = 'You are not a member of a legal organization.' } end
    local org = Config.Organizations[member.organizationId]
    local roster = MySQL.query.await([[
        SELECT m.character_id, m.on_duty, m.suspended_until, r.id AS rank_id,
               r.name AS rank_name, r.tier, r.is_leader, c.first_name, c.last_name
        FROM cm_legal_members m
        JOIN cm_legal_ranks r ON r.id = m.rank_id AND r.organization_id = m.organization_id
        LEFT JOIN characters c ON c.id = m.character_id
        WHERE m.organization_id = ? ORDER BY r.tier DESC, c.first_name ASC, c.last_name ASC
    ]], { member.organizationId }) or {}
    for _, row in ipairs(roster) do
        row.character_id = tostring(row.character_id)
        row.name = (('%s %s'):format(row.first_name or '', row.last_name or '')):gsub('^%s+', ''):gsub('%s+$', '')
        row.on_duty = dbBoolean(row.on_duty)
        row.is_leader = dbBoolean(row.is_leader)
        row.suspended = row.suspended_until ~= nil
        row.first_name, row.last_name, row.suspended_until = nil, nil, nil
    end
    local ranks = MySQL.query.await('SELECT id, name, tier, is_leader, permissions FROM cm_legal_ranks WHERE organization_id = ? ORDER BY tier DESC', { member.organizationId }) or {}
    for _, rank in ipairs(ranks) do
        rank.is_leader = dbBoolean(rank.is_leader)
        rank.permissions = permissionsFor(rank)
    end
    return { ok = true, organization = { id = member.organizationId, label = org.label, shortLabel = org.shortLabel,
        color = org.color, jurisdiction = org.jurisdiction },
        member = statePayload(member, activeUniform(member.characterId, member.organizationId) ~= nil), canManage = canManage(member),
        characterId = member.characterId,
        canDispatch = member.isLeader or member.permissions['law.receive_dispatch'] == true,
        canMdt = member.isLeader or member.permissions['law.mdt'] == true,
        canFleetManage = member.isLeader or member.permissions['law.fleet'] == true,
        canFleetSpawn = member.isLeader or member.permissions['law.vehicle'] == true,
        canManageRanks = member.isLeader or member.permissions['law.manage_ranks'] == true,
        canManagePermissions = member.isLeader or member.permissions['law.manage_permissions'] == true,
        permissions = Config.Permissions,
        roster = roster, ranks = ranks }
end

local function ensureSchema()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_organizations (
        organization_id VARCHAR(32) NOT NULL, label VARCHAR(96) NOT NULL,
        short_label VARCHAR(24) NOT NULL, organization_type VARCHAR(32) NOT NULL,
        icon VARCHAR(48) NULL, leader_cid VARCHAR(64) NULL, enabled TINYINT(1) NOT NULL DEFAULT 1,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (organization_id), KEY idx_cm_legal_leader (leader_cid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_ranks (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, organization_id VARCHAR(32) NOT NULL,
        tier INT NOT NULL, name VARCHAR(64) NOT NULL, is_leader TINYINT(1) NOT NULL DEFAULT 0,
        permissions LONGTEXT NOT NULL,
        PRIMARY KEY (id), UNIQUE KEY uq_cm_legal_rank_tier (organization_id, tier),
        KEY idx_cm_legal_rank_org (organization_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_members (
        organization_id VARCHAR(32) NOT NULL, character_id VARCHAR(64) NOT NULL,
        rank_id BIGINT UNSIGNED NOT NULL, on_duty TINYINT(1) NOT NULL DEFAULT 0,
        suspended_until DATETIME NULL, joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (organization_id, character_id), KEY idx_cm_legal_member_character (character_id),
        KEY idx_cm_legal_member_rank (rank_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_activity_logs (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, organization_id VARCHAR(32) NOT NULL,
        actor_cid VARCHAR(64) NULL, action VARCHAR(64) NOT NULL, detail LONGTEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id), KEY idx_cm_legal_logs_org_time (organization_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_facilities (
        organization_id VARCHAR(32) NOT NULL, facility_type VARCHAR(32) NOT NULL,
        x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading FLOAT NOT NULL DEFAULT 0,
        routing_bucket INT NOT NULL DEFAULT 0, updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (organization_id, facility_type),
        KEY idx_cm_legal_facility_type (facility_type)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_capabilities (
        organization_id VARCHAR(32) NOT NULL, capability VARCHAR(32) NOT NULL,
        enabled TINYINT(1) NOT NULL DEFAULT 1, updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (organization_id, capability)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    for orgId in pairs(Config.Organizations) do
        for _, capability in ipairs(Config.Capabilities or {}) do
            MySQL.insert.await([[INSERT IGNORE INTO cm_legal_capabilities
                (organization_id, capability, enabled, updated_by) VALUES (?, ?, 1, 'migration')]],
                { orgId, capability })
        end
    end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_jail_settings (
        setting_key VARCHAR(32) NOT NULL,setting_value LONGTEXT NOT NULL,updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY(setting_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_active_outfits (
        organization_id VARCHAR(32) NOT NULL, character_id VARCHAR(64) NOT NULL,
        sex VARCHAR(8) NOT NULL, outfit LONGTEXT NOT NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (organization_id, character_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- What each org's Fleet facility offers: model, whether it's a car or
    -- helicopter, minimum rank tier to spawn it, and whether it's currently
    -- enabled. Appearance/label/image come live from rn-vehicleshop's
    -- GetOrgCatalog export (see server/vehicles.lua) -- never duplicated here.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_fleet_vehicles (
        organization_id VARCHAR(32) NOT NULL, model VARCHAR(64) NOT NULL,
        kind ENUM('car','helicopter') NOT NULL DEFAULT 'car',
        min_tier SMALLINT UNSIGNED NOT NULL DEFAULT 0, enabled TINYINT(1) NOT NULL DEFAULT 1,
        spawn_x DOUBLE NULL, spawn_y DOUBLE NULL, spawn_z DOUBLE NULL, spawn_h FLOAT NOT NULL DEFAULT 0,
        updated_by VARCHAR(64) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (organization_id, model)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Added after the table above already shipped on some installs -- a
    -- persistent, garage-quality cm-vehicles record per configured fleet
    -- vehicle (condition/fuel/damage survive between recalls), same as
    -- cm-police's cm_police_fleet_vehicles.vehicle_id. NULL until a manager
    -- drives the location-setting dummy and presses H (server/vehicles.lua's
    -- saveFleetVehicleLocation), which is also what creates this row.
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_fleet_vehicles ADD COLUMN vehicle_id BIGINT UNSIGNED NULL') end)
    -- Minimal custody tracking (server/cuffs.lua) -- enough to restore a
    -- cuffed player's restraint state on reconnect. Actual jail sentences
    -- live in cm-prison's own cm_prison_sentences once booked.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_custody (
        character_id VARCHAR(64) NOT NULL, organization_id VARCHAR(32) NOT NULL,
        officer_cid VARCHAR(64) NULL, status VARCHAR(24) NOT NULL DEFAULT 'cuffed',
        reason VARCHAR(160) NULL, booking_minutes INT UNSIGNED NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id), KEY idx_cm_legal_custody_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Joint citizen and officer dispatch (server/dispatch.lua). Officer
    -- alerts retain their originating organization and routing bucket while
    -- responders may still come from any authorized legal organization.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_incidents (
        id BIGINT UNSIGNED NOT NULL,
        caller_cid VARCHAR(64) NULL, caller_name VARCHAR(128) NULL,
        details VARCHAR(180) NOT NULL,
        coords_x FLOAT NOT NULL, coords_y FLOAT NOT NULL, coords_z FLOAT NOT NULL,
        location VARCHAR(120) NULL,
        status ENUM('waiting','accepted','resolved','expired') NOT NULL DEFAULT 'waiting',
        call_type VARCHAR(24) NOT NULL DEFAULT 'citizen',
        priority TINYINT UNSIGNED NOT NULL DEFAULT 1,
        organization_id VARCHAR(32) NULL,
        routing_bucket INT NOT NULL DEFAULT 0,
        responders LONGTEXT NULL, resolution VARCHAR(160) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        resolved_at TIMESTAMP NULL,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    pcall(function() MySQL.query.await("ALTER TABLE cm_legal_incidents ADD COLUMN call_type VARCHAR(24) NOT NULL DEFAULT 'citizen'") end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_incidents ADD COLUMN priority TINYINT UNSIGNED NOT NULL DEFAULT 1') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_incidents ADD COLUMN organization_id VARCHAR(32) NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_incidents ADD COLUMN routing_bucket INT NOT NULL DEFAULT 0') end)

    for orgId, org in pairs(Config.Organizations) do
        MySQL.insert.await([[INSERT INTO cm_legal_organizations
            (organization_id, label, short_label, organization_type, icon)
            VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE label = VALUES(label),
            short_label = VALUES(short_label), organization_type = VALUES(organization_type), icon = VALUES(icon)]],
            { orgId, org.label, org.shortLabel, org.type, org.icon })
        -- Seed-once, not seed-every-restart: once the F9 Ranks & Access page
        -- (server-side saveRank/deleteRank) can edit a rank's name/tier/
        -- permissions, the database becomes authoritative for that org --
        -- same convention cm-police uses (server/main.lua's setupDatabase,
        -- "if existingRankCount == 0"). Config.Organizations[orgId].ranks
        -- only ever seeds a brand-new organization's initial rank ladder;
        -- editing config.lua after that point no longer reaches an
        -- already-running server's existing rank rows.
        local existingRankCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_legal_ranks WHERE organization_id = ?', { orgId })) or 0
        if existingRankCount == 0 then
            for _, rank in ipairs(org.ranks or {}) do
                MySQL.insert.await('INSERT INTO cm_legal_ranks (organization_id, tier, name, is_leader, permissions) VALUES (?, ?, ?, ?, ?)',
                    { orgId, rank.tier, rank.name, rank.leader and 1 or 0, json.encode(rank.permissions or Config.DefaultPermissions) })
            end
        end
    end
end

local function summary(orgId)
    orgId = validOrgId(orgId)
    if not ready or not orgId then return {} end
    local org = MySQL.single.await('SELECT leader_cid FROM cm_legal_organizations WHERE organization_id = ? LIMIT 1', { orgId }) or {}
    return {
        leaderCid = org.leader_cid and tostring(org.leader_cid) or nil,
        leaderName = org.leader_cid and nameFor(org.leader_cid) or nil,
        memberCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_legal_members WHERE organization_id = ?', { orgId })) or 0,
        onDutyCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_legal_members WHERE organization_id = ? AND on_duty = 1', { orgId })) or 0,
    }
end

local function assignLeader(src, targetCid, orgId)
    orgId = validOrgId(orgId)
    if not orgId then return false, 'Unknown legal organization.' end
    if not adminAllowed(tonumber(src)) then return false, 'Permission denied.' end
    if leaderLocks[orgId] then return false, 'Another leader assignment is already running.' end
    targetCid = tostring(targetCid or '')
    if targetCid == '' or not MySQL.scalar.await('SELECT id FROM characters WHERE id = ? LIMIT 1', { targetCid }) then
        return false, 'Character ID does not exist.'
    end
    local rival = exports[Config.AdminResource]:FindRivalMembership(orgId, targetCid)
    if rival then
        local allowSameLeader = exports[Config.AdminResource]:GetOrgPolicySetting('allowSameLeaderAcrossOrgs') == true
        if not (allowSameLeader and rival.isLeader) then
            return false, ('That character is already a member of %s.'):format(rival.orgLabel)
        end
    end
    local leaderRank = MySQL.single.await('SELECT id FROM cm_legal_ranks WHERE organization_id = ? AND is_leader = 1 LIMIT 1', { orgId })
    local fallbackRank = MySQL.single.await('SELECT id FROM cm_legal_ranks WHERE organization_id = ? AND is_leader = 0 ORDER BY tier DESC LIMIT 1', { orgId })
    if not leaderRank or not fallbackRank then return false, 'Organization ranks are incomplete.' end
    leaderLocks[orgId] = true
    local called, committed = pcall(function()
        return MySQL.transaction.await({
            { query = 'UPDATE cm_legal_members SET rank_id = ?, on_duty = 0 WHERE organization_id = ? AND rank_id = ? AND character_id <> ?', values = { fallbackRank.id, orgId, leaderRank.id, targetCid } },
            { query = [[INSERT INTO cm_legal_members (organization_id, character_id, rank_id, on_duty)
                VALUES (?, ?, ?, 0) ON DUPLICATE KEY UPDATE rank_id = VALUES(rank_id), on_duty = 0]], values = { orgId, targetCid, leaderRank.id } },
            { query = 'UPDATE cm_legal_organizations SET leader_cid = ? WHERE organization_id = ?', values = { targetCid, orgId } },
            { query = 'DELETE FROM cm_legal_active_outfits WHERE organization_id = ? AND character_id = ?', values = { orgId, targetCid } },
            { query = 'INSERT INTO cm_legal_activity_logs (organization_id, actor_cid, action, detail) VALUES (?, ?, ?, ?)', values = { orgId, characterIdFor(src), 'leader_assigned', json.encode({ targetCid = targetCid }) } },
        })
    end)
    leaderLocks[orgId] = nil
    if not called or committed ~= true then return false, 'Leader assignment transaction failed safely.' end
    syncOrganization(orgId)
    TriggerEvent('cm-admin:server:addLog', src, 'legal_org_leader_assigned', { category = 'orgs', organizationId = orgId, characterId = targetCid })
    return true, ('%s is now the leader of %s.'):format(nameFor(targetCid) or targetCid, Config.Organizations[orgId].label)
end

local function removeLeader(src, orgId)
    orgId = validOrgId(orgId)
    if not orgId then return false, 'Unknown legal organization.' end
    if not adminAllowed(tonumber(src)) then return false, 'Permission denied.' end
    if leaderLocks[orgId] then return false, 'Another leader change is already running.' end

    local current = MySQL.single.await(
        'SELECT leader_cid FROM cm_legal_organizations WHERE organization_id = ? LIMIT 1', { orgId })
    local leaderCid = current and current.leader_cid and tostring(current.leader_cid) or nil
    if not leaderCid then return false, 'This organization does not have a leader.' end

    leaderLocks[orgId] = true
    local called, committed = pcall(function()
        return MySQL.transaction.await({
            { query = 'UPDATE cm_legal_organizations SET leader_cid = NULL WHERE organization_id = ? AND leader_cid = ?', values = { orgId, leaderCid } },
            { query = 'DELETE FROM cm_legal_members WHERE organization_id = ? AND character_id = ?', values = { orgId, leaderCid } },
            { query = 'DELETE FROM cm_legal_active_outfits WHERE organization_id = ? AND character_id = ?', values = { orgId, leaderCid } },
            { query = 'INSERT INTO cm_legal_activity_logs (organization_id, actor_cid, action, detail) VALUES (?, ?, ?, ?)', values = {
                orgId, characterIdFor(src), 'leader_removed', json.encode({ formerLeaderCid = leaderCid })
            } },
        })
    end)
    leaderLocks[orgId] = nil
    if not called or committed ~= true then return false, 'Leader removal transaction failed safely.' end

    syncCharacter(leaderCid)
    TriggerEvent('cm-admin:server:addLog', src, 'legal_org_leader_removed', {
        category = 'orgs', organizationId = orgId, characterId = leaderCid,
    })
    return true, ('Removed %s as leader of %s.'):format(
        nameFor(leaderCid) or leaderCid, Config.Organizations[orgId].label)
end

exports('GetMember', memberFor)
exports('GetOrganizationSummary', summary)
exports('AdminAssignLeader', assignLeader)
exports('AdminRemoveLeader', removeLeader)
exports('GetOrganization', function(orgId)
    orgId = validOrgId(orgId)
    if not orgId then return nil end
    local configured = Config.Organizations[orgId]
    return { id = orgId, label = configured.label, shortLabel = configured.shortLabel, type = configured.type,
        icon = configured.icon, color = configured.color, jurisdiction = configured.jurisdiction,
        chatChannel = configured.chatChannel, radioChannel = configured.radioChannel,
        fleetNamespace = configured.fleetNamespace, armoryNamespace = configured.armoryNamespace,
        wardrobeNamespace = configured.wardrobeNamespace, serviceNpc = configured.serviceNpc }
end)
exports('GetOrganizations', function()
    local organizations = {}
    for orgId, configured in pairs(Config.Organizations) do
        organizations[#organizations + 1] = { id = orgId, label = configured.label, shortLabel = configured.shortLabel,
            type = configured.type, icon = configured.icon, color = configured.color, jurisdiction = configured.jurisdiction,
            chatChannel = configured.chatChannel, radioChannel = configured.radioChannel,
            fleetNamespace = configured.fleetNamespace, armoryNamespace = configured.armoryNamespace,
            wardrobeNamespace = configured.wardrobeNamespace, serviceNpc = configured.serviceNpc }
    end
    table.sort(organizations, function(a, b) return a.label < b.label end)
    return organizations
end)
exports('HasPermission', function(characterId, permission, orgId)
    local member = memberFor(characterId, orgId)
    return member and (member.isLeader or member.permissions[tostring(permission)] == true) or false
end)
exports('IsOnDuty', function(characterId, orgId)
    local member = memberFor(characterId, orgId)
    return member and member.onDuty == true or false
end)

lib.callback.register('cm-law:server:dashboard', function(src)
    if not ready then return { ok = false, error = 'Legal organizations are still starting.' } end
    return dashboardFor(src)
end)

local function endLawDuty(src, characterId, orgId, reason)
    src, characterId, orgId = tonumber(src), tostring(characterId or ''), validOrgId(orgId)
    if characterId == '' or not orgId then return false end
    local member = memberFor(characterId, orgId)
    if not member or member.onDuty ~= true then return false end
    local committed = MySQL.transaction.await({
        { query = 'UPDATE cm_legal_members SET on_duty = 0 WHERE organization_id = ? AND character_id = ?', values = { orgId, characterId } },
        { query = 'DELETE FROM cm_legal_active_outfits WHERE organization_id = ? AND character_id = ?', values = { orgId, characterId } },
    })
    if committed ~= true then return false end
    TriggerEvent('cm-law:server:memberWentOffDuty', src, characterId, orgId, tostring(reason or 'off_duty'))
    if src and GetPlayerName(src) then TriggerClientEvent('cm-law:client:forceDutyCleanup', src, tostring(reason or 'off_duty')) end
    logActivity(orgId, characterId, 'duty_ended', { reason = tostring(reason or 'manual') })
    syncCharacter(characterId)
    return true
end

lib.callback.register('cm-law:server:setDuty', function(src, requested)
    local member, characterId = activeMemberForSource(src)
    if not member then return { ok = false, error = 'No legal organization membership.' } end
    if member.suspended then return { ok = false, error = 'Your membership is suspended.' } end
    local org = Config.Organizations[member.organizationId]
    local plainclothesAllowed = tonumber(org.plainclothesMinTier) ~= nil
        and member.tier >= tonumber(org.plainclothesMinTier)
    if requested == true and not plainclothesAllowed then
        return { ok = false, error = 'Wear an approved uniform at your organization wardrobe to start duty.' }
    end
    local onDuty = requested == true
    if not onDuty then
        if not endLawDuty(src, characterId, member.organizationId, 'manual') then
            return { ok = false, error = 'Duty status did not save. Please try again.' }
        end
        return { ok = true, message = 'You are now off duty. Your personal clothes and equipment have been restored.' }
    end
    local statements = {
        { query = 'UPDATE cm_legal_members SET on_duty = ? WHERE organization_id = ? AND character_id = ?', values = { onDuty and 1 or 0, member.organizationId, characterId } },
    }
    -- Plainclothes duty must never inherit a stale uniform from an earlier
    -- shift. Ending duty likewise removes the active duty snapshot.
    statements[#statements + 1] = { query = 'DELETE FROM cm_legal_active_outfits WHERE organization_id = ? AND character_id = ?', values = { member.organizationId, characterId } }
    if MySQL.transaction.await(statements) ~= true then return { ok = false, error = 'Duty status did not save. Please try again.' } end
    local storedDuty = dbBoolean(MySQL.scalar.await(
        'SELECT on_duty FROM cm_legal_members WHERE organization_id = ? AND character_id = ? LIMIT 1',
        { member.organizationId, characterId }))
    if storedDuty ~= onDuty then return { ok = false, error = 'Duty status did not save. Please try again.' } end
    logActivity(member.organizationId, characterId, onDuty and 'duty_started' or 'duty_ended', {})
    syncCharacter(characterId)
    return { ok = true, message = onDuty and 'You are now on duty in plain clothes.'
        or 'You are now off duty. Your personal clothes have been restored.' }
end)

lib.callback.register('cm-law:server:staffAction', function(src, action, payload)
    local actor, actorCid = activeMemberForSource(src)
    if not canManage(actor) then return { ok = false, error = 'You cannot manage organization members.' } end
    payload = type(payload) == 'table' and payload or {}
    local targetCid = tostring(payload.characterId or '')
    if targetCid == '' or not MySQL.scalar.await('SELECT id FROM characters WHERE id = ? LIMIT 1', { targetCid }) then
        return { ok = false, error = 'Character ID does not exist.' }
    end
    local target = memberFor(targetCid, actor.organizationId)
    if action == 'hire' then
        if target then return { ok = false, error = 'That character is already a member.' } end
        local rival = exports[Config.AdminResource]:FindRivalMembership(actor.organizationId, targetCid)
        if rival then return { ok = false, error = ('That character already belongs to %s.'):format(rival.orgLabel) } end
        local rank = MySQL.single.await('SELECT id, tier, is_leader FROM cm_legal_ranks WHERE id = ? AND organization_id = ? LIMIT 1',
            { tonumber(payload.rankId), actor.organizationId })
        if not rank or dbBoolean(rank.is_leader) or tonumber(rank.tier) >= actor.tier then
            return { ok = false, error = 'Choose a rank below your own.' }
        end
        MySQL.insert.await('INSERT INTO cm_legal_members (organization_id, character_id, rank_id) VALUES (?, ?, ?)',
            { actor.organizationId, targetCid, rank.id })
    elseif action == 'rank' then
        if not target or target.isLeader or target.tier >= actor.tier then return { ok = false, error = 'You cannot change that member.' } end
        local rank = MySQL.single.await('SELECT id, tier, is_leader FROM cm_legal_ranks WHERE id = ? AND organization_id = ? LIMIT 1',
            { tonumber(payload.rankId), actor.organizationId })
        if not rank or dbBoolean(rank.is_leader) or tonumber(rank.tier) >= actor.tier then
            return { ok = false, error = 'Choose a rank below your own.' }
        end
        MySQL.update.await('UPDATE cm_legal_members SET rank_id = ? WHERE organization_id = ? AND character_id = ?',
            { rank.id, actor.organizationId, targetCid })
    elseif action == 'suspend' or action == 'reinstate' then
        if not target or target.isLeader or target.tier >= actor.tier then return { ok = false, error = 'You cannot change that member.' } end
        if action == 'suspend' then endLawDuty(sourceFor(targetCid), targetCid, actor.organizationId, 'suspended') end
        MySQL.update.await('UPDATE cm_legal_members SET suspended_until = ?, on_duty = 0 WHERE organization_id = ? AND character_id = ?',
            { action == 'suspend' and '2099-12-31 23:59:59' or nil, actor.organizationId, targetCid })
        if action == 'suspend' then MySQL.update.await('DELETE FROM cm_legal_active_outfits WHERE organization_id = ? AND character_id = ?', { actor.organizationId, targetCid }) end
    elseif action == 'fire' then
        if not target or target.isLeader or target.tier >= actor.tier or targetCid == actorCid then
            return { ok = false, error = 'You cannot remove that member.' }
        end
        endLawDuty(sourceFor(targetCid), targetCid, actor.organizationId, 'removed')
        MySQL.update.await('DELETE FROM cm_legal_members WHERE organization_id = ? AND character_id = ?', { actor.organizationId, targetCid })
        MySQL.update.await('DELETE FROM cm_legal_active_outfits WHERE organization_id = ? AND character_id = ?', { actor.organizationId, targetCid })
    else
        return { ok = false, error = 'Unknown staffing action.' }
    end
    logActivity(actor.organizationId, actorCid, 'member_' .. action, { targetCid = targetCid, rankId = tonumber(payload.rankId) })
    TriggerEvent('cm-admin:server:addLog', src, 'legal_org_member_' .. action, { category = 'orgs', organizationId = actor.organizationId, characterId = targetCid })
    syncCharacter(targetCid)
    return { ok = true, message = 'Organization roster updated.' }
end)

-- F9 Ranks & Access page. Separate from staffAction above (which assigns
-- members TO ranks) -- this defines the ranks themselves. Mirrors
-- cm-police's save_rank/delete_rank guards (server/main.lua): the leader
-- rank is fully protected, a rank can never be created/edited at or above
-- the acting member's own tier, and a permission can only be granted to a
-- rank if the acting member already holds it themselves.
lib.callback.register('cm-law:server:saveRank', function(src, payload)
    local actor, actorCid = activeMemberForSource(src)
    if not actor or not (actor.isLeader or actor.permissions['law.manage_ranks'] == true) then
        return { ok = false, error = 'Your rank cannot manage ranks.' }
    end
    payload = type(payload) == 'table' and payload or {}
    local orgId = actor.organizationId
    local rankId = tonumber(payload.rankId)
    local name = tostring(payload.name or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%c]', '')
    if #name < 2 or #name > 48 then return { ok = false, error = 'Rank name must be 2-48 characters.' } end
    local tier = math.floor(tonumber(payload.tier) or -1)
    if tier < 1 or tier >= 100 then return { ok = false, error = 'Tier must be between 1 and 99.' } end
    if not actor.isLeader and tier >= actor.tier then return { ok = false, error = 'You cannot set a tier at or above your own.' } end

    local existing = rankId and MySQL.single.await('SELECT id, tier, is_leader FROM cm_legal_ranks WHERE id = ? AND organization_id = ? LIMIT 1', { rankId, orgId })
    if rankId and not existing then return { ok = false, error = 'That rank no longer exists.' } end
    if existing then
        if dbBoolean(existing.is_leader) then return { ok = false, error = 'The organization leader rank is protected.' } end
        if not actor.isLeader and tonumber(existing.tier) >= actor.tier then return { ok = false, error = 'You cannot edit a rank at or above your own tier.' } end
    end

    -- Permissions only change if the payload actually included a
    -- permissions table AND the actor holds law.manage_permissions --
    -- otherwise a plain name/tier edit leaves the rank's permissions alone.
    local permissionsJson = nil
    if type(payload.permissions) == 'table' then
        if not (actor.isLeader or actor.permissions['law.manage_permissions'] == true) then
            return { ok = false, error = 'Your rank cannot assign permissions.' }
        end
        local granted = {}
        for key, value in pairs(payload.permissions) do
            local permission = tostring(key)
            if value == true and Config.Permissions[permission] and (actor.isLeader or actor.permissions[permission] == true) then
                granted[#granted + 1] = permission
            end
        end
        permissionsJson = json.encode(granted)
    end

    -- cm_legal_ranks has a UNIQUE(organization_id, tier) constraint --
    -- checked explicitly (rather than letting the UPDATE/INSERT hit it) so
    -- both branches return a clear message instead of an uncaught SQL error.
    local tierConflict = MySQL.scalar.await('SELECT id FROM cm_legal_ranks WHERE organization_id = ? AND tier = ? AND id != ?', { orgId, tier, rankId or 0 })
    if tierConflict then return { ok = false, error = 'Another rank already uses that tier.' } end

    if existing then
        if permissionsJson then
            MySQL.update.await('UPDATE cm_legal_ranks SET name = ?, tier = ?, permissions = ? WHERE id = ? AND organization_id = ? AND is_leader = 0',
                { name, tier, permissionsJson, rankId, orgId })
        else
            MySQL.update.await('UPDATE cm_legal_ranks SET name = ?, tier = ? WHERE id = ? AND organization_id = ? AND is_leader = 0',
                { name, tier, rankId, orgId })
        end
        logActivity(orgId, actorCid, 'rank_edited', { rankId = rankId, name = name, tier = tier })
    else
        MySQL.insert.await('INSERT INTO cm_legal_ranks (organization_id, tier, name, is_leader, permissions) VALUES (?, ?, ?, 0, ?)',
            { orgId, tier, name, permissionsJson or '[]' })
        logActivity(orgId, actorCid, 'rank_created', { name = name, tier = tier })
    end
    return { ok = true, message = 'Rank saved.' }
end)

lib.callback.register('cm-law:server:deleteRank', function(src, rankId)
    local actor, actorCid = activeMemberForSource(src)
    if not actor or not (actor.isLeader or actor.permissions['law.manage_ranks'] == true) then
        return { ok = false, error = 'Your rank cannot manage ranks.' }
    end
    rankId = tonumber(rankId)
    local orgId = actor.organizationId
    local rank = rankId and MySQL.single.await('SELECT id, name, tier, is_leader FROM cm_legal_ranks WHERE id = ? AND organization_id = ? LIMIT 1', { rankId, orgId })
    if not rank then return { ok = false, error = 'That rank no longer exists.' } end
    if dbBoolean(rank.is_leader) then return { ok = false, error = 'The organization leader rank is protected.' } end
    if not actor.isLeader and tonumber(rank.tier) >= actor.tier then return { ok = false, error = 'You cannot delete a rank at or above your own tier.' } end
    local memberCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_legal_members WHERE organization_id = ? AND rank_id = ?', { orgId, rankId })) or 0
    if memberCount > 0 then return { ok = false, error = ('%d member(s) still hold this rank. Reassign them first.'):format(memberCount) } end
    local rankCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_legal_ranks WHERE organization_id = ? AND is_leader = 0', { orgId })) or 0
    if rankCount <= 1 then return { ok = false, error = 'An organization must keep at least one non-leader rank.' } end
    MySQL.update.await('DELETE FROM cm_legal_ranks WHERE id = ? AND organization_id = ? AND is_leader = 0', { rankId, orgId })
    logActivity(orgId, actorCid, 'rank_deleted', { rankId = rankId, name = rank.name })
    return { ok = true, message = 'Rank deleted.' }
end)

-- F9 Activity Logs page. On-demand fetch (like fleetCatalog/dispatchHistory
-- above it), not bundled into the initial dashboard payload.
lib.callback.register('cm-law:server:activityLog', function(src)
    local actor = activeMemberForSource(src)
    if not canManage(actor) then return {} end
    local rows = MySQL.query.await([[
        SELECT l.id, l.actor_cid, l.action, l.detail, l.created_at,
               TRIM(CONCAT(COALESCE(c.first_name, ''), ' ', COALESCE(c.last_name, ''))) AS actor_name
        FROM cm_legal_activity_logs l
        LEFT JOIN characters c ON c.id = l.actor_cid
        WHERE l.organization_id = ?
        ORDER BY l.id DESC LIMIT 100
    ]], { actor.organizationId }) or {}
    for _, row in ipairs(rows) do
        row.actorCid = tostring(row.actor_cid or '')
        row.actorName = row.actor_name ~= '' and row.actor_name or row.actorCid
        row.createdAt = tostring(row.created_at or '')
        row.detail = (type(row.detail) == 'string' and json.decode(row.detail)) or {}
        row.actor_cid, row.actor_name, row.created_at = nil, nil, nil
    end
    return rows
end)

local function validFacilityType(value)
    value = tostring(value or ''):lower()
    return Config.FacilityTypes[value] and value or nil
end

local function facilityAccess(src, orgId, facilityType)
    orgId, facilityType = validOrgId(orgId), validFacilityType(facilityType)
    if not orgId or not facilityType then return nil, nil, 'Unknown organization facility.' end
    if Config.FacilityTypes[facilityType].public == true then return true, nil, nil end
    local characterId = characterIdFor(src)
    local member = characterId and memberFor(characterId, orgId)
    local org = Config.Organizations[orgId]
    if not member then
        return nil, characterId, ('You are not a member of %s. This service is restricted.'):format(org.label)
    end
    if member.suspended then return nil, characterId, 'Your organization access is suspended.' end
    local capability = facilityType == 'armory' and 'armory'
        or facilityType == 'evidence' and 'evidence'
        or facilityType == 'fleet' and 'fleet'
        or facilityType == 'intake' and 'prisonIntake' or nil
    if capability and not LawCapabilityEnabled(orgId, capability) then
        return nil, characterId, 'This service is disabled for your organization.'
    end
    if Config.FacilityTypes[facilityType].allowOffDuty ~= true and not member.onDuty then
        return nil, characterId, 'Visit your wardrobe and wear an approved uniform before using this service.'
    end
    local permission = facilityType == 'armory' and 'law.armory'
        or facilityType == 'storage' and 'law.storage'
        or facilityType == 'evidence' and 'law.search'
        or facilityType == 'fleet' and 'law.fleet'
        or facilityType == 'intake' and 'law.cuff' or nil
    if permission and not member.isLeader and member.permissions[permission] ~= true then
        return nil, characterId, 'Your rank does not have access to this service.'
    end
    return member, characterId, nil
end

function nearFacility(src, orgId, facilityType)
    local location = facilityRows(orgId)[facilityType]
    local ped = GetPlayerPed(src)
    if not location or not ped or ped == 0 then return false end
    if GetPlayerRoutingBucket(src) ~= location.bucket then return false end
    return #(GetEntityCoords(ped) - vector3(location.x, location.y, location.z)) <= (Config.FacilityInteractDistance or 2.5) + 1.0
end

local wardrobeRate = {}
local function wardrobeOfficer(src, orgId)
    orgId = validOrgId(orgId)
    local characterId = characterIdFor(src)
    local member = characterId and orgId and memberFor(characterId, orgId)
    if not member then return nil, characterId, 'You are not a member of this organization.' end
    if member.suspended then return nil, characterId, 'Your organization access is suspended.' end
    if not nearFacility(src, orgId, 'wardrobe') then return nil, characterId, 'You must remain at the wardrobe NPC.' end
    return member, characterId
end

local function wardrobeCatalog(orgId, sex)
    local rows = {}
    local ok = pcall(function()
        -- Organization assignment is the wardrobe access boundary. The
        -- clothing manager's publish flag only controls shop purchasing;
        -- legal duty wardrobes, like the Police wardrobe, must also show
        -- assigned rows carrying the SAVED/unpublished state.
        rows = exports['cm-items']:GetClothingCatalogRows({ gender = sex, shop = 'org_' .. orgId, includeDisabled = true }) or {}
    end)
    return ok and rows or nil
end

lib.callback.register('cm-law:server:wardrobeCatalog', function(src, orgId, requestedSex)
    orgId = validOrgId(orgId)
    local member, _, reason = wardrobeOfficer(src, orgId)
    if not member then return { ok = false, error = reason } end
    local sex = requestedSex == 'female' and 'female' or 'male'
    local rows = wardrobeCatalog(orgId, sex)
    if not rows then return { ok = false, error = 'Organization clothing catalog is unavailable.' } end
    return { ok = true, items = rows, organizationId = orgId, label = Config.Organizations[orgId].label }
end)

-- Read-only recovery contract used after character spawn, respawn and a
-- cm-law client/resource restart. The server derives character and active
-- organization from the session; clients cannot request another outfit.
lib.callback.register('cm-law:server:dutyUniform', function(src)
    local member = activeMemberForSource(src)
    if not member or member.suspended or not member.onDuty then return false end
    return activeUniform(member.characterId, member.organizationId) or false
end)

lib.callback.register('cm-law:server:finishWardrobeDuty', function(src, orgId, outfit, requestedSex)
    local now = GetGameTimer()
    if wardrobeRate[src] and now - wardrobeRate[src] < 1000 then return { ok = false, error = 'Please wait.' } end
    wardrobeRate[src] = now
    orgId = validOrgId(orgId)
    local member, characterId, reason = wardrobeOfficer(src, orgId)
    if not member then return { ok = false, error = reason } end
    if type(outfit) ~= 'table' or type(outfit.components) ~= 'table' or type(outfit.props) ~= 'table' then
        return { ok = false, error = 'Invalid uniform data.' }
    end
    local sex = requestedSex == 'female' and 'female' or 'male'
    local rows = wardrobeCatalog(orgId, sex)
    if not rows then return { ok = false, error = 'Organization clothing catalog is unavailable.' } end
    local missing = {}
    for _, required in ipairs({ { index = 11, label = 'outerwear' }, { index = 4, label = 'pants' }, { index = 6, label = 'shoes' } }) do
        local selected = outfit.components[tostring(required.index)] or outfit.components[required.index]
        local approved = false
        for _, row in ipairs(rows) do
            if tostring(row.componentType or 'component') == 'component'
                and tonumber(row.componentIndex) == required.index
                and tonumber(row.drawableId) == tonumber(selected and selected.drawable)
                and math.max(0, tonumber(row.textureId) or 0) == tonumber(selected and selected.texture) then approved = true; break end
        end
        if not approved then missing[#missing + 1] = required.label end
    end
    if #missing > 0 then return { ok = false, error = ('Select approved %s before starting duty.'):format(table.concat(missing, ', ')) } end
    local encoded = json.encode(outfit)
    if #encoded > 16000 then return { ok = false, error = 'Uniform data is too large.' } end
    local changed = MySQL.transaction.await({
        { query = 'UPDATE cm_legal_members SET on_duty = 1 WHERE organization_id = ? AND character_id = ?', values = { orgId, characterId } },
        { query = [[INSERT INTO cm_legal_active_outfits (organization_id, character_id, sex, outfit) VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE sex = VALUES(sex), outfit = VALUES(outfit), updated_at = NOW()]], values = { orgId, characterId, sex, encoded } },
    })
    if not changed then return { ok = false, error = 'Could not start duty. Please try again.' } end
    local storedDuty = dbBoolean(MySQL.scalar.await(
        'SELECT on_duty FROM cm_legal_members WHERE organization_id = ? AND character_id = ? LIMIT 1',
        { orgId, characterId }))
    if not storedDuty then return { ok = false, error = 'Uniform was accepted, but duty status did not save. Please try again.' } end
    logActivity(orgId, characterId, 'wardrobe_duty_started', {})
    syncCharacter(characterId)
    return { ok = true, message = ('You are now on duty with %s.'):format(Config.Organizations[orgId].shortLabel) }
end)

AddEventHandler('cm-playerdata:server:characterUnloaded', function(src)
    local member, characterId = activeMemberForSource(src)
    if member and characterId then endLawDuty(src, characterId, member.organizationId, 'character_unloaded') end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local member, characterId = activeMemberForSource(src)
    if member and characterId then endLawDuty(src, characterId, member.organizationId, 'disconnected') end
    wardrobeRate[src] = nil
end)

-- Death ends a legal shift. This is a local server lifecycle event owned by
-- cm-playerdata, not a network event a client can spoof. The inventory client
-- restores the character's real equipped clothing after respawn.
AddEventHandler('cm-playerdata:server:deathStateChanged', function(src, dead)
    if dead ~= true then return end
    src = tonumber(src)
    if not src then return end
    local member, characterId = activeMemberForSource(src)
    if not member or not characterId or not member.onDuty then return end
    endLawDuty(src, characterId, member.organizationId, 'death')
end)

local function setFacility(src, orgId, facilityType, reset)
    orgId, facilityType = validOrgId(orgId), validFacilityType(facilityType)
    if not orgId or not facilityType then return false, 'Unknown organization facility.' end
    local actor = select(1, activeMemberForSource(src))
    if not adminAllowed(src) and not (actor and actor.organizationId == orgId and canManage(actor)) then
        return false, 'Permission denied.'
    end
    local actorCid = characterIdFor(src)
    if reset == true then
        MySQL.update.await('DELETE FROM cm_legal_facilities WHERE organization_id = ? AND facility_type = ?', { orgId, facilityType })
        logActivity(orgId, actorCid, 'facility_reset', { facilityType = facilityType })
        TriggerClientEvent('cm-law:client:facilitiesChanged', -1)
        return true, ('%s reset.'):format(Config.FacilityTypes[facilityType].label)
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Player entity is unavailable.' end
    local coords = GetEntityCoords(ped)
    local heading, bucket = 0.0, GetPlayerRoutingBucket(src)
    pcall(function() heading = tonumber(GetEntityHeading(ped)) or 0.0 end)
    MySQL.insert.await([[INSERT INTO cm_legal_facilities
        (organization_id, facility_type, x, y, z, heading, routing_bucket, updated_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y),
        z = VALUES(z), heading = VALUES(heading), routing_bucket = VALUES(routing_bucket), updated_by = VALUES(updated_by)]],
        { orgId, facilityType, coords.x, coords.y, coords.z, heading, bucket, actorCid })
    local saved = MySQL.single.await([[SELECT x, y, z, heading, routing_bucket
        FROM cm_legal_facilities WHERE organization_id = ? AND facility_type = ? LIMIT 1]],
        { orgId, facilityType })
    if not saved then return false, 'Facility location could not be verified after saving.' end
    logActivity(orgId, actorCid, 'facility_set', { facilityType = facilityType, bucket = bucket })
    TriggerClientEvent('cm-law:client:facilitiesChanged', -1)
    return true, ('%s set at your current location.'):format(Config.FacilityTypes[facilityType].label)
end

exports('AdminSetFacility', function(src, orgId, facilityType, reset)
    if facilityType == 'jail_spawn' or facilityType == 'jail_release' or facilityType == 'jail_spawns' then
        if type(LawAdminSetSharedJail) ~= 'function' then return false, 'Shared jail configuration is still loading.' end
        return LawAdminSetSharedJail(tonumber(src), facilityType, reset == true)
    end
    return setFacility(tonumber(src), orgId, facilityType, reset == true)
end)

exports('AdminGetCapabilities', function(src, orgId)
    src, orgId = tonumber(src), validOrgId(orgId)
    if not adminAllowed(src) then return { ok = false, error = 'Permission denied.' } end
    if not orgId then return { ok = false, error = 'Unknown organization.' } end
    local items = {}
    for _, capability in ipairs(Config.Capabilities or {}) do
        items[#items + 1] = { id = capability, enabled = LawCapabilityEnabled(orgId, capability) }
    end
    return { ok = true, organizationId = orgId, items = items }
end)

exports('AdminConfigureCapability', function(src, orgId, capability, enabled)
    src, orgId, capability = tonumber(src), validOrgId(orgId), tostring(capability or '')
    if not adminAllowed(src) then return false, 'Permission denied.' end
    local known = false
    for _, value in ipairs(Config.Capabilities or {}) do
        if value == capability then known = true; break end
    end
    if not orgId or not known then return false, 'Unknown organization capability.' end
    local actorCid = characterIdFor(src)
    MySQL.insert.await([[INSERT INTO cm_legal_capabilities
        (organization_id, capability, enabled, updated_by) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE enabled = VALUES(enabled), updated_by = VALUES(updated_by)]],
        { orgId, capability, enabled == true and 1 or 0, actorCid })
    CapabilityCache[orgId] = CapabilityCache[orgId] or {}
    CapabilityCache[orgId][capability] = enabled == true
    logActivity(orgId, actorCid, 'admin_capability_configured', { capability = capability, enabled = enabled == true })
    syncOrganization(orgId)
    return true, 'Organization capability saved.'
end)

lib.callback.register('cm-law:server:facilities', function()
    if not ready then return {} end
    local list = {}
    for orgId, org in pairs(Config.Organizations) do
        for facilityType, location in pairs(facilityRows(orgId)) do
            local typeConfig = Config.FacilityTypes[facilityType]
            if typeConfig then
                list[#list + 1] = {
                    organizationId = orgId, organizationLabel = org.label, shortLabel = org.shortLabel,
                    facilityType = facilityType, label = typeConfig.label,
                    name = facilityType == 'front_desk' and org.serviceNpc.name or (org.shortLabel .. ' ' .. typeConfig.label),
                    role = facilityType == 'front_desk' and org.serviceNpc.role or typeConfig.role,
                    model = org.serviceNpc.model, location = location,
                }
            end
        end
    end
    return list
end)

lib.callback.register('cm-law:server:facilityAccess', function(src, orgId, facilityType)
    local allowed, _, reason = facilityAccess(src, orgId, facilityType)
    return allowed ~= nil, reason
end)

lib.callback.register('cm-law:server:useFacility', function(src, orgId, facilityType)
    orgId, facilityType = validOrgId(orgId), validFacilityType(facilityType)
    if not orgId or not facilityType then return { ok = false, error = 'Unknown organization facility.' } end
    local member, characterId, reason = facilityAccess(src, orgId, facilityType)
    if not member then return { ok = false, error = reason } end
    if not nearFacility(src, orgId, facilityType) then return { ok = false, error = 'You are not at that facility NPC.' } end
    local org = Config.Organizations[orgId]
    if facilityType == 'front_desk' then
        return { ok = true, action = 'frontdesk', organizationId = orgId, label = org.label }
    end
    if facilityType == 'wardrobe' then
        return { ok = true, action = 'wardrobe', organizationId = orgId, label = org.label .. ' Wardrobe' }
    end
    if facilityType == 'fleet' then
        return { ok = true, action = 'fleet', organizationId = orgId, label = org.label .. ' Fleet' }
    end
    if facilityType == 'armory' then
        return { ok = true, action = 'armory', organizationId = orgId, label = org.label .. ' Armory' }
    end
    if facilityType == 'intake' then
        return { ok = true, message = 'Bring a cuffed suspect to this desk, open their G interaction, and select Book Suspect.' }
    end
    if GetResourceState('cm-inventory') ~= 'started' then return { ok = false, error = 'Inventory is unavailable.' } end
    local ownerType = facilityType == 'evidence' and 'legal_org_evidence' or 'legal_org_storage'
    local called, opened, openReason = pcall(function()
        return exports['cm-inventory']:OpenExternalInventory(src, {
            ownerType = ownerType, ownerId = orgId, slots = facilityType == 'evidence' and 100 or 30, displaySlots = 30,
            slotPrefix = orgId .. '-', label = org.label .. ' ' .. Config.FacilityTypes[facilityType].label,
            subtitle = 'Organization-only department container', kind = ownerType, icon = Config.FacilityTypes[facilityType].icon,
            canDeposit = true, canWithdraw = true, resource = RESOURCE,
        })
    end)
    if not called or opened ~= true then return { ok = false, error = openReason or 'Could not open organization inventory.' } end
    logActivity(orgId, characterId, 'facility_opened', { facilityType = facilityType })
    return { ok = true, action = 'inventory', message = Config.FacilityTypes[facilityType].label .. ' opened.' }
end)

lib.callback.register('cm-law:server:setFacility', function(src, orgId, facilityType, reset)
    local ok, message = setFacility(src, orgId, facilityType, reset == true)
    return { ok = ok, message = ok and message or nil, error = not ok and message or nil }
end)

-- Revoke organization containers if a client walks away, changes routing
-- bucket, goes off duty, is suspended, or loses membership while it is open.
CreateThread(function()
    while true do
        Wait(1000)
        if ready and GetResourceState('cm-inventory') == 'started' then
            for _, playerId in ipairs(GetPlayers()) do
                local src = tonumber(playerId)
                local ok, context = pcall(function() return exports['cm-inventory']:GetOpenExternalInventory(src) end)
                if ok and type(context) == 'table'
                    and (context.ownerType == 'legal_org_storage' or context.ownerType == 'legal_org_evidence') then
                    local orgId = validOrgId(context.ownerId)
                    local facilityType = context.ownerType == 'legal_org_evidence' and 'evidence' or 'storage'
                    local allowed = orgId and select(1, facilityAccess(src, orgId, facilityType))
                    if not allowed or not nearFacility(src, orgId, facilityType) then
                        pcall(function() exports['cm-inventory']:CloseExternalInventory(src) end)
                    end
                end
            end
        end
    end
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    local characterId = type(data) == 'table' and (data.characterId or data.id) or characterIdFor(src)
    SetTimeout(500, function() syncCharacter(characterId or characterIdFor(src)) end)
end)

-- Registered via TriggerEvent (not the RegisterInteractionAction export) so
-- this file doesn't need to care whether cm-playerdata is up yet -- same
-- convention cm-police/server/main.lua uses for its own G-menu actions.
local function registerGMenu()
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return end
    -- Membership actions -- invite/promote/demote only, no kick/remove in
    -- the G-menu (removal stays an F9 Staffing-tab-only action). Handled
    -- below, not in server/cuffs.lua or server/booking.lua.
    for _, action in ipairs({ 'law_invite', 'law_promote', 'law_demote' }) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', { id = action, event = 'cm-law:server:gMenuAction', resource = RESOURCE, allowDeadTarget = false })
    end
    -- Cuffing must work on a suspect an officer just knocked unconscious, so
    -- allowDeadTarget = true. Handled in server/cuffs.lua, not here -- this
    -- function only owns registration.
    for _, action in ipairs({ 'law_cuff', 'law_uncuff', 'law_escort_grab', 'law_escort_release', 'law_put_in_vehicle' }) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', { id = action, event = 'cm-law:server:cuffAction', resource = RESOURCE, allowDeadTarget = true })
    end
    -- allowVehicleTarget = true: this action's entire purpose is acting on a
    -- suspect who IS currently seated in a vehicle -- cm-playerdata's generic
    -- "use the vehicle interaction menu instead" block would otherwise
    -- reject it unconditionally, making the action permanently unusable.
    TriggerEvent('cm-playerdata:server:registerInteractionAction', { id = 'law_take_out_vehicle', event = 'cm-law:server:cuffAction', resource = RESOURCE, allowDeadTarget = true, allowVehicleTarget = true })
    -- Booking actions, same allowDeadTarget = true reasoning as cuffing -- an
    -- officer must be able to book a suspect still unconscious from the
    -- arrest. Handled in server/booking.lua.
    for _, action in ipairs(LawBookingActionIds()) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', { id = action, event = 'cm-law:server:bookingAction', resource = RESOURCE, allowDeadTarget = true })
    end
end

-- Promote/demote via the G-menu: moves exactly one non-leader rank up or
-- down, independent of the F9 Staffing tab's own explicit-rank-picker flow
-- (staffAction's 'rank' action) -- same separation cm-police keeps between
-- its G-menu's targetChange and its own F7 rank editor.
local function orgTargetChange(actorCid, targetCid, orgId, direction)
    if tostring(actorCid) == tostring(targetCid) then return false, 'You cannot change your own rank.' end
    local actor, target = memberFor(actorCid, orgId), memberFor(targetCid, orgId)
    if not actor or not target then return false, 'That character is not a member of this organization.' end
    if target.isLeader then return false, 'The organization leader rank is admin-managed.' end
    if actor.tier <= target.tier then return false, 'You can only manage lower ranks.' end
    local op = direction == 'up' and '>' or '<'
    local order = direction == 'up' and 'ASC' or 'DESC'
    local rank = MySQL.single.await(('SELECT id, name, tier FROM cm_legal_ranks WHERE organization_id = ? AND is_leader = 0 AND tier %s ? AND tier < ? ORDER BY tier %s LIMIT 1'):format(op, order),
        { orgId, target.tier, actor.tier })
    if not rank then return false, direction == 'up' and 'No available promotion rank.' or 'No available demotion rank.' end
    MySQL.update.await('UPDATE cm_legal_members SET rank_id = ? WHERE organization_id = ? AND character_id = ?', { rank.id, orgId, targetCid })
    syncCharacter(targetCid)
    logActivity(orgId, actorCid, direction == 'up' and 'member_promoted' or 'member_demoted', { targetCid = targetCid, rank = rank.name })
    return true, ('%s is now %s.'):format(nameFor(targetCid), rank.name)
end

AddEventHandler('cm-law:server:gMenuAction', function(src, targetSrc, action, _, context)
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    if not LawIsReady() or not src or not targetSrc or src == targetSrc then return end
    if not rateLimit(src, 'law_gmenu', 900) then return end
    local actor, actorCid = activeMemberForSource(src)
    local targetCid = characterIdFor(targetSrc)
    if not actor or not targetCid or actorCid == targetCid then return end
    local orgId = actor.organizationId
    local function notifySrc(message, kind) TriggerClientEvent('cm-playerdata:client:interactionNotify', src, tostring(message), kind or 'inform') end

    if action == 'law_invite' then
        if not canManage(actor) then return notifySrc('Your rank cannot invite members.', 'error') end
        if memberFor(targetCid, orgId) then return notifySrc('That character is already a member.', 'error') end
        local rival = exports[Config.AdminResource]:FindRivalMembership(orgId, targetCid)
        if rival then return notifySrc(('That character already belongs to %s.'):format(rival.orgLabel), 'error') end
        local rank = MySQL.single.await('SELECT id, name FROM cm_legal_ranks WHERE organization_id = ? AND is_leader = 0 ORDER BY tier ASC LIMIT 1', { orgId })
        if not rank then return notifySrc('No recruit rank is configured.', 'error') end
        MySQL.insert.await('INSERT INTO cm_legal_members (organization_id, character_id, rank_id) VALUES (?, ?, ?)', { orgId, targetCid, rank.id })
        syncCharacter(targetCid)
        logActivity(orgId, actorCid, 'member_hire', { targetCid = targetCid, rankId = rank.id })
        TriggerEvent('cm-admin:server:addLog', src, 'legal_org_member_hire', { category = 'orgs', organizationId = orgId, characterId = targetCid })
        return notifySrc(('%s added as %s.'):format(nameFor(targetCid), rank.name), 'success')
    end

    if not canManage(actor) then return notifySrc('Your rank cannot manage members.', 'error') end
    local ok, message
    if action == 'law_promote' then ok, message = orgTargetChange(actorCid, targetCid, orgId, 'up')
    elseif action == 'law_demote' then ok, message = orgTargetChange(actorCid, targetCid, orgId, 'down')
    end
    notifySrc(message or 'Action failed.', ok and 'success' or 'error')
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == Config.PlayerDataResource then Wait(500); registerGMenu() end
end)

CreateThread(function()
    local ok, err = pcall(ensureSchema)
    if not ok then
        print(('[cm-law] schema initialization failed: %s'):format(tostring(err)))
        return
    end
    ready = true
    -- Remove snapshots that cannot represent an active shift. This makes
    -- upgrades and interrupted duty transitions self-reconciling.
    MySQL.update.await([[DELETE a FROM cm_legal_active_outfits a
        LEFT JOIN cm_legal_members m ON m.organization_id = a.organization_id AND m.character_id = a.character_id
        WHERE m.character_id IS NULL OR m.on_duty = 0 OR m.suspended_until IS NOT NULL]])
    registerGMenu()
    for orgId, org in pairs(Config.Organizations) do
        exports[Config.AdminResource]:RegisterOrganization({
            id = orgId, label = org.label, resource = RESOURCE, icon = org.icon,
            canRemoveLeader = true, canManageFacilities = true, canManageArmory = true,
            canManageCapabilities = true,
            canManageFleet = true,
            facilityTypes = {
                { id = 'front_desk', label = 'Front desk NPC' },
                { id = 'wardrobe', label = 'Wardrobe' },
                { id = 'armory', label = 'Armory' },
                { id = 'storage', label = 'Storage' },
                { id = 'evidence', label = 'Evidence' },
                { id = 'fleet', label = 'Fleet' },
                { id = 'intake', label = 'Prison intake' },
                { id = 'jail_spawn', label = 'Shared jail: add spawn' },
                { id = 'jail_release', label = 'Shared jail: release point' },
                { id = 'jail_spawns', label = 'Shared jail: all spawns' },
            },
        })
    end
    print('[cm-law] SAHP, Sheriff, FIB, and Army organization foundations are ready')
    for _, src in ipairs(GetPlayers()) do
        local characterId = characterIdFor(src)
        if characterId then syncCharacter(characterId) end
    end
end)
