CMGangDatabaseReady = false
CMGangDatabaseError = 'initializing'


-- oxmysql may return TINYINT(1) columns as Lua booleans on some server/database
-- combinations and as 0/1 numbers/strings on others. Never use tonumber(true)
-- for authority/state columns: it becomes nil and can invert leader/enabled checks.
function CMGangDbTrue(value)
    if value == true or value == 1 or value == '1' then return true end
    if type(value) == 'string' then
        local lowered = value:lower()
        return lowered == 'true' or lowered == 'yes' or lowered == 'on'
    end
    return false
end

local REQUIRED_TABLES = {
    'cm_gangs',
    'cm_gang_ranks',
    'cm_gang_members',
    'cm_gang_invites',
    'cm_gang_activity',
    'cm_gang_facilities',
    'cm_gang_fleet_vehicles',
    'cm_gang_armory_config',
    'cm_gang_armory_issues',
    'cm_gang_migrations',
    'cm_gang_blacklist',
    'cm_gang_wardrobe_outfits',
    'cm_gang_profit',
    'cm_gang_graffiti',
    'cm_gang_turf_snapshots',
    'cm_gang_turf_claims',
    'cm_gang_event_config',
    'cm_gang_event_entry_points',
    'cm_gang_event_drop_locations',
    'cm_gang_event_reward_config',
    'cm_gang_events',
    'cm_gang_event_players',
    'cm_gang_event_drops',
}

local REQUIRED_COLUMNS = {
    cm_gangs = { 'gang_id','display_name','short_tag','color','leader_character_id','enabled' },
    cm_gang_ranks = { 'id','gang_id','tier','name','permissions','is_leader_rank' },
    cm_gang_members = { 'id','gang_id','character_id','rank_id','is_leader' },
    cm_gang_invites = { 'invite_id','gang_id','actor_character_id','target_character_id','entry_rank_id','status','expires_at' },
    cm_gang_activity = { 'id','event_uid','gang_id','action','actor_character_id','target_character_id','detail' },
    cm_gang_facilities = { 'gang_id','facility_type','enabled','x','y','z','routing_bucket' },
    cm_gang_fleet_vehicles = { 'gang_id','catalog_id','vehicle_id','minimum_tier','trunk_minimum_tier','enabled','x','y','z' },
    cm_gang_armory_config = { 'gang_id','item_id','enabled','minimum_tier','issue_quantity','issue_limit','stock_quantity' },
    cm_gang_armory_issues = { 'issue_uid','gang_id','character_id','item_id','item_type','quantity','status' },
    cm_gang_migrations = { 'migration_id','applied_at' },
    cm_gang_blacklist = { 'id','gang_id','character_id','reason','blacklisted_by','created_at' },
    cm_gang_wardrobe_outfits = { 'id','gang_id','name','sex','components','minimum_tier' },
    cm_gang_profit = { 'gang_id','activity_score','pending_amount','last_tick_at','last_collected_at' },
    cm_gang_graffiti = { 'id','name','x','y','z','heading','normal_x','normal_y','normal_z','up_x','up_y','up_z','rotation','width','height','placement_ready','routing_bucket','gang_id','texture_key','enabled' },
    cm_gang_turf_snapshots = { 'snapshot_key','gang_id','tag_count','eligible_member_count','revenue','created_at' },
    cm_gang_turf_claims = { 'snapshot_key','gang_id','character_id','amount','claimed_at' },
    cm_gang_event_config = { 'event_type','enabled','event_name','zone_x','zone_y','zone_z','zone_radius','announcement_seconds','duration_seconds','routing_bucket','config_json' },
    cm_gang_event_entry_points = { 'event_type','gang_id','enabled','x','y','z','heading' },
    cm_gang_event_drop_locations = { 'id','event_type','label','enabled','x','y','z' },
    cm_gang_event_reward_config = { 'id','event_type','tier','item_id','enabled','min_quantity','max_quantity','weight' },
    cm_gang_events = { 'event_id','event_type','status','routing_bucket','config_snapshot','final_scores','end_reason' },
    cm_gang_event_players = { 'event_id','character_id','gang_id','kills','deaths','drops_secured','original_bucket','joined_at' },
    cm_gang_event_drops = { 'event_id','drop_id','drop_number','tier','location_id','state','claim_operation_id' },
}

