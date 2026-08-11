while not Config do Citizen.Wait(1) end

Config.RadioList = {}

---@field Enabled: boolean [master toggle for the radio list HUD feature]
Config.RadioList.Enabled = true

---@field ToggleKey: string|boolean [key to toggle the radio list HUD (false to disable the keybind)]
Config.RadioList.ToggleKey = 'G'

---@field MoveCommand: string|boolean [chat command to reposition the radio list HUD (false to disable)]
Config.RadioList.MoveCommand = 'radiolist'

---@field RestrictedJobs: table|boolean [jobs (and min grade) that can see the HUD - { jobName = minGrade } (false = everyone on a channel)]
Config.RadioList.RestrictedJobs = {
    ['police'] = 0,
    ['sheriff'] = 0,
}

---@field ChangePageKeys: table [keys to page the user list when more than 5 users connected - { left: string, right: string }]
Config.RadioList.ChangePageKeys = {
    ['left'] = 'LEFT',
    ['right'] = 'RIGHT',
}

---@field ChannelNames: table [friendly names shown beside the channel number, keyed by channel string = name]
Config.RadioList.ChannelNames = {
    ['1'] = 'LSPD',
    ['2'] = 'LSPD',
    ['3'] = 'LSPD',
    ['4'] = 'SHERIFF',
    ['5'] = 'SHERIFF',
}

---@field RadialChannels: table [channels offered in the police radial menu - list of { channel: number, label: string, icon: string }]
Config.RadioList.RadialChannels = {
    { channel = 1, label = 'LSPD #1', icon = 'walkie-talkie' },
    { channel = 2, label = 'LSPD #2', icon = 'walkie-talkie' },
    { channel = 3, label = 'LSPD #3', icon = 'walkie-talkie' },
    { channel = 4, label = 'Sheriff #1', icon = 'walkie-talkie' },
    { channel = 5, label = 'Sheriff #2', icon = 'walkie-talkie' },
}

---@field GetBadge: function [SERVER - return the badge/callsign string beside a player (nil to hide) - (playerId: number, identifier: string)]
Config.RadioList.GetBadge = function(playerId, identifier)
    return nil
end

---@field RadioAnimations: table [radio talk animations - list of { label: string, animDict: string, animClip: string, animFlag: number, prop?: table, isDefault?: boolean }]
Config.RadioAnimations = {
    {
        label = 'Holding radio',
        animDict = 'anim@male@holding_radio',
        animClip = 'holding_radio_clip',
        animFlag = 50,
        prop = {
            model = 'prop_cs_hand_radio',
            bone = 6286,
            coords = vector3(0.08, 0.03, -0.01),
            rotation = vector3(-59.99, 15.54, -52.55),
        }
    },
    {
        label = 'Fast talk',
        animDict = 'random@arrests',
        animClip = 'generic_radio_chatter',
        animFlag = 50,
        isDefault = true,
    },
    {
        label = 'Slow talk',
        animDict = 'amb@code_human_police_investigate@idle_a',
        animClip = 'idle_b',
        animFlag = 50,
    }
}
