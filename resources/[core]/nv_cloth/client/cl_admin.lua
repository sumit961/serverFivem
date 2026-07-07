--========================================================
-- nvCloth Admin Studio
-- Clean admin preview/capture environment:
-- - base underwear outfit only
-- - props/weapons cleared
-- - reference mannequin/NPC beside player
-- - real configurable green airport backdrop prop for admin capture
-- - DrawBox fallback only if the prop cannot load
--========================================================

local studio = {
  active = false,
  refPed = nil,
  backdropActive = false,
  backdropProps = {},
  backdropLayout = {},
  fallbackDrawBox = false,
  testProps = {},
  envApplied = false,
  appearanceSnapshot = nil,
  backdropMode = 'green',
  forceBackdropDrawBox = false,
  captureWallHeading = nil,
  -- Live greenscreen tuning (set by /vehgreen* commands). These feed BOTH the
  -- live tuning prop and the real capture backdrop so what you tune is what
  -- capture uses. Defaults come from Config.AdminStudio.Backdrop.
  greenTune = nil,        -- { scale, zOffset } once initialised
  greenTuneProp = nil,    -- handle of the single live tuning prop from /vehgreen
}

local function notify(msg, typ)
  msg = tostring(msg or '')
  typ = typ or 'info'
  TriggerEvent('cm-hud:client:notify', msg, typ)
  TriggerEvent('chat:addMessage', { color = { 0, 255, 0 }, multiline = false, args = { 'nv_cloth', msg } })
end

local function loadModel(model, timeoutMs)
  timeoutMs = timeoutMs or 3000
  local hash = type(model) == 'number' and model or GetHashKey(tostring(model))
  if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
  RequestModel(hash)
  local endAt = GetGameTimer() + timeoutMs
  while not HasModelLoaded(hash) and GetGameTimer() < endAt do Wait(0) end
  if not HasModelLoaded(hash) then return nil end
  return hash
end

local function deleteEntity(ent)
  if ent and ent ~= 0 and DoesEntityExist(ent) then
    SetEntityAsMissionEntity(ent, true, true)
    DeleteEntity(ent)
  end
end

local function clearBackdropProps()
  for i = #studio.backdropProps, 1, -1 do
    deleteEntity(studio.backdropProps[i])
    studio.backdropProps[i] = nil
  end
  studio.backdropLayout = {}
end

--========================================================
-- Live greenscreen tuning (scale + vertical offset)
-- Shared by the /vehgreen* commands and the real capture backdrop so tuning is
-- live and 1:1 with what capture produces.
--========================================================
local function greenTune()
  if not studio.greenTune then
    local cfg = (Config.AdminStudio and Config.AdminStudio.Backdrop) or {}
    studio.greenTune = {
      scale = tonumber(cfg.scale) or 1.0,
      zOffset = tonumber(cfg.tuneZOffset) or 0.0,
    }
  end
  return studio.greenTune
end

-- Apply the current tuned scale to a greenscreen prop.
-- GTA/FiveM has no SetEntityScale native, so we scale the prop's world matrix.
-- IMPORTANT: SetEntityMatrix expects the basis in (right, forward, up) order, and
-- FiveM's GetEntityMatrix returns them in that same order when captured as
-- (right, forward, up, pos). We keep that exact order — swapping forward/right
-- would tilt the flat greenscreen edge-on to the camera and make it "vanish".
local function scaleVec(v, s)
  local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if len < 0.0001 then return vector3(0.0, 0.0, 0.0) end
  return vector3((v.x / len) * s, (v.y / len) * s, (v.z / len) * s)
end

local function applyGreenScale(ent)
  if not ent or ent == 0 or not DoesEntityExist(ent) then return end
  local t = greenTune()
  local scale = tonumber(t.scale) or 1.0
  if scale <= 0 then scale = 1.0 end

  if type(GetEntityMatrix) ~= 'function' or type(SetEntityMatrix) ~= 'function' then
    return
  end

  local ok, right, forward, up, pos = pcall(GetEntityMatrix, ent)
  if not ok or not right or not forward or not up or not pos then return end

  local r = scaleVec(right, scale)
  local f = scaleVec(forward, scale)
  local u = scaleVec(up, scale)

  pcall(SetEntityMatrix, ent,
    r.x, r.y, r.z,
    f.x, f.y, f.z,
    u.x, u.y, u.z,
    pos.x, pos.y, pos.z)
end

-- Re-apply scale + z to every currently spawned backdrop tile and the live prop.
local function refreshGreenTuning()
  for _, ent in ipairs(studio.backdropProps) do
    applyGreenScale(ent)
  end
  if studio.greenTuneProp and studio.greenTuneProp ~= 0 and DoesEntityExist(studio.greenTuneProp) then
    applyGreenScale(studio.greenTuneProp)
  end
end


local function getGender()
  return GetEntityModel(PlayerPedId()) == `mp_f_freemode_01` and 'female' or 'male'
end

local function clearHeadOverlays(ped)
  for i = 0, 12 do
    SetPedHeadOverlay(ped, i, 0, 0.0)
  end
  SetPedEyeColor(ped, 0)
  SetPedHairColor(ped, 0, 0)
  SetPedHeadOverlayColor(ped, 1, 1, 0, 0)
  SetPedHeadOverlayColor(ped, 2, 1, 0, 0)
  SetPedHeadOverlayColor(ped, 10, 1, 0, 0)
  SetPedHeadOverlayColor(ped, 11, 1, 0, 0)
  SetPedFaceFeature(ped, 19, 0.0)
  SetPedFaceFeature(ped, 20, 0.0)
