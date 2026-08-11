if not Config or not Config.Interactions or not Config.Interactions.MouthTape then
    return
end

MouthTape = {
    props = {},
    isActive = false,
}

AddStateBagChangeHandler("mouthTaped", nil, function(bagName, _, value, _, replicated)
    if replicated then
        return
    end
    local playerId = GetPlayerFromStateBagName(bagName)
    if playerId == 0 then
        return
    end
    local ped = GetPlayerPed(playerId)
    local serverId = GetPlayerServerId(playerId)
    if not value then
        MouthTape:removeProp(serverId)
        if cache.serverId == serverId then
            MouthTape.isActive = false
        end
        return
    end
    Wait(1)
    MouthTape:attachProp(serverId, ped)
    if cache.serverId == serverId and not MouthTape.isActive then
        MouthTape.isActive = true
        CreateThread(function()
            while MouthTape.isActive do
                Wait(1000)
                if GetResourceState("pma-voice") == "started" then
                    exports["pma-voice"]:overrideProximityCheck(function()
                        return false
                    end)
                elseif GetResourceState("yaca-voice") == "started" then
                    exports["yaca-voice"]:setMaxVoiceRange(0.0)
                end
            end
            Wait(1000)
            if GetResourceState("pma-voice") == "started" then
                exports["pma-voice"]:resetProximityCheck()
            elseif GetResourceState("yaca-voice") == "started" then
                exports["yaca-voice"]:setMaxVoiceRange(-1)
            end
        end)
    end
end)

function MouthTape.attachProp(self, serverId, ped)
    if self.props[serverId] and DoesEntityExist(self.props[serverId]) then
        DeleteEntity(self.props[serverId])
    end
    local tapeConfig = Config.Interactions.MouthTape
    local model = lib.requestModel(tapeConfig.model)
    local prop = CreateObject(model, GetEntityCoords(ped), false, false, false)
    local boneIndex = GetPedBoneIndex(ped, tapeConfig.bone)
    AttachEntityToEntity(
        prop, ped, boneIndex,
        tapeConfig.coords, tapeConfig.rotation,
        true, true, false, true, 1, true
    )
    SetEntityAsMissionEntity(prop, true, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityCollision(prop, true, false)
    self.props[serverId] = prop
end

function MouthTape.removeProp(self, serverId)
    local prop = self.props[serverId]
    if prop and DoesEntityExist(prop) then
        DeleteEntity(prop)
        self.props[serverId] = nil
    end
end

exports("isMouthTaped", function()
    return LocalPlayer.state.mouthTaped == true
end)

exports("setPlayerMouthTape", function(player, state)
    TriggerServerEvent("p_policejob:mouthtape:toggleTape", {
        player = player,
        state = state,
    })
end)
