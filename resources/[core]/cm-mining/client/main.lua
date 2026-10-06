-- cm-mining/client/main.lua
-- Davis Quartz Quarry Mining Physical Gameplay Client Controller.

local Config = CMMining.Config
CMMining = CMMining or {}
CMMining.Client = CMMining.Client or {}

local onShift = false
local cartOre = 0
local cartIngots = 0
local oreMined = 0
local ingotsSmelted = 0
local isExtracting = false
local isSmelting = false

local activePromptOwner = nil
local nodeCooldowns = {} -- [nodeId] = gameTimerExpiry
local pickaxeProp = nil

-- ---------------------------------------------------------------------------
-- Public Client State Queries
-- ---------------------------------------------------------------------------

function CMMining.Client.IsOnShift()
    return onShift
end

function CMMining.Client.GetCartStatus()
    return {
        ore = cartOre,
        ingots = cartIngots,
        mined = oreMined,
        smelted = ingotsSmelted,
        maxOre = Config.Extraction.maxCartOreCapacity,
    }
end

exports('IsOnShift', CMMining.Client.IsOnShift)
exports('GetCartStatus', CMMining.Client.GetCartStatus)

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
                name = 'Davis Quartz Quarry',
                role = 'MINERAL EXTRACTION',
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
        action = 'cmMining:updateHud',
        data = {
            visible = visible,
            onShift = onShift,
            cartOre = cartOre,
            maxCartOre = Config.Extraction.maxCartOreCapacity,
            cartIngots = cartIngots,
            oreMined = oreMined,
            ingotsSmelted = ingotsSmelted,
            objective = objectiveText or (cartOre >= 3 and 'SMELT ORE AT INDUSTRIAL FURNACE OR CONTINUE MINING' or 'EXTRACT RAW IRON ORE AT VEIN NODES'),
        }
    })
end

-- ---------------------------------------------------------------------------
-- Server State Synchronization
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-mining:client:syncState', function(data)
    if not data or not data.onShift then
        onShift = false
        cartOre = 0
        cartIngots = 0
        oreMined = 0
        ingotsSmelted = 0
        isExtracting = false
        isSmelting = false
        clearPrompt()
        updateNuiHud(false)
        return
    end

    onShift = true
    cartOre = data.cartOre or 0
    cartIngots = data.cartIngots or 0
    oreMined = data.oreMined or 0
    ingotsSmelted = data.ingotsSmelted or 0
    updateNuiHud(true)
end)

RegisterNetEvent('cm-mining:client:updateNodeCooldown', function(nodeId, expiry)
    nodeCooldowns[nodeId] = expiry
end)

RegisterNetEvent('cm-mining:client:notify', function(message, kind)
    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:Notify(message, kind or 'info') end)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(message)
        EndTextCommandThefeedPostTicker(false, true)
    end
end)

-- ---------------------------------------------------------------------------
-- Physical Extraction Gameplay (Pickaxe & Animation)
-- ---------------------------------------------------------------------------

local function cleanupPickaxe()
    if pickaxeProp and DoesEntityExist(pickaxeProp) then
        DetachEntity(pickaxeProp, true, true)
        DeleteEntity(pickaxeProp)
        pickaxeProp = nil
    end
end

