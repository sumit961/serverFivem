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
  hat      = { type = "prop",      index = 0  },
  glasses  = { type = "prop",      index = 1  },
  earrings = { type = "prop",      index = 2  },
  watches  = { type = "prop",      index = 6  },
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

function NvCloth_IsAdminShop() return isAdminShop == true end
function NvCloth_GetCurrentShopKey() return currentShopKey or 'clothes' end
function NvCloth_GetCurrentShopData() return currentShopData end
function NvCloth_GetReturnCoords() return currentShopCoords end

local function setClothingPositionSaveBlocked(block)
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
  if type(setOutfit) == 'function' and type(saveClothes) == 'table' then
    setOutfit(saveClothes)
  else
    local ped = PlayerPedId()
    if type(saveClothes) == 'table' then
      for category, item in pairs(saveClothes) do
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
  end
end

--- Envoie l’état complet d’ouverture au NUI (avec init si première fois)
local function sendOpenMessage(label, cats, counts, isOpen)
  if not nuiInitialized then
    SendNUIMessage({
      type         = "openClothShop",
      value        = isOpen,
      prices       = Config.Prices,
      label        = label,
      categories   = cats,
      translations = Config.Translations[Config.Lang],
      counts       = counts,
      useCatalogOnly = Config.UseCatalogOnly ~= false,
    })
    nuiInitialized = true
  else
    SendNUIMessage({
      type       = "openClothShop",
      value      = isOpen,
      label      = label,
      categories = cats,
      counts     = counts,
      useCatalogOnly = Config.UseCatalogOnly ~= false,
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

  opened = false
  isAdminShop = false
  -- Close UI first, then forcefully destroy every scripted camera.
  applyUiGameFocus(false)
  SendNUIMessage({ type = "adminMode", value = false })
  SendNUIMessage({ type = "openClothShop", value = false })
  restoreShopPreviewClothes()
  if StopClothingAdminStudio then StopClothingAdminStudio() end
  if SetShopCameraFixedMode then SetShopCameraFixedMode(false) end
  DestroySkinCam()
  Wait(75)
  RenderScriptCams(false, false, 0, true, true)
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

  local ped = PlayerPedId()
  local startCoords = GetEntityCoords(ped)
  local startHeading = GetEntityHeading(ped)
  setClothingPositionSaveBlocked(true)

  -- Every shopper/admin gets their own private dressing room instance.
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

  setShopPlayerLocked(true)
  if SetShopCameraFixedMode then SetShopCameraFixedMode(true) end
  CreateSkinCam("body")

  SendNUIMessage({
    type = "adminMode",
    value = isAdminShop,
    shopKey = currentShopKey,
  })
end

--========================================================
-- Commande de test
--========================================================
RegisterCommand("clothShop", function()
  openClothShop("Clothing Store", { "hat", "torso", "arms", "tshirt", "pants", "shoes", "glasses" }, "clothes", nil, false)
end, false)

-- /clothingadmin is registered server-side so normal players cannot open it.
RegisterNetEvent('nvCloth:client:openAdminPanel', function()
  openClothShop("ADMIN PANEL", { "torso", "arms", "tshirt", "pants", "shoes", "hat", "glasses", "earrings", "chains", "bags", "watches" }, "clothes", nil, true)
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



RegisterNUICallback("adminToggleItem", function(data, cb)
  local ped = PlayerPedId()
  local category = tostring(data.category or data.type or ''):lower()
  local cat = categories[category]
  if not cat then
    cb({ success = false, error = 'invalid_category' })
    return
  end

  local drawable = tonumber(data.drawableId or data.drawable)
  local texture = -1 -- admin toggles the whole drawable; all textures come with it
  if not drawable then
    cb({ success = false, error = 'invalid_drawable' })
    return
  end

  local gender = GetEntityModel(ped) == GetHashKey('mp_f_freemode_01') and 'female' or 'male'
  local enabled = data.enabled == true or data.enabled == 1

  local payload = {
    shop = currentShopKey or 'clothes',
    gender = gender,
    category = category,
    componentType = cat.type,
    componentIndex = cat.index,
    drawableId = drawable,
    textureId = -1, -- store one row for this drawable; all textures are included
    label = data.label,
    price = data.price,
    enabled = enabled,
  }

  -- For torso, admin can select jacket, then select matching arms/t-shirt,
  -- and press the admin button. We save current component 3 + 8 as the fit.
  if category == 'torso' then
    payload.arms = GetPedDrawableVariation(ped, 3)
    payload.armsTexture = GetPedTextureVariation(ped, 3)
    payload.undershirt = GetPedDrawableVariation(ped, 8)
    payload.undershirtTexture = GetPedTextureVariation(ped, 8)
  end

  -- Bags need their capacity level saved into catalog metadata.
  -- The NUI admin panel sends this when capturing icons, but the direct
  -- SAVE CURRENT TEXTURE/adminToggle path also needs to forward it.
  if category == 'bags' then
    local level = tonumber(data.bagLevel or data.bag_level or data.level) or 1
    level = math.max(1, math.min(4, math.floor(level)))
    payload.bagLevel = level
    payload.bag_level = level
    payload.level = level
  end

  TriggerServerEvent('nvCloth:server:adminToggleItem', payload)

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


AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  if opened then closeShopRoutine() end
  DestroySkinCam()
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
end)
