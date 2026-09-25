-- cm-auth/server/modules/identity.lua
-- Player identity extraction (license/HWID/IP), email validation, and the
-- logged-in state helpers/exports. These are the values we trust to bind an
-- account to a physical device, so they are always read server-side.

local Util = _G.CMAuthUtil
local Identity = {}

function Identity.getSocialClubId(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find('license:', 1, true) then return id end
    end
    local identifiers = GetPlayerIdentifiers(src)
    return identifiers[1] or ('unknown_' .. tostring(src))
end

-- Bundle of the trust anchors for a connecting player.
function Identity.getSecurity(src)
    return {
        social = Identity.getSocialClubId(src),
        hwid   = GetPlayerToken(src, 0) or 'unknown',
        ip     = GetPlayerEndpoint(src) or 'unknown',
    }
end

function Identity.validateEmail(email)
    email = Util.sanitize(email):lower()
    if email == '' then return false, 'Email is required.' end
    if #email > 100 then return false, 'Email is too long.' end
    -- Lua patterns have no {n,} quantifier, so the TLD is matched as
    -- "one letter then one-or-more letters" = 2+ letters total.
    if not email:match('^[%w%._%+%-]+@[%w%-%.]+%.[%a][%a]+$') then
        return false, 'Enter a valid email address.'
    end
    return true, email
end

-- Validate a password against shared bounds. Returns ok, errorMessage.
function Identity.validatePassword(password, confirm)
    if type(password) ~= 'string' or #password < Config.Password.min then
        return false, ('Password must be at least %d characters.'):format(Config.Password.min)
    end
    if #password > Config.Password.max then
        return false, 'Password is too long.'
    end
    if confirm ~= nil and password ~= confirm then
        return false, 'Passwords do not match.'
    end
    return true
end

-- ---- Server-only Authenticated Session store --------------------------------
local AuthSessions = {}

function Identity.setSession(src, session)
    src = tonumber(src)
    if not src or src <= 0 then return end
    AuthSessions[src] = session
end

function Identity.clearSession(src)
    src = tonumber(src)
    if not src or src <= 0 then return end
    AuthSessions[src] = nil
end

function Identity.getSession(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    return AuthSessions[src]
end

function Identity.isLoggedIn(src)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    local session = AuthSessions[src]
    return session ~= nil and session.authenticated == true
end

function Identity.getAccountId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local session = AuthSessions[src]
    if session and session.authenticated == true and session.accountId then
        return tostring(session.accountId)
    end
    return nil
end

_G.CMAuthIdentity = Identity
return Identity
