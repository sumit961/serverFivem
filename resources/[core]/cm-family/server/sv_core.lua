-- ============================================================
--  cm-family | sv_core.lua
--  In-memory family state, the permission engine, and the exports cm-house
--  and other resources call. This is the authority for "who is in which family
--  at which rank, and what does that rank allow".
-- ============================================================

local B = CMFamilyBridge

-- In-memory caches, rebuilt from the DB at startup and kept in sync on writes.
Families      = {}   -- [familyId] = { id, name, tag, color, founder_cid, house_id, bank_balance, ranks = {[tier]=rank}, ranksById = {[rankId]=rank} }
MemberByCid   = {}   -- [cid]      = { family_id, rank_id }
WithdrawnToday = {}  -- [cid]      = { day = 'YYYY-MM-DD', amount = n }

local function decodeJson(value, fallback)
    if type(value) == 'table' then return value end
    if value == nil or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    if ok and decoded ~= nil then return decoded end
    return fallback
end

-- Convert a stored permissions payload (array of keys, or ALL sentinel, or a
-- key->bool map) into a normalized key->true map.
local function normalizePermissions(raw)
    local out = {}
    if raw == 'ALL' then
        for _, p in ipairs(Config.Permissions) do out[p.key] = true end
        return out
    end
    raw = decodeJson(raw, {})
    if type(raw) ~= 'table' then return out end
    -- Array form: { 'family.invite', 'bank.view', ... }
    local isArray = raw[1] ~= nil
    if isArray then
        for _, key in ipairs(raw) do out[tostring(key)] = true end
    else
        for key, value in pairs(raw) do
            if value == true or value == 1 then out[tostring(key)] = true end
        end
    end
    return out
end

CMFamilyNormalizePermissions = normalizePermissions

-- Legacy installations can contain both `permissions` and `perms`.  Never
-- prefer one column blindly: some migrations created `permissions = '{}'`
-- while the real grants remained in `perms`.  Merge every recognized payload
-- so an empty compatibility column cannot silently remove house access.
local function mergePermissions(...)
    local out = {}
    for index = 1, select('#', ...) do
        local normalized = normalizePermissions(select(index, ...))
        for key, enabled in pairs(normalized) do
            if enabled == true then out[tostring(key)] = true end
        end
    end
    return out
end
CMFamilyMergePermissions = mergePermissions

local function normalizeSymbol(value)
    local key = tostring(value or ''):lower():gsub('[^a-z0-9_%-]', '')
    local allowed = Config.Identity and Config.Identity.allowedSymbols or {}
    if key ~= '' and allowed[key] then return key end
    local fallback = tostring(Config.Identity and Config.Identity.defaultSymbol or 'shield'):lower()
    return allowed[fallback] and fallback or 'shield'
end

local function normalizeSymbolColor(value, fallback)
    local color = tostring(value or ''):lower()
    if color:match('^#%x%x%x%x%x%x$') then return color end
    fallback = tostring(fallback or (Config.Identity and Config.Identity.defaultColor) or '#00f0ff'):lower()
    if fallback:match('^#%x%x%x%x%x%x$') then return fallback end
    return '#00f0ff'
end

local function defaultSymbolForTier(tier, isFounder)
    if isFounder == true then return 'crown', '#ffd76a' end
    tier = tonumber(tier) or 1
    if tier >= 10 then return 'shield', '#00f0ff' end
    if tier >= 5 then return 'star', '#75e6ff' end
    return 'flower', '#9be7ff'
end

CMFamilyNormalizeSymbol = normalizeSymbol
CMFamilyNormalizeSymbolColor = normalizeSymbolColor
CMFamilyDefaultSymbolForTier = defaultSymbolForTier

-- ---------- loading ----------
local function indexRank(family, rank)
    family.ranks = family.ranks or {}
    family.ranksById = family.ranksById or {}
    local tierKey = tonumber(rank.tier) or rank.tier
    local idKey = tonumber(rank.id) or rank.id
    family.ranks[tierKey] = rank
    family.ranksById[idKey] = rank
end

local function rankById(family, rankId)
    if not family or rankId == nil then return nil end
    return family.ranksById[tonumber(rankId) or rankId]
        or family.ranksById[tostring(rankId)]
end


