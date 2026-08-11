while not Config do Citizen.Wait(1) end

Config.Camera = {
    ---@field Enabled: boolean [master toggle for the handheld camera feature]
    Enabled = true,

    ---@field Jobs: table [jobs allowed to use the camera - { jobName = minGrade }]
    Jobs = {
        ['police'] = 0,
        ['sheriff'] = 0,
    },

    ---@field onCameraStart: function [CLIENT - called when the camera mode opens]
    onCameraStart = function()
        lib.showTextUI(locale('camera_controls'))
    end,

    ---@field onCameraStop: function [CLIENT - called when the camera mode closes]
    onCameraStop = function()
        lib.hideTextUI()
    end,
}
