--========================================================
-- Skin Camera Manager (CLEAN)
-- - Smooth preset cameras around the player (face/body/feet)
-- - Collision-aware placement to avoid walls/props
-- - NUI callbacks: changeCamera, rotateCamera
--========================================================

-- Presets (only FOV is used; positions are computed around the player)
local CAM_PRESET = {
  face = { fov = 28.0 },
  head = { fov = 32.0 },
  body = { fov = 38.0 },
  feet = { fov = 34.0 },
}

-- State
local isBusy = false
local skinCam = nil        -- camera handle
local createdCams = {}
local currentPreset = nil  -- "face" | "head" | "body" | "feet"
local useFixedShopCamera = false
local rememberCam

-- Live capture-camera parameters, kept so manual pose can nudge them with WASD.
-- Rebuilt into the actual cam whenever they change.
local LiveCaptureCam = nil  -- { pedX, pedY, pedZ, dist, targetZ, fov, heading }

function SetShopCameraFixedMode(enabled)
  useFixedShopCamera = enabled == true
end


local function fixedCameraConfig(preset)
  local fixed = {
    face = { dist = 2.25, z = 0.66, fov = 28.0 },
    head = { dist = 2.60, z = 0.74, fov = 32.0 },
    body = { dist = 4.35, z = 0.18, fov = 38.0 },
    feet = { dist = 3.10, z = -0.78, fov = 34.0 },
  }
  return fixed[preset] or fixed.body
end

local function setOrMoveSkinCam(camPos, target, fov, instant)
  if skinCam then
    local oldCam = skinCam
    local newCam = rememberCam(CreateCamWithParams(
      "DEFAULT_SCRIPTED_CAMERA",
      camPos.x, camPos.y, camPos.z,
      0.0, 0.0, 0.0,
      fov,
      false, 0
    ))
    PointCamAtCoord(newCam, target.x, target.y, target.z)
    if instant then
      SetCamActive(newCam, true)
      if oldCam and DoesCamExist(oldCam) then DestroyCam(oldCam, false) end
    else
      SetCamActiveWithInterp(newCam, oldCam, 350, true, true)
      CreateThread(function()
        Wait(450)
        if oldCam and oldCam ~= newCam and DoesCamExist(oldCam) then DestroyCam(oldCam, false) end
      end)
    end
    skinCam = newCam
  else
    skinCam = rememberCam(CreateCamWithParams(
      "DEFAULT_SCRIPTED_CAMERA",
      camPos.x, camPos.y, camPos.z,
      0.0, 0.0, 0.0,
      fov,
      false, 0
    ))
    PointCamAtCoord(skinCam, target.x, target.y, target.z)
    SetCamActive(skinCam, true)
    RenderScriptCams(true, false, 250, true, true)
  end
end

function CreateSkinCamCapture(preset, cameraHeading, zOffset, targetPed)
  local ped = targetPed and DoesEntityExist(targetPed) and targetPed or PlayerPedId()
  local pPos = GetEntityCoords(ped)
  preset = tostring(preset or 'body')
  currentPreset = preset

  local cfg = fixedCameraConfig(preset)
  local targetZ = pPos.z + (cfg.z or 0.25) + (tonumber(zOffset) or 0.0)
  local rad = math.rad(tonumber(cameraHeading) or GetEntityHeading(ped))
  local camPos = vector3(
    pPos.x - math.sin(rad) * (cfg.dist or 3.25),
    pPos.y + math.cos(rad) * (cfg.dist or 3.25),
    targetZ + 0.15
  )

  local fovP = cfg.fov or CAM_PRESET[preset].fov or 32.0
  CaptureCamGeom = {
    cam = camPos,
    target = vector3(pPos.x, pPos.y, targetZ),
    fov = fovP,
  }
  setOrMoveSkinCam(camPos, vector3(pPos.x, pPos.y, targetZ), fovP, true)
end

