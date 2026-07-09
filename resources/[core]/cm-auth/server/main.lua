-- cm-auth/server/main.lua
-- Modern email/password auth with trusted-device token login, lockouts,
-- safe session state, and clean handoff to cm-characters.
-- Admin/staff tools belong in cm-admin, not here.

local DEBUG = false
local LOGIN_COOLDOWN = 1500
local REGISTER_COOLDOWN = 3000
local FAILED_WINDOW_MINUTES = 15
local FAILED_LIMIT = 5
local LOCKOUT_MINUTES = 30
local REGISTER_WINDOW_MINUTES = 60
local REGISTER_LIMIT = 3
local TOKEN_MAX_AGE_DAYS = 30

local lastLogin = {}
local lastRegister = {}
local lastTokenLogin = {}
local lastReset = {}

-- Prefer FXServer native password hashing. If the server artifact does not
-- provide it, use CM1 local salted iterative SHA-256 fallback. No external
-- external password resource/export is used by this version.
local TOKEN_CHARS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
local LOCAL_HASH_PREFIX = 'CM1$'
local LOCAL_HASH_ROUNDS = 1500

math.randomseed(os.time() + GetGameTimer())

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

local function shouldPrintLevel(level)
    level = tostring(level or 'info'):lower()
    return DEBUG or level == 'warning' or level == 'error' or level == 'critical'
end

local function safeLog(resource, level, message, metadata)
    metadata = metadata or {}
    metadata.category = metadata.category or 'auth'
    local ok = pcall(function()
        if exports['cm-core'] and exports['cm-core'].Log then
            exports['cm-core'].Log(resource or 'cm-auth', level or 'info', message or '', metadata)
        elseif shouldPrintLevel(level) then
            print(('[CM-AUTH] %s: %s'):format(level or 'info', message or ''))
        end
    end)
    if not ok and shouldPrintLevel(level) then
        print(('[CM-AUTH] %s: %s'):format(level or 'info', message or ''))
    end
end

local function notify(src, message, msgType)
    if src == 0 then
        print(('[CM-AUTH] %s'):format(message or ''))
        return
    end

    local color = { 210, 210, 210 }
    if msgType == 'success' then
        color = { 90, 220, 160 }
    elseif msgType == 'error' then
        color = { 255, 105, 120 }
    end

    TriggerClientEvent('chat:addMessage', src, {
        color = color,
        args = { 'cm-auth', message or '' }
    })
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
        dprint('SQL:', sql)
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
        dprint('SQL:', sql)
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
        dprint('SQL:', sql)
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

local function isSourceLoggedIn(src)
    if not src or src == 0 then return false end
    local ok, value = pcall(function() return Player(src).state.isLoggedIn == true end)
    return ok and value == true
end

local function getSourceAccountId(src)
    if not src or src == 0 then return nil end
    local ok, value = pcall(function() return Player(src).state.accountId end)
    if ok and value then return tostring(value) end
    return nil
end

exports('IsLoggedIn', isSourceLoggedIn)
exports('GetAccountId', getSourceAccountId)

-- Reseed from several changing sources before generating a credential. This is
-- not a full CSPRNG (Lua has no native secure RNG), but it removes the trivial
-- predictability of seeding once at boot.
local function reseedRandom()
    local micro = math.floor((os.clock() * 1000000) % 1000000)
    local seed = ((os.time() % 100000) * 1000000) + micro + (GetGameTimer() % 1000000)
    math.randomseed(seed)
    for _ = 1, 7 do math.random() end
end

