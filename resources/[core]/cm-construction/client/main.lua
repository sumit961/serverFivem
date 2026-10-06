-- cm-construction/client/main.lua
-- Municipal Construction & Heavy Infrastructure Client Controller.

local Config = CMConstruction.Config
CMConstruction = CMConstruction or {}
CMConstruction.Client = CMConstruction.Client or {}

local onShift = false
local truckNetId = nil
local truckPlate = nil
local truckEntity = nil

local currentTask = nil
local currentStageIndex = 1
local isWorking = false
local payrollBlocked = false

local activeBlip = nil
local activePromptOwner = nil

-- ---------------------------------------------------------------------------
-- Public Client State Queries
-- ---------------------------------------------------------------------------

function CMConstruction.Client.IsOnShift()
    return onShift
end

function CMConstruction.Client.GetActiveTask()
    return currentTask
end

function CMConstruction.Client.GetCurrentStage()
    return currentStageIndex
end

-- ---------------------------------------------------------------------------
-- UI Helpers (cm-ui and NUI HUD)
-- ---------------------------------------------------------------------------

local function showPrompt(owner, label)
    if activePromptOwner == owner then return end
    if activePromptOwner and GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract(activePromptOwner) end)
    end

    activePromptOwner = owner
    if GetResourceState('cm-ui') == 'started' then
        pcall(function()
            exports['cm-ui']:ShowInteract({
                owner = owner,
                priority = 10,
                key = Config.InteractKeyLabel or 'E',
                label = label,
                name = 'Municipal Works',
                role = 'INFRASTRUCTURE',
            })
        end)
    end
end

local function hidePrompt(owner)
    if activePromptOwner == owner or (not owner and activePromptOwner) then
        local toHide = owner or activePromptOwner
        if GetResourceState('cm-ui') == 'started' then
            pcall(function() exports['cm-ui']:HideInteract(toHide) end)
        end
        activePromptOwner = nil
    end
end

local function updateHud()
    if not onShift or not currentTask then
        SendNUIMessage({ action = 'hide' })
        return
    end

    local totalStages = #currentTask.stages
    local isCompleted = currentStageIndex > totalStages
    local stage = not isCompleted and currentTask.stages[currentStageIndex] or nil

    local instruction = 'PROCEED TO WORK STAGE LOCATION'
    local stageLabel = 'Return to Downtown HQ'
    local percent = math.floor(((currentStageIndex - 1) / totalStages) * 100)

    if payrollBlocked then
        instruction = 'PAYOUT STORED IN LEDGER // CANNOT BE COLLECTED IN-GAME'
    elseif isCompleted then
        instruction = 'RETURN TO SITE OFFICE TO SUBMIT INSPECTION MANIFEST'
        stageLabel = 'All Physical Stages Verified'
        percent = 100
    elseif isWorking then
        instruction = 'EXECUTING PHYSICAL STAGE WORK...'
        stageLabel = stage and stage.label or 'Active Construction'
    elseif stage then
        instruction = ('EXECUTE: %s'):format(stage.action or 'STAGE WORK')
        stageLabel = stage.label or ('Stage ' .. currentStageIndex)
    end

    SendNUIMessage({
        action = 'update',
        onShift = onShift,
        stageIndex = currentStageIndex,
        totalStages = totalStages,
        completed = isCompleted,
        taskTitle = currentTask.title or 'Municipal Infrastructure Project',
        stageLabel = stageLabel,
        percent = percent,
        instruction = instruction,
    })
end

-- ---------------------------------------------------------------------------
-- Blip & Waypoint Management
-- ---------------------------------------------------------------------------

local function clearTrackedBlip()
    if activeBlip and DoesBlipExist(activeBlip) then
        RemoveBlip(activeBlip)
    end
    activeBlip = nil
end

local function setTrackedBlip(coords, name, sprite, color, setWaypoint)
    clearTrackedBlip()
    if not coords then return end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 1)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.80)
    SetBlipColour(blip, color or 5)
    SetBlipAsShortRange(blip, false)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, color or 5)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(name or 'Construction Waypoint')
    EndTextCommandSetBlipName(blip)

    activeBlip = blip

    if setWaypoint then
        SetNewWaypoint(coords.x, coords.y)
    end
end

-- ---------------------------------------------------------------------------
-- 3D Marker Thread (CM Cyan theme: #00e5ff)
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local waitMs = 800

        if onShift and currentTask and not isWorking then
            local totalStages = #currentTask.stages
            local isCompleted = currentStageIndex > totalStages
            local targetCoords = nil

            if not isCompleted then
                local stage = currentTask.stages[currentStageIndex]
                if stage then targetCoords = stage.coords end
            else
                targetCoords = Config.Depot.returnBay.coords
            end

            if targetCoords then
                local ped = PlayerPedId()
                local pCoords = GetEntityCoords(ped)
                local dist = #(pCoords - targetCoords)

                if dist < 100.0 then
                    waitMs = 0
                    local r = Config.Beacon.color.r or 0
                    local g = Config.Beacon.color.g or 229
                    local b = Config.Beacon.color.b or 255

                    -- Cylindrical ground marker
                    DrawMarker(1, targetCoords.x, targetCoords.y, targetCoords.z - 1.0,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        3.5, 3.5, 0.8,
                        r, g, b, 60,
                        false, false, 2, false, nil, nil, false)

                    -- Inner cyan beacon ring
                    DrawMarker(27, targetCoords.x, targetCoords.y, targetCoords.z + 0.1,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        2.8, 2.8, 0.8,
                        r, g, b, 130,
                        false, false, 2, false, nil, nil, false)
                end
            end
        end

        Wait(waitMs)
    end
end)

