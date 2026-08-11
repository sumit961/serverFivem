if not Config.Objects.enabled then
    return
end

Objects = {
    registry = {},
}

function getPoliceJobGrade(playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    return job and Config.Jobs[job.name] or nil
end

function getEntityFromNetId(netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        return entity
    end
    return nil
end

function isPlayerNearEntity(playerId, entity, maxDistance)
    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then
        return false
    end
    return maxDistance >= #(GetEntityCoords(ped) - GetEntityCoords(entity))
end

RegisterNetEvent("p_policejob/server/objects/register", function(netId)
    local playerId = source
    if not getPoliceJobGrade(playerId) then
        return
    end
    local entity = getEntityFromNetId(netId)
    if not entity then
        return
    end
    FreezeEntityPosition(entity, true)
    Entity(entity).state:set("PoliceObject", true, true)
    Objects.registry[netId] = {
        owner = playerId,
        model = GetEntityModel(entity),
    }
    Bridge.Debug(("[Objects] Player %s registered object netId=%s model=%s"):format(
        playerId,
        netId,
        GetEntityModel(entity)
    ))
    Bridge.Logs.Send(
        playerId,
        "Objects",
        locale("player_placed_object", GetEntityModel(entity)),
        Config.Webhooks.objects
    )
end)

RegisterNetEvent("p_policejob/server/objects/remove", function(netId)
    local playerId = source
    if not Config.Objects.allowSteal and not getPoliceJobGrade(playerId) then
        return
    end
    local entity = getEntityFromNetId(netId)
    if not entity then
        return
    end
    if not isPlayerNearEntity(playerId, entity, Config.Objects.interactDistance + 2.0) then
        return
    end
    if not Entity(entity).state or not Entity(entity).state.PoliceObject then
        return
    end
    DeleteEntity(entity)
    Objects.registry[netId] = nil
    TriggerClientEvent("p_policejob/client/objects/deleted", playerId, netId)
    Bridge.Debug(("[Objects] Player %s removed object netId=%s"):format(playerId, netId))
    Bridge.Logs.Send(
        playerId,
        "Objects",
        locale("player_took_object", netId),
        Config.Webhooks.objects
    )
end)

RegisterNetEvent("p_policejob/server/objects/removeAllByModel", function(modelHash)
    local playerId = source
    if not Config.Objects.allowSteal and not getPoliceJobGrade(playerId) then
        return
    end
    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then
        return
    end
    local playerCoords = GetEntityCoords(ped)
    local removedNetIds = {}
    for netId, entry in pairs(Objects.registry) do
        if entry.model == modelHash then
            local entity = getEntityFromNetId(netId)
            if entity and #(playerCoords - GetEntityCoords(entity)) <= 30.0 then
                DeleteEntity(entity)
                removedNetIds[#removedNetIds + 1] = netId
                Objects.registry[netId] = nil
            end
        end
    end
    if #removedNetIds > 0 then
        TriggerClientEvent("p_policejob/client/objects/deletedBulk", playerId, removedNetIds)
        Bridge.Logs.Send(
            playerId,
            "Objects",
            locale("player_took_objects", modelHash),
            Config.Webhooks.objects
        )
    end
end)

RegisterNetEvent("p_policejob/server/objects/deploySpikeStrip", function(netId)
    local playerId = source
    local spikeConfig = Config.Objects.SpikeStrip
    if not spikeConfig or not spikeConfig.enabled then
        return
    end
    if not getPoliceJobGrade(playerId) then
        return
    end
    local entity = getEntityFromNetId(netId)
    if not entity then
        return
    end
    Entity(entity).state:set("PoliceObject", true, true)
    Objects.registry[netId] = {
        owner = playerId,
        model = GetEntityModel(entity),
    }
    TriggerClientEvent("p_policejob/client/objects/playSpikeAnim", -1, netId)
    Bridge.Logs.Send(playerId, "Objects", "Deployed spike strip", Config.Webhooks.objects)
end)

function getTrunkItemConfig(modelHash, itemName)
    local trunkConfig = Config.Objects.Trunk
    if not trunkConfig or not trunkConfig.enabled then
        return nil
    end
    for modelName, items in pairs(trunkConfig.vehicles) do
        if GetHashKey(modelName) == modelHash then
            for _, itemEntry in ipairs(items) do
                if itemEntry.item == itemName then
                    return itemEntry
                end
            end
        end
    end
    return nil
end

RegisterNetEvent("p_policejob/server/objects/trunk/take", function(netId, itemName)
    local playerId = source
    local trunkConfig = Config.Objects.Trunk
    if not trunkConfig or not trunkConfig.enabled or type(itemName) ~= "string" then
        return
    end
    if not getPoliceJobGrade(playerId) then
        return
    end
    local entity = getEntityFromNetId(netId)
    if not entity then
        return
    end
    if not isPlayerNearEntity(playerId, entity, trunkConfig.interactDistance + 2.0) then
        return
    end
    local itemConfig = getTrunkItemConfig(GetEntityModel(entity), itemName)
    if not itemConfig then
        return
    end
    if Bridge.Inventory.getItemCount(playerId, itemName) >= trunkConfig.maxHold then
        return Bridge.Notify.showNotify(playerId, locale("trunk_already_have"), "error")
    end
    Bridge.Inventory.addItem(playerId, itemName, 1)
    Bridge.Notify.showNotify(playerId, locale("trunk_took_item", itemConfig.label), "success")
    Bridge.Logs.Send(
        playerId,
        "Objects",
        locale("trunk_log_took", itemName),
        Config.Webhooks.objects
    )
end)

RegisterNetEvent("p_policejob/server/objects/trunk/store", function(netId, itemName)
    local playerId = source
    local trunkConfig = Config.Objects.Trunk
    if not trunkConfig or not trunkConfig.enabled or type(itemName) ~= "string" then
        return
    end
    if not getPoliceJobGrade(playerId) then
        return
    end
    local entity = getEntityFromNetId(netId)
    if not entity then
        return
    end
    if not isPlayerNearEntity(playerId, entity, trunkConfig.interactDistance + 2.0) then
        return
    end
    local itemConfig = getTrunkItemConfig(GetEntityModel(entity), itemName)
    if not itemConfig then
        return
    end
    if Bridge.Inventory.getItemCount(playerId, itemName) < 1 then
        return
    end
    Bridge.Inventory.removeItem(playerId, itemName, 1)
    Bridge.Notify.showNotify(playerId, locale("trunk_stored_item", itemConfig.label), "success")
    Bridge.Logs.Send(
        playerId,
        "Objects",
        locale("trunk_log_stored", itemName),
        Config.Webhooks.objects
    )
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    for netId in pairs(Objects.registry) do
        local entity = getEntityFromNetId(netId)
        if entity then
            DeleteEntity(entity)
        end
    end
    Objects.registry = {}
end)

CreateThread(function()
    while not Bridge or not Bridge.Framework do
        Citizen.Wait(500)
    end
    local itemConfig = Config.Objects and Config.Objects.Items
    if not itemConfig then
        return
    end
    for itemName, itemData in pairs(itemConfig) do
        local model = itemData.model
        if model then
            Bridge.Framework.registerItem(itemName, function(playerId)
                if not getPoliceJobGrade(playerId) then
                    return
                end
                Bridge.Inventory.removeItem(playerId, itemName, 1)
                TriggerClientEvent("p_policejob/client/objects/deployFromItem", playerId, model)
            end)
        end
    end
end)
