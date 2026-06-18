--========================================================
-- nvCloth – Client (CLEAN)
-- - Prévisualisation et application de vêtements/props
-- - Compatible "skinchanger" (si Config.AppearanceRessource == "skinchanger")
-- - Callbacks NUI: sélection article, textures, reset, achat, etc.
-- - Événements: nvCloth:getClothes, nvCloth:resetClothes
-- - Envoi des “counts” (variations disponibles) au NUI au chargement
--========================================================

--========================================================
-- ÉTAT / CONFIG
--========================================================

outfitToBuy = nil

-- Map des champs skinchanger par catégorie (si utilisé)
local SKINCHANGER_FIELDS = {
  tshirt   = { d = "tshirt_1",  t = "tshirt_2"  },
  torso    = { d = "torso_1",   t = "torso_2"   },
  arms     = { d = "arms",      t = "arms_2"    },
  pants    = { d = "pants_1",   t = "pants_2"   },
  shoes    = { d = "shoes_1",   t = "shoes_2"   },
  chains   = { d = "chain_1",   t = "chain_2"   },
  bags     = { d = "bags_1",    t = "bags_2"    },
  hat      = { d = "helmet_1",  t = "helmet_2"  },
  glasses  = { d = "glasses_1", t = "glasses_2" },
  earrings = { d = "ears_1",    t = "ears_2"    },
  watches  = { d = "watches_1", t = "watches_2" },
}

--========================================================
-- HELPERS
--========================================================

--- Applique un changement via skinchanger (si activé), sinon renvoie false.
---@param category string
---@param drawable integer
---@param texture integer|nil
---@return boolean applied
local function ApplyWithSkinchanger(category, drawable, texture)
  if Config.AppearanceRessource ~= "skinchanger" or GetResourceState('skinchanger') ~= 'started' then
    return false
  end

  local map = SKINCHANGER_FIELDS[category]
  if not map then return false end

  if map.d then
    TriggerEvent("skinchanger:change", map.d, drawable)
  end

  if map.t then
    TriggerEvent("skinchanger:change", map.t, texture or 0)
  end

  return true
end

--- Raccourci de notification localisée
local function notifyKey(key)
  local T = Config.Translations[Config.Lang]
  if showNotification and T and T[key] then
    showNotification(T[key])
  end
end


local function getPedGender(ped)
  local model = GetEntityModel(ped or PlayerPedId())
  return model == GetHashKey('mp_f_freemode_01') and 'female' or 'male'
end

local function normalizeSleeveStyle(style)
  local value = tostring(style or ''):lower()
  if value == '' then return nil end
  if value == 'full' or value == 'long' or value == 'longsleeve' or value == 'long_sleeve' or value == 'fullsleeve' or value == 'full_sleeve' then
    return 'full'
  end
  if value == 'half' or value == 'short' or value == 'shortsleeve' or value == 'short_sleeve' or value == 'halfsleeve' or value == 'half_sleeve' then
    return 'half'
  end
  return nil
end

local function sleeveStyleFromArms(arms)
  arms = tonumber(arms)
  if arms == 6 then return 'full' end
  if arms == 5 then return 'half' end
  return nil
end

local function applySleevePreset(style)
  style = normalizeSleeveStyle(style)
  local ped = PlayerPedId()
  if style == 'full' then
    SetPedComponentVariation(ped, 3, 6, 0, 0)
    print('[CM-CLOTH] Full sleeve preset applied: arms/body = 6')
    ExecuteCommand('cmclothinfo')
    return true
  elseif style == 'half' then
    SetPedComponentVariation(ped, 3, 5, 0, 0)
    print('[CM-CLOTH] Half sleeve preset applied: arms/body = 5')
    ExecuteCommand('cmclothinfo')
    return true
  end
  print('Usage: /cmsleeve <full|half>')
  return false
end

local function resolveTorsoFit(gender, drawable, texture, fallback)
  if GetResourceState('cm-items') ~= 'started' then return fallback or {} end
  local ok, fit = pcall(function()
    return exports['cm-items']:ResolveTorsoFit(gender, drawable, texture, fallback or {})
  end)
  if ok and type(fit) == 'table' then return fit end
  ok, fit = pcall(function()
    return exports['cm-items'].ResolveTorsoFit(gender, drawable, texture, fallback or {})
  end)
  if ok and type(fit) == 'table' then return fit end
  return fallback or {}
end

