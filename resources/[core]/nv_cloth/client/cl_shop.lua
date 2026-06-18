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
  DisplayRadar(not isOpen)
end

--- Informe l’inventaire (qs-inventory) de l’état “en cabine”
local function setInventoryClothingState(isInClothing)
  if Config.Inventory == "qs-inventory" then
    exports["qs-inventory"]:setInClothing(isInClothing)
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
    })
    nuiInitialized = true
  else
    SendNUIMessage({
      type       = "openClothShop",
      value      = isOpen,
      label      = label,
      categories = cats,
      counts     = counts,
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
function openClothShop(label, cats, shopKey)
  -- Toggle d'état
  opened = not opened

  -- qs-inventory : prévenir qu'on entre/sort de la cabine
  setInventoryClothingState(opened)

  -- S'assurer du modèle si skinchanger
  ensureFreemodeIfSkinchanger()

  -- Sauvegarder les vêtements actuels (pour reset, etc.)
  snapshotCurrentClothes()

  -- Préparer front
  applyUiGameFocus(opened)
  local counts = computeCounts()

  -- Envoyer au NUI
  sendOpenMessage(label, cats, counts, opened)

  if opened then
    local gender = GetEntityModel(PlayerPedId()) == GetHashKey('mp_f_freemode_01') and 'female' or 'male'
    TriggerServerEvent('nvCloth:server:getCachedShopCatalog', GetGameTimer(), shopKey or 'city', gender)
  end

  -- Caméra d'aperçu
  if not opened then
    DestroySkinCam()
  else
    CreateSkinCam("body")
  end
end

--========================================================
-- Commande de test
--========================================================
RegisterCommand("clothShop", openClothShop, false)

--========================================================
-- NUI: fermeture
--========================================================
RegisterNUICallback("closeMenu", function(_, cb)
  opened = false
  applyUiGameFocus(false)
  DestroySkinCam()
  DisplayRadar(true)
  setInventoryClothingState(false)
  cb("ok")
end)

-- Fermeture via event
RegisterNetEvent("nvCloth:closeMenu")
AddEventHandler("nvCloth:closeMenu", function()
  opened = false
  applyUiGameFocus(false)
  DestroySkinCam()
  DisplayRadar(true)
  setInventoryClothingState(false)
end)


RegisterNetEvent('nvCloth:client:cachedShopCatalog', function(requestId, rows)
  SendNUIMessage({
    type = 'clothingCatalog',
    requestId = requestId,
    catalog = rows or {}
  })
end)
