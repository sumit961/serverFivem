--========================================================
-- nvCloth – Categories & Shop UI toggle
--========================================================
-- Garde les mêmes noms/exports globaux utilisés ailleurs :
--   - categories (table)
--   - opened (bool)
--   - saveClothes (table)
--   - openClothShop(label, categories)
--   - NUI callbacks: closeMenu
--   - Event: nvCloth:closeMenu
--   - Commande: /clothShop
-- Dépend de fonctions globales définies ailleurs :
--   - CreateSkinCam("face"/"body"/"feet")
--   - DestroySkinCam()
--   - Config (AppearanceRessource, Inventory, Prices, Translations, Lang)
--========================================================

--========================
-- Catégories de vêtements
--========================
categories = {
  tshirt   = { type = "component", index = 8  },
  torso    = { type = "component", index = 11 },
  arms     = { type = "component", index = 3  }, -- preview-only; sold inside torso metadata
  pants    = { type = "component", index = 4  },
  shoes    = { type = "component", index = 6  },
  chains   = { type = "component", index = 7  },
  bags     = { type = "component", index = 5  },
  armor    = { type = "component", index = 9  }, -- body armor / vest; managed in /clothingstore, sold/equipped via cm-gunstore
  hat      = { type = "prop",      index = 0  },
  glasses  = { type = "prop",      index = 1  },
  earrings = { type = "prop",      index = 2  },
  watches  = { type = "prop",      index = 6  },
  bracelets = { type = "prop",     index = 7  },
}

-- État UI
opened = false

-- Une seule initialisation lourde du front (translations/prices)
local nuiInitialized = false

-- Sauvegarde temporaire des vêtements au moment de l’ouverture
saveClothes = {}

local currentShopCoords = nil -- exact return position before opening shop
local currentShopKey = nil
local currentShopData = nil
local isAdminShop = false
local inPrivateBucket = false
local currentShopCategories = {}
local adminOriginalAppearance = nil

function NvCloth_IsAdminShop() return isAdminShop == true end
function NvCloth_GetCurrentShopKey() return currentShopKey or 'clothes' end
function NvCloth_GetCurrentShopData() return currentShopData end
function NvCloth_GetReturnCoords() return currentShopCoords end

local function setClothingPositionSaveBlocked(block)
  block = block == true
  if LocalPlayer and LocalPlayer.state and LocalPlayer.state.set then
    LocalPlayer.state:set('inClothingStore', block, true)
    LocalPlayer.state:set('cmClothingPreview', block, true)
    LocalPlayer.state:set('skipPositionSave', block, true)
    LocalPlayer.state:set('cmSkipPositionSave', block, true)
    LocalPlayer.state:set('ignorePositionSave', block, true)
  end
  TriggerEvent('cm-playerdata:client:setPositionSaveBlocked', block)
  TriggerServerEvent('nvCloth:server:setPositionSaveBlocked', block)
end

local shopFrozen = false
local shopSavedCoords = nil
local shopSavedHeading = nil

local function setShopPlayerLocked(lock)
  local ped = PlayerPedId()
  if lock then
    shopSavedCoords = GetEntityCoords(ped)
    shopSavedHeading = GetEntityHeading(ped)
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    shopFrozen = true
  else
    if shopFrozen then
      FreezeEntityPosition(ped, false)
      SetEntityInvincible(ped, false)
      SetPedCanRagdoll(ped, true)
    end
    shopFrozen = false
    shopSavedCoords = nil
    shopSavedHeading = nil
  end
end

CreateThread(function()
  while true do
    if opened and shopFrozen and shopSavedCoords then
      local ped = PlayerPedId()
      local coords = GetEntityCoords(ped)
      if #(coords - shopSavedCoords) > 0.35 then
        SetEntityCoordsNoOffset(ped, shopSavedCoords.x, shopSavedCoords.y, shopSavedCoords.z, false, false, false)
      end
      if shopSavedHeading then
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
      end
      DisableControlAction(0, 30, true) -- left/right
      DisableControlAction(0, 31, true) -- forward/back
      DisableControlAction(0, 21, true) -- sprint
      DisableControlAction(0, 22, true) -- jump
      DisableControlAction(0, 24, true) -- attack
      DisableControlAction(0, 25, true) -- aim
      Wait(0)
    else
      Wait(500)
    end
  end
end)

--========================================================
-- Helpers
--========================================================

