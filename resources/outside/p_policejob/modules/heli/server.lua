while not Config or not Config.Helicam do
    Citizen.Wait(500)
end

if not Config.Helicam.Enabled then
    return
end

activeSpotlights = {}

function isPlayerInHeli(playerId, netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end
    if GetEntityType(entity) ~= 2 then
        return false
    end
    if GetVehicleType(entity) ~= "heli" then
        return false
    end
    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then
        return false
    end
    return GetVehiclePedIsIn(ped, false) == entity
end

RegisterNetEvent("p_policejob:heli:setSpotlight", function(netId, enabled, direction, radius)
    if type(netId) ~= "number" then
        return
    end
    if enabled and not isPlayerInHeli(source, netId) then
        return
    end
    if enabled then
        activeSpotlights[netId] = {
            dir = direction or { x = 0.0, y = 0.0, z = -1.0 },
            radius = radius,
        }
        TriggerClientEvent(
            "p_policejob:heli:syncSpotlight",
            -1,
            netId,
            true,
            activeSpotlights[netId].dir,
            activeSpotlights[netId].radius
        )
    else
        activeSpotlights[netId] = nil
        TriggerClientEvent("p_policejob:heli:syncSpotlight", -1, netId, false)
    end
end)

RegisterNetEvent("p_policejob:heli:updateSpotlightDir", function(netId, direction)
    if type(netId) ~= "number" or not direction then
        return
    end
    if not activeSpotlights[netId] then
        return
    end
    if not isPlayerInHeli(source, netId) then
        return
    end
    activeSpotlights[netId].dir = direction
    TriggerClientEvent("p_policejob:heli:syncSpotlightDir", -1, netId, direction)
end)

RegisterNetEvent("p_policejob:heli:updateSpotlightRadius", function(netId, radius)
    if type(netId) ~= "number" or type(radius) ~= "number" then
        return
    end
    if not activeSpotlights[netId] then
        return
    end
    if not isPlayerInHeli(source, netId) then
        return
    end
    activeSpotlights[netId].radius = radius
    TriggerClientEvent("p_policejob:heli:syncSpotlightRadius", -1, netId, radius)
end)

RegisterNetEvent("p_policejob:heli:requestSpotlights", function()
    local playerId = source
    for netId, spotlight in pairs(activeSpotlights) do
        TriggerClientEvent(
            "p_policejob:heli:syncSpotlight",
            playerId,
            netId,
            true,
            spotlight.dir,
            spotlight.radius
        )
    end
end)
