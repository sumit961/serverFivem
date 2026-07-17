-- cm-auth/shared/config.lua
-- All tunable constants live here so behavior can be adjusted without touching logic.
-- Loaded on both server and client (see fxmanifest shared_scripts).

Config = Config or {}

-- Master debug switch. Leave false in production; gates verbose prints only.
Config.Debug = false

-- Rate limiting (per-player, in-memory cooldowns between attempts, milliseconds).
Config.Cooldowns = {
    login    = 1500,
    register = 3000,
    reset    = 3000,
    token    = 1500,
}

-- Lockout policy (database-backed, survives reconnects).
Config.Lockout = {
    failedWindowMinutes   = 15,   -- window over which failed logins are counted
    failedLimit           = 5,    -- failures within the window that triggers a lockout
    lockoutMinutes        = 30,   -- how long a lockout lasts
    registerWindowMinutes = 60,   -- window over which registrations are counted
    registerLimit         = 3,    -- registrations within the window before lockout
}

-- Trusted-device token settings.
Config.Token = {
    maxAgeDays = 30,  -- saved logins older than this force a fresh password login
    length     = 48,  -- raw token length (stored hashed at rest)
}

-- Local password-hash fallback (only used when the FXServer native is unavailable).
-- NOTE: the FXServer native GetPasswordHash/VerifyPasswordHash (bcrypt) is strongly
-- preferred. This SHA-256 fallback exists only so the server still functions on
-- builds without the native; it is weaker and logs a loud warning when used.
Config.LocalHash = {
    prefix = 'CM1$',
    rounds = 1500,
}

-- KVP keys used client-side to persist the trusted-device token.
Config.Kvp = {
    token = 'cm_auth_token',
    email = 'cm_auth_email',
}

-- Character alphabet for token / username suffix generation.
Config.TokenChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

-- Password bounds shared by register/reset validation.
Config.Password = {
    min = 6,
    max = 72,   -- bcrypt hard limit; keep in sync with the native
}
