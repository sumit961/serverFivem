--========================================================
-- Admin inventory icon capture
-- Captures the current live preview with screenshot-basic,
-- sends it to NUI for green-screen background removal,
-- then server saves transparent PNG/WebP files inside nv_cloth/generated_images.
--
-- NO-HEAD METHOD: require allowEmptyHeadDrawable + component 0 drawable -1.
-- Inventory capture has no reset-flag or image-subtraction fallback.
--========================================================

local pendingIconCapture = nil
local activeCaptureSession = nil

local emptyHeadCommandLastAt = -10000

local function ensureClientEmptyHeadEnabled()
  -- A replicated value is not honoured on every artifact. Request the client
  -- setting automatically at resource start and again before every capture run.
  -- FiveM still requires the capture client to be launched in developer mode.
  local now = GetGameTimer()
  if now - emptyHeadCommandLastAt >= 1000 then
    ExecuteCommand('allowEmptyHeadDrawable true')
    emptyHeadCommandLastAt = now
    Wait(0)
  end
end

CreateThread(function()
  Wait(500)
  ensureClientEmptyHeadEnabled()
  Wait(1500)
  ensureClientEmptyHeadEnabled()
end)



--========================================================
-- Clean daylight / no-shadow capture environment
--========================================================

local cleanCaptureLightingActive = false
local cleanCaptureLightingThreadRunning = false
local activeCaptureLightingOverride = nil

local function safeCall(fn, ...)
  if type(fn) ~= 'function' then return end
  pcall(fn, ...)
end

local function applyCleanCaptureLightingOnce()
  local cfg = activeCaptureLightingOverride
    or (Config.IconCapture and Config.IconCapture.lighting) or {}
  if cfg.enabled == false then return end

  local hour = tonumber(cfg.hour) or 12
  local minute = tonumber(cfg.minute) or 0
  local second = tonumber(cfg.second) or 0
  local weather = tostring(cfg.weather or 'EXTRASUNNY')

  -- Stable bright daylight.
  safeCall(NetworkOverrideClockTime, hour, minute, second)
  safeCall(ClearOverrideWeather)
  safeCall(ClearWeatherTypePersist)
  safeCall(SetWeatherTypeNow, weather)
  safeCall(SetWeatherTypeNowPersist, weather)
  safeCall(SetWeatherTypePersist, weather)
  safeCall(SetRainLevel, 0.0)
  safeCall(SetWind, 0.0)
  safeCall(SetWindSpeed, 0.0)
  safeCall(SetCloudHatOpacity, 0.0)
  safeCall(ClearCloudHat)

  -- Keep artificial/night lighting from changing the color of clothes.
  safeCall(SetArtificialLightsState, false)
  safeCall(SetArtificialLightsStateAffectsVehicles, false)

  -- Neutral daylight color. Strength 0 still keeps the modifier from adding odd tint.
  if cfg.timecycle and tostring(cfg.timecycle) ~= '' then
    safeCall(SetTimecycleModifier, tostring(cfg.timecycle))
    safeCall(SetTimecycleModifierStrength, tonumber(cfg.timecycleStrength) or 0.0)
  else
    safeCall(ClearTimecycleModifier)
  end

  -- Remove GTA's dark ambient blob under/around the ped.
  if cfg.noPedBlobShadow ~= false then
    local ped = PlayerPedId()
    if ped and ped ~= 0 and DoesEntityExist(ped) then
      safeCall(SetPedAoBlobRendering, ped, false)
    end
  end

  -- Try to reduce sun cascade shadows during the screenshot window.
  -- These natives exist on many FiveM builds; safeCall keeps old builds safe.
  if cfg.suppressCascadeShadows ~= false then
    safeCall(CascadeShadowsEnableEntityTracker, false)
    safeCall(CascadeShadowsSetDynamicDepthMode, false)
    safeCall(CascadeShadowsSetCascadeBoundsScale, 0.0)
    safeCall(CascadeShadowsSetEntityTrackerScale, 0.0)
    safeCall(CascadeShadowsClearShadowSampleType)
  end
end

local function startCleanCaptureLighting(override)
  activeCaptureLightingOverride = type(override) == 'table' and override or nil
  local cfg = activeCaptureLightingOverride
    or (Config.IconCapture and Config.IconCapture.lighting) or {}
  if cfg.enabled == false then return end

  applyCleanCaptureLightingOnce()
  cleanCaptureLightingActive = true

  if cleanCaptureLightingThreadRunning or cfg.applyEveryFrame == false then return end
  cleanCaptureLightingThreadRunning = true

  CreateThread(function()
    while cleanCaptureLightingActive do
      applyCleanCaptureLightingOnce()
      Wait(0)
    end
    cleanCaptureLightingThreadRunning = false
  end)
end

local function stopCleanCaptureLighting()
  cleanCaptureLightingActive = false

  -- Restore normal client environment after capture.
  safeCall(ClearTimecycleModifier)
  safeCall(NetworkClearClockTimeOverride)
  safeCall(ClearOverrideWeather)
  safeCall(ClearWeatherTypePersist)

  local ped = PlayerPedId()
  if ped and ped ~= 0 and DoesEntityExist(ped) then
    safeCall(SetPedAoBlobRendering, ped, true)
  end

  safeCall(CascadeShadowsEnableEntityTracker, true)
  safeCall(CascadeShadowsSetDynamicDepthMode, true)
  safeCall(CascadeShadowsSetCascadeBoundsScale, 1.0)
  safeCall(CascadeShadowsSetEntityTrackerScale, 1.0)
  activeCaptureLightingOverride = nil
end

local function getCurrentGender()
  return GetEntityModel(PlayerPedId()) == GetHashKey('mp_f_freemode_01') and 'female' or 'male'
end

local function normalizeCaptureGender(value)
  value = tostring(value or ''):lower()
  if value == 'female' or value == 'f' or value == 'mp_f_freemode_01' then return 'female' end
  if value == 'male' or value == 'm' or value == 'mp_m_freemode_01' then return 'male' end
  return nil
end


local function safeFilePart(value)
  value = tostring(value or ''):lower()
  value = value:gsub('[^%w_%-]', '_')
  value = value:gsub('_+', '_')
  return value
end

local function getCapturePreset(category)
  local presets = Config.IconCapture and Config.IconCapture.presets or {}
  local preset = presets[category]
  if type(preset) ~= 'table' then preset = {} end
  return preset
end

local function getIconCaptureCrop(category)
  local configured = Config.IconCapture and Config.IconCapture.crops and Config.IconCapture.crops[category]
  if type(configured) == 'table' then return configured end

  local preset = getCapturePreset(category)

  local paddings = {
    torso = 10,
    armor = 10,
    tshirt = 10,
    pants = 8,
    shoes = 8,
    hat = 8,
    glasses = 6,
    earrings = 6,
    chains = 6,
    bags = 10,
    watches = 6,
    bracelets = 6,
  }

  local crop = {
    -- Keep almost the entire screenshot as a safety frame. The chroma/alpha pass
    -- below finds the real item bounds and centres them, so an early 10% trim only
    -- risked cutting wide bags, hats, sleeves and shoe tips.
    x = 0.02,
    y = 0.02,
    w = 0.96,
    h = 0.96,
    camera = category,
    padding = preset.padding or paddings[category] or 10,
  }

  return crop
end

local function viewOffset(view)
  view = tostring(view or 'front'):lower()

  if view == 'back' then return 180.0 end
  if view == 'left' then return 90.0 end
  if view == 'right' then return -90.0 end
  if view == 'front-left' then return 45.0 end
  if view == 'front-right' then return -45.0 end
  if view == 'back-left' then return 135.0 end
  if view == 'back-right' then return -135.0 end

  return 0.0
end

