-- ============================================================
-- cm-house | family-house lifecycle integration | v1.7.7, refactored v1.8.17
--
-- A linked property is the family's authoritative home. Property access stays
-- rank-gated through CanAccessProperty. When that property is sold, evicted or
-- deleted, the linked family must be removed with it instead of being left as
-- an orphan with a nil house_id.
--
-- cm-family owns every cm_family_* table and is the only resource that
-- deletes them. This file no longer builds DELETE statements against those
-- tables itself -- FL.FinalizeDeletedFamily calls cm-family's single
-- authoritative export (FinalizeHouseFamilyDeletion), which performs the
-- transactional, idempotent row deletion AND clears cm-family's runtime
-- caches / online members' replicated state in one call. Callers must invoke
-- FL.FinalizeDeletedFamily and check its result BEFORE mutating any
-- cm-house table, so a failure here never leaves a half-deleted family.
-- ============================================================

CMHouseFamilyLifecycle = CMHouseFamilyLifecycle or {}
local FL = CMHouseFamilyLifecycle

local FAMILY_RESOURCE = tostring(Config.Family and Config.Family.resource or 'cm-family')

local function normalizedFamilyId(value)
    local id = tonumber(value)
    if not id or id <= 0 then return nil end
    return math.floor(id)
end

function FL.IsLinkedFamilyHouse(house)
    return type(house) == 'table' and normalizedFamilyId(house.family_id) ~= nil
end

function FL.GetContext(house, options)
    options = type(options) == 'table' and options or {}
    if type(house) ~= 'table' then return false, 'house_not_found' end

    local familyId = normalizedFamilyId(house.family_id)
    if not familyId then return true, nil end

    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT id, name, founder_cid, house_id, bank_balance
            FROM cm_families
            WHERE id = ?
            LIMIT 1
        ]], { familyId })
    end)
    if not ok then
        print(('[cm-house] family lifecycle lookup failed for family %s: %s')
            :format(tostring(familyId), tostring(row)))
        return false, 'family_database_unavailable'
    end

    -- A stale house.family_id can exist after an old partial migration. Keep the
    -- id so child rows are still cleaned, but do not invent family metadata.
    if not row then
        return true, {
            id = familyId,
            name = ('Family #%d'):format(familyId),
            founderCid = nil,
            houseId = tonumber(house.id),
            bankBalance = 0,
            orphanLink = true,
        }
    end

    local linkedHouseId = tonumber(row.house_id)
    if linkedHouseId and linkedHouseId ~= tonumber(house.id) then
        return false, 'family_is_linked_to_another_house'
    end

    local bankBalance = math.floor(tonumber(row.bank_balance) or 0)
    if options.requireEmptyBank == true and bankBalance ~= 0 then
        return false, ('family_bank_not_empty:%d'):format(bankBalance)
    end

    return true, {
        id = familyId,
        name = tostring(row.name or ('Family #%d'):format(familyId)),
        founderCid = row.founder_cid and tostring(row.founder_cid) or nil,
        houseId = linkedHouseId or tonumber(house.id),
        bankBalance = bankBalance,
        orphanLink = false,
    }
end

-- Ask cm-family to authoritatively delete every cm_family_* row for this
-- family and clear its own runtime caches / online members' replicated
-- state. This is the ONLY step that deletes family-domain data -- cm-house
-- never touches a cm_family_* table directly. Callers MUST check the
-- returned (ok, ...) and must not mutate any cm-house table if it is false:
-- a failure here (including cm-family being stopped) fails the whole
-- operation closed rather than falling back to a local DELETE list.
--
-- Idempotent: cm-family's underlying delete is transactional and safe to
-- call twice (an already-deleted family simply deletes zero rows and still
-- reports success), so a retried house-lifecycle action is always safe.
function FL.FinalizeDeletedFamily(context, houseId, reason, actorCid)
    if type(context) ~= 'table' or not normalizedFamilyId(context.id) then return true end
    local familyId = normalizedFamilyId(context.id)

    if GetResourceState(FAMILY_RESOURCE) ~= 'started' then
        print(('[cm-house] ^1cannot finalize family %s for house %s: %s is not running^7')
            :format(tostring(familyId), tostring(houseId), FAMILY_RESOURCE))
        return false, 'family_resource_unavailable'
    end

    local ok, result, why = pcall(function()
        return exports[FAMILY_RESOURCE]:FinalizeHouseFamilyDeletion(
            familyId, tonumber(houseId), tostring(reason or 'house_lifecycle'), actorCid)
    end)
    if not ok or result ~= true then
        print(('[cm-house] ^1family deletion failed for family %s / house %s: %s^7')
            :format(tostring(familyId), tostring(houseId), tostring(why or result)))
        return false, why or result
    end
    return true
end

function FL.FamilyDeletionMessage(context)
    if type(context) ~= 'table' or not normalizedFamilyId(context.id) then return nil end
    return ('%s was disbanded because its family house was removed.')
        :format(tostring(context.name or ('Family #' .. tostring(context.id))))