local function applyTorsoFitForPreview(ped, torsoDrawable, torsoTexture)
  local fit = resolveTorsoFit(getPedGender(ped), torsoDrawable, torsoTexture, {
    arms = GetPedDrawableVariation(ped, 3),
    armsTexture = GetPedTextureVariation(ped, 3),
    undershirt = GetPedDrawableVariation(ped, 8),
    undershirtTexture = GetPedTextureVariation(ped, 8),
  })

  if fit.undershirt ~= nil then
    SetPedComponentVariation(ped, 8, tonumber(fit.undershirt) or 0, tonumber(fit.undershirtTexture) or 0, 0)
  end
  if fit.arms ~= nil then
    SetPedComponentVariation(ped, 3, tonumber(fit.arms) or 0, tonumber(fit.armsTexture) or 0, 0)
  end
end

--- Extrait un tableau d’items depuis une charge utile hétérogène (cart/selected/outfit/etc.)
---@param payload table
---@return table items, string outfitName
local function extractItemsAndName(payload)
  payload = type(payload) == 'table' and payload or {}

  local items = payload.items or payload.cart or payload.selectedItems or payload.selected
  if not items and payload.outfit and payload.outfit.items then
    items = payload.outfit.items
  end

  -- Compatibility: some UIs call buyItem with one item directly instead of an items/cart array.
  if not items and (payload.category or payload.type) and (payload.drawable or payload.drawableId or payload.component or payload.componentId) then
    items = { payload }
  end

  items = type(items) == 'table' and items or {}

  local name = payload.name
  if not name and payload.outfit and payload.outfit.name then
    name = payload.outfit.name
  end
  name = name or "Tenue"

  return items, name
end

--- Applique un item (component ou prop) selon la table `categories`
---@param ped number
---@param category string
---@param drawable integer
---@param texture integer
local function applyItem(ped, category, drawable, texture)
  local cat = categories[category]
  if not cat then
    notifyKey("invalid-category")
    return
  end

  -- cm-core uses native ped clothing. Do native apply first so store preview is instant.
  if cat.type == "component" then
    SetPedComponentVariation(ped, cat.index, drawable, texture or 0, 0)
    if category == 'torso' then
      applyTorsoFitForPreview(ped, drawable, texture or 0)
    end
  elseif cat.type == "prop" then
    if drawable ~= -1 then
      SetPedPropIndex(ped, cat.index, drawable, texture or 0, true)
    else
      ClearPedProp(ped, cat.index)
    end
  end
end

--- Change uniquement la texture de l’élément actuellement porté dans la catégorie
---@param ped number
---@param category string
---@param texture integer
local function changeCurrentTexture(ped, category, texture)
  local cat = categories[category]
  if not cat then
    notifyKey("invalid-category")
    return
  end

  if cat.type == "prop" then
    local cur = GetPedPropIndex(ped, cat.index)
    if cur ~= -1 then
      if not ApplyWithSkinchanger(category, cur, texture) then
        SetPedPropIndex(ped, cat.index, cur, texture, true)
      end
    else
      -- rien porté -> clear
      if not ApplyWithSkinchanger(category, -1, 0) then
        ClearPedProp(ped, cat.index)
      end
    end
  else
    local cur = GetPedDrawableVariation(ped, cat.index)
    if not ApplyWithSkinchanger(category, cur, texture) then
      SetPedComponentVariation(ped, cat.index, cur, texture, 0)
    end
  end
end

--- Applique une tenue complète (items = { {category, drawable, texture}, ... })
---@param items table
local function setOutfit(items)
  local ped = PlayerPedId()
  items = items or {}

  -- Supports cart arrays: { { category='torso', drawable=1, texture=0 }, ... }
  if items[1] ~= nil then
    for _, it in ipairs(items) do
      if it.category and it.drawable ~= nil and it.texture ~= nil then
        applyItem(ped, it.category, it.drawable, it.texture)
      end
    end
    return
  end

  -- Supports saved snapshots: saveClothes[category] = { drawable=..., texture=... }
  for category, it in pairs(items) do
    if categories[category] and it.drawable ~= nil and it.texture ~= nil then
      applyItem(ped, category, it.drawable, it.texture)
    end
  end
end