local function lowestUsableRank(family)
    if not family then return nil end
    local chosen
    for _, rank in pairs(family.ranksById or {}) do
        if type(rank) == 'table' and rank.is_founder ~= true then
            if not chosen or (tonumber(rank.tier) or 0) < (tonumber(chosen.tier) or 0) then
                chosen = rank
            end
        end
    end
    if chosen then return chosen end
    for _, rank in pairs(family.ranksById or {}) do
        if type(rank) == 'table' then return rank end
    end
    return nil
end

local function resolveMembershipRank(family, membership)
    if not family or not membership then return nil end
    local rank = rankById(family, membership.rank_id)
    if rank then return rank end

    local legacyTier = tonumber(membership.rank_tier or membership.grade or membership.rank_grade or membership.level)
    if legacyTier then
        rank = family.ranks[legacyTier] or family.ranks[tostring(legacyTier)]
        if rank then
            membership.rank_id = rank.id
            membership.rank_tier = tonumber(rank.tier) or legacyTier
            return rank
        end
    end

    -- A valid member row must never become unusable only because an old schema
    -- stored a stale/missing rank_id. Use the family's lowest rank and repair
    -- rank_id asynchronously when possible.
    rank = lowestUsableRank(family)
    if rank then
        membership.rank_id = rank.id
        membership.rank_tier = tonumber(rank.tier) or 1
    end
    return rank
end

local function isBasicMemberHousePermission(permissionKey)
    local set = Config.BasicMemberHousePermissions or {}
    return set[tostring(permissionKey or '')] == true
end

CMFamilyResolveMembershipRank = resolveMembershipRank
CMFamilyIsBasicMemberHousePermission = isBasicMemberHousePermission

-- The family owner is authoritative from cm_families.founder_cid. Legacy rank
-- rows are not always marked is_founder=1, so owner authority must not depend
-- on that compatibility column. Return a per-member rank copy so founder powers
-- are never granted to another member who shares the same rank row.
local function isFamilyFounder(characterId, family)
    if characterId == nil or not family then return false end
    return tostring(family.founder_cid or '') == tostring(characterId)
end

local function effectiveRankForMember(characterId, family, rank)
    if not rank or not isFamilyFounder(characterId, family) then return rank end

    local effective = {}
    for key, value in pairs(rank) do effective[key] = value end
    effective.is_founder = true
    effective.permissions = {}
    for key, value in pairs(rank.permissions or {}) do
        if value == true then effective.permissions[key] = true end
    end
    for _, permission in ipairs(Config.Permissions or {}) do
        effective.permissions[permission.key] = true
    end
    return effective
end

local function highestFamilyRank(family)
    local chosen
    for _, rank in pairs((family and family.ranksById) or {}) do
        if type(rank) == 'table' and (not chosen or (tonumber(rank.tier) or 0) > (tonumber(chosen.tier) or 0)) then
            chosen = rank
        end
    end
    return chosen
end

CMFamilyIsFounder = isFamilyFounder
CMFamilyEffectiveRank = effectiveRankForMember

local function reconcileAuthoritativeFamilyHouses()
    local rows = MySQL.query.await([[
        SELECT f.id, f.name, f.founder_cid, f.house_id, f.bank_balance,
               h.id AS linked_house_exists, h.owner_cid AS house_owner_cid,
               h.family_id AS house_family_id,
               owner_member.character_id AS owner_membership_cid
        FROM cm_families f
        LEFT JOIN cm_houses h ON h.id = f.house_id
        LEFT JOIN cm_family_members owner_member
          ON owner_member.family_id = f.id
         AND owner_member.character_id = CAST(h.owner_cid AS CHAR)
    ]]) or {}

    local removed = 0
    for _, row in ipairs(rows) do
        local familyId = tonumber(row.id)
        local houseId = tonumber(row.house_id)
        local houseFamilyId = tonumber(row.house_family_id)
        local valid = familyId and houseId and row.linked_house_exists ~= nil
            and houseFamilyId == familyId
            and row.owner_membership_cid ~= nil

        if not valid and familyId then
            local deleted, why = CMFamilyDeleteFamilyRows(familyId)
            if deleted then
                removed = removed + 1
                print(('[cm-family] removed orphan family %s (%s); every family must remain linked to a house owned by one of its members')
                    :format(tostring(familyId), tostring(row.name or 'unnamed')))
            else
                error(('could_not_remove_orphan_family_%s:%s'):format(tostring(familyId), tostring(why)))
            end
        end
    end
    return removed
