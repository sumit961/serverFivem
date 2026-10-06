-- Apply saved appearance to ped


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

local function safeN(val, fallback)
    return tonumber(val) or tonumber(fallback) or 0
end

-- Applies saved appearance to the REAL player ped after spawn (not the selector
-- preview dummy in main.lua, though it shares the same field names/pitfall).
-- Each logical group below runs in its OWN pcall on purpose — see Phase 3's
-- fix in client/main.lua applySkinToPed for the exact failure mode this
-- prevents: one giant pcall meant a single bad value anywhere (e.g. an
-- out-of-range head-blend id) silently skipped every native after it,
-- including hair/clothing, leaving the real player naked/default with no
-- visible error. A failure in one group must not take any other group down.
RegisterNetEvent('cm-characters:client:applyAppearance')
AddEventHandler('cm-characters:client:applyAppearance', function(appearanceData)
    if not appearanceData or type(appearanceData) ~= 'table' then return end

    local isFemale = (appearanceData.sex == 1 or appearanceData.sex == '1' or appearanceData.sex == 'female' or appearanceData.sex == 'f')
    local model = isFemale and GetHashKey('mp_f_freemode_01') or GetHashKey('mp_m_freemode_01')

    local modelOk, modelErr = pcall(function()
        if GetEntityModel(PlayerPedId()) ~= model then
            RequestModel(model)
            local timeout = GetGameTimer() + 5000
            while not HasModelLoaded(model) do
                if GetGameTimer() > timeout then break end
                RequestModel(model)
                Wait(0)
            end
            SetPlayerModel(PlayerId(), model)
            SetModelAsNoLongerNeeded(model)
            SetPedComponentVariation(PlayerPedId(), 0, 0, 0, 2)
        end
    end)
    if not modelOk then
        print('[CM-CHARACTERS] WARNING applyAppearance model group failed: ' .. tostring(modelErr))
    end

    local ped = PlayerPedId()
    local skin = appearanceData

    local function n(key, fallback)
        return safeN(skin[key], fallback or 0)
    end

    local headOk, headErr = pcall(function()
        -- Head blend
        local face_weight = n('face_md_weight', 50) / 100.0
        local skin_weight = n('skin_md_weight', 50) / 100.0
        SetPedHeadBlendData(ped, n('mom', 21), n('dad', 0), 0, n('mom', 21), n('dad', 0), 0, face_weight, skin_weight, 0.0, false)

        -- Face features
        SetPedFaceFeature(ped, 0,  n('nose_1')        / 10.0)
        SetPedFaceFeature(ped, 1,  n('nose_2')        / 10.0)
        SetPedFaceFeature(ped, 2,  n('nose_3')        / 10.0)
        SetPedFaceFeature(ped, 3,  n('nose_4')        / 10.0)
        SetPedFaceFeature(ped, 4,  n('nose_5')        / 10.0)
        SetPedFaceFeature(ped, 5,  n('nose_6')        / 10.0)
        SetPedFaceFeature(ped, 8,  n('cheeks_1')      / 10.0)
        SetPedFaceFeature(ped, 9,  n('cheeks_2')      / 10.0)
        SetPedFaceFeature(ped, 10, n('cheeks_3')      / 10.0)
        SetPedFaceFeature(ped, 12, n('lip_thickness')  / 10.0)
        SetPedFaceFeature(ped, 13, n('jaw_1')          / 10.0)
        SetPedFaceFeature(ped, 14, n('jaw_2')          / 10.0)
        SetPedFaceFeature(ped, 15, n('chin_1')         / 10.0)
        SetPedFaceFeature(ped, 16, n('chin_2')         / 10.0)
        SetPedFaceFeature(ped, 17, n('chin_3')         / 10.0)
        SetPedFaceFeature(ped, 18, n('chin_4')         / 10.0)
        SetPedFaceFeature(ped, 19, n('neck_thickness') / 10.0)
        SetPedFaceFeature(ped, 6,  n('eyebrows_5')    / 10.0)
        SetPedFaceFeature(ped, 7,  n('eyebrows_6')    / 10.0)
    end)
    if not headOk then
        print('[CM-CHARACTERS] WARNING applyAppearance head-blend/face-feature group failed: ' .. tostring(headErr))
    end

    local overlayOk, overlayErr = pcall(function()
        SetPedHeadOverlay(ped, 0,  n('blemishes_1'),  n('blemishes_2')  / 10.0)

        local eb1 = n('eyebrows_1')
        local eb2 = n('eyebrows_2', 10) / 10.0
        if eb1 >= 0 and eb1 ~= 255 and eb2 <= 0.0 then eb2 = 1.0 end
        local eb3 = n('eyebrows_3', n('hair_color_1'))
        local eb4 = n('eyebrows_4', eb3)
        SetPedHeadOverlay(ped, 2,  eb1,   eb2)
        SetPedHeadOverlayColor(ped, 2, 1, eb3, eb4)

        SetPedHeadOverlay(ped, 3,  n('age_1'),        n('age_2')        / 10.0)
        SetPedHeadOverlay(ped, 4,  n('makeup_1'),     n('makeup_2')     / 10.0)
        SetPedHeadOverlayColor(ped, 4, 2, n('makeup_3'), n('makeup_4'))
        SetPedHeadOverlay(ped, 5,  n('blush_1'),      n('blush_2')      / 10.0)
        SetPedHeadOverlayColor(ped, 5, 2, n('blush_3'), n('blush_3'))
        SetPedHeadOverlay(ped, 6,  n('complexion_1'), n('complexion_2') / 10.0)
        SetPedHeadOverlay(ped, 7,  n('sun_1'),        n('sun_2')        / 10.0)
        SetPedHeadOverlay(ped, 8,  n('lipstick_1'),   n('lipstick_2')   / 10.0)
        SetPedHeadOverlayColor(ped, 8, 1, n('lipstick_3'), n('lipstick_4'))
        SetPedHeadOverlay(ped, 9,  n('moles_1'),      n('moles_2')      / 10.0)

        if isFemale then
            SetPedHeadOverlay(ped, 1, 255, 0.0)
            SetPedHeadOverlay(ped, 10, 255, 0.0)
        else
            local b1 = n('beard_1')
            local b2 = n('beard_2', 10) / 10.0
            if b1 <= 0 or b1 == 255 or b2 <= 0.0 then
                SetPedHeadOverlay(ped, 1, 255, 0.0)
            else
                SetPedHeadOverlay(ped, 1, b1, b2)
                SetPedHeadOverlayColor(ped, 1, 1, n('beard_3'), n('beard_4', n('beard_3')))
            end

            local ch1 = n('chest_1')
            local ch2 = n('chest_2', 10) / 10.0
            if ch1 <= 0 or ch1 == 255 or ch2 <= 0.0 then
                SetPedHeadOverlay(ped, 10, 255, 0.0)
            else
                SetPedHeadOverlay(ped, 10, ch1, ch2)
                SetPedHeadOverlayColor(ped, 10, 1, n('chest_3'), n('chest_3'))
            end
        end

        SetPedEyeColor(ped, n('eye_color'))
    end)
    if not overlayOk then
        print('[CM-CHARACTERS] WARNING applyAppearance overlay group failed: ' .. tostring(overlayErr))
    end

    local hairOk, hairErr = pcall(function()
        SetPedComponentVariation(ped, 2, n('hair_1'), n('hair_2'), 2)
        SetPedHairColor(ped, n('hair_color_1'), n('hair_color_2', n('hair_color_1')))
    end)
    if not hairOk then
        print('[CM-CHARACTERS] WARNING applyAppearance hair group failed: ' .. tostring(hairErr))
    end

    local propsOk, propsErr = pcall(function()
        -- Props (nil-safe: treat nil the same as -1)
        local ears      = tonumber(skin['ears_1'])
        local helmet    = tonumber(skin['helmet_1'])
        local glasses   = tonumber(skin['glasses_1'])
        local watches   = tonumber(skin['watches_1'])
        local bracelets = tonumber(skin['bracelets_1'])

        if ears      == nil or ears      < 0 then ClearPedProp(ped, 2) else SetPedPropIndex(ped, 2, ears,      n('ears_2'),      true) end
        if helmet    == nil or helmet    < 0 then ClearPedProp(ped, 0) else SetPedPropIndex(ped, 0, helmet,    n('helmet_2'),    true) end
        if glasses   == nil or glasses   < 0 then ClearPedProp(ped, 1) else SetPedPropIndex(ped, 1, glasses,   n('glasses_2'),   true) end
        if watches   == nil or watches   < 0 then ClearPedProp(ped, 6) else SetPedPropIndex(ped, 6, watches,   n('watches_2'),   true) end
        if bracelets == nil or bracelets < 0 then ClearPedProp(ped, 7) else SetPedPropIndex(ped, 7, bracelets, n('bracelets_2'), true) end
    end)
    if not propsOk then
        print('[CM-CHARACTERS] WARNING applyAppearance props group failed: ' .. tostring(propsErr))
    end

    local componentsOk, componentsErr = pcall(function()
        SetPedComponentVariation(ped, 8,  n('tshirt_1'), n('tshirt_2'), 2)
        SetPedComponentVariation(ped, 11, n('torso_1'),  n('torso_2'),  2)
        SetPedComponentVariation(ped, 3,  n('arms'),     n('arms_2'),   2)
        SetPedComponentVariation(ped, 10, n('decals_1'), n('decals_2'), 2)
        SetPedComponentVariation(ped, 4,  n('pants_1'),  n('pants_2'),  2)
        SetPedComponentVariation(ped, 6,  n('shoes_1'),  n('shoes_2'),  2)
        SetPedComponentVariation(ped, 1,  n('mask_1'),   n('mask_2'),   2)
        SetPedComponentVariation(ped, 9,  n('bproof_1'), n('bproof_2'), 2)
        SetPedComponentVariation(ped, 7,  n('chain_1'),  n('chain_2'),  2)
        SetPedComponentVariation(ped, 5,  n('bags_1'),   n('bags_2'),   2)
    end)
    if not componentsOk then
        print('[CM-CHARACTERS] WARNING applyAppearance components group failed: ' .. tostring(componentsErr))
    end

    TriggerEvent('cm-characters:client:updateAppearanceCache', appearanceData)
    TriggerEvent('cm-inventory:client:forceWearEquippedClothing')
end)

