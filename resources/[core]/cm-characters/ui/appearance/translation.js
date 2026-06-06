const translate = {
    create_character: 'CREATE YOUR CHARACTER',
    select_category: 'SELECT CATEGORY',
    height: 'CAMERA HEIGHT',
    rotate: 'CAMERA ROTATE',
    distance: 'CAMERA DISTANCE',
    save: 'SAVE & SPAWN',
    cancel: 'CANCEL',

    category: {
        parents: 'PARENTS',
        face: 'FACE',
        clothes: 'CLOTHES',
        clothesets: 'OUTFITS',
        hairs: 'HAIR',
        makeup: 'MAKEUP'
    },

    title_sex: "GENDER",
    sub_sex: "Slide to change",

    title_parents: 'PARENTS',
    sub_mom: 'Mother',
    sub_dad: 'Father',

    title_resemblance: 'RESEMBLANCE',
    sub_face_md_weight: 'Resemblance to parents',

    title_skin_md_weight: 'SKIN',
    sub_skin_md_weight: 'Skin tone mix',

    title_nose: 'NOSE',
    sub_nose_1: 'Nose width',
    sub_nose_2: 'Nose height',
    sub_nose_3: 'Nose length',
    sub_nose_4: 'Nose bridge height',
    sub_nose_5: 'Nose peak height',
    sub_nose_6: 'Nose twist',

    title_cheekbones: 'CHEEKBONES',
    sub_cheeks_1: 'Cheekbone height',
    sub_cheeks_2: 'Cheekbone width',
    sub_cheeks_3: 'Cheek width',

    title_lips: 'LIPS',
    sub_lip_thickness: 'Lip thickness',

    title_jaw: 'JAW',
    sub_jaw_1: 'Jaw width',
    sub_jaw_2: 'Jaw length',

    title_chin: 'CHIN',
    sub_chin_1: 'Chin height',
    sub_chin_2: 'Chin length',
    sub_chin_3: 'Chin width',
    sub_chin_4: 'Chin dimple',

    title_eye_color: 'EYES',
    sub_eye_color: 'Eye color',

    title_blemishes: 'BLEMISHES',
    sub_blemishes_1: 'Type',
    sub_blemishes_2: 'Intensity',

    title_complexion: 'COMPLEXION',
    sub_complexion_1: 'Type',
    sub_complexion_2: 'Intensity',

    title_sun: 'SUN DAMAGE',
    sub_sun_1: 'Type',
    sub_sun_2: 'Intensity',

    title_moles: 'MOLES & FRECKLES',
    sub_moles_1: 'Type',
    sub_moles_2: 'Intensity',

    title_tshirt: 'T-SHIRT',
    sub_tshirt_1: 'Style',
    sub_tshirt_2: 'Variant',

    title_torso: 'TORSO',
    sub_torso_1: 'Style',
    sub_torso_2: 'Variant',

    title_arms: 'ARMS',
    sub_arms: 'Style',
    sub_arms_2: 'Variant',

    title_pants: 'PANTS',
    sub_pants_1: 'Style',
    sub_pants_2: 'Variant',

    title_shoes: 'SHOES',
    sub_shoes_1: 'Style',
    sub_shoes_2: 'Variant',

    title_decals: 'DECALS',
    sub_decals_1: 'Style',
    sub_decals_2: 'Variant',

    title_mask: 'MASK',
    sub_mask_1: 'Style',
    sub_mask_2: 'Variant',

    title_bproof: 'VEST',
    sub_bproof_1: 'Style',
    sub_bproof_2: 'Variant',

    title_chain: 'CHAIN',
    sub_chain_1: 'Style',
    sub_chain_2: 'Variant',

    title_helmet: 'HAT',
    sub_helmet_1: 'Style',
    sub_helmet_2: 'Variant',

    title_glasses: 'GLASSES',
    sub_glasses_1: 'Style',
    sub_glasses_2: 'Variant',

    title_watches: 'WATCH',
    sub_watches_1: 'Style',
    sub_watches_2: 'Variant',

    title_bracelets: 'BRACELET',
    sub_bracelets_1: 'Style',
    sub_bracelets_2: 'Variant',

    title_bags: 'BAG',
    sub_bags_1: 'Style',
    sub_bags_2: 'Variant',

    title_ears: 'EARRINGS',
    sub_ears_1: 'Style',
    sub_ears_2: 'Variant',

    title_clothesets: 'OUTFITS',
    sub_clotheset: 'Select outfit',

    title_hair: 'HAIR',
    sub_hair_1: 'Style',
    sub_hair_2: 'Highlight',
    sub_hair_color_1: 'Primary color',
    sub_hair_color_2: 'Secondary color',

    title_beard: 'BEARD',
    sub_beard_1: 'Style',
    sub_beard_2: 'Opacity',
    sub_beard_3: 'Color',

    title_neck_thickness: 'NECK THICKNESS',
    sub_neck_thickness: 'Adjust',

    title_ageing: 'AGEING',
    sub_age_1: 'Style',
    sub_age_2: 'Intensity',

    title_eyebrow: 'EYEBROWS',
    sub_eyebrows_1: 'Style',
    sub_eyebrows_2: 'Opacity',
    sub_eyebrows_3: 'Color',
    sub_eyebrows_5: 'Eyebrow height',
    sub_eyebrows_6: 'Eyebrow forward',

    title_chesthair: 'CHEST HAIR',
    sub_chest_1: 'Style',
    sub_chest_2: 'Opacity',
    sub_chest_3: 'Color',

    title_makeup: 'MAKEUP',
    sub_makeup_1: 'Style',
    sub_makeup_2: 'Opacity',
    sub_makeup_3: 'Color',

    title_blush: 'BLUSH',
    sub_blush_1: 'Style',
    sub_blush_2: 'Opacity',
    sub_blush_3: 'Color',

    title_lipstick: 'LIPSTICK',
    sub_lipstick_1: 'Style',
    sub_lipstick_2: 'Opacity',
    sub_lipstick_3: 'Color',

    parentsNames: {
        dad: {
            0: 'Benjamin', 1: 'Daniel', 2: 'Joshua', 3: 'Noah', 4: 'Andrew',
            5: 'Juan', 6: 'Alex', 7: 'Isaac', 8: 'Evan', 9: 'Ethan',
            10: 'Vincent', 11: 'Angel', 12: 'Diego', 13: 'Adrian', 14: 'Gabriel',
            15: 'Michael', 16: 'Santiago', 17: 'Kevin', 18: 'Louis', 19: 'Samuel',
            20: 'Anthony', 42: 'John', 43: 'Niko', 44: 'Claude'
        },
        mom: {
            21: 'Hannah', 22: 'Audrey', 23: 'Jasmine', 24: 'Giselle', 25: 'Amelia',
            26: 'Isabella', 27: 'Zoe', 28: 'Ava', 29: 'Camilla', 30: 'Violet',
            31: 'Sophia', 32: 'Eveline', 33: 'Nicole', 34: 'Ashley', 35: 'Grace',
            36: 'Brianna', 37: 'Natalie', 38: 'Olivia', 39: 'Elizabeth', 40: 'Charlotte',
            41: 'Emma', 45: 'Misty'
        }
    }
};