--- Precise capture camera driven by an explicit { dist, z, fov } config.
--- Used by icon capture so each clothing type is framed on its own body region
--- (pants -> legs, shoes -> feet, hat -> head, watch -> wrist, ...).
---@param cfg table   -- { dist = number, z = number, fov = number }
---@param cameraHeading number
---@param extraZ number|nil  -- optional per-item zOffset from the preset/config
function CreateSkinCamCaptureConfig(cfg, cameraHeading, extraZ, targetPed)
  cfg = type(cfg) == 'table' and cfg or {}
  local ped = targetPed and DoesEntityExist(targetPed) and targetPed or PlayerPedId()
  local pPos = GetEntityCoords(ped)

  local dist = tonumber(cfg.dist) or 2.6
  -- Most slots aim at a height relative to the ped root. Wrist accessories use
  -- OP's bone targets so a tiny floating watch/bracelet stays exactly centred.
  local targetX, targetY
  local targetZ
  local bone = tonumber(cfg.bone)
  if bone and bone > 0 then
    local bonePos = GetPedBoneCoords(ped, bone, 0.0, 0.0, 0.0)
    targetX, targetY = bonePos.x, bonePos.y
    targetZ = bonePos.z + (tonumber(cfg.z) or 0.0) + (tonumber(extraZ) or 0.0)
  else
    targetX, targetY = pPos.x, pPos.y
    -- z is the height (relative to the ped root) that the camera AIMS at.
    -- Positive = higher up the body (head/torso), negative = lower (legs/feet).
    targetZ = pPos.z + (tonumber(cfg.z) or 0.25) + (tonumber(extraZ) or 0.0)
  end
  local fov = tonumber(cfg.fov) or 32.0

  local rad = math.rad(tonumber(cameraHeading) or GetEntityHeading(ped))
  local camPos = vector3(
    targetX - math.sin(rad) * dist,
    targetY + math.cos(rad) * dist,
    targetZ + 0.05
  )

  currentPreset = 'capture'
  -- Remember the live parameters so manual pose (WASD) can move/zoom this camera.
  LiveCaptureCam = {
    pedX = targetX, pedY = targetY, pedZ = pPos.z,
    dist = dist, targetZ = targetZ, fov = fov,
    heading = tonumber(cameraHeading) or GetEntityHeading(ped),
  }
  -- Expose the exact capture geometry so the backdrop can be placed to fill THIS
  -- shot's frame (fixes tight/low/side shots like glasses, shoes, watch, bags).
  CaptureCamGeom = {
    cam = camPos,
    target = vector3(targetX, targetY, targetZ),
    fov = fov,
  }
  setOrMoveSkinCam(camPos, vector3(targetX, targetY, targetZ), fov, true)
end

-- Rebuild the capture camera from LiveCaptureCam params. Used by manual WASD moves.
-- Moves the EXISTING cam in place (no recreate) so adjustments are smooth and
-- flicker-free while posing.
local function rebuildLiveCaptureCam()
  local p = LiveCaptureCam
  if not p then return end
  local rad = math.rad(p.heading)
  local camPos = vector3(
    p.pedX - math.sin(rad) * p.dist,
    p.pedY + math.cos(rad) * p.dist,
    p.targetZ + 0.05
  )
  local target = vector3(p.pedX, p.pedY, p.targetZ)
  CaptureCamGeom = { cam = camPos, target = target, fov = p.fov }

  if skinCam and DoesCamExist(skinCam) then
    SetCamCoord(skinCam, camPos.x, camPos.y, camPos.z)
    PointCamAtCoord(skinCam, target.x, target.y, target.z)
    SetCamFov(skinCam, p.fov)
  else
    setOrMoveSkinCam(camPos, target, p.fov, true)
  end
end

-- Return a shallow copy of the current live capture-camera params (for pose memory).
function GetLiveCaptureCamParams(targetPed)
  if not LiveCaptureCam then return nil end
  local ped = targetPed and DoesEntityExist(targetPed) and targetPed or PlayerPedId()
  local pPos = GetEntityCoords(ped)
  return {
    dist = LiveCaptureCam.dist,
    targetZ = LiveCaptureCam.targetZ,
    fov = LiveCaptureCam.fov,
    heading = LiveCaptureCam.heading,
    -- Camera target relative to the posed ped. This preserves intentional
    -- off-centre framing after the ped is moved in manual setup.
    targetOffsetX = LiveCaptureCam.pedX - pPos.x,
    targetOffsetY = LiveCaptureCam.pedY - pPos.y,
    relZ = LiveCaptureCam.targetZ - pPos.z,
  }
