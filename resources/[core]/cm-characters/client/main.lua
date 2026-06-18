-- cm-characters/client/main.lua
-- Simple character selector preview: selected character spawns and idles.

local display = false
local currentAccountId = nil
local selectorCam = nil
local previewPeds = {}
local currentPreviewPed = nil
local currentPreviewCharId = nil
local currentSlots = {}
local selectorOpen = false
local lastPlayerCoords = nil
local lastPlayerHeading = nil
local nuiReady = false
local pendingSelectorOpen = false
local previewWalkToken = 0
local preloadedPreviewModels = false
local dynamicStage = nil
local restoreSceneEnvironment
local selectorAudioMuted = false
local waitingForSpawnAfterSelect = false

-- v1.2.5 fixed preview scene: flat, streamed ground location.
-- We move the hidden real player here during selection so GTA streams the world,
-- then spawn the preview ped on this same ground instead of using current/underground coords.
local SafePreviewScene = {
    base = vector4(927.4528, 11.8477, 113.5550, 296.7522), -- Fixed selector preview scene
    finishOffset = 0.0,
    startOffset = 0.0,
    camBack = 0.0,
    camSide = 0.0,
    camHeight = 0.0,
    lookHeight = 0.92
}

-- AfterLife-style character selection scenes.
-- The linked AfterLife resource uses real map locations, scripted cameras, weather/time,
-- and character scene configs. We keep your cm-auth/cm-core database flow, but use this
-- scene-based preview approach for the selector.
local SelectionScenes = {
    {
        id = 'casino',
        weather = 'EXTRASUNNY',
        time = { hours = 7, minutes = 0, seconds = 0 },
        location = vector4(870.8840, -34.0424, 77.7642, 128.9946),
        camlocation = vector3(866.0497, -35.3764, 78.7642),
        camrotation = vector3(2.648569, 0.014925, -73.680183),
        fov = 40.0,
        walkDistance = 3.25,
        dict = 'amb@world_human_leaning@female@wall@back@holding_elbow@idle_a',
        anim = 'idle_a'
    },
    {
        id = 'sinner',
        weather = 'EXTRASUNNY',
        time = { hours = 12, minutes = 0, seconds = 0 },
        location = vector4(453.4954, -764.8195, 26.3578, 41.3342),
        camlocation = vector3(453.1763, -762.3759, 27.0578),
        camrotation = vector3(15.472958, 0.021996, -171.108337),
        fov = 40.0,
        walkDistance = 3.0,
        dict = 'amb@world_human_leaning@female@wall@back@holding_elbow@idle_a',
        anim = 'idle_a'
    },
    {
        id = 'zancudo',
        weather = 'EXTRASUNNY',
        time = { hours = 20, minutes = 0, seconds = 0 },
        location = vector4(-1146.6541, 2663.2451, 17.9856, 311.0547),
        camlocation = vector3(-1141.5577, 2663.3613, 18.0520),
        camrotation = vector3(1.180936, 0.054204, 79.498993),
        fov = 40.0,
        walkDistance = 3.0,
        dict = 'amb@world_human_picnic@female@idle_a',
        anim = 'idle_a'
    },
    {
        id = 'confine',
        weather = 'EXTRASUNNY',
        time = { hours = 12, minutes = 0, seconds = 0 },
        location = vector4(402.8329, -996.3921, -100.0002, 181.3700),
        camlocation = vector3(402.8754, -998.3820, -98.6040),
        camrotation = vector3(-3.047215, 0.014113, -0.650071),
        fov = 40.0,
        walkDistance = 2.2,
        dict = 'amb@world_human_hang_out_street@male_c@idle_a',
        anim = 'idle_b'
    }
}



-- Stable outdoor preview scene. We always move the hidden real player here while
-- the selector is open so the map collision/ground is streamed before the
-- preview ped is created. This avoids the camera being under terrain or inside
-- unloaded world geometry.
local FixedGroundPreview = {
    sceneId = 'fixed-night-preview',
    stream = vector4(927.4528, 11.8477, 113.5550, 296.7522),
    walkStart = vector4(927.4528, 11.8477, 113.5550, 296.7522),
    walkFinish = vector4(927.4528, 11.8477, 113.5550, 296.7522),
    camera = vector4(931.2687, 14.1728, 114.5444, 116.2193),
    camrotation = { x = -3.8893, y = 0.0, z = 116.2193 },
    fov = 50.0,
    weather = 'CLEAR',
    time = { hours = 23, minutes = 0, seconds = 0 },
    idleDict = 'anim@heists@heist_corona@team_idles@male_a',
    idleAnim = 'idle'
}

local SavedSelectorScene = nil
local EditorSceneDraft = nil
local selectorEditMode = false
local editorCam = nil

local function setCmHudVisible(visible)
    DisplayRadar(visible == true)
    LocalPlayer.state:set('cmHudHidden', visible ~= true, true)
    TriggerEvent('cm-hud:client:setVisible', visible == true)
    TriggerEvent('cm-hud:client:toggle', visible == true)
    TriggerEvent('cm-hud:client:hide', visible ~= true)
    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:SetVisible(visible == true) end)
        pcall(function() exports['cm-hud']:ToggleHud(visible == true) end)
        pcall(function() exports['cm-hud']:HideHud(visible ~= true) end)
    end
end


local function showCharacterLoading(message, percent)
    SendNUIMessage({
        action = 'creationLoading',
        show = true,
        message = message or 'Preparing character...',
        percent = percent or 0
    })
end

local function hideCharacterLoading(force)
    if force == true then
        SendNUIMessage({ action = 'forceHideLoading' })
    else
        SendNUIMessage({ action = 'creationLoading', show = false })
    end
end

local function markSpawnFlowStarted()
    SendNUIMessage({ action = 'spawnStarted' })
    hideCharacterLoading(true)
end

local function muteSelectorAudio()
    if selectorAudioMuted then return end
    selectorAudioMuted = true
    pcall(function() StartAudioScene('CHARACTER_CHANGE_IN_SKY_SCENE') end)
    pcall(function() StartAudioScene('DLC_MPHEIST_TRANSITION_TO_APT_FADE_IN_RADIO_SCENE') end)
    pcall(function() SetAudioFlag('DisableFlightMusic', true) end)
    pcall(function() SetAudioFlag('PoliceScannerDisabled', true) end)
    pcall(function() SetAudioFlag('WantedMusicDisabled', true) end)
    pcall(function() SetUserRadioControlEnabled(false) end)
    pcall(function() SetVehRadioStation(GetVehiclePedIsIn(PlayerPedId(), false), 'OFF') end)
end

local function unmuteSelectorAudio()
    if not selectorAudioMuted then return end
    selectorAudioMuted = false
    pcall(function() StopAudioScene('CHARACTER_CHANGE_IN_SKY_SCENE') end)
    pcall(function() StopAudioScene('DLC_MPHEIST_TRANSITION_TO_APT_FADE_IN_RADIO_SCENE') end)
    pcall(function() SetAudioFlag('DisableFlightMusic', false) end)
    pcall(function() SetAudioFlag('PoliceScannerDisabled', false) end)
    pcall(function() SetAudioFlag('WantedMusicDisabled', false) end)
    pcall(function() SetUserRadioControlEnabled(true) end)
end

local function tableVec4(v, fallback)
    fallback = fallback or {}
    if type(v) ~= 'table' then v = {} end
    return vector4(
        tonumber(v.x) or tonumber(fallback.x) or 0.0,
        tonumber(v.y) or tonumber(fallback.y) or 0.0,
        tonumber(v.z) or tonumber(fallback.z) or 0.0,
        tonumber(v.w or v.h or v.heading) or tonumber(fallback.w or fallback.h or fallback.heading) or 0.0
    )
end

local function vector4ToTable(v)
    return {
        x = tonumber(v.x) or 0.0,
        y = tonumber(v.y) or 0.0,
        z = tonumber(v.z) or 0.0,
        w = tonumber(v.w) or 0.0
    }
end

local function deepCopySceneConfig(cfg)
    cfg = type(cfg) == 'table' and cfg or {}
    local base = FixedGroundPreview
    return {
        sceneId = tostring(cfg.sceneId or base.sceneId or 'custom-selector-scene'),
        stream = tableVec4(cfg.stream, base.stream),
        walkStart = tableVec4(cfg.walkStart, base.walkStart),
        walkFinish = tableVec4(cfg.walkFinish, base.walkFinish),
        camera = tableVec4(cfg.camera, base.camera),
        camrotation = type(cfg.camrotation) == 'table' and {
            x = tonumber(cfg.camrotation.x) or 0.0,
            y = tonumber(cfg.camrotation.y) or 0.0,
            z = tonumber(cfg.camrotation.z) or 0.0
        } or nil,
        fov = tonumber(cfg.fov) or tonumber(base.fov) or 34.0,
        weather = tostring(cfg.weather or base.weather or 'EXTRASUNNY'),
        time = {
            hours = tonumber(cfg.time and cfg.time.hours) or tonumber(base.time and base.time.hours) or 12,
            minutes = tonumber(cfg.time and cfg.time.minutes) or tonumber(base.time and base.time.minutes) or 0,
            seconds = tonumber(cfg.time and cfg.time.seconds) or tonumber(base.time and base.time.seconds) or 0
        },
        idleDict = tostring(cfg.idleDict or cfg.dict or base.idleDict or 'amb@world_human_hang_out_street@male_c@idle_a'),
        idleAnim = tostring(cfg.idleAnim or cfg.anim or base.idleAnim or 'idle_b')
    }
