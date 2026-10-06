-- cm-lumber/shared/config.lua
-- Paleto Forest Timber Harvesting & Sawmill Processing Configuration.

CMLumber = CMLumber or {}
CMLumber.Config = {}

local Config = CMLumber.Config

-- Debug logging toggle
Config.Debug = false

-- Foreman & Operations Base (Paleto Forest Sawmill Office Deck)
Config.Foreman = {
    model = `s_m_y_construct_02`,
    coords = vector4(-553.85, 5325.64, 73.60, 245.0),
    pedName = 'Gunnar Lindholm',
    role = 'PALETO SAWMILL FOREMAN',
    blip = {
        sprite = 77, -- Forestry / Tree icon
        color = 3,   -- Cyan / ice-blue (CM brand identity)
        scale = 0.85,
        label = 'Paleto Forest Sawmill',
    },
    dialogueQuote = 'Paleto Forest supplies raw timber for regional construction. Clock in, fell marked timber stands, and haul your logs to the mill deck.',
}

-- Industrial Sawmill Processing Station (Conveyor & Table Saw Deck)
Config.Sawmill = {
    id = 'paleto_sawmill_1',
    coords = vector3(-585.80, 5293.40, 70.25),
    radius = 3.5,
    label = 'Paleto Industrial Sawmill',
}

-- Logging Nodes (Marked Timber Stands around Paleto Forest Access Trails)
Config.LoggingNodes = {
    { id = 1, coords = vector3(-597.20, 5361.50, 70.40), radius = 2.5, label = 'Timber Stand Alpha' },
    { id = 2, coords = vector3(-614.80, 5349.30, 73.80), radius = 2.5, label = 'Timber Stand Bravo' },
    { id = 3, coords = vector3(-636.50, 5334.20, 76.50), radius = 2.5, label = 'Timber Stand Charlie' },
    { id = 4, coords = vector3(-621.10, 5312.40, 76.10), radius = 2.5, label = 'Timber Stand Delta' },
    { id = 5, coords = vector3(-603.40, 5275.60, 72.80), radius = 2.5, label = 'Timber Stand Echo' },
    { id = 6, coords = vector3(-568.20, 5262.10, 71.00), radius = 2.5, label = 'Timber Stand Foxtrot' },
    { id = 7, coords = vector3(-540.70, 5283.50, 73.40), radius = 2.5, label = 'Timber Stand Golf' },
    { id = 8, coords = vector3(-524.30, 5314.80, 77.20), radius = 2.5, label = 'Timber Stand Hotel' },
}

-- Harvesting / Felling Timings & Yield
-- Quantity ceiling anchor: <= 80 logs/hour initial operational baseline (cm-materials ceiling: 166 logs/h)
Config.Harvesting = {
    durationMs = 9000,        -- 9 seconds physical felling action
    minDurationMs = 8000,     -- Anti-speedhack server enforcement threshold
    nodeCooldownMs = 60000,   -- 60 seconds per-stand server cooldown
    logYieldPerNode = 2,      -- Yields 2x raw log per tree stand
    maxHaulLogCapacity = 20,  -- Maximum raw logs worker can haul per run
    hatchetProp = `prop_w_me_hatchet`,
    animDict = 'melee@hatchet@streamed_core',
    animName = 'ground_attack_0',
}

-- Sawmill Processing Parameters
-- Recipe Authority: cm-crafting owns recipe 'materials:saw_timber'.
-- Status: cm-lumber is NOT currently in CMCrafting.Config.TrustedOwners.
-- Per architectural rules, conversion MUST NOT be reproduced locally.
-- Sawing conversion is disabled fail-closed; raw logs are held in ledger.
Config.Processing = {
    recipeId = 'materials:saw_timber',
    conversionEnabled = false, -- Disabled: requires cm-crafting trusted owner authorization
    statusNotice = 'Sawmill conversion is held: recipe execution requires cm-crafting trusted-owner authorization. Raw logs remain safely stored.',
    durationMs = 10000,
    minDurationMs = 9000,
    inputItem = 'log',
    inputAmount = 2,
    outputItem = 'timber',
    outputAmount = 3,
    animDict = 'amb@prop_human_bum_bin@idle_b',
    animName = 'idle_d',
}

-- Authoritative Item IDs (strictly referenced from cm-items)
-- Note: Catalog reference values are NOT cash prices or approved rewards.
-- Value calculations are excluded; manifests track pure physical quantities and status.
Config.Items = {
    rawLog = {
        id = 'log',
        label = 'Log',
    },
    processedTimber = {
        id = 'timber',
        label = 'Timber',
    },
}

-- Custody & Settlement Guardrails (Fail-Closed Enforcement)
Config.Custody = {
    materialsInventoryEnabled = false, -- Held fail-closed until downstream consumer (cm-construction) is active
    payrollEnabled = false,            -- Held fail-closed until cm-payday supports idempotent wage settlement
    sawmillConversionEnabled = false,  -- Held fail-closed until cm-crafting authorizes cm-lumber
    holdingNotice = 'Raw logs and shift manifests are securely held in the sawmill database ledger. Sawmill conversion is held pending cm-crafting trusted-owner authorization, and inventory custody/payroll remain held pending downstream sink and idempotent settlement integration.',
}

