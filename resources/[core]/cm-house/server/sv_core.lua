-- ============================================================
--  cm-house | sv_core.lua
--  Cache, permission resolution, logging. Every other server file
--  goes through this. Nothing here trusts the client.
-- ============================================================

Houses   = {}   -- [houseId]  = houseRecord
Families = {}   -- [familyId] = { id, name, owner_cid, house_id, ranks = {[rankId]=rank}, members = {[cid]={cid,rank_id}} }

MemberFamily = {}  -- [cid] -> familyId   (reverse index, one family per player)
OwnerHouses  = {}  -- [cid] -> { houseId, ... }

-- ------------------------------------------------------------
--  Helpers
-- ------------------------------------------------------------
local function jdec(v, fallback)
    if v == nil or v == '' then return fallback end
    if type(v) == 'table' then return v end
    local ok, out = pcall(json.decode, v)
    if not ok or out == nil then return fallback end
    return out
end

-- GetCid / GetSrcByCid / GetCharName / TakeMoney / GiveMoney all live in
-- sv_compat.lua, which resolves cm-playerdata's real export names at boot.

-- ------------------------------------------------------------
--  Logging  -- fire and forget, never blocks a gameplay path
-- ------------------------------------------------------------
-- house_id, family_id, cid and detail are all routinely nil. A nil in a Lua
-- table literal truncates the array, so every optional value goes through
-- SqlNull or the placeholder count silently stops matching.
function LogHouse(houseId, familyId, cid, action, detail)
    MySQL.insert('INSERT INTO cm_house_logs (house_id, family_id, cid, action, detail) VALUES (?, ?, ?, ?, ?)', {
        [1] = SqlNull(houseId),
        [2] = SqlNull(familyId),
        [3] = SqlNull(cid),
        [4] = action,
        [5] = detail and json.encode(detail) or false,
    })

    -- Family-house activity is mirrored into cm-family's durable audit table.
    -- The export is server-only and allowlisted by cm-family; no client payload
    -- can choose a family id or forge an activity row.
    local linkedFamilyId = tonumber(familyId)
    if linkedFamilyId and GetResourceState('cm-family') == 'started' then
        local payload = type(detail) == 'table' and detail or {}
        CreateThread(function()
            local ok, logged, why = pcall(function()
                return exports['cm-family']:WriteFamilyActivity(
                    linkedFamilyId, cid, tostring(action), payload, {
                        houseId = tonumber(houseId),
                        entityType = 'house',
                        entityId = houseId and tostring(houseId) or nil,
                    })
            end)
            if not ok or logged ~= true then
                print(('[cm-house] family activity audit failed family=%s action=%s: %s')
                    :format(tostring(linkedFamilyId), tostring(action), tostring(why or logged)))
            end
        end)
    end
end
exports('LogHouse', LogHouse)

