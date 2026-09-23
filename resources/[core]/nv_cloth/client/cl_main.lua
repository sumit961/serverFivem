--========================================================
-- nvCloth – NPC Shops, Blips & E Interaction
-- cm-core / cm-inventory version
--========================================================

local spawnedShopPeds = {}
local shopPedByLocation = {}
local lastNpcGreeting = {}
local defaultNpcModel = `s_f_y_shop_low`


-- The E prompt and the clerk conversation both come from cm-ui so they look like
-- every other CM interaction instead of nv_cloth drawing its own text. Guarded
-- at call time rather than declared as a manifest dependency: if cm-ui is
-- stopped the store still opens, it just skips straight past the conversation.
local function cmUiReady()
  return GetResourceState('cm-ui') == 'started'
end

local activePrompt = nil

local function showPrompt(key, label, name, role)
  if activePrompt == key or not cmUiReady() then return end
  activePrompt = key
  pcall(function()
    exports['cm-ui']:ShowInteract({ key = 'E', label = label, name = name, role = role })
  end)
end

local function hidePrompt()
  if not activePrompt then return end
  activePrompt = nil
  if not cmUiReady() then return end
  pcall(function() exports['cm-ui']:HideInteract() end)
end

local function dialogueOpen()
  if not cmUiReady() then return false end
  local ok, result = pcall(function() return exports['cm-ui']:IsNpcDialogueOpen() end)
  return ok and result == true
end

