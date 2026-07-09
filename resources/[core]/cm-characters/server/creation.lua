-- cm-characters/server/creation.lua
-- Secure character creation. Account/slot ownership is server-authoritative only.


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

local creationLocks = {}

local function creationFail(src, message)
    TriggerClientEvent('cm-characters:client:createResult', src, false, tostring(message or 'Character creation failed'))
end

RegisterNetEvent('cm-characters:server:create', function(_clientAccountId, charSlot, data)
    local src = source
    if CMCharacters.IsRateLimited(src, 'createCharacter', 3, 30) then
        creationFail(src, 'Please wait before creating another character.')
        return
    end
    local accountId = CMCharacters.RequireAccount(src)
    if not accountId then
        creationFail(src, 'You are not logged in. Please login again.')
        return
    end

    local maxCharacters = CMCharacters.GetMaxCharacters(accountId)
    local valid, cleanOrErr = CMCharacters.ValidateCreationData(data, charSlot, maxCharacters)
    if not valid then
        creationFail(src, cleanOrErr)
        return
    end

    local clean = cleanOrErr
    local lockKey = accountId .. ':' .. tostring(clean.slot)
    if creationLocks[lockKey] then
        creationFail(src, 'This slot is already being created. Please wait a moment.')
        return
    end
    creationLocks[lockKey] = true

    local function done()
        creationLocks[lockKey] = nil
    end

    print(('[CM-CHARACTERS] secure create: src=%s account=%s slot=%s name=%s %s'):format(
        tostring(src), tostring(accountId), tostring(clean.slot), clean.firstName, clean.lastName
    ))

    -- Check slot not taken. DB unique key also protects this as a second safety layer.
    local existing = CMCharacters.Query(
        'SELECT id FROM characters WHERE account_id = ? AND slot = ? LIMIT 1',
        { accountId, clean.slot }
    )
    if existing and #existing > 0 then
        done()
        creationFail(src, 'Character slot already used')
        return
    end

    -- Check max characters for this account.
    local count = tonumber(CMCharacters.Scalar(
        'SELECT COUNT(*) FROM characters WHERE account_id = ?',
        { accountId }
    ) or 0) or 0

    if count >= maxCharacters then
        done()
        creationFail(src, 'Maximum ' .. tostring(maxCharacters) .. ' characters reached')
        return
    end

    -- Check RP name not taken, case-insensitive.
    local nameTaken = CMCharacters.Query(
        'SELECT id FROM characters WHERE LOWER(first_name) = LOWER(?) AND LOWER(last_name) = LOWER(?) LIMIT 1',
        { clean.firstName, clean.lastName }
    )
    if nameTaken and #nameTaken > 0 then
        done()
        creationFail(src, 'Name already taken')
        return
    end

    local newCharId, idErr = CMAllocateCharacterId()
    if not newCharId then
        done()
        print('[CM-CHARACTERS] ERROR allocating fixed character ID: ' .. tostring(idErr))
        creationFail(src, 'Could not allocate character ID')
        return
    end

    local spawn = { x = -1037.0, y = -2737.0, z = 13.8, heading = 0.0 }
    local ok, err = pcall(function()
        CMCharacters.Query([[
            INSERT INTO characters
            (id, account_id, slot, first_name, last_name, dob, gender, appearance_json, last_position, cash, bank, has_spawned)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            tostring(newCharId),
            accountId,
            clean.slot,
            clean.firstName,
            clean.lastName,
            clean.dob,
            clean.gender,
            '{}',
            json.encode(spawn),
            tonumber(Config and Config.StartingCash) or 500,
            tonumber(Config and Config.StartingBank) or 2000,
            0
        })
    end)

    done()

    if not ok then
        print('[CM-CHARACTERS] ERROR creating character: ' .. tostring(err))
        creationFail(src, 'Database error while creating character')
        return
    end

    exports['cm-core']:CacheInvalidate('chars:' .. accountId)
    exports['cm-core']:Log('cm-characters', 'info', 'Character created', {
        player_src = src,
        account_id = accountId,
        char_id = tostring(newCharId),
        slot = clean.slot,
        name = clean.firstName .. ' ' .. clean.lastName
    })

    print('[CM-CHARACTERS] Character created successfully: ' .. tostring(newCharId))
    TriggerClientEvent('cm-characters:client:createResult', src, true, {
        charId = tostring(newCharId),
        gender = clean.gender,
        message = 'Character created'
    })
end)