end

-- Re-apply remembered camera params to the current ped/capture (used to replay a
-- manual pose for the remaining textures). pedPos anchors the camera to where the
-- ped stands for this shot.
function ApplyLiveCaptureCamParams(params, targetPed)
  if type(params) ~= 'table' then return false end
  local ped = targetPed and DoesEntityExist(targetPed) and targetPed or PlayerPedId()
  local pPos = GetEntityCoords(ped)
  local anchorX = pPos.x + (tonumber(params.targetOffsetX) or 0.0)
  local anchorY = pPos.y + (tonumber(params.targetOffsetY) or 0.0)
  local relZ = tonumber(params.relZ)
  local targetZ = relZ and (pPos.z + relZ) or (tonumber(params.targetZ) or (pPos.z + 0.25))
  LiveCaptureCam = {
    pedX = anchorX, pedY = anchorY, pedZ = pPos.z,
    dist = tonumber(params.dist) or 2.6,
    targetZ = targetZ,
    fov = tonumber(params.fov) or 32.0,
    heading = tonumber(params.heading) or GetEntityHeading(ped),
  }
  rebuildLiveCaptureCam()
  return true
end

-- Nudge the live capture camera during manual pose.
-- action: 'zoom' (+in/-out), 'orbit' (+right/-left), 'height' (+up/-down).
function AdjustLiveCaptureCam(action, amount)
  if not LiveCaptureCam then return false end
  amount = tonumber(amount) or 0.0
  if action == 'zoom' then
    -- Move the camera closer/farther. Clamp so it can't cross the ped or fly off.
    LiveCaptureCam.dist = math.max(0.4, math.min(8.0, LiveCaptureCam.dist - amount))
  elseif action == 'orbit' then
    LiveCaptureCam.heading = (LiveCaptureCam.heading + amount) % 360.0
  elseif action == 'height' then
    LiveCaptureCam.targetZ = LiveCaptureCam.targetZ + amount
  elseif action == 'fov' then
    LiveCaptureCam.fov = math.max(4.0, math.min(90.0, LiveCaptureCam.fov - amount))
  end
  rebuildLiveCaptureCam()
  return true
end

--========================================================
-- Capture-camera overrides saved by the optional live position editor.
-- RuntimeCaptureCameras is filled from the DB after the editor confirms a shot.
-- Capture reads GetCaptureCameraConfig() so tuned values apply without a restart.
--========================================================
RuntimeCaptureCameras = RuntimeCaptureCameras or {}

function GetCaptureCameraConfig(category)
  category = tostring(category or ''):lower()
  local configured = Config.IconCapture and Config.IconCapture.captureCameras
    and Config.IconCapture.captureCameras[category] or nil
  local override = RuntimeCaptureCameras[category]
  if type(override) == 'table' and override.dist and override.z and override.fov then
    -- Keep non-editable slot metadata (notably wrist bone targets) even when an
    -- admin has saved custom distance/Z/FOV values for the category.
    local merged = {}
    if type(configured) == 'table' then
      for key, value in pairs(configured) do merged[key] = value end
    end
    for key, value in pairs(override) do merged[key] = value end
    return merged
  end
  return configured
end

local function captureBaseHeading()
  local studio = Config.AdminStudio and Config.AdminStudio.StudioCoords
  return (studio and studio.w) or GetEntityHeading(PlayerPedId())
end

local CAPTURE_VIEW_OFFSETS = {
  front = 0.0, back = 180.0, left = 90.0, right = -90.0,
  ['front-left'] = 45.0, ['front-right'] = -45.0,
  ['back-left'] = 135.0, ['back-right'] = -135.0,
}

local function defaultCaptureHeading(category)
  local presets = Config.IconCapture and Config.IconCapture.presets or {}
  local preset = presets[tostring(category or ''):lower()] or {}
  local offset = tonumber(preset.viewAngle)
  if offset == nil then offset = CAPTURE_VIEW_OFFSETS[tostring(preset.view or 'front'):lower()] or 0.0 end
  return (captureBaseHeading() + offset) % 360.0
