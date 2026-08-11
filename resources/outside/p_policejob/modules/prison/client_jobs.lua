if not Config or not Config.Prison or not Config.Prison.Enabled then
    return
end

if not Config.Prison.PrisonJobs or not Config.Prison.PrisonJobs.enabled then
    return
end

local jobCooldowns = {}
local lastCompletedJobId = nil
local activePrisonJob = nil
local minigameResultCallback = nil

function removeJobSphereZone(zoneId)
    if not zoneId then
        return
    end
    if Bridge.Target and Bridge.Target.removeSphereZone then
        pcall(Bridge.Target.removeSphereZone, zoneId)
    elseif exports.ox_target then
        pcall(function()
            exports.ox_target:removeZone(zoneId)
        end)
    end
end

function cleanupDirtProps()
    if not activePrisonJob or not activePrisonJob.dirtProps then
        return
    end
    for _, prop in ipairs(activePrisonJob.dirtProps) do
        if DoesEntityExist(prop) then
            DeleteEntity(prop)
        end
    end
    activePrisonJob.dirtProps = nil
end

function spawnDirtProps(jobId, coords)
    local dirtConfig = Config.Prison.PrisonJobs.dirtProps
    if not dirtConfig or dirtConfig.enabled == false then
        return
    end
    if dirtConfig.jobs and not dirtConfig.jobs[jobId] then
        return
    end
    local models = dirtConfig.models or {}
    if #models == 0 then
        return
    end

    local count = math.max(0, tonumber(dirtConfig.count) or 0)
    local radius = tonumber(dirtConfig.radius) or 1.5
    local props = {}

    for _ = 1, count do
        local modelEntry = models[math.random(#models)]
        local modelHash = type(modelEntry) == "number" and modelEntry or joaat(modelEntry)
        if IsModelValid(modelHash) then
            lib.requestModel(modelHash, 5000)
            if HasModelLoaded(modelHash) then
                local angle = math.random() * 2 * math.pi
                local offset = math.sqrt(math.random()) * radius
                local x = coords.x + math.cos(angle) * offset
                local y = coords.y + math.sin(angle) * offset
                local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, coords.z + 1.0, false)
                local prop = CreateObject(
                    modelHash, x, y,
                    foundGround and groundZ or coords.z,
                    false, false, false
                )
                PlaceObjectOnGroundProperly(prop)
                SetEntityHeading(prop, math.random(0, 359) + 0.0)
                FreezeEntityPosition(prop, true)
                SetModelAsNoLongerNeeded(modelHash)
                props[#props + 1] = prop
            end
        end
    end

    activePrisonJob.dirtProps = props
end

function cleanupActiveJobVisuals()
    if not activePrisonJob then
        return
    end
    if activePrisonJob.blip and DoesBlipExist(activePrisonJob.blip) then
        RemoveBlip(activePrisonJob.blip)
    end
    activePrisonJob.blip = nil
    removeJobSphereZone(activePrisonJob.zoneId)
    activePrisonJob.zoneId = nil
    cleanupDirtProps()
end

function pickJobLocation(jobId, excludeCoords)
    if not Prison.Map or not Prison.Map.jobLocations then
        return nil
    end
    local locations = Prison.Map.jobLocations[jobId]
    if not locations or #locations == 0 then
        return nil
    end
    if #locations == 1 or not excludeCoords then
        return locations[math.random(#locations)]
    end

    local picked = nil
    for _ = 1, 8 do
        picked = locations[math.random(#locations)]
        if #(vector3(picked.x, picked.y, picked.z) - excludeCoords) > 0.5 then
            return picked
        end
    end
    return picked
end

function buildJobsList()
    local jobs = {}
    local now = GetGameTimer()
    local defaultJobs = Config.Prison.PrisonJobs.defaultJobs or {}
    local jobIcons = {
        cleaning = "bubbles",
        laundry = "shirt",
        kitchen = "chef",
    }

    for _, jobDef in ipairs(defaultJobs) do
        local cooldownUntil = jobCooldowns[jobDef.id] or 0
        local onCooldown = now < cooldownUntil
        jobs[#jobs + 1] = {
            id = jobDef.id,
            label = jobDef.label,
            description = jobDef.description,
            payment = jobDef.payment,
            duration = jobDef.duration,
            timeReduction = jobDef.timeReduction,
            icon = jobIcons[jobDef.id],
            onCooldown = onCooldown,
            cooldownLeft = onCooldown and math.ceil((cooldownUntil - now) / 1000) or 0,
            locked = jobDef.id == lastCompletedJobId,
        }
    end

    return jobs
end

function runPrisonMinigame(jobDef)
    local minigameConfig = Config.Prison.Minigames
    if minigameConfig and minigameConfig.useExternal and type(minigameConfig.externalExport) == "function" then
        local ok, result = pcall(minigameConfig.externalExport)
        if ok then
            return result == true
        end
    end

    local jobMinigameConfig = Config.Prison.PrisonJobs.minigame or {}
    if jobMinigameConfig.useCustom and type(jobMinigameConfig.customRun) == "function" then
        local ok, result = pcall(jobMinigameConfig.customRun, jobDef)
        if ok then
            return result == true
        end
    end

    local variant = (jobMinigameConfig.perJob and jobMinigameConfig.perJob[jobDef.id])
        or jobMinigameConfig.default
        or "scrub"

    local promiseObj = promise.new()

    function resolveMinigame(success)
        if promiseObj then
            local resolve = promiseObj.resolve
            promiseObj = nil
            resolve(success == true)
        end
    end

    minigameResultCallback = resolveMinigame
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "setVisiblePrisonMinigame",
        data = {
            variant = variant,
            label = jobDef.label or "Prison Task",
        },
    })

    local success = Citizen.Await(promiseObj)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisiblePrisonMinigame", data = false })
    return success
end

function playJobAnimation(jobDef, duration)
    local anim = jobDef.animation
    if not anim or not anim.dict or not anim.clip then
        Wait(duration)
        return
    end

    lib.requestAnimDict(anim.dict)
    TaskPlayAnim(
        cache.ped, anim.dict, anim.clip,
        4.0, -4.0, duration,
        1, 0, false, false, false
    )
    Wait(duration)
    ClearPedTasks(cache.ped)
end

function setupNextJobStop()
    if not activePrisonJob then
        return
    end

    local jobDef = activePrisonJob.jobDef
    local location = pickJobLocation(jobDef.id, activePrisonJob.currentCoords)
    if not location then
        Bridge.Notify.showNotify(locale("prison_job_no_locations"), "error")
        cleanupActiveJobVisuals()
        activePrisonJob = nil
        return
    end

    activePrisonJob.currentCoords = vector3(location.x, location.y, location.z)
    spawnDirtProps(jobDef.id, activePrisonJob.currentCoords)

    local blipConfig = Config.Prison.PrisonJobs.stopBlip or {}
    local blip = AddBlipForCoord(location.x, location.y, location.z)
    SetBlipSprite(blip, blipConfig.sprite or 280)
    SetBlipColour(blip, blipConfig.color or 5)
    SetBlipScale(blip, blipConfig.scale or 0.9)
    SetBlipAsShortRange(blip, true)
    SetBlipRoute(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(
        ("%s (%d/%d)"):format(
            blipConfig.label or "Prison Task",
            activePrisonJob.stopsDone + 1,
            activePrisonJob.stopsTotal
        )
    )
    EndTextCommandSetBlipName(blip)
    activePrisonJob.blip = blip

    local zoneName = ("p_policejob_prison_job_stop_%d"):format(GetGameTimer())
    activePrisonJob.zoneId = Bridge.Target.addSphereZone({
        coords = activePrisonJob.currentCoords,
        radius = 1.2,
        debug = Bridge and Bridge.Config and Bridge.Config.Debug,
        drawSprite = true,
        options = {
            {
                name = zoneName,
                label = jobDef.label or "Work",
                icon = "fa-solid fa-broom",
                distance = 1.8,
                onSelect = onJobStopSelected,
            },
        },
    })
end

function onJobStopSelected()
    if not activePrisonJob or activePrisonJob.busy then
        return
    end
    if not Prison.isInPrison then
        return
    end

    activePrisonJob.busy = true
    playJobAnimation(activePrisonJob.jobDef, 200)

    local anim = activePrisonJob.jobDef.animation
    if anim and anim.dict then
        lib.requestAnimDict(anim.dict)
        TaskPlayAnim(
            cache.ped, anim.dict, anim.clip,
            4.0, -4.0, -1,
            1, 0, false, false, false
        )
    end

    local minigameSuccess = runPrisonMinigame(activePrisonJob.jobDef)
    ClearPedTasks(cache.ped)

    if not minigameSuccess then
        Bridge.Notify.showNotify(locale("prison_job_failed"), "error")
        activePrisonJob.busy = false
        return
    end

    Bridge.Notify.showNotify(
        locale("prison_job_task_progress", activePrisonJob.stopsDone + 1, activePrisonJob.stopsTotal),
        "success"
    )
    activePrisonJob.stopsDone = activePrisonJob.stopsDone + 1
    cleanupActiveJobVisuals()

    if activePrisonJob.stopsDone >= activePrisonJob.stopsTotal then
        local jobDef = activePrisonJob.jobDef
        local stopsCompleted = activePrisonJob.stopsDone
        local cooldownMs = (jobDef.duration or 30) * 1000
        jobCooldowns[jobDef.id] = GetGameTimer() + cooldownMs
        lastCompletedJobId = jobDef.id
        activePrisonJob = nil

        TriggerServerEvent("p_policejob/server/prison/jobComplete", {
            jobId = jobDef.id,
            stopsCompleted = stopsCompleted,
        })

        local payment = (jobDef.payment or 0) * stopsCompleted
        local timeReduction = (jobDef.timeReduction or 0) * stopsCompleted
        Bridge.Notify.showNotify(
            ("Shift complete! +$%d, -%d min off your sentence"):format(payment, timeReduction),
            "success"
        )
        Bridge.Notify.showNotify(locale("prison_job_talk_to_guard"), "info")
        return
    end

    activePrisonJob.busy = false
    setupNextJobStop()
end

function startJobMarkerThread()
    CreateThread(function()
        local markerConfig = Config.Prison.PrisonJobs.stopMarker or {}
        if markerConfig.enabled == false then
            return
        end

        local color = markerConfig.color or { r = 255, g = 170, b = 40, a = 200 }
        local size = markerConfig.size or 0.35
        local drawDistance = markerConfig.drawDistance or 60.0

        while activePrisonJob do
            local coords = activePrisonJob.currentCoords
            if coords then
                if #(GetEntityCoords(cache.ped) - coords) <= drawDistance then
                    DrawMarker(
                        markerConfig.type or 2,
                        coords.x, coords.y, coords.z + (markerConfig.height or 1.4),
                        0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                        size, size, size,
                        color.r, color.g, color.b, color.a,
                        true, false, 2, true, nil, nil, false
                    )
                    Wait(0)
                else
                    Wait(400)
                end
            else
                Wait(200)
            end
        end
    end)
end

function startPrisonJob(jobDef)
    if activePrisonJob then
        Bridge.Notify.showNotify(locale("prison_job_already_active"), "error")
        return
    end
    if jobDef.id == lastCompletedJobId then
        Bridge.Notify.showNotify(locale("prison_job_repeat"), "error")
        return
    end

    local cooldownUntil = jobCooldowns[jobDef.id]
    if cooldownUntil and GetGameTimer() < cooldownUntil then
        Bridge.Notify.showNotify(locale("prison_job_cooldown"), "error")
        return
    end

    local stopsTotal = tonumber(Config.Prison.PrisonJobs.stopsPerJob) or 5
    if stopsTotal < 1 then
        stopsTotal = 1
    end

    activePrisonJob = {
        jobDef = jobDef,
        stopsTotal = stopsTotal,
        stopsDone = 0,
        currentCoords = nil,
        blip = nil,
        zoneId = nil,
        busy = false,
    }

    Bridge.Notify.showNotify(
        ("Shift started: %s. Complete %d tasks marked on your map."):format(jobDef.label, stopsTotal),
        "info"
    )
    setupNextJobStop()
    startJobMarkerThread()
end

function openPrisonJobsUI()
    if not Prison.isInPrison then
        Bridge.Notify.showNotify(locale("prison_job_not_in_prison"), "error")
        return
    end
    if activePrisonJob then
        Bridge.Notify.showNotify(locale("prison_job_already_active"), "error")
        return
    end

    SendNUIMessage({ action = "setVisiblePrisonJobs", data = true })
    SendNUIMessage({
        action = "setPrisonJobsData",
        data = { jobs = buildJobsList() },
    })
    SetNuiFocus(true, true)
end

RegisterNetEvent("p_policejob/client/prison/openJobs", function()
    openPrisonJobsUI()
end)

RegisterNUICallback("prison/jobs/close", function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisiblePrisonJobs", data = false })
    cb({})
end)

RegisterNUICallback("prison/minigame/result", function(data, cb)
    cb({})
    local callback = minigameResultCallback
    minigameResultCallback = nil
    if callback then
        callback(data and data.success == true)
    end
end)

RegisterNUICallback("prison/jobs/complete", function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisiblePrisonJobs", data = false })
    cb({})

    if not data or not data.jobId then
        return
    end
    if not Prison.isInPrison then
        return
    end

    local selectedJob = nil
    for _, jobDef in ipairs(Config.Prison.PrisonJobs.defaultJobs or {}) do
        if jobDef.id == data.jobId then
            selectedJob = jobDef
            break
        end
    end
    if not selectedJob then
        return
    end

    startPrisonJob(selectedJob)
end)

function cleanupPrisonJobOnRelease(message)
    if not activePrisonJob then
        return
    end

    cleanupActiveJobVisuals()
    activePrisonJob = nil
    ClearPedTasks(cache.ped)

    if minigameResultCallback then
        local callback = minigameResultCallback
        minigameResultCallback = nil
        callback(false)
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisiblePrisonMinigame", data = false })

    if message then
        Bridge.Notify.showNotify(message, "error")
    end
end

RegisterNetEvent("p_policejob/client/prison/release", function()
    cleanupPrisonJobOnRelease()
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cleanupActiveJobVisuals()
    end
end)

exports("openPrisonJobs", function()
    openPrisonJobsUI()
end)
