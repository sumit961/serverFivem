if not Config or not Config.VehicleShop or not Config.VehicleShop.Enabled then
    return
end

VehicleShop = {
    shopCam = nil,
    previewVehicle = nil,
    currentShop = nil,
    testDriveVehicle = nil,
    testDriveTimer = nil,
    testDriveCoords = nil,
    inShop = false,
    rotationId = 0,
    isSpawning = false,
}

local vehicleStatsCache = {}

local function applyDefaultVehicleProperties(vehicle, model)
    if not vehicle or vehicle == 0 or not Config.Garage or not Config.Garage.GetVehicleProperties then
        return
    end
    local properties = Config.Garage.GetVehicleProperties(model)
    if properties then
        lib.setVehicleProperties(vehicle, properties)
    end
end

function spawnShopPed(pedConfig)
    local model = lib.requestModel(pedConfig.model)
    if not model then
        return nil
    end
    local ped = CreatePed(
        4, model,
        pedConfig.coords.x, pedConfig.coords.y, pedConfig.coords.z - 1.0,
        pedConfig.coords.w,
        false, true
    )
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    if pedConfig.scenario then
        TaskStartScenarioInPlace(ped, pedConfig.scenario, 0, true)
    elseif pedConfig.anim then
        local animDict = lib.requestAnimDict(pedConfig.anim.dict)
        TaskPlayAnim(
            ped, animDict, pedConfig.anim.clip,
            8.0, -8.0, -1, 1, 0,
            false, false, false
        )
        RemoveAnimDict(animDict)
    end
    SetModelAsNoLongerNeeded(model)
    return ped
end

function clampStat(value, maxValue)
    if not maxValue or maxValue <= 0 then
        return 0
    end
    local percent = math.floor((value / maxValue) * 100 + 0.5)
    if percent < 0 then
        return 0
    elseif percent > 100 then
        return 100
    end
    return percent
end

function getVehicleStats(model)
    if vehicleStatsCache[model] then
        return vehicleStatsCache[model]
    end
    local modelHash = type(model) == "number" and model or joaat(model)
    if not IsModelInCdimage(modelHash) or not IsModelAVehicle(modelHash) then
        vehicleStatsCache[model] = {
            maxSpeed = 0,
            acceleration = 0,
            braking = 0,
            handling = 0,
            seats = 0,
        }
        return vehicleStatsCache[model]
    end
    local vehicleClass = GetVehicleClassFromName(modelHash)
    local classMaxSpeed = GetVehicleClassEstimatedMaxSpeed(vehicleClass)
    local classMaxAccel = GetVehicleClassMaxAcceleration(vehicleClass)
    local classMaxBraking = GetVehicleClassMaxBraking(vehicleClass)
    local classMaxTraction = GetVehicleClassMaxTraction(vehicleClass)
    local stats = {
        maxSpeed = clampStat(GetVehicleModelEstimatedMaxSpeed(modelHash), classMaxSpeed),
        acceleration = clampStat(GetVehicleModelAcceleration(modelHash), classMaxAccel),
        braking = clampStat(GetVehicleModelMaxBraking(modelHash), classMaxBraking),
        handling = clampStat(GetVehicleModelMaxTraction(modelHash), classMaxTraction),
        seats = GetVehicleModelNumberOfSeats(modelHash),
    }
    vehicleStatsCache[model] = stats
    return stats
end