local REQUIRED_UNIQUE_INDEXES = {
    cm_gang_ranks = { 'uniq_gang_rank_tier', 'uniq_gang_rank_name', 'uniq_gang_rank_identity', 'uniq_gang_leader_rank' },
    cm_gang_members = { 'uniq_gang_member_character', 'uniq_gang_leader_member' },
    cm_gang_invites = { 'uniq_gang_pending_target' },
    cm_gang_activity = { 'uniq_gang_activity_uid' },
    cm_gang_facilities = { 'uniq_gang_facility_type' },
    cm_gang_fleet_vehicles = { 'uniq_gang_fleet_catalog', 'uniq_gang_fleet_vehicle_id' },
    cm_gang_armory_config = { 'uniq_gang_armory_item' },
    cm_gang_armory_issues = { 'uniq_cm_gang_armory_issue_uid' },
    cm_gang_blacklist = { 'uniq_gang_blacklist_member' },
    cm_gang_wardrobe_outfits = { 'uniq_gang_wardrobe_outfit' },
    cm_gang_turf_snapshots = { 'uniq_cm_turf_snapshot_gang' },
    cm_gang_turf_claims = { 'uniq_cm_turf_claim' },
    cm_gang_event_config = { 'uniq_cm_gang_event_bucket' },
    cm_gang_event_reward_config = { 'uniq_cm_gang_event_reward' },
    cm_gang_event_drops = { 'uniq_cm_gang_event_drop_number', 'uniq_cm_gang_event_claim_operation' },
}


local function allGangPermissions()
    local permissions = {}
    for _, permission in ipairs(Config.Permissions or {}) do
        permissions[tostring(permission.key)] = true
    end
    return permissions
end

local function firstFreeTier(ranks, ignoreRankId)
    local used = { [100] = true }
    for _, rank in ipairs(ranks or {}) do
        if tonumber(rank.id) ~= tonumber(ignoreRankId) then
            used[tonumber(rank.tier)] = true
        end
    end
    for tier = 99, 1, -1 do
        if not used[tier] then return tier end
    end
    return nil
end