RegisterNetEvent('cm-characters:client:applyBarberAppearance', function(barberData)
    if not barberData or type(barberData) ~= 'table' then return end
    local ped = PlayerPedId()
    local function n(key, fallback) return safeN(barberData[key], fallback or 0) end

    local hairOk, hairErr = pcall(function()
        SetPedComponentVariation(ped, 2, n('hair_1'), n('hair_2'), 2)
        SetPedHairColor(ped, n('hair_color_1'), n('hair_color_2', n('hair_color_1')))
    end)
    if not hairOk then
        print('[CM-CHARACTERS] WARNING applyBarberAppearance hair group failed: ' .. tostring(hairErr))
    end

    local eyebrowOk, eyebrowErr = pcall(function()
        local eb1 = n('eyebrows_1')
        local eb2 = n('eyebrows_2', 10) / 10.0
        if eb1 >= 0 and eb1 ~= 255 and eb2 <= 0.0 then eb2 = 1.0 end
        local eb3 = n('eyebrows_3', n('hair_color_1'))
        local eb4 = n('eyebrows_4', eb3)
        SetPedHeadOverlay(ped, 2, eb1, eb2)
        SetPedHeadOverlayColor(ped, 2, 1, eb3, eb4)
        SetPedFaceFeature(ped, 6, n('eyebrows_5') / 10.0)
        SetPedFaceFeature(ped, 7, n('eyebrows_6') / 10.0)
    end)
    if not eyebrowOk then
        print('[CM-CHARACTERS] WARNING applyBarberAppearance eyebrow group failed: ' .. tostring(eyebrowErr))
    end

    local beardChestOk, beardChestErr = pcall(function()
        local isFemale = (GetEntityModel(ped) == GetHashKey('mp_f_freemode_01'))
        if isFemale then
            SetPedHeadOverlay(ped, 1, 255, 0.0)
            SetPedHeadOverlay(ped, 10, 255, 0.0)
        else
            local b1 = n('beard_1')
            local b2 = n('beard_2', 10) / 10.0
            if b1 <= 0 or b1 == 255 or b2 <= 0.0 then
                SetPedHeadOverlay(ped, 1, 255, 0.0)
            else
                SetPedHeadOverlay(ped, 1, b1, b2)
                SetPedHeadOverlayColor(ped, 1, 1, n('beard_3'), n('beard_4', n('beard_3')))
            end

            local ch1 = n('chest_1')
            local ch2 = n('chest_2', 10) / 10.0
            if ch1 <= 0 or ch1 == 255 or ch2 <= 0.0 then
                SetPedHeadOverlay(ped, 10, 255, 0.0)
            else
                SetPedHeadOverlay(ped, 10, ch1, ch2)
                SetPedHeadOverlayColor(ped, 10, 1, n('chest_3'), n('chest_3'))
            end
        end
    end)
    if not beardChestOk then
        print('[CM-CHARACTERS] WARNING applyBarberAppearance beard/chest group failed: ' .. tostring(beardChestErr))
    end

    TriggerEvent('cm-characters:client:updateAppearanceCache', barberData)
end)


-- Re-equip starter clothing after first character creation.
RegisterNetEvent('cm-characters:client:equipStarterClothingSlots', function(equipment)
    equipment = type(equipment) == 'table' and equipment or {}

    CreateThread(function()
        local function applyStarter()
            if equipment.pants then
                TriggerEvent('cm-inventory:client:equipmentSlot', 'pants', equipment.pants)
            end
            if equipment.shoes then
                TriggerEvent('cm-inventory:client:equipmentSlot', 'shoes', equipment.shoes)
            end
            -- Top last: torso metadata contains arms + undershirt, applying it last prevents clipping.
            if equipment.outerwear then
                TriggerEvent('cm-inventory:client:equipmentSlot', 'outerwear', equipment.outerwear)
            end
        end

        -- Apply immediately, then again after spawn/appearance scripts have finished.
        applyStarter()
        Wait(250); applyStarter()
        Wait(500); applyStarter()
        Wait(900); applyStarter()
        Wait(1200); applyStarter()

        if IsScreenFadedOut() or IsScreenFadingOut() then
            DoScreenFadeIn(350)
        end

        TriggerEvent('cm-characters:client:requestCurrentAppearanceSave')
    end)
end)
