-- cm-crime configuration. cm-crime is shared INFRASTRUCTURE: it never creates money, items or XP, owns no inventory, evidence,
-- dispatch, police roster or physical gameplay. Crime content resources register an activity here and consume sessions.
CMCrime = CMCrime or {}
local C = {}
CMCrime.Config = C

-- Resources allowed to REGISTER crime activities (GetInvokingResource allowlist). Fail closed: empty means nobody can register.
-- Add the exact resource name of a crime content resource (e.g. 'cm-store-robbery') when it is built and reviewed.
C.TrustedOwners = {
}

-- Bounds applied to every registered definition (a content resource cannot exceed them).
C.Limits = {
    sessionSeconds = { 60, 7200 },
    maxParticipants = 8,
    maxPolice = 32,
    maxCooldownSeconds = 30 * 24 * 3600,
    maxMetadataBytes = 1000,
    maxDispatchesPerSession = 5,
    maxStages = 16,
}

-- Defaults for fields a definition omits. Individual activities define their real numbers (economy/gameplay context decides them).
C.Defaults = {
    category = 'general',
    minPolice = 0,
    policeOrg = 'police',
    participants = { min = 1, max = 1 },
    allowJoin = false,                 -- may characters join after the session was created
    sessionSeconds = 900,
    siteMode = 'exclusive',            -- 'exclusive' = one active session per site key | 'none' = no site lock
    busyGroup = 'high_value',          -- one active session per character PER GROUP (different groups may coexist)
    cooldowns = { site = 0, activity = 0, character = 0, onFailure = 'full', partialFactor = 0.5 },  -- seconds; onFailure: full | partial | none
    dispatch = { mode = 'none', once = true, priority = 2, chance = 1.0, delaySeconds = 0, types = {} },
    strictOrder = false,
    reward = { enabled = true },
    policy = { onInitiatorLeave = 'continue', disconnectGraceSeconds = 120, onOwnerStop = 'fail', ownerStopGraceSeconds = 120 },
}

C.Police = { org = 'police', cacheSeconds = 5 }
C.Dispatch = { retryBaseSeconds = 30, maxAttempts = 5 }
C.Reward = { pendingSeconds = 900 }    -- a delivered-confirmation that never arrives flags the reward for reconciliation after this
C.SweepSeconds = 10
C.RateLimits = { begin = { 6, 60 }, join = { 12, 60 } }   -- { max, windowSeconds } per owner+character
C.AdminCallers = { ['cm-admin'] = true }
C.SelfTest = { convar = 'cm_environment', value = 'development' }
