while not Config do
    Citizen.Wait(1)
end

function getTargetDebug()
    return Bridge and Bridge.Config and Bridge.Config.Debug
end

function validateTable(value, errorMessage)
    if type(value) ~= "table" then
        lib.print.error(errorMessage, type(value))
        return false
    end
    return true
end

function loadDepartmentMaps()
    local maps = {}

    if type(Config.DepartmentMap) == "string" then
        table.insert(maps, {
            name = Config.DepartmentMap,
            data = lib.load(("maps.departments.%s"):format(Config.DepartmentMap)),
        })
    elseif type(Config.DepartmentMap) == "table" then
        for _, mapName in ipairs(Config.DepartmentMap) do
            table.insert(maps, {
                name = mapName,
                data = lib.load(("maps.departments.%s"):format(mapName)),
            })
        end
    end

    return maps
end

function spawnDepartmentPed(coords, pedConfig, useDefaultHeading)
    local model = lib.requestModel(pedConfig.model)
    local heading = coords.w
    if useDefaultHeading and not heading then
        heading = 0.0
    end

    local ped = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, heading, false, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    if pedConfig.scenario then
        TaskStartScenarioInPlace(ped, pedConfig.scenario, 0, true)
    elseif pedConfig.anim then
        local animDict = pedConfig.anim.dict
        local animName = pedConfig.anim.name
        lib.requestAnimDict(animDict)
        TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false)
        RemoveAnimDict(animDict)
    end

    if pedConfig.onCreate and type(pedConfig.onCreate) == "function" then
        pedConfig.onCreate(ped)
    end

    return ped
end