end

local function serializableSceneConfig(cfg)
    cfg = deepCopySceneConfig(cfg)
    return {
        sceneId = cfg.sceneId,
        stream = vector4ToTable(cfg.stream),
        walkStart = vector4ToTable(cfg.walkStart),
        walkFinish = vector4ToTable(cfg.walkFinish),
        camera = vector4ToTable(cfg.camera),
        camrotation = cfg.camrotation,
        fov = cfg.fov,
        weather = cfg.weather,
        time = cfg.time,
        idleDict = cfg.idleDict,
        idleAnim = cfg.idleAnim
    }
end

local buildCreationStyleSceneConfig

local function getActiveSelectorSceneConfig()
    -- Hard-force the selector preview scene. Do not use old editor data or Legion fallback.
    return deepCopySceneConfig(buildCreationStyleSceneConfig())
end

-- Character selection fixed preview scene.
-- These are the coordinates captured in-game with /getcampos.
-- The selector uses this scene every time, in a private routing bucket.
local CreationPreviewScene = {
    ped = vector4(927.4528, 11.8477, 113.5550, 296.7522),
    camera = vector3(931.2687, 14.1728, 114.5444),
    camrotation = vector3(-3.8893, 0.0000, 116.2193),
    fov = 50.0,
    weather = 'CLEAR',
    time = { hours = 23, minutes = 0, seconds = 0 }
}

local function headingForwardVector(heading)
    local rad = math.rad(tonumber(heading) or 0.0)
    return vector3(-math.sin(rad), math.cos(rad), 0.0)
end

function buildCreationStyleSceneConfig()
    local ped = CreationPreviewScene.ped
    local cam = CreationPreviewScene.camera
    local camRot = CreationPreviewScene.camrotation

    return {
        sceneId = 'fixed-night-preview',
        stream = ped,
        walkStart = ped,
        walkFinish = ped,
        camera = vector4(cam.x, cam.y, cam.z, ped.w),
        camrotation = { x = camRot.x, y = camRot.y, z = camRot.z },
        fov = CreationPreviewScene.fov,
        weather = CreationPreviewScene.weather or 'CLEAR',
        time = CreationPreviewScene.time or { hours = 23, minutes = 0, seconds = 0 },
        idleDict = 'anim@heists@heist_corona@team_idles@male_a',
        idleAnim = 'idle',
        lookHeight = 0.92
    }
end

local function normalizePreviewGender(char, appearance)
    appearance = type(appearance) == 'table' and appearance or {}
    local gender = tostring((type(char) == 'table' and char.gender) or appearance.gender or ''):lower()
    if gender == 'f' or gender == 'woman' or gender == 'female' then return 'female' end
    if gender == 'm' or gender == 'man' or gender == 'male' then return 'male' end

    local sex = appearance.sex
    if sex == 1 or sex == '1' or sex == 'female' or sex == 'f' then return 'female' end
    return 'male'
end

local function getFreemodeModelForGender(gender)
    return gender == 'female' and GetHashKey('mp_f_freemode_01') or GetHashKey('mp_m_freemode_01')
end


