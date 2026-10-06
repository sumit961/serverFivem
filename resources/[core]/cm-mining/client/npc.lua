-- cm-mining/client/npc.lua
-- Davis Quartz Quarry Foreman & Map Blip Controller.

local Config = CMMining.Config
CMMining = CMMining or {}
CMMining.Client = CMMining.Client or {}

local foremanPed = nil
local quarryBlip = nil
local isNearForeman = false
local foremanPromptActive = false

-- ---------------------------------------------------------------------------
-- Blip Management
-- ---------------------------------------------------------------------------

local function createQuarryBlip()
    if quarryBlip and DoesBlipExist(quarryBlip) then return end

    local cfg = Config.Foreman.blip
    local coords = Config.Foreman.coords
    quarryBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(quarryBlip, cfg.sprite)
    SetBlipDisplay(quarryBlip, 4)
    SetBlipScale(quarryBlip, cfg.scale)
    SetBlipColour(quarryBlip, cfg.color)
    SetBlipAsShortRange(quarryBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(cfg.label)
    EndTextCommandSetBlipName(quarryBlip)
end

-- ---------------------------------------------------------------------------
-- Foreman NPC Spawn & Lifecycle
-- ---------------------------------------------------------------------------

local function spawnForeman()
    if foremanPed and DoesEntityExist(foremanPed) then return end

    local modelHash = Config.Foreman.model
    RequestModel(modelHash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
        Wait(50)
    end

    if not HasModelLoaded(modelHash) then return end

    local coords = Config.Foreman.coords
    foremanPed = CreatePed(4, modelHash, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetEntityHeading(foremanPed, coords.w)
    FreezeEntityPosition(foremanPed, true)
    SetEntityInvincible(foremanPed, true)
    SetBlockingOfNonTemporaryEvents(foremanPed, true)
    SetModelAsNoLongerNeeded(modelHash)
end

-- ---------------------------------------------------------------------------
-- Foreman Dialogue Interaction (cm-ui integration)
-- ---------------------------------------------------------------------------

local function openForemanDialogue()
    local onShift = CMMining.Client.IsOnShift and CMMining.Client.IsOnShift() or false
    local choices = {}

    if not onShift then
        table.insert(choices, {
            id = 'clock_in',
            label = 'Clock In for Mining Shift',
            description = 'Begin extraction shift at Davis Quartz. Mine ore veins and smelt ingots.',
            event = 'cm-mining:client:handleDialogueChoice',
            payload = { action = 'clock_in' }
        })
    else
        table.insert(choices, {
            id = 'clock_out',
            label = 'Clock Out & File Shift Manifest',
            description = 'Conclude your shift and register mined ore and smelted ingots.',
            event = 'cm-mining:client:handleDialogueChoice',
            payload = { action = 'clock_out' }
        })
    end

    table.insert(choices, {
        id = 'status_notice',
        label = 'Quarry Status & Payroll Policy',
        description = 'Review quarry custody status and downstream material integration notices.',
        event = 'cm-mining:client:handleDialogueChoice',
        payload = { action = 'status_notice' }
    })

    if GetResourceState('cm-ui') == 'started' then
        pcall(function()
            exports['cm-ui']:OpenNpcDialogue(foremanPed, {
                name = Config.Foreman.pedName,
                role = Config.Foreman.role,
                quote = Config.Foreman.dialogueQuote,
                continueLabel = 'Review Work Order',
                deferChoices = false,
                serviceLabel = 'Davis Quartz Quarry Operations',
                choices = choices,
                closeEvent = 'cm-mining:client:dialogueClosed',
            })
        end)
    end
end

RegisterNetEvent('cm-mining:client:handleDialogueChoice', function(payload)
    if not payload or not payload.action then return end

    if payload.action == 'clock_in' then
        TriggerServerEvent('cm-mining:server:clockIn')
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Shift started! Grab your pickaxe and head into the pit.', 'success', 2500)
            end)
        end
    elseif payload.action == 'clock_out' then
        TriggerServerEvent('cm-mining:server:clockOut')
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond('Shift manifest recorded. See you tomorrow, miner.', 'info', 2500)
            end)
        end
    elseif payload.action == 'status_notice' then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function()
                exports['cm-ui']:NpcDialogueRespond(
                    'Notice: Raw ore and ingots are tracked in the quarry ledger. Material inventory custody and payroll are held pending downstream sink (cm-construction) activation.',
                    'info',
                    4500
                )
            end)
        end
    end
end)

RegisterNetEvent('cm-mining:client:dialogueClosed', function()
    -- Dialogue was dismissed
end)

-- ---------------------------------------------------------------------------
-- Proximity Loop for Foreman Interaction
-- ---------------------------------------------------------------------------

CreateThread(function()
    createQuarryBlip()
    spawnForeman()

    while true do
        local waitMs = 1000
        local playerPed = PlayerPedId()
        if DoesEntityExist(playerPed) and not IsEntityDead(playerPed) then
            local pCoords = GetEntityCoords(playerPed)
            local fCoords = vector3(Config.Foreman.coords.x, Config.Foreman.coords.y, Config.Foreman.coords.z)
            local dist = #(pCoords - fCoords)

            if dist < 25.0 then
                waitMs = 250
                if not foremanPed or not DoesEntityExist(foremanPed) then
                    spawnForeman()
                end

                if dist < 2.8 then
                    waitMs = 0
                    if not foremanPromptActive then
                        foremanPromptActive = true
                        if GetResourceState('cm-ui') == 'started' then
                            pcall(function()
                                exports['cm-ui']:ShowInteract({
                                    owner = 'cm-mining:foreman',
                                    priority = 10,
                                    key = 'E',
                                    label = 'Speak to Foreman Vance',
                                    name = Config.Foreman.pedName,
                                    role = Config.Foreman.role,
                                })
                            end)
                        end
                    end

                    if IsControlJustPressed(0, 38) then -- Key E
                        openForemanDialogue()
                    end
                else
                    if foremanPromptActive then
                        foremanPromptActive = false
                        if GetResourceState('cm-ui') == 'started' then
                            pcall(function()
                                exports['cm-ui']:HideInteract('cm-mining:foreman')
                            end)
                        end
                    end
                end
            else
                if foremanPromptActive then
                    foremanPromptActive = false
                    if GetResourceState('cm-ui') == 'started' then
                        pcall(function()
                            exports['cm-ui']:HideInteract('cm-mining:foreman')
                        end)
                    end
                end
            end
        end
        Wait(waitMs)
    end
end)

-- ---------------------------------------------------------------------------
-- Cleanup on Stop
-- ---------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    if foremanPromptActive and GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract('cm-mining:foreman') end)
    end

    if foremanPed and DoesEntityExist(foremanPed) then
        DeletePed(foremanPed)
        foremanPed = nil
    end

    if quarryBlip and DoesBlipExist(quarryBlip) then
        RemoveBlip(quarryBlip)
        quarryBlip = nil
    end
end)

