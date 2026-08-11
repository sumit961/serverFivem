Config = {}

Config.Key = 38 -- E
Config.PromptDistance = 10.0
Config.InteractDistance = 2.5
Config.AccessDistance = 3.0

Config.PedModel = 's_m_m_doctor_01'
Config.Scenario = 'WORLD_HUMAN_CLIPBOARD'

Config.HospitalBlips = {
    enabled = true,
    sprite = 61,
    colour = 3,
    scale = 0.82,
    shortRange = true,
}

-- Must match cm-playerdata's Config.Vitals.MaxHealth (server/main.lua Heal/
-- SetHealth exports use this same 0-200 native health scale).
Config.MaxHealth = 200

Config.Doctors = {
    {
        id = 'sandy_shores',
        name = 'Dr. Hayes',
        hospitalId = 'sandy_shores',
        coords = vector4(1821.4374, 3686.1863, 34.8925, 209.4785),
    },
    {
        id = 'pillbox_upper',
        name = 'Dr. Okafor',
        hospitalId = 'pillbox',
        coords = vector4(310.5745, -585.7300, 43.2676, 71.1961),
    },
    {
        id = 'pillbox_entrance',
        name = 'Dr. Bennett',
        hospitalId = 'pillbox',
        coords = vector4(350.2381, -588.6317, 28.8474, 252.6511),
    },
    {
        id = 'pillbox_supply_doctor',
        name = 'Dr. Morgan',
        hospitalId = 'pillbox',
        coords = vector4(301.5257, -579.6008, 28.8474, 279.7823),
        services = {
            treatment = false,
            pharmacy = false,
            medicineRun = true,
        },
    },
}

-- Every coordinate below is a real post-death spawn/bed supplied in-game.
-- Occupancy is authoritative on the server, and the nearest hospital is used.
Config.Hospitals = {
    pillbox = {
        label = 'Pillbox Hill Medical Center',
        treatmentCenter = vector3(330.0, -585.0, 43.27),
        treatmentRadius = 75.0,
        beds = {
            { id = 'PB-01', coords = vector4(316.9794, -583.0529, 43.2677, 269.6746) },
            { id = 'PB-02', coords = vector4(328.6644, -587.0997, 43.2676, 67.5935) },
            { id = 'PB-03', coords = vector4(354.9866, -594.3669, 43.2676, 127.2216) },
            { id = 'PB-04', coords = vector4(356.5632, -585.9722, 43.2676, 298.0485) },
            { id = 'PB-05', coords = vector4(360.5836, -580.4874, 43.2676, 58.5215) },
            { id = 'PB-06', coords = vector4(344.4613, -591.2683, 43.2676, 246.0411) },
        },
        -- EMS operational points. Change only these four coordinates if your
        -- Pillbox interior has different locker/garage/helipad placements.
        storage = vector3(306.36, -601.34, 43.28),
        wardrobe = vector3(300.42, -597.21, 43.28),
        garage = vector3(294.68, -600.68, 43.31),
        helipad = vector3(338.74, -583.89, 74.16),
    },
    sandy_shores = {
        label = 'Sandy Shores Medical Center',
        treatmentCenter = vector3(1847.0, 3699.0, 34.89),
        treatmentRadius = 45.0,
        beds = {
            { id = 'SS-01', coords = vector4(1841.9744, 3699.0725, 34.8924, 201.8588) },
            { id = 'SS-02', coords = vector4(1846.3287, 3700.9285, 34.8924, 204.4538) },
            { id = 'SS-03', coords = vector4(1850.4952, 3703.9087, 34.8924, 177.1764) },
            { id = 'SS-04', coords = vector4(1855.6122, 3702.3831, 34.8925, 63.0708) },
            { id = 'SS-05', coords = vector4(1849.9167, 3697.7371, 34.8925, 52.9699) },
        },
        storage = vector3(1837.69, 3690.65, 34.27),
        wardrobe = vector3(1826.57, 3691.15, 34.22),
        garage = vector3(1837.82, 3678.05, 33.77),
        helipad = vector3(1770.84, 3239.83, 42.13),
    },
}

Config.Hospital = {
    deathRespawnPrice = 500,
    bedReservationMs = 90000,
    dischargeDistance = 5.0,
    treatmentBedReleaseMs = 45000,
    storageSlots = 30,
}

Config.Treatment = {
    label = 'Check in for treatment',
    price = 250,
    account = 'cash',
    durationMs = 30000,
    steps = 15,
}

Config.Medkit = {
    item = 'medikit',
    label = 'Medikit',
    price = 150,
    maxQuantity = 10,
    description = 'Fully heals you, or fully heals/revives a nearby player.',
}

Config.Medicines = {
    { item = 'bandage', label = 'Bandage', price = 25, maxQuantity = 20, description = 'Restores 20 health. 20-second cooldown.' },
    { item = 'painkillers', label = 'Painkillers', price = 40, maxQuantity = 20, description = 'Restores 10 health. 60-second cooldown.' },
    { item = 'antibiotics', label = 'Antibiotics', price = 60, maxQuantity = 20, description = 'Supports recovery and restores 25 health. 3-minute cooldown.' },
    { item = 'adrenaline_shot', label = 'Adrenaline Shot', price = 120, maxQuantity = 10, description = 'Restores 40 health. 2-minute cooldown.' },
}

-- Health-only medicine system. All changes are server authoritative.
Config.MedicineEffects = {
    bandage = { heal = 20, cooldownSeconds = 20 },
    painkillers = { heal = 10, cooldownSeconds = 60 },
    antibiotics = { heal = 25, cooldownSeconds = 180 },
    adrenaline_shot = { heal = 40, cooldownSeconds = 120 },
    medikit = { cooldownSeconds = 90 },
    medkit = { cooldownSeconds = 90 },
}
