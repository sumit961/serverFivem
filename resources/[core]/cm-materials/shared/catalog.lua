-- cm-materials: the authoritative V1 material catalog. DATA ONLY. Item identity/weight/stack live in cm-items; custody in cm-inventory;
-- recipes run in cm-crafting. This file adds only economic metadata (stage, category, reference value, sources, sinks, processing).
-- Full specification and rules: agent-docs/CM_MATERIAL_ECONOMY.md. Never repurpose or silently rename an item id once players can own it.
CMMaterials = CMMaterials or {}

CMMaterials.Version = 1

CMMaterials.Economy = {
    -- City Support 150,000 / 4 eligible hours (CM_ECONOMY_STANDARD.md)
    supportPerHour = 37500,
    activeWorkHour = 87500,                          -- 37.5k support + ~50k beginner job activity
    gatheringActivityBandPerHour = { 50000, 62500 }, -- beginner legal activity component
    -- A gathering job may pay at most this share of the LOWER band edge as material reference value; the rest is cash/XP.
    maxMaterialShareOfActivity = 0.40,
    processing = {
        timeValuePerSecond = 5,                      -- semi-passive wait; ~18k/h, about 20% of an active-work hour
        inputPremium = 0.10,                         -- allowance on top of input value for handling/loss compensation
        maxValueCreatedPerHour = 17500,              -- 20% of an active-work hour, per recipe running back-to-back
    },
    directSaleMaxShareOfReference = 0.50,            -- if a material is ever sold to an NPC it must pay at most half its reference value
}

CMMaterials.Stages = { raw = true, processed = true, component = true }
CMMaterials.Categories = { mineral = true, wood = true, reclaimed = true }
CMMaterials.Tags = { raw = true, processed = true, component = true, mineral = true, wood = true, reclaimed = true, construction = true, mechanic = true, industrial = true }
-- ACTIVE needs every listed source AND sink to be active. Nothing may be ACTIVE until its owner is integrated.
CMMaterials.Statuses = { ACTIVE = true, DEFINED_NOT_SOURCED = true, DEFINED_NOT_CONSUMED = true, DEFERRED = true }
CMMaterials.LinkStatuses = { active = true, integration_required = true, deferred = true, disabled = true }
-- Station types processing recipes need. The OWNER of the physical site registers the station with cm-crafting (shared = true if the
-- recipe owner differs). Site/coords belong to the world-owner resource, never to this catalog.
CMMaterials.StationTypes = {
    furnace = { suggestedOwner = 'cm-mining' },
    sawmill = { suggestedOwner = 'cm-lumber' },
    recycling_processor = { suggestedOwner = 'cm-recycling' },
}

