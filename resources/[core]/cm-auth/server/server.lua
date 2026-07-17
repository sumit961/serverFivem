-- cm-auth/server/server.lua
-- Entry point. Wires the net-event handlers to the modules:
--   util · crypto · database · identity · security
-- Behavior and every event/state-bag name are preserved from v2.3.1 so the rest
-- of the CM framework keeps working unchanged.

local Util     = _G.CMAuthUtil
local Crypto   = _G.CMAuthCrypto
local DB       = _G.CMAuthDB
local Identity = _G.CMAuthIdentity
local Sec      = _G.CMAuthSecurity

-- ---- Client response helpers ------------------------------------------------

local function sendLogin(src, success, message)
    TriggerClientEvent('cm-auth:client:loginResult', src, success, message)
end
local function sendRegister(src, success, message)
    TriggerClientEvent('cm-auth:client:registerResult', src, success, message)
end
local function sendReset(src, success, message)
    TriggerClientEvent('cm-auth:client:resetResult', src, success, message)
end

-- Exports consumed by other resources.
exports('IsLoggedIn', Identity.isLoggedIn)
exports('GetAccountId', Identity.getAccountId)

-- ---- Shared login finalization ---------------------------------------------

local function finishLogin(src, account, token, mode)
    local accountIdStr = tostring(account.id)
    local email = tostring(account.email or ''):lower()

    Player(src).state:set('accountId', accountIdStr, true)
    Player(src).state:set('accountEmail', email, true)
    Player(src).state:set('isLoggedIn', true, true)
    Player(src).state:set('authLoggedIn', true, true)

    Util.log('cm-auth', 'info', 'Login success', {
        player_src = src, account_id = accountIdStr, email = email, mode = mode or 'password'
    })
    Util.dprint('Login success, accountId=' .. accountIdStr .. ', mode=' .. tostring(mode or 'password'))

    sendLogin(src, true, {
        accountId = accountIdStr,
        email = email,
        username = account.username or email,
        authToken = token,
        mode = mode or 'password'
    })
end

-- Validate a saved trusted-device token for this player. Returns account or nil,reason.
local function validateTokenForPlayer(src, token, email)
    token = Util.sanitize(token)
    email = Util.sanitize(email or ''):lower()
    if token == '' or #token < 16 or email == '' then
        return nil, 'Saved login expired. Please login again.'
    end

    local account = DB.getAccountByEmail(email)
    if not account or not account.auth_token or tostring(account.auth_token) == '' then
        return nil, 'Saved login expired. Please login again.'
    end

    if not Crypto.verify(token, tostring(account.auth_token)) then
        return nil, 'Saved login expired. Please login again.'
    end

    if account.auth_token_created_at then
        local expired = Util.scalar(
            ('SELECT (auth_token_created_at < DATE_SUB(NOW(), INTERVAL %d DAY)) FROM accounts WHERE id = ?'):format(Config.Token.maxAgeDays),
            { account.id })
        if expired == 1 or expired == true then
            return nil, 'Saved login expired. Please login again.'
        end
    end

    if account.banned == true or account.banned == 1 then
        return nil, 'Banned: ' .. tostring(account.ban_reason or 'No reason')
    end

    local security = Identity.getSecurity(src)
    if tostring(account.social_club_id or '') == '' or tostring(account.social_club_id) ~= security.social then
        return nil, 'Saved login does not match this Rockstar license.'
    end
    if tostring(account.hwid_hash or '') == '' or tostring(account.hwid_hash) ~= security.hwid then
        return nil, 'Saved login does not match this device.'
    end

    return account, nil, security
end

local function readTokenPayload(payload)
    if type(payload) == 'table' then
        return tostring(payload.token or ''), tostring(payload.email or '')
    end
    return tostring(payload or ''), ''  -- legacy: bare token string
end

-- ---- REGISTER ---------------------------------------------------------------