local function hideRealPlayerForSelector()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityAlpha(ped, 0, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    SetPedCanBeTargetted(ped, false)
    SetPedCanRagdoll(ped, false)
    ClearPedTasksImmediately(ped)

    -- Extra local-player visibility guards. This prevents the GTA default story
    -- ped/Michael from being visible while the selector dummy is being shown.
    pcall(function() SetLocalPlayerVisibleLocally(false) end)
    pcall(function() NetworkSetEntityInvisibleToNetwork(ped, true) end)
end

local function restoreRealPlayerAfterSelector()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    pcall(function() NetworkSetEntityInvisibleToNetwork(ped, false) end)
    pcall(function() SetLocalPlayerVisibleLocally(true) end)
    ResetEntityAlpha(ped)
    SetEntityAlpha(ped, 255, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    SetPedCanBeTargetted(ped, true)
    SetPedCanRagdoll(ped, true)
    FreezeEntityPosition(ped, false)
end

local DefaultSkin = {
    sex = 0, mom = 21, dad = 0, face_md_weight = 50, skin_md_weight = 50,
    nose_1 = 0, nose_2 = 0, nose_3 = 0, nose_4 = 0, nose_5 = 0, nose_6 = 0,
    cheeks_1 = 0, cheeks_2 = 0, cheeks_3 = 0, lip_thickness = 0,
    jaw_1 = 0, jaw_2 = 0, chin_1 = 0, chin_2 = 0, chin_3 = 0, chin_4 = 0,
    neck_thickness = 0, hair_1 = 0, hair_2 = 0, hair_color_1 = 0, hair_color_2 = 0,
    tshirt_1 = 15, tshirt_2 = 0, torso_1 = 15, torso_2 = 0, decals_1 = 0, decals_2 = 0,
    arms = 15, arms_2 = 0, pants_1 = 14, pants_2 = 1, shoes_1 = 34, shoes_2 = 0,
    mask_1 = 0, mask_2 = 0, bproof_1 = 0, bproof_2 = 0, chain_1 = 0, chain_2 = 0,
    helmet_1 = -1, helmet_2 = 0, glasses_1 = -1, glasses_2 = 0,
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

print('[CM-CHARACTERS] main.lua loaded!')

local function copyDefaultSkin(appearance, gender)
    local skin = {}
    for k, v in pairs(DefaultSkin) do skin[k] = v end

    if gender == 'female' then
        skin.sex = 1
        skin.pants_1 = 15
        skin.pants_2 = 0
        skin.shoes_1 = 35
        skin.shoes_2 = 0
    end

    if type(appearance) == 'table' then
        for k, v in pairs(appearance) do
            if v ~= nil then skin[k] = v end
        end
    end

    if gender == 'female' then
        skin.sex = 1
    elseif gender == 'male' then
        skin.sex = 0
    end

    return skin
end

local function requestModel(model)
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        Wait(0)
        RequestModel(model)
        if GetGameTimer() > timeout then return false end
    end
    return true
end


local function preloadPreviewModels()
    if preloadedPreviewModels then return end
    preloadedPreviewModels = true
    CreateThread(function()
        local models = { GetHashKey('mp_m_freemode_01'), GetHashKey('mp_f_freemode_01') }
        for _, model in ipairs(models) do
            RequestModel(model)
        end
        local timeout = GetGameTimer() + 2500
        while GetGameTimer() < timeout do
            local allLoaded = true
            for _, model in ipairs(models) do
                if not HasModelLoaded(model) then
                    RequestModel(model)
                    allLoaded = false
                end
            end
            if allLoaded then break end
            Wait(0)
        end
        print('[CM-CHARACTERS] Preview freemode models preloaded')
    end)
end

local function safeNumber(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0 end
    return value
end

local function applySkinToPed(ped, appearance, gender)
    if not DoesEntityExist(ped) then return end

    local skin = copyDefaultSkin(appearance, gender)

    local function n(key, fallback)
        return safeNumber(skin[key], fallback or 0)
    end

    SetPedDefaultComponentVariation(ped)

    pcall(function()
        local faceWeight = (n('face_md_weight', 50) / 100) + 0.0
        local skinWeight = (n('skin_md_weight', 50) / 100) + 0.0
        SetPedHeadBlendData(ped, n('mom', 21), n('dad', 0), 0, n('mom', 21), n('dad', 0), 0, faceWeight, skinWeight, 0.0, false)

        SetPedFaceFeature(ped, 0, (n('nose_1') / 10) + 0.0)
        SetPedFaceFeature(ped, 1, (n('nose_2') / 10) + 0.0)
        SetPedFaceFeature(ped, 2, (n('nose_3') / 10) + 0.0)
        SetPedFaceFeature(ped, 3, (n('nose_4') / 10) + 0.0)
        SetPedFaceFeature(ped, 4, (n('nose_5') / 10) + 0.0)
        SetPedFaceFeature(ped, 5, (n('nose_6') / 10) + 0.0)
        SetPedFaceFeature(ped, 8, (n('cheeks_1') / 10) + 0.0)
        SetPedFaceFeature(ped, 9, (n('cheeks_2') / 10) + 0.0)
        SetPedFaceFeature(ped, 10, (n('cheeks_3') / 10) + 0.0)
        SetPedFaceFeature(ped, 12, (n('lip_thickness') / 10) + 0.0)
        SetPedFaceFeature(ped, 13, (n('jaw_1') / 10) + 0.0)
        SetPedFaceFeature(ped, 14, (n('jaw_2') / 10) + 0.0)
        SetPedFaceFeature(ped, 15, (n('chin_1') / 10) + 0.0)
        SetPedFaceFeature(ped, 16, (n('chin_2') / 10) + 0.0)
        SetPedFaceFeature(ped, 17, (n('chin_3') / 10) + 0.0)
        SetPedFaceFeature(ped, 18, (n('chin_4') / 10) + 0.0)
        SetPedFaceFeature(ped, 19, (n('neck_thickness') / 10) + 0.0)

        SetPedHeadOverlay(ped, 3, n('age_1'), (n('age_2') / 10) + 0.0)
        SetPedHeadOverlay(ped, 0, n('blemishes_1'), (n('blemishes_2') / 10) + 0.0)
        SetPedEyeColor(ped, n('eye_color'))
        SetPedHeadOverlay(ped, 2, n('eyebrows_1'), (n('eyebrows_2') / 10) + 0.0)
        SetPedHeadOverlayColor(ped, 2, 1, n('eyebrows_3'), n('eyebrows_4'))
        SetPedFaceFeature(ped, 6, (n('eyebrows_5') / 10) + 0.0)
        SetPedFaceFeature(ped, 7, (n('eyebrows_6') / 10) + 0.0)

        -- Keep makeup/lipstick off in preview too.
        SetPedHeadOverlay(ped, 4, 0, 0.0)
        SetPedHeadOverlay(ped, 5, 0, 0.0)
        SetPedHeadOverlay(ped, 8, 0, 0.0)

        SetPedComponentVariation(ped, 2, n('hair_1'), n('hair_2'), 2)
        SetPedHairColor(ped, n('hair_color_1'), n('hair_color_2'))
        SetPedHeadOverlay(ped, 1, n('beard_1'), (n('beard_2') / 10) + 0.0)
        SetPedHeadOverlayColor(ped, 1, 1, n('beard_3'), n('beard_4'))

        SetPedComponentVariation(ped, 8, n('tshirt_1'), n('tshirt_2'), 2)
        SetPedComponentVariation(ped, 11, n('torso_1'), n('torso_2'), 2)
        SetPedComponentVariation(ped, 3, n('arms'), n('arms_2'), 2)
        SetPedComponentVariation(ped, 10, n('decals_1'), n('decals_2'), 2)
        SetPedComponentVariation(ped, 4, n('pants_1'), n('pants_2'), 2)
        SetPedComponentVariation(ped, 6, n('shoes_1'), n('shoes_2'), 2)
        SetPedComponentVariation(ped, 1, n('mask_1'), n('mask_2'), 2)
        SetPedComponentVariation(ped, 9, n('bproof_1'), n('bproof_2'), 2)
        SetPedComponentVariation(ped, 7, n('chain_1'), n('chain_2'), 2)
        SetPedComponentVariation(ped, 5, n('bags_1'), n('bags_2'), 2)

        if n('helmet_1', -1) == -1 then ClearPedProp(ped, 0) else SetPedPropIndex(ped, 0, n('helmet_1'), n('helmet_2'), true) end
        if n('glasses_1', -1) == -1 then ClearPedProp(ped, 1) else SetPedPropIndex(ped, 1, n('glasses_1'), n('glasses_2'), true) end
        if n('ears_1', -1) == -1 then ClearPedProp(ped, 2) else SetPedPropIndex(ped, 2, n('ears_1'), n('ears_2'), true) end
        if n('watches_1', -1) == -1 then ClearPedProp(ped, 6) else SetPedPropIndex(ped, 6, n('watches_1'), n('watches_2'), true) end
        if n('bracelets_1', -1) == -1 then ClearPedProp(ped, 7) else SetPedPropIndex(ped, 7, n('bracelets_1'), n('bracelets_2'), true) end
    end)
end



local PreviewClothingSlotMap = {
    shirt = { type = 'component', index = 8 },
    outerwear = { type = 'component', index = 11 },
    pants = { type = 'component', index = 4 },
    shoes = { type = 'component', index = 6 },
    accessory = { type = 'component', index = 7 },
    bag = { type = 'component', index = 5 },
    headwear = { type = 'prop', index = 0 },
    glasses = { type = 'prop', index = 1 },
    earrings = { type = 'prop', index = 2 },
    watch = { type = 'prop', index = 6 }
}

local function applyInventoryClothingToPreviewPed(ped, equipment, gender)
    if not DoesEntityExist(ped) or type(equipment) ~= 'table' then return end

    local order = { 'shirt', 'outerwear', 'pants', 'shoes', 'accessory', 'bag', 'headwear', 'glasses', 'earrings', 'watch' }

    for _, slot in ipairs(order) do
        local item = equipment[slot]
        local map = PreviewClothingSlotMap[slot]
        if item and map and tostring(item.item_name or ''):find('clothing_', 1, true) == 1 then
            local metadata = type(item.metadata) == 'table' and item.metadata or {}
            local drawable = tonumber(metadata.drawableId or metadata.drawable)
            local texture = tonumber(metadata.textureId or metadata.texture or 0) or 0

            if drawable ~= nil then
                if map.type == 'prop' then
                    if drawable < 0 then
                        ClearPedProp(ped, map.index)
                    else
                        SetPedPropIndex(ped, map.index, drawable, texture, true)
                    end
                else
                    if slot == 'outerwear' then
                        local undershirt = tonumber(metadata.undershirt or metadata.tshirt_1)
                        local undershirtTexture = tonumber(metadata.undershirtTexture or metadata.tshirt_2 or 0) or 0
                        local arms = tonumber(metadata.arms)
                        local armsTexture = tonumber(metadata.armsTexture or metadata.arms_2 or 0) or 0

                        if undershirt then SetPedComponentVariation(ped, 8, undershirt, undershirtTexture, 0) end
                        SetPedComponentVariation(ped, map.index, drawable, texture, 0)
                        if arms then SetPedComponentVariation(ped, 3, arms, armsTexture, 0) end
                    else
                        SetPedComponentVariation(ped, map.index, drawable, texture, 0)
                    end
                end
            end
        end
    end
end

local function hardDeletePed(ped)
    if not ped or ped == 0 then return end
    if not DoesEntityExist(ped) then return end

    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, false, false)
    SetEntityVisible(ped, false, false)
    SetEntityAlpha(ped, 0, false)
    SetEntityAsMissionEntity(ped, true, true)

    DeletePed(ped)
    DeleteEntity(ped)

    SetTimeout(0, function()
        if ped and DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)
            DeletePed(ped)
            DeleteEntity(ped)
        end
    end)

    SetTimeout(250, function()
        if ped and DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)
            DeletePed(ped)
            DeleteEntity(ped)
        end
    end)
end

local function getPreviewCenterForCleanup()
    local cfg = getActiveSelectorSceneConfig and getActiveSelectorSceneConfig() or FixedGroundPreview
    local finish = cfg and cfg.walkFinish or FixedGroundPreview.walkFinish
    return vector3(tonumber(finish.x) or 927.4528, tonumber(finish.y) or 11.8477, tonumber(finish.z) or 113.5550)
end

local function cleanupUntrackedPreviewDummies()
    local center = getPreviewCenterForCleanup()
    local playerPed = PlayerPedId()
    local deleted = 0

    local ok, peds = pcall(function() return GetGamePool('CPed') end)
    if not ok or type(peds) ~= 'table' then return 0 end

    for _, ped in ipairs(peds) do
        if ped and ped ~= 0 and DoesEntityExist(ped) and ped ~= playerPed and not IsPedAPlayer(ped) then
            local model = GetEntityModel(ped)
            if model == GetHashKey('mp_m_freemode_01') or model == GetHashKey('mp_f_freemode_01') then
                local coords = GetEntityCoords(ped)
                if #(coords - center) < 18.0 then
                    hardDeletePed(ped)
                    deleted = deleted + 1
                end
            end
        end
    end

    if deleted > 0 then
        print(('[CM-CHARACTERS] cleaned %s old dummy preview peds'):format(deleted))
    end

    return deleted
end

local function deletePreviewPeds(cleanNearby)
    if currentPreviewPed and DoesEntityExist(currentPreviewPed) then
        hardDeletePed(currentPreviewPed)
    end

    for _, ped in pairs(previewPeds) do
        if ped and DoesEntityExist(ped) then
            hardDeletePed(ped)
        end
    end

    previewPeds = {}
    currentPreviewPed = nil
    currentPreviewCharId = nil
    if cleanNearby == true then
        cleanupUntrackedPreviewDummies()
    end
end

local function destroySelectorCam()
    if selectorCam and DoesCamExist(selectorCam) then
        RenderScriptCams(false, true, 450, true, true)
        DestroyCam(selectorCam, false)
    end
    selectorCam = nil
end

local function cleanupSelectorScene(restorePlayer)
    deletePreviewPeds(true)
    destroySelectorCam()
    ClearFocus()
    dynamicStage = nil
    restoreSceneEnvironment()
    unmuteSelectorAudio()
    DoScreenFadeIn(250)
    DisplayRadar(true)
    setCmHudVisible(true)

    local ped = PlayerPedId()
    restoreRealPlayerAfterSelector()

    if restorePlayer and lastPlayerCoords then
        SetEntityCoordsNoOffset(ped, lastPlayerCoords.x, lastPlayerCoords.y, lastPlayerCoords.z, false, false, false)
        if lastPlayerHeading then SetEntityHeading(ped, lastPlayerHeading) end
    end
end


local function cleanupSelectorSceneForSpawn()
    -- Used after pressing Enter City. Do not restore/show the real player here,
    -- because GTA may briefly show the default story ped (Michael) before spawn
    -- applies the selected freemode model/appearance. cm-spawn will unhide after spawn.
    deletePreviewPeds(false)
    destroySelectorCam()
    ClearFocus()
    dynamicStage = nil
    restoreSceneEnvironment()
    hideRealPlayerForSelector()
    DisplayRadar(false)
    setCmHudVisible(false)
end



local function getGroundZ(x, y, z)
    local fallback = tonumber(z) or 30.0
    RequestCollisionAtCoord(x, y, fallback)
    for i = 1, 40 do
        local probeZ = fallback + 40.0 - (i * 1.5)
        local groundFound, groundZ = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, probeZ + 0.0, false)
        if groundFound and groundZ and groundZ > -50.0 then
            return groundZ + 0.04
        end
        Wait(0)
    end
    return fallback
end

local function headingForwardVector(heading)
    local rad = math.rad(heading or 0.0)
    return vector3(-math.sin(rad), math.cos(rad), 0.0)
