-- cm-courier/client/npc.lua
-- Municipal Courier Dispatcher (Sal Moreno) & Courier Depot Facility Interaction.

local Config = CMCourier.Config
local INTERACT_OWNER = 'cm-courier:dispatcher'

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

    local hash = loadModel(def.model) or loadModel('s_m_m_postal_02') or loadModel('s_m_y_autopep_01')
    if not hash then
        print('[CM-COURIER] Failed to load dispatcher model: ' .. tostring(def.model))
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
    SetBlipSprite(blip, blipCfg.sprite or 67)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, blipCfg.scale or 0.85)
    SetBlipColour(blip, blipCfg.color or 5)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipCfg.name or 'Municipal Courier Depot')
    EndTextCommandSetBlipName(blip)
end)

-- Receive available routes dynamically from server
RegisterNetEvent('cm-courier:client:receiveWorkBoardChoices', function(choices, quote)
    if not npcPed or not DoesEntityExist(npcPed) then return end
    local def = Config.Facility.supervisor

    if promptActive and GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract(INTERACT_OWNER) end)
        promptActive = false
    end

    if GetResourceState('cm-ui') == 'started' then
        pcall(function()
            exports['cm-ui']:OpenNpcDialogue(npcPed, {
                name = def.name or 'Sal Moreno',
                role = def.role or 'MUNICIPAL COURIER DISPATCH',
                quote = quote or 'City Courier Dispatch has municipal delivery manifests ready for pickup. Select an assignment.',
                continueLabel = 'Review Delivery Routes',
                deferChoices = true,
                serviceLabel = 'Municipal Courier Service',
                choices = choices or {},
            })
        end)
    end
end)

RegisterNetEvent('cm-courier:client:dialogueChoice', function(payload)
    if type(payload) ~= 'table' then return end

    if payload.action == 'select_route' and payload.routeId then
        TriggerServerEvent('cm-courier:server:selectRoute', payload.routeId)
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Delivery manifest assigned. Van staged in bay. Load parcels at the dock before departing (earnings stored in durable ledger; cash held pending payroll integration).', 'success', 3500)
            end)
        end
    elseif payload.action == 'sign_off' then
        TriggerServerEvent('cm-courier:server:signOff')
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Manifest processed! All delivery signatures verified. Earnings recorded to durable ledger.', 'success', 3000)
            end)
        end
    elseif payload.action == 'abort' then
        TriggerServerEvent('cm-courier:server:cancelShift')
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Delivery route clocked out. Courier van and parcels logged back in.', 'inform', 2000)
            end)
        end
    elseif payload.action == 'commercial_unavailable' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond(payload.reason or 'Commercial parcel order is currently unavailable due to missing tariff or route specifications.', 'warning', 4000)
            end)
        end
    elseif payload.action == 'info' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Sign on at dispatch, load parcels at the dock into your van, follow your route GPS to each drop, obtain delivery confirmation, return to the depot bay, and sign off with Sal.', 'inform', 4500)
            end)
        end
    end
end)

-- Proximity loop for Dispatcher interaction
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
                                label = 'TALK TO COURIER DISPATCHER',
                                name = def.name,
                                role = def.role,
                            })
                        end)
                        promptActive = true
                    end
                end

                if IsControlJustReleased(0, Config.InteractKey or 38) then
                    TriggerServerEvent('cm-courier:server:openWorkBoard')
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

