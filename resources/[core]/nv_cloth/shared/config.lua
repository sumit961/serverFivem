Config = {}

Config.Framework = 'cm-core'
Config.Lang = 'fr'
Config.Inventory = 'cm-inventory'
Config.AppearanceRessource = 'native'
Config.Accounts = {
    ['bank'] = 'bank',
    ['cash'] = 'money',
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
        categories = {
            'torso',
            -- Preview-only: lets players pick the correct upper-body/arms mesh for jackets.
            -- buyCommon() filters this out and stores it inside torso metadata.
            'arms',
            'tshirt',
            'pants',
            'shoes',
        }
    },
    ['accessories'] = {
        coords = {
            vec3(80.004395, -1389.494507, 29.364136),
        },
        label = 'Accessoires',
        blip = { style = 73, color = 81, size = 0.5 },
        categories = {
            'hat',
            'glasses',
            'earrings',
            'chains',
            'bags',
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
