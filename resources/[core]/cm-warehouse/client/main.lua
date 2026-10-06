-- cm-warehouse/client/main.lua
-- Port Logistics & Warehouse Freight Operations Client Controller.

local Config = CMWarehouse.Config
CMWarehouse = CMWarehouse or {}
CMWarehouse.Client = CMWarehouse.Client or {}

local onShift = false
local truckNetId = nil
local truckPlate = nil
local truckEntity = nil

local currentShift = nil
local currentStageIndex = 1
local isWorking = false
local payrollBlocked = false

local activeBlip = nil
local activePromptOwner = nil

-- ---------------------------------------------------------------------------
-- Public Client State Queries
-- ---------------------------------------------------------------------------

function CMWarehouse.Client.IsOnShift()
    return onShift
end

function CMWarehouse.Client.GetActiveShift()
    return currentShift
end

function CMWarehouse.Client.GetCurrentStage()
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
                name = 'Port Logistics',
                role = 'WAREHOUSE FREIGHT',
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
    if not onShift or not currentShift then
        SendNUIMessage({ action = 'hide' })
        return
    end

    local totalStages = #currentShift.stages
    local isCompleted = currentStageIndex > totalStages
    local stage = not isCompleted and currentShift.stages[currentStageIndex] or nil

    local instruction = 'PROCEED TO WORK STATION'
    local stageLabel = 'Return to Supervisor Office'
    local percent = math.floor(((currentStageIndex - 1) / totalStages) * 100)

    if payrollBlocked then
        instruction = 'PAYOUT STORED IN LEDGER // CANNOT BE COLLECTED IN-GAME'
    elseif isCompleted then
        instruction = 'RETURN TO OFFICE TO SUBMIT FREIGHT MANIFEST'
        stageLabel = 'All Logistics Stages Complete'
        percent = 100
    elseif isWorking then
        instruction = 'PHYSICAL CARGO HANDLING IN PROGRESS...'
        stageLabel = stage and stage.label or 'Active Handling'
    elseif stage then
        instruction = ('EXECUTE: %s'):format(stage.action or 'TASK')
        stageLabel = stage.label or ('Stage ' .. currentStageIndex)
    end

    SendNUIMessage({
        action = 'update',
        onShift = onShift,
        stageIndex = currentStageIndex,
        totalStages = totalStages,
        completed = isCompleted,
        manifestTitle = currentShift.title or 'Municipal Logistics Manifest',
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
    AddTextComponentString(name or 'Logistics Waypoint')
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

        if onShift and currentShift and not isWorking then
            local totalStages = #currentShift.stages
            local isCompleted = currentStageIndex > totalStages
            local targetCoords = nil

            if not isCompleted then
                local stage = currentShift.stages[currentStageIndex]
                if stage then targetCoords = stage.coords end
            else
                targetCoords = Config.Facility.returnBay.coords
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

                    -- Flat cylindrical marker
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

        if onShift and currentShift and not isWorking then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local totalStages = #currentShift.stages
            local isCompleted = currentStageIndex > totalStages

            if not isCompleted then
                local stage = currentShift.stages[currentStageIndex]
                if stage and stage.coords then
                    local dist = #(pCoords - stage.coords)
                    if dist <= (Config.Security.stageInteractDistance or 4.5) then
                        waitMs = 0
                        local promptKey = ('cm-wh:stage_%d'):format(currentStageIndex)
                        showPrompt(promptKey, stage.action or 'EXECUTE TASK')

                        if IsControlJustReleased(0, Config.InteractKey or 38) then
                            hidePrompt(promptKey)
                            TriggerServerEvent('cm-warehouse:server:startStageWork', currentShift.id, currentStageIndex)
                        end
                    else
                        hidePrompt(('cm-wh:stage_%d'):format(currentStageIndex))
                    end
                end
            else
                local returnBay = Config.Facility.returnBay.coords
                local dist = #(pCoords - returnBay)
                if dist <= (Config.Security.depotReturnDistance or 14.0) then
                    waitMs = 0
                    local promptKey = 'cm-wh:return'
                    local label = payrollBlocked
                        and 'RETRY SUBMITTING FREIGHT MANIFEST'
                        or 'SUBMIT FREIGHT MANIFEST & CLEAR SHIFT'
                    showPrompt(promptKey, label)

                    if IsControlJustReleased(0, Config.InteractKey or 38) then
                        hidePrompt(promptKey)
                        TriggerServerEvent('cm-warehouse:server:checkInManifest')
                    end
                else
                    hidePrompt('cm-wh:return')
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

RegisterNetEvent('cm-warehouse:client:shiftStarted', function(data)
    if type(data) ~= 'table' then return end

    onShift = true
    currentShift = data.shift
    currentStageIndex = 1
    truckNetId = data.truckNetId
    truckPlate = data.truckPlate
    isWorking = false
    payrollBlocked = false

    local firstStage = currentShift.stages and currentShift.stages[1]
    if firstStage and firstStage.coords then
        setTrackedBlip(firstStage.coords, firstStage.label, Config.Blip.stage.sprite, Config.Blip.stage.color, true)
    end

    updateHud()
end)

RegisterNetEvent('cm-warehouse:client:stageWorkStarted', function(data)
    if type(data) ~= 'table' then return end

    isWorking = true
    hidePrompt()

    local ped = PlayerPedId()
    local scenario = data.scenario or 'PROP_HUMAN_BUM_BIN'
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

        if onShift and currentShift then
            TriggerServerEvent('cm-warehouse:server:completeStageWork', currentShift.id, data.stageIndex or currentStageIndex)
        end
    end)
end)

RegisterNetEvent('cm-warehouse:client:stageCompleted', function(data)
    if type(data) ~= 'table' then return end

    currentStageIndex = data.nextStageIndex or (currentStageIndex + 1)
    local totalStages = #currentShift.stages

    if currentStageIndex <= totalStages then
        local nextStage = currentShift.stages[currentStageIndex]
        if nextStage and nextStage.coords then
            setTrackedBlip(nextStage.coords, nextStage.label, Config.Blip.stage.sprite, Config.Blip.stage.color, true)
        end
    else
        local returnBay = Config.Facility.returnBay.coords
        setTrackedBlip(returnBay, Config.Blip.depotReturn.name, Config.Blip.depotReturn.sprite, Config.Blip.depotReturn.color, true)
    end

    updateHud()
end)

RegisterNetEvent('cm-warehouse:client:shiftCompleted', function(data)
    onShift = false
    currentShift = nil
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

RegisterNetEvent('cm-warehouse:client:shiftFailed', function(data)
    isWorking = false
    local ped = PlayerPedId()
    ClearPedTasks(ped)

    payrollBlocked = true
    updateHud()
end)

RegisterNetEvent('cm-warehouse:client:shiftEnded', function(reason)
    onShift = false
    currentShift = nil
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

RegisterNetEvent('cm-warehouse:client:notify', function(message, kind)
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

exports('GetActiveShift', function()
    return currentShift
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

