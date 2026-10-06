-- cm-characters appearance client
-- Integrates vms_charcreator for character customization


-- Production-safe local logger wrapper.
-- When Config.Debug/Config.VerboseLogs is false, normal CM-CHARACTERS debug prints are hidden.
-- Warnings/errors still print so real problems are visible.
local __cmCharactersPrint = print
local function __cmCharactersShouldVerbose()
    return Config and (Config.Debug == true or Config.VerboseLogs == true or Config.ProductionMode == false)
end
local function print(...)
    if __cmCharactersShouldVerbose() then
        return __cmCharactersPrint(...)
    end

    local first = tostring(select(1, ...) or '')
    local isCmCharactersLog = first:find('%[CM%-CHARACTERS') ~= nil
    if not isCmCharactersLog then
        return __cmCharactersPrint(...)
    end

    local upper = first:upper()
    if upper:find('ERROR', 1, true) or upper:find('WARNING', 1, true) or upper:find('FAILED', 1, true) or upper:find('DENIED', 1, true) then
        return __cmCharactersPrint(...)
    end
end

local appearanceCam = nil
local appearanceOffset = nil
local camTargetPos = nil
local camBaseCoord = nil
local camHeightOffset = 0.0
local camCurrentFov = 34.0
local currentCamCategory = 'hairs'
local currentCharData = nil
local isInAppearance = false
local appearanceSavePending = false

-- PHASE 4C: identity-screen gender preview state. While the player is on the
-- Basic Identity screen, the real ped is already parked in the creator room
-- wearing the currently-selected gender's freemode model + a clean base
-- appearance. openAppearance() below reuses this instead of redoing the
-- whole teleport/model-load/fade sequence, so there is no second visible
-- flash on the Identity -> Appearance handoff.
local identityPreviewActive = false
local identityPreviewGender = nil
local identityPreviewToken = 0
local appearanceServiceMode = nil

-- Config (from vms_charcreator adapted for cm)
-- creatingCoords/afterSpawnCoords now come from config.lua (Config.CharacterCreatorRoom/
-- Config.CharacterFirstSpawnCoords) so client/creator.lua's gender-preview code
-- can share the exact same creator-room location — see config.lua for why.
local AppearanceConfig = {
    creatingCoords = Config.CharacterCreatorRoom,
    afterSpawnCoords = Config.CharacterFirstSpawnCoords,
    defaultCamDistance = 0.95,
    cameraHeight = {
        ['parents'] = {z = 0.65, fov = 30.0},
        ['face'] = {z = 0.65, fov = 30.0},
        ['hairs'] = {z = 0.65, fov = 30.0},
        ['clothes'] = {z = -0.1, fov = 100.0},
    },
    animDict = "anim@heists@heist_corona@team_idles@male_a",
    animName = "idle",
    handsUpAnim = {'missminuteman_1ig_2', 'handsup_enter', 50},
    handsUpKey = 'x',
    sounds = true,
    blur = true
}

