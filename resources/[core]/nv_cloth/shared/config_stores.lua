-- nv_cloth/shared/config_stores.lua
-- Load AFTER shared/config.lua. Adds per-store positioning + camera settings.

Config = Config or {}

Config.IsolateDressing    = true   -- private routing bucket while shopping (no griefing / no collisions)
Config.InteractDistance   = 1.6    -- how close to the counter the player must be
Config.ClerkSpawnDistance = 60.0   -- clerks are local peds, spawned only when a player is nearby
Config.CameraDebug        = false  -- draws the camera collision rays (green = clear, red = blocked)

-- Camera presets
--   bone  : ped bone the camera looks at (11816 pelvis, 24818 upper spine, 31086 head)
--   z     : vertical offset from that bone
--   dist  : desired distance from the focus point (auto-shortened if a wall is in the way)
--   pitch : degrees, + looks down from above, - looks up from below
--   yaw   : extra orbit angle (180 = view from behind, useful for bags)
Config.CameraPresets = {
    full  = { bone = 11816, z =  0.05, dist = 2.40, pitch =   4.0, fov = 45.0 },
    head  = { bone = 31086, z =  0.03, dist = 0.75, pitch =   2.0, fov = 38.0 },
    torso = { bone = 24818, z =  0.00, dist = 1.25, pitch =   3.0, fov = 42.0 },
    legs  = { bone = 11816, z = -0.45, dist = 1.45, pitch =  -4.0, fov = 42.0 },
    feet  = { bone = 11816, z = -0.85, dist = 1.10, pitch = -12.0, fov = 40.0 },
    bag   = { bone = 24818, z =  0.00, dist = 1.40, pitch =   3.0, fov = 42.0, yaw = 180.0 },
}

-- NUI category -> camera preset
Config.CategoryCamera = {
    tops = 'torso', undershirts = 'torso', accessories = 'torso', watches = 'torso', bracelets = 'torso',
    pants = 'legs',
    shoes = 'feet',
    hats = 'head', hat = 'head', glasses = 'head', masks = 'head', earrings = 'head',
    bags = 'bag',
}

--[[
  Per-Store Configurations.
  Capture clerk/interact in-game with /clothdev (client/cl_shopdev.lua):
    /clothdev clerk    -> behind counter facing customer
    /clothdev interact -> customer side of counter
    /clothdev test     -> test 360 camera raycast clearance

  Every store's `dressing` spot is deliberately the SAME shared, known-good
  room (Config.DefaultDressingRoom, shared/config.lua) rather than a per-store
  capture. The old per-store dressing coordinates were inconsistently curated
  and kept putting players near walls/tables, which also fouled the collision-
  avoidance camera. Config.IsolateDressing already puts every shopping player
  in their own private routing bucket, so many players can share this one
  physical spot with no visibility/collision between them. Do not add a
  per-store `dressing` override back without re-verifying it doesn't clip.

  Every regular clothing storefront is deliberately limited to the same six
  categories: headwear, glasses, outerwear (torso, with 'arms' as its preview-
  only mesh companion), shirt, pants, shoes. Accessories (earrings, bracelets,
  watches, chains, bags) are sold only through the single dedicated
  Config.Shops['accessories'] location in shared/config.lua.
]]
local CLOTHING_CATEGORIES = { 'hat', 'torso', 'arms', 'tshirt', 'pants', 'shoes', 'glasses' }