--- Restaure une catégorie depuis `saveClothes[category]`
---@param ped number
---@param category string
local function restoreCategoryFromSaved(ped, category)
  local cat = categories[category]
  if not (cat and saveClothes and saveClothes[category]) then
    notifyKey("no-saved-outfit")
    return
  end

  local d = saveClothes[category].drawable
  local t = saveClothes[category].texture

  if cat.type == "prop" then
    if d ~= -1 then
      if not ApplyWithSkinchanger(category, d, t) then
        SetPedPropIndex(ped, cat.index, d, t, true)
      end
    else
      if not ApplyWithSkinchanger(category, -1, 0) then
        ClearPedProp(ped, cat.index)
      end
    end
  else
    if not ApplyWithSkinchanger(category, d, t) then
      SetPedComponentVariation(ped, cat.index, d, t, 0)
    end
  end
end

--- Attend que le modèle du joueur soit freemode (mp_m_freemode_01 / mp_f_freemode_01)
local function WaitForFreemodeModel()
  local tries, maxTries = 0, 1000
  while true do
    local ped = PlayerPedId()
    local model = GetEntityModel(ped)
    if model == `mp_m_freemode_01` or model == `mp_f_freemode_01` then
      break
    end
    tries = tries + 1
    if tries >= maxTries then break end
    Wait(200)
  end
end


RegisterNetEvent('nvCloth:client:purchaseComplete', function()
  -- Purchase is buy-to-inventory only. Restore the pre-shop outfit after buying.
  outfitToBuy = nil
  setOutfit(saveClothes)
  showNotification('Clothing purchased. Check your inventory.', 'success')
end)

RegisterNetEvent('nvCloth:client:purchaseFailed', function()
  setOutfit(saveClothes)
end)

--========================================================
-- NUI: ACTIONS SUR ARTICLES
--========================================================

-- Applique l’article choisi et renvoie le nombre de textures possibles
RegisterNUICallback("sendSelectedArticle", function(data, cb)
  local ped = PlayerPedId()
  local category = tostring(data.category or data.type or '')
  local cat = categories[category]
  local drawable = tonumber(data.drawable or data.drawableId or data.component or data.componentId)
  local texture  = tonumber(data.texture or data.textureId or 0) or 0

  if not cat then
    notifyKey("invalid-category")
    cb({ success = false })
    return
  end
  if drawable == nil then
    showNotification("Valeurs de vêtement invalides.")
    cb({ success = false })
    return
  end

  -- Appliquer immediately for store preview
  applyItem(ped, category, drawable, texture)

  -- Nombre de textures disponibles pour ce drawable
  local count
  if cat.type == "component" then
    count = GetNumberOfPedTextureVariations(ped, cat.index, drawable)
  else
    count = GetNumberOfPedPropTextureVariations(ped, cat.index, drawable)
  end
  cb({ count = count })
end)

-- Reset d’une catégorie depuis la sauvegarde locale `saveClothes`
RegisterNUICallback("resetCloth", function(data, cb)
  local category = data.category
  local ped = PlayerPedId()
  local cat = categories[category]

  if not cat then
    notifyKey("invalid-category")
    cb({ success = false })
    return
  end

  if not saveClothes or not saveClothes[category] then
    notifyKey("no-saved-outfit")
    cb({ success = false })
    return
  end

  restoreCategoryFromSaved(ped, category)
  cb({ success = true })
end)

-- Changement de texture de l’élément en cours
RegisterNUICallback("changeTexture", function(data, cb)
  local ped = PlayerPedId()
  local cat = categories[data.category]
  local texture = data.texture

  if not cat then
    notifyKey("invalid-category")
    cb({ success = false })
    return
  end

  changeCurrentTexture(ped, tostring(data.category or data.type or ''), tonumber(texture) or 0)
  cb({ success = true })
end)

-- Applique une tenue (prévisualisation ou finale)
RegisterNUICallback("setOutfit", function(data, cb)
  local ped = PlayerPedId()
  local outfit = data.outfit or {}
  setOutfit(outfit)

  if not data.preview then
    notifyKey("outfit-applied")
  end

  cb({ success = true })
end)

--========================================================
-- NUI: RESET / CLEAR (restaurent simplement la tenue sauvegardée)
--========================================================

local function nuiReply(cb, payload)
  if type(cb) == "function" then
    cb(payload or { success = true })
  end
end

-- NUI callbacks always pass (data, cb).
-- Keep the unused first arg or cb becomes nil/table and Axios reports Network Error.
local function resetToSaved(_, cb)
  setOutfit(saveClothes)
  nuiReply(cb, { success = true })