--- Force un modèle freemode si on utilise skinchanger et que le ped n'est pas bon
local function ensureFreemodeIfSkinchanger()
  if Config.AppearanceRessource ~= "skinchanger" then 
    return 
  end

  local ped = PlayerPedId()
  local curModel = GetEntityModel(ped)
  local maleHash   = GetHashKey("mp_m_freemode_01")
  local femaleHash = GetHashKey("mp_f_freemode_01")

  -- Si déjà en freemode, pas besoin de changer
  if curModel == maleHash or curModel == femaleHash then
    return
  end
  
  -- Récup skin via skinchanger:getSkin avec timeout
  local skin = nil
  local timeout = false
  
  CreateThread(function()
    Wait(2000) -- 2 secondes de timeout
    timeout = true
  end)
  
  TriggerEvent("skinchanger:getSkin", function(s) 
    skin = s 
  end)
  
  -- Attendre la réponse ou le timeout
  local waited = 0
  while not skin and not timeout and waited < 2000 do
    Wait(100)
    waited = waited + 100
  end
  
  if timeout or not skin then
    return
  end
  
  TriggerEvent("skinchanger:loadDefaultModel", (skin.sex == 0))

  -- Attendre le swap de modèle (max 5s)
  for _ = 1, 50 do
    local check = GetEntityModel(PlayerPedId())
    if check == maleHash or check == femaleHash then 
      break 
    end
    Wait(100)
  end
end

local function captureAdminOriginalAppearance()
  local ped = PlayerPedId()
  local snap = {
    model = GetEntityModel(ped),
    components = {}, props = {}, overlays = {}, faceFeatures = {},
    hairColor = GetPedHairColor(ped),
    hairHighlight = GetPedHairHighlightColor(ped),
    eyeColor = GetPedEyeColor(ped),
  }
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
    local ok, value, colourType, firstColour, secondColour, opacity = GetPedHeadOverlayData(ped, i)
    snap.overlays[i] = {
      ok = ok == true, value = tonumber(value) or 0,
      colourType = tonumber(colourType) or 0,
      firstColour = tonumber(firstColour) or 0,
      secondColour = tonumber(secondColour) or 0,
      opacity = tonumber(opacity) or 0.0,
    }
  end
  for i = 0, 19 do snap.faceFeatures[i] = GetPedFaceFeature(ped, i) or 0.0 end
  local okBlend, hasBlend, blend = pcall(GetPedHeadBlendData, ped)
  if okBlend and hasBlend and type(blend) == 'table' then snap.headBlend = blend end
  return snap
end

local function requestPlayerModel(hash)
  if not IsModelInCdimage(hash) or not IsModelValid(hash) then return false end
  RequestModel(hash)
  local deadline = GetGameTimer() + 8000
  while not HasModelLoaded(hash) do
    if GetGameTimer() > deadline then return false end
    Wait(25)
  end
  return true
end

local function applyAdminOriginalAppearance(snap)
  if type(snap) ~= 'table' then return false end
  local ped = PlayerPedId()
  if snap.model and GetEntityModel(ped) ~= snap.model then
    if not requestPlayerModel(snap.model) then return false end
    SetPlayerModel(PlayerId(), snap.model)
    SetModelAsNoLongerNeeded(snap.model)
    ped = PlayerPedId()
  end
  for i = 0, 11 do
    local c = snap.components[i]
    if c then SetPedComponentVariation(ped, i, c.drawable or 0, c.texture or 0, c.palette or 0) end
  end
  for i = 0, 12 do
    local p = snap.props[i]
    if p and tonumber(p.drawable) and tonumber(p.drawable) >= 0 then
      SetPedPropIndex(ped, i, tonumber(p.drawable), tonumber(p.texture) or 0, true)
    else
      ClearPedProp(ped, i)
    end
  end
  if snap.hairColor ~= nil then SetPedHairColor(ped, tonumber(snap.hairColor) or 0, tonumber(snap.hairHighlight) or 0) end
  if snap.eyeColor ~= nil then SetPedEyeColor(ped, tonumber(snap.eyeColor) or 0) end
  local b = snap.headBlend
  if type(b) == 'table' then
    pcall(SetPedHeadBlendData, ped,
      tonumber(b.shapeFirst) or 0, tonumber(b.shapeSecond) or 0, tonumber(b.shapeThird) or 0,
      tonumber(b.skinFirst) or 0, tonumber(b.skinSecond) or 0, tonumber(b.skinThird) or 0,
      tonumber(b.shapeMix) or 0.0, tonumber(b.skinMix) or 0.0, tonumber(b.thirdMix) or 0.0,
      false)
  end
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
  return true
