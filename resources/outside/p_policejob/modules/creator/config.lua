while not Config do Citizen.Wait(1) end

Config.Creator = {
    ---@field enabled: boolean [master toggle for the in-game creators (department + prison)]
    enabled = true,

    ---@field access: table [jobs allowed to open the creators - { jobName = minGrade }]
    access = {
        ['police']  = 15, -- KOMENDANT
        ['sheriff'] = 15,
    },

    ---@field allowAdmins: boolean [allow server admins to open the creators regardless of job/grade]
    allowAdmins = true,

    ---@field adminPermission: string [ace permission checked server-side when allowAdmins is true]
    adminPermission = 'group.admin',

    ---@field commands: table [creator chat commands - { department: string, prison: string }]
    commands = {
        department = 'departmentcreator',
        prison = 'prisoncreator',
    },

    ---@field previewPed: string [ped model used as the preview in the placement overlay]
    previewPed = 's_m_y_cop_01',
}
