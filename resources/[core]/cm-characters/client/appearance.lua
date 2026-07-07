-- cm-characters appearance client
-- Integrates vms_charcreator for character customization

local appearanceCam = nil
local appearanceOffset = nil
local currentCharData = nil
local isInAppearance = false
local appearanceSavePending = false

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
        ['makeup'] = {z = 0.65, fov = 30.0}, -- disabled in CM simplified creator
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
    ['clothes'] = true, -- first creation only: choose starter shirt/pants/shoes
    ['clothesets'] = false, -- no outfit packs
    ['makeup'] = false, -- disabled: no makeup category in character creation
}

-- Available items per category
local AvailableItems = {
    ['parents'] = {sex = true, parents = true, face_md_weight = true, skin_md_weight = true},
    ['face'] = {
        neck_thickness = false, age = false, eyebrows = true, nose = true,
        cheeks = true, lip_thickness = true, jaw = true, chin = true,
        eye_color = true, blemishes = false, complexion = false, sun = false, moles = false
    },
    ['clothes'] = {torso = true, pants = true, shoes = true},
    ['hairs'] = {hair = true, beard = true, eyebrow = true, chesthair = false},
    ['makeup'] = {makeup = false, lipstick = false, blush = false}
}

-- Default no-clothes/underwear base for first creation.
-- Players choose only starter shirt, pants, and shoes individually.
local FirstCreationClothes = {
    ['m'] = {
        tshirt_1 = 15, tshirt_2 = 0, torso_1 = 15, torso_2 = 0, arms = 15, arms_2 = 0,
        pants_1 = 14, pants_2 = 1, shoes_1 = 34, shoes_2 = 0,
        helmet_1 = -1, helmet_2 = 0, chain_1 = 0, chain_2 = 0, glasses_1 = -1, glasses_2 = 0,
    },
    ['f'] = {
        tshirt_1 = 15, tshirt_2 = 0, torso_1 = 15, torso_2 = 0, arms = 15, arms_2 = 0,
        pants_1 = 15, pants_2 = 0, shoes_1 = 35, shoes_2 = 0,
        helmet_1 = -1, helmet_2 = 0, chain_1 = 0, chain_2 = 0, glasses_1 = -1, glasses_2 = 0,
    }
}

-- Only two starter choices for each visible clothing category in character creation.
-- These are NOT outfit packs and are saved as starting appearance only.
local StarterClothingChoices = {
    ['m'] = {
        torso = {
            [0] = {torso_1 = 15, torso_2 = 0, tshirt_1 = 15, tshirt_2 = 0, arms = 15, arms_2 = 0},
            [1] = {torso_1 = 5,  torso_2 = 0, tshirt_1 = 15, tshirt_2 = 0, arms = 5,  arms_2 = 0},
        },
        pants = {
            [0] = {pants_1 = 14, pants_2 = 1},
            [1] = {pants_1 = 1,  pants_2 = 0},
        },
        shoes = {
            [0] = {shoes_1 = 34, shoes_2 = 0},
            [1] = {shoes_1 = 7,  shoes_2 = 0},
        }
    },
    ['f'] = {
        torso = {
            [0] = {torso_1 = 15, torso_2 = 0, tshirt_1 = 15, tshirt_2 = 0, arms = 15, arms_2 = 0},
            [1] = {torso_1 = 6,  torso_2 = 0, tshirt_1 = 14, tshirt_2 = 0, arms = 6,  arms_2 = 0},
        },
        pants = {
            [0] = {pants_1 = 15, pants_2 = 0},
            [1] = {pants_1 = 0,  pants_2 = 0},
        },
        shoes = {
            [0] = {shoes_1 = 35, shoes_2 = 0},
            [1] = {shoes_1 = 3,  shoes_2 = 0},
        }
    }
}

local ClotheSets = {}

-- Skin data structure (ESX style adapted)
local SkinData = {}
local tempSkinTable = {}
local lastSkin = nil
local lastCoords = nil
local gender = 'male'
local playerHasSkin = false
local handsup = false

local function CopyTable(tbl)
    local copy = {}
    if type(tbl) == 'table' then
        for k, v in pairs(tbl) do copy[k] = v end
    end
    return copy
end

