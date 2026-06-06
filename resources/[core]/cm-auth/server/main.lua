-- cm-auth/server/main.lua
-- 1 account per social club, 2 character slots

local DEBUG = true

local function dprint(...)
    if DEBUG then
        local args = {...}
        local msg = '[CM-AUTH-DEBUG] '
        for i = 1, #args do
            msg = msg .. tostring(args[i]) .. ' '
        end
        print(msg)
    end
end

-- ============================================
-- PASSWORD HASHING
-- ============================================

local function HashPassword(password)
    dprint('HashPassword called')
    local ok, hash = pcall(function()
        return exports.ox_lib:hashPassword(password)
    end)
    if ok and hash then return hash end
    dprint('ox_lib failed, using fallback')
    local h = 5381
    for i = 1, #password do
        h = ((h * 33) + string.byte(password, i)) % 2147483647
    end
    return 'TEMP_' .. tostring(h)
end

local function VerifyPassword(password, hash)
    if string.sub(hash, 1, 5) == 'TEMP_' then
        return HashPassword(password) == hash
    end
    local ok, result = pcall(function()
        return exports.ox_lib:verifyPassword(password, hash)
    end)
    if ok then return result end
    return false
end

-- Get social club ID (license identifier)
local function GetSocialClubId(src)
    local identifiers = GetPlayerIdentifiers(src)
    for _, id in ipairs(identifiers) do
        if string.find(id, 'license:') then
            return id
        end
    end
    return identifiers[1] or 'unknown_' .. src
end

-- Check if social club already has an account
local function GetAccountBySocialClub(socialClubId)
    local result = exports['cm-core']:Query(
        'SELECT * FROM accounts WHERE social_club_id = ? LIMIT 1',
        {socialClubId}
    )
    return result and result[1] or nil
end

-- ============================================
-- REGISTER (only 1 account per social club)
-- ============================================

RegisterNetEvent('cm-auth:server:register', function(data)
    local src = source
    dprint('========== REGISTER START ==========')
    dprint('Source:', src)
    
    local socialClubId = GetSocialClubId(src)
    dprint('Social Club:', socialClubId)
    
    -- Check if social club already has account
    local existing = GetAccountBySocialClub(socialClubId)
    if existing then
        dprint('Social club already has account:', existing.username)
        TriggerClientEvent('cm-auth:client:registerResult', src, false, 
            'You already have an account: ' .. existing.username .. '. Please login instead.')
        return
    end
    
    data.username = exports['cm-core']:Sanitize(data.username or "")
    data.email = exports['cm-core']:Sanitize(data.email or "")
    
    local ok, err = exports['cm-core']:Validate('username', data.username)
    if not ok then
        TriggerClientEvent('cm-auth:client:registerResult', src, false, err)
        return
    end
    
    if not data.password or #data.password < 6 then
        TriggerClientEvent('cm-auth:client:registerResult', src, false, 'Password too short')
        return
    end
    
    -- Check username unique
    local exists = exports['cm-core']:Scalar('SELECT COUNT(*) FROM accounts WHERE username = ?', {data.username})
    if exists and exists > 0 then
        TriggerClientEvent('cm-auth:client:registerResult', src, false, 'Username taken')
        return
    end
    
    local id = tostring(os.time()) .. '_' .. math.random(1000, 9999)
    local hwid = GetPlayerToken(src, 0) or 'unknown'
    local ip = GetPlayerEndpoint(src) or 'unknown'
    
    local ok2, result = pcall(function()
        return exports['cm-core']:Insert([[
            INSERT INTO accounts (id, social_club_id, username, password_hash, email, hwid_hash, ip_address)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], {id, socialClubId, data.username, HashPassword(data.password), data.email, hwid, ip})
    end)
    
    if not ok2 then
        TriggerClientEvent('cm-auth:client:registerResult', src, false, 'Database error: ' .. tostring(result))
        return
    end
    
    exports['cm-core']:Log('cm-auth', 'info', 'Account registered', {
        category = 'auth', player_src = src, username = data.username, social_club = socialClubId
    })
    
    TriggerClientEvent('cm-auth:client:registerResult', src, true, 'Account created')
    dprint('========== REGISTER END ==========')
end)

-- ============================================
-- LOGIN
-- ============================================

RegisterNetEvent('cm-auth:server:login', function(data)
    local src = source
    dprint('========== LOGIN START ==========')
    
    local socialClubId = GetSocialClubId(src)
    dprint('Social Club:', socialClubId)
    
    data.username = exports['cm-core']:Sanitize(data.username or "")
    
    -- Find account by username OR social club (auto-login if account exists)
    local account = exports['cm-core']:Query('SELECT * FROM accounts WHERE username = ?', {data.username})
    
    if not account or #account == 0 then
        -- Check if social club has account (maybe they forgot username)
        local socialAccount = GetAccountBySocialClub(socialClubId)
        if socialAccount then
            dprint('Found account by social club:', socialAccount.username)
            account = {socialAccount}
        else
            TriggerClientEvent('cm-auth:client:loginResult', src, false, 'Invalid credentials')
            return
        end
    end
    
    account = account[1]
    
    -- If logging in with different username than social club account, block it
    if account.social_club_id and account.social_club_id ~= socialClubId then
        dprint('Account belongs to different social club')
        TriggerClientEvent('cm-auth:client:loginResult', src, false, 'This account is linked to another PC')
        return
    end
    
    -- Verify password (skip if auto-login by social club)
    if data.username ~= '' and data.password and #data.password > 0 then
        if not VerifyPassword(data.password, account.password_hash) then
            exports['cm-core']:Insert('INSERT INTO login_attempts (username, ip_address, hwid_hash, success) VALUES (?, ?, ?, ?)', {
                data.username, GetPlayerEndpoint(src) or 'unknown', GetPlayerToken(src, 0) or 'unknown', false
            })
            TriggerClientEvent('cm-auth:client:loginResult', src, false, 'Invalid password')
            return
        end
    end
    
    -- Check ban
    if account.banned then
        if account.ban_expires == nil or account.ban_expires > os.date('%Y-%m-%d %H:%M:%S') then
            TriggerClientEvent('cm-auth:client:loginResult', src, false, 'Banned: ' .. (account.ban_reason or 'No reason'))
            return
        end
    end
    
    -- Update last login and social club (if not set)
    exports['cm-core']:Query('UPDATE accounts SET last_login = NOW(), social_club_id = ? WHERE id = ?', 
        {socialClubId, account.id})
    
    exports['cm-core']:Insert('INSERT INTO login_attempts (username, ip_address, hwid_hash, success) VALUES (?, ?, ?, ?)', {
        account.username, GetPlayerEndpoint(src) or 'unknown', GetPlayerToken(src, 0) or 'unknown', true
    })
    
    exports['cm-core']:Log('cm-auth', 'info', 'Login success', {
        category = 'auth', player_src = src, account_id = account.id
    })
    
    TriggerClientEvent('cm-auth:client:loginResult', src, true, account.id)
    dprint('========== LOGIN END ==========')
end)