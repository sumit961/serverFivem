-- cm-crafting configuration. cm-crafting orchestrates ITEM INPUT -> ITEM OUTPUT sessions. It owns no items, inventory, money, jobs,
-- businesses or physical gameplay. Item custody and the atomic settlement belong to cm-inventory; item definitions to cm-items.
CMCrafting = CMCrafting or {}
local C = {}
CMCrafting.Config = C

-- Resources allowed to REGISTER recipes/stations and to run crafts (GetInvokingResource allowlist). Ships empty = fail closed.
-- Add the exact resource name of a reviewed content resource (e.g. a future mining/lumber/mechanic-parts resource).
C.TrustedOwners = {
}

-- LIVE item settlement uses the cm-inventory contract in docs/README.md (ValidateCraftTransaction / ExecuteCraftTransaction /
-- GetCraftTransactionStatus, implemented in cm-inventory server/craft.lua). While those owner exports are unavailable every BeginCraft
-- fails with 'settlement_unavailable'. There is deliberately NO RemoveItem + AddItem fallback.
C.RequireAtomicInventory = true

C.Limits = {
    maxBatch = 50,
    maxAmount = 1000,              -- per input/output line, per unit
    maxTotalAmount = 20000,        -- per line after multiplying by quantity (overflow guard)
    maxInputs = 8, maxOutputs = 4, maxTools = 4,
    secondsPerUnit = { 1, 3600 },
    maxTotalSeconds = 7200,
    maxMetadataBytes = 500,
    maxDurabilityUse = 100,
    speedModifier = { 0.5, 2.0 },  -- trusted owner modifier, clamped; total duration is never below 1 s
}

C.Session = {
    graceAfterReadySeconds = 600,  -- an uncommitted session expires this long after it became ready
    disconnectGraceSeconds = 60,   -- an offline crafter fails the session (no offline outputs)
    ownerStopGraceSeconds = 120,
    maxCommitAttempts = 5,
    commitRetryBaseSeconds = 15,
    reconcileFlagSeconds = 900,    -- committing + unknown inventory status this long -> audit alert (never re-applied by guessing)
}

C.RateLimits = { begin = { 6, 30 }, cancel = { 10, 30 }, complete = { 12, 30 } }   -- { max, windowSeconds } per owner+character
C.SweepSeconds = 5
C.AdminCallers = { ['cm-admin'] = true }
C.SelfTest = { convar = 'cm_environment', value = 'development' }