end

function LoadFamilies()
    Families, MemberByCid = {}, {}
    reconcileAuthoritativeFamilyHouses()

    for _, f in ipairs(MySQL.query.await('SELECT * FROM cm_families') or {}) do
        local familyId = tonumber(f.id) or f.id
        Families[familyId] = {
            id = familyId, name = f.name, tag = f.tag, color = f.color,
            tag_visible = tonumber(f.tag_visible) ~= 0,
            founder_cid = f.founder_cid, house_id = tonumber(f.house_id) or f.house_id,
            announcement = f.announcement, announcement_by = f.announcement_by,
            announcement_at = f.announcement_at,
            bank_balance = tonumber(f.bank_balance) or 0,
            created_at = f.created_at,
            ranks = {}, ranksById = {},
        }
    end

    for _, r in ipairs(MySQL.query.await('SELECT * FROM cm_family_ranks') or {}) do
        local fam = Families[tonumber(r.family_id) or r.family_id]
        if fam then
            local tier = (CMFamilyRankTier and CMFamilyRankTier(r)) or tonumber(r.tier)
            local founder = tonumber(r.is_founder) == 1
            local defaultSymbol, defaultColor = defaultSymbolForTier(tier, founder)
            local needsInitialSymbol = r.overhead_color == nil or tostring(r.overhead_color) == ''
            local symbol = needsInitialSymbol and defaultSymbol or normalizeSymbol(r.overhead_symbol)
            local symbolColor = normalizeSymbolColor(r.overhead_color, needsInitialSymbol and defaultColor or fam.color)

            indexRank(fam, {
                id = tonumber(r.id) or r.id, family_id = tonumber(r.family_id) or r.family_id, tier = tier,
                name = r.name, is_founder = founder,
                bank_daily_limit = tonumber(r.bank_daily_limit) or 0,
                overhead_symbol = symbol,
                overhead_color = symbolColor,
                permissions = mergePermissions(r.permissions, r.perms),
            })

            if needsInitialSymbol then
                pcall(function()
                    MySQL.update.await(
                        'UPDATE cm_family_ranks SET overhead_symbol = ?, overhead_color = ? WHERE id = ?',
                        { symbol, symbolColor, tonumber(r.id) or r.id })
                end)
            end
        end
    end

    -- Upgrade only the untouched stock Recruit permission set. Custom ranks
    -- are deliberately left alone. This makes existing families receive the
    -- same basic family-house access as newly created families.
    if type(CMFamilyUpgradeStockRecruitPermissions) == 'function' then
        local upgraded = CMFamilyUpgradeStockRecruitPermissions()
        if tonumber(upgraded) and tonumber(upgraded) > 0 then
            print(('[cm-family] upgraded %d untouched Recruit rank%s with basic family-house access')
                :format(upgraded, upgraded == 1 and '' or 's'))
        end
    end
    if type(CMFamilyUpgradeStockOfficerAuditPermission) == 'function' then
        local upgraded = CMFamilyUpgradeStockOfficerAuditPermission()
        if tonumber(upgraded) and tonumber(upgraded) > 0 then
            print(('[cm-family] upgraded %d untouched Officer rank%s with family activity-log access')
                :format(upgraded, upgraded == 1 and '' or 's'))
        end
    end

    for _, m in ipairs(MySQL.query.await('SELECT * FROM cm_family_members') or {}) do
        local familyId = tonumber(m.family_id) or m.family_id
        local characterId = m.character_id or m.cid or m.citizenid
        local family = Families[familyId]
        if family and characterId ~= nil then
            local membership = {
                family_id = familyId,
                rank_id = tonumber(m.rank_id) or m.rank_id,
                rank_tier = tonumber(m.rank_tier or m.grade or m.rank_grade or m.level),
                custom_title = m.custom_title,
                tag_hidden = tonumber(m.tag_hidden) == 1,
            }
            local rank = resolveMembershipRank(family, membership)

            -- Repair only the authoritative founder membership when a legacy
            -- database points it at a lower rank. Founder authority itself is
            -- still per-character and never inherited merely by sharing a rank.
            if isFamilyFounder(characterId, family) then
                local founderRank = highestFamilyRank(family)
                if founderRank then
                    rank = founderRank
                    membership.rank_id = founderRank.id
                    membership.rank_tier = tonumber(founderRank.tier) or membership.rank_tier
                end
            end

            MemberByCid[tostring(characterId)] = membership

            if rank and tostring(m.rank_id or '') ~= tostring(rank.id or '') then
                pcall(function()
                    MySQL.update.await(
                        'UPDATE cm_family_members SET rank_id = ? WHERE character_id = ? AND family_id = ?',
                        { rank.id, tostring(characterId), familyId })
                end)
            end
        end
    end

    local n = 0 ; for _ in pairs(Families) do n = n + 1 end
    print(('[cm-family] ^2loaded^7 %d famil%s'):format(n, n == 1 and 'y' or 'ies'))

    CreateThread(function()
        Wait(250)
        for _, rawSrc in ipairs(GetPlayers()) do
            local src = tonumber(rawSrc)
            local cid = src and B.GetCid(src) or nil
            if cid and SyncFamilyMemberState then SyncFamilyMemberState(cid) end
        end
        -- cm-house can already be running when only cm-family is restarted.
        -- Refresh every linked member so accessible-house maps/blips are rebuilt.
        for familyId in pairs(Families) do B.RefreshFamilyMembers(familyId) end
    end)
