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


local function jenc(data)
  local ok, out = pcall(function() return json.encode(data or {}) end)
  return ok and out or '{}'
end

local function dbUpdate(query, params)
  if not MySQL or not MySQL.update or not MySQL.update.await then return false, 'mysql_unavailable' end
  local ok, result = pcall(function()
    return MySQL.update.await(query, params or {})
  end)
  if ok then return true, result end
  print(('[nv_cloth] DB update failed: %s'):format(tostring(result)))
  return false, result
end

local function dbSingle(query, params)
  if not MySQL or not MySQL.single or not MySQL.single.await then return nil, 'mysql_unavailable' end
  local ok, result = pcall(function()
    return MySQL.single.await(query, params or {})
  end)
  if ok then return result end
  print(('[nv_cloth] DB single failed: %s'):format(tostring(result)))
  return nil, result
end

local function ensureNvClothSchema()
  dbUpdate([[CREATE TABLE IF NOT EXISTS nv_cloth_purchase_receipts (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    receipt_id VARCHAR(64) NOT NULL UNIQUE,
    character_id VARCHAR(64) NULL,
    source INT NULL,
    payment_method VARCHAR(16) NOT NULL,
    total INT NOT NULL DEFAULT 0,
    items_json LONGTEXT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'paid',
    reason VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )]], {})
  dbUpdate([[CREATE TABLE IF NOT EXISTS nv_cloth_audit_logs (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    actor_source INT NULL,
    actor_character_id VARCHAR(64) NULL,
    action VARCHAR(64) NOT NULL,
    item_key VARCHAR(160) NULL,
    details_json LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )]], {})
  -- Per-player favourites. Global across shops: keyed only by character + item key
  -- (gender:category:drawable:texture), never by shop, so a favourite followed
  -- anywhere shows up everywhere.
  dbUpdate([[CREATE TABLE IF NOT EXISTS nv_cloth_favourites (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    character_id VARCHAR(64) NOT NULL,
    fav_key VARCHAR(160) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_fav (character_id, fav_key)
  )]], {})
  -- Admin capture-camera overrides tuned live in the clothing admin panel.
  -- One row per clothing category; overrides Config.IconCapture.captureCameras.
  dbUpdate([[CREATE TABLE IF NOT EXISTS nv_cloth_capture_cameras (
    category VARCHAR(32) NOT NULL PRIMARY KEY,
    dist FLOAT NOT NULL,
    z FLOAT NOT NULL,
    fov FLOAT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  )]], {})
  -- Admin per-category capture crops. Set once per clothing category in the admin
  -- panel; every future capture of that category reuses the same crop (percent
  -- trims from each edge) until it is changed or cleared.
  dbUpdate([[CREATE TABLE IF NOT EXISTS nv_cloth_capture_crops (
    category VARCHAR(32) NOT NULL PRIMARY KEY,
    trim_left FLOAT NOT NULL DEFAULT 0,
    trim_top FLOAT NOT NULL DEFAULT 0,
    trim_right FLOAT NOT NULL DEFAULT 0,
    trim_bottom FLOAT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  )]], {})
end

CreateThread(function()
  Wait(1000)
  ensureNvClothSchema()
end)

local function getStateCharacterId(src)
  local p = Player(src)
  local state = p and p.state or nil
  if not state then return nil end
  local candidates = {}
  local function add(v)
    if v ~= nil and tostring(v) ~= '' then candidates[#candidates + 1] = v end
  end
  add(state.charId); add(state.characterId); add(state.character_id); add(state.cid); add(state.citizenid)
  add(state.cm_charId); add(state.cmCharacterId); add(state.selectedCharacterId)
  if type(state.character) == 'table' then
    add(state.character.id); add(state.character.charId); add(state.character.characterId); add(state.character.citizenid)
  end
  if type(state.PlayerData) == 'table' then
    add(state.PlayerData.charId); add(state.PlayerData.characterId); add(state.PlayerData.citizenid)
  end
  return candidates[1] and tostring(candidates[1]) or nil
end

local function setMoneyState(src, cash, bank)
  local p = Player(src)
  if not (p and p.state) then return end
  if cash ~= nil then pcall(function() p.state:set('cash', tonumber(cash) or 0, true) end) end
  if bank ~= nil then pcall(function() p.state:set('bank', tonumber(bank) or 0, true) end) end
end

local function getCharacterMoney(src)
  local charId = getStateCharacterId(src)
  if not charId then return nil, 'No selected character ID.' end
  local row = dbSingle('SELECT cash, bank FROM characters WHERE id = ? LIMIT 1', { charId })
  if not row then return nil, 'Could not read character balance.' end
  return {
    characterId = charId,
    cash = tonumber(row.cash) or 0,
    bank = tonumber(row.bank) or 0,
  }
end

local function takeCharacterMoney(src, method, amount)
  method = method == 'cash' and 'cash' or 'bank'
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return true, { method = method, characterId = getStateCharacterId(src) } end

  local money, err = getCharacterMoney(src)
  if not money then
    -- Safe fallback for older test servers, but normal CM uses characters.cash/bank above.
    local ok, paid = pcall(function() return exports['cm-core']:RemoveMoney(src, method, amount) end)
    if ok and paid == true then return true, { method = method, fallback = true } end
    return false, err or 'Could not read character balance.'
  end

  local balance = tonumber(money[method]) or 0
  if balance < amount then
    return false, ('Not enough %s. Need $%s, you have $%s.'):format(method, amount, balance)
  end

  local query = ('UPDATE characters SET %s = GREATEST(0, COALESCE(%s, 0) - ?) WHERE id = ? AND COALESCE(%s, 0) >= ?'):format(method, method, method)
  local ok, affected = dbUpdate(query, { amount, money.characterId, amount })
  if not ok or (type(affected) == 'number' and affected < 1) then
    return false, 'Payment failed. Balance changed; try again.'
  end

  money[method] = balance - amount
  setMoneyState(src, money.cash, money.bank)
  return true, { method = method, characterId = money.characterId, cash = money.cash, bank = money.bank }
end

local function refundCharacterMoney(src, payment, amount)
  amount = math.floor(tonumber(amount) or 0)
  if not payment or amount <= 0 then return false end
  local method = payment.method == 'cash' and 'cash' or 'bank'

  if payment.fallback then
    local ok = pcall(function() return exports['cm-core']:AddMoney(src, method, amount) end)
    return ok == true
  end

  if not payment.characterId then return false end
  local ok = dbUpdate(('UPDATE characters SET %s = COALESCE(%s, 0) + ? WHERE id = ?'):format(method, method), { amount, payment.characterId })
  local money = getCharacterMoney(src)
  if money then setMoneyState(src, money.cash, money.bank) end
  return ok == true
end

local function makeReceiptId(src)
  return ('CLOTH-%s-%s-%04d'):format(os.date('!%Y%m%d%H%M%S'), tostring(src), math.random(0, 9999))
end

local function savePurchaseReceipt(src, receiptId, payment, total, items, status, reason)
  dbUpdate('INSERT INTO nv_cloth_purchase_receipts (receipt_id, character_id, source, payment_method, total, items_json, status, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
    receiptId,
    payment and payment.characterId or getStateCharacterId(src),
    src,
    payment and payment.method or 'unknown',
    math.floor(tonumber(total) or 0),
    jenc(items or {}),
    tostring(status or 'paid'),
    reason and tostring(reason):sub(1, 250) or nil
  })
