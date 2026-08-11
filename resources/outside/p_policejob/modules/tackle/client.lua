while not Config or not Config.Tackle do
    Citizen.Wait(500)
end

if not Config.Tackle.Enabled then
    return
end

local tackleConfig = Config.Tackle
local isTackling = false
local tackleCooldownUntil = 0

exports("isTackling", function()
    return isTackling
end)

function canAttemptTackle()
    if isTackling then
        return false
    end
    if IsPedRagdoll(cache.ped) then
        return false
    end
    if cache.vehicle and cache.vehicle ~= 0 then
        return false
    end
    if not IsPedSprinting(cache.ped) then
        return false
    end
    if Config.Jobs then
        local job = Bridge.Framework.fetchPlayerJob()
        if not job or not job.name then
            return false
        end
        local requiredGrade = Config.Jobs[job.name]
        if requiredGrade == nil then
            return false
        end
        local playerGrade = job.grade or 0
        if requiredGrade > playerGrade then
            return false
        end
    end
    return true
end

lib.addKeybind({
    name = "tackle",
    description = "Tackle nearest player",
    defaultKey = tackleConfig.Keybind,
    defaultMapper = "keyboard",
    onPressed = function()
        if not IsControlPressed(0, 21) then
            return
        end
        if GetGameTimer() < tackleCooldownUntil then
            return
        end
        if not canAttemptTackle() then
            return
        end
        local closestPlayer, closestPed = lib.getClosestPlayer(GetEntityCoords(cache.ped), tackleConfig.Distance, false)
        if not closestPlayer or not closestPed or closestPed == 0 or closestPed == cache.ped then
            return
        end
        tackleCooldownUntil = GetGameTimer() + tackleConfig.Timeout
        TriggerServerEvent("p_policejob/server/tackle/tacklePlayer", GetPlayerServerId(closestPlayer))
    end,
})

RegisterNetEvent("p_policejob/client/tackle/tacklePlayer", function(data)
    if isTackling then
        return
    end
    isTackling = true

    if tackleConfig.Type == "animation" then
        local animDict = lib.requestAnimDict("missmic2ig_11")
        if data.isTackler then
            TaskPlayAnim(cache.ped, animDict, "mic_2_ig_11_intro_goon", 8.0, -8.0, 4500, 0, 0)
            SetTimeout(4500, function()
                isTackling = false
            end)
        else
            local tacklerPed = GetPlayerPed(GetPlayerFromServerId(data.targetId))
            AttachEntityToEntity(cache.ped, tacklerPed, 11816, 0.25, 0.5, 0.0, 0.5, 0.5, 180.0, false, false, false, false, 2, false)
            TaskPlayAnim(cache.ped, animDict, "mic_2_ig_11_intro_p_one", 8.0, -8.0, 4000, 0, 0)
            SetTimeout(4000, function()
                DetachEntity(cache.ped, true, true)
                CreateThread(function()
                    while isTackling do
                        SetPedToRagdoll(cache.ped, 1000, 1000, 0, 0, 0, 0)
                        Wait(1)
                    end
                end)
                Wait(4000)
                isTackling = false
            end)
        end
    else
        local ragdollDuration = data.isTackler and 2500 or 4000
        SetPedToRagdoll(cache.ped, ragdollDuration, ragdollDuration, 0, 0, 0, 0)
        Wait(4000)
        isTackling = false
    end
end)