-- ---------------------------------------------------------------------------
-- Proximity and Interaction Loop
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local waitMs = 500

        if onShift and currentTask and not isWorking then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local totalStages = #currentTask.stages
            local isCompleted = currentStageIndex > totalStages

            if not isCompleted then
                local stage = currentTask.stages[currentStageIndex]
                if stage and stage.coords then
                    local dist = #(pCoords - stage.coords)
                    if dist <= (Config.Security.stageInteractDistance or 4.5) then
                        waitMs = 0
                        local promptKey = ('cm-const:stage_%d'):format(currentStageIndex)
                        showPrompt(promptKey, stage.action or 'EXECUTE STAGE WORK')

                        if IsControlJustReleased(0, Config.InteractKey or 38) then
                            hidePrompt(promptKey)
                            TriggerServerEvent('cm-construction:server:startStageWork', currentTask.id, currentStageIndex)
                        end
                    else
                        hidePrompt(('cm-const:stage_%d'):format(currentStageIndex))
                    end
                end
            else
                local returnBay = Config.Depot.returnBay.coords
                local dist = #(pCoords - returnBay)
                if dist <= (Config.Security.depotReturnDistance or 14.0) then
                    waitMs = 0
                    local promptKey = 'cm-const:return'
                    local label = payrollBlocked
                        and 'RETRY SUBMITTING INSPECTION MANIFEST'
                        or 'SUBMIT INSPECTION MANIFEST & SIGN OFFS'
                    showPrompt(promptKey, label)

                    if IsControlJustReleased(0, Config.InteractKey or 38) then
                        hidePrompt(promptKey)
                        TriggerServerEvent('cm-construction:server:checkInManifest')
                    end
                else
                    hidePrompt('cm-const:return')
                end
            end
        else
            hidePrompt()
        end

        Wait(waitMs)
    end
end)

-- ---------------------------------------------------------------------------
-- Net Events from Server
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-construction:client:taskStarted', function(data)
    if type(data) ~= 'table' then return end

    onShift = true
    currentTask = data.task
    currentStageIndex = 1
    truckNetId = data.truckNetId
    truckPlate = data.truckPlate
    isWorking = false
    payrollBlocked = false

    local firstStage = currentTask.stages and currentTask.stages[1]
    if firstStage and firstStage.coords then
        setTrackedBlip(firstStage.coords, firstStage.label, Config.Blip.stage.sprite, Config.Blip.stage.color, true)
    end

    updateHud()
end)

RegisterNetEvent('cm-construction:client:stageWorkStarted', function(data)
    if type(data) ~= 'table' then return end

    isWorking = true
    hidePrompt()

    local ped = PlayerPedId()
    local scenario = data.scenario or 'WORLD_HUMAN_HAMMERING'
    local durationMs = data.durationMs or 6000

    TaskStartScenarioInPlace(ped, scenario, 0, true)

    SendNUIMessage({
        action = 'stage_progress',
        durationMs = durationMs,
    })

    updateHud()

    SetTimeout(durationMs, function()
        ClearPedTasks(ped)
        isWorking = false

        if onShift and currentTask then
            TriggerServerEvent('cm-construction:server:completeStageWork', currentTask.id, data.stageIndex or currentStageIndex)
        end
    end)
end)

RegisterNetEvent('cm-construction:client:stageCompleted', function(data)
    if type(data) ~= 'table' then return end

    currentStageIndex = data.nextStageIndex or (currentStageIndex + 1)
    local totalStages = #currentTask.stages

    if currentStageIndex <= totalStages then
        local nextStage = currentTask.stages[currentStageIndex]
        if nextStage and nextStage.coords then
            setTrackedBlip(nextStage.coords, nextStage.label, Config.Blip.stage.sprite, Config.Blip.stage.color, true)
        end
    else
        local returnBay = Config.Depot.returnBay.coords
        setTrackedBlip(returnBay, Config.Blip.depotReturn.name, Config.Blip.depotReturn.sprite, Config.Blip.depotReturn.color, true)
    end

    updateHud()
end)

RegisterNetEvent('cm-construction:client:taskCompleted', function(data)
    onShift = false
    currentTask = nil
    currentStageIndex = 1
    truckNetId = nil
    truckPlate = nil
    truckEntity = nil
    isWorking = false
    payrollBlocked = false

    hidePrompt()
    clearTrackedBlip()
    updateHud()
end)

RegisterNetEvent('cm-construction:client:taskFailed', function(data)
    isWorking = false
    local ped = PlayerPedId()
    ClearPedTasks(ped)

    payrollBlocked = true
    updateHud()
end)

RegisterNetEvent('cm-construction:client:shiftEnded', function(reason)
    onShift = false
    currentTask = nil
    currentStageIndex = 1
    truckNetId = nil
    truckPlate = nil
    truckEntity = nil
    isWorking = false
    payrollBlocked = false

    hidePrompt()
    clearTrackedBlip()
    updateHud()
end)

RegisterNetEvent('cm-construction:client:notify', function(message, kind)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message or '')
    EndTextCommandThefeedPostTicker(false, true)
end)

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

exports('IsOnShift', function()
    return onShift
end)

exports('GetActiveTask', function()
    return currentTask
end)

exports('GetCurrentStage', function()
    return currentStageIndex
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    hidePrompt()
    clearTrackedBlip()
    SendNUIMessage({ action = 'hide' })
end)

