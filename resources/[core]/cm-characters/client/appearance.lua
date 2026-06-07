-- cm-characters appearance client
-- Integrates vms_charcreator for character customization

local appearanceCam = nil
local appearanceOffset = nil
local currentCharData = nil
local isInAppearance = false

-- Config (from vms_charcreator adapted for cm)
local AppearanceConfig = {
    creatingCoords = vector4(916.7, 46.18, 110.66, 57.78),
    afterSpawnCoords = vector4(-255.93, -983.88, 30.22, 250.85),
    defaultCamDistance = 0.95,
    cameraHeight = {
        ['parents'] = {z = 0.65, fov = 30.0},
        ['face'] = {z = 0.65, fov = 30.0},
        ['hairs'] = {z = 0.65, fov = 30.0},
        ['clothes'] = {z = -0.1, fov = 100.0},
        ['clothesets'] = {z = -0.1, fov = 100.0},
        ['makeup'] = {z = 0.65, fov = 30.0},
    },
    animDict = "anim@heists@heist_corona@team_idles@male_a",
    animName = "idle",
    handsUpAnim = {'missminuteman_1ig_2', 'handsup_enter', 50},
    handsUpKey = 'x',
    sounds = true,
    blur = true
}

-- Categories enabled
local EnabledCategories = {
    ['parents'] = true,
    ['face'] = true,
    ['hairs'] = true,
    ['clothes'] = true,
    ['clothesets'] = true,
    ['makeup'] = true,
}

-- Available items per category
local AvailableItems = {
    ['parents'] = {sex = true, parents = true, face_md_weight = true, skin_md_weight = true},
    ['face'] = {
        neck_thickness = true, age = true, eyebrows = true, nose = true,
        cheeks = true, lip_thickness = true, jaw = true, chin = true,
        eye_color = true, blemishes = true, complexion = true, sun = true, moles = true
    },
    ['clothes'] = {
        tshirt = true, torso = true, decals = true, arms = true, pants = true,
        shoes = true, mask = true, bproof = true, chain = true, helmet = true,
        glasses = true, watches = true, bracelets = true, bags = true, ears = true
    },
    ['hairs'] = {hair = true, beard = true, eyebrow = true, chesthair = true},
    ['makeup'] = {makeup = true, lipstick = true, blush = true}
}

-- Default clothes for first creation
local FirstCreationClothes = {
    ['m'] = {
        tshirt_1 = 15, tshirt_2 = 0,
        torso_1 = 15, torso_2 = 0,
        arms = 15, arms_2 = 0,
        pants_1 = 14, pants_2 = 1,
        shoes_1 = 34, shoes_2 = 0,
        helmet_1 = -1, helmet_2 = 0,
        chain_1 = 0, chain_2 = 0,
    },
    ['f'] = {
        tshirt_1 = 15, tshirt_2 = 0,
        torso_1 = 15, torso_2 = 0,
        arms = 15, arms_2 = 0,
        pants_1 = 15, pants_2 = 0,
        shoes_1 = 35, shoes_2 = 0,
        helmet_1 = -1, helmet_2 = 0,
        chain_1 = 0, chain_2 = 0,
        glasses_1 = 5, glasses_2 = 0,
    }
}

-- Clothing sets
local ClotheSets = {
    [0] = {
        ['name'] = "FORMAL",
        ['m'] = {tshirt_1 = 4, tshirt_2 = 0, torso_1 = 10, torso_2 = 0, arms = 1, arms_2 = 0,
                  pants_1 = 10, pants_2 = 0, shoes_1 = 10, shoes_2 = 0, helmet_1 = -1, helmet_2 = 0, chain_1 = 0, chain_2 = 0},
        ['f'] = {tshirt_1 = 41, tshirt_2 = 2, torso_1 = 6, torso_2 = 4, arms = 2, arms_2 = 0,
                  pants_1 = 6, pants_2 = 0, shoes_1 = 29, shoes_2 = 0, helmet_1 = -1, helmet_2 = 0, chain_1 = 0, chain_2 = 0},
    },
    [1] = {
        ['name'] = "CASUAL 1",
        ['m'] = {tshirt_1 = 15, tshirt_2 = 0, torso_1 = 80, torso_2 = 0, arms = 11, arms_2 = 0,
                  pants_1 = 1, pants_2 = 1, shoes_1 = 7, shoes_2 = 0, helmet_1 = -1, helmet_2 = 0, chain_1 = 0, chain_2 = 0},
        ['f'] = {tshirt_1 = 14, tshirt_2 = 0, torso_1 = 30, torso_2 = 0, arms = 2, arms_2 = 0,
                  pants_1 = 0, pants_2 = 1, shoes_1 = 27, shoes_2 = 0, helmet_1 = -1, helmet_2 = 0, chain_1 = 0, chain_2 = 0},
    },
    [2] = {
        ['name'] = "CASUAL 2",
        ['m'] = {tshirt_1 = 15, tshirt_2 = 0, torso_1 = 193, torso_2 = 14, arms = 11, arms_2 = 0,
                  pants_1 = 105, pants_2 = 0, shoes_1 = 57, shoes_2 = 10, helmet_1 = 96, helmet_2 = 0, chain_1 = 51, chain_2 = 0},
        ['f'] = {tshirt_1 = 14, tshirt_2 = 0, torso_1 = 195, torso_2 = 0, arms = 15, arms_2 = 0,
                  pants_1 = 64, pants_2 = 1, shoes_1 = 60, shoes_2 = 10, helmet_1 = 0, helmet_2 = 0, chain_1 = 0, chain_2 = 0},
    },
}