-- Resolve the exact ped rotation offset for a capture.
-- Priority: an explicit numeric per-item captureAngleDeg > per-category viewAngle
-- (from the preset) > the named view keyword (front/left/right/back/...).
-- This is Option B: the CAMERA stays fixed per category and only the PED rotates
-- so the item (watch, glasses, bag) is presented to the camera the same way for
-- every drawable in that category.
local function resolveViewOffset(payload, preset)
  local explicit = tonumber(payload and payload.captureAngleDeg)
  if explicit then return explicit % 360.0 end

  if payload and payload.captureAngleOverride == true then
    return viewOffset(payload.captureAngle or 'front')
  end

  local presetAngle = tonumber(preset and preset.viewAngle)
  if presetAngle then return presetAngle % 360.0 end

  return viewOffset((payload and payload.captureAngle) or (preset and preset.view) or 'front')
end

local function snapshotPedAppearance(ped)
  local snap = {
    comps = {},
    props = {},
    appearance = nil,
  }

  -- Optional full appearance snapshot for servers using an appearance resource.
  if type(getPedAppearance) == 'function' then
    local ok, appearance = pcall(getPedAppearance)
    if ok and type(appearance) == 'table' then
      snap.appearance = appearance
    end
  end

  for i = 0, 11 do
    snap.comps[i] = {
      drawable = GetPedDrawableVariation(ped, i),
      texture = GetPedTextureVariation(ped, i),
    }
  end

  for i = 0, 7 do
    snap.props[i] = {
      drawable = GetPedPropIndex(ped, i),
      texture = GetPedPropTextureIndex(ped, i),
    }
  end

  return snap
end

local function restorePedAppearance(ped, snap)
  if type(snap) ~= 'table' then return end

  local comps = snap.comps or {}
  for i = 0, 11 do
    local it = comps[i]
    if it and it.drawable ~= nil then
      SetPedComponentVariation(ped, i, tonumber(it.drawable) or 0, tonumber(it.texture) or 0, 0)
    end
  end

  local props = snap.props or {}
  for i = 0, 7 do
    local it = props[i]

    if it then
      local d = tonumber(it.drawable) or -1

      if d >= 0 then
        SetPedPropIndex(ped, i, d, tonumber(it.texture) or 0, true)
      else
        ClearPedProp(ped, i)
      end
    else
      ClearPedProp(ped, i)
    end
  end

  if snap.appearance and type(savePedAppearance) == 'function' then
    pcall(savePedAppearance, snap.appearance)
  end
end

local function restoreRealPedAfterCapture(playerPed, originalCoords, originalHeading, originalVisible,
  originalAlpha, originalFrozen, originalInvincible, originalCanRagdoll)
  if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed) then return end

  SetEntityVisible(playerPed, originalVisible ~= false, false)

  if originalAlpha and originalAlpha < 255 then
    SetEntityAlpha(playerPed, originalAlpha, false)
  else
    ResetEntityAlpha(playerPed)
  end

  SetEntityCoordsNoOffset(playerPed, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false)
  SetEntityHeading(playerPed, originalHeading)
  SetPedAoBlobRendering(playerPed, true)

  if originalFrozen ~= nil then
    FreezeEntityPosition(playerPed, originalFrozen == true)
  else
    FreezeEntityPosition(playerPed, false)
  end

  SetPedCanRagdoll(playerPed, originalCanRagdoll ~= false)
  SetEntityInvincible(playerPed, originalInvincible == true)
end

-- Components hidden by default, with the value used to hide each one.
-- (Head [0] and hair [2] are handled separately so the head can stay invisible.)
local GHOST_HIDE = {
  [1] = 0, [3] = -1, [4] = -1, [5] = 0, [6] = -1,
  [7] = 0, [8] = -1, [9] = 0, [10] = 0, [11] = -1,
}

-- Every configurable freemode component except the head mesh (component 0).
-- The empty drawable mirrors the values already used by the ghost capture path:
-- some overlay slots use drawable 0 for "none", while body meshes use -1.
local CAPTURE_COMPONENTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local CAPTURE_PROPS = { 0, 1, 2, 3, 4, 5, 6, 7 }

-- Single-pass native isolation. The clean capture ped never receives head blend
-- data, so allowEmptyHeadDrawable can hide component 0 with drawable -1. Every
-- unrelated body component/prop is emptied and only the selected item is applied.
local function applyNativeIsolatedCapture(ped, payload)
  local category = tostring(payload.category or ''):lower()
  local cat = categories[category]
  if not cat then return nil end

  local drawable = math.max(0, math.floor(tonumber(payload.drawableId or payload.drawable) or 0))
  local texture = math.max(0, math.floor(tonumber(payload.textureId or payload.texture or 0) or 0))
  local targetComponent = cat.type == 'component' and cat.index or nil

  ClearPedTasksImmediately(ped)
  RemoveAllPedWeapons(ped, true)
  ClearAllPedProps(ped)
  ensureClientEmptyHeadEnabled()
  SetPedComponentVariation(ped, 2, -1, 0, 0) -- hair

  local emptyHeadAccepted = false
  for _ = 1, 3 do
    SetPedComponentVariation(ped, 0, -1, 0, 0)
    Wait(50)
    if GetPedDrawableVariation(ped, 0) == -1 then
      emptyHeadAccepted = true
      break
    end
  end

  for _, componentId in ipairs(CAPTURE_COMPONENTS) do
    if componentId ~= 2 and componentId ~= targetComponent then
      SetPedComponentVariation(ped, componentId, GHOST_HIDE[componentId] or -1, 0, 0)
    end
  end

  if cat.type == 'prop' then
    SetPedPropIndex(ped, cat.index, drawable, texture, true)
  else
    SetPedComponentVariation(ped, cat.index, drawable, texture, 0)
  end

  print(('[nv_cloth] native single-pass cat=%s type=%s idx=%s item=%s/%s emptyHead=%s'):format(
    category, cat.type, tostring(cat.index), drawable, texture, tostring(emptyHeadAccepted)))
  return emptyHeadAccepted
end


local function buildIconCapturePayload(data)
  data = type(data) == 'table' and data or {}

  local ped = PlayerPedId()
  local category = tostring(data.category or data.type or ''):lower()
  local cat = categories[category]

  if not cat then return nil, 'invalid_category' end

  local preset = getCapturePreset(category)
  local crop = getIconCaptureCrop(category)
  local studioSettings = type(GetStudioSettings) == 'function' and GetStudioSettings(category) or nil
  local captureLighting = {}
  local configuredLighting = Config.IconCapture and Config.IconCapture.lighting or {}
  for key, value in pairs(configuredLighting) do captureLighting[key] = value end
  if type(studioSettings) == 'table' and studioSettings.lightStrength ~= nil then
    captureLighting.timecycleStrength = tonumber(studioSettings.lightStrength) or captureLighting.timecycleStrength
  end

  local drawable = tonumber(data.drawableId or data.drawable)
  if not drawable then return nil, 'invalid_drawable' end

  -- Admin catalog rows can represent a different gender from the real player.
  -- Capture the selected item's model, otherwise a female hat/glasses row selected
  -- by a male admin spawns the male freemode head and uses the wrong prop indices.
  local gender = normalizeCaptureGender(data.gender or data.pedGender or data.sex)
    or getCurrentGender()
  local texture = math.max(0, math.floor(tonumber(data.textureId or data.texture or 0) or 0))

  local sharedGender = (category == 'bags' and data.sharedGender ~= false)
    or data.sharedGender == true
    or preset.sharedGender == true

  local fileGender = sharedGender and 'shared' or gender

  local fileName = ('%s_%s_%s_%s_%s.png'):format(
    safeFilePart(fileGender),
    safeFilePart(category),
    tostring(cat.index),
    tostring(drawable),
    tostring(texture)
  )
  local uniqueId = ('nvcloth_%s_%s_%s_%s_d%s_t%s'):format(
    gender, safeFilePart(category), tostring(cat.type), tostring(cat.index),
    tostring(drawable), tostring(texture))

  local payload = {
    shop = (NvCloth_GetCurrentShopKey and NvCloth_GetCurrentShopKey()) or 'clothes',
    gender = gender,
    category = category,
    componentType = cat.type,
    componentIndex = cat.index,
    drawableId = drawable,
    textureId = texture,
    label = data.label,
    price = data.price,
    enabled = true,
    fileName = fileName,
    uniqueId = uniqueId,
    unique_id = uniqueId,
    clothingId = uniqueId,
    clothing_id = uniqueId,
    width = Config.IconCapture and Config.IconCapture.width or 512,
    height = Config.IconCapture and Config.IconCapture.height or 512,
    padding = crop.padding or (Config.IconCapture and Config.IconCapture.padding) or 18,
    chroma = Config.IconCapture and Config.IconCapture.chroma or nil,
    autoCrop = Config.IconCapture and Config.IconCapture.autoCrop or nil,
    formats = Config.IconCapture and Config.IconCapture.formats or { png = true },
    webpQuality = tonumber(Config.IconCapture and Config.IconCapture.webpQuality) or 0.94,
    lighting = captureLighting,
    crop = crop,
    captureAngle = tostring(data.captureAngle or preset.view or 'front'):lower(),
    captureAngleOverride = data.captureAngleOverride == true,
    zOffset = tonumber(data.zOffset or preset.zOffset or 0.0) or 0.0,
    -- Backdrop: explicit request wins, else the saved studio backdrop for this
    -- category, else preset/green.
    captureBackground = tostring(
      data.captureBackground or data.backgroundColor
      or (type(studioSettings) == 'table' and studioSettings.backdrop)
      or preset.backgroundColor or 'green'):lower(),
    sharedGender = sharedGender,
    level = tonumber(data.level or data.bagLevel),
    bagLevel = tonumber(data.bagLevel or data.level),
    armorValue = tonumber(data.armorValue or data.armor_value),

    -- Store/hidden destination + restrictions.
    destination = tostring(data.destination or 'store'):lower(),
    requiredJob = data.requiredJob or data.required_job,
    requiredGang = data.requiredGang or data.required_gang,
    requiredFamily = data.requiredFamily or data.required_family,
  }

  if category == 'torso' then
    payload.arms = GetPedDrawableVariation(ped, 3)
    payload.armsTexture = GetPedTextureVariation(ped, 3)
    payload.undershirt = GetPedDrawableVariation(ped, 8)
    payload.undershirtTexture = GetPedTextureVariation(ped, 8)
  end

  return payload