function buildShopItems(jobName, jobGrade)
    local items = {}
    for category, vehicles in pairs(Config.VehicleShop.Vehicles) do
        for _, vehicle in ipairs(vehicles) do
            local jobAllowed = false
            for _, allowedJob in ipairs(vehicle.allowedJobs) do
                if allowedJob == jobName then
                    jobAllowed = true
                    break
                end
            end
            local locked = not jobAllowed
            if jobAllowed and vehicle.allowedGrades[jobName] then
                locked = jobGrade < vehicle.allowedGrades[jobName]
            end
            local stats = getVehicleStats(vehicle.model)
            local armor = 0
            if vehicle.armor then
                armor = (math.max(0, math.min(4, vehicle.armor)) + 1) * 20
            end
            items[#items + 1] = {
                id = vehicle.id,
                name = vehicle.name,
                model = vehicle.model,
                category = category,
                price = vehicle.price,
                maxSpeed = stats.maxSpeed,
                acceleration = stats.acceleration,
                braking = stats.braking,
                handling = stats.handling,
                seats = stats.seats,
                armor = armor,
                description = vehicle.description,
                locked = locked,
                rank = vehicle.rank,
            }
        end
    end
    return items
end

function VehicleShop.initCamera(self, shopConfig)
    self.shopCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(
        self.shopCam,
        shopConfig.camera.coords.x,
        shopConfig.camera.coords.y,
        shopConfig.camera.coords.z
    )
    PointCamAtCoord(
        self.shopCam,
        shopConfig.camera.pointAt.x,
        shopConfig.camera.pointAt.y,
        shopConfig.camera.pointAt.z
    )
    SetCamFov(self.shopCam, shopConfig.camera.fov or 50.0)
    SetCamActive(self.shopCam, true)
    RenderScriptCams(true, true, 500, true, true)
end

function VehicleShop.destroyCamera(self)
    if not self.shopCam then
        return
    end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(self.shopCam, true)
    self.shopCam = nil
end

function VehicleShop.deletePreviewVehicle(self)
    if self.previewVehicle and DoesEntityExist(self.previewVehicle) then
        DeleteVehicle(self.previewVehicle)
        self.previewVehicle = nil
    end
end

function VehicleShop.spawnPreviewVehicle(self, model, shopConfig)
    if self.isSpawning then
        return
    end
    self.isSpawning = true
    self.rotationId = self.rotationId + 1
    local currentRotation = self.rotationId
    self:deletePreviewVehicle()
    local modelHash = lib.requestModel(model)
    if not modelHash or self.rotationId ~= currentRotation then
        self.isSpawning = false
        return
    end
    local spawn = shopConfig.vehicleSpawn
    self.previewVehicle = CreateVehicle(
        modelHash,
        spawn.x, spawn.y, spawn.z, spawn.w,
        false, false
    )
    SetEntityAsMissionEntity(self.previewVehicle, true, true)
    SetVehicleOnGroundProperly(self.previewVehicle)
    SetVehicleDoorsLocked(self.previewVehicle, 2)
    FreezeEntityPosition(self.previewVehicle, true)
    SetVehicleNumberPlateText(self.previewVehicle, "PREVIEW")
    applyDefaultVehicleProperties(self.previewVehicle, model)
    SetModelAsNoLongerNeeded(modelHash)
    self.isSpawning = false
    local previewVehicle = self.previewVehicle
    Citizen.CreateThread(function()
        local heading = spawn.w
        while self.rotationId == currentRotation
            and previewVehicle
            and DoesEntityExist(previewVehicle)
            and self.inShop
        do
            heading = heading + 0.2
            if heading > 360 then
                heading = 0
            end
            SetEntityHeading(previewVehicle, heading)
            Citizen.Wait(25)
        end
    end)
end

function VehicleShop.open(self, shopName)
    local shopConfig = Config.DepartmentData.vehicleShops[shopName]
    if not shopConfig then
        return
    end
    self.currentShop = shopName
    self.inShop = true
    TriggerServerEvent("p_policejob/vehicleshop/setBucket", true)
    local job = Bridge.Framework.fetchPlayerJob()
    local money = lib.callback.await("p_bridge/server/framework/getMoney", false)
    local items = buildShopItems(job.name, job.grade)
    self:initCamera(shopConfig)
    SendNUIMessage({
        action = "setVehicleShopItems",
        data = items,
    })
    SendNUIMessage({
        action = "setPlayerMoney",
        data = {
            cash = money.cash or 0,
            bank = money.bank or 0,
        },
    })
    SendNUIMessage({
        action = "setVisibleVehicleShop",
        data = true,
    })
    SetNuiFocus(true, true)
