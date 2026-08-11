if not Config.Objects.enabled then
    return
end

Objects = {
    placed = {},
    shield = nil,
}

function ensureNetworkId(entity)
    if not DoesEntityExist(entity) then
        return 0
    end
    if not NetworkGetEntityIsNetworked(entity) then
        NetworkRegisterEntityAsNetworked(entity)
        local attempts = 0
        while not NetworkGetEntityIsNetworked(entity) and attempts < 50 do
            Wait(10)
            attempts = attempts + 1
        end
    end
    return NetworkGetNetworkIdFromEntity(entity)
end

function hasPoliceJob()
    local job = Bridge.Framework.fetchPlayerJob()
    return job and Config.Jobs[job.name] or nil
end

function canInteractWithObject(entity)
    if not DoesEntityExist(entity) then
        return false
    end
    local state = Entity(entity).state
    if not state or not state.PoliceObject then
        return false
    end
    if Config.Objects.allowSteal then
        return true
    end
    return hasPoliceJob()
end

function Objects.open(self)
    if not hasPoliceJob() then
        return
    end
    if cache.vehicle then
        Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
        return
    end
    local categories = {}
    for _, category in ipairs(Config.Objects.Categories) do
        local objects = {}
        for _, objectEntry in ipairs(category.objects) do
            objects[#objects + 1] = {
                model = objectEntry.model,
                label = objectEntry.label,
                icon = objectEntry.icon,
            }
        end
        categories[#categories + 1] = {
            name = category.name,
            label = category.label,
            icon = category.icon,
            objects = objects,
        }
    end
    SendNUIMessage({ action = "setVisibleObjects", data = true })
    SendNUIMessage({
        action = "setObjectsData",
        data = {
            categories = categories,
            placed = self:getPlacedCount(),
            maxObjects = Config.Objects.maxObjectsPerPlayer,
        },
    })
    SetNuiFocus(true, true)
end

function Objects.close(self)
    SendNUIMessage({ action = "setVisibleObjects", data = false })
    SetNuiFocus(false, false)
end

function Objects.updatePlacedCount(self)
    SendNUIMessage({
        action = "setObjectsPlaced",
        data = self:getPlacedCount(),
    })
end

function Objects.getPlacedCount(self)
    local count = 0
    for _ in pairs(self.placed) do
        count = count + 1
    end
    return count
end

RegisterNUICallback("objects/place", function(data, cb)
    cb("ok")
    Objects:close()
    local model = data.model
    local amount = data.amount or 1
    if type(model) ~= "string" then
        return
    end
    amount = math.max(1, math.min(amount, 20))
    local maxObjects = Config.Objects.maxObjectsPerPlayer
    if maxObjects > 0 then
        local placedCount = Objects:getPlacedCount()
        if placedCount + amount > maxObjects then
            amount = maxObjects - placedCount
            if amount <= 0 then
                return Bridge.Notify.showNotify(locale("obj_max_reached"), "error")
            end
        end
    end
    Objects:placeObjects(model, amount)
end)

RegisterNUICallback("objects/removeAll", function(data, cb)
    cb("ok")
    Objects:close()
    if type(data.model) ~= "string" then
        return
    end
    Objects:removeAllByModel(data.model)
end)

RegisterNUICallback("hideFrame", function(_, cb)
    cb("ok")
    Objects:close()
end)

function Objects.placeObjects(self, model, amount)
    if cache.vehicle then
        Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
        return
    end
    lib.requestModel(model)
    for _ = 1, amount do
        local playerCoords = GetEntityCoords(cache.ped)
        local forwardOffset = GetEntityForwardVector(cache.ped) * 2.5
        local spawnCoords = playerCoords + forwardOffset
        local object = CreateObject(
            GetHashKey(model),
            spawnCoords.x,
            spawnCoords.y,
            spawnCoords.z,
            true,
            false,
            true
        )
        if DoesEntityExist(object) then
            PlaceObjectOnGroundProperly(object)
            FreezeEntityPosition(object, true)
            local useGizmo = Config.Objects.useGizmo
                and GetResourceState("object_gizmo") == "started"
            if useGizmo then
                FreezeEntityPosition(object, false)
                local gizmoResult = exports.object_gizmo:useGizmo(object)
                if not gizmoResult or not DoesEntityExist(object) then
                    if DoesEntityExist(object) then
                        DeleteEntity(object)
                    end
                    goto continue_placement
                end
                if Config.Objects.snapToGround then
                    PlaceObjectOnGroundProperly(object)
                end
                FreezeEntityPosition(object, true)
            end
            local netId = ensureNetworkId(object)
            if netId == 0 then
                DeleteEntity(object)
            else
                SetNetworkIdCanMigrate(netId, true)
                SetNetworkIdExistsOnAllMachines(netId, true)
                self.placed[netId] = { model = model, entity = object }
                TriggerServerEvent("p_policejob/server/objects/register", netId)
                Config.Objects.onPlace(model, GetEntityCoords(object))
                self:updatePlacedCount()
            end
        end
        ::continue_placement::
    end
    SetModelAsNoLongerNeeded(model)