-- Skin data structure (ESX style adapted)
local SkinData = {}
local tempSkinTable = {}
local lastSkin = nil
local lastCoords = nil
local gender = 'male'
local playerHasSkin = false
local handsup = false

-- Initialize default skin values
local function InitSkinData()
    SkinData = {
        sex = 0, mom = 21, dad = 0, face_md_weight = 50, skin_md_weight = 50,
        nose_1 = 0, nose_2 = 0, nose_3 = 0, nose_4 = 0, nose_5 = 0, nose_6 = 0,
        cheeks_1 = 0, cheeks_2 = 0, cheeks_3 = 0, lip_thickness = 0,
        jaw_1 = 0, jaw_2 = 0, chin_1 = 0, chin_2 = 0, chin_3 = 0, chin_4 = 0,
        neck_thickness = 0, hair_1 = 0, hair_2 = 0, hair_color_1 = 0, hair_color_2 = 0,
        tshirt_1 = 0, tshirt_2 = 0, torso_1 = 0, torso_2 = 0, decals_1 = 0, decals_2 = 0,
        arms = 0, arms_2 = 0, pants_1 = 0, pants_2 = 0, shoes_1 = 0, shoes_2 = 0,
        mask_1 = 0, mask_2 = 0, bproof_1 = 0, bproof_2 = 0, chain_1 = 0, chain_2 = 0,
        helmet_1 = -1, helmet_2 = 0, glasses_1 = 0, glasses_2 = 0,
        watches_1 = -1, watches_2 = 0, bracelets_1 = -1, bracelets_2 = 0,
        bags_1 = 0, bags_2 = 0, eye_color = 0, eye_squint = 0,
        eyebrows_1 = 0, eyebrows_2 = 0, eyebrows_3 = 0, eyebrows_4 = 0, eyebrows_5 = 0, eyebrows_6 = 0,
        makeup_1 = 0, makeup_2 = 0, makeup_3 = 0, makeup_4 = 0,
        lipstick_1 = 0, lipstick_2 = 0, lipstick_3 = 0, lipstick_4 = 0,
        ears_1 = -1, ears_2 = 0, chest_1 = 0, chest_2 = 0, chest_3 = 0,
        bodyb_1 = -1, bodyb_2 = 0, bodyb_3 = -1, bodyb_4 = 0,
        age_1 = 0, age_2 = 0, blemishes_1 = 0, blemishes_2 = 0,
        blush_1 = 0, blush_2 = 0, blush_3 = 0, complexion_1 = 0, complexion_2 = 0,
        sun_1 = 0, sun_2 = 0, moles_1 = 0, moles_2 = 0,
        beard_1 = 0, beard_2 = 0, beard_3 = 0, beard_4 = 0
    }
    tempSkinTable = {}
    for k,v in pairs(SkinData) do
        tempSkinTable[k] = v
    end
end

