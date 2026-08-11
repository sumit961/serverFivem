--========================================================
-- nv_cloth · Build 2.22 · /clothingstore — admin store manager (client)
--========================================================
-- Separate from the shop/admin studio on purpose:
--   · /clothingadmin  = capture + save clothes (unpublished records)
--   · /clothingstore  = browse saved clothes with images, publish/unpublish,
--                       set price, assign to an org, preview on the real
--                       player model (male + female), and jump back into
--                       /clothingadmin to retake an image.
-- The original player model and components are restored when the manager closes.
-- Reuses globals from sibling files: categories + openClothShop (cl_shop),
-- CreateSkinCam / DestroySkinCam (cl_camera).
--========================================================

local manageOpen = false
local manageReturnCoords = nil
local originalAppearance = nil   -- captured only for a retake's real-model swap
local retakeSwapPending = false  -- true while the admin panel runs on a swapped model
local managePreviewToken = 0

local previewPed = nil       -- current real player ped used for MALE/FEMALE preview
local previewGender = 'male'
local previewUsesPlayer = false

local MANAGE_COMPONENTS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local MANAGE_PROPS = { 0, 1, 2, 6, 7 }

local function captureAppearance()
  if type(NvClothCaptureFullAppearance) == 'function' then
    return NvClothCaptureFullAppearance()
  end
  local ped = PlayerPedId()
  local snap = { model = GetEntityModel(ped), components = {}, props = {} }
  for _, idx in ipairs(MANAGE_COMPONENTS) do
    snap.components[idx] = {
      drawable = GetPedDrawableVariation(ped, idx),
      texture = GetPedTextureVariation(ped, idx),
      palette = GetPedPaletteVariation(ped, idx),
    }
  end
  for _, idx in ipairs(MANAGE_PROPS) do
    snap.props[idx] = {
      drawable = GetPedPropIndex(ped, idx),
      texture = GetPedPropTextureIndex(ped, idx),
    }
  end
  return snap
end

local function loadModel(hash)
  if not IsModelInCdimage(hash) then return false end
  RequestModel(hash)
  local deadline = GetGameTimer() + 8000
  while not HasModelLoaded(hash) do
    if GetGameTimer() > deadline then return false end
    Wait(25)
  end
  return true
end

local function applyAppearance(snap)
  if type(NvClothApplyFullAppearance) == 'function' then
    return NvClothApplyFullAppearance(snap)
  end
  if type(snap) ~= 'table' then return end
  local ped = PlayerPedId()
  if snap.model and GetEntityModel(ped) ~= snap.model then
    if loadModel(snap.model) then
      SetPlayerModel(PlayerId(), snap.model)
      SetModelAsNoLongerNeeded(snap.model)
      ped = PlayerPedId()
    end
  end
  for idx, comp in pairs(snap.components or {}) do
    SetPedComponentVariation(ped, idx, comp.drawable or 0, comp.texture or 0, comp.palette or 0)
  end
  for idx, prop in pairs(snap.props or {}) do
    if prop.drawable and prop.drawable >= 0 then
      SetPedPropIndex(ped, idx, prop.drawable, prop.texture or 0, true)
    else
      ClearPedProp(ped, idx)
    end
  end
end

-- Swaps the admin's OWN ped to the requested freemode gender. Only used for a
-- RETAKE hand-off into /clothingadmin, which operates on the real player, not
-- the manager's fake preview ped. Waits for the async model swap to actually
-- finish before returning, otherwise callers can act on a ped that's mid-swap.
local function ensureGenderModel(gender, expectedToken)
  gender = tostring(gender or 'male'):lower() == 'female' and 'female' or 'male'
  if expectedToken and (expectedToken ~= managePreviewToken or not manageOpen) then return false end
  local model = gender == 'female' and `mp_f_freemode_01` or `mp_m_freemode_01`
  if GetEntityModel(PlayerPedId()) == model then return true end
  if not loadModel(model) then return false end
  if expectedToken and (expectedToken ~= managePreviewToken or not manageOpen) then
    SetModelAsNoLongerNeeded(model)
    return false
  end
  SetPlayerModel(PlayerId(), model)
  SetModelAsNoLongerNeeded(model)

  local deadline = GetGameTimer() + 3000
  while GetEntityModel(PlayerPedId()) ~= model do
    if GetGameTimer() > deadline then return false end
    if expectedToken and (expectedToken ~= managePreviewToken or not manageOpen) then return false end
    Wait(0)
  end

  local ped = PlayerPedId()
  SetPedDefaultComponentVariation(ped)
  ClearAllPedProps(ped)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  return true
