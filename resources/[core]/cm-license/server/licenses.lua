-- CM License System — License Management

Licenses = {}

-- HasLicense is called by other resources (police stops, vehicle shops) on hot
-- paths, so character rows are cached briefly and invalidated on every write.
local licenseCache = {}
local LICENSE_CACHE_TTL = 30

function Licenses.InvalidateCache(characterId)
    licenseCache[tonumber(characterId) or -1] = nil
end

local function characterLicenses(characterId)
    characterId = tonumber(characterId)
    if not characterId then return {} end

    local entry = licenseCache[characterId]
    if entry and (os.time() - entry.at) < LICENSE_CACHE_TTL then
        return entry.rows
    end

    local rows = Database.GetCharacterLicenses(characterId) or {}
    licenseCache[characterId] = { at = os.time(), rows = rows }
    return rows
end

-- Check if player has an active, unexpired license
function Licenses.HasLicense(characterId, licenseType)
    if not characterId or not licenseType then
        return false, 'invalid_params'
    end

    for _, license in ipairs(characterLicenses(characterId)) do
        if license.license_type == licenseType then
            if license.status ~= Constants.LICENSE_STATUS.ACTIVE then
                return false, license.status
            end
            if tonumber(license.expires_at) > os.time() then
                return true, license
            end
            return false, 'expired'
        end
    end

    return false, 'not_found'
end