-- Get max values for components
local function GetMaxVals()
    local ped = PlayerPedId()
    return {
        sex = 1, mom = 45, dad = 44, face_md_weight = 100, skin_md_weight = 100,
        nose_1 = 10, nose_2 = 10, nose_3 = 10, nose_4 = 10, nose_5 = 10, nose_6 = 10,
        cheeks_1 = 10, cheeks_2 = 10, cheeks_3 = 10, lip_thickness = 10,
        jaw_1 = 10, jaw_2 = 10, chin_1 = 10, chin_2 = 10, chin_3 = 10, chin_4 = 10,
        neck_thickness = 10, age_1 = GetPedHeadOverlayNum(3)-1, age_2 = 10,
        beard_1 = GetPedHeadOverlayNum(1)-1, beard_2 = 10,
        beard_3 = GetNumHairColors()-1, beard_4 = GetNumHairColors()-1,
        hair_1 = GetNumberOfPedDrawableVariations(ped, 2) - 1,
        hair_2 = GetNumberOfPedTextureVariations(ped, 2, tempSkinTable['hair_1']) - 1,
        hair_color_1 = GetNumHairColors()-1, hair_color_2 = GetNumHairColors()-1,
        eye_color = 31, eye_squint = 10,
        eyebrows_1 = GetPedHeadOverlayNum(2)-1, eyebrows_2 = 10,
        eyebrows_3 = GetNumHairColors()-1, eyebrows_4 = GetNumHairColors()-1,
        eyebrows_5 = 10, eyebrows_6 = 10,
        makeup_1 = GetPedHeadOverlayNum(4)-1, makeup_2 = 10,
        makeup_3 = GetNumHairColors()-1, makeup_4 = GetNumHairColors()-1,
        lipstick_1 = GetPedHeadOverlayNum(8)-1, lipstick_2 = 10,
        lipstick_3 = GetNumHairColors()-1, lipstick_4 = GetNumHairColors()-1,
        blemishes_1 = GetPedHeadOverlayNum(0)-1, blemishes_2 = 10,
        blush_1 = GetPedHeadOverlayNum(5)-1, blush_2 = 10, blush_3 = GetNumHairColors()-1,
        complexion_1 = GetPedHeadOverlayNum(6)-1, complexion_2 = 10,
        sun_1 = GetPedHeadOverlayNum(7)-1, sun_2 = 10,
        moles_1 = GetPedHeadOverlayNum(9)-1, moles_2 = 10,
        chest_1 = GetPedHeadOverlayNum(10)-1, chest_2 = 10, chest_3 = GetNumHairColors()-1,
        bodyb_1 = GetPedHeadOverlayNum(11)-1, bodyb_2 = 10,
        bodyb_3 = GetPedHeadOverlayNum(12)-1, bodyb_4 = 10,
        ears_1 = GetNumberOfPedPropDrawableVariations(ped, 2) - 1,
        ears_2 = GetNumberOfPedPropTextureVariations(ped, 2, tempSkinTable['ears_1']) - 1,
        tshirt_1 = GetNumberOfPedDrawableVariations(ped, 8) - 1,
        tshirt_2 = GetNumberOfPedTextureVariations(ped, 8, tempSkinTable['tshirt_1']) - 1,
        torso_1 = GetNumberOfPedDrawableVariations(ped, 11) - 1,
        torso_2 = GetNumberOfPedTextureVariations(ped, 11, tempSkinTable['torso_1']) - 1,
        decals_1 = GetNumberOfPedDrawableVariations(ped, 10) - 1,
        decals_2 = GetNumberOfPedTextureVariations(ped, 10, tempSkinTable['decals_1']) - 1,
        arms = GetNumberOfPedDrawableVariations(ped, 3) - 1, arms_2 = 10,
        pants_1 = GetNumberOfPedDrawableVariations(ped, 4) - 1,
        pants_2 = GetNumberOfPedTextureVariations(ped, 4, tempSkinTable['pants_1']) - 1,
        shoes_1 = GetNumberOfPedDrawableVariations(ped, 6) - 1,
        shoes_2 = GetNumberOfPedTextureVariations(ped, 6, tempSkinTable['shoes_1']) - 1,
        mask_1 = GetNumberOfPedDrawableVariations(ped, 1) - 1,
        mask_2 = GetNumberOfPedTextureVariations(ped, 1, tempSkinTable['mask_1']) - 1,
        bproof_1 = GetNumberOfPedDrawableVariations(ped, 9) - 1,
        bproof_2 = GetNumberOfPedTextureVariations(ped, 9, tempSkinTable['bproof_1']) - 1,
        chain_1 = GetNumberOfPedDrawableVariations(ped, 7) - 1,
        chain_2 = GetNumberOfPedTextureVariations(ped, 7, tempSkinTable['chain_1']) - 1,
        bags_1 = GetNumberOfPedDrawableVariations(ped, 5) - 1,
        bags_2 = GetNumberOfPedTextureVariations(ped, 5, tempSkinTable['bags_1']) - 1,
        helmet_1 = GetNumberOfPedPropDrawableVariations(ped, 0) - 1,
        helmet_2 = GetNumberOfPedPropTextureVariations(ped, 0, tempSkinTable['helmet_1']) - 1,
        glasses_1 = GetNumberOfPedPropDrawableVariations(ped, 1) - 1,
        glasses_2 = GetNumberOfPedPropTextureVariations(ped, 1, tempSkinTable['glasses_1']) - 1,
        watches_1 = GetNumberOfPedPropDrawableVariations(ped, 6) - 1,
        watches_2 = GetNumberOfPedPropTextureVariations(ped, 6, tempSkinTable['watches_1']) - 1,
        bracelets_1 = GetNumberOfPedPropDrawableVariations(ped, 7) - 1,
        bracelets_2 = GetNumberOfPedPropTextureVariations(ped, 7, tempSkinTable['bracelets_1']) - 1,
    }
