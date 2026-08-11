if not Config or not Config.Prison or not Config.Prison.Enabled then
    return
end

if not Config.Prison.OfficerTasks or not Config.Prison.OfficerTasks.enabled then
    return
end

local activeOfficerTask = nil
local officerTaskBlip = nil
local officerTaskZoneId = nil
local officerTaskMarkerCoords = nil
local officerPatrolIndex = 0

function removeOfficerTaskZone(zoneId)
    if not zoneId then
        return
    end
    if Bridge.Target and Bridge.Target.removeSphereZone then
        pcall(Bridge.Target.removeSphereZone, zoneId)
    end
end

function cleanupOfficerTaskVisuals()
    if officerTaskBlip and DoesBlipExist(officerTaskBlip) then
        RemoveBlip(officerTaskBlip)
    end
    officerTaskBlip = nil
    removeOfficerTaskZone(officerTaskZoneId)
    officerTaskZoneId = nil
    officerTaskMarkerCoords = nil
end

function startOfficerTaskMarkerThread()
    CreateThread(function()
        while activeOfficerTask do
            if officerTaskMarkerCoords then
                local playerCoords = GetEntityCoords(cache.ped)
                if #(playerCoords - officerTaskMarkerCoords) <= 60.0 then
                    local isCellInspection = activeOfficerTask.id == "cell_inspection"
                    DrawMarker(
                        2,
                        officerTaskMarkerCoords.x,
                        officerTaskMarkerCoords.y,
                        officerTaskMarkerCoords.z + (isCellInspection and 1.0 or 1.4),
                        0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                        0.35, 0.35, 0.35,
                        59, 130, 246, 200,
                        true, false, 2, true, nil, nil, false
                    )
                    if not isCellInspection then
                        DrawMarker(
                            1,
                            officerTaskMarkerCoords.x,
                            officerTaskMarkerCoords.y,
                            officerTaskMarkerCoords.z - 0.98,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            2.0, 2.0, 0.5,
                            59, 130, 246, 90,
                            false, false, 2, false, nil, nil, false
                        )
                    end
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

function setOfficerTaskBlip(coords, label)
    cleanupOfficerTaskVisuals()

    officerTaskBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(officerTaskBlip, 280)
    SetBlipColour(officerTaskBlip, 3)
    SetBlipScale(officerTaskBlip, 0.9)
    SetBlipAsShortRange(officerTaskBlip, true)
    SetBlipRoute(officerTaskBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(officerTaskBlip)
end

function playOfficerTaskAnimation(animConfig, duration)
    if not animConfig or not animConfig.dict or not animConfig.clip then
        Wait(duration or 0)
        return
    end

    lib.requestAnimDict(animConfig.dict)
    TaskPlayAnim(
        cache.ped, animConfig.dict, animConfig.clip,
        4.0, -4.0, duration or -1,
        1, 0, false, false, false
    )

    if duration then
        Wait(duration)
        ClearPedTasks(cache.ped)
    end
end

function completeOfficerTask()
    local completedTask = activeOfficerTask
    cleanupOfficerTaskVisuals()
    activeOfficerTask = nil
    officerPatrolIndex = 0
    Bridge.Notify.showNotify(locale("prison_officer_task_done"), "success")
    return completedTask
end

function cancelOfficerTask(silent)
    cleanupOfficerTaskVisuals()
    activeOfficerTask = nil
    officerPatrolIndex = 0
    ClearPedTasks(cache.ped)
    if not silent then
        Bridge.Notify.showNotify(locale("prison_officer_task_cancel"), "info")
    end
end

function advancePatrolRoute(taskDef)
    local waypoints = Prison.Map and Prison.Map.officerPatrolWaypoints
    if not waypoints or #waypoints == 0 then
        Bridge.Notify.showNotify(locale("prison_officer_no_waypoints"), "error")
        cancelOfficerTask(true)
        return
    end

    officerPatrolIndex = officerPatrolIndex + 1
    if officerPatrolIndex > #waypoints then
        completeOfficerTask()
        return
    end

    local waypoint = waypoints[officerPatrolIndex]
    local waypointCoords = vector3(waypoint.x, waypoint.y, waypoint.z)
    local patrolIndex = officerPatrolIndex
    local reached = false

    setOfficerTaskBlip(waypoint, ("Patrol %d/%d"):format(officerPatrolIndex, #waypoints))
    officerTaskMarkerCoords = waypointCoords

    Bridge.Notify.showNotify(locale("prison_officer_patrol_next", officerPatrolIndex, #waypoints), "info")

    officerTaskZoneId = Bridge.Target.addSphereZone({
        coords = waypointCoords,
        radius = 2.0,
        debug = false,
        drawSprite = true,
        options = {
            {
                name = "p_policejob_prison_patrol_" .. GetGameTimer(),
                label = ("Reach point %d/%d"):format(officerPatrolIndex, #waypoints),
                icon = "fa-solid fa-person-walking",
                distance = 2.0,
                onSelect = function()
                    if not activeOfficerTask or reached or patrolIndex ~= officerPatrolIndex then
                        return
                    end
                    if #(GetEntityCoords(cache.ped) - waypointCoords) > 3.0 then
                        return
                    end
                    reached = true
                    removeOfficerTaskZone(officerTaskZoneId)
                    officerTaskZoneId = nil
                    advancePatrolRoute(taskDef)
                end,
            },
        },
    })
end

function startPatrolRouteTask(taskDef)
    officerPatrolIndex = 0
    advancePatrolRoute(taskDef)
end

function startCellInspectionTask(taskDef)
    local cells = Prison.Map and Prison.Map.cells
    if not cells or #cells == 0 then
        Bridge.Notify.showNotify(locale("prison_officer_no_cells"), "error")
        cancelOfficerTask(true)
        return
    end

    local cellsToInspect = math.min(3, #cells)
    local inspectedCount = 0
    local inspecting = false

    function inspectNextCell()
        if not activeOfficerTask then
            return
        end
        if inspectedCount >= cellsToInspect then
            completeOfficerTask()
            return
        end

        local cell = cells[inspectedCount + 1]
        local cellCoords = vector3(cell.coords.x, cell.coords.y, cell.coords.z)
        setOfficerTaskBlip(cellCoords, ("%s %d/%d"):format(taskDef.label, inspectedCount + 1, cellsToInspect))
        officerTaskMarkerCoords = cellCoords

        Bridge.Notify.showNotify(locale("prison_officer_goto_cell", inspectedCount + 1, cellsToInspect), "info")

        officerTaskZoneId = Bridge.Target.addSphereZone({
            coords = cellCoords,
            radius = 1.5,
            debug = false,
            drawSprite = true,
            options = {
                {
                    name = ("p_policejob_prison_inspect_%d"):format(cell.id),
                    label = locale("prison_officer_inspect_cell") .. " " .. (cell.label or tostring(cell.id)),
                    icon = "fa-solid fa-magnifying-glass",
                    distance = 1.8,
                    onSelect = function()
                        if not activeOfficerTask or inspecting then
                            return
                        end
                        inspecting = true

                        local completed = Bridge.Progress.Start({
                            duration = taskDef.duration or 8000,
                            label = locale("prison_officer_inspecting"),
                            useWhileDead = false,
                            canCancel = true,
                            disable = { move = true, car = true, combat = true },
                            anim = taskDef.animation,
                        })

                        inspecting = false
                        if not completed or not activeOfficerTask then
                            return
                        end

                        inspectedCount = inspectedCount + 1
                        removeOfficerTaskZone(officerTaskZoneId)
                        officerTaskZoneId = nil
                        Bridge.Notify.showNotify(locale("prison_officer_cell_inspected", inspectedCount, cellsToInspect), "success")
                        inspectNextCell()
                    end,
                },
            },
        })
    end

    inspectNextCell()
end

function startOfficerTask(taskDef)
    if activeOfficerTask then
        Bridge.Notify.showNotify(locale("prison_officer_active_task"), "error")
        return
    end
    if not Prison:hasJobAccess() then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return
    end

    activeOfficerTask = taskDef
    startOfficerTaskMarkerThread()
    Bridge.Notify.showNotify(locale("prison_officer_task_started", taskDef.label), "info")

    if taskDef.id == "patrol_route" then
        startPatrolRouteTask(taskDef)
    elseif taskDef.id == "cell_inspection" then
        startCellInspectionTask(taskDef)
    else
        playOfficerTaskAnimation(taskDef.animation, taskDef.duration or 5000)
        completeOfficerTask()
    end
end

function Prison.getOfficerTasksForUI(self)
    local tasks = {}
    for _, task in ipairs(Config.Prison.OfficerTasks.tasks or {}) do
        tasks[#tasks + 1] = {
            id = task.id,
            label = task.label,
            description = task.description,
        }
    end
    return tasks
end

function Prison.getActiveOfficerTaskId(self)
    return activeOfficerTask and activeOfficerTask.id or nil
end

function Prison.startOfficerTaskById(self, taskId)
    for _, task in ipairs(Config.Prison.OfficerTasks.tasks or {}) do
        if task.id == taskId then
            startOfficerTask(task)
            return true
        end
    end
    return false
end

function Prison.cancelOfficerTask(self)
    if not activeOfficerTask then
        return
    end
    cancelOfficerTask()
end

function Prison.openOfficerTasks(self)
    if not self:hasJobAccess() then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return
    end
    self:openManagement()
    SendNUIMessage({ action = "setPrisonManagementTab", data = "tasks" })
end

RegisterCommand("prisontasks", function()
    Prison:openOfficerTasks()
end, false)

RegisterNetEvent("p_policejob/client/prison/openOfficerTasks", function()
    Prison:openOfficerTasks()
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cleanupOfficerTaskVisuals()
    end
end)

exports("openPrisonOfficerTasks", function()
    Prison:openOfficerTasks()
end)
