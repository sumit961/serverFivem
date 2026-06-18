--========================================================
-- nvCloth – Buy clothing into cm-inventory, no ESX/QB, no DB skin save
--========================================================

local BLOCKED_CATEGORIES = {
  mask = true,
  arms = true,
  gloves = true,
}


local EQUIP_SLOT_BY_CATEGORY = {
  tshirt = 'shirt', torso = 'outerwear', pants = 'pants', legs = 'pants', shoes = 'shoes',
  chains = 'accessory', bags = 'bag', hat = 'headwear', glasses = 'glasses',
  earrings = 'earrings', watches = 'watch'
}

local CATEGORY_COMPONENTS = {
  tshirt   = { type = 'component', index = 8,  label = 'T-Shirt' },
  torso    = { type = 'component', index = 11, label = 'Torso' },
  pants    = { type = 'component', index = 4,  label = 'Pants' },
  shoes    = { type = 'component', index = 6,  label = 'Shoes' },
  chains   = { type = 'component', index = 7,  label = 'Chain' },
  bags     = { type = 'component', index = 5,  label = 'Bag' },
  hat      = { type = 'prop',      index = 0,  label = 'Hat' },
  glasses  = { type = 'prop',      index = 1,  label = 'Glasses' },
  earrings = { type = 'prop',      index = 2,  label = 'Earrings' },
  watches  = { type = 'prop',      index = 6,  label = 'Watch' },
}

local function notify(src, msg, typ)
  TriggerClientEvent('cm-hud:client:notify', src, tostring(msg or ''), typ or 'info')
end

local function priceFor(category, metadata)
  if type(metadata) == 'table' and tonumber(metadata.price) ~= nil then
    return math.max(0, tonumber(metadata.price) or 0)
  end
  return tonumber(Config and Config.Prices and Config.Prices[category]) or 0
end

local function cmItemsCall(method, ...)
  if GetResourceState('cm-items') ~= 'started' then return nil end
  local args = { ... }

  local ok, result, extra = pcall(function()
    return exports['cm-items'][method](table.unpack(args))
  end)
  if ok and result ~= nil then return result, extra end

  ok, result, extra = pcall(function()
    return exports['cm-items'][method](exports['cm-items'], table.unpack(args))
  end)
  if ok and result ~= nil then return result, extra end

  return nil
end

local function fallbackImage(gender, componentType, componentIndex, drawable)
  gender = tostring(gender or 'male'):lower() == 'female' and 'female' or 'male'
  local propPrefix = tostring(componentType or ''):lower() == 'prop' and 'prop_' or ''
  drawable = tonumber(drawable)
  if not drawable or drawable < 0 then return 'nui://cm-items/ui/images/clothing.png' end
  return ('nui://cm-items/ui/images/clothing/%s_%s%s_%s.png'):format(gender, propPrefix, tostring(componentIndex), tostring(drawable))
end

local function normaliseItem(raw)
  if type(raw) ~= 'table' then return nil end

  local category = tostring(raw.category or raw.type or ''):lower()
  if BLOCKED_CATEGORIES[category] then return nil, 'This category is not sold here.' end

  local def = CATEGORY_COMPONENTS[category]
  if not def then return nil, 'Invalid clothing category.' end

  local drawable = tonumber(raw.drawable or raw.drawableId or raw.component or raw.componentId)
  local texture = tonumber(raw.texture or raw.textureId or 0) or 0

  if drawable == nil then return nil, 'Invalid clothing drawable.' end

  local label = raw.label or raw.name or ('%s %s/%s'):format(def.label, drawable, texture)
  local incoming = type(raw.metadata) == 'table' and raw.metadata or {}
  local gender = incoming.gender or raw.gender or raw.sex or raw.pedGender or 'male'

  -- cm-items is the single source for clothing metadata + image path.
  local built = cmItemsCall('BuildClothingMetadata', category, raw, {
    label = label,
    gender = gender,
    purchasedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
  })

  if type(built) == 'table' then
    built.itemName = built.itemName or ('clothing_' .. category)
    built.categoryType = built.categoryType or category
    built.componentType = built.componentType or def.type
    built.componentIndex = built.componentIndex or def.index
    built.drawableId = tonumber(built.drawableId) or drawable
    built.textureId = tonumber(built.textureId) or texture
    built.label = built.label or label
    built.description = built.description or ('%s clothing item'):format(def.label)
    built.itemType = built.itemType or 'clothing'
    built.rarity = built.rarity or 'normal'
    built.purchasedAt = built.purchasedAt or os.date('!%Y-%m-%dT%H:%M:%SZ')
    return built
  end

  local meta = {
    itemName = 'clothing_' .. category,
    categoryType = category,
    componentType = def.type,
    componentIndex = def.index,
    drawableId = tonumber(incoming.drawableId or incoming.drawable) or drawable,
    textureId = tonumber(incoming.textureId or incoming.texture) or texture,
    gender = tostring(gender):lower() == 'female' and 'female' or 'male',
    arms = tonumber(incoming.arms),
    armsTexture = tonumber(incoming.armsTexture) or 0,
    undershirt = tonumber(incoming.undershirt),
    undershirtTexture = tonumber(incoming.undershirtTexture) or 0,
    label = incoming.label or label,
    description = ('%s clothing item'):format(def.label),
    itemType = 'clothing',
    rarity = 'normal',
    purchasedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
  }
  meta.image = fallbackImage(meta.gender, meta.componentType, meta.componentIndex, meta.drawableId)
  meta.icon = meta.image
  return meta
