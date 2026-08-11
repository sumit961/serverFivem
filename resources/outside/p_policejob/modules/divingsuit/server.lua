while not Config or not Config.DivingSuit do
    Citizen.Wait(500)
end

if not Config.DivingSuit.enabled then
    return
end

lib.callback.register("p_policejob/server/divingsuit/canUseSuit", function(source)
    local job = Bridge.Framework.getPlayerJob(source)
    if not job or not Config.Jobs[job.name] then
        return false
    end
    if Bridge.Inventory.getItemCount(source, "diving_suit") < 1 then
        return false
    end
    return true
end)

RegisterNetEvent("p_policejob/server/divingsuit/activate", function()
    local playerId = source
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job or not Config.Jobs[job.name] then
        Bridge.Debug(("[DivingSuit] Activation denied for player %s (job not allowed)"):format(playerId))
        return Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
    end
    if Bridge.Inventory.getItemCount(playerId, "diving_suit") < 1 then
        return Bridge.Notify.showNotify(playerId, locale("no_diving_suit_item"), "error")
    end
    Bridge.Debug(("[DivingSuit] Player %s activated diving suit"):format(playerId))
    if Config.Webhooks and Config.Webhooks.divingsuit then
        local playerName = Bridge.Framework.getPlayerName(playerId)
        Bridge.Logs.Send(
            playerId,
            "DivingSuit",
            ("Player activated diving suit"):format(playerName),
            Config.Webhooks.divingsuit
        )
    end
end)

RegisterNetEvent("p_policejob/server/divingsuit/deactivate", function()
    local playerId = source
    if Config.Webhooks and Config.Webhooks.divingsuit then
        local playerName = Bridge.Framework.getPlayerName(playerId)
        Bridge.Logs.Send(
            playerId,
            "DivingSuit",
            ("Player removed diving suit"):format(playerName),
            Config.Webhooks.divingsuit
        )
    end
end)
