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
-- The NUI removes green pixels and saves a transparent PNG into cm-items/ui/images/clothing/custom/.
Config.IconCapture = {
    enabled = true,
    resource = 'cm-items',
    folder = 'ui/images/clothing/custom',
    catalogImagePrefix = 'custom',
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
        waitBeforeScreenshot = 900,
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
        torso    = { camera = 'body', view = 'front', zOffset = 0.00, padding = 10 },
        tshirt   = { camera = 'body', view = 'front', zOffset = 0.00, padding = 10 },
        pants    = { camera = 'body', view = 'front', zOffset = 0.05, padding = 8  },
        shoes    = { camera = 'feet', view = 'front', zOffset = 0.00, padding = 8  },
        hat      = { camera = 'face', view = 'front', zOffset = 0.00, padding = 8  },
        glasses  = { camera = 'face', view = 'front', zOffset = 0.00, padding = 6  },
        -- Ears/watches/bracelets present the item at a precise diagonal so the
        -- accessory faces the camera and the supporting limb is turned mostly out
        -- of frame (then cropped). Tune viewAngle if an item sits slightly off.
        earrings = { camera = 'face', view = 'right', viewAngle = -122.5, zOffset = 0.00, padding = 6  },
        chains   = { camera = 'body', view = 'front', zOffset = 0.00, padding = 6  },
        bags     = { camera = 'body', view = 'back',  zOffset = 0.00, padding = 10, sharedGender = true },
        watches  = { camera = 'body', view = 'left',  viewAngle = 59.0, zOffset = 0.00, padding = 6  },
    },

    -- ── Per-category capture CAMERA framing ──────────────────────────────
    -- This is what makes "pant shot frames the pant, shoe shot frames the shoe".
    -- Each entry positions the capture camera on that item's body region:
    --   dist = camera distance from the ped (smaller = closer / bigger item)
    --   z    = height the camera AIMS at, relative to the ped root
    --          (positive = higher up = head/torso, negative = lower = legs/feet)
    --   fov  = zoom (smaller fov = tighter/more zoomed in)
    -- Starting values are adapted from Bentix's greenscreener per-component
    -- settings. Tweak these live and re-capture; you don't need to touch any Lua.
    captureCameras = {
        torso    = { dist = 2.95, z =  0.26, fov = 36.0 },
        tshirt   = { dist = 2.90, z =  0.28, fov = 36.0 },
        armor    = { dist = 2.90, z =  0.28, fov = 36.0 },
        chains   = { dist = 2.10, z =  0.40, fov = 26.0 },
        pants    = { dist = 2.85, z = -0.40, fov = 36.0 },
        shoes    = { dist = 1.80, z = -0.90, fov = 26.0 },
        bags     = { dist = 3.05, z =  0.26, fov = 38.0 },
        hat      = { dist = 1.90, z =  0.64, fov = 24.0 },
        glasses  = { dist = 1.55, z =  0.60, fov = 18.0 },
        earrings = { dist = 1.45, z =  0.62, fov = 16.0 },
        -- Watch: very tight and close on the wrist so the forearm/hand fall outside
        -- the frame and are cropped away, leaving just the watch (Option B).
        watches  = { dist = 1.10, z =  0.05, fov = 14.0 },
    },

    -- ── Head-prop capture: force freemode model ──────────────────────────
    -- Hat/glasses/earrings hide the head via the streamed invisible-head file,
    -- which only overrides mp_m_freemode_01 / mp_f_freemode_01. The capture code
    -- re-asserts the invisible head before each shot, which normally suffices.
    -- If the head STILL shows on head-prop shots, set this true to force the ped
    -- to the matching freemode model during capture (most reliable, but resets
    -- appearance during the shot and restores after). Leave false unless needed.
    forceFreemodeForHeadProps = false,

    -- ── Per-category ground lift ─────────────────────────────────────────
    -- Raises the ped vertically during capture so items don't sink into the
    -- floor. Mainly for shoes (the feet sit at ground level and can clip). The
    -- manual pose bar can also lift live with the ▲/▼ buttons; this is the
    -- default applied automatically. Value in metres.
    groundLift = {
        shoes = 0.35,
    },


    -- ── Streamed grey support body for accessory/icon capture ─────────────────
    -- These use the stream files you added:
    --   head_000_r.ydd / head_diff_000_a_whi.ytd
    --   uppr_015_r.ydd / uppr_diff_015_a_whi.ytd
    --   lowr_015_r.ydd / lowr_diff_015_a_whi.ytd
    -- Only accessories + lower-body categories use them. T-shirts / torso keep
    -- the old pure-item logic unchanged.
    supportModels = {
        -- These streamed files are female-only. Male capture deliberately has no
        -- support model entry and therefore falls back to the previous logic.
        female = {
            categories = {
                hat      = { head = { drawable = 0, texture = 0, hair = -1 } },
                glasses  = { head = { drawable = 0, texture = 0, hair = -1 } },
                earrings = { head = { drawable = 0, texture = 0, hair = -1 } },
                mask     = { head = { drawable = 0, texture = 0, hair = -1 } },

                watches  = { [3] = { drawable = 15, texture = 0 } },
                chains   = { [3] = { drawable = 15, texture = 0 } },
                bags     = { [3] = { drawable = 15, texture = 0 } },

                pants    = { [4] = { drawable = 15, texture = 0 } },
                shoes    = { [4] = { drawable = 15, texture = 0 } },
            }
        },
        male = {
            categories = {}
        }
    },

    -- ── Keep supporting body parts visible per category ──────────────────
    -- Items that sit ON the body (shoes on a foot, watch on a wrist) look wrong
    -- floating in empty space. For those, keep the supporting component visible
    -- at a neutral skin drawable instead of hiding it. Everything else still hides,
    -- and the head stays invisible unless a category sets head = true.
    --   [componentIndex] = neutralDrawable   (3 = arms/torso, 4 = legs, 6 = feet)
    --   head = true                          (show a normal head — also shows the face)
    --   hair = <drawable>                    (only used when head = true; -1 = bald)
    keepBody = {
        -- Pure item capture for outerwear, pants and bags: do NOT keep the mannequin body.
        -- This leaves only the target clothing visible after the head-hide / ghost pass.
        torso    = { },
        -- T-shirt: capture like outerwear — item only, no mannequin body.
        tshirt   = { },
        armor    = { [3] = 0, [4] = 0, [6] = 0, [8] = 0 },
        pants    = { },
        bags     = { },
        -- Shoes: the shoe IS component 6 (feet) and is always shown as the target.
        -- Do NOT keep the legs (component 4) — leg drawable 0 renders as pants/
        -- underwear, which is the "pants" that was showing in shoe shots. With legs
        -- hidden, only the foot/shoe shows (bare shin above it at most), and the low
        -- shoe camera + crop trims the rest.
        shoes    = { },
        -- Watch: prop-only. Hide the arm (component 3 -> -1) so ONLY the watch
        -- renders, with no hand/forearm skin. The watch stays attached to the wrist
        -- bone (which still exists even with the arm mesh hidden), so it floats
        -- alone. On the rare model where -1 leaves a bare-arm fallback, the tight
        -- watch camera (captureCameras.watches) still crops the stub out.
        watches  = { },
        -- Chains / necklaces (component 7) sit on the upper chest. Keep a BARE
        -- torso skin so the chain has a neck/chest to rest on, but HIDE the
        -- undershirt/shirt (8) and top (11) so no shirt covers it. If your torso
        -- drawable 0 still shows a shirt on your build, try a different nude value
        -- here (e.g. [3] = 15) — it's the bare-skin torso drawable.
        chains   = { [3] = 0 },
        -- Hats, glasses and earrings attach to the HEAD BONE, which still exists
        -- even when the head mesh is invisible. So we hide the head (head not kept)
        -- and the prop renders alone, floating where the head would be — no head in
        -- the icon. Set head = true instead if you WANT a visible head for context.
        hat      = { },
        glasses  = { },
        earrings = { },
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

Config.Shops = {
    ['clothes'] = {
        coords = {
            vec3(72.658409118652, -1398.9842529297, 29.376123428345),
            vec3(4489.457031, -4452.023438, 4.171892),
            vec3(-703.94110107422, -152.1471862793, 37.415134429932),
            vec3(-168.08949279785, -298.69085693359, 39.73327255249),
            vec3(428.51501464844, -800.30999755859, 29.491121292114),
            vec3(-829.43786621094, -1073.8389892578, 11.328098297119),
            vec3(-1447.4333496094, -243.05351257324, 49.822105407715),
            vec3(11.785837173462, 6514.0327148438, 31.877853393555),
            vec3(121.41311645508, -225.09120178223, 54.557891845703),
            vec3(1695.9750976562, 4829.3217773438, 42.063121795654),
            vec3(617.74530029297, 2765.0300292969, 42.088153839111),
            vec3(1190.4202880859, 2713.3115234375, 38.222579956055),
            vec3(-1188.4792480469, -769.00695800781, 17.325212478638),
            vec3(-3174.9614257812, 1042.6502685547, 20.863206863403),
            vec3(-1108.4439697266, 2709.0046386719, 19.106767654419),
        },
        label = 'BINCO',
        blip = { style = 73, color = 81, size = 0.5 },
        -- Player is moved here when the clothing UI opens.
        dressingRoom = Config.DefaultDressingRoom,
        -- Player is returned here when the clothing UI closes.
        exitCoords = vec4(72.6, -1399.0, 29.3, 0.0),
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
        }
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