-- Keeps the appearance editor/save cache in sync when another file applies a saved skin.
RegisterNetEvent('cm-characters:client:updateAppearanceCache', function(appearanceData)
    if type(appearanceData) ~= 'table' then return end
    tempSkinTable = CopyTable(appearanceData)
end)

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
        tshirt_1 = 0,
        tshirt_2 = 0,
        torso_1 = 1,
        torso_2 = 0,
        decals_1 = GetNumberOfPedDrawableVariations(ped, 10) - 1,
        decals_2 = GetNumberOfPedTextureVariations(ped, 10, tempSkinTable['decals_1']) - 1,
        arms = GetNumberOfPedDrawableVariations(ped, 3) - 1, arms_2 = 10,
        pants_1 = 1,
        pants_2 = 0,
        shoes_1 = 1,
        shoes_2 = 0,
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
    SetPedHeadOverlayColor(ped, 5, 2, skin['blush_3'], skin['blush_3'])
    SetPedHeadOverlay(ped, 6, skin['complexion_1'], (skin['complexion_2'] / 10) + 0.0)
    SetPedHeadOverlay(ped, 7, skin['sun_1'], (skin['sun_2'] / 10) + 0.0)
    SetPedHeadOverlay(ped, 9, skin['moles_1'], (skin['moles_2'] / 10) + 0.0)
    SetPedHeadOverlay(ped, 10, skin['chest_1'], (skin['chest_2'] / 10) + 0.0)
    SetPedHeadOverlayColor(ped, 10, 1, skin['chest_3'], skin['chest_3'])

    -- Props (nil-safe)
    local _ears      = tonumber(skin['ears_1'])
    local _helmet    = tonumber(skin['helmet_1'])
    local _glasses   = tonumber(skin['glasses_1'])
    local _watches   = tonumber(skin['watches_1'])
    local _bracelets = tonumber(skin['bracelets_1'])

    if _ears      == nil or _ears      < 0 then ClearPedProp(ped, 2) else SetPedPropIndex(ped, 2, _ears,      skin['ears_2']      or 0, true) end
    if _helmet    == nil or _helmet    < 0 then ClearPedProp(ped, 0) else SetPedPropIndex(ped, 0, _helmet,    skin['helmet_2']    or 0, true) end
    if _glasses   == nil or _glasses   < 0 then ClearPedProp(ped, 1) else SetPedPropIndex(ped, 1, _glasses,   skin['glasses_2']   or 0, true) end
    if _watches   == nil or _watches   < 0 then ClearPedProp(ped, 6) else SetPedPropIndex(ped, 6, _watches,   skin['watches_2']   or 0, true) end
    if _bracelets == nil or _bracelets < 0 then ClearPedProp(ped, 7) else SetPedPropIndex(ped, 7, _bracelets, skin['bracelets_2'] or 0, true) end

    -- Components
    SetPedComponentVariation(ped, 8,  skin['tshirt_1'] or 15, skin['tshirt_2'] or 0, 2)
    SetPedComponentVariation(ped, 11, skin['torso_1']  or 15, skin['torso_2']  or 0, 2)
    SetPedComponentVariation(ped, 3,  skin['arms']     or 15, skin['arms_2']   or 0, 2)
    SetPedComponentVariation(ped, 10, skin['decals_1'] or 0,  skin['decals_2'] or 0, 2)
    SetPedComponentVariation(ped, 4,  skin['pants_1']  or 14, skin['pants_2']  or 0, 2)
    SetPedComponentVariation(ped, 6,  skin['shoes_1']  or 34, skin['shoes_2']  or 0, 2)
    SetPedComponentVariation(ped, 1,  skin['mask_1']   or 0,  skin['mask_2']   or 0, 2)
    SetPedComponentVariation(ped, 9,  skin['bproof_1'] or 0,  skin['bproof_2'] or 0, 2)
    SetPedComponentVariation(ped, 7,  skin['chain_1']  or 0,  skin['chain_2']  or 0, 2)
    SetPedComponentVariation(ped, 5,  skin['bags_1']   or 0,  skin['bags_2']   or 0, 2)
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


