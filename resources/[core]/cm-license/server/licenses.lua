-- CM License System — License Management

Licenses = {}

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
    if not success or tonumber(success) == 0 then
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
        licenseType = tostring(itemName):gsub('_license$', ''),
        licenseClass = tostring(itemName):gsub('_license$', ''),
        characterId = characterId,
        issuedAt = os.time(),
        expiresAt = expiresAt or Utils.CalculateExpiration(validDays or 30),
        validDays = validDays or 30
    }
    metadata.issuedAtDate = Utils.FormatDate(metadata.issuedAt)
    metadata.expiresAtDate = Utils.FormatDate(metadata.expiresAt)
    metadata.testCompletedAt = metadata.issuedAt
    metadata.testCompletedDate = metadata.issuedAtDate
    metadata.licenseNumber = ('CM-%s-%s-%s'):format(metadata.licenseType:upper(), tostring(characterId), tostring(metadata.issuedAt))
    
    -- Try to get character info for display
    local charData = exports['cm-playerdata']:GetCharacterData(src)
    local character = charData and (charData.Character or charData.character) or charData
    metadata.firstName = character and (character.FirstName or character.firstName or character.first_name) or nil
    metadata.lastName = character and (character.LastName or character.lastName or character.last_name) or nil

    local alreadyOwned = exports['cm-inventory']:HasItem(src, itemName, 1)
    if alreadyOwned == true then return true, 'already_delivered' end
    local canCarry, carryReason = exports['cm-inventory']:CanCarryItem(src, itemName, 1)
    if canCarry ~= true then return false, carryReason or 'inventory_full' end
    
    local ok, slot = exports['cm-inventory']:AddItem(src, itemName, 1, metadata, 'license_issued')
    
    if not ok then
        print('^1[CM-License]^7 Failed to add license item to inventory: ' .. tostring(slot))
        return false, slot
    end
    
    return true, slot
end

function Licenses.RevokeDroppedItem(src, characterId, itemName, metadata)
    characterId = tonumber(characterId)
    if not characterId or exports['cm-playerdata']:GetCharacterId(src) ~= characterId then return false, 'identity_mismatch' end
    metadata = type(metadata) == 'table' and metadata or {}
    if tonumber(metadata.characterId) ~= characterId then return false, 'item_owner_mismatch' end
    local licenseType
    for _, definition in ipairs(Cache.GetLicenseTypes() or {}) do
        if tostring(definition.item_name) == tostring(itemName) then licenseType = definition; break end
    end
    if not licenseType then return false, 'not_license_item' end
    local changed = Database.RevokeLicense(characterId, licenseType.id, characterId, 'license_item_discarded')
    return tonumber(changed) == 1, tonumber(changed) == 1 and nil or 'license_not_active'
end

function Licenses.DeliverPending(src, characterId)
    local delivered = 0
    for _, license in ipairs(Database.GetPendingDeliveries(characterId)) do
        local ok = Licenses.AddInventoryItem(src, characterId, license.item_name, license.valid_days, license.expires_at)
        if ok and tonumber(Database.MarkLicenseDelivered(characterId, license.license_type_id)) == 1 then
            delivered = delivered + 1
        end
    end
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
