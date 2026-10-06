-- CM License System — License Management

Licenses = {}

-- HasLicense is authoritative physical-card validation. Inventory possession
-- is intentionally read fresh so give/drop/pickup changes apply immediately.
function Licenses.InvalidateCache(characterId)
    -- Compatibility no-op: physical possession is resolved fresh from the
    -- authoritative inventory export for every authorization check.
end

local function licenseTypeFor(licenseType)
    local requested = tostring(licenseType or ''):lower()
    if requested == '' then return nil end
    for _, definition in ipairs(Cache.GetLicenseTypes() or {}) do
        if tostring(definition.license_type):lower() == requested
            or tostring(definition.item_name):lower() == requested
        then
            return definition
        end
    end
    return nil
end

local function heldInventoryItems(characterId)
    local src = exports['cm-playerdata']:GetSourceByCharId(characterId)
    if not src or tonumber(src) <= 0 then return nil, 'character_offline' end
    local ok, inventory = pcall(function()
        return exports['cm-inventory']:GetInventory(tonumber(src))
    end)
    if not ok or type(inventory) ~= 'table' then return nil, 'inventory_unavailable' end
    return type(inventory.items) == 'table' and inventory.items or {}, nil
end

local function validHeldCard(characterId, definition, item)
    if type(item) ~= 'table' then return nil end
    if tostring(item.item_name or item.name or ''):lower() ~= tostring(definition.item_name):lower() then return nil end
    if (tonumber(item.quantity) or 0) < 1 then return nil end

    local metadata = type(item.metadata) == 'table' and item.metadata or nil
    if not metadata then return nil end
    local expectedType = tostring(definition.license_type):lower()
    local metadataType = metadata.licenseType and tostring(metadata.licenseType):lower() or nil
    local metadataClass = metadata.licenseClass and tostring(metadata.licenseClass):lower() or nil
    if not metadataType and not metadataClass then return nil end
    if (metadataType and metadataType ~= expectedType) or (metadataClass and metadataClass ~= expectedType) then return nil end

    local originalCharacterId = tonumber(metadata.issuedToCharacterId or metadata.characterId)
    local issuedAt = tonumber(metadata.issuedAt or metadata.issued_at)
    local expiresAt = tonumber(metadata.expiresAt or metadata.expires_at)
    local licenseNumber = tostring(metadata.licenseNumber or '')
    if not originalCharacterId or not issuedAt or not expiresAt or expiresAt <= os.time() or licenseNumber == '' then return nil end

    local issuance = Database.GetCharacterLicenseRow(originalCharacterId, definition.id)
    if not issuance or issuance.status ~= Constants.LICENSE_STATUS.ACTIVE then return nil end
    if issuance.delivery_status and issuance.delivery_status ~= 'delivered' then return nil end
    if tonumber(issuance.issued_at) ~= issuedAt or tonumber(issuance.expires_at) ~= expiresAt then return nil end

    local prefix = ('CM-%s-%s-'):format(expectedType:upper(), tostring(originalCharacterId))
    if licenseNumber:sub(1, #prefix) ~= prefix then return nil end

    local result = Utils.DeepCopy(issuance)
    result.holderCharacterId = tonumber(characterId)
    result.item_name = definition.item_name
    result.license_type = definition.license_type
    result.label = definition.label
    result.metadata = Utils.DeepCopy(metadata)
    result.licenseNumber = licenseNumber
    result.isHeld = true
    return result
end

local function heldLicense(characterId, definition)
    local items, reason = heldInventoryItems(characterId)
    if not items then return nil, reason end
    for _, item in ipairs(items) do
        local card = validHeldCard(characterId, definition, item)
        if card then return card end
    end
    return nil, 'not_held'
end

-- The current holder is authoritative. metadata.characterId identifies the
-- original issuance only; it is never compared with the current holder.
function Licenses.HasLicense(characterId, licenseType)
    if not characterId or not licenseType then return false, 'invalid_params' end
    local definition = licenseTypeFor(licenseType)
    if not definition then return false, 'license_type_not_found' end
    local card, reason = heldLicense(characterId, definition)
    return card ~= nil, card or reason or 'not_held'
end

function Licenses.GetLicenses(characterId)
    if not characterId then return {} end
    local licenses = {}
    for _, definition in ipairs(Cache.GetLicenseTypes() or {}) do
        local license = heldLicense(characterId, definition)
        if license then
            license.remainingDays = Utils.CalculateRemainingDays(license.expires_at)
            license.isExpired = false
            license.expiresAtDate = Utils.FormatDate(license.expires_at)
            license.issuedAtDate = Utils.FormatDate(license.issued_at)
            licenses[#licenses + 1] = license
        end
    end
    return licenses
end

function Licenses.GetLicense(characterId, licenseType)
    local definition = licenseTypeFor(licenseType)
    return definition and heldLicense(characterId, definition) or nil
end

function Licenses.GetLicenseSummary(characterId)
    local summary = {}
    for _, license in ipairs(Licenses.GetLicenses(characterId)) do
        summary[license.license_type] = {
            label = license.label,
            status = Constants.LICENSE_STATUS.ACTIVE,
            expiresAt = tonumber(license.expires_at),
            expiresAtDate = license.expiresAtDate,
            remainingDays = license.remainingDays,
            holderCharacterId = license.holderCharacterId,
            licenseNumber = license.licenseNumber,
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

    local days = math.floor(tonumber(validDays) or tonumber(licenseType.valid_days) or 30)
    if days < 1 or days > 3650 then
        return false, 'invalid_valid_days'
    end
    local ok, expiresAt = Database.IssueLicense(characterId, licenseTypeId, days)
    if not ok then
        return false, 'database_error'
    end

    local row = Database.GetCharacterLicenseRow(characterId, licenseTypeId)
    Licenses.InvalidateCache(characterId)

    return true, {
        characterId = characterId,
        licenseTypeId = licenseTypeId,
        licenseType = licenseType.license_type,
        licenseLabel = licenseType.label,
        validDays = days,
        issuedAt = row and tonumber(row.issued_at) or os.time(),
        expiresAt = expiresAt,
        licenseId = row and tonumber(row.id) or nil,
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

    return true
end

-- Check and cleanup expired licenses
function Licenses.CheckAndCleanupExpired(characterId)
    if not characterId then return 0 end

    local expiredLicenses = Database.GetExpiredLicenses(characterId)
    if not expiredLicenses or #expiredLicenses == 0 then
        return 0
    end

    for _, license in ipairs(expiredLicenses) do
        -- Expiry is enforced by HasLicense against the issuance row and card
        -- metadata. Do not remove a transferred physical card from anybody's
        -- inventory as part of maintenance.
        Database.MarkLicenseExpired(license.id)
    end

    Licenses.InvalidateCache(characterId)
    return #expiredLicenses
end

-- Add license item to player inventory
function Licenses.AddInventoryItem(src, characterId, itemName, validDays, expiresAt, issuedAt)
    if not src or not itemName then
        return false, 'invalid_params'
    end

    local licenseClass = tostring(itemName):gsub('_license$', '')
    local metadata = {
        licenseType = licenseClass,
        licenseClass = licenseClass,
        characterId = characterId,
        issuedAt = tonumber(issuedAt) or os.time(),
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


-- Hand over any license the character has been granted but not yet received
function Licenses.DeliverPending(src, characterId)
    local delivered = 0
    for _, license in ipairs(Database.GetPendingDeliveries(characterId)) do
        local ok = Licenses.AddInventoryItem(src, characterId, license.item_name, license.valid_days, license.expires_at, license.issued_at)
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
