-- Public server contracts. See docs/CONTRACTS.md.
-- Read-only lookups are open; anything that sends data to a player requires GetInvokingResource() to be
-- on Config.TrustedResources. No export returns a character name or another identity field.
local S = CMPhone.Server
local Config = CMPhone.Config

local function trusted()
    local invoking = GetInvokingResource()
    return invoking ~= nil and Config.TrustedResources[invoking] == true, invoking
end

-- GetPhoneNumber(characterId) -> 'AAA-BBBB' | nil
exports('GetPhoneNumber', function(characterId)
    return S.GetNumber(characterId and tostring(characterId))
end)

-- GetPhoneNumberForSource(source) -> number | nil (resolved from the live session)
exports('GetPhoneNumberForSource', function(src)
    local cid = S.CharacterOf(src)
    return cid and S.GetNumber(cid) or nil
end)

-- GetCharacterByPhoneNumber(number) -> characterId | nil. Trusted resources only (identity bridge).
exports('GetCharacterByPhoneNumber', function(number)
    local ok = trusted()
    if not ok then return nil end
    return S.CidByNumber(number)
end)

-- IsNumberBlocked(ownerCharacterId, number) -> boolean
exports('IsNumberBlocked', function(ownerCharacterId, number)
    local normalized = S.NormalizeNumber(number)
    if not ownerCharacterId or not normalized then return false end
    return S.IsBlocked(tostring(ownerCharacterId), normalized)
end)

-- SendSystemMessage(characterId, title, body, payload?) -> ok, reason. Trusted resources only.
-- Creates a receive-only thread titled `title` in the character's phone. Offline characters receive it on next load.
exports('SendSystemMessage', function(characterId, title, body, payload)
    local ok, invoking = trusted()
    if not ok then return false, 'forbidden' end
    if not characterId then return false, 'invalid_character' end
    if type(payload) ~= 'table' then payload = nil end
    local sent, result = S.SendSystem(tostring(characterId), title, body, payload)
    if sent then S.audit(0, 'cm_phone_system_message', { resource = invoking, characterId = tostring(characterId) }) end
    return sent, result
end)

-- CreateNotification(characterId, { title, message }) -> boolean. Transient toast only (not persisted).
exports('CreateNotification', function(characterId, data)
    local ok = trusted()
    if not ok or type(data) ~= 'table' then return false end
    local src = S.SourceOf(characterId and tostring(characterId))
    if not src then return false end
    local title = S.cleanText(tostring(data.title or 'Phone'), 32) or 'Phone'
    local message = S.cleanText(tostring(data.message or ''), 120)
    if not message then return false end
    S.Emit(src, 'cm-phone:client:notify', { title = title, message = message })
    return true
end)

-- SendCharacterMessage is intentionally NOT exported: acting as a character would bypass sender authority.
