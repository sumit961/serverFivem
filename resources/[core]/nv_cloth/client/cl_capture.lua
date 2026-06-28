-- Admin inventory icon capture
-- Captures the current live preview with screenshot-basic, sends it to NUI
-- for green-screen background removal, then server saves transparent PNG to cm-items.
--========================================================
local pendingIconCapture = nil

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
  -- x/y/w/h are percentages of the full screenshot.
  -- These defaults crop only the item zone so transparent icons stay clean.
  local defaults = {
    torso = { x = 0.30, y = 0.16, w = 0.40, h = 0.48, camera = 'body', padding = 10 },
    armor = { x = 0.30, y = 0.16, w = 0.40, h = 0.48, camera = 'body', padding = 10 },
    tshirt = { x = 0.31, y = 0.18, w = 0.38, h = 0.34, camera = 'body', padding = 10 },
    pants = { x = 0.33, y = 0.47, w = 0.34, h = 0.39, camera = 'body', padding = 8 },
    shoes = { x = 0.34, y = 0.68, w = 0.32, h = 0.27, camera = 'feet', padding = 8 },
    hat = { x = 0.35, y = 0.02, w = 0.30, h = 0.26, camera = 'face', padding = 8 },
    glasses = { x = 0.34, y = 0.13, w = 0.32, h = 0.20, camera = 'face', padding = 6 },
    earrings = { x = 0.28, y = 0.13, w = 0.44, h = 0.28, camera = 'face', padding = 6 },
    chains = { x = 0.33, y = 0.26, w = 0.34, h = 0.25, camera = 'body', padding = 6 },
    bags = { x = 0.25, y = 0.18, w = 0.50, h = 0.55, camera = 'body', padding = 10 },
    watches = { x = 0.22, y = 0.30, w = 0.56, h = 0.34, camera = 'body', padding = 6 },
  }
  local crop = defaults[category] or { x = 0.28, y = 0.10, w = 0.44, h = 0.82, camera = 'body', padding = 12 }
  crop.camera = preset.camera or crop.camera
  crop.padding = preset.padding or crop.padding
  return crop
end

local function viewOffset(view)
  view = tostring(view or 'front'):lower()
  if view == 'back' then return 180.0 end
  if view == 'left' then return 90.0 end
  if view == 'right' then return -90.0 end
  return 0.0
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
  local sharedGender = (category == 'bags' and data.sharedGender ~= false) or data.sharedGender == true or preset.sharedGender == true
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
    textureId = tonumber(data.textureId or data.texture or 0) or 0,
    label = data.label,
    price = data.price,
    enabled = true,
    fileName = fileName,
    width = Config.IconCapture and Config.IconCapture.width or 512,
    height = Config.IconCapture and Config.IconCapture.height or 512,
    padding = crop.padding or (Config.IconCapture and Config.IconCapture.padding) or 18,
    chroma = Config.IconCapture and Config.IconCapture.chroma or nil,
    crop = crop,
    captureAngle = tostring(data.captureAngle or preset.view or 'front'):lower(),
    zOffset = tonumber(data.zOffset or preset.zOffset or 0.0) or 0.0,
    captureBackground = tostring(data.captureBackground or data.backgroundColor or preset.backgroundColor or 'green'):lower(),
    sharedGender = sharedGender,
    level = tonumber(data.level or data.bagLevel),
    bagLevel = tonumber(data.bagLevel or data.level),
    armorValue = tonumber(data.armorValue or data.armor_value),
  }

  if category == 'torso' then
    payload.arms = GetPedDrawableVariation(ped, 3)
    payload.armsTexture = GetPedTextureVariation(ped, 3)
    payload.undershirt = GetPedDrawableVariation(ped, 8)
    payload.undershirtTexture = GetPedTextureVariation(ped, 8)
  end

  return payload
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

  local ped = PlayerPedId()
  local originalCoords = GetEntityCoords(ped)
  local originalHeading = GetEntityHeading(ped)
  local studioCoords = Config.AdminStudio and Config.AdminStudio.StudioCoords or nil
  local baseHeading = (studioCoords and studioCoords.w) or originalHeading
  print(('[nv_cloth] Capture payload category=%s drawable=%s texture=%s bg=%s imageFile=%s bagLevel=%s'):format(
    tostring(payload.category), tostring(payload.drawableId), tostring(payload.textureId), tostring(payload.captureBackground), tostring(payload.fileName), tostring(payload.bagLevel)))

  if EnsureAdminStudioGreenScreen then EnsureAdminStudioGreenScreen() end
  if SetAdminCaptureBackdropMode then SetAdminCaptureBackdropMode(payload.captureBackground or 'green', baseHeading) end
  local angleMode = tostring(payload.captureAngle or 'front'):lower()
  local pedHeading = (angleMode == 'current') and originalHeading or ((baseHeading + viewOffset(angleMode)) % 360.0)
  local zOffset = tonumber(payload.zOffset) or 0.0

  SetEntityCoordsNoOffset(ped, originalCoords.x, originalCoords.y, originalCoords.z + zOffset, false, false, false)
  SetEntityHeading(ped, pedHeading)
  FreezeEntityPosition(ped, true)
  SetPedAoBlobRendering(ped, false)

  -- Move camera to the best preset for this category before taking the screenshot.
  -- CreateSkinCamCapture keeps the camera at the same clean studio/front background while we rotate the ped for bags/side items.
  local captureCamera = payload.crop and payload.crop.camera or 'body'
  if CreateSkinCamCapture then
    DestroySkinCam()
    Wait(50)
    CreateSkinCamCapture(captureCamera, baseHeading, 0.0)
  elseif CreateSkinCam then
    DestroySkinCam()
    Wait(50)
    CreateSkinCam(captureCamera)
  end

  SendNUIMessage({ type = 'prepareIconCapture', value = true })
  SetNuiFocus(false, false)
  SetTimecycleModifier('neutral')
  SetTimecycleModifierStrength(0.0)
  Wait(750)

  exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(imageData)
    ClearTimecycleModifier()
    SetEntityCoordsNoOffset(ped, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false)
    SetEntityHeading(ped, originalHeading)
    SetPedAoBlobRendering(ped, true)
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'prepareIconCapture', value = false })
    if SetAdminCaptureBackdropMode then SetAdminCaptureBackdropMode('none', nil) end

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

  cb({ success = true, pending = true })
end)

RegisterNUICallback('setCaptureBackdrop', function(data, cb)
  local mode = type(data) == 'table' and data.mode or 'none'
  mode = tostring(mode or 'none'):lower()
  if mode ~= 'none' and EnsureAdminStudioGreenScreen then EnsureAdminStudioGreenScreen() end
  if SetAdminCaptureBackdropMode then SetAdminCaptureBackdropMode(mode) end
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

  print(('[nv_cloth] Sending inventory icon to server: %s (%s bytes b64)'):format(tostring(payload.fileName), tostring(#tostring(payload.imageBase64 or ''))))
  -- Base64 PNG data can be too large for a normal TriggerServerEvent.
  -- Use a latent event so FiveM streams the payload instead of silently dropping it.
  TriggerLatentServerEvent('nvCloth:server:saveInventoryIcon', 200000, payload)
  pendingIconCapture = nil
  cb({ success = true })
end)

RegisterNetEvent('nvCloth:client:inventoryIconSaved', function(entry)
  SendNUIMessage({ type = 'iconCaptureResult', success = true, entry = entry or {} })
end)

RegisterNetEvent('nvCloth:client:inventoryIconSaveFailed', function(reason)
  SendNUIMessage({ type = 'iconCaptureResult', success = false, error = tostring(reason or 'save_failed') })
end)


