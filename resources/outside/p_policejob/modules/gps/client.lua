while not Config or not Config.GPS do
    Citizen.Wait(500)
end

if not Config.GPS.enabled then
    return
end

GPS = {
    state = false,
    blips = {},
    panicBlips = {},
}

function GPS.init(self, gpsData)
    self:clear()
    Citizen.Wait(10)
    AddTextEntryByHash(1248374007, "GPS~w~")
    for serverId, playerData in pairs(gpsData) do
        local blipType = Config.GPS.types[playerData.type]
        if blipType and blipType.enabled ~= false then
            local ped = GetPlayerPed(GetPlayerFromServerId(serverId))
            local blip
            if ped and ped ~= 0 then
                if not (ped == cache.ped and cache.serverId ~= serverId) then
                    blip = AddBlipForEntity(ped)
                end
            else
                blip = AddBlipForCoord(playerData.coords.x, playerData.coords.y, playerData.coords.z)
            end
            SetBlipSprite(blip, blipType.sprite)
            SetBlipColour(blip, blipType.color)
            SetBlipScale(blip, blipType.scale)
            SetBlipShrink(blip, true)
            SetBlipPriority(blip, 10)
            ShowHeightOnBlip(blip, false)
            SetBlipHiddenOnLegend(blip, false)
            SetBlipCategory(blip, 7)
            SetBlipAsShortRange(blip, true)
            ShowNumberOnBlip(blip, "10")
            ShowHeadingIndicatorOnBlip(blip, Config.GPS.showHeading)
            SetBlipRotation(blip, math.ceil(playerData.heading))
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(playerData.label)
            EndTextCommandSetBlipName(blip)
            self.blips[serverId] = blip
            if playerData.sirens then
                Citizen.Wait(2000)
                SetBlipColour(blip, blipType.sirenColor)
            end
        end
    end
end

function GPS.clear(self)
    for _, blip in pairs(self.blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    self.blips = {}
end

function GPS.toggle(self)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Jobs[job.name] then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return
    end
    self.state = not self.state
    SetBlipScale(GetMainPlayerBlipId(), self.state and 0.0 or 0.9)
    TriggerServerEvent("p_policejob/gps/server/toggle")
    if not self.state then
        self:clear()
    end
end

exports("isGpsActive", function()
    return GPS.state
end)

function GPS.panic(self)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Jobs[job.name] then
        return
    end
    TriggerServerEvent("p_policejob/gps/server/panic")
end

exports("triggerPanic", function()
    GPS:panic()
end)

function GPS.showPanicAlert(self, alertData)
    if not self.state then
        return
    end
    local existingBlip = self.panicBlips[alertData.source]
    if existingBlip and DoesBlipExist(existingBlip) then
        RemoveBlip(existingBlip)
    end
    local panicConfig = Config.GPS.panic
    local blip = AddBlipForCoord(alertData.coords.x, alertData.coords.y, alertData.coords.z)
    SetBlipSprite(blip, panicConfig.blip.sprite)
    SetBlipColour(blip, panicConfig.blip.color)
    SetBlipScale(blip, panicConfig.blip.scale)
    SetBlipFlashes(blip, panicConfig.blip.flash)
    SetBlipAsShortRange(blip, false)
    SetBlipPriority(blip, 10)
    SetBlipCategory(blip, 7)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(("~r~PANIC~w~ - %s"):format(alertData.name))
    EndTextCommandSetBlipName(blip)
    self.panicBlips[alertData.source] = blip
    if panicConfig.sound then
        PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
    end
    Bridge.Notify.showNotify(("PANIC ALERT: %s"):format(alertData.name), "error")
    Citizen.SetTimeout(panicConfig.duration * 1000, function()
        local panicBlip = self.panicBlips[alertData.source]
        if panicBlip and DoesBlipExist(panicBlip) then
            RemoveBlip(panicBlip)
            self.panicBlips[alertData.source] = nil
        end
    end)
end

function GPS.getClosestOfficer(self)
    local playerCoords = GetEntityCoords(cache.ped)
    local closestDistance = math.huge
    local closestId = nil
    local closestData = nil
    local gpsData = GlobalState["p_policejob/gpsData"]
    if not gpsData then
        return nil
    end
    for serverId, playerData in pairs(gpsData) do
        if serverId ~= cache.serverId then
            local officerCoords = vector3(playerData.coords.x, playerData.coords.y, playerData.coords.z)
            local distance = #(playerCoords - officerCoords)
            if closestDistance > distance then
                closestDistance = distance
                closestId = serverId
                closestData = playerData
            end
        end
    end
    if closestId then
        return {
            id = closestId,
            distance = closestDistance,
            data = closestData,
        }
    end
    return nil
end

exports("getClosestOfficer", function()
    return GPS:getClosestOfficer()
end)

RegisterNetEvent("p_policejob/client/gps/toggle", function()
    GPS:toggle()
end)

RegisterNetEvent("p_policejob/client/gps/panic", function(alertData)
    if not Config.GPS.panic.enabled then
        return
    end
    GPS:showPanicAlert(alertData)
end)

AddStateBagChangeHandler("p_policejob/gpsData", "global", function(_, _, gpsData)
    if not GPS.state then
        return
    end
    local job = Bridge.Framework.fetchPlayerJob()
    if not job or not Config.Jobs[job.name] then
        GPS:clear()
        return
    end
    GPS:init(gpsData)
end)
