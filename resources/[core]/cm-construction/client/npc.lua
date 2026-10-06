-- cm-construction/client/npc.lua
-- Site Superintendent (Earle "Mac" McAllister) & Construction Headquarters Interaction.

local Config = CMConstruction.Config
local INTERACT_OWNER = 'cm-construction:superintendent'

local npcPed = nil
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
    local def = Config.Depot.superintendent
    if not def or not def.coords then return end

    local hash = loadModel(def.model)
    if not hash then
        print('[CM-CONSTRUCTION] Failed to load superintendent model: ' .. tostring(def.model))
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

    npcPed = ped
end)

-- Headquarters Map Blip
CreateThread(function()
    local depot = Config.Depot
    local blipCfg = Config.Blip.depot
    local blip = AddBlipForCoord(depot.superintendent.coords.x, depot.superintendent.coords.y, depot.superintendent.coords.z)
    SetBlipSprite(blip, blipCfg.sprite or 357)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, blipCfg.scale or 0.85)
    SetBlipColour(blip, blipCfg.color or 5)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipCfg.name or 'Downtown Construction HQ')
    EndTextCommandSetBlipName(blip)
end)

-- Receive available tasks dynamically from server
RegisterNetEvent('cm-construction:client:receiveWorkBoardChoices', function(choices, quote)
    if not npcPed or not DoesEntityExist(npcPed) then return end
    local def = Config.Depot.superintendent

    if promptActive and GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract(INTERACT_OWNER) end)
        promptActive = false
    end

    if GetResourceState('cm-ui') == 'started' then
        pcall(function()
            exports['cm-ui']:OpenNpcDialogue(npcPed, {
                name = def.name or 'Earle "Mac" McAllister',
                role = def.role or 'SITE SUPERINTENDENT',
                quote = quote or 'Department of Public Works has infrastructure assignments ready. What are you looking to tackle today?',
                continueLabel = 'Review Work Orders',
                deferChoices = true,
                serviceLabel = 'Municipal Infrastructure & Heavy Maintenance',
                choices = choices or {},
            })
        end)
    end
end)

RegisterNetEvent('cm-construction:client:dialogueChoice', function(payload)
    if type(payload) ~= 'table' then return end

    if payload.action == 'select_task' and payload.taskId then
        TriggerServerEvent('cm-construction:server:selectTask', payload.taskId)
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Work order assigned. Payout stored in durable ledger (cash cannot currently be collected in-game). Utility hauler is staged in the yard.', 'success', 3000)
            end)
        end
    elseif payload.action == 'cancel' then
        TriggerServerEvent('cm-construction:server:cancelShift')
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Shift clocked out. Equipment and site vehicles checked back in.', 'inform', 2000)
            end)
        end
    elseif payload.action == 'premium_unavailable' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond(payload.reason or 'Commercial architectural tenders are currently offline. Municipal city work orders are available.', 'warning', 4000)
            end)
        end
    elseif payload.action == 'info' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Clock in at the site trailer, take a utility vehicle to the marked zone, complete each sequential physical stage, then return here to sign off the manifest.', 'inform', 4000)
            end)
        end
    end
end)

-- Proximity loop for Superintendent interaction
CreateThread(function()
    while true do
        local waitMs = 800
        local def = Config.Depot.superintendent

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
                                label = 'TALK TO SITE SUPERINTENDENT',
                                name = def.name,
                                role = def.role,
                            })
                        end)
                        promptActive = true
                    end
                end

                if IsControlJustReleased(0, Config.InteractKey or 38) then
                    TriggerServerEvent('cm-construction:server:openWorkBoard')
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
    if npcPed and DoesEntityExist(npcPed) then
        DeleteEntity(npcPed)
    end
end)