end

-- Complete effective preset used by automatic capture and the optional editor.
function GetEffectiveStudioSettings(category)
  category = tostring(category or ''):lower()
  local cameras = Config.IconCapture and Config.IconCapture.captureCameras or {}
  local presets = Config.IconCapture and Config.IconCapture.presets or {}
  local lifts = Config.IconCapture and Config.IconCapture.groundLift or {}
  local lighting = Config.IconCapture and Config.IconCapture.lighting or {}
  local camera = cameras[category] or { dist = 2.6, z = 0.0, fov = 32.0 }
  local preset = presets[category] or {}
  local saved = RuntimeCaptureCameras and RuntimeCaptureCameras[category] or nil

  return {
    dist = tonumber(saved and saved.dist) or tonumber(camera.dist) or 2.6,
    z = tonumber(saved and saved.z) or tonumber(camera.z) or 0.0,
    fov = tonumber(saved and saved.fov) or tonumber(camera.fov) or 32.0,
    poseHeading = saved and saved.poseHeading ~= nil and tonumber(saved.poseHeading)
      or tonumber(camera.poseHeading) or defaultCaptureHeading(category),
    poseLift = saved and saved.poseLift ~= nil and tonumber(saved.poseLift)
      or tonumber(camera.poseLift) or tonumber(lifts[category]) or 0.0,
    lightStrength = saved and saved.lightStrength ~= nil and tonumber(saved.lightStrength)
      or tonumber(lighting.timecycleStrength) or 0.0,
    backdrop = saved and saved.backdrop or tostring(preset.backgroundColor or 'green'):lower(),
    camRelZ = saved and saved.camRelZ ~= nil and tonumber(saved.camRelZ) or tonumber(camera.z) or 0.0,
    camHeading = saved and saved.camHeading ~= nil and tonumber(saved.camHeading)
      or tonumber(camera.camHeading) or captureBaseHeading(),
    camTargetX = saved and saved.camTargetX ~= nil and tonumber(saved.camTargetX)
      or -(tonumber(camera.playerOffsetX) or 0.0),
    camTargetY = saved and saved.camTargetY ~= nil and tonumber(saved.camTargetY)
      or -(tonumber(camera.playerOffsetY) or 0.0),
    overridden = type(saved) == 'table',
  }
end

RegisterNetEvent('nvCloth:client:captureCameras', function(overrides)
  RuntimeCaptureCameras = {}
  if type(overrides) == 'table' then
    for cat, cfg in pairs(overrides) do
      if type(cfg) == 'table' and cfg.dist and cfg.z and cfg.fov then
        RuntimeCaptureCameras[tostring(cat):lower()] = {
          dist = cfg.dist + 0.0, z = cfg.z + 0.0, fov = cfg.fov + 0.0,
          poseHeading = cfg.poseHeading and (cfg.poseHeading + 0.0) or nil,
          poseLift = cfg.poseLift and (cfg.poseLift + 0.0) or nil,
          lightStrength = cfg.lightStrength and (cfg.lightStrength + 0.0) or nil,
          backdrop = cfg.backdrop and tostring(cfg.backdrop) or nil,
          camRelZ = cfg.camRelZ and (cfg.camRelZ + 0.0) or nil,
          camHeading = cfg.camHeading and (cfg.camHeading + 0.0) or nil,
          camTargetX = cfg.camTargetX and (cfg.camTargetX + 0.0) or nil,
          camTargetY = cfg.camTargetY and (cfg.camTargetY + 0.0) or nil,
        }
      end
    end
  end
end)

-- Unified studio settings for a category (camera + pose + lighting + backdrop).
function GetStudioSettings(category)
  return GetEffectiveStudioSettings(category)
end

