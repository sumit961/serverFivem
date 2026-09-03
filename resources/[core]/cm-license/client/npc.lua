-- CM License System — Client NPC Interaction

local Constants = require 'shared.constants'
local Utils = require 'shared.utils'

local NPC = {}

-- NPC state tracking
NPC.LoadedModels = {}
NPC.Peds = {}

function NPC.Init()
    -- Load NPC data from server cache on demand
    print('^2[CM-License NPC]^7 NPC system initialized')
end

-- Load NPC model
function NPC.LoadModel(modelName)
    if not modelName then return false end

    local modelHash = GetHashKey(modelName)
    if NPC.LoadedModels[modelHash] then
        return true
    end

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if HasModelLoaded(modelHash) then
        NPC.LoadedModels[modelHash] = true
        return true
    end

    print('^1[CM-License]^7 Failed to load NPC model: ' .. modelName)
    return false
end

-- Spawn NPC
function NPC.Spawn(model, coords, heading)
    if not NPC.LoadModel(model) then
        return nil
    end

    local modelHash = GetHashKey(model)
    local ped = CreatePed(4, modelHash, coords.x, coords.y, coords.z, heading or 0.0, true, false)

    if not DoesEntityExist(ped) then
        return nil
    end

    -- Configure NPC
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    return ped
end

-- Check if player is near NPC and show interaction prompt
function NPC.CheckNPCInteraction()
    local playerCoords = GetEntityCoords(PlayerPedId())

    -- Request NPC locations from server
    TriggerServerEvent('cm-license:server:getNPCLocations', playerCoords)
end

-- Show license menu via NUI
function NPC.ShowLicenseMenu(licenses)
    SetNuiFocus(true, true)
    SendNuiMessage(json.encode({
        type = 'openLicenseMenu',
        licenses = licenses
    }))
end

-- Show my licenses dialog via NUI
function NPC.ShowMyLicenses(licenses)
    SetNuiFocus(true, true)
    SendNuiMessage(json.encode({
        type = 'showMyLicenses',
        licenses = licenses
    }))
end

-- Show test confirmation dialog
function NPC.ShowTestConfirmation(licenseType, price)
    SetNuiFocus(true, true)
    SendNuiMessage(json.encode({
        type = 'showTestConfirmation',
        licenseType = licenseType,
        price = price
    }))
end

-- Request to start test
function NPC.RequestStartTest(licenseType)
    TriggerServerEvent(Constants.EVENTS.SERVER.REQUEST_START_TEST, licenseType)
end

-- Cancel test
function NPC.CancelTest()
    TriggerServerEvent(Constants.EVENTS.SERVER.CANCEL_TEST)
end

-- Close menu
function NPC.CloseMenu()
    SetNuiFocus(false, false)
end

return NPC