RegisterNetEvent('cm-mining:client:startExtractionApproved', function(payload)
    if not payload or not payload.nodeId then return end
    local nodeId = payload.nodeId
    local durationMs = payload.durationMs or Config.Extraction.durationMs

    local playerPed = PlayerPedId()
    if not DoesEntityExist(playerPed) or IsEntityDead(playerPed) then return end

    isExtracting = true
    clearPrompt()
    updateNuiHud(true, 'MINING RAW IRON ORE VEIN...')

    -- Load animation dictionary
    local animDict = Config.Extraction.animDict
    RequestAnimDict(animDict)
    local animTimeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(animDict) and GetGameTimer() < animTimeout do
        Wait(50)
    end

    -- Spawn and attach pickaxe prop
    local model = Config.Extraction.pickaxeProp
    RequestModel(model)
    local propTimeout = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < propTimeout do
        Wait(50)
    end

    cleanupPickaxe()
    local coords = GetEntityCoords(playerPed)
    pickaxeProp = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
    SetModelAsNoLongerNeeded(model)

    -- Attach to Right Hand (Bone 57005: SKEL_R_Hand)
    local boneIdx = GetPedBoneIndex(playerPed, 57005)
    AttachEntityToEntity(
        pickaxeProp, playerPed, boneIdx,
        0.09, -0.05, -0.02,
        -78.0, 13.0, 28.0,
        true, true, false, true, 1, true
    )

    -- Physical extraction loop
    local startTime = GetGameTimer()
    local endTime = startTime + durationMs

    TaskPlayAnim(playerPed, animDict, Config.Extraction.animName, 3.0, 3.0, -1, 1, 0, false, false, false)

    while isExtracting and GetGameTimer() < endTime do
        Wait(100)

        -- Validation check during animation
        if IsEntityDead(playerPed) or not DoesEntityExist(playerPed) then
            isExtracting = false
            cleanupPickaxe()
            TriggerServerEvent('cm-mining:server:cancelExtraction')
            return
        end

        -- Ensure animation keeps playing
        if not IsEntityPlayingAnim(playerPed, animDict, Config.Extraction.animName, 3) then
            TaskPlayAnim(playerPed, animDict, Config.Extraction.animName, 3.0, 3.0, -1, 1, 0, false, false, false)
        end

        -- Disable combat & attack controls during extraction
        DisableControlAction(0, 24, true)  -- Attack
        DisableControlAction(0, 25, true)  -- Aim
        DisableControlAction(0, 140, true) -- Light Melee
        DisableControlAction(0, 141, true) -- Heavy Melee
        DisableControlAction(0, 142, true) -- Melee Alternate
    end

    -- Cleanup physical props & anims
    StopAnimTask(playerPed, animDict, Config.Extraction.animName, 1.0)
    RemoveAnimDict(animDict)
    cleanupPickaxe()

    if isExtracting then
        isExtracting = false
        TriggerServerEvent('cm-mining:server:completeExtraction', nodeId)
    end
end)

-- ---------------------------------------------------------------------------
-- Physical Smelting Gameplay (Furnace Inspection)
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-mining:client:startSmeltingApproved', function(payload)
    local durationMs = payload and payload.durationMs or Config.Smelting.durationMs
    local playerPed = PlayerPedId()
    if not DoesEntityExist(playerPed) or IsEntityDead(playerPed) then return end

    isSmelting = true
    clearPrompt()
    updateNuiHud(true, 'PROCESSING ORE IN INDUSTRIAL SMELTER...')

    local animDict = Config.Smelting.animDict
    RequestAnimDict(animDict)
    local animTimeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(animDict) and GetGameTimer() < animTimeout do
        Wait(50)
    end

    TaskPlayAnim(playerPed, animDict, Config.Smelting.animName, 2.0, 2.0, -1, 1, 0, false, false, false)

    local startTime = GetGameTimer()
    local endTime = startTime + durationMs

    while isSmelting and GetGameTimer() < endTime do
        Wait(100)

        if IsEntityDead(playerPed) or not DoesEntityExist(playerPed) then
            isSmelting = false
            TriggerServerEvent('cm-mining:server:cancelSmelting')
            return
        end

        if not IsEntityPlayingAnim(playerPed, animDict, Config.Smelting.animName, 3) then
            TaskPlayAnim(playerPed, animDict, Config.Smelting.animName, 2.0, 2.0, -1, 1, 0, false, false, false)
        end

        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
    end

    StopAnimTask(playerPed, animDict, Config.Smelting.animName, 1.0)
    RemoveAnimDict(animDict)

    if isSmelting then
        isSmelting = false
        TriggerServerEvent('cm-mining:server:completeSmelting')
    end
end)