end

function Objects.removeObject(self, netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then
        return
    end
    local animDict = lib.requestAnimDict("random@domestic")
    TaskPlayAnim(cache.ped, animDict, "pickup_low", -8.0, 8.0, 1000, 1, false)
    Wait(700)
    RemoveAnimDict(animDict)
    TriggerServerEvent("p_policejob/server/objects/remove", netId)
end

function Objects.removeAllByModel(self, model)
    local animDict = lib.requestAnimDict("random@domestic")
    TaskPlayAnim(cache.ped, animDict, "pickup_low", -8.0, 8.0, 1000, 1, false)
    Wait(700)
    RemoveAnimDict(animDict)
    TriggerServerEvent("p_policejob/server/objects/removeAllByModel", GetHashKey(model))
end

RegisterNetEvent("p_policejob/client/objects/deployFromItem", function(model)
    if type(model) ~= "string" then
        return
    end
    Objects:placeObjects(model, 1)
end)

RegisterNetEvent("p_policejob/client/objects/deleted", function(netId)
    local entry = Objects.placed[netId]
    if entry then
        Config.Objects.onRemove(entry.model)
        Objects.placed[netId] = nil
        Objects:updatePlacedCount()
    end
end)

RegisterNetEvent("p_policejob/client/objects/deletedBulk", function(netIds)
    for _, netId in ipairs(netIds) do
        if Objects.placed[netId] then
            Objects.placed[netId] = nil
        end
    end
    Objects:updatePlacedCount()
end)

function deploySpikeStrip()
    local spikeConfig = Config.Objects.SpikeStrip
    if not spikeConfig.enabled then
        return
    end
    if not hasPoliceJob() then
        Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
        return
    end
    if cache.vehicle then
        Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
        return
    end
    local spawnCoords = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 2.5, 0.0)
    local heading = GetEntityHeading(cache.ped)
    lib.requestModel(spikeConfig.model)
    local spike = CreateObject(
        GetHashKey(spikeConfig.model),
        spawnCoords.x,
        spawnCoords.y,
        spawnCoords.z,
        true,
        true,
        true
    )
    SetEntityHeading(spike, heading)
    PlaceObjectOnGroundProperly(spike)
    local netId = ensureNetworkId(spike)
    if netId == 0 then
        DeleteEntity(spike)
        return
    end
    local deployAnim = spikeConfig.deployAnim
    local animDict = lib.requestAnimDict(deployAnim.dict)
    TaskPlayAnim(
        cache.ped,
        animDict,
        deployAnim.anim,
        -8.0, 8.0,
        deployAnim.duration,
        1, 0
    )
    RemoveAnimDict(animDict)
    TriggerServerEvent("p_policejob/server/objects/deploySpikeStrip", netId)
    SetModelAsNoLongerNeeded(spikeConfig.model)
end

RegisterNetEvent("p_policejob/useSpikeStrip", deploySpikeStrip)
lib.callback.register("p_policejob/useSpikeStrip", deploySpikeStrip)