-- Categories enabled. clothesets (outfit packs) and makeup were removed
-- entirely (dead code — never enabled in any flow; see the appearance-system
-- audit) rather than kept as permanently-false flags.
local EnabledCategories = {
    ['parents'] = true,
    ['face'] = true,
    ['hairs'] = true,
    ['clothes'] = true, -- first creation only: choose starter shirt/pants/shoes
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
local CaptureCurrentAppearance = nil

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
        eyebrows_1 = 0, eyebrows_2 = 10, eyebrows_3 = 0, eyebrows_4 = 0, eyebrows_5 = 0, eyebrows_6 = 0,
        makeup_1 = 0, makeup_2 = 0, makeup_3 = 0, makeup_4 = 0,
        lipstick_1 = 0, lipstick_2 = 0, lipstick_3 = 0, lipstick_4 = 0,
        ears_1 = -1, ears_2 = 0, chest_1 = 0, chest_2 = 10, chest_3 = 0,
        bodyb_1 = -1, bodyb_2 = 0, bodyb_3 = -1, bodyb_4 = 0,
        age_1 = 0, age_2 = 0, blemishes_1 = 0, blemishes_2 = 0,
        blush_1 = 0, blush_2 = 0, blush_3 = 0, complexion_1 = 0, complexion_2 = 0,
        sun_1 = 0, sun_2 = 0, moles_1 = 0, moles_2 = 0,
        beard_1 = 0, beard_2 = 10, beard_3 = 0, beard_4 = 0
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
        hair_2 = GetNumberOfPedTextureVariations(ped, 2, tonumber(tempSkinTable['hair_1']) or 0) - 1,
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
        ears_2 = GetNumberOfPedPropTextureVariations(ped, 2, tonumber(tempSkinTable['ears_1']) or 0) - 1,
        tshirt_1 = 0,
        tshirt_2 = 0,
        torso_1 = 1,
        torso_2 = 0,
        decals_1 = GetNumberOfPedDrawableVariations(ped, 10) - 1,
        decals_2 = GetNumberOfPedTextureVariations(ped, 10, tonumber(tempSkinTable['decals_1']) or 0) - 1,
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
-- Each logical group below runs in its OWN pcall on purpose (see Phase 3's
-- fix in client/main.lua applySkinToPed, and the same fix in client/apply.lua
-- applyAppearance, for the exact failure mode this prevents). This function
-- is called from openAppearance/openAppearanceService/appearanceClose with
-- NO surrounding pcall at all in most call sites, so previously a single bad
-- native anywhere here (e.g. an out-of-range head-blend id) would raise an
-- uncaught Lua error and abort every group after it with no recovery.
local function ApplySkin(skin)
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    skin = type(skin) == 'table' and skin or {}

    local function n(key, fallback)
        local val = skin[key]
        return tonumber(val) or tonumber(fallback) or 0
    end

    local hc1 = n('hair_color_1', 0)
    local isFemale = (GetEntityModel(ped) == GetHashKey('mp_f_freemode_01')) or (skin['sex'] == 1 or skin['sex'] == '1' or skin['sex'] == 'female')

    local headOk, headErr = pcall(function()
        -- Head blend
        local face_weight = n('face_md_weight', 50) / 100.0
        local skin_weight = n('skin_md_weight', 50) / 100.0
        SetPedHeadBlendData(ped, n('mom', 21), n('dad', 0), 0, n('mom', 21), n('dad', 0), 0, face_weight, skin_weight, 0.0, false)

        -- Face features
        SetPedFaceFeature(ped, 0, (n('nose_1', 0) / 10.0))
        SetPedFaceFeature(ped, 1, (n('nose_2', 0) / 10.0))
        SetPedFaceFeature(ped, 2, (n('nose_3', 0) / 10.0))
        SetPedFaceFeature(ped, 3, (n('nose_4', 0) / 10.0))
        SetPedFaceFeature(ped, 4, (n('nose_5', 0) / 10.0))
        SetPedFaceFeature(ped, 5, (n('nose_6', 0) / 10.0))
        SetPedFaceFeature(ped, 8, (n('cheeks_1', 0) / 10.0))
        SetPedFaceFeature(ped, 9, (n('cheeks_2', 0) / 10.0))
        SetPedFaceFeature(ped, 10, (n('cheeks_3', 0) / 10.0))
        SetPedFaceFeature(ped, 12, (n('lip_thickness', 0) / 10.0))
        SetPedFaceFeature(ped, 13, (n('jaw_1', 0) / 10.0))
        SetPedFaceFeature(ped, 14, (n('jaw_2', 0) / 10.0))
        SetPedFaceFeature(ped, 15, (n('chin_1', 0) / 10.0))
        SetPedFaceFeature(ped, 16, (n('chin_2', 0) / 10.0))
        SetPedFaceFeature(ped, 17, (n('chin_3', 0) / 10.0))
        SetPedFaceFeature(ped, 18, (n('chin_4', 0) / 10.0))
        SetPedFaceFeature(ped, 19, (n('neck_thickness', 0) / 10.0))
    end)
    if not headOk then
        print('[CM-CHARACTERS] WARNING ApplySkin head-blend/face-feature group failed: ' .. tostring(headErr))
    end

    local overlayOk, overlayErr = pcall(function()
        SetPedHeadOverlay(ped, 3, n('age_1', 0), (n('age_2', 0) / 10.0))
        SetPedHeadOverlay(ped, 0, n('blemishes_1', 0), (n('blemishes_2', 0) / 10.0))
        SetPedEyeColor(ped, n('eye_color', 0))

        -- Eyebrows
        local eb1 = n('eyebrows_1', 0)
        local eb2 = n('eyebrows_2', 10) / 10.0
        if eb1 >= 0 and eb1 ~= 255 and eb2 <= 0.0 then eb2 = 1.0 end
        local eb3 = n('eyebrows_3', hc1)
        local eb4 = n('eyebrows_4', eb3)
        SetPedHeadOverlay(ped, 2, eb1, eb2)
        SetPedHeadOverlayColor(ped, 2, 1, eb3, eb4)
        SetPedFaceFeature(ped, 6, (n('eyebrows_5', 0) / 10.0))
        SetPedFaceFeature(ped, 7, (n('eyebrows_6', 0) / 10.0))

        SetPedHeadOverlay(ped, 4, n('makeup_1', 0), (n('makeup_2', 0) / 10.0))
        SetPedHeadOverlayColor(ped, 4, 2, n('makeup_3', 0), n('makeup_4', 0))
        SetPedHeadOverlay(ped, 8, n('lipstick_1', 0), (n('lipstick_2', 0) / 10.0))
        SetPedHeadOverlayColor(ped, 8, 1, n('lipstick_3', 0), n('lipstick_4', 0))

        SetPedHeadOverlay(ped, 5, n('blush_1', 0), (n('blush_2', 0) / 10.0))
        SetPedHeadOverlayColor(ped, 5, 2, n('blush_3', 0), n('blush_3', 0))
        SetPedHeadOverlay(ped, 6, n('complexion_1', 0), (n('complexion_2', 0) / 10.0))
        SetPedHeadOverlay(ped, 7, n('sun_1', 0), (n('sun_2', 0) / 10.0))
        SetPedHeadOverlay(ped, 9, n('moles_1', 0), (n('moles_2', 0) / 10.0))
    end)
    if not overlayOk then
        print('[CM-CHARACTERS] WARNING ApplySkin overlay group failed: ' .. tostring(overlayErr))
    end

    local hairOk, hairErr = pcall(function()
        local h1 = n('hair_1', 0)
        local h2 = n('hair_2', 0)
        local hc2 = n('hair_color_2', hc1)
        SetPedComponentVariation(ped, 2, h1, h2, 2)
        SetPedHairColor(ped, hc1, hc2)
    end)
    if not hairOk then
        print('[CM-CHARACTERS] WARNING ApplySkin hair group failed: ' .. tostring(hairErr))
    end

    local beardChestOk, beardChestErr = pcall(function()
        -- Beard & Chest Hair: STRICT GENDER CHECK
        if isFemale then
            SetPedHeadOverlay(ped, 1, 255, 0.0)
            SetPedHeadOverlay(ped, 10, 255, 0.0)
        else
            local b1 = n('beard_1', 0)
            local b2 = n('beard_2', 0) / 10.0
            if b1 <= 0 or b1 == 255 or b2 <= 0.0 then
                SetPedHeadOverlay(ped, 1, 255, 0.0)
            else
                local b3 = n('beard_3', hc1)
                local b4 = n('beard_4', b3)
                SetPedHeadOverlay(ped, 1, b1, b2)
                SetPedHeadOverlayColor(ped, 1, 1, b3, b4)
            end

            local ch1 = n('chest_1', 0)
            local ch2 = n('chest_2', 0) / 10.0
            if ch1 <= 0 or ch1 == 255 or ch2 <= 0.0 then
                SetPedHeadOverlay(ped, 10, 255, 0.0)
            else
                local ch3 = n('chest_3', 0)
                SetPedHeadOverlay(ped, 10, ch1, ch2)
                SetPedHeadOverlayColor(ped, 10, 1, ch3, ch3)
            end
        end
    end)
    if not beardChestOk then
        print('[CM-CHARACTERS] WARNING ApplySkin beard/chest group failed: ' .. tostring(beardChestErr))
    end

    if appearanceServiceMode ~= 'barber' then
        local propsOk, propsErr = pcall(function()
            -- Props (nil-safe)
            local _ears      = tonumber(skin['ears_1'])
            local _helmet    = tonumber(skin['helmet_1'])
            local _glasses   = tonumber(skin['glasses_1'])
            local _watches   = tonumber(skin['watches_1'])
            local _bracelets = tonumber(skin['bracelets_1'])

            if _ears      == nil or _ears      < 0 then ClearPedProp(ped, 2) else SetPedPropIndex(ped, 2, _ears,      n('ears_2', 0), true) end
            if _helmet    == nil or _helmet    < 0 then ClearPedProp(ped, 0) else SetPedPropIndex(ped, 0, _helmet,    n('helmet_2', 0), true) end
            if _glasses   == nil or _glasses   < 0 then ClearPedProp(ped, 1) else SetPedPropIndex(ped, 1, _glasses,   n('glasses_2', 0), true) end
            if _watches   == nil or _watches   < 0 then ClearPedProp(ped, 6) else SetPedPropIndex(ped, 6, _watches,   n('watches_2', 0), true) end
            if _bracelets == nil or _bracelets < 0 then ClearPedProp(ped, 7) else SetPedPropIndex(ped, 7, _bracelets, n('bracelets_2', 0), true) end
        end)
        if not propsOk then
            print('[CM-CHARACTERS] WARNING ApplySkin props group failed: ' .. tostring(propsErr))
        end

        local componentsOk, componentsErr = pcall(function()
            -- Components
            SetPedComponentVariation(ped, 8,  n('tshirt_1', 15), n('tshirt_2', 0), 2)
            SetPedComponentVariation(ped, 11, n('torso_1', 15),  n('torso_2', 0), 2)
            SetPedComponentVariation(ped, 3,  n('arms', 15),     n('arms_2', 0), 2)
            SetPedComponentVariation(ped, 10, n('decals_1', 0),  n('decals_2', 0), 2)
            SetPedComponentVariation(ped, 4,  n('pants_1', 14),  n('pants_2', 0), 2)
            SetPedComponentVariation(ped, 6,  n('shoes_1', 34),  n('shoes_2', 0), 2)
            SetPedComponentVariation(ped, 1,  n('mask_1', 0),    n('mask_2', 0), 2)
            SetPedComponentVariation(ped, 9,  n('bproof_1', 0),  n('bproof_2', 0), 2)
            SetPedComponentVariation(ped, 7,  n('chain_1', 0),   n('chain_2', 0), 2)
            SetPedComponentVariation(ped, 5,  n('bags_1', 0),    n('bags_2', 0), 2)
        end)
        if not componentsOk then
            print('[CM-CHARACTERS] WARNING ApplySkin components group failed: ' .. tostring(componentsErr))
        end
    end
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
        {name = 'eyebrows_2', value = 10, min = 0},
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
        {name = 'chest_2', value = 10, min = 0},
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
        {name = 'beard_2', value = 10, min = 0},
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

-- CHARACTER CREATION REPAIR PASS: one authoritative camera preset table,
-- decoupled from whatever string names a category happens to use. Root
-- cause of the HAIR (and EYES) body-camera bug: this function used to
-- compare the incoming category directly against the OLD internal Lua data
-- names ('hairs', 'face', 'parents') to decide head-vs-body framing. Phase 4C's
-- UI (ui/appearance/app.js CATEGORY_DEFS) sends its OWN display-category keys
-- straight through unchanged -- 'face' happened to still match, but 'hair'
-- (new, singular) never matched 'hairs' (old, plural), and 'eyes' has no old
-- equivalent at all -- both silently fell through to the BODY branch.
--
-- CameraCategoryToPreset maps every category string this function has ever
-- been called with (new UI keys AND old/internal Lua item-group names, since
-- barber/surgery/gender service modes still pass the old names) to one of
-- four semantic presets. Anything NOT in this table defaults to HEAD, never
-- BODY -- only an explicit clothing category may ever request the full-body
-- preset.
local CameraCategoryToPreset = {
    -- current UI display categories (ui/appearance/app.js)
    face = 'HEAD',
    hair = 'HAIR',
    eyes = 'EYES',
    clothing = 'BODY',
    -- old/internal Lua items-group names (barber/surgery/gender service modes)
    parents = 'HEAD',
    hairs = 'HAIR',
    clothes = 'BODY',
}

-- fov: camera field of view. dist: distance back from the target along the
-- ped's forward vector. zOffset: added to the head-bone Z (ignored for BODY,
-- which frames off the ped's root coords instead of the head bone).
local CameraPresets = {
    HEAD = { fov = 32.0, dist = 0.90, zOffset = 0.04 },
    -- Slightly wider FOV and a touch higher than HEAD so the full hairstyle
    -- (including volume above the scalp) stays in frame.
    HAIR = { fov = 36.0, dist = 1.05, zOffset = 0.14 },
    -- Slightly closer than HEAD for a tight eye-level shot.
    EYES = { fov = 24.0, dist = 0.62, zOffset = 0.00 },
    BODY = { fov = 48.0, dist = 2.40, zOffset = 0.10 },
}

local function resolveCameraPreset(category)
    -- Barber/hair service always frames HAIR regardless of which specific
    -- field is being edited -- defense in depth on top of the category
    -- mapping above (barber only ever populates the 'hairs' items group, so
    -- 'hairs'/'hair' would already resolve to HAIR on their own).
    if appearanceServiceMode == 'barber' then return 'HAIR' end
    return CameraCategoryToPreset[category] or 'HEAD'
end

-- Token-guarded short interpolation so a rapid run of category switches can
-- never leave two competing transitions fighting over the same camera, and a
-- stale one from a superseded switch aborts instead of continuing to write
-- frames after a newer switch has already taken over.
local cameraTransitionToken = 0

local function animateAppearanceCam(fromCoord, fromTarget, fromFov, toCoord, toTarget, toFov, durationMs)
    cameraTransitionToken = cameraTransitionToken + 1
    local myToken = cameraTransitionToken
    local startedAt = GetGameTimer()

    CreateThread(function()
        while true do
            if myToken ~= cameraTransitionToken then return end
            if not DoesCamExist(appearanceCam) then return end

            local t = math.min(1.0, (GetGameTimer() - startedAt) / durationMs)
            local cx = fromCoord.x + (toCoord.x - fromCoord.x) * t
            local cy = fromCoord.y + (toCoord.y - fromCoord.y) * t
            local cz = fromCoord.z + (toCoord.z - fromCoord.z) * t
            local tx = fromTarget.x + (toTarget.x - fromTarget.x) * t
            local ty = fromTarget.y + (toTarget.y - fromTarget.y) * t
            local tz = fromTarget.z + (toTarget.z - fromTarget.z) * t
            local fv = fromFov + (toFov - fromFov) * t

            SetCamCoord(appearanceCam, cx, cy, cz)
            PointCamAtCoord(appearanceCam, tx, ty, tz)
            SetCamFov(appearanceCam, fv)

            if t >= 1.0 then return end
            Wait(0)
        end
    end)
end

local function UpdateCameraPosition(category)
    if not DoesCamExist(appearanceCam) then return end
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end

    local previousCategory = currentCamCategory
    category = category or currentCamCategory or 'hair'
    currentCamCategory = category

    -- A category switch always re-establishes the preset's base framing.
    -- Any manual drag-height nudge from a previous category must never bleed
    -- into the new one (this was silently retained before -- a body-view
    -- height nudge, on the same scale as a 2.4-unit shot, looked wildly
    -- exaggerated once carried over onto a ~0.9-unit head shot).
    local hadHeightOffset = camHeightOffset ~= 0.0
    camHeightOffset = 0.0

    local preset = resolveCameraPreset(category)
    local presetCfg = CameraPresets[preset]

    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)

    local targetZ, dist, fov
    local newTargetPos, newBaseCoord

    if preset == 'BODY' then
        dist = presetCfg.dist
        fov = presetCfg.fov
        targetZ = coords.z + presetCfg.zOffset

        newTargetPos = vector3(coords.x, coords.y, targetZ)
        newBaseCoord = vector3(
            coords.x + forward.x * dist,
            coords.y + forward.y * dist,
            targetZ + 0.04
        )
    else
        -- Prefer a stable, ped-relative head-bone position (works across
        -- male/female models, animations, and model swaps) with a sanity
        -- fallback if the bone lookup is ever unreasonable.
        local headBone = GetPedBoneIndex(ped, 31086)
        local headPos
        if headBone ~= -1 then
            headPos = GetWorldPositionOfEntityBone(ped, headBone)
        end
        if not headPos or #(headPos - coords) > 2.5 then
            headPos = vector3(coords.x, coords.y, coords.z + 0.72)
        end

        dist = presetCfg.dist
        fov = presetCfg.fov
        targetZ = headPos.z + presetCfg.zOffset

        newTargetPos = vector3(headPos.x, headPos.y, targetZ)
        newBaseCoord = vector3(
            headPos.x + forward.x * dist,
            headPos.y + forward.y * dist,
            targetZ + 0.04
        )
    end

    local presetChanged = previousCategory ~= category
    local canInterpolate = presetChanged and not hadHeightOffset and camBaseCoord and camTargetPos
    -- Capture the OLD camera state before overwriting the module-level
    -- values below -- animateAppearanceCam needs distinct from/to endpoints.
    local oldBaseCoord, oldTargetPos, oldFov = camBaseCoord, camTargetPos, camCurrentFov

    camTargetPos = newTargetPos
    camBaseCoord = newBaseCoord
    camCurrentFov = fov

    if canInterpolate then
        -- Short, tasteful transition (~220ms) between two established
        -- framings. No transition on first activation/reset (no previous
        -- coords to blend from) and no transition if a drag-height nudge was
        -- active (snap cleanly to the new base instead of easing from an
        -- offset position).
        animateAppearanceCam(oldBaseCoord, oldTargetPos, oldFov, newBaseCoord, newTargetPos, fov, 220)
    else
        cameraTransitionToken = cameraTransitionToken + 1 -- cancel any in-flight transition
        SetCamCoord(appearanceCam, camBaseCoord.x, camBaseCoord.y, camBaseCoord.z)
        PointCamAtCoord(appearanceCam, camTargetPos.x, camTargetPos.y, camTargetPos.z)
        SetCamFov(appearanceCam, camCurrentFov)
    end
