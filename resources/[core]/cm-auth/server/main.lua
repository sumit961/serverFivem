-- cm-auth/server/main.lua
-- Modern email/password auth with bcrypt support and legacy TEMP_ migration.

local DEBUG = false
local LOGIN_COOLDOWN = 1500
local REGISTER_COOLDOWN = 3000
local lastLogin = {}
local lastRegister = {}

local BCRYPT_RESOURCES = { 'bcrypt', 'fivem-bcrypt', 'cm-bcrypt' }

local function dprint(...)
    if not DEBUG then return end
    local args = { ... }
    local msg = '[CM-AUTH-DEBUG] '
    for i = 1, #args do msg = msg .. tostring(args[i]) .. ' ' end
    print(msg)
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

local function validateEmail(email)
    email = sanitize(email):lower()
    if email == '' then return false, 'Email is required.' end
    if #email > 100 then return false, 'Email is too long.' end
    if not email:match('^[%w%._%+%-]+@[%w%-%.]+%.[%a][%a]+$') then
        return false, 'Enter a valid email address.'
    end
    return true, email
end

local function makeUsernameFromEmail(email)
    local base = tostring(email or ''):match('^([^@]+)') or 'player'
    base = base:lower():gsub('[^a-z0-9_%.%-]', '')
    if #base < 3 then base = 'player' end
    if #base > 18 then base = base:sub(1, 18) end

    local candidate = base
    local index = 1
    while true do
        local count = tonumber(dbScalar('SELECT COUNT(*) FROM accounts WHERE LOWER(username) = LOWER(?)', { candidate }) or 0) or 0
        if count <= 0 then return candidate end
        candidate = ('%s%s'):format(base:sub(1, 18), tostring(index))
        if #candidate > 24 then candidate = candidate:sub(1, 24) end
        index = index + 1
    end
end

local function getBcryptResource()
    for _, resourceName in ipairs(BCRYPT_RESOURCES) do
        if GetResourceState(resourceName) == 'started' then
            return resourceName
        end
    end
    return nil
end

local function callBcrypt(exportNames, ...)
    local resourceName = getBcryptResource()
    if not resourceName then
        return false, 'bcrypt resource is not started. Ensure bcrypt before cm-auth.'
    end

    for _, exportName in ipairs(exportNames) do
        local ok, result = pcall(function(...)
            return exports[resourceName][exportName](...)
        end, ...)
        if ok and result ~= nil then
            return true, result
        end
    end

    return false, ('bcrypt export not found on %s'):format(resourceName)
end

-- Legacy support only for migrating old TEMP_ accounts after bcrypt is installed.
local function LegacyTempHash(password)
    local h = 5381
    for i = 1, #password do
        h = ((h * 33) + string.byte(password, i)) % 2147483647
    end
    return 'TEMP_' .. tostring(h)
end

local function HashPassword(password)
    if type(password) ~= 'string' then return nil, 'Invalid password.' end
    local ok, result = callBcrypt({ 'hash_sync', 'HashPassword', 'hash' }, password)
    if not ok then return nil, result end
    if type(result) ~= 'string' or result == '' then return nil, 'bcrypt returned invalid hash.' end
    return result
end

local function VerifyPassword(password, storedHash)
    if type(password) ~= 'string' or type(storedHash) ~= 'string' or storedHash == '' then
        return false, 'Invalid credentials.'
    end

    if storedHash:sub(1, 5) == 'TEMP_' then
        local resourceName = getBcryptResource()
        if not resourceName then
            return false, 'Password security service is not running.'
        end
        if LegacyTempHash(password) == storedHash then
            return true, 'legacy'
        end
        return false, 'Wrong password. Try again.'
    end

    local ok, result = callBcrypt({ 'check_sync', 'verify_sync', 'compare_sync', 'VerifyPassword', 'check', 'compare' }, password, storedHash)
    if not ok then return false, result end
    if result == true or result == 1 then return true, 'bcrypt' end
    return false, 'Wrong password. Try again.'
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

local function GetAccountByEmail(email)
    return dbSingle('SELECT * FROM accounts WHERE LOWER(email) = LOWER(?) LIMIT 1', { email })
end

