Config = Config or {}

-- CM Framework adaptation for Sumit's server.
-- This resource keeps the rn-vehicleshop UI, but all ownership goes through cm-vehicles.

Config.Debug = false

Config.PaymentAccount = 'bank' -- gun store charges 'bank' by default; set to 'cash' if you prefer.

-- Money is handled exactly like cm-gunstore: exports['cm-core']:RemoveMoney / AddMoney.
-- Config.PaymentAccount above picks which of these accounts is charged by default.
Config.Accounts = {
    cash = 'cash',
    bank = 'bank'
}

-- Transparent vehicle image capture (admin only), mirrors nv_cloth screenshot-basic flow.
-- Vehicle admin now uses a real 3D airport studio: green wall + green floor/stage
-- made from prop_ld_greenscreen_01. The flat DrawRect fallback is disabled by default
-- because it can cover the vehicle and gives poor tyre/floor cut-outs.
Config.ImageCapture = {
    enabled = true,
    folder = 'ui/images/vehicles',          -- saved inside this resource
    catalogImagePrefix = 'images/vehicles', -- kept for compatibility
    width = 512,
    height = 512,
    padding = 12,
    background = 'green',
    crop = { x = 0.00, y = 0.00, w = 1.00, h = 1.00 },
    chroma = {
        minGreen = 45,
        dominance = 1.10,
        greenMargin = 10,
        maxRed = 190,
        maxBlue = 190,
        soften = true
    },

    Backdrop = {
        enabled = true,
        model = 'prop_ld_greenscreen_01',
        fallbackDrawRect = false,

        -- This prop is already a complete 3D greenscreen/stage. Spawn only one.
        fixedCoords = vector4(-1228.0586, -2271.1174, 16.1346, 117.3766),
        rotation = vector3(0.0, 0.0, 0.0),

        -- 2x green-screen prop size applied with SetEntityMatrix.
        scale = 2.00,

        zLift = 0.62,
        collision = false
    }
}

-- Airport vehicle-admin studio. This is intentionally separate from the public showroom.
Config.VehicleAdminStudio = {
    enabled = true,
    player = vector4(-1238.4271, -2266.0142, 13.3036, 231.0500),
    vehicle = vector4(-1227.8779, -2271.1907, 13.3395, 242.6514),
    camera = vector3(-1219.7456, -2268.8145, 15.2026),
    cameraLookAt = vector3(-1248.9626, -2277.5510, 12.9446),
    cameraFov = 50.0,
    Environment = {
        hour = 12,
        minute = 0,
        second = 0,
        weather = 'EXTRASUNNY',
        timecycle = 'neutral',
        timecycleStrength = 0.0
    }
}

Config.HUD = {
    resource = 'cm-hud',
    hideWhileInStore = true,
    hideWhileInAdmin = true,
    hideWhileCapturing = true
}

Config.Admin = {
    -- For now every player can use /vehicleadmin, matching your current admin workflow.
    -- Later set AllPlayers = false and give ace permission: add_ace group.admin rnvehicleshop.admin allow
    AllPlayers = true,
    AcePermission = 'rnvehicleshop.admin'
}

-- Dealership interior (Pacific Bluffs MLO).
Config.Location = vector3(-2261.85, 391.45, 174.67)
Config.ExitLocation = vector4(-2264.3823, 392.3130, 174.6739, 263.2466)
Config.BoughtVehicleSpawnLocation = { coords = vector3(-2268.13, 383.24, 174.82), heading = 69.53 }
Config.TestVehicleSpawnLocation = { coords = vector3(-1047.42, -3023.59, 13.95), heading = 60.00 } -- airport test-drive spawn

Config.Dealer = {
    ped = 'a_m_m_business_01',
    coords = vector4(-2261.85, 391.45, 174.67, 115.80),
    npcName = 'Michael',
    greeting = 'Welcome to the vehicle showroom.',
    openText = '[E] Talk to dealer',
    distance = 2.6,
    drawDistance = 18.0
}

-- Per-player routing bucket / dimension.
-- When a player opens the showroom they are moved into their own bucket so the
-- preview car (and the green-screen capture) never clash with other players using
-- the shop at the same time. They return to the world bucket on exit.
-- The bucket id is derived from the player's server id so each player is isolated.
Config.Dimension = {
    enabled = true,         -- required for private showroom, test drive, and vehicle-admin capture.
    base = 700000,          -- bucket = base + serverId (kept high to avoid clashing with other systems)
    lockdownMode = 'strict' -- 'strict' = relaxed population; players only see entities in their bucket
}