-- Get all licenses for character, enriched with expiry info
function Licenses.GetLicenses(characterId)
    if not characterId then return {} end

    local licenses = {}
    for _, row in ipairs(characterLicenses(characterId)) do
        local license = Utils.DeepCopy(row)
        license.remainingDays = Utils.CalculateRemainingDays(license.expires_at)
        license.isExpired = Utils.IsExpired(license.expires_at)
        license.expiresAtDate = Utils.FormatDate(license.expires_at)
        license.issuedAtDate = Utils.FormatDate(license.issued_at)
        licenses[#licenses + 1] = license
    end

    return licenses
end

-- Get single license
function Licenses.GetLicense(characterId, licenseType)
    for _, license in ipairs(Licenses.GetLicenses(characterId)) do
        if license.license_type == licenseType then
            return license
        end
    end
    return nil
end

-- Compact summary for ID checks by other resources
function Licenses.GetLicenseSummary(characterId)
    local summary = {}
    for _, license in ipairs(Licenses.GetLicenses(characterId)) do
        summary[license.license_type] = {
            label = license.label,
            status = license.isExpired and Constants.LICENSE_STATUS.EXPIRED or license.status,
            expiresAt = tonumber(license.expires_at),
            expiresAtDate = license.expiresAtDate,
            remainingDays = license.remainingDays,
        }
    end
    return summary
end

-- Issue license to character
function Licenses.IssueLicense(characterId, licenseTypeId, validDays)
    if not characterId or not licenseTypeId then
        return false, 'invalid_params'
    end

    local licenseType = Cache.GetLicenseType(licenseTypeId)
    if not licenseType then
        return false, 'license_type_not_found'
    end

    local days = tonumber(validDays) or tonumber(licenseType.valid_days) or 30
    local ok, expiresAt = Database.IssueLicense(characterId, licenseTypeId, days)
    if not ok then
        return false, 'database_error'
    end

    Licenses.InvalidateCache(characterId)

    return true, {
        characterId = characterId,
        licenseTypeId = licenseTypeId,
        licenseType = licenseType.license_type,
        licenseLabel = licenseType.label,
        validDays = days,
        expiresAt = expiresAt,
    }
end

-- Revoke license (admin action, or the player discarding the physical card)
function Licenses.RevokeLicense(characterId, licenseTypeId, revokedBy, reason)
    if not characterId or not licenseTypeId or not revokedBy then
        return false, 'invalid_params'
    end

    local changed = Database.RevokeLicense(characterId, licenseTypeId, revokedBy, reason)
    Licenses.InvalidateCache(characterId)
    if not changed then
        return false, 'license_not_active'
    end

    local licenseType = Cache.GetLicenseType(licenseTypeId)
    if licenseType then
        Licenses.RemoveInventoryItem(characterId, licenseType.item_name)
    end

    return true
end

-- Check and cleanup expired licenses
function Licenses.CheckAndCleanupExpired(characterId)
    if not characterId then return 0 end

    local expiredLicenses = Database.GetExpiredLicenses(characterId)
    if not expiredLicenses or #expiredLicenses == 0 then
        return 0
    end

    local removedCount = 0
    for _, license in ipairs(expiredLicenses) do
        Database.MarkLicenseExpired(license.id)
        if license.item_name and Licenses.RemoveInventoryItem(characterId, license.item_name) then
            removedCount = removedCount + 1
        end
    end

    Licenses.InvalidateCache(characterId)
    return removedCount
end

-- Add license item to player inventory
function Licenses.AddInventoryItem(src, characterId, itemName, validDays, expiresAt)
    if not src or not itemName then
        return false, 'invalid_params'
    end

    local licenseClass = tostring(itemName):gsub('_license$', '')
    local metadata = {
        licenseType = licenseClass,
        licenseClass = licenseClass,
        characterId = characterId,
        issuedAt = os.time(),
        expiresAt = tonumber(expiresAt) or Utils.CalculateExpiration(validDays or 30),
        validDays = validDays or 30,
    }
    metadata.issuedAtDate = Utils.FormatDate(metadata.issuedAt)
    metadata.expiresAtDate = Utils.FormatDate(metadata.expiresAt)
    metadata.testCompletedAt = metadata.issuedAt
    metadata.testCompletedDate = metadata.issuedAtDate
    metadata.licenseNumber = ('CM-%s-%s-%s'):format(licenseClass:upper(), tostring(characterId), tostring(metadata.issuedAt))

    local charData = exports['cm-playerdata']:GetCharacterData(src)
    local character = charData and (charData.Character or charData.character) or charData
    metadata.firstName = character and (character.FirstName or character.firstName or character.first_name) or nil
    metadata.lastName = character and (character.LastName or character.lastName or character.last_name) or nil

    if exports['cm-inventory']:HasItem(src, itemName, 1) == true then
        return true, 'already_delivered'
    end

    local canCarry, carryReason = exports['cm-inventory']:CanCarryItem(src, itemName, 1)
    if canCarry ~= true then
        return false, carryReason or 'inventory_full'
    end

    local ok, slot = exports['cm-inventory']:AddItem(src, itemName, 1, metadata, 'license_issued')
    if not ok then
        print('^1[CM-License]^7 Failed to add license item to inventory: ' .. tostring(slot))
        return false, slot
    end

    return true, slot
end

local function licenseTypeForItem(itemName)
    for _, definition in ipairs(Cache.GetLicenseTypes() or {}) do
        if tostring(definition.item_name) == tostring(itemName) then return definition end
    end
    return nil
end

-- Shared validation for both halves of the physical-card contract: the person
-- handling the item must be the character the card was issued to.
local function resolveCardHolder(src, characterId, itemName, metadata)
    characterId = tonumber(characterId)
    if not characterId or exports['cm-playerdata']:GetCharacterId(src) ~= characterId then
        return nil, 'identity_mismatch'
    end

    metadata = type(metadata) == 'table' and metadata or {}
    if tonumber(metadata.characterId) ~= characterId then
        return nil, 'item_owner_mismatch'
    end

    local licenseType = licenseTypeForItem(itemName)
    if not licenseType then return nil, 'not_license_item' end

    return { characterId = characterId, licenseType = licenseType, metadata = metadata }
end

-- Local-only authoritative inventory contract: discarding the physical card
-- revokes the entitlement behind it.
function Licenses.RevokeDroppedItem(src, characterId, itemName, metadata)
    local card, reason = resolveCardHolder(src, characterId, itemName, metadata)
    if not card then return false, reason end

    local changed = Database.RevokeLicense(card.characterId, card.licenseType.id, card.characterId, Constants.DISCARD_REASON)
    Licenses.InvalidateCache(card.characterId)
    return changed, changed and nil or 'license_not_active'
end

-- The other half of that contract: picking your own card back up re-activates
-- the same entitlement, keeping its original expiry. It never revives a
-- license an admin revoked, one that expired while it lay on the ground, or
-- somebody else's card.
function Licenses.RestoreDroppedItem(src, characterId, itemName, metadata)
    local card, reason = resolveCardHolder(src, characterId, itemName, metadata)
    if not card then return false, reason end

    local licenseTypeId = card.licenseType.id
    local expiresAt = tonumber(card.metadata.expiresAt)

    if Database.RestoreDiscardedLicense(card.characterId, licenseTypeId, expiresAt) then
        Licenses.InvalidateCache(card.characterId)
        return true, card.licenseType
    end

    -- Nothing changed: say why, so the player is told rather than left holding
    -- a card that silently does nothing.
    local row = Database.GetCharacterLicenseRow(card.characterId, licenseTypeId)
    if not row then return false, 'no_license_record' end
    if row.status == Constants.LICENSE_STATUS.ACTIVE then return false, 'already_active' end
    if tonumber(row.expires_at) <= os.time() then return false, 'expired' end
    if row.status == Constants.LICENSE_STATUS.REVOKED and row.revoke_reason ~= Constants.DISCARD_REASON then
        return false, 'revoked_by_authority'
    end
    if expiresAt and tonumber(row.expires_at) ~= expiresAt then return false, 'superseded_card' end

    return false, 'license_not_restorable'
end

-- Hand over any license the character has been granted but not yet received
function Licenses.DeliverPending(src, characterId)
    local delivered = 0
    for _, license in ipairs(Database.GetPendingDeliveries(characterId)) do
        local ok = Licenses.AddInventoryItem(src, characterId, license.item_name, license.valid_days, license.expires_at)
        if ok and Database.MarkLicenseDelivered(characterId, license.license_type_id) then
            delivered = delivered + 1
        end
    end
    if delivered > 0 then Licenses.InvalidateCache(characterId) end
    return delivered
end

-- Remove license item from inventory
function Licenses.RemoveInventoryItem(characterId, itemName)
    if not characterId or not itemName then
        return false
    end

    local src = exports['cm-playerdata']:GetSourceByCharId(characterId)
    if not src then return false, 'character_offline' end
    return exports['cm-inventory']:RemoveItem(src, itemName, 1, nil, 'license_expired_or_revoked')
end

-- Cleanup on player disconnect
function Licenses.OnPlayerDropped(characterId)
    if not characterId then return end
    Licenses.CheckAndCleanupExpired(characterId)
    Licenses.InvalidateCache(characterId)
end

return Licenses
