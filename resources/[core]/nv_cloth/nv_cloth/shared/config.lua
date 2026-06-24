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
    StudioCoords = vec4(-1341.6483, -2802.7166, 13.9449, 231.0469),
    LockPlayerToStudio = true,
    StripToDefaultNaked = true,
    -- Disabled by default so admin capture does not show any extra/naked NPC.
    -- Set this to 'same_as_player' if you want a reference mannequin beside the player.
    ReferencePedModel = false,
    ReferenceOffset = vec3(1.15, 0.20, 0.0),

    Backdrop = {
        enabled = true,
        -- Custom green prop. Put prop_ld_greenscreen_01.ydr in nv_cloth/stream/.
        model = 'prop_ld_greenscreen_01',
        pieces = 1,
        -- Keep the greenscreen fixed at the confirmed world position.
        fixedCoords = vec4(-1341.9189, -2802.7861, 14.5417, 52.0929),
        spacing = 1.55,
        distanceBehindPed = 1.25,
        zOffset = 0.0,
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
    },

    -- Category-specific capture presets used by admin auto image save.
    -- view: front/back/left/right. For bags, back view turns the ped while keeping the same camera/background.
    presets = {
        torso    = { camera = 'body', view = 'front', zOffset = 0.00, padding = 10 },
        tshirt   = { camera = 'body', view = 'front', zOffset = 0.00, padding = 10 },
        pants    = { camera = 'body', view = 'front', zOffset = 0.05, padding = 8  },
        shoes    = { camera = 'feet', view = 'front', zOffset = 0.28, padding = 8  },
        hat      = { camera = 'face', view = 'front', zOffset = 0.00, padding = 8  },
        glasses  = { camera = 'face', view = 'front', zOffset = 0.00, padding = 6  },
        earrings = { camera = 'face', view = 'right', zOffset = 0.00, padding = 6  },
        chains   = { camera = 'body', view = 'front', zOffset = 0.00, padding = 6  },
        bags     = { camera = 'body', view = 'back',  zOffset = 0.00, padding = 10, sharedGender = true },
        watches  = { camera = 'body', view = 'left',  zOffset = 0.00, padding = 6  },
    }
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
