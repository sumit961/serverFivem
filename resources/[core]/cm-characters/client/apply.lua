-- Apply saved appearance to ped
RegisterNetEvent('cm-characters:client:applyAppearance')
AddEventHandler('cm-characters:client:applyAppearance', function(appearanceData)
    if not appearanceData or type(appearanceData) ~= 'table' then return end

    -- Ensure model is loaded
    local sex = appearanceData.sex or 0
    local model = sex == 0 and GetHashKey('mp_m_freemode_01') or GetHashKey('mp_f_freemode_01')

    RequestModel(model)
    while not HasModelLoaded(model) do
        RequestModel(model)
        Wait(0)
    end
    SetPlayerModel(PlayerId(), model)
    SetPedComponentVariation(PlayerPedId(), 0, 0, 0, 2)

    -- Apply all skin data (same as ApplySkin in appearance.lua)
    local ped = PlayerPedId()
    local skin = appearanceData

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
end)
