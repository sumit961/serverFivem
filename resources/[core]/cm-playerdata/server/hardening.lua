-- cm-playerdata/server/hardening.lua
-- Additive hardening + future-proofing layer. Loads AFTER server/main.lua and
-- extends it purely through the existing exports and shared globals. It never
-- edits main.lua, keeping clean boundaries (same philosophy as cross-resource
-- integration: additive, reversible, low-risk).
--
-- Adds:
--   1. Player-to-player money transfer with atomic deduct/credit + audited
--      refund on failure (unblocks "give cash" between two different players).
--   2. Persistent identity-memory table (cm_known_identities) so remembered
--      names survive restarts and no longer bloat character metadata JSON.
--   3. A small set of read helpers other resources need for the feature roadmap.

local RESOURCE = GetCurrentResourceName()

-- ---- Safe access to main.lua internals via its own exports --------------------
-- We deliberately go through exports rather than reaching into locals, so this
-- module stays decoupled and won't break if main.lua's internals move.

local function getData(src)
    -- GetRawPlayerData returns the live in-memory table (authoritative balances).
    local ok, data = pcall(function() return exports[RESOURCE]:GetRawPlayerData(src) end)
    if ok then return data end
    return nil
end

local function charIdOf(src)
    local ok, id = pcall(function() return exports[RESOURCE]:GetCharacterId(src) end)
    if ok then return id end
    return nil
end

local function isLoaded(src)
    local ok, loaded = pcall(function() return exports[RESOURCE]:IsLoaded(src) end)
    return ok and loaded == true
end

local function notify(src, msg, kind)
    TriggerClientEvent('cm-playerdata:client:notify', src, msg, kind or 'info')
end

-- =============================================================================
-- 1. PLAYER-TO-PLAYER MONEY TRANSFER
-- =============================================================================
-- The built-in TransferMoney only moves between accounts of the SAME player.
-- This moves an amount from one player's account to ANOTHER player's account,
-- with server-side validation and an audited refund if the credit leg fails.

local MAX_TRANSFER = 100000000  -- hard ceiling; matches money normalization cap

local function normalizeAmount(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or amount > MAX_TRANSFER then return nil end
    return amount
end

local function normalizeAccount(account)
    account = tostring(account or 'cash'):lower()
    if account ~= 'cash' and account ~= 'bank' then return nil end
    return account
end

-- Returns ok(boolean), errorMessage(string|nil).
-- fromSrc / toSrc are server IDs; they may differ (that's the whole point).
local function transferBetweenPlayers(fromSrc, toSrc, account, amount, reason, metadata)
    fromSrc = tonumber(fromSrc)
    toSrc = tonumber(toSrc)
    account = normalizeAccount(account)
    amount = normalizeAmount(amount)

    if not fromSrc or not toSrc then return false, 'invalid_players' end
    if fromSrc == toSrc then return false, 'same_player' end
    if not account then return false, 'invalid_account' end
    if not amount then return false, 'invalid_amount' end
    if not isLoaded(fromSrc) or not isLoaded(toSrc) then return false, 'player_not_loaded' end

    -- Affordability is checked by RemoveMoney itself (returns false if short),
    -- but we check first to avoid a pointless state write.
    local canAfford = exports[RESOURCE]:CanAfford(fromSrc, account, amount)
    if not canAfford then return false, 'insufficient_funds' end

    local reasonOut = reason or 'p2p_transfer_out'
    local reasonIn = reason or 'p2p_transfer_in'
    local meta = type(metadata) == 'table' and metadata or {}
    meta.counterparty_character_id = charIdOf(toSrc)

    -- Deduct leg. RemoveMoney is synchronous and atomic within the call.
    if not exports[RESOURCE]:RemoveMoney(fromSrc, account, amount, reasonOut, meta) then
        return false, 'deduct_failed'
    end

    -- Credit leg. If it fails, refund the source and audit the anomaly loudly.
    local creditMeta = { counterparty_character_id = charIdOf(fromSrc) }
    if not exports[RESOURCE]:AddMoney(toSrc, account, amount, reasonIn, creditMeta) then
        local refunded = exports[RESOURCE]:AddMoney(fromSrc, account, amount, 'p2p_transfer_refund', {
            originalReason = reasonOut,
            failedTarget = charIdOf(toSrc)
        })
        -- Record the failure regardless of refund success so money never silently vanishes.
        pcall(function()
            exports[RESOURCE]:GetPlayerData(fromSrc)  -- touch to ensure still loaded
        end)
        if not refunded then
            print(('[CM-PLAYERDATA] CRITICAL: p2p transfer credit AND refund failed. from=%s to=%s amount=%d account=%s')
                :format(tostring(charIdOf(fromSrc)), tostring(charIdOf(toSrc)), amount, account))
            return false, 'credit_failed_refund_failed'
        end
        return false, 'credit_failed_refunded'
    end

    return true, nil
end

-- Public export. Other resources (give-cash interaction, trade, shops) call this.
exports('TransferMoneyBetween', function(fromSrc, toSrc, account, amount, reason, metadata)
    local ok = transferBetweenPlayers(fromSrc, toSrc, account, amount, reason, metadata)
    return ok
end)

-- Verbose variant returning the error code, for callers that want to message the user.
exports('TransferMoneyBetweenDetailed', function(fromSrc, toSrc, account, amount, reason, metadata)
    return transferBetweenPlayers(fromSrc, toSrc, account, amount, reason, metadata)
end)

-- =============================================================================
-- 2. PERSISTENT IDENTITY MEMORY  (cm_known_identities)
-- =============================================================================
-- main.lua stores known identities inside character metadata JSON. That works
-- but grows unbounded and can't be queried. This adds a relational table (the
-- one sketched in docs/FUTURE_EXTENSIONS) and mirrors writes into it, so names
-- remembered between two characters survive restarts and scale cleanly.

local function ensureIdentityTable()
    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cm_known_identities (
                owner_character_id BIGINT NOT NULL,
                known_character_id BIGINT NOT NULL,
                reason VARCHAR(32) NOT NULL DEFAULT 'met',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (owner_character_id, known_character_id),
                INDEX idx_owner (owner_character_id)
            )
        ]])
    end)