end

-- Create camera with head-level framing and crisp clear rendering
local function CreateAppearanceCam(category)
    if not DoesCamExist(appearanceCam) then
        appearanceCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    end
    local ped = PlayerPedId()
    camHeightOffset = 0.0
    category = category or (appearanceServiceMode == 'barber' and 'hairs' or 'hairs')

    SetCamActive(appearanceCam, true)
    RenderScriptCams(true, true, 500, true, true)
    UpdateCameraPosition(category)

    -- Clear heavy blur DOF so haircut and face details are crystal clear
    ClearTimecycleModifier()

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
    camTargetPos = nil
    camBaseCoord = nil
    camHeightOffset = 0.0
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

-- Safe model/base-appearance choreography shared by the Basic Identity
-- gender dropdown and the initial Appearance setup (see openAppearance
-- below). Token-guarded: if a newer call starts while an older one is still
-- waiting on model load, the older one notices it is stale after every yield
-- and abandons without touching the ped — rapid Male/Female/Male/Female
-- switching can never leave two half-applied models or a stray duplicate,
-- and a slow/late model load can never "win" over a newer selection.
local function PrepareCreatorPreview(genderInput, opts)
    opts = type(opts) == 'table' and opts or {}
    local sex = (genderInput == 'female' or genderInput == 1 or genderInput == '1') and 1 or 0
    local gender = sex == 1 and 'female' or 'male'

    identityPreviewToken = identityPreviewToken + 1
    local myToken = identityPreviewToken

    local firstSetup = opts.firstSetup == true or not identityPreviewActive

    if firstSetup then
        sendCreationLoading(true, 'Preparing character creator...')
        DoScreenFadeOut(250)
        Wait(250)
        if myToken ~= identityPreviewToken then return end

        local ped = PlayerPedId()
        lastCoords = {
            x = GetEntityCoords(ped).x,
            y = GetEntityCoords(ped).y,
            z = GetEntityCoords(ped).z,
            w = GetEntityHeading(ped)
        }

        loadCreatorCollision(AppearanceConfig.creatingCoords)
        if myToken ~= identityPreviewToken then return end

        SetEntityCoordsNoOffset(ped, AppearanceConfig.creatingCoords.x, AppearanceConfig.creatingCoords.y, AppearanceConfig.creatingCoords.z, false, false, false)
        SetEntityHeading(ped, AppearanceConfig.creatingCoords.w)
        FreezeEntityPosition(ped, true)
    else
        -- Already parked in the creator room, just switching gender: hide,
        -- swap model, reveal — no re-fade, no re-teleport of the world.
        SetEntityVisible(PlayerPedId(), false, false)
    end

    local model = sex == 0 and GetHashKey('mp_m_freemode_01') or GetHashKey('mp_f_freemode_01')
    RequestModel(model)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        RequestModel(model)
        Wait(0)
        if myToken ~= identityPreviewToken then
            SetModelAsNoLongerNeeded(model)
            return
        end
    end
    if myToken ~= identityPreviewToken then
        SetModelAsNoLongerNeeded(model)
        return
    end
    if not HasModelLoaded(model) then
        print('[CM-CHARACTERS] WARNING: PrepareCreatorPreview model load timed out for ' .. tostring(gender) .. ', continuing anyway')
    end

    SetPlayerModel(PlayerId(), model)
    SetModelAsNoLongerNeeded(model)
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, AppearanceConfig.creatingCoords.x, AppearanceConfig.creatingCoords.y, AppearanceConfig.creatingCoords.z, false, false, false)
    SetEntityHeading(ped, AppearanceConfig.creatingCoords.w)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetPedComponentVariation(ped, 0, 0, 0, 2)

    if firstSetup then
        InitSkinData()
    end
    tempSkinTable['sex'] = sex
    local mySex = sex == 0 and 'm' or 'f'
    for k, v in pairs(FirstCreationClothes[mySex]) do
        tempSkinTable[k] = v
    end
    ApplySkin(tempSkinTable)

    if myToken ~= identityPreviewToken then return end

    SetEntityVisible(PlayerPedId(), true, false)
    identityPreviewActive = true
    identityPreviewGender = gender

    if firstSetup then
        DoScreenFadeIn(350)
        CreateAppearanceCam()
        sendCreationLoading(false)
    elseif DoesCamExist(appearanceCam) then
        UpdateCameraPosition(currentCamCategory)
    end
