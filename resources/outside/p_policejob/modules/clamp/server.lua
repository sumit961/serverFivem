while not Config or not Config.Clamp do
    Citizen.Wait(500)
end

if not Config.Clamp.enabled then
    return
end

Clamp = {}

RegisterNetEvent("p_policejob/server/clamp/setWheelClamp", function(data)
    local playerId = source
    if not data or type(data) ~= "table" or not data.netId then
        return
    end
    local vehicle = NetworkGetEntityFromNetworkId(data.netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Config.Jobs[job.name] then
        return Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
    end
    if data.state then
        if Entity(vehicle).state.wheelClamp then
            return
        end
        if Bridge.Inventory.getItemCount(playerId, "wheel_clamp") < 1 then
            return Bridge.Notify.showNotify(playerId, locale("no_wheel_clamp_item"), "error")
        end
        Bridge.Inventory.removeItem(playerId, "wheel_clamp", 1)
        Bridge.Notify.showNotify(playerId, locale("wheel_clamped"), "success")
    else
        if not Entity(vehicle).state.wheelClamp then
            return
        end
        Bridge.Inventory.addItem(playerId, "wheel_clamp", 1)
        Bridge.Notify.showNotify(playerId, locale("wheel_clamp_removed"), "success")
    end
    Entity(vehicle).state:set("wheelClamp", data.state, true)
    local action = data.state and "applied" or "removed"
    Bridge.Debug(("[Clamp] Player %s %s wheel clamp on netId %s"):format(playerId, action, data.netId))
    if Config.Webhooks and Config.Webhooks.clamp then
        local webhookAction = data.state and "Applied" or "Removed"
        Bridge.Logs.Send(
            playerId,
            "Clamp",
            ("%s wheel clamp on vehicle"):format(webhookAction),
            Config.Webhooks.clamp
        )
    end
end)
