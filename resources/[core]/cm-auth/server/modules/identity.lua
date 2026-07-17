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

-- ---- Session state ----------------------------------------------------------

function Identity.isLoggedIn(src)
    if not src or src == 0 then return false end
    local ok, value = pcall(function() return Player(src).state.isLoggedIn == true end)
    return ok and value == true
end

function Identity.getAccountId(src)
    if not src or src == 0 then return nil end
    local ok, value = pcall(function() return Player(src).state.accountId end)
    if ok and value then return tostring(value) end
    return nil
end

_G.CMAuthIdentity = Identity
return Identity