end

-- Apply skin to ped
local function ApplySkin(skin)
    local ped = PlayerPedId()

    -- Head blend
    local face_weight = (skin['face_md_weight'] / 100) + 0.0
    local skin_weight = (skin['skin_md_weight'] / 100) + 0.0
    SetPedHeadBlendData(ped, skin['mom'], skin['dad'], 0, skin['mom'], skin['dad'], 0, face_weight, skin_weight, 0.0, false)

    -- Face features
    SetPedFaceFeature(ped, 0, (skin['nose_1'] / 10) + 0.0)
    SetPedFaceFeature(ped, 1, (skin['nose_2'] / 10) + 0.0)
    SetPedFaceFeature(ped, 2, (skin['nose_3'] / 10) + 0.0)
    SetPedFaceFeature(ped, 3, (skin['nose_4'] / 10) + 0.0)
    SetPedFaceFeature(ped, 4, (skin['nose_5'] / 10) + 0.0)
    SetPedFaceFeature(ped, 5, (skin['nose_6'] / 10) + 0.0)
    SetPedFaceFeature(ped, 8, (skin['cheeks_1'] / 10) + 0.0)
    SetPedFaceFeature(ped, 9, (skin['cheeks_2'] / 10) + 0.0)
    SetPedFaceFeature(ped, 10, (skin['cheeks_3'] / 10) + 0.0)
    SetPedFaceFeature(ped, 12, (skin['lip_thickness'] / 10) + 0.0)
    SetPedFaceFeature(ped, 13, (skin['jaw_1'] / 10) + 0.0)
    SetPedFaceFeature(ped, 14, (skin['jaw_2'] / 10) + 0.0)
    SetPedFaceFeature(ped, 15, (skin['chin_1'] / 10) + 0.0)
    SetPedFaceFeature(ped, 16, (skin['chin_2'] / 10) + 0.0)
    SetPedFaceFeature(ped, 17, (skin['chin_3'] / 10) + 0.0)
    SetPedFaceFeature(ped, 18, (skin['chin_4'] / 10) + 0.0)
    SetPedFaceFeature(ped, 19, (skin['neck_thickness'] / 10) + 0.0)

    -- Overlays
    SetPedHeadOverlay(ped, 3, skin['age_1'], (skin['age_2'] / 10) + 0.0)
    SetPedHeadOverlay(ped, 0, skin['blemishes_1'], (skin['blemishes_2'] / 10) + 0.0)
    SetPedEyeColor(ped, skin['eye_color'])
    SetPedHeadOverlay(ped, 2, skin['eyebrows_1'], (skin['eyebrows_2'] / 10) + 0.0)
    SetPedHeadOverlayColor(ped, 2, 1, skin['eyebrows_3'], skin['eyebrows_4'])
    SetPedFaceFeature(ped, 6, (skin['eyebrows_5'] / 10) + 0.0)
    SetPedFaceFeature(ped, 7, (skin['eyebrows_6'] / 10) + 0.0)
    SetPedHeadOverlay(ped, 4, skin['makeup_1'], (skin['makeup_2'] / 10) + 0.0)
    SetPedHeadOverlayColor(ped, 4, 2, skin['makeup_3'], skin['makeup_4'])
    SetPedHeadOverlay(ped, 8, skin['lipstick_1'], (skin['lipstick_2'] / 10) + 0.0)
    SetPedHeadOverlayColor(ped, 8, 1, skin['lipstick_3'], skin['lipstick_4'])
    SetPedComponentVariation(ped, 2, skin['hair_1'], skin['hair_2'], 2)
    SetPedHairColor(ped, skin['hair_color_1'], skin['hair_color_2'])
    SetPedHeadOverlay(ped, 1, skin['beard_1'], (skin['beard_2'] / 10) + 0.0)
    SetPedHeadOverlayColor(ped, 1, 1, skin['beard_3'], skin['beard_4'])
    SetPedHeadOverlay(ped, 5, skin['blush_1'], (skin['blush_2'] / 10) + 0.0)
    SetPedHeadOverlayColor(ped, 5, 2, skin['blush_3'])
    SetPedHeadOverlay(ped, 6, skin['complexion_1'], (skin['complexion_2'] / 10) + 0.0)
    SetPedHeadOverlay(ped, 7, skin['sun_1'], (skin['sun_2'] / 10) + 0.0)
    SetPedHeadOverlay(ped, 9, skin['moles_1'], (skin['moles_2'] / 10) + 0.0)
    SetPedHeadOverlay(ped, 10, skin['chest_1'], (skin['chest_2'] / 10) + 0.0)
    SetPedHeadOverlayColor(ped, 10, 1, skin['chest_3'])

    -- Props
    if skin['ears_1'] == -1 then ClearPedProp(ped, 2)
    else SetPedPropIndex(ped, 2, skin['ears_1'], skin['ears_2'], 2) end

    -- Components
    SetPedComponentVariation(ped, 8, skin['tshirt_1'], skin['tshirt_2'], 2)
    SetPedComponentVariation(ped, 11, skin['torso_1'], skin['torso_2'], 2)
    SetPedComponentVariation(ped, 3, skin['arms'], skin['arms_2'], 2)
    SetPedComponentVariation(ped, 10, skin['decals_1'], skin['decals_2'], 2)
    SetPedComponentVariation(ped, 4, skin['pants_1'], skin['pants_2'], 2)
    SetPedComponentVariation(ped, 6, skin['shoes_1'], skin['shoes_2'], 2)
    SetPedComponentVariation(ped, 1, skin['mask_1'], skin['mask_2'], 2)
    SetPedComponentVariation(ped, 9, skin['bproof_1'], skin['bproof_2'], 2)
    SetPedComponentVariation(ped, 7, skin['chain_1'], skin['chain_2'], 2)
    SetPedComponentVariation(ped, 5, skin['bags_1'], skin['bags_2'], 2)

    if skin['helmet_1'] == -1 then ClearPedProp(ped, 0)
    else SetPedPropIndex(ped, 0, skin['helmet_1'], skin['helmet_2'], 2) end

    if skin['glasses_1'] == -1 then ClearPedProp(ped, 1)
    else SetPedPropIndex(ped, 1, skin['glasses_1'], skin['glasses_2'], 2) end

    if skin['watches_1'] == -1 then ClearPedProp(ped, 6)
    else SetPedPropIndex(ped, 6, skin['watches_1'], skin['watches_2'], 2) end

    if skin['bracelets_1'] == -1 then ClearPedProp(ped, 7)
    else SetPedPropIndex(ped, 7, skin['bracelets_1'], skin['bracelets_2'], 2) end