local function randomString(length)
    local output = {}
    for i = 1, length do
        local index = math.random(1, #TOKEN_CHARS)
        output[#output + 1] = TOKEN_CHARS:sub(index, index)
    end
    return table.concat(output)
end

local function makeUsernameFromEmail(email)
    local base = tostring(email or ''):match('^([^@]+)') or 'player'
    base = base:lower():gsub('[^a-z0-9_%.%-]', '')
    if #base < 3 then base = 'player' end
    if #base > 14 then base = base:sub(1, 14) end
    return ('%s_%s'):format(base, randomString(6):lower())
end

local function generateAuthToken()
    reseedRandom()
    -- 48 random chars from a 62-char alphabet. The raw token is sent only to
    -- the client once and a hash is stored in the database.
    return randomString(48)
end

local function tryNativeHash(password)
    if type(GetPasswordHash) ~= 'function' then
        return false, 'FXServer GetPasswordHash native is not available on this build.'
    end

    local ok, result = pcall(function()
        return GetPasswordHash(password)
    end)

    if ok and type(result) == 'string' and result ~= '' then
        return true, result
    end

    return false, ok and 'FXServer GetPasswordHash returned an invalid hash.' or tostring(result)
end

local function tryNativeVerify(password, storedHash)
    if type(VerifyPasswordHash) ~= 'function' then
        return false, 'FXServer VerifyPasswordHash native is not available on this build.'
    end

    local ok, result = pcall(function()
        return VerifyPasswordHash(password, storedHash)
    end)

    if ok then
        return true, (result == true or result == 1)
    end

    return false, tostring(result)
end

local function bxor(a, b)
    return (a ~ b) & 0xffffffff
end

local function rrotate(x, n)
    return ((x >> n) | (x << (32 - n))) & 0xffffffff
end

local SHA256_K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

local function sha256(message)
    message = tostring(message or '')
    local bytes = { message:byte(1, #message) }
    local bitLen = #bytes * 8

    bytes[#bytes + 1] = 0x80
    while (#bytes % 64) ~= 56 do
        bytes[#bytes + 1] = 0
    end

    -- FiveM passwords/tokens are far below 2^32 bits, so the high 32 bits are 0.
    for _ = 1, 4 do bytes[#bytes + 1] = 0 end
    for shift = 24, 0, -8 do
        bytes[#bytes + 1] = (bitLen >> shift) & 0xff
    end

    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

    for chunk = 1, #bytes, 64 do
        local w = {}
        for i = 0, 15 do
            local j = chunk + (i * 4)
            w[i] = (((bytes[j] or 0) << 24) | ((bytes[j + 1] or 0) << 16) | ((bytes[j + 2] or 0) << 8) | (bytes[j + 3] or 0)) & 0xffffffff
        end

        for i = 16, 63 do
            local s0 = bxor(bxor(rrotate(w[i - 15], 7), rrotate(w[i - 15], 18)), (w[i - 15] >> 3))
            local s1 = bxor(bxor(rrotate(w[i - 2], 17), rrotate(w[i - 2], 19)), (w[i - 2] >> 10))
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff
        end

        local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7

        for i = 0, 63 do
            local S1 = bxor(bxor(rrotate(e, 6), rrotate(e, 11)), rrotate(e, 25))
            local ch = bxor((e & f), (((~e) & 0xffffffff) & g))
            local temp1 = (h + S1 + ch + SHA256_K[i + 1] + w[i]) & 0xffffffff
            local S0 = bxor(bxor(rrotate(a, 2), rrotate(a, 13)), rrotate(a, 22))
            local maj = bxor(bxor((a & b), (a & c)), (b & c))
            local temp2 = (S0 + maj) & 0xffffffff

            h = g
            g = f
            f = e
            e = (d + temp1) & 0xffffffff
            d = c
            c = b
            b = a
            a = (temp1 + temp2) & 0xffffffff
        end

        h0 = (h0 + a) & 0xffffffff
        h1 = (h1 + b) & 0xffffffff
        h2 = (h2 + c) & 0xffffffff
        h3 = (h3 + d) & 0xffffffff
        h4 = (h4 + e) & 0xffffffff
        h5 = (h5 + f) & 0xffffffff
        h6 = (h6 + g) & 0xffffffff
        h7 = (h7 + h) & 0xffffffff
    end

    return ('%08x%08x%08x%08x%08x%08x%08x%08x'):format(h0, h1, h2, h3, h4, h5, h6, h7)
end

local function safeEquals(a, b)
    a = tostring(a or '')
    b = tostring(b or '')
    if #a ~= #b then return false end

    local diff = 0
    for i = 1, #a do
        diff = diff | (a:byte(i) ~ b:byte(i))
    end
    return diff == 0
end

local function makeLocalPasswordHash(password, salt, rounds)
    rounds = tonumber(rounds) or LOCAL_HASH_ROUNDS
    local digest = sha256(tostring(salt) .. ':' .. tostring(password))
    for _ = 1, rounds do
        digest = sha256(digest .. ':' .. tostring(salt) .. ':' .. tostring(password))
    end
    return digest
end

local function createLocalPasswordHash(password)
    reseedRandom()
    local salt = randomString(24)
    local digest = makeLocalPasswordHash(password, salt, LOCAL_HASH_ROUNDS)
    return ('%s%d$%s$%s'):format(LOCAL_HASH_PREFIX, LOCAL_HASH_ROUNDS, salt, digest)
end

local function verifyLocalPasswordHash(password, storedHash)
    local rounds, salt, digest = tostring(storedHash or ''):match('^CM1%$(%d+)%$([A-Za-z0-9]+)%$([a-fA-F0-9]+)$')
    if not rounds or not salt or not digest then
        return false
    end

    local check = makeLocalPasswordHash(password, salt, tonumber(rounds) or LOCAL_HASH_ROUNDS)
    return safeEquals(check:lower(), digest:lower())
end

local function LegacyTempHash(password)
    local h = 5381
    for i = 1, #password do
        h = ((h * 33) + string.byte(password, i)) % 2147483647
    end
    return 'TEMP_' .. tostring(h)
end

local function HashPassword(password)
    if type(password) ~= 'string' then return nil, 'Invalid password.' end

    local nativeOk, nativeResult = tryNativeHash(password)
    if nativeOk then return nativeResult end

    -- No external dependency: use the local CM1 salted SHA-256 fallback.
    return createLocalPasswordHash(password)
end

local function VerifyPassword(password, storedHash)
    if type(password) ~= 'string' or type(storedHash) ~= 'string' or storedHash == '' then
        return false, 'Invalid credentials.'
    end

    if storedHash:sub(1, #LOCAL_HASH_PREFIX) == LOCAL_HASH_PREFIX then
        if verifyLocalPasswordHash(password, storedHash) then
            return true, 'cm-local'
        end
        return false, 'Wrong password. Try again.'
    end

    -- Legacy fallback hashes do not depend on any external resource.
    if storedHash:sub(1, 5) == 'TEMP_' then
        if LegacyTempHash(password) == storedHash then
            return true, 'legacy'
        end
        return false, 'Wrong password. Try again.'
    end

    local nativeOk, nativeResult = tryNativeVerify(password, storedHash)
    if nativeOk then
        if nativeResult == true then return true, 'native' end
        return false, 'Wrong password. Try again.'
    end

    return false, 'Password verification unavailable for this old hash. Reset the password.'
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

local function GetAccountByToken(token)
    return dbSingle('SELECT * FROM accounts WHERE auth_token = ? LIMIT 1', { token })
end

local function GetAccountByIdOrEmail(target)
    target = sanitize(target)
    if target == '' then return nil end
    return dbSingle('SELECT * FROM accounts WHERE id = ? OR LOWER(email) = LOWER(?) LIMIT 1', { target, target })
end

local function getPlayerSecurity(src)
    return {
        social = GetSocialClubId(src),
        hwid = GetPlayerToken(src, 0) or 'unknown',
        ip = GetPlayerEndpoint(src) or 'unknown'
    }
end

local function lockKeyEmail(email)
    email = sanitize(email):lower()
    if email == '' then return nil end
    return 'email:' .. email
end

local function lockKeyIp(ip)
    ip = sanitize(ip)
    if ip == '' or ip == 'unknown' then return nil end
    return 'ip:' .. ip
end

local function activeLockout(email, ip)
    local keys = {}
    local emailKey = lockKeyEmail(email)
    local ipKey = lockKeyIp(ip)
    if emailKey then keys[#keys + 1] = emailKey end
    if ipKey then keys[#keys + 1] = ipKey end
    if #keys == 0 then return nil end

    local placeholders = {}
    for i = 1, #keys do placeholders[#placeholders + 1] = '?' end

    local sql = ([[
        SELECT lock_key, locked_until, reason
        FROM auth_lockouts
        WHERE lock_key IN (%s) AND locked_until > NOW()
        ORDER BY locked_until DESC
        LIMIT 1
    ]]):format(table.concat(placeholders, ','))

    return dbSingle(sql, keys)
end

local function lockoutMessage(lockout)
    if not lockout then return nil end
    return 'Too many failed login attempts. Try again after ' .. tostring(lockout.locked_until or 'the lockout expires') .. '.'
end

local function countRecentFailures(email, ip)
    local sql = ([[
        SELECT COUNT(*)
        FROM login_attempts
        WHERE success = 0
          AND created_at >= DATE_SUB(NOW(), INTERVAL %d MINUTE)
          AND (LOWER(username) = LOWER(?) OR ip_address = ?)
    ]]):format(FAILED_WINDOW_MINUTES)

    return tonumber(dbScalar(sql, { email or 'unknown', ip or 'unknown' }) or 0) or 0
end

local function applyLockout(email, ip, reason)
    reason = reason or 'Too many failed login attempts'
    local keys = {}
    local emailKey = lockKeyEmail(email)
    local ipKey = lockKeyIp(ip)
    if emailKey then keys[#keys + 1] = emailKey end
    if ipKey then keys[#keys + 1] = ipKey end

    local sql = ([[
        INSERT INTO auth_lockouts (lock_key, locked_until, reason)
        VALUES (?, DATE_ADD(NOW(), INTERVAL %d MINUTE), ?)
        ON DUPLICATE KEY UPDATE locked_until = VALUES(locked_until), reason = VALUES(reason)
    ]]):format(LOCKOUT_MINUTES)

    for _, key in ipairs(keys) do
        dbQuery(sql, { key, reason })
    end
end

local function recordLoginAttempt(identifier, src, success)
    dbQuery('INSERT INTO login_attempts (username, ip_address, hwid_hash, success) VALUES (?, ?, ?, ?)', {
        identifier or 'unknown',
        GetPlayerEndpoint(src) or 'unknown',
        GetPlayerToken(src, 0) or 'unknown',
        success and 1 or 0
    })
end

local function recordRegisterAttempt(src, email)
    dbQuery('INSERT INTO register_attempts (ip_address, hwid_hash, email) VALUES (?, ?, ?)', {
        GetPlayerEndpoint(src) or 'unknown',
        GetPlayerToken(src, 0) or 'unknown',
        email or 'unknown'
    })
end

local function countRecentRegisters(ip, hwid)
    local sql = ([[
        SELECT COUNT(*)
        FROM register_attempts
        WHERE created_at >= DATE_SUB(NOW(), INTERVAL %d MINUTE)
          AND (ip_address = ? OR hwid_hash = ?)
    ]]):format(REGISTER_WINDOW_MINUTES)

    return tonumber(dbScalar(sql, { ip or 'unknown', hwid or 'unknown' }) or 0) or 0
end

local function handleFailedLogin(email, src)
    local security = getPlayerSecurity(src)
    recordLoginAttempt(email or 'unknown', src, false)

    local failures = countRecentFailures(email or 'unknown', security.ip)
    if failures >= FAILED_LIMIT then
        applyLockout(email, security.ip, ('%d failed attempts in %d minutes'):format(FAILED_LIMIT, FAILED_WINDOW_MINUTES))
        safeLog('cm-auth', 'warning', 'Login lockout applied', {
            player_src = src,
            email = email,
            ip = security.ip,
            failures = failures
        })
        return true
    end

    return false
end

local function ensureAuthDatabase()
    dbQuery([[CREATE TABLE IF NOT EXISTS login_attempts (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(100) NOT NULL,
        ip_address VARCHAR(64) NULL,
        hwid_hash VARCHAR(255) NULL,
        success TINYINT(1) NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])

    dbQuery([[CREATE TABLE IF NOT EXISTS auth_lockouts (
        lock_key VARCHAR(160) NOT NULL PRIMARY KEY,
        locked_until DATETIME NOT NULL,
        reason VARCHAR(255) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])


    dbQuery([[CREATE TABLE IF NOT EXISTS register_attempts (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        ip_address VARCHAR(64) NULL,
        hwid_hash VARCHAR(255) NULL,
        email VARCHAR(100) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_register_lookup (ip_address, hwid_hash, created_at)
    )]])

    local createdAtCol = dbQuery("SHOW COLUMNS FROM login_attempts LIKE 'created_at'")
    if not createdAtCol or not createdAtCol[1] then
        dbQuery('ALTER TABLE login_attempts ADD COLUMN created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP')
    end

    local tokenCol = dbQuery("SHOW COLUMNS FROM accounts LIKE 'auth_token'")
    if not tokenCol or not tokenCol[1] then
        dbQuery('ALTER TABLE accounts ADD COLUMN auth_token VARCHAR(128) NULL')
    end

    local tokenCreatedCol = dbQuery("SHOW COLUMNS FROM accounts LIKE 'auth_token_created_at'")
    if not tokenCreatedCol or not tokenCreatedCol[1] then
        dbQuery('ALTER TABLE accounts ADD COLUMN auth_token_created_at DATETIME NULL')
    end


    -- Indexes to speed up lookups and stop duplicate-account races at the DB level.
    local function indexExists(tableName, indexName)
        local rows = dbQuery(("SHOW INDEX FROM %s WHERE Key_name = ?"):format(tableName), { indexName })
        return rows and rows[1] ~= nil
    end

    if not indexExists('accounts', 'uniq_accounts_email') then
        local added = dbQuery('ALTER TABLE accounts ADD UNIQUE INDEX uniq_accounts_email (email)')
        if added == nil then
            print('[CM-AUTH] NOTE: could not add UNIQUE index on accounts.email (likely existing duplicate emails). Clean duplicates, then restart to enforce it.')
        end
    end

    if not indexExists('accounts', 'uniq_accounts_social') then
        local added = dbQuery('ALTER TABLE accounts ADD UNIQUE INDEX uniq_accounts_social (social_club_id)')
        if added == nil then
            print('[CM-AUTH] NOTE: could not add UNIQUE index on accounts.social_club_id (likely existing duplicates). Clean duplicates, then restart to enforce it.')
        end
    end

    if not indexExists('login_attempts', 'idx_attempts_lookup') then
        dbQuery('ALTER TABLE login_attempts ADD INDEX idx_attempts_lookup (username, ip_address, created_at)')
    end

end

local function finishLogin(src, account, token, mode)
    local accountIdStr = tostring(account.id)
    local email = tostring(account.email or ''):lower()

    Player(src).state:set('accountId', accountIdStr, true)
    Player(src).state:set('accountEmail', email, true)
    Player(src).state:set('isLoggedIn', true, true)
    Player(src).state:set('authLoggedIn', true, true)

    safeLog('cm-auth', 'info', 'Login success', {
        player_src = src,
        account_id = accountIdStr,
        email = email,
        mode = mode or 'password'
    })

    dprint('Login success, accountId=' .. accountIdStr .. ', mode=' .. tostring(mode or 'password'))

    sendLogin(src, true, {
        accountId = accountIdStr,
        email = email,
        username = account.username or email,
        authToken = token,
        mode = mode or 'password'
    })
end

local function validateTokenForPlayer(src, token, email)
    token = sanitize(token)
    email = sanitize(email or ''):lower()
    if token == '' or #token < 16 or email == '' then
        return nil, 'Saved login expired. Please login again.'
    end

    -- Look the account up by email, then verify the raw token against the
    -- hash stored at rest. A leaked database row no longer reveals usable tokens.
    local account = GetAccountByEmail(email)
    if not account or not account.auth_token or tostring(account.auth_token) == '' then
        return nil, 'Saved login expired. Please login again.'
    end

    local tokenOk = VerifyPassword(token, tostring(account.auth_token))
    if not tokenOk then
        return nil, 'Saved login expired. Please login again.'
    end

    -- Optional expiry: tokens older than TOKEN_MAX_AGE_DAYS require a fresh login.
    if account.auth_token_created_at then
        local expired = dbScalar(
            ('SELECT (auth_token_created_at < DATE_SUB(NOW(), INTERVAL %d DAY)) FROM accounts WHERE id = ?'):format(TOKEN_MAX_AGE_DAYS),
            { account.id })
        if expired == 1 or expired == true then
            return nil, 'Saved login expired. Please login again.'
        end
    end

    if account.banned == true or account.banned == 1 then
        return nil, 'Banned: ' .. tostring(account.ban_reason or 'No reason')
    end

    local security = getPlayerSecurity(src)
    local accountSocial = tostring(account.social_club_id or '')
    local accountHwid = tostring(account.hwid_hash or '')

    if accountSocial == '' or accountSocial ~= security.social then
        return nil, 'Saved login does not match this Rockstar license.'
    end

    if accountHwid == '' or accountHwid ~= security.hwid then
        return nil, 'Saved login does not match this device.'
    end

    return account, nil, security
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
        local security = getPlayerSecurity(src)

        -- A brute-forcer who got login-locked should not be able to pivot to register.
        local ipLock = activeLockout(nil, security.ip)
        if ipLock then sendRegister(src, false, lockoutMessage(ipLock)) return end

        -- Throttle account creation per IP/HWID to stop mass-registration abuse.
        local recentRegs = countRecentRegisters(security.ip, security.hwid)
        if recentRegs >= REGISTER_LIMIT then
            applyLockout(nil, security.ip, ('%d registrations in %d minutes'):format(REGISTER_LIMIT, REGISTER_WINDOW_MINUTES))
            safeLog('cm-auth', 'warning', 'Register lockout applied', { player_src = src, ip = security.ip, attempts = recentRegs })
            sendRegister(src, false, ('Too many accounts created from this connection. Try again in %d minutes.'):format(LOCKOUT_MINUTES))
            return
        end

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

        local existingBySocial = GetAccountBySocialClub(security.social)
        if existingBySocial then
            sendRegister(src, false, 'You already have an account. Please login instead.')
            return
        end

        local emailCount = tonumber(dbScalar('SELECT COUNT(*) FROM accounts WHERE LOWER(email) = LOWER(?)', { email }) or 0) or 0
        if emailCount > 0 then
            sendRegister(src, false, 'Email already registered.')
            return
        end

        local accountId = tostring(os.time()) .. '_' .. tostring(math.random(1000, 9999))
        local username = makeUsernameFromEmail(email)
        local passwordHash, hashErr = HashPassword(password)
        if not passwordHash then
            sendRegister(src, false, hashErr or 'Password security service error.')
            return
        end

        recordRegisterAttempt(src, email)

        local result = dbQuery([[
            INSERT INTO accounts (id, social_club_id, account_slot, username, password_hash, email, hwid_hash, ip_address)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], { accountId, security.social, 1, username, passwordHash, email, security.hwid, security.ip })

        if result == nil then
            sendRegister(src, false, 'Database error. Check server console.')
            safeLog('cm-auth', 'error', 'Account insert returned nil', { player_src = src, email = email })
            return
        end

        safeLog('cm-auth', 'info', 'Account registered', {
            player_src = src,
            email = email,
            username = username,
            social_club = security.social
        })

        sendRegister(src, true, 'Account created. You can login now.')
    end)

    if not ok then
        print('[CM-AUTH] Register error: ' .. tostring(err))
        sendRegister(src, false, 'Register failed. Check server console.')
    end
end)

local function sendReset(src, success, message)
    TriggerClientEvent('cm-auth:client:resetResult', src, success, message)
end

-- Self-service password reset. Ownership is proven by the player's Rockstar
-- license matching the account, so no email server is required.
RegisterNetEvent('cm-auth:server:resetPassword', function(data)
    local src = source
    local now = GetGameTimer()
    if lastReset[src] and now - lastReset[src] < REGISTER_COOLDOWN then
        sendReset(src, false, 'Please wait before trying again.')
        return
    end
    lastReset[src] = now

    local ok, err = pcall(function()
        data = type(data) == 'table' and data or {}
        local security = getPlayerSecurity(src)

        local ipLock = activeLockout(nil, security.ip)
        if ipLock then sendReset(src, false, lockoutMessage(ipLock)) return end

        local validEmail, emailOrError = validateEmail(data.email)
        if not validEmail then sendReset(src, false, emailOrError) return end
        local email = emailOrError

        local password = data.password
        local confirmPassword = data.confirmPassword or data.password2 or data.confirm_password
        if type(password) ~= 'string' or #password < 6 then
            sendReset(src, false, 'Password must be at least 6 characters.')
            return
        end
        if #password > 72 then
            sendReset(src, false, 'Password is too long.')
            return
        end
        if password ~= confirmPassword then
            sendReset(src, false, 'Passwords do not match.')
            return
        end

        local account = GetAccountByEmail(email)
        -- Generic response when missing OR license mismatch, to avoid leaking
        -- which emails exist.
        if not account or tostring(account.social_club_id or '') ~= security.social then
            if account then
                safeLog('cm-auth', 'warning', 'Password reset denied (license mismatch)', {
                    player_src = src, email = email, ip = security.ip
                })
            end
            sendReset(src, false, 'This account is not linked to your Rockstar profile. Ask staff to reset it through cm-admin.')
            return
        end

        local newHash, hashErr = HashPassword(password)
        if not newHash then
            sendReset(src, false, hashErr or 'Password security service error.')
            return
        end

        dbQuery('UPDATE accounts SET password_hash = ?, auth_token = NULL, auth_token_created_at = NULL WHERE id = ?', { newHash, account.id })
        safeLog('cm-auth', 'warning', 'Password reset via Rockstar ownership', {
            player_src = src, account_id = tostring(account.id), email = email
        })

        TriggerClientEvent('cm-auth:client:clearToken', src)
        sendReset(src, true, 'Password updated. You can login now.')
    end)

    if not ok then
        print('[CM-AUTH] Reset error: ' .. tostring(err))
        sendReset(src, false, 'Reset failed. Check server console.')
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
        local security = getPlayerSecurity(src)

        local ipLock = activeLockout(nil, security.ip)
        if ipLock then
            sendLogin(src, false, lockoutMessage(ipLock))
            return
        end

        local validEmail, emailOrError = validateEmail(data.email)
        if not validEmail then sendLogin(src, false, emailOrError) return end
        local email = emailOrError

        local lockout = activeLockout(email, security.ip)
        if lockout then
            sendLogin(src, false, lockoutMessage(lockout))
            return
        end

        local password = data.password
        if type(password) ~= 'string' or password == '' then
            sendLogin(src, false, 'Password is required.')
            return
        end

        local account = GetAccountByEmail(email)
        if not account then
            handleFailedLogin(email, src)
            sendLogin(src, false, 'Email or password is incorrect.')
            return
        end

        if account.social_club_id and account.social_club_id ~= '' and account.social_club_id ~= security.social then
            handleFailedLogin(email, src)
            sendLogin(src, false, 'This account is linked to another PC.')
            return
        end

        local verified, modeOrMessage = VerifyPassword(password, tostring(account.password_hash or ''))
        if not verified then
            local lockedNow = handleFailedLogin(email, src)
            if lockedNow then
                sendLogin(src, false, ('Too many failed attempts. Account is locked for %d minutes.'):format(LOCKOUT_MINUTES))
            else
                sendLogin(src, false, modeOrMessage or 'Wrong password. Try again.')
            end
            return
        end

        if account.banned == true or account.banned == 1 then
            sendLogin(src, false, 'Banned: ' .. tostring(account.ban_reason or 'No reason'))
            return
        end

        if modeOrMessage == 'legacy' then
            local newHash = HashPassword(password)
            if newHash then
                dbQuery('UPDATE accounts SET password_hash = ? WHERE id = ?', { newHash, account.id })
                dprint('Migrated legacy password hash for account', account.id)
            end
        end

        local authToken = generateAuthToken()
        local tokenHash = HashPassword(authToken)
        if not tokenHash then
            -- Should not happen (login already proved password hashing works), but never
            -- store a raw token if hashing fails.
            sendLogin(src, false, 'Password security service error. Try again.')
            return
        end

        dbQuery([[
            UPDATE accounts
            SET last_login = NOW(), social_club_id = ?, hwid_hash = ?, ip_address = ?, auth_token = ?, auth_token_created_at = NOW()
            WHERE id = ?
        ]], { security.social, security.hwid, security.ip, tokenHash, account.id })

        account.social_club_id = security.social
        account.hwid_hash = security.hwid
        account.ip_address = security.ip
        account.auth_token = tokenHash

        recordLoginAttempt(email, src, true)
        finishLogin(src, account, authToken, 'password')
    end)

    if not ok then
        print('[CM-AUTH] Login error: ' .. tostring(err))
        sendLogin(src, false, 'Login failed. Check server console.')
    end
end)

local function readTokenPayload(payload)
    if type(payload) == 'table' then
        return tostring(payload.token or ''), tostring(payload.email or '')
    end
    -- Backwards compatibility: older clients sent just the token string.
    return tostring(payload or ''), ''
end

RegisterNetEvent('cm-auth:server:previewToken', function(payload)
    local src = source
    local guardOk, alreadyIn = pcall(function() return Player(src).state.isLoggedIn or Player(src).state.accountId end)
    if guardOk and alreadyIn then return end

    local token, email = readTokenPayload(payload)

    local ok, accountOrErr = pcall(function()
        local account, reason = validateTokenForPlayer(src, token, email)
        if not account then
            TriggerClientEvent('cm-auth:client:tokenPreview', src, false, reason)
            return
        end

        TriggerClientEvent('cm-auth:client:tokenPreview', src, true, {
            accountId = tostring(account.id),
            email = tostring(account.email or ''):lower(),
            username = account.username or account.email or 'Player'
        })
    end)

    if not ok then
        print('[CM-AUTH] Token preview error: ' .. tostring(accountOrErr))
        TriggerClientEvent('cm-auth:client:tokenPreview', src, false, 'Saved login failed. Please login again.')
    end
end)

RegisterNetEvent('cm-auth:server:loginWithToken', function(payload)
    local src = source
    local now = GetGameTimer()
    if lastTokenLogin[src] and now - lastTokenLogin[src] < LOGIN_COOLDOWN then
        sendLogin(src, false, 'Please wait before trying again.')
        return
    end
    lastTokenLogin[src] = now

    local token, email = readTokenPayload(payload)

    local ok, err = pcall(function()
        if Player(src).state.isLoggedIn or Player(src).state.accountId then return end

        local security = getPlayerSecurity(src)
        local lockout = activeLockout(nil, security.ip)
        if lockout then
            sendLogin(src, false, lockoutMessage(lockout))
            return
        end

        local account, reason = validateTokenForPlayer(src, token, email)
        if not account then
            TriggerClientEvent('cm-auth:client:clearToken', src)
            sendLogin(src, false, reason or 'Saved login expired. Please login again.')
            return
        end

        dbQuery('UPDATE accounts SET last_login = NOW(), ip_address = ? WHERE id = ?', { security.ip, account.id })
        recordLoginAttempt(account.email or 'token', src, true)
        finishLogin(src, account, token, 'token')
    end)

    if not ok then
        print('[CM-AUTH] Token login error: ' .. tostring(err))
        sendLogin(src, false, 'Saved login failed. Please login again.')
    end
end)

RegisterNetEvent('cm-auth:server:requestOpen', function()
    local src = source
    if Player(src).state.isLoggedIn or Player(src).state.accountId then return end
    TriggerClientEvent('cm-auth:client:openLogin', src)
end)

RegisterNetEvent('cm-auth:server:logout', function()
    local src = source
    local accountId = Player(src).state.accountId

    if accountId then
        dbQuery('UPDATE accounts SET auth_token = NULL, auth_token_created_at = NULL WHERE id = ?', { tostring(accountId) })
    end

    Player(src).state:set('accountId', nil, true)
    Player(src).state:set('accountEmail', nil, true)
    Player(src).state:set('isLoggedIn', false, true)
    Player(src).state:set('authLoggedIn', false, true)
    TriggerClientEvent('cm-auth:client:clearToken', src)
    TriggerClientEvent('cm-auth:client:openLogin', src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastLogin[src] = nil
    lastRegister[src] = nil
    lastTokenLogin[src] = nil
    lastReset[src] = nil
end)

CreateThread(function()
    ensureAuthDatabase()

    -- Self-test: prove hashing + verifying actually works at boot so any
    -- problem is visible before a player tries to register/login.
    local probe, hashErr = HashPassword('cm-auth-selftest')
    if probe then
        local okVerify, verifyMode = VerifyPassword('cm-auth-selftest', probe)
        if okVerify then
            local provider = (verifyMode == 'native') and 'FXServer native GetPasswordHash/VerifyPasswordHash'
                or 'CM1 local salted SHA-256 fallback'
            dprint(('Password hashing OK via %s | trusted-device login enabled'):format(provider))
        else
            print(('[CM-AUTH] WARNING: password hash self-test failed to verify. %s'):format(tostring(verifyMode)))
        end
    else
        print(('[CM-AUTH] WARNING: password hashing unavailable. Register/login will fail. %s'):format(tostring(hashErr)))
    end
end)