local StoreList = {
    {
        id       = 'strawberry',
        label    = 'Discount Store - Strawberry',
        clerk    = {
            model    = 's_f_y_shop_low',
            coords   = vector4(73.85, -1391.80, 28.38, 175.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(74.45, -1392.85, 29.38),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'hawick',
        label    = 'Suburban - Hawick',
        clerk    = {
            model    = 's_f_y_shop_mid',
            coords   = vector4(-710.20, -152.40, 36.42, 140.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(-709.85, -153.25, 37.42),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'rockford',
        label    = 'Ponsonbys - Rockford',
        clerk    = {
            model    = 's_f_m_shop_high',
            coords   = vector4(-162.90, -304.30, 38.73, 335.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(-163.50, -303.40, 39.73),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'textile',
        label    = 'Discount Store - Textile City',
        clerk    = {
            model    = 's_f_y_shop_low',
            coords   = vector4(427.50, -805.80, 28.49, 90.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(426.50, -805.80, 29.49),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'vespucci_beach',
        label    = 'Binco - Vespucci Beach',
        clerk    = {
            model    = 's_f_y_shop_low',
            coords   = vector4(-823.10, -1072.80, 10.33, 210.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(-823.80, -1073.80, 11.33),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'del_perro',
        label    = 'Ponsonbys - Del Perro',
        clerk    = {
            model    = 's_f_m_shop_high',
            coords   = vector4(-1449.80, -237.20, 48.82, 50.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(-1449.10, -238.10, 49.82),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'paleto',
        label    = 'Discount Store - Paleto',
        clerk    = {
            model    = 's_f_y_shop_low',
            coords   = vector4(4.90, 6511.40, 30.88, 45.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(5.70, 6512.20, 31.88),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'alta',
        label    = 'Suburban - Alta',
        clerk    = {
            model    = 's_f_y_shop_mid',
            coords   = vector4(128.20, -225.40, 53.56, 32.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(127.40, -224.60, 54.56),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'grapeseed',
        label    = 'Discount - Grapeseed',
        clerk    = {
            model    = 's_f_y_shop_low',
            coords   = vector4(1694.00, 4822.40, 41.06, 95.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(1694.90, 4823.40, 42.06),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'harmony',
        label    = 'Discount - Harmony',
        clerk    = {
            model    = 's_f_y_shop_low',
            coords   = vector4(616.40, 2764.80, 41.09, 180.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(616.40, 2763.50, 42.09),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'sandy',
        label    = 'Discount - Sandy Shores',
        clerk    = {
            model    = 's_f_y_shop_low',
            coords   = vector4(1197.80, 2710.20, 37.22, 180.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(1197.80, 2711.50, 38.22),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'south_rockford',
        label    = 'Suburban - South Rockford',
        clerk    = {
            model    = 's_f_y_shop_mid',
            coords   = vector4(-1193.65, -766.75, 16.32, 215.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(-1193.15, -767.80, 17.32),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'chumash',
        label    = 'Suburban - Chumash',
        clerk    = {
            model    = 's_f_y_shop_mid',
            coords   = vector4(-3170.80, 1044.20, 19.86, 335.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(-3171.50, 1045.20, 20.86),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
    {
        id       = 'route68_north',
        label    = 'Discount - Route 68 North',
        clerk    = {
            model    = 's_f_y_shop_low',
            coords   = vector4(-1103.50, 2712.40, 18.11, 220.0),
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        interact = vector3(-1104.30, 2711.50, 19.11),
        dressing = Config.DefaultDressingRoom,
        categories = CLOTHING_CATEGORIES,
    },
}

-- Config.Shops intentionally holds two different row shapes side by side:
--   Config.Shops['clothes']  -- set in shared/config.lua: catalog-level shop meta
--                                ({ label, blip, dressingRoom, categories, locations }).
--   Config.Shops[1..N]       -- set here: per-location interaction rows
--                                ({ id, label, clerk, interact, dressing, categories })
--                                consumed via ipairs() by cl_shop.lua, cl_shopdev.lua,
--                                cl_stores.lua, sv_clothing_stores.lua, sv_store_session.lua.
-- ipairs() only walks the numeric keys so it never sees 'clothes', and pairs()
-- consumers (e.g. sv_cloth.lua's dressing-zone check) must type-check every
-- field before reading it, since no single field exists on both shapes.
Config.Shops = Config.Shops or {}
for i, shop in ipairs(StoreList) do
    Config.Shops[i] = shop
end