end

-- Update single value
local function UpdateValue(skin)
    for k,v in pairs(skin) do
        tempSkinTable[k] = v
    end
    ApplySkin(tempSkinTable)
end

-- Get component data for UI
local function GetComponentData()
    local components = {
        {name = 'sex', value = 0, min = 0},
        {name = 'mom', value = 21, min = 21},
        {name = 'dad', value = 0, min = 0},
        {name = 'face_md_weight', value = 50, min = 0},
        {name = 'skin_md_weight', value = 50, min = 0},
        {name = 'nose_1', value = 0, min = -10},
        {name = 'nose_2', value = 0, min = -10},
        {name = 'nose_3', value = 0, min = -10},
        {name = 'nose_4', value = 0, min = -10},
        {name = 'nose_5', value = 0, min = -10},
        {name = 'nose_6', value = 0, min = -10},
        {name = 'cheeks_1', value = 0, min = -10},
        {name = 'cheeks_2', value = 0, min = -10},
        {name = 'cheeks_3', value = 0, min = -10},
        {name = 'lip_thickness', value = 0, min = -10},
        {name = 'jaw_1', value = 0, min = -10},
        {name = 'jaw_2', value = 0, min = -10},
        {name = 'chin_1', value = 0, min = -10},
        {name = 'chin_2', value = 0, min = -10},
        {name = 'chin_3', value = 0, min = -10},
        {name = 'chin_4', value = 0, min = -10},
        {name = 'neck_thickness', value = 0, min = -10},
        {name = 'hair_1', value = 0, min = 0},
        {name = 'hair_2', value = 0, min = 0},
        {name = 'hair_color_1', value = 0, min = 0},
        {name = 'hair_color_2', value = 0, min = 0},
        {name = 'tshirt_1', value = 0, min = 0},
        {name = 'tshirt_2', value = 0, min = 0},
        {name = 'torso_1', value = 0, min = 0},
        {name = 'torso_2', value = 0, min = 0},
        {name = 'decals_1', value = 0, min = 0},
        {name = 'decals_2', value = 0, min = 0},
        {name = 'arms', value = 0, min = 0},
        {name = 'arms_2', value = 0, min = 0},
        {name = 'pants_1', value = 0, min = 0},
        {name = 'pants_2', value = 0, min = 0},
        {name = 'shoes_1', value = 0, min = 0},
        {name = 'shoes_2', value = 0, min = 0},
        {name = 'mask_1', value = 0, min = 0},
        {name = 'mask_2', value = 0, min = 0},
        {name = 'bproof_1', value = 0, min = 0},
        {name = 'bproof_2', value = 0, min = 0},
        {name = 'chain_1', value = 0, min = 0},
        {name = 'chain_2', value = 0, min = 0},
        {name = 'helmet_1', value = -1, min = -1},
        {name = 'helmet_2', value = 0, min = 0},
        {name = 'glasses_1', value = 0, min = 0},
        {name = 'glasses_2', value = 0, min = 0},
        {name = 'watches_1', value = -1, min = -1},
        {name = 'watches_2', value = 0, min = 0},
        {name = 'bracelets_1', value = -1, min = -1},
        {name = 'bracelets_2', value = 0, min = 0},
        {name = 'bags_1', value = 0, min = 0},
        {name = 'bags_2', value = 0, min = 0},
        {name = 'eye_color', value = 0, min = 0},
        {name = 'eyebrows_1', value = 0, min = 0},
        {name = 'eyebrows_2', value = 0, min = 0},
        {name = 'eyebrows_3', value = 0, min = 0},
        {name = 'eyebrows_4', value = 0, min = 0},
        {name = 'eyebrows_5', value = 0, min = -10},
        {name = 'eyebrows_6', value = 0, min = -10},
        {name = 'makeup_1', value = 0, min = 0},
        {name = 'makeup_2', value = 0, min = 0},
        {name = 'makeup_3', value = 0, min = 0},
        {name = 'makeup_4', value = 0, min = 0},
        {name = 'lipstick_1', value = 0, min = 0},
        {name = 'lipstick_2', value = 0, min = 0},
        {name = 'lipstick_3', value = 0, min = 0},
        {name = 'lipstick_4', value = 0, min = 0},
        {name = 'ears_1', value = -1, min = -1},
        {name = 'ears_2', value = 0, min = 0},
        {name = 'chest_1', value = 0, min = 0},
        {name = 'chest_2', value = 0, min = 0},
        {name = 'chest_3', value = 0, min = 0},
        {name = 'bodyb_1', value = -1, min = -1},
        {name = 'bodyb_2', value = 0, min = 0},
        {name = 'bodyb_3', value = -1, min = -1},
        {name = 'bodyb_4', value = 0, min = 0},
        {name = 'age_1', value = 0, min = 0},
        {name = 'age_2', value = 0, min = 0},
        {name = 'blemishes_1', value = 0, min = 0},
        {name = 'blemishes_2', value = 0, min = 0},
        {name = 'blush_1', value = 0, min = 0},
        {name = 'blush_2', value = 0, min = 0},
        {name = 'blush_3', value = 0, min = 0},
        {name = 'complexion_1', value = 0, min = 0},
        {name = 'complexion_2', value = 0, min = 0},
        {name = 'sun_1', value = 0, min = 0},
        {name = 'sun_2', value = 0, min = 0},
        {name = 'moles_1', value = 0, min = 0},
        {name = 'moles_2', value = 0, min = 0},
        {name = 'beard_1', value = 0, min = 0},
        {name = 'beard_2', value = 0, min = 0},
        {name = 'beard_3', value = 0, min = 0},
        {name = 'beard_4', value = 0, min = 0},
    }

    local maxVals = GetMaxVals()
    local data = {}
    for i=1, #components do
        data[components[i].name] = {
            value = tempSkinTable[components[i].name] or components[i].value,
            min = components[i].min,
            max = maxVals[components[i].name] or 0
        }
    end
    return data