end

function VehicleShop.close(self)
    self.inShop = false
    self.currentShop = nil
    self:deletePreviewVehicle()
    self:destroyCamera()
    TriggerServerEvent("p_policejob/vehicleshop/setBucket", false)
    SendNUIMessage({
        action = "setVisibleVehicleShop",
        data = false,
    })
    SetNuiFocus(false, false)
end

function VehicleShop.endTestDrive(self)
    if self.testDriveTimer then
        self.testDriveTimer = nil
    end
    if self.testDriveVehicle and DoesEntityExist(self.testDriveVehicle) then
        local ped = cache.ped
        if GetVehiclePedIsIn(ped, false) == self.testDriveVehicle then
            TaskLeaveVehicle(ped, self.testDriveVehicle, 0)
            Citizen.Wait(1500)
        end
        DeleteVehicle(self.testDriveVehicle)
        self.testDriveVehicle = nil
        if self.testDriveCoords then
            SetEntityCoords(
                ped,
                self.testDriveCoords.x,
                self.testDriveCoords.y,
                self.testDriveCoords.z,
                false, false, false, false
            )
            SetEntityHeading(ped, self.testDriveCoords.w)
            self.testDriveCoords = nil
        end
        if Config.VehicleShop.TestDrive.returnMessage then
            Bridge.Notify.showNotify(Config.VehicleShop.TestDrive.returnMessage, "inform")
        end
    end
end

function VehicleShop.startTestDrive(self, model)
    if not Config.VehicleShop.TestDrive.enabled then
        return Bridge.Notify.showNotify(locale("vehicle_shop_test_drive_disabled"), "error")
    end
    if self.testDriveVehicle then
        self:endTestDrive()
    end
    local shopConfig = Config.DepartmentData.vehicleShops[self.currentShop]
    if not shopConfig then
        return
    end
    local ped = cache.ped
    local pedCoords = GetEntityCoords(ped)
    self.testDriveCoords = vec4(pedCoords.x, pedCoords.y, pedCoords.z, GetEntityHeading(ped))
    self:close()
    local modelHash = lib.requestModel(model)
    if not modelHash then
        return
    end
    local spawn = shopConfig.purchaseSpawn
    local offset = Config.VehicleShop.TestDrive.spawnOffset
    self.testDriveVehicle = CreateVehicle(
        modelHash,
        spawn.x + offset.x,
        spawn.y + offset.y,
        spawn.z + offset.z,
        spawn.w,
        false, false
    )
    SetEntityAsMissionEntity(self.testDriveVehicle, true, true)
    SetVehicleOnGroundProperly(self.testDriveVehicle)
    SetVehicleNumberPlateText(self.testDriveVehicle, "TESTDRV")
    applyDefaultVehicleProperties(self.testDriveVehicle, model)
    SetModelAsNoLongerNeeded(modelHash)
    TaskWarpPedIntoVehicle(cache.ped, self.testDriveVehicle, -1)
    Bridge.Notify.showNotify(
        locale("vehicle_shop_test_drive_started", Config.VehicleShop.TestDrive.duration),
        "success"
    )
    self.testDriveTimer = true
    Citizen.SetTimeout(Config.VehicleShop.TestDrive.duration * 1000, function()
        if self.testDriveTimer then
            self:endTestDrive()
        end
    end)
end

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleVehicleShop" then
        VehicleShop:close()
    end
    cb("ok")
end)

RegisterNUICallback("vehicleShop:preview", function(data, cb)
    if VehicleShop.currentShop and data.model then
        local shopConfig = Config.DepartmentData.vehicleShops[VehicleShop.currentShop]
        if shopConfig then
            VehicleShop:spawnPreviewVehicle(data.model, shopConfig)
        end
    end
    cb("ok")
end)