end

RegisterNetEvent('nvCloth:buyClothes')
AddEventHandler('nvCloth:buyClothes', function(method, outfit)
  local src = source
  method = method == 'cash' and 'cash' or 'bank'

  local rawItems = outfit and outfit.items or {}
  if type(rawItems) ~= 'table' or #rawItems == 0 then
    notify(src, 'No clothing selected.', 'error')
    TriggerClientEvent('nvCloth:client:purchaseFailed', src)
    return
  end

  local total = 0
  local metadataItems = {}

  for _, raw in ipairs(rawItems) do
    local meta, err = normaliseItem(raw)
    if not meta then
      notify(src, err or 'Invalid clothing item.', 'error')
      TriggerClientEvent('nvCloth:client:purchaseFailed', src)
      return
    end

    if meta.catalogDisabled == true or meta.enabled == false then
      notify(src, 'This clothing item is not available.', 'error')
      TriggerClientEvent('nvCloth:client:purchaseFailed', src)
      return
    end

    total = total + priceFor(meta.categoryType, meta)
    metadataItems[#metadataItems + 1] = meta
  end

  -- Check inventory capacity before taking money. This avoids charging the player when the item cannot fit.
  if GetResourceState('cm-inventory') ~= 'started' then
    notify(src, 'Inventory is not available.', 'error')
    TriggerClientEvent('nvCloth:client:purchaseFailed', src)
    return
  end

  for _, meta in ipairs(metadataItems) do
    local okCall, canCarry, carryErr = pcall(function()
      return exports['cm-inventory']:CanCarryItem(src, meta.itemName, 1)
    end)
    if okCall and canCarry ~= true then
      notify(src, tostring(carryErr or 'You cannot carry this item.'), 'error')
      TriggerClientEvent('nvCloth:client:purchaseFailed', src)
      return
    elseif not okCall then
      notify(src, 'Could not check inventory capacity.', 'error')
      TriggerClientEvent('nvCloth:client:purchaseFailed', src)
      return
    end
  end

  if total > 0 then
    local paid = exports['cm-core']:RemoveMoney(src, method, total)
    if paid ~= true then
      notify(src, 'You do not have enough money.', 'error')
      TriggerClientEvent('nvCloth:client:purchaseFailed', src)
      return
    end
  end

  for _, meta in ipairs(metadataItems) do
    local itemName = meta.itemName
    meta.itemName = nil

    -- Buy-to-inventory only. Do not auto-save appearance or directly equip from the shop.
    local added = exports['cm-inventory']:AddItem(src, itemName, 1, meta)
    if added ~= true then
      notify(src, ('Inventory full or item missing: %s'):format(itemName), 'error')
      TriggerClientEvent('nvCloth:client:purchaseFailed', src)
      return
    end
  end

  notify(src, 'Clothing purchased. Check your inventory.', 'success')
  TriggerClientEvent('nvCloth:client:purchaseComplete', src)
end)

RegisterNetEvent('nvCloth:addClothToInventory')
AddEventHandler('nvCloth:addClothToInventory', function()
  -- Disabled: old nvCloth DB inventory insert removed.
end)

--========================================================
-- v7 cached catalog bridge
-- This lets shop UI/client request catalog rows from cm-items memory cache.
-- It does not query SQL on every shop open; cm-items owns the server cache.
--========================================================
RegisterNetEvent('nvCloth:server:getCachedShopCatalog', function(requestId, shopName, gender)
  local src = source
  local rows = {}
  if GetResourceState('cm-items') == 'started' then
    local ok, result = pcall(function()
      return exports['cm-items']:GetShopClothingCatalog(shopName or 'city', gender or 'male')
    end)
    if ok and type(result) == 'table' then rows = result end
  end
  TriggerClientEvent('nvCloth:client:cachedShopCatalog', src, requestId, rows)
end)