end

-- Shared rollback contract used by /clothingadmin, the public clothing store,
-- and /clothingstore. It includes model, clothes, props, head blend, all face
-- features, overlays, hair colours and eye colour.
function NvClothCaptureFullAppearance()
  return captureAdminOriginalAppearance()
end

function NvClothApplyFullAppearance(snap)
  return applyAdminOriginalAppearance(snap)
end

--- Snapshot des vêtements actuels -> saveClothes
local function snapshotCurrentClothes()
  local ped = PlayerPedId()
  for key, def in pairs(categories) do
    if def.type == "component" then
      saveClothes[key] = {
        drawable = GetPedDrawableVariation(ped, def.index),
        texture  = GetPedTextureVariation(ped, def.index),
      }
    elseif def.type == "prop" then
      saveClothes[key] = {
        drawable = GetPedPropIndex(ped, def.index),
        texture  = GetPedPropTextureIndex(ped, def.index),
      }
    end
  end

  -- Preserve natural hair and mask so hat/mask previews never leave the player bald
  saveClothes.__hair = {
    drawable = GetPedDrawableVariation(ped, 2),
    texture  = GetPedTextureVariation(ped, 2),
    color    = GetPedHairColor(ped),
    highlight= GetPedHairHighlightColor(ped),
  }
  saveClothes.__mask = {
    drawable = GetPedDrawableVariation(ped, 1),
    texture  = GetPedTextureVariation(ped, 1),
  }
end

--- Calcule les nombres de variations (drawable count) par catégorie pour l’UI
local function computeCounts()
  local ped = PlayerPedId()
  local counts = {}

  for key, def in pairs(categories) do
    if def.type == "component" then
      counts[key] = GetNumberOfPedDrawableVariations(ped, def.index)
    elseif def.type == "prop" then
      counts[key] = GetNumberOfPedPropDrawableVariations(ped, def.index)
    end
  end

  return counts
end

--- Applique focus/radar en fonction de l’état
local function applyUiGameFocus(isOpen)
  SetNuiFocus(isOpen, isOpen)
  SetNuiFocusKeepInput(false)
  DisplayRadar(not isOpen)
end

--- Informe l’inventaire (qs-inventory) de l’état “en cabine”
local function setInventoryClothingState(isInClothing)
  if Config.Inventory == "qs-inventory" then
    exports["qs-inventory"]:setInClothing(isInClothing)
  end
end

local function setHudHiddenForClothing(hidden)
  hidden = hidden == true
  if LocalPlayer and LocalPlayer.state and LocalPlayer.state.set then
    LocalPlayer.state:set('inClothingStore', hidden, true)
    LocalPlayer.state:set('cmHudHiddenByClothing', hidden, true)
  end

  -- cm-hud's actual registered events (hideForUi / showAfterUi).
  TriggerEvent(hidden and 'cm-hud:client:hideForUi' or 'cm-hud:client:showAfterUi')

  -- Fallback aliases in case of different cm-hud build.
  TriggerEvent('cm-hud:client:setVisible', not hidden)
  TriggerEvent('cm_hud:client:setVisible', not hidden)
  TriggerEvent('cm-hud:client:toggleHud', not hidden)
  TriggerEvent('cm_hud:client:toggleHud', not hidden)
  TriggerEvent(hidden and 'cm-hud:client:hide' or 'cm-hud:client:show')
  TriggerEvent(hidden and 'cm_hud:client:hide' or 'cm_hud:client:show')

  -- Also hide native HUD/radar while the clothing UI owns the screen.
  DisplayHud(not hidden)
  DisplayRadar(not hidden)
end

