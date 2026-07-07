--========================================================
-- Skin Camera Manager (CLEAN)
-- - Smooth preset cameras around the player (face/body/feet)
-- - Collision-aware placement to avoid walls/props
-- - NUI callbacks: changeCamera, rotateCamera
--========================================================

-- Presets (only FOV is used; positions are computed around the player)
local CAM_PRESET = {
  face = { fov = 15.0 },
  head = { fov = 28.0 },
  body = { fov = 34.0 },
  feet = { fov = 42.0 },
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
    face = { dist = 1.55, z = 0.66, fov = 21.0 },
    head = { dist = 1.90, z = 0.76, fov = 28.0 },
    body = { dist = 3.45, z = 0.22, fov = 34.0 },
    feet = { dist = 2.45, z = -0.58, fov = 42.0 },
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

function CreateSkinCamCapture(preset, cameraHeading, zOffset)
  local ped = PlayerPedId()
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
function CreateSkinCamCaptureConfig(cfg, cameraHeading, extraZ)
  cfg = type(cfg) == 'table' and cfg or {}
  local ped = PlayerPedId()
  local pPos = GetEntityCoords(ped)

  local dist = tonumber(cfg.dist) or 2.6
  -- z is the height (relative to the ped root) that the camera AIMS at.
  -- Positive = higher up the body (head/torso), negative = lower (legs/feet).
  local targetZ = pPos.z + (tonumber(cfg.z) or 0.25) + (tonumber(extraZ) or 0.0)
  local fov = tonumber(cfg.fov) or 32.0

  local rad = math.rad(tonumber(cameraHeading) or GetEntityHeading(ped))
  local camPos = vector3(
    pPos.x - math.sin(rad) * dist,
    pPos.y + math.cos(rad) * dist,
    targetZ + 0.05
  )

  currentPreset = 'capture'
  -- Remember the live parameters so manual pose (WASD) can move/zoom this camera.
  LiveCaptureCam = {
    pedX = pPos.x, pedY = pPos.y, pedZ = pPos.z,
    dist = dist, targetZ = targetZ, fov = fov,
    heading = tonumber(cameraHeading) or GetEntityHeading(ped),
  }
  -- Expose the exact capture geometry so the backdrop can be placed to fill THIS
  -- shot's frame (fixes tight/low/side shots like glasses, shoes, watch, bags).
  CaptureCamGeom = {
    cam = camPos,
    target = vector3(pPos.x, pPos.y, targetZ),
    fov = fov,
  }
  setOrMoveSkinCam(camPos, vector3(pPos.x, pPos.y, targetZ), fov, true)
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
function GetLiveCaptureCamParams()
  if not LiveCaptureCam then return nil end
  return {
    dist = LiveCaptureCam.dist,
    targetZ = LiveCaptureCam.targetZ,
    fov = LiveCaptureCam.fov,
    heading = LiveCaptureCam.heading,
    -- relative aim height above the ped root, so it transfers across ped positions
    relZ = LiveCaptureCam.targetZ - (LiveCaptureCam.pedZ or 0.0),
  }
end

-- Re-apply remembered camera params to the current ped/capture (used to replay a
-- manual pose for the remaining textures). pedPos anchors the camera to where the
-- ped stands for this shot.
function ApplyLiveCaptureCamParams(params)
  if type(params) ~= 'table' then return false end
  local ped = PlayerPedId()
  local pPos = GetEntityCoords(ped)
  local relZ = tonumber(params.relZ)
  local targetZ = relZ and (pPos.z + relZ) or (tonumber(params.targetZ) or (pPos.z + 0.25))
  LiveCaptureCam = {
    pedX = pPos.x, pedY = pPos.y, pedZ = pPos.z,
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
-- Capture-camera overrides (tuned live in the clothing admin panel)
-- RuntimeCaptureCameras is filled from the DB (server) and by the admin sliders.
-- Capture reads GetCaptureCameraConfig() so tuned values apply without a restart.
--========================================================
RuntimeCaptureCameras = RuntimeCaptureCameras or {}

function GetCaptureCameraConfig(category)
  category = tostring(category or ''):lower()
  local override = RuntimeCaptureCameras[category]
  if type(override) == 'table' and override.dist and override.z and override.fov then
    return override
  end
  return Config.IconCapture and Config.IconCapture.captureCameras and Config.IconCapture.captureCameras[category] or nil
end

local function captureBaseHeading()
  local studio = Config.AdminStudio and Config.AdminStudio.StudioCoords
  return (studio and studio.w) or GetEntityHeading(PlayerPedId())
end

-- Push the effective per-category cameras (defaults merged with overrides) to the UI.
function SendCaptureCamerasToNui()
  local cams = {}
  local defaults = (Config.IconCapture and Config.IconCapture.captureCameras) or {}
  for cat, cfg in pairs(defaults) do
    cams[cat] = { dist = cfg.dist, z = cfg.z, fov = cfg.fov, overridden = false }
  end
  for cat, cfg in pairs(RuntimeCaptureCameras) do
    if type(cfg) == 'table' then
      cams[cat] = { dist = cfg.dist, z = cfg.z, fov = cfg.fov, overridden = true }
    end
  end
  SendNUIMessage({ type = 'captureCameras', cameras = cams })
end

RegisterNetEvent('nvCloth:client:captureCameras', function(overrides)
  RuntimeCaptureCameras = {}
  if type(overrides) == 'table' then
    for cat, cfg in pairs(overrides) do
      if type(cfg) == 'table' and cfg.dist and cfg.z and cfg.fov then
        RuntimeCaptureCameras[tostring(cat):lower()] = {
          dist = cfg.dist + 0.0, z = cfg.z + 0.0, fov = cfg.fov + 0.0,
        }
      end
    end
  end
  SendCaptureCamerasToNui()
end)

-- Live preview: move the browsing camera so the admin sees the framing on the
-- real ped as they drag the sliders (this is the live preview, not the capture).
RegisterNUICallback('previewCaptureCamera', function(data, cb)
  data = type(data) == 'table' and data or {}
  local cfg = { dist = tonumber(data.dist), z = tonumber(data.z), fov = tonumber(data.fov) }
  if cfg.dist and cfg.z and cfg.fov and CreateSkinCamCaptureConfig then
    CreateSkinCamCaptureConfig(cfg, captureBaseHeading(), 0.0)
  end
  cb({ success = true })
end)

RegisterNUICallback('saveCaptureCamera', function(data, cb)
  data = type(data) == 'table' and data or {}
  local category = tostring(data.category or ''):lower()
  local cfg = { dist = tonumber(data.dist), z = tonumber(data.z), fov = tonumber(data.fov) }
  if category ~= '' and cfg.dist and cfg.z and cfg.fov then
    RuntimeCaptureCameras[category] = cfg -- apply locally immediately
    TriggerServerEvent('nvCloth:server:saveCaptureCamera', {
      category = category, dist = cfg.dist, z = cfg.z, fov = cfg.fov,
    })
  end
  cb({ success = true })
end)

RegisterNUICallback('resetCaptureCamera', function(data, cb)
  data = type(data) == 'table' and data or {}
  local category = tostring(data.category or ''):lower()
  if category ~= '' then
    RuntimeCaptureCameras[category] = nil
    TriggerServerEvent('nvCloth:server:resetCaptureCamera', category)
  end
  cb({ success = true })
end)

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
      face = { dist = 1.25, z = 0.68, fov = 18.0 },
      head = { dist = 1.65, z = 0.78, fov = 24.0 },
      body = { dist = 3.25, z = 0.25, fov = 32.0 },
      feet = { dist = 2.15, z = -0.55, fov = 38.0 },
    }
    local cfg = fixed[preset] or fixed.body
    dist = cfg.dist
    targetZ = pPos.z + cfg.z
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

  local fov = CAM_PRESET[preset].fov or 30.0

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
  isBusy = false
  useFixedShopCamera = false
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
  CreateSkinCam(preset)
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
