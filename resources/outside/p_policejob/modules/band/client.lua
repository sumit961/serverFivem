if not Config.Band.Enabled then
    return
end

Band = {
    props = {},
    blips = {},
    isTracking = false,
}

exports("isBandTracking", function()
    return Band.isTracking
end)

exports("SetPlayerBand", function(player, state)
    TriggerServerEvent("p_policejob/server/band/SetPlayerBand", {
        player = player,
        state = state,
    })
end)

exports("RemovePlayerBand", function(player)
    TriggerServerEvent("p_policejob/server/band/SetPlayerBand", {
        player = player,
        state = false,
    })
end)

AddStateBagChangeHandler("hasTrackingBand", nil, function(bagName, _, value, _, replicated)
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
        Band:removeProp(serverId)
        return
    end
    Wait(1)
    Band:attachProp(serverId, ped)
end)

function Band.attachProp(self, serverId, ped)
    local existingProp = self.props[serverId]
    if existingProp and DoesEntityExist(existingProp) then
        DeleteEntity(existingProp)
    end
    local model = lib.requestModel(Config.Band.Prop.model)
    local prop = CreateObject(model, GetEntityCoords(ped), false, false, false)
    local boneIndex = GetPedBoneIndex(ped, 14201)
    AttachEntityToEntity(
        prop, ped, boneIndex,
        Config.Band.Prop.coords, Config.Band.Prop.rotation,
        true, true, false, true, 1, true
    )
    SetModelAsNoLongerNeeded(model)
    SetEntityCollision(prop, true, false)
    self.props[serverId] = prop
    if serverId == cache.serverId then
        Config.Band.onAttach()
    end
end

function Band.removeProp(self, serverId)
    local prop = self.props[serverId]
    if prop and DoesEntityExist(prop) then
        DeleteEntity(prop)
        self.props[serverId] = nil
    end
    if serverId == cache.serverId then
        Config.Band.onRemove()
    end
end

function Band.createBlip(self, identifier, playerData)
    if not playerData.online or not playerData.coords then
        return
    end
    self:removeBlip(identifier)
    self.blips[identifier] = {}
    local blipConfig = Config.Band.Blip
    local coords = playerData.coords
    local blipEntry = self.blips[identifier]
    blipEntry.first = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipScale(blipEntry.first, blipConfig.scale or 1.1)
    SetBlipSprite(blipEntry.first, blipConfig.sprite or 1)
    SetBlipCategory(blipEntry.first, blipConfig.category or 3)
    SetBlipShrink(blipEntry.first, blipConfig.shrink ~= false)
    SetBlipPriority(blipEntry.first, blipConfig.priority or 3)
    ShowHeightOnBlip(blipEntry.first, blipConfig.height or false)
    SetBlipColour(blipEntry.first, blipConfig.color or 76)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(playerData.name or "Unknown")
    EndTextCommandSetBlipName(blipEntry.first)
    if blipConfig.pulse then
        blipEntry.second = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blipEntry.second, 161)
        SetBlipScale(blipEntry.second, 1.0)
        SetBlipColour(blipEntry.second, blipConfig.color or 76)
        PulseBlip(blipEntry.second)
    end
    if blipConfig.heading and playerData.heading then
        ShowHeadingIndicatorOnBlip(blipEntry.first, true)
        SetBlipRotation(blipEntry.first, playerData.heading)
    end
end

function Band.removeBlip(self, identifier)
    local blipEntry = self.blips[identifier]
    if not blipEntry then
        return
    end
    if blipEntry.first then
        RemoveBlip(blipEntry.first)
    end
    if blipEntry.second then
        RemoveBlip(blipEntry.second)
    end
    self.blips[identifier] = nil
end

function Band.removeAllBlips(self)
    for identifier in pairs(self.blips) do
        self:removeBlip(identifier)
    end
end

function Band.updateBlips(self)
    local playersWithBand = GlobalState.playersWithBand
    if not playersWithBand then
        return
    end
    for identifier, playerData in pairs(playersWithBand) do
        if playerData.coords and playerData.online then
            self:createBlip(identifier, playerData)
        else
            self:removeBlip(identifier)
        end
    end
end

function Band.startTracking(self)
    if self.isTracking then
        return
    end
    self.isTracking = true
    CreateThread(function()
        while self.isTracking do
            self:updateBlips()
            Wait(Config.Band.LoopRate)
        end
    end)
    Bridge.Debug("[Band] Started tracking")
end

function Band.stopTracking(self)
    if not self.isTracking then
        return
    end
    self.isTracking = false
    self:removeAllBlips()
    Bridge.Debug("[Band] Stopped tracking")
end

function Band.checkJobAccess(self)
    if not Bridge.Framework.isPlayerLoaded() then
        return false
    end
    local job = Bridge.Framework.fetchPlayerJob()
    if not job then
        return false
    end
    return Config.Jobs[job.name] ~= nil
end

CreateThread(function()
    while true do
        Wait(2500)
        if Band:checkJobAccess() then
            if not Band.isTracking then
                Band:startTracking()
            end
        elseif Band.isTracking then
            Band:stopTracking()
        end
    end
end)

RegisterNetEvent("p_policejob/client/band/SetPlayerBand", function(state)
    LocalPlayer.state:set("hasTrackingBand", state, true)
end)

RegisterNetEvent("p_policejob/client/band/RemoveBandBlip", function(data)
    Band:removeBlip(data.id)
end)
