local config = lib.load("core.market.config")

local Utils = require "modules.utils.client"
local Target = require "modules.target.client"

--[[ state ]]

Market = {}

local orderDroneObject = nil
local orderBagObject = nil

--[[ functions ]]

local function deleteDroneObject()
    if orderDroneObject and DoesEntityExist(orderDroneObject) then
        DeleteEntity(orderDroneObject)
        SetEntityAsNoLongerNeeded(orderDroneObject)
    end
    orderDroneObject = nil
end

local function deleteBagObject()
    if orderBagObject and DoesEntityExist(orderBagObject) then
        DeleteEntity(orderBagObject)
        SetEntityAsNoLongerNeeded(orderBagObject)
    end
    orderBagObject = nil
end

local function dropLootableBag()
    FreezeEntityPosition(orderBagObject, false)
    DetachEntity(orderBagObject, true, true)
    SetEntityDynamic(orderBagObject, true)
    ActivatePhysics(orderBagObject)

    Target.addLocalEntity(orderBagObject, { {
        label = locale("market.collect"),
        icon = "fa-solid fa-briefcase",
        distance = 2.0,
        onSelect = function()
            Target.removeLocalEntity(orderBagObject)
            lib.playAnim(cache.ped, "pickup_object", "pickup_low")
            lib.callback.await(_e("server:market:collectLootableBag"), false)
            Citizen.Wait(1000)
            deleteBagObject()
        end,
    } })
end

Market.onUnload = function()
    deleteBagObject()
    deleteDroneObject()
end

-- Market itemlerini type'a göre ayıran fonksiyonlar
Market.getBuyItems = function()
    local buyItems = {}
    for _, item in pairs(config.items) do
        if item.type == nil or item.type == "buy" then
            table.insert(buyItems, item)
        end
    end
    return buyItems
end

Market.getSellItems = function()
    local sellItems = {}
    for _, item in pairs(config.items) do
        if item.type == nil or item.type == "sell" then
            table.insert(sellItems, item)
        end
    end
    return sellItems
end

-- Eski fonksiyon uyumluluğu için
Market.getDataItems = function()
    return config.items
end

--[[ events ]]

RegisterNUICallback("nui:market:payCart", function(data, resultCallback)
    local response = lib.callback.await(_e("server:market:payCart"), false, data)
    if response.error then
        client.sendReactAlert(response.error, "error")
        return resultCallback(false)
    end
    client.hideUI()
    Utils.notify(locale("market.order_delivered"), "success")
    client.sendReactMessage("ui:setOrderInfo", { delivery_time = response.pendingDelivery.delivery_time })
    resultCallback(true)
end)

RegisterNUICallback("nui:market:sellItems", function(data, resultCallback)
    local response = lib.callback.await(_e("server:market:sellItems"), false, data)
    if response.error then
        client.sendReactAlert(response.error, "error")
        return resultCallback(false)
    end
    client.sendReactAlert(locale("market.items_sold"), "success")
    resultCallback(true)
end)

RegisterNetEvent(_e("client:market:spawnDeliveryDrone"), function(data)
    if not lib.callback.await(_e("server:market:getPlayerDelivery"), false) then
        return
    end

    local playerPed = cache.ped
    local playerCoords = GetEntityCoords(playerPed)
    local spawnRadius = 75.0
    local spawnAngle = math.rad(math.random(0, 360))
    local spawnPos = vector3(
        playerCoords.x + math.cos(spawnAngle) * spawnRadius,
        playerCoords.y + math.sin(spawnAngle) * spawnRadius,
        playerCoords.z + 10.0
    )

    local droneModel = config.droneDelivery.objectModel
    local bagModel = config.droneDelivery.bagModel
    local drone = Utils.createObject(droneModel, spawnPos, nil, true, true, false)
    orderDroneObject = drone
    SetEntityAsMissionEntity(drone, true, true)
    Utils.addBlip(drone, config.droneDelivery.blip)

    local bag = Utils.createObject(bagModel, spawnPos, nil, true, true, false)
    orderBagObject = bag
    SetEntityAsMissionEntity(bag, true, true)

    AttachEntityToEntity(bag, drone, 0, 0.0, 0.0, -0.5, 0.0, 0.0, 0.0, false, false, false, false, 2, true)

    local moveSpeed = 3.5
    local reachedTarget = false

    Citizen.CreateThread(function()
        while DoesEntityExist(drone) and not reachedTarget do
            local droneCoords = GetEntityCoords(drone)
            playerCoords = GetEntityCoords(playerPed)
            local distanceToPlayer = #(playerCoords - droneCoords)

            if distanceToPlayer < 5.0 then
                reachedTarget = true
                break
            end

            local targetPos = vector3(playerCoords.x, playerCoords.y, playerCoords.z + 4.0)
            local direction = targetPos - droneCoords
            local moveVector = direction / #direction * moveSpeed * 0.02
            SetEntityCoords(drone, droneCoords + moveVector, false, false, false, true)

            Citizen.Wait(0)
        end

        Citizen.Wait(3000)

        dropLootableBag()
        client.sendReactMessage("ui:setOrderInfo", nil)
        Citizen.Wait(5000)
        DeleteEntity(orderDroneObject)
    end)
end)