end

-- Create camera
local function CreateAppearanceCam()
    if not DoesCamExist(appearanceCam) then
        appearanceCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    appearanceOffset = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0 + AppearanceConfig.defaultCamDistance, 0.0)

    SetCamActive(appearanceCam, true)
    RenderScriptCams(true, true, 500, true, true)
    SetCamCoord(appearanceCam, appearanceOffset.x, appearanceOffset.y, appearanceOffset.z + 0.65)
    PointCamAtCoord(appearanceCam, coords.x, coords.y, coords.z + 0.65)
    SetCamFov(appearanceCam, 30.0)

    SetTimecycleModifier('MP_corona_heist_DOF')
    SetTimecycleModifierStrength(1.0)

    -- Play idle anim
    RequestAnimDict(AppearanceConfig.animDict)
    while not HasAnimDictLoaded(AppearanceConfig.animDict) do Wait(1) end
    TaskPlayAnim(ped, AppearanceConfig.animDict, AppearanceConfig.animName, 8.0, 0.0, -1, 1, 0, 0, 0, 0)
end

-- Delete camera
local function DeleteAppearanceCam()
    DoScreenFadeOut(500)
    Wait(500)

    SetCamActive(appearanceCam, false)
    appearanceCam = nil
    RenderScriptCams(false, true, 500, true, true)
    ClearTimecycleModifier()

    FreezeEntityPosition(PlayerPedId(), false)
    ClearPedTasks(PlayerPedId())
    ClearPedTasksImmediately(PlayerPedId())

    Wait(500)
    DoScreenFadeIn(500)
