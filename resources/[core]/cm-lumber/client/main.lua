-- cm-lumber/client/main.lua
-- Paleto Forest Timber Harvesting & Sawmill Physical Gameplay Client Controller.

local Config = CMLumber.Config
CMLumber = CMLumber or {}
CMLumber.Client = CMLumber.Client or {}

local onShift = false
local haulLogs = 0
local haulTimber = 0
local logsHarvested = 0
local timberProcessed = 0
local isFelling = false
local isProcessing = false

local activePromptOwner = nil
local nodeCooldowns = {} -- [nodeId] = gameTimerExpiry
local hatchetProp = nil

-- ---------------------------------------------------------------------------
-- Public Client State Queries
-- ---------------------------------------------------------------------------

function CMLumber.Client.IsOnShift()
    return onShift
end

function CMLumber.Client.GetHaulStatus()
    return {
        logs = haulLogs,
        timber = haulTimber,
        harvested = logsHarvested,
        processed = timberProcessed,
        maxLogs = Config.Harvesting.maxHaulLogCapacity,
    }
end

exports('IsOnShift', CMLumber.Client.IsOnShift)
exports('GetHaulStatus', CMLumber.Client.GetHaulStatus)

-- ---------------------------------------------------------------------------
-- UI Prompt Management (cm-ui & NUI HUD)
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
                key = 'E',
                label = label,
                name = 'Paleto Forest Sawmill',
                role = 'TIMBER OPERATIONS',
            })
        end)
    end
end

local function clearPrompt(owner)
    if owner and activePromptOwner ~= owner then return end
    if activePromptOwner and GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract(activePromptOwner) end)
    end
    activePromptOwner = nil
end

local function updateNuiHud(visible, objectiveText)
    SendNUIMessage({
        action = 'cmLumber:updateHud',
        data = {
            visible = visible,
            onShift = onShift,
            haulLogs = haulLogs,
            maxHaulLogs = Config.Harvesting.maxHaulLogCapacity,
            haulTimber = haulTimber,
            logsHarvested = logsHarvested,
            timberProcessed = timberProcessed,
            objective = objectiveText or (haulLogs >= Config.Harvesting.maxHaulLogCapacity and 'HAUL FULL (20/20 LOGS) - RETURN TO SAWMILL FOREMAN' or 'FELL MARKED TIMBER STANDS IN PALETO FOREST'),
        }
    })
end

-- ---------------------------------------------------------------------------
-- Server State Synchronization
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-lumber:client:syncState', function(data)
    if not data or not data.onShift then
        onShift = false
        haulLogs = 0
        haulTimber = 0
        logsHarvested = 0
        timberProcessed = 0
        isFelling = false
        isProcessing = false
        clearPrompt()
        updateNuiHud(false)
        return
    end

    onShift = true
    haulLogs = data.haulLogs or 0
    haulTimber = data.haulTimber or 0
    logsHarvested = data.logsHarvested or 0
    timberProcessed = data.timberProcessed or 0
    updateNuiHud(true)
end)

RegisterNetEvent('cm-lumber:client:updateNodeCooldown', function(nodeId, expiry)
    nodeCooldowns[nodeId] = expiry
end)

RegisterNetEvent('cm-lumber:client:notify', function(message, kind)
    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:Notify(message, kind or 'info') end)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(message)
        EndTextCommandThefeedPostTicker(false, true)
    end
end)

-- ---------------------------------------------------------------------------
-- Physical Felling Gameplay (Hatchet Prop & Animation)
-- ---------------------------------------------------------------------------

local function cleanupHatchet()
    if hatchetProp and DoesEntityExist(hatchetProp) then
        DetachEntity(hatchetProp, true, true)
        DeleteEntity(hatchetProp)
        hatchetProp = nil
    end
end