end

local function saveAdminAppearanceSnapshot(ped)
  local snap = { components = {}, props = {}, overlays = {}, faceFeatures = {} }
  for i = 0, 11 do
    snap.components[i] = {
      drawable = GetPedDrawableVariation(ped, i),
      texture = GetPedTextureVariation(ped, i),
      palette = GetPedPaletteVariation(ped, i),
    }
  end
  for i = 0, 12 do
    snap.props[i] = {
      drawable = GetPedPropIndex(ped, i),
      texture = GetPedPropTextureIndex(ped, i),
    }
  end
  snap.hairColor = GetPedHairColor(ped)
  snap.hairHighlight = GetPedHairHighlightColor(ped)
  snap.eyeColor = GetPedEyeColor(ped)
  for i = 0, 12 do
    local ok, value, colourType, firstColour, secondColour, opacity = GetPedHeadOverlayData(ped, i)
    snap.overlays[i] = {
      ok = ok == true,
      value = tonumber(value) or 0,
      colourType = tonumber(colourType) or 0,
      firstColour = tonumber(firstColour) or 0,
      secondColour = tonumber(secondColour) or 0,
      opacity = tonumber(opacity) or 0.0,
    }
  end
  for i = 0, 19 do
    snap.faceFeatures[i] = GetPedFaceFeature(ped, i) or 0.0
  end
  studio.appearanceSnapshot = snap
end

local function restoreAdminAppearanceSnapshot(ped)
  local snap = studio.appearanceSnapshot
  if type(snap) ~= 'table' then return end
  for i = 0, 11 do
    local c = snap.components[i]
    if c then SetPedComponentVariation(ped, i, c.drawable or 0, c.texture or 0, c.palette or 0) end
  end
  for i = 0, 12 do
    local pr = snap.props[i]
    if pr then
      if tonumber(pr.drawable) and tonumber(pr.drawable) >= 0 then
        SetPedPropIndex(ped, i, tonumber(pr.drawable), tonumber(pr.texture) or 0, true)
      else
        ClearPedProp(ped, i)
      end
    end
  end
  if snap.hairColor ~= nil then SetPedHairColor(ped, tonumber(snap.hairColor) or 0, tonumber(snap.hairHighlight) or 0) end
  if snap.eyeColor ~= nil then SetPedEyeColor(ped, tonumber(snap.eyeColor) or 0) end
  for i = 0, 12 do
    local o = snap.overlays[i]
    if o then
      SetPedHeadOverlay(ped, i, o.value or 0, o.opacity or 0.0)
      SetPedHeadOverlayColor(ped, i, o.colourType or 0, o.firstColour or 0, o.secondColour or 0)
    end
  end
  for i = 0, 19 do
    if snap.faceFeatures[i] ~= nil then SetPedFaceFeature(ped, i, snap.faceFeatures[i]) end
  end
  studio.appearanceSnapshot = nil
end

local function lockPedNoLife(ped)
  ClearPedTasksImmediately(ped)
  TaskStandStill(ped, -1)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  SetPedCanRagdoll(ped, false)
  SetPedCanPlayAmbientAnims(ped, false)
  SetPedCanPlayAmbientBaseAnims(ped, false)
end

local function applyAdminStudioEnvironment()
  -- Force a bright, clean capture scene for admin preview and icon capture.
  NetworkOverrideClockTime(12, 0, 0)
  ClearOverrideWeather()
  ClearWeatherTypePersist()
  SetWeatherTypeNow('EXTRASUNNY')
  SetWeatherTypeNowPersist('EXTRASUNNY')
  SetWeatherTypePersist('EXTRASUNNY')
  SetArtificialLightsState(false)
  SetArtificialLightsStateAffectsVehicles(false)
  ClearTimecycleModifier()
  SetTimecycleModifier('neutral')
  SetTimecycleModifierStrength(0.0)
  SetPedAoBlobRendering(PlayerPedId(), false)
  studio.envApplied = true
end

local function clearAdminStudioEnvironment()
  if not studio.envApplied then return end
  ClearOverrideWeather()
  ClearWeatherTypePersist()
  ClearTimecycleModifier()
  NetworkClearClockTimeOverride()
  SetPedAoBlobRendering(PlayerPedId(), true)
  studio.envApplied = false
end

local function applyCleanBaseOutfit(ped)
  -- Freemode-safe base outfit. It is only for admin preview and is restored on close by cl_shop snapshot.
  local female = GetEntityModel(ped) == `mp_f_freemode_01`
  ClearPedTasksImmediately(ped)
  RemoveAllPedWeapons(ped, true)
  for i = 0, 12 do ClearPedProp(ped, i) end

  -- Strip the admin preview ped to a clean default freemode look: no hair, no makeup, no props.
  SetPedComponentVariation(ped, 2, 0, 0, 0) -- hair
  clearHeadOverlays(ped)

  if female then
    SetPedComponentVariation(ped, 1, 0, 0, 0)
    SetPedComponentVariation(ped, 3, 15, 0, 0) -- arms/body
    SetPedComponentVariation(ped, 4, 15, 0, 0) -- base legs/underwear fallback
    SetPedComponentVariation(ped, 6, 35, 0, 0) -- bare feet fallback
    SetPedComponentVariation(ped, 8, 15, 0, 0) -- undershirt none
    SetPedComponentVariation(ped, 11, 15, 0, 0) -- top none
    SetPedComponentVariation(ped, 7, 0, 0, 0)
    SetPedComponentVariation(ped, 5, 0, 0, 0)
    SetPedComponentVariation(ped, 9, 0, 0, 0)
    SetPedComponentVariation(ped, 10, 0, 0, 0)
  else
    SetPedComponentVariation(ped, 1, 0, 0, 0)
    SetPedComponentVariation(ped, 3, 15, 0, 0)
    SetPedComponentVariation(ped, 4, 14, 0, 0)
    SetPedComponentVariation(ped, 6, 34, 0, 0)
    SetPedComponentVariation(ped, 8, 15, 0, 0)
    SetPedComponentVariation(ped, 11, 15, 0, 0)
    SetPedComponentVariation(ped, 7, 0, 0, 0)
    SetPedComponentVariation(ped, 5, 0, 0, 0)
    SetPedComponentVariation(ped, 9, 0, 0, 0)
    SetPedComponentVariation(ped, 10, 0, 0, 0)
  end

  lockPedNoLife(ped)
