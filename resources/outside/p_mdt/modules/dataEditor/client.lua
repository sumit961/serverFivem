DataEditor = {
    setup = false,
}

function DataEditor.open(self)
    local job = Bridge.Framework.fetchPlayerJob()

    if not job or not Config.Departments[job.name] then
        return Bridge.Notify.showNotify(locale("no_permission"), "error")
    end

    if not lib.table.contains(Config.Departments[job.name].bossGrades, job.grade) then
        return Bridge.Notify.showNotify(locale("no_permission"), "error")
    end

    local vehiclesData = lib.load("data.vehicles")
    local garagesData = lib.load("data.garages")

    SendNUIMessage({ action = "setVisibleDataEditor", data = true })
    SendNUIMessage({
        action = "dataEditor/loadData",
        data = {
            Vehicles = vehiclesData[job.name] or {},
            Garages = garagesData[job.name] or {},
        },
    })
    SetNuiFocus(true, true)
end

RegisterCommand("mdt:editconfig", function()
    DataEditor:open()
end)

RegisterNUICallback("dataEditor/setupCoords", function(data, cb)
    if DataEditor.setup then
        return
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setTempVisibleDataEditor", data = false })
    DataEditor.setup = true

    local targetCoords = nil
    local model = lib.requestModel("mp_m_freemode_01")
    local spawnCoords = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 1.0, 0.1)
    local previewPed = CreatePed(4, model, spawnCoords, 0.0, false, true)

    SetEntityAlpha(previewPed, 200)
    FreezeEntityPosition(previewPed, true)
    SetEntityInvincible(previewPed, true)
    SetEntityCollision(previewPed, false, false)
    SetBlockingOfNonTemporaryEvents(previewPed, true)

    CreateThread(function()
        while DataEditor.setup do
            Wait(0)
            local hit, _, coords = lib.raycast.fromCamera(511, 4, 15.0)
            if hit and hit ~= 0 then
                targetCoords = coords
            end
        end
    end)

    while DataEditor.setup do
        Wait(0)
        DisableControlAction(0, 24, true)

        if targetCoords then
            SetEntityCoordsNoOffset(
                previewPed,
                targetCoords.x,
                targetCoords.y,
                targetCoords.z + 1.0,
                true,
                true,
                true
            )

            DrawMarker(
                28,
                targetCoords.x, targetCoords.y, targetCoords.z,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                0.4, 0.4, 0.4,
                255, 0, 0, 150,
                false, false, false, false
            )

            if IsControlPressed(0, 24) or IsDisabledControlPressed(0, 24) then
                DataEditor.setup = false
                SetNuiFocus(true, true)
                SendNUIMessage({ action = "setTempVisibleDataEditor", data = true })
                cb({
                    x = targetCoords.x,
                    y = targetCoords.y,
                    z = targetCoords.z + 1.0,
                    w = GetEntityHeading(previewPed),
                })
                DeletePed(previewPed)
                return
            end

            if IsControlPressed(0, 174) or IsDisabledControlPressed(0, 174) then
                SetEntityHeading(previewPed, GetEntityHeading(previewPed) + 1.0)
            end

            if IsControlPressed(0, 175) or IsDisabledControlPressed(0, 175) then
                SetEntityHeading(previewPed, GetEntityHeading(previewPed) - 1.0)
            end

            if IsControlPressed(0, 73) then
                DeletePed(previewPed)
                DataEditor.setup = false
                cb(nil)
                SetNuiFocus(true, true)
                SendNUIMessage({ action = "setTempVisibleDataEditor", data = true })
                return
            end
        end
    end
end)

RegisterNUICallback("dataEditor/save", function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisibleDataEditor", data = false })
    TriggerServerEvent("p_mdt/server/dataEditor/save", data)
    cb(1)
end)

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleDataEditor" then
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "setVisibleDataEditor", data = false })
    end
    cb(1)
end)
