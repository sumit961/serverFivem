while not Config or not Config.Creator do
    Citizen.Wait(1000)
end

if not Config.Creator.enabled then
    return
end

local activePanel = nil
local placementActive = false
local placementCooldown = 0

function roundCoord(value)
    return math.floor(value * 10000 + 0.5) / 10000
end

function openCreatorPanel(panelName)
    if activePanel then
        return
    end
    local canAccess = lib.callback.await("p_policejob/server/creator/canAccess", false)
    if not canAccess then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    activePanel = panelName
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "setVisible" .. panelName,
        data = true,
    })
end

RegisterCommand(Config.Creator.commands.department, function()
    openCreatorPanel("DepartmentCreator")
end, false)

RegisterCommand(Config.Creator.commands.prison, function()
    openCreatorPanel("PrisonCreator")
end, false)

function getRaycastCoords()
    local _, _, coords = lib.raycast.fromCamera(17, 4, 100.0)
    return coords
end

function runPlacement(fields, panelName)
    if placementActive or GetGameTimer() < placementCooldown then
        return
    end
    placementActive = true
    local hasHeading = false
    for _, field in ipairs(fields) do
        if field == "h" then
            hasHeading = true
            break
        end
    end
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "setVisible" .. panelName,
        data = false,
    })
    SendNUIMessage({
        action = "creatorPlacement",
        data = {
            visible = true,
            hasHeading = hasHeading,
            mode = hasHeading and "ped" or "marker",
        },
    })
    local startCoords = GetEntityCoords(cache.ped)
    local previewPed = nil
    local heading = 0.0
    if hasHeading then
        local model = lib.requestModel(Config.Creator.previewPed)
        previewPed = CreatePed(26, model, startCoords.x, startCoords.y, startCoords.z, 0.0, false, false)
        SetModelAsNoLongerNeeded(model)
        SetEntityAlpha(previewPed, 200, false)
        SetEntityCollision(previewPed, false, false)
        SetEntityInvincible(previewPed, true)
        FreezeEntityPosition(previewPed, true)
        SetBlockingOfNonTemporaryEvents(previewPed, true)
    end
    local currentCoords = startCoords
    local controlsReleased = false
    local confirmed = false
    CreateThread(function()
        while placementActive do
            Wait(0)
            if hasHeading then
                DrawMarker(28, currentCoords.x, currentCoords.y, currentCoords.z - 0.98, 0, 0, 0, 0, 0, 0, 0.4, 0.4, 0.4, 0, 150, 255, 150, false, false, false, false)
            else
                DrawMarker(28, currentCoords.x, currentCoords.y, currentCoords.z, 0, 0, 0, 0, 0, 0, 0.4, 0.4, 0.4, 255, 0, 0, 150, false, false, false, false)
            end
        end
    end)
    while placementActive do
        Wait(0)
        local hitCoords = getRaycastCoords()
        if hitCoords then
            currentCoords = hitCoords
            if previewPed then
                SetEntityCoords(previewPed, hitCoords.x, hitCoords.y, hitCoords.z, false, false, false, false)
            end
        end
        if hasHeading then
            if IsControlPressed(0, 174) then
                heading = (heading + 1.0) % 360.0
            end
            if IsControlPressed(0, 175) then
                heading = (heading - 1.0 + 360.0) % 360.0
            end
            if IsControlPressed(0, 27) then
                heading = (heading + 0.1) % 360.0
            end
            if IsControlPressed(0, 173) then
                heading = (heading - 0.1 + 360.0) % 360.0
            end
            SetEntityHeading(previewPed, heading)
        end
        if not controlsReleased then
            if not IsControlPressed(0, 191) and not IsControlPressed(0, 194) then
                controlsReleased = true
            end
        else
            if IsControlJustPressed(0, 191) then
                confirmed = true
                placementActive = false
            elseif IsControlJustPressed(0, 194) then
                confirmed = false
                placementActive = false
            end
        end
    end
    if previewPed and DoesEntityExist(previewPed) then
        DeleteEntity(previewPed)
    end
    SendNUIMessage({
        action = "creatorPlacement",
        data = { visible = false },
    })
    Wait(350)
    SendNUIMessage({
        action = "setVisible" .. panelName,
        data = true,
    })
    SetNuiFocus(true, true)
    placementCooldown = GetGameTimer() + 1000
    if confirmed then
        local values = {}
        for _, field in ipairs(fields) do
            if field == "x" then
                values[#values + 1] = roundCoord(currentCoords.x)
            elseif field == "y" then
                values[#values + 1] = roundCoord(currentCoords.y)
            elseif field == "z" then
                values[#values + 1] = roundCoord(currentCoords.z + 1.0)
            elseif field == "h" then
                values[#values + 1] = roundCoord(heading)
            end
        end
        SendNUIMessage({
            action = "creatorCoordsResult",
            data = { values = values },
        })
    end
end

RegisterNUICallback("creatorGetCoords", function(data, cb)
    cb(json.encode({ ok = true }))
    local panelName = data.panel or "DepartmentCreator"
    CreateThread(function()
        runPlacement(data.fields or { "x", "y", "z" }, panelName)
    end)
end)

RegisterNUICallback("creatorCopyCode", function(data, cb)
    if data and data.content then
        lib.setClipboard(data.content)
        Bridge.Notify.showNotify(locale("creator_copied") or "Copied to clipboard", "success")
    end
    cb("ok")
end)

RegisterNUICallback("hideFrame", function(data, cb)
    cb("ok")
    if not data or not data.name then
        return
    end
    if data.name:find("DepartmentCreator") or data.name:find("PrisonCreator") then
        if placementActive then
            return
        end
        activePanel = nil
        SetNuiFocus(false, false)
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    placementActive = false
    if activePanel then
        SetNuiFocus(false, false)
        activePanel = nil
    end
end)