-- refValue: whole-dollar BALANCE ANCHOR, not a price. directSale = false means no NPC may buy it for cash (no universal sell NPC).
-- Weights/stack are NOT here (cm-items). `sources`/`sinks` entries point at the owner resource that must integrate them.
CMMaterials.Items = {
    iron_ore = {
        stage = 'raw', category = 'mineral', tags = { 'raw', 'mineral', 'industrial' }, refValue = 100, directSale = false,
        sources = { { owner = 'cm-mining', status = 'integration_required', note = 'cm-mining is an empty scaffold today (all files 0 bytes, not ensured)' } },
        sinks = { { kind = 'process', recipe = 'materials:smelt_iron', status = 'integration_required', station = 'furnace' } },
        status = 'DEFINED_NOT_SOURCED',
    },
    iron_ingot = {
        stage = 'processed', category = 'mineral', tags = { 'processed', 'mineral', 'construction', 'industrial' }, refValue = 350, directSale = false,
        sources = { { kind = 'process', recipe = 'materials:smelt_iron', status = 'integration_required', station = 'furnace' } },
        sinks = {
            { kind = 'external', owner = 'cm-construction', status = 'integration_required', contract = 'ConsumeMaterial (structural steel for build tasks); cm-construction is an empty scaffold' },
            { kind = 'external', owner = 'cm-mechanic', status = 'deferred', contract = 'mechanic parts supply; cm-mechanic prices repairs in cash and has no parts/storage system' },
        },
        status = 'DEFINED_NOT_SOURCED',
    },
    log = {
        stage = 'raw', category = 'wood', tags = { 'raw', 'wood', 'industrial' }, refValue = 120, directSale = false,
        sources = { { owner = 'cm-lumber', status = 'integration_required', note = 'cm-lumber is an empty scaffold today (all files 0 bytes, not ensured)' } },
        sinks = { { kind = 'process', recipe = 'materials:saw_timber', status = 'integration_required', station = 'sawmill' } },
        status = 'DEFINED_NOT_SOURCED',
    },
    timber = {
        stage = 'processed', category = 'wood', tags = { 'processed', 'wood', 'construction' }, refValue = 90, directSale = false,
        sources = { { kind = 'process', recipe = 'materials:saw_timber', status = 'integration_required', station = 'sawmill' } },
        sinks = { { kind = 'external', owner = 'cm-construction', status = 'integration_required', contract = 'ConsumeMaterial (framing/scaffold timber); cm-construction is an empty scaffold' } },
        status = 'DEFINED_NOT_SOURCED',
    },
    metal_scrap = {   -- EXISTING cm-items item, reused (cm-recycling already references it)
        stage = 'raw', category = 'reclaimed', tags = { 'raw', 'reclaimed', 'industrial' }, refValue = 40, directSale = false,
        sources = { { owner = 'cm-recycling', status = 'integration_required', note = 'Config.Earnings.materialsEnabled = false by design until this catalog exists' } },
        sinks = { { kind = 'process', recipe = 'materials:reclaim_metal', status = 'integration_required', station = 'recycling_processor' } },
        status = 'DEFINED_NOT_SOURCED',
    },
    reclaimed_metal = {
        stage = 'processed', category = 'reclaimed', tags = { 'processed', 'reclaimed', 'construction', 'mechanic' }, refValue = 180, directSale = false,
        sources = { { kind = 'process', recipe = 'materials:reclaim_metal', status = 'integration_required', station = 'recycling_processor' } },
        sinks = {
            { kind = 'external', owner = 'cm-construction', status = 'integration_required', contract = 'ConsumeMaterial (fixtures/fasteners); cm-construction is an empty scaffold' },
            { kind = 'external', owner = 'cm-mechanic', status = 'deferred', contract = 'mechanic parts supply; no parts system exists' },
        },
        status = 'DEFINED_NOT_SOURCED',
    },
    plastic = {       -- EXISTING cm-items item. DEFERRED: it has no sink, so recycling must NOT grant it yet.
        stage = 'raw', category = 'reclaimed', tags = { 'raw', 'reclaimed' }, refValue = 25, directSale = false,
        sources = { { owner = 'cm-recycling', status = 'deferred', note = 'listed in cm-recycling Config.Earnings.materials; keep materialsEnabled=false or drop plastic from the grant list' } },
        sinks = { { kind = 'external', owner = 'cm-mechanic', status = 'deferred', contract = 'plastic components need a mechanic/fabrication consumer that does not exist; add one before enabling' } },
        status = 'DEFERRED',
    },
}

-- Processing recipes: shaped exactly like cm-crafting RegisterCraftRecipe definitions, plus `enabled`.
-- ids use the namespace `materials:`. These are PRODUCTION definitions (cm-crafting's test recipes live only in its tests).
CMMaterials.Recipes = {
    {
        id = 'materials:smelt_iron', label = 'Smelt Iron Ingot', category = 'smelting', durationSeconds = 15, batch = { min = 1, max = 10 },
        stations = { 'furnace' }, handcraft = false, enabled = true,
        inputs = { { item = 'iron_ore', amount = 3 } }, outputs = { { item = 'iron_ingot', amount = 1 } },
    },
    {
        id = 'materials:saw_timber', label = 'Saw Timber', category = 'sawmill', durationSeconds = 10, batch = { min = 1, max = 10 },
        stations = { 'sawmill' }, handcraft = false, enabled = true,
        inputs = { { item = 'log', amount = 2 } }, outputs = { { item = 'timber', amount = 3 } },
    },
    {
        id = 'materials:reclaim_metal', label = 'Reclaim Metal', category = 'reclaiming', durationSeconds = 12, batch = { min = 1, max = 10 },
        stations = { 'recycling_processor' }, handcraft = false, enabled = true,
        inputs = { { item = 'metal_scrap', amount = 4 } }, outputs = { { item = 'reclaimed_metal', amount = 1 } },
    },
}