end

-- Clears the preview reference. The player ped must never be deleted.
local function destroyPreviewPed()
  if previewPed and DoesEntityExist(previewPed) and not previewUsesPlayer then
    DeleteEntity(previewPed)
  end
  previewPed = nil
  previewUsesPlayer = false
end

-- Swap the actual player freemode model so the manager behaves like
-- /clothingadmin. The saved appearance is restored when the manager closes.
-- ped standing in the same spot — nothing about the admin's own character is
-- ever touched by a normal preview/gender switch.
local function ensureGenderPed(gender, expectedToken)
  gender = tostring(gender or 'male'):lower() == 'female' and 'female' or 'male'
  if expectedToken and (expectedToken ~= managePreviewToken or not manageOpen) then return false end
  if previewUsesPlayer and previewPed == PlayerPedId() and previewGender == gender then return true end

  if not originalAppearance then originalAppearance = captureAppearance() end
  destroyPreviewPed()
  if not ensureGenderModel(gender, expectedToken) then return false end

  local ped = PlayerPedId()
  SetEntityVisible(ped, true, false)
  NetworkSetEntityInvisibleToNetwork(ped, false)
  SetEntityCollision(ped, true, true)
  previewPed = ped
  previewUsesPlayer = true
  previewGender = gender
  return true
end

local function resetPreviewBase()
  if previewPed and DoesEntityExist(previewPed) then
    SetPedDefaultComponentVariation(previewPed)
    ClearAllPedProps(previewPed)
  end
end

local function applyRowToPed(row)
  if type(row) ~= 'table' then return false end
  if not (previewPed and DoesEntityExist(previewPed)) then return false end
  local category = tostring(row.category or ''):lower()
  local cat = categories and categories[category]
  if not cat then return false end
  local ped = previewPed
  local drawable = tonumber(row.drawableId or row.drawable_id or row.drawable)
  local texture = tonumber(row.textureId or row.texture_id or row.texture) or 0
  if texture < 0 then texture = 0 end
  if drawable == nil then return false end

  if cat.type == 'prop' then
    if drawable >= 0 then
      ClearPedProp(ped, cat.index)
      SetPedPropIndex(ped, cat.index, drawable, texture, true)
    else
      ClearPedProp(ped, cat.index)
    end
    return true
  end

  SetPedComponentVariation(ped, cat.index, drawable, texture, 0)
  -- Torso rows carry the arms/undershirt fit saved in /clothingstore; show
  -- exactly that fit rather than an auto-resolved guess.
  if category == 'torso' then
    local arms = tonumber(row.arms)
    if arms ~= nil then
      SetPedComponentVariation(ped, 3, arms, tonumber(row.armsTexture or row.arms_texture) or 0, 0)
    end
    local undershirt = tonumber(row.undershirt)
    if undershirt ~= nil then
      SetPedComponentVariation(ped, 8, undershirt, tonumber(row.undershirtTexture or row.undershirt_texture) or 0, 0)
    end
  end
  return true
end

local function manageFitState(success)
  local ped = previewPed
  if not (ped and DoesEntityExist(ped)) then
    return { success = false }
  end
  return {
    success = success ~= false,
    arms = GetPedDrawableVariation(ped, 3),
    armsTexture = GetPedTextureVariation(ped, 3),
    armsCount = GetNumberOfPedDrawableVariations(ped, 3),
    undershirt = GetPedDrawableVariation(ped, 8),
    undershirtTexture = GetPedTextureVariation(ped, 8),
    undershirtCount = GetNumberOfPedDrawableVariations(ped, 8),
  }