end

RegisterNetEvent('cm-characters:client:prepareIdentityPreview', function(gender, firstSetup)
    PrepareCreatorPreview(gender, { firstSetup = firstSetup == true })
end)

RegisterNUICallback('creatorGenderChanged', function(data, cb)
    PrepareCreatorPreview(data and data.gender or 'male', {})
    cb('ok')
end)

-- Cleanup when the player leaves Basic Identity back to the Selector without
-- ever reaching Appearance (see client/creator.lua's closeCreator). The
-- selector's own re-entry (spawnPreviewPeds/hideRealPlayerForSelector) takes
-- over hiding/repositioning the real player from here.
RegisterNetEvent('cm-characters:client:cleanupIdentityPreview', function()
    if identityPreviewActive and DoesCamExist(appearanceCam) then
        SetCamActive(appearanceCam, false)
        RenderScriptCams(false, true, 300, true, true)
    end
    appearanceCam = nil
    FreezeEntityPosition(PlayerPedId(), false)
    identityPreviewActive = false
    identityPreviewGender = nil
end)

-- Open appearance editor
AddEventHandler('cm-characters:client:openAppearance', function(charData)
    appearanceServiceMode = nil
    currentCharData = charData
    isInAppearance = true
    TriggerEvent('cm-characters:client:setWorldLock', 'creator', true)
    setCreationState(true)
    setCreationHudVisible(false)

    local wantedGender = (charData.gender == 'female') and 'female' or 'male'

    if identityPreviewActive and identityPreviewGender == wantedGender then
        -- PHASE 4C: Basic Identity already parked the correct freemode model
        -- + base appearance in the creator room. Reuse it — do NOT
        -- teleport/reload the model/fade a second time, that second flash is
        -- exactly what this feature's handoff requirement forbids.
        if not DoesCamExist(appearanceCam) then
            CreateAppearanceCam()
        end
    else
        -- Fallback: full original setup. Covers Appearance being entered
        -- from anywhere that did NOT go through Basic Identity (or a
        -- mismatched-gender edge case) — this path stays fully self-sufficient.
        sendCreationLoading(true, 'Preparing character creator...')
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

        local sex = wantedGender == 'female' and 1 or 0
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

        InitSkinData()
        tempSkinTable['sex'] = sex
        local mySex = sex == 0 and 'm' or 'f'
        for k, v in pairs(FirstCreationClothes[mySex]) do
            tempSkinTable[k] = v
        end
        ApplySkin(tempSkinTable)
        SetEntityVisible(PlayerPedId(), true, false)

        DoScreenFadeIn(350)
        CreateAppearanceCam()
        sendCreationLoading(false)

        identityPreviewActive = true
        identityPreviewGender = wantedGender
    end

    -- Build UI data
    local uiData = GetComponentData()
    local ped = PlayerPedId()

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
        enableCancelButtonUI = true, -- PHASE 4C: Back to Identity is now supported for new chars
        playerHasAlreadySkin = false,
        charId = charData.charId
    })

    SetNuiFocus(true, true)
    sendCreationLoading(false)