RegisterNetEvent('cm-lumber:client:startFellingApproved', function(payload)
    if not payload or not payload.nodeId then return end
    local nodeId = payload.nodeId
    local durationMs = payload.durationMs or Config.Harvesting.durationMs

    local playerPed = PlayerPedId()
    if not DoesEntityExist(playerPed) or IsEntityDead(playerPed) then return end

    isFelling = true
    clearPrompt()
    updateNuiHud(true, 'FELLING MARKED TIMBER STAND...')

    -- Load animation dictionary
    local animDict = Config.Harvesting.animDict
    RequestAnimDict(animDict)
    local animTimeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(animDict) and GetGameTimer() < animTimeout do
        Wait(50)
    end

    -- Spawn and attach hatchet prop
    local model = Config.Harvesting.hatchetProp
    RequestModel(model)
    local propTimeout = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < propTimeout do
        Wait(50)
    end

    cleanupHatchet()
    local coords = GetEntityCoords(playerPed)
    hatchetProp = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
    SetModelAsNoLongerNeeded(model)

    -- Attach to Right Hand (Bone 57005: SKEL_R_Hand)
    local boneIdx = GetPedBoneIndex(playerPed, 57005)
    AttachEntityToEntity(
        hatchetProp, playerPed, boneIdx,
        0.08, -0.05, -0.02,
        -80.0, 0.0, 0.0,
        true, true, false, true, 1, true
    )

    -- Action progress loop
    local startTime = GetGameTimer()
    local endTime = startTime + durationMs

    TaskPlayAnim(playerPed, animDict, Config.Harvesting.animName, 3.0, 3.0, -1, 1, 0, false, false, false)

    while isFelling and GetGameTimer() < endTime do
        Wait(100)

        -- Validation check during animation
        if IsEntityDead(playerPed) or not DoesEntityExist(playerPed) then
            isFelling = false
            cleanupHatchet()
            TriggerServerEvent('cm-lumber:server:cancelFelling')
            return
        end

        -- Ensure animation keeps playing
        if not IsEntityPlayingAnim(playerPed, animDict, Config.Harvesting.animName, 3) then
            TaskPlayAnim(playerPed, animDict, Config.Harvesting.animName, 3.0, 3.0, -1, 1, 0, false, false, false)
        end
    end

    if isFelling then
        isFelling = false
        ClearPedTasks(playerPed)
        cleanupHatchet()
        TriggerServerEvent('cm-lumber:server:completeFelling')
    end
end)

-- ---------------------------------------------------------------------------
-- Sawmill Processing Governance
-- cm-crafting owns recipe 'materials:saw_timber'. Local conversion is disabled fail-closed.
-- ---------------------------------------------------------------------------
RegisterNetEvent('cm-lumber:client:startProcessingApproved', function()
    -- Disabled fail-closed: conversion requires cm-crafting authorization
    TriggerEvent('cm-lumber:client:notify', Config.Processing.statusNotice, 'warning')
end)

-- ---------------------------------------------------------------------------
-- Shift Conclusion Dialog / Manifest Display
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-lumber:client:shiftConcluded', function(manifest)
    onShift = false
    haulLogs = 0
    haulTimber = 0
    clearPrompt()
    updateNuiHud(false)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'cmLumber:shiftSummary',
        data = manifest or {}
    })
end)

-- ---------------------------------------------------------------------------
-- Main Physical World Interaction Loop
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local waitMs = 800

        if onShift and not isFelling and not isProcessing then
            local playerPed = PlayerPedId()
            if DoesEntityExist(playerPed) and not IsEntityDead(playerPed) and not IsPedInAnyVehicle(playerPed, false) then
                local coords = GetEntityCoords(playerPed)
                local inRangeOfSomething = false

                -- 1. Check Timber Stand Nodes
                local now = GetGameTimer()
                for _, node in ipairs(Config.LoggingNodes) do
                    local dist = #(coords - node.coords)
                    if dist < 15.0 then
                        waitMs = 0
                        inRangeOfSomething = true

                        if dist < (node.radius + 1.2) then
                            local cooldownExpiry = nodeCooldowns[node.id] or 0
                            if cooldownExpiry <= now then
                                if haulLogs < Config.Harvesting.maxHaulLogCapacity then
                                    showPrompt('cm-lumber-node-' .. node.id, ('Fell %s [E]'):format(node.label))
                                    if IsControlJustReleased(0, 38) then -- Key E
                                        TriggerServerEvent('cm-lumber:server:requestFelling', node.id)
                                    end
                                else
                                    showPrompt('cm-lumber-node-' .. node.id, 'Haul Capacity Full [20/20 Logs]')
                                end
                            else
                                local sec = math.ceil((cooldownExpiry - now) / 1000)
                                showPrompt('cm-lumber-node-' .. node.id, ('Stand Regrowing (%ds)'):format(sec))
                            end
                        else
                            clearPrompt('cm-lumber-node-' .. node.id)
                        end
                    end
                end

                -- 2. Check Industrial Sawmill Deck
                local millDist = #(coords - Config.Sawmill.coords)
                if millDist < 15.0 then
                    waitMs = 0
                    inRangeOfSomething = true

                    if millDist < (Config.Sawmill.radius + 1.0) then
                        showPrompt('cm-lumber-sawmill', 'Sawmill Inactive (Sawing Held: cm-crafting Authorization Pending)')
                        if IsControlJustReleased(0, 38) then -- Key E
                            TriggerEvent('cm-lumber:client:notify', Config.Processing.statusNotice, 'warning')
                        end
                    else
                        clearPrompt('cm-lumber-sawmill')
                    end
                end

                if not inRangeOfSomething then
                    clearPrompt()
                end
            end
        end

        Wait(waitMs)
    end
end)

-- ---------------------------------------------------------------------------
-- NUI Callback Handlers
-- ---------------------------------------------------------------------------

RegisterNUICallback('closeSummary', function(_, cb)
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    cleanupHatchet()
    clearPrompt()
    updateNuiHud(false)
    SetNuiFocus(false, false)
end)

