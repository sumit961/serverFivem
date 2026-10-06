-- Persistent phone identity: character_id -> phone number ("AAA-BBBB"), generated server-side,
-- unique-constrained, collision-safe. The number carries no database ID and no source ID.
local S = CMPhone.Server
local Config = CMPhone.Config

local numberByCid = {}
local cidByNumber = {}

-- Accepts "3235551234"-style 7 digits with or without a dash; returns canonical "AAA-BBBB" or nil.
function S.NormalizeNumber(input)
    if type(input) ~= 'string' and type(input) ~= 'number' then return nil end
    local digits = tostring(input):gsub('%D', '')
    if #digits ~= 7 then return nil end
    return digits:sub(1, 3) .. '-' .. digits:sub(4)
end

local function generate()
    local prefixes = Config.Number.prefixes
    local prefix = prefixes[math.random(1, #prefixes)]
    return ('%s-%04d'):format(prefix, math.random(0, 9999))
end

local function isDuplicateError(err)
    err = tostring(err or ''):lower()
    return err:find('duplicate', 1, true) ~= nil or err:find('1062', 1, true) ~= nil
end

local function remember(cid, number)
    numberByCid[cid] = number
    cidByNumber[number] = cid
end

-- Cached/DB read only; does not create.
function S.GetNumber(cid)
    cid = cid and tostring(cid)
    if not cid then return nil end
    if numberByCid[cid] then return numberByCid[cid] end
    if not S.SchemaReady then return nil end
    local row = MySQL.single.await('SELECT phone_number FROM cm_phone_numbers WHERE character_id = ? LIMIT 1', { cid })
    if row and row.phone_number then
        remember(cid, row.phone_number)
        return row.phone_number
    end
    return nil
end

-- Creates the number once per character. Safe under concurrent loads: PK on character_id and
-- UNIQUE on phone_number; a collision either re-reads the winner's row or retries a new number.
function S.EnsureNumber(cid)
    cid = cid and tostring(cid)
    if not cid or cid == '' then return nil, 'invalid_character' end
    local existing = S.GetNumber(cid)
    if existing then return existing end
    if not S.AwaitSchema() then return nil, 'schema_unavailable' end

    for _ = 1, tonumber(Config.Number.generationAttempts) or 30 do
        local candidate = generate()
        local ok, err = pcall(function()
            return MySQL.insert.await('INSERT INTO cm_phone_numbers (character_id, phone_number) VALUES (?, ?)', { cid, candidate })
        end)
        if ok then
            remember(cid, candidate)
            return candidate
        end
        if not isDuplicateError(err) then
            print(('[cm-phone] number insert failed: %s'):format(tostring(err)))
            return nil, 'insert_failed'
        end
        -- Duplicate: either another load created this character's row, or the number is taken.
        local winner = MySQL.single.await('SELECT phone_number FROM cm_phone_numbers WHERE character_id = ? LIMIT 1', { cid })
        if winner and winner.phone_number then
            remember(cid, winner.phone_number)
            return winner.phone_number
        end
    end
    return nil, 'exhausted'
end

-- number -> character id, only for characters that still exist (never returns identity data).
function S.CidByNumber(number)
    number = S.NormalizeNumber(number)
    if not number then return nil end
    if cidByNumber[number] then return cidByNumber[number] end
    if not S.SchemaReady then return nil end
    local row = MySQL.single.await([[SELECT n.character_id FROM cm_phone_numbers n
        JOIN characters c ON c.id = n.character_id WHERE n.phone_number = ? LIMIT 1]], { number })
    if row and row.character_id then
        remember(tostring(row.character_id), number)
        return tostring(row.character_id)
    end
    return nil
end

-- Selftest/cleanup hook only.
function S.ForgetNumberCache(cid)
    local number = numberByCid[cid]
    numberByCid[cid] = nil
    if number then cidByNumber[number] = nil end
end

-- Phone numbers are assigned when a character loads; offline lookups never create numbers.
AddEventHandler('cm-phone:internal:characterLoaded', function(src)
    CreateThread(function()
        local cid = S.CharacterOf(src)
        if not cid then return end
        local number, reason = S.EnsureNumber(cid)
        if not number then
            print(('[cm-phone] could not assign a number to character %s: %s'):format(cid, tostring(reason)))
            return
        end
        S.Emit(src, 'cm-phone:client:identity', { number = number })
    end)
end)

math.randomseed(os.time() + GetGameTimer())