end

-- ---------- lookups ----------
function GetFamilyById(familyId)
    return Families[tonumber(familyId)]
end

function GetMembership(cid)
    if cid == nil then return nil end
    local m = MemberByCid[cid]
    if m then return m end
    m = MemberByCid[tostring(cid)]
    if m then return m end
    local asNum = tonumber(cid)
    if asNum ~= nil then return MemberByCid[asNum] end
    return nil
end

function GetRankForCid(cid)
    local m = GetMembership(cid)
    if not m and CMFamilyRefreshMembership then m = CMFamilyRefreshMembership(cid) end
    if not m then return nil end
    local fam = Families[tonumber(m.family_id) or m.family_id]
    if not fam then return nil end
    local rank = resolveMembershipRank(fam, m)
    return effectiveRankForMember(cid, fam, rank), fam
end


local function permissionSnapshot(rank)
    local out = {}
    if not rank then return out end
    for _, permission in ipairs(Config.Permissions or {}) do
        out[permission.key] = rank.is_founder == true or rank.permissions[permission.key] == true
    end
    return out
end

function BuildFamilyMemberState(characterId)
    local membership = GetMembership(characterId)
    if not membership then return nil end
    local family = Families[tonumber(membership.family_id) or membership.family_id]
    if not family then return nil end
    local rank = effectiveRankForMember(characterId, family, resolveMembershipRank(family, membership))
    if not rank then return nil end

    return {
        active = true,
        id = family.id,
        name = family.name,
        tag = family.tag,
        color = family.color or '#00f0ff',
        -- Symbol-only overhead identity. Text tag/rank/title remain available
        -- for chat and profiles but cm-playerdata never renders them above peds.
        symbol = normalizeSymbol(family.symbol),
        symbolColor = normalizeSymbolColor(family.color),
        -- Family membership always carries an overhead symbol. Legacy
        -- family/member visibility fields are intentionally ignored.
        symbolVisible = true,
        tagVisible = false,
        rankId = rank.id,
        rankName = rank.name,
        tier = rank.tier,
        isFounder = rank.is_founder == true,
        customTitle = membership.custom_title,
        permissions = permissionSnapshot(rank),
    }
end

function SyncFamilyMemberState(characterId)
    if characterId == nil then return false end
    local src = B.GetSrcByCid(characterId)
    if not src then return false end
    local state = BuildFamilyMemberState(characterId)
    Player(src).state:set('cmFamily', state or false, true)
    if state then
        B.SetPlayerFamily(src, state.id, state.name, state)
    else
        B.SetPlayerFamily(src, nil, nil, nil)
    end
    TriggerClientEvent('cm-playerdata:client:familyIdentityChanged', src)
    TriggerEvent('cm-chat:server:refreshPlayerChannels', src)
    return true
end

function SyncFamilyState(familyId)
    familyId = tonumber(familyId)
    if not familyId then return end
    for cid, membership in pairs(MemberByCid) do
        if tonumber(membership.family_id) == familyId then
            SyncFamilyMemberState(cid)
        end
    end