local function setCreationHudVisible(visible)
    visible = visible == true
    LocalPlayer.state:set('cmHudHiddenByCharacters', not visible, true)

    if visible then
        TriggerEvent('cm-hud:client:showUiOnly', 'cm-characters-appearance')
        TriggerEvent('cm-hud:client:setUiVisible', true, 'cm-characters-appearance')
    else
        TriggerEvent('cm-hud:client:hideUiOnly', 'cm-characters-appearance')
        TriggerEvent('cm-hud:client:setUiVisible', false, 'cm-characters-appearance')
    end

    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:SetUiVisible(visible, 'cm-characters-appearance') end)
        if visible then
            pcall(function() exports['cm-hud']:ShowUiOnly('cm-characters-appearance') end)
        else
            pcall(function() exports['cm-hud']:HideUiOnly('cm-characters-appearance') end)
        end
    end
end

local function setCreationState(active)
    LocalPlayer.state:set('isInCharacterSelector', active == true, true)
    LocalPlayer.state:set('isInCharacterCreation', active == true, true)
    LocalPlayer.state:set('skipPositionSave', active == true, true)
    LocalPlayer.state:set('characterFullySpawned', active ~= true, true)
end

local function sendCreationLoading(show, message)
    SendNUIMessage({
        action = 'creationLoading',
        show = show == true,
        message = message or 'Preparing character creator...'
    })
end

local function requestModelBlocking(model, label)
    sendCreationLoading(true, label or 'Loading character model...')
    RequestModel(model)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        RequestModel(model)
        Wait(0)
    end
    return HasModelLoaded(model)
end

local function loadCreatorCollision(coords)
    sendCreationLoading(true, 'Loading creator room...')
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    NewLoadSceneStart(coords.x, coords.y, coords.z, coords.x, coords.y, coords.z, 45.0, 0)
    local timeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end
    NewLoadSceneStop()
end

-- Open appearance editor
AddEventHandler('cm-characters:client:openAppearance', function(charData)
    currentCharData = charData
    isInAppearance = true
    TriggerEvent('cm-characters:client:setWorldLock', 'creator', true)
    setCreationState(true)
    setCreationHudVisible(false)
    sendCreationLoading(true, 'Preparing character creator...')

    -- Fade out and prepare the creator scene behind a small loading overlay.
    DoScreenFadeOut(250)
    Wait(250)

    local ped = PlayerPedId()
    lastCoords = {
        x = GetEntityCoords(ped).x,
        y = GetEntityCoords(ped).y,
        z = GetEntityCoords(ped).z,
        w = GetEntityHeading(ped)
    }

    loadCreatorCollision(AppearanceConfig.creatingCoords)
    SetEntityCoordsNoOffset(ped, AppearanceConfig.creatingCoords.x, AppearanceConfig.creatingCoords.y, AppearanceConfig.creatingCoords.z, false, false, false)
    SetEntityHeading(ped, AppearanceConfig.creatingCoords.w)
    FreezeEntityPosition(ped, true)

    -- Set default model based on gender
    local sex = 0
    if charData.gender == 'female' then sex = 1 end

    local model = sex == 0 and GetHashKey('mp_m_freemode_01') or GetHashKey('mp_f_freemode_01')
    local modelLoaded = requestModelBlocking(model, 'Loading freemode character...')
    if not modelLoaded then
        print('[CM-CHARACTERS] WARNING: freemode model load timed out, continuing anyway')
    end
    SetPlayerModel(PlayerId(), model)
    ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, AppearanceConfig.creatingCoords.x, AppearanceConfig.creatingCoords.y, AppearanceConfig.creatingCoords.z, false, false, false)
    SetEntityHeading(ped, AppearanceConfig.creatingCoords.w)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetPedComponentVariation(ped, 0, 0, 0, 2)

    -- Init skin data
    InitSkinData()
    tempSkinTable['sex'] = sex

    -- Apply default underwear clothes
    local mySex = sex == 0 and 'm' or 'f'
    for k, v in pairs(FirstCreationClothes[mySex]) do
        tempSkinTable[k] = v
    end
    ApplySkin(tempSkinTable)
    SetEntityVisible(PlayerPedId(), true, false)

    DoScreenFadeIn(350)

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
    sendCreationLoading(false)
end)