end

-- Which categories support manual "pose then confirm" capture.
local MANUAL_CAPABLE = {
  torso = true, tshirt = true, pants = true, shoes = true, hat = true,
  glasses = true, earrings = true, chains = true, bags = true,
  watches = true, bracelets = true, armor = true,
}

-- Active manual-capture session (nil when not posing). Holds everything needed to
-- shoot + restore once the admin confirms the angle.
local manualSession = nil

local captureAnimationClockLocked = false

-- The character-creation animation rotates shoulders and changes the apparent
-- angle/shape of upper-body clothing. For these categories the capture clock is
-- still stopped and every idle/IK/facial source is disabled, but no pose clip is
-- applied. That keeps Shirts and Outerwear in the exact neutral orientation used
-- when their camera/player preset was measured.
local TRANSFORM_ONLY_FREEZE = {
  torso = true,
  tshirt = true,
  armor = true,
}

local function capturePoseClip(gender)
  if tostring(gender or ''):lower() == 'female' then
    return 'mp_character_creation@customise@female_a', 'loop'
  end
  return 'mp_character_creation@customise@male_a', 'loop'
end

local function disablePedSecondaryAnimation(ped)
  if not ped or ped == 0 or not DoesEntityExist(ped) then return end
  SetPedCanPlayAmbientAnims(ped, false)
  SetPedCanPlayAmbientBaseAnims(ped, false)
  SetPedCanPlayGestureAnims(ped, false)
  SetPedCanPlayVisemeAnims(ped, false, false)
  SetPedCanHeadIk(ped, false)
  SetPedCanTorsoIk(ped, false)
  SetPedCanTorsoReactIk(ped, false)
  SetPedCanArmIk(ped, false)
  SetPedCanRagdoll(ped, false)
end

-- Lock the skeleton to one exact frame of GTA's neutral character-creation pose.
-- FreezeEntityPosition only locks world coordinates; this additionally stops
-- breathing, idle sway, gestures, IK, speech/viseme animation and facial idles.
local function startCaptureAnimationLock(session)
  if type(session) ~= 'table' then return false end
  local ped = session.playerPed
  if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
  local category = tostring(session.category or ''):lower()
  disablePedSecondaryAnimation(ped)
  ClearPedTasksImmediately(ped)

  if TRANSFORM_ONLY_FREEZE[category] then
    session.animationLock = { staticTransform = true }
    captureAnimationClockLocked = true
    SetTimeScale(0.0)
    print(('[nv_cloth] capture skeleton frozen without pose animation: %s'):format(category))
    return true
  end

  local dict, clip = capturePoseClip(session.captureGender)
  RequestAnimDict(dict)
  local deadline = GetGameTimer() + 4000
  while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
  if not HasAnimDictLoaded(dict) then
    print(('[nv_cloth] static capture pose failed to load: %s/%s'):format(dict, clip))
    return false
  end

  TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
  Wait(100)
  local frame = 0.15
  SetEntityAnimCurrentTime(ped, dict, clip, frame)
  SetEntityAnimSpeed(ped, dict, clip, 0.0)
  session.animationLock = { dict = dict, clip = clip, frame = frame }
  captureAnimationClockLocked = true
  SetTimeScale(0.0)
  print(('[nv_cloth] capture skeleton/facial animation locked: %s/%s @ %.2f'):format(dict, clip, frame))
  return true
end

local function stopCaptureAnimationLock(session)
  if captureAnimationClockLocked then
    SetTimeScale(1.0)
    captureAnimationClockLocked = false
  end
  local lock = type(session) == 'table' and session.animationLock or nil
  if lock and lock.dict then RemoveAnimDict(lock.dict) end
  if type(session) == 'table' then session.animationLock = nil end
end

