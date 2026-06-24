--========================================================
-- Skin Camera Manager (CLEAN)
-- - Smooth preset cameras around the player (face/body/feet)
-- - Collision-aware placement to avoid walls/props
-- - NUI callbacks: changeCamera, rotateCamera
--========================================================

-- Presets (only FOV is used; positions are computed around the player)
local CAM_PRESET = {
  face = { fov = 10.0 },
  head = { fov = 24.0 },
  body = { fov = 30.0 },
  feet = { fov = 40.0 },
}

-- State
local isBusy = false
local skinCam = nil        -- camera handle
local createdCams = {}
local currentPreset = nil  -- "face" | "head" | "body" | "feet"
local useFixedShopCamera = false
local rememberCam

function SetShopCameraFixedMode(enabled)
  useFixedShopCamera = enabled == true
end


local function fixedCameraConfig(preset)
  local fixed = {
    face = { dist = 1.25, z = 0.68, fov = 18.0 },
    head = { dist = 1.65, z = 0.78, fov = 24.0 },
    body = { dist = 3.25, z = 0.25, fov = 32.0 },
    feet = { dist = 2.15, z = -0.55, fov = 38.0 },
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

  setOrMoveSkinCam(camPos, vector3(pPos.x, pPos.y, targetZ), cfg.fov or CAM_PRESET[preset].fov or 32.0, true)
end

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
