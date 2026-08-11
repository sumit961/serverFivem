while not Config or not Config.Clamp do
    Citizen.Wait(500)
end

if not Config.Clamp.enabled then
    return
end

Clamp = {
    wheelClamps = {},
}

exports("applyWheelClamp", function(vehicle)
    if Clamp:canApplyClamp(vehicle) then
        Clamp:applyClamp(vehicle)
    end
end)

exports("removeWheelClamp", function(vehicle)
    if Clamp:canRemoveClamp(vehicle) then
        Clamp:removeClamp(vehicle)
    end
end)

function Clamp.canApplyClamp(self, vehicle)
    if not DoesEntityExist(vehicle) then
        return false
    end
    local vehicleClass = GetVehicleClass(vehicle)
    local blockedClasses = { 13, 14, 15, 16, 21 }
    if lib.table.contains(blockedClasses, vehicleClass) then
        return false
    end
    if Bridge.Inventory.getItemCount("wheel_clamp") < 1 then
        return false
    end
    return not Entity(vehicle).state.wheelClamp
end

function Clamp.canRemoveClamp(self, vehicle)
    if not DoesEntityExist(vehicle) then
        return false
    end
    return Entity(vehicle).state.wheelClamp
end

function Clamp.applyClamp(self, vehicle)
    if not self:canApplyClamp(vehicle) then
        return
    end
    local completed = lib.progressBar({
        duration = 5000,
        label = locale("clamping_wheel"),
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
        },
        anim = {
            dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@",
            clip = "machinic_loop_mechandplayer",
            flag = 1,
        },
    })
    if not completed then
        Bridge.Notify.showNotify(locale("clamp_cancelled"), "error")
        return
    end
    if not DoesEntityExist(vehicle) then
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then
        return
    end
    TriggerServerEvent("p_policejob/server/clamp/setWheelClamp", {
        netId = netId,
        state = true,
    })
end

function Clamp.removeClamp(self, vehicle)
    if not self:canRemoveClamp(vehicle) then
        return
    end
    local completed = lib.progressBar({
        duration = 5000,
        label = locale("removing_wheel_clamp"),
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
        },
        anim = {
            dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@",
            clip = "machinic_loop_mechandplayer",
            flag = 1,
        },
    })
    if not completed then
        Bridge.Notify.showNotify(locale("clamp_cancelled"), "error")
        return
    end
    if not DoesEntityExist(vehicle) then
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then
        return
    end
    TriggerServerEvent("p_policejob/server/clamp/setWheelClamp", {
        netId = netId,
        state = false,
    })
end

function Clamp.attachProp(self, vehicle)
    if not DoesEntityExist(vehicle) then
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then
        return
    end
    local existingClamp = self.wheelClamps[netId]
    if existingClamp and DoesEntityExist(existingClamp) then
        return
    end
    local model = lib.requestModel(Config.Clamp.Prop.model)
    local coords = GetEntityCoords(vehicle)
    local prop = CreateObject(model, coords.x, coords.y, coords.z - 3.0, false, false, false)
    local boneIndex = GetEntityBoneIndexByName(vehicle, Config.Clamp.Prop.boneIndex)
    AttachEntityToEntity(
        prop, vehicle, boneIndex,
        Config.Clamp.Prop.offset, Config.Clamp.Prop.rotation,
        true, true, false, false, 2, true
    )
    SetEntityAsMissionEntity(prop, true, true)
    FreezeEntityPosition(prop, true, true)
    SetModelAsNoLongerNeeded(model)
    SetVehicleHandbrake(vehicle, true)
    SetVehicleDoorsLockedForAllPlayers(vehicle, true)
    self.wheelClamps[netId] = prop
    Config.Clamp.onWheelClamped(vehicle)
end

function Clamp.removeProp(self, vehicle)
    if not DoesEntityExist(vehicle) then
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then
        return
    end
    local prop = self.wheelClamps[netId]
    if prop and DoesEntityExist(prop) then
        SetVehicleHandbrake(vehicle, false)
        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
        DeleteEntity(prop)
        self.wheelClamps[netId] = nil
        Config.Clamp.onWheelUnclamped(vehicle)
    end
end

AddStateBagChangeHandler("wheelClamp", nil, function(bagName, _, value, _, replicated)
    if replicated then
        return
    end
    local entity = GetEntityFromStateBagName(bagName)
    if not entity or entity == 0 then
        return
    end
    if not DoesEntityExist(entity) then
        return
    end
    if value then
        Clamp:attachProp(entity)
    else
        Clamp:removeProp(entity)
    end
end)

CreateThread(function()
    while true do
        Citizen.Wait(10000)
        for netId, prop in pairs(Clamp.wheelClamps) do
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                -- entity still valid
            else
                if DoesEntityExist(prop) then
                    DeleteEntity(prop)
                end
                Clamp.wheelClamps[netId] = nil
            end
        end
    end
end)

CreateThread(function()
    Bridge.Target.addVehicle({
        {
            name = "p_policejob/clamp/apply",
            label = locale("use_wheel_clamp"),
            icon = "fa-solid fa-lock",
            distance = 2.5,
            onSelect = function(data)
                local vehicle = type(data) == "number" and data or data.entity
                Clamp:applyClamp(vehicle)
            end,
            canInteract = function(vehicle)
                return Clamp:canApplyClamp(vehicle)
            end,
        },
        {
            name = "p_policejob/clamp/remove",
            label = locale("remove_wheel_clamp"),
            icon = "fa-solid fa-unlock",
            distance = 2.5,
            onSelect = function(data)
                local vehicle = type(data) == "number" and data or data.entity
                Clamp:removeClamp(vehicle)
            end,
            canInteract = function(vehicle)
                return Clamp:canRemoveClamp(vehicle)
            end,
        },
    })
end)
