-- cm-auth/server/main.lua
-- Stable auth using direct oxmysql calls. Keeps old working flow and avoids cm-core DB export argument issues.

local DEBUG = false
local LOGIN_COOLDOWN = 1500
local REGISTER_COOLDOWN = 3000
local lastLogin = {}
local lastRegister = {}

local function dprint(...)
    if DEBUG then
        local args = {...}
        local msg = '[CM-AUTH-DEBUG] '
        for i = 1, #args do msg = msg .. tostring(args[i]) .. ' ' end
        print(msg)
    end
end

local function sendLogin(src, success, message)
    TriggerClientEvent('cm-auth:client:loginResult', src, success, message)
end

local function sendRegister(src, success, message)
    TriggerClientEvent('cm-auth:client:registerResult', src, success, message)
end

local function safeLog(resource, level, message, metadata)
    metadata = metadata or {}
    metadata.category = metadata.category or 'auth'
    local ok = pcall(function()
        if exports['cm-core'] and exports['cm-core'].Log then
            exports['cm-core'].Log(resource or 'cm-auth', level or 'info', message or '', metadata)
        else
            print(('[CM-AUTH] %s: %s'):format(level or 'info', message or ''))
        end
    end)
    if not ok then
        print(('[CM-AUTH] %s: %s'):format(level or 'info', message or ''))
    end
end

local function dbQuery(sql, params)
    if type(sql) ~= 'string' then
        print(('[CM-AUTH] dbQuery expected SQL string, got %s'):format(type(sql)))
        return nil
    end
    local ok, result = pcall(function()
        return MySQL.query.await(sql, params or {})
    end)
    if not ok then
        print('[CM-AUTH] DB query failed: ' .. tostring(result))
        print('[CM-AUTH] SQL: ' .. sql)
        return nil
    end
    return result
end

local function dbSingle(sql, params)
    if type(sql) ~= 'string' then
        print(('[CM-AUTH] dbSingle expected SQL string, got %s'):format(type(sql)))
        return nil
    end
    local ok, result = pcall(function()
        return MySQL.single.await(sql, params or {})
    end)
    if not ok then
        print('[CM-AUTH] DB single failed: ' .. tostring(result))
        print('[CM-AUTH] SQL: ' .. sql)
        return nil
    end
    return result
end

local function dbScalar(sql, params)
    if type(sql) ~= 'string' then
        print(('[CM-AUTH] dbScalar expected SQL string, got %s'):format(type(sql)))
        return nil
    end
    local ok, result = pcall(function()
        return MySQL.scalar.await(sql, params or {})
    end)
    if not ok then
        print('[CM-AUTH] DB scalar failed: ' .. tostring(result))
        print('[CM-AUTH] SQL: ' .. sql)
        return nil
    end
    return result
end