end

function ClearFamilyMemberState(characterId)
    local src = B.GetSrcByCid(characterId)
    if not src then return false end
    Player(src).state:set('cmFamily', false, true)
    B.SetPlayerFamily(src, nil, nil, nil)
    TriggerClientEvent('cm-playerdata:client:familyIdentityChanged', src)
    TriggerEvent('cm-chat:server:refreshPlayerChannels', src)
    return true
end

exports('GetMemberIdentity', function(characterId)
    return BuildFamilyMemberState(characterId)
end)

exports('GetFamilyMember', function(characterId)
    local state = BuildFamilyMemberState(characterId)
    if not state then return nil end
    return state
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    local cid = type(data) == 'table' and (data.charId or data.characterId or data.id) or nil
    cid = cid or B.GetCid(src)
    if cid then SyncFamilyMemberState(cid) end
end)

AddEventHandler('cm-playerdata:server:characterUnloaded', function(src, data)
    src = tonumber(src)
    if src then
        Player(src).state:set('cmFamily', false, true)
        TriggerEvent('cm-chat:server:refreshPlayerChannels', src)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= tostring(Config.PlayerDataResource or 'cm-playerdata') then return end
    CreateThread(function()
        Wait(500)
        for _, rawSrc in ipairs(GetPlayers()) do
            local src = tonumber(rawSrc)
            local cid = src and B.GetCid(src) or nil
            if cid then SyncFamilyMemberState(cid) end
        end
    end)
end)

-- Does this rank hold a permission? Founder ranks always do.
function RankHasPermission(rank, key)
    if not rank then return false end
    if rank.is_founder then return true end
    return rank.permissions[key] == true
end

-- A cache miss after an invite/restart must not strand an otherwise valid
-- member outside the family house. Re-read only that character, then repopulate
-- the authoritative cache. This is a fail-closed fallback, not a per-frame DB
-- query: normal permission checks remain fully cached.
local function refreshMembershipFromDatabase(characterId)
    if characterId == nil then return nil end
    local cid = tostring(characterId)
    local row = MySQL.single.await([[
        SELECT *
        FROM cm_family_members
        WHERE character_id = ?
        LIMIT 1
    ]], { cid })
    if not row then return nil end
    local familyId = tonumber(row.family_id) or row.family_id
    local family = Families[familyId]
    if not family then return nil end
    local membership = {
        family_id = familyId,
        rank_id = tonumber(row.rank_id) or row.rank_id,
        rank_tier = tonumber(row.rank_tier or row.grade or row.rank_grade or row.level),
        custom_title = row.custom_title,
        tag_hidden = tonumber(row.tag_hidden) == 1,
    }
    local rank = resolveMembershipRank(family, membership)
    MemberByCid[cid] = membership

    if rank and tostring(row.rank_id or '') ~= tostring(rank.id or '') then
        pcall(function()
            MySQL.update.await(
                'UPDATE cm_family_members SET rank_id = ? WHERE character_id = ? AND family_id = ?',
                { rank.id, cid, familyId })
        end)
    end
    return membership
end
CMFamilyRefreshMembership = refreshMembershipFromDatabase

