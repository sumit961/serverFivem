Config = {}

Config.Framework = 'cm-core'
Config.Lang = 'en'
Config.Inventory = 'cm-inventory'
Config.AppearanceRessource = 'native'

-- New live-preview shop UI: no item images are loaded in the clothing store.
-- true = only clothing saved/enabled by /clothingadmin appears in the shop.
-- false = fallback to all GTA drawable variations when catalog is empty.
Config.UseCatalogOnly = true

-- Return player to the exact place where they pressed E.
-- This avoids closing an accessories shop and being teleported to another store exit.
Config.ReturnToOriginalPosition = true

-- Normal player clothing preview location. Set from /cmpos in the clothing store.
-- Player is returned to their original position when the menu closes.
Config.DefaultDressingRoom = vec4(-1197.2906, -778.9427, 17.3298, 128.0196)


-- Admin studio is used only for /clothingadmin.
-- Admin preview now uses a real green prop setup at LSIA airport instead of only a drawn green box.
-- Use /cmpos in-game to print your current position, then replace StudioCoords if you want another spot.
Config.AdminStudio = {
    -- Fixed admin player spot confirmed in-game.
    StudioCoords = vec4(-1339.2468, -2799.4224, 13.9449, 328.4029),
    LockPlayerToStudio = true,
    StripToDefaultNaked = true,
    -- Disabled by default so admin capture does not show any extra/naked NPC.
    -- Set this to 'same_as_player' if you want a reference mannequin beside the player.
    ReferencePedModel = false,
    ReferenceOffset = vec3(1.15, 0.20, 0.0),

    Backdrop = {
        enabled = true,
        -- Custom green prop. Put prop_ld_greenscreen_01.ydr in nv_cloth/stream/.
        -- This prop has both the floor and the wall in green.
        model = 'prop_ld_greenscreen_01',
        -- Keep the greenscreen fixed at the confirmed world position.
        fixedCoords = vec4(-1338.6660, -2797.2190, 17.6949, 151.4439),

        -- ── Enlarge the greenscreen by tiling copies of the same prop ──────────
        -- The prop is widened into a row of copies so the green wall fills the
        -- whole screenshot frame from every capture angle (front/back/left/right).
        -- Tiles only ever extend sideways and BEHIND the player, never in front.
        --   tileCols = how many side-by-side (left↔right). 3 ≈ double width.
        --   tileRows = how many stacked BEHIND each other (depth). Keep 1 unless
        --              you need deeper cover; extra rows always push away from the
        --              player so they can never appear in front of them.
        --   tileSpacing = metres between side tiles (a bit under prop width so
        --                 they overlap and leave no seam).
        --   tileDepthSpacing = metres between depth rows (defaults to tileSpacing).
        -- The prop is scaled 3x below, so a single tile already fills the frame.
        -- Keep tileCols at 1 to avoid overlapping duplicate copies; raise it only
        -- if you lower the scale and need to widen the wall again.
        tileCols = 1,
        tileRows = 1,
        tileSpacing = 2.6,
        tileDepthSpacing = 2.6,

        distanceBehindPed = 1.25,
        zOffset = 0.0,

        -- ── Live tuning (set via the /vehgreen* commands) ──────────────────────
        -- scale       = mesh scale applied to every greenscreen tile (1.0 = default,
        --               2.0 = twice as big). Uses the entity-matrix scale trick so
        --               it visibly resizes the prop. Also useful alongside tileCols.
        -- tuneZOffset = extra vertical offset applied to the whole backdrop, on top
        --               of zOffset. /vehgreenup and /vehgreendown adjust this live.
        -- Spawn a live prop with /vehgreen, tune it, then /vehgreenpos and paste the
        -- printed fixedCoords / scale / tuneZOffset back here.
        scale = 3.0,
        -- Note: the tuned +3.75 height is already baked into fixedCoords.z above
        -- (the /vehgreenpos position was captured after the up-nudge), so the extra
        -- runtime offset must be 0 here to avoid raising the backdrop twice.
        tuneZOffset = 0.0,

        -- prop_ld_greenscreen_01 should already be upright.
        rotation = vec3(0.0, 0.0, 0.0),
        headingOffset = 0.0,
        collision = false,
        fallbackDrawBox = true,
    },
}