-- 'clothes' lists rich per-storefront locations; 'accessories' still uses a
-- plain coords list, so normalise both into one shape.
local function shopLocations(shop)
  if type(shop.locations) == 'table' then return shop.locations end
  local list = {}
  for _, pos in pairs(shop.coords or {}) do
    list[#list + 1] = { pos = pos }
  end
  return list
end

local function greetShopNpc(key, ped, shop)
  if not (Config.ClothingStore and Config.ClothingStore.EnableNpcSpeech ~= false) then return end
  if not ped or ped == 0 or not DoesEntityExist(ped) then return end
  local now = GetGameTimer()
  local cooldown = tonumber(Config.ClothingStore.NpcGreetingCooldown or 18000) or 18000
  if lastNpcGreeting[key] and (now - lastNpcGreeting[key]) < cooldown then return end
  lastNpcGreeting[key] = now
  local speech = (shop and shop.npcSpeech) or 'SHOP_GREET'
  pcall(function() PlayPedAmbientSpeechNative(ped, speech, 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR') end)
end

local function DrawText3D(x, y, z, text)
  SetDrawOrigin(x, y, z, 0)
  SetTextScale(0.35, 0.35)
  SetTextFont(4)
  SetTextProportional(1)
  SetTextCentre(true)
  SetTextColour(255, 255, 255, 215)
  BeginTextCommandDisplayText('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayText(0.0, 0.0)
  ClearDrawOrigin()
end

local function loadModel(model)
  if type(model) == 'string' then model = joaat(model) end
  if not IsModelInCdimage(model) then model = defaultNpcModel end

  RequestModel(model)
  while not HasModelLoaded(model) do
    Wait(10)
  end

  return model
end

local function createShopPed(shopKey, index, shop, loc)
  local npcModel = loc.npcModel or shop.npcModel or shop.pedModel or defaultNpcModel
  local model = loadModel(npcModel)

  -- loc.npc is the clerk's own spot behind the counter, captured with
  -- /clothingnpcpos. loc.pos is the storefront/blip point, used only until a
  -- counter position is filled in -- it puts the clerk in the doorway.
  local stand = loc.npc or loc.pos
  local heading = stand.w or loc.heading or shop.heading or shop.npcHeading or 0.0
  local groundZ = loc.npc and stand.z or (stand.z - 1.0)

  local ped = CreatePed(0, model, stand.x, stand.y, groundZ, heading, false, true)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetPedCanRagdoll(ped, false)
  TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)

  spawnedShopPeds[#spawnedShopPeds + 1] = ped
  shopPedByLocation[('%s:%s'):format(shopKey, index)] = ped
  SetModelAsNoLongerNeeded(model)
end

RegisterNetEvent('nv_cloth:openShopInteraction', function(label, categories, shopKey, shopData)
  if not opened then
    openClothShop(label, categories, shopKey, shopData)
  end
end)

CreateThread(function()
  -- Blips (every shop) + NPCs (only shops NOT already handled by
  -- cl_stores.lua's clerk system). The 14 physical 'clothes' storefronts get
  -- their clerk, [E] prompt, and dialogue from cl_stores.lua's
  -- Config.Shops[1..N] StoreList instead -- that system also owns the
  -- counter/dressing-room/camera flow. Spawning a second ped + prompt here
  -- too was creating two overlapping clerks at every clothing store.
  for shopKey, shop in pairs(Config.Shops or {}) do
    for index, loc in ipairs(shopLocations(shop)) do
      local pos = loc.pos
      local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
      SetBlipSprite(blip, (shop.blip and shop.blip.style) or 73)
      SetBlipDisplay(blip, 4)
      SetBlipScale(blip, (shop.blip and shop.blip.size) or 0.5)
      SetBlipColour(blip, (shop.blip and shop.blip.color) or 81)
      SetBlipAsShortRange(blip, true)
      BeginTextCommandSetBlipName('STRING')
      AddTextComponentString(loc.label or shop.label or 'Clothing Store')
      EndTextCommandSetBlipName(blip)

      if shopKey ~= 'clothes' then
        createShopPed(shopKey, index, shop, loc)
      end
    end
  end
end)

-- Opens the wardrobe for one storefront. The shop table is copied so the
-- location's own label, categories and exit point reach the shop UI without
-- mutating the shared 'clothes' entry every location hangs off.
local function openLocation(shopKey, shop, loc)
  local merged = {}
  for k, v in pairs(shop) do merged[k] = v end
  merged.label = loc.label or shop.label
  merged.categories = loc.categories or shop.categories
  merged.exitCoords = loc.exitCoords or shop.exitCoords
    or vec4(loc.pos.x, loc.pos.y, loc.pos.z, 0.0)
  merged.locationId = loc.id
  TriggerEvent('nv_cloth:openShopInteraction', merged.label, merged.categories, shopKey, merged)
end

-- cm-ui dialogue choices name an event rather than a callback, because closures
-- do not marshal across resources. Remember which clerk was talking so the
-- answer opens the right storefront.
local pendingClerk = nil

AddEventHandler('nv_cloth:client:clerkBrowse', function()
  local pending = pendingClerk
  pendingClerk = nil
  if pending then openLocation(pending.shopKey, pending.shop, pending.loc) end
end)

AddEventHandler('nv_cloth:client:clerkDismissed', function()
  pendingClerk = nil
end)

local function talkToClerk(shopKey, shop, loc, ped)
  if not cmUiReady() or not ped or not DoesEntityExist(ped) then
    openLocation(shopKey, shop, loc)
    return
  end

  hidePrompt()
  pendingClerk = { shopKey = shopKey, shop = shop, loc = loc }

  local ok = pcall(function()
    exports['cm-ui']:OpenNpcDialogue(ped, {
      name = loc.npcName or 'Store Clerk',
      role = loc.label or shop.label or 'Clothing',
      quote = loc.npcDialog or 'Welcome. Browse the racks and pay at the counter.',
      choices = {
        {
          id = 'browse',
          label = 'Browse clothing',
          description = 'Open the wardrobe and try things on.',
          event = 'nv_cloth:client:clerkBrowse',
        },
      },
      closeEvent = 'nv_cloth:client:clerkDismissed',
    })
  end)

  if not ok then
    pendingClerk = nil
    openLocation(shopKey, shop, loc)
  end
end

-- Stand where the clerk should be, run this, and paste the printed line into
-- that location's `npc` field in shared/config.lua.
RegisterCommand('clothingnpcpos', function()
  local coords = GetEntityCoords(PlayerPedId())
  local line = ('npc = vec4(%.3f, %.3f, %.3f, %.1f),'):format(
    coords.x, coords.y, coords.z, GetEntityHeading(PlayerPedId()))
  print(('[nv_cloth] %s'):format(line))
  TriggerEvent('chat:addMessage', { args = { 'nv_cloth', line } })
end, false)

CreateThread(function()
  while true do
    local sleep = 1000
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)

    local nearest = nil

    -- 'clothes' locations are excluded here too -- cl_stores.lua owns their
    -- [E] prompt and dialogue now that it owns their clerk.
    for shopKey, shop in pairs(Config.Shops or {}) do
      if shopKey ~= 'clothes' then
        for index, loc in ipairs(shopLocations(shop)) do
          local pos = loc.pos
          local dist = #(playerCoords - vector3(pos.x, pos.y, pos.z))

          if dist <= 12.0 then
            sleep = 0
          end

          if dist <= 2.5 and (not nearest or dist < nearest.dist) then
            nearest = { dist = dist, shopKey = shopKey, shop = shop, loc = loc, index = index }
          end
        end
      end
    end

    -- The prompt stays hidden while the wardrobe or the conversation is up, as
    -- world prompts must not sit on top of an open NUI.
    if nearest and not opened and not dialogueOpen() then
      local key = ('%s:%s'):format(nearest.shopKey, nearest.index)
      local ped = shopPedByLocation[key]
      greetShopNpc(key, ped, nearest.shop)
      showPrompt(key,
        ('Talk to %s'):format(nearest.loc.npcName or 'the clerk'),
        nearest.loc.npcName,
        nearest.loc.label or nearest.shop.label)

      if IsControlJustPressed(0, 38) then -- E
        talkToClerk(nearest.shopKey, nearest.shop, nearest.loc, ped)
      end
    else
      hidePrompt()
    end

    Wait(sleep)
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end

  for _, ped in ipairs(spawnedShopPeds) do
    if DoesEntityExist(ped) then
      DeleteEntity(ped)
    end
  end
end)