-- Expose saved pose (heading + lift) for a category so capture can reuse it.
function GetSavedPose(category)
  category = tostring(category or ''):lower()
  local configured = Config.IconCapture and Config.IconCapture.captureCameras
    and Config.IconCapture.captureCameras[category] or nil
  local o = RuntimeCaptureCameras[category] or configured
  if type(o) == 'table' and (o.poseHeading ~= nil or o.poseLift ~= nil) then
    local cam = nil
    if o.dist ~= nil and o.fov ~= nil then
      cam = {
        dist = o.dist,
        fov = o.fov,
        relZ = o.camRelZ or o.z,
        heading = o.camHeading,
        targetOffsetX = o.camTargetX ~= nil and o.camTargetX or -(tonumber(o.playerOffsetX) or 0.0),
        targetOffsetY = o.camTargetY ~= nil and o.camTargetY or -(tonumber(o.playerOffsetY) or 0.0),
      }
    end
    return { heading = o.poseHeading, lift = o.poseLift, cam = cam }
  end
  return nil
end


-- Normal admin browsing preview. This camera is completely separate from the
-- inventory-icon camera: selecting a section or receiving saved capture presets
-- must never zoom the middle character into capture framing.
function RestoreAdminCategoryPreview(category, instant)
  -- Capture cleanup can finish a frame after the menu closes. Never let that
  -- delayed cleanup recreate the camera or reapply the last preview clothe.
  if opened ~= true or not (NvCloth_IsAdminShop and NvCloth_IsAdminShop()) then
    return false
  end
  category = tostring(category or 'torso'):lower()
  if category == 'arms' then category = 'torso' end

  local previews = Config.IconCapture and Config.IconCapture.previewCameras or {}
  local cfg = previews[category] or previews.torso
    or { dist = 4.35, z = 0.18, fov = 38.0, viewAngle = 0.0 }
  local ped = PlayerPedId()
  if not DoesEntityExist(ped) then return false end

  local baseHeading = captureBaseHeading()
  local pedHeading = (baseHeading + (tonumber(cfg.viewAngle) or 0.0)) % 360.0
  SetEntityHeading(ped, pedHeading)

  local pPos = GetEntityCoords(ped)
  local dist = math.max(1.25, math.min(7.0, tonumber(cfg.dist) or 4.35))
  local targetZ = pPos.z + (tonumber(cfg.z) or 0.18)
  local fov = math.max(18.0, math.min(65.0, tonumber(cfg.fov) or 38.0))
  local rad = math.rad(baseHeading)
  local camPos = vector3(
    pPos.x - math.sin(rad) * dist,
    pPos.y + math.cos(rad) * dist,
    targetZ + 0.15
  )

  LiveCaptureCam = nil
  CaptureCamGeom = nil
  currentPreset = 'admin-preview:' .. category
  setOrMoveSkinCam(camPos, vector3(pPos.x, pPos.y, targetZ), fov, instant ~= false)
  return true
end

--========================================================
-- Per-category saved crops (set once, reused for every capture of that category)
-- The NUI stores the crop and applies it; the server persists it so it survives
-- restarts and is shared across admins. These callbacks just relay to the server.
--========================================================
RegisterNUICallback('saveCaptureCrop', function(data, cb)
  data = type(data) == 'table' and data or {}
  local category = tostring(data.category or ''):lower()
  if category ~= '' then
    TriggerServerEvent('nvCloth:server:saveCaptureCrop', {
      category = category,
      left = tonumber(data.left) or 0,
      top = tonumber(data.top) or 0,
      right = tonumber(data.right) or 0,
      bottom = tonumber(data.bottom) or 0,
    })
  end
  cb({ success = true })
end)

RegisterNUICallback('resetCaptureCrop', function(data, cb)
  data = type(data) == 'table' and data or {}
  local category = tostring(data.category or ''):lower()
  if category ~= '' then
    TriggerServerEvent('nvCloth:server:resetCaptureCrop', category)
  end
  cb({ success = true })
end)

RegisterNetEvent('nvCloth:client:captureCrops', function(crops)
  local out = {}
  if type(crops) == 'table' then
    for cat, cfg in pairs(crops) do
      if type(cfg) == 'table' then
        out[tostring(cat):lower()] = {
          left = tonumber(cfg.left) or 0,
          top = tonumber(cfg.top) or 0,
          right = tonumber(cfg.right) or 0,
          bottom = tonumber(cfg.bottom) or 0,
        }
      end
    end
  end
  SendNUIMessage({ type = 'captureCrops', crops = out })
end)

