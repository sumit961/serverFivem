while not Config do Citizen.Wait(1) end

-- An item that lets police force a locked door open with an animation + prop.
-- The doorlock interaction lives in getTargetDoor / forceDoor so it can be adapted
-- to any doorlock script (ox_doorlock by default).
Config.BatteringRam = {
    ---@field enabled: boolean [master toggle for the battering ram feature]
    enabled = true,

    ---@field item: string [inventory item that triggers the ram (registered as a usable item)]
    item = 'battering_ram',

    ---@field jobs: table|nil [jobs allowed to use it - { jobName = minGrade } (nil reuses the global Config.Jobs)]
    jobs = nil,

    ---@field duration: number [time (ms) the forcing animation plays before the door is forced]
    duration = 2500,

    ---@field cooldown: number [cooldown (ms) between uses]
    cooldown = 6000,

    ---@field anim: table [forcing animation - { dict: string, clip: string, flag: number }]
    anim = { dict = 'battering_ram', clip = 'hit', flag = 1 },

    ---@field prop: table [ram prop attached to the officer hand - { model: string, bone: number, pos: vector3, rot: vector3 }]
    prop = {
        model = 'rambar',
        bone = 28422,
        pos = vector3(0.25, -0.1, -0.21),
        rot = vector3(103.8, -27.51, -125.08),
    },

    ---@field getTargetDoor: function [edit for your doorlock - return the door in front of the player, or nil. The return value is passed to forceDoor]
    getTargetDoor = function()
        if GetResourceState('ox_doorlock') ~= 'started' then return nil end
        return exports.ox_doorlock:getClosestDoor()
    end,

    ---@field forceDoor: function [edit for your doorlock - force the given door open, return true on success - (door: any)]
    forceDoor = function(door)
        if not door then return false end
        if door.state == 0 then return false end
        TriggerServerEvent('p_policejob/server/batteringram/forceDoor', door.id)
        return true
    end,
}