local function sanitize(value)
    if type(value) ~= 'string' then return '' end
    value = value:gsub('%z', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return value
end

local function validateUsername(username)
    username = sanitize(username):lower()
    if #username < 3 then return false, 'Username must be at least 3 characters.' end
    if #username > 24 then return false, 'Username must be maximum 24 characters.' end
    if not username:match('^[a-z0-9_%.%-]+$') then
        return false, 'Username can only use letters, numbers, _, -, and .'
    end
    return true, username
end

local function validateEmail(email)
    email = sanitize(email):lower()
    if email == '' then return false, 'Email is required.' end
    if #email > 100 then return false, 'Email is too long.' end
    if not email:match('^[%w%._%+%-]+@[%w%-%.]+%.[%a][%a]+$') then
        return false, 'Enter a valid email.'
    end
    return true, email
end

local function LegacyTempHash(password)
    local h = 5381
    for i = 1, #password do
        h = ((h * 33) + string.byte(password, i)) % 2147483647
    end
    return 'TEMP_' .. tostring(h)
end

local function HashPassword(password)
    if type(password) ~= 'string' then return nil end
    -- Stable dev hash. Later we can migrate to bcrypt after the full flow is stable.
    return LegacyTempHash(password)
end

local function VerifyPassword(password, storedHash)
    if type(password) ~= 'string' or type(storedHash) ~= 'string' then return false end
    return HashPassword(password) == storedHash
end

local function GetSocialClubId(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find('license:', 1, true) then return id end
    end
    local identifiers = GetPlayerIdentifiers(src)
    return identifiers[1] or ('unknown_' .. tostring(src))
end

local function GetAccountBySocialClub(socialClubId)
    return dbSingle('SELECT * FROM accounts WHERE social_club_id = ? LIMIT 1', { socialClubId })
end

local function GetAccountByUsername(username)
    return dbSingle('SELECT * FROM accounts WHERE LOWER(username) = LOWER(?) LIMIT 1', { username })
end

local function recordLoginAttempt(username, src, success)
    dbQuery('INSERT INTO login_attempts (username, ip_address, hwid_hash, success) VALUES (?, ?, ?, ?)', {
        username or 'unknown',
        GetPlayerEndpoint(src) or 'unknown',
        GetPlayerToken(src, 0) or 'unknown',
        success and 1 or 0
    })
end

RegisterNetEvent('cm-auth:server:register', function(data)
    local src = source
    local now = GetGameTimer()
    if lastRegister[src] and now - lastRegister[src] < REGISTER_COOLDOWN then
        sendRegister(src, false, 'Please wait before trying again.')
        return
    end
    lastRegister[src] = now

    local ok, err = pcall(function()
        data = type(data) == 'table' and data or {}
        local socialClubId = GetSocialClubId(src)

        local validUsername, usernameOrError = validateUsername(data.username)
        if not validUsername then sendRegister(src, false, usernameOrError) return end
        local username = usernameOrError

        local validEmail, emailOrError = validateEmail(data.email)
        if not validEmail then sendRegister(src, false, emailOrError) return end
        local email = emailOrError

        local password = data.password
        if type(password) ~= 'string' or #password < 6 then
            sendRegister(src, false, 'Password must be at least 6 characters.')
            return
        end
        if #password > 72 then
            sendRegister(src, false, 'Password is too long.')
            return
        end

        local existingBySocial = GetAccountBySocialClub(socialClubId)
        if existingBySocial then
            sendRegister(src, false, 'You already have an account: ' .. tostring(existingBySocial.username) .. '. Please login instead.')
            return
        end

        local usernameCount = dbScalar('SELECT COUNT(*) FROM accounts WHERE LOWER(username) = LOWER(?)', { username }) or 0
        if tonumber(usernameCount) > 0 then
            sendRegister(src, false, 'Username taken')
            return
        end

        local accountId = tostring(os.time()) .. '_' .. math.random(1000, 9999)
        local hwid = GetPlayerToken(src, 0) or 'unknown'
        local ip = GetPlayerEndpoint(src) or 'unknown'
        local passwordHash = HashPassword(password)

        local result = dbQuery([[
            INSERT INTO accounts (id, social_club_id, account_slot, username, password_hash, email, hwid_hash, ip_address)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], { accountId, socialClubId, 1, username, passwordHash, email, hwid, ip })

        if result == nil then
            sendRegister(src, false, 'Database error. Check server console.')
            safeLog('cm-auth', 'error', 'Account insert returned nil', { player_src = src, username = username })
            return
        end

        safeLog('cm-auth', 'info', 'Account registered', {
            player_src = src, username = username, social_club = socialClubId
        })

        sendRegister(src, true, 'Account created')
    end)

    if not ok then
        print('[CM-AUTH] Register error: ' .. tostring(err))
        sendRegister(src, false, 'Register failed. Check server console.')
    end
end)

RegisterNetEvent('cm-auth:server:login', function(data)
    local src = source
    local now = GetGameTimer()
    if lastLogin[src] and now - lastLogin[src] < LOGIN_COOLDOWN then
        sendLogin(src, false, 'Please wait before trying again.')
        return
    end
    lastLogin[src] = now

    local ok, err = pcall(function()
        data = type(data) == 'table' and data or {}
        local socialClubId = GetSocialClubId(src)

        local username = sanitize(data.username or ''):lower()
        local password = data.password or ''

        local account = nil
        if username ~= '' then
            account = GetAccountByUsername(username)
        end

        if not account then
            account = GetAccountBySocialClub(socialClubId)
        end

        if not account then
            recordLoginAttempt(username, src, false)
            sendLogin(src, false, 'Invalid credentials')
            return
        end

        if account.social_club_id and account.social_club_id ~= '' and account.social_club_id ~= socialClubId then
            recordLoginAttempt(username, src, false)
            sendLogin(src, false, 'This account is linked to another PC')
            return
        end

        if password ~= '' and not VerifyPassword(password, tostring(account.password_hash or '')) then
            recordLoginAttempt(account.username or username, src, false)
            sendLogin(src, false, 'Invalid password')
            return
        end

        if account.banned == true or account.banned == 1 then
            sendLogin(src, false, 'Banned: ' .. tostring(account.ban_reason or 'No reason'))
            return
        end

        dbQuery('UPDATE accounts SET last_login = NOW(), social_club_id = ?, hwid_hash = ?, ip_address = ? WHERE id = ?', {
            socialClubId,
            GetPlayerToken(src, 0) or 'unknown',
            GetPlayerEndpoint(src) or 'unknown',
            account.id
        })

        recordLoginAttempt(account.username, src, true)

        safeLog('cm-auth', 'info', 'Login success', {
            player_src = src, account_id = account.id, username = account.username
        })

        local accountIdStr = tostring(account.id)
        print('[CM-AUTH] Login success, accountId=' .. accountIdStr)

        Player(src).state:set('accountId', accountIdStr, true)
        Player(src).state:set('isLoggedIn', true, true)
        Player(src).state:set('authLoggedIn', true, true)

        sendLogin(src, true, accountIdStr)
        Wait(100)
        TriggerClientEvent('cm-characters:client:openSelector', src, accountIdStr)
    end)

    if not ok then
        print('[CM-AUTH] Login error: ' .. tostring(err))
        sendLogin(src, false, 'Login failed. Check server console.')
    end
end)

RegisterNetEvent('cm-auth:server:requestOpen', function()
    local src = source
    if Player(src).state.isLoggedIn or Player(src).state.accountId then return end
    TriggerClientEvent('cm-auth:client:openLogin', src)
end)

RegisterNetEvent('cm-auth:server:logout', function()
    local src = source
    Player(src).state:set('accountId', nil, true)
    Player(src).state:set('isLoggedIn', false, true)
    Player(src).state:set('authLoggedIn', false, true)
    TriggerClientEvent('cm-auth:client:openLogin', src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastLogin[src] = nil
    lastRegister[src] = nil
end)

CreateThread(function()
    Wait(1000)
    print('[CM-AUTH] Stable patched v3 loaded')
end)