local function restoreShopPreviewClothes()
  -- Store/admin preview must never permanently save to the player's character.
  -- We restore the exact snapshot taken before opening the UI on every close.
  local ped = PlayerPedId()
  if type(saveClothes) == 'table' then
    for category, item in pairs(saveClothes) do
      if not category:find('^__') then
        local cat = categories and categories[category]
        if cat and item and item.drawable ~= nil then
          if cat.type == 'prop' then
            if tonumber(item.drawable) and tonumber(item.drawable) >= 0 then
              SetPedPropIndex(ped, cat.index, tonumber(item.drawable), tonumber(item.texture) or 0, true)
            else
              ClearPedProp(ped, cat.index)
            end
          else
            SetPedComponentVariation(ped, cat.index, tonumber(item.drawable) or 0, tonumber(item.texture) or 0, 0)
          end
        end
      end
    end

    -- Explicitly restore natural hair and mask
    if saveClothes.__hair and saveClothes.__hair.drawable ~= nil then
      SetPedComponentVariation(ped, 2, saveClothes.__hair.drawable, saveClothes.__hair.texture or 0, 0)
      if saveClothes.__hair.color and saveClothes.__hair.color >= 0 then
        SetPedHairColor(ped, saveClothes.__hair.color, saveClothes.__hair.highlight or saveClothes.__hair.color)
      end
    end
    if saveClothes.__mask and saveClothes.__mask.drawable ~= nil then
      SetPedComponentVariation(ped, 1, saveClothes.__mask.drawable, saveClothes.__mask.texture or 0, 0)
    end
  end
end

--- Envoie l’état complet d’ouverture au NUI (avec init si première fois)
local function sendOpenMessage(label, cats, counts, isOpen)
  local gender = GetEntityModel(PlayerPedId()) == GetHashKey('mp_f_freemode_01') and 'female' or 'male'
  local bank = 0
  local cash = 0
  if LocalPlayer and LocalPlayer.state then
    bank = tonumber(LocalPlayer.state.bank) or 0
    cash = tonumber(LocalPlayer.state.cash) or 0
  end

  if not nuiInitialized then
    SendNUIMessage({
      type         = "openClothShop",
      value        = isOpen,
      prices       = Config.Prices,
      label        = label,
      categories   = cats,
      translations = Config.Translations[Config.Lang],
      counts       = counts,
      gender       = gender,
      bank         = bank,
      cash         = cash,
      useCatalogOnly = Config.UseCatalogOnly ~= false,
      pricePresets = Config.PricePresets or {},
      economy      = Config.Economy or {},
      iconCapture  = {
        maxRetries = tonumber(Config.IconCapture and Config.IconCapture.maxRetries) or 2,
        retryDelay = tonumber(Config.IconCapture and Config.IconCapture.retryDelay) or 650,
      },
    })
    nuiInitialized = true
  else
    SendNUIMessage({
      type       = "openClothShop",
      value      = isOpen,
      label      = label,
      categories = cats,
      counts     = counts,
      gender     = gender,
      bank       = bank,
      cash       = cash,
      useCatalogOnly = Config.UseCatalogOnly ~= false,
      pricePresets = Config.PricePresets or {},
      economy      = Config.Economy or {},
      iconCapture  = {
        maxRetries = tonumber(Config.IconCapture and Config.IconCapture.maxRetries) or 2,
        retryDelay = tonumber(Config.IconCapture and Config.IconCapture.retryDelay) or 650,
      },
    })
  end

  -- Toujours rafraîchir les counts (utile quand on change de modèle)
  SendNUIMessage({ type = "clothingCounts", counts = counts })
end

--========================================================
-- API principale
--========================================================

