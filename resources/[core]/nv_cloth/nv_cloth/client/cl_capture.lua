--========================================================
-- Admin inventory icon capture
-- Captures the current live preview with screenshot-basic,
-- sends it to NUI for green-screen background removal,
-- then server saves transparent PNG to cm-items.
--
-- NO-HEAD FIX:
-- Uses SetPedResetFlag(ped, 166, true) for normal/body captures.
-- For head props (hat/glasses/earrings), do NOT use flag 166 because it hides the prop too.
-- Those use the streamed invisible head mesh instead.
--========================================================

local pendingIconCapture = nil

local noHeadCaptureActive = false
local noHeadCaptureThreadRunning = false

local function startNoHeadCaptureFlag()
  if noHeadCaptureActive then return end

  noHeadCaptureActive = true

  if noHeadCaptureThreadRunning then return end
  noHeadCaptureThreadRunning = true

  CreateThread(function()
    while noHeadCaptureActive do
      local ped = PlayerPedId()

      if ped and ped ~= 0 and DoesEntityExist(ped) then
        -- Flag 166 hides the player head like first-person mode.
        -- This MUST run every frame while the screenshot is being taken.
        SetPedResetFlag(ped, 166, true)
      end

      Wait(0)
    end

    noHeadCaptureThreadRunning = false
  end)
end

local function stopNoHeadCaptureFlag()
  noHeadCaptureActive = false
end

local function categoryNeedsVisibleHead(category)
  category = tostring(category or ''):lower()
  local keep = (Config.IconCapture and Config.IconCapture.keepBody and Config.IconCapture.keepBody[category]) or {}
  -- Force pure item capture for outerwear, pants and bags even if an older config still keeps body parts.
  if category == 'torso' or category == 'pants' or category == 'bags' then
    keep = {}
  end
  return keep.head == true
end

-- Props that ATTACH TO THE HEAD BONE. For these we must NOT use reset flag 166
-- (the first-person head-hide), because that flag hides everything on the head
-- bone — including the hat/glasses/mask/earrings we are trying to photograph.
-- The head MESH is still hidden via the invisible streamed head component
-- (SetPedComponentVariation 0,0,1,0), so we get "no head" but the prop stays.
local HEAD_PROP_CATEGORIES = {
  hat = true, hats = true, helmet = true,
  glasses = true, glass = true,
  earrings = true, ears = true,
  mask = true, masks = true,
}

local function categoryAttachesToHead(category)
  return HEAD_PROP_CATEGORIES[tostring(category or ''):lower()] == true
end


--========================================================
-- Clean daylight / no-shadow capture environment
--========================================================

local cleanCaptureLightingActive = false
local cleanCaptureLightingThreadRunning = false

local function safeCall(fn, ...)
  if type(fn) ~= 'function' then return end
  pcall(fn, ...)
end

local function applyCleanCaptureLightingOnce()
  local cfg = Config.IconCapture and Config.IconCapture.lighting or {}
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

local function startCleanCaptureLighting()
  local cfg = Config.IconCapture and Config.IconCapture.lighting or {}
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
end