end

local function sendManageFitState()
  local state = manageFitState(true)
  state.type = 'manageFitState'
  SendNUIMessage(state)
end

local function setManagePositionSaveBlocked(block)
  block = block == true
  if LocalPlayer and LocalPlayer.state and LocalPlayer.state.set then
    LocalPlayer.state:set('inClothingStore', block, true)
    LocalPlayer.state:set('cmClothingPreview', block, true)
    LocalPlayer.state:set('cmSkipPositionSave', block, true)
    LocalPlayer.state:set('ignorePositionSave', block, true)
  end
  TriggerEvent('cm-playerdata:client:setPositionSaveBlocked', block)
  TriggerServerEvent('nvCloth:server:setPositionSaveBlocked', block)
end

local function setManageHudHidden(hidden)
  hidden = hidden == true
  -- cm-hud checks these state locks before accepting showAfterUi. Update them
  -- locally first so closing the manager cannot be rejected by its own stale
  -- inClothingStore state while the server bucket update is still replicating.
  if LocalPlayer and LocalPlayer.state and LocalPlayer.state.set then
    LocalPlayer.state:set('inClothingStore', hidden, true)
    LocalPlayer.state:set('cmHudHiddenByClothing', hidden, true)
  end
  TriggerEvent(hidden and 'cm-hud:client:hideForUi' or 'cm-hud:client:showAfterUi')
  DisplayHud(not hidden)
  DisplayRadar(not hidden)
end

-- Copies the real (hidden) anchor ped's heading onto the visible fake preview
-- ped. CreateSkinCam works out a "face the camera" heading and applies it to
-- PlayerPedId() — since that's now the hidden anchor, mirror it onto the ped
-- that's actually on screen.
local function syncPreviewHeadingToCamera()
  if previewPed and DoesEntityExist(previewPed) then
    SetEntityHeading(previewPed, GetEntityHeading(PlayerPedId()))
  end
end

local function openManageScene(payload)
  if manageOpen then return end
  -- The shop/admin studio and the manager can never run at once. A stale/open
  -- shop used to make /clothingstore silently return; close it first and continue
  -- so the manager command always has a deterministic result.
  if opened == true then
    if type(closeShopRoutine) == 'function' then
      closeShopRoutine()
      Wait(150)
    else
      TriggerEvent('nvCloth:showNotification', nil, 'error', 'Could not close the current clothing panel.')
      return
    end
  end
  manageOpen = true

  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  manageReturnCoords = vector4(coords.x, coords.y, coords.z, GetEntityHeading(ped))

  setManagePositionSaveBlocked(true)
  TriggerServerEvent('nvCloth:server:enterDressingRoom')
  Wait(100)

  local room = (Config.AdminStudio and Config.AdminStudio.StudioCoords) or Config.DefaultDressingRoom
  if room then
    SetEntityCoordsNoOffset(ped, room.x, room.y, room.z, false, false, false)
    if room.w then SetEntityHeading(ped, room.w) end
  end
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  Wait(250)

  setManageHudHidden(true)
  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(false)

  managePreviewToken = managePreviewToken + 1
  local token = managePreviewToken
  ensureGenderPed('male', token)
  if CreateSkinCam then CreateSkinCam('body') end
  syncPreviewHeadingToCamera()

  SendNUIMessage({
    type = 'openManagePanel',
    value = true,
    orgs = (payload and payload.orgs) or {},
    prices = (payload and payload.prices) or {},
    gender = previewGender,
  })
  TriggerServerEvent('nvCloth:server:getManageCatalog')
end

