-- cm-lumber/client/npc.lua
-- Paleto Forest Sawmill Foreman & Map Blip Controller.

local Config = CMLumber.Config
CMLumber = CMLumber or {}
CMLumber.Client = CMLumber.Client or {}

local foremanPed = nil
local sawmillBlip = nil
local isNearForeman = false
local foremanPromptActive = false

-- ---------------------------------------------------------------------------
-- Blip Management
-- ---------------------------------------------------------------------------

local function createSawmillBlip()
    if sawmillBlip and DoesBlipExist(sawmillBlip) then return end

    local cfg = Config.Foreman.blip
    local coords = Config.Foreman.coords
    sawmillBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(sawmillBlip, cfg.sprite)
    SetBlipDisplay(sawmillBlip, 4)
    SetBlipScale(sawmillBlip, cfg.scale)
    SetBlipColour(sawmillBlip, cfg.color)
    SetBlipAsShortRange(sawmillBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(cfg.label)
    EndTextCommandSetBlipName(sawmillBlip)
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
    local onShift = CMLumber.Client.IsOnShift and CMLumber.Client.IsOnShift() or false
    local choices = {}

    if not onShift then
        table.insert(choices, {
            id = 'clock_in',
            label = 'Clock In for Forestry Shift',
            description = 'Begin timber harvesting at Paleto Forest. Fell marked trees and haul logs to the mill deck.',
            event = 'cm-lumber:client:handleDialogueChoice',
            payload = { action = 'clock_in' }
        })
    else
        table.insert(choices, {
            id = 'clock_out',
            label = 'Clock Out & File Shift Manifest',
            description = 'Conclude your forestry shift and register felled timber and sawn lumber in the mill ledger.',
            event = 'cm-lumber:client:handleDialogueChoice',
            payload = { action = 'clock_out' }
        })
    end

    table.insert(choices, {
        id = 'status_notice',
        label = 'Sawmill Status & Payroll Policy',
        description = 'Review sawmill material custody status and downstream construction integration notices.',
        event = 'cm-lumber:client:handleDialogueChoice',
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
                serviceLabel = 'Paleto Sawmill Operations',
                serviceType = 'forestry',
                serviceIcon = '🌲',
                choices = choices,
            })
        end)
    else
        -- Fallback if cm-ui dialogue is unmounted
        if not onShift then
            TriggerServerEvent('cm-lumber:server:clockIn')
        else
            TriggerServerEvent('cm-lumber:server:clockOut')
        end
    end
end

RegisterNetEvent('cm-lumber:client:handleDialogueChoice', function(data)
    if not data or not data.action then return end

    if data.action == 'clock_in' then
        TriggerServerEvent('cm-lumber:server:clockIn')
    elseif data.action == 'clock_out' then
        TriggerServerEvent('cm-lumber:server:clockOut')
    elseif data.action == 'status_notice' then
        local msg = Config.Custody.holdingNotice
        TriggerEvent('cm-lumber:client:notify', msg, 'info')
    end
end)

-- ---------------------------------------------------------------------------
-- Proximity Loop for Foreman Interaction
-- ---------------------------------------------------------------------------

CreateThread(function()
    createSawmillBlip()
    spawnForeman()

    while true do
        local waitMs = 1000
        local playerPed = PlayerPedId()

        if DoesEntityExist(playerPed) and not IsEntityDead(playerPed) then
            local coords = GetEntityCoords(playerPed)
            local foremanCoords = vector3(Config.Foreman.coords.x, Config.Foreman.coords.y, Config.Foreman.coords.z)
            local dist = #(coords - foremanCoords)

            if dist < 25.0 then
                waitMs = 0
                if dist < 2.5 then
                    isNearForeman = true
                    if not foremanPromptActive then
                        foremanPromptActive = true
                        if GetResourceState('cm-ui') == 'started' then
                            pcall(function()
                                exports['cm-ui']:ShowInteract({
                                    owner = 'cm-lumber-foreman',
                                    priority = 10,
                                    key = 'E',
                                    label = 'Speak with Sawmill Foreman',
                                    name = Config.Foreman.pedName,
                                    role = Config.Foreman.role,
                                })
                            end)
                        end
                    end

                    if IsControlJustReleased(0, 38) then -- Key E
                        openForemanDialogue()
                    end
                else
                    if isNearForeman then
                        isNearForeman = false
                        if foremanPromptActive then
                            foremanPromptActive = false
                            if GetResourceState('cm-ui') == 'started' then
                                pcall(function() exports['cm-ui']:HideInteract('cm-lumber-foreman') end)
                            end
                        end
                    end
                end
            else
                if isNearForeman then
                    isNearForeman = false
                    if foremanPromptActive then
                        foremanPromptActive = false
                        if GetResourceState('cm-ui') == 'started' then
                            pcall(function() exports['cm-ui']:HideInteract('cm-lumber-foreman') end)
                        end
                    end
                end
            end
        end

        Wait(waitMs)
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end

    if foremanPed and DoesEntityExist(foremanPed) then
        DeletePed(foremanPed)
        foremanPed = nil
    end

    if sawmillBlip and DoesBlipExist(sawmillBlip) then
        RemoveBlip(sawmillBlip)
        sawmillBlip = nil
    end

    if foremanPromptActive and GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract('cm-lumber-foreman') end)
    end
end)