local function getCurrentGender()
  return GetEntityModel(PlayerPedId()) == GetHashKey('mp_f_freemode_01') and 'female' or 'male'
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
  }

  local crop = {
    x = 0.10,
    y = 0.05,
    w = 0.80,
    h = 0.90,
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

local function restoreRealPedAfterCapture(playerPed, originalCoords, originalHeading, originalVisible, originalAlpha, originalFrozen)
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
end

-- Components hidden by default, with the value used to hide each one.
-- (Head [0] and hair [2] are handled separately so the head can stay invisible.)
local GHOST_HIDE = {
  [1] = 0, [3] = -1, [4] = -1, [5] = 0, [6] = -1,
  [7] = 0, [8] = -1, [9] = 0, [10] = 0, [11] = -1,
}

local function applyGhostCaptureBase(ped, payload)
  local category = tostring(payload.category or ''):lower()
  local cat = categories[category]
  if not cat then return end

  local drawable = tonumber(payload.drawableId or payload.drawable) or 0
  local texture = tonumber(payload.textureId or payload.texture or 0) or 0

  ClearPedTasksImmediately(ped)
  RemoveAllPedWeapons(ped, true)

  for i = 0, 7 do
    ClearPedProp(ped, i)
  end

  -- Supporting body parts to KEEP for this category (so items that sit on the
  -- body don't float). Config-driven: shoes keep legs, watches keep arms, etc.
  local keep = (Config.IconCapture and Config.IconCapture.keepBody and Config.IconCapture.keepBody[category]) or {}
  -- Force pure item capture for outerwear, pants and bags even if an older config still keeps body parts.
  if category == 'torso' or category == 'pants' or category == 'bags' then
    keep = {}
  end

  -- Accessory PROPS (hat, glasses, earrings, watches) attach to a bone, not to
  -- visible skin. For these we want the PROP ALONE with no body skin at all, so
  -- ignore any kept parts and hide the whole body. The bone still exists with the
  -- mesh hidden, so the prop stays attached and floats by itself.
  if cat.type == 'prop' then
    keep = {}
  end

  -- Head: invisible streamed mesh unless this category needs a real head
  -- (e.g. earrings/glasses configured with head = true).
  if keep.head == true then
    SetPedComponentVariation(ped, 0, 0, 0, 0)                       -- normal head
    SetPedComponentVariation(ped, 2, tonumber(keep.hair) or -1, 0, 0) -- hair (default bald)
  else
    SetPedComponentVariation(ped, 0, 0, 0, 0)   -- invisible streamed head mesh: stream/mp_*_freemode_01^head_000_r.ydd
    SetPedComponentVariation(ped, 2, -1, 0, 0)  -- hair hidden
  end
  SetPedHairColor(ped, 45, 15)

  -- Hide every other component, EXCEPT the target component and any kept supports.
  for idx, hideVal in pairs(GHOST_HIDE) do
    if keep[idx] ~= nil then
      SetPedComponentVariation(ped, idx, tonumber(keep[idx]) or 0, 0, 0) -- keep at neutral skin
    elseif not (cat.type == 'component' and cat.index == idx) then
      SetPedComponentVariation(ped, idx, hideVal, 0, 0)
    end
  end

  -- Apply only the selected item.
  if cat.type == 'prop' then
    ClearPedProp(ped, cat.index)
    SetPedPropIndex(ped, cat.index, drawable, texture, true)
    return
  end

  SetPedComponentVariation(ped, cat.index, drawable, texture, 0)
end

local function buildIconCapturePayload(data)
  data = type(data) == 'table' and data or {}

  local ped = PlayerPedId()
  local category = tostring(data.category or data.type or ''):lower()
  local cat = categories[category]

  if not cat then return nil, 'invalid_category' end

  local preset = getCapturePreset(category)
  local crop = getIconCaptureCrop(category)

  local drawable = tonumber(data.drawableId or data.drawable)
  if not drawable then return nil, 'invalid_drawable' end

  local gender = getCurrentGender()
  local texture = tonumber(data.textureId or data.texture or 0) or 0

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
    width = Config.IconCapture and Config.IconCapture.width or 512,
    height = Config.IconCapture and Config.IconCapture.height or 512,
    padding = crop.padding or (Config.IconCapture and Config.IconCapture.padding) or 18,
    chroma = Config.IconCapture and Config.IconCapture.chroma or nil,
    autoCrop = Config.IconCapture and Config.IconCapture.autoCrop or nil,
    lighting = Config.IconCapture and Config.IconCapture.lighting or nil,
    crop = crop,
    captureAngle = tostring(data.captureAngle or preset.view or 'front'):lower(),
    zOffset = tonumber(data.zOffset or preset.zOffset or 0.0) or 0.0,
    captureBackground = tostring(data.captureBackground or data.backgroundColor or preset.backgroundColor or 'green'):lower(),
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
  hat = true, glasses = true, earrings = true, watches = true, chains = true, shoes = true,
}

-- Active manual-capture session (nil when not posing). Holds everything needed to
-- shoot + restore once the admin confirms the angle.
local manualSession = nil

-- Remembered manual pose per category. Once you pose & shoot one texture, the
-- rest of that item's textures (and re-captures of the category) reuse the same
-- ped heading, lift and camera automatically — no re-posing each time.
local RememberedPose = {}

-- Perform the actual screenshot + restore for a prepared capture session, then
-- hand the image to the NUI processor. Shared by auto and manual capture.
local function runScreenshotForSession(session)
  local playerPed = session.playerPed

  SendNUIMessage({ type = 'prepareIconCapture', value = true })
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)

  applyCleanCaptureLightingOnce()

  -- For head-worn props (hat/glasses/earrings) the head is hidden by the streamed
  -- invisible-head file via SetPedComponentVariation(0,0,1,0). On an already-loaded
  -- ped the game can keep the cached real head, so re-assert the invisible head a
  -- few times (with the streamed model requested) right before the shot to force
  -- the override to take. This does NOT use flag 166, which would hide the prop.
  if session.headProp then
    local model = GetEntityModel(playerPed)
    RequestModel(model)
    for _ = 1, 3 do
      SetPedComponentVariation(playerPed, 0, 0, 0, 0) -- invisible streamed head mesh
      SetPedComponentVariation(playerPed, 2, -1, 0, 0) -- hair off
      Wait(60)
    end
  end

  local waitBeforeScreenshot = tonumber(session.waitBeforeScreenshot) or 900
  if waitBeforeScreenshot < 250 then waitBeforeScreenshot = 250 end
  Wait(waitBeforeScreenshot)

  -- One final re-assert immediately before the capture, in case anything reset it.
  if session.headProp and DoesEntityExist(playerPed) then
    SetPedComponentVariation(playerPed, 0, 0, 1, 0)
    SetPedComponentVariation(playerPed, 2, -1, 0, 0)
  end

  exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(imageData)
    stopNoHeadCaptureFlag()
    stopCleanCaptureLighting()
    ClearTimecycleModifier()

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

    restorePedAppearance(playerPed, session.appearanceSnapshot)
    restoreRealPedAfterCapture(playerPed, session.originalCoords, session.originalHeading,
      session.originalVisible, session.originalAlpha, session.originalFrozen)

    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'prepareIconCapture', value = false })

    if SetAdminCaptureBackdropMode then
      SetAdminCaptureBackdropMode('none', nil)
    end

    if CreateSkinCam then
      CreateThread(function()
        Wait(50)
        CreateSkinCam('body')
      end)
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
  end)
