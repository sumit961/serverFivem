-- ============================================================
-- cm-family | sv_hq.lua | v1.8.0
-- Authoritative Family Headquarters upgrade system.
-- Server-authoritative purchase and verification; funded by family treasury.
-- ============================================================

local B = CMFamilyBridge

local UPGRADE_KEY_ALIASES = {
    ['storage'] = 'storage_capacity',
    ['storage_capacity'] = 'storage_capacity',
    ['armory'] = 'weapon_storage_capacity',
    ['weapon_storage_capacity'] = 'weapon_storage_capacity',
    ['garage_slots'] = 'garage_slots',
    ['garage'] = 'garage_slots',
    ['command_room'] = 'meeting_room',
    ['meeting_room'] = 'meeting_room',
}

local function normalizeUpgradeKey(key)
    local k = tostring(key or ''):lower():gsub('%s+', '_')
    return UPGRADE_KEY_ALIASES[k] or k
end

local upgradeLocks = {}

function GetFamilyHQUpgrades(familyId)
    familyId = tonumber(familyId)
    if not familyId then return {} end

    local rows = MySQL.query.await([[
        SELECT upgrade_key, tier, purchased_by, purchased_at
        FROM cm_family_hq_upgrades
        WHERE family_id = ?
    ]], { familyId }) or {}

    local currentTiers = {}
    for _, r in ipairs(rows) do
        local nk = normalizeUpgradeKey(r.upgrade_key)
        currentTiers[nk] = tonumber(r.tier) or 1
        currentTiers[r.upgrade_key] = tonumber(r.tier) or 1
    end

    local catalog = {}
    for key, cfg in pairs(Config.HQUpgrades or {}) do
        local cur = currentTiers[key] or 0
        local nextTier = cur + 1
        local nextCfg = cfg.tiers and cfg.tiers[nextTier]
        catalog[#catalog + 1] = {
            key = key,
            label = cfg.label,
            description = cfg.description,
            currentTier = cur,
            maxTier = cfg.maxTier or 1,
            isMax = cur >= (cfg.maxTier or 1),
            nextCost = nextCfg and nextCfg.cost or 0,
            nextMinLevel = nextCfg and nextCfg.minLevel or 1,
            nextLabel = nextCfg and nextCfg.label or 'Unlocked',
        }
    end

    table.sort(catalog, function(a, b) return a.label < b.label end)
    return catalog
end
exports('GetFamilyHQUpgrades', GetFamilyHQUpgrades)

function GetFamilyHQUpgradeLevel(familyId, upgradeKey)
    familyId = tonumber(familyId)
    upgradeKey = normalizeUpgradeKey(upgradeKey)
    if not familyId or upgradeKey == '' then return 0 end

    -- Query both canonical key and raw key if they differ
    local tier = MySQL.scalar.await([[
        SELECT tier FROM cm_family_hq_upgrades
        WHERE family_id = ? AND (upgrade_key = ? OR upgrade_key = ?)
        ORDER BY tier DESC
        LIMIT 1
    ]], { familyId, upgradeKey, tostring(upgradeKey) })

    return tonumber(tier) or 0
end
exports('GetFamilyHQUpgradeLevel', GetFamilyHQUpgradeLevel)

function GetFamilyHQModifiers(familyId)
    familyId = tonumber(familyId)
    if not familyId then
        return {
            storageBonusSlots = 0,
            armoryBonusSlots = 0,
            garageBonusSlots = 0,
            commandRoomUnlocked = false,
        }
    end

    local storageTier = GetFamilyHQUpgradeLevel(familyId, 'storage_capacity')
    local armoryTier = GetFamilyHQUpgradeLevel(familyId, 'weapon_storage_capacity')
    local garageTier = GetFamilyHQUpgradeLevel(familyId, 'garage_slots')
    local commandTier = GetFamilyHQUpgradeLevel(familyId, 'meeting_room')

    return {
        storageBonusSlots = storageTier == 1 and 10 or (storageTier == 2 and 20 or (storageTier >= 3 and 35 or 0)),
        armoryBonusSlots = armoryTier == 1 and 10 or (armoryTier == 2 and 20 or (armoryTier >= 3 and 35 or 0)),
        garageBonusSlots = garageTier == 1 and 2 or (garageTier == 2 and 4 or (garageTier >= 3 and 6 or 0)),
        commandRoomUnlocked = commandTier >= 1,
        storageTier = storageTier,
        armoryTier = armoryTier,
        garageTier = garageTier,
        commandTier = commandTier,
    }
end
exports('GetFamilyHQModifiers', GetFamilyHQModifiers)