end)

local function FetchActiveCharacterAppearance()
    local p = promise.new()
    local resolved = false
    local reqId = tostring(GetGameTimer()) .. '_' .. tostring(math.random(1000, 9999))
    local handler = nil
    handler = AddEventHandler('cm-characters:client:receiveAppearanceData', function(id, data)
        if tostring(id) == reqId and not resolved then
            resolved = true
            p:resolve(data)
        end
    end)
    TriggerServerEvent('cm-characters:server:requestAppearanceData', reqId)
    SetTimeout(1500, function()
        if not resolved then
            resolved = true
            p:resolve(nil)
        end
    end)
    local res = Citizen.Await(p)
    if handler then pcall(RemoveEventHandler, handler) end
    return res
end

-- Opens the existing editor for an active character without entering the
-- first-character creation/spawn flow. Callers may expose only the service
-- categories they own; cm-characters still owns the save operation.
AddEventHandler('cm-characters:client:openAppearanceService', function(options)
    if isInAppearance then return end
    options = type(options) == 'table' and options or {}

    local service = tostring(options.service or '')
    if service ~= 'gender' and service ~= 'surgery' and service ~= 'barber' then return end

    local charId = LocalPlayer.state.charId or LocalPlayer.state.characterId
    if not charId then
        TriggerEvent('cm-characters:client:error', 'No active character is available for this service.')
        TriggerEvent('cm-ems:client:appearanceServiceClosed')
        return
    end
    local ped = PlayerPedId()
    local isFemalePed = (GetEntityModel(ped) == GetHashKey('mp_f_freemode_01'))

    -- Initialize default skin baseline if not yet populated
    if not SkinData or not next(SkinData) then
        InitSkinData()
    end

    -- 1. Use cached authentic appearance, or query active character appearance from DB, or baseline
    local charAppearance = nil
    if type(lastSkin) == 'table' and next(lastSkin) and lastSkin['face_md_weight'] ~= nil then
        charAppearance = CopyTable(lastSkin)
    else
        charAppearance = FetchActiveCharacterAppearance()
    end

    if type(charAppearance) == 'table' and next(charAppearance) then
        tempSkinTable = CopyTable(charAppearance)
    elseif not next(tempSkinTable) then
        -- No cached appearance and the server didn't respond in time: refuse to open
        -- the editor rather than silently saving generic baseline defaults over the
        -- character's real face/body.
        TriggerEvent('cm-characters:client:error', 'Could not load your character appearance. Please try again.')
        TriggerEvent('cm-ems:client:appearanceServiceClosed')
        return
    end

    -- Ensure every single baseline key is present so nothing is ever nil
    for k, v in pairs(SkinData or {}) do
        if tempSkinTable[k] == nil then
            tempSkinTable[k] = v
        end
    end

    appearanceServiceMode = service
    currentCharData = { charId = charId, serviceMode = service }
    isInAppearance = true

    -- Strictly enforce genuine active ped gender and prevent cross-gender overlays
    if isFemalePed then
        tempSkinTable.sex = 1
        tempSkinTable.beard_1 = 255
        tempSkinTable.beard_2 = 0
        tempSkinTable.chest_1 = 255
        tempSkinTable.chest_2 = 0
    else
        tempSkinTable.sex = 0
    end

    if service == 'barber' then
        local currentHair = GetPedDrawableVariation(ped, 2)
        if (tonumber(tempSkinTable.hair_1) == nil or tonumber(tempSkinTable.hair_1) <= 0) and currentHair and currentHair > 0 then
            tempSkinTable.hair_1 = currentHair
            tempSkinTable.hair_2 = GetPedTextureVariation(ped, 2)
        end
        if (tonumber(tempSkinTable.eyebrows_2) or 0) <= 0 then
            tempSkinTable.eyebrows_2 = 10
        end
        if tempSkinTable.eyebrows_3 == nil then
            tempSkinTable.eyebrows_3 = tempSkinTable.hair_color_1 or 0
        end
        if tempSkinTable.eyebrows_4 == nil then
            tempSkinTable.eyebrows_4 = tempSkinTable.eyebrows_3
        end
    else
        for key, value in pairs(lastSkin or {}) do tempSkinTable[key] = value end
    end

    lastSkin = CopyTable(tempSkinTable)

    local coords = GetEntityCoords(ped)
    lastCoords = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(ped) }

    if service == 'barber' then
        -- In barber shops, players face the counter/NPC. Turn ped 180 degrees away from counter
        -- so ped faces out into the open salon floor with clear line-of-sight directly into the camera.
        local openHeading = (GetEntityHeading(ped) + 180.0) % 360.0
        SetEntityHeading(ped, openHeading)
    end

    -- Active character services edit in place with Try-Before-Buy crash/cancel safety.
    FreezeEntityPosition(ped, true)
    ApplySkin(tempSkinTable)
    CreateAppearanceCam(service == 'barber' and 'hairs' or 'hairs')

    local categories
    local items
    if service == 'gender' then
        categories = { parents = true }
        items = {
            parents = { sex = true, parents = false, face_md_weight = false, skin_md_weight = false }
        }
    elseif service == 'barber' then
        categories = { hairs = true }
        items = {
            hairs = {
                hair = true,
                eyebrow = true,
                beard = not isFemalePed,
                chesthair = not isFemalePed
            }
        }
    else
        categories = { parents = true, face = true }
        items = {
            parents = { sex = false, parents = true, face_md_weight = true, skin_md_weight = true },
            face = AvailableItems.face,
        }
    end

    local serviceCost = tonumber(options and options.cost) or (service == 'barber' and 100 or 0)
    SendNUIMessage({
        action = 'openAppearance',
        serviceMode = service,
        serviceCost = serviceCost,
        categories = categories,
        items = items,
        data = GetComponentData(),
        currentRotate = GetEntityHeading(PlayerPedId()),
        currentDistance = 30,
        clotheSets = {},
        handsUpKey = AppearanceConfig.handsUpKey,
        enableHandsUpButton = false,
        enableCancelButtonUI = true,
        playerHasAlreadySkin = true,
        charId = charId,
    })

    SetNuiFocus(true, true)

    -- Guard against external dialogue or transition cameras asynchronously tearing down scripted cams
    CreateThread(function()
        Wait(400)
        if isInAppearance and DoesCamExist(appearanceCam) then
            SetCamActive(appearanceCam, true)
            RenderScriptCams(true, false, 0, true, true)
            SetNuiFocus(true, true)
        end
    end)