end

RegisterNUICallback("resetAllClothes", resetToSaved)
RegisterNUICallback("resetCart",        resetToSaved)
RegisterNUICallback("clearCart",        resetToSaved)

RegisterNUICallback("reset", function(_, cb)
  setOutfit(saveClothes)
  nuiReply(cb, "ok")
end)

RegisterNUICallback("clear", function(_, cb)
  setOutfit(saveClothes)
  nuiReply(cb, "ok")
end)

RegisterNUICallback("resetCartItems", function(_, cb)
  setOutfit(saveClothes)
  nuiReply(cb, "ok")
end)

RegisterNUICallback("clearCartItems", function(_, cb)
  setOutfit(saveClothes)
  nuiReply(cb, "ok")
end)

--========================================================
-- ACHATS
--========================================================

local function buildBuyMetadata(item)
  local ped = PlayerPedId()
  local category = tostring(item.category or item.type or ''):lower()
  local model = GetEntityModel(ped)
  local gender = model == GetHashKey('mp_f_freemode_01') and 'female' or 'male'

  local metadata = {
    categoryType = category,
    drawableId = tonumber(item.drawable or item.drawableId or item.component or item.componentId) or 0,
    textureId = tonumber(item.texture or item.textureId or 0) or 0,
    gender = gender,
    label = item.label or item.name or ('Clothing ' .. category)
  }

  -- Torso items must remember matching arms and undershirt to prevent clipping.
  if category == 'torso' then
    metadata.arms = GetPedDrawableVariation(ped, 3)
    metadata.armsTexture = GetPedTextureVariation(ped, 3)
    metadata.undershirt = GetPedDrawableVariation(ped, 8)
    metadata.undershirtTexture = GetPedTextureVariation(ped, 8)

    -- Your clothing pack rule: full sleeve = arms 6, half sleeve = arms 5.
    -- This tag helps cm-items keep using the same fit in inventory/spawn.
    metadata.sleeveStyle = normalizeSleeveStyle(item.sleeveStyle or item.sleeve or item.sleeveType) or sleeveStyleFromArms(metadata.arms)
  end

  return metadata
end