--- Ouvre/ferme la boutique de vêtements
--- @param label string|nil
--- @param cats table|nil (filtre/ordre côté UI)
function closeShopRoutine()
  local ped = PlayerPedId()
  local appearanceToRestore = adminOriginalAppearance

  opened = false
  isAdminShop = false
  -- Close UI first, then forcefully destroy every scripted camera.
  applyUiGameFocus(false)
  SendNUIMessage({ type = "adminMode", value = false })
  SendNUIMessage({ type = "openClothShop", value = false })
  -- Safety net: the JS layer normally blocks closing while a capture/manual pose
  -- is in flight, but this guarantees the real player never stays hidden/frozen
  -- if the panel is ever closed out from under an active capture session anyway
  -- (e.g. a future UI path, or the nvCloth:closeMenu event fired externally).
  if CancelActiveClothingCapture then CancelActiveClothingCapture() end
  if StopClothingAdminStudio then StopClothingAdminStudio() end
  if appearanceToRestore then
    applyAdminOriginalAppearance(appearanceToRestore)
    adminOriginalAppearance = nil
  else
    restoreShopPreviewClothes()
  end
  ped = PlayerPedId()
  if SetShopCameraFixedMode then SetShopCameraFixedMode(false) end
  DestroySkinCam()
  Wait(75)
  RenderScriptCams(false, false, 0, true, true)
  -- Reassert once after camera/capture cleanup. This closes the race where a
  -- delayed capture-preview task used to equip the photographed item again.
  if appearanceToRestore then
    applyAdminOriginalAppearance(appearanceToRestore)
    ped = PlayerPedId()
  end
  setShopPlayerLocked(false)
  ClearPedTasksImmediately(ped)
  DisplayRadar(true)
  setInventoryClothingState(false)
  setHudHiddenForClothing(false)

  if inPrivateBucket then
    TriggerServerEvent('nvCloth:server:leaveDressingRoom')
    inPrivateBucket = false
  end


  -- Return player to the exact place where they opened the shop.
  if currentShopCoords then
    SetEntityCoordsNoOffset(ped, currentShopCoords.x, currentShopCoords.y, currentShopCoords.z, false, false, false)
    if currentShopCoords.w then SetEntityHeading(ped, currentShopCoords.w) end
  end
  Wait(100)
  setClothingPositionSaveBlocked(false)

  currentShopCoords = nil
  currentShopKey = nil
  currentShopData = nil
  currentShopCategories = {}

  -- Build 2.19: if /clothingstore swapped the admin's ped model for an
  -- opposite-gender image retake, restore the original model + appearance now
  -- that the admin panel has closed.
  if type(NvClothManage_OnShopClosed) == 'function' then
    NvClothManage_OnShopClosed()
  end

  if type(CloseStore) == 'function' and exports[GetCurrentResourceName()] and exports[GetCurrentResourceName()]:GetActiveShop() ~= nil then
    CloseStore()
  end

  -- Revert all preview clothing variations and reassert the player's saved equipped inventory items.
  TriggerEvent('cm-inventory:client:restoreEquippedClothing')
  TriggerEvent('cm-inventory:client:forceWearEquippedClothing')
end

--- Ouvre/ferme la boutique de vêtements
--- @param label string|nil
--- @param cats table|nil (filtre/ordre côté UI)
function openClothShop(label, cats, shopKey, shopData, adminMode)
  if opened then
    closeShopRoutine()
    return
  end

  opened = true
  isAdminShop = adminMode == true
  currentShopKey = shopKey or 'clothes'
  currentShopData = shopData
  currentShopCategories = type(cats) == 'table' and cats or {}

  local ped = PlayerPedId()
  local startCoords = GetEntityCoords(ped)
  local startHeading = GetEntityHeading(ped)
  -- Capture before entering the bucket, swapping model, clearing overlays, or
  -- applying any preview clothing. Nothing selected in either UI may survive.
  adminOriginalAppearance = captureAdminOriginalAppearance()
  setClothingPositionSaveBlocked(true)

  local inClothStoreSession = (ClothCam and ClothCam.IsActive())
    or (exports[GetCurrentResourceName()] and exports[GetCurrentResourceName()]:GetActiveShop() ~= nil)

  -- Every shopper/admin gets their own private dressing room instance.
  if not inClothStoreSession then
    TriggerServerEvent('nvCloth:server:enterDressingRoom')
    inPrivateBucket = true
    Wait(100)

    -- Always return to where the player pressed E.
    -- This fixes being sent to another store's exit when closing accessories/clothes.
    if Config.ReturnToOriginalPosition ~= false then
      currentShopCoords = vector4(startCoords.x, startCoords.y, startCoords.z, startHeading)
    elseif (not isAdminShop) and shopData and shopData.exitCoords then
      currentShopCoords = shopData.exitCoords
    else
      currentShopCoords = vector4(startCoords.x, startCoords.y, startCoords.z, startHeading)
    end

    -- Teleport into a clean preview scene. Admin uses the LSIA airport green-prop studio.
    local room
    if isAdminShop and Config.AdminStudio and Config.AdminStudio.StudioCoords then
      room = Config.AdminStudio.StudioCoords
    else
      room = (not isAdminShop) and shopData and shopData.dressingRoom or Config.DefaultDressingRoom
    end
    if room then
      SetEntityCoordsNoOffset(ped, room.x, room.y, room.z, false, false, false)
      if room.w then SetEntityHeading(ped, room.w) end
      FreezeEntityPosition(ped, true)
      Wait(250)
    end
  end

  setInventoryClothingState(true)
  setHudHiddenForClothing(true)
  ensureFreemodeIfSkinchanger()
  snapshotCurrentClothes()
  if isAdminShop and StartClothingAdminStudio then StartClothingAdminStudio() end
  applyUiGameFocus(true)

  local counts = computeCounts()
  sendOpenMessage(label, cats, counts, true)

  local gender = GetEntityModel(PlayerPedId()) == GetHashKey('mp_f_freemode_01') and 'female' or 'male'
  -- Admin needs disabled + non-catalog native variations; normal shop only receives enabled catalog rows.
  TriggerServerEvent('nvCloth:server:getCachedShopCatalog', GetGameTimer(), currentShopKey, gender, isAdminShop)

  -- Pull the player's favourites (store) or the admin capture overrides.
  if isAdminShop then
    TriggerServerEvent('nvCloth:server:getCaptureCameras')
    TriggerServerEvent('nvCloth:server:getCaptureCrops')
    TriggerServerEvent('nvCloth:server:requestCaptureVisibility')
  else
    TriggerServerEvent('nvCloth:server:getFavourites')
    TriggerServerEvent('nvCloth:server:getOutfits')
  end

  setShopPlayerLocked(true)
  if not inClothStoreSession then
    if SetShopCameraFixedMode then SetShopCameraFixedMode(true) end
    CreateSkinCam("body")
  end

  SendNUIMessage({
    type = "adminMode",
    value = isAdminShop,
    shopKey = currentShopKey,
  })

  local activeShopId = (currentShopData and currentShopData.id)
  if not activeShopId and exports[GetCurrentResourceName()] and exports[GetCurrentResourceName()].GetActiveShop then
    activeShopId = exports[GetCurrentResourceName()]:GetActiveShop()
  end
  if activeShopId then
    TriggerServerEvent('nv_cloth:server:getStoreDetails', activeShopId)
  end