RegisterNetEvent("p_policejob/client/objects/playSpikeAnim", function(netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or not DoesEntityExist(entity) then
        return
    end
    local animDict = lib.requestAnimDict("p_ld_stinger_s")
    PlayEntityAnim(entity, "p_stinger_s_deploy", animDict, 1000.0, false, true, false, 0.0, 0)
    RemoveAnimDict(animDict)
end)

local wheelBones = {
    wheel_lf = 0,
    wheel_rf = 1,
    wheel_lr = 4,
    wheel_rr = 5,
}
local spikeStripHash = GetHashKey("p_ld_stinger_s")
local spikeMonitorActive = false

function isWheelNearSpike(wheelCoords, spikeEntity)
    return #(wheelCoords - GetEntityCoords(spikeEntity)) < 1.5
end

lib.onCache("vehicle", function(vehicle)
    if vehicle and vehicle ~= 0 then
        if not spikeMonitorActive then
            spikeMonitorActive = true
            CreateThread(function()
                while spikeMonitorActive do
                    local waitTime = 500
                    local playerCoords = GetEntityCoords(cache.ped)
                    local spike = GetClosestObjectOfType(
                        playerCoords.x,
                        playerCoords.y,
                        playerCoords.z,
                        35.0,
                        spikeStripHash,
                        false,
                        false,
                        false
                    )
                    if DoesEntityExist(spike) then
                        local distance = #(playerCoords - GetEntityCoords(spike))
                        if distance <= 20.0 then
                            waitTime = 5
                            if IsEntityTouchingEntity(cache.vehicle, spike) then
                                for boneName, wheelIndex in pairs(wheelBones) do
                                    if not IsVehicleTyreBurst(cache.vehicle, wheelIndex, false) then
                                        local wheelCoords = GetWorldPositionOfEntityBone(
                                            cache.vehicle,
                                            GetEntityBoneIndexByName(cache.vehicle, boneName)
                                        )
                                        if isWheelNearSpike(wheelCoords, spike) then
                                            SetVehicleTyreBurst(cache.vehicle, wheelIndex, true, 1148846080)
                                        end
                                    end
                                end
                            end
                        else
                            waitTime = 250
                        end
                    end
                    Wait(waitTime)
                end
            end)
        end
    else
        spikeMonitorActive = false
    end
end)

function Objects.toggleShield(self, modelName)
    local shieldConfig = Config.Objects.Shield
    if not shieldConfig.enabled then
        return
    end
    if not hasPoliceJob() then
        Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
        return
    end
    if self.shield then
        DeleteEntity(self.shield)
        self.shield = nil
        return
    end
    if cache.vehicle then
        Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
        return
    end
    modelName = modelName or shieldConfig.defaultModel
    lib.requestModel(modelName)
    self.shield = CreateObject(
        GetHashKey(modelName),
        GetEntityCoords(cache.ped),
        true,
        true,
        true
    )
    AttachEntityToEntity(
        self.shield,
        cache.ped,
        GetPedBoneIndex(cache.ped, shieldConfig.boneIndex),
        shieldConfig.offset.x,
        shieldConfig.offset.y,
        shieldConfig.offset.z,
        shieldConfig.rotation.x,
        shieldConfig.rotation.y,
        shieldConfig.rotation.z,
        true, true, true, true, false, true
    )
    CreateThread(function()
        while self.shield and DoesEntityExist(self.shield) do
            SetPlayerMayNotEnterAnyVehicle(cache.playerId)
            Wait(0)
        end
    end)
    CreateThread(function()
        while self.shield and DoesEntityExist(self.shield) do
            if LocalPlayer.state.isDead then
                DeleteEntity(self.shield)
                self.shield = nil
                break
            end
            Wait(1000)
        end
    end)
    SetModelAsNoLongerNeeded(modelName)
end

RegisterNetEvent("p_policejob/client/objects/togglePoliceShield", function(modelName)
    if type(modelName) ~= "string" or modelName == "" then
        modelName = nil
    end
    Objects:toggleShield(modelName)
end)

CreateThread(function()
    Wait(1500)
    local targetModels = { "p_ld_stinger_s" }
    local seenModels = {}
    for _, category in ipairs(Config.Objects.Categories) do
        for _, objectEntry in ipairs(category.objects) do
            if not seenModels[objectEntry.model] then
                seenModels[objectEntry.model] = true
                targetModels[#targetModels + 1] = objectEntry.model
            end
        end
    end
    Bridge.Target.addModel(targetModels, {
        {
            name = "p_policejob/objects/take",
            label = locale("take_object"),
            icon = "fas fa-hand",
            distance = Config.Objects.interactDistance,
            onSelect = function(target)
                local entity = type(target) == "number" and target or target.entity
                local netId = ensureNetworkId(entity)
                if not netId or netId == 0 then
                    return
                end
                Objects:removeObject(netId)
            end,
            canInteract = canInteractWithObject,
        },
        {
            name = "p_policejob/objects/takeAll",
            label = locale("take_all_objects"),
            icon = "fas fa-trash",
            distance = Config.Objects.interactDistance,
            onSelect = function(target)
                local entity = type(target) == "number" and target or target.entity
                local animDict = lib.requestAnimDict("random@domestic")
                TaskPlayAnim(cache.ped, animDict, "pickup_low", -8.0, 8.0, 1000, 1, false)
                Wait(700)
                RemoveAnimDict(animDict)
                TriggerServerEvent(
                    "p_policejob/server/objects/removeAllByModel",
                    GetEntityModel(entity)
                )
            end,
            canInteract = canInteractWithObject,
        },
    })
end)

function isTrunkOpen(vehicle)
    return GetVehicleDoorAngleRatio(vehicle, 5) > 0.1
end

function playTrunkAnim()
    local animConfig = Config.Objects.Trunk.anim
    local animDict = lib.requestAnimDict(animConfig.dict)
    TaskPlayAnim(
        cache.ped,
        animDict,
        animConfig.anim,
        -8.0, 8.0,
        animConfig.duration,
        1, false
    )
    Wait(animConfig.duration or 700)
    RemoveAnimDict(animDict)
end

function openTrunkTakeMenu(vehicle, items)
    local trunkConfig = Config.Objects.Trunk
    local netId = ensureNetworkId(vehicle)
    if not netId or netId == 0 then
        return
    end
    local options = {}
    for _, itemEntry in ipairs(items) do
        local itemName = itemEntry.item
        local disabled = Bridge.Inventory.getItemCount(itemName) >= trunkConfig.maxHold
        options[#options + 1] = {
            title = itemEntry.label,
            icon = itemEntry.icon or "fa-solid fa-hand",
            disabled = disabled,
            onSelect = function()
                TriggerServerEvent("p_policejob/server/objects/trunk/take", netId, itemName)
            end,
        }
    end
    if #options == 0 then
        return
    end
    lib.registerContext({
        id = "p_policejob_trunk_take",
        title = locale("take_from_trunk"),
        options = options,
    })
    lib.showContext("p_policejob_trunk_take")
end

CreateThread(function()
    local trunkConfig = Config.Objects.Trunk
    if not trunkConfig or not trunkConfig.enabled then
        return
    end
    Wait(1500)
    for modelName, items in pairs(trunkConfig.vehicles) do
        local targetOptions = {
            {
                name = "p_policejob/objects/trunk/take/" .. modelName,
                label = locale("take_from_trunk"),
                icon = "fa-solid fa-box-open",
                distance = trunkConfig.interactDistance,
                onSelect = function(target)
                    local entity = type(target) == "number" and target or target.entity
                    openTrunkTakeMenu(entity, items)
                end,
                canInteract = function(vehicle)
                    if not hasPoliceJob() then
                        return false
                    end
                    if trunkConfig.requireOpenTrunk and not isTrunkOpen(vehicle) then
                        return false
                    end
                    return true
                end,
            },
        }
        for _, itemEntry in ipairs(items) do
            local itemName = itemEntry.item
            targetOptions[#targetOptions + 1] = {
                name = "p_policejob/objects/trunk/store/" .. modelName .. "/" .. itemName,
                label = locale("store_object_trunk", itemEntry.label),
                icon = itemEntry.icon or "fa-solid fa-hand",
                distance = trunkConfig.interactDistance,
                onSelect = function(target)
                    local entity = type(target) == "number" and target or target.entity
                    local netId = ensureNetworkId(entity)
                    if not netId or netId == 0 then
                        return
                    end
                    playTrunkAnim()
                    TriggerServerEvent("p_policejob/server/objects/trunk/store", netId, itemName)
                end,
                canInteract = function(vehicle)
                    if not hasPoliceJob() then
                        return false
                    end
                    if trunkConfig.requireOpenTrunk and not isTrunkOpen(vehicle) then
                        return false
                    end
                    return Bridge.Inventory.getItemCount(itemName) >= 1
                end,
            }
        end
        Bridge.Target.addModel(modelName, targetOptions)
    end
end)

exports("ObjectMenu", function()
    Objects:open()
end)

exports("isObjectsOpen", function()
    return false
end)

RegisterNetEvent("p_policejob/client/objects/open", function()
    Objects:open()
end)

RegisterCommand("openObjectMenu", function()
    Objects:open()
end, false)