RegisterNetEvent('cm-auth:server:register', function(data)
    local src = source
    if not Sec.checkCooldown('register', src) then
        return sendRegister(src, false, 'Please wait before trying again.')
    end

    local ok, err = pcall(function()
        data = type(data) == 'table' and data or {}
        local security = Identity.getSecurity(src)

        if Sec.activeLockout(nil, security.ip) then
            return sendRegister(src, false, Sec.lockoutMessage(Sec.activeLockout(nil, security.ip)))
        end

        local recentRegs = Sec.countRecentRegisters(security.ip, security.hwid)
        if recentRegs >= Config.Lockout.registerLimit then
            Sec.applyLockout(nil, security.ip, ('%d registrations in %d minutes'):format(Config.Lockout.registerLimit, Config.Lockout.registerWindowMinutes))
            Util.log('cm-auth', 'warning', 'Register lockout applied', { player_src = src, ip = security.ip, attempts = recentRegs })
            return sendRegister(src, false, ('Too many accounts created from this connection. Try again in %d minutes.'):format(Config.Lockout.lockoutMinutes))
        end

        local validEmail, email = Identity.validateEmail(data.email)
        if not validEmail then return sendRegister(src, false, email) end

        local confirm = data.confirmPassword or data.password2 or data.confirm_password
        local pOk, pErr = Identity.validatePassword(data.password, confirm)
        if not pOk then return sendRegister(src, false, pErr) end

        if DB.getAccountBySocialClub(security.social) then
            return sendRegister(src, false, 'You already have an account. Please login instead.')
        end
        if DB.emailExists(email) then
            return sendRegister(src, false, 'Email already registered.')
        end

        local accountId = tostring(os.time()) .. '_' .. Crypto.randomString(4)
        local username = Crypto.makeUsernameFromEmail(email)
        local passwordHash, hashErr = Crypto.hash(data.password)
        if not passwordHash then return sendRegister(src, false, hashErr or 'Password security service error.') end

        Sec.recordRegisterAttempt(src, email)

        local result = Util.query([[
            INSERT INTO accounts (id, social_club_id, account_slot, username, password_hash, email, hwid_hash, ip_address)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], { accountId, security.social, 1, username, passwordHash, email, security.hwid, security.ip })

        if result == nil then
            Util.log('cm-auth', 'error', 'Account insert returned nil', { player_src = src, email = email })
            return sendRegister(src, false, 'Database error. Check server console.')
        end

        Util.log('cm-auth', 'info', 'Account registered', {
            player_src = src, email = email, username = username, social_club = security.social
        })
        sendRegister(src, true, 'Account created. You can login now.')
    end)

    if not ok then
        print('[CM-AUTH] Register error: ' .. tostring(err))
        sendRegister(src, false, 'Register failed. Check server console.')
    end
end)

-- ---- RESET PASSWORD (ownership proven by Rockstar license) ------------------

RegisterNetEvent('cm-auth:server:resetPassword', function(data)
    local src = source
    if not Sec.checkCooldown('reset', src) then
        return sendReset(src, false, 'Please wait before trying again.')
    end

    local ok, err = pcall(function()
        data = type(data) == 'table' and data or {}
        local security = Identity.getSecurity(src)

        if Sec.activeLockout(nil, security.ip) then
            return sendReset(src, false, Sec.lockoutMessage(Sec.activeLockout(nil, security.ip)))
        end

        local validEmail, email = Identity.validateEmail(data.email)
        if not validEmail then return sendReset(src, false, email) end

        local confirm = data.confirmPassword or data.password2 or data.confirm_password
        local pOk, pErr = Identity.validatePassword(data.password, confirm)
        if not pOk then return sendReset(src, false, pErr) end

        local account = DB.getAccountByEmail(email)
        -- Generic response whether the account is missing OR the license doesn't
        -- match, so we never reveal which emails exist.
        if not account or tostring(account.social_club_id or '') ~= security.social then
            if account then
                Util.log('cm-auth', 'warning', 'Password reset denied (license mismatch)', {
                    player_src = src, email = email, ip = security.ip
                })
            end
            return sendReset(src, false, 'This account is not linked to your Rockstar profile. Ask staff to reset it through cm-admin.')
        end

        local newHash, hashErr = Crypto.hash(data.password)
        if not newHash then return sendReset(src, false, hashErr or 'Password security service error.') end

        Util.query('UPDATE accounts SET password_hash = ?, auth_token = NULL, auth_token_created_at = NULL WHERE id = ?', { newHash, account.id })
        Util.log('cm-auth', 'warning', 'Password reset via Rockstar ownership', {
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

-- ---- LOGIN (email + password) -----------------------------------------------

RegisterNetEvent('cm-auth:server:login', function(data)
    local src = source
    if not Sec.checkCooldown('login', src) then
        return sendLogin(src, false, 'Please wait before trying again.')
    end

    local ok, err = pcall(function()
        data = type(data) == 'table' and data or {}
        local security = Identity.getSecurity(src)

        local ipLock = Sec.activeLockout(nil, security.ip)
        if ipLock then return sendLogin(src, false, Sec.lockoutMessage(ipLock)) end

        local validEmail, email = Identity.validateEmail(data.email)
        if not validEmail then return sendLogin(src, false, email) end

        local lockout = Sec.activeLockout(email, security.ip)
        if lockout then return sendLogin(src, false, Sec.lockoutMessage(lockout)) end

        if type(data.password) ~= 'string' or data.password == '' then
            return sendLogin(src, false, 'Password is required.')
        end

        local account = DB.getAccountByEmail(email)
        if not account then
            Sec.handleFailedLogin(email, src, security)
            return sendLogin(src, false, 'Email or password is incorrect.')
        end

        if account.social_club_id and account.social_club_id ~= '' and account.social_club_id ~= security.social then
            Sec.handleFailedLogin(email, src, security)
            return sendLogin(src, false, 'This account is linked to another PC.')
        end

        local verified, modeOrMessage = Crypto.verify(data.password, tostring(account.password_hash or ''))
        if not verified then
            local lockedNow = Sec.handleFailedLogin(email, src, security)
            if lockedNow then
                return sendLogin(src, false, ('Too many failed attempts. Account is locked for %d minutes.'):format(Config.Lockout.lockoutMinutes))
            end
            return sendLogin(src, false, modeOrMessage or 'Wrong password. Try again.')
        end

        if account.banned == true or account.banned == 1 then
            return sendLogin(src, false, 'Banned: ' .. tostring(account.ban_reason or 'No reason'))
        end

        -- Transparently upgrade legacy hashes to the strong scheme on success.
        if modeOrMessage == 'legacy' then
            local newHash = Crypto.hash(data.password)
            if newHash then
                Util.query('UPDATE accounts SET password_hash = ? WHERE id = ?', { newHash, account.id })
                Util.dprint('Migrated legacy password hash for account', account.id)
            end
        end

        -- Issue a fresh trusted-device token; store only its hash at rest.
        local authToken = Crypto.generateAuthToken()
        local tokenHash = Crypto.hash(authToken)
        if not tokenHash then
            return sendLogin(src, false, 'Password security service error. Try again.')
        end

        Util.query([[
            UPDATE accounts
            SET last_login = NOW(), social_club_id = ?, hwid_hash = ?, ip_address = ?, auth_token = ?, auth_token_created_at = NOW()
            WHERE id = ?
        ]], { security.social, security.hwid, security.ip, tokenHash, account.id })

        account.social_club_id = security.social
        account.hwid_hash = security.hwid
        account.ip_address = security.ip
        account.auth_token = tokenHash

        Sec.recordLoginAttempt(email, src, true)
        finishLogin(src, account, authToken, 'password')
    end)

    if not ok then
        print('[CM-AUTH] Login error: ' .. tostring(err))
        sendLogin(src, false, 'Login failed. Check server console.')
    end
end)

-- ---- TOKEN PREVIEW (show "welcome back" without logging in) ------------------

RegisterNetEvent('cm-auth:server:previewToken', function(payload)
    local src = source
    local guardOk, alreadyIn = pcall(function() return Player(src).state.isLoggedIn or Player(src).state.accountId end)
    if guardOk and alreadyIn then return end

    local token, email = readTokenPayload(payload)
    local ok, e = pcall(function()
        local account, reason = validateTokenForPlayer(src, token, email)
        if not account then
            return TriggerClientEvent('cm-auth:client:tokenPreview', src, false, reason)
        end
        TriggerClientEvent('cm-auth:client:tokenPreview', src, true, {
            accountId = tostring(account.id),
            email = tostring(account.email or ''):lower(),
            username = account.username or account.email or 'Player'
        })
    end)

    if not ok then
        print('[CM-AUTH] Token preview error: ' .. tostring(e))
        TriggerClientEvent('cm-auth:client:tokenPreview', src, false, 'Saved login failed. Please login again.')
    end
end)

-- ---- TOKEN LOGIN ------------------------------------------------------------

RegisterNetEvent('cm-auth:server:loginWithToken', function(payload)
    local src = source
    if not Sec.checkCooldown('token', src) then
        return sendLogin(src, false, 'Please wait before trying again.')
    end

    local token, email = readTokenPayload(payload)
    local ok, err = pcall(function()
        if Player(src).state.isLoggedIn or Player(src).state.accountId then return end

        local security = Identity.getSecurity(src)
        local lockout = Sec.activeLockout(nil, security.ip)
        if lockout then return sendLogin(src, false, Sec.lockoutMessage(lockout)) end

        local account, reason = validateTokenForPlayer(src, token, email)
        if not account then
            TriggerClientEvent('cm-auth:client:clearToken', src)
            return sendLogin(src, false, reason or 'Saved login expired. Please login again.')
        end

        Util.query('UPDATE accounts SET last_login = NOW(), ip_address = ? WHERE id = ?', { security.ip, account.id })
        Sec.recordLoginAttempt(account.email or 'token', src, true)
        finishLogin(src, account, token, 'token')
    end)

    if not ok then
        print('[CM-AUTH] Token login error: ' .. tostring(err))
        sendLogin(src, false, 'Saved login failed. Please login again.')
    end
end)

-- ---- OPEN / LOGOUT ----------------------------------------------------------

RegisterNetEvent('cm-auth:server:requestOpen', function()
    local src = source
    if Player(src).state.isLoggedIn or Player(src).state.accountId then return end
    TriggerClientEvent('cm-auth:client:openLogin', src)
end)

RegisterNetEvent('cm-auth:server:logout', function()
    local src = source
    local accountId = Player(src).state.accountId
    if accountId then
        Util.query('UPDATE accounts SET auth_token = NULL, auth_token_created_at = NULL WHERE id = ?', { tostring(accountId) })
    end
    Player(src).state:set('accountId', nil, true)
    Player(src).state:set('accountEmail', nil, true)
    Player(src).state:set('isLoggedIn', false, true)
    Player(src).state:set('authLoggedIn', false, true)
    TriggerClientEvent('cm-auth:client:clearToken', src)
    TriggerClientEvent('cm-auth:client:openLogin', src)
end)

AddEventHandler('playerDropped', function()
    Sec.clearPlayer(source)
end)

-- ---- Boot: schema + hashing self-test --------------------------------------

CreateThread(function()
    DB.ensureSchema()

    local probe, hashErr = Crypto.hash('cm-auth-selftest')
    if probe then
        local okVerify, verifyMode = Crypto.verify('cm-auth-selftest', probe)
        if okVerify then
            local provider = (verifyMode == 'native') and 'FXServer native bcrypt'
                or 'CM1 local salted SHA-256 fallback (WEAKER — enable the native if possible)'
            Util.dprint(('Password hashing OK via %s | trusted-device login enabled'):format(provider))
        else
            print(('[CM-AUTH] WARNING: password hash self-test failed to verify. %s'):format(tostring(verifyMode)))
        end
    else
        print(('[CM-AUTH] WARNING: password hashing unavailable. Register/login will fail. %s'):format(tostring(hashErr)))
    end
end)