end)

-- NUI Callbacks for appearance
RegisterNUICallback('appearanceChange', function(data, cb)
    local ok, err = pcall(function()
        if not data or not data.type then return end

        if data.type == 'sex' then
            local sex = tonumber(data.new)
            local model = sex == 0 and GetHashKey('mp_m_freemode_01') or GetHashKey('mp_f_freemode_01')
            if not appearanceServiceMode then
                sendCreationLoading(true, 'Changing character model...')
            end
            RequestModel(model)
            while not HasModelLoaded(model) do
                RequestModel(model)
                Wait(0)
            end
            SetPlayerModel(PlayerId(), model)
            SetPedComponentVariation(PlayerPedId(), 0, 0, 0, 2)
            if appearanceServiceMode and lastCoords then
                SetEntityCoordsNoOffset(PlayerPedId(), lastCoords.x, lastCoords.y, lastCoords.z, false, false, false)
                SetEntityHeading(PlayerPedId(), lastCoords.w)
                FreezeEntityPosition(PlayerPedId(), true)
            end
            if not appearanceServiceMode then
                sendCreationLoading(false)
            end
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
            if data.type == 'eyebrows_1' then
                if (tonumber(tempSkinTable['eyebrows_2']) or 0) <= 0 then
                    tempSkinTable['eyebrows_2'] = 10
                    SendNUIMessage({ action = 'setValue', item = 'eyebrows_2', value = 10 })
                end
            elseif data.type == 'eyebrows_3' then
                tempSkinTable['eyebrows_4'] = tonumber(data.new)
            elseif data.type == 'hair_color_1' then
                if not tempSkinTable['hair_color_2'] or tempSkinTable['hair_color_2'] == 0 then
                    tempSkinTable['hair_color_2'] = tonumber(data.new)
                end
            elseif data.type == 'beard_1' then
                if (tonumber(tempSkinTable['beard_2']) or 0) <= 0 then
                    tempSkinTable['beard_2'] = 10
                    SendNUIMessage({ action = 'setValue', item = 'beard_2', value = 10 })
                end
            elseif data.type == 'beard_3' then
                tempSkinTable['beard_4'] = tonumber(data.new)
            elseif data.type == 'chest_1' then
                if (tonumber(tempSkinTable['chest_2']) or 0) <= 0 then
                    tempSkinTable['chest_2'] = 10
                    SendNUIMessage({ action = 'setValue', item = 'chest_2', value = 10 })
                end
            end
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

        if AppearanceConfig.sounds then
            PlaySoundFrontend(-1, "NAV_LEFT_RIGHT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        end
    end)
    if not ok then
        print('[CM-CHARACTERS] ERROR in appearanceChange callback: ' .. tostring(err))
    end
    if cb then cb('ok') end
end)

RegisterNUICallback('appearanceCamera', function(data, cb)
    if appearanceCam and data.type then
        UpdateCameraPosition(data.type)
    end
    cb('ok')
end)

-- Screen drag rotation and camera nudge (like nv_cloth clothing store)
RegisterNUICallback('appearanceDrag', function(data, cb)
    local ped = PlayerPedId()
    if not ped or ped == 0 then return cb('ok') end

    -- Horizontal drag: smoothly rotate the ped
    if data.deltaX and math.abs(tonumber(data.deltaX) or 0) > 0.005 then
        local delta = tonumber(data.deltaX) or 0.0
        if delta > 30.0 then delta = 30.0 end
        if delta < -30.0 then delta = -30.0 end
        local newHeading = (GetEntityHeading(ped) + delta) % 360.0
        SetEntityHeading(ped, newHeading)
    end

    -- Vertical drag: adjust camera height slightly up or down
    if data.deltaY and math.abs(tonumber(data.deltaY) or 0) > 0.0005 and DoesCamExist(appearanceCam) then
        local dy = tonumber(data.deltaY) or 0.0
        camHeightOffset = math.max(-0.25, math.min(0.35, camHeightOffset + dy))
        if camBaseCoord and camTargetPos then
            SetCamCoord(appearanceCam, camBaseCoord.x, camBaseCoord.y, camBaseCoord.z + camHeightOffset)
            PointCamAtCoord(appearanceCam, camTargetPos.x, camTargetPos.y, camTargetPos.z + (camHeightOffset * 0.5))
        end
    end

    cb('ok')
end)

-- Mouse wheel zoom
RegisterNUICallback('appearanceZoom', function(data, cb)
    if DoesCamExist(appearanceCam) and data.delta then
        local delta = tonumber(data.delta) or 0.0
        camCurrentFov = math.max(18.0, math.min(55.0, camCurrentFov + delta))
        SetCamFov(appearanceCam, camCurrentFov)
    end
    cb('ok')
end)

-- Camera reset
RegisterNUICallback('appearanceResetCam', function(data, cb)
    camHeightOffset = 0.0
    UpdateCameraPosition(currentCamCategory)
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
    if not appearanceServiceMode then
        SendNUIMessage({ action = 'creationLoading', show = true, message = 'Saving character...', percent = 55 })

        -- Hide the transition while the server saves naked/base JSON and inventory re-equips
        -- starter clothes. This prevents the brief default-body blink after pressing Create.
        if not IsScreenFadedOut() and not IsScreenFadingOut() then
            DoScreenFadeOut(150)
            Wait(180)
        end
    end

    -- Server acknowledgement will close the creator after DB/inventory work finishes.
    TriggerServerEvent('cm-characters:server:saveAppearance',
        currentCharData.charId, tempSkinTable, appearanceServiceMode)

    -- Safety: if the server event fails for any reason, do not leave the screen black forever.
    local savedCharId = currentCharData.charId
    SetTimeout(9000, function()
        if appearanceSavePending and currentCharData and tostring(currentCharData.charId) == tostring(savedCharId) then
            appearanceSavePending = false
            isInAppearance = false
            -- spawning=true: this emergency fallback (server never acked the
            -- save) ends in a direct local recovery reveal, not back at the
            -- Selector, so the UI's cached slot-list state is no longer
            -- relevant -- see ui/app.js's hideAll handler.
            SendNUIMessage({ action = 'hideAll', spawning = true })
            DeleteAppearanceCam()
            if appearanceServiceMode then
                appearanceServiceMode = nil
                if lastCoords then
                    SetEntityCoordsNoOffset(PlayerPedId(), lastCoords.x, lastCoords.y, lastCoords.z, false, false, false)
                    SetEntityHeading(PlayerPedId(), lastCoords.w)
                end
                FreezeEntityPosition(PlayerPedId(), false)
                TriggerEvent('cm-ems:client:appearanceServiceClosed')
            else
                setCreationState(false)
                setCreationHudVisible(false)
                -- PHASE 5: the server never acknowledged the save, so we cannot
                -- trust cm-core:characterLoaded to have fired and driven
                -- cm-spawn's normal pipeline. This is the one remaining caller
                -- of the legacy full-recovery characterReady handler: move the
                -- player off the appearance-room coordinate to the configured
                -- safe fallback position before restoring visibility/bucket,
                -- so a genuine server failure never reveals/leaves them at a
                -- creation-room coordinate in the public bucket.
                local ped = PlayerPedId()
                SetEntityCoords(ped, AppearanceConfig.afterSpawnCoords.x, AppearanceConfig.afterSpawnCoords.y, AppearanceConfig.afterSpawnCoords.z)
                SetEntityHeading(ped, AppearanceConfig.afterSpawnCoords.w)
                TriggerEvent('cm-characters:client:characterReady', savedCharId)
            end
            if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(350) end
        end
    end)

    cb('ok')
end)



local function callClimatimeExport(name, payload)
    if GetResourceState('cm-climatime') ~= 'started' then return false end
    local ok = pcall(function()
        exports['cm-climatime'][name](payload)
    end)
    return ok == true
end

local function notifyPreSpawnClimatePhase(phase, payload)
    payload = type(payload) == 'table' and payload or {}
    payload.phase = phase
    payload.source = 'cm-characters'
    payload.startedAt = GetGameTimer()
    TriggerEvent('cm-spawn:client:climatePreloadPhase', payload)
    TriggerEvent('cm-climatime:client:preSpawnPhase', payload)
    TriggerEvent('cm-climatime:client:requestSync', payload.reason or 'cm-characters-pre-spawn')
end

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

    notifyPreSpawnClimatePhase('starting', payload)

    local preparedByExport = callClimatimeExport('PrepareBeforeSpawn', payload)
        or callClimatimeExport('PreloadBeforeSpawn', payload)
        or callClimatimeExport('RequestPreSpawnSync', payload)
        or callClimatimeExport('SyncNow', payload)

    TriggerEvent('cm-climatime:client:prepareBeforeSpawn', payload)
    TriggerEvent('cm-climatime:client:preloadBeforeSpawn', payload)
    TriggerEvent('cm-climatime:client:requestImmediateSync', payload)

    Wait(prepareMs)

    payload.preparedByExport = preparedByExport
    notifyPreSpawnClimatePhase('ready', payload)

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

    if appearanceServiceMode then
        local serviceMode = appearanceServiceMode
        appearanceServiceMode = nil
        isInAppearance = false
        SendNUIMessage({ action = 'hideAll' })
        DeleteAppearanceCam()

        if lastCoords then
            SetEntityCoordsNoOffset(PlayerPedId(), lastCoords.x, lastCoords.y, lastCoords.z, false, false, false)
            SetEntityHeading(PlayerPedId(), lastCoords.w)
        end
        FreezeEntityPosition(PlayerPedId(), false)
        TriggerEvent('cm-ems:client:appearanceServiceClosed', serviceMode)
        if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(350) end
        return
    end

    isInAppearance = false
    -- spawning=true: this is the real hand-off to cm-spawn (see the PHASE 5
    -- comment below) -- the only hideAll call in this file that actually
    -- means "gameplay is starting, the character-selection UI's cached state
    -- is now irrelevant". See ui/app.js's hideAll handler.
    SendNUIMessage({ action = 'hideAll', spawning = true })
    DeleteAppearanceCam()
    -- Defensive reset: a later, unrelated character creation in the same
    -- session must never reuse this completed session's prepared ped/gender.
    -- openCreator always passes firstSetup=true anyway, so this isn't load-
    -- bearing for the normal flow, but keeps identityPreviewGender from ever
    -- being stale if openAppearance is somehow reached another way.
    identityPreviewActive = false
    identityPreviewGender = nil

    -- PHASE 5: cm-spawn is now the SOLE spawn authority for both new and
    -- existing characters. The old code teleported straight to
    -- AppearanceConfig.afterSpawnCoords and fired characterReady here, which
    -- raced against cm-core:characterLoaded (fired server-side by
    -- server/appearance.lua right before this event) driving cm-spawn's own
    -- DoSpawn -> first-time-hotel pipeline. Both were placing/revealing the
    -- player independently, which could interleave into a double-teleport/
    -- double-reveal. Now this handler only keeps the player hidden, frozen,
    -- private and skipPositionSave=true, and does NOT touch position, bucket,
    -- or completion state. cm-spawn's beginSpawn -> reveal -> spawnComplete
    -- handshake (see cm-spawn/server+client/main.lua) does the real teleport
    -- and reveal, then cm-characters' existing 'cm-spawn:client:spawned'
    -- handler (client/main.lua) closes out the creation UI/audio/world-lock
    -- exactly like it already does for an existing character's spawn.
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetPlayerControl(PlayerId(), false, 0)

    setCreationState(false)
    setCreationHudVisible(false)

    if not IsScreenFadedOut() and not IsScreenFadingOut() then
        DoScreenFadeOut(200)
        Wait(220)
    end

    -- Prepare live cm-climatime while still faded out, before cm-spawn
    -- reveals the real view. New characters then spawn directly into the
    -- right time/weather instead of seeing it change afterwards.
    prepareClimatimeBeforeFirstSpawn()
end)