end

-- Open appearance editor
AddEventHandler('cm-characters:client:openAppearance', function(charData)
    currentCharData = charData
    isInAppearance = true

    -- Fade out and teleport
    DoScreenFadeOut(500)
    Wait(1000)

    local ped = PlayerPedId()
    lastCoords = {
        x = GetEntityCoords(ped).x,
        y = GetEntityCoords(ped).y,
        z = GetEntityCoords(ped).z,
        w = GetEntityHeading(ped)
    }

    SetEntityCoords(ped, AppearanceConfig.creatingCoords.x, AppearanceConfig.creatingCoords.y, AppearanceConfig.creatingCoords.z)
    SetEntityHeading(ped, AppearanceConfig.creatingCoords.w)
    FreezeEntityPosition(ped, true)

    -- Set default model based on gender
    local sex = 0
    if charData.gender == 'female' then sex = 1 end

    local model = sex == 0 and GetHashKey('mp_m_freemode_01') or GetHashKey('mp_f_freemode_01')
    RequestModel(model)
    while not HasModelLoaded(model) do
        RequestModel(model)
        Wait(0)
    end
    SetPlayerModel(PlayerId(), model)
    SetPedComponentVariation(PlayerPedId(), 0, 0, 0, 2)

    -- Init skin data
    InitSkinData()
    tempSkinTable['sex'] = sex

    -- Apply default underwear clothes
    local mySex = sex == 0 and 'm' or 'f'
    for k, v in pairs(FirstCreationClothes[mySex]) do
        tempSkinTable[k] = v
    end
    ApplySkin(tempSkinTable)

    DoScreenFadeIn(500)

    -- Create camera
    CreateAppearanceCam()

    -- Build UI data
    local uiData = GetComponentData()

    -- Send to UI
    SendNUIMessage({
        action = 'openAppearance',
        categories = EnabledCategories,
        items = AvailableItems,
        data = uiData,
        currentRotate = GetEntityHeading(ped),
        currentDistance = 30,
        clotheSets = ClotheSets,
        handsUpKey = AppearanceConfig.handsUpKey,
        enableHandsUpButton = true,
        enableCancelButtonUI = false, -- No cancel for new chars
        playerHasAlreadySkin = false,
        charId = charData.charId
    })

    SetNuiFocus(true, true)
end)

