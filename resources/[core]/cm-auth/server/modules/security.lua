-- cm-auth/server/modules/security.lua
-- Brute-force defense: DB-backed lockouts, failure/registration counting, and
-- lightweight in-memory per-player cooldowns (cleared on disconnect).

local Util = _G.CMAuthUtil
local Sec = {}

local L = Config.Lockout

-- ---- In-memory per-src cooldowns -------------------------------------------

local cooldowns = { login = {}, register = {}, reset = {}, token = {} }

-- Returns true if the action is allowed (and stamps it); false if still cooling down.
function Sec.checkCooldown(kind, src)
    local table_ = cooldowns[kind]
    if not table_ then return true end
    local now = GetGameTimer()
    local last = table_[src]
    local wait = Config.Cooldowns[kind] or 1500
    if last and (now - last) < wait then return false end
    table_[src] = now
    return true
end

function Sec.clearPlayer(src)
    for _, t in pairs(cooldowns) do t[src] = nil end
end

-- ---- Lockout keys -----------------------------------------------------------

local function lockKeyEmail(email)
    email = Util.sanitize(email):lower()
    if email == '' then return nil end
    return 'email:' .. email
end

local function lockKeyIp(ip)
    ip = Util.sanitize(ip)
    if ip == '' or ip == 'unknown' then return nil end
    return 'ip:' .. ip
end

local function keysFor(email, ip)
    local keys = {}
    local ek, ik = lockKeyEmail(email), lockKeyIp(ip)
    if ek then keys[#keys + 1] = ek end
    if ik then keys[#keys + 1] = ik end
    return keys
end

-- ---- Lockout queries --------------------------------------------------------

function Sec.activeLockout(email, ip)
    local keys = keysFor(email, ip)
    if #keys == 0 then return nil end
    local placeholders = {}
    for i = 1, #keys do placeholders[i] = '?' end
    local sql = ([[
        SELECT lock_key, locked_until, reason
        FROM auth_lockouts
        WHERE lock_key IN (%s) AND locked_until > NOW()
        ORDER BY locked_until DESC LIMIT 1
    ]]):format(table.concat(placeholders, ','))
    return Util.single(sql, keys)
end

function Sec.lockoutMessage(lockout)
    if not lockout then return nil end
    return 'Too many failed login attempts. Try again after ' .. tostring(lockout.locked_until or 'the lockout expires') .. '.'
end

function Sec.applyLockout(email, ip, reason)
    reason = reason or 'Too many failed login attempts'
    local sql = ([[
        INSERT INTO auth_lockouts (lock_key, locked_until, reason)
        VALUES (?, DATE_ADD(NOW(), INTERVAL %d MINUTE), ?)
        ON DUPLICATE KEY UPDATE locked_until = VALUES(locked_until), reason = VALUES(reason)
    ]]):format(L.lockoutMinutes)
    for _, key in ipairs(keysFor(email, ip)) do
        Util.query(sql, { key, reason })
    end
end

-- ---- Attempt recording + counting ------------------------------------------

function Sec.recordLoginAttempt(identifier, src, success)
    Util.query('INSERT INTO login_attempts (username, ip_address, hwid_hash, success) VALUES (?, ?, ?, ?)', {
        identifier or 'unknown',
        GetPlayerEndpoint(src) or 'unknown',
        GetPlayerToken(src, 0) or 'unknown',
        success and 1 or 0
    })
end

function Sec.recordRegisterAttempt(src, email)
    Util.query('INSERT INTO register_attempts (ip_address, hwid_hash, email) VALUES (?, ?, ?)', {
        GetPlayerEndpoint(src) or 'unknown',
        GetPlayerToken(src, 0) or 'unknown',
        email or 'unknown'
    })
end

function Sec.countRecentFailures(email, ip)
    local sql = ([[
        SELECT COUNT(*) FROM login_attempts
        WHERE success = 0
          AND created_at >= DATE_SUB(NOW(), INTERVAL %d MINUTE)
          AND (LOWER(username) = LOWER(?) OR ip_address = ?)
    ]]):format(L.failedWindowMinutes)
    return tonumber(Util.scalar(sql, { email or 'unknown', ip or 'unknown' }) or 0) or 0
end

function Sec.countRecentRegisters(ip, hwid)
    local sql = ([[
        SELECT COUNT(*) FROM register_attempts
        WHERE created_at >= DATE_SUB(NOW(), INTERVAL %d MINUTE)
          AND (ip_address = ? OR hwid_hash = ?)
    ]]):format(L.registerWindowMinutes)
    return tonumber(Util.scalar(sql, { ip or 'unknown', hwid or 'unknown' }) or 0) or 0
end

-- Record the failed login and apply a lockout once the threshold is crossed.
-- Returns true if a lockout was applied this call.
function Sec.handleFailedLogin(email, src, security)
    Sec.recordLoginAttempt(email or 'unknown', src, false)
    local failures = Sec.countRecentFailures(email or 'unknown', security.ip)
    if failures >= L.failedLimit then
        Sec.applyLockout(email, security.ip, ('%d failed attempts in %d minutes'):format(L.failedLimit, L.failedWindowMinutes))
        Util.log('cm-auth', 'warning', 'Login lockout applied', {
            player_src = src, email = email, ip = security.ip, failures = failures
        })
        return true
    end
    return false
end

_G.CMAuthSecurity = Sec
return Sec