-- ------------------------------------------------------------
--  Load
-- ------------------------------------------------------------
local function indexHouse(h)
    -- House names are intentionally generic. Keep legacy database text intact
    -- for rollback, but never expose it as the active runtime identity.
    h.label = 'House'
    Houses[h.id] = h
    if h.owner_cid then
        OwnerHouses[h.owner_cid] = OwnerHouses[h.owner_cid] or {}
        OwnerHouses[h.owner_cid][#OwnerHouses[h.owner_cid] + 1] = h.id
    end
end

function LoadHouses()
    Houses, OwnerHouses = {}, {}

    local rows = MySQL.query.await('SELECT * FROM cm_houses') or {}
    for _, r in ipairs(rows) do
        -- Normalize every numeric DB field before any comparison or table-key
        -- lookup. This supports both normal INT results and legacy VARCHAR
        -- columns that return values such as "0" or "123".
        local rawOwner = r.owner_cid
        r.id                   = DbPositiveInteger(r.id)
        r.owner_cid            = DbPositiveInteger(r.owner_cid)
        r.family_id            = DbPositiveInteger(r.family_id)
        r.created_by           = DbPositiveInteger(r.created_by)
        r.interior_template_id = DbPositiveInteger(r.interior_template_id)
        r.garage_template_id   = DbPositiveInteger(r.garage_template_id)
        r.garage_slots         = math.max(0, DbInteger(r.garage_slots, 0))
        r.wardrobe_count       = math.max(0, DbInteger(r.wardrobe_count, 0))
        r.star_rating          = math.max(0, DbInteger(r.star_rating, 0))
        r.price                = math.max(0, DbInteger(r.price, 0))
        r.gov_value            = math.max(0, DbInteger(r.gov_value, 0))
        r.insurance            = math.max(0, DbInteger(r.insurance, 0))
        r.daily_cost           = math.max(0, DbInteger(r.daily_cost, 0))

        r.door_coords    = jdec(r.door_coords)
        r.garage_coords  = jdec(r.garage_coords, nil)
        r.helipad_coords = jdec(r.helipad_coords, nil)
        r.vehicle_exit   = jdec(r.vehicle_exit, nil)
        r.photo_cam      = jdec(r.photo_cam, nil)
        r.has_garden     = DbBool(r.has_garden)
        r.has_pool       = DbBool(r.has_pool)
        r.has_helipad    = DbBool(r.has_helipad)
        r.locked         = DbBool(r.locked)
        r.for_sale       = DbBool(r.for_sale)
        r.family_eligible = DbBool(r.family_eligible)

        if not r.id then
            print(('[cm-house] ^1Skipped a house row with invalid id: %s^7'):format(tostring(r.id)))
        else
            if rawOwner ~= nil and rawOwner ~= '' and r.owner_cid == nil
                and DbInteger(rawOwner, nil) ~= 0 then
                print(('[cm-house] ^3House %s has invalid owner_cid %q; treating it as unowned.^7')
                    :format(tostring(r.id), tostring(rawOwner)))
            end
            indexHouse(r)
        end
    end

    -- Wardrobes are no longer per-house: they live on the interior template.

    -- Garage contents are NOT cached. cm-vehicles owns whether a car is
    -- stored, and caching that here would be a second opinion -- which is
    -- exactly how a vehicle ends up existing twice. Read it live instead.

    -- Keys and guest grants now live in cm_house_access, loaded by sv_access.

    print(('[cm-house] loaded %d houses'):format(#rows))
end

function LoadFamilies()
    Families, MemberFamily = {}, {}

    local frows = MySQL.query.await('SELECT * FROM cm_families') or {}
    for _, f in ipairs(frows) do
        local familyId = tonumber(f.id) or f.id
        f.id = familyId
        f.house_id = tonumber(f.house_id) or f.house_id
        f.ranks = {}
        f.members = {}
        Families[familyId] = f
    end

    local rrows = MySQL.query.await('SELECT * FROM cm_family_ranks') or {}
    for _, r in ipairs(rrows) do
        local familyId = tonumber(r.family_id) or r.family_id
        local fam = Families[familyId]
        if fam then
            r.id = tonumber(r.id) or r.id
            r.family_id = familyId
            r.tier = tonumber(r.tier or r.grade) or 0
            local fromPermissions = jdec(r.permissions, {})
            local fromPerms = jdec(r.perms, {})
            r.perms = {}
            for key, enabled in pairs(fromPermissions or {}) do
                if enabled == true or enabled == 1 then r.perms[tostring(key)] = true end
            end
            for key, enabled in pairs(fromPerms or {}) do
                if enabled == true or enabled == 1 then r.perms[tostring(key)] = true end
            end
            fam.ranks[r.id] = r
        end
    end

    local mrows = MySQL.query.await('SELECT * FROM cm_family_members') or {}
    for _, m in ipairs(mrows) do
        local familyId = tonumber(m.family_id) or m.family_id
        local cid = m.character_id or m.cid or m.citizenid
        local fam = Families[familyId]
        if fam and cid ~= nil then
            m.family_id = familyId
            m.rank_id = tonumber(m.rank_id) or m.rank_id
            m.cid = tonumber(cid) or tostring(cid)
            fam.members[m.cid] = m
            MemberFamily[m.cid] = familyId
            MemberFamily[tostring(m.cid)] = familyId
        end
    end

    print(('[cm-house] loaded %d families (legacy columns normalized)'):format(#frows))
end

-- ------------------------------------------------------------
--  Permission resolution
--  THE authority. Client-side checks are cosmetic; this is the gate.
-- ------------------------------------------------------------

function GetFamilyOf(cid)
    local fid = MemberFamily[cid]
    return fid and Families[fid] or nil
end

function GetRankOf(cid)
    local fam = GetFamilyOf(cid)
    if not fam then return nil, nil end
    local m = fam.members[cid]
    if not m then return nil, nil end
    return fam.ranks[m.rank_id], fam
end

--- Is this player the outright owner of the house?
function IsHouseOwner(cid, house)
    return house.owner_cid ~= nil and tonumber(house.owner_cid) == tonumber(cid)
end

-- Permission resolution now lives in sv_access.lua as CanAccessProperty().
-- Spec 16.12: one centralized action check, not owner-only conditions
-- scattered through every file. cm-family hooks into that ONE function.

-- ------------------------------------------------------------
--  Family display bridge
--
--  cm-family owns live family membership/ranks. The legacy local family tables
--  remain readable for old data, but UI display prefers explicit cm-family
--  imports and fails safely when that resource is unavailable.
-- ------------------------------------------------------------
function GetFamilyDisplay(familyId)
    familyId = tonumber(familyId)
    if not familyId then return nil end

    local resource = tostring(Config.Family and Config.Family.resource or 'cm-family')
    if GetResourceState(resource) == 'started' then
        local exportName = tostring(Config.Family and Config.Family.getFamilyExport or 'GetFamilyById')
        local ok, family = pcall(function()
            return exports[resource][exportName](familyId)
        end)
        if ok and type(family) == 'table' then return family end
    end
    return Families[familyId]
end
exports('GetFamilyDisplay', GetFamilyDisplay)


function GetFamilyForCharacter(cid)
    cid = tonumber(cid) or cid
    if not cid then return nil end
    local resource = tostring(Config.Family and Config.Family.resource or 'cm-family')
    if GetResourceState(resource) == 'started' then
        local exportName = tostring(Config.Family and Config.Family.getFamilyForCharacterExport or 'GetFamilyForCharacter')
        local ok, family = pcall(function()
            return exports[resource][exportName](cid)
        end)
        if ok and type(family) == 'table' then return family end
    end
    return GetFamilyOf(cid)
end
exports('GetFamilyForCharacter', GetFamilyForCharacter)

-- ------------------------------------------------------------
--  Status / view models
-- ------------------------------------------------------------
function DaysRemaining(house)
    if not house.paid_until then return -math.huge end
    local y, m, d = tostring(house.paid_until):match('(%d+)-(%d+)-(%d+)')
    if not y then return -math.huge end
    local paid = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    return math.floor(os.difftime(paid, os.time()) / 86400)
end

--- Everything the door menu needs and nothing it does not. Buttons are
--- resolved HERE, per requester, so a tampered NUI still cannot act.
function BuildDoorView(cid, house)
    local days  = DaysRemaining(house)

    -- owner_cid = 0 is a legacy "nobody". Only a positive id is a real owner.
    local ownerCid = (house.owner_cid and house.owner_cid > 0) and house.owner_cid or nil
    local unowned  = ownerCid == nil
    local listed   = unowned and (house.for_sale == true or Config.Purchase.autoListUnowned)

    local id = house.id
    local tpl = InteriorTemplates[house.interior_template_id]
    local g   = house.garage_template_id and GarageTemplates[house.garage_template_id]

    return {
        id           = id,
        houseNumber  = house.house_number,
        label        = house.label,
        houseType    = house.house_type,

        -- The photo is a local NUI asset written by screenshot-basic. The
        -- framing is retained for admin retakes and future real-estate views.
        image        = ValidPhotoUrl(house.image_url) and house.image_url or nil,
        photoCam     = house.photo_cam,

        ownerName    = ownerCid and GetCharName(ownerCid) or nil,
        isOwner      = ownerCid ~= nil and ownerCid == cid,
        isUnowned    = unowned,
        familyName   = (function()
            local family = house.family_id and GetFamilyDisplay(house.family_id) or nil
            return family and (family.name or family.label) or nil
        end)(),
        familyEligible = house.family_eligible,

        insurance    = house.insurance,
        price        = house.price,
        govValue     = house.gov_value,
        dailyCost    = house.daily_cost,
        paidUntil    = house.paid_until,
        daysRemaining = days == -math.huge and nil or days,
        stars        = unowned and 0 or Config.StarsFor(days),

        locked       = house.locked,
        forSale      = listed,
        interior     = tpl and tpl.label or nil,
        garageLabel  = g and g.label or nil,
        garageCapacity = g and g.capacity or 0,
        hasGarage    = g ~= nil,
        hasHelipad   = house.helipad_coords ~= nil,

        can = {
            lock   = CanAccessProperty(cid, id, ACTIONS.HOUSE_LOCK, false),
            enter  = CanAccessProperty(cid, id, ACTIONS.HOUSE_ENTER, false),
            garage = g ~= nil and CanAccessProperty(cid, id, ACTIONS.GARAGE_ENTER, false),
            sell   = CanAccessProperty(cid, id, ACTIONS.HOUSE_SELL, false),
            activity = CanAccessProperty(cid, id, ACTIONS.HOUSE_VIEW_LOGS, false),
            buy    = listed,
        },
    }
end

lib.callback.register('cm-house:server:getHouseActivity', function(src, houseId)
    local cid = GetCid(src)
    houseId = tonumber(houseId)
    if not cid or not houseId or not Houses[houseId] then return nil, 'That property does not exist.' end
    local allowed, reason = CanAccessProperty(cid, houseId, ACTIONS.HOUSE_VIEW_LOGS, false)
    if not allowed then return nil, reason end
    local rows = MySQL.query.await([[
        SELECT id, cid, action, detail, created_at
        FROM cm_house_logs
        WHERE house_id = ? AND (
            action LIKE 'storage_%' OR action LIKE 'weapon_storage_%'
            OR action LIKE 'garage_%' OR action LIKE 'heli_%'
        )
        ORDER BY id DESC LIMIT ?
    ]], { houseId, math.max(1, math.min(100, tonumber(Config.MaxLogRows) or 100)) }) or {}
    for _, row in ipairs(rows) do
        row.actorName = row.cid and GetCharName(row.cid) or 'System'
        row.cid = row.cid and tostring(row.cid) or nil
    end
    return rows
end)

lib.callback.register('cm-house:server:getDoorView', function(src, houseId)
    houseId = tonumber(houseId)
    local cid   = GetCid(src)
    local house = houseId and Houses[houseId]
    if not house then return nil end
    return BuildDoorView(cid, house)
end)

-- ------------------------------------------------------------
--  Current-version schema repair
--
--  The SQL migration files remain the canonical install path, but local
--  development databases are frequently upgraded out of order. Repair the
--  additive v1.5/v1.6 columns and tables before the strict schema check so a
--  missing migration cannot crash the admin/template callbacks later.
-- ------------------------------------------------------------
local function schemaTableExists(tableName)
    local found = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
    ]], { tableName })
    return (tonumber(found) or 0) > 0
end

local function schemaColumnExists(tableName, columnName)
    local found = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { tableName, columnName })
    return (tonumber(found) or 0) > 0
end

local function runSchemaStatement(label, sql, params)
    local ok, result = pcall(function()
        return MySQL.query.await(sql, params or {})
    end)
    if not ok then
        print(('[cm-house] ^1Schema repair failed (%s): %s^7'):format(label, tostring(result)))
        return false
    end
    return true
end

function EnsureCurrentHouseSchema()
    local changed = false

    if schemaTableExists('cm_house_interior_templates') then
        if not schemaColumnExists('cm_house_interior_templates', 'weapon_storages') then
            if runSchemaStatement('weapon_storages column', [[
                ALTER TABLE `cm_house_interior_templates`
                ADD COLUMN `weapon_storages` JSON NULL AFTER `wardrobes`
            ]]) then
                changed = true
                print('[cm-house] ^3Auto-added missing interior weapon_storages column.^7')
            end
        end

        if schemaColumnExists('cm_house_interior_templates', 'weapon_storages') then
            runSchemaStatement('migrate wardrobe points to weapon storage', [[
                UPDATE `cm_house_interior_templates`
                SET `weapon_storages` = `wardrobes`
                WHERE (`weapon_storages` IS NULL OR JSON_LENGTH(`weapon_storages`) = 0)
                  AND `wardrobes` IS NOT NULL
            ]])
        end
    end

    if schemaTableExists('cm_house_garage_templates') then
        local garageColumns = {
            vehicle_exits = 'JSON NULL AFTER `vehicle_exit`',
        }
        for columnName, definition in pairs(garageColumns) do
            if not schemaColumnExists('cm_house_garage_templates', columnName) then
                if runSchemaStatement(columnName .. ' column',
                    ('ALTER TABLE `cm_house_garage_templates` ADD COLUMN `%s` %s')
                        :format(columnName, definition)) then
                    changed = true
                    print(('[cm-house] ^3Auto-added missing garage column %s.^7'):format(columnName))
                end
            end
        end

        if schemaColumnExists('cm_house_garage_templates', 'vehicle_exits') then
            runSchemaStatement('migrate single garage exits', [[
                UPDATE `cm_house_garage_templates`
                SET `vehicle_exits` = JSON_ARRAY(`vehicle_exit`)
                WHERE (`vehicle_exits` IS NULL OR JSON_LENGTH(`vehicle_exits`) = 0)
                  AND `vehicle_exit` IS NOT NULL
            ]])
        end
    end

    if schemaTableExists('cm_houses') then
        if runSchemaStatement('weapon transfer table', [[
            CREATE TABLE IF NOT EXISTS `cm_house_weapon_transfers` (
              `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
              `house_id` INT NOT NULL,
              `storage_index` INT NOT NULL,
              `character_id` VARCHAR(64) NOT NULL,
              `direction` VARCHAR(16) NOT NULL,
              `item_name` VARCHAR(100) NOT NULL,
              `quantity` INT NOT NULL DEFAULT 1,
              `status` VARCHAR(24) NOT NULL DEFAULT 'completed',
              `details` JSON NULL,
              `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
              INDEX `idx_house_weapon_transfer_house` (`house_id`, `created_at`),
              INDEX `idx_house_weapon_transfer_character` (`character_id`, `created_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]]) then
            -- CREATE IF NOT EXISTS is intentionally harmless on every boot.
        end
    end

    return changed
end

-- ------------------------------------------------------------
--  Schema check
-- ------------------------------------------------------------
local REQUIRED_COLUMNS = {
    cm_houses = { 'interior_template_id', 'garage_template_id',
                  'vehicle_exit', 'family_eligible', 'status',
                  'has_garden', 'has_pool', 'has_helipad', 'star_rating', 'photo_cam' },
    cm_house_interior_templates = { 'signature', 'weapon_storages' },
    cm_house_garage_templates = { 'vehicle_exits' },
}
local REQUIRED_TABLES = {
    'cm_house_interior_templates',
    'cm_house_garage_templates',
    'cm_house_garage_slots',
    'cm_house_vehicle_slots',
    'cm_house_access',
    'cm_house_pricing',
    'cm_house_garage_sizes',
    'cm_house_purchase_locks',
    'cm_house_weapon_transfers',
}

function CheckSchema()
    local missing = {}

    for tbl, cols in pairs(REQUIRED_COLUMNS) do
        for _, col in ipairs(cols) do
            local found = MySQL.scalar.await([[
                SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
            ]], { tbl, col })
            if (tonumber(found) or 0) == 0 then
                missing[#missing + 1] = ('%s.%s'):format(tbl, col)
            end
        end
    end

    for _, tbl in ipairs(REQUIRED_TABLES) do
        local found = MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
        ]], { tbl })
        if (tonumber(found) or 0) == 0 then
            missing[#missing + 1] = ('table %s'):format(tbl)
        end
    end

    if #missing > 0 then
        print('[cm-house] ^1----------------------------------------------^7')
        print('[cm-house] ^1DATABASE IS OUT OF DATE^7')
        print(('[cm-house] ^1Missing: %s^7'):format(table.concat(missing, ', ')))
        print('[cm-house] ^3Run all SQL migrations in order through sql/016_deleted_house_vehicle_recovery_v1.7.1.sql.^7')
        print('[cm-house] ^1----------------------------------------------^7')
        return false
    end

    return true
end

-- ------------------------------------------------------------
--  Boot
-- ------------------------------------------------------------
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end

    -- Fail loudly at boot rather than silently at first use.
    local deps = { 'oxmysql', 'ox_lib', 'cm-playerdata', 'cm-inventory', 'cm-vehicles' }
    local missing = {}
    for _, d in ipairs(deps) do
        if GetResourceState(d) ~= 'started' then
            missing[#missing + 1] = ('%s (%s)'):format(d, GetResourceState(d))
        end
    end
    if #missing > 0 then
        print('[cm-house] ^1DEPENDENCY NOT STARTED: ' .. table.concat(missing, ', ') .. '^7')
    end

    -- sv_compat must have finished loading, or every helper below is nil.
    if not CompatLoaded then
        print('[cm-house] ^1sv_compat.lua failed to load. Nothing will work.^7')
        print('[cm-house] ^1Scroll up for the real error -- it is above this line.^7')
        return
    end

    CheckPlayerData()

    -- Phase 1 security tables are safe to auto-create before schema checks.
    if EnsureHouseSecurityTables then EnsureHouseSecurityTables() end

    -- Repair additive v1.5/v1.6 schema pieces before the strict check. This
    -- prevents out-of-order local migrations from crashing admin/template use.
    if Config.AutoRepairSchema ~= false then EnsureCurrentHouseSchema() end

    -- CREATE TABLE IF NOT EXISTS silently does nothing when the table already
    -- exists, so a new column in 001 never lands on an existing database. Say
    -- so plainly here rather than dying halfway through an INSERT later.
    if not CheckSchema() then return end

    LoadPricing()     -- features -> garage size, stars, price
    LoadTemplates()   -- must precede LoadHouses: houses point at these
    LoadHouses()
    LoadAccess()
    LoadFamilies()

    -- Older builds could delete a property while cars still pointed at its
    -- garage. Release those cars first so they can be called again.
    if RecoverOrphanedHouseVehicles then RecoverOrphanedHouseVehicles() end

    -- A crash leaves cars mid-transition: not stored, but still holding a
    -- space. Clear those seats or the space can never be used again.
    ReconcileGarages()

    -- One query for every owner name, so no door menu ever blocks on a lookup.
    local owners = {}
    for _, h in pairs(Houses) do
        if h.owner_cid then owners[#owners + 1] = h.owner_cid end
    end
    WarmNameCache(owners)

    print('[cm-house] ^2ready^7 | admin: cm-admin Developer > House Admin')
end)

-- Wardrobes need no registration: cm-inventory opens storage on demand by
-- (ownerType, ownerId, slotPrefix). The cm_house_wardrobes rows only record
-- which slots exist and what they are called.

exports('GetHouse',       function(id)  return Houses[tonumber(id)] end)
exports('GetHouses',      function()    return Houses end)
exports('GetFamily',      function(id)  return GetFamilyDisplay(id) end)
exports('GetFamilyOfCid', function(cid) return GetFamilyForCharacter(cid) end)
