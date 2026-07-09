-- cm-characters/server/id-generator.lua
-- Global fixed character ID generator.
-- This creates character IDs like 0, 1, 2, 3... and keeps them forever in characters.id.


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

local idTableReady = false

local function safeNumber(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function ensureIdTable()
    if idTableReady then return true end

    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cm_character_id_counter (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])

        -- If you already have numeric character IDs, continue after the highest one.
        -- Example: existing characters.id has 0,1,2, then next will be 3.
        local maxCharId = MySQL.scalar.await([[
            SELECT COALESCE(MAX(CAST(id AS UNSIGNED)), -1)
            FROM characters
            WHERE id REGEXP '^[0-9]+$'
        ]])

        local desiredAutoIncrement = safeNumber(maxCharId, -1) + 2
        if desiredAutoIncrement < 1 then desiredAutoIncrement = 1 end

        local info = MySQL.query.await([[
            SELECT AUTO_INCREMENT
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'cm_character_id_counter'
            LIMIT 1
        ]])

        local currentAutoIncrement = 1
        if info and info[1] then
            currentAutoIncrement = safeNumber(info[1].AUTO_INCREMENT, 1)
        end

        if currentAutoIncrement < desiredAutoIncrement then
            MySQL.query.await(('ALTER TABLE cm_character_id_counter AUTO_INCREMENT = %d'):format(desiredAutoIncrement))
        end
    end)

    if not ok then
        print('[CM-CHARACTERS] Fixed ID table setup failed: ' .. tostring(err))
        return false
    end

    idTableReady = true
    print('[CM-CHARACTERS] Fixed character ID generator ready')
    return true
end

function CMAllocateCharacterId()
    if not ensureIdTable() then
        return nil, 'Fixed character ID table is not ready'
    end

    local insertId = MySQL.insert.await('INSERT INTO cm_character_id_counter (created_at) VALUES (CURRENT_TIMESTAMP)')
    insertId = tonumber(insertId)

    if not insertId then
        return nil, 'Failed to allocate character ID'
    end

    -- Auto increment starts at 1, but RP character IDs start at 0.
    return tostring(insertId - 1), nil
end

exports('AllocateCharacterId', function()
    return CMAllocateCharacterId()
end)

exports('PeekNextCharacterId', function()
    if not ensureIdTable() then return nil end

    local info = MySQL.query.await([[
        SELECT AUTO_INCREMENT
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'cm_character_id_counter'
        LIMIT 1
    ]])

    local autoInc = info and info[1] and tonumber(info[1].AUTO_INCREMENT) or 1
    return tostring(autoInc - 1)
end)

CreateThread(function()
    Wait(2500)
    ensureIdTable()
end)