-- NUI Callbacks for appearance
RegisterNUICallback('appearanceChange', function(data, cb)
    if data.type == 'clotheset' then
        -- Outfit packs disabled. Clothing is selected individually below.
    else
        if data.type == 'sex' then
            local sex = tonumber(data.new)
            local model = sex == 0 and GetHashKey('mp_m_freemode_01') or GetHashKey('mp_f_freemode_01')
            sendCreationLoading(true, 'Changing character model...')
            RequestModel(model)
            while not HasModelLoaded(model) do
                RequestModel(model)
                Wait(0)
            end
            SetPlayerModel(PlayerId(), model)
            SetPedComponentVariation(PlayerPedId(), 0, 0, 0, 2)
            sendCreationLoading(false)
            tempSkinTable['sex'] = sex
            -- Reapply default clothes for new gender
            local mySex = sex == 0 and 'm' or 'f'
            for k, v in pairs(FirstCreationClothes[mySex]) do
                tempSkinTable[k] = v
            end
        elseif data.type == 'torso_1' or data.type == 'pants_1' or data.type == 'shoes_1' then
            local mySex = IsPedModel(PlayerPedId(), GetHashKey('mp_m_freemode_01')) and 'm' or 'f'
            local category = data.type == 'torso_1' and 'torso' or (data.type == 'pants_1' and 'pants' or 'shoes')
            local choice = tonumber(data.new) or 0
            local selected = StarterClothingChoices[mySex] and StarterClothingChoices[mySex][category] and StarterClothingChoices[mySex][category][choice]
            if selected then
                for k, v in pairs(selected) do tempSkinTable[k] = v end
            end
        elseif data.type == 'torso_2' or data.type == 'pants_2' or data.type == 'shoes_2' or data.type == 'tshirt_1' or data.type == 'tshirt_2' then
            -- Starter clothing textures are locked to 0 and tshirt is controlled by shirt choice.
            tempSkinTable[data.type] = 0
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
    if appearanceSavePending then
        cb('ok')
        return
    end

    if not currentCharData or not currentCharData.charId then
        cb('ok')
        return
    end

    appearanceSavePending = true
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'creationLoading', show = true, message = 'Saving character...', percent = 55 })

    -- Hide the transition while the server saves naked/base JSON and inventory re-equips
    -- starter clothes. This prevents the brief default-body blink after pressing Create.
    if not IsScreenFadedOut() and not IsScreenFadingOut() then
        DoScreenFadeOut(150)
        Wait(180)
    end

    -- Server acknowledgement will close the creator after DB/inventory work finishes.
    TriggerServerEvent('cm-characters:server:saveAppearance', currentCharData.charId, tempSkinTable)

    -- Safety: if the server event fails for any reason, do not leave the screen black forever.
    local savedCharId = currentCharData.charId
    SetTimeout(9000, function()
        if appearanceSavePending and currentCharData and tostring(currentCharData.charId) == tostring(savedCharId) then
            appearanceSavePending = false
            isInAppearance = false
            SendNUIMessage({ action = 'hideAll' })
            DeleteAppearanceCam()
            setCreationState(false)
            setCreationHudVisible(false)
            TriggerEvent('cm-characters:client:characterReady', savedCharId)
            if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(350) end
        end
    end)

    cb('ok')
end)


local function prepareClimatimeBeforeFirstSpawn()
    local c = Config and Config.CharacterScreenWorld or {}
    if c.preSpawnClimatePrepare ~= true then return false end
    if GetResourceState('cm-climatime') ~= 'started' then return false end

    local prepareMs = tonumber(c.preSpawnClimatePrepareMs) or 2600
    if prepareMs < 600 then prepareMs = 600 end

    LocalPlayer.state:set('cmCharactersPreparingSpawnClimate', true, true)
    LocalPlayer.state:set('cmClimatimePreSpawnPreparing', true, true)
    LocalPlayer.state:set('cmClimatimePreSpawnPrepared', false, true)
    TriggerEvent('cm-characters:client:setWorldLock', 'creator', false)
    LocalPlayer.state:set('isInCharacterCreation', false, true)

    local payload = {
        reason = 'cm-characters-new-character-pre-spawn',
        prepareMs = prepareMs,
        validMs = tonumber(c.preSpawnValidMs) or 25000,
        weatherTransitionSeconds = tonumber(c.preSpawnWeatherTransitionSeconds) or 1.2,
        rainRampSeconds = tonumber(c.preSpawnRainRampSeconds) or 1.2
    }

    local preparedByExport = false
    if GetResourceState('cm-climatime') == 'started' then
        preparedByExport = pcall(function() exports['cm-climatime']:PrepareBeforeSpawn(payload) end)
    end
    if not preparedByExport then
        TriggerEvent('cm-climatime:client:prepareBeforeSpawn', payload)
    end
    Wait(prepareMs)
    LocalPlayer.state:set('cmCharactersPreparingSpawnClimate', false, true)
    LocalPlayer.state:set('cmClimatimePreSpawnPreparing', false, true)
    LocalPlayer.state:set('cmClimatimePreSpawnPrepared', true, true)
    return true