local function closeManageScene(keepSwappedModel)
  if not manageOpen then return end
  manageOpen = false
  managePreviewToken = managePreviewToken + 1

  SendNUIMessage({ type = 'openManagePanel', value = false })
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
  if DestroySkinCam then DestroySkinCam() end
  Wait(50)
  RenderScriptCams(false, false, 0, true, true)

  -- Always drop the fake preview ped and restore the real admin ped's
  -- visibility. For a retake, manageRetake already called destroyPreviewPed
  -- before swapping the REAL ped's model, so this is a harmless no-op here.
  destroyPreviewPed()

  local ped = PlayerPedId()
  if keepSwappedModel ~= true then
    if originalAppearance then
      applyAppearance(originalAppearance)
      originalAppearance = nil
    end
    ped = PlayerPedId()
  end

  FreezeEntityPosition(ped, false)
  SetEntityInvincible(ped, false)

  if keepSwappedModel ~= true then
    -- Clear the server/state lock before asking cm-hud to show. showAfterUi
    -- intentionally refuses while inClothingStore is still true.
    TriggerServerEvent('nvCloth:server:leaveDressingRoom')
    setManageHudHidden(false)
    if manageReturnCoords then
      SetEntityCoordsNoOffset(ped, manageReturnCoords.x, manageReturnCoords.y, manageReturnCoords.z, false, false, false)
      SetEntityHeading(ped, manageReturnCoords.w or 0.0)
    end
    Wait(100)
    setManagePositionSaveBlocked(false)
    manageReturnCoords = nil
  end
end

-- Called by cl_shop's closeShopRoutine. Restores the admin's real model and
-- outfit after a retake that ran the admin panel on a swapped ped.
function NvClothManage_OnShopClosed()
  if not retakeSwapPending then return end
  retakeSwapPending = false
  applyAppearance(originalAppearance)
  originalAppearance = nil
  if manageReturnCoords then
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, manageReturnCoords.x, manageReturnCoords.y, manageReturnCoords.z, false, false, false)
    SetEntityHeading(ped, manageReturnCoords.w or 0.0)
    manageReturnCoords = nil
  end
end

--========================================================
-- Server events
--========================================================
RegisterNetEvent('nvCloth:client:openManagePanel', function(payload)
  print('[nv_cloth] /clothingstore manager open request received')
  CreateThread(function() openManageScene(payload) end)
end)

RegisterNetEvent('nvCloth:client:manageCatalog', function(rows)
  SendNUIMessage({ type = 'manageCatalog', rows = rows or {} })
end)

RegisterNetEvent('nvCloth:client:manageItemSaved', function(row)
  SendNUIMessage({ type = 'manageItemSaved', row = row })
end)

--========================================================
-- NUI callbacks
--========================================================
RegisterNUICallback('manageClose', function(_, cb)
  cb({ success = true })
  CreateThread(function() closeManageScene(false) end)
end)

RegisterNUICallback('manageRefresh', function(_, cb)
  if manageOpen then TriggerServerEvent('nvCloth:server:getManageCatalog') end
  cb({ success = true })
end)

RegisterNUICallback('manageSetGender', function(data, cb)
  if not manageOpen then cb({ success = false }); return end
  local gender = tostring(data and data.gender or 'male'):lower()
  managePreviewToken = managePreviewToken + 1
  local token = managePreviewToken
  CreateThread(function()
    -- Spawning a fresh fake ped is effectively instant (no async model-swap
    -- wait like the real player would need), so the camera never has to be
    -- torn down for a gender switch — only the ped standing in front of it changes.
    local ok = ensureGenderPed(gender, token)
    if ok and (token ~= managePreviewToken or not manageOpen) then ok = false end
    if ok then
      resetPreviewBase()
      syncPreviewHeadingToCamera()
      TriggerServerEvent('nvCloth:server:getManageCatalog')
    end
    cb({ success = ok, gender = gender })
  end)
end)