function setupDepartmentBlips(mapData)
    if not mapData.blips then
        return true
    end

    if not validateTable(mapData.blips, "Invalid blips data. Expected a table, got %s") then
        return false
    end

    for _, blipData in ipairs(mapData.blips) do
        if not validateTable(blipData, "Invalid blip data. Expected a table, got %s") then
            return false
        end

        local blip = AddBlipForCoord(blipData.coords.x, blipData.coords.y, blipData.coords.z)
        SetBlipSprite(blip, blipData.sprite)
        SetBlipColour(blip, blipData.color)
        SetBlipScale(blip, blipData.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(blipData.label)
        EndTextCommandSetBlipName(blip)
    end

    return true
end

function setupDepartmentTrashes(mapName, mapData)
    if not mapData.trashes then
        return true
    end

    if not validateTable(mapData.trashes, "Invalid trashes data. Expected a table, got %s") then
        return false
    end

    for trashIndex, trashData in ipairs(mapData.trashes) do
        if not validateTable(trashData, "Invalid trash data. Expected a table, got %s") then
            return false
        end

        local trashId = ("%s_%d"):format(mapName, trashIndex)
        Bridge.Target.addSphereZone({
            coords = vec3(trashData.coords.x, trashData.coords.y, trashData.coords.z),
            radius = trashData.radius or 1.0,
            drawSprite = true,
            debug = getTargetDebug(),
            options = {
                {
                    name = "open_trash_" .. trashId,
                    label = locale("open_trash"),
                    icon = "fa-solid fa-dumpster",
                    distance = trashData.distance or 2.0,
                    groups = Config.Jobs,
                    onSelect = function()
                        exports[GetCurrentResourceName()]:openTrash(trashId)
                    end,
                },
                {
                    name = "clear_trash_" .. trashId,
                    label = locale("clear_trash"),
                    icon = "fa-solid fa-trash-can",
                    distance = trashData.distance or 2.0,
                    groups = Config.Jobs,
                    onSelect = function()
                        exports[GetCurrentResourceName()]:clearTrash(trashId)
                    end,
                },
            },
        })
    end

    return true
end

function setupDepartmentLockers(mapName, mapData)
    if not mapData.lockers then
        return true
    end

    if not validateTable(mapData.lockers, "Invalid lockers data. Expected a table, got %s") then
        return false
    end

    for lockerIndex, lockerData in ipairs(mapData.lockers) do
        if not validateTable(lockerData, "Invalid locker data. Expected a table, got %s") then
            return false
        end

        Bridge.Target.addSphereZone({
            coords = vec3(lockerData.coords.x, lockerData.coords.y, lockerData.coords.z),
            radius = lockerData.radius or 1.0,
            drawSprite = true,
            debug = getTargetDebug(),
            options = {
                {
                    name = ("open_locker_%s_%d"):format(mapName, lockerIndex),
                    label = locale("open_locker"),
                    icon = "fa-solid fa-vault",
                    distance = lockerData.distance or 2.0,
                    groups = Config.Jobs,
                    onSelect = function()
                        exports[GetCurrentResourceName()]:openLockerWithInput()
                    end,
                },
            },
        })
    end

    return true
end

function setupDepartmentCctv(mapName, mapData)
    if not mapData.cctv then
        return true
    end

    if not validateTable(mapData.cctv, "Invalid cctv data. Expected a table, got %s") then
        return false
    end

    for cctvIndex, cctvData in ipairs(mapData.cctv) do
        if not validateTable(cctvData, "Invalid cctv data. Expected a table, got %s") then
            return false
        end

        Bridge.Target.addSphereZone({
            coords = vec3(cctvData.coords.x, cctvData.coords.y, cctvData.coords.z),
            radius = cctvData.radius or 1.0,
            drawSprite = true,
            debug = getTargetDebug(),
            options = {
                {
                    name = ("open_cctv_%s_%d"):format(mapName, cctvIndex),
                    label = cctvData.label or locale("watch_cameras"),
                    icon = "fa-solid fa-video",
                    distance = cctvData.distance or 2.0,
                    groups = Config.Jobs,
                    onSelect = function()
                        exports[GetCurrentResourceName()]:cctvMenu()
                    end,
                },
            },
        })
    end

    return true
end

function canGoOnDuty()
    return not Bridge.Framework.CheckJobDuty() or Bridge.Framework.CheckJobDuty()
end

function canGoOffDuty()
    if Bridge.Framework.CheckJobDuty then
        if Bridge.Framework.CheckJobDuty() then
            return true
        end
    end
    return false
end

function setupDepartmentDuty(mapName, mapData)
    if not mapData.duty then
        return true
    end

    if not validateTable(mapData.duty, "Invalid duty data. Expected a table, got %s") then
        return false
    end

    for dutyIndex, dutyData in ipairs(mapData.duty) do
        if not validateTable(dutyData, "Invalid duty data. Expected a table, got %s") then
            return false
        end

        local dutyId = ("%s_%d"):format(mapName, dutyIndex)
        local dutyOptions = {
            {
                name = "go_on_duty_" .. dutyId,
                label = locale("go_on_duty"),
                icon = "fa-solid fa-clipboard-check",
                distance = dutyData.distance or 2.0,
                groups = Config.Jobs,
                canInteract = canGoOnDuty,
                onSelect = function()
                    TriggerServerEvent("p_policejob/server/toggleDuty")
                end,
            },
            {
                name = "go_off_duty_" .. dutyId,
                label = locale("go_off_duty"),
                icon = "fa-solid fa-clipboard",
                distance = dutyData.distance or 2.0,
                groups = Config.Jobs,
                canInteract = canGoOffDuty,
                onSelect = function()
                    TriggerServerEvent("p_policejob/server/toggleDuty")
                end,
            },
        }

        if dutyData.ped then
            local dutyPoint = lib.points.new({
                coords = vec3(dutyData.coords.x, dutyData.coords.y, dutyData.coords.z),
                distance = 20,
            })

            function dutyPoint.onEnter(point)
                local ped = spawnDepartmentPed(dutyData.coords, dutyData.ped, true)
                Bridge.Target.addLocalEntity(ped, dutyOptions)
                point.ped = ped
            end

            function dutyPoint.onExit(point)
                if point.ped then
                    Bridge.Target.removeLocalEntity(point.ped, {
                        "go_on_duty_" .. dutyId,
                        "go_off_duty_" .. dutyId,
                    })
                    DeleteEntity(point.ped)
                    point.ped = nil
                end
            end
        else
            Bridge.Target.addSphereZone({
                coords = vec3(dutyData.coords.x, dutyData.coords.y, dutyData.coords.z),
                radius = dutyData.radius or 1.0,
                drawSprite = true,
                debug = getTargetDebug(),
                options = dutyOptions,
            })
        end
    end

    return true
end

function setupDepartmentArmouries(mapName, mapData)
    if not mapData.armouries then
        return true
    end

    if not validateTable(mapData.armouries, "Invalid armouries data. Expected a table, got %s") then
        return false
    end

    for armouryIndex, armouryData in ipairs(mapData.armouries) do
        local armouryId = ("%s:%d"):format(mapName, armouryIndex)
        local armouryPoint = lib.points.new({
            coords = vec3(armouryData.coords.x, armouryData.coords.y, armouryData.coords.z),
            distance = 20,
        })

        function armouryPoint.onEnter(point)
            local ped = spawnDepartmentPed(armouryData.coords, armouryData.ped, false)
            Bridge.Target.addLocalEntity(ped, {
                {
                    name = "open_armoury_" .. armouryId,
                    label = locale("open_armoury"),
                    icon = "fa-solid fa-cart-shopping",
                    groups = Config.Jobs,
                    onSelect = function()
                        Armoury:open(armouryId)
                    end,
                },
                {
                    name = "manage_armoury_" .. armouryId,
                    label = locale("manage_armoury"),
                    icon = "fa-solid fa-gear",
                    groups = Config.Jobs,
                    canInteract = function()
                        return Armoury:canManage()
                    end,
                    onSelect = function()
                        Armoury:openManage(armouryId)
                    end,
                },
            })
            point.ped = ped
        end

        function armouryPoint.onExit(point)
            if point.ped then
                Bridge.Target.removeLocalEntity(point.ped, {
                    "open_armoury",
                    "manage_armoury",
                })
                DeleteEntity(point.ped)
                point.ped = nil
            end
        end
    end

    return true
end

function setupDepartmentMap(mapName, mapData)
    if not validateTable(mapData, "Invalid department map data. Expected a table, got %s") then
        return false
    end

    if not setupDepartmentBlips(mapData) then
        return false
    end

    if not setupDepartmentTrashes(mapName, mapData) then
        return false
    end

    if not setupDepartmentLockers(mapName, mapData) then
        return false
    end

    if not setupDepartmentCctv(mapName, mapData) then
        return false
    end

    if not setupDepartmentDuty(mapName, mapData) then
        return false
    end

    if not setupDepartmentArmouries(mapName, mapData) then
        return false
    end

    return true
end

CreateThread(function()
    local departmentMaps = loadDepartmentMaps()
    if #departmentMaps < 1 then
        return
    end

    for _, departmentMap in ipairs(departmentMaps) do
        if not setupDepartmentMap(departmentMap.name, departmentMap.data) then
            return
        end
    end
end)
