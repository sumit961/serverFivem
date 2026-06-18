--========================================================
-- Skin Camera Manager (CLEAN)
-- - Smooth preset cameras around the player (face/body/feet)
-- - Collision-aware placement to avoid walls/props
-- - NUI callbacks: changeCamera, rotateCamera
--========================================================

-- Presets (only FOV is used; positions are computed around the player)
local CAM_PRESET = {
  face = { fov = 10.0 },
  body = { fov = 30.0 },
  feet = { fov = 40.0 },
}

-- State
local isBusy = false
local skinCam = nil        -- camera handle
local currentPreset = nil  -- "face" | "body" | "feet"

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
  elseif preset == "body" then
    targetZ = pPos.z
  else -- "feet"
    dist = dist - 2.0
    targetZ = pPos.z - 0.5
  end

  -- Try to find a collision-free position
  local camPos = FindSafeCamPos(pPos, pHeading, dist, targetZ)

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

  -- Make the ped face the camera
  local faceHeading = (GetHeadingFromVector_2d(pPos.x - camPos.x, pPos.y - camPos.y) + 180.0) % 360.0
  TaskAchieveHeading(ped, faceHeading, 1000)

  local fov = CAM_PRESET[preset].fov or 30.0

  if skinCam then
    -- Smoothly interpolate to a new camera
    local newCam = CreateCamWithParams(
      "DEFAULT_SCRIPTED_CAMERA",
      camPos.x, camPos.y, camPos.z,
      0.0, 0.0, 0.0,
      fov,
      false, 0
    )
    PointCamAtCoord(newCam, pPos.x, pPos.y, targetZ)
    SetCamActiveWithInterp(newCam, skinCam, 2000, true, true)
    skinCam = newCam
  else
    -- First-time camera creation
    skinCam = CreateCamWithParams(
      "DEFAULT_SCRIPTED_CAMERA",
      camPos.x, camPos.y, camPos.z,
      0.0, 0.0, 0.0,
      fov,
      false, 0
    )
    PointCamAtCoord(skinCam, pPos.x, pPos.y, targetZ)
    SetCamActive(skinCam, true)
    RenderScriptCams(true, false, 2000, true, true)
  end
end

--- Destroy the skin camera and stop rendering.
function DestroySkinCam()
  if skinCam then
    DestroyCam(skinCam, true)
    skinCam = nil
    currentPreset = nil
    RenderScriptCams(false, false, 0, true, true)
  end
end

--========================================================
-- NUI Callbacks
--========================================================

RegisterNUICallback("changeCamera", function(data, cb)
  if isBusy then
    cb({ success = false })
    return
  end
  isBusy = true

  local preset = tostring(data.camera or "")
  if preset ~= currentPreset then
    CreateSkinCam(preset)
  end

  CreateThread(function()
    Wait(1000)
    isBusy = false
  end)

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
  TaskAchieveHeading(ped, heading, 1000)

  CreateThread(function()
    Wait(1000)
    isBusy = false
  end)

  cb({ success = true })
end)

--========================================================
-- OPTIONAL: expose destroy if UI or flow needs to exit camera mode
--========================================================
-- exports("destroySkinCam", DestroySkinCam)
