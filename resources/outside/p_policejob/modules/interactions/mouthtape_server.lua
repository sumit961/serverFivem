if not Config or not Config.Interactions or not Config.Interactions.MouthTape then
    return
end

MouthTape = {}

RegisterNetEvent("p_policejob:mouthtape:toggleTape", function(data)
    local playerId = source
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job or not Config.Jobs[job.name] then
        return
    end
    local target = Player(data.player)
    local targetState = target.state
    if not targetState then
        return
    end
    if data.state then
        if targetState.mouthTaped then
            return
        end
    elseif not targetState.mouthTaped then
        return
    end
    if data.state then
        if Bridge.Inventory.getItemCount(playerId, "mouthtape") < 1 then
            return
        end
        Bridge.Inventory.removeItem(playerId, "mouthtape", 1)
    else
        Bridge.Inventory.addItem(playerId, "mouthtape", 1)
    end
    targetState:set("mouthTaped", data.state, true)
    local actionLabel = data.state and "Mouth-taped" or "Removed mouth tape from"
    Bridge.Logs.Send(
        playerId,
        "Interactions",
        actionLabel .. " player " .. tostring(data.player),
        Config.Webhooks.interactions
    )
end)

exports("setPlayerMouthTape", function(playerId, state)
    local target = Player(playerId)
    if not target.state then
        return false
    end
    target.state:set("mouthTaped", state, true)
    return true
end)

exports("isPlayerMouthTaped", function(playerId)
    local target = Player(playerId)
    if not target.state then
        return false
    end
    return target.state.mouthTaped == true
end)
