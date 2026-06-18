-- cm-auth/server/main.lua
-- Modern email/password auth with bcrypt, trusted-device token login, lockouts,
-- 10-tier RBAC admin cache, and identifier reset helpers.

local DEBUG = false
local LOGIN_COOLDOWN = 1500
local REGISTER_COOLDOWN = 3000
local FAILED_WINDOW_MINUTES = 15
local FAILED_LIMIT = 5
local LOCKOUT_MINUTES = 30

local lastLogin = {}
local lastRegister = {}
local lastTokenLogin = {}

local BCRYPT_RESOURCES = { 'bcrypt', 'fivem-bcrypt', 'cm-bcrypt' }
local TOKEN_CHARS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

local RankCache = {}
local DefaultRankSeeds = {
    { level = 1,  name = 'Helper',             permissions = { 'auth.lookup' } },
    { level = 2,  name = 'Trial Moderator',    permissions = { 'auth.lookup', 'auth.reset.ip' } },
    { level = 3,  name = 'Moderator',          permissions = { 'auth.lookup', 'auth.reset.ip', 'auth.reset.hwid' } },
    { level = 4,  name = 'Senior Moderator',   permissions = { 'auth.lookup', 'auth.reset.ip', 'auth.reset.hwid' } },
    { level = 5,  name = 'Administrator',      permissions = { 'auth.lookup', 'auth.reset.ip', 'auth.reset.hwid', 'auth.reset.socialclub' } },
    { level = 6,  name = 'Senior Admin',       permissions = { 'auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload' } },
    { level = 7,  name = 'Head Admin',         permissions = { 'auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload' } },
    { level = 8,  name = 'Community Manager',  permissions = { 'auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload' } },
    { level = 9,  name = 'Developer',          permissions = { 'auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload' } },
    { level = 10, name = 'Owner',              permissions = { '*' } },
}

local RESET_PERMISSION_MAP = {
    hwid_hash = 'auth.reset.hwid',
    ip_address = 'auth.reset.ip',
    social_club_id = 'auth.reset.socialclub'
}

local RESET_LABELS = {
    hwid_hash = 'HWID',
    ip_address = 'IP address',
    social_club_id = 'Social Club / Rockstar license'
}

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

