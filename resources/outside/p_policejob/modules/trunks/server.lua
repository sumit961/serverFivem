if not Config.Trunks.enabled then
    return
end

Trunks = {
    occupiedTrunks = {},
}

GlobalState["p_policejob:occupiedTrunks"] = Trunks.occupiedTrunks

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    Wait(100)
    local fileContents = LoadResourceFile(resourceName, "trunks.json")
    if fileContents then
        local offsets = json.decode(fileContents)
        if offsets then
            Bridge.Debug(("[Trunks] Loaded %d saved offsets"):format(#offsets))
        end
    end
end)

RegisterNetEvent("p_policejob/server/trunks/setOccupied", function(netId, occupied)
    local playerId = source
    Trunks.occupiedTrunks[netId] = (occupied and playerId) or nil
    GlobalState["p_policejob:occupiedTrunks"] = Trunks.occupiedTrunks
end)

RegisterNetEvent("p_policejob/server/trunks/save", function(data)
    local playerId = source
    if not data or type(data) ~= "table" or not data.model then
        return
    end
    if not Bridge.Framework.checkPermissions(playerId, Config.Trunks.allowedGroups) then
        Bridge.Notify.showNotify(playerId, locale("trunk_editor_no_access"), "error")
        return
    end
    local fileContents = LoadResourceFile(GetCurrentResourceName(), "trunks.json") or "{}"
    local offsets = json.decode(fileContents) or {}
    offsets[data.model] = {
        coords = data.coords,
        rotation = data.rotation,
    }
    SaveResourceFile(
        GetCurrentResourceName(),
        "trunks.json",
        json.encode(offsets, { indent = true }),
        -1
    )
    Bridge.Notify.showNotify(playerId, locale("trunk_saved", data.model), "success")
    TriggerClientEvent("p_policejob/client/trunks/refreshOffsets", -1, offsets)
end)

RegisterNetEvent("p_policejob/server/trunks/takeOut", function(netId)
    local playerId = source
    if not netId or not Trunks.occupiedTrunks[netId] then
        return
    end
    local targetId = Trunks.occupiedTrunks[netId]
    TriggerClientEvent("p_policejob/client/trunks/exit", targetId)
    local webhook = Config.Webhooks and Config.Webhooks.trunks or ""
    Bridge.Logs.Send(playerId, "Trunks", locale("player_took_out_player_from_trunk", targetId), webhook)
end)

RegisterNetEvent("p_policejob/server/trunks/putIn", function(targetId)
    local playerId = source
    if not targetId or not GetPlayerPed(targetId) then
        return
    end
    local officerCoords = GetEntityCoords(GetPlayerPed(playerId))
    local targetCoords = GetEntityCoords(GetPlayerPed(targetId))
    if #(officerCoords - targetCoords) > 5.0 then
        return
    end
    TriggerClientEvent("p_policejob/client/trunks/enter", targetId)
    local webhook = Config.Webhooks and Config.Webhooks.trunks or ""
    Bridge.Logs.Send(playerId, "Trunks", locale("player_put_player_in_trunk", targetId), webhook)
end)

AddEventHandler("playerDropped", function()
    local playerId = source
    for netId, occupant in pairs(Trunks.occupiedTrunks) do
        if occupant == playerId then
            Trunks.occupiedTrunks[netId] = nil
        end
    end
    GlobalState["p_policejob:occupiedTrunks"] = Trunks.occupiedTrunks
end)