end

RegisterNetEvent('nv_cloth:client:openUI', function(shopId)
  local shopData = nil
  if type(Config.Shops) == 'table' then
    for _, s in ipairs(Config.Shops) do
      if s.id == shopId then shopData = s; break end
    end
  end
  local label = shopData and shopData.label or 'Clothing Store'
  local cats = shopData and shopData.categories or { "hat", "torso", "arms", "tshirt", "pants", "shoes", "glasses" }
  openClothShop(label, cats, 'clothes', shopData, false)
end)

-- Dedicated wardrobe opener (e.g. from house interior, dressing room, or command)
RegisterNetEvent('nvCloth:client:openWardrobe', function()
  openClothShop("WARDROBE", { "torso", "tshirt", "pants", "shoes", "hat", "glasses", "chains", "bags", "watches", "bracelets", "earrings" }, "clothes", nil, false)
  CreateThread(function()
    Wait(200)
    SendNUIMessage({ type = 'openWardrobeTab' })
  end)
end)

RegisterCommand("wardrobe", function()
  TriggerEvent('nvCloth:client:openWardrobe')
end, false)

RegisterCommand("outfits", function()
  TriggerEvent('nvCloth:client:openWardrobe')
end, false)

--========================================================
-- Commande de test
--========================================================
RegisterCommand("clothShop", function()
  openClothShop("Clothing Store", { "hat", "torso", "arms", "tshirt", "pants", "shoes", "glasses" }, "clothes", nil, false)
end, false)

-- /clothingadmin is registered server-side so normal players cannot open it.
RegisterNetEvent('nvCloth:client:openAdminPanel', function()
  -- Capture-only panel. Torso fitting, publishing, price and org assignment
  -- are managed after capture in /clothingstore. Armor/vest is captured here
  -- like every other category now -- the server tags its clothing_catalog row
  -- with shop='armor' (not the public 'clothes' shop) and mirrors it into
  -- cm-gunstore's own sellable catalog, since armor is still bought/equipped
  -- through cm-gunstore, not nv_cloth's own checkout.
  openClothShop("ADMIN PANEL", { "torso", "tshirt", "pants", "shoes", "hat", "glasses", "earrings", "chains", "bags", "watches", "bracelets", "armor" }, "clothes", nil, true)
end)

-- Build 2.19: org clothing locker. Opened only through the server /orgcloset
-- command after the player's job was verified against Config.OrgShops. Uses the
-- normal store UI on the org's own shop key, so only rows published to
-- 'org_<job>' in /clothingstore appear here.
RegisterNetEvent('nvCloth:client:openOrgShop', function(job, label)
  job = tostring(job or ''):lower()
  if job == '' then return end
  openClothShop(tostring(label or (job:upper() .. ' Locker')),
    { "hat", "torso", "arms", "tshirt", "pants", "shoes", "glasses", "chains", "bags", "watches", "bracelets", "earrings" },
    'org_' .. job, nil, false)
end)