-- ---------- the core question cm-house asks ----------
-- HasHousePermission(characterId, familyId, houseId, permissionKey, action)
-- Returns exactly true when the member's current rank grants it. For vehicle
-- LEVEL actions that target a specific vehicle, the rank tier must also be
-- >= the vehicle's required level.
local function hasHousePermission(characterId, familyId, houseId, permissionKey, action)
    if CMFamilyIsDatabaseReady and not CMFamilyIsDatabaseReady() then return false end
    local m = GetMembership(characterId) or refreshMembershipFromDatabase(characterId)
    if not m then return false end
    if tonumber(m.family_id) ~= tonumber(familyId) then return false end

    local familyKey = tonumber(m.family_id) or m.family_id
    local fam = Families[familyKey]
    if not fam then return false end
    if houseId ~= nil and tonumber(fam.house_id) ~= tonumber(houseId) then return false end

    permissionKey = tostring(permissionKey or '')

    local rank = effectiveRankForMember(characterId, fam, resolveMembershipRank(fam, m))
    if not rank then
        if type(CMFamilyReloadRanks) == 'function' then CMFamilyReloadRanks(fam.id) end
        rank = effectiveRankForMember(characterId, fam, resolveMembershipRank(fam, m))
    end

    -- Per-vehicle tier requirements apply whenever a specific vehicle is
    -- targeted, even for baseline/basic-membership permissions -- otherwise
    -- raising a car's required level would have no effect on ordinary members.
    if Config.VehicleLevelActions[permissionKey] then
        local vehicleId = CMFamilyResolveVehicleId and CMFamilyResolveVehicleId(action)
        if vehicleId then
            local level = GetVehicleLevel(fam.id, vehicleId)
            if not rank or (tonumber(rank.tier) or 1) < tonumber(level) then return false end
        end
    end

    -- Baseline family-house use is granted by committed membership itself.
    -- Management powers remain rank-controlled below.
    if isBasicMemberHousePermission(permissionKey) then
        return true
    end

    if not rank or not RankHasPermission(rank, permissionKey) then return false end

    return true
end

exports('HasHousePermission', hasHousePermission)

exports('GetHousePermissionDecision', function(characterId, familyId, houseId, permissionKey, action)
    local membership = GetMembership(characterId) or refreshMembershipFromDatabase(characterId)
    if not membership then return false, 'not_a_family_member' end
    if tonumber(membership.family_id) ~= tonumber(familyId) then return false, 'different_family' end
    local family = Families[tonumber(membership.family_id) or membership.family_id]
    if not family then return false, 'family_not_loaded' end
    if houseId ~= nil and tonumber(family.house_id) ~= tonumber(houseId) then
        return false, 'not_the_active_family_house'
    end

    local key = tostring(permissionKey or '')

    if not hasHousePermission(characterId, familyId, houseId, permissionKey, action) then
        if isBasicMemberHousePermission(key) then
            return false, 'vehicle_level_or_context_denied'
        end
        local rank = effectiveRankForMember(characterId, family, resolveMembershipRank(family, membership))
        if not rank then return false, 'rank_not_loaded' end
        if not RankHasPermission(rank, key) then
            return false, ('rank_missing_permission:%s'):format(key)
        end
        return false, 'vehicle_level_or_context_denied'
    end
    return true, 'allowed'
end)

-- Compatibility: older cm-house import signature HasPermission(cid, familyId, key)
exports('HasPermission', function(characterId, familyId, permissionKey)
    return hasHousePermission(characterId, familyId, nil, permissionKey, nil)
end)

-- ---------- exports cm-house / others use ----------
-- cm-house's SetFamilyHouseLink verifies the owner is in the family by calling
-- this. Must return a table with a numeric `id`.
exports('GetFamilyForCharacter', function(characterId)
    local m = GetMembership(characterId) or refreshMembershipFromDatabase(characterId)
    if not m then return nil end
    local fam = Families[tonumber(m.family_id) or m.family_id]
    if not fam then return nil end
    local rank = effectiveRankForMember(characterId, fam, resolveMembershipRank(fam, m))
    return {
        id = fam.id, name = fam.name, house_id = fam.house_id,
        rank_id = rank and rank.id or m.rank_id,
        tier = rank and rank.tier or m.rank_tier or 1,
        isFounder = isFamilyFounder(characterId, fam),
    }
end)