end

-- Repair stale house links left by older builds where the family row was
-- deleted independently. This never invents a family; it only removes an
-- unusable pointer so the property falls back to owner-only access.
MySQL.ready(function()
    CreateThread(function()
        Wait(3000)
        local ok, rows = pcall(function()
            return MySQL.query.await([[
                SELECT h.id, h.family_id
                FROM cm_houses h
                LEFT JOIN cm_families f ON f.id = h.family_id
                WHERE h.family_id IS NOT NULL AND f.id IS NULL
            ]]) or {}
        end)
        if not ok then
            print(('[cm-house] orphan family-link reconciliation failed: %s'):format(tostring(rows)))
            return
        end
        for _, row in ipairs(rows) do
            local houseId = tonumber(row.id)
            MySQL.update.await('UPDATE cm_houses SET family_id = NULL WHERE id = ?', { houseId })
            if Houses and Houses[houseId] then
                Houses[houseId].family_id = nil
                TriggerClientEvent('cm-house:client:syncHouse', -1, BuildClientHouse(Houses[houseId]))
            end
            print(('[cm-house] cleared orphan family link %s from house %s')
                :format(tostring(row.family_id), tostring(houseId)))
        end
    end)
end)

-- Writable and family-scoped: matches the gate every sibling export in
-- sv_phase2.lua uses. cm-family already validates founder/rank before
-- calling this, but cm-house owns house state and must not trust that on
-- faith -- fail closed for any caller outside the family integration scope.
function FL.TransferFamilyHouseOwnership(familyId, newOwnerCid, actorCid)
    if type(CMHouseIntegrationAllowed) == 'function' and not CMHouseIntegrationAllowed('family') then
        return false, 'resource_not_authorized'
    end

    familyId = normalizedFamilyId(familyId)
    newOwnerCid = tostring(newOwnerCid or '')
    if not familyId or newOwnerCid == '' then return false, 'invalid_arguments' end

    local houseRow = MySQL.single.await([[
        SELECT id, owner_cid, family_id
        FROM cm_houses
        WHERE family_id = ?
        LIMIT 1
    ]], { familyId })
    if not houseRow then return false, 'no_linked_family_house' end

    local houseId = tonumber(houseRow.id)
    local previousOwner = houseRow.owner_cid

    local updated = MySQL.update.await([[
        UPDATE cm_houses
        SET owner_cid = ?
        WHERE id = ? AND family_id = ?
    ]], { newOwnerCid, houseId, familyId })

    if not updated or updated <= 0 then
        -- The DB update did not commit. Never mutate the in-memory ownership
        -- cache as if the transfer succeeded.
        return false, 'house_ownership_update_failed'
    end

    if Houses and Houses[houseId] then
        Houses[houseId].owner_cid = tonumber(newOwnerCid) or newOwnerCid
        TriggerClientEvent('cm-house:client:syncHouse', -1, BuildClientHouse(Houses[houseId]))
    end

    -- Keep the OwnerHouses reverse index in sync with the DB in the same
    -- successful path, exactly like buyHouse/sellHouse do. Previously this
    -- was left stale until the next full LoadHouses() (a server restart).
    if OwnerHouses then
        local previousKey = previousOwner ~= nil and tostring(previousOwner) or nil
        if previousKey and OwnerHouses[previousKey] then
            for i = #OwnerHouses[previousKey], 1, -1 do
                if tonumber(OwnerHouses[previousKey][i]) == houseId then
                    table.remove(OwnerHouses[previousKey], i)
                end
            end
        end
        -- Legacy in-memory keys may be numeric rather than string; clear both.
        local previousNumericKey = tonumber(previousOwner)
        if previousNumericKey and OwnerHouses[previousNumericKey] then
            for i = #OwnerHouses[previousNumericKey], 1, -1 do
                if tonumber(OwnerHouses[previousNumericKey][i]) == houseId then
                    table.remove(OwnerHouses[previousNumericKey], i)
                end
            end
        end

        local newOwnerKey = tonumber(newOwnerCid) or newOwnerCid
        OwnerHouses[newOwnerKey] = OwnerHouses[newOwnerKey] or {}
        local alreadyIndexed = false
        for _, existing in ipairs(OwnerHouses[newOwnerKey]) do
            if tonumber(existing) == houseId then alreadyIndexed = true break end
        end
        if not alreadyIndexed then
            OwnerHouses[newOwnerKey][#OwnerHouses[newOwnerKey] + 1] = houseId
        end
    end

    -- The transfer is integration-driven (cm-family authorizes it); attribute
    -- the log to the actor cm-family identified, not to the new owner, unless
    -- no actor was supplied.
    local logActor = actorCid ~= nil and tostring(actorCid) or newOwnerCid
    LogHouse(houseId, familyId, logActor, 'family_house_owner_transferred', {
        previousOwner = previousOwner,
        newOwner = newOwnerCid,
    })

    return true, houseId
end
exports('TransferFamilyHouseOwnership', FL.TransferFamilyHouseOwnership)

return FL
