-- cm-trucking/client/npc.lua
-- Central Logistics Dispatcher (Arthur Briggs) & Depot Interaction.

local Config = CMTrucking.Config
local INTERACT_OWNER = 'cm-trucking:broker'

local brokerPed = nil
local promptActive = false

local function loadModel(model)
    local hash = joaat(model)
    if not IsModelValid(hash) then return nil end

    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 250 do
        Wait(10)
        timeout = timeout + 1
    end

    return HasModelLoaded(hash) and hash or nil
end

CreateThread(function()
    local def = Config.Depot.broker
    if not def or not def.coords then return end

    local hash = loadModel(def.model)
    if not hash then
        print('[CM-TRUCKING] Failed to load broker NPC model: ' .. tostring(def.model))
        return
    end

    local coords = def.coords
    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, false)
    if not DoesEntityExist(ped) then return end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanRagdoll(ped, false)

    if def.scenario then
        TaskStartScenarioInPlace(ped, def.scenario, 0, true)
    end
    SetModelAsNoLongerNeeded(hash)

    brokerPed = ped
end)

-- Depot Map Blip
CreateThread(function()
    local depot = Config.Depot
    local blipCfg = Config.Blip.depot
    local coords = depot.broker.coords
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, blipCfg.sprite or 477)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, blipCfg.scale or 0.85)
    SetBlipColour(blip, blipCfg.color or 5)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipCfg.name or 'Terminal Island Freight Logistics')
    EndTextCommandSetBlipName(blip)
end)

-- Receive available contracts dynamically from server (broker + depot routes)
RegisterNetEvent('cm-trucking:client:receiveDispatcherChoices', function(choices, quote)
    if not brokerPed or not DoesEntityExist(brokerPed) then return end
    local def = Config.Depot.broker

    if promptActive and GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract(INTERACT_OWNER) end)
        promptActive = false
    end

    if GetResourceState('cm-ui') == 'started' then
        pcall(function()
            exports['cm-ui']:OpenNpcDialogue(brokerPed, {
                name = def.name or 'Arthur Briggs',
                role = def.role or 'FREIGHT LOGISTICS',
                quote = quote or 'Pick your freight route, driver.',
                continueLabel = 'Review manifests',
                deferChoices = true,
                serviceLabel = 'Long-Distance Commercial Freight',
                choices = choices or {},
            })
        end)
    end
end)

RegisterNetEvent('cm-trucking:client:dialogueChoice', function(payload)
    if type(payload) ~= 'table' then return end

    if payload.action == 'select_contract' and payload.contractId then
        TriggerServerEvent('cm-trucking:server:selectContract', payload.contractId)
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Contract assigned. Payout stored in durable ledger (cash cannot currently be collected in-game). Hauler staged in bay.', 'success', 3000)
            end)
        end
    elseif payload.action == 'cancel' then
        TriggerServerEvent('cm-trucking:server:cancelShift')
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Contract abort requested.', 'inform', 2000)
            end)
        end
    elseif payload.action == 'commercial_unavailable' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond(payload.reason or 'Commercial order is currently unavailable due to missing tariff or route data.', 'warning', 4000)
            end)
        end
    elseif payload.action == 'info' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Back your truck into the container loading dock, secure the cargo, drive safely to destination, unload, and return to check in your manifest.', 'inform', 3800)
            end)
        end
    end
end)

-- Proximity loop for Broker interaction
CreateThread(function()
    while true do
        local waitMs = 800
        local def = Config.Depot.broker

        if def and def.coords then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local dist = #(pCoords - vector3(def.coords.x, def.coords.y, def.coords.z))

            if dist <= (def.interactDistance or 3.0) then
                waitMs = 0
                if not promptActive and GetResourceState('cm-ui') == 'started' then
                    local isDialogueOpen = false
                    pcall(function() isDialogueOpen = exports['cm-ui']:IsNpcDialogueOpen() end)

                    if not isDialogueOpen then
                        pcall(function()
                            exports['cm-ui']:ShowInteract({
                                owner = INTERACT_OWNER,
                                priority = 10,
                                key = Config.InteractKeyLabel or 'E',
                                label = 'TALK TO FREIGHT DISPATCHER',
                                name = def.name,
                                role = def.role,
                            })
                        end)
                        promptActive = true
                    end
                end

                if IsControlJustReleased(0, Config.InteractKey or 38) then
                    TriggerServerEvent('cm-trucking:server:openDispatcher')
                end
            elseif promptActive then
                if GetResourceState('cm-ui') == 'started' then
                    pcall(function() exports['cm-ui']:HideInteract(INTERACT_OWNER) end)
                end
                promptActive = false
            end
        end

        Wait(waitMs)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if promptActive and GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract(INTERACT_OWNER) end)
    end
    if brokerPed and DoesEntityExist(brokerPed) then
        DeleteEntity(brokerPed)
    end
end)