local function normalizePermissions(raw)
    if type(raw) == 'string' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            raw = decoded
        else
            raw = {}
        end
    end

    if type(raw) ~= 'table' then
        raw = {}
    end

    local seen = {}
    local output = {}
    for _, perm in ipairs(raw) do
        if type(perm) == 'string' then
            perm = sanitize(perm)
            if perm ~= '' and not seen[perm] then
                seen[perm] = true
                output[#output + 1] = perm
            end
        end
    end

    return output
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
    return ('cm_%s_%s_%s'):format(tostring(os.time()), randomString(32), randomString(32))
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

local function seedAdminRanksIfNeeded()
    local count = tonumber(dbScalar('SELECT COUNT(*) FROM admin_ranks', {}) or 0) or 0
    if count > 0 then return end

    for _, rank in ipairs(DefaultRankSeeds) do
        dbQuery('INSERT INTO admin_ranks (`level`, `name`, `permissions`) VALUES (?, ?, ?)', {
            rank.level,
            rank.name,
            json.encode(rank.permissions)
        })
    end
end

local function loadRankCache()
    RankCache = {}
    local rows = dbQuery('SELECT `level`, `name`, `permissions` FROM admin_ranks ORDER BY `level` ASC', {}) or {}

    for _, row in ipairs(rows) do
        local level = tonumber(row.level) or 0
        if level > 0 then
            RankCache[level] = {
                level = level,
                name = tostring(row.name or ('Level ' .. tostring(level))),
                permissions = normalizePermissions(row.permissions)
            }
        end
    end

    return RankCache
end

local function getRankData(adminLevel)
    adminLevel = tonumber(adminLevel) or 0
    local rank = RankCache[adminLevel]
    if rank then return rank end

    return {
        level = adminLevel,
        name = adminLevel > 0 and ('Level ' .. tostring(adminLevel)) or 'Player',
        permissions = {}
    }
end

local function permissionMatches(granted, requested)
    if granted == '*' or granted == requested then return true end
    if granted:sub(-2) == '.*' then
        local prefix = granted:sub(1, -3)
        return requested:sub(1, #prefix) == prefix
    end
    return false
end

local function syncAdminState(src, adminLevel)
    local rank = getRankData(adminLevel)
    local perms = rank.permissions or {}

    Player(src).state:set('adminLevel', tonumber(rank.level) or 0, true)
    Player(src).state:set('adminRankName', rank.name or 'Player', true)
    Player(src).state:set('adminPermissions', perms, true)

    return perms, rank
end

local function clearAdminState(src)
    Player(src).state:set('adminLevel', 0, true)
    Player(src).state:set('adminRankName', nil, true)
    Player(src).state:set('adminPermissions', {}, true)
end

function HasPermission(src, permissionNode)
    if src == 0 then return true end
    if not src or not permissionNode or type(permissionNode) ~= 'string' then return false end

    local state = Player(src).state
    local adminLevel = tonumber(state.adminLevel or 0) or 0
    if adminLevel >= 10 then return true end

    local perms = state.adminPermissions or {}
    if type(perms) == 'string' then
        perms = normalizePermissions(perms)
    elseif type(perms) ~= 'table' then
        perms = {}
    end

    for _, granted in ipairs(perms) do
        if type(granted) == 'string' and permissionMatches(granted, permissionNode) then
            return true
        end
    end

    return false
end

_G.HasPermission = HasPermission
exports('HasPermission', HasPermission)

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

    dbQuery([[CREATE TABLE IF NOT EXISTS admin_ranks (
        `level` TINYINT UNSIGNED NOT NULL,
        `name` VARCHAR(64) NOT NULL,
        `permissions` JSON NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`level`)
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

    local adminLevelCol = dbQuery("SHOW COLUMNS FROM accounts LIKE 'admin_level'")
    if not adminLevelCol or not adminLevelCol[1] then
        dbQuery('ALTER TABLE accounts ADD COLUMN admin_level TINYINT UNSIGNED NOT NULL DEFAULT 0')
    end

    seedAdminRanksIfNeeded()
    loadRankCache()
end

local function finishLogin(src, account, token, mode)
    local accountIdStr = tostring(account.id)
    local email = tostring(account.email or ''):lower()
    local adminLevel = tonumber(account.admin_level or 0) or 0

    Player(src).state:set('accountId', accountIdStr, true)
    Player(src).state:set('accountEmail', email, true)
    Player(src).state:set('isLoggedIn', true, true)
    Player(src).state:set('authLoggedIn', true, true)

    local activePerms, rank = syncAdminState(src, adminLevel)

    safeLog('cm-auth', 'info', 'Login success', {
        player_src = src,
        account_id = accountIdStr,
        email = email,
        mode = mode or 'password',
        admin_level = adminLevel,
        admin_rank = rank.name or 'Player'
    })

    print('[CM-AUTH] Login success, accountId=' .. accountIdStr .. ', mode=' .. tostring(mode or 'password'))

    sendLogin(src, true, {
        accountId = accountIdStr,
        email = email,
        username = account.username or email,
        authToken = token,
        mode = mode or 'password',
        adminLevel = adminLevel,
        adminRank = rank.name or 'Player',
        adminPermissions = activePerms
    })
end

local function validateTokenForPlayer(src, token)
    token = sanitize(token)
    if token == '' or #token < 32 then
        return nil, 'Saved login expired. Please login again.'
    end

    local account = GetAccountByToken(token)
    if not account then
        return nil, 'Saved login expired. Please login again.'
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

local function canResetField(src, field)
    local permissionNode = RESET_PERMISSION_MAP[field]
    if not permissionNode then return false end

    if HasPermission(src, 'auth.reset.identifiers') then return true end
    return HasPermission(src, permissionNode)
end

local function performAdminReset(actorSrc, target, field)
    if not canResetField(actorSrc, field) then
        notify(actorSrc, 'You do not have permission to reset ' .. tostring(RESET_LABELS[field] or field) .. '.', 'error')
        return false
    end

    local account = GetAccountByIdOrEmail(target)
    if not account then
        notify(actorSrc, 'Target account not found.', 'error')
        return false
    end

    dbQuery(([[
        UPDATE accounts
        SET %s = NULL,
            auth_token = NULL,
            auth_token_created_at = NULL
        WHERE id = ?
    ]]):format(field), { account.id })

    safeLog('cm-auth', 'warning', 'Admin reset identifier', {
        actor_src = actorSrc,
        target_account = tostring(account.id),
        target_email = tostring(account.email or ''),
        field = field
    })

    notify(actorSrc, ('Reset %s for account %s (%s).'):format(RESET_LABELS[field] or field, tostring(account.id), tostring(account.email or 'no-email')), 'success')
    return true
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

        local result = dbQuery([[
            INSERT INTO accounts (id, social_club_id, account_slot, username, password_hash, email, hwid_hash, ip_address, admin_level)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], { accountId, security.social, 1, username, passwordHash, email, security.hwid, security.ip, 0 })

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
        dbQuery([[
            UPDATE accounts
            SET last_login = NOW(), social_club_id = ?, hwid_hash = ?, ip_address = ?, auth_token = ?, auth_token_created_at = NOW()
            WHERE id = ?
        ]], { security.social, security.hwid, security.ip, authToken, account.id })

        account.social_club_id = security.social
        account.hwid_hash = security.hwid
        account.ip_address = security.ip
        account.auth_token = authToken

        recordLoginAttempt(email, src, true)
        finishLogin(src, account, authToken, 'password')
    end)

    if not ok then
        print('[CM-AUTH] Login error: ' .. tostring(err))
        sendLogin(src, false, 'Login failed. Check server console.')
    end
end)

RegisterNetEvent('cm-auth:server:previewToken', function(token)
    local src = source
    if Player(src).state.isLoggedIn or Player(src).state.accountId then return end

    local ok, accountOrErr = pcall(function()
        local account, reason = validateTokenForPlayer(src, token)
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

RegisterNetEvent('cm-auth:server:loginWithToken', function(token)
    local src = source
    local now = GetGameTimer()
    if lastTokenLogin[src] and now - lastTokenLogin[src] < LOGIN_COOLDOWN then
        sendLogin(src, false, 'Please wait before trying again.')
        return
    end
    lastTokenLogin[src] = now

    local ok, err = pcall(function()
        if Player(src).state.isLoggedIn or Player(src).state.accountId then return end

        local security = getPlayerSecurity(src)
        local lockout = activeLockout(nil, security.ip)
        if lockout then
            sendLogin(src, false, lockoutMessage(lockout))
            return
        end

        local account, reason = validateTokenForPlayer(src, token)
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
    clearAdminState(src)

    TriggerClientEvent('cm-auth:client:clearToken', src)
    TriggerClientEvent('cm-auth:client:openLogin', src)
end)

RegisterNetEvent('cm-auth:server:adminResetIdentifier', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local target = sanitize(data.target)
    local field = sanitize(data.field)

    if target == '' or field == '' then
        notify(src, 'Usage: target and field are required.', 'error')
        return
    end

    if RESET_PERMISSION_MAP[field] == nil then
        notify(src, 'Invalid reset field.', 'error')
        return
    end

    performAdminReset(src, target, field)
end)

RegisterCommand('authreloadranks', function(src)
    if src ~= 0 and not HasPermission(src, 'auth.ranks.reload') then
        notify(src, 'You do not have permission to reload admin ranks.', 'error')
        return
    end

    loadRankCache()
    notify(src, ('Admin rank cache reloaded (%d ranks).'):format(#DefaultRankSeeds), 'success')
end, false)

RegisterCommand('authresethwid', function(src, args)
    local target = sanitize(args[1] or '')
    if target == '' then
        notify(src, 'Usage: /authresethwid <accountId|email>', 'error')
        return
    end
    performAdminReset(src, target, 'hwid_hash')
end, false)

RegisterCommand('authresetip', function(src, args)
    local target = sanitize(args[1] or '')
    if target == '' then
        notify(src, 'Usage: /authresetip <accountId|email>', 'error')
        return
    end
    performAdminReset(src, target, 'ip_address')
end, false)

RegisterCommand('authresetsocialclub', function(src, args)
    local target = sanitize(args[1] or '')
    if target == '' then
        notify(src, 'Usage: /authresetsocialclub <accountId|email>', 'error')
        return
    end
    performAdminReset(src, target, 'social_club_id')
end, false)

AddEventHandler('playerDropped', function()
    local src = source
    lastLogin[src] = nil
    lastRegister[src] = nil
    lastTokenLogin[src] = nil
end)

CreateThread(function()
    ensureAuthDatabase()

    local bcryptResource = getBcryptResource()
    if bcryptResource then
        print(('[CM-AUTH] Modern bcrypt auth loaded | bcrypt resource: %s | trusted-device login enabled | admin ranks cached: %s'):format(bcryptResource, tostring(#DefaultRankSeeds)))
    else
        print('[CM-AUTH] Modern bcrypt auth loaded | WARNING: no bcrypt resource started. Register/login will fail until bcrypt is ensured before cm-auth.')
    end
end)