local function buyCommon(data, payment)
  local items, name = extractItemsAndName(data)

  -- Arms/gloves are preview-only. They are saved inside torso metadata, not bought as a separate item.
  local purchasable = {}
  for _, item in ipairs(items) do
    local category = tostring(item.category or item.type or ''):lower()
    if category ~= 'arms' and category ~= 'gloves' then
      item.metadata = buildBuyMetadata(item)
      purchasable[#purchasable + 1] = item
    end
  end

  if #purchasable == 0 then
    showNotification('No purchasable clothing selected. Arms/body is preview-only and is saved inside torso items.', 'error')
    outfitToBuy = nil
    return
  end

  outfitToBuy = { items = purchasable, name = name }
  TriggerServerEvent("nvCloth:buyClothes", payment, outfitToBuy)

  -- Strip preview immediately. Bought clothes stay as physical inventory items.
  setOutfit(saveClothes)
end

RegisterNUICallback("buyClothes", function(data, cb)
  local method = data.paymentMethod
  if method == "card" then method = "bank" end -- compat UI
  buyCommon(data, method)
  cb("ok")
end)

RegisterNUICallback("buy", function(data, cb)
  local method = data.paymentMethod
  if method == "card" then method = "bank" end
  buyCommon(data, method)
  cb("ok")
end)

RegisterNUICallback("buyCash", function(data, cb)
  buyCommon(data, "cash")
  cb("ok")
end)

RegisterNUICallback("buyBank", function(data, cb)
  buyCommon(data, "bank")
  cb("ok")
end)

RegisterNUICallback("buyCard", function(data, cb)
  buyCommon(data, "card") -- côté serveur, traite "card" comme il faut si nécessaire
  cb("ok")
end)



--========================================================
-- CM native clothing bridge
-- Used by cm-inventory / cm-itemactions when clothing items are equipped.
--========================================================
local CM_CATEGORY_ALIASES = {
  legs = 'pants', pants = 'pants', watches = 'watches', watch = 'watches',
  jacket = 'torso', outerwear = 'torso', shirt = 'tshirt', tshirt = 'tshirt',
  chain = 'chains', accessory = 'chains', bag = 'bags', headwear = 'hat', hat = 'hat',
  arms = 'arms', gloves = 'arms'
}


local function normaliseCategory(category)
  category = tostring(category or ''):lower()
  return CM_CATEGORY_ALIASES[category] or category
end

function CMApplyClothingItem(category, drawable, texture)
  category = normaliseCategory(category)
  drawable = tonumber(drawable)
  texture = tonumber(texture) or 0
  if drawable == nil then return false end

  local ped = PlayerPedId()
  local cat = categories and categories[category]
  if not cat then return false end

  -- Always apply native first for cm-core. This fixes preview/equip when skinchanger is not actually running.
  if cat.type == 'prop' then
    if drawable < 0 then
      ClearPedProp(ped, cat.index)
    else
      SetPedPropIndex(ped, cat.index, drawable, texture, true)
    end
  else
    SetPedComponentVariation(ped, cat.index, drawable, texture, 0)
    if category == 'torso' then
      applyTorsoFitForPreview(ped, drawable, texture)
    end
  end

  return true
end

RegisterNetEvent('nvCloth:client:equipClothingItem', function(category, drawable, texture)
  CMApplyClothingItem(category, drawable, texture)
end)

exports('ApplyClothingItem', CMApplyClothingItem)


-- Debug helpers for fixing torso/arms clipping.
-- Use /cmclothinfo to see current component ids, then test arms with /cmarms 4 0.
RegisterCommand('cmclothinfo', function()
  local ped = PlayerPedId()
  print(('[CM-CLOTH] gender=%s torso=%s:%s arms=%s:%s tshirt=%s:%s pants=%s:%s shoes=%s:%s'):format(
    getPedGender(ped),
    GetPedDrawableVariation(ped, 11), GetPedTextureVariation(ped, 11),
    GetPedDrawableVariation(ped, 3), GetPedTextureVariation(ped, 3),
    GetPedDrawableVariation(ped, 8), GetPedTextureVariation(ped, 8),
    GetPedDrawableVariation(ped, 4), GetPedTextureVariation(ped, 4),
    GetPedDrawableVariation(ped, 6), GetPedTextureVariation(ped, 6)
  ))
end, false)

RegisterCommand('cmarms', function(_, args)
  local ped = PlayerPedId()
  local arms = tonumber(args[1])
  local texture = tonumber(args[2]) or 0
  if arms == nil then
    print('Usage: /cmarms <armsDrawable> [armsTexture]')
    return
  end
  SetPedComponentVariation(ped, 3, arms, texture, 0)
  print(('[CM-CLOTH] Set arms to %s:%s. If fixed, add this torso to CMItems.Clothing.TorsoFit.'):format(arms, texture))
  ExecuteCommand('cmclothinfo')
end, false)

RegisterCommand('cmsleeve', function(_, args)
  applySleevePreset(args[1])
end, false)

RegisterCommand('cmfullsleeve', function()
  applySleevePreset('full')
end, false)

RegisterCommand('cmhalfsleeve', function()
  applySleevePreset('half')
end, false)

RegisterCommand('cmshirt', function(_, args)
  local ped = PlayerPedId()
  local shirt = tonumber(args[1])
  local texture = tonumber(args[2]) or 0
  if shirt == nil then
    print('Usage: /cmshirt <undershirtDrawable> [undershirtTexture]')
    return
  end
  SetPedComponentVariation(ped, 8, shirt, texture, 0)
  print(('[CM-CLOTH] Set undershirt/t-shirt to %s:%s.'):format(shirt, texture))
  ExecuteCommand('cmclothinfo')
end, false)

RegisterCommand('cmupper', function(_, args)
  local ped = PlayerPedId()
  local arms = tonumber(args[1])
  local shirt = tonumber(args[2])
  local armsTexture = tonumber(args[3]) or 0
  local shirtTexture = tonumber(args[4]) or 0
  if arms == nil or shirt == nil then
    print('Usage: /cmupper <armsDrawable> <undershirtDrawable> [armsTexture] [undershirtTexture]')
    print('Example: /cmupper 4 15')
    return
  end
  SetPedComponentVariation(ped, 3, arms, armsTexture, 0)
  SetPedComponentVariation(ped, 8, shirt, shirtTexture, 0)
  print(('[CM-CLOTH] Set upper body fit arms=%s:%s undershirt=%s:%s.'):format(arms, armsTexture, shirt, shirtTexture))
  ExecuteCommand('cmclothinfo')
end, false)

RegisterCommand('cmtestfit', function(_, args)
  local ped = PlayerPedId()
  local startArms = tonumber(args[1]) or 0
  local endArms = tonumber(args[2]) or 20
  print(('[CM-CLOTH] Testing arms %s to %s. Use /cmarms <id> when you find a good one, then /cmfit.'):format(startArms, endArms))
  CreateThread(function()
    for i = startArms, endArms do
      SetPedComponentVariation(ped, 3, i, 0, 0)
      print(('[CM-CLOTH] Preview arms=%s. Wait 1200ms...'):format(i))
      Wait(1200)
    end
    ExecuteCommand('cmclothinfo')
  end)
end, false)

--========================================================
-- EVENTS
--========================================================

-- Applique une tenue reçue du serveur
RegisterNetEvent("nvCloth:getClothes", function(payload)
  local ped = PlayerPedId()
  if not payload then return end

  local items = payload.items or {}
  for _, it in ipairs(items) do
    local cat = categories[it.category]
    if cat then
      -- Comme applyItem mais inline pour limiter appels
      if cat.type == "prop" then
        if it.drawable ~= -1 then
          if not ApplyWithSkinchanger(it.category, it.drawable, it.texture) then
            SetPedPropIndex(ped, cat.index, it.drawable, it.texture, true)
          end
        else
          if not ApplyWithSkinchanger(it.category, -1, 0) then
            ClearPedProp(ped, cat.index)
          end
        end
      else
        if not ApplyWithSkinchanger(it.category, it.drawable, it.texture) then
          SetPedComponentVariation(ped, cat.index, it.drawable, it.texture, 0)
        end
      end
    end
  end
end)

-- Reset complet -> restore `saveClothes`
RegisterNetEvent("nvCloth:resetClothes", function()
  setOutfit(saveClothes)
end)

--========================================================
-- ENVOI DES COMPTEURS (variations) AU NUI
--========================================================

CreateThread(function()
  -- Attendre la session + le ped + freemode
  while true do
    if NetworkIsSessionStarted() and DoesEntityExist(PlayerPedId()) then
      break
    end
    Wait(100)
  end

  WaitForFreemodeModel()

  local ped = PlayerPedId()
  local counts = {}

  for key, cat in pairs(categories) do
    if cat.type == "component" then
      counts[key] = GetNumberOfPedDrawableVariations(ped, cat.index)
    elseif cat.type == "prop" then
      counts[key] = GetNumberOfPedPropDrawableVariations(ped, cat.index)
    end
  end

  SendNUIMessage({
    type   = "clothingCounts",
    counts = counts
  })
end)


-- Compatibility for UIs that call buyItem instead of buy/buyClothes.
RegisterNUICallback("buyItem", function(data, cb)
  local method = data.paymentMethod or data.method or data.pay or "bank"
  if method == "card" then method = "bank" end
  buyCommon(data, method)
  cb("ok")
end)

RegisterCommand('cmfit', function(_, args)
  local ped = PlayerPedId()
  local gender = getPedGender(ped)
  local torso = GetPedDrawableVariation(ped, 11)
  local torsoTexture = GetPedTextureVariation(ped, 11)
  local style = normalizeSleeveStyle(args and args[1]) or sleeveStyleFromArms(GetPedDrawableVariation(ped, 3))

  if style == 'full' then
    SetPedComponentVariation(ped, 3, 6, 0, 0)
  elseif style == 'half' then
    SetPedComponentVariation(ped, 3, 5, 0, 0)
  end

  local arms = GetPedDrawableVariation(ped, 3)
  local armsTexture = GetPedTextureVariation(ped, 3)
  local tshirt = GetPedDrawableVariation(ped, 8)
  local tshirtTexture = GetPedTextureVariation(ped, 8)

  print('[CM-CLOTH] Copy one of these into cm-items/shared/clothing.lua.')
  if style then
    print(("[CM-CLOTH] CMItems.Clothing.TorsoSleeveStyle.%s[%s] = '%s' -- %s sleeve uses arms %s"):format(
      gender, torso, style, style, arms
    ))
  end
  print(("[CM-CLOTH] %s[%s] = { default = { arms = %s, armsTexture = %s, undershirt = %s, undershirtTexture = %s } }, -- torso texture %s"):format(
    gender, torso, arms, armsTexture, tshirt, tshirtTexture, torsoTexture
  ))
end, false)

