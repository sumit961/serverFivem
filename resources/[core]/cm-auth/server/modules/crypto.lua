-- cm-auth/server/modules/crypto.lua
-- Password hashing + verification and secure-ish token generation.
--
-- Strategy: ALWAYS prefer the FXServer native bcrypt (GetPasswordHash /
-- VerifyPasswordHash). The local CM1 salted-SHA-256 path is a last-resort
-- fallback for builds without the native and is intentionally flagged as weaker.

local Util = _G.CMAuthUtil
local Crypto = {}

local TOKEN_CHARS   = Config.TokenChars
local LOCAL_PREFIX  = Config.LocalHash.prefix
local LOCAL_ROUNDS  = Config.LocalHash.rounds

-- ---- RNG (not a true CSPRNG; reseeded from changing sources per credential) --

math.randomseed(os.time() + GetGameTimer())

local function reseedRandom()
    local micro = math.floor((os.clock() * 1000000) % 1000000)
    local seed = ((os.time() % 100000) * 1000000) + micro + (GetGameTimer() % 1000000)
    math.randomseed(seed)
    for _ = 1, 7 do math.random() end
end

local function randomString(length)
    local out = {}
    for i = 1, length do
        local idx = math.random(1, #TOKEN_CHARS)
        out[#out + 1] = TOKEN_CHARS:sub(idx, idx)
    end
    return table.concat(out)
end

Crypto.randomString = randomString

function Crypto.generateAuthToken()
    reseedRandom()
    return randomString(Config.Token.length)
end

-- Username = sanitized email local-part + random suffix. Collisions are avoided
-- at the DB layer by the unique index; the suffix just reduces churn.
function Crypto.makeUsernameFromEmail(email)
    local base = tostring(email or ''):match('^([^@]+)') or 'player'
    base = base:lower():gsub('[^a-z0-9_%.%-]', '')
    if #base < 3 then base = 'player' end
    if #base > 14 then base = base:sub(1, 14) end
    return ('%s_%s'):format(base, randomString(6):lower())
end

-- ---- SHA-256 (pure Lua, used only by the local fallback hash) ---------------

local function bxor(a, b) return (a ~ b) & 0xffffffff end
local function rrotate(x, n) return ((x >> n) | (x << (32 - n))) & 0xffffffff end

local K = {
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
    while (#bytes % 64) ~= 56 do bytes[#bytes + 1] = 0 end
    for _ = 1, 4 do bytes[#bytes + 1] = 0 end       -- high 32 bits always 0 here
    for shift = 24, 0, -8 do bytes[#bytes + 1] = (bitLen >> shift) & 0xff end

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
            local t1 = (h + S1 + ch + K[i + 1] + w[i]) & 0xffffffff
            local S0 = bxor(bxor(rrotate(a, 2), rrotate(a, 13)), rrotate(a, 22))
            local maj = bxor(bxor((a & b), (a & c)), (b & c))
            local t2 = (S0 + maj) & 0xffffffff
            h = g; g = f; f = e; e = (d + t1) & 0xffffffff
            d = c; c = b; b = a; a = (t1 + t2) & 0xffffffff
        end

        h0 = (h0 + a) & 0xffffffff; h1 = (h1 + b) & 0xffffffff
        h2 = (h2 + c) & 0xffffffff; h3 = (h3 + d) & 0xffffffff
        h4 = (h4 + e) & 0xffffffff; h5 = (h5 + f) & 0xffffffff
        h6 = (h6 + g) & 0xffffffff; h7 = (h7 + h) & 0xffffffff
    end

    return ('%08x%08x%08x%08x%08x%08x%08x%08x'):format(h0, h1, h2, h3, h4, h5, h6, h7)
end

-- Constant-time string compare to avoid leaking length/position via timing.
local function safeEquals(a, b)
    a = tostring(a or ''); b = tostring(b or '')
    if #a ~= #b then return false end
    local diff = 0
    for i = 1, #a do diff = diff | (a:byte(i) ~ b:byte(i)) end
    return diff == 0
end

-- ---- Local fallback hash (salted, iterated SHA-256) -------------------------

local function makeLocalHash(password, salt, rounds)
    rounds = tonumber(rounds) or LOCAL_ROUNDS
    local digest = sha256(tostring(salt) .. ':' .. tostring(password))
    for _ = 1, rounds do
        digest = sha256(digest .. ':' .. tostring(salt) .. ':' .. tostring(password))
    end
    return digest
end

local function createLocalHash(password)
    reseedRandom()
    local salt = randomString(24)
    return ('%s%d$%s$%s'):format(LOCAL_PREFIX, LOCAL_ROUNDS, salt, makeLocalHash(password, salt, LOCAL_ROUNDS))
end

local function verifyLocalHash(password, stored)
    local rounds, salt, digest = tostring(stored or ''):match('^CM1%$(%d+)%$([A-Za-z0-9]+)%$([a-fA-F0-9]+)$')
    if not rounds or not salt or not digest then return false end
    return safeEquals(makeLocalHash(password, salt, tonumber(rounds) or LOCAL_ROUNDS):lower(), digest:lower())
end

-- Legacy pre-existing djb2 hashes ('TEMP_...'); verified then transparently upgraded on login.
local function legacyTempHash(password)
    local h = 5381
    for i = 1, #password do h = ((h * 33) + string.byte(password, i)) % 2147483647 end
    return 'TEMP_' .. tostring(h)
end

-- ---- Native bcrypt (preferred) ----------------------------------------------

local function tryNativeHash(password)
    if type(GetPasswordHash) ~= 'function' then
        return false, 'FXServer GetPasswordHash native is not available on this build.'
    end
    local ok, result = pcall(function() return GetPasswordHash(password) end)
    if ok and type(result) == 'string' and result ~= '' then return true, result end
    return false, ok and 'GetPasswordHash returned an invalid hash.' or tostring(result)
end

local function tryNativeVerify(password, stored)
    if type(VerifyPasswordHash) ~= 'function' then
        return false, 'FXServer VerifyPasswordHash native is not available on this build.'
    end
    local ok, result = pcall(function() return VerifyPasswordHash(password, stored) end)
    if ok then return true, (result == true or result == 1) end
    return false, tostring(result)
end

-- ---- Public API -------------------------------------------------------------

-- Returns hash string, or nil + error. Prefers native bcrypt; warns on fallback.
function Crypto.hash(password)
    if type(password) ~= 'string' then return nil, 'Invalid password.' end
    local ok, result = tryNativeHash(password)
    if ok then return result end
    Util.log('cm-auth', 'warning', 'Native bcrypt unavailable; using weaker local SHA-256 fallback', { reason = result })
    return createLocalHash(password)
end

-- Returns verified(boolean), mode(string) where mode is one of
-- 'native' | 'cm-local' | 'legacy', or an error message on failure.
function Crypto.verify(password, stored)
    if type(password) ~= 'string' or type(stored) ~= 'string' or stored == '' then
        return false, 'Invalid credentials.'
    end
    if stored:sub(1, #LOCAL_PREFIX) == LOCAL_PREFIX then
        if verifyLocalHash(password, stored) then return true, 'cm-local' end
        return false, 'Wrong password. Try again.'
    end
    if stored:sub(1, 5) == 'TEMP_' then
        if legacyTempHash(password) == stored then return true, 'legacy' end
        return false, 'Wrong password. Try again.'
    end
    local ok, res = tryNativeVerify(password, stored)
    if ok then
        if res == true then return true, 'native' end
        return false, 'Wrong password. Try again.'
    end
    return false, 'Password verification unavailable for this old hash. Reset the password.'
end

_G.CMAuthCrypto = Crypto
return Crypto