end

local function sceneForSlot(slot)
    slot = tonumber(slot or 1) or 1
    local index = ((slot - 1) % #SelectionScenes) + 1
    return SelectionScenes[index] or SelectionScenes[1]
end

local function applySceneEnvironment(scene)
    if not scene then return end

    pcall(function()
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        local weather = scene.weather or 'CLEAR'
        SetWeatherTypeNowPersist(weather)
        SetWeatherTypeNow(weather)
        SetWeatherTypePersist(weather)
        SetRainFxIntensity(0.0)
        SetWindSpeed(0.0)
        ClearTimecycleModifier()
        ClearExtraTimecycleModifier()
        SetArtificialLightsState(false)
    end)

    if type(scene.time) == 'table' then
        pcall(function()
            NetworkOverrideClockTime(scene.time.hours or 23, scene.time.minutes or 0, scene.time.seconds or 0)
            PauseClock(true)
        end)
    end
end

function restoreSceneEnvironment()
    pcall(function()
        PauseClock(false)
        ClearOverrideWeather()
        ClearWeatherTypePersist()
    end)
end

local function headingToCoord(fromCoords, toCoords)
    local dx = (toCoords.x or 0.0) - (fromCoords.x or 0.0)
    local dy = (toCoords.y or 0.0) - (fromCoords.y or 0.0)
    return GetHeadingFromVector_2d(dx, dy)
end

local function loadCollisionAt(x, y, z, radius, timeoutMs)
    radius = radius or 55.0
    timeoutMs = timeoutMs or 3500

    RequestCollisionAtCoord(x, y, z)
    pcall(function()
        NewLoadSceneStartSphere(x, y, z, radius, 0)
    end)

    local timeout = GetGameTimer() + timeoutMs
    while GetGameTimer() < timeout do
        RequestCollisionAtCoord(x, y, z)
        Wait(0)
    end

    pcall(function() NewLoadSceneStop() end)
end

local function getSafeGroundZ(x, y, fallbackZ)
    fallbackZ = tonumber(fallbackZ) or 30.0

    local heights = { 1000.0, 300.0, 120.0, 80.0, 50.0, 35.0, fallbackZ + 8.0 }
    for _, height in ipairs(heights) do
        RequestCollisionAtCoord(x, y, height)
        local found, groundZ = GetGroundZFor_3dCoord(x, y, height, false)
        if found and groundZ and groundZ > -50.0 then
            return groundZ + 0.03
        end
        Wait(0)
    end

    return fallbackZ
end

local function buildDynamicStage(scene)
    -- v1.2.5: Fixed ground preview location.
    -- We no longer build the preview scene from the player's current position,
    -- because the player might reconnect in mountains, interiors, unloaded areas,
    -- or below-map spawn states. Instead, move the hidden real player to a known
    -- outdoor ground coordinate and build the character walk-in stage there.
    local ped = PlayerPedId()
    local cfg = getActiveSelectorSceneConfig()

    local exactScenes = { ['creator-style-preview'] = true, ['fixed-night-preview'] = true }
    local useExactCreatorZ = exactScenes[tostring(cfg.sceneId or '')] == true
    local streamZ = useExactCreatorZ and cfg.stream.z or getSafeGroundZ(cfg.stream.x, cfg.stream.y, cfg.stream.z)
    local finishZ = useExactCreatorZ and cfg.walkFinish.z or getSafeGroundZ(cfg.walkFinish.x, cfg.walkFinish.y, cfg.walkFinish.z)
    local startZ = useExactCreatorZ and cfg.walkStart.z or getSafeGroundZ(cfg.walkStart.x, cfg.walkStart.y, cfg.walkStart.z)

    -- Move the real player to the preview area first. Even though the player is
    -- hidden, this keeps the game world, collision, and peds streamed correctly.
    SetEntityCoordsNoOffset(ped, cfg.stream.x, cfg.stream.y, streamZ, false, false, false)
    if not useExactCreatorZ then PlaceEntityOnGroundProperly(ped) end
    SetEntityHeading(ped, cfg.stream.w)
    hideRealPlayerForSelector()
    loadCollisionAt(cfg.walkFinish.x, cfg.walkFinish.y, finishZ, 60.0, useExactCreatorZ and 120 or 450)

    if not useExactCreatorZ then
        finishZ = getSafeGroundZ(cfg.walkFinish.x, cfg.walkFinish.y, finishZ)
        startZ = getSafeGroundZ(cfg.walkStart.x, cfg.walkStart.y, startZ)
    end

    local finishVec = vector3(cfg.walkFinish.x, cfg.walkFinish.y, finishZ)
    local cameraVec = vector3(cfg.camera.x, cfg.camera.y, cfg.camera.z)
    local faceCameraHeading = headingToCoord(finishVec, cameraVec)

    dynamicStage = {
        sceneId = cfg.sceneId,
        scene = {
            weather = cfg.weather or (scene and scene.weather) or 'EXTRASUNNY',
            time = cfg.time or (scene and scene.time) or { hours = 12, minutes = 0, seconds = 0 }
        },
        camera = vector4(cfg.camera.x, cfg.camera.y, cfg.camera.z, cfg.camera.w),
        camrotation = nil,
        fov = cfg.fov or 34.0,
        camrotation = cfg.camrotation,
        walkStart = vector4(cfg.walkStart.x, cfg.walkStart.y, startZ, cfg.walkStart.w or faceCameraHeading),
        walkFinish = vector4(cfg.walkFinish.x, cfg.walkFinish.y, finishZ, cfg.walkFinish.w or faceCameraHeading),
        lookHeight = cfg.lookHeight or 0.92,
        idleDict = cfg.idleDict,
        idleAnim = cfg.idleAnim
    }

    ClearFocus()
    SetFocusPosAndVel(cfg.walkFinish.x, cfg.walkFinish.y, finishZ, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(cfg.walkStart.x, cfg.walkStart.y, startZ)
    RequestCollisionAtCoord(cfg.walkFinish.x, cfg.walkFinish.y, finishZ)
    RequestCollisionAtCoord(cfg.camera.x, cfg.camera.y, cfg.camera.z)

    print(('[CM-CHARACTERS] Fixed requested preview scene: player=(%.2f %.2f %.2f) start=(%.2f %.2f %.2f) finish=(%.2f %.2f %.2f) cam=(%.2f %.2f %.2f)'):format(
        cfg.stream.x, cfg.stream.y, streamZ,
        cfg.walkStart.x, cfg.walkStart.y, startZ,
        cfg.walkFinish.x, cfg.walkFinish.y, finishZ,
        cfg.camera.x, cfg.camera.y, cfg.camera.z
    ))

    return dynamicStage
end

local function getStage()
    if not dynamicStage then
        return buildDynamicStage(SelectionScenes[1])
    end
    return dynamicStage
end

local function setupSelectorScene(char)
    local ped = PlayerPedId()
    if not lastPlayerCoords then
        lastPlayerCoords = GetEntityCoords(ped)
        lastPlayerHeading = GetEntityHeading(ped)
    end

    preloadPreviewModels()
    cleanupUntrackedPreviewDummies()

    local scene = SelectionScenes[1]
    if type(char) == 'table' then
        scene = sceneForSlot(char.slot)
    end

    buildDynamicStage(scene)
    local stage = getStage()
    applySceneEnvironment(stage.scene)
    muteSelectorAudio()

    DoScreenFadeIn(0)
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    SetArtificialLightsState(false)
    DisplayRadar(false)
    setCmHudVisible(false)
    hideRealPlayerForSelector()

    if selectorCam and DoesCamExist(selectorCam) then DestroyCam(selectorCam, false) end
    selectorCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(selectorCam, stage.camera.x, stage.camera.y, stage.camera.z)
    if stage.camrotation then
        SetCamRot(selectorCam, stage.camrotation.x, stage.camrotation.y, stage.camrotation.z, 2)
    else
        PointCamAtCoord(selectorCam, stage.walkFinish.x, stage.walkFinish.y, stage.walkFinish.z + (stage.lookHeight or 0.92))
    end
    SetCamFov(selectorCam, stage.fov or 40.0)
    SetCamActive(selectorCam, true)
    RenderScriptCams(true, true, 180, true, true)

    print(('[CM-CHARACTERS] AfterLife scene loaded: %s cam=(%.2f %.2f %.2f) ped=(%.2f %.2f %.2f)'):format(
        tostring(stage.sceneId), stage.camera.x, stage.camera.y, stage.camera.z, stage.walkFinish.x, stage.walkFinish.y, stage.walkFinish.z
    ))
end

local function getExistingCharacters(slots)
    local chars = {}
    for slot = 1, (tonumber(Config and Config.MaxCharacters) or 2) do
        local char = slots[tostring(slot)] or slots[slot]
        if char and char.uniqueId then
            chars[#chars + 1] = char
        end
    end
    return chars
end

local function findCharacterById(charId)
    charId = tostring(charId or '')
    if charId == '' then return nil end

    for slot = 1, (tonumber(Config and Config.MaxCharacters) or 2) do
        local char = currentSlots[tostring(slot)] or currentSlots[slot]
        if char and tostring(char.uniqueId or '') == charId then
            return char
        end
    end

    return nil
end

local function playPreviewIdle(ped)
    if not DoesEntityExist(ped) then return end

    local stage = getStage()
    local animDict = stage.idleDict or 'amb@world_human_hang_out_street@male_c@idle_a'
    RequestAnimDict(animDict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(animDict) and GetGameTimer() < timeout do Wait(0) end

    if HasAnimDictLoaded(animDict) then
        TaskPlayAnim(ped, animDict, stage.idleAnim or 'idle_b', 8.0, 0.0, -1, 1, 0, false, false, false)
    else
        TaskStandStill(ped, -1)
    end
end

local function focusStageCamera(targetCoords)
    if not selectorCam or not DoesCamExist(selectorCam) then return end

    local stage = getStage()
    targetCoords = targetCoords or vector3(stage.walkFinish.x, stage.walkFinish.y, stage.walkFinish.z)
    SetCamCoord(selectorCam, stage.camera.x, stage.camera.y, stage.camera.z)
    if stage.camrotation then
        SetCamRot(selectorCam, stage.camrotation.x, stage.camrotation.y, stage.camrotation.z, 2)
    else
        PointCamAtCoord(selectorCam, targetCoords.x, targetCoords.y, targetCoords.z + (stage.lookHeight or 0.92))
    end
    SetCamFov(selectorCam, stage.fov or 40.0)
    SetCamActive(selectorCam, true)
    RenderScriptCams(true, false, 0, true, true)
end

local function spawnPreviewPeds(slots)
    -- We no longer spawn all characters at once. The selected character is spawned directly in the visible stage when selected.
    deletePreviewPeds()
    setupSelectorScene()
    local stage = getStage()
    focusStageCamera(vector3(stage.walkFinish.x, stage.walkFinish.y, stage.walkFinish.z))
end

local function spawnSimplePreviewCharacter(charId)
    charId = tostring(charId or '')
    local char = findCharacterById(charId)
    if not char then
        print('[CM-CHARACTERS] simple preview failed: character not found for charId=' .. charId)
        return
    end

    -- Strict dummy preview mode:
    -- never use PlayerPedId() as preview, never keep old preview peds, and ignore stale double-click requests.
    previewWalkToken = previewWalkToken + 1
    local myToken = previewWalkToken

    setupSelectorScene(char)
    deletePreviewPeds(false)

    local appearance = type(char.appearance) == 'table' and char.appearance or {}
    local gender = normalizePreviewGender(char, appearance)

    -- IMPORTANT: never allow model 0/player_zero/player_one/player_two here. Those
    -- are GTA story characters such as Michael. Character preview must use a local
    -- freemode dummy based on the selected character's gender/appearance.
    local model = getFreemodeModelForGender(gender)
    local modelName = gender == 'female' and 'mp_f_freemode_01' or 'mp_m_freemode_01'

    if not requestModel(model) then
        print('[CM-CHARACTERS] dummy preview failed: freemode model did not load for ' .. tostring(modelName))
        return
    end

    -- If the player clicked another card while this model was loading, do not spawn this stale ped.
    if myToken ~= previewWalkToken then
        SetModelAsNoLongerNeeded(model)
        return
    end

    local stage = getStage()
    local pos = stage.walkFinish
    RequestCollisionAtCoord(pos.x, pos.y, pos.z)
    local exactScenes = { ['creator-style-preview'] = true, ['fixed-night-preview'] = true }
    local groundZ = exactScenes[tostring(stage.sceneId or '')] and pos.z or getSafeGroundZ(pos.x, pos.y, pos.z)
    pos = vector4(pos.x, pos.y, groundZ, pos.w or 0.0)

    -- Fast path: delete only our tracked dummy here. Nearby cleanup is expensive and
    -- is now done when the selector opens/closes or through /charpreviewclear.
    deletePreviewPeds(false)
    hideRealPlayerForSelector()

    local previewPed = CreatePed(4, model, pos.x, pos.y, pos.z, pos.w or 0.0, false, false)
    if not DoesEntityExist(previewPed) then
        print('[CM-CHARACTERS] dummy preview failed: ped was not created')
        SetModelAsNoLongerNeeded(model)
        return
    end

    -- If another click happened after CreatePed, delete this stale dummy immediately.
    if myToken ~= previewWalkToken then
        hardDeletePed(previewPed)
        SetModelAsNoLongerNeeded(model)
        return
    end

    currentPreviewPed = previewPed
    currentPreviewCharId = charId
    previewPeds = { [charId] = previewPed }

    SetEntityAsMissionEntity(previewPed, true, true)
    SetEntityInvincible(previewPed, true)
    SetBlockingOfNonTemporaryEvents(previewPed, true)
    SetPedCanRagdoll(previewPed, false)
    SetPedCanRagdollFromPlayerImpact(previewPed, false)
    SetPedCanBeTargetted(previewPed, false)
    SetEntityCollision(previewPed, true, true)
    SetEntityNoCollisionEntity(previewPed, PlayerPedId(), true)
    SetEntityAlpha(previewPed, 0, false)
    SetEntityVisible(previewPed, false, false)
    SetEntityLodDist(previewPed, 999)
    SetEntityCoordsNoOffset(previewPed, pos.x, pos.y, pos.z, false, false, false)
    if tostring(stage.sceneId or '') ~= 'creator-style-preview' and tostring(stage.sceneId or '') ~= 'fixed-night-preview' then PlaceEntityOnGroundProperly(previewPed) end
    SetEntityHeading(previewPed, pos.w or 0.0)
    FreezeEntityPosition(previewPed, true)

    -- Apply selected character appearance while hidden so players never see the
    -- GTA default freemode ped. Then re-apply clothing a few times because GTA can
    -- reset components just after a freemode model is created.
    Wait(0)
    applySkinToPed(previewPed, appearance, gender)
    applyInventoryClothingToPreviewPed(previewPed, char.equipment or {}, gender)
    Wait(0)
    applySkinToPed(previewPed, appearance, gender)
    applyInventoryClothingToPreviewPed(previewPed, char.equipment or {}, gender)

    SetEntityAlpha(previewPed, 255, false)
    SetEntityVisible(previewPed, true, false)
    playPreviewIdle(previewPed)
    focusStageCamera(vector3(pos.x, pos.y, pos.z))

    SetTimeout(tonumber(Config and Config.SelectorInitialLoadingMs) or 1800, function()
        if selectorOpen and myToken == previewWalkToken then
            hideCharacterLoading()
        end
    end)

    -- Final late equipment pass for inventory clothes/torso arms pairing.
    SetTimeout(150, function()
        if myToken == previewWalkToken and DoesEntityExist(previewPed) then
            applyInventoryClothingToPreviewPed(previewPed, char.equipment or {}, gender)
            playPreviewIdle(previewPed)
        end
    end)

    print(('[CM-CHARACTERS] dummy preview spawned with selected appearance: char=%s entity=%s gender=%s scene=%s pos=(%.2f %.2f %.2f) equipment=%s'):format(
        tostring(charId), tostring(previewPed), tostring(gender), tostring(stage.sceneId), pos.x, pos.y, pos.z,
        tostring(type(char.equipment) == 'table' and 'yes' or 'no')
    ))

    SetModelAsNoLongerNeeded(model)
end

local function walkInPreviewCharacter(charId)
    -- Backwards-compatible name used by existing callbacks/test commands.
    spawnSimplePreviewCharacter(charId)
end

local function focusPreviewCharacter(charId)
    walkInPreviewCharacter(charId)
end

local function sendShowApp()
    -- showApp can be lost if it fires before ui/app.js has mounted.
    -- uiReady below lets us replay it safely after the NUI is ready.
    SendNUIMessage({ action = 'showApp' })
end

local function sendShowSlots(accountId)
    SendNUIMessage({
        action = 'showSlots',
        slots = currentSlots or {},
        accountId = accountId or currentAccountId,
        maxCharacters = tonumber(Config and Config.MaxCharacters) or 2
    })
end

local function replaySelectorUi()
    if not selectorOpen then return end
    sendShowApp()
    if currentSlots then
        sendShowSlots(currentAccountId)
    end
end


RegisterNetEvent('cm-characters:client:selectorSceneConfig', function(config)
    if type(config) == 'table' then
        SavedSelectorScene = deepCopySceneConfig(config)
        if not EditorSceneDraft then EditorSceneDraft = deepCopySceneConfig(SavedSelectorScene) end
        dynamicStage = nil
        print('[CM-CHARACTERS] Selector scene config loaded: ' .. tostring(SavedSelectorScene.sceneId))
    end
end)

RegisterNetEvent('cm-characters:client:selectorSceneSaved', function(ok, message, config)
    if ok and type(config) == 'table' then
        SavedSelectorScene = deepCopySceneConfig(config)
        EditorSceneDraft = deepCopySceneConfig(SavedSelectorScene)
        dynamicStage = nil
    end
    print('[CM-CHARACTERS] selector editor save: ' .. tostring(message or ok))
end)

RegisterNUICallback('uiReady', function(data, cb)
    nuiReady = true
    cb('ok')

    if selectorOpen or pendingSelectorOpen then
        pendingSelectorOpen = false
        replaySelectorUi()
        if currentAccountId then
            TriggerServerEvent('cm-characters:server:getSlots', currentAccountId)
        end
    end
end)

RegisterNetEvent('cm-characters:client:openSelector', function(accountId)
    local accId = tostring(accountId)
    print('[CM-CHARACTERS] openSelector received! accountId=' .. accId)

    if selectorOpen and currentAccountId == accId then
        print('[CM-CHARACTERS] selector already open for this account, refreshing slots only')
    end

    currentAccountId = accId
    LocalPlayer.state:set('isInCharacterSelector', true, true)
    LocalPlayer.state:set('characterFullySpawned', false, true)
    LocalPlayer.state:set('skipPositionSave', true, true)
    TriggerServerEvent('cm-characters:server:enterSelectorBucket')
    preloadPreviewModels()
    TriggerServerEvent('cm-characters:server:requestSelectorSceneConfig')
    display = true
    selectorOpen = true
    SetNuiFocus(true, true)
    showCharacterLoading('Loading your character preview...')

    pendingSelectorOpen = not nuiReady
    sendShowApp()
    TriggerServerEvent('cm-characters:server:getSlots', accId)

    -- Fallback: if auth opens character selector before NUI JS is ready,
    -- replay the open message for a few seconds. This fixes the "music only, no UI" case.
    local attempts = 0
    local function retryOpenUi()
        if not selectorOpen then return end
        attempts = attempts + 1
        replaySelectorUi()
        if attempts < 12 then
            SetTimeout(250, retryOpenUi)
        end
    end
    SetTimeout(250, retryOpenUi)
end)

RegisterNetEvent('cm-characters:client:showSlots', function(slots, accountId, maxCharacters)
    print('[CM-CHARACTERS] showSlots received!')

    currentSlots = slots or {}
    showCharacterLoading('Preparing your character preview...')
    spawnPreviewPeds(currentSlots)

    sendShowSlots(accountId)

    -- Replay after a small delay in case the NUI page finished loading just after this event.
    SetTimeout(350, function()
        if selectorOpen then sendShowSlots(accountId) end
    end)

    -- Auto-preview immediately. The preview ped is created hidden first, then shown only
    -- after appearance/clothes are applied, so first load feels fast without default-ped flicker.
    local firstChar = nil
    for slot = 1, (tonumber(maxCharacters) or tonumber(Config and Config.MaxCharacters) or 2) do
        firstChar = currentSlots[tostring(slot)] or currentSlots[slot]
        if firstChar and firstChar.uniqueId then break end
    end
    if firstChar and firstChar.uniqueId then
        walkInPreviewCharacter(firstChar.uniqueId)
    else
        SetTimeout(tonumber(Config and Config.SelectorInitialLoadingMs) or 1800, function()
            if selectorOpen then hideCharacterLoading() end
        end)
    end
end)

RegisterNetEvent('cm-characters:client:error', function(msg)
    print('[CM-CHARACTERS] error: ' .. tostring(msg))
    display = true
    selectorOpen = true
    SetNuiFocus(true, true)
    sendShowApp()
    hideCharacterLoading()
    SendNUIMessage({ action = 'error', message = msg })
end)

-- Character deletion disabled. Characters are permanent for now.
RegisterNetEvent('cm-characters:client:deleted', function(charId)
    print('[CM-CHARACTERS] Delete event ignored; character deletion is disabled.')
end)

RegisterNUICallback('previewCharacter', function(data, cb)
    if data and data.charId then
        focusPreviewCharacter(data.charId)
    end
    cb('ok')
end)

RegisterNUICallback('selectSlot', function(data, cb)
    print('[CM-CHARACTERS] selectSlot: ' .. json.encode(data))

    if data.charId then
        display = false
        selectorOpen = false
        pendingSelectorOpen = false
        waitingForSpawnAfterSelect = true
        SetNuiFocus(false, false)
        -- No end loading screen. Close character UI/loading immediately and let cm-spawn open
        -- the selector for returning players, or do hotel spawn for true first-time players.
        markSpawnFlowStarted()
        SendNUIMessage({ action = 'hideAll' })
        -- Smooth transition: remove only the local preview dummy and camera, but keep
        -- the real player invisible/frozen until cm-spawn finishes. This removes the
        -- one-frame Michael/default ped blink before the spawn screen.
        cleanupSelectorSceneForSpawn()
        TriggerServerEvent('cm-characters:server:leaveSelectorBucket')
        -- Keep skipPositionSave=true until cm-playerdata/cm-spawn finishes the real spawn.
        TriggerServerEvent('cm-characters:server:selectCharacter', data.charId)
    else
        deletePreviewPeds(false)
        cleanupSelectorScene(true)
        TriggerServerEvent('cm-characters:server:leaveSelectorBucket')
        LocalPlayer.state:set('isInCharacterSelector', false, true)
        TriggerEvent('cm-characters:client:openCreator', data.slot, currentAccountId)
    end

    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    display = false
    selectorOpen = false
    pendingSelectorOpen = false
    SetNuiFocus(false, false)
    hideCharacterLoading()
    cleanupSelectorScene(true)
    TriggerServerEvent('cm-characters:server:leaveSelectorBucket')
    LocalPlayer.state:set('isInCharacterSelector', false, true)
    LocalPlayer.state:set('skipPositionSave', false, true)
    cb('ok')
end)


CreateThread(function()
    while true do
        if selectorOpen then
            if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(0) end
            HideHudAndRadarThisFrame()
            if selectorCam and DoesCamExist(selectorCam) then
                SetCamActive(selectorCam, true)
                RenderScriptCams(true, false, 0, true, true)
            end
            Wait(0)
        elseif waitingForSpawnAfterSelect then
            HideHudAndRadarThisFrame()
            DisplayRadar(false)
            hideRealPlayerForSelector()
            setCmHudVisible(false)
            Wait(0)
        else
            Wait(500)
        end
    end
end)


RegisterCommand('chartestui', function()
    local accountId = currentAccountId or tostring(LocalPlayer.state.accountId or '')
    if accountId == '' then
        print('[CM-CHARACTERS] /chartestui failed: no accountId in state yet')
        return
    end
    TriggerEvent('cm-characters:client:openSelector', accountId)
end, false)



RegisterCommand('charpreviewclear', function()
    deletePreviewPeds(true)
    print('[CM-CHARACTERS] Cleared all tracked selector preview peds.')
end, false)

RegisterCommand('charpreviewtest', function()
    local firstChar = nil
    for slot = 1, 2 do
        firstChar = currentSlots[tostring(slot)] or currentSlots[slot]
        if firstChar and firstChar.uniqueId then break end
    end

    if firstChar and firstChar.uniqueId then
        walkInPreviewCharacter(firstChar.uniqueId)
    else
        print('[CM-CHARACTERS] /charpreviewtest failed: no loaded character slots. Open selector first.')
    end
end, false)


local function printEditorHelp()
    print('^5[CM-CHARACTERS EDITOR]^7 Commands:')
    print('/charselectedit - enter/exit selector edit mode')
    print('/cssetplayer - save current player position as preview finish')
    print('/cssetwalkstart - save current player position as walk-in start')
    print('/cssetstream - save current player position as streaming/player move location')
    print('/cscamfromview - save current gameplay camera as selector camera')
    print('/csfov <number> - set camera FOV')
    print('/cstime <hour> <minute> - set selector time')
    print('/csweather <type> - set selector weather')
    print('/csanim <dict> <anim> - set idle animation')
    print('/cspreview - preview current draft')
    print('/cssave - save scene to data/selector_scene.json')
end

local function ensureEditorDraft()
    if not EditorSceneDraft then EditorSceneDraft = getActiveSelectorSceneConfig() end
    return EditorSceneDraft
end

local function getPedVec4()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    return vector4(coords.x, coords.y, coords.z, GetEntityHeading(ped))
end

local function setEditorCameraFromGameplay()
    local draft = ensureEditorDraft()
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    draft.camera = vector4(camCoords.x, camCoords.y, camCoords.z, 0.0)
    draft.camrotation = { x = camRot.x, y = camRot.y, z = camRot.z }
    dynamicStage = nil
    print(('[CM-CHARACTERS EDITOR] Camera saved: pos=(%.2f %.2f %.2f) rot=(%.2f %.2f %.2f)'):format(camCoords.x, camCoords.y, camCoords.z, camRot.x, camRot.y, camRot.z))
end

RegisterCommand('charselectedit', function()
    openSelectorSceneEditorUi()
end, false)

RegisterCommand('cshelp', printEditorHelp, false)

RegisterCommand('cssetplayer', function()
    local draft = ensureEditorDraft()
    draft.walkFinish = getPedVec4()
    draft.stream = getPedVec4()
    dynamicStage = nil
    print(('[CM-CHARACTERS EDITOR] Preview finish saved: %.2f %.2f %.2f h=%.2f'):format(draft.walkFinish.x, draft.walkFinish.y, draft.walkFinish.z, draft.walkFinish.w))
end, false)

RegisterCommand('cssetwalkstart', function()
    local draft = ensureEditorDraft()
    draft.walkStart = getPedVec4()
    dynamicStage = nil
    print(('[CM-CHARACTERS EDITOR] Walk start saved: %.2f %.2f %.2f h=%.2f'):format(draft.walkStart.x, draft.walkStart.y, draft.walkStart.z, draft.walkStart.w))
end, false)

RegisterCommand('cssetstream', function()
    local draft = ensureEditorDraft()
    draft.stream = getPedVec4()
    dynamicStage = nil
    print(('[CM-CHARACTERS EDITOR] Stream/player move location saved: %.2f %.2f %.2f h=%.2f'):format(draft.stream.x, draft.stream.y, draft.stream.z, draft.stream.w))
end, false)

RegisterCommand('cscamfromview', function()
    setEditorCameraFromGameplay()
end, false)

RegisterCommand('csfov', function(_, args)
    local draft = ensureEditorDraft()
    draft.fov = tonumber(args[1]) or draft.fov or 34.0
    dynamicStage = nil
    print('[CM-CHARACTERS EDITOR] FOV set to ' .. tostring(draft.fov))
end, false)

RegisterCommand('cstime', function(_, args)
    local draft = ensureEditorDraft()
    draft.time = draft.time or {}
    draft.time.hours = math.max(0, math.min(23, tonumber(args[1]) or draft.time.hours or 12))
    draft.time.minutes = math.max(0, math.min(59, tonumber(args[2]) or draft.time.minutes or 0))
    draft.time.seconds = 0
    applySceneEnvironment(draft)
    print(('[CM-CHARACTERS EDITOR] Time set to %02d:%02d'):format(draft.time.hours, draft.time.minutes))
end, false)

RegisterCommand('csweather', function(_, args)
    local draft = ensureEditorDraft()
    draft.weather = tostring(args[1] or draft.weather or 'EXTRASUNNY'):upper()
    applySceneEnvironment(draft)
    print('[CM-CHARACTERS EDITOR] Weather set to ' .. draft.weather)
end, false)

RegisterCommand('csanim', function(_, args)
    local draft = ensureEditorDraft()
    draft.idleDict = tostring(args[1] or draft.idleDict or 'amb@world_human_hang_out_street@male_c@idle_a')
    draft.idleAnim = tostring(args[2] or draft.idleAnim or 'idle_b')
    dynamicStage = nil
    print('[CM-CHARACTERS EDITOR] Animation set to dict=' .. draft.idleDict .. ' anim=' .. draft.idleAnim)
end, false)

RegisterCommand('cspreview', function()
    EditorSceneDraft = ensureEditorDraft()
    dynamicStage = nil
    selectorOpen = true
    local firstChar = nil
    for slot = 1, 2 do
        firstChar = currentSlots[tostring(slot)] or currentSlots[slot]
        if firstChar and firstChar.uniqueId then break end
    end
    if firstChar and firstChar.uniqueId then
        walkInPreviewCharacter(firstChar.uniqueId)
    else
        setupSelectorScene()
        print('[CM-CHARACTERS EDITOR] Preview scene loaded. No character slots loaded, so only camera/location changed.')
    end
end, false)

RegisterCommand('cssave', function()
    local draft = serializableSceneConfig(ensureEditorDraft())
    TriggerServerEvent('cm-characters:server:saveSelectorSceneConfig', draft)
end, false)

RegisterCommand('csprint', function()
    print(json.encode(serializableSceneConfig(ensureEditorDraft())))
end, false)


AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    cleanupSelectorScene(true)
end)

-- v1.3.1 NUI-based selector scene editor. This keeps the old console commands
-- available, but the normal workflow is now /charselectedit -> click editor buttons.
local function sendEditorSceneUpdate(message, ok)
    SendNUIMessage({
        action = 'sceneEditorUpdate',
        scene = serializableSceneConfig(ensureEditorDraft()),
        message = message,
        ok = ok ~= false
    })
end

local setupEditorPlayerPreview

function openSelectorSceneEditorUi()
    selectorEditMode = true
    EditorSceneDraft = getActiveSelectorSceneConfig()
    cleanupSelectorScene(false)

    local ped = PlayerPedId()
    local draft = ensureEditorDraft()
    local groundZ = getSafeGroundZ(draft.walkFinish.x, draft.walkFinish.y, draft.walkFinish.z)
    SetEntityCoordsNoOffset(ped, draft.walkFinish.x, draft.walkFinish.y, groundZ, false, false, false)
    SetEntityHeading(ped, draft.walkFinish.w or 0.0)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    DisplayRadar(true)
    setCmHudVisible(true)
    DoScreenFadeIn(0)
    applySceneEnvironment(draft)

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openSceneEditor', scene = serializableSceneConfig(draft) })
    setupEditorPlayerPreview('Editor opened with your current character preview.')
    print('[CM-CHARACTERS EDITOR] UI editor opened. Use the panel buttons/sliders to edit and save.')
end



-- v1.3.2 editor helper: the editor must show a real character even when the
-- normal selector slots are not loaded. This uses the player's current ped as
-- the preview actor, places it at the saved finish position, and activates the
-- saved camera. The NUI editor is only an overlay; this is the real GTA preview.
setupEditorPlayerPreview = function(message)
    selectorEditMode = true
    EditorSceneDraft = ensureEditorDraft()
    dynamicStage = nil

    deletePreviewPeds()
    destroySelectorCam()

    local realPed = PlayerPedId()
    if not lastPlayerCoords then
        lastPlayerCoords = GetEntityCoords(realPed)
        lastPlayerHeading = GetEntityHeading(realPed)
    end

    buildDynamicStage(EditorSceneDraft)
    local stage = getStage()
    applySceneEnvironment(stage.scene)

    local finish = stage.walkFinish
    local z = getSafeGroundZ(finish.x, finish.y, finish.z)

    -- Keep the real player only for world streaming. It is not the preview actor.
    SetEntityCoordsNoOffset(realPed, finish.x, finish.y, z, false, false, false)
    SetEntityHeading(realPed, finish.w or 0.0)
    SetEntityVisible(realPed, false, false)
    SetEntityCollision(realPed, false, false)
    SetEntityInvincible(realPed, true)
    FreezeEntityPosition(realPed, true)

    cleanupUntrackedPreviewDummies()

    local model = GetEntityModel(realPed)
    local previewPed = ClonePed(realPed, finish.w or 0.0, false, false)
    if not DoesEntityExist(previewPed) then
        requestModel(model)
        previewPed = CreatePed(4, model, finish.x, finish.y, z, finish.w or 0.0, false, false)
    end

    if DoesEntityExist(previewPed) then
        currentPreviewPed = previewPed
        currentPreviewCharId = '__editor_dummy__'
        previewPeds = { __editor_dummy__ = previewPed }

        SetEntityAsMissionEntity(previewPed, true, true)
        SetEntityCoordsNoOffset(previewPed, finish.x, finish.y, z, false, false, false)
        SetEntityHeading(previewPed, finish.w or 0.0)
        SetEntityVisible(previewPed, true, false)
        SetEntityAlpha(previewPed, 255, false)
        SetEntityCollision(previewPed, true, true)
        SetEntityInvincible(previewPed, true)
        SetBlockingOfNonTemporaryEvents(previewPed, true)
        SetPedCanRagdoll(previewPed, false)
        FreezeEntityPosition(previewPed, true)
        ClearPedTasksImmediately(previewPed)
        playPreviewIdle(previewPed)
    end

    DoScreenFadeIn(0)
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    SetArtificialLightsState(false)
    DisplayRadar(false)

    selectorCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(selectorCam, stage.camera.x, stage.camera.y, stage.camera.z)
    if stage.camrotation then
        SetCamRot(selectorCam, stage.camrotation.x, stage.camrotation.y, stage.camrotation.z, 2)
    else
        PointCamAtCoord(selectorCam, finish.x, finish.y, z + (stage.lookHeight or 0.92))
    end
    SetCamFov(selectorCam, stage.fov or 34.0)
    SetCamActive(selectorCam, true)
    RenderScriptCams(true, true, 350, true, true)

    SetFocusPosAndVel(finish.x, finish.y, z, 0.0, 0.0, 0.0)

    print(('[CM-CHARACTERS EDITOR] dummy preview active: entity=%s pos=(%.2f %.2f %.2f) cam=(%.2f %.2f %.2f)'):format(
        tostring(previewPed), finish.x, finish.y, z, stage.camera.x, stage.camera.y, stage.camera.z
    ))

    if message then
        sendEditorSceneUpdate(message, true)
    end
end


-- v1.3.4 Free Camera Builder
-- This makes scene setup easy: click Free Camera Mode, move with WASD/QE, look with mouse,
-- use mouse wheel to change FOV, ENTER to save camera, BACKSPACE to cancel.
local editorFreeCamActive = false

local function drawEditorHelpText(text)
    SetTextFont(4)
    SetTextScale(0.34, 0.34)
    SetTextColour(255, 255, 255, 225)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(0.025, 0.82)
end

local function startEditorFreeCamera()
    local draft = ensureEditorDraft()
    setupEditorPlayerPreview(nil)

    if not selectorCam or not DoesCamExist(selectorCam) then
        selectorCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    end

    local pos = vector3(draft.camera.x, draft.camera.y, draft.camera.z)
    local rot = draft.camrotation or { x = -8.0, y = 0.0, z = draft.camera.w or 0.0 }
    local pitch = tonumber(rot.x) or -8.0
    local yaw = tonumber(rot.z) or 0.0
    local fov = tonumber(draft.fov) or 34.0

    SetCamCoord(selectorCam, pos.x, pos.y, pos.z)
    SetCamRot(selectorCam, pitch, 0.0, yaw, 2)
    SetCamFov(selectorCam, fov)
    SetCamActive(selectorCam, true)
    RenderScriptCams(true, true, 150, true, true)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)

    editorFreeCamActive = true
    print('[CM-CHARACTERS EDITOR] Free camera mode enabled. WASD/QE + mouse, ENTER save, BACKSPACE cancel.')

    CreateThread(function()
        while editorFreeCamActive do
            Wait(0)

            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)   -- look left/right
            EnableControlAction(0, 2, true)   -- look up/down
            EnableControlAction(0, 241, true) -- wheel up
            EnableControlAction(0, 242, true) -- wheel down

            local speed = IsDisabledControlPressed(0, 21) and 0.22 or 0.075
            if IsDisabledControlPressed(0, 36) then speed = 0.025 end

            local lookX = GetDisabledControlNormal(0, 1)
            local lookY = GetDisabledControlNormal(0, 2)
            yaw = yaw - (lookX * 5.0)
            pitch = math.max(-89.0, math.min(89.0, pitch - (lookY * 5.0)))

            local yawRad = math.rad(yaw)
            local forward = vector3(-math.sin(yawRad), math.cos(yawRad), 0.0)
            local right = vector3(math.cos(yawRad), math.sin(yawRad), 0.0)

            if IsDisabledControlPressed(0, 32) then pos = pos + forward * speed end -- W
            if IsDisabledControlPressed(0, 33) then pos = pos - forward * speed end -- S
            if IsDisabledControlPressed(0, 34) then pos = pos - right * speed end -- A
            if IsDisabledControlPressed(0, 35) then pos = pos + right * speed end -- D
            if IsDisabledControlPressed(0, 44) then pos = vector3(pos.x, pos.y, pos.z + speed) end -- Q
            if IsDisabledControlPressed(0, 38) then pos = vector3(pos.x, pos.y, pos.z - speed) end -- E

            if IsDisabledControlJustPressed(0, 241) then fov = math.max(15.0, fov - 1.0) end
            if IsDisabledControlJustPressed(0, 242) then fov = math.min(75.0, fov + 1.0) end

            SetCamCoord(selectorCam, pos.x, pos.y, pos.z)
            SetCamRot(selectorCam, pitch, 0.0, yaw, 2)
            SetCamFov(selectorCam, fov)

            drawEditorHelpText(('~p~Character Selector Free Camera~s~\nWASD move | Q/E up-down | Mouse look | Wheel FOV %.0f\nSHIFT fast | CTRL slow | ~g~ENTER save~s~ | ~r~BACKSPACE cancel~s~'):format(fov))

            if IsDisabledControlJustPressed(0, 191) then -- ENTER
                editorFreeCamActive = false
                draft.camera = vector4(pos.x, pos.y, pos.z, yaw)
                draft.camrotation = { x = pitch, y = 0.0, z = yaw }
                draft.fov = fov
                dynamicStage = nil
                setupEditorPlayerPreview('Free camera saved. Continue editing or Save Scene.')
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'openSceneEditor', scene = serializableSceneConfig(draft) })
                break
            elseif IsDisabledControlJustPressed(0, 177) then -- BACKSPACE
                editorFreeCamActive = false
                setupEditorPlayerPreview('Free camera cancelled.')
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'openSceneEditor', scene = serializableSceneConfig(draft) })
                break
            end
        end
    end)