-- Hard movement lock for the complete capture lifecycle. The disposable capture
-- ped was already frozen, but the hidden real player could still receive WASD or
-- controller input underneath NUI. Freeze both and suppress gameplay movement;
-- every cleanup route restores the real player's original frozen state.
CreateThread(function()
  while true do
    local session = manualSession or activeCaptureSession
    if session then
      local realPed = session.realPlayerPed or PlayerPedId()
      if realPed and DoesEntityExist(realPed) then
        FreezeEntityPosition(realPed, true)
        SetEntityVelocity(realPed, 0.0, 0.0, 0.0)
      end
      local capturePed = session.playerPed
      if capturePed and DoesEntityExist(capturePed) then
        FreezeEntityPosition(capturePed, true)
        SetEntityVelocity(capturePed, 0.0, 0.0, 0.0)
        local lock = session.animationLock
        if lock then
          SetTimeScale(0.0)
          disablePedSecondaryAnimation(capturePed)
          if not lock.staticTransform then
            if not IsEntityPlayingAnim(capturePed, lock.dict, lock.clip, 3) then
              TaskPlayAnim(capturePed, lock.dict, lock.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            end
            SetEntityAnimCurrentTime(capturePed, lock.dict, lock.clip, lock.frame)
            SetEntityAnimSpeed(capturePed, lock.dict, lock.clip, 0.0)
          end
        end
      end

      -- Keyboard/controller movement, sprint, jump, combat and vehicle exit.
      for _, control in ipairs({ 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 44, 75 }) do
        DisableControlAction(0, control, true)
      end
      DisablePlayerFiring(PlayerId(), true)
      Wait(0)
    else
      Wait(200)
    end
  end
end)

-- Remembered manual pose per category. Once you pose & shoot one texture, the
-- rest of that item's textures (and re-captures of the category) reuse the same
-- ped heading, lift and camera automatically — no re-posing each time.
local RememberedPose = {}

-- Apply the exact capture target again after the body visibility preset has run.
-- Streamed props can fail their first SetPedPropIndex call while the drawable is
-- still loading; components can also be replaced by an appearance event between
-- setup and screenshot. Reasserting from one normalized spec makes every shot use
-- the requested drawable/texture, independent of the normal store preview state.
local function applyCaptureTargetSpec(ped, spec)
  if not ped or ped == 0 or not DoesEntityExist(ped) or type(spec) ~= 'table' then return false end
  local drawable = math.floor(tonumber(spec.drawable) or -1)
  local texture = math.max(0, math.floor(tonumber(spec.texture) or 0))
  local index = tonumber(spec.index)
  if index == nil then return false end

  if spec.type == 'prop' then
    ClearPedProp(ped, index)
    SetPedPropIndex(ped, index, drawable, texture, true)
    return GetPedPropIndex(ped, index) == drawable
      and GetPedPropTextureIndex(ped, index) == texture
  end

  SetPedComponentVariation(ped, index, drawable, texture, 0)
  return GetPedDrawableVariation(ped, index) == drawable
    and GetPedTextureVariation(ped, index) == texture
end

local function captureTargetSpec(payload)
  local category = tostring(payload and payload.category or ''):lower()
  local cat = categories[category]
  if not cat then return nil end
  return {
    type = cat.type,
    index = cat.index,
    drawable = math.floor(tonumber(payload.drawableId or payload.drawable) or -1),
    texture = math.max(0, math.floor(tonumber(payload.textureId or payload.texture or 0) or 0)),
  }
end

local function readCaptureTargetSpec(ped, spec)
  if not ped or ped == 0 or not DoesEntityExist(ped) or type(spec) ~= 'table' then
    return { drawable = -999, texture = -999, matches = false }
  end

  local drawable, texture
  if spec.type == 'prop' then
    drawable = GetPedPropIndex(ped, spec.index)
    texture = GetPedPropTextureIndex(ped, spec.index)
  else
    drawable = GetPedDrawableVariation(ped, spec.index)
    texture = GetPedTextureVariation(ped, spec.index)
  end

  return {
    drawable = drawable,
    texture = texture,
    matches = drawable == spec.drawable and texture == spec.texture,
  }
end

local function emitCaptureDiagnostic(session, ped)
  local spec = session and session.itemReassert or nil
  local actual = readCaptureTargetSpec(ped, spec)
  local model = ped and DoesEntityExist(ped) and GetEntityModel(ped) or 0
  local actualGender = model == GetHashKey('mp_f_freemode_01') and 'female'
    or (model == GetHashKey('mp_m_freemode_01') and 'male' or 'other')
  local headDrawable = ped and DoesEntityExist(ped) and GetPedDrawableVariation(ped, 0) or -999
  local headTexture = ped and DoesEntityExist(ped) and GetPedTextureVariation(ped, 0) or -999
  local captureGender = normalizeCaptureGender(session and session.captureGender) or actualGender

  local diagnostic = {
    category = session and session.category or 'unknown',
    expectedGender = captureGender,
    actualGender = actualGender,
    modelHash = model,
    targetType = spec and spec.type or 'unknown',
    targetIndex = spec and spec.index or -1,
    expectedDrawable = spec and spec.drawable or -1,
    expectedTexture = spec and spec.texture or -1,
    actualDrawable = actual.drawable,
    actualTexture = actual.texture,
    itemAttached = actual.matches == true,
    headDrawable = headDrawable,
    headTexture = headTexture,
    isolationMode = session and session.nativeSinglePass and 'native_ghost_single' or 'legacy',
    emptyHeadAccepted = session and session.emptyHeadAccepted == true,
  }

  print(('^3[nv_cloth] CAPTURE DEBUG cat=%s gender expected=%s actual=%s model=%s '
    .. 'item=%s[%s] expected=%s/%s actual=%s/%s attached=%s '
    .. 'head=%s/%s isolation=%s emptyHead=%s^7'):format(
      tostring(diagnostic.category), tostring(diagnostic.expectedGender), tostring(diagnostic.actualGender),
      tostring(diagnostic.modelHash), tostring(diagnostic.targetType), tostring(diagnostic.targetIndex),
      tostring(diagnostic.expectedDrawable), tostring(diagnostic.expectedTexture),
      tostring(diagnostic.actualDrawable), tostring(diagnostic.actualTexture),
      tostring(diagnostic.itemAttached), tostring(diagnostic.headDrawable), tostring(diagnostic.headTexture),
      tostring(diagnostic.isolationMode), tostring(diagnostic.emptyHeadAccepted)))
  SendNUIMessage({ type = 'captureDiagnostic', diagnostic = diagnostic })
end

-- Perform the actual screenshot + restore for a prepared capture session, then
-- hand the image to the NUI processor. Shared by auto and manual capture.
local function runScreenshotForSession(session)
  local playerPed = session.playerPed
  local captureFinished = false

  SendNUIMessage({ type = 'prepareIconCapture', value = true })
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)

  applyCleanCaptureLightingOnce()

  local waitBeforeScreenshot = tonumber(session.waitBeforeScreenshot) or 900
  if waitBeforeScreenshot < 250 then waitBeforeScreenshot = 250 end
  Wait(waitBeforeScreenshot)


  -- Re-apply the exact target immediately before the screenshot. Retry briefly for
  -- streamed props while leaving every unrelated component empty.
  local targetReady = session.itemReassert == nil
  if session.itemReassert and DoesEntityExist(playerPed) then
    for attempt = 1, 4 do
      if applyCaptureTargetSpec(playerPed, session.itemReassert) then
        targetReady = true
        break
      end
      Wait(75)
    end
    Wait(75)
  end

  -- Native readback proves whether the requested prop/component attached and that
  -- the client accepted the empty head drawable before the single screenshot.
  emitCaptureDiagnostic(session, playerPed)

  local function finishCapture(imageData, failureReason)
    if captureFinished then return end
    captureFinished = true
    activeCaptureSession = nil
    stopCaptureAnimationLock(session)
    stopCleanCaptureLighting()
    ClearTimecycleModifier()

    -- If we captured on a clean throwaway ped, delete it and restore the real
    -- player's visibility. Point all restore logic back at the real player.
    if session.captureIsCleanPed then
      if session.cleanPed and DoesEntityExist(session.cleanPed) then
        DeleteEntity(session.cleanPed)
      end
      local realPed = session.realPlayerPed or PlayerPedId()
      if DoesEntityExist(realPed) then
        SetEntityVisible(realPed, session.originalVisible ~= false, false)
        NetworkSetEntityInvisibleToNetwork(realPed, false)
      end
      playerPed = realPed
      session.playerPed = realPed
      print('[nv_cloth] clean capture ped deleted, real player restored')
    end

    -- Restore the original model first if we forced freemode for a head prop.
    if session.originalModel then
      RequestModel(session.originalModel)
      local endAt = GetGameTimer() + 3000
      while not HasModelLoaded(session.originalModel) and GetGameTimer() < endAt do Wait(0) end
      if HasModelLoaded(session.originalModel) then
        SetPlayerModel(PlayerId(), session.originalModel)
        SetModelAsNoLongerNeeded(session.originalModel)
        playerPed = PlayerPedId()
        session.playerPed = playerPed
      end
    end

    if not session.captureIsCleanPed then
      restorePedAppearance(playerPed, session.appearanceSnapshot)
    end
    restoreRealPedAfterCapture(playerPed, session.originalCoords, session.originalHeading,
      session.originalVisible, session.originalAlpha, session.originalFrozen,
      session.originalInvincible, session.originalCanRagdoll)

    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'prepareIconCapture', value = false })

    if SetAdminCaptureBackdropMode then
      SetAdminCaptureBackdropMode('none', nil)
    end

    if RestoreAdminCategoryPreview or CreateSkinCam then
      CreateThread(function()
        Wait(50)
        if RestoreAdminCategoryPreview then
          RestoreAdminCategoryPreview(session.category, true)
        else
          CreateSkinCam('body')
        end
      end)
    end

    if failureReason then
      SendNUIMessage({ type = 'iconCaptureResult', success = false, error = tostring(failureReason) })
      pendingIconCapture = nil
      return
    end
    if not imageData or imageData == '' then
      SendNUIMessage({ type = 'iconCaptureResult', success = false, error = 'screenshot_failed' })
      pendingIconCapture = nil
      return
    end
    SendNUIMessage({
      type = 'processIconImage',
      image = imageData,
      payload = pendingIconCapture,
    })
  end

  -- screenshot-basic callbacks can be lost if the resource/client is interrupted.
  -- Restore the player instead of leaving them hidden forever.
  CreateThread(function()
    Wait(45000)
    if not captureFinished then finishCapture(nil, 'screenshot_timeout') end
  end)

  -- Never save a screenshot if the native readback says GTA did not attach the
  -- requested drawable/texture. The NUI batch runner will retry this job.
  if not targetReady then
    finishCapture(nil, 'target_unloaded')
    return
  end
  if session.isolationFailure then
    finishCapture(nil, session.isolationFailure)
    return
  end

  -- True single-pass isolation: the native ghost already contains only the target
  -- item, so take exactly one screenshot and proceed directly to chroma removal.
  exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(imageData)
    print(('[nv_cloth] single-pass capture complete cat=%s image=%s'):format(
      tostring(session.category), tostring(imageData and #imageData or 0)))
    finishCapture(imageData)
  end)
end

-- Prepare the ped/camera/backdrop for a capture. Returns a session table with the
-- data needed to shoot and restore. Does NOT take the screenshot.
local function prepareCaptureSession(payload)
  local playerPed = PlayerPedId()
  local realPlayerPed = playerPed
  local appearanceSnapshot = snapshotPedAppearance(realPlayerPed)

  local originalCoords = GetEntityCoords(playerPed)
  local originalHeading = GetEntityHeading(playerPed)
  local originalVisible = IsEntityVisible(playerPed)
  local originalAlpha = GetEntityAlpha(playerPed)
  local originalInvincible = GetPlayerInvincible(PlayerId()) == true
  local originalCanRagdoll = true
  if type(CanPedRagdoll) == 'function' then
    local ok, value = pcall(CanPedRagdoll, playerPed)
    if ok then originalCanRagdoll = value == true end
  end

  local originalFrozen = nil
  if type(IsEntityPositionFrozen) == 'function' then
    local ok, frozen = pcall(IsEntityPositionFrozen, playerPed)
    if ok then originalFrozen = frozen == true end
  end

  local studioCoords = Config.AdminStudio and Config.AdminStudio.StudioCoords or nil
  local captureCoords = studioCoords and vec3(studioCoords.x, studioCoords.y, studioCoords.z) or originalCoords
  local baseHeading = (studioCoords and studioCoords.w) or originalHeading

  local category = tostring(payload.category or ''):lower()
  local angleMode = tostring(payload.captureAngle or 'front'):lower()
  local categoryPreset = getCapturePreset(category)
  -- Every category uses a fresh freemode capture ped. This makes male/female
  -- enumeration deterministic and guarantees that stripping/restoring clothing
  -- can never mutate the real player's model or appearance.
  local captureIsCleanPed = false
  local originalModel = nil
  local captureGender = normalizeCaptureGender(payload.gender) or getCurrentGender()
  local wantModel = captureGender == 'female' and 'mp_f_freemode_01' or 'mp_m_freemode_01'
  local wantHash = GetHashKey(wantModel)

  RequestModel(wantHash)
  local endAt = GetGameTimer() + 7000
  while not HasModelLoaded(wantHash) and GetGameTimer() < endAt do Wait(0) end
  if not HasModelLoaded(wantHash) then
    return nil, 'capture_model_load_failed'
  end

  local cleanPed = CreatePed(4, wantHash, captureCoords.x, captureCoords.y,
    captureCoords.z, baseHeading, false, true)
  SetModelAsNoLongerNeeded(wantHash)
  if not cleanPed or cleanPed == 0 or not DoesEntityExist(cleanPed) then
    return nil, 'capture_ped_create_failed'
  end

  SetEntityAsMissionEntity(cleanPed, true, true)
  SetPedDefaultComponentVariation(cleanPed)
  SetEntityInvincible(cleanPed, true)
  FreezeEntityPosition(cleanPed, true)
  SetBlockingOfNonTemporaryEvents(cleanPed, true)
  SetPedCanRagdoll(cleanPed, false)
  SetEntityCollision(cleanPed, false, false)
  SetEntityAlpha(cleanPed, 255, false)
  ClearAllPedProps(cleanPed)

  SetEntityVisible(realPlayerPed, false, false)
  NetworkSetEntityInvisibleToNetwork(realPlayerPed, true)
  FreezeEntityPosition(realPlayerPed, true)
  SetEntityVelocity(realPlayerPed, 0.0, 0.0, 0.0)
  captureIsCleanPed = true
  playerPed = cleanPed
  print(('[nv_cloth] isolated capture ped ready: %s / %s'):format(captureGender, category))

  -- Start from the remembered, DB-saved, or DOCX default composition. The optional
  -- live editor therefore opens on the same framing an automatic capture would use.
  local remembered = RememberedPose[category]
  if not remembered and type(GetSavedPose) == 'function' then
    remembered = GetSavedPose(category)
  end

  local pedHeading
  if remembered and remembered.heading and payload.captureAngleOverride ~= true then
    pedHeading = remembered.heading % 360.0
  elseif angleMode == 'current' then
    pedHeading = originalHeading
  else
    pedHeading = (baseHeading + resolveViewOffset(payload, categoryPreset)) % 360.0
  end

  local zOffset = tonumber(payload.zOffset) or 0.0

  -- Extra vertical lift for the ped, e.g. raise shoes off the ground so they are
  -- not clipping into the floor. Config-driven per category + optional per-capture.
  -- A remembered manual pose overrides with the exact lift you set.
  local groundLift
  if remembered and remembered.lift then
    groundLift = tonumber(remembered.lift) or 0.0
  else
    groundLift = tonumber(payload.groundLift)
    if not groundLift then
      local lifts = (Config.IconCapture and Config.IconCapture.groundLift) or {}
      groundLift = tonumber(lifts[category]) or 0.0
    end
  end

  print(('[nv_cloth] Capture payload category=%s drawable=%s texture=%s gender=%s bg=%s imageFile=%s'):format(
    tostring(payload.category), tostring(payload.drawableId), tostring(payload.textureId),
    tostring(payload.gender), tostring(payload.captureBackground), tostring(payload.fileName)))

  startCleanCaptureLighting(payload.lighting)

  -- Ground lift moves the ped relative to the studio floor. zOffset is a CAMERA
  -- aim adjustment and is intentionally not added here; moving both ped and camera
  -- together made the admin Z Offset control have no visible effect.
  local baseZ = captureCoords.z + groundLift
  SetEntityCoordsNoOffset(playerPed, captureCoords.x, captureCoords.y, baseZ, false, false, false)
  SetEntityHeading(playerPed, pedHeading)
  FreezeEntityPosition(playerPed, true)
  SetPedAoBlobRendering(playerPed, false)

  -- Make the ped a completely still statue for the shot: no idle sway, no
  -- breathing, no hand/finger movement, no ragdoll. Applies to auto AND manual.
  SetEntityInvincible(playerPed, true)
  SetPedCanRagdoll(playerPed, false)
  ClearPedTasksImmediately(playerPed)
  FreezeEntityPosition(playerPed, true)

  -- The capture path is intentionally hard-wired to one native ghost pass.
  -- Configuration cannot silently reactivate the removed subtraction pipeline.
  local emptyHeadAccepted = applyNativeIsolatedCapture(playerPed, payload)

  local itemReassert = captureTargetSpec(payload)
  if itemReassert then
    for attempt = 1, 4 do
      if applyCaptureTargetSpec(playerPed, itemReassert) then break end
      Wait(75)
    end
  end

  -- Diagnostic: log what the ped looks like after stripping, so accessory/body
  -- issues are visible in F8. cat 11 = top, 8 = undershirt; both should be -1 for
  -- a clean item/prop shot. Prop index shows if the accessory actually attached.
  do
    local c = tostring(category)
    print(('[nv_cloth] After ghost strip cat=%s top(11)=%d under(8)=%d legs(4)=%d feet(6)=%d'):format(
      c,
      GetPedDrawableVariation(playerPed, 11),
      GetPedDrawableVariation(playerPed, 8),
      GetPedDrawableVariation(playerPed, 4),
      GetPedDrawableVariation(playerPed, 6)))
    local catDef = categories[c]
    if catDef and catDef.type == 'prop' then
      print(('[nv_cloth]   prop %d drawable=%d (payload draw=%s tex=%s)'):format(
        catDef.index, GetPedPropIndex(playerPed, catDef.index),
        tostring(payload.drawableId), tostring(payload.textureId)))
    end
  end

  local isolationFailure = nil
  if not emptyHeadAccepted then
    -- Fail closed. There is no reset-flag, streamed-head, subtraction, or second-pass
    -- fallback because those can hide the selected prop or reintroduce body parts.
    isolationFailure = 'allowEmptyHeadDrawable_unavailable'
    print(('[nv_cloth] native single-pass refused: empty head unavailable for %s'):format(category))
  end

  local camCfg = (GetCaptureCameraConfig and GetCaptureCameraConfig(category))
    or (Config.IconCapture and Config.IconCapture.captureCameras and Config.IconCapture.captureCameras[category])
    or nil

  if camCfg and CreateSkinCamCaptureConfig then
    DestroySkinCam()
    Wait(50)
    -- The ped lift affects its floor position; zOffset affects only the camera aim.
    -- This makes the admin Z Offset control and each category preset deterministic.
    CreateSkinCamCaptureConfig(camCfg, baseHeading, zOffset, playerPed)
  else
    local captureCamera = (payload.crop and payload.crop.camera) or 'body'
    if captureCamera ~= 'body' and captureCamera ~= 'head' and captureCamera ~= 'face' and captureCamera ~= 'feet' then
      captureCamera = 'body'
    end
    if CreateSkinCamCapture then
      DestroySkinCam()
      Wait(50)
      CreateSkinCamCapture(captureCamera, baseHeading, zOffset, playerPed)
    elseif CreateSkinCam then
      DestroySkinCam()
      Wait(50)
      CreateSkinCam(captureCamera)
    end
  end

  -- Replay the remembered manual camera (zoom/orbit/height) so other textures of
  -- this item frame identically to the one you posed by hand.
  if remembered and remembered.cam and type(ApplyLiveCaptureCamParams) == 'function' then
    ApplyLiveCaptureCamParams(remembered.cam, playerPed)
  end

  if EnsureAdminStudioGreenScreen then
    EnsureAdminStudioGreenScreen()
  end

  if SetAdminCaptureBackdropMode then
    local bgMode = tostring(payload.captureBackground or 'green'):lower()
    if bgMode == 'green' then
      SetAdminCaptureBackdropMode('green')
    else
      SetAdminCaptureBackdropMode(bgMode, baseHeading)
    end
  end

  return {
    playerPed = playerPed,
    -- The real player ped, kept separately so we can restore/delete correctly even
    -- when playerPed above has been redirected to a clean throwaway capture ped.
    realPlayerPed = realPlayerPed,
    captureIsCleanPed = captureIsCleanPed,
    cleanPed = captureIsCleanPed and playerPed or nil,
    appearanceSnapshot = appearanceSnapshot,
    originalCoords = originalCoords,
    originalHeading = originalHeading,
    originalVisible = originalVisible,
    originalAlpha = originalAlpha,
    originalFrozen = originalFrozen,
    originalInvincible = originalInvincible,
    originalCanRagdoll = originalCanRagdoll,
    waitBeforeScreenshot = tonumber(payload.lighting and payload.lighting.waitBeforeScreenshot) or 900,
    category = category,
    captureGender = captureGender,
    itemReassert = itemReassert,
    nativeIsolated = true,
    nativeSinglePass = true,
    emptyHeadAccepted = emptyHeadAccepted,
    isolationFailure = isolationFailure,
    originalModel = originalModel,
    baseX = captureCoords.x, baseY = captureCoords.y, baseZ = baseZ,
    initialGroundLift = groundLift,
    liftOffset = 0.0,
    moveX = 0.0,
    moveY = 0.0,
  }
end

-- Build a complete native capture queue for both freemode models. Counts are read
-- from disposable male/female peds, so the result does not depend on the admin's
-- current character. Each drawable is expanded to every valid texture.
RegisterNUICallback('enumerateCaptureJobs', function(_, cb)
  if not (NvCloth_IsAdminShop and NvCloth_IsAdminShop()) then
    cb({ success = false, error = 'not_admin_mode' })
    return
  end

  CreateThread(function()
    local jobs = {}
    local captureCfg = Config.IconCapture or {}
    local categoryOrder = captureCfg.captureCategories or {
      'torso', 'tshirt', 'pants', 'shoes', 'hat', 'glasses',
      'earrings', 'chains', 'bags', 'watches', 'bracelets', 'armor',
    }
    local maxJobs = 50000

    for _, gender in ipairs({ 'male', 'female' }) do
      local modelName = gender == 'female' and 'mp_f_freemode_01' or 'mp_m_freemode_01'
      local model = GetHashKey(modelName)
      RequestModel(model)
      local timeout = GetGameTimer() + 7000
      while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
      if not HasModelLoaded(model) then
        cb({ success = false, error = gender .. '_model_load_failed' })
        return
      end

      local origin = Config.AdminStudio and Config.AdminStudio.StudioCoords or GetEntityCoords(PlayerPedId())
      local ped = CreatePed(4, model, origin.x, origin.y, origin.z - 10.0, 0.0, false, true)
      SetModelAsNoLongerNeeded(model)
      if not ped or ped == 0 or not DoesEntityExist(ped) then
        cb({ success = false, error = gender .. '_enumeration_ped_failed' })
        return
      end

      SetEntityAsMissionEntity(ped, true, true)
      SetEntityVisible(ped, false, false)
      SetEntityCollision(ped, false, false)
      FreezeEntityPosition(ped, true)
      SetPedDefaultComponentVariation(ped)

      for _, category in ipairs(categoryOrder) do
        local cat = categories[category]
        if cat and category ~= 'arms' then
          local drawCount = cat.type == 'prop'
            and GetNumberOfPedPropDrawableVariations(ped, cat.index)
            or GetNumberOfPedDrawableVariations(ped, cat.index)
          drawCount = math.max(0, math.floor(tonumber(drawCount) or 0))

          for drawable = 0, drawCount - 1 do
            local textureCount = cat.type == 'prop'
              and GetNumberOfPedPropTextureVariations(ped, cat.index, drawable)
              or GetNumberOfPedTextureVariations(ped, cat.index, drawable)
            textureCount = math.max(1, math.floor(tonumber(textureCount) or 1))

            for texture = 0, textureCount - 1 do
              jobs[#jobs + 1] = {
                gender = gender,
                category = category,
                componentType = cat.type,
                componentIndex = cat.index,
                drawableId = drawable,
                textureId = texture,
                drawable = drawable,
                texture = texture,
                label = ('%s %s/%s'):format(category, drawable, texture),
                destination = 'hidden',
                sharedGender = false,
              }
              if #jobs >= maxJobs then break end
            end
            if #jobs >= maxJobs then break end
          end
        end
        if #jobs >= maxJobs then break end
      end

      DeleteEntity(ped)
      if #jobs >= maxJobs then break end
      Wait(100)
    end

    print(('[nv_cloth] enumerated %s male/female drawable+texture capture jobs'):format(#jobs))
    cb({ success = true, jobs = jobs, count = #jobs, truncated = #jobs >= maxJobs })
  end)
end)

RegisterNUICallback('captureInventoryIcon', function(data, cb)
  if not (NvCloth_IsAdminShop and NvCloth_IsAdminShop()) then
    cb({ success = false, error = 'not_admin_mode' })
    return
  end

  if not Config.IconCapture or Config.IconCapture.enabled == false then
    cb({ success = false, error = 'icon_capture_disabled' })
    return
  end

  if GetResourceState('screenshot-basic') ~= 'started' then
    cb({ success = false, error = 'screenshot-basic_not_started' })
    return
  end

  if activeCaptureSession or manualSession then
    cb({ success = false, error = 'capture_busy' })
    return
  end

  local payload, err = buildIconCapturePayload(data)
  if not payload then
    cb({ success = false, error = err or 'invalid_capture_payload' })
    return
  end

  pendingIconCapture = payload

  local category = tostring(payload.category or ''):lower()
  local wantManual = (data and (data.manual == true or data.manualPose == true))
    and MANUAL_CAPABLE[category] == true

  local session, sessionErr = prepareCaptureSession(payload)
  if not session then
    pendingIconCapture = nil
    cb({ success = false, error = sessionErr or 'capture_prepare_failed' })
    return
  end
  activeCaptureSession = session
  startCaptureAnimationLock(session)

  if wantManual then
    -- Manual pose mode: don't shoot yet. Hand rotation control to the admin and
    -- wait for confirmManualShot / cancelManualShot from the NUI.
    manualSession = session
    manualSession.poseHoldActive = true

    -- Pose-hold thread: keep the ped FROZEN (rigid, no physics deform) at its base
    -- position + lift. Only re-place it when the lift value actually changes, so the
    -- ped doesn't drift into an animation/rest pose (which was warping the shoe).
    CreateThread(function()
      local ped = manualSession and manualSession.playerPed
      if ped and DoesEntityExist(ped) then
        SetEntityInvincible(ped, true)
        SetPedCanRagdoll(ped, false)
        ClearPedTasksImmediately(ped)
        local bx = (tonumber(manualSession.baseX) or GetEntityCoords(ped).x) + (tonumber(manualSession.moveX) or 0.0)
        local by = (tonumber(manualSession.baseY) or GetEntityCoords(ped).y) + (tonumber(manualSession.moveY) or 0.0)
        local bz = (tonumber(manualSession.baseZ) or GetEntityCoords(ped).z) + (tonumber(manualSession.liftOffset) or 0.0)
        SetEntityCoordsNoOffset(ped, bx, by, bz, false, false, false)
        FreezeEntityPosition(ped, true) -- rigid; no deform
      end
      local lastLift = tonumber(manualSession and manualSession.liftOffset) or 0.0
      local lastMoveX = tonumber(manualSession and manualSession.moveX) or 0.0
      local lastMoveY = tonumber(manualSession and manualSession.moveY) or 0.0
      while manualSession and manualSession.poseHoldActive and ped and DoesEntityExist(ped) do
        local curLift = tonumber(manualSession.liftOffset) or 0.0
        local curMoveX = tonumber(manualSession.moveX) or 0.0
        local curMoveY = tonumber(manualSession.moveY) or 0.0
        if curLift ~= lastLift or curMoveX ~= lastMoveX or curMoveY ~= lastMoveY then
          -- Lift changed: unfreeze briefly, move, refreeze. Only happens on button
          -- press, so the ped stays rigid (undeformed) the rest of the time.
          local bx = (tonumber(manualSession.baseX) or GetEntityCoords(ped).x) + curMoveX
          local by = (tonumber(manualSession.baseY) or GetEntityCoords(ped).y) + curMoveY
          local bz = (tonumber(manualSession.baseZ) or GetEntityCoords(ped).z) + curLift
          FreezeEntityPosition(ped, false)
          SetEntityCoordsNoOffset(ped, bx, by, bz, false, false, false)
          FreezeEntityPosition(ped, true)
          lastLift = curLift
          lastMoveX = curMoveX
          lastMoveY = curMoveY
        end
        Wait(30)
      end
    end)

    -- Keep the NUI visible AND let mouse/keys through so the admin can drag-rotate
    -- the ped and click the on-screen Confirm/Cancel controls.
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    SendNUIMessage({
      type = 'manualPoseStart',
      category = category,
      heading = GetEntityHeading(session.playerPed),
      camera = type(GetLiveCaptureCamParams) == 'function' and GetLiveCaptureCamParams(session.playerPed) or nil,
    })

    cb({ success = true, manual = true, pending = true })
    return
  end

  -- Auto mode: shoot immediately.
  CreateThread(function()
    runScreenshotForSession(session)
  end)

  cb({ success = true, pending = true })
end)

-- Rotate the posed ped during manual capture. delta is degrees (from drag or a
-- button); absolute sets an exact heading (from a slider).
RegisterNUICallback('manualPoseRotate', function(data, cb)
  if not manualSession then cb({ success = false, error = 'no_manual_session' }); return end
  local ped = manualSession.playerPed
  if not ped or not DoesEntityExist(ped) then cb({ success = false }); return end

  data = type(data) == 'table' and data or {}
  if data.absolute ~= nil then
    SetEntityHeading(ped, (tonumber(data.absolute) or 0.0) % 360.0)
  else
    local delta = tonumber(data.delta) or 0.0
    if delta > 45.0 then delta = 45.0 end
    if delta < -45.0 then delta = -45.0 end
    SetEntityHeading(ped, (GetEntityHeading(ped) + delta) % 360.0)
  end
  cb({ success = true, heading = GetEntityHeading(ped) })
end)

-- Nudge the posed ped vertically during manual capture (e.g. lift shoes off the
-- floor). delta in metres. The ped is frozen, so SetEntityCoords alone won't stick
-- reliably — unfreeze, move, refreeze. The camera target is raised by the same
-- amount so the item stays centered in frame while clearing the ground.
RegisterNUICallback('manualPoseLift', function(data, cb)
  if not manualSession then cb({ success = false, error = 'no_manual_session' }); return end
  local ped = manualSession.playerPed
  if not ped or not DoesEntityExist(ped) then cb({ success = false }); return end

  data = type(data) == 'table' and data or {}
  local delta = tonumber(data.delta) or 0.0
  if delta > 1.0 then delta = 1.0 end
  if delta < -1.0 then delta = -1.0 end

  manualSession.liftOffset = (tonumber(manualSession.liftOffset) or 0.0) + delta
  -- The pose-hold thread re-sets the ped to baseZ + liftOffset every frame (without
  -- freezing), so the new lift takes effect on the very next tick — no manual
  -- placement or freeze toggling needed here.
  print(('[nv_cloth] manual lift delta=%.3f total=%.3f'):format(delta, manualSession.liftOffset))
  cb({ success = true, lift = manualSession.liftOffset })
end)

-- Move the posed ped while leaving the camera fixed. Side shifts across the
-- camera plane; depth moves toward/away. The saved camera-target offset then
-- reproduces this exact composition for future captures in the category.
RegisterNUICallback('manualPoseMove', function(data, cb)
  if not manualSession then cb({ success = false, error = 'no_manual_session' }); return end
  local ped = manualSession.playerPed
  if not ped or not DoesEntityExist(ped) then cb({ success = false }); return end
  data = type(data) == 'table' and data or {}
  local axis = tostring(data.axis or 'side')
  local amount = math.max(-0.5, math.min(0.5, tonumber(data.amount) or 0.0))
  local cam = type(GetLiveCaptureCamParams) == 'function' and GetLiveCaptureCamParams(ped) or nil
  local heading = tonumber(cam and cam.heading) or GetEntityHeading(ped)
  local rad = math.rad(heading)
  local dx, dy = 0.0, 0.0
  if axis == 'depth' then
    dx = math.sin(rad) * amount
    dy = -math.cos(rad) * amount
  else
    dx = math.cos(rad) * amount
    dy = math.sin(rad) * amount
  end
  manualSession.moveX = (tonumber(manualSession.moveX) or 0.0) + dx
  manualSession.moveY = (tonumber(manualSession.moveY) or 0.0) + dy
  local bx = (tonumber(manualSession.baseX) or GetEntityCoords(ped).x) + manualSession.moveX
  local by = (tonumber(manualSession.baseY) or GetEntityCoords(ped).y) + manualSession.moveY
  local bz = (tonumber(manualSession.baseZ) or GetEntityCoords(ped).z)
    + (tonumber(manualSession.liftOffset) or 0.0)
  FreezeEntityPosition(ped, false)
  SetEntityCoordsNoOffset(ped, bx, by, bz, false, false, false)
  FreezeEntityPosition(ped, true)
  cb({ success = true, moveX = manualSession.moveX, moveY = manualSession.moveY })
end)

-- Move/zoom the capture camera during manual pose (WASD + zoom keys from NUI).
-- action: 'zoom' | 'orbit' | 'height' | 'fov'; amount in the action's units.
RegisterNUICallback('manualPoseCam', function(data, cb)
  if not manualSession then cb({ success = false, error = 'no_manual_session' }); return end
  data = type(data) == 'table' and data or {}
  local action = tostring(data.action or '')
  local amount = tonumber(data.amount) or 0.0
  if type(AdjustLiveCaptureCam) == 'function' then
    AdjustLiveCaptureCam(action, amount)
  end
  local ped = manualSession.playerPed
  local params = type(GetLiveCaptureCamParams) == 'function' and GetLiveCaptureCamParams(ped) or nil
  cb({ success = true, camera = params })
end)

-- Admin confirmed the angle: take the screenshot now.
RegisterNUICallback('confirmManualShot', function(_, cb)
  if not manualSession then cb({ success = false, error = 'no_manual_session' }); return end
  local session = manualSession
  session.poseHoldActive = false
  manualSession = nil
  activeCaptureSession = session

  -- Snapshot the pose so it can be replayed for the other textures of this item.
  local ped = session.playerPed
  local cat = tostring(session.category or ''):lower()
  if ped and DoesEntityExist(ped) and cat ~= '' then
    local heading = GetEntityHeading(ped)
    local lift = (tonumber(session.initialGroundLift) or 0.0)
      + (tonumber(session.liftOffset) or 0.0)
    local camParams = (type(GetLiveCaptureCamParams) == 'function') and GetLiveCaptureCamParams(ped) or nil
    RememberedPose[cat] = { heading = heading, lift = lift, cam = camParams }

    -- Auto-save to the database so this camera + pose is reused for every future
    -- capture of this category, across restarts and for all admins.
    local payload = { category = cat, poseHeading = heading, poseLift = lift }
    if type(camParams) == 'table' then
      payload.dist = camParams.dist
      payload.z = camParams.relZ or camParams.z
      payload.fov = camParams.fov
      payload.camRelZ = camParams.relZ or camParams.z
      payload.camHeading = camParams.heading
      payload.camTargetX = camParams.targetOffsetX
      payload.camTargetY = camParams.targetOffsetY
    end
    if payload.dist and payload.z and payload.fov then
      TriggerServerEvent('nvCloth:server:saveCaptureCamera', payload)
      print(('[nv_cloth] auto-saved camera+pose for %s (heading=%.1f lift=%.2f)'):format(cat, heading, lift))
    end
  end

  CreateThread(function()
    runScreenshotForSession(session)
  end)
  cb({ success = true })
end)

-- Admin cancelled: restore the ped and abort without saving.
RegisterNUICallback('cancelManualShot', function(_, cb)
  if not manualSession then cb({ success = true }); return end
  local session = manualSession
  session.poseHoldActive = false
  manualSession = nil
  activeCaptureSession = nil

  stopCaptureAnimationLock(session)
  stopCleanCaptureLighting()
  ClearTimecycleModifier()

  local restorePed = session.playerPed
  if session.captureIsCleanPed then
    if session.cleanPed and DoesEntityExist(session.cleanPed) then DeleteEntity(session.cleanPed) end
    restorePed = session.realPlayerPed or PlayerPedId()
    if DoesEntityExist(restorePed) then
      SetEntityVisible(restorePed, true, false)
      NetworkSetEntityInvisibleToNetwork(restorePed, false)
    end
    session.playerPed = restorePed
  end

  if not session.captureIsCleanPed then
    restorePedAppearance(restorePed, session.appearanceSnapshot)
  end
  restoreRealPedAfterCapture(restorePed, session.originalCoords, session.originalHeading,
    session.originalVisible, session.originalAlpha, session.originalFrozen,
    session.originalInvincible, session.originalCanRagdoll)

  if SetAdminCaptureBackdropMode then
    SetAdminCaptureBackdropMode('none', nil)
  end
  if RestoreAdminCategoryPreview or CreateSkinCam then
    CreateThread(function()
      Wait(50)
      if RestoreAdminCategoryPreview then
        RestoreAdminCategoryPreview(session.category, true)
      else
        CreateSkinCam('body')
      end
    end)
  end

  SendNUIMessage({ type = 'iconCaptureResult', success = false, error = 'manual_cancelled' })
  pendingIconCapture = nil
  cb({ success = true })
end)

RegisterNUICallback('setCaptureBackdrop', function(data, cb)
  local mode = type(data) == 'table' and data.mode or 'none'
  mode = tostring(mode or 'none'):lower()

  if mode ~= 'none' and EnsureAdminStudioGreenScreen then
    EnsureAdminStudioGreenScreen()
  end

  if SetAdminCaptureBackdropMode then
    SetAdminCaptureBackdropMode(mode)
  end

  cb({ success = true })
end)

RegisterNUICallback('iconProcessed', function(data, cb)
  data = type(data) == 'table' and data or {}

  local payload = type(data.payload) == 'table' and data.payload or pendingIconCapture

  if not payload then
    cb({ success = false, error = 'no_pending_capture' })
    return
  end

  payload.imageBase64 = data.imageBase64 or data.base64
  payload.dataUrl = data.dataUrl
  payload.webpBase64 = data.webpBase64
  payload.webpDataUrl = data.webpDataUrl

  if not payload.imageBase64 or payload.imageBase64 == '' then
    pendingIconCapture = nil
    cb({ success = false, error = 'empty_processed_image' })
    return
  end

  print(('[nv_cloth] Sending inventory icon to server: %s (%s bytes b64)'):format(
    tostring(payload.fileName),
    tostring(#tostring(payload.imageBase64 or ''))
  ))

  -- Base64 PNG data can be too large for a normal TriggerServerEvent.
  -- Use latent event so FiveM streams the payload instead of silently dropping it.
  TriggerLatentServerEvent('nvCloth:server:saveInventoryIcon', 200000, payload)

  pendingIconCapture = nil
  cb({ success = true })
end)

RegisterNetEvent('nvCloth:client:inventoryIconSaved', function(entry)
  SendNUIMessage({
    type = 'iconCaptureResult',
    success = true,
    entry = entry or {},
  })
end)

RegisterNetEvent('nvCloth:client:inventoryIconSaveFailed', function(reason)
  SendNUIMessage({
    type = 'iconCaptureResult',
    success = false,
    error = tostring(reason or 'save_failed'),
  })
end)

-- Last-resort cleanup for restarts/stops during either screenshot pass.
AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  local session = activeCaptureSession or manualSession
  if not session then
    if captureAnimationClockLocked then stopCaptureAnimationLock(nil) end
    return
  end

  stopCaptureAnimationLock(session)
  stopCleanCaptureLighting()
  if session.cleanPed and DoesEntityExist(session.cleanPed) then DeleteEntity(session.cleanPed) end
  local realPed = session.realPlayerPed or PlayerPedId()
  if realPed and DoesEntityExist(realPed) then
    SetEntityVisible(realPed, session.originalVisible ~= false, false)
    NetworkSetEntityInvisibleToNetwork(realPed, false)
    if not session.captureIsCleanPed then
      restorePedAppearance(realPed, session.appearanceSnapshot)
    end
    restoreRealPedAfterCapture(realPed, session.originalCoords, session.originalHeading,
      session.originalVisible, session.originalAlpha, session.originalFrozen,
      session.originalInvincible, session.originalCanRagdoll)
  end
  activeCaptureSession = nil
  manualSession = nil
  pendingIconCapture = nil
end)
