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

local playersInDressingRoom = {}

local function isClothingAdmin(src)
  -- Production permission. Recommended server.cfg:
  -- add_ace group.admin cm.clothing.admin allow
  -- add_principal identifier.fivem:YOUR_ID group.admin
  return IsPlayerAceAllowed(src, 'cm.clothing.admin')
      or IsPlayerAceAllowed(src, 'command.clothingadmin')
      or IsPlayerAceAllowed(src, 'command')
end

RegisterNetEvent('nvCloth:server:enterDressingRoom', function()
  local src = source
  playersInDressingRoom[src] = true
  -- Bucket per player prevents overlap/clipping when multiple players shop at the same time.
  SetPlayerRoutingBucket(src, src)
end)

RegisterNetEvent('nvCloth:server:leaveDressingRoom', function()
  local src = source
  playersInDressingRoom[src] = nil
  SetPlayerRoutingBucket(src, 0)
end)

AddEventHandler('playerDropped', function()
  local src = source
  playersInDressingRoom[src] = nil
end)

RegisterNetEvent('nvCloth:server:setPositionSaveBlocked', function(block)
  local src = source
  local value = block == true
  if Player(src) and Player(src).state then
    Player(src).state:set('inClothingStore', value, true)
    Player(src).state:set('cmClothingPreview', value, true)
    Player(src).state:set('cmSkipPositionSave', value, true)
    Player(src).state:set('ignorePositionSave', value, true)
  end
end)

RegisterCommand('clothingadmin', function(src)
  if src == 0 then
    print('[nv_cloth] /clothingadmin can only be used in-game.')
    return
  end

  if not isClothingAdmin(src) then
    notify(src, 'You do not have permission to use clothing admin.', 'error')
    return
  end

  TriggerClientEvent('nvCloth:client:openAdminPanel', src)
end, false)

local function runPositionCommand(src)
  if src == 0 then
    print('[nv_cloth] Position command can only be used in-game.')
    return
  end

  if not isClothingAdmin(src) then
    notify(src, 'You do not have permission to use this command.', 'error')
    return
  end

  TriggerClientEvent('nvCloth:client:printPosition', src)
end

RegisterCommand('cmpos', function(src)
  runPositionCommand(src)
end, false)

RegisterCommand('getpos', function(src)
  runPositionCommand(src)
end, false)

local function runTestPropCommand(src, args)
  if src == 0 then
    print('[nv_cloth] /cmtestprop can only be used in-game.')
    return
  end

  if not isClothingAdmin(src) then
    notify(src, 'You do not have permission to use this command.', 'error')
    return
  end

  local model = args and args[1] or nil
  TriggerClientEvent('nvCloth:client:testSpawnProp', src, model)
end

RegisterCommand('cmtestprop', function(src, args)
  runTestPropCommand(src, args)
end, false)

RegisterCommand('testgreen', function(src, args)
  runTestPropCommand(src, args)
end, false)

RegisterCommand('cmclearprop', function(src)
  if src == 0 then
    print('[nv_cloth] /cmclearprop can only be used in-game.')
    return
  end

  if not isClothingAdmin(src) then
    notify(src, 'You do not have permission to use this command.', 'error')
    return
  end

  TriggerClientEvent('nvCloth:client:clearTestProps', src)
end, false)

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

local function normaliseDestination(data)
  local destination = tostring((type(data) == 'table' and data.destination) or 'store'):lower()
  if destination ~= 'hidden' then destination = 'store' end
  return destination
end

local function applyDestinationToEntry(entry, destination)
  destination = destination == 'hidden' and 'hidden' or 'store'
  entry.destination = destination
  if destination == 'hidden' then
    -- Hidden/event items are real catalog entries so inventory/task scripts can use them,
    -- but they are not visible in the public clothing store catalog.
    entry.enabled = false
    entry.shop = 'hidden_event'
    entry.hidden = true
  else
    entry.enabled = entry.enabled ~= false
    entry.shop = entry.shop or 'clothes'
    entry.hidden = false
  end
  return entry
end

