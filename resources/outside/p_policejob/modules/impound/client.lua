while not Config or not Config.Impound do
    Citizen.Wait(500)
end

if not Config.Impound.Enabled then
    return
end

Impound = {
    activePoints = {},
    currentEntity = nil,
    currentImpoundData = {},
}

photoCaptureActive = false

function formatDuration(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

function removeUnownedVehicle(vehicle, netId)
    local unownedConfig = Config.Impound.UnownedVehicles
    local completed = Bridge.Progress.Start({
        duration = unownedConfig.removeTime,
        label = locale("impound_removing_vehicle"),
        useWhileDead = false,
        canCancel = true,
        disable = { move = false, car = true, combat = true },
    })
    if not completed or not DoesEntityExist(vehicle) then
        return
    end
    TriggerServerEvent("p_policejob/server/impound/removeUnownedVehicle", netId)
end

function checkOwnedVehicle(vehicle, plate)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then
        Bridge.Notify.showNotify(locale("impound_vehicle_error"), "error")
        return false
    end
    local isOwned = lib.callback.await("p_policejob/server/impound/checkOwnedVehicle", false, plate, netId)
    if not isOwned then
        local unownedConfig = Config.Impound.UnownedVehicles
        if unownedConfig and unownedConfig.remove then
            removeUnownedVehicle(vehicle, netId)
        else
            Bridge.Notify.showNotify(locale("impound_vehicle_not_owned"), "error")
        end
        return false
    end
    return true
end

function openImpoundMenu(vehicle)
    if not DoesEntityExist(vehicle) then
        Bridge.Notify.showNotify(locale("impound_vehicle_error"), "error")
        return
    end
    local plate = GetVehicleNumberPlateText(vehicle)
    if not checkOwnedVehicle(vehicle, plate) then
        return
    end
    local modelHash = GetEntityModel(vehicle)
    local modelName = GetDisplayNameFromVehicleModel(modelHash)
    local modelLabel = GetLabelText(modelName)
    if modelLabel == "NULL" or modelLabel == "" then
        modelLabel = modelName
    end
    local officerName = Bridge.Framework.getPlayerName() or ""
    Impound.currentEntity = vehicle
    Impound.currentImpoundData = {
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        plate = plate,
        model = modelHash,
        modelLabel = modelLabel,
        officer = officerName,
    }
    local photoConfig = Config.Impound.Photo
    SendNUIMessage({
        action = "setImpoundLocations",
        data = Config.Impound.Locations,
    })
    SendNUIMessage({
        action = "setImpoundVehicleInfo",
        data = {
            plate = plate,
            model = modelLabel,
            officer = officerName,
            photoEnabled = photoConfig and photoConfig.enabled or false,
            photoRequired = photoConfig and photoConfig.required or false,
            offences = Config.Impound.Offences or {},
        },
    })
    SendNUIMessage({
        action = "setVisibleImpound",
        data = true,
    })
    SetNuiFocus(true, true)
end

exports("openImpoundMenu", openImpoundMenu)

function createImpoundPoint(locationId, locationData)
    local point = lib.points.new({
        coords = locationData.coords,
        distance = 30,
    })
    function point.onEnter(self)
        local model = lib.requestModel(locationData.ped.model)
        if not model then
            return
        end
        self.ped = CreatePed(
            4,
            model,
            locationData.coords.x,
            locationData.coords.y,
            locationData.coords.z - 1.0,
            locationData.coords.w,
            false,
            true
        )
        FreezeEntityPosition(self.ped, true)
        SetEntityInvincible(self.ped, true)
        SetBlockingOfNonTemporaryEvents(self.ped, true)
        if locationData.anim then
            if locationData.anim.dict then
                local animDict = lib.requestAnimDict(locationData.anim.dict)
                if animDict then
                    TaskPlayAnim(
                        self.ped,
                        animDict,
                        locationData.anim.name,
                        8.0, 8.0, -1,
                        locationData.anim.flag or 1,
                        0, false, false, false
                    )
                    RemoveAnimDict(animDict)
                end
            elseif locationData.anim.scenario then
                TaskStartScenarioInPlace(self.ped, locationData.anim.scenario, 0, true)
            end
        end
        SetModelAsNoLongerNeeded(model)
        if locationData.ped.onCreate then
            locationData.ped.onCreate(self.ped)
        end
        Bridge.Target.addLocalEntity(self.ped, {
            {
                name = "p_policejob/impound/checkImpound_" .. locationId,
                label = locale("check_impound"),
                icon = "fa-solid fa-file",
                distance = 2.5,
                onSelect = function()
                    Impound:openImpoundLot(locationId)
                end,
            },
        })
    end
    function point.onExit(self)
        if self.ped and DoesEntityExist(self.ped) then
            DeleteEntity(self.ped)
            self.ped = nil
        end
    end
    return point
end

function getFormattedImpoundList(locationId)
    local vehicles = lib.callback.await("p_policejob/server/impound/getImpoundedVehicles", false, locationId) or {}
    local formatted = {}
    for _, vehicle in pairs(vehicles) do
        local props = json.decode(vehicle.vehicle)
        local modelName = GetDisplayNameFromVehicleModel(props.model)
        local label = GetLabelText(modelName)
        formatted[#formatted + 1] = {
            id = vehicle.plate,
            plate = vehicle.plate,
            name = (label == "NULL" or not label) and modelName or label,
            price = vehicle.price,
            reason = vehicle.reason,
            notes = vehicle.notes,
            photo = vehicle.photo,
            officer = vehicle.officer_name,
            timeLeft = vehicle.timeLeft,
            location = locationId,
        }
    end
    return formatted
end

function Impound.openImpoundLot(self, locationId)
    local vehicles = getFormattedImpoundList(locationId)
    if #vehicles == 0 then
        Bridge.Notify.showNotify(locale("impound_no_vehicles"), "error")
        return
    end
    SendNUIMessage({
        action = "setImpoundedVehicles",
        data = vehicles,
    })
    SendNUIMessage({
        action = "setVisibleImpoundLot",
        data = true,
    })
    SetNuiFocus(true, true)
end

function Impound.payoutVehicle(self, plate, locationId)
    local success = lib.callback.await("p_policejob/server/impound/payoutVehicle", false, {
        plate = plate,
        location = locationId,
    })
    if success then
        SendNUIMessage({
            action = "setImpoundedVehicles",
            data = getFormattedImpoundList(locationId),
        })
    end
    return success
end

RegisterNUICallback("impound/close", function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisibleImpound", data = false })
    SendNUIMessage({ action = "setVisibleImpoundLot", data = false })
    cb("ok")
end)

RegisterNUICallback("impound/submitForm", function(data, cb)
    if not Impound.currentEntity or not DoesEntityExist(Impound.currentEntity) then
        return cb(false)
    end
    TriggerServerEvent("p_policejob/server/impound/startImpound", {
        netId = Impound.currentImpoundData.netId,
        price = data.price or 0,
        reason = data.reason,
        notes = data.notes,
        photo = data.photo,
        releaseAt = data.releaseAt,
        time = data.time or 1,
        location = data.location,
        model = data.model or Impound.currentImpoundData.modelLabel,
    })
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisibleImpound", data = false })
    Impound.currentEntity = nil
    Impound.currentImpoundData = {}
    cb(true)
end)

RegisterNUICallback("impound/capturePhoto", function(_, cb)
    cb("ok")
    if photoCaptureActive then
        return
    end
    local photoConfig = Config.Impound.Photo
    if not photoConfig or not photoConfig.enabled then
        SendNUIMessage({ action = "setImpoundPhoto", data = false })
        return
    end
    photoCaptureActive = true
    SetNuiFocus(false, false)
    CreateThread(function()
        lib.showTextUI(locale("impound_photo_hint"), { position = "bottom-center" })
        local previousCamMode = GetFollowPedCamViewMode()
        SetFollowPedCamViewMode(4)
        local photoUrl = nil
        local finished = false
        while not finished do
            Wait(0)
            if IsControlJustPressed(0, 38) then
                lib.hideTextUI()
                Bridge.Notify.showNotify(locale("impound_photo_capturing"), "inform")
                photoUrl = PolicePhotoCapture()
                finished = true
            elseif IsControlJustPressed(0, 177) then
                finished = true
            end
        end
        SetFollowPedCamViewMode(previousCamMode)
        lib.hideTextUI()
        SetNuiFocus(true, true)
        if photoUrl then
            Bridge.Notify.showNotify(locale("impound_photo_saved"), "success")
        end
        SendNUIMessage({
            action = "setImpoundPhoto",
            data = photoUrl or false,
        })
        photoCaptureActive = false
    end)
end)

RegisterNUICallback("impound/payoutVehicle", function(data, cb)
    cb(Impound:payoutVehicle(data.plate, data.location) or false)
end)

CreateThread(function()
    Bridge.Target.addVehicle({
        {
            name = "p_policejob/impound/startImpound",
            label = locale("impound_vehicle"),
            icon = "fa-solid fa-car",
            distance = 2.0,
            groups = Config.Jobs,
            onSelect = function(target)
                if Config.Impound.UseGarageExport then
                    if GetResourceState("qs-advancedgarages") == "started" then
                        exports["qs-advancedgarages"]:ImpoundVehicle()
                        return
                    elseif GetResourceState("jg-advancedgarages") == "started" then
                        TriggerEvent("jg-advancedgarages:client:show-impound-form")
                        return
                    elseif GetResourceState("cd_garage") == "started" then
                        ExecuteCommand("impound")
                        return
                    elseif GetResourceState("okokGarage") == "started" then
                        TriggerEvent("okokGarage:openPoliceImpound")
                        return
                    elseif GetResourceState("mt_garages") == "started" then
                        exports.mt_garages:openImpound()
                        return
                    end
                end
                local vehicle = type(target) == "number" and target or target.entity
                openImpoundMenu(vehicle)
            end,
        },
    })
    for locationId, locationData in pairs(Config.Impound.Locations) do
        Impound.activePoints[locationId] = createImpoundPoint(locationId, locationData)
    end
end)