-- NPC greet + RP-talk behaviour (mirrors cm-gunstore).
-- Custom dialog text is shown as a bubble above the dealer; a GTA native voice bark
-- plays at the same time because FiveM cannot voice arbitrary custom sentences.
Config.Ped = {
    enabled = true,
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    invincible = true,
    freeze = true,
    blockEvents = true,

    voiceEnabled = false,     -- no spoken bark
    showGreeting = false,     -- no greeting/farewell text bubble above the dealer
    greetingVoices = { 'GENERIC_HI', 'GENERIC_HOWS_IT_GOING', 'SHOP_GREET' },
    farewellVoices = { 'GENERIC_BYE', 'GENERIC_THANKS', 'SHOP_GOODBYE' },

    showName = true,
    nameHeight = 1.30,
    nameDistance = 8.0,

    speechDistance = 6.0,
    speechDuration = 5500,
    speechCooldown = 15000,
    greetings = {
        'Welcome to Pacific Bluffs. Looking for something special?',
        'Afternoon. Take a look around, every model is on the floor.',
        'Need something fast, or something comfortable?',
        'Fresh stock just landed. Want me to show you?',
        'Tell me your taste and I will find your car.'
    },
    farewells = {
        'Drive safe out there.',
        'Come back when you are ready.',
        'Maybe next time. Take care.',
        'Pleasure doing business.',
        'Catch you later.'
    },

    -- The RP "talk" step shown after pressing E, before the catalog opens.
    dialog = {
        clerkName = 'Michael',
        title = 'How can I help you today?',
        line = 'Take a seat. Tell me what you are after and I will pull it up on the floor for you.',
        optionStore = 'Show me the catalog',
        optionClose = 'Just browsing, thanks'
    }
}

-- On-screen interaction prompt shown when close to the dealer.
Config.Interact = {
    distance = 2.6,
    markerDistance = 18.0,
    key = 38,        -- E
    keyLabel = 'E',
    title = 'Talk to Dealer',
    subtitle = 'Browse and buy vehicles'
}


Config.Showroom = {
    -- In-store preview spot inside the Pacific Bluffs MLO.
    -- Camera placed in front of the car for a clean 3/4 showroom view of the whole vehicle.
    player = vector4(-2267.17, 380.10, 174.82, 107.10),
    vehicle = vector4(-2268.13, 383.24, 174.82, 69.53),
    camera = vector3(-2272.24, 387.97, 175.97),
    cameraLookAt = vector3(-2268.13, 383.24, 175.37),
    cameraRot = vector3(-6.0, 0.0, 250.0),
    cameraFov = 50.0
}

Config.Blip = {
    id = 326,
    color = 3,
    scale = 0.8,
    label = 'Car Dealer',
    showBlip = true
}

Config.TestDrive = {
    enabled = true,
    testDriveTimer = 60,
    testDriveCost = 50
}

-- Vehicles below are only a SOURCE LIST for /vehicleadmin.
-- A vehicle is NOT visible/usable until saved in the admin catalog with Available in Server or Available in Store enabled.