RegisterNUICallback("vehicleShop:purchase", function(data, cb)
    if not VehicleShop.currentShop or not data.vehicle then
        cb({ success = false })
        return
    end
    TriggerServerEvent("p_policejob/vehicleshop/purchase", {
        shopName = VehicleShop.currentShop,
        vehicleId = data.vehicle.id,
        paymentMethod = data.paymentMethod or "bank",
    })
    cb({ success = true })
end)

RegisterNUICallback("vehicleShop:testDrive", function(data, cb)
    if data.model then
        VehicleShop:startTestDrive(data.model)
    end
    cb("ok")
end)

RegisterNetEvent("p_policejob/vehicleshop/purchaseSuccess", function(data)
    VehicleShop:close()
    local shopConfig = Config.DepartmentData.vehicleShops[data.shopName]
    if not shopConfig then
        return
    end
    local model = lib.requestModel(data.model)
    if not model then
        return
    end
    local spawn = shopConfig.purchaseSpawn
    local vehicle = CreateVehicle(
        model,
        spawn.x, spawn.y, spawn.z, spawn.w,
        true, false
    )
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleNumberPlateText(vehicle, data.plate)
    if data.mods then
        lib.setVehicleProperties(vehicle, data.mods)
    else
        applyDefaultVehicleProperties(vehicle, data.model)
    end
    SetModelAsNoLongerNeeded(model)
    if GetResourceState("ox_doorlock") == "started" or GetResourceState("qb-vehiclekeys") == "started" then
        TriggerEvent("vehiclekeys:client:SetOwner", data.plate)
    end
    TaskWarpPedIntoVehicle(cache.ped, vehicle, -1)
    Bridge.Notify.showNotify(locale("vehicle_shop_purchased", data.price), "success")
end)

RegisterNetEvent("p_policejob/vehicleshop/purchaseFailed", function(message)
    Bridge.Notify.showNotify(message or locale("vehicle_shop_purchase_failed"), "error")
end)

RegisterNetEvent("p_policejob/vehicleshop/updateMoney", function(money)
    SendNUIMessage({
        action = "setPlayerMoney",
        data = money,
    })
end)

Citizen.CreateThread(function()
    Citizen.Wait(1000)
    local shops = Config.DepartmentData.vehicleShops or {}
    for shopName, shopConfig in pairs(shops) do
        if shopConfig.blip and shopConfig.blip.enabled then
            local blip = AddBlipForCoord(
                shopConfig.blip.coords.x,
                shopConfig.blip.coords.y,
                shopConfig.blip.coords.z
            )
            SetBlipSprite(blip, shopConfig.blip.sprite)
            SetBlipColour(blip, shopConfig.blip.color)
            SetBlipScale(blip, shopConfig.blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(shopConfig.blip.label)
            EndTextCommandSetBlipName(blip)
        end
        local point = lib.points.new({
            coords = vector3(
                shopConfig.ped.coords.x,
                shopConfig.ped.coords.y,
                shopConfig.ped.coords.z
            ),
            distance = 50,
        })
        point.onEnter = function(pointData)
            pointData.ped = spawnShopPed(shopConfig.ped)
            if pointData.ped then
                Bridge.Target.addLocalEntity(pointData.ped, {
                    {
                        name = "vehicleshop_" .. shopName,
                        label = locale("open_vehicle_shop"),
                        icon = "fa-solid fa-car",
                        distance = 2.5,
                        groups = Config.Jobs,
                        onSelect = function()
                            VehicleShop:open(shopName)
                        end,
                    },
                })
            end
        end
        point.onExit = function(pointData)
            if pointData.ped then
                Bridge.Target.removeLocalEntity(pointData.ped, { "vehicleshop_" .. shopName })
                DeleteEntity(pointData.ped)
                pointData.ped = nil
            end
        end
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    VehicleShop:deletePreviewVehicle()
    VehicleShop:destroyCamera()
    VehicleShop:endTestDrive()
end)