end

local function auditLog(src, action, details, itemKey)
  dbUpdate('INSERT INTO nv_cloth_audit_logs (actor_source, actor_character_id, action, item_key, details_json) VALUES (?, ?, ?, ?, ?)', {
    src,
    getStateCharacterId(src),
    tostring(action or 'unknown'),
    itemKey and tostring(itemKey):sub(1, 150) or nil,
    jenc(details or {})
  })
end

local function csvAllows(required, actual)
  required = tostring(required or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  if required == '' or required == 'all' or required == 'none' or required == 'public' then return true end
  actual = tostring(actual or ''):lower()
  for value in required:gmatch('[^,]+') do
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value ~= '' and value == actual then return true end
  end
  return false
end

local function stateStringValue(src, ...)
  local p = Player(src)
  local state = p and p.state or nil
  if not state then return '' end
  for _, key in ipairs({ ... }) do
    local v = state[key]
    if type(v) == 'table' then v = v.name or v.id or v.label or v.grade end
    if v ~= nil and tostring(v) ~= '' then return tostring(v):lower() end
  end
  return ''
end

local function restrictionAllowed(src, row)
  if type(row) ~= 'table' then return true end
  local job = stateStringValue(src, 'jobName', 'job_name', 'job')
  local gang = stateStringValue(src, 'gangName', 'gang', 'org', 'organization')
  local family = stateStringValue(src, 'familyName', 'family', 'familyId', 'family_id')
  local requiredJob = row.requiredJob or row.required_job
  local requiredGang = row.requiredGang or row.required_gang
  local requiredFamily = row.requiredFamily or row.required_family
  if not csvAllows(requiredJob, job) then return false, ('This clothing requires job: %s'):format(tostring(requiredJob)) end
  if not csvAllows(requiredGang, gang) then return false, ('This clothing requires gang/org: %s'):format(tostring(requiredGang)) end
  if not csvAllows(requiredFamily, family) then return false, ('This clothing requires family: %s'):format(tostring(requiredFamily)) end
  return true
end

local function copyRestrictions(entry, data, incoming)
  incoming = type(incoming) == 'table' and incoming or {}
  local rJob = data.requiredJob or data.required_job or incoming.requiredJob or incoming.required_job or ''
  local rGang = data.requiredGang or data.required_gang or incoming.requiredGang or incoming.required_gang or ''
  local rFamily = data.requiredFamily or data.required_family or incoming.requiredFamily or incoming.required_family or ''
  entry.requiredJob = rJob
  entry.required_job = rJob
  entry.requiredGang = rGang
  entry.required_gang = rGang
  entry.requiredFamily = rFamily
  entry.required_family = rFamily
end


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

--========================================================
-- Live greenscreen tuning commands (/vehgreen family)
-- Spawn and tune the real capture greenscreen prop in-game, then copy the
-- printed values into Config.AdminStudio.Backdrop.
--========================================================
local function greenGuard(src)
  if src == 0 then
    print('[nv_cloth] /vehgreen commands can only be used in-game.')
    return false
  end
  if not isClothingAdmin(src) then
    notify(src, 'You do not have permission to use this command.', 'error')
    return false
  end
  return true
end

-- /vehgreen         -> spawn at your position
-- /vehgreen fixed   -> spawn at the configured fixedCoords
RegisterCommand('vehgreen', function(src, args)
  if not greenGuard(src) then return end
  local useFixed = (args and args[1] and tostring(args[1]):lower() == 'fixed') or false
  TriggerClientEvent('nvCloth:client:greenSpawn', src, useFixed)
end, false)

-- /vehgreenscale 2.0
RegisterCommand('vehgreenscale', function(src, args)
  if not greenGuard(src) then return end
  local scale = tonumber(args and args[1])
  TriggerClientEvent('nvCloth:client:greenScale', src, scale)
end, false)

-- /vehgreenup [amount]   (default 0.10)
RegisterCommand('vehgreenup', function(src, args)
  if not greenGuard(src) then return end
  local amount = tonumber(args and args[1]) or 0.10
  TriggerClientEvent('nvCloth:client:greenUp', src, amount)
end, false)

-- /vehgreendown [amount] (default 0.05)
RegisterCommand('vehgreendown', function(src, args)
  if not greenGuard(src) then return end
  local amount = tonumber(args and args[1]) or 0.05
  TriggerClientEvent('nvCloth:client:greenDown', src, amount)
end, false)

-- /vehgreenpos  -> prints the prop's position + scale + zOffset to paste in config
RegisterCommand('vehgreenpos', function(src)
  if not greenGuard(src) then return end
  TriggerClientEvent('nvCloth:client:greenPos', src)
end, false)

-- /vehgreenclear -> remove the live tuning prop
RegisterCommand('vehgreenclear', function(src)
  if not greenGuard(src) then return end
  TriggerClientEvent('nvCloth:client:greenClear', src)
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


local function decodeMetadataTable(value)
  if type(value) == 'table' then return value end
  if type(value) ~= 'string' or value == '' then return {} end
  local ok, decoded = pcall(function() return json.decode(value) end)
  if ok and type(decoded) == 'table' then return decoded end
  return {}
end

local function firstNonEmpty(...)
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    if v ~= nil and tostring(v) ~= '' and tostring(v) ~= 'nil' then
      return v
    end
  end
  return nil
end

local function cleanItemKey(value)
  value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' or value == 'nil' then return nil end
  -- Item keys in CM are identifiers, not display labels. Avoid accidentally using labels.
  if value:find('%s') then return nil end
  return value
end

local function catalogKey(gender, category, drawable, texture)
  return ('%s:%s:%s:%s'):format(
    tostring(gender or ''), tostring(category or ''), tostring(drawable or ''), tostring(texture or '')
  )
end

local function rowMatchesClothing(row, category, gender, drawable, texture)
  if type(row) ~= 'table' then return false end
  local rowCategory = tostring(row.category or row.type or ''):lower()
  if rowCategory ~= category then return false end
  local rowGender = tostring(row.gender or row.sex or row.pedGender or gender or 'male'):lower()
  if rowGender ~= 'all' and gender ~= 'all' and rowGender ~= gender then return false end
  local rowDrawable = tonumber(row.drawableId or row.drawable_id or row.drawable or row.componentId or row.component)
  if tonumber(rowDrawable) ~= tonumber(drawable) then return false end
  local rowTexture = tonumber(row.textureId or row.texture_id or row.texture or 0) or 0
  if rowTexture < 0 then rowTexture = 0 end
  return tonumber(rowTexture) == tonumber(texture or 0)
end

local function findCatalogRowForPurchase(category, gender, drawable, texture, shopName)
  if GetResourceState('cm-items') ~= 'started' then return nil end
  shopName = shopName or 'clothes'

  local directMethods = {
    'GetClothingCatalogEntry',
    'GetClothingCatalogItem',
    'ResolveClothingCatalogEntry',
    'FindClothingCatalogEntry',
  }

  for _, method in ipairs(directMethods) do
    local result = cmItemsCall(method, {
      category = category,
      gender = gender,
      drawableId = drawable,
      drawable = drawable,
      textureId = texture,
      texture = texture,
      shop = shopName,
    })
    if type(result) == 'table' and rowMatchesClothing(result, category, gender, drawable, texture) then
      return result
    end

    result = cmItemsCall(method, gender, category, drawable, texture, shopName)
    if type(result) == 'table' and rowMatchesClothing(result, category, gender, drawable, texture) then
      return result
    end
  end

  local lists = {}
  local rows = cmItemsCall('GetShopClothingCatalog', shopName, gender)
  if type(rows) == 'table' then lists[#lists + 1] = rows end
  rows = cmItemsCall('GetClothingCatalogRows', { shop = shopName, gender = gender, includeDisabled = true })
  if type(rows) == 'table' then lists[#lists + 1] = rows end

  for _, list in ipairs(lists) do
    for _, row in ipairs(list) do
      if rowMatchesClothing(row, category, gender, drawable, texture) then
        return row
      end
    end
  end

  return nil
end

local function resolveExactClothingItemName(raw, incoming, catalogRow, category, gender, drawable, texture)
  -- IMPORTANT:
  -- /cmitempreview works because cm-items gives the generic physical clothing item
  -- (clothing_torso, clothing_pants, etc.) plus rich metadata. The store must do
  -- the same. Do NOT create/use per-drawable item keys like clothing_male_torso_11_0
  -- here unless cm-items explicitly says that exact physical item exists; otherwise
  -- inventory/itemactions cannot resolve image/use/equip correctly.
  category = tostring(category or ''):lower()

  local categoryItem = cleanItemKey(cmItemsCall('GetClothingItemName', category))
  if categoryItem then return categoryItem end

  raw = type(raw) == 'table' and raw or {}
  incoming = type(incoming) == 'table' and incoming or {}
  catalogRow = type(catalogRow) == 'table' and catalogRow or {}

  local candidates = {
    raw.itemName, raw.item_name, raw.nameKey, raw.name_key, raw.inventoryItem, raw.inventory_item, raw.item_key,
    incoming.itemName, incoming.item_name, incoming.nameKey, incoming.name_key, incoming.inventoryItem, incoming.inventory_item, incoming.item_key,
    catalogRow.itemName, catalogRow.item_name, catalogRow.nameKey, catalogRow.name_key, catalogRow.inventoryItem, catalogRow.inventory_item, catalogRow.item_key,
  }

  for _, v in ipairs(candidates) do
    local key = cleanItemKey(v)
    if key then
      local item = cmItemsCall('GetPhysicalItem', key)
      if type(item) == 'table' then return key end
    end
  end

  return cleanItemKey('clothing_' .. category)
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

local function normalizeClothingImagePath(image, gender, componentType, componentIndex, drawable)
  image = tostring(image or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if image == '' or image == 'nil' or image == 'placeholder.png' then
    return fallbackImage(gender, componentType, componentIndex, drawable)
  end

  -- Keep paths that already work cross-resource.
  if image:find('^nui://') or image:find('^https?://') or image:find('^data:image') then
    return image
  end

  -- Admin capture usually saves inside cm-items/ui/images/clothing/custom/...
  if image:find('^ui/images/') then
    return 'nui://cm-items/' .. image
  end
  if image:find('^images/') then
    return 'nui://cm-items/ui/' .. image
  end
  if image:find('^clothing/') then
    return 'nui://cm-items/ui/images/' .. image
  end
  if image:find('^custom/') then
    return 'nui://cm-items/ui/images/clothing/' .. image
  end

  -- Plain png name from older captured rows.
  if image:find('%.png$') or image:find('%.webp$') or image:find('%.jpg$') or image:find('%.jpeg$') or image:find('%.svg$') then
    return 'nui://cm-items/ui/images/clothing/' .. image
  end

  return image
end

local function normalizeMetadataAliases(meta, category, def, drawable, texture, gender, image)
  if type(meta) ~= 'table' then meta = {} end
  category = tostring(category or meta.categoryType or meta.category or ''):lower()
  drawable = tonumber(drawable or meta.drawableId or meta.drawable or meta.component or meta.componentId) or 0
  texture = tonumber(texture or meta.textureId or meta.texture) or 0
  gender = tostring(gender or meta.gender or 'male'):lower() == 'female' and 'female' or 'male'
  def = def or CATEGORY_COMPONENTS[category] or {}

  meta.itemType = meta.itemType or 'clothing'
  meta.type = meta.type or 'clothing'
  meta.category = category
  meta.categoryType = category
  meta.clothingCategory = category
  meta.componentType = meta.componentType or def.type
  meta.component_type = meta.component_type or meta.componentType
  meta.componentIndex = tonumber(meta.componentIndex or meta.component_index) or tonumber(def.index)
  meta.component_index = meta.componentIndex
  meta.drawableId = drawable
  meta.drawable_id = drawable
  meta.drawable = drawable
  meta.component = drawable
  meta.componentId = drawable
  meta.textureId = texture
  meta.texture_id = texture
  meta.texture = texture
  meta.gender = gender
  meta.sex = gender
  meta.equipmentSlot = meta.equipmentSlot or EQUIP_SLOT_BY_CATEGORY[category]
  meta.equipSlot = meta.equipSlot or meta.equipmentSlot
  meta.slot = meta.slot or meta.equipmentSlot
  meta.isClothing = true
  meta.stack = false
  meta.unique = true

  image = normalizeClothingImagePath(image or meta.image or meta.icon or meta.inventoryImage, gender, meta.componentType, meta.componentIndex, drawable)
  meta.image = image
  meta.icon = image
  meta.inventoryImage = image
  meta.inventory_icon = image
  meta.displayImage = image
  meta.display_image = image
  return meta
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

  local incoming = decodeMetadataTable(raw.metadata)
  local gender = tostring(incoming.gender or raw.gender or raw.sex or raw.pedGender or 'male'):lower() == 'female' and 'female' or 'male'
  local shopName = tostring(raw.shop or incoming.shop or 'clothes'):lower()

  -- Pull the authoritative row from cm-items again on the server. The browser may only send
  -- a display row, but cm-items owns the exact item key + image created by clothing admin.
  local catalogRow = findCatalogRowForPurchase(category, gender, drawable, texture, shopName)
  local catalogMeta = type(catalogRow) == 'table' and decodeMetadataTable(catalogRow.metadata) or {}

  if type(catalogRow) == 'table' then
    for k, v in pairs(catalogRow) do
      if raw[k] == nil or raw[k] == '' then raw[k] = v end
    end
    for k, v in pairs(catalogMeta) do
      if incoming[k] == nil or incoming[k] == '' then incoming[k] = v end
    end
  end

  local exactItemName = resolveExactClothingItemName(raw, incoming, catalogRow, category, gender, drawable, texture)
  raw.itemName = exactItemName
  raw.item_name = exactItemName
  raw.nameKey = exactItemName
  incoming.itemName = exactItemName
  incoming.item_name = exactItemName
  incoming.nameKey = exactItemName

  local label = raw.label or catalogRow and catalogRow.label or incoming.label or raw.name or ('%s %s/%s'):format(def.label, drawable, texture)
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
    built.itemName = exactItemName or built.itemName or built.item_name or built.name or ('clothing_' .. category)
    built.item_name = built.itemName
    built.nameKey = built.itemName
    built.categoryType = built.categoryType or category
    built.componentType = built.componentType or def.type
    built.componentIndex = built.componentIndex or def.index
    built.drawableId = tonumber(built.drawableId) or drawable
    built.textureId = tonumber(built.textureId) or texture
    built.label = built.label or label
    built.description = built.description or ('%s clothing item'):format(def.label)
    built.itemType = built.itemType or 'clothing'
    built.rarity = built.rarity or 'normal'
    built.price = tonumber(built.price or raw.price or incoming.price or (catalogRow and catalogRow.price)) or built.price
    built.catalogId = built.catalogId or built.catalog_id or raw.catalogId or raw.catalog_id or (catalogRow and (catalogRow.id or catalogRow.catalogId or catalogRow.catalog_id))
    built.catalogKey = built.catalogKey or catalogKey(gender, category, drawable, texture)
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
    -- IMPORTANT: captured/catalog image must win over generated fallback image.
    local finalImage = (catalogRow and (catalogRow.image or catalogRow.icon)) or incoming.image or incoming.icon or raw.image or raw.icon or built.image or built.icon
    normalizeMetadataAliases(built, category, def, drawable, texture, gender, finalImage)
    built.itemName = exactItemName or built.itemName or built.item_name or built.name or ('clothing_' .. category)
    built.item_name = built.itemName
    built.nameKey = built.itemName
    built.name = built.itemName
    built.label = built.label or label
    built.description = built.description or ('%s clothing item'):format(def.label)
    copyRestrictions(built, raw, incoming)
    print(('[nv_cloth] Build metadata item=%s category=%s drawable=%s texture=%s image=%s bagLevel=%s'):format(
      tostring(built.itemName), tostring(built.categoryType), tostring(built.drawableId), tostring(built.textureId), tostring(built.image), tostring(built.bagLevel)))
    return built
  end

  local meta = {
    itemName = exactItemName or ('clothing_' .. category),
    item_name = exactItemName or ('clothing_' .. category),
    nameKey = exactItemName or ('clothing_' .. category),
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
    description = incoming.description or raw.description or (catalogRow and catalogRow.description) or ('%s clothing item'):format(def.label),
    price = tonumber(incoming.price or raw.price or (catalogRow and catalogRow.price)) or nil,
    catalogId = incoming.catalogId or incoming.catalog_id or raw.catalogId or raw.catalog_id or (catalogRow and (catalogRow.id or catalogRow.catalogId or catalogRow.catalog_id)),
    catalogKey = catalogKey(gender, category, drawable, texture),
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
  -- IMPORTANT: use exact captured catalog image from the row, then fall back to generated cm-items path.
  local finalImage = (catalogRow and (catalogRow.image or catalogRow.icon)) or incoming.image or incoming.icon or raw.image or raw.icon or fallbackImage(meta.gender, meta.componentType, meta.componentIndex, meta.drawableId)
  normalizeMetadataAliases(meta, category, def, drawable, texture, gender, finalImage)
  meta.itemName = exactItemName or meta.itemName
  meta.item_name = meta.itemName
  meta.nameKey = meta.itemName
  meta.name = meta.itemName
  copyRestrictions(meta, raw, incoming)
  return meta
end


local function inventorySuccess(result)
  if result == true then return true end
  if type(result) == 'number' then return result > 0 end
  if type(result) == 'string' then
    -- Some inventory builds return the slot name on success.
    return result:find('^pocket%-') ~= nil or result:find('^backpack%-') ~= nil or result:find('^quickaccess%-') ~= nil
  end
  if type(result) == 'table' then
    if result.success == true or result.ok == true or result.added == true then return true end
    if result[1] == true then return true end
    if type(result.slot) == 'string' or type(result.placedSlot) == 'string' then return true end
  end
  return false
end

local function inventoryResultSlot(result, fallback)
  if type(result) == 'string' and result ~= '' then return result end
  if type(result) == 'table' then
    return result.slot or result.placedSlot or result.toSlot or fallback
  end
  return fallback
end

local function cloneTable(value)
  local out = {}
  if type(value) ~= 'table' then return out end
  for k, v in pairs(value) do
    if type(v) == 'table' then
      local child = {}
      for ck, cv in pairs(v) do child[ck] = cv end
      out[k] = child
    else
      out[k] = v
    end
  end
  return out
end

local function addItemViaCmInventory(src, itemName, amount, metadata, reason, preferredSlot)
  local inv = exports['cm-inventory']
  local meta = metadata or {}
  local attempts = {
    -- Match cm-items /cmitempreview compatibility: send metadata in arg #4 AND #5.
    -- Some older cm-inventory builds accidentally read metadata from the 5th argument.
    -- Without this, bought store clothes become plain/no-image/no-equip while preview works.
    function() return inv.AddItem(src, itemName, amount, meta, meta, preferredSlot) end,
    function() return inv:AddItem(src, itemName, amount, meta, meta, preferredSlot) end,

    -- Current CM signature: src, item, amount, metadata, reason, preferredSlot.
    function() return inv.AddItem(src, itemName, amount, meta, reason, preferredSlot) end,
    function() return inv:AddItem(src, itemName, amount, meta, reason, preferredSlot) end,
  }

  -- Older resources may not support the slot parameter; keep these only as fallback.
  if preferredSlot == nil then
    attempts[#attempts + 1] = function() return inv.AddItem(src, itemName, amount, meta, meta, reason) end
    attempts[#attempts + 1] = function() return inv:AddItem(src, itemName, amount, meta, meta, reason) end
    attempts[#attempts + 1] = function() return inv.AddItem(src, itemName, amount, meta, reason) end
    attempts[#attempts + 1] = function() return inv:AddItem(src, itemName, amount, meta, reason) end
    attempts[#attempts + 1] = function() return inv.AddItem(src, itemName, amount, meta) end
    attempts[#attempts + 1] = function() return inv:AddItem(src, itemName, amount, meta) end
  end

  local lastErr = nil
  for _, fn in ipairs(attempts) do
    local ok, result, extra = pcall(fn)
    if ok and inventorySuccess(result) then
      return true, inventoryResultSlot(result, preferredSlot)
    end
    if not ok then lastErr = result else lastErr = extra or result or lastErr end
  end

  return false, tostring(lastErr or 'inventory_add_failed')
end


local function removeItemViaCmInventory(src, itemName, amount, metadata, reason, preferredSlot)
  if GetResourceState('cm-inventory') ~= 'started' then return false, 'inventory_not_started' end
  local inv = exports['cm-inventory']
  local attempts = {
    function() return inv.RemoveItem(src, itemName, amount, metadata, reason, preferredSlot) end,
    function() return inv:RemoveItem(src, itemName, amount, metadata, reason, preferredSlot) end,
    function() return inv.RemoveItem(src, itemName, amount, metadata, reason) end,
    function() return inv:RemoveItem(src, itemName, amount, metadata, reason) end,
    function() return inv.RemoveItem(src, itemName, amount, preferredSlot) end,
    function() return inv:RemoveItem(src, itemName, amount, preferredSlot) end,
  }
  local lastErr = nil
  for _, fn in ipairs(attempts) do
    local ok, result = pcall(fn)
    if ok and (result == true or result == nil or (type(result) == 'number' and result >= 0) or (type(result) == 'table' and (result.success == true or result.ok == true))) then
      return true
    end
    lastErr = ok and result or result
  end
  return false, tostring(lastErr or 'remove_failed')
end

local function rollbackAddedClothing(src, addedRecords)
  local okAll = true
  for i = #addedRecords, 1, -1 do
    local rec = addedRecords[i]
    local ok, err = removeItemViaCmInventory(src, rec.itemName, 1, rec.metadata or {}, 'nv_cloth_purchase_rollback', rec.slot)
    if not ok then
      okAll = false
      print(('[nv_cloth] Rollback RemoveItem failed src=%s item=%s slot=%s err=%s'):format(src, tostring(rec.itemName), tostring(rec.slot), tostring(err)))
    end
  end
  return okAll
end

local function shouldTryNextSlot(reason)
  reason = tostring(reason or ''):lower()
  if reason == '' then return true end
  return reason:find('slot') ~= nil
      or reason:find('occupied') ~= nil
      or reason:find('locked') ~= nil
      or reason:find('full') ~= nil
      or reason:find('empty') ~= nil
      or reason:find('bag') ~= nil
      or reason:find('capacity') ~= nil
end

local function normalInventorySlots()
  local slots = {}
  for i = 1, 6 do slots[#slots + 1] = ('pocket-%s'):format(i) end
  for i = 1, 30 do slots[#slots + 1] = ('backpack-%s'):format(i) end
  return slots
end

local function canCarryClothingItem(src, itemName, amount)
  if GetResourceState('cm-inventory') ~= 'started' then
    return false, 'Inventory is not available.'
  end

  -- Do not trust old CanCarry/CanAdd pre-checks here. Some builds only check backpack slots
  -- and reject purchases even when pocket slots are free. AddItem below is the source of truth.
  return true
end

local function addClothingInventoryItem(src, itemName, amount, metadata)
  if GetResourceState('cm-inventory') ~= 'started' then
    return false, 'Inventory is not available.'
  end

  itemName = tostring(itemName or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if itemName == '' then return false, 'Invalid clothing item name.' end

  metadata = cloneTable(metadata)
  metadata.itemName = metadata.itemName or itemName
  metadata.item_name = metadata.item_name or itemName
  metadata.name = metadata.name or itemName
  metadata = normalizeMetadataAliases(metadata, metadata.categoryType or metadata.category, nil, metadata.drawableId or metadata.drawable, metadata.textureId or metadata.texture, metadata.gender, metadata.image or metadata.icon)
  metadata.itemType = metadata.itemType or 'clothing'
  metadata.inventoryOnly = true
  metadata.shopPurchase = true
  metadata.purchaseSource = 'nv_cloth'
  metadata.equipped = false

  -- These flags are intentionally duplicated because different CM inventory builds used
  -- different names while evolving. The result is the same: buying never wears the item.
  metadata.preferredContainer = 'inventory'
  metadata.preferredStorage = 'inventory'
  metadata.inventoryTarget = 'inventory'
  metadata.slotGroup = 'inventory'
  metadata.autoEquip = false
  metadata.autoWear = false
  metadata.wearOnBuy = false
  metadata.equipOnAdd = false
  metadata.directEquip = false

  local lastErr = nil

  -- First force normal storage slots only. This prevents a clothing definition with an
  -- equipmentSlot like outerwear/pants/shoes/bag from being placed straight onto the body.
  for _, slot in ipairs(normalInventorySlots()) do
    local ok, resultOrErr = addItemViaCmInventory(src, itemName, amount, cloneTable(metadata), 'nv_cloth_purchase_inventory_only', slot)
    if ok then
      print(('[nv_cloth] Purchase added to inventory src=%s item=%s slot=%s image=%s bagLevel=%s'):format(src, itemName, tostring(resultOrErr or slot), tostring(metadata.image), tostring(metadata.bagLevel)))
      return true, resultOrErr or slot
    end
    lastErr = resultOrErr or lastErr
    if not shouldTryNextSlot(resultOrErr) then break end
  end

  -- Final compatibility fallback for older cm-inventory builds that ignore preferredSlot.
  -- CM inventory's findEmptySlot resolves pockets first, then unlocked backpack slots.
  local ok, resultOrErr = addItemViaCmInventory(src, itemName, amount, cloneTable(metadata), 'nv_cloth_purchase_inventory_only', nil)
  if ok then
    print(('[nv_cloth] Purchase added to inventory src=%s item=%s slot=%s image=%s bagLevel=%s'):format(src, itemName, tostring(resultOrErr), tostring(metadata.image), tostring(metadata.bagLevel)))
    return true, resultOrErr
  end

  lastErr = resultOrErr or lastErr
  print(('[nv_cloth] AddItem failed src=%s item=%s image=%s bagLevel=%s err=%s'):format(src, itemName, tostring(metadata.image), tostring(metadata.bagLevel), tostring(lastErr)))
  return false, tostring(lastErr or 'No empty pocket/backpack slot. Equip a better bag or clear inventory space.')
end

RegisterNetEvent('nvCloth:buyClothes')
AddEventHandler('nvCloth:buyClothes', function(method, outfit)
  local src = source
  method = method == 'cash' and 'cash' or 'bank'

  local rawItems = outfit and outfit.items or {}
  if type(rawItems) ~= 'table' or #rawItems == 0 then
    notify(src, 'No clothing selected.', 'error')
    TriggerClientEvent('nvCloth:client:purchaseFailed', src, 'No clothing selected.')
    return
  end

  local total = 0
  local metadataItems = {}
  local receiptItems = {}

  for _, raw in ipairs(rawItems) do
    local meta, err = normaliseItem(raw)
    if not meta then
      notify(src, err or 'Invalid clothing item.', 'error')
      TriggerClientEvent('nvCloth:client:purchaseFailed', src, err or 'Invalid clothing item.')
      return
    end

    if meta.catalogDisabled == true or meta.enabled == false then
      notify(src, 'This clothing item is not available.', 'error')
      TriggerClientEvent('nvCloth:client:purchaseFailed', src, 'This clothing item is not available.')
      return
    end

    local allowed, accessErr = restrictionAllowed(src, meta)
    if not allowed then
      notify(src, accessErr, 'error')
      TriggerClientEvent('nvCloth:client:purchaseFailed', src, accessErr)
      return
    end

    local price = priceFor(meta.categoryType, meta)
    total = total + price
    metadataItems[#metadataItems + 1] = meta
    receiptItems[#receiptItems + 1] = {
      itemName = meta.itemName,
      label = meta.label,
      category = meta.categoryType,
      drawable = meta.drawableId,
      texture = meta.textureId,
      price = price,
      image = meta.image,
      gender = meta.gender,
    }
  end

  -- Check inventory availability before taking money. AddItem below is still the final source of truth.
  for _, meta in ipairs(metadataItems) do
    local canCarry, carryErr = canCarryClothingItem(src, meta.itemName, 1)
    if canCarry ~= true then
      notify(src, tostring(carryErr or 'You cannot carry this item.'), 'error')
      TriggerClientEvent('nvCloth:client:purchaseFailed', src, tostring(carryErr or 'You cannot carry this item.'))
      return
    end
  end

  local receiptId = makeReceiptId(src)
  local paid, paymentOrErr = takeCharacterMoney(src, method, total)
  if paid ~= true then
    notify(src, tostring(paymentOrErr or 'You do not have enough money.'), 'error')
    savePurchaseReceipt(src, receiptId, { method = method, characterId = getStateCharacterId(src) }, total, receiptItems, 'payment_failed', tostring(paymentOrErr))
    auditLog(src, 'purchase_payment_failed', { receiptId = receiptId, method = method, total = total, reason = tostring(paymentOrErr), items = receiptItems }, receiptId)
    TriggerClientEvent('nvCloth:client:purchaseFailed', src, tostring(paymentOrErr or 'You do not have enough money.'))
    return
  end

  local paymentInfo = paymentOrErr
  local addedSlots = {}
  local addedRecords = {}
  for index, meta in ipairs(metadataItems) do
    local itemName = meta.itemName or meta.item_name or meta.name
    -- Keep itemName inside metadata too. Some inventory/itemactions builds use metadata.itemName
    -- for label/image/action routing while the DB row uses item_name separately.
    meta.itemName = itemName
    meta.item_name = itemName
    meta.name = itemName

    -- Buy-to-inventory only. Do not auto-save appearance or directly equip from the shop.
    local added, addErr = addClothingInventoryItem(src, itemName, 1, meta)
    if added ~= true then
      local rolledBack = rollbackAddedClothing(src, addedRecords)
      local refunded = refundCharacterMoney(src, paymentInfo, total)
      local msg = ('Could not add clothing item to inventory: %s%s%s'):format(tostring(addErr or itemName), rolledBack and ' Added items rolled back.' or ' Check partial items manually.', refunded and ' Payment refunded.' or ' Refund failed; staff notified.')
      notify(src, msg, 'error')
      print(('[nv_cloth] AddItem failed src=%s item=%s err=%s refunded=%s'):format(src, itemName, tostring(addErr), tostring(refunded)))
      savePurchaseReceipt(src, receiptId, paymentInfo, total, receiptItems, refunded and 'refunded_inventory_failed' or 'refund_failed_inventory_failed', tostring(addErr))
      auditLog(src, refunded and 'purchase_refunded_inventory_failed' or 'purchase_refund_failed', {
        receiptId = receiptId,
        method = method,
        total = total,
        failedItem = itemName,
        failedIndex = index,
        reason = tostring(addErr),
        rolledBack = rolledBack,
        items = receiptItems,
      }, receiptId)
      TriggerClientEvent('nvCloth:client:purchaseFailed', src, msg)
      return
    end
    addedSlots[#addedSlots + 1] = addErr
    addedRecords[#addedRecords + 1] = { itemName = itemName, metadata = cloneTable(meta), slot = addErr }
    receiptItems[index].slot = addErr
  end

  savePurchaseReceipt(src, receiptId, paymentInfo, total, receiptItems, 'paid', nil)
  auditLog(src, 'purchase_paid', { receiptId = receiptId, method = method, total = total, slots = addedSlots, items = receiptItems }, receiptId)
  notify(src, ('Clothing purchased. Receipt %s. Item added to your bag.'):format(receiptId), 'success')
  TriggerClientEvent('nvCloth:client:purchaseComplete', src, {
    receiptId = receiptId,
    total = total,
    method = method,
    count = #metadataItems,
    slots = addedSlots,
  })
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
        local allowed = restrictionAllowed(src, row)
        if img ~= '' and allowed then
          filtered[#filtered + 1] = row
        end
      end
    end
    rows = filtered
  end

  TriggerClientEvent('nvCloth:client:cachedShopCatalog', src, requestId, rows)
end)


--========================================================
-- Favourites (per-character, global across all shops)
--========================================================
local function sanitizeFavKey(key)
  key = tostring(key or ''):lower()
  -- Only gender:category:drawable:texture shapes; strip anything unexpected.
  key = key:gsub('[^%w:_%-]', '')
  if #key == 0 or #key > 150 then return nil end
  return key
end

local function sendFavouritesToClient(src)
  local charId = getStateCharacterId(src)
  local keys = {}
  if charId then
    local ok, rows = pcall(function()
      return MySQL.query.await('SELECT fav_key FROM nv_cloth_favourites WHERE character_id = ?', { charId })
    end)
    if ok and type(rows) == 'table' then
      for _, r in ipairs(rows) do keys[#keys + 1] = r.fav_key end
    end
  end
  TriggerClientEvent('nvCloth:client:favourites', src, keys)
end

RegisterNetEvent('nvCloth:server:getFavourites', function()
  sendFavouritesToClient(source)
end)

RegisterNetEvent('nvCloth:server:toggleFavourite', function(favKey, on)
  local src = source
  local charId = getStateCharacterId(src)
  if not charId then return end
  local key = sanitizeFavKey(favKey)
  if not key then return end

  if on == true then
    dbUpdate('INSERT IGNORE INTO nv_cloth_favourites (character_id, fav_key) VALUES (?, ?)', { charId, key })
  else
    dbUpdate('DELETE FROM nv_cloth_favourites WHERE character_id = ? AND fav_key = ?', { charId, key })
  end
  -- Echo the authoritative list back so the UI stays in sync across shops.
  sendFavouritesToClient(src)
end)


--========================================================
-- Admin capture-camera overrides (tuned live in the admin panel)
--========================================================
local function sendCaptureCamerasToClient(src)
  local overrides = {}
  local ok, rows = pcall(function()
    return MySQL.query.await('SELECT category, dist, z, fov FROM nv_cloth_capture_cameras', {})
  end)
  if ok and type(rows) == 'table' then
    for _, r in ipairs(rows) do
      overrides[tostring(r.category)] = {
        dist = tonumber(r.dist),
        z = tonumber(r.z),
        fov = tonumber(r.fov),
      }
    end
  end
  TriggerClientEvent('nvCloth:client:captureCameras', src, overrides)
end

RegisterNetEvent('nvCloth:server:getCaptureCameras', function()
  local src = source
  if not isClothingAdmin(src) then return end
  sendCaptureCamerasToClient(src)
end)

RegisterNetEvent('nvCloth:server:saveCaptureCamera', function(data)
  local src = source
  if not isClothingAdmin(src) then
    notify(src, 'You do not have permission to tune capture cameras.', 'error')
    return
  end
  if type(data) ~= 'table' then return end
  local category = tostring(data.category or ''):lower():gsub('[^%w_%-]', '')
  if category == '' then return end

  local dist = tonumber(data.dist)
  local z = tonumber(data.z)
  local fov = tonumber(data.fov)
  if not dist or not z or not fov then return end
  -- Clamp to sane ranges so a bad slider value can't wreck the camera.
  dist = math.max(0.6, math.min(6.0, dist))
  z = math.max(-1.5, math.min(1.5, z))
  fov = math.max(6.0, math.min(70.0, fov))

  dbUpdate([[INSERT INTO nv_cloth_capture_cameras (category, dist, z, fov)
             VALUES (?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE dist = VALUES(dist), z = VALUES(z), fov = VALUES(fov)]],
    { category, dist, z, fov })
  auditLog(src, 'capture_camera_saved', { category = category, dist = dist, z = z, fov = fov }, category)
  sendCaptureCamerasToClient(src)
end)

RegisterNetEvent('nvCloth:server:resetCaptureCamera', function(category)
  local src = source
  if not isClothingAdmin(src) then return end
  category = tostring(category or ''):lower():gsub('[^%w_%-]', '')
  if category == '' then return end
  dbUpdate('DELETE FROM nv_cloth_capture_cameras WHERE category = ?', { category })
  auditLog(src, 'capture_camera_reset', { category = category }, category)
  sendCaptureCamerasToClient(src)
end)

--========================================================
-- Admin per-category capture crops (set once, reused every capture of that category)
--========================================================
local function sendCaptureCropsToClient(src)
  local crops = {}
  local ok, rows = pcall(function()
    return MySQL.query.await('SELECT category, trim_left, trim_top, trim_right, trim_bottom FROM nv_cloth_capture_crops', {})
  end)
  if ok and type(rows) == 'table' then
    for _, r in ipairs(rows) do
      crops[tostring(r.category)] = {
        left = tonumber(r.trim_left) or 0,
        top = tonumber(r.trim_top) or 0,
        right = tonumber(r.trim_right) or 0,
        bottom = tonumber(r.trim_bottom) or 0,
      }
    end
  end
  TriggerClientEvent('nvCloth:client:captureCrops', src, crops)
end

RegisterNetEvent('nvCloth:server:getCaptureCrops', function()
  local src = source
  if not isClothingAdmin(src) then return end
  sendCaptureCropsToClient(src)
end)

RegisterNetEvent('nvCloth:server:saveCaptureCrop', function(data)
  local src = source
  if not isClothingAdmin(src) then
    notify(src, 'You do not have permission to set capture crops.', 'error')
    return
  end
  if type(data) ~= 'table' then return end
  local category = tostring(data.category or ''):lower():gsub('[^%w_%-]', '')
  if category == '' then return end

  -- Percent trims from each edge, clamped so a bad value can't blank the icon.
  local function clampTrim(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0 end
    if v > 45 then v = 45 end
    return v
  end
  local left = clampTrim(data.left)
  local top = clampTrim(data.top)
  local right = clampTrim(data.right)
  local bottom = clampTrim(data.bottom)

  dbUpdate([[INSERT INTO nv_cloth_capture_crops (category, trim_left, trim_top, trim_right, trim_bottom)
             VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE trim_left = VALUES(trim_left), trim_top = VALUES(trim_top),
                                     trim_right = VALUES(trim_right), trim_bottom = VALUES(trim_bottom)]],
    { category, left, top, right, bottom })
  auditLog(src, 'capture_crop_saved', { category = category, left = left, top = top, right = right, bottom = bottom }, category)
  sendCaptureCropsToClient(src)
end)

RegisterNetEvent('nvCloth:server:resetCaptureCrop', function(category)
  local src = source
  if not isClothingAdmin(src) then return end
  category = tostring(category or ''):lower():gsub('[^%w_%-]', '')
  if category == '' then return end
  dbUpdate('DELETE FROM nv_cloth_capture_crops WHERE category = ?', { category })
  auditLog(src, 'capture_crop_reset', { category = category }, category)
  sendCaptureCropsToClient(src)
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
  copyRestrictions(entry, data)

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
    entry.bag_level = level
    entry.level = level
    entry.itemName = 'clothing_bags'
    entry.item_name = 'clothing_bags'
    entry.description = ('Level %s bag. Unlocks backpack slots.'):format(level)
    print(('[nv_cloth] Admin save bag drawable=%s level=%s image=%s destination=%s'):format(tostring(drawable), tostring(level), tostring(entry.image), tostring(destination)))
  end

  local ok, result, err = pcall(function()
    return exports['cm-items']:SaveClothingCatalogEntry(entry)
  end)

  if ok and result then
    auditLog(src, enabled and 'catalog_enabled' or 'catalog_disabled', entry, ('%s:%s:%s:%s'):format(gender, category, drawable, texture))
    notify(src, enabled and 'Clothing item enabled for all textures. Torso fit saved if this is a torso item.' or 'Clothing item disabled for all textures.', enabled and 'success' or 'info')
    TriggerClientEvent('nvCloth:client:adminCatalogSaved', src, entry)
  else
    local reason = tostring(err or result or 'unknown')
    print(('[nv_cloth] Catalog save failed for %s/%s/%s gender=%s shop=%s: %s'):format(category, def.index, drawable, gender, shop, reason))
    notify(src, ('Could not update clothing item: %s'):format(reason), 'error')
  end
end)


RegisterNetEvent('nvCloth:server:adminBulkToggleItems', function(data)
  local src = source
  if not isClothingAdmin(src) then
    notify(src, 'You do not have permission to bulk edit clothing catalog.', 'error')
    return
  end
  if GetResourceState('cm-items') ~= 'started' then
    notify(src, 'cm-items is not started.', 'error')
    return
  end
  data = type(data) == 'table' and data or {}
  local items = type(data.items) == 'table' and data.items or {}
  local enabled = data.enabled == true or data.enabled == 1
  local updated, failed = 0, 0
  local maxItems = math.min(#items, 250)

  for i = 1, maxItems do
    local row = items[i]
    if type(row) == 'table' then
      local category = tostring(row.category or row.type or ''):lower()
      local def = CATEGORY_COMPONENTS[category]
      local drawable = tonumber(row.drawableId or row.drawable or row.componentId or row.component)
      if def and drawable then
        local texture = tonumber(row.textureId or row.texture or -1) or -1
        local gender = tostring(row.gender or data.gender or 'male'):lower() == 'female' and 'female' or 'male'
        local shop = tostring(row.shop or data.shop or 'clothes'):lower()
        local label = tostring(row.label or row.name or ('%s %s'):format(def.label, drawable))
        local destination = normaliseDestination(row.destination and row or data)
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
          description = row.description or ('%s clothing item'):format(def.label),
          price = tonumber(row.price or data.price or Config.Prices[category] or 0) or 0,
          category = category,
          shop = shop,
          image = row.image or row.icon,
          icon = row.icon or row.image,
          enabled = enabled,
          updatedBy = ('player:%s'):format(src),
          updated_by = ('player:%s'):format(src),
        }
        copyRestrictions(entry, row)
        applyDestinationToEntry(entry, destination)
        if category == 'torso' then
          entry.arms = tonumber(row.arms)
          entry.armsTexture = tonumber(row.armsTexture) or 0
          entry.arms_texture = entry.armsTexture
          entry.undershirt = tonumber(row.undershirt)
          entry.undershirtTexture = tonumber(row.undershirtTexture) or 0
          entry.undershirt_texture = entry.undershirtTexture
        end
        if category == 'bags' then
          local level = tonumber(row.bagLevel or row.bag_level or row.level)
          if level then
            level = math.max(1, math.min(4, math.floor(level)))
            entry.bagLevel = level
            entry.bag_level = level
            entry.level = level
            entry.itemName = 'clothing_bags'
            entry.item_name = 'clothing_bags'
            entry.description = ('Level %s bag. Unlocks backpack slots.'):format(level)
          end
        end
        local ok, result = pcall(function() return exports['cm-items']:SaveClothingCatalogEntry(entry) end)
        if ok and result then updated = updated + 1 else failed = failed + 1 end
      else
        failed = failed + 1
      end
    end
  end

  auditLog(src, enabled and 'catalog_bulk_enabled' or 'catalog_bulk_disabled', { count = updated, failed = failed, requested = #items, enabled = enabled })
  notify(src, ('Bulk update complete: %s updated, %s failed.'):format(updated, failed), failed > 0 and 'info' or 'success')
  TriggerClientEvent('nvCloth:client:adminCatalogSaved', src, { bulk = true, updated = updated, failed = failed, enabled = enabled })
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
    icon = imagePath,
    enabled = true,
    createdBy = ('player:%s'):format(src),
    created_by = ('player:%s'):format(src),
    updatedBy = ('player:%s'):format(src),
    updated_by = ('player:%s'):format(src),
  }
  copyRestrictions(entry, data)

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
    local level = tonumber(data.bagLevel or data.bag_level or data.level) or 1
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

  --========================================================
  -- ARMOR / GUNS BRANCH (model b, cm-items owns the image)
  -- Vest captures are NOT clothing items. We DON'T save a file here and we DON'T
  -- write a clothing_catalog row. Instead we hand the raw base64 PNG + vest data
  -- to the gun admin form. cm-items saves the PNG when the admin creates the item.
  --========================================================
  local category = tostring(data.category or ''):lower()
  local shopKey = tostring(data.shop or ''):lower()
  if category == 'armor' or shopKey == 'guns' then
    if GetResourceState('cm-gunstore') ~= 'started' then
      TriggerClientEvent('nvCloth:client:inventoryIconSaveFailed', src, 'cm-gunstore_not_started')
      notify(src, 'cm-gunstore is not started; cannot deliver vest image.', 'error')
      return
    end

    -- Re-encode the decoded bytes to a base64 data URL to forward to the gun store.
    local dataUrl = data.dataUrl or data.imageBase64
    if type(dataUrl) == 'string' and dataUrl ~= '' and not dataUrl:find('^data:image') then
      dataUrl = 'data:image/png;base64,' .. dataUrl
    end

    local vestPayload = {
      imageData = dataUrl, -- base64 PNG; cm-items saves it on item create
      gender = tostring(data.gender or 'both'),
      componentId = tonumber(data.componentIndex or data.componentId) or 9,
      drawableId = tonumber(data.drawableId or data.drawable),
      textureId = tonumber(data.textureId or data.texture or 0) or 0,
      armorValue = tonumber(data.armorValue or data.armor_value) or 0, -- gun admin sets real value
      label = data.label,
      price = data.price,
      destination = data.destination,
    }
    print(('[nv_cloth] vest captured for gun store drawable=%s texture=%s (image forwarded as base64)'):format(
      tostring(vestPayload.drawableId), tostring(vestPayload.textureId)))

    local delivered = pcall(function()
      return exports['cm-gunstore']:ReceiveArmorImage(src, vestPayload)
    end)
    if not delivered then
      TriggerEvent('cm-gunstore:server:armorImageReady', src, vestPayload)
    end
    notify(src, 'Vest captured. Open the gun admin form to set name/price/armor and create the item.', 'success')
    TriggerClientEvent('nvCloth:client:inventoryIconSaved', src, { armor = true })
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

  auditLog(src, 'catalog_icon_saved', entryOrErr, entryOrErr and ('%s:%s:%s:%s'):format(tostring(entryOrErr.gender), tostring(entryOrErr.category), tostring(entryOrErr.drawableId), tostring(entryOrErr.textureId)) or nil)
  notify(src, (data.destination == 'hidden') and 'Inventory icon captured. Item saved hidden/event-only.' or 'Inventory icon captured and clothing enabled.', 'success')
  TriggerClientEvent('nvCloth:client:inventoryIconSaved', src, entryOrErr)
end)
