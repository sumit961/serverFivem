while not Config do Citizen.Wait(1) end

Config.DrugTestKit = {
    ---@field enabled: boolean [master toggle for the drug test kit feature]
    enabled = true,

    ---@field itemName: string [inventory item registered to start a drug test]
    itemName = 'drug_test_kit',

    ---@field maxDistance: number [max distance (metres) between officer and target to start a test]
    maxDistance = 4.0,

    ---@field requireConsent: boolean [if true the target must accept the test before the officer's UI opens]
    requireConsent = true,

    ---@field testDuration: number [how long (ms) the analyzing animation runs before showing the result]
    testDuration = 6000,

    ---@field progressAnim: table [animation played on the officer during the test - { dict: string, clip: string, flag: number }]
    progressAnim = {
        dict = 'amb@medic@standing@kneel@base',
        clip = 'base',
        flag = 49,
    },

    ---@field notifyTarget: boolean [notify the target when the test starts and completes]
    notifyTarget = true,

    ---@field jobs: table [jobs allowed to use the kit - { jobName = minGrade } (or true for any grade)]
    jobs = {
        ['police'] = 0,
        ['sheriff'] = 0,
    },

    ---@field getDrugTestResults: function [integration point - return boolean, a substance string, or { positive: boolean, substances: string[], details: table } - (targetId: number, officerId: number)]
    getDrugTestResults = function(targetId, officerId)
        -- Example integration:
        -- if GetResourceState('my_drug_script') == 'started' then
        --     return exports['my_drug_script']:GetPlayerDrugTest(targetId)
        -- end

        return {
            positive = false,
            substances = {},
            details = {},
        }
    end,

    ---@field onOpen: function [CLIENT - called when the UI opens - (targetId: number)]
    onOpen = function(targetId)
    end,

    ---@field onClose: function [CLIENT - called when the UI closes - (targetId: number)]
    onClose = function(targetId)
    end,

    ---@field onTestStart: function [CLIENT - called when the test starts - (targetId: number)]
    onTestStart = function(targetId)
    end,

    ---@field onTestComplete: function [CLIENT - called when the test finishes - (targetId: number, result: any)]
    onTestComplete = function(targetId, result)
    end,

    ---@field onTestStart_Server: function [SERVER - called when the test starts - (officerId: number, targetId: number)]
    onTestStart_Server = function(officerId, targetId)
    end,

    ---@field onTestComplete_Server: function [SERVER - called when the test finishes - (officerId: number, targetId: number, result: any)]
    onTestComplete_Server = function(officerId, targetId, result)
    end,
}
