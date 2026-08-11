while not Config or not Config.Rappel do
    Citizen.Wait(500)
end

if not Config.Rappel.enabled then
    return
end

lib.callback.register("p_policejob/server/rappel/authorize", function(sourceId)
    if Config.Rappel.requireJob then
        local job = Bridge.Framework.getPlayerJob(sourceId)
        if not job or not Config.Jobs[job.name] then
            Bridge.Notify.showNotify(sourceId, locale("no_access"), "error")
            return false
        end
    end
    if Bridge.Inventory.getItemCount(sourceId, Config.Rappel.item) < 1 then
        Bridge.Notify.showNotify(sourceId, locale("rappel_no_kit"), "error")
        return false
    end
    if Config.Rappel.consumeItem then
        Bridge.Inventory.removeItem(sourceId, Config.Rappel.item, 1)
    end
    return true
end)

Bridge.Framework.registerItem(Config.Rappel.item, function(sourceId)
    TriggerClientEvent("p_policejob/client/rappel/use", sourceId)
end)