RegisterNUICallback('managePreviewItem', function(data, cb)
  cb({ success = manageOpen })
  if not manageOpen then return end
  local row = type(data) == 'table' and (data.row or data) or {}
  managePreviewToken = managePreviewToken + 1
  local token = managePreviewToken
  CreateThread(function()
    local gender = tostring(row.gender or 'male'):lower()
    if not ensureGenderPed(gender, token) then
      TriggerEvent('nvCloth:showNotification', nil, 'error', 'Could not load the preview model.')
      return
    end
    if token ~= managePreviewToken or not manageOpen then return end
    resetPreviewBase()
    applyRowToPed(row)
    sendManageFitState()
  end)
end)

RegisterNUICallback('manageCycleFit', function(data, cb)
  if not manageOpen then cb({ success = false, error = 'manager_closed' }); return end
  if not (previewPed and DoesEntityExist(previewPed)) then cb({ success = false, error = 'no_preview_ped' }); return end
  local ped = previewPed
  local slot = tostring(data and data.slot or 'arms'):lower()
  local component = slot == 'undershirt' and 8 or 3
  local count = GetNumberOfPedDrawableVariations(ped, component)
  if count <= 0 then cb({ success = false, error = 'no_variations' }); return end
  local dir = tonumber(data and data.dir) or 1
  dir = dir >= 0 and 1 or -1
  local current = GetPedDrawableVariation(ped, component)
  local nextDrawable = (current + dir) % count
  SetPedComponentVariation(ped, component, nextDrawable, 0, 0)
  local state = manageFitState(true)
  sendManageFitState()
  cb(state)
end)

RegisterNUICallback('manageGetFit', function(_, cb)
  if not manageOpen then cb({ success = false, error = 'manager_closed' }); return end
  cb(manageFitState(true))
end)

RegisterNUICallback('manageResetPreview', function(_, cb)
  if manageOpen then resetPreviewBase() end
  cb({ success = true })
end)

RegisterNUICallback('manageRotatePed', function(data, cb)
  local delta = tonumber(data and data.delta) or 0.0
  if previewPed and DoesEntityExist(previewPed) then
    SetEntityHeading(previewPed, (GetEntityHeading(previewPed) + delta) % 360.0)
  end
  cb({ success = true })
end)

RegisterNUICallback('manageSaveItem', function(data, cb)
  TriggerServerEvent('nvCloth:server:manageSaveItem', type(data) == 'table' and data or {})
  cb({ success = true })
end)

-- Retake: close the manager but keep the (possibly swapped) preview model so
-- /clothingadmin lists the right gender's drawables, open the admin panel, and
-- hand the target row to the NUI so it preselects the exact clothe.
-- /clothingadmin operates on the admin's REAL character, not the manager's fake
-- preview ped, so the fake ped is dropped and the real ped is what gets swapped.
RegisterNUICallback('manageRetake', function(data, cb)
  cb({ success = manageOpen })
  if not manageOpen then return end
  local row = type(data) == 'table' and (data.row or data) or {}
  CreateThread(function()
    local gender = tostring(row.gender or 'male'):lower()
    destroyPreviewPed()
    originalAppearance = originalAppearance or captureAppearance()
    if not ensureGenderModel(gender) then
      TriggerEvent('nvCloth:showNotification', nil, 'error', 'Could not load the capture model.')
      return
    end
    retakeSwapPending = true
    closeManageScene(true) -- keep swapped model + dressing bucket for the admin panel

    Wait(150)
    -- The dressing-room bucket is already active; openClothShop re-enters it,
    -- which is a no-op server-side (same bucket id).
    if type(openClothShop) == 'function' then
      openClothShop('ADMIN PANEL', { 'torso', 'tshirt', 'pants', 'shoes', 'hat', 'glasses', 'earrings', 'chains', 'bags', 'watches', 'bracelets' }, 'clothes', nil, true)
      Wait(400)
      SendNUIMessage({ type = 'manageRetakeTarget', row = row })
    end
  end)
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  -- Route through the same restore path as a normal CLOSE/ESC so a resource
  -- restart while the manager is open can't skip the skin cam teardown or
  -- heading restore that a hand-rolled duplicate here used to miss.
  closeManageScene(false)
end)