-- NUI Callbacks for appearance
RegisterNUICallback('appearanceChange', function(data, cb)
    if data.type == 'clotheset' then
        local mySex = IsPedModel(PlayerPedId(), GetHashKey('mp_m_freemode_01')) and 'm' or 'f'
        if ClotheSets[tonumber(data.new)] then
            for k, v in pairs(ClotheSets[tonumber(data.new)][mySex]) do
                tempSkinTable[k] = v
            end
            UpdateValue(tempSkinTable)
        end
    else
        if data.type == 'sex' then
            local sex = tonumber(data.new)
            local model = sex == 0 and GetHashKey('mp_m_freemode_01') or GetHashKey('mp_f_freemode_01')
            RequestModel(model)
            while not HasModelLoaded(model) do
                RequestModel(model)
                Wait(0)
            end
            SetPlayerModel(PlayerId(), model)
            SetPedComponentVariation(PlayerPedId(), 0, 0, 0, 2)
            tempSkinTable['sex'] = sex
            -- Reapply default clothes for new gender
            local mySex = sex == 0 and 'm' or 'f'
            for k, v in pairs(FirstCreationClothes[mySex]) do
                tempSkinTable[k] = v
            end
        else
            tempSkinTable[data.type] = tonumber(data.new)
        end
        UpdateValue(tempSkinTable)

        -- Update secondary value (texture) if needed
        local secondItems = {
            ['tshirt_1'] = 'tshirt_2', ['torso_1'] = 'torso_2', ['helmet_1'] = 'helmet_2',
            ['pants_1'] = 'pants_2', ['shoes_1'] = 'shoes_2', ['mask_1'] = 'mask_2',
            ['decals_1'] = 'decals_2', ['chain_1'] = 'chain_2', ['glasses_1'] = 'glasses_2',
            ['watches_1'] = 'watches_2', ['bracelets_1'] = 'bracelets_2',
            ['bags_1'] = 'bags_2', ['ears_1'] = 'ears_2', ['bproof_1'] = 'bproof_2',
            ['hair_1'] = 'hair_2'
        }
        if secondItems[data.type] then
            local maxVals = GetMaxVals()
            SendNUIMessage({
                action = 'updateSecondValue',
                secondItem = secondItems[data.type],
                secondValue = maxVals[secondItems[data.type]] or 0
            })
            tempSkinTable[secondItems[data.type]] = 0
            UpdateValue(tempSkinTable)
        end
    end

    if AppearanceConfig.sounds then
        PlaySoundFrontend(-1, "NAV_LEFT_RIGHT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
    cb('ok')
end)

RegisterNUICallback('appearanceCamera', function(data, cb)
    if appearanceCam and data.type then
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local newPos = AppearanceConfig.cameraHeight[data.type]
        SetCamCoord(appearanceCam, appearanceOffset.x, appearanceOffset.y, appearanceOffset.z + newPos.z)
        PointCamAtCoord(appearanceCam, coords.x, coords.y, coords.z + newPos.z)
        SetCamFov(appearanceCam, newPos.fov)
        SendNUIMessage({
            action = 'updateInputs',
            fov = math.floor(newPos.fov)
        })
    end
    cb('ok')
end)

RegisterNUICallback('appearanceHeight', function(data, cb)
    if appearanceCam and data.height then
        SetCamCoord(appearanceCam, appearanceOffset.x, appearanceOffset.y, appearanceOffset.z + data.height)
    end
    cb('ok')
end)

RegisterNUICallback('appearanceDistance', function(data, cb)
    if appearanceCam and data.distance then
        SetCamFov(appearanceCam, tonumber(data.distance) + 0.0)
    end
    cb('ok')
end)

RegisterNUICallback('appearanceRotate', function(data, cb)
    if data.rotate then
        local ped = PlayerPedId()
        local newHeading = tonumber(math.floor(data.rotate) + 0.0)
        SetEntityHeading(ped, newHeading)
    end
    cb('ok')
end)

RegisterNUICallback('appearanceHandsUp', function(data, cb)
    local ped = PlayerPedId()
    if handsup then
        ClearPedTasksImmediately(ped)
        RequestAnimDict(AppearanceConfig.animDict)
        while not HasAnimDictLoaded(AppearanceConfig.animDict) do Wait(1) end
        TaskPlayAnim(ped, AppearanceConfig.animDict, AppearanceConfig.animName, 8.0, 0.0, -1, 1, 0, 0, 0, 0)
        handsup = false
    else
        RequestAnimDict(AppearanceConfig.handsUpAnim[1])
        while not HasAnimDictLoaded(AppearanceConfig.handsUpAnim[1]) do Wait(1) end
        TaskPlayAnim(ped, AppearanceConfig.handsUpAnim[1], AppearanceConfig.handsUpAnim[2], 8.0, 0.0, -1, AppearanceConfig.handsUpAnim[3], 0, 0, 0, 0)
        handsup = true
    end
    cb('ok')
end)

-- SAVE - Complete character creation
RegisterNUICallback('appearanceSave', function(data, cb)
    isInAppearance = false
    SetNuiFocus(false, false)

    -- Save appearance to server
    TriggerServerEvent('cm-characters:server:saveAppearance', currentCharData.charId, tempSkinTable)

    -- Cleanup camera
    DeleteAppearanceCam()

    -- Teleport to spawn
    local ped = PlayerPedId()
    SetEntityCoords(ped, AppearanceConfig.afterSpawnCoords.x, AppearanceConfig.afterSpawnCoords.y, AppearanceConfig.afterSpawnCoords.z)
    SetEntityHeading(ped, AppearanceConfig.afterSpawnCoords.w)

    -- Notify core that character is fully ready
    TriggerEvent('cm-characters:client:characterReady', currentCharData.charId)

    cb('ok')
end)

-- Close appearance (shouldn't happen for new chars, but handle it)
RegisterNUICallback('appearanceClose', function(data, cb)
    isInAppearance = false
    SetNuiFocus(false, false)
    DeleteAppearanceCam()
    cb('ok')
end)