local function recordLoginAttempt(identifier, src, success)
    dbQuery('INSERT INTO login_attempts (username, ip_address, hwid_hash, success) VALUES (?, ?, ?, ?)', {
        identifier or 'unknown',
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

        local validEmail, emailOrError = validateEmail(data.email)
        if not validEmail then sendRegister(src, false, emailOrError) return end
        local email = emailOrError

        local password = data.password
        local confirmPassword = data.confirmPassword or data.password2 or data.confirm_password
        if type(password) ~= 'string' or #password < 6 then
            sendRegister(src, false, 'Password must be at least 6 characters.')
            return
        end
        if #password > 72 then
            sendRegister(src, false, 'Password is too long.')
            return
        end
        if password ~= confirmPassword then
            sendRegister(src, false, 'Passwords do not match.')
            return
        end

        local existingBySocial = GetAccountBySocialClub(socialClubId)
        if existingBySocial then
            sendRegister(src, false, 'You already have an account. Please login instead.')
            return
        end

        local emailCount = tonumber(dbScalar('SELECT COUNT(*) FROM accounts WHERE LOWER(email) = LOWER(?)', { email }) or 0) or 0
        if emailCount > 0 then
            sendRegister(src, false, 'Email already registered.')
            return
        end

        local accountId = tostring(os.time()) .. '_' .. math.random(1000, 9999)
        local username = makeUsernameFromEmail(email)
        local hwid = GetPlayerToken(src, 0) or 'unknown'
        local ip = GetPlayerEndpoint(src) or 'unknown'
        local passwordHash, hashErr = HashPassword(password)
        if not passwordHash then
            sendRegister(src, false, hashErr or 'Password security service error.')
            return
        end

        local result = dbQuery([[
            INSERT INTO accounts (id, social_club_id, account_slot, username, password_hash, email, hwid_hash, ip_address)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], { accountId, socialClubId, 1, username, passwordHash, email, hwid, ip })

        if result == nil then
            sendRegister(src, false, 'Database error. Check server console.')
            safeLog('cm-auth', 'error', 'Account insert returned nil', { player_src = src, email = email })
            return
        end

        safeLog('cm-auth', 'info', 'Account registered', {
            player_src = src, email = email, username = username, social_club = socialClubId
        })

        sendRegister(src, true, 'Account created. You can login now.')
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

        local validEmail, emailOrError = validateEmail(data.email)
        if not validEmail then sendLogin(src, false, emailOrError) return end
        local email = emailOrError

        local password = data.password
        if type(password) ~= 'string' or password == '' then
            sendLogin(src, false, 'Password is required.')
            return
        end

        local account = GetAccountByEmail(email)
        if not account then
            recordLoginAttempt(email, src, false)
            sendLogin(src, false, 'Email or password is incorrect.')
            return
        end

        if account.social_club_id and account.social_club_id ~= '' and account.social_club_id ~= socialClubId then
            recordLoginAttempt(email, src, false)
            sendLogin(src, false, 'This account is linked to another PC.')
            return
        end

        local verified, modeOrMessage = VerifyPassword(password, tostring(account.password_hash or ''))
        if not verified then
            recordLoginAttempt(email, src, false)
            sendLogin(src, false, modeOrMessage or 'Wrong password. Try again.')
            return
        end

        if account.banned == true or account.banned == 1 then
            sendLogin(src, false, 'Banned: ' .. tostring(account.ban_reason or 'No reason'))
            return
        end

        -- If the old TEMP_ hash was used, migrate this account to bcrypt after successful login.
        if modeOrMessage == 'legacy' then
            local newHash = HashPassword(password)
            if newHash then
                dbQuery('UPDATE accounts SET password_hash = ? WHERE id = ?', { newHash, account.id })
                dprint('Migrated legacy password hash for account', account.id)
            end
        end

        dbQuery('UPDATE accounts SET last_login = NOW(), social_club_id = ?, hwid_hash = ?, ip_address = ? WHERE id = ?', {
            socialClubId,
            GetPlayerToken(src, 0) or 'unknown',
            GetPlayerEndpoint(src) or 'unknown',
            account.id
        })

        recordLoginAttempt(email, src, true)

        safeLog('cm-auth', 'info', 'Login success', {
            player_src = src, account_id = account.id, email = email
        })

        local accountIdStr = tostring(account.id)
        print('[CM-AUTH] Login success, accountId=' .. accountIdStr)

        Player(src).state:set('accountId', accountIdStr, true)
        Player(src).state:set('accountEmail', email, true)
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
    Player(src).state:set('accountEmail', nil, true)
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
    local bcryptResource = getBcryptResource()
    if bcryptResource then
        print(('[CM-AUTH] Modern bcrypt auth loaded | bcrypt resource: %s'):format(bcryptResource))
    else
        print('[CM-AUTH] Modern bcrypt auth loaded | WARNING: no bcrypt resource started. Register/login will fail until bcrypt is ensured before cm-auth.')
    end
end)