-- Close appearance (shouldn't happen for new chars, but handle it)
RegisterNUICallback('appearanceClose', function(data, cb)
    local wasService = appearanceServiceMode ~= nil
    -- PHASE 4C: for a brand-new character (not a service edit), Close/Back
    -- now means "return to Basic Identity", not "abandon and restore to
    -- spawned world" — that old fallback only made sense back when Cancel
    -- was never actually shown to new characters.
    local isFirstCreationBack = (not wasService) and currentCharData and currentCharData.isNew == true

    if appearanceServiceMode then
        appearanceServiceMode = nil
        if lastSkin then
            tempSkinTable = CopyTable(lastSkin)
            ApplySkin(tempSkinTable)
            TriggerEvent('cm-inventory:client:forceWearEquippedClothing')
        end
        if lastCoords then
            SetEntityCoordsNoOffset(PlayerPedId(), lastCoords.x, lastCoords.y, lastCoords.z, false, false, false)
            SetEntityHeading(PlayerPedId(), lastCoords.w)
        end
        FreezeEntityPosition(PlayerPedId(), false)
        TriggerEvent('cm-ems:client:appearanceServiceClosed')
    end

    isInAppearance = false
    -- No spawning flag: this either goes back to Identity (isFirstCreationBack
    -- below) or is a service-mode close on an already-spawned character.
    -- Neither is gameplay starting, so the Selector's cached slot-list state
    -- must survive (see ui/app.js's hideAll handler) and creationLoading must
    -- remain usable for a later real transition.
    SendNUIMessage({ action = 'hideAll' })

    if isFirstCreationBack then
        -- Keep the private bucket, creator world lock, skipPositionSave, and
        -- the already-prepared preview ped exactly as they are — only the
        -- NUI panel changes. The character-flow session (server/main.lua's
        -- bucket lifecycle) is not over until a real spawn happens.
        SetNuiFocus(true, true)
        TriggerEvent('cm-characters:client:showCreatorAgain')
        cb('ok')
        return
    end

    SetNuiFocus(false, false)
    if not wasService then
        sendCreationLoading(false)
        TriggerEvent('cm-characters:client:setWorldLock', 'creator', false)
        setCreationState(false)
        setCreationHudVisible(true)
        identityPreviewActive = false
        identityPreviewGender = nil
    end
    DeleteAppearanceCam()
    cb('ok')
end)


-- Capture current ped components after inventory clothing changes and save them.
CaptureCurrentAppearance = function()
    local ped = PlayerPedId()

    -- Copy first so we do not accidentally mutate and send stale/default face data.
    local data = CopyTable(tempSkinTable)
    local isFemale = (GetEntityModel(ped) == GetHashKey('mp_f_freemode_01'))
    data.sex = isFemale and 1 or 0

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

RegisterCommand('fixappearance', function()
    local dbAppearance = FetchActiveCharacterAppearance()
    if type(dbAppearance) == 'table' and next(dbAppearance) then
        tempSkinTable = CopyTable(dbAppearance)
        TriggerEvent('cm-characters:client:applyAppearance', dbAppearance)
        TriggerEvent('cm-inventory:client:forceWearEquippedClothing')
        TriggerEvent('cm-hud:client:notify', 'Appearance restored from character database.', 'success')
    else
        TriggerServerEvent('cm-characters:server:requestAppearance')
        TriggerEvent('cm-hud:client:notify', 'Requested appearance sync from server.', 'info')
    end
end, false)
