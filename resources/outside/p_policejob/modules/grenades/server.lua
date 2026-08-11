while not Config or not Config.Grenades do
    Wait(50)
end

if not Config.Grenades.Enabled then
    return
end

local flashbangConfig = Config.Grenades.Flashbang
local smokeConfig = Config.Grenades.SmokeGrenade

Grenades = {
    lastThrow = {},
}

function Grenades.hasJobAccess(self, playerId)
    if not next(Config.Jobs) then
        return true
    end
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job or not job.name then
        return false
    end
    local requiredGrade = Config.Jobs[job.name]
    if requiredGrade == nil then
        return false
    end
    local grade = job.grade or 0
    return requiredGrade <= grade
end

function Grenades.detonate(self, playerId, position, radius, clientEvent, label)
    if type(position) ~= "vector3" then
        return
    end
    if not self:hasJobAccess(playerId) then
        Bridge.Debug(("[Grenades] Player %s denied detonation (no access)"):format(playerId))
        return
    end
    local now = GetGameTimer()
    local lastThrow = self.lastThrow[playerId] or 0
    if now - lastThrow < Config.Grenades.CooldownMs then
        return
    end
    self.lastThrow[playerId] = now
    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then
        return
    end
    if #(GetEntityCoords(ped) - position) > Config.Grenades.MaxThrowDistance then
        Bridge.Debug(("[Grenades] Player %s detonation rejected (out of range)"):format(playerId))
        return
    end
    Bridge.Debug(("[Grenades] Player %s detonated %s at %.1f,%.1f,%.1f"):format(
        playerId, label, position.x, position.y, position.z
    ))
    local payload = { pos = position }
    for _, targetId in ipairs(GetPlayers()) do
        targetId = tonumber(targetId)
        local targetPed = GetPlayerPed(targetId)
        if targetPed and targetPed ~= 0 then
            if #(GetEntityCoords(targetPed) - position) <= radius then
                TriggerClientEvent(clientEvent, targetId, payload)
            end
        end
    end
end

RegisterNetEvent("p_policejob/server/grenades/flashbangDetonate", function(position)
    if not flashbangConfig.Enabled then
        return
    end
    Grenades:detonate(source, position, flashbangConfig.Radius, "p_policejob/client/grenades/flashbang", "flashbang")
end)

RegisterNetEvent("p_policejob/server/grenades/smokeDetonate", function(position)
    if not smokeConfig.Enabled then
        return
    end
    Grenades:detonate(source, position, smokeConfig.Radius, "p_policejob/client/grenades/smoke", "smoke")
end)

AddEventHandler("playerDropped", function()
    Grenades.lastThrow[source] = nil
end)