Config.Vehicles = {
    --[[ { -- A category that shows the vehicles that added into stock today. DONT TOUCH IF YOU WANT THIS OPTION/CATEGORY.
      title = "daily vehicles", -- Title of category.
      buttons = {} -- DONT TOUCH!
    }, ]]

    -- Examples:
    {
      title = "Compacts", -- Title of category.
      buttons = {
        {name = "Maxwell Asbo", costs = 1750, model = "Asbo", maxStock = 10},
        {name = "Dinka Blista", costs = 7000, model = "blista", maxStock = 10},
        {name = "Brioso R/A", costs = 10000, model = "brioso", maxStock = 10},
        {name = "Club BF", costs = 2750, model = "club", maxStock = 10},
        {name = "Karin Dilettante", costs = 12500, model = "dilettante", maxStock = 10},
        {name = "Dinka Blista Kanjo", costs = 17000, model = "kanjo", maxStock = 10},
        {name = "Weeny Issi", costs = 11000, model = "issi2", maxStock = 10},
        {name = "Weeny Issi Classic", costs = 2000, model = "issi3", maxStock = 10},
        {name = "Benefactor Panto", costs = 7500, model = "panto", maxStock = 10},
        {name = "Bollokan Prairie", costs = 25000, model = "prairie", maxStock = 10},
        {name = "Declasse Rhapsody", costs = 8000, model = "rhapsody", maxStock = 10},
        {name = "Grotti Brioso 300", costs = 6500, model = "brioso2", maxStock = 10},
        {name = "BF Weevil", costs = 20000, model = "weevil", maxStock = 5},
      }
    },
    {
      title = "Coupes", -- Title of category.
      buttons = {
        {name = "Cognoscenti Cabrio Enus", costs = 35000, model = "cogcabrio", maxStock = 10},
        {name = "Exemplar Dewbauchee", costs = 45000, model = "exemplar", maxStock = 10},
        {name = "Ocelot F620", costs = 27500, model = "f620", maxStock = 10},
        {name = "Lampadati Felon", costs = 30000, model = "felon", maxStock = 10},
        {name = "Lampadati Felon GT", costs = 75000, model = "felon2", maxStock = 10},
        {name = "Ocelot Jackal", costs = 50000, model = "jackal", maxStock = 10},
        {name = "Übermacht Oracle", costs = 60000, model = "oracle", maxStock = 10},
        {name = "Übermacht Oracle XS", costs = 70000, model = "oracle2", maxStock = 10},
        {name = "Übermacht Sentinel", costs = 65000, model = "sentinel", maxStock = 10},
        {name = "Übermacht Sentinel XS", costs = 57500, model = "sentinel2", maxStock = 10},
        {name = "Enus Windsor", costs = 70000, model = "windsor", maxStock = 10},
        {name = "Enus Windsor Drop", costs = 80000, model = "windsor2", maxStock = 10},
        {name = "Übermacht Zion", costs = 37000, model = "zion", maxStock = 10},
        {name = "Übermacht Zion Cabrio", costs = 45000, model = "zion2", maxStock = 10},
        {name = "Karin Previon", costs = 60000, model = "previon", maxStock = 10},
        {name = "Karin Sultan CR", costs = 75000, model = "sultan2", maxStock = 10},
        {name = "Vapid Flash GT", costs = 60000, model = "flashgt", maxStock = 10},

      }
    },
    {
      title = "Bicycles", -- Title of category.
      buttons = {
        {name = "BMX", costs = 1000, model = "bmx", maxStock = 10},
        {name = "Cruiser", costs = 1050, model = "cruiser", maxStock = 10},
        {name = "Fixter", costs = 1500, model = "fixter", maxStock = 10},
        {name = "Scorcher", costs = 1750, model = "scorcher", maxStock = 10},
        {name = "Tribike", costs = 2000, model = "tribike", maxStock = 10},
        {name = "Tribike 2", costs = 2000, model = "tribike2", maxStock = 10},
        {name = "Tribike 3", costs = 2000, model = "tribike3", maxStock = 10},
      }
    },
    {
      title = "Sedans", -- Title of category.
      buttons = {
        {name = "Enus Cognoscenti 55", costs = 90000, model = "cog55", maxStock = 10},
        {name = "Cheval Fugitive", costs = 80000, model = "fugitive", maxStock = 10},
        {name = "Cinquemila Lampadati", costs = 77000, model = "cinquemila", maxStock = 10},
        {name = "Albany V-STR", costs = 100000, model = "vstr", maxStock = 10},
      }
    },
    {
      title = "Sports", -- Title of category.
      buttons = {
        {name = "Grotti Bestia GTS", costs = 135000, model = "bestiagts", maxStock = 10},
        {name = "Pfister Comet S2 Cabrio", costs = 300000, model = "comet7", maxStock = 10},
        {name = "Pfister Comet", costs = 300000, model = "comet2", maxStock = 10},
        {name = "Pfister Comet Retro", costs = 225000, model = "comet3", maxStock = 10},
        {name = "Pfister Comet SR", costs = 270000, model = "comet5", maxStock = 10},
        {name = "Invetero Coquette", costs = 140000, model = "coquette", maxStock = 10},
        {name = "Obey 8F Drafter", costs = 400000, model = "drafter", maxStock = 10},
        {name = "Banshee", costs = 120000, model = "banshee", maxStock = 10},
        {name = "Banshee 2", costs = 200000, model = "banshee2", maxStock = 10},
        {name = "Annis Elegy Retro Custom", costs = 190000, model = "elegy", maxStock = 10},
        {name = "Annis Elegy RH8", costs = 160000, model = "elegy2", maxStock = 10},
        {name = "Benefactor Feltzer", costs = 140000, model = "feltzer2", maxStock = 10},
        {name = "Lampadati Furore GT", costs = 175000, model = "furoregt", maxStock = 10},
        {name = "Lampadati Komoda", costs = 202000, model = "komoda", maxStock = 10},
        {name = "Överflöd Imorgon", costs = 135000, model = "imorgon", maxStock = 10},
        {name = "Ocelot Jugular", costs = 420000, model = "jugular", maxStock = 10},
        {name = "Dinka Jester", costs = 120250, model = "jester", maxStock = 10},
        {name = "Dinka Jester Classic", costs = 220000, model = "jester3", maxStock = 10},
        {name = "Ocelot Lynx", costs = 200000, model = "lynx", maxStock = 10},
        {name = "Dewbauchee Massacro", costs = 210000, model = "massacro", maxStock = 10},
        {name = "Vysser Neo", costs = 230000, model = "neo", maxStock = 10},
        {name = "Pfister Neon", costs = 220000, model = "neon", maxStock = 10},
        {name = "Obey 9F Cabrio", costs = 205000, model = "ninef2", maxStock = 10},
        {name = "Enus Paragon", costs = 390000, model = "paragon", maxStock = 10},
        {name = "Maibatsu Penumbra FF", costs = 89000, model = "penumbra2", maxStock = 10},
        {name = "Dewbauchee Rapid GT Convertible", costs = 92000, model = "rapidgt2", maxStock = 10},
        {name = "Übermacht Revolter", costs = 300000, model = "revolter", maxStock = 10},
        {name = "Benefactor Schlagen GT", costs = 260000, model = "schlagen", maxStock = 10},
        {name = "Dewbauchee Seven-70", costs = 200000, model = "seven70", maxStock = 10},
        {name = "Dewbauchee Specter", costs = 215000, model = "specter", maxStock = 10},
        {name = "Vapid Dominator ASP", costs = 110000, model = "dominator7", maxStock = 10},
        {name = "Pfister Astron", costs = 190000, model = "astron", maxStock = 10},
      }
    },
    {
      title = "Sports Classic", -- Title of category.
      buttons = {
        {name = "Invetero Coquette Classic", costs = 165000, model = "coquette2", maxStock = 10},
        {name = "Invetero Coquette BlackFin", costs = 80000, model = "coquette3", maxStock = 10},
        {name = "Vapid Hotknife", costs = 90000, model = "hotknife", maxStock = 10},
      }
    },
    --{
    --  title = "Super", -- Title of category.
    --  buttons = {
    --    {name = "Principe Deveste", costs = 234000, model = "deveste", maxStock = 10},
    --    {name = "Pegassi Ignus", costs = 1120000, model = "ignus", maxStock = 10},
    --    {name = "Överflöd Zeno", costs = 1350000, model = "zeno", maxStock = 10},
    --    {name = "Invetero Coquette D10", costs = 300000, model = "coquette4", maxStock = 10},
    --    {name = "Progen Itali GTO", costs = 450000, model = "italigto", maxStock = 10},
    --    {name = "Progen Itali RSX", costs = 460000, model = "italirsx", maxStock = 10},
--
    --  }
    --},
    {
      title = "Muscle", -- Title of category.
      buttons = {
        {name = "Vapid Blade", costs = 17500, model = "blade", maxStock = 10},
        {name = "Ellie", costs = 65000, model = "ellie", maxStock = 10},
        {name = "Bravado Buffalo S", costs = 35000, model = "buffalo2", maxStock = 10},
        {name = "Albany Buccaneer Lux", costs = 24500, model = "buccaneer2", maxStock = 10},
        {name = "Vapid Chino Lux", costs = 28500, model = "chino2", maxStock = 10},
        {name = "Schyster Deviant", costs = 50000, model = "deviant", maxStock = 10},
        {name = "Vapid Dominator GTX", costs = 70000, model = "dominator3", maxStock = 10},
        {name = "Vapid Dominator GTT", costs = 80000, model = "dominator8", maxStock = 10},
        {name = "Willard Faction GT", costs = 62000, model = "faction2", maxStock = 10},
        {name = "Bravado Gauntlet Hellfire", costs = 170000, model = "gauntlet4", maxStock = 10},
        {name = "Bravado Gauntlet Classic Custom", costs = 90000, model = "gauntlet5", maxStock = 10},
        {name = "Vapid Impaler", costs = 87300, model = "impaler", maxStock = 10},
        {name = "Declasse Moonbeam", costs = 130000, model = "moonbeam2", maxStock = 10},
        {name = "Imponte Nightshade", costs = 70000, model = "nightshade", maxStock = 10},
        {name = "Declasse Sabre GT Turbo", costs = 95000, model = "sabregt2", maxStock = 10},
        {name = "Vapid Slam Van", costs = 47000, model = "slamvan3", maxStock = 10},
        {name = "Dundreary Virgo Custom", costs = 49800, model = "virgo2", maxStock = 10},
        {name = "Bravado Buffalo STX", costs = 345000, model = "buffalo4", maxStock = 10},
      }
    },
    {
      title = "SUV", -- Title of category.
      buttons = {
        {name = "Gallivanter Baller LE LWB", costs = 338000, model = "baller4", maxStock = 10},
        {name = "Gallivanter Baller ST", costs = 398000, model = "baller7", maxStock = 10},
        {name = "Karin BeeJay XL", costs = 75000, model = "bjxl", maxStock = 10},
        {name = "Albany Cavalcade", costs = 64000, model = "cavalcade2", maxStock = 10},
        {name = "Benefactor Dubsta", costs = 132000, model = "dubsta2", maxStock = 10},
        {name = "Fathom FQ2", costs = 82000, model = "fq2", maxStock = 10},
        {name = "Declasse Granger", costs = 129000, model = "granger", maxStock = 10},
        {name = "Bravado Gresley", costs = 45000, model = "gresley", maxStock = 10},
        {name = "Emperor Habanero", costs = 45000, model = "habanero", maxStock = 10},
        {name = "Enus Huntley", costs = 45000, model = "huntley", maxStock = 10},
        {name = "Dundreary Landstalker XL", costs = 95000, model = "landstalker2", maxStock = 10},
        {name = "Lampadati Novak", costs = 95000, model = "novak", maxStock = 10},
        {name = "Mammoth Patriot Stretch", costs = 139000, model = "patriot2", maxStock = 10},
        {name = "Übermacht Rebla GTS", costs = 134000, model = "rebla", maxStock = 10},
        {name = "Obey Rocoto", costs = 130000, model = "rocoto", maxStock = 10},
        {name = "Canis Seminole", costs = 20000, model = "seminole", maxStock = 10},
        {name = "Canis Seminole Frontier", costs = 29000, model = "seminole2", maxStock = 10},
        {name = "Pegassi Toros", costs = 335000, model = "toros", maxStock = 10},
        {name = "Benefactor XLS", costs = 68000, model = "xls", maxStock = 10},
        {name = "Dinka Sugoi", costs = 85000, model = "sugoi", maxStock = 10},
        {name = "Obey I-Wagen", costs = 225000, model = "iwagen", maxStock = 10},
        {name = "Enus Jubilee", costs = 385000, model = "jubilee", maxStock = 10},
      }
    },
    {
      title = "Off Road", -- Title of category.
      buttons = {
        {name = "Annis Bifta", costs = 15500, model = "bifta", maxStock = 10},
        {name = "Vapid Caracara 4x4", costs = 130000, model = "caracara2", maxStock = 10},
        {name = "Annis Dubsta 6x6", costs = 150000, model = "dubsta3", maxStock = 10},
        {name = "Karin Everon", costs = 140000, model = "everon", maxStock = 10},
        {name = "Canis Freecrawler", costs = 120000, model = "freecrawler", maxStock = 10},
        {name = "Annis Hellion", costs = 140000, model = "hellion", maxStock = 10},
        {name = "Canis Kamacho", costs = 120000, model = "kamacho", maxStock = 10},
        {name = "Vapid Riata", costs = 80000, model = "riata", maxStock = 10},
        {name = "Vapid Sandking XL", costs = 150000, model = "sandking", maxStock = 10},
        {name = "Vapid Sandking SWB", costs = 12500, model = "sandking2", maxStock = 10},
        {name = "Maxwell Vagrant", costs = 12500, model = "vagrant", maxStock = 10},
        {name = "Dinka Verus", costs = 20000, model = "verus", maxStock = 10},
        {name = "Annis Bf Injection", costs = 9000, model = "bfinjection", maxStock = 10},
        {name = "Vapid Contender", costs = 35000, model = "contender", maxStock = 10},
      }
    },
    {
      title = "Motorcycles", -- Title of category.
      buttons = {
        {name = "Dinka Akuma", costs = 55000, model = "akuma", maxStock = 10},
        {name = "LCC Avarus", costs = 20000, model = "avarus", maxStock = 10},
        {name = "WMC Bagger", costs = 43500, model = "bagger", maxStock = 10},
        {name = "Pegassi Bati 801", costs = 50000, model = "bati", maxStock = 10},
        {name = "Pegassi Bati 801RR", costs = 64000, model = "bati2", maxStock = 10},
        {name = "Nagasaki BF400", costs = 22000, model = "bf400", maxStock = 10},
        {name = "Nagasaki Carbon RS", costs = 52000, model = "carbonrs", maxStock = 10},
        {name = "Nagasaki Chimera", costs = 71000, model = "chimera", maxStock = 10},
        {name = "Western Cliffhanger", costs = 28500, model = "cliffhanger", maxStock = 10},
        {name = "Western Daemon Custom", costs = 63000, model = "daemon2", maxStock = 10},
        {name = "Shitzu Defiler", costs = 30000, model = "defiler", maxStock = 10},
        {name = "Principe Diablous", costs = 47000, model = "diablous", maxStock = 10},
        {name = "Principe Diablous Custom", costs = 78000, model = "diablous2", maxStock = 10},
        {name = "Dinka Double-T", costs = 28000, model = "double", maxStock = 10},
        {name = "Pegassi Esskey", costs = 12000, model = "esskey", maxStock = 10},
        {name = "Pegassi FCR 1000", costs = 15000, model = "fcr", maxStock = 10},
        {name = "Pegassi FCR 1000 Custom", costs = 39000, model = "fcr2", maxStock = 10},
        {name = "Shitzu Hakuchou", costs = 67000, model = "hakuchou", maxStock = 10},
        {name = "LLC Innovation", costs = 53500, model = "innovation", maxStock = 10},
        {name = "Principe Lectro", costs = 28000, model = "lectro", maxStock = 10},
        {name = "WMC Nightblade", costs = 63000, model = "nightblade", maxStock = 10},
        {name = "Nagasaki Stryder", costs = 50000, model = "stryder", maxStock = 10},
        {name = "Dinka Vindicator", costs = 59000, model = "vindicator", maxStock = 10},
        {name = "Nagasaki Shinobi", costs = 55000, model = "shinobi", maxStock = 10},
        {name = "Western Reever", costs = 25000, model = "reever", maxStock = 10},
      }
    },
}
-- Explanation of the buttons:
--[[
    name = vehicle's label (The name which is displayed in the vehicle menu).
    costs = vehicle's price.
    model = vehicle's model.
    stock = The maximum stock a vehicle can reach (Explanation from above).
]]

