-- cm-characters/server/utils.lua
-- Shared server-side helpers for trust, validation, slots, permissions, and character state.


-- Production-safe local logger wrapper.
-- When Config.Debug/Config.VerboseLogs is false, normal CM-CHARACTERS debug prints are hidden.
-- Warnings/errors still print so real problems are visible.
local __cmCharactersPrint = print
local function __cmCharactersShouldVerbose()
    return Config and (Config.Debug == true or Config.VerboseLogs == true or Config.ProductionMode == false)
end
local function print(...)
    if __cmCharactersShouldVerbose() then
        return __cmCharactersPrint(...)
    end

    local first = tostring(select(1, ...) or '')
    local isCmCharactersLog = first:find('%[CM%-CHARACTERS') ~= nil
    if not isCmCharactersLog then
        return __cmCharactersPrint(...)
    end

    local upper = first:upper()
    if upper:find('ERROR', 1, true) or upper:find('WARNING', 1, true) or upper:find('FAILED', 1, true) or upper:find('DENIED', 1, true) then
        return __cmCharactersPrint(...)
    end
end

CMCharacters = CMCharacters or {}

local cmCharacterRateLimits = {}

local function safeCoreQuery(sql, params)
    local ok, result = pcall(function()
        return exports['cm-core']:Query(sql, params or {})
    end)
    if not ok then
        print('[CM-CHARACTERS] SQL error: ' .. tostring(result))
        return nil, result
    end
    return result
end

local function safeCoreScalar(sql, params)
    local ok, result = pcall(function()
        return exports['cm-core']:Scalar(sql, params or {})
    end)
    if not ok then
        print('[CM-CHARACTERS] SQL scalar error: ' .. tostring(result))
        return nil, result
    end
    return result
end

CMCharacters.Query = safeCoreQuery
CMCharacters.Scalar = safeCoreScalar

