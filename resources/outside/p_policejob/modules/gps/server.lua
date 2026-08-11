while not Config or not Config.GPS do
    Citizen.Wait(500)
end

if not Config.GPS.enabled then
    return
end

GPS = {
    players = {},
}

GlobalState["p_policejob/gpsData"] = GPS.players

function GPS.getType(self, ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle and vehicle ~= 0 then
        local vehicleType = GetVehicleType(vehicle)
        if vehicleType == "boat" then
            return "boat"
        elseif vehicleType == "plane" then
            return "plane"
        elseif vehicleType == "heli" then
            return "heli"
        else
            return "car"
        end
    end
    return "walk"
end

function GPS.getSpeed(self, ped)
    local velocity = GetEntityVelocity(ped)
    local speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)
    return math.floor(speed * 3.6)
end

function GPS.update(self, playerId)
    if not playerId or playerId == 0 then
        return
    end
    local success, ped = pcall(GetPlayerPed, playerId)
    if success and ped and ped ~= 0 then
        local vehicle = GetVehiclePedIsIn(ped, false)
        local playerName = Bridge.Framework.getPlayerName(playerId)
        local job = Bridge.Framework.getPlayerJob(playerId)
        self.players[playerId] = {
            label = ("%s - %s"):format(playerName, job.grade_label),
            heading = GetEntityHeading(ped),
            coords = GetEntityCoords(ped),
            type = self:getType(ped),
            speed = self:getSpeed(ped),
            sirens = vehicle ~= 0 and IsVehicleSirenOn(vehicle) or false,
        }
    else
        self.players[playerId] = nil
    end
end

function GPS.toggle(self, playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job or not Config.Jobs[job.name] then
        Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
        return
    end
    if self.players[playerId] then
        self.players[playerId] = nil
        Bridge.Debug(("[GPS] Player %s deactivated GPS"):format(playerId))
        Bridge.Notify.showNotify(playerId, locale("deactivated_gps"), "inform")
    else
        self:update(playerId)
        Bridge.Debug(("[GPS] Player %s activated GPS"):format(playerId))
        Bridge.Notify.showNotify(playerId, locale("activated_gps"), "inform")
    end
end

function GPS.triggerPanic(self, playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job or not Config.Jobs[job.name] then
        return
    end
    if not Config.GPS.panic.enabled then
        return
    end
    local success, ped = pcall(GetPlayerPed, playerId)
    if not success or not ped or ped == 0 then
        return
    end
    local playerName = Bridge.Framework.getPlayerName(playerId)
    local coords = GetEntityCoords(ped)
    Bridge.Debug(("[GPS] Panic triggered by %s (%s)"):format(playerId, playerName))
    local alertData = {
        source = playerId,
        name = playerName,
        coords = coords,
    }
    for otherPlayerId in pairs(self.players) do
        if otherPlayerId ~= playerId then
            TriggerClientEvent("p_policejob/client/gps/panic", otherPlayerId, alertData)
        end
    end
    Bridge.Notify.showNotify(playerId, "Panic signal sent!", "error")
end

function GPS.init(self)
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(Config.GPS.updateInterval or 3000)
            for playerId in pairs(self.players) do
                Citizen.Wait(1)
                if Config.GPS.requiredItem then
                    if Bridge.Inventory.getItemCount(playerId, Config.GPS.requiredItemName) < 1 then
                        TriggerClientEvent("p_policejob/client/gps/toggle", playerId)
                    end
                else
                    self:update(playerId)
                end
            end
            GlobalState["p_policejob/gpsData"] = self.players
        end
    end)
end

RegisterNetEvent("p_policejob/gps/server/toggle", function()
    GPS:toggle(source)
end)

RegisterNetEvent("p_policejob/gps/server/panic", function()
    GPS:triggerPanic(source)
end)

GPS:init()

exports("getGpsPlayers", function()
    return GPS.players
end)

exports("isGpsActive", function(playerId)
    return GPS.players[playerId] ~= nil
end)

exports("toggleGps", function(playerId)
    GPS:toggle(playerId)
end)

exports("triggerPanic", function(playerId)
    GPS:triggerPanic(playerId)
end)
