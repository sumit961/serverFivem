while not Config do Citizen.Wait(1) end

Config.Evidences = {
    ---@field enabled: boolean [master toggle for the evidence system]
    enabled = true,

    ---@field MaxWorldEvidences: number [max evidences kept world-wide (oldest removed first)]
    MaxWorldEvidences = 2000,

    ---@field MaxPerArea: number [max evidences kept within AreaRadius (oldest in that cell removed first)]
    MaxPerArea = 60,

    ---@field AreaRadius: number [radius (metres) used for the per-area evidence cap]
    AreaRadius = 50.0,

    ---@field StreamDistance: number [only evidences within this range (metres) are sent/rendered to a client]
    StreamDistance = 90.0,

    ---@field StreamInterval: number [interval (ms) between server->client stream refreshes]
    StreamInterval = 1500,

    ---@field RenderDistance: number [distance (metres) at which the 3D prop/glow becomes visible]
    RenderDistance = 25.0,

    ---@field InteractDistance: number [distance (metres) at which evidence can be collected]
    InteractDistance = 1.8,

    ---@field ReconstructionItem: string [item that reveals nearby evidence as non-collectable holograms]
    ReconstructionItem = 'evidence_reconstructor',

    ---@field ReconstructionRadius: number [reveal radius (metres) for the reconstruction tool]
    ReconstructionRadius = 30.0,

    ---@field ReconstructionDuration: number [how long (ms) the reconstruction reveal lasts]
    ReconstructionDuration = 25 * 1000,

    ---@field StorageStashPrefix: string [prefix used to build the long-term evidence storage stash id]
    StorageStashPrefix = 'p_policejob_evidence_storage',

    ---@field StorageStashSlots: number [slots in the evidence storage stash]
    StorageStashSlots = 200,

    ---@field StorageStashWeight: number [max weight (grams) of the evidence storage stash]
    StorageStashWeight = 500000,

    ---@field Types: table [evidence type definitions, keyed by type name]
    ---@field Types.entry: table [{ label: string, item: string, prop: string|nil, offset: vector3, rotation: vector3, scale: number, color: { r,g,b }, expire: number(seconds), requiredItems: { police: {item=count}, civilian: {item=count} } }]
    Types = {
        ['blood'] = {
            label  = locale('evidence_type_blood'),
            item   = 'evidence_blood',
            prop   = 'e_ch_b',
            offset = vector3(0.0, 0.0, -0.95),
            rotation = vector3(0.0, 0.0, 0.0),
            scale  = 1.0,
            color  = { r = 180, g = 30, b = 30 },
            expire = 60 * 60,
            requiredItems = {
                police   = { ['evidence_kit'] = 1, ['swab_kit'] = 1 },
                civilian = { ['cleaning_kit'] = 1 },
            },
        },
        ['bullet_casing'] = {
            label  = locale('evidence_type_bullet_casing'),
            item   = 'evidence_casing',
            prop   = 'e_ch_a',
            offset = vector3(0.0, 0.0, -0.97),
            rotation = vector3(0.0, 0.0, 0.0),
            scale  = 1.0,
            color  = { r = 220, g = 170, b = 60 },
            expire = 45 * 60,
            requiredItems = {
                police   = { ['evidence_kit'] = 1 },
                civilian = { ['broom'] = 1 },
            },
        },
        ['fingerprint'] = {
            label  = locale('evidence_type_fingerprint'),
            item   = 'evidence_fingerprint',
            prop   = nil,
            offset = vector3(0.0, 0.0, -0.95),
            rotation = vector3(0.0, 0.0, 0.0),
            scale  = 1.0,
            color  = { r = 80, g = 200, b = 230 },
            expire = 90 * 60,
            requiredItems = {
                police   = { ['evidence_kit'] = 1, ['fingerprint_kit'] = 1 },
                civilian = { ['cleaning_kit'] = 1 },
            },
        },
        ['drug_residue'] = {
            label  = locale('evidence_type_drug_residue'),
            item   = 'evidence_drug_residue',
            prop   = 'sf_prop_sf_bag_weed_open_01c',
            offset = vector3(0.0, 0.0, -0.95),
            rotation = vector3(0.0, 0.0, 0.0),
            scale  = 0.6,
            color  = { r = 180, g = 110, b = 220 },
            expire = 50 * 60,
            requiredItems = {
                police   = { ['evidence_kit'] = 1, ['swab_kit'] = 1 },
                civilian = { ['cleaning_kit'] = 1 },
            },
        },
        ['weapon_fragment'] = {
            label  = locale('evidence_type_weapon_fragment'),
            item   = 'evidence_fragment',
            prop   = 'e_ch_b',
            offset = vector3(0.0, 0.0, -0.95),
            rotation = vector3(0.0, 0.0, 0.0),
            scale  = 1.0,
            color  = { r = 230, g = 220, b = 100 },
            expire = 75 * 60,
            requiredItems = {
                police   = { ['evidence_kit'] = 1 },
                civilian = { ['cleaning_kit'] = 1 },
            },
        },
    },

    ---@field AutoCreate: table [rules for automatically spawning evidence from world events]
    AutoCreate = {
        ---@field gunshot: table [on gunshot - { enabled: boolean, tracerLength: number(m), tracerDuration: number(ms), fingerprintChance: number(0-1) }]
        gunshot = {
            enabled = true,
            tracerLength = 4.0,
            tracerDuration = 3000,
            fingerprintChance = 0.10,
        },
        ---@field bloodOnDamage: table [on significant ped damage spawn blood - { enabled: boolean, minDamage: number }]
        bloodOnDamage = {
            enabled = true,
            minDamage = 15.0,
        },
        ---@field drugResidue: table [on drug use/drop spawn residue - { enabled: boolean }]
        drugResidue = {
            enabled = true,
        },
    },

    ---@field WeaponCalibers: table [caliber label per weapon hash, keyed by weapon hash = string]
    WeaponCalibers = {
        [`WEAPON_PISTOL`]        = '9mm',
        [`WEAPON_PISTOL_MK2`]    = '9mm',
        [`WEAPON_COMBATPISTOL`]  = '9mm',
        [`WEAPON_APPISTOL`]      = '.45 ACP',
        [`WEAPON_PISTOL50`]      = '.50 AE',
        [`WEAPON_SNSPISTOL`]     = '.380',
        [`WEAPON_HEAVYPISTOL`]   = '.45 ACP',
        [`WEAPON_VINTAGEPISTOL`] = '.45 ACP',
        [`WEAPON_MICROSMG`]      = '9mm',
        [`WEAPON_SMG`]           = '9mm',
        [`WEAPON_ASSAULTSMG`]    = '5.56',
        [`WEAPON_MINISMG`]       = '9mm',
        [`WEAPON_PUMPSHOTGUN`]   = '12 GA',
        [`WEAPON_SAWNOFFSHOTGUN`]= '12 GA',
        [`WEAPON_ASSAULTSHOTGUN`]= '12 GA',
        [`WEAPON_BULLPUPSHOTGUN`]= '12 GA',
        [`WEAPON_ASSAULTRIFLE`]  = '7.62x39',
        [`WEAPON_CARBINERIFLE`]  = '5.56',
        [`WEAPON_ADVANCEDRIFLE`] = '5.56',
        [`WEAPON_SPECIALCARBINE`]= '5.56',
        [`WEAPON_BULLPUPRIFLE`]  = '5.56',
        [`WEAPON_MG`]            = '7.62x51',
        [`WEAPON_COMBATMG`]      = '7.62x51',
        [`WEAPON_SNIPERRIFLE`]   = '.338',
        [`WEAPON_HEAVYSNIPER`]   = '.50 BMG',
        [`WEAPON_MARKSMANRIFLE`] = '7.62x51',
    },

    ---@field BloodTypes: table [cosmetic blood type labels assigned per suspect - list of strings]
    BloodTypes = { 'O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-' },

    ---@field Vehicle: table [vehicle-linked evidence - fingerprints left on entry, plus blood/casings created while inside a vehicle; surfaced through the "Analyze vehicle" interaction and collected into the same evidence bags the lab analyses]
    Vehicle = {
        ---@field enabled: boolean [master toggle for vehicle-linked evidence + the analyze-vehicle interaction]
        enabled = true,

        ---@field fingerprintOnEnter: boolean [leave a fingerprint on a vehicle when a bare-handed player enters it]
        fingerprintOnEnter = true,

        ---@field fingerprintChance: number [percent chance (1-100) to leave a fingerprint on entry]
        fingerprintChance = 100,

        ---@field bloodInVehicle: boolean [link blood to the vehicle (instead of the ground) when the occupant is hurt while inside it]
        bloodInVehicle = true,

        ---@field casingInVehicle: boolean [link a bullet casing to the vehicle (instead of the ground) when a weapon is fired from inside it]
        casingInVehicle = true,

        ---@field checkGloves: boolean [if true, wearing gloves stops a player leaving fingerprints on entry (freemode peds only)]
        checkGloves = true,

        ---@field expire: number [seconds a vehicle evidence entry is kept before it is pruned]
        expire = 60 * 60,

        ---@field maxPerVehicle: number [max evidence entries kept per vehicle (oldest removed first)]
        maxPerVehicle = 20,
    },
}