-- Structural recovery runs before the strict readiness audit.  Older gang
-- builds allowed cm-admin to leave a leader rank below tier 100 (or a
-- non-leader at tier 100).  The v0.2.0 validator then failed closed before
-- cm-admin could open, making the documented recovery path impossible.
-- This repair is intentionally narrow: it preserves rank IDs, member
-- assignments, names, gang identity, and all non-leader permissions.
local function repairRecoverableRankBaseline(gangId)
    local ranks = MySQL.query.await([[SELECT id,tier,name,permissions,is_leader_rank
        FROM cm_gang_ranks WHERE gang_id=? ORDER BY tier DESC,id ASC]], { gangId }) or {}

    local leaders = {}
    for _, rank in ipairs(ranks) do
        if CMGangDbTrue(rank.is_leader_rank) then leaders[#leaders + 1] = rank end
    end

    -- Multiple leader ranks are ambiguous and must remain a hard failure.
    if #leaders > 1 then return false, 'multiple_leader_ranks' end

    local leaderRank = leaders[1]
    if not leaderRank then
        local occupiedTier100
        for _, rank in ipairs(ranks) do
            if tonumber(rank.tier) == 100 then occupiedTier100 = rank; break end
        end
        if occupiedTier100 then
            local replacementTier = firstFreeTier(ranks, occupiedTier100.id)
            if not replacementTier then return false, 'rank_tiers_exhausted' end
            local moved = MySQL.update.await([[UPDATE cm_gang_ranks SET tier=?
                WHERE id=? AND gang_id=? AND is_leader_rank=0]],
                { replacementTier, occupiedTier100.id, gangId })
            if tonumber(moved) ~= 1 then return false, 'tier_100_recovery_failed' end
            occupiedTier100.tier = replacementTier
        end
        local rankId = MySQL.insert.await([[INSERT INTO cm_gang_ranks
            (gang_id,tier,name,permissions,is_leader_rank) VALUES (?,100,'Leader',?,1)]],
            { gangId, json.encode(allGangPermissions()) })
        if not rankId then return false, 'leader_rank_create_failed' end
        leaderRank = { id = rankId, tier = 100, is_leader_rank = 1 }
        print(('^3[cm-gang] repaired %s: created dedicated tier-100 leader rank^7'):format(gangId))
    elseif tonumber(leaderRank.tier) ~= 100 then
        local occupiedTier100
        for _, rank in ipairs(ranks) do
            if tonumber(rank.id) ~= tonumber(leaderRank.id) and tonumber(rank.tier) == 100 then
                occupiedTier100 = rank
                break
            end
        end
        if occupiedTier100 then
            local replacementTier = firstFreeTier(ranks, occupiedTier100.id)
            if not replacementTier then return false, 'rank_tiers_exhausted' end
            local moved = MySQL.update.await([[UPDATE cm_gang_ranks SET tier=?
                WHERE id=? AND gang_id=? AND is_leader_rank=0]],
                { replacementTier, occupiedTier100.id, gangId })
            if tonumber(moved) ~= 1 then return false, 'tier_100_recovery_failed' end
            print(('^3[cm-gang] repaired %s: moved non-leader rank %s from tier 100 to tier %d^7')
                :format(gangId, tostring(occupiedTier100.id), replacementTier))
        end
        local changed = MySQL.update.await([[UPDATE cm_gang_ranks SET tier=100,permissions=?
            WHERE id=? AND gang_id=? AND is_leader_rank=1]],
            { json.encode(allGangPermissions()), leaderRank.id, gangId })
        if changed == nil then return false, 'leader_rank_tier_recovery_failed' end
        print(('^3[cm-gang] repaired %s: restored leader rank to tier 100^7'):format(gangId))
    else
        -- Keep the dedicated leader rank fully privileged without rewriting
        -- any custom non-leader permissions.
        MySQL.update.await([[UPDATE cm_gang_ranks SET permissions=?
            WHERE id=? AND gang_id=? AND is_leader_rank=1]],
            { json.encode(allGangPermissions()), leaderRank.id, gangId })
    end

    -- Ensure there is at least one safe non-leader rank so recovery/member
    -- reassignment never needs to use the dedicated Leader rank.
    local nonLeaderCount = tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM cm_gang_ranks WHERE gang_id=? AND is_leader_rank=0', { gangId })) or 0
    if nonLeaderCount == 0 then
        local current = MySQL.query.await('SELECT id,tier FROM cm_gang_ranks WHERE gang_id=?', { gangId }) or {}
        local fallbackTier = firstFreeTier(current)
        if not fallbackTier then return false, 'rank_tiers_exhausted' end
        local fallbackPermissions = { ['gang.view_members'] = true, ['gang.chat'] = true }
        local rankId = MySQL.insert.await([[INSERT INTO cm_gang_ranks
            (gang_id,tier,name,permissions,is_leader_rank) VALUES (?,?,'Member',?,0)]],
            { gangId, fallbackTier, json.encode(fallbackPermissions) })
        if not rankId then return false, 'fallback_rank_create_failed' end
        print(('^3[cm-gang] repaired %s: created fallback non-leader rank at tier %d^7'):format(gangId, fallbackTier))
    end

    return true
end

local function repairRecoverableLeadershipState(gangId)
    local leaderRankId = tonumber(MySQL.scalar.await(
        'SELECT id FROM cm_gang_ranks WHERE gang_id=? AND is_leader_rank=1 LIMIT 1', { gangId }))
    local fallbackRankId = tonumber(MySQL.scalar.await(
        'SELECT id FROM cm_gang_ranks WHERE gang_id=? AND is_leader_rank=0 ORDER BY tier DESC,id ASC LIMIT 1', { gangId }))
    if not leaderRankId or not fallbackRankId then return false, 'rank_baseline_missing' end

    -- Nobody who is not the gang leader may remain assigned to the dedicated
    -- leader rank, even if an older build left that combination behind.
    local demoted = MySQL.update.await([[UPDATE cm_gang_members SET rank_id=?
        WHERE gang_id=? AND rank_id=? AND is_leader=0]],
        { fallbackRankId, gangId, leaderRankId })
    if tonumber(demoted) and tonumber(demoted) > 0 then
        print(('^3[cm-gang] repaired %s: moved %d non-leader member(s) off Leader rank^7')
            :format(gangId, tonumber(demoted)))
    end

    local pointer = MySQL.scalar.await('SELECT leader_character_id FROM cm_gangs WHERE gang_id=? LIMIT 1', { gangId })
    pointer = pointer and tostring(pointer) or nil
    local leaderMembers = MySQL.query.await([[SELECT character_id,rank_id FROM cm_gang_members
        WHERE gang_id=? AND is_leader=1]], { gangId }) or {}

    if #leaderMembers > 1 then return false, 'multiple_leader_members' end

    if #leaderMembers == 1 then
        local memberCid = tostring(leaderMembers[1].character_id)
        if pointer and pointer ~= memberCid then
            return false, 'leader_pointer_conflicts_with_leader_member'
        end
        MySQL.update.await([[UPDATE cm_gang_members SET rank_id=?
            WHERE gang_id=? AND character_id=? AND is_leader=1]],
            { leaderRankId, gangId, memberCid })
        if not pointer then
            MySQL.update.await('UPDATE cm_gangs SET leader_character_id=? WHERE gang_id=?', { memberCid, gangId })
            print(('^3[cm-gang] repaired %s: restored leader pointer to CID %s^7'):format(gangId, memberCid))
        end
    elseif pointer then
        local member = MySQL.single.await([[SELECT id,gang_id FROM cm_gang_members
            WHERE character_id=? LIMIT 1]], { pointer })
        if member and tostring(member.gang_id) == gangId then
            local promoted = MySQL.update.await([[UPDATE cm_gang_members SET is_leader=1,rank_id=?
                WHERE id=? AND gang_id=?]], { leaderRankId, member.id, gangId })
            if tonumber(promoted) ~= 1 then return false, 'leader_member_recovery_failed' end
            print(('^3[cm-gang] repaired %s: restored leader membership for CID %s^7'):format(gangId, pointer))
        else
            -- A stale pointer without a matching member cannot safely create a
            -- membership automatically. Clear only the pointer so cm-admin can
            -- assign a leader once the resource is ready.
            MySQL.update.await('UPDATE cm_gangs SET leader_character_id=NULL WHERE gang_id=?', { gangId })
            print(('^3[cm-gang] repaired %s: cleared stale leader pointer CID %s^7'):format(gangId, pointer))
        end
    end

    return true
end

local function repairRecoverableSchemaState()
    -- Give a clear migration error before issuing recovery queries.
    for _, tableName in ipairs({ 'cm_gang_ranks', 'cm_gang_members', 'cm_gang_facilities', 'cm_gangs' }) do
        local exists = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema=DATABASE() AND table_name=?]], { tableName })) or 0
        if exists ~= 1 then
            error(('missing table %s; apply all cm-gang sql migrations in order'):format(tableName))
        end
    end

    for _, gangId in ipairs(Config.GangIds) do
        local ok, reason = repairRecoverableRankBaseline(gangId)
        if not ok then
            error(('gang %s automatic rank recovery failed: %s'):format(gangId, tostring(reason)))
        end

        local leadershipOk, leadershipReason = repairRecoverableLeadershipState(gangId)
        if not leadershipOk then
            error(('gang %s automatic leadership recovery failed: %s'):format(gangId, tostring(leadershipReason)))
        end

        -- Missing facility rows are safe to recreate because the unique key
        -- protects existing configured locations from being overwritten.
        for facilityType in pairs(Config.FacilityTypes or {}) do
            MySQL.insert.await([[INSERT IGNORE INTO cm_gang_facilities
                (gang_id,facility_type,enabled) VALUES (?,?,0)]], { gangId, facilityType })
        end

        -- Compatibility repair for the former multi-facility admin UI. It
        -- used the same success message for armory/stash/fleet/profit, so an
        -- operator could save every service point while leaving the actual
        -- primary contact empty. Copy only the newest configured legacy point
        -- into an empty headquarters row; never overwrite a real contact.
        local headquarters=MySQL.single.await([[SELECT x,y,z FROM cm_gang_facilities
            WHERE gang_id=? AND facility_type='headquarters' LIMIT 1]],{gangId})
        if not headquarters or tonumber(headquarters.x)==nil or tonumber(headquarters.y)==nil or tonumber(headquarters.z)==nil then
            local legacy=MySQL.single.await([[SELECT x,y,z,heading,updated_by FROM cm_gang_facilities
                WHERE gang_id=? AND facility_type IN ('armory','stash','fleet','profit')
                  AND x IS NOT NULL AND y IS NOT NULL AND z IS NOT NULL
                ORDER BY updated_at DESC,id DESC LIMIT 1]],{gangId})
            if legacy then
                local models=Config.ContactNpcs[gangId] and Config.ContactNpcs[gangId].models or {}
                local model=tostring(models[1] or '')
                local repaired=MySQL.update.await([[UPDATE cm_gang_facilities SET enabled=1,npc_model=NULLIF(?,''),
                    x=?,y=?,z=?,heading=?,routing_bucket=0,updated_by=?
                    WHERE gang_id=? AND facility_type='headquarters' AND x IS NULL AND y IS NULL AND z IS NULL]],
                    {model,legacy.x,legacy.y,legacy.z,legacy.heading,legacy.updated_by,gangId})
                if tonumber(repaired)==1 then
                    print(('[cm-gang] repaired primary contact location gang=%s from legacy facility configuration'):format(gangId))
                end
            end
        end
    end