-- Armor-only admin, kept as a direct shortcut for cm-gunstore's own admin UI.
-- Locks the panel to the vest category; the server still saves it as a normal
-- clothing_catalog row (shop='armor') and syncs it into cm-gunstore.
RegisterNetEvent('nvCloth:client:openArmorAdminPanel', function()
  openClothShop("ARMOR CAPTURE", { "armor" }, "armor", nil, true)
end)

--========================================================
-- NUI: fermeture
--========================================================
RegisterNUICallback("closeMenu", function(_, cb)
  closeShopRoutine()
  cb("ok")
end)

-- Fermeture via event
RegisterNetEvent("nvCloth:closeMenu")
AddEventHandler("nvCloth:closeMenu", function()
  closeShopRoutine()
end)


--========================================================
-- Favourites bridge (global across shops)
--========================================================
RegisterNUICallback('toggleFavourite', function(data, cb)
  data = type(data) == 'table' and data or {}
  local key = tostring(data.key or '')
  if key ~= '' then
    TriggerServerEvent('nvCloth:server:toggleFavourite', key, data.on == true)
  end
  cb({ success = true })
end)

RegisterNUICallback('requestFavourites', function(_, cb)
  TriggerServerEvent('nvCloth:server:getFavourites')
  cb({ success = true })
end)

RegisterNetEvent('nvCloth:client:favourites', function(keys)
  SendNUIMessage({ type = 'favourites', keys = keys or {} })
end)


-- Build 2.20: /clothingadmin switches the actual freemode ped, not just a UI
-- filter. Native drawable/texture counts, previews, captures and saved torso
-- fits therefore all belong to the selected gender.
RegisterNUICallback('adminSetGender', function(data, cb)
  if not opened or not isAdminShop then
    cb({ success = false, error = 'not_admin_mode' })
    return
  end

  local gender = tostring(data and data.gender or 'male'):lower() == 'female' and 'female' or 'male'
  local targetModel = gender == 'female' and GetHashKey('mp_f_freemode_01') or GetHashKey('mp_m_freemode_01')
  if GetEntityModel(PlayerPedId()) == targetModel then
    cb({ success = true, gender = gender, counts = computeCounts() })
    return
  end

  if StopClothingAdminStudio then StopClothingAdminStudio() end
  if SetShopCameraFixedMode then SetShopCameraFixedMode(false) end
  DestroySkinCam()
  RenderScriptCams(false, false, 0, true, true)
  setShopPlayerLocked(false)

  if not requestPlayerModel(targetModel) then
    if StartClothingAdminStudio then StartClothingAdminStudio() end
    setShopPlayerLocked(true)
    if SetShopCameraFixedMode then SetShopCameraFixedMode(true) end
    CreateSkinCam('body')
    cb({ success = false, error = 'model_load_failed' })
    return
  end

  SetPlayerModel(PlayerId(), targetModel)
  SetModelAsNoLongerNeeded(targetModel)
  local ped = PlayerPedId()
  SetPedDefaultComponentVariation(ped)
  ClearAllPedProps(ped)

  local room = Config.AdminStudio and Config.AdminStudio.StudioCoords
  if room then
    SetEntityCoordsNoOffset(ped, room.x, room.y, room.z, false, false, false)
    if room.w then SetEntityHeading(ped, room.w) end
  end
  ClearPedTasksImmediately(ped)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  SetPedCanRagdoll(ped, false)

  -- This snapshot is only the clean temporary model used by category reset.
  -- adminOriginalAppearance remains untouched until the whole panel closes.
  saveClothes = {}
  snapshotCurrentClothes()
  if StartClothingAdminStudio then StartClothingAdminStudio() end
  setShopPlayerLocked(true)
  if SetShopCameraFixedMode then SetShopCameraFixedMode(true) end
  CreateSkinCam('body')

  local counts = computeCounts()
  SendNUIMessage({ type = 'clothingCounts', counts = counts })
  cb({ success = true, gender = gender, counts = counts })
  -- Let the NUI reset its old-gender rows before the fresh catalog arrives.
  CreateThread(function()
    Wait(50)
    TriggerServerEvent('nvCloth:server:getCachedShopCatalog', GetGameTimer(), currentShopKey or 'clothes', gender, true)
  end)
end)

