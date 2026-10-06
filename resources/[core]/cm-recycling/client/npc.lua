local Config = CMRecycling.Config
local INTERACT_OWNER = 'cm-recycling:npc'

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
        print('[CM-RECYCLING] Failed to load NPC model: ' .. tostring(def.model))
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
    local coords = facility.supervisor.coords
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, blipCfg.sprite or 365)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, blipCfg.scale or 0.85)
    SetBlipColour(blip, blipCfg.color or 25)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipCfg.name or 'Rogers Salvage & Recycling')
    EndTextCommandSetBlipName(blip)
end)

local function buildChoices()
    local onShift = CMRecycling.Client and CMRecycling.Client.IsOnShift()
    local choices = {}

    if not onShift then
        choices[#choices + 1] = {
            id = 'start',
            label = 'Start Salvage & Recycling Shift',
            description = 'Sign on for industrial scrap collection & sorting ($8,400 / run) [Held in durable ledger; cash cannot currently be collected in-game]',
            event = 'cm-recycling:client:dialogueChoice',
            payload = { action = 'start' },
        }
    else
        choices[#choices + 1] = {
            id = 'cancel',
            label = 'Clock Out & Return Truck',
            description = 'End your current shift and hand in your utility truck',
            event = 'cm-recycling:client:dialogueChoice',
            payload = { action = 'cancel' },
        }
    end

    choices[#choices + 1] = {
        id = 'info',
        label = 'Salvage Operations Briefing',
        description = 'Learn about scrap recovery, truck loading, hopper unloading, and sorting',
        event = 'cm-recycling:client:dialogueChoice',
        payload = { action = 'info' },
    }

    return choices
end

local function openDialogue()
    if not npcPed or not DoesEntityExist(npcPed) then return end
    local def = Config.Facility.supervisor
    local onShift = CMRecycling.Client and CMRecycling.Client.IsOnShift()

    if GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract(INTERACT_OWNER) end)
    end
    promptActive = false

    local quote = onShift
        and 'How is the scrap haul looking? Make sure all salvage is unloaded and sorted at the separator before clocking out.'
        or 'Welcome to Rogers Salvage. The city generates tons of recyclable industrial scrap every day. Ready for a run?'

    if GetResourceState('cm-ui') == 'started' then
        pcall(function()
            exports['cm-ui']:OpenNpcDialogue(npcPed, {
                name = def.name or 'Frank Kovac',
                role = def.role or 'SALVAGE OPERATIONS',
                quote = quote,
                continueLabel = 'Review options',
                deferChoices = true,
                serviceLabel = 'Industrial Recycling & Salvage',
                choices = buildChoices(),
            })
        end)
    end
end

RegisterNetEvent('cm-recycling:client:dialogueChoice', function(payload)
    if type(payload) ~= 'table' then return end

    if payload.action == 'start' then
        TriggerServerEvent('cm-recycling:server:startShift')
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Assignment logged (payout stored in durable ledger; cash cannot currently be collected in-game). Your utility truck is fueled and ready in the yard.', 'success', 3000)
            end)
        end
    elseif payload.action == 'cancel' then
        TriggerServerEvent('cm-recycling:server:cancelShift')
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Clock out requested.', 'inform', 2000)
            end)
        end
    elseif payload.action == 'info' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Collect scrap bundles from sites, load into your truck bed, unload at the facility hopper, then run the mechanical sorting table.', 'inform', 3600)
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

            if dist <= (def.interactDistance or 2.8) then
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
                                label = 'TALK TO SUPERVISOR',
                                name = def.name,
                                role = def.role,
                            })
                        end)
                        promptActive = true
                    end
                end

                if IsControlJustReleased(0, Config.InteractKey or 38) then
                    openDialogue()
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

