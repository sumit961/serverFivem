if not Config or not Config.Interactions or not Config.Interactions.Enabled then
    return
end

Interactions = {
    cuffedBy = {},
}

function Interactions.canInteract(self, sourceId, targetId, distance)
    return Editable:canInteract(sourceId, targetId, distance)
end

function Interactions.isPlayerDead(self, playerId)
    return Editable:isPlayerDead(playerId)
end

function forceUncuffPlayer(playerId)
    local state = Player(playerId).state
    if not state.isCuffed then
        return
    end

    state:set('cuffed', false, true)
    state:set('isCuffed', false, true)
    state:set('cuffType', 'none', true)

    local attempts = 0
    Wait(1000)
    while Player(playerId).state.isCuffed do
        Wait(500)
        attempts = attempts + 1
        if attempts >= 5 then
            break
        end
    end

    TriggerClientEvent('p_policejob/client/interactions/ForceUncuff', playerId)
    Bridge.Logs.Send(playerId, 'Interactions', locale('player_has_been_force_uncuffed'), Config.Webhooks.interactions)
end

function forceCuffPlayer(playerId)
    local state = Player(playerId).state
    if state.isCuffed then
        return
    end

    state:set('cuffed', true, true)
    state:set('isCuffed', true, true)
    state:set('cuffType', 'cuffs', true)
    TriggerClientEvent('p_policejob/client/interactions/ForceCuff', playerId)
    Bridge.Logs.Send(playerId, 'Interactions', locale('player_has_been_force_cuffed'), Config.Webhooks.interactions)
end

exports('forceUncuff', forceUncuffPlayer)
exports('forceCuff', forceCuffPlayer)

function shouldPersistCuffAfterLogout()
    if not Config.Interactions.Cuffs.saveAfterLogout then
        return false
    end
    return GetResourceState('es_extended') == 'started'
end

function setPlayerHandcuffMetadata(player, value)
    if not player then
        return
    end
    value = value == true

    if player.setMeta then
        player.setMeta('ishandcuffed', value)
    elseif player.Functions and player.Functions.SetMetaData then
        player.Functions.SetMetaData('ishandcuffed', value)
    end
end

function getPlayerHandcuffMetadata(player)
    if not player then
        return false
    end

    if player.getMeta then
        return player.getMeta('ishandcuffed') == true
    end

    if player.PlayerData and player.PlayerData.metadata then
        return player.PlayerData.metadata.ishandcuffed == true
    end

    return false
end

RegisterNetEvent('p_policejob/server/interactions/HandCuffs', function(data)
    local sourceId = source
    if not Interactions:canInteract(sourceId, data.player, 5.0) then
        Bridge.Debug(('[Interactions] Player %s invalid cuff attempt on %s'):format(sourceId, tostring(data.player)))
        Bridge.Logs.Send(sourceId, 'Interactions', 'Attempted invalid cuff on ' .. tostring(data.player), Config.Webhooks.interactions)
        return
    end

    if data.type == 'cuffs' then
        if Config.Interactions.Cuffs.cuffKeys then
            Interactions.cuffedBy[data.player] = data.state and sourceId or nil

            if data.state then
                if Bridge.Inventory.getItemCount(sourceId, 'handcuffs') < 1 then
                    return
                end
                Bridge.Inventory.removeItem(sourceId, 'handcuffs', 1)
                Bridge.Inventory.addItem(sourceId, 'cuffs_key', 1, data.player)
            else
                if Bridge.Inventory.getItemCount(sourceId, 'cuffs_key', data.player) < 1 then
                    return
                end
                Bridge.Inventory.removeItem(sourceId, 'cuffs_key', 1, data.player)
                Bridge.Inventory.addItem(sourceId, 'handcuffs', 1)
            end
        elseif Bridge.Inventory.getItemCount(sourceId, 'handcuffs') < 1 then
            return
        end
    elseif data.state then
        if Bridge.Inventory.getItemCount(sourceId, 'cable_ties') < 1 then
            return
        end
        Bridge.Inventory.removeItem(sourceId, 'cable_ties', 1)
    else
        Bridge.Inventory.addItem(sourceId, 'cable_ties', 1)
    end

    if data.state then
        Config.Interactions.onCuff_Server(sourceId, data.player, data.type)
    else
        Config.Interactions.onUnCuff_Server(sourceId, data.player, data.type)
    end

    local officerPayload = {
        isCuff = data.state,
        isArrested = false,
        player = data.player,
        type = data.type,
        timer = data.timer,
        time = data.time,
        front = data.front,
        isHard = data.isHard,
    }
    TriggerClientEvent('p_policejob/client/interactions/HandCuffsAnimation', sourceId, officerPayload)

    local arrestedPayload = {
        isCuff = data.state,
        isArrested = true,
        player = sourceId,
        type = data.type,
        timer = data.timer,
        time = data.time,
        front = data.front,
        isHard = data.isHard,
    }
    TriggerClientEvent('p_policejob/client/interactions/HandCuffsAnimation', data.player, arrestedPayload)

    local action = data.state and 'Cuffed' or 'Uncuffed'
    Bridge.Logs.Send(
        sourceId,
        'Interactions',
        action .. ' player ' .. tostring(data.player) .. ' (' .. data.type .. ')',
        Config.Webhooks.interactions
    )
    Bridge.Debug(('[Interactions] Player %s %s player %s (%s)'):format(
        sourceId,
        data.state and 'cuffed' or 'uncuffed',
        tostring(data.player),
        tostring(data.type)
    ))
end)

