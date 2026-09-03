-- CM License System — License Management

local Database = require 'server.database'
local Cache = require 'server.cache'
local Constants = require 'shared.constants'
local Utils = require 'shared.utils'

local Licenses = {}

-- Check if player has active valid license
function Licenses.HasLicense(characterId, licenseType)
    if not characterId or not licenseType then
        return false, 'invalid_params'
    end

    local licenseTypeRecord = Cache.GetLicenseTypeByName(licenseType)
    if not licenseTypeRecord then
        return false, 'license_type_not_found'
    end

    local licenses = Database.GetCharacterLicenses(characterId)
    if not licenses then
        return false, 'not_found'
    end

    for _, license in ipairs(licenses) do
        if license.license_type == licenseType and license.status == Constants.LICENSE_STATUS.ACTIVE then
            if license.expires_at > os.time() then
                return true, license
            else
                return false, 'expired'
            end
        end
    end

    return false, 'not_found'
end

-- Get all licenses for character
function Licenses.GetLicenses(characterId)
    if not characterId then
        return nil
    end

    local licenses = Database.GetCharacterLicenses(characterId)
    if not licenses then
        return {}
    end

    -- Enrich with expiration info
    for _, license in ipairs(licenses) do
        license.remainingDays = Utils.CalculateRemainingDays(license.expires_at)
        license.isExpired = Utils.IsExpired(license.expires_at)
        license.expiresAtDate = Utils.FormatDate(license.expires_at)
    end

    return licenses
end

-- Get single license
function Licenses.GetLicense(characterId, licenseType)
    if not characterId or not licenseType then
        return nil
    end

    local licenses = Licenses.GetLicenses(characterId)
    for _, license in ipairs(licenses) do
        if license.license_type == licenseType then
            return license
        end
    end

    return nil
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

    local days = validDays or licenseType.valid_days or 30

    -- Use transaction to ensure atomicity
    local success = Database.IssueLicense(characterId, licenseTypeId, days)
    if not success then
        return false, 'database_error'
    end

    return true, {
        characterId = characterId,
        licenseTypeId = licenseTypeId,
        validDays = days,
        expiresAt = Utils.CalculateExpiration(days)
    }
end

-- Revoke license (admin action)
function Licenses.RevokeLicense(characterId, licenseTypeId, revokedBy, reason)
    if not characterId or not licenseTypeId or not revokedBy then
        return false, 'invalid_params'
    end

    local success = Database.RevokeLicense(characterId, licenseTypeId, revokedBy, reason)
    if not success then
        return false, 'database_error'
    end

    -- Remove inventory item
    local licenseType = Cache.GetLicenseType(licenseTypeId)
    if licenseType then
        Licenses.RemoveInventoryItem(characterId, licenseType.item_name)
    end

    return true
end

-- Check and cleanup expired licenses
function Licenses.CheckAndCleanupExpired(characterId)
    if not characterId then
        return 0
    end

    local expiredLicenses = Database.GetExpiredLicenses(characterId)
    if not expiredLicenses or #expiredLicenses == 0 then
        return 0
    end

    local removedCount = 0
    for _, license in ipairs(expiredLicenses) do
        -- Mark as expired in DB
        Database.MarkLicenseExpired(license.id)

        -- Remove inventory item
        if license.item_name then
            local success = Licenses.RemoveInventoryItem(characterId, license.item_name)
            if success then
                removedCount = removedCount + 1
            end
        end
    end

    return removedCount
end

-- Add license item to player inventory
function Licenses.AddInventoryItem(src, characterId, itemName, validDays, expiresAt)
    if not src or not itemName then
        return false, 'invalid_params'
    end

    local metadata = {
        licenseType = itemName,
        characterId = characterId,
        issuedAt = os.time(),
        expiresAt = expiresAt or Utils.CalculateExpiration(validDays or 30),
        validDays = validDays or 30
    }

    -- Try to get character info for display
    local charData = exports['cm-playerdata']:GetCharacterData(src)
    if charData and charData.Character then
        metadata.firstName = charData.Character.FirstName
        metadata.lastName = charData.Character.LastName
    end

    local ok, slot = exports['cm-inventory']:AddItem(src, itemName, 1, metadata, 'license_issued')

    if not ok then
        print('^1[CM-License]^7 Failed to add license item to inventory: ' .. tostring(slot))
        return false, slot
    end

    return true, slot
end

-- Remove license item from inventory
function Licenses.RemoveInventoryItem(characterId, itemName)
    if not characterId or not itemName then
        return false
    end

    -- Note: RemoveItem works with src, not characterId
    -- We may need to track online players or handle this differently
    -- For now, this is a placeholder for inventory cleanup
    -- In practice, the inventory system will handle item removal on cleanup

    return true
end

-- Cleanup on player disconnect
function Licenses.OnPlayerDropped(characterId)
    if not characterId then
        return
    end

    -- Check for active test and fail it
    -- (Handled in tests.lua)

    -- Mark expired licenses
    Licenses.CheckAndCleanupExpired(characterId)
end

-- Periodic cleanup (run every few minutes)
function Licenses.PeriodicCleanup()
    -- This would need to check all characters with expired licenses
    -- Implementation depends on how we track online characters
    -- Could iterate through database and cleanup stale sessions
end

return Licenses