RegisterNUICallback("adminBulkToggleItems", function(data, cb)
  data = type(data) == 'table' and data or {}
  TriggerServerEvent('nvCloth:server:adminBulkToggleItems', data)
  cb({ success = true })
end)

RegisterNUICallback('saveBagPairing', function(data, cb)
  data = type(data) == 'table' and data or {}

  -- The ped is wearing the TARGET gender model at this point (that is what the
  -- pairing overlay previews), so this is the only moment the target bag's
  -- collection address can be read. Collections are per-model, so the source
  -- gender's address cannot be read from here -- the server reuses the one
  -- already stored on the source row from its capture.
  local targetDrawable = tonumber(data.targetDrawable)
  if targetDrawable then
    -- Bags are component 5.
    local collection, localIndex = NvClothCollection.read(
      PlayerPedId(), 'component', 5, targetDrawable)
    if collection then
      data.targetCollection = collection
      data.targetCollectionLocalId = localIndex
    end
  end

  TriggerServerEvent('nvCloth:server:saveBagPairing', data)
  cb({ success = true })
end)

-- Admin inventory icon capture moved to client/cl_capture.lua


RegisterNetEvent('nvCloth:client:cachedShopCatalog', function(requestId, rows)
  SendNUIMessage({
    type = 'clothingCatalog',
    requestId = requestId,
    catalog = rows or {}
  })
end)

RegisterNetEvent('nv_cloth:client:storeDetailsResult', function(payload)
  SendNUIMessage({
    type = 'storeOwnership',
    store = payload
  })
end)

local function refreshActiveStoreDetails(shopId)
  local activeShopId = shopId or (currentShopData and currentShopData.id)
  if not activeShopId and exports[GetCurrentResourceName()] and exports[GetCurrentResourceName()].GetActiveShop then
    activeShopId = exports[GetCurrentResourceName()]:GetActiveShop()
  end
  if activeShopId then
    TriggerServerEvent('nv_cloth:server:getStoreDetails', activeShopId)
  end
end

RegisterNetEvent('nv_cloth:client:storeUpdated', function(shopId)
  refreshActiveStoreDetails(shopId)
end)

RegisterNetEvent('nv_cloth:client:storePurchased', function(shopId)
  refreshActiveStoreDetails(shopId)
end)

RegisterNUICallback('buyStore', function(data, cb)
  local shopId = (data and data.shopId) or (currentShopData and currentShopData.id)
  if not shopId and exports[GetCurrentResourceName()] and exports[GetCurrentResourceName()].GetActiveShop then
    shopId = exports[GetCurrentResourceName()]:GetActiveShop()
  end
  if shopId then
    TriggerServerEvent('nv_cloth:server:buyStore', shopId)
  end
  cb({ ok = true })
end)

RegisterNUICallback('manageStore', function(data, cb)
  data = type(data) == 'table' and data or {}
  local shopId = data.shopId or (currentShopData and currentShopData.id)
  if not shopId and exports[GetCurrentResourceName()] and exports[GetCurrentResourceName()].GetActiveShop then
    shopId = exports[GetCurrentResourceName()]:GetActiveShop()
  end
  if shopId then
    data.shopId = shopId
    TriggerServerEvent('nv_cloth:server:manageStore', data)
  end
  cb({ ok = true })
end)

RegisterNUICallback('payStoreTax', function(data, cb)
  local shopId = (data and data.shopId) or (currentShopData and currentShopData.id)
  if not shopId and exports[GetCurrentResourceName()] and exports[GetCurrentResourceName()].GetActiveShop then
    shopId = exports[GetCurrentResourceName()]:GetActiveShop()
  end
  if shopId then
    TriggerServerEvent('nv_cloth:server:payStoreTax', shopId)
  end
  cb({ ok = true })
end)

RegisterNUICallback('withdrawStoreBalance', function(data, cb)
  local shopId = (data and data.shopId) or (currentShopData and currentShopData.id)
  if not shopId and exports[GetCurrentResourceName()] and exports[GetCurrentResourceName()].GetActiveShop then
    shopId = exports[GetCurrentResourceName()]:GetActiveShop()
  end
  if shopId then
    TriggerServerEvent('nv_cloth:server:withdrawStoreBalance', shopId)
  end
  cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  if opened then closeShopRoutine() end
  DestroySkinCam()
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
end)
