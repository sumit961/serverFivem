-- cm-warehouse/client/npc.lua
-- Port Logistics Supervisor (Vince "Cargo" Calderon) & Warehouse Facility Interaction.

local Config = CMWarehouse.Config
local INTERACT_OWNER = 'cm-warehouse:supervisor'

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
    local def = Config.Facility.supervisor
    if not def or not def.coords then return end

    local hash = loadModel(def.model)
    if not hash then
        print('[CM-WAREHOUSE] Failed to load supervisor model: ' .. tostring(def.model))
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

-- Facility Map Blip
CreateThread(function()
    local facility = Config.Facility
    local blipCfg = Config.Blip.facility
    local blip = AddBlipForCoord(facility.supervisor.coords.x, facility.supervisor.coords.y, facility.supervisor.coords.z)
    SetBlipSprite(blip, blipCfg.sprite or 473)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, blipCfg.scale or 0.85)
    SetBlipColour(blip, blipCfg.color or 5)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipCfg.name or 'Port Logistics Warehouse')
    EndTextCommandSetBlipName(blip)
end)

-- Receive available shifts dynamically from server
RegisterNetEvent('cm-warehouse:client:receiveWorkBoardChoices', function(choices, quote)
    if not npcPed or not DoesEntityExist(npcPed) then return end
    local def = Config.Facility.supervisor

    if promptActive and GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract(INTERACT_OWNER) end)
        promptActive = false
    end

    if GetResourceState('cm-ui') == 'started' then
        pcall(function()
            exports['cm-ui']:OpenNpcDialogue(npcPed, {
                name = def.name or 'Vince "Cargo" Calderon',
                role = def.role or 'PORT LOGISTICS SUPERVISOR',
                quote = quote or 'Port Terminal Logistics has municipal cargo manifests ready for processing. Select an assignment.',
                continueLabel = 'Review Cargo Manifests',
                deferChoices = true,
                serviceLabel = 'Port Logistics & Warehouse Freight',
                choices = choices or {},
            })
        end)
    end
end)

RegisterNetEvent('cm-warehouse:client:dialogueChoice', function(payload)
    if type(payload) ~= 'table' then return end

    if payload.action == 'select_shift' and payload.shiftId then
        TriggerServerEvent('cm-warehouse:server:selectShift', payload.shiftId)
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Shift manifest assigned. Payout stored in durable ledger (cash cannot currently be collected in-game). Equipment is staged in the yard.', 'success', 3000)
            end)
        end
    elseif payload.action == 'cancel' then
        TriggerServerEvent('cm-warehouse:server:cancelShift')
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Shift clocked out. Warehouse equipment and manifest logged back in.', 'inform', 2000)
            end)
        end
    elseif payload.action == 'commercial_unavailable' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond(payload.reason or 'Commercial cargo order is currently unavailable due to missing tariff or stage definitions.', 'warning', 4000)
            end)
        end
    elseif payload.action == 'premium_unavailable' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond(payload.reason or 'Commercial enterprise freight contracts are currently offline. Municipal port logistics shifts are available.', 'warning', 4000)
            end)
        end
    elseif payload.action == 'info' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Sign on at the office, offload inbound freight at Receiving, barcode scan and sort at Conveyor, band pallets at Staging, and transport to Outbound Dispatch before signing off.', 'inform', 4000)
            end)
        end
    end
end)

-- Proximity loop for Supervisor interaction
CreateThread(function()
    while true do
        local waitMs = 800
        local def = Config.Facility.supervisor

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
                                label = 'TALK TO PORT SUPERVISOR',
                                name = def.name,
                                role = def.role,
                            })
                        end)
                        promptActive = true
                    end
                end

                if IsControlJustReleased(0, Config.InteractKey or 38) then
                    TriggerServerEvent('cm-warehouse:server:openWorkBoard')
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

