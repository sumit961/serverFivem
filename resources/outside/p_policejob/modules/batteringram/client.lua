while not Config or not Config.BatteringRam do
    Citizen.Wait(500)
end

if not Config.BatteringRam.enabled then
    return
end

local cooldownUntil = 0

function hasBatteringRamAccess()
    local job = Bridge.Framework.fetchPlayerJob()
    local allowedJobs = Config.BatteringRam.jobs or Config.Jobs
    local hasAccess = allowedJobs or job
    if job and allowedJobs then
        hasAccess = allowedJobs[job.name] ~= nil
    end
    return hasAccess
end

function attachBatteringRamProp()
    local propConfig = Config.BatteringRam.prop
    if not propConfig or not propConfig.model then
        return nil
    end
    local ped = cache.ped
    local model = type(propConfig.model) == "number" and propConfig.model or joaat(propConfig.model)
    if not IsModelValid(model) then
        return nil
    end
    lib.requestModel(model, 3000)
    if not HasModelLoaded(model) then
        return nil
    end
    local prop = CreateObject(model, GetEntityCoords(ped), true, true, false)
    local boneIndex = GetPedBoneIndex(ped, propConfig.bone or 28422)
    local pos = propConfig.pos or vector3(0, 0, 0)
    local rot = propConfig.rot or vector3(0, 0, 0)
    AttachEntityToEntity(
        prop, ped, boneIndex,
        pos.x, pos.y, pos.z, rot.x, rot.y, rot.z,
        true, true, false, false, 1, true
    )
    SetModelAsNoLongerNeeded(model)
    return prop
end

function useBatteringRam()
    local config = Config.BatteringRam
    if not hasBatteringRamAccess() then
        return Bridge.Notify.showNotify(locale("battering_ram_no_access"), "error")
    end
    if GetGameTimer() < cooldownUntil then
        return
    end
    local targetDoor = config.getTargetDoor and config.getTargetDoor() or nil
    if not targetDoor then
        return Bridge.Notify.showNotify(locale("battering_ram_no_door"), "error")
    end
    cooldownUntil = GetGameTimer() + (config.cooldown or 6000)
    local prop = attachBatteringRamProp()
    local anim = config.anim
    local progressCompleted = Bridge.Progress.Start({
        duration = config.duration or 2500,
        label = locale("battering_ram_forcing"),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = anim and {
            dict = anim.dict,
            clip = anim.clip,
            flag = anim.flag,
        } or nil,
    })
    if prop and DoesEntityExist(prop) then
        DeleteEntity(prop)
    end
    ClearPedTasks(cache.ped)
    if not progressCompleted then
        return
    end
    local door = config.getTargetDoor and config.getTargetDoor() or targetDoor
    local forced = config.forceDoor and config.forceDoor(door)
    if forced then
        Bridge.Notify.showNotify(locale("battering_ram_success"), "success")
    else
        Bridge.Notify.showNotify(locale("battering_ram_failed"), "error")
    end
end

RegisterNetEvent("p_policejob/client/batteringram/use", function()
    useBatteringRam()
end)

exports("useBatteringRam", useBatteringRam)

RegisterCommand("play_ram", function()
    local animDict = lib.requestAnimDict("battering_ram")
    TaskPlayAnim(cache.ped, animDict, "hit", 8.0, 1.0, -1, 1, 0, false, false, false)
    RemoveAnimDict(animDict)
end)