function CMCharacters.Trim(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function CMCharacters.Notify(src, message, msgType)
    if src == 0 then
        print('[CM-CHARACTERS] ' .. tostring(message))
        return
    end

    local sent = false
    if GetResourceState('cm-core') == 'started' then
        sent = pcall(function()
            exports['cm-core']:Notify(src, tostring(message), msgType or 'info', 5000)
        end)
    end

    if sent then return end

    if GetResourceState('cm-hud') == 'started' then
        TriggerClientEvent('cm-hud:client:notify', src, tostring(message), msgType or 'info')
    else
        TriggerClientEvent('chat:addMessage', src, {
            color = msgType == 'error' and {255, 80, 80} or {0, 229, 255},
            args = {'[CM-CHARACTERS]', tostring(message)}
        })
    end
end

function CMCharacters.GetAccountId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local state = Player(src).state
    local accountId = state and state.accountId or nil
    if accountId == nil or tostring(accountId) == '' then return nil end
    return tostring(accountId)
end

function CMCharacters.RequireAccount(src)
    local accountId = CMCharacters.GetAccountId(src)
    if not accountId then
        CMCharacters.Notify(src, 'You are not logged in. Please login again.', 'error')
        return nil
    end
    return accountId
end

function CMCharacters.HasPermission(src, permission)
    src = tonumber(src)
    if src == 0 then return true end
    if not src or src <= 0 then return false end
    permission = tostring(permission or '')
    if permission == '' then return false end

    -- cm-admin is the real staff permission owner. cm-characters never owns ranks/admin UI.
    if GetResourceState('cm-admin') == 'started' then
        local ok, allowed = pcall(function()
            return exports['cm-admin']:HasPermission(src, permission)
        end)
        if ok and allowed == true then return true end
    end

    -- ACE fallback for early dev servers or before cm-admin is fully migrated.
    local checks = {
        permission,
        'cm.characters.admin',
        'characters.admin',
        'command.charadmin'
    }

    for _, ace in ipairs(checks) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end

    return false
end


function CMCharacters.IsAdmin(src)
    return CMCharacters.HasPermission(src, 'characters.admin')
end

function CMCharacters.IsRateLimited(src, key, defaultLimit, defaultSeconds)
    src = tonumber(src)
    if not src or src <= 0 then return false end

    key = tostring(key or 'default')
    local rlConfig = Config and Config.RateLimits and Config.RateLimits[key] or {}
    local limit = tonumber(rlConfig.limit or defaultLimit) or 5
    local seconds = tonumber(rlConfig.seconds or defaultSeconds) or 10

    if GetResourceState('cm-core') == 'started' then
        local ok, limited = pcall(function()
            return exports['cm-core']:IsRateLimited(src, 'cm-characters:' .. key, limit, seconds)
        end)
        if ok then return limited == true end
    end

    local now = os.time()
    local bucketKey = tostring(src) .. ':' .. key
    local bucket = cmCharacterRateLimits[bucketKey]
    if not bucket or now >= bucket.resetAt then
        cmCharacterRateLimits[bucketKey] = { count = 1, resetAt = now + seconds }
        return false
    end

    bucket.count = bucket.count + 1
    return bucket.count > limit
end

function CMCharacters.SyncWithPlayerData(src, charId, reason)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    if GetResourceState('cm-playerdata') ~= 'started' then return false end

    local ok = pcall(function()
        -- cm-playerdata reads Player(src).state.charId, so set character state first.
        exports['cm-playerdata']:Load(src)
    end)

    if ok then
        TriggerEvent('cm-playerdata:server:characterLoaded', src, tostring(charId or ''), reason or 'cm-characters')
    end

    return ok == true
end

function CMCharacters.GetMaxCharacters(accountId)
    local defaultMax = tonumber(Config and Config.MaxCharacters) or 2
    accountId = tostring(accountId or '')
    if accountId == '' then return defaultMax end

    local rows = safeCoreQuery('SELECT max_slots FROM character_slot_limits WHERE account_id = ? LIMIT 1', { accountId })
    if rows and rows[1] and tonumber(rows[1].max_slots) then
        local value = tonumber(rows[1].max_slots) or defaultMax
        return math.max(1, math.min(20, value))
    end

    return defaultMax
end

function CMCharacters.CleanName(value)
    value = CMCharacters.Trim(value)
    value = value:gsub('%s+', ' ')
    return value
end

function CMCharacters.ValidateName(value, field)
    value = CMCharacters.CleanName(value)
    field = field or 'Name'

    if value == '' then return false, field .. ' is required' end
    if #value < 2 then return false, field .. ' must be at least 2 characters' end
    if #value > 20 then return false, field .. ' must be 20 characters or less' end
    if not value:match("^[A-Za-z][A-Za-z'%-]*$") then
        return false, field .. ' can only use letters, apostrophe, or hyphen'
    end

    return true, value
end

function CMCharacters.ValidateDob(value)
    value = CMCharacters.Trim(value)
    if value == '' then return false, 'Date of birth is required' end

    local y, m, d = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or not m or not d then return false, 'Date of birth must be YYYY-MM-DD' end
    if y < 1900 or y > 2015 or m < 1 or m > 12 or d < 1 or d > 31 then
        return false, 'Invalid date of birth'
    end

    local t = os.date('*t')
    local age = (t.year or 2026) - y
    if (t.month or 1) < m or ((t.month or 1) == m and (t.day or 1) < d) then age = age - 1 end

    local minAge = tonumber(Config and Config.MinCharacterAge) or 16
    local maxAge = tonumber(Config and Config.MaxCharacterAge) or 100
    if age < minAge then return false, 'Character must be at least ' .. tostring(minAge) .. ' years old' end
    if age > maxAge then return false, 'Character age must be under ' .. tostring(maxAge) end

    return true, ('%04d-%02d-%02d'):format(y, m, d), age
end

function CMCharacters.ValidateCreationData(raw, slot, maxSlots)
    raw = type(raw) == 'table' and raw or {}
    slot = tonumber(slot)
    maxSlots = tonumber(maxSlots) or tonumber(Config and Config.MaxCharacters) or 2

    if not slot or slot < 1 or slot > maxSlots or math.floor(slot) ~= slot then
        return false, 'Invalid character slot'
    end

    local okFirst, firstOrErr = CMCharacters.ValidateName(raw.firstName or raw.firstname or raw.first_name, 'First name')
    if not okFirst then return false, firstOrErr end

    local okLast, lastOrErr = CMCharacters.ValidateName(raw.lastName or raw.lastname or raw.last_name, 'Last name')
    if not okLast then return false, lastOrErr end

    local gender = tostring(raw.gender or 'male'):lower()
    if gender ~= 'male' and gender ~= 'female' then
        return false, 'Invalid gender'
    end

    local okDob, dobOrErr, age = CMCharacters.ValidateDob(raw.dob or raw.dateOfBirth or raw.date_of_birth)
    if not okDob then return false, dobOrErr end

    return true, {
        slot = slot,
        firstName = firstOrErr,
        lastName = lastOrErr,
        dob = dobOrErr,
        age = age,
        gender = gender
    }
end

function CMCharacters.GetCharacterById(charId)
    if charId == nil or tostring(charId) == '' then return nil end
    local rows = safeCoreQuery('SELECT * FROM characters WHERE id = ? LIMIT 1', { tostring(charId) })
    return rows and rows[1] or nil
end

function CMCharacters.GetOwnedCharacter(src, charId)
    local accountId = CMCharacters.RequireAccount(src)
    if not accountId then return nil, nil, 'Not logged in' end

    local char = CMCharacters.GetCharacterById(charId)
    if not char then return nil, accountId, 'Character not found' end
    if tostring(char.account_id) ~= tostring(accountId) then
        return nil, accountId, 'This character does not belong to your account'
    end
    return char, accountId, nil
end

function CMCharacters.CharacterFullName(char)
    if type(char) ~= 'table' then return '' end
    local full = (tostring(char.first_name or '') .. ' ' .. tostring(char.last_name or ''))
    return full:gsub('^%s+', ''):gsub('%s+$', '')
end

function CMCharacters.SetCharacterState(src, char)
    if not char then return false end
    local fixedCharId = tostring(char.id)
    local fullName = CMCharacters.CharacterFullName(char)

    Player(src).state:set('charId', fixedCharId, true)
    Player(src).state:set('characterId', fixedCharId, true)
    Player(src).state:set('charFirstName', tostring(char.first_name or ''), true)
    Player(src).state:set('charLastName', tostring(char.last_name or ''), true)
    Player(src).state:set('charFullName', fullName, true)
    Player(src).state:set('characterName', fullName, true)
    Player(src).state:set('charGender', tostring(char.gender or ''), true)
    Player(src).state:set('characterLoaded', true, true)
    Player(src).state:set('isLoggedIn', true, true)
    Player(src).state:set('cash', tonumber(char.cash or 0) or 0, true)
    Player(src).state:set('bank', tonumber(char.bank or 0) or 0, true)
    return true
end

function CMCharacters.ClearCharacterState(src)
    Player(src).state:set('charId', nil, true)
    Player(src).state:set('characterId', nil, true)
    Player(src).state:set('charFirstName', nil, true)
    Player(src).state:set('charLastName', nil, true)
    Player(src).state:set('charFullName', nil, true)
    Player(src).state:set('characterName', nil, true)
    Player(src).state:set('charGender', nil, true)
    Player(src).state:set('characterLoaded', false, true)
end

function CMCharacters.LogAdmin(src, action, data)
    data = type(data) == 'table' and data or {}
    data.admin_src = src
    data.action = action

    if GetResourceState('cm-admin') == 'started' then
        pcall(function()
            exports['cm-admin']:LogAdminAction(src, tostring(action), data)
        end)
    end

    pcall(function()
        exports['cm-core']:Log('cm-characters-admin', 'info', tostring(action), data)
    end)
end

function CMCharacters.EnsureSchema()
    pcall(function()
        exports['cm-core']:Query('ALTER TABLE characters ADD COLUMN IF NOT EXISTS has_spawned TINYINT(1) NOT NULL DEFAULT 0')
        exports['cm-core']:Query('ALTER TABLE characters ADD COLUMN IF NOT EXISTS playtime_minutes INT NOT NULL DEFAULT 0')
        exports['cm-core']:Query('ALTER TABLE characters ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP NULL DEFAULT NULL')
        exports['cm-core']:Query([[CREATE TABLE IF NOT EXISTS character_slot_limits (
            account_id VARCHAR(64) NOT NULL PRIMARY KEY,
            max_slots INT NOT NULL DEFAULT 2,
            reason VARCHAR(255) NULL,
            updated_by VARCHAR(64) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )]])

        local indexes = exports['cm-core']:Query("SHOW INDEX FROM characters WHERE Key_name = 'uniq_cm_characters_account_slot'") or {}
        if #indexes == 0 then
            pcall(function()
                exports['cm-core']:Query('ALTER TABLE characters ADD UNIQUE KEY uniq_cm_characters_account_slot (account_id, slot)')
            end)
        end
    end)
end
