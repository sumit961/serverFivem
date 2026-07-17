-- ============================================================
--  cm-family | sv_ranks.lua | v1.0.5
--  Rank creation, editing, permission toggles, reordering. Enforces the two
--  authority rules that keep the hierarchy safe:
--    1. You can never edit a rank at or above your own tier.
--    2. You can never grant a permission you do not yourself hold.
--  The founder rank bypasses these (it always holds everything).
-- ============================================================

local B = CMFamilyBridge

local ValidPermissionKeys = {}
for _, permission in ipairs(Config.Permissions or {}) do
    ValidPermissionKeys[tostring(permission.key)] = true
end

-- Store permissions as a JSON object, not an array. Legacy cm-family schemas
-- commonly define a JSON CHECK on `perms` that accepts an object payload. The
-- runtime reader still accepts both arrays and maps for backwards compatibility.
local function buildPermissionMap(raw)
    local out = {}
    if type(raw) ~= 'table' then return out end

    if raw[1] ~= nil then
        for _, key in ipairs(raw) do
            key = tostring(key)
            if ValidPermissionKeys[key] then out[key] = true end
        end
    else
        for key, enabled in pairs(raw) do
            key = tostring(key)
            if ValidPermissionKeys[key] and (enabled == true or enabled == 1) then
                out[key] = true
            end
        end
    end
    return out
end