end

local function spawnReferencePed()
  deleteEntity(studio.refPed)
  studio.refPed = nil

  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)
  local h = GetEntityHeading(ped)
  local cfg = Config.AdminStudio or {}
  local requested = cfg.ReferencePedModel
  if requested == false or requested == nil or tostring(requested):lower() == 'none' then return end

  local hash
  if requested == 'same_as_player' then
    hash = GetEntityModel(ped)
    RequestModel(hash)
    local endAt = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < endAt do Wait(0) end
  else
    hash = loadModel(requested)
    if not hash or not IsModelAPed(hash) then
      hash = loadModel(getGender() == 'female' and 'mp_f_freemode_01' or 'mp_m_freemode_01')
    end
  end

  if not hash then return end

  local side = cfg.ReferenceOffset or vector3(1.15, 0.20, 0.0)
  local rad = math.rad(h)
  local x = p.x + math.cos(rad) * side.x - math.sin(rad) * side.y
  local y = p.y + math.sin(rad) * side.x + math.cos(rad) * side.y
  local z = p.z + side.z

  studio.refPed = CreatePed(4, hash, x, y, z, h, false, true)
  if studio.refPed and studio.refPed ~= 0 then
    SetEntityAsMissionEntity(studio.refPed, true, true)
    SetEntityInvincible(studio.refPed, true)
    FreezeEntityPosition(studio.refPed, true)
    SetBlockingOfNonTemporaryEvents(studio.refPed, true)
    SetPedCanRagdoll(studio.refPed, false)
    SetPedAoBlobRendering(studio.refPed, false)
    TaskStandStill(studio.refPed, -1)
    applyCleanBaseOutfit(studio.refPed)
  end

  SetModelAsNoLongerNeeded(hash)
end

local function backdropConfig()
  local admin = Config.AdminStudio or {}
  local backdrop = admin.Backdrop or {}
  local legacyWall = Config.IconCapture and Config.IconCapture.wall or {}
  return backdrop, legacyWall
end

local function currentBackdropPalette()
  local palettes = {
    green = { r = 0, g = 255, b = 0, a = 255 },
    blue = { r = 40, g = 130, b = 255, a = 255 },
    magenta = { r = 255, g = 0, b = 255, a = 255 },
    pink = { r = 255, g = 0, b = 255, a = 255 },
    white = { r = 255, g = 255, b = 255, a = 255 },
    black = { r = 5, g = 5, b = 5, a = 255 },
  }
  return palettes[tostring(studio.backdropMode or 'green'):lower()] or palettes.green
end