end

-- Prepare the ped/camera/backdrop for a capture. Returns a session table with the
-- data needed to shoot and restore. Does NOT take the screenshot.
local function prepareCaptureSession(payload)
  local playerPed = PlayerPedId()
  local appearanceSnapshot = snapshotPedAppearance(playerPed)

  local originalCoords = GetEntityCoords(playerPed)
  local originalHeading = GetEntityHeading(playerPed)
  local originalVisible = IsEntityVisible(playerPed)
  local originalAlpha = GetEntityAlpha(playerPed)

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

  -- Optional fallback: force the matching freemode model for head props so the
  -- streamed invisible-head file definitely applies. Off by default; only used
  -- when Config.IconCapture.forceFreemodeForHeadProps = true.
  local originalModel = nil
  local isHeadProp = categoryAttachesToHead(category) and not categoryNeedsVisibleHead(category)
  if isHeadProp and Config.IconCapture and Config.IconCapture.forceFreemodeForHeadProps == true then
    local curModel = GetEntityModel(playerPed)
    local femaleHash = GetHashKey('mp_f_freemode_01')
    local maleHash = GetHashKey('mp_m_freemode_01')
    local wantModel = (curModel == femaleHash) and 'mp_f_freemode_01' or 'mp_m_freemode_01'
    local wantHash = GetHashKey(wantModel)
    local isFreemode = (curModel == maleHash or curModel == femaleHash)
    -- Swap when on a non-freemode model (to restore after). When already freemode,
    -- a same-model SetPlayerModel forces the ped to rebuild and pick up the streamed
    -- invisible head; no restore needed since it's the same model.
    RequestModel(wantHash)
    local endAt = GetGameTimer() + 3000
    while not HasModelLoaded(wantHash) and GetGameTimer() < endAt do Wait(0) end
    if HasModelLoaded(wantHash) then
      if not isFreemode then originalModel = curModel end
      SetPlayerModel(PlayerId(), wantHash)
      playerPed = PlayerPedId()
      SetModelAsNoLongerNeeded(wantHash)
    end
  end

  -- If a manual pose was set for this category, reuse its exact angle + lift for
  -- every other texture of this item so you don't re-pose each one. Skip when this
  -- capture is itself a manual pose (the admin is setting a new one).
  local remembered = (not payload.manual) and RememberedPose[category] or nil

  local pedHeading
  if remembered and remembered.heading then
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

  startCleanCaptureLighting()

  SetEntityCoordsNoOffset(playerPed, captureCoords.x, captureCoords.y, captureCoords.z + zOffset + groundLift, false, false, false)
  SetEntityHeading(playerPed, pedHeading)
  FreezeEntityPosition(playerPed, true)
  SetPedAoBlobRendering(playerPed, false)

  applyGhostCaptureBase(playerPed, payload)

  -- Decide head hiding:
  --  - Head props (hat/glasses/earrings/mask): head MESH is already hidden by the
  --    invisible streamed head component; do NOT run flag 166 or it would hide the
  --    prop too. So the prop shows with no head.
  --  - Visible-head categories: no hiding.
  --  - Everything else: use flag 166 to fully hide the head.
  if categoryAttachesToHead(payload.category) or categoryNeedsVisibleHead(payload.category) then
    stopNoHeadCaptureFlag()
  else
    startNoHeadCaptureFlag()
  end

  local camCfg = (GetCaptureCameraConfig and GetCaptureCameraConfig(category))
    or (Config.IconCapture and Config.IconCapture.captureCameras and Config.IconCapture.captureCameras[category])
    or nil

  if camCfg and CreateSkinCamCaptureConfig then
    DestroySkinCam()
    Wait(50)
    CreateSkinCamCaptureConfig(camCfg, baseHeading, zOffset + groundLift)
  else
    local captureCamera = (payload.crop and payload.crop.camera) or 'body'
    if captureCamera ~= 'body' and captureCamera ~= 'head' and captureCamera ~= 'face' and captureCamera ~= 'feet' then
      captureCamera = 'body'
    end
    if CreateSkinCamCapture then
      DestroySkinCam()
      Wait(50)
      CreateSkinCamCapture(captureCamera, baseHeading, zOffset + groundLift)
    elseif CreateSkinCam then
      DestroySkinCam()
      Wait(50)
      CreateSkinCam(captureCamera)
    end
  end

  -- Replay the remembered manual camera (zoom/orbit/height) so other textures of
  -- this item frame identically to the one you posed by hand.
  if remembered and remembered.cam and type(ApplyLiveCaptureCamParams) == 'function' then
    ApplyLiveCaptureCamParams(remembered.cam)
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
    appearanceSnapshot = appearanceSnapshot,
    originalCoords = originalCoords,
    originalHeading = originalHeading,
    originalVisible = originalVisible,
    originalAlpha = originalAlpha,
    originalFrozen = originalFrozen,
    waitBeforeScreenshot = tonumber(payload.lighting and payload.lighting.waitBeforeScreenshot) or 900,
    category = category,
    -- True for hat/glasses/earrings/mask so the screenshot step re-asserts the
    -- invisible head (without flag 166, which would hide the prop).
    headProp = categoryAttachesToHead(category) and not categoryNeedsVisibleHead(category),
    originalModel = originalModel,
  }
