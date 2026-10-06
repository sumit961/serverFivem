-- cm-trade/config.lua
-- Direct nearby player-to-player trading (cash + inventory items). Economy neutral: no fee, payout, XP or reward.
Config = {}

Config.PlayerData = 'cm-playerdata'
Config.Inventory = 'cm-inventory'

Config.Invite = {
    ExpirySeconds = 45,
    MaxDistance = 3.0,       -- inviter <-> target when the invite is sent AND when it is accepted
}

Config.Session = {
    MaxDistance = 3.0,       -- required at final settlement
    CancelDistance = 6.0,    -- an open session is cancelled when participants drift further apart than this
    CheckIntervalMs = 1000,
    MaxMinutes = 10,         -- hard lifetime of any session
    CancelOnDeath = true,
}

Config.Limits = {
    MaxCash = 1000000,       -- per side, per trade (wallet cash only; bank balance is never tradeable)
    MaxItemLines = 8,        -- per side
    MaxQuantityPerLine = 100,
}

Config.RateLimits = {        -- { max, windowSeconds } per character
    invite  = { 5, 60 },
    offer   = { 40, 10 },
    confirm = { 12, 10 },
    cancel  = { 8, 30 },
    inventory = { 10, 10 },
}

Config.Money = { Account = 'cash' }

-- Items are settled by a trusted cm-inventory exchange contract (see docs/SHARED_INTEGRATION.md).
-- 'auto' = enabled only when cm-inventory exposes the contract; false = cash-only; true = require it (fails closed).
Config.Items = {
    Enabled = 'auto',
    -- Defense in depth on top of the item definition's `tradeable` flag: these item names are never tradeable here.
    DenyPatterns = { '^weapon_', '^vehicle_?key', '^key_', '^id_card', '^license', '^admin_', '^dev_', '^test_' },
}

Config.Reconcile = { IntervalSeconds = 30, StaleSeconds = 20 }
Config.SelfTest = { convar = 'cm_environment', value = 'development' }