end

RegisterNetEvent('cm-characters:client:appearanceSaved', function(ok, payload)
    payload = type(payload) == 'table' and payload or {}
    if not appearanceSavePending then return end
    appearanceSavePending = false

    if ok ~= true then
        isInAppearance = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openAppearance' })
        SendNUIMessage({ action = 'creationLoading', show = false })
        if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(250) end
        return
    end

    isInAppearance = false
    SendNUIMessage({ action = 'hideAll' })
    DeleteAppearanceCam()

    local ped = PlayerPedId()
    SetEntityCoords(ped, AppearanceConfig.afterSpawnCoords.x, AppearanceConfig.afterSpawnCoords.y, AppearanceConfig.afterSpawnCoords.z)
    SetEntityHeading(ped, AppearanceConfig.afterSpawnCoords.w)

    setCreationState(false)
    setCreationHudVisible(false)

    -- Prepare live cm-climatime while still faded out, before characterReady
    -- restores the real view. New characters then spawn directly into the right
    -- time/weather instead of seeing it change afterwards.
    prepareClimatimeBeforeFirstSpawn()
    TriggerEvent('cm-characters:client:characterReady', payload.charId or (currentCharData and currentCharData.charId))

    SetTimeout(250, function()
        if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(350) end
    end)
end)

-- Close appearance (shouldn't happen for new chars, but handle it)
RegisterNUICallback('appearanceClose', function(data, cb)
    isInAppearance = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideAll' })
    sendCreationLoading(false)
    TriggerEvent('cm-characters:client:setWorldLock', 'creator', false)
    setCreationState(false)
    setCreationHudVisible(true)
    DeleteAppearanceCam()
    cb('ok')
end)


-- Capture current ped components after inventory clothing changes and save them.
local function CaptureCurrentAppearance()
    local ped = PlayerPedId()

    -- Copy first so we do not accidentally mutate and send stale/default face data.
    local data = CopyTable(tempSkinTable)

    data['tshirt_1'] = GetPedDrawableVariation(ped, 8)
    data['tshirt_2'] = GetPedTextureVariation(ped, 8)
    data['torso_1'] = GetPedDrawableVariation(ped, 11)
    data['torso_2'] = GetPedTextureVariation(ped, 11)
    data['arms'] = GetPedDrawableVariation(ped, 3)
    data['arms_2'] = GetPedTextureVariation(ped, 3)
    data['pants_1'] = GetPedDrawableVariation(ped, 4)
    data['pants_2'] = GetPedTextureVariation(ped, 4)
    data['shoes_1'] = GetPedDrawableVariation(ped, 6)
    data['shoes_2'] = GetPedTextureVariation(ped, 6)
    data['chain_1'] = GetPedDrawableVariation(ped, 7)
    data['chain_2'] = GetPedTextureVariation(ped, 7)
    data['bags_1'] = GetPedDrawableVariation(ped, 5)
    data['bags_2'] = GetPedTextureVariation(ped, 5)
    data['helmet_1'] = GetPedPropIndex(ped, 0)
    data['helmet_2'] = GetPedPropTextureIndex(ped, 0)
    data['glasses_1'] = GetPedPropIndex(ped, 1)
    data['glasses_2'] = GetPedPropTextureIndex(ped, 1)
    data['ears_1'] = GetPedPropIndex(ped, 2)
    data['ears_2'] = GetPedPropTextureIndex(ped, 2)
    data['watches_1'] = GetPedPropIndex(ped, 6)
    data['watches_2'] = GetPedPropTextureIndex(ped, 6)

    tempSkinTable = data
    return data
end

RegisterNetEvent('cm-characters:client:captureCurrentAppearance', function()
    CaptureCurrentAppearance()
end)

RegisterNetEvent('cm-characters:client:requestCurrentAppearanceSave', function()
    local data = CaptureCurrentAppearance()
    TriggerServerEvent('cm-characters:server:saveCurrentAppearance', data)
end)

exports('CaptureCurrentAppearance', CaptureCurrentAppearance)