local function fallbackImage(gender, componentType, componentIndex, drawable)
  gender = tostring(gender or 'male'):lower() == 'female' and 'female' or 'male'
  local propPrefix = tostring(componentType or ''):lower() == 'prop' and 'prop_' or ''
  drawable = tonumber(drawable)
  if not drawable or drawable < 0 then return 'nui://cm-items/ui/images/clothing.png' end
  return ('nui://cm-items/ui/images/clothing/%s_%s%s_%s.png'):format(gender, propPrefix, tostring(componentIndex), tostring(drawable))
end

local function normaliseCatalogImagePath(image)
  image = tostring(image or '')
  if image == '' or image == 'nil' then return nil end
  image = image:gsub('^%s+', ''):gsub('%s+$', '')
  image = image:gsub('\\', '/')

  -- Keep complete paths untouched. Convert relative catalog paths to the cm-items
  -- NUI path because cm-inventory stores and renders that reliably.
  if image:find('^nui://') or image:find('^https?://') then return image end
  image = image:gsub('^ui/images/clothing/', '')
  image = image:gsub('^images/clothing/', '')
  image = image:gsub('^clothing/', '')
  return ('nui://cm-items/ui/images/clothing/%s'):format(image)
end

local function firstCatalogImage(raw, incoming)
  return normaliseCatalogImagePath(
    (incoming and (incoming.image or incoming.icon or incoming.imagePath or incoming.image_path or incoming.imageFile or incoming.image_file)) or
    (raw and (raw.image or raw.icon or raw.imagePath or raw.image_path or raw.imageFile or raw.image_file))
  )
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
  local sourceImage = firstCatalogImage(raw, incoming)
  local gender = incoming.gender or raw.gender or raw.sex or raw.pedGender or 'male'
  local bagLevel = nil
  if category == 'bags' then
    bagLevel = tonumber(incoming.bagLevel or incoming.bag_level or incoming.level or raw.bagLevel or raw.bag_level or raw.level)
    if bagLevel ~= nil then
      bagLevel = math.max(1, math.min(4, math.floor(bagLevel)))
      raw.bagLevel = bagLevel
      raw.bag_level = bagLevel
      raw.level = bagLevel
    end
  end

  -- Preserve the exact icon captured by nv_cloth. cm-items can also resolve the
  -- catalog row, but this keeps purchases correct even if its cache is stale.
  if sourceImage then
    incoming.image = sourceImage
    incoming.icon = sourceImage
    raw.image = sourceImage
    raw.icon = sourceImage
  end

  -- cm-items is the single source for clothing metadata + image path.
  local built = cmItemsCall('BuildClothingMetadata', category, raw, {
    label = label,
    gender = gender,
    bagLevel = bagLevel,
    bag_level = bagLevel,
    level = bagLevel,
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
    if category == 'bags' then
      local finalLevel = tonumber(raw.bagLevel or raw.bag_level or raw.level or incoming.bagLevel or incoming.bag_level or incoming.level or built.bagLevel or built.bag_level or built.level)
      if not finalLevel then
        return nil, 'Bag item is missing bagLevel. Select Level 1-4 in clothing admin.'
      end
      finalLevel = math.max(1, math.min(4, math.floor(finalLevel)))
      built.bagLevel = finalLevel
      built.bag_level = nil
      built.level = nil
      built.description = ('Level %s bag. Unlocks backpack slots.'):format(finalLevel)
    end
    if sourceImage then
      built.image = sourceImage
      built.icon = sourceImage
    else
      built.image = built.image or built.icon or incoming.image or raw.image
      built.icon = built.icon or built.image
    end
    print(('[nv_cloth] Build metadata item=%s category=%s drawable=%s texture=%s image=%s bagLevel=%s'):format(
      tostring(built.itemName), tostring(built.categoryType), tostring(built.drawableId), tostring(built.textureId), tostring(built.image), tostring(built.bagLevel)))
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
    bagLevel = bagLevel,
    bag_level = bagLevel,
    level = bagLevel,
    label = incoming.label or label,
    description = ('%s clothing item'):format(def.label),
    itemType = 'clothing',
    rarity = 'normal',
    purchasedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
  }
  if category == 'bags' then
    if not bagLevel then return nil, 'Bag item is missing bagLevel. Select Level 1-4 in clothing admin.' end
    meta.bagLevel = math.max(1, math.min(4, math.floor(tonumber(bagLevel) or 1)))
    meta.bag_level = nil
    meta.level = nil
    meta.description = ('Level %s bag. Unlocks backpack slots.'):format(meta.bagLevel)
  end
  meta.image = sourceImage or normaliseCatalogImagePath(incoming.image or raw.image) or fallbackImage(meta.gender, meta.componentType, meta.componentIndex, meta.drawableId)
  meta.icon = meta.image
  return meta
end


local function inventorySuccess(result)
  if result == true then return true end
  if type(result) == 'number' then return result > 0 end
  if type(result) == 'table' then
    if result.success == true or result.ok == true or result.added == true then return true end
    if result[1] == true then return true end
  end
  return false
end

local function canCarryClothingItem(src, itemName, amount)
  if GetResourceState('cm-inventory') ~= 'started' then
    return false, 'Inventory is not available.'
  end

  -- IMPORTANT:
  -- Do not call CanCarryItem/CanAddItem for clothing purchases here. Some cm-inventory
  -- versions only check backpack capacity in those exports. If the player has no bag,
  -- that pre-check returns full even when pockets / fast-access slots are free.
  -- AddItem is the source of truth because it can choose the correct open container.
  return true
end

local function addClothingInventoryItem(src, itemName, amount, metadata)
  if GetResourceState('cm-inventory') ~= 'started' then
    return false, 'Inventory is not available.'
  end

  metadata = type(metadata) == 'table' and metadata or {}
  metadata.itemType = metadata.itemType or 'clothing'
  metadata.inventoryOnly = true
  metadata.equipped = false

  -- Force item into normal pockets — never into the equipment/bag slot on purchase.
  -- The player must manually equip from inventory via USE.
  metadata.preferredContainer = 'pockets'
  metadata.preferredStorage = 'pockets'
  metadata.inventoryTarget = 'pockets'
  metadata.slotGroup = 'pockets'
  -- Explicitly block auto-equip flags so no inventory implementation silently wears the item.
  metadata.autoEquip = false
  metadata.autoWear = false

  local attempts = {
    -- CM inventory style: AddItem(src, item, amount, metadata, reason)
    function() return exports['cm-inventory']:AddItem(src, itemName, amount, metadata, 'nv_cloth_purchase') end,
    -- Basic style: AddItem(src, item, amount, metadata)
    function() return exports['cm-inventory']:AddItem(src, itemName, amount, metadata) end,
    -- QBCore style: AddItem(src, item, amount, slot, info, reason)
    function() return exports['cm-inventory']:AddItem(src, itemName, amount, false, metadata, 'nv_cloth_purchase') end,
    -- Some custom versions accept a target/container after reason.
    function() return exports['cm-inventory']:AddItem(src, itemName, amount, metadata, 'nv_cloth_purchase', 'pockets') end,
    function() return exports['cm-inventory']:AddItem(src, itemName, amount, metadata, 'nv_cloth_purchase', 'fastaccess') end,
  }

  local lastErr = nil
  for _, fn in ipairs(attempts) do
    local ok, result, reason = pcall(fn)
    if ok and inventorySuccess(result) then
      print(('[nv_cloth] AddItem success src=%s item=%s image=%s bagLevel=%s'):format(src, itemName, tostring(metadata.image), tostring(metadata.bagLevel)))
      return true
    end
    lastErr = reason or result or lastErr
  end
  print(('[nv_cloth] AddItem failed src=%s item=%s image=%s bagLevel=%s err=%s'):format(src, itemName, tostring(metadata.image), tostring(metadata.bagLevel), tostring(lastErr)))

  return false, tostring(lastErr or 'inventory_full')
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
  for _, meta in ipairs(metadataItems) do
    local canCarry, carryErr = canCarryClothingItem(src, meta.itemName, 1)
    if canCarry ~= true then
      notify(src, tostring(carryErr or 'You cannot carry this item.'), 'error')
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
    local added, addErr = addClothingInventoryItem(src, itemName, 1, meta)
    if added ~= true then
      notify(src, ('Could not add clothing item to inventory: %s'):format(tostring(addErr or itemName)), 'error')
      print(('[nv_cloth] AddItem failed src=%s item=%s err=%s'):format(src, itemName, tostring(addErr)))
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
RegisterNetEvent('nvCloth:server:getCachedShopCatalog', function(requestId, shopName, gender, includeDisabled)
  local src = source
  local rows = {}
  shopName = shopName or 'clothes'
  gender = gender or 'male'

  if GetResourceState('cm-items') == 'started' then
    local ok, result = pcall(function()
      if includeDisabled == true then
        return exports['cm-items']:GetClothingCatalogRows({
          shop = shopName,
          gender = gender,
          includeDisabled = true,
        })
      end
      return exports['cm-items']:GetShopClothingCatalog(shopName, gender)
    end)
    if ok and type(result) == 'table' then rows = result end
  end

  if includeDisabled ~= true then
    local filtered = {}
    for _, row in ipairs(rows) do
      if type(row) == 'table' then
        local img = tostring(row.image or row.icon or '')
        if img ~= '' then
          filtered[#filtered + 1] = row
        end
      end
    end
    rows = filtered
  end

  TriggerClientEvent('nvCloth:client:cachedShopCatalog', src, requestId, rows)
end)

RegisterNetEvent('nvCloth:server:adminToggleItem', function(data)
  local src = source
  if not isClothingAdmin(src) then
    notify(src, 'You do not have permission to edit clothing catalog.', 'error')
    return
  end
  if type(data) ~= 'table' then return end

  local category = tostring(data.category or ''):lower()
  local def = CATEGORY_COMPONENTS[category]
  if not def then
    notify(src, 'Invalid clothing category.', 'error')
    return
  end

  local drawable = tonumber(data.drawableId or data.drawable)
  local texture = -1 -- admin enables/disables the whole drawable, not one texture
  if not drawable then
    notify(src, 'Invalid clothing drawable.', 'error')
    return
  end

  local gender = tostring(data.gender or 'male'):lower() == 'female' and 'female' or 'male'
  local destination = normaliseDestination(data)
  local enabled = data.enabled == true or data.enabled == 1
  local shop = tostring(data.shop or 'clothes'):lower()
  local label = tostring(data.label or ('%s %s'):format(def.label, drawable))
  local price = tonumber(data.price or Config.Prices[category] or 0) or 0

  if GetResourceState('cm-items') ~= 'started' then
    notify(src, 'cm-items is not started.', 'error')
    return
  end

  local entry = {
    -- Send both camelCase and snake_case so any cm-items version can normalise it.
    gender = gender,
    componentType = def.type,
    component_type = def.type,
    componentIndex = def.index,
    component_index = def.index,
    drawableId = drawable,
    drawable_id = drawable,
    drawable = drawable,
    textureId = texture,
    texture_id = texture,
    texture = texture,
    label = label,
    name = label,
    description = ('%s clothing item'):format(def.label),
    price = price,
    category = category,
    shop = shop,
    enabled = enabled,
    createdBy = ('player:%s'):format(src),
    created_by = ('player:%s'):format(src),
    updatedBy = ('player:%s'):format(src),
    updated_by = ('player:%s'):format(src),
  }

  applyDestinationToEntry(entry, destination)

  -- For torso rows we save the matching component 3 arms/body and component 8 undershirt.
  -- Admin can set the fit once; because textureId = -1, every texture of this drawable uses it.
  if category == 'torso' then
    entry.arms = tonumber(data.arms)
    entry.armsTexture = tonumber(data.armsTexture) or 0
    entry.arms_texture = entry.armsTexture
    entry.undershirt = tonumber(data.undershirt)
    entry.undershirtTexture = tonumber(data.undershirtTexture) or 0
    entry.undershirt_texture = entry.undershirtTexture
  end


  if category == 'bags' then
    local level = tonumber(data.bagLevel or data.bag_level or data.level)
    if not level then
      notify(src, 'Bag items require a level (1-4). Use the Capture Image button in the admin panel to save bag catalog entries.', 'error')
      return
    end
    level = math.max(1, math.min(4, math.floor(level)))
    entry.bagLevel = level
    entry.description = ('Level %s bag. Unlocks backpack slots.'):format(level)
    print(('[nv_cloth] Admin save bag drawable=%s level=%s image=%s destination=%s'):format(tostring(drawable), tostring(level), tostring(entry.image), tostring(destination)))
  end

  local ok, result, err = pcall(function()
    return exports['cm-items']:SaveClothingCatalogEntry(entry)
  end)

  if ok and result then
    notify(src, enabled and 'Clothing item enabled for all textures. Torso fit saved if this is a torso item.' or 'Clothing item disabled for all textures.', enabled and 'success' or 'info')
    TriggerClientEvent('nvCloth:client:adminCatalogSaved', src, entry)
  else
    local reason = tostring(err or result or 'unknown')
    print(('[nv_cloth] Catalog save failed for %s/%s/%s gender=%s shop=%s: %s'):format(category, def.index, drawable, gender, shop, reason))
    notify(src, ('Could not update clothing item: %s'):format(reason), 'error')
  end
end)

--========================================================
-- Admin inventory icon save
-- Receives transparent PNG from NUI canvas, saves it in cm-items, then saves path to clothing_catalog.image.
--========================================================
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64lookup = {}
for i = 1, #b64chars do b64lookup[b64chars:sub(i, i)] = i - 1 end

local function base64Decode(data)
  data = tostring(data or ''):gsub('%s', '')
  data = data:gsub('^data:image/%w+;base64,', '')
  local out = {}
  local buffer = 0
  local bits = 0
  for i = 1, #data do
    local c = data:sub(i, i)
    if c ~= '=' then
      local val = b64lookup[c]
      if val ~= nil then
        buffer = buffer * 64 + val
        bits = bits + 6
        if bits >= 8 then
          bits = bits - 8
          local byte = math.floor(buffer / (2 ^ bits)) % 256
          out[#out + 1] = string.char(byte)
          buffer = buffer % (2 ^ bits)
        end
      end
    end
  end
  return table.concat(out)
end

local function safeFilePart(value)
  value = tostring(value or ''):lower()
  value = value:gsub('[^%w_%-%.]', '_')
  value = value:gsub('_+', '_')
  return value
end

local function saveCatalogEntryFromIcon(src, data, imagePath)
  local category = tostring(data.category or ''):lower()
  local def = CATEGORY_COMPONENTS[category]
  if not def then return false, 'invalid_category' end

  local drawable = tonumber(data.drawableId or data.drawable)
  if not drawable then return false, 'invalid_drawable' end
  local texture = tonumber(data.textureId or data.texture or 0) or 0

  local gender = tostring(data.gender or 'male'):lower() == 'female' and 'female' or 'male'
  local shop = tostring(data.shop or 'clothes'):lower()
  local label = tostring(data.label or ('%s %s'):format(def.label, drawable))
  local price = tonumber(data.price or Config.Prices[category] or 0) or 0
  local destination = normaliseDestination(data)

  local entry = {
    gender = gender,
    componentType = def.type,
    component_type = def.type,
    componentIndex = def.index,
    component_index = def.index,
    drawableId = drawable,
    drawable_id = drawable,
    drawable = drawable,
    textureId = texture,
    texture_id = texture,
    texture = texture,
    label = label,
    name = label,
    description = ('%s clothing item'):format(def.label),
    price = price,
    category = category,
    shop = shop,
    image = imagePath,
    enabled = true,
    createdBy = ('player:%s'):format(src),
    created_by = ('player:%s'):format(src),
    updatedBy = ('player:%s'):format(src),
    updated_by = ('player:%s'):format(src),
  }

  applyDestinationToEntry(entry, destination)

  if category == 'torso' then
    entry.arms = tonumber(data.arms)
    entry.armsTexture = tonumber(data.armsTexture) or 0
    entry.arms_texture = entry.armsTexture
    entry.undershirt = tonumber(data.undershirt)
    entry.undershirtTexture = tonumber(data.undershirtTexture) or 0
    entry.undershirt_texture = entry.undershirtTexture
  end


  if category == 'bags' then
    local level = tonumber(data.bagLevel or data.bag_level or data.level)
    if not level then
      return false, 'bag_level_required'
    end
    level = math.max(1, math.min(4, math.floor(level)))
    -- Keep bag metadata minimal. cm-inventory only needs metadata.bagLevel;
    -- backpack slots/weight are resolved from inventory config, not stored per item.
    entry.bagLevel = level
    entry.description = ('Level %s bag. Unlocks backpack slots.'):format(level)
    print(('[nv_cloth] Icon catalog bag drawable=%s texture=%s level=%s image=%s shared=%s'):format(tostring(drawable), tostring(texture), tostring(level), tostring(imagePath), tostring(data.sharedGender)))
  end

  local function saveEntry(row)
    local ok, result, err = pcall(function()
      return exports['cm-items']:SaveClothingCatalogEntry(row)
    end)
    if ok and result then return true end
    return false, tostring(err or result or 'catalog_save_failed')
  end

  local sharedGender = (category == 'bags' and data.sharedGender ~= false) or data.sharedGender == true
  if sharedGender then
    entry.sharedGender = true
    entry.shared_gender = true
    local male = {}
    for k, v in pairs(entry) do male[k] = v end
    male.gender = 'male'
    local female = {}
    for k, v in pairs(entry) do female[k] = v end
    female.gender = 'female'

    local okMale, errMale = saveEntry(male)
    if not okMale then return false, errMale end
    local okFemale, errFemale = saveEntry(female)
    if not okFemale then return false, errFemale end

    entry.gender = gender
    return true, entry
  end

  local okSave, errSave = saveEntry(entry)
  if okSave then return true, entry end
  return false, errSave
end

RegisterNetEvent('nvCloth:server:saveInventoryIcon', function(data)
  local src = source
  print(('[nv_cloth] saveInventoryIcon received from %s'):format(src))
  if not isClothingAdmin(src) then
    TriggerClientEvent('nvCloth:client:inventoryIconSaveFailed', src, 'no_permission')
    notify(src, 'You do not have permission to save clothing icons.', 'error')
    return
  end

  if GetResourceState('cm-items') ~= 'started' then
    TriggerClientEvent('nvCloth:client:inventoryIconSaveFailed', src, 'cm-items_not_started')
    notify(src, 'cm-items is not started.', 'error')
    return
  end

  data = type(data) == 'table' and data or {}
  local fileName = safeFilePart(data.fileName or '')
  print(('[nv_cloth] icon filename=%s category=%s drawable=%s'):format(tostring(fileName), tostring(data.category), tostring(data.drawableId or data.drawable)))
  if fileName == '' or not fileName:find('%.png$') then
    TriggerClientEvent('nvCloth:client:inventoryIconSaveFailed', src, 'invalid_filename')
    return
  end

  local raw = data.imageBase64 or data.dataUrl
  if not raw or raw == '' then
    TriggerClientEvent('nvCloth:client:inventoryIconSaveFailed', src, 'empty_image')
    return
  end

  local bytes = base64Decode(raw)
  print(('[nv_cloth] decoded icon bytes=%s'):format(bytes and #bytes or 0))
  if not bytes or #bytes < 100 then
    TriggerClientEvent('nvCloth:client:inventoryIconSaveFailed', src, 'decode_failed')
    return
  end

  local folder = (Config.IconCapture and Config.IconCapture.folder) or 'ui/images/clothing/custom'
  folder = tostring(folder):gsub('^/', ''):gsub('/$', '')
  local savePath = ('%s/%s'):format(folder, fileName)
  print(('[nv_cloth] saving icon into cm-items:%s'):format(savePath))
  local okSave = SaveResourceFile('cm-items', savePath, bytes, #bytes)
  if not okSave then
    TriggerClientEvent('nvCloth:client:inventoryIconSaveFailed', src, 'save_file_failed')
    notify(src, 'Could not save icon file into cm-items. Check folder exists and server has write permission.', 'error')
    return
  end

  local prefix = (Config.IconCapture and Config.IconCapture.catalogImagePrefix) or 'custom'
  prefix = tostring(prefix):gsub('^/', ''):gsub('/$', '')
  local catalogImage = ('%s/%s'):format(prefix, fileName)
  print(('[nv_cloth] saved icon file, catalog image=%s'):format(catalogImage))

  local okCatalog, entryOrErr = saveCatalogEntryFromIcon(src, data, catalogImage)
  if not okCatalog then
    TriggerClientEvent('nvCloth:client:inventoryIconSaveFailed', src, entryOrErr)
    notify(src, ('Icon saved but catalog update failed: %s'):format(tostring(entryOrErr)), 'error')
    return
  end

  notify(src, (data.destination == 'hidden') and 'Inventory icon captured. Item saved hidden/event-only.' or 'Inventory icon captured and clothing enabled.', 'success')
  TriggerClientEvent('nvCloth:client:inventoryIconSaved', src, entryOrErr)
end)
