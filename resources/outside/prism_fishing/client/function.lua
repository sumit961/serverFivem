function createBlip(data)
    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, data.sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, data.scale)
    SetBlipColour(blip, data.color)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(data.blipText)
    EndTextCommandSetBlipName(blip)
    return blip
end

function createPed(data)
    lib.requestModel(data.model)
    local ped = CreatePed(4, data.model, data.coords.x, data.coords.y, data.coords.z - 1, data.coords.w, false, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    if data.animDict and data.animName then
        lib.requestAnimDict(data.animDict)
        TaskPlayAnim(ped, data.animDict, data.animName, 3.0, 3.0, -1, 1, 0, false, false, false)
    end
    return ped
end

function addTarget(data)
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addLocalEntity(data.entity, data.options)
    end
end

function setFuel(vehicle, fuelLevel)
    if GetResourceState('ox_fuel') == 'started' then
        Entity(vehicle).state.fuel = fuelLevel
    elseif GetResourceState('legacyfuel') == 'started' then
        exports['legacyfuel']:SetFuel(vehicle, fuelLevel)
    end
end

function createVehicle(data)
    lib.requestModel(data.model)
    local vehicle = CreateVehicle(data.model, data.spawnCoords.x, data.spawnCoords.y, data.spawnCoords.z,
        data.spawnCoords.w, false,
        false)
    SetVehicleNumberPlateText(vehicle, "Rental" .. math.random(1000, 9999))
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetVehicleDirtLevel(vehicle, 0)
    SetVehRadioStation(vehicle, "OFF")
    giveKeys(GetVehicleNumberPlateText(vehicle))
    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    setFuel(vehicle, 100.0)
    return vehicle
end

function giveKeys(plate)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
end

function Notify(msg, type)
    lib.notify({
        description = msg,
        type = type or 'info',
    })
end

RegisterNetEvent('prism_fishing:client:Notification', Notify)