function GetFamilySharedVehicleLimit(familyId)
    familyId = tonumber(familyId)
    if not familyId then return 4 end

    local prog = GetFamilyProgression(familyId)
    local lvl = prog and prog.level or 1
    local lvlUnlocks = Config.GetLevelUnlocks and Config.GetLevelUnlocks(lvl) or {}
    local baseLimit = lvlUnlocks.sharedVehicleLimit or 4

    local garageTier = GetFamilyHQUpgradeLevel(familyId, 'garage_slots')
    local bonus = garageTier == 1 and 2 or (garageTier == 2 and 4 or (garageTier >= 3 and 6 or 0))

    return baseLimit + bonus
end
exports('GetFamilySharedVehicleLimit', GetFamilySharedVehicleLimit)

function PurchaseHQUpgrade(actorCid, upgradeKey)
    actorCid = tostring(actorCid)
    local canonicalKey = normalizeUpgradeKey(upgradeKey)

    local rank, fam = GetRankForCid(actorCid)
    if not rank or not fam then return false, 'not_in_family' end
    if not (rank.is_founder or RankHasPermission(rank, 'house.manage_access') or RankHasPermission(rank, 'family.manage_ranks')) then
        return false, 'no_permission'
    end

    -- Mutex against simultaneous purchase requests for the same family
    if upgradeLocks[fam.id] then
        return false, 'Another upgrade transaction is currently processing. Please try again in a moment.'
    end
    upgradeLocks[fam.id] = true

    local function releaseLock(ok, ret)
        upgradeLocks[fam.id] = nil
        return ok, ret
    end

    local upgradeCfg = Config.HQUpgrades and Config.HQUpgrades[canonicalKey]
    if not upgradeCfg then
        return releaseLock(false, 'unknown_upgrade')
    end

    -- Re-read exact current tier from DB under lock to prevent race condition
    local currentTier = GetFamilyHQUpgradeLevel(fam.id, canonicalKey)
    local targetTier = currentTier + 1
    if targetTier > (upgradeCfg.maxTier or 1) then
        return releaseLock(false, 'already_max_tier')
    end

    local tierCfg = upgradeCfg.tiers and upgradeCfg.tiers[targetTier]
    if not tierCfg then
        return releaseLock(false, 'tier_not_configured')
    end

    -- Check family progression level requirement
    local prog = GetFamilyProgression(fam.id)
    local currentLevel = prog and prog.level or 1
    if currentLevel < (tierCfg.minLevel or 1) then
        return releaseLock(false, ('Requires Family Level %d (current: Level %d).'):format(tierCfg.minLevel or 1, currentLevel))
    end

    local cost = math.floor(tonumber(tierCfg.cost) or 0)
    if cost > 0 then
        -- Atomic deduction from family bank
        local affected = MySQL.update.await([[
            UPDATE cm_families
            SET bank_balance = bank_balance - ?
            WHERE id = ? AND bank_balance >= ?
        ]], { cost, fam.id, cost })

        if not affected or affected == 0 then
            return releaseLock(false, 'Insufficient family bank balance.')
        end

        local newBalance = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { fam.id })) or 0
        fam.bank_balance = newBalance

        MySQL.insert.await([[
            INSERT INTO cm_family_bank_log (family_id, character_id, direction, category, amount, balance_after, reason)
            VALUES (?, ?, 'withdraw', 'hq_upgrade', ?, ?, ?)
        ]], { fam.id, actorCid, cost, newBalance, ('hq_upgrade:%s:t%d'):format(canonicalKey, targetTier) })
    end

    -- Persist upgrade
    pcall(function()
        MySQL.query.await([[
            INSERT INTO cm_family_hq_upgrades (family_id, upgrade_key, tier, purchased_by, purchased_at)
            VALUES (?, ?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE
              tier = VALUES(tier),
              purchased_by = VALUES(purchased_by),
              purchased_at = NOW()
        ]], { fam.id, canonicalKey, targetTier, actorCid })
    end)

    LogFamily(fam.id, actorCid, 'hq_upgrade_purchased', {
        upgradeKey = canonicalKey,
        tier = targetTier,
        cost = cost,
        label = tierCfg.label,
    }, { severity = 'info' })

    -- Advance any relevant objectives
    if type(AdvanceFamilyObjective) == 'function' then
        AdvanceFamilyObjective(fam.id, 'family_actions', 1, actorCid)
    end

    return releaseLock(true, {
        upgradeKey = canonicalKey,
        newTier = targetTier,
        cost = cost,
    })
end
exports('PurchaseHQUpgrade', PurchaseHQUpgrade)