Config.Accounts = {
    ['bank'] = 'bank',
    ['cash'] = 'money',
}


-- Inventory icon capture for /clothingadmin.
-- For transparent icons, capture in front of a solid green background/greenscreen.
-- The NUI removes the backdrop and the server writes transparent images into this
-- resource. Nothing in the capture path calls RCore or an external HTTP API.

Config.IconCapture = {
    enabled = true,
    resource = 'nv_cloth',
    folder = 'generated_images',
    -- One clothing item = exactly one saved photo. Only the PNG published into
    -- cm-items (where cm-inventory's clothing image resolver expects it) is
    -- kept; no nv_cloth/generated_images working copy and no .webp companion
    -- are written. Set keepLocalCopy = true to bring back the local png/webp
    -- working copy for debugging.
    keepLocalCopy = false,
    catalogImageResource = 'cm-items',
    catalogImageFolder = 'ui/images/clothing/custom',
    catalogImagePrefix = 'custom',
    formats = { png = true, webp = false },
    webpQuality = 0.94,

    -- Build 2.19: every successful capture also writes a clothing catalog record
    -- so the item shows up in the /clothingstore manager. New records are saved
    -- UNPUBLISHED (enabled = false); nothing reaches the player store until an
    -- admin publishes it in /clothingstore. Retakes of an already-published item
    -- keep its publish state, price, label, and org assignment.
    catalogSync = true,

    -- Every automatic shot uses a fresh local freemode ped of the requested sex.
    -- The real player is hidden but never model-swapped or stripped.
    dedicatedCapturePed = true,

    -- Single-pass native ghost capture. Requires the capture client to accept
    -- `allowEmptyHeadDrawable true`: head/body/hair are made empty, only the
    -- selected component/prop is applied, and exactly ONE screenshot is taken.
    -- There is deliberately no body-subtraction or baseline fallback.
    isolationMode = 'native_ghost',
    isolateEveryCategory = false,
    maxRetries = 2,
    retryDelay = 650,
    captureCategories = {
        'torso', 'tshirt', 'pants', 'shoes', 'hat', 'glasses',
        'earrings', 'chains', 'bags', 'watches', 'bracelets', 'armor',
    },
    width = 512,
    height = 512,
    padding = 18,

    -- Clean daylight screenshot mode.
    -- This is applied only while screenshot-basic is taking the admin icon.
    -- It keeps the scene bright and stable and reduces shadow/ambient-occlusion marks.
    lighting = {
        enabled = true,
        hour = 12,
        minute = 0,
        second = 0,
        weather = 'EXTRASUNNY',
        timecycle = 'neutral',
        timecycleStrength = 0.0,
        noPedBlobShadow = true,
        suppressCascadeShadows = true,
        applyEveryFrame = true,
        -- The ped's component INDEX updates instantly on SetPedComponentVariation,
        -- but the streamed mesh/texture for that item can still take a moment to
        -- finish loading -- too short a wait here occasionally screenshots the
        -- previous garment even though the index already reads correctly.
        waitBeforeScreenshot = 1400,
    },

    -- NUI image processor.
    -- First removes the green/blue/magenta/white/black background, then automatically
    -- trims to the visible clothing pixels. squareOutput keeps all saved icons the same
    -- 512x512 size while still auto-cropping/centering the clothing item inside it.
    autoCrop = {
        enabled = true,
        floodFillBackground = true, -- removes shadowed green backdrop connected to crop edges
        removeLoosePixels = true,
        loosePixelPasses = 1,
        squareOutput = true,
        outputWidth = 512,
        outputHeight = 512,
        outputPadding = 18,
        minAlpha = 12,
        minItemRatio = 0.025,
    },

    -- Capture uses the admin airport studio prop backdrop when /clothingadmin is open.
    -- The DrawBox wall is now only a fallback if the configured prop model fails to load.
    studioCoords = Config.AdminStudio.StudioCoords or Config.DefaultDressingRoom,
    forceHeading = 180.0,
    wall = {
        enabled = true,
        width = 8.5,
        height = 5.4,
        zOffset = 0.55,
        distanceBehindPed = 0.85,
        colorWallDistanceBehindPed = 3.00,
        thickness = 0.08,
        r = 0,
        g = 255,
        b = 0,
        a = 255,
        floor = false,
    },

    chroma = {
        enabled = true,
        -- Conservative chroma key: remove only true greenscreen pixels, not dark/blue clothing.
        minGreen = 95,
        dominance = 1.35,
        greenMargin = 35,
        maxRed = 130,
        maxBlue = 150,
        soften = true,
        edgeTolerance = 0,
        -- Helps remove green shadows on the backdrop without needing harsh lighting.
        -- The NUI uses this mainly with edge flood-fill so green clothing is safer.
        shadowKey = true,
        shadowMinGreen = 35,
        shadowDominance = 1.10,
        shadowGreenMargin = 8,
    },

    -- Category-specific capture presets used by admin auto image save.
    -- view: front/back/left/right/front-left/front-right/back-left/back-right.
    -- viewAngle: an EXACT rotation offset (degrees) applied to the ped so the item
    --            faces the fixed camera the same way for every drawable. This is
    --            Option B: the camera never moves per item; only the ped rotates.
    --            When set, viewAngle overrides `view`. Angles below are adapted
    --            from the reference greenscreener's per-component rotations.
    presets = {
        torso    = { camera = 'body', view = 'front', viewAngle =   0.0, zOffset =  0.00, padding = 10 },
        tshirt   = { camera = 'body', view = 'front', viewAngle =   0.0, zOffset =  0.00, padding = 10 },
        armor    = { camera = 'body', view = 'front', viewAngle =   0.0, zOffset =  0.00, padding = 10 },
        pants    = { camera = 'body', view = 'front', viewAngle =   0.0, zOffset =  0.02, padding = 8  },
        -- A slight three-quarter turn exposes both the toe and side profile while
        -- keeping the pair centred. Straight-on hid too much of many shoe models.
        shoes    = { camera = 'feet', view = 'front', viewAngle = -18.0, zOffset = -0.02, padding = 8  },
        hat      = { camera = 'face', view = 'front', viewAngle =   0.0, zOffset =  0.00, padding = 8  },
        glasses  = { camera = 'face', view = 'front', viewAngle =   0.0, zOffset =  0.00, padding = 6  },
        -- Ears/watches/bracelets present the item at a precise diagonal so the
        -- accessory faces the camera and the supporting limb is turned mostly out
        -- of frame (then cropped). Tune viewAngle if an item sits slightly off.
        earrings = { camera = 'face', view = 'front', viewAngle =   0.0, zOffset =  0.00, padding = 6  },
        chains   = { camera = 'body', view = 'front', viewAngle =   0.0, zOffset =  0.02, padding = 6  },
        bags     = { camera = 'body', view = 'back',  viewAngle = 180.0, zOffset =  0.00, padding = 10, sharedGender = true },
        -- OP-style prop presentation: watches are rotated so the outside of the
        -- left wrist faces the fixed camera; bracelets stay front-facing. Their
        -- capture cameras aim at the real wrist bones below.
        watches  = { camera = 'body', view = 'right', viewAngle = -90.0, zOffset =  0.00, padding = 6  },
        bracelets = { camera = 'body', view = 'front', viewAngle =   0.0, zOffset = 0.00, padding = 6  },
    },

    -- Normal /clothingadmin browsing cameras. These are deliberately wider than
    -- the inventory-icon cameras below: the middle preview character remains easy
    -- to inspect while each accessory still gets the correct side/back angle.
    -- viewAngle rotates only the ped; the preview camera stays on the fixed studio axis.
    previewCameras = {
        torso    = { dist = 4.35, z =  0.18, fov = 38.0, viewAngle =   0.0 },
        tshirt   = { dist = 4.35, z =  0.18, fov = 38.0, viewAngle =   0.0 },
        armor    = { dist = 4.20, z =  0.22, fov = 38.0, viewAngle =   0.0 },
        chains   = { dist = 3.20, z =  0.34, fov = 32.0, viewAngle =   0.0 },
        pants    = { dist = 3.90, z = -0.35, fov = 38.0, viewAngle =   0.0 },
        shoes    = { dist = 3.10, z = -0.82, fov = 34.0, viewAngle = -18.0 },
        bags     = { dist = 4.45, z =  0.20, fov = 40.0, viewAngle = 180.0 },
        hat      = { dist = 2.60, z =  0.72, fov = 32.0, viewAngle =   0.0 },
        glasses  = { dist = 2.25, z =  0.65, fov = 28.0, viewAngle =   0.0 },
        earrings = { dist = 2.20, z =  0.64, fov = 27.0, viewAngle = -78.0 },
        watches  = { dist = 3.00, z =  0.12, fov = 32.0, viewAngle =  70.0 },
        bracelets = { dist = 3.00, z = 0.12, fov = 32.0, viewAngle = -70.0 },
    },

    -- ── Per-category capture CAMERA framing ──────────────────────────────
    -- This is what makes "pant shot frames the pant, shoe shot frames the shoe".
    -- Each entry positions the capture camera on that item's body region:
    --   dist = camera distance from the ped (smaller = closer / bigger item)
    --   z    = height the camera AIMS at, relative to the ped root
    --          (positive = higher up = head/torso, negative = lower = legs/feet)
    --   fov  = zoom (smaller fov = tighter/more zoomed in)
    -- Exact player/camera compositions transcribed from For glass.docx. The
    -- optional live editor saves a DB override when a custom item needs adjustment.
    -- playerOffsetX/Y are converted to camera-target offsets at capture time.
    captureCameras = {
        torso     = { dist = 2.41, z =  0.22, fov = 45.0, poseHeading = 319.0, poseLift =  0.08, camHeading = 332.4 },
        tshirt    = { dist = 2.74, z =  0.22, fov = 40.0, poseHeading = 328.4, poseLift =  0.08, camHeading = 328.4 },
        armor     = { dist = 2.41, z =  0.22, fov = 45.0, poseHeading = 319.0, poseLift =  0.08, camHeading = 332.4 },
        chains    = { dist = 1.80, z =  0.52, fov = 38.0, poseHeading = 328.4, poseLift =  0.08, camHeading = 324.4, playerOffsetX =  0.04, playerOffsetY = -0.03 },
        pants     = { dist = 4.28, z = -0.51, fov = 42.0, poseHeading = 323.0, poseLift =  0.08, camHeading = 328.4 },
        shoes     = { dist = 1.96, z = -0.90, fov = 34.0, poseHeading = 295.0, poseLift =  0.08, camHeading = 328.4 },
        bags      = { dist = 1.50, z =  0.30, fov = 45.0 }, -- component 5; back view
        hat       = { dist = 3.69, z =  0.70, fov = 26.0, poseHeading = 336.0, poseLift =  0.08, camHeading = 340.4, playerOffsetX =  0.05, playerOffsetY = -0.02 },
        glasses   = { dist = 1.42, z =  0.66, fov = 22.0, poseHeading = 335.0, poseLift =  0.00, camHeading = 328.4 },
        earrings  = { dist = 1.18, z =  0.58, fov = 26.0, poseHeading =  43.0, poseLift =  0.00, camHeading = 336.4 },
        watches   = { dist = 2.18, z =  0.19, fov = 24.0, poseHeading =  57.0, poseLift = -0.24, camHeading = 336.4, playerOffsetX = -0.25, playerOffsetY =  0.17 },
        bracelets = { dist = 2.18, z =  0.19, fov = 24.0, poseHeading =  57.0, poseLift = -0.24, camHeading = 336.4, playerOffsetX = -0.25, playerOffsetY =  0.17 },
    },

}

Config.Prices = {
    ['tshirt'] = 10,
    ['pants'] = 15,
    ['shoes'] = 20,
    ['hat'] = 20,
    ['torso'] = 50,
    -- Arms/body mesh is preview-only. It is saved inside torso metadata, not sold separately.
    ['arms'] = 0,
    ['chains'] = 30,
    ['glasses'] = 10,
    ['bags'] = 20,
    ['earrings'] = 30,
    ['watches'] = 40,
    ['bracelets'] = 35,
    -- Server-authoritative fallback price when a captured armor row has no
    -- price of its own yet. Matches cm-gunstore's Config.DefaultArmor.price so
    -- a freshly captured vest doesn't default to free before an admin sets one.
    ['armor'] = 3500,
}


-- ── Automatic pricing (economy-balanced) ─────────────────────────────────
-- Anchored to your earn rate: ~50k per 4h played  ->  ~12,500/hour (~208/min).
-- Store (base-game) clothing is a small sink: seconds-to-minutes of play.
-- Add-on clothing is a flex: roughly 30 minutes to ~4 hours of play, and is kept
-- OUT of the public store by default (still fully capturable in the admin panel).
Config.Economy = {
    enabled = true,          -- master switch for auto-price suggestions
    hourlyEarn = 12500,      -- documentation anchor only

    -- Base-game (store) price per category — cheap.
    storePrices = {
        tshirt = 200,  glasses = 250, hat = 350,  pants = 500,  shoes = 750,
        torso  = 1200, chains  = 1500, bags = 1800, earrings = 1200, watches = 3000,
        armor  = 0,
    },
    -- Add-on (exclusive) price per category — a flex.
    addonPrices = {
        tshirt = 6000,  glasses = 8000,  hat = 9000,  pants = 12000, shoes = 15000,
        torso  = 22000, chains  = 28000, bags = 18000, earrings = 20000, watches = 45000,
        armor  = 0,
    },

    -- An item is treated as ADD-ON when its drawable index is >= the number here.
    -- Set each to your VANILLA drawable count for that category (what
    -- GetNumberOfPedDrawableVariations returned BEFORE you streamed your add-on
    -- packs). Leave a category unset to treat all of its items as store.
    -- You can split by gender: torso = { male = 180, female = 200 }.
    -- Tip: open the admin panel and browse to the first add-on item; the panel
    -- shows the drawable index and Store/Add-on flag so you can read the boundary.
    addonStartsAt = {
        -- torso = 200, pants = 150, shoes = 120, ...
    },

    -- Where add-on items go. 'hidden' = not shown in the public store.
    addonDestination = 'hidden',
}



-- CM clothing purchase behaviour
Config.AutoOpenInventoryAfterPurchase = false
Config.TryBeforeBuySeconds = 60
Config.ClothingStore = Config.ClothingStore or {}
Config.ClothingStore.EnableCheckoutConfirm = true
Config.ClothingStore.EnableNpcSpeech = true
Config.ClothingStore.NpcGreetingCooldown = 18000
Config.ClothingStore.DefaultRestrictionText = 'Members only'

-- Admin price presets shown in the clothing creator UI.
Config.PricePresets = {
    default = Config.Prices,
    economy = { tshirt = 8, torso = 35, pants = 12, shoes = 15, hat = 12, chains = 20, glasses = 8, bags = 18, earrings = 18, watches = 25 },
    standard = { tshirt = 15, torso = 60, pants = 25, shoes = 30, hat = 25, chains = 40, glasses = 20, bags = 35, earrings = 35, watches = 50 },
    premium = { tshirt = 35, torso = 120, pants = 70, shoes = 85, hat = 65, chains = 100, glasses = 70, bags = 120, earrings = 90, watches = 150 },
    luxury = { tshirt = 75, torso = 250, pants = 160, shoes = 220, hat = 150, chains = 300, glasses = 180, bags = 350, earrings = 220, watches = 500 },
}

-- Bag inventory capacity levels saved in catalog metadata.
-- Bag levels match cm-inventory's expected metadata key: metadata.bagLevel.
-- cm-inventory clamps bag levels to 0-4, so clothing admin only offers 1-4.
Config.BagLevels = {
    [1] = { label = 'Bag Level 1', backpackSlots = 5,  maxWeight = 30000 },
    [2] = { label = 'Bag Level 2', backpackSlots = 10, maxWeight = 40000 },
    [3] = { label = 'Bag Level 3', backpackSlots = 15, maxWeight = 50000 },
    [4] = { label = 'Bag Level 4', backpackSlots = 20, maxWeight = 65000 },
}

-- ── /clothingstore manager + organisation lockers (build 2.19) ───────────
-- /clothingstore (admin only): browse every captured clothe with its image,
-- publish/unpublish to the player store, set price, assign to an org, preview
-- on the ped (male + female), and jump back into /clothingadmin to retake the
-- image.
Config.ManageCommand = 'clothingstore'

-- Clothes assigned to an org are stored under shop 'org_<key>' with
-- required_job = <key>. Org members open their locker with /orgcloset (or the
-- command below). Add more orgs by adding keys here; the /clothingstore org
-- dropdown reads this table.
Config.OrgShopCommand = 'orgcloset'
Config.OrgShops = {
    ['ems']    = { label = 'EMS Locker' },
    ['police'] = { label = 'Police Locker' },
    ['sahp']   = { label = 'SAHP Locker' },
    ['sheriff'] = { label = 'Sheriff Locker' },
    ['fib']     = { label = 'FIB Locker' },
    ['army']    = { label = 'Army Locker' },
}

-- Every clothing storefront is a LOCATION under the single 'clothes' shop, not a
-- shop of its own. The Config.Shops key is also the catalog shop name that
-- clothing_catalog rows are saved under (see allManagedShopNames in
-- sv_cloth.lua), so splitting the storefronts into separate keys would point
-- each one at a catalog shop with no rows and every store would open empty.
-- Per-location label/clerk/categories live on the location instead.
Config.Shops = {
    ['clothes'] = {
        label = 'Clothing',
        blip = { style = 73, color = 81, size = 0.5 },
        -- Player is moved here when the clothing UI opens.
        dressingRoom = Config.DefaultDressingRoom,
        -- Fallback for a location that sets no categories of its own.
        categories = {
            'hat',
            'torso',
            -- Preview-only: lets players/admins pick the correct upper-body/arms mesh for jackets.
            -- buyCommon() filters this out and stores it inside torso metadata.
            'arms',
            'tshirt',
            'pants',
            'shoes',
            'glasses',
            -- Only ever shows rows an admin explicitly flagged "regular clothing" in
            -- /clothingstore (treatAsClothing). Real vests use shop='armor' and never
            -- appear here -- see BLOCKED_CATEGORIES/normaliseItem in sv_cloth.lua.
            'armor',
        },
        -- pos is the storefront/blip point. `npc` is where the clerk actually
        -- stands, as vec4(x, y, z, heading) -- set it to a spot behind the
        -- counter. While it is nil the clerk stands on pos, which is the doorway.
        -- Stand where you want the clerk and run /clothingnpcpos to get the line.
        locations = {
            {
                id = 'strawberry', label = 'Discount Store - Strawberry',
                pos = vec3(71.835, -1399.081, 29.376), npc = nil,
                npcModel = 's_f_y_shop_low', npcName = 'Maya Cortez',
                npcDialog = 'Everything on the racks is marked down. Yell if you need a size.',
                categories = { 'torso', 'arms', 'tshirt', 'pants', 'shoes' },
            },
            {
                id = 'hawick', label = 'Suburban - Hawick',
                pos = vec3(-708.791199, -160.114288, 37.401489), npc = nil,
                npcModel = 's_f_y_shop_mid', npcName = 'Priya Raines',
                npcDialog = 'New season just landed. The fitting rooms are free if you want to try something.',
                categories = { 'torso', 'arms', 'tshirt', 'pants', 'shoes', 'glasses' },
            },
            {
                id = 'rockford', label = 'Ponsonbys - Rockford',
                pos = vec3(-167.863, -298.969, 39.743), npc = nil,
                npcModel = 's_f_m_shop_high', npcName = 'Vivienne Marchetti',
                npcDialog = 'Welcome to Ponsonbys. Everything here is hand finished -- take your time.',
                categories = { 'torso', 'arms', 'pants', 'shoes', 'chains', 'watches', 'bracelets', 'earrings' },
            },
            {
                id = 'textile', label = 'Discount Store - Textile City',
                pos = vec3(428.694, -800.106, 29.511), npc = nil,
                npcModel = 's_f_y_shop_low', npcName = 'Dana Whitlock',
                npcDialog = 'Cheapest prices downtown. Bags are in the back corner.',
                categories = { 'torso', 'arms', 'pants', 'shoes', 'bags' },
            },
            {
                id = 'vespucci_beach', label = 'Binco - Vespucci Beach',
                pos = vec3(-829.413, -1073.710, 11.348), npc = nil,
                npcModel = 's_f_y_shop_low', npcName = 'Kiara Nunez',
                npcDialog = 'Beach fits, cheap and cheerful. Take a look around.',
                categories = { 'torso', 'arms', 'pants', 'shoes', 'bags' },
            },
            {
                id = 'del_perro', label = 'Ponsonbys - Del Perro',
                pos = vec3(-1447.797, -242.461, 49.840), npc = nil,
                npcModel = 's_f_m_shop_high', npcName = 'Camille Duval',
                npcDialog = 'Good afternoon. Shall I show you the new arrivals?',
                categories = { 'torso', 'arms', 'pants', 'shoes', 'chains', 'watches', 'bracelets', 'earrings' },
            },
            {
                id = 'paleto', label = 'Discount Store - Paleto',
                pos = vec3(11.632, 6514.224, 31.897), npc = nil,
                npcModel = 's_f_y_shop_low', npcName = 'Ruth Baker',
                npcDialog = 'Not much choice this far north, but the prices are honest.',
                categories = { 'torso', 'arms', 'pants', 'shoes' },
            },
            {
                id = 'alta', label = 'Suburban - Alta',
                pos = vec3(123.646, -219.440, 54.577), npc = nil,
                npcModel = 's_f_y_shop_mid', npcName = 'Elena Voss',
                npcDialog = 'Take your time. Sunglasses are by the register.',
                categories = { 'torso', 'arms', 'pants', 'shoes', 'glasses' },
            },
            {
                id = 'grapeseed', label = 'Discount - Grapeseed',
                pos = vec3(1696.291, 4829.312, 42.083), npc = nil,
                npcModel = 's_f_y_shop_low', npcName = 'Sally Kemp',
                npcDialog = 'Work clothes mostly, and they last. Holler if you need a hand.',
                categories = { 'torso', 'arms', 'pants', 'shoes', 'bags' },
            },
            {
                id = 'harmony', label = 'Discount - Harmony',
                pos = vec3(618.093, 2759.629, 42.108), npc = nil,
                npcModel = 's_f_y_shop_low', npcName = 'Wanda Pierce',
                npcDialog = 'Helmets are by the door. Everything else is on the racks.',
                categories = { 'torso', 'arms', 'pants', 'shoes', 'hat' },
            },
            {
                id = 'sandy', label = 'Discount - Sandy Shores',
                pos = vec3(1190.550, 2713.441, 38.242), npc = nil,
                npcModel = 's_f_y_shop_low', npcName = 'Birdie Hollis',
                npcDialog = 'Dust gets into everything out here. Buy dark colours.',
                categories = { 'torso', 'arms', 'pants', 'shoes' },
            },
            {
                id = 'south_rockford', label = 'Suburban - South Rockford',
                pos = vec3(-1193.429, -772.262, 17.344), npc = nil,
                npcModel = 's_f_y_shop_mid', npcName = 'Tasha Lin',
                npcDialog = 'Everything is organised by size. Accessories are at the counter.',
                categories = { 'torso', 'arms', 'pants', 'shoes', 'chains', 'watches', 'bracelets', 'earrings' },
            },
            {
                id = 'chumash', label = 'Suburban - Chumash',
                pos = vec3(-3172.496, 1048.133, 20.883), npc = nil,
                npcModel = 's_f_y_shop_mid', npcName = 'Nora Vance',
                npcDialog = 'Quiet today. Plenty of room to browse.',
                categories = { 'torso', 'arms', 'pants', 'shoes', 'bags' },
            },
            {
                id = 'route68_north', label = 'Discount - Route 68 North',
                pos = vec3(-1108.441, 2708.923, 19.127), npc = nil,
                npcModel = 's_f_y_shop_low', npcName = 'Josie Pratt',
                npcDialog = 'Middle of nowhere, but we stock the basics. Look around.',
                categories = { 'torso', 'arms', 'pants', 'shoes', 'glasses' },
            },
        },
    },
    ['accessories'] = {
        coords = {
            vec3(80.004395, -1389.494507, 29.364136),
        },
        label = 'Accessoires',
        blip = { style = 73, color = 81, size = 0.5 },
        dressingRoom = Config.DefaultDressingRoom,
        exitCoords = vec4(80.0, -1389.5, 29.36, 0.0),
        categories = {
            -- Headwear and glasses now live in the main clothing store. Bags are admin/hidden only.
            -- This shop is only for true accessories.
            'earrings',
            'chains',
            'watches',
            'bracelets',
        }
    }
}

Config.Translations = {
    ['fr'] = {
        ['tshirt'] = 'T-SHIRT',
        ['pants'] = 'PANTALON',
        ['shoes'] = 'CHAUSSURES',
        ['hat'] = 'CHAPEAU',
        ['torso'] = 'TORSE',
        ['arms'] = 'BRAS / CORPS',
        ['chains'] = 'COLLIER',
        ['glasses'] = 'LUNETTES',
        ['bags'] = 'SAC',
        ['earrings'] = 'BOUCLES D\'OREILLES',
        ['watches'] = 'MONTRES',
        ['bracelets'] = 'BRACELETS',
        ['bproof'] = 'GILET PB',
        ['cart'] = 'PANIER',
        ['buy'] = 'ACHETER',
        ['cash'] = 'CASH',
        ['bank'] = 'BANQUE',
        ['variations'] = 'TEXTURES',
        ['no-selection'] = 'Aucune selection',
        ['no-preview'] = 'Aucune preview',
        ['editing-name'] = 'MODIFIER LE NOM',
        ['save-name'] = 'NOM DE LA TENUE',
        ['save-name-prompt'] = 'Entrez le nom de la tenue',
        ['invalid-category'] = 'Catégorie de vêtement invalide.',
        ['no-saved-outfit'] = 'Aucune tenue sauvegardée pour cette catégorie.',
        ['outfit-applied'] = 'Tenue appliquée avec succès.',
        ['invalid-outfit'] = 'Tenue invalide.',
        ['help-notif'] = 'Appuie sur ~INPUT_CONTEXT~ pour ouvrir la boutique',
        ['no-cloth-selected'] = '~r~Aucun vêtement sélectionné.',
        ['account-error'] = '~r~Account %s not found. For paiement in %s',
        ['not-enough-money'] = 'Vous n\'avez pas assez ~r~d\'argent.',
        ['save-error'] = 'Erreur lors de l\'enregistrement de la tenue.',
        ['save-success'] = 'Tenue enregistrée avec ~g~succès.',
        ['delete-error'] = 'Erreur lors de la suppression de la tenue.',
        ['delete-success'] = 'Tenue supprimée avec succès.',
        ['edit-name-success'] = 'Nom de la tenue modifié avec succès.',
        ['edit-name-error'] = 'Erreur lors de la modification du nom de la tenue.',
        ['outfit-not-found'] = 'Tenue ~r~introuvable.',
        ['purchase-success'] = 'Merci pour votre achat.',
    },

    ['en'] = {
        ['tshirt'] = 'T-SHIRT',
        ['pants'] = 'PANTS',
        ['shoes'] = 'SHOES',
        ['hat'] = 'HAT',
        ['torso'] = 'TORSO',
        ['arms'] = 'ARMS / BODY',
        ['chains'] = 'CHAIN',
        ['glasses'] = 'GLASSES',
        ['bags'] = 'BAG',
        ['earrings'] = 'EARRINGS',
        ['watches'] = 'WATCHES',
        ['bracelets'] = 'BRACELETS',
        ['bproof'] = 'BODY ARMOR',
        ['cart'] = 'CART',
        ['buy'] = 'BUY',
        ['cash'] = 'CASH',
        ['bank'] = 'BANK',
        ['variations'] = 'TEXTURES',
        ['no-selection'] = 'No selection',
        ['no-preview'] = 'No preview',
        ['editing-name'] = 'EDIT NAME',
        ['save-name'] = 'OUTFIT NAME',
        ['save-name-prompt'] = 'Enter the outfit name',
        ['invalid-category'] = 'Invalid clothing category.',
        ['no-saved-outfit'] = 'No saved outfit for this category.',
        ['outfit-applied'] = 'Outfit applied successfully.',
        ['invalid-outfit'] = 'Invalid outfit.',
        ['help-notif'] = 'Press ~INPUT_CONTEXT~ to open the shop',
        ['no-cloth-selected'] = '~r~No clothing selected.',
        ['account-error'] = '~r~Account %s not found. For payment in %s',
        ['not-enough-money'] = 'You don\'t have enough ~r~money.',
        ['save-error'] = 'Error while saving outfit.',
        ['save-success'] = 'Outfit saved ~g~successfully.',
        ['delete-error'] = 'Error while deleting outfit.',
        ['delete-success'] = 'Outfit deleted successfully.',
        ['edit-name-success'] = 'Outfit name updated successfully.',
        ['edit-name-error'] = 'Error while editing outfit name.',
        ['outfit-not-found'] = 'Outfit ~r~not found.',
        ['purchase-success'] = 'Thank you for your purchase.',
    }
}
