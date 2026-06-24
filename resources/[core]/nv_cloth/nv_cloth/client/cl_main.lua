--========================================================
-- nvCloth – NPC Shops, Blips & E Interaction
-- cm-core / cm-inventory version
--========================================================

local spawnedShopPeds = {}
local defaultNpcModel = `s_f_y_shop_low`

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

local function createShopPed(shopKey, index, shop, coords)
  local npcModel = shop.npcModel or shop.pedModel or defaultNpcModel
  local model = loadModel(npcModel)
  local heading = shop.heading or shop.npcHeading or 0.0

  -- Optional per-location vector4 heading support if you add vector4 coords later.
  if coords.w then heading = coords.w end

  local ped = CreatePed(0, model, coords.x, coords.y, coords.z - 1.0, heading, false, true)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetPedCanRagdoll(ped, false)
  TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)

  spawnedShopPeds[#spawnedShopPeds + 1] = ped
  SetModelAsNoLongerNeeded(model)
end

RegisterNetEvent('nv_cloth:openShopInteraction', function(label, categories, shopKey, shopData)
  if not opened then
    openClothShop(label, categories, shopKey, shopData)
  end
end)

CreateThread(function()
  -- Blips + NPCs
  for shopKey, shop in pairs(Config.Shops or {}) do
    if shop.coords then
      for index, pos in pairs(shop.coords) do
        local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
        SetBlipSprite(blip, (shop.blip and shop.blip.style) or 73)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, (shop.blip and shop.blip.size) or 0.5)
        SetBlipColour(blip, (shop.blip and shop.blip.color) or 81)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(shop.label or 'Clothing Store')
        EndTextCommandSetBlipName(blip)

        createShopPed(shopKey, index, shop, pos)
      end
    end
  end
end)

CreateThread(function()
  while true do
    local sleep = 1000
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)

    for shopKey, shop in pairs(Config.Shops or {}) do
      if shop.coords then
        for _, pos in pairs(shop.coords) do
          local dist = #(playerCoords - vector3(pos.x, pos.y, pos.z))

          if dist <= 12.0 then
            sleep = 0
          end

          if dist <= 2.0 and not opened then
            DrawText3D(pos.x, pos.y, pos.z + 1.05, ('[E] Open %s'):format(shop.label or 'Clothing Store'))

            if IsControlJustPressed(0, 38) then -- E
              TriggerEvent('nv_cloth:openShopInteraction', shop.label, shop.categories, shopKey, shop)
            end
          end
        end
      end
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
