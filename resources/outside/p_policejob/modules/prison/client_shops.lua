if not Config or not Config.Prison or not Config.Prison.Enabled then
    return
end

local shopZoneIds = {}
local shopPeds = {}

function spawnShopPed(pedConfig)
    local modelHash = type(pedConfig.model) == "string" and joaat(pedConfig.model) or pedConfig.model
    lib.requestModel(pedConfig.model)

    if not HasModelLoaded(modelHash) then
        return nil
    end

    local coords = pedConfig.coords
    local ped = CreatePed(4, modelHash, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, true)
    SetEntityHeading(ped, coords.w or 0.0)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)

    if pedConfig.anim and pedConfig.anim.dict and pedConfig.anim.clip then
        lib.requestAnimDict(pedConfig.anim.dict)
        TaskPlayAnim(
            ped, pedConfig.anim.dict, pedConfig.anim.clip,
            4.0, -4.0, -1, pedConfig.anim.flag or 1,
            0, false, false, false
        )
    elseif pedConfig.scenario then
        TaskStartScenarioInPlace(ped, pedConfig.scenario, 0, true)
    end

    SetModelAsNoLongerNeeded(modelHash)
    return ped
end

function registerShopTarget(location, targetOption)
    if type(location) == "table" and location.model then
        local ped = spawnShopPed(location)
        if not ped then
            return
        end
        shopPeds[#shopPeds + 1] = ped
        Bridge.Target.addLocalEntity(ped, { targetOption })
        return
    end

    local zoneId = exports.ox_target:addSphereZone({
        coords = vec3(location.x, location.y, location.z),
        radius = 1.2,
        debug = false,
        options = { targetOption },
    })
    shopZoneIds[#shopZoneIds + 1] = zoneId
end

CreateThread(function()
    while not Config.Prison do
        Wait(100)
    end
    while not Prison.Map do
        Wait(100)
    end

    if Config.Prison.Commissary.enabled and Prison.Map.commissary then
        registerShopTarget(Prison.Map.commissary, {
            name = "p_policejob:prison:commissary",
            label = locale("prison_commissary"),
            icon = "fa-solid fa-cart-shopping",
            canInteract = function()
                return Prison.isInPrison == true
            end,
            onSelect = function()
                openShopNui("commissary")
            end,
        })
    end

    if Config.Prison.IllegalShop.enabled and Prison.Map.illegalShop then
        registerShopTarget(Prison.Map.illegalShop, {
            name = "p_policejob:prison:illegalShop",
            label = locale("prison_illegal_shop"),
            icon = "fa-solid fa-mask",
            canInteract = function()
                return Prison.isInPrison == true
            end,
            onSelect = function()
                openShopNui("illegal")
            end,
        })
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    for _, zoneId in ipairs(shopZoneIds) do
        pcall(function()
            exports.ox_target:removeZone(zoneId)
        end)
    end

    for _, ped in ipairs(shopPeds) do
        if DoesEntityExist(ped) then
            Bridge.Target.removeLocalEntity(ped)
            DeleteEntity(ped)
        end
    end
end)