exports('GetFamilyMemberCharacterIds', function(familyId)
    familyId = tonumber(familyId)
    if not familyId then return {} end
    local out, seen = {}, {}

    -- Query the committed membership table so a stale runtime cache can never
    -- stop cm-house from refreshing a newly joined player's access map.
    local ok, rows = pcall(function()
        return MySQL.query.await(
            'SELECT character_id FROM cm_family_members WHERE family_id = ?',
            { familyId }) or {}
    end)
    if ok and type(rows) == 'table' then
        for _, row in ipairs(rows) do
            local cid = row.character_id
            if cid ~= nil and not seen[tostring(cid)] then
                seen[tostring(cid)] = true
                out[#out + 1] = tonumber(cid) or tostring(cid)
            end
        end
    end

    for cid, m in pairs(MemberByCid) do
        if tonumber(m.family_id) == familyId and not seen[tostring(cid)] then
            seen[tostring(cid)] = true
            out[#out + 1] = tonumber(cid) or cid
        end
    end
    return out
end)

exports('GetFamilyById', function(familyId)
    local fam = Families[tonumber(familyId)]
    if not fam then return nil end
    return {
        id = fam.id, name = fam.name, tag = fam.tag, color = fam.color, tag_visible = fam.tag_visible ~= false,
        founder_cid = fam.founder_cid, house_id = fam.house_id,
        bank_balance = fam.bank_balance,
    }
end)

-- Publish the import contract cm-family satisfies, so cm-house's
-- GetFamilyImportContract lines up during integration checks.
exports('GetFamilyExportContract', function()
    return {
        resource = GetCurrentResourceName(),
        permission = 'HasHousePermission(characterId, familyId, houseId, permissionKey, action) -> boolean',
        lookups = {
            'GetFamilyForCharacter', 'GetFamilyMemberCharacterIds', 'GetFamilyById',
            'GetMemberIdentity', 'GetFamilyMember', 'CanUseFamilyVehicle',
            'GetFamilyVehicleAccessDecision',
        },
        maxRanks = Config.MaxRanks,
    }
end)

-- ---------- logging ----------
-- server/sv_audit.lua replaces this bootstrap fallback before any gameplay
-- callback is registered. Keeping a defensive fallback here protects unusual
-- manual load orders without making gameplay depend on a nil global.
function LogFamily(familyId, actorCid, action, detail, options)
    local encoded = detail and json.encode(detail) or '{}'
    local ok, result = pcall(function()
        return MySQL.insert.await(
            'INSERT INTO cm_family_log (family_id, actor_cid, action, detail) VALUES (?, ?, ?, ?)',
            { tonumber(familyId), actorCid and tostring(actorCid) or false, tostring(action), encoded })
    end)
    return ok and result ~= nil, result
end

-- Database startup is owned by server/sv_schema.lua.

-- ============================================================
-- House-authoritative lifecycle finalizer | v1.0.8
-- cm-house deletes the linked family rows inside the same DB transaction that
-- sells/evicts/deletes the property. This export then removes the corresponding
-- runtime caches and playerdata family markers without calling back into
-- cm-house (which would create a lifecycle loop).
-- ============================================================
local function houseLifecycleInvokerAllowed()
    local invoker = GetInvokingResource()
    return invoker == tostring(Config.HouseResource or 'cm-house')
        or invoker == GetCurrentResourceName()
end

exports('FinalizeHouseFamilyDeletion', function(familyId, houseId, reason, actorCid)
    if not houseLifecycleInvokerAllowed() then
        return false, 'resource_not_authorized'
    end

    familyId = tonumber(familyId)
    houseId = tonumber(houseId)
    if not familyId or familyId <= 0 then return false, 'invalid_family_id' end

    local family = Families[familyId]
    if family and houseId and family.house_id and tonumber(family.house_id) ~= houseId then
        return false, 'family_house_mismatch'
    end

    local removedMembers = {}
    for cid, membership in pairs(MemberByCid) do
        if tonumber(membership.family_id) == familyId then
            removedMembers[#removedMembers + 1] = tostring(cid)
            MemberByCid[cid] = nil
            WithdrawnToday[cid] = nil
            WithdrawnToday[tostring(cid)] = nil
        end
    end

    if CMFamilyRevokeVehicleKeysForFamily then
        CMFamilyRevokeVehicleKeysForFamily(familyId, 'family-house-removed')
    end
    Families[familyId] = nil
    if InvalidateVehicleCache then InvalidateVehicleCache(familyId) end

    for _, cid in ipairs(removedMembers) do
        local src = B.GetSrcByCid(cid)
        if src then
            ClearFamilyMemberState(cid)
            B.Notify(src,
                ('Your family was disbanded because its family house was %s.')
                    :format(tostring(reason or 'removed'):gsub('_', ' ')),
                'inform')
        end
    end

    -- Refresh cm-house/future integrations after our local caches are clean.
    B.RefreshFamilyMembers(familyId)
    B.RefreshFamilyAccess(familyId)

    print(('[cm-family] family %s finalized after house %s lifecycle action %s by cid %s')
        :format(tostring(familyId), tostring(houseId), tostring(reason), tostring(actorCid)))
    return true, { removedMembers = #removedMembers }
end)
