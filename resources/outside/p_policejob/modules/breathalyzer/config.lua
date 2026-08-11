while not Config do Citizen.Wait(1) end

Config.Breathalyzer = {
    ---@field Enabled: boolean [master toggle for the breathalyzer feature]
    Enabled = true,

    ---@field thresholds: table [BAC limits - { warning: number (yellow), overLimit: number (red) }]
    thresholds = {
        warning = 0.05,
        overLimit = 0.08,
    },

    ---@field colors: table [device screen colours per state, any valid CSS colour string]
    colors = {
        ---@field idle: string [screen colour when idle / value below warning]
        idle      = 'rgb(84, 235, 147)',
        ---@field testing: string [screen colour while a test is running]
        testing   = '#b58900',
        ---@field warning: string [screen colour when value is between warning and overLimit]
        warning   = '#b56b00',
        ---@field overLimit: string [screen colour when value is at/above overLimit]
        overLimit = '#b00020',
    },

    ---@field requireConsent: boolean [if true the suspect must accept the test before the device opens for the officer]
    requireConsent = true,

    ---@field getDrunkLevel: function [CLIENT - returns the local player's current BAC/drunk value; add a branch for your drunk script]
    getDrunkLevel = function()
        if GetResourceState('rcore_drunk') == 'started' then
            return exports['rcore_drunk']:GetMilligramsAlcoholInBlood()
        elseif GetResourceState('devcore_needs') == 'started' then
            return exports['devcore_needs']:GetAlcoholValue()
        elseif GetResourceState('nrg_alcoeffect') == 'started' then
            return exports['nrg_alcoeffect']:GetDrunkLevel()
        elseif GetResourceState('pixel-consumables') == 'started' then
            return exports['pixel-consumables']:GetBACLevel()
        elseif GetResourceState('Renewed-Drunk') == 'started' then
            local ok, value = pcall(function() return exports['Renewed-Drunk']:getDrunk() end)
            if ok and value then return value end
        elseif GetResourceState('brutal_drugs') == 'started' then
            local ok, value = pcall(function() return exports['brutal_drugs']:GetAlcoholLevel() end)
            if ok and value then return value end
        elseif GetResourceState('jl_drunksystem') == 'started' then
            local ok, value = pcall(function() return exports['jl_drunksystem']:GetDrunkLevel() end)
            if ok and value then return value end
        elseif GetResourceState('okok-drinks') == 'started' then
            local ok, value = pcall(function() return exports['okok-drinks']:GetAlcohol() end)
            if ok and value then return value end
        elseif GetResourceState('codem-drugsystem') == 'started' then
            local ok, value = pcall(function() return exports['codem-drugsystem']:GetAlcoholLevel() end)
            if ok and value then return value end
        elseif GetResourceState('qb-smallresources') == 'started' then
            local QBCore = exports['qb-core'] and exports['qb-core']:GetCoreObject()
            if QBCore then
                local data = QBCore.Functions.GetPlayerData()
                if data and data.metadata and data.metadata.alcohol then
                    return data.metadata.alcohol
                end
            end
        elseif GetResourceState('esx_status') == 'started' then
            local p = promise.new()
            TriggerEvent('esx_status:getStatus', 'drunk', function(status)
                p:resolve(status.getPercent())
            end)
            return Citizen.Await(p)
        end

        -- Fallback: many drunk scripts publish a value on the player entity state.
        local state = LocalPlayer and LocalPlayer.state
        if state then
            if state.bac then return state.bac end
            if state.alcohol then return state.alcohol end
            if state.drunk then return state.drunk end
        end

        return 0
    end,

    ---@field onTestStart: function [CLIENT - called when a test starts - (targetId: number)]
    onTestStart = function(targetId)
    end,

    ---@field onTestComplete: function [CLIENT - called when a test completes - (targetId: number, result: number)]
    onTestComplete = function(targetId, result)
    end,

    ---@field onOpen: function [CLIENT - called when the breathalyzer UI opens]
    onOpen = function()
    end,

    ---@field onClose: function [CLIENT - called when the breathalyzer UI closes]
    onClose = function()
    end,

    ---@field onTestStart_Server: function [SERVER - called when a test starts - (playerId: number, targetId: number)]
    onTestStart_Server = function(playerId, targetId)
    end,

    ---@field onTestComplete_Server: function [SERVER - called when a test completes - (playerId: number, targetId: number, result: number)]
    onTestComplete_Server = function(playerId, targetId, result)
    end,
}