end

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

  local payload, err = buildIconCapturePayload(data)
  if not payload then
    cb({ success = false, error = err or 'invalid_capture_payload' })
    return
  end

  pendingIconCapture = payload

  local category = tostring(payload.category or ''):lower()
  local wantManual = (data and (data.manual == true or data.manualPose == true))
    and MANUAL_CAPABLE[category] == true

  local session = prepareCaptureSession(payload)

  if wantManual then
    -- Manual pose mode: don't shoot yet. Hand rotation control to the admin and
    -- wait for confirmManualShot / cancelManualShot from the NUI.
    manualSession = session

    -- Keep the NUI visible AND let mouse/keys through so the admin can drag-rotate
    -- the ped and click the on-screen Confirm/Cancel controls.
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    SendNUIMessage({
      type = 'manualPoseStart',
      category = category,
      heading = GetEntityHeading(session.playerPed),
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
-- reliably — unfreeze, move, refreeze. Track the total lift on the session so it
-- survives any re-place and is preserved through the screenshot.
RegisterNUICallback('manualPoseLift', function(data, cb)
  if not manualSession then cb({ success = false, error = 'no_manual_session' }); return end
  local ped = manualSession.playerPed
  if not ped or not DoesEntityExist(ped) then cb({ success = false }); return end

  data = type(data) == 'table' and data or {}
  local delta = tonumber(data.delta) or 0.0
  if delta > 1.0 then delta = 1.0 end
  if delta < -1.0 then delta = -1.0 end

  manualSession.liftOffset = (tonumber(manualSession.liftOffset) or 0.0) + delta

  local c = GetEntityCoords(ped)
  FreezeEntityPosition(ped, false)
  SetEntityCoordsNoOffset(ped, c.x, c.y, c.z + delta, false, false, false)
  FreezeEntityPosition(ped, true)
  cb({ success = true, lift = manualSession.liftOffset })
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
  cb({ success = true })
end)

-- Admin confirmed the angle: take the screenshot now.
RegisterNUICallback('confirmManualShot', function(_, cb)
  if not manualSession then cb({ success = false, error = 'no_manual_session' }); return end
  local session = manualSession
  manualSession = nil

  -- Snapshot the pose so it can be replayed for the other textures of this item.
  local ped = session.playerPed
  local cat = tostring(session.category or ''):lower()
  if ped and DoesEntityExist(ped) and cat ~= '' then
    RememberedPose[cat] = {
      heading = GetEntityHeading(ped),
      lift = tonumber(session.liftOffset) or 0.0,
      cam = (type(GetLiveCaptureCamParams) == 'function') and GetLiveCaptureCamParams() or nil,
    }
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
  manualSession = nil

  stopNoHeadCaptureFlag()
  stopCleanCaptureLighting()
  ClearTimecycleModifier()

  restorePedAppearance(session.playerPed, session.appearanceSnapshot)
  restoreRealPedAfterCapture(session.playerPed, session.originalCoords, session.originalHeading,
    session.originalVisible, session.originalAlpha, session.originalFrozen)

  if SetAdminCaptureBackdropMode then
    SetAdminCaptureBackdropMode('none', nil)
  end
  if CreateSkinCam then
    CreateThread(function()
      Wait(50)
      CreateSkinCam('body')
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

--========================================================
-- Debug commands
--========================================================

RegisterCommand('nvheadflagtest', function()
  CreateThread(function()
    print('[nv_cloth] Head reset flag 166 test running for 10 seconds.')

    local started = GetGameTimer()

    while GetGameTimer() - started < 10000 do
      local ped = PlayerPedId()

      if ped and ped ~= 0 and DoesEntityExist(ped) then
        SetPedResetFlag(ped, 166, true)
      end

      Wait(0)
    end

    print('[nv_cloth] Head reset flag 166 test ended.')
  end)
end)

RegisterCommand('nvstreamcheck', function()
  CreateThread(function()
    local resource = GetCurrentResourceName()

    local files = {
      'stream/mp_m_freemode_01^head_000_r.ydd',
      'stream/mp_f_freemode_01^head_000_r.ydd',
      'stream/prop_ld_greenscreen_01.ydr',
    }

    print('^3[nv_cloth] Stream file check for resource: ' .. resource .. '^7')

    for _, file in ipairs(files) do
      local data = LoadResourceFile(resource, file)

      if data and #data > 0 then
        print(('^2[nv_cloth] FOUND %s | bytes=%s^7'):format(file, tostring(#data)))
      else
        print(('^1[nv_cloth] MISSING OR NOT READABLE: %s^7'):format(file))
      end
    end
  end)
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end

  stopNoHeadCaptureFlag()
  stopCleanCaptureLighting()

  local ped = PlayerPedId()
  if ped and ped ~= 0 and DoesEntityExist(ped) then
    SetPedAoBlobRendering(ped, true)
    ResetEntityAlpha(ped)
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
  end
end)