AddStateBagChangeHandler('isCuffed', nil, function(bagName, _, value, _, replicated)
    if replicated then
        return
    end

    local playerId = GetPlayerFromStateBagName(bagName)
    if not playerId then
        return
    end

    local cufferId = Interactions.cuffedBy[playerId]
    if cufferId and not value then
        Bridge.Inventory.removeItem(cufferId, 'cuffs_key', 1, playerId)
        Bridge.Inventory.addItem(cufferId, 'handcuffs', 1)
    end

    if shouldPersistCuffAfterLogout() then
        local player = Bridge.Framework.getPlayerById(playerId)
        setPlayerHandcuffMetadata(player, value)
    end
end)

AddEventHandler('p_bridge/server/playerLoaded', function(playerId)
    Wait(1000)
    if not shouldPersistCuffAfterLogout() then
        return
    end

    local player = Bridge.Framework.getPlayerById(playerId)
    if getPlayerHandcuffMetadata(player) then
        forceCuffPlayer(playerId)
    end
end)

RegisterNetEvent('p_policejob/server/interactions/OpenCuffs', function(data)
    local sourceId = source
    if not Interactions:canInteract(sourceId, data.player) then
        return
    end

    local success = lib.callback.await('p_policejob/client/interactions/attemptOpenCuffs', sourceId)
    if not success then
        return
    end

    forceUncuffPlayer(data.player)
    Bridge.Notify.showNotify(sourceId, locale('you_opened_cuffs'), 'success')
    Bridge.Logs.Send(sourceId, 'Interactions', 'Lockpicked cuffs on player ' .. tostring(data.player), Config.Webhooks.interactions)
end)

RegisterNetEvent('p_policejob/server/interactions/DragPlayer', function(data)
    local sourceId = source
    if not Interactions:canInteract(sourceId, data.player, 5.0) then
        return
    end

    local officerState = Player(sourceId).state
    local targetState = Player(data.player).state

    if data.state and targetState.draggedBy then
        return
    end

    local targetIsDead = Interactions:isPlayerDead(data.player)
    local canDrag = targetIsDead
        or targetState.isCuffed
        or (officerState.draggingPlayer and officerState.draggingPlayer == data.player)

    if not canDrag then
        return
    end

    TriggerClientEvent('p_policejob/client/interactions/StartDrag', sourceId, {
        state = data.state,
        isDragging = true,
        player = data.player,
    })
    TriggerClientEvent('p_policejob/client/interactions/StartDrag', data.player, {
        state = data.state,
        isDragging = false,
        player = sourceId,
    })

    officerState:set('draggingPlayer', data.state and data.player or nil, true)
    targetState:set('draggedBy', data.state and sourceId or nil, true)
    targetState:set('escorted', data.state, true)

    local action = data.state and 'Started dragging' or 'Stopped dragging'
    Bridge.Logs.Send(sourceId, 'Interactions', action .. ' player ' .. tostring(data.player), Config.Webhooks.interactions)
end)

RegisterNetEvent('p_policejob/server/interactions/OutVehicle', function(data)
    local sourceId = source
    if not Interactions:canInteract(sourceId, data.player) then
        return
    end

    local targetState = Player(data.player).state
    if not Interactions:isPlayerDead(data.player) and not targetState.isCuffed then
        return
    end

    TriggerClientEvent('p_policejob/client/interactions/TakeOutVehicle', data.player)
    Bridge.Logs.Send(sourceId, 'Interactions', 'Took out player ' .. tostring(data.player) .. ' from vehicle', Config.Webhooks.interactions)
end)

RegisterNetEvent('p_policejob/server/interactions/PutInVehicle', function(data)
    local sourceId = source
    if not Interactions:canInteract(sourceId, data.player) then
        return
    end

    local targetState = Player(data.player).state
    if not Interactions:isPlayerDead(data.player) and not targetState.isCuffed then
        return
    end

    if targetState.draggedBy then
        TriggerClientEvent('p_policejob/client/interactions/StartDrag', sourceId, {
            state = false,
            isDragging = true,
            player = data.player,
        })
        TriggerClientEvent('p_policejob/client/interactions/StartDrag', data.player, {
            state = false,
            isDragging = false,
            player = sourceId,
        })
        Player(sourceId).state:set('draggingPlayer', nil, true)
        targetState:set('draggedBy', nil, true)
        targetState:set('escorted', false, true)
        Wait(100)
    end

    TriggerClientEvent('p_policejob/client/interactions/PutInVehicle', data.player, {
        player = sourceId,
        seat = data.seat,
    })
    Bridge.Logs.Send(
        sourceId,
        'Interactions',
        'Put player ' .. tostring(data.player) .. ' in vehicle seat ' .. tostring(data.seat),
        Config.Webhooks.interactions
    )
end)