local function encodePermissions(raw, shape)
    local permissionMap = buildPermissionMap(raw)
    if shape == 'array' then
        local arr = {}
        for key in pairs(permissionMap) do arr[#arr + 1] = key end
        table.sort(arr)
        return json.encode(arr)
    end
    return json.encode(permissionMap)
end

local function persistRankPermissions(rankId, permMap)
    local payload = encodePermissions(permMap, 'object')
    if CMFamilyUsesLegacyPermsColumn then
        local legacyPayload = encodePermissions(permMap, CMFamilyLegacyPermsFormat)
        MySQL.update.await('UPDATE cm_family_ranks SET permissions = ?, perms = ? WHERE id = ?',
            { payload, legacyPayload, tonumber(rankId) })
    else
        MySQL.update.await('UPDATE cm_family_ranks SET permissions = ? WHERE id = ?',
            { payload, tonumber(rankId) })
    end
end

local function insertRank(familyId, tier, name, permissions, isFounder, bankDailyLimit, overheadSymbol, overheadColor)
    local columns = { 'family_id', 'tier' }
    local placeholders = { '?', '?' }
    local values = { familyId, tier }

    -- Legacy schemas enforce UNIQUE(family_id, grade). If grade is left at its
    -- default (usually 0), the second rank in every family collides as `X-0`.
    -- Keep both names synchronized on every insert.
    if CMFamilyUsesLegacyGradeColumn then
        columns[#columns + 1] = 'grade'
        placeholders[#placeholders + 1] = '?'
        values[#values + 1] = tier
    end

    columns[#columns + 1] = 'name'
    placeholders[#placeholders + 1] = '?'
    values[#values + 1] = name

    local fallbackSymbol, fallbackColor = CMFamilyDefaultSymbolForTier(tier, isFounder == 1)
    columns[#columns + 1] = 'overhead_symbol'
    placeholders[#placeholders + 1] = '?'
    values[#values + 1] = CMFamilyNormalizeSymbol(overheadSymbol or fallbackSymbol)

    columns[#columns + 1] = 'overhead_color'
    placeholders[#placeholders + 1] = '?'
    values[#values + 1] = CMFamilyNormalizeSymbolColor(overheadColor, fallbackColor)

    columns[#columns + 1] = 'permissions'
    placeholders[#placeholders + 1] = '?'
    values[#values + 1] = encodePermissions(permissions, 'object')

    if CMFamilyUsesLegacyPermsColumn then
        columns[#columns + 1] = 'perms'
        placeholders[#placeholders + 1] = '?'
        values[#values + 1] = encodePermissions(permissions, CMFamilyLegacyPermsFormat)
    end

    columns[#columns + 1] = 'is_founder'
    placeholders[#placeholders + 1] = '?'
    values[#values + 1] = isFounder

    columns[#columns + 1] = 'bank_daily_limit'
    placeholders[#placeholders + 1] = '?'
    values[#values + 1] = bankDailyLimit

    local quoted = {}
    for i, column in ipairs(columns) do quoted[i] = ('`%s`'):format(column) end
    local query = ('INSERT INTO cm_family_ranks (%s) VALUES (%s)')
        :format(table.concat(quoted, ', '), table.concat(placeholders, ', '))
    return MySQL.insert.await(query, values)
end

-- Reload one family's ranks from DB into cache (keeps ranks/ranksById aligned).
local function reloadFamilyRanks(familyId)
    local fam = Families[tonumber(familyId)]
    if not fam then return end
    fam.ranks, fam.ranksById = {}, {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM cm_family_ranks WHERE family_id = ?', { familyId }) or {}) do
        local rank = {
            id = tonumber(r.id) or r.id, family_id = tonumber(r.family_id) or r.family_id, tier = (CMFamilyRankTier and CMFamilyRankTier(r)) or tonumber(r.tier),
            name = r.name, is_founder = (tonumber(r.is_founder) == 1),
            bank_daily_limit = tonumber(r.bank_daily_limit) or 0,
            overhead_symbol = CMFamilyNormalizeSymbol(r.overhead_symbol),
            overhead_color = CMFamilyNormalizeSymbolColor(r.overhead_color, fam.color),
            permissions = (CMFamilyMergePermissions or CMFamilyNormalizePermissions)(r.permissions, r.perms),
        }
        local tierKey = tonumber(rank.tier) or rank.tier
        local idKey = tonumber(rank.id) or rank.id
        fam.ranks[tierKey] = rank
        fam.ranksById[idKey] = rank
    end
end
CMFamilyReloadRanks = reloadFamilyRanks

local STOCK_RECRUIT_OLD = {
    ['chat.family'] = true,
    ['bank.view'] = true,
    ['door.enter'] = true,
    ['garage.access'] = true,
}

local STOCK_RECRUIT_BASIC_HOUSE = {
    'garage.take', 'garage.store', 'trunk.access',
    'weapon_storage.access', 'weapon_storage.deposit', 'weapon_storage.withdraw',
    'storage.access',
}

-- Exact untouched Recruit set written by v1.1.6-v1.1.9. It predates the
-- explicit trunk.access permission, so upgrade only this known stock shape.
local STOCK_RECRUIT_PRE_TRUNK = {
    ['chat.family'] = true,
    ['bank.view'] = true,
    ['door.enter'] = true,
    ['garage.access'] = true,
    ['garage.take'] = true,
    ['garage.store'] = true,
    ['weapon_storage.access'] = true,
    ['weapon_storage.deposit'] = true,
    ['weapon_storage.withdraw'] = true,
    ['storage.access'] = true,
}

-- Untouched Officer permissions written before v1.4.0 introduced the
-- family.view_logs capability. Exact-set matching prevents custom ranks from
-- being modified silently.
local STOCK_OFFICER_PRE_AUDIT = {
    ['family.invite'] = true,
    ['family.kick'] = true,
    ['family.promote'] = true,
    ['family.demote'] = true,
    ['family.manage_vehicles'] = true,
    ['family.manage_tags'] = true,
    ['family.manage_titles'] = true,
    ['chat.family'] = true,
    ['bank.view'] = true,
    ['bank.deposit'] = true,
    ['bank.withdraw'] = true,
    ['door.enter'] = true,
    ['door.lock'] = true,
    ['garage.access'] = true,
    ['garage.take'] = true,
    ['garage.store'] = true,
    ['garage.manage_shared'] = true,
    ['trunk.access'] = true,
    ['weapon_storage.access'] = true,
    ['weapon_storage.deposit'] = true,
    ['weapon_storage.withdraw'] = true,
    ['storage.access'] = true,
    ['helipad.use'] = true,
}

-- Untouched Officer permissions written by v1.4.0 before vehicle.track.
local STOCK_OFFICER_PRE_TRACK = {}
for key, enabled in pairs(STOCK_OFFICER_PRE_AUDIT) do STOCK_OFFICER_PRE_TRACK[key] = enabled end
STOCK_OFFICER_PRE_TRACK['family.view_logs'] = true

local function samePermissionSet(actual, expected)
    local actualCount, expectedCount = 0, 0
    for key, enabled in pairs(actual or {}) do
        if enabled == true then
            actualCount = actualCount + 1
            if expected[key] ~= true then return false end
        end
    end
    for _, enabled in pairs(expected) do if enabled == true then expectedCount = expectedCount + 1 end end
    return actualCount == expectedCount
end

-- Existing families created before v1.1.6 have an untouched Recruit rank with
-- only chat/bank-view/door/garage-view. Upgrade precisely that stock set so a
-- newly accepted member can enter the family house, use its shared storage and
-- drive/store family-shared cars. Any customized Recruit permissions are left
-- unchanged.
function CMFamilyUpgradeStockRecruitPermissions()
    local upgraded = 0
    for _, family in pairs(Families or {}) do
        for _, rank in pairs(family.ranksById or {}) do
            if type(rank) == 'table' and rank.is_founder ~= true
                and tonumber(rank.tier) == 1
                and tostring(rank.name or ''):lower() == 'recruit'
                and (samePermissionSet(rank.permissions, STOCK_RECRUIT_OLD)
                    or samePermissionSet(rank.permissions, STOCK_RECRUIT_PRE_TRUNK)) then
                for _, key in ipairs(STOCK_RECRUIT_BASIC_HOUSE) do rank.permissions[key] = true end
                persistRankPermissions(rank.id, rank.permissions)
                upgraded = upgraded + 1
            end
        end
    end
    return upgraded
end

function CMFamilyUpgradeStockOfficerAuditPermission()
    local upgraded = 0
    for _, family in pairs(Families or {}) do
        for _, rank in pairs(family.ranksById or {}) do
            if type(rank) == 'table' and rank.is_founder ~= true
                and tonumber(rank.tier) == 10
                and tostring(rank.name or ''):lower() == 'officer'
                and (samePermissionSet(rank.permissions, STOCK_OFFICER_PRE_AUDIT)
                    or samePermissionSet(rank.permissions, STOCK_OFFICER_PRE_TRACK)) then
                rank.permissions['family.view_logs'] = true
                rank.permissions['vehicle.track'] = true
                persistRankPermissions(rank.id, rank.permissions)
                upgraded = upgraded + 1
            end
        end
    end
    return upgraded
end

-- Count ranks in a family.
local function rankCount(fam)
    local n = 0 ; for _ in pairs(fam.ranksById) do n = n + 1 end ; return n
end

-- Create the default rank set for a brand-new family. Returns the founder rank id.
function CreateDefaultRanks(familyId)
    local founderRankId
    for _, def in ipairs(Config.DefaultRanks) do
        local permissionMap = {}
        if def.permissions == 'ALL' then
            for _, p in ipairs(Config.Permissions) do permissionMap[p.key] = true end
        else
            for _, key in ipairs(def.permissions or {}) do permissionMap[key] = true end
        end

        local id = insertRank(
            familyId, def.tier, def.name, permissionMap,
            def.is_founder and 1 or 0, def.bank_daily_limit or 0,
            def.overhead_symbol, def.overhead_color
        )
        id = tonumber(id)
        if not id or id <= 0 then
            return nil, ('default_rank_insert_failed:%s'):format(tostring(def.name))
        end
        if def.is_founder then founderRankId = id end
    end

    if not founderRankId then return nil, 'founder_rank_missing' end
    reloadFamilyRanks(familyId)
    return founderRankId
end

-- ---------- guarded operations (actorCid must be a member) ----------
local function actorContext(actorCid)
    local rank, fam = GetRankForCid(actorCid)
    if not rank or not fam then return nil, nil, 'not_in_family' end
    return rank, fam
end

function CreateRank(actorCid, name, tier, permissions)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.manage_ranks') then return false, 'no_permission' end
    if rankCount(fam) >= Config.MaxRanks then return false, ('Maximum of %d ranks reached.'):format(Config.MaxRanks) end

    tier = math.max(1, math.min(Config.MaxRanks, math.floor(tonumber(tier) or 1)))
    if fam.ranks[tier] then return false, 'A rank already uses that tier.' end
    if not actorRank.is_founder and tier >= actorRank.tier then
        return false, 'You cannot create a rank at or above your own tier.'
    end
    name = tostring(name or 'Rank'):sub(1, 48)

    -- Filter requested permissions to those the actor holds. Accept either the
    -- UI array format or a key->boolean map.
    local requested = buildPermissionMap(permissions or {})
    local permMap = {}
    for key in pairs(requested) do
        if RankHasPermission(actorRank, key) then permMap[key] = true end
    end

    local defaultSymbol, defaultColor = CMFamilyDefaultSymbolForTier(tier, false)
    local id = insertRank(fam.id, tier, name, permMap, 0, 0, defaultSymbol, defaultColor)
    reloadFamilyRanks(fam.id)
    SyncFamilyState(fam.id)
    LogFamily(fam.id, actorCid, 'rank_create', { rankId = id, tier = tier, name = name })
    return true, id
end

function RenameRank(actorCid, rankId, newName)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.manage_ranks') then return false, 'no_permission' end
    local rank = fam.ranksById[tonumber(rankId)]
    if not rank then return false, 'no_such_rank' end
    if rank.is_founder then return false, 'The founder rank cannot be renamed here.' end
    if not actorRank.is_founder and rank.tier >= actorRank.tier then
        return false, 'You cannot edit a rank at or above your own tier.'
    end
    newName = tostring(newName or ''):sub(1, 48)
    if newName == '' then return false, 'empty_name' end
    MySQL.update.await('UPDATE cm_family_ranks SET name = ? WHERE id = ?', { newName, rank.id })
    reloadFamilyRanks(fam.id)
    SyncFamilyState(fam.id)
    LogFamily(fam.id, actorCid, 'rank_rename', { rankId = rank.id, name = newName })
    return true
end

function SetRankPermission(actorCid, rankId, key, enabled)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.manage_perms') then return false, 'no_permission' end
    local rank = fam.ranksById[tonumber(rankId)]
    if not rank then return false, 'no_such_rank' end
    if rank.is_founder then return false, 'The founder rank always has every permission.' end
    if not actorRank.is_founder and rank.tier >= actorRank.tier then
        return false, 'You cannot edit a rank at or above your own tier.'
    end
    key = tostring(key or '')
    -- You can only grant permissions you yourself hold. You may always revoke.
    if enabled == true and not RankHasPermission(actorRank, key) then
        return false, 'You cannot grant a permission you do not have.'
    end
    rank.permissions[key] = enabled == true or nil
    persistRankPermissions(rank.id, rank.permissions)
    reloadFamilyRanks(fam.id)
    if CMFamilyRevokeVehicleKeysForCharacter then
        for cid, membership in pairs(MemberByCid) do
            if tonumber(membership.family_id) == tonumber(fam.id)
                and tonumber(membership.rank_id) == tonumber(rank.id) then
                CMFamilyRevokeVehicleKeysForCharacter(cid, 'family-rank-permission-changed')
            end
        end
    end
    SyncFamilyState(fam.id)
    LogFamily(fam.id, actorCid, 'rank_permission', { rankId = rank.id, key = key, enabled = enabled == true })
    return true
end

function SetRankSymbol(actorCid, rankId, symbol, color)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.manage_ranks') then return false, 'no_permission' end

    local rank = fam.ranksById[tonumber(rankId)]
    if not rank then return false, 'no_such_rank' end
    if rank.is_founder and not actorRank.is_founder then
        return false, 'Only the family owner can change the founder symbol.'
    end
    if not actorRank.is_founder and tonumber(rank.tier) >= tonumber(actorRank.tier) then
        return false, 'You cannot edit a rank at or above your own tier.'
    end

    symbol = CMFamilyNormalizeSymbol(symbol)
    color = CMFamilyNormalizeSymbolColor(color, rank.overhead_color or fam.color)
    local affected = tonumber(MySQL.update.await(
        'UPDATE cm_family_ranks SET overhead_symbol = ?, overhead_color = ? WHERE id = ? AND family_id = ?',
        { symbol, color, rank.id, fam.id })) or 0
    if affected < 1 then return false, 'rank_symbol_update_failed' end

    reloadFamilyRanks(fam.id)
    SyncFamilyState(fam.id)
    LogFamily(fam.id, actorCid, 'rank_symbol_updated', {
        rankId = rank.id,
        symbol = symbol,
        color = color,
    })
    return true
end

function SetRankBankLimit(actorCid, rankId, limit)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.manage_ranks') then return false, 'no_permission' end
    local rank = fam.ranksById[tonumber(rankId)]
    if not rank then return false, 'no_such_rank' end
    if not actorRank.is_founder and rank.tier >= actorRank.tier then
        return false, 'You cannot edit a rank at or above your own tier.'
    end
    limit = math.floor(tonumber(limit) or 0)
    MySQL.update.await('UPDATE cm_family_ranks SET bank_daily_limit = ? WHERE id = ?', { limit, rank.id })
    reloadFamilyRanks(fam.id)
    SyncFamilyState(fam.id)
    LogFamily(fam.id, actorCid, 'rank_bank_limit', { rankId = rank.id, limit = limit })
    return true
end

function DeleteRank(actorCid, rankId)
    local actorRank, fam, err = actorContext(actorCid)
    if not actorRank then return false, err end
    if not RankHasPermission(actorRank, 'family.manage_ranks') then return false, 'no_permission' end
    local rank = fam.ranksById[tonumber(rankId)]
    if not rank then return false, 'no_such_rank' end
    if rank.is_founder then return false, 'The founder rank cannot be deleted.' end
    if not actorRank.is_founder and rank.tier >= actorRank.tier then
        return false, 'You cannot delete a rank at or above your own tier.'
    end
    -- Anyone on this rank drops to the lowest rank.
    local lowest
    for _, r in pairs(fam.ranksById) do
        if not lowest or r.tier < lowest.tier then lowest = r end
    end
    if lowest and lowest.id ~= rank.id then
        MySQL.update.await('UPDATE cm_family_members SET rank_id = ? WHERE rank_id = ?', { lowest.id, rank.id })
        for cid, m in pairs(MemberByCid) do
            if m.rank_id == rank.id then
                m.rank_id = lowest.id
                if CMFamilyRevokeVehicleKeysForCharacter then
                    CMFamilyRevokeVehicleKeysForCharacter(cid, 'family-rank-deleted')
                end
            end
        end
    end
    MySQL.update.await('DELETE FROM cm_family_ranks WHERE id = ?', { rank.id })
    reloadFamilyRanks(fam.id)
    SyncFamilyState(fam.id)
    LogFamily(fam.id, actorCid, 'rank_delete', { rankId = rank.id })
    return true
end