local function refreshBackdropVisibility()
  local mode = tostring(studio.backdropMode or 'green'):lower()
  local preferDrawBox = studio.forceBackdropDrawBox == true or (mode ~= 'green' and mode ~= 'none')
  local showProps = (mode == 'green') and (not preferDrawBox) and #studio.backdropProps > 0
  for _, ent in ipairs(studio.backdropProps) do
    if ent and ent ~= 0 and DoesEntityExist(ent) then
      SetEntityVisible(ent, showProps, false)
      SetEntityAlpha(ent, showProps and 255 or 0, false)
    end
  end
  studio.fallbackDrawBox = (mode ~= 'none') and (preferDrawBox or (#studio.backdropProps == 0 and mode == 'green'))
end

local function vectorComponent(v, key, index, default)
  if type(v) ~= 'vector3' and type(v) ~= 'vector4' and type(v) ~= 'table' then return default end
  return tonumber(v[key] or v[index]) or default
end

-- Place one greenscreen prop tile. The backdrop is enlarged by tiling copies of
-- the same prop in a grid: `col` shifts sideways (left/right of centre), `row`
-- shifts backwards (behind the fixed wall). This roughly doubles the green field
-- so it fills the whole screenshot from any capture angle, ground included.
local function placeBackdropProp(ent, col, row)
  if not ent or ent == 0 or not DoesEntityExist(ent) then return end

  local ped = PlayerPedId()
  local cfg = (Config.AdminStudio and Config.AdminStudio.Backdrop) or {}
  local fixed = cfg.fixedCoords
  col = tonumber(col) or 0.0
  row = tonumber(row) or 0.0

  -- Spacing between tiles. Keep it a touch under the prop width so tiles overlap
  -- slightly and leave no gap/seam in the green.
  local sideSpacing = tonumber(cfg.tileSpacing) or tonumber(cfg.spacing) or 2.6
  local backSpacing = tonumber(cfg.tileDepthSpacing) or sideSpacing

  local bx, by, bz, heading
  if fixed and fixed.x and fixed.y and fixed.z then
    bx = fixed.x
    by = fixed.y
    bz = fixed.z
    heading = tonumber(fixed.w) or 0.0
  else
    local pos = GetEntityCoords(ped)
    heading = GetEntityHeading(ped)
    local rad = math.rad(heading)
    local distance = tonumber(cfg.distanceBehindPed) or 1.05
    local zOffset = tonumber(cfg.zOffset) or 0.45
    bx = pos.x + math.sin(rad) * distance
    by = pos.y - math.cos(rad) * distance
    bz = pos.z + zOffset
  end

  -- Sideways offset (perpendicular to the wall heading): widens the back wall so
  -- side/rotated shots stay on green. This never moves toward the ped.
  local sideRad = math.rad(heading + 90.0)
  local sx = math.cos(sideRad) * col * sideSpacing
  local sy = math.sin(sideRad) * col * sideSpacing

  -- Depth offset: extra rows must push AWAY from the player, never in front of
  -- them. Derive the "behind" direction from the ped→prop vector so tiles always
  -- stack behind the wall regardless of the prop's own heading.
  local bxo, byo = 0.0, 0.0
  if row and row > 0 then
    local studio = Config.AdminStudio and Config.AdminStudio.StudioCoords
    local awayX, awayY
    if studio and studio.x and studio.y then
      awayX = bx - studio.x
      awayY = by - studio.y
    else
      local pos = GetEntityCoords(ped)
      awayX = bx - pos.x
      awayY = by - pos.y
    end
    local len = math.sqrt(awayX * awayX + awayY * awayY)
    if len > 0.01 then
      awayX, awayY = awayX / len, awayY / len
      bxo = awayX * row * backSpacing
      byo = awayY * row * backSpacing
    end
  end

  -- Apply the live-tuned vertical offset (from /vehgreenup / /vehgreendown) so
  -- nudging the greenscreen moves the real capture backdrop too.
  local tunedZ = tonumber(greenTune().zOffset) or 0.0

  SetEntityCoordsNoOffset(ent, bx + sx + bxo, by + sy + byo, bz + tunedZ, false, false, false)
  SetEntityHeading(ent, (heading + (tonumber(cfg.headingOffset) or 0.0)) % 360.0)

  local rot = cfg.rotation or vector3(90.0, 0.0, 0.0)
  local rx = vectorComponent(rot, 'x', 1, 90.0)
  local ry = vectorComponent(rot, 'y', 2, 0.0)
  local rz = (heading + (tonumber(cfg.headingOffset) or 0.0) + vectorComponent(rot, 'z', 3, 0.0)) % 360.0
  SetEntityRotation(ent, rx, ry, rz, 2, true)
end

-- Camera-aware backdrop: a solid, unlit colour quad placed just behind the item
-- along the CAPTURE camera's view axis and sized to overfill its FOV. Because it
-- follows the actual capture camera, it stays behind the item for tight, low, and
-- side/rotated shots (glasses, shoes, watch, bags) — not just full-body outerwear.
-- A flat colour keys more cleanly than a shaded prop, so this works for every
-- colour including green.
local function drawCameraAwareWall(r, g, b, a)
  local geom = CaptureCamGeom
  if not geom or not geom.cam or not geom.target then return false end
  local cam, tgt = geom.cam, geom.target

  local fx, fy, fz = tgt.x - cam.x, tgt.y - cam.y, tgt.z - cam.z
  local flen = math.sqrt(fx * fx + fy * fy + fz * fz)
  if flen < 0.01 then return false end
  fx, fy, fz = fx / flen, fy / flen, fz / flen

  -- right = forward x worldUp ; up = right x forward
  local rx = fy * 1.0 - fz * 0.0
  local ry = fz * 0.0 - fx * 1.0
  local rz = fx * 0.0 - fy * 0.0
  local rlen = math.sqrt(rx * rx + ry * ry + rz * rz)
  if rlen < 0.001 then rx, ry, rz, rlen = 1.0, 0.0, 0.0, 1.0 end
  rx, ry, rz = rx / rlen, ry / rlen, rz / rlen
  local upx = ry * fz - rz * fy
  local upy = rz * fx - rx * fz
  local upz = rx * fy - ry * fx

  local fov = tonumber(geom.fov) or 34.0
  local backMargin = 0.85                       -- how far behind the item the wall sits
  local depth = flen + backMargin
  local halfH = math.tan(math.rad(fov * 0.5)) * depth * 1.9  -- overfill vertically
  local halfW = halfH * 2.0                                  -- and horizontally (wide aspect)

  local cx = tgt.x + fx * backMargin
  local cy = tgt.y + fy * backMargin
  local cz = tgt.z + fz * backMargin

  local function corner(sw, sh)
    return cx + rx * halfW * sw + upx * halfH * sh,
           cy + ry * halfW * sw + upy * halfH * sh,
           cz + rz * halfW * sw + upz * halfH * sh
  end
  local tlx, tly, tlz = corner(-1,  1)
  local trx, try_, trz = corner( 1,  1)
  local brx, bry, brz = corner( 1, -1)
  local blx, bly, blz = corner(-1, -1)

  -- Two triangles, drawn both windings so the wall is opaque from either side.
  DrawPoly(tlx, tly, tlz, trx, try_, trz, brx, bry, brz, r, g, b, a)
  DrawPoly(tlx, tly, tlz, brx, bry, brz, blx, bly, blz, r, g, b, a)
  DrawPoly(brx, bry, brz, trx, try_, trz, tlx, tly, tlz, r, g, b, a)
  DrawPoly(blx, bly, blz, brx, bry, brz, tlx, tly, tlz, r, g, b, a)
  return true
end

local function drawFallbackGreenWall()
  local _, cfg = backdropConfig()
  if cfg.enabled == false then return end

  local ped = PlayerPedId()
  local mode = tostring(studio.backdropMode or 'green'):lower()
  if mode == 'none' then return end
  local palette = currentBackdropPalette()
  local r = palette.r or tonumber(cfg.r) or 0
  local g = palette.g or tonumber(cfg.g) or 255
  local b = palette.b or tonumber(cfg.b) or 0
  local a = palette.a or tonumber(cfg.a) or 255

  -- Preferred path during capture: a camera-aware quad that always fills the frame,
  -- for every colour. Falls through to the legacy world DrawBox only when no
  -- capture camera geometry is available (e.g. live browsing preview).
  if drawCameraAwareWall(r, g, b, a) then return end

  local pedPos = GetEntityCoords(ped)
  -- For capture, keep the generated colour wall locked to the camera/studio heading.
  -- This prevents blue/magenta/white/black walls moving away when the ped is rotated
  -- for bags, watches, earrings, or side captures.
  local heading = tonumber(studio.captureWallHeading) or GetEntityHeading(ped)
  local rad = math.rad(heading)

  -- Bigger generated wall and farther distance so arms/hands never clip into the wall.
  local width = tonumber(cfg.width) or 7.5
  if width < 7.5 then width = 7.5 end
  local height = tonumber(cfg.height) or 4.8
  if height < 4.8 then height = 4.8 end
  local thickness = tonumber(cfg.thickness) or 0.12
  if thickness < 0.12 then thickness = 0.12 end
  local back = tonumber(cfg.colorWallDistanceBehindPed) or 2.35
  local bx, by, minZ, maxZ

  if mode == 'green' then
    -- Green uses prop normally. This path is only the fallback if the prop fails.
    local fixed = Config.AdminStudio and Config.AdminStudio.Backdrop and Config.AdminStudio.Backdrop.fixedCoords
    if fixed and fixed.x and fixed.y and fixed.z then
      bx = fixed.x
      by = fixed.y
      minZ = fixed.z - 1.25
      maxZ = fixed.z + height
      heading = tonumber(fixed.w) or heading
      rad = math.rad(heading)
    else
      local forwardX = -math.sin(rad)
      local forwardY = math.cos(rad)
      bx = pedPos.x - forwardX * back
      by = pedPos.y - forwardY * back
      minZ = pedPos.z - 1.25
      maxZ = pedPos.z + height
    end
  else
    -- Non-green backgrounds ignore the fixed green prop position.
    -- Put the generated wall behind the player's back, not through the player's arms.
    local forwardX = -math.sin(rad)
    local forwardY = math.cos(rad)
    bx = pedPos.x - forwardX * back
    by = pedPos.y - forwardY * back
    minZ = pedPos.z - 1.25
    maxZ = pedPos.z + height
  end

  local h = (heading % 360.0)
  if (h > 45.0 and h < 135.0) or (h > 225.0 and h < 315.0) then
    DrawBox(bx - thickness, by - width / 2.0, minZ, bx + thickness, by + width / 2.0, maxZ, r, g, b, a)
  else
    DrawBox(bx - width / 2.0, by - thickness, minZ, bx + width / 2.0, by + thickness, maxZ, r, g, b, a)
  end
end

local function startBackdropLoop()
  if studio.backdropActive then return end
  studio.backdropActive = true

  CreateThread(function()
    while studio.backdropActive do
      if studio.fallbackDrawBox then
        -- DrawBox must still render even when hidden green prop entities exist.
        drawFallbackGreenWall()
        Wait(0)
      elseif #studio.backdropProps > 0 then
        -- The backdrop props are frozen and never move on their own, so there is
        -- no need to re-place or re-scale them every cycle. Re-placing them here
        -- (SetEntityRotation + re-scale) caused a visible per-cycle flicker. Just
        -- idle; spawn/tuning already positioned and scaled them.
        Wait(500)
      else
        Wait(250)
      end
    end
  end)
end

local function spawnBackdropProps()
  clearBackdropProps()
  studio.fallbackDrawBox = false

  local cfg = (Config.AdminStudio and Config.AdminStudio.Backdrop) or {}
  if cfg.enabled == false then return end

  local hash = loadModel(cfg.model or 'cs_dry_ice_freezer_floor', 3500)
  if not hash then
    studio.fallbackDrawBox = cfg.fallbackDrawBox ~= false
    print(('[nv_cloth] Admin backdrop model failed to load: %s. Fallback DrawBox: %s'):format(tostring(cfg.model), tostring(studio.fallbackDrawBox)))
    return
  end

  -- Build a grid of tiles so the green field is roughly 2x the single prop and
  -- wraps behind + to the sides. cols spread left/right, rows push backwards.
  local cols = math.floor(tonumber(cfg.tileCols) or 3)
  local rows = math.floor(tonumber(cfg.tileRows) or 2)
  if cols < 1 then cols = 1 end
  if cols > 6 then cols = 6 end
  if rows < 1 then rows = 1 end
  if rows > 4 then rows = 4 end

  -- Backwards compatibility: if an old config still sets `pieces`, use it as cols
  -- and keep a single row unless tileRows was explicitly provided.
  if cfg.pieces and not cfg.tileCols then
    cols = math.max(1, math.min(6, math.floor(tonumber(cfg.pieces) or cols)))
    if not cfg.tileRows then rows = 1 end
  end

  local colOffsets = {}
  for c = 1, cols do colOffsets[c] = c - ((cols + 1) / 2.0) end  -- centre the row

  for r = 0, rows - 1 do
    for c = 1, cols do
      -- Create the object directly at its final world position (not at 0,0,0 then
      -- moved). Spawning at the origin and teleporting can leave a non-networked
      -- prop unstreamed at its real location, which makes it flicker then vanish.
      local obj = CreateObjectNoOffset(hash, 0.0, 0.0, 0.0, false, false, false)
      if obj and obj ~= 0 then
        SetEntityAsMissionEntity(obj, true, true)
        SetEntityCollision(obj, cfg.collision == true, cfg.collision == true)
        FreezeEntityPosition(obj, true)
        SetEntityAlpha(obj, 255, false)
        SetEntityLodDist(obj, 1000)
        studio.backdropProps[#studio.backdropProps + 1] = obj
        studio.backdropLayout[#studio.backdropProps] = { col = colOffsets[c], row = r }
        placeBackdropProp(obj, colOffsets[c], r)
        applyGreenScale(obj)
      end
    end
  end

  SetModelAsNoLongerNeeded(hash)

  if #studio.backdropProps == 0 then
    studio.fallbackDrawBox = cfg.fallbackDrawBox ~= false
    print('[nv_cloth] Admin backdrop object creation failed. Using DrawBox fallback.')
  end

  refreshBackdropVisibility()
end

local function stopGreenWall()
  studio.backdropActive = false
  studio.fallbackDrawBox = false
  clearBackdropProps()
end

local function clearTestProps()
  for i = #studio.testProps, 1, -1 do
    deleteEntity(studio.testProps[i])
    studio.testProps[i] = nil
  end
end

local function modelNameFromArg(model)
  model = tostring(model or ''):gsub('`', ''):gsub('"', ''):gsub("'", '')
  model = model:gsub('^%s+', ''):gsub('%s+$', '')
  if model == '' then
    local cfg = (Config.AdminStudio and Config.AdminStudio.Backdrop) or {}
    model = tostring(cfg.model or 'prop_ld_greenscreen_01')
  end
  return model
end

local function spawnTestProp(model)
  model = modelNameFromArg(model)
  local hash = loadModel(model, 5000)
  if not hash then
    print(('[nv_cloth] /cmtestprop failed. Model not valid/loaded: %s'):format(model))
    print('[nv_cloth] Put prop_ld_greenscreen_01.ydr inside nv_cloth/stream/ and restart nv_cloth. If it is a fully custom prop, you also need a matching .ytyp archetype.')
    notify(('Prop failed: %s. Check F8 and your stream folder.'):format(model), 'error')
    return
  end

  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)
  local h = GetEntityHeading(ped)
  local rad = math.rad(h)

  -- Spawn directly in front of the player so admins can visually confirm the stream works.
  local distance = 2.3
  local x = p.x - math.sin(rad) * distance
  local y = p.y + math.cos(rad) * distance
  local z = p.z

  local obj = CreateObjectNoOffset(hash, x, y, z, true, false, false)
  if not obj or obj == 0 or not DoesEntityExist(obj) then
    SetModelAsNoLongerNeeded(hash)
    print(('[nv_cloth] /cmtestprop CreateObject failed for model: %s'):format(model))
    notify(('CreateObject failed: %s'):format(model), 'error')
    return
  end

  SetEntityAsMissionEntity(obj, true, true)
  SetEntityHeading(obj, h)
  SetEntityCollision(obj, true, true)
  FreezeEntityPosition(obj, true)
  SetEntityAlpha(obj, 255, false)
  SetEntityLodDist(obj, 200)
  PlaceObjectOnGroundProperly(obj)

  studio.testProps[#studio.testProps + 1] = obj
  SetModelAsNoLongerNeeded(hash)

  local c = GetEntityCoords(obj)
  print(('[nv_cloth] Spawned test prop %s at vec4(%.4f, %.4f, %.4f, %.4f). Entity: %s'):format(model, c.x, c.y, c.z, GetEntityHeading(obj), tostring(obj)))
  notify(('Spawned test prop: %s. Use /cmclearprop to remove it.'):format(model), 'success')
end

function SetAdminCaptureBackdropMode(mode, wallHeading)
  studio.backdropMode = tostring(mode or 'none'):lower()
  if studio.backdropMode == '' then studio.backdropMode = 'none' end
  studio.captureWallHeading = tonumber(wallHeading)

  -- A wallHeading is only passed by the capture flow. During capture we use the
  -- camera-aware quad for EVERY colour (including green) so coverage is guaranteed
  -- for tight/low/side shots. While browsing we keep the physical green prop.
  local capturing = wallHeading ~= nil
  if studio.backdropMode == 'none' then
    CaptureCamGeom = nil
    studio.forceBackdropDrawBox = false
  elseif capturing then
    -- Green capture uses the real streamed greenscreen prop (floor + wall, both
    -- green). It is tiled/enlarged so it fills the whole screenshot frame from
    -- every capture angle. Other colours still use the generated flat wall.
    studio.forceBackdropDrawBox = (studio.backdropMode ~= 'green')
  else
    -- While browsing, green uses the physical prop; other colours use the flat wall.
    studio.forceBackdropDrawBox = (studio.backdropMode ~= 'green')
  end

  refreshBackdropVisibility()
  if studio.backdropMode == 'none' then
    print('[nv_cloth] Chroma wall mode: hidden while browsing.')
  elseif capturing then
    print(('[nv_cloth] Chroma wall mode: %s camera-aware wall for capture.'):format(studio.backdropMode))
  elseif studio.backdropMode ~= 'green' then
    print(('[nv_cloth] Chroma wall mode: %s DrawBox wall enabled, green prop hidden.'):format(studio.backdropMode))
  else
    print('[nv_cloth] Chroma wall mode: green prop enabled.')
  end
end

function EnsureAdminStudioGreenScreen()
  -- Kept as the public function name so cl_capture.lua stays compatible.
  spawnBackdropProps()
  refreshBackdropVisibility()
  startBackdropLoop()
end

function ResetClothingAdminPlayerToBase()
  local ped = PlayerPedId()
  if Config.AdminStudio and Config.AdminStudio.StudioCoords and Config.AdminStudio.LockPlayerToStudio ~= false then
    local room = Config.AdminStudio.StudioCoords
    SetEntityCoordsNoOffset(ped, room.x, room.y, room.z, false, false, false)
    if room.w then SetEntityHeading(ped, room.w) end
  end
  applyCleanBaseOutfit(ped)
end

function StartClothingAdminStudio()
  if studio.active then return end
  studio.active = true
  -- Keep capture backdrop hidden while admins browse items.
  -- It is shown only during image capture or when Preview Capture Wall is enabled in the UI.
  studio.backdropMode = 'none'
  studio.forceBackdropDrawBox = false
  local ped = PlayerPedId()
  saveAdminAppearanceSnapshot(ped)
  applyAdminStudioEnvironment()
  ResetClothingAdminPlayerToBase()
  spawnReferencePed()
  startBackdropLoop()
end

function StopClothingAdminStudio()
  studio.active = false
  stopGreenWall()
  deleteEntity(studio.refPed)
  studio.refPed = nil
  clearAdminStudioEnvironment()
  local ped = PlayerPedId()
  studio.backdropMode = 'none'
  studio.forceBackdropDrawBox = false
  restoreAdminAppearanceSnapshot(ped)
  SetPedCanPlayAmbientAnims(ped, true)
  SetPedCanPlayAmbientBaseAnims(ped, true)
  SetPedAoBlobRendering(ped, true)
end

RegisterNetEvent('nvCloth:client:testSpawnProp', function(model)
  spawnTestProp(model)
end)

RegisterNetEvent('nvCloth:client:clearTestProps', function()
  clearTestProps()
  notify('Cleared nv_cloth test props.', 'success')
end)

RegisterNetEvent('nvCloth:client:printPosition', function()
  local ped = PlayerPedId()
  local c = GetEntityCoords(ped)
  local h = GetEntityHeading(ped)
  local vec3Line = ('vec3(%.4f, %.4f, %.4f)'):format(c.x, c.y, c.z)
  local vec4Line = ('vec4(%.4f, %.4f, %.4f, %.4f)'):format(c.x, c.y, c.z, h)
  local rawLine = ('x = %.4f, y = %.4f, z = %.4f, heading = %.4f'):format(c.x, c.y, c.z, h)

  print('[nv_cloth] Current player position:')
  print('[nv_cloth] ' .. vec3Line)
  print('[nv_cloth] ' .. vec4Line)
  print('[nv_cloth] ' .. rawLine)
  notify(('Position printed in F8: %s'):format(vec4Line), 'success')
end)

--========================================================
-- Live greenscreen tuning commands (/vehgreen family)
-- Spawn and tune the REAL capture greenscreen prop in-game so you can dial in
-- scale, height and position, then copy the printed values into config.
--========================================================

-- Spawn a single live greenscreen prop where you're standing (or at the
-- configured fixedCoords). This is the same model used for capture, so what you
-- see is what capture uses once you copy the values into config.
local function spawnLiveGreenProp(useFixed)
  local cfg = (Config.AdminStudio and Config.AdminStudio.Backdrop) or {}
  local model = tostring(cfg.model or 'prop_ld_greenscreen_01')
  local hash = loadModel(model, 5000)
  if not hash then
    notify(('Greenscreen prop failed to load: %s. Check stream folder.'):format(model), 'error')
    print(('[nv_cloth] /vehgreen failed. Model not valid/loaded: %s'):format(model))
    return
  end

  -- Remove any previous live prop first.
  if studio.greenTuneProp and studio.greenTuneProp ~= 0 and DoesEntityExist(studio.greenTuneProp) then
    deleteEntity(studio.greenTuneProp)
    studio.greenTuneProp = nil
  end

  local ped = PlayerPedId()
  local px, py, pz, heading

  local fixed = cfg.fixedCoords
  if useFixed and fixed and fixed.x then
    px, py, pz, heading = fixed.x, fixed.y, fixed.z, tonumber(fixed.w) or 0.0
  else
    local p = GetEntityCoords(ped)
    heading = GetEntityHeading(ped)
    local rad = math.rad(heading)
    local distance = tonumber(cfg.distanceBehindPed) or 1.25
    px = p.x - math.sin(rad) * distance
    py = p.y + math.cos(rad) * distance
    pz = p.z
  end

  local tunedZ = tonumber(greenTune().zOffset) or 0.0
  local obj = CreateObjectNoOffset(hash, px, py, pz + tunedZ, false, false, false)
  if not obj or obj == 0 or not DoesEntityExist(obj) then
    SetModelAsNoLongerNeeded(hash)
    notify(('CreateObject failed: %s'):format(model), 'error')
    return
  end

  SetEntityAsMissionEntity(obj, true, true)
  SetEntityCollision(obj, false, false)
  FreezeEntityPosition(obj, true)
  SetEntityAlpha(obj, 255, false)
  SetEntityLodDist(obj, 300)

  local rot = cfg.rotation or vector3(90.0, 0.0, 0.0)
  local rx = vectorComponent(rot, 'x', 1, 90.0)
  local ry = vectorComponent(rot, 'y', 2, 0.0)
  local rz = (heading + (tonumber(cfg.headingOffset) or 0.0) + vectorComponent(rot, 'z', 3, 0.0)) % 360.0
  SetEntityRotation(obj, rx, ry, rz, 2, true)

  studio.greenTuneProp = obj
  applyGreenScale(obj)
  SetModelAsNoLongerNeeded(hash)

  local t = greenTune()
  notify(('Greenscreen spawned. scale=%.2f zOffset=%.2f. Use /vehgreenscale /vehgreenup /vehgreendown /vehgreenpos.'):format(t.scale, t.zOffset), 'success')
  print(('[nv_cloth] /vehgreen spawned %s scale=%.2f zOffset=%.2f'):format(model, t.scale, t.zOffset))
end

local function moveLiveGreenZ(delta)
  local t = greenTune()
  t.zOffset = (tonumber(t.zOffset) or 0.0) + (tonumber(delta) or 0.0)

  -- Move the live prop.
  local ent = studio.greenTuneProp
  if ent and ent ~= 0 and DoesEntityExist(ent) then
    local c = GetEntityCoords(ent)
    SetEntityCoordsNoOffset(ent, c.x, c.y, c.z + (tonumber(delta) or 0.0), false, false, false)
  end

  -- Also nudge the real backdrop tiles live (they read zOffset on next placement).
  notify(('Greenscreen zOffset = %.2f'):format(t.zOffset), 'success')
  print(('[nv_cloth] /vehgreen zOffset = %.4f'):format(t.zOffset))
end

RegisterNetEvent('nvCloth:client:greenSpawn', function(useFixed)
  spawnLiveGreenProp(useFixed == true)
end)

RegisterNetEvent('nvCloth:client:greenScale', function(scale)
  local t = greenTune()
  scale = tonumber(scale)
  if not scale or scale <= 0 then
    notify('Usage: /vehgreenscale <number>  (e.g. /vehgreenscale 2.0)', 'error')
    return
  end
  if scale > 8.0 then scale = 8.0 end
  t.scale = scale
  refreshGreenTuning()
  notify(('Greenscreen scale = %.2f'):format(scale), 'success')
  print(('[nv_cloth] /vehgreenscale = %.4f'):format(scale))
end)

RegisterNetEvent('nvCloth:client:greenUp', function(delta)
  moveLiveGreenZ(math.abs(tonumber(delta) or 0.10))
end)

RegisterNetEvent('nvCloth:client:greenDown', function(delta)
  moveLiveGreenZ(-math.abs(tonumber(delta) or 0.05))
end)

RegisterNetEvent('nvCloth:client:greenPos', function()
  local ent = studio.greenTuneProp
  local t = greenTune()
  if not ent or ent == 0 or not DoesEntityExist(ent) then
    notify('No live greenscreen prop. Spawn one first with /vehgreen.', 'error')
    return
  end
  local c = GetEntityCoords(ent)
  local h = GetEntityHeading(ent)
  -- The live prop's world z already includes the tuned zOffset (from /vehgreenup /
  -- /vehgreendown). Print fixedCoords with that offset removed and report the
  -- offset separately, so pasting BOTH values never raises the backdrop twice.
  local tunedZ = tonumber(t.zOffset) or 0.0
  local baseZ = c.z - tunedZ
  local vec4Line = ('vec4(%.4f, %.4f, %.4f, %.4f)'):format(c.x, c.y, baseZ, h)

  print('[nv_cloth] Greenscreen prop position (paste into Config.AdminStudio.Backdrop):')
  print(('[nv_cloth]     fixedCoords = %s,'):format(vec4Line))
  print(('[nv_cloth]     scale       = %.4f,'):format(tonumber(t.scale) or 1.0))
  print(('[nv_cloth]     tuneZOffset = %.4f,'):format(tunedZ))
  print(('[nv_cloth] (fixedCoords height already excludes tuneZOffset; paste both as-is.)'))
  notify(('Greenscreen pos printed in F8: %s'):format(vec4Line), 'success')
end)

RegisterNetEvent('nvCloth:client:greenClear', function()
  if studio.greenTuneProp and studio.greenTuneProp ~= 0 and DoesEntityExist(studio.greenTuneProp) then
    deleteEntity(studio.greenTuneProp)
  end
  studio.greenTuneProp = nil
  notify('Live greenscreen prop removed.', 'success')
end)


AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    StopClothingAdminStudio()
    clearTestProps()
    if studio.greenTuneProp and studio.greenTuneProp ~= 0 and DoesEntityExist(studio.greenTuneProp) then
      deleteEntity(studio.greenTuneProp)
      studio.greenTuneProp = nil
    end
  end
end)