-- ---------------------------------------------------------------------------
-- Main Quarry Proximity & Interaction Loop
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local waitMs = 1000

        if onShift and not isExtracting and not isSmelting then
            local playerPed = PlayerPedId()
            if DoesEntityExist(playerPed) and not IsEntityDead(playerPed) then
                local pCoords = GetEntityCoords(playerPed)
                local inInteractionZone = false

                -- 1. Check Mineral Vein Nodes
                for _, node in ipairs(Config.ExtractionNodes) do
                    local dist = #(pCoords - node.coords)
                    if dist < 30.0 then
                        waitMs = 0 -- Smooth frame rendering for markers
                        local now = GetGameTimer()
                        local isDepleted = (nodeCooldowns[node.id] or 0) > now

                        -- Render CM Cyan extraction beacon / marker (Dim red if depleted)
                        if isDepleted then
                            DrawMarker(
                                1, node.coords.x, node.coords.y, node.coords.z - 0.9,
                                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                                node.radius * 2.0, node.radius * 2.0, 0.35,
                                180, 50, 50, 90,
                                false, false, 2, false, nil, nil, false
                            )
                        else
                            DrawMarker(
                                1, node.coords.x, node.coords.y, node.coords.z - 0.9,
                                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                                node.radius * 2.0, node.radius * 2.0, 0.45,
                                0, 204, 255, 120, -- CM Cyan / ice-blue
                                false, false, 2, false, nil, nil, false
                            )
                        end

                        if dist <= node.radius then
                            inInteractionZone = true
                            local ownerKey = 'cm-mining:node:' .. node.id

                            if isDepleted then
                                local remaining = math.ceil(((nodeCooldowns[node.id] or 0) - now) / 1000)
                                showPrompt(ownerKey, ('Vein Depleted (%d s remaining)'):format(remaining))
                            elseif cartOre >= Config.Extraction.maxCartOreCapacity then
                                showPrompt(ownerKey, ('Cart Full (%d/%d Ore) - Smelt at Furnace'):format(cartOre, Config.Extraction.maxCartOreCapacity))
                            else
                                showPrompt(ownerKey, ('Mine Raw Iron Ore (%s | Cart: %d/%d)'):format(node.label, cartOre, Config.Extraction.maxCartOreCapacity))
                                if IsControlJustPressed(0, 38) then -- Key E
                                    TriggerServerEvent('cm-mining:server:startExtraction', node.id)
                                end
                            end
                            break
                        end
                    end
                end

                -- 2. Check Industrial Furnace
                if not inInteractionZone then
                    local fDist = #(pCoords - Config.Furnace.coords)
                    if fDist < 25.0 then
                        waitMs = 0
                        DrawMarker(
                            1, Config.Furnace.coords.x, Config.Furnace.coords.y, Config.Furnace.coords.z - 0.9,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            Config.Furnace.radius * 2.0, Config.Furnace.radius * 2.0, 0.5,
                            0, 204, 255, 130, -- CM Cyan
                            false, false, 2, false, nil, nil, false
                        )

                        if fDist <= Config.Furnace.radius then
                            inInteractionZone = true
                            local ownerKey = 'cm-mining:furnace'
                            if cartOre < Config.Smelting.inputAmount then
                                showPrompt(ownerKey, ('Industrial Furnace (Need %d Raw Ore | Have: %d)'):format(Config.Smelting.inputAmount, cartOre))
                            else
                                showPrompt(ownerKey, ('Smelt 3 Ore -> 1 Iron Ingot (Cart: %d Ore)'):format(cartOre))
                                if IsControlJustPressed(0, 38) then
                                    TriggerServerEvent('cm-mining:server:startSmelting')
                                end
                            end
                        end
                    end
                end

                if not inInteractionZone and activePromptOwner and string.find(activePromptOwner, 'cm-mining:node') or (activePromptOwner == 'cm-mining:furnace') then
                    clearPrompt()
                end
            end
        end

        Wait(waitMs)
    end
end)

-- ---------------------------------------------------------------------------
-- Cleanup Handlers
-- ---------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    cleanupPickaxe()
    clearPrompt()
    updateNuiHud(false)
end)