------------------------------------------------------------------------------------------------------------------------
-- Color selection:
------------------------------------------------------------------------------------------------------------------------

-- Full list of colors - https://wiki.rage.mp/index.php?title=Vehicle_Colors
Config.Colors = {
  {r = 13, g = 17, b = 22, colorName = "Metallic Black", gtaColor = 0},
  {r = 28, g = 29, b = 33, colorName = "Metallic Graphite Black", gtaColor = 1},
  {r = 50, g = 56, b = 61, colorName = "Metallic Black Steal", gtaColor = 2},
  {r = 69, g = 75, b = 79, colorName = "Metallic Dark Silver", gtaColor = 3},
  {r = 153, g = 157, b = 160, colorName = "Metallic Silver", gtaColor = 4},
  {r = 194, g = 196, b = 198, colorName = "Metallic Blue Silver", gtaColor = 5},
  {r = 151, g = 154, b = 151, colorName = "Metallic Steel Gray", gtaColor = 6},
  {r = 99, g = 115, b = 128, colorName = "Metallic Shadow Silver", gtaColor = 7},
  {r = 99, g = 98, b = 92, colorName = "Metallic Stone Silver", gtaColor = 8},
  {r = 60, g = 63, b = 71, colorName = "Metallic Midnight Silver", gtaColor = 9},
  {r = 68, g = 78, b = 84, colorName = "Metallic Gun Metal", gtaColor = 10},
  {r = 29, g = 33, b = 41, colorName = "Metallic Anthracite Grey", gtaColor = 11},
  {r = 99, g = 98, b = 92, colorName = "Matte Black", gtaColor = 12},
  {r = 38, g = 40, b = 42, colorName = "Matte Gray", gtaColor = 13},
  {r = 81, g = 85, b = 84, colorName = "Matte Light Grey", gtaColor = 14},
  {r = 21, g = 25, b = 33, colorName = "Util Black", gtaColor = 15},
  {r = 30, g = 36, b = 41, colorName = "Util Black Poly", gtaColor = 16},
  {r = 51, g = 58, b = 60, colorName = "Util Dark Silver", gtaColor = 17},
  {r = 140, g = 144, b = 149, colorName = "Util Silver", gtaColor = 18},
  {r = 57, g = 67, b = 77, colorName = "Util Gun Metal", gtaColor = 19},
  {r = 80, g = 98, b = 114, colorName = "Util Shadow Silver", gtaColor = 20},
  {r = 30, g = 35, b = 47, colorName = "Worn Black", gtaColor = 21},
  {r = 54, g = 58, b = 63, colorName = "Worn Graphite", gtaColor = 22},
  {r = 160, g = 161, b = 153, colorName = "Worn Silver Grey", gtaColor = 23},
  {r = 211, g = 211, b = 211, colorName = "Worn Silver", gtaColor = 24},
  {r = 183, g = 191, b = 202, colorName = "Worn Blue Silver", gtaColor = 25},
  {r = 119, g = 135, b = 148, colorName = "Worn Shadow Silver", gtaColor = 26},
  {r = 192, g = 14, b = 26, colorName = "Metallic Red", gtaColor = 27},
  {r = 218, g = 25, b = 24, colorName = "Metallic Torino Red", gtaColor = 28},
  {r = 182, g = 17, b = 27, colorName = "Metallic Formula Red", gtaColor = 29},
  {r = 165, g = 30, b = 35, colorName = "Metallic Blaze Red", gtaColor = 30},
  {r = 123, g = 26, b = 34, colorName = "Metallic Graceful Red", gtaColor = 31},
  {r = 142, g = 27, b = 31, colorName = "Metallic Garnet Red", gtaColor = 32},
  {r = 111, g = 24, b = 24, colorName = "Metallic Desert Red", gtaColor = 33},
  {r = 73, g = 17, b = 29, colorName = "Metallic Cabernet Red", gtaColor = 34},
  {r = 99, g = 98, b = 92, colorName = "Metallic Candy Red", gtaColor = 35},
  {r = 212, g = 74, b = 23, colorName = "Metallic Sunrise Orange", gtaColor = 36},
  {r = 194, g = 148, b = 79, colorName = "Metallic Classic Gold", gtaColor = 37},
  {r = 247, g = 134, b = 22, colorName = "Metallic Orange", gtaColor = 38},
  {r = 207, g = 31, b = 33, colorName = "Matte Red", gtaColor = 39},
  {r = 115, g = 32, b = 33, colorName = "Matte Dark Red", gtaColor = 40},
  {r = 242, g = 125, b = 32, colorName = "Matte Orange", gtaColor = 41},
  {r = 255, g = 201, b = 31, colorName = "Matte Yellow", gtaColor = 42},
  {r = 156, g = 16, b = 22, colorName = "Util Red", gtaColor = 43},
  {r = 222, g = 15, b = 24, colorName = "Util Bright Red", gtaColor = 44},
  {r = 143, g = 30, b = 23, colorName = "Util Garnet Red", gtaColor = 45},
  {r = 169, g = 71, b = 68, colorName = "Worn Red", gtaColor = 46},
  {r = 177, g = 108, b = 81, colorName = "Worn Golden Red", gtaColor = 47},
  {r = 55, g = 28, b = 37, colorName = "Worn Dark Red", gtaColor = 48},
  {r = 19, g = 36, b = 40, colorName = "Metallic Dark Green", gtaColor = 49},
  {r = 18, g = 46, b = 43, colorName = "Metallic Racing Green", gtaColor = 50},
  {r = 18, g = 56, b = 60, colorName = "Metallic Sea Green", gtaColor = 51},
  {r = 49, g = 66, b = 63, colorName = "Metallic Olive Green", gtaColor = 52},
  {r = 21, g = 92, b = 45, colorName = "Metallic Green", gtaColor = 53},
  {r = 27, g = 103, b = 112, colorName = "Metallic Gasoline Blue Green", gtaColor = 54},
  {r = 102, g = 184, b = 31, colorName = "Matte Lime Green", gtaColor = 55},
  {r = 34, g = 56, b = 62, colorName = "Util Dark Green", gtaColor = 56},
  {r = 29, g = 90, b = 63, colorName = "Util Green", gtaColor = 57},
  {r = 45, g = 66, b = 63, colorName = "Worn Dark Green", gtaColor = 58},
  {r = 69, g = 89, b = 75, colorName = "Worn Green", gtaColor = 59},
  {r = 101, g = 134, b = 127, colorName = "Worn Sea Wash", gtaColor = 60},
  {r = 34, g = 46, b = 70, colorName = "Metallic Midnight Blue", gtaColor = 61},
  {r = 35, g = 49, b = 85, colorName = "Metallic Dark Blue", gtaColor = 62},
  {r = 48, g = 76, b = 126, colorName = "Metallic Saxony Blue", gtaColor = 63},
  {r = 71, g = 87, b = 143, colorName = "Metallic Blue", gtaColor = 64},
  {r = 99, g = 123, b = 167, colorName = "Metallic Mariner Blue", gtaColor = 65},
  {r = 57, g = 71, b = 98, colorName = "Metallic Harbor Blue", gtaColor = 66},
  {r = 214, g = 231, b = 241, colorName = "Metallic Diamond Blue", gtaColor = 67},
  {r = 118, g = 175, b = 190, colorName = "Metallic Surf Blue", gtaColor = 68},
  {r = 39, g = 81, b = 144, colorName = "Util Blue", gtaColor = 77},
  {r = 66, g = 113, b = 225, colorName = "Util Maui Blue Poly", gtaColor = 80},
  {r = 37, g = 58, b = 167, colorName = "Matte Blue", gtaColor = 83},
  {r = 255, g = 207, b = 32, colorName = "Metallic Taxi Yellow", gtaColor = 88},
  {r = 251, g = 226, b = 18, colorName = "Metallic Race Yellow", gtaColor = 89},
  {r = 80, g = 50, b = 24, colorName = "Metallic Pueblo Beige", gtaColor = 94},
  {r = 34, g = 27, b = 25, colorName = "Metallic Choco Brown", gtaColor = 96},
  {r = 172, g = 153, b = 117, colorName = "Metallic Straw Beige", gtaColor = 99},
  {r = 117, g = 43, b = 25, colorName = "Metallic Choco Orange", gtaColor = 104},
  {r = 223, g = 213, b = 178, colorName = "Metallic Sun Bleeched Sand", gtaColor = 106},
  {r = 247, g = 237, b = 213, colorName = "Metallic Cream", gtaColor = 107},
  {r = 120, g = 95, b = 51, colorName = "Util Medium Brown", gtaColor = 109},
  {r = 255, g = 255, b = 246, colorName = "Metallic White", gtaColor = 111},
  {r = 234, g = 234, b = 234, colorName = "Metallic Frost White", gtaColor = 112},
  {r = 176, g = 171, b = 148, colorName = "Worn Honey Beige", gtaColor = 113},
  {r = 53, g = 65, b = 88, colorName = "Brushed Black steel", gtaColor = 118},
  {r = 234, g = 230, b = 222, colorName = "Worn Off White", gtaColor = 121},
  {r = 223, g = 221, b = 208, colorName = "Util Off White", gtaColor = 122},
  {r = 242, g = 173, b = 46, colorName = "Worn Orange", gtaColor = 123},
  {r = 249, g = 164, b = 88, colorName = "Worn Light Orange", gtaColor = 124},
  {r = 78, g = 100, b = 67, colorName = "Matte Green", gtaColor = 128},
  {r = 246, g = 174, b = 32, colorName = "Orange", gtaColor = 138},
  {r = 176, g = 238, b = 110, colorName = "Green", gtaColor = 139},
  {r = 105, g = 103, b = 72, colorName = "Matte Olive Drab", gtaColor = 152},
  {r = 122, g = 108, b = 85, colorName = "Matte Desert Brown", gtaColor = 153},
  {r = 195, g = 180, b = 146, colorName = "Matte Desert Tan", gtaColor = 154},
  {r = 90, g = 99, b = 82, colorName = "Matte Foilage Green", gtaColor = 155},
}
-- Explanation of color selection:
--[[
    r,g,b = (The color rgb values according to your gta color).
    colorName = color's name (put whatever you want).
    gtaColor = the color number from gta list.
]]

