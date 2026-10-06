-- cm-mining/shared/config.lua
-- Davis Quartz Mining & Industrial Mineral Extraction Configuration.

CMMining = CMMining or {}
CMMining.Config = {}

local Config = CMMining.Config

-- Debug logging toggle
Config.Debug = false

-- Foreman & Operations Base (Davis Quartz Quarry Office)
Config.Foreman = {
    model = `s_m_y_construct_01`,
    coords = vector4(2953.50, 2789.00, 41.50, 118.0),
    pedName = 'Hal Vance',
    role = 'DAVIS QUARTZ FOREMAN',
    blip = {
        sprite = 318, -- Mining pickaxe icon
        color = 3,    -- Cyan / light blue
        scale = 0.85,
        label = 'Davis Quartz Quarry',
    },
    dialogueQuote = 'Davis Quartz is the industrial backbone of San Andreas. Clock in, grab your gear, and keep your hard hat strapped tight.',
}

-- Industrial Smelting Furnace (Near quarry modular plant)
Config.Furnace = {
    coords = vector3(2976.20, 2796.80, 41.50),
    radius = 3.5,
    label = 'Industrial Smelting Furnace',
}

-- Extraction Veins (Pit rock nodes located across Davis Quartz quarry bed)
Config.ExtractionNodes = {
    { id = 1, coords = vector3(2968.20, 2779.80, 39.20), radius = 2.5, label = 'Mineral Vein Alpha' },
    { id = 2, coords = vector3(2975.50, 2768.40, 39.50), radius = 2.5, label = 'Mineral Vein Bravo' },
    { id = 3, coords = vector3(2954.10, 2761.30, 39.80), radius = 2.5, label = 'Mineral Vein Charlie' },
    { id = 4, coords = vector3(2937.80, 2772.60, 39.40), radius = 2.5, label = 'Mineral Vein Delta' },
    { id = 5, coords = vector3(2925.30, 2788.10, 39.90), radius = 2.5, label = 'Mineral Vein Echo' },
    { id = 6, coords = vector3(2942.00, 2805.50, 41.20), radius = 2.5, label = 'Mineral Vein Foxtrot' },
}

-- Extraction Timings & Yield
Config.Extraction = {
    durationMs = 8000,        -- 8 seconds physical mining action
    minDurationMs = 7000,     -- Anti-speedhack server enforcement threshold
    nodeCooldownMs = 60000,   -- 60 seconds per-node server cooldown
    oreYieldPerNode = 3,      -- Yields 3x iron_ore per successful extraction
    maxCartOreCapacity = 30,  -- Maximum raw ore carried in worker cart per shift batch
    pickaxeProp = `prop_tool_pickaxe`,
    animDict = 'melee@large_wpn@streamed_core',
    animName = 'ground_attack_0',
}

-- Smelting Parameters (Authoritative match to cm-materials recipe 'materials:smelt_iron')
-- Recipe contract: 3 iron_ore -> 1 iron_ingot (15 seconds at furnace)
Config.Smelting = {
    recipeId = 'materials:smelt_iron',
    durationMs = 15000,       -- 15 seconds processing duration
    minDurationMs = 14000,    -- Anti-speedhack server enforcement threshold
    inputItem = 'iron_ore',
    inputAmount = 3,
    outputItem = 'iron_ingot',
    outputAmount = 1,
    animDict = 'amb@world_human_welding@male@base',
    animName = 'base',
}

-- Authoritative Economic & Material Anchors (strictly referenced from cm-materials & cm-items)
Config.Items = {
    rawOre = {
        id = 'iron_ore',
        label = 'Iron Ore',
        refValue = 100, -- Authoritative refValue from cm-materials/shared/catalog.lua
    },
    processedIngot = {
        id = 'iron_ingot',
        label = 'Iron Ingot',
        refValue = 350, -- Authoritative refValue from cm-materials/shared/catalog.lua
    },
}

-- Custody & Settlement Guardrails (Fail-Closed Enforcement)
--
-- 1. Downstream Material Sink Status:
--    cm-materials catalog reports iron_ingot sinks are cm-construction (empty scaffold)
--    and cm-mechanic (deferred). No live verified sink exists to consume iron_ingot.
--    Transferring loose items into player inventory would create untracked, un-sinkable economic bloat.
--
-- 2. Payroll Settlement Status:
--    cm-payday has no 'mining' entry in CMPayday.Config.Jobs, and AddPendingCash is non-idempotent.
--    Direct wage payments are blocked from automated execution to prevent unrecoverable balance duplication.
Config.Custody = {
    materialsInventoryEnabled = false, -- Held fail-closed until downstream consumer (cm-construction) is active
    payrollEnabled = false,            -- Held fail-closed until cm-payday supports idempotent wage settlement
    holdingNotice = 'Material inventory custody and wage payroll remain held in the quarry ledger pending downstream sink integration and idempotent settlement.',
}