end

RegisterNUICallback('editorClose', function(data, cb)
    SetNuiFocus(false, false)
    selectorEditMode = false
    selectorOpen = false
    cleanupSelectorScene(true)
    cb({ ok = true })
end)

RegisterNUICallback('editorAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local actionName = tostring(data.actionName or '')
    local draft = ensureEditorDraft()

    if actionName == 'setPlayerFromCurrent' then
        draft.walkFinish = getPedVec4()
        draft.stream = getPedVec4()
        dynamicStage = nil
        setupEditorPlayerPreview('Character finish saved from current player position.')

    elseif actionName == 'setWalkStartFromCurrent' then
        draft.walkStart = getPedVec4()
        dynamicStage = nil
        setupEditorPlayerPreview('Walk start saved from current player position.')

    elseif actionName == 'setStreamFromCurrent' then
        draft.stream = getPedVec4()
        dynamicStage = nil
        setupEditorPlayerPreview('Stream location saved from current player position.')

    elseif actionName == 'setCamFromView' then
        setEditorCameraFromGameplay()
        setupEditorPlayerPreview('Camera saved from current view.')

    elseif actionName == 'updateBasic' then
        draft.fov = tonumber(data.fov) or draft.fov or 34.0
        draft.weather = tostring(data.weather or draft.weather or 'EXTRASUNNY'):upper()
        if type(data.time) == 'table' then
            draft.time = draft.time or {}
            draft.time.hours = math.max(0, math.min(23, tonumber(data.time.hours) or draft.time.hours or 12))
            draft.time.minutes = math.max(0, math.min(59, tonumber(data.time.minutes) or draft.time.minutes or 0))
            draft.time.seconds = 0
        end
        dynamicStage = nil
        applySceneEnvironment(draft)
        setupEditorPlayerPreview(nil)

    elseif actionName == 'nudge' then
        local target = tostring(data.target or '')
        local axis = tostring(data.axis or '')
        local delta = tonumber(data.delta) or 0.0
        if draft[target] and (axis == 'x' or axis == 'y' or axis == 'z' or axis == 'w') then
            draft[target] = vector4(
                draft[target].x + (axis == 'x' and delta or 0.0),
                draft[target].y + (axis == 'y' and delta or 0.0),
                draft[target].z + (axis == 'z' and delta or 0.0),
                draft[target].w + (axis == 'w' and delta or 0.0)
            )
            dynamicStage = nil
            setupEditorPlayerPreview(('Nudged %s %s by %s.'):format(target, axis, tostring(delta)))
        else
            sendEditorSceneUpdate('Invalid nudge target.', false)
        end

    elseif actionName == 'applyAnimPreset' then
        local preset = tostring(data.preset or 'idle')
        local presets = {
            idle = { dict = 'amb@world_human_hang_out_street@male_c@idle_a', anim = 'idle_b' },
            lean = { dict = 'amb@world_human_leaning@female@wall@back@holding_elbow@idle_a', anim = 'idle_a' },
            armscrossed = { dict = 'amb@world_human_hang_out_street@female_arms_crossed@idle_a', anim = 'idle_a' },
            guard = { dict = 'amb@world_human_stand_guard@male@idle_a', anim = 'idle_a' }
        }
        local picked = presets[preset] or presets.idle
        draft.idleDict = picked.dict
        draft.idleAnim = picked.anim
        dynamicStage = nil
        setupEditorPlayerPreview('Animation preset applied.')

    elseif actionName == 'preview' then
        EditorSceneDraft = draft
        dynamicStage = nil
        selectorOpen = true
        local firstChar = nil
        for slot = 1, (tonumber(maxCharacters) or tonumber(Config and Config.MaxCharacters) or 2) do
            firstChar = currentSlots[tostring(slot)] or currentSlots[slot]
            if firstChar and firstChar.uniqueId then break end
        end
        if firstChar and firstChar.uniqueId then
            walkInPreviewCharacter(firstChar.uniqueId)
            sendEditorSceneUpdate('Previewing with first loaded character.', true)
        else
            setupEditorPlayerPreview('Previewing with your current character. Open selector first only if you want to preview a saved slot instead.')
        end

    elseif actionName == 'showPlayerPreview' then
        setupEditorPlayerPreview('Showing your current character in the scene.')

    elseif actionName == 'freeCamera' then
        startEditorFreeCamera()
        sendEditorSceneUpdate('Free camera enabled. ENTER saves, BACKSPACE cancels.', true)

    elseif actionName == 'resetDraft' then
        EditorSceneDraft = SavedSelectorScene and deepCopySceneConfig(SavedSelectorScene) or deepCopySceneConfig(FixedGroundPreview)
        dynamicStage = nil
        setupEditorPlayerPreview('Draft reset and preview refreshed.')

    elseif actionName == 'save' then
        local saveData = serializableSceneConfig(draft)
        TriggerServerEvent('cm-characters:server:saveSelectorSceneConfig', saveData)
        sendEditorSceneUpdate('Saving scene...', true)

    else
        sendEditorSceneUpdate('Unknown editor action: ' .. actionName, false)
    end

    cb({ ok = true })
end)