end

local function validateSchema()
    for _, tableName in ipairs(REQUIRED_TABLES) do
        local exists = tonumber(MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema = DATABASE() AND table_name = ?
        ]], { tableName })) or 0
        if exists ~= 1 then
            error(('missing table %s; apply all cm-gang sql migrations in order'):format(tableName))
        end
    end

    for tableName, columns in pairs(REQUIRED_COLUMNS) do
        for _, columnName in ipairs(columns) do
            local exists = tonumber(MySQL.scalar.await([[
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?
            ]], { tableName, columnName })) or 0
            if exists ~= 1 then
                error(('missing column %s.%s; apply all cm-gang sql migrations in order'):format(tableName, columnName))
            end
        end
    end

    for tableName, indexes in pairs(REQUIRED_UNIQUE_INDEXES) do
        for _, indexName in ipairs(indexes) do
            local exists = tonumber(MySQL.scalar.await([[
                SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
                WHERE table_schema=DATABASE() AND table_name=? AND index_name=? AND non_unique=0
            ]], { tableName, indexName })) or 0
            if exists ~= 1 then
                error(('missing critical unique index %s.%s; apply all cm-gang sql migrations in order'):format(tableName, indexName))
            end
        end
    end

    -- Legacy gang_1..gang_4 rows may coexist in this table after the
    -- five-gang migration (kept for audit/manual recovery), so only the
    -- canonical rows are counted/ordered here. Legacy rows are never
    -- validated or repaired by this function.
    local rows = MySQL.query.await('SELECT gang_id FROM cm_gangs ORDER BY gang_id') or {}
    local canonicalRows = {}
    for _, row in ipairs(rows) do
        if Config.IsFixedGangId(row.gang_id) then canonicalRows[#canonicalRows + 1] = row.gang_id end
    end
    table.sort(canonicalRows)
    local expected = { table.unpack(Config.GangIds) }
    table.sort(expected)
    if #canonicalRows ~= #expected then
        error(('expected exactly %d canonical cm_gangs rows, found %d'):format(#expected, #canonicalRows))
    end
    for index, gangId in ipairs(expected) do
        if canonicalRows[index] ~= gangId then
            error(('invalid canonical gang row at index %d: %s'):format(index, tostring(canonicalRows[index])))
        end
    end

    for _, gangId in ipairs(Config.GangIds) do
        local leaderRanks = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM cm_gang_ranks WHERE gang_id = ? AND is_leader_rank = 1', { gangId })) or 0
        local nonLeaderRanks = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM cm_gang_ranks WHERE gang_id = ? AND is_leader_rank = 0', { gangId })) or 0
        if leaderRanks ~= 1 then
            error(('gang %s must have exactly one leader rank; found %d'):format(gangId, leaderRanks))
        end
        if nonLeaderRanks < 1 then
            error(('gang %s must have at least one non-leader rank'):format(gangId))
        end
        local leaderTier = tonumber(MySQL.scalar.await(
            'SELECT tier FROM cm_gang_ranks WHERE gang_id=? AND is_leader_rank=1 LIMIT 1', { gangId }))
        local invalidTier100 = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM cm_gang_ranks WHERE gang_id=? AND is_leader_rank=0 AND tier=100', { gangId })) or 0
        if leaderTier ~= 100 or invalidTier100 ~= 0 then
            error(('gang %s leader rank must exclusively own tier 100; repair through cm-admin'):format(gangId))
        end
        local facilities = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM cm_gang_facilities WHERE gang_id = ?', { gangId })) or 0
        local expectedFacilities = 0
        for _ in pairs(Config.FacilityTypes or {}) do expectedFacilities = expectedFacilities + 1 end
        if facilities ~= expectedFacilities then
            error(('gang %s must have exactly %d facility rows; found %d'):format(gangId, expectedFacilities, facilities))
        end
        local mismatchedLeaderRanks = tonumber(MySQL.scalar.await([[
            SELECT COUNT(*) FROM cm_gang_members m
            JOIN cm_gang_ranks r ON r.id=m.rank_id AND r.gang_id=m.gang_id
            WHERE m.gang_id=? AND ((m.is_leader=1 AND r.is_leader_rank<>1) OR (m.is_leader=0 AND r.is_leader_rank=1))
        ]], { gangId })) or 0
        if mismatchedLeaderRanks ~= 0 then
            error(('gang %s has %d member(s) with inconsistent leader rank state; repair through cm-admin'):format(gangId, mismatchedLeaderRanks))
        end
        local leaderPointerMismatch = tonumber(MySQL.scalar.await([[
            SELECT COUNT(*) FROM cm_gangs g
            LEFT JOIN cm_gang_members m ON m.gang_id=g.gang_id AND m.is_leader=1
            WHERE g.gang_id=? AND (
                (g.leader_character_id IS NULL AND m.character_id IS NOT NULL) OR
                (g.leader_character_id IS NOT NULL AND (m.character_id IS NULL OR m.character_id<>g.leader_character_id))
            )
        ]], { gangId })) or 0
        if leaderPointerMismatch ~= 0 then
            error(('gang %s leader pointer/member state is inconsistent; repair through cm-admin'):format(gangId))
        end
    end
end

function CMGangIsDatabaseReady()
    return CMGangDatabaseReady == true, CMGangDatabaseError
end

exports('IsDatabaseReady', CMGangIsDatabaseReady)

MySQL.ready(function()
    CreateThread(function()
        local ok, err = xpcall(function()
            repairRecoverableSchemaState()
            validateSchema()
        end, debug.traceback)
        if not ok then
            CMGangDatabaseReady = false
            CMGangDatabaseError = tostring(err)
            print('^1[cm-gang] DATABASE NOT READY^7')
            print(('[cm-gang] %s'):format(CMGangDatabaseError))
            return
        end

        CMGangDatabaseError = nil
        CMGangDatabaseReady = true
        print('^2[cm-gang] fixed five-gang schema ready^7')
    end)
end)