--========================================================
-- Helpers
--========================================================

--- Capsule raycast between two points to detect collisions
---@param fromX number
---@param fromY number
---@param fromZ number
---@param toVec vector3
---@return boolean -- true if colliding
local function IsCamColliding(fromX, fromY, fromZ, toVec)
  local test = StartShapeTestCapsule(
    fromX, fromY, fromZ,
    toVec.x, toVec.y, toVec.z,
    0.30,                 -- radius
    1,                    -- flags
    PlayerPedId(),        -- ignore entity
    7
  )
  local _, hit, _, _, _ = GetShapeTestResult(test)
  return (hit ~= 0)
end

--- Find a safe camera position on a ring around the player (sweeps by angle)
---@param origin vector3   -- player coords
---@param baseHeading number
---@param distance number
---@param camZ number
---@return vector3|nil
rememberCam = function(cam)
  if cam and cam ~= 0 then createdCams[#createdCams + 1] = cam end
  return cam
end

local function FindSafeCamPos(origin, baseHeading, distance, camZ)
  local step = 10.0
  for a = 0, 360, step do
    local angle = baseHeading + a
    local rad = math.rad(angle)

    local x = origin.x - math.sin(rad) * distance
    local y = origin.y + math.cos(rad) * distance
    if not IsCamColliding(x, y, camZ, origin) then
      return vector3(x, y, camZ)
    end
  end
  return nil
end

--========================================================
-- Core camera logic
--========================================================

--- Create or move the skin camera to the requested preset.
---@param preset "face"|"body"|"feet"
function CreateSkinCam(preset)
  local ped = PlayerPedId()
  local pPos = GetEntityCoords(ped)
  local pHeading = GetEntityHeading(ped)

  -- Distance from player and target height (Z) per preset
  local dist = 4.0
  local targetZ
  local configuredFov = nil

  currentPreset = preset
  if preset == "face" then
    targetZ = pPos.z + 0.5
  elseif preset == "head" then
    dist = 2.0
    targetZ = pPos.z + 0.72
  elseif preset == "body" then
    targetZ = pPos.z
  else -- "feet"
    dist = dist - 2.0
    targetZ = pPos.z - 0.5
  end

  local camPos

  -- In the fixed dressing room we do NOT run wall collision sweeps.
  -- Small interiors make shape tests snap the camera into the player.
  if useFixedShopCamera then
    local fixed = {
      face = { dist = 2.25, z = 0.66, fov = 28.0 },
      head = { dist = 2.60, z = 0.74, fov = 32.0 },
      body = { dist = 4.35, z = 0.18, fov = 38.0 },
      feet = { dist = 3.10, z = -0.78, fov = 34.0 },
    }
    local cfg = fixed[preset] or fixed.body
    dist = cfg.dist
    targetZ = pPos.z + cfg.z
    configuredFov = cfg.fov
    local rad = math.rad(pHeading)
    camPos = vector3(
      pPos.x - math.sin(rad) * dist,
      pPos.y + math.cos(rad) * dist,
      targetZ + 0.15
    )
  else
    -- Try to find a collision-free position in normal/free preview mode.
    camPos = FindSafeCamPos(pPos, pHeading, dist, targetZ)

    -- Fallback: bring camera a bit closer on collision-heavy spots
    if not camPos then
      local closer = dist - 1.5
      local rad = math.rad(pHeading)
      camPos = vector3(
        pPos.x - math.sin(rad) * closer,
        pPos.y + math.cos(rad) * closer,
        targetZ
      )
    end
  end

  -- Make the ped face the camera. In fixed shop/admin mode use an instant heading change so the preview ped stays lifeless.
  local faceHeading = (GetHeadingFromVector_2d(pPos.x - camPos.x, pPos.y - camPos.y) + 180.0) % 360.0
  if useFixedShopCamera then
    SetEntityHeading(ped, faceHeading)
  else
    TaskAchieveHeading(ped, faceHeading, 1000)
  end

  local fov = configuredFov or CAM_PRESET[preset].fov or 30.0

  if skinCam then
    -- Smoothly interpolate to a new camera
    local oldCam = skinCam
    local newCam = rememberCam(CreateCamWithParams(
      "DEFAULT_SCRIPTED_CAMERA",
      camPos.x, camPos.y, camPos.z,
      0.0, 0.0, 0.0,
      fov,
      false, 0
    ))
    PointCamAtCoord(newCam, pPos.x, pPos.y, targetZ)
    SetCamActiveWithInterp(newCam, oldCam, 750, true, true)
    skinCam = newCam
    CreateThread(function()
      Wait(850)
      if oldCam and oldCam ~= skinCam and DoesCamExist(oldCam) then
        DestroyCam(oldCam, false)
      end
    end)
  else
    -- First-time camera creation
    skinCam = rememberCam(CreateCamWithParams(
      "DEFAULT_SCRIPTED_CAMERA",
      camPos.x, camPos.y, camPos.z,
      0.0, 0.0, 0.0,
      fov,
      false, 0
    ))
    PointCamAtCoord(skinCam, pPos.x, pPos.y, targetZ)
    SetCamActive(skinCam, true)
    RenderScriptCams(true, false, 2000, true, true)
  end
end

--- Destroy the skin camera and stop rendering.
function DestroySkinCam()
  -- Hard reset. This fixes the common “camera stuck after close” problem caused by interpolated cams.
  RenderScriptCams(false, true, 350, true, true)
  Wait(50)

  for i = #createdCams, 1, -1 do
    local cam = createdCams[i]
    if cam and DoesCamExist(cam) then
      SetCamActive(cam, false)
      DestroyCam(cam, false)
    end
    createdCams[i] = nil
  end

  if skinCam and DoesCamExist(skinCam) then
    SetCamActive(skinCam, false)
    DestroyCam(skinCam, false)
  end

  skinCam = nil
  currentPreset = nil
  LiveCaptureCam = nil
  isBusy = false
  ClearFocus()
  ClearTimecycleModifier()
  RenderScriptCams(false, false, 0, true, true)
  -- DestroyAllCams(true) -- REMOVED: would destroy other resources cameras
  SetGameplayCamRelativeHeading(0.0)
  SetGameplayCamRelativePitch(0.0, 1.0)
end

--========================================================
-- NUI Callbacks
--========================================================

RegisterNUICallback("changeCamera", function(data, cb)
  -- Camera switches must be responsive; old 1s busy lock made category buttons feel like
  -- they needed a double click when players changed categories quickly.
  local preset = tostring(data.camera or "body")
  if preset ~= "face" and preset ~= "head" and preset ~= "body" and preset ~= "feet" then
    preset = "body"
  end
  local category = tostring(data.category or ''):lower()
  if NvCloth_IsAdminShop and NvCloth_IsAdminShop() and category ~= '' then
    RestoreAdminCategoryPreview(category, true)
  else
    CreateSkinCam(preset)
  end
  cb({ success = true })
end)

RegisterNUICallback("rotateCamera", function(_, cb)
  if isBusy then
    cb({ success = false })
    return
  end
  isBusy = true

  local ped = PlayerPedId()
  local heading = (GetEntityHeading(ped) + 180.0) % 360.0
  if useFixedShopCamera then
    SetEntityHeading(ped, heading)
  else
    TaskAchieveHeading(ped, heading, 1000)
  end

  CreateThread(function()
    Wait(180)
    isBusy = false
  end)

  cb({ success = true })
end)

--========================================================
-- OPTIONAL: expose destroy if UI or flow needs to exit camera mode
--========================================================
-- exports("destroySkinCam", DestroySkinCam)

-- Smooth mouse-drag rotation from the new live-preview shop UI.
RegisterNUICallback("rotatePed", function(data, cb)
  local ped = PlayerPedId()
  local delta = tonumber(data and data.delta) or 0.0
  if delta > 25.0 then delta = 25.0 end
  if delta < -25.0 then delta = -25.0 end
  SetEntityHeading(ped, (GetEntityHeading(ped) + delta) % 360.0)
  cb({ success = true })
end)
