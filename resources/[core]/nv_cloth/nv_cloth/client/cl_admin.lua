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
  fallbackDrawBox = false,
  testProps = {},
  envApplied = false,
  appearanceSnapshot = nil,
  backdropMode = 'green',
  forceBackdropDrawBox = false,
  captureWallHeading = nil,
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

local function placeBackdropProp(ent, pieceIndex, pieceCount)
  if not ent or ent == 0 or not DoesEntityExist(ent) then return end

  local ped = PlayerPedId()
  local cfg = (Config.AdminStudio and Config.AdminStudio.Backdrop) or {}
  local fixed = cfg.fixedCoords
  local sideIndex = pieceIndex - ((pieceCount + 1) / 2.0)
  local spacing = tonumber(cfg.spacing) or 1.55

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

  local sideRad = math.rad(heading + 90.0)
  local sx = math.cos(sideRad) * sideIndex * spacing
  local sy = math.sin(sideRad) * sideIndex * spacing

  SetEntityCoordsNoOffset(ent, bx + sx, by + sy, bz, false, false, false)
  SetEntityHeading(ent, (heading + (tonumber(cfg.headingOffset) or 0.0)) % 360.0)

  local rot = cfg.rotation or vector3(90.0, 0.0, 0.0)
  local rx = vectorComponent(rot, 'x', 1, 90.0)
  local ry = vectorComponent(rot, 'y', 2, 0.0)
  local rz = (heading + (tonumber(cfg.headingOffset) or 0.0) + vectorComponent(rot, 'z', 3, 0.0)) % 360.0
  SetEntityRotation(ent, rx, ry, rz, 2, true)
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
        for i, ent in ipairs(studio.backdropProps) do
          placeBackdropProp(ent, i, #studio.backdropProps)
        end
        Wait(100)
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

  local pieces = math.floor(tonumber(cfg.pieces) or 3)
  if pieces < 1 then pieces = 1 end
  if pieces > 6 then pieces = 6 end

  for i = 1, pieces do
    local obj = CreateObjectNoOffset(hash, 0.0, 0.0, 0.0, false, false, false)
    if obj and obj ~= 0 then
      SetEntityAsMissionEntity(obj, true, true)
      SetEntityCollision(obj, cfg.collision == true, cfg.collision == true)
      FreezeEntityPosition(obj, true)
      SetEntityAlpha(obj, 255, false)
      SetEntityLodDist(obj, 200)
      studio.backdropProps[#studio.backdropProps + 1] = obj
      placeBackdropProp(obj, #studio.backdropProps, pieces)
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
  studio.forceBackdropDrawBox = (studio.backdropMode ~= 'green' and studio.backdropMode ~= 'none')
  refreshBackdropVisibility()
  if studio.backdropMode == 'none' then
    print('[nv_cloth] Chroma wall mode: hidden while browsing.')
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

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    StopClothingAdminStudio()
    clearTestProps()
  end
end)