RegisterNetEvent('p_policejob/server/interactions/CheckGunPowder', function(targetId)
    local sourceId = source
    if not Interactions:canInteract(sourceId, targetId) then
        return
    end

    local hasGunpowder = lib.callback.await('p_policejob/client/evidence/checkGunPowder', targetId)
    if hasGunpowder then
        Bridge.Notify.showNotify(sourceId, locale('this_player_have_gun_powder'), 'info')
    else
        Bridge.Notify.showNotify(sourceId, locale('this_player_dont_have_gun_powder'), 'info')
    end

    Bridge.Logs.Send(
        sourceId,
        'Interactions',
        'Checked gunpowder on ' .. tostring(targetId) .. ' (' .. (hasGunpowder and '+' or '-') .. ')',
        Config.Webhooks.interactions
    )
end)

RegisterNetEvent('p_policejob/server/interactions/ToggleHeadBag', function(data)
    local sourceId = source
    if not Interactions:canInteract(sourceId, data.player) then
        return
    end

    local targetState = Player(data.player).state
    if data.state and targetState.hasHeadBag then
        return
    end
    if not data.state and not targetState.hasHeadBag then
        return
    end

    if data.state then
        if Bridge.Inventory.getItemCount(sourceId, 'headbag') < 1 then
            return
        end
        Bridge.Inventory.removeItem(sourceId, 'headbag', 1)
    else
        Bridge.Inventory.addItem(sourceId, 'headbag', 1)
    end

    targetState:set('hasHeadBag', data.state, true)
    TriggerClientEvent('p_policejob/client/interactions/ToggleHeadBag', data.player, data.state)

    local action = data.state and 'Put head bag on' or 'Removed head bag from'
    Bridge.Logs.Send(sourceId, 'Interactions', action .. ' player ' .. tostring(data.player), Config.Webhooks.interactions)
end)

RegisterNetEvent('p_policejob/server/interactions/ToggleMouthTape', function(data)
    local sourceId = source
    if not Interactions:canInteract(sourceId, data.player) then
        return
    end

    local targetState = Player(data.player).state
    if data.state and targetState.mouthTaped then
        return
    end
    if not data.state and not targetState.mouthTaped then
        return
    end

    if data.state then
        if Bridge.Inventory.getItemCount(sourceId, 'mouthtape') < 1 then
            return
        end
        Bridge.Inventory.removeItem(sourceId, 'mouthtape', 1)
    else
        Bridge.Inventory.addItem(sourceId, 'mouthtape', 1)
    end

    targetState:set('mouthTaped', data.state, true)

    local action = data.state and 'Mouth-taped' or 'Removed mouth tape from'
    Bridge.Logs.Send(sourceId, 'Interactions', action .. ' player ' .. tostring(data.player), Config.Webhooks.interactions)
end)

RegisterNetEvent('p_policejob/server/interactions/StartCarryPlayer', function(targetId)
    local sourceId = source
    if not Interactions:canInteract(sourceId, targetId) then
        return
    end

    local targetState = Player(targetId).state
    if targetState.carriedBy then
        return
    end

    local accepted = true
    if Config.Interactions.Carry.useRequest then
        accepted = lib.callback.await('p_policejob/client/interactions/RequestCarryPlayer', targetId, sourceId)
    end

    if not accepted then
        return
    end

    targetState:set('carriedBy', sourceId, true)
    Player(sourceId).state:set('carryingPlayer', targetId, true)
    TriggerClientEvent('p_policejob/client/interactions/StartCarryPlayer', sourceId, {
        isCarrying = true,
        playerId = targetId,
    })
    TriggerClientEvent('p_policejob/client/interactions/StartCarryPlayer', targetId, {
        isCarrying = false,
        playerId = sourceId,
    })
    Bridge.Logs.Send(sourceId, 'Interactions', 'Started carrying player ' .. tostring(targetId), Config.Webhooks.interactions)
end)

RegisterNetEvent('p_policejob/server/interactions/StopCarryPlayer', function(targetId)
    local sourceId = source
    if not Interactions:canInteract(sourceId, targetId) then
        return
    end

    local targetState = Player(targetId).state
    if not targetState.carriedBy or targetState.carriedBy ~= sourceId then
        return
    end

    targetState:set('carriedBy', nil, true)
    Player(sourceId).state:set('carryingPlayer', nil, true)
    TriggerClientEvent('p_policejob/client/interactions/StopCarryPlayer', sourceId)
    TriggerClientEvent('p_policejob/client/interactions/StopCarryPlayer', targetId)
    Bridge.Logs.Send(sourceId, 'Interactions', 'Stopped carrying player ' .. tostring(targetId), Config.Webhooks.interactions)
end)

AddEventHandler('playerDropped', function()
    Interactions.cuffedBy[source] = nil
end)