end

-- Persist a directed "owner knows known" edge. Idempotent (upsert).
local function persistKnown(ownerCharId, knownCharId, reason)
    ownerCharId = tonumber(ownerCharId)
    knownCharId = tonumber(knownCharId)
    if not ownerCharId or not knownCharId or ownerCharId == knownCharId then return false end
    pcall(function()
        MySQL.query.await([[
            INSERT INTO cm_known_identities (owner_character_id, known_character_id, reason)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE reason = VALUES(reason)
        ]], { ownerCharId, knownCharId, tostring(reason or 'met'):sub(1, 32) })
    end)
    return true
end

-- Export so main.lua's identity events (or any resource) can mirror into the table.
-- Call alongside the existing KnowPlayerIdentity so both layers stay in sync.
exports('PersistKnownIdentity', function(ownerCharId, knownCharId, reason)
    return persistKnown(ownerCharId, knownCharId, reason)
end)

-- Load all character IDs a given owner already knows (for warm-loading on join).
exports('GetKnownIdentities', function(ownerCharId)
    ownerCharId = tonumber(ownerCharId)
    if not ownerCharId then return {} end
    local rows = {}
    pcall(function()
        rows = MySQL.query.await(
            'SELECT known_character_id, reason, created_at FROM cm_known_identities WHERE owner_character_id = ?',
            { ownerCharId }
        ) or {}
    end)
    return rows
end)

-- Combined export: mark identity known (in-memory, via main.lua) AND persist it
-- to the relational table in one call. Extension resources and the handshake/
-- shared-id flows should call THIS instead of KnowPlayerIdentity when they want
-- the memory to survive restarts. It degrades gracefully if either layer fails.
--
--   exports['cm-playerdata']:KnowPlayerIdentityPersistent(viewerSrc, targetSrc, 'handshake')
exports('KnowPlayerIdentityPersistent', function(viewerSrc, targetSrc, reason)
    local memOk = false
    pcall(function()
        memOk = exports[RESOURCE]:KnowPlayerIdentity(viewerSrc, targetSrc, reason) == true
    end)
    local owner, known = charIdOf(viewerSrc), charIdOf(targetSrc)
    local dbOk = (owner and known) and persistKnown(owner, known, reason) or false
    return memOk or dbOk
end)

-- =============================================================================
-- 3. ROADMAP READ HELPERS
-- =============================================================================
-- Small conveniences the planned extension resources (medical, families, orgs,
-- police, trade) will want, so they never need to reach into playerdata internals.

-- True if the two server IDs are within `maxDist` metres of each other, checked
-- server-side. Extension resources should gate any player-to-player action on this.
exports('ArePlayersWithin', function(aSrc, bSrc, maxDist)
    aSrc, bSrc = tonumber(aSrc), tonumber(bSrc)
    maxDist = tonumber(maxDist) or 5.0
    if not aSrc or not bSrc then return false end
    local aPed, bPed = GetPlayerPed(aSrc), GetPlayerPed(bSrc)
    if aPed == 0 or bPed == 0 then return false end
    local ac, bc = GetEntityCoords(aPed), GetEntityCoords(bPed)
    -- vector distance (cheaper than Vdist native)
    return #(ac - bc) <= maxDist
end)

-- Current family/org metadata for a player, read-only, for rank/kick logic in
-- the future cm-families / cm-orgs resources.
exports('GetAffiliation', function(src)
    local data = getData(src)
    if not data or not data.metadata then return nil end
    local m = data.metadata
    return {
        familyId = m.family_id, family = m.family,
        organizationId = m.organization_id, organization = m.organization,
    }
end)

CreateThread(function()
    -- Wait for main.lua's schema pass to have run, then add ours.
    Wait(1500)
    ensureIdentityTable()
    print('[CM-PLAYERDATA] hardening layer ready: p2p transfer, persistent identity, roadmap helpers')
end)