-- Override the previous command handler with a UI-first editor entry point.
RegisterCommand('charselecteditui', function()
    openSelectorSceneEditorUi()
end, false)

AddEventHandler('cm-characters:client:selectorSceneSaved', function(ok, message, config)
    if selectorEditMode then
        sendEditorSceneUpdate(message or (ok and 'Scene saved.' or 'Save failed.'), ok == true)
    end
end)

RegisterCommand('csfreecam', function()
    if not selectorEditMode then openSelectorSceneEditorUi() end
    SetTimeout(250, function() startEditorFreeCamera() end)
end, false)


-- cm-playerdata compatibility: selection/preview moves the hidden player to the preview scene.
-- Keep position saving disabled during selector and only re-enable after the real character spawn is finished.
RegisterNetEvent('cm-characters:client:characterReady', function()
    waitingForSpawnAfterSelect = false
    hideCharacterLoading(true)
    unmuteSelectorAudio()
    restoreRealPlayerAfterSelector()
    LocalPlayer.state:set('isInCharacterSelector', false, true)
    LocalPlayer.state:set('characterFullySpawned', true, true)
    LocalPlayer.state:set('skipPositionSave', false, true)
    setCmHudVisible(true)
end)

RegisterNetEvent('cm-spawn:client:spawned', function()
    waitingForSpawnAfterSelect = false
    hideCharacterLoading(true)
    unmuteSelectorAudio()
    restoreRealPlayerAfterSelector()
    LocalPlayer.state:set('isInCharacterSelector', false, true)
    LocalPlayer.state:set('characterFullySpawned', true, true)
    LocalPlayer.state:set('skipPositionSave', false, true)
    setCmHudVisible(true)
end)


-- Hard guard: if cm-spawn starts/open selector, cm-characters loader must never stay over spawn UI.
RegisterNetEvent('cm-spawn:client:open', function()
    markSpawnFlowStarted()
end)

RegisterNetEvent('cm-spawn:client:openSelector', function()
    markSpawnFlowStarted()
end)

RegisterNetEvent('cm-spawn:client:showSelector', function()
    markSpawnFlowStarted()
end)
