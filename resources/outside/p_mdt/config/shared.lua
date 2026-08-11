Config = {} -- do not touch it!

--- IMPORTANT INFO:
--- Please setup your Framework, Target, Inventory etc in p_bridge config
Config.UseCache = true -- If true, some data will be cached for few seconds to reduce server load [good for high population servers]

---@class Config.Departments: Record<jobName: string, Department>
---@class Department
---@field label: string [Full department name]
---@field shortName: string [Short department name]
---@field image: string [URL to department image/logo]
---@field licences: table<string, string> [Table of licences available for officers in this department, it use own licence system!]
Config.Departments = {
    ['police'] = {
        label = 'Los Santos Police Department',
        shortName = 'LSPD',
        image = ('https://cfx-nui-%s/web/assets/lspd.png'):format(GetCurrentResourceName()),
        licences = {
            ['police_seu'] = 'SEU',
            ['police_eagle'] = 'Eagle'
        },
        citizen_licences = {
            ['driver'] = 'Driver License',
            ['firearm'] = 'Firearm License',
            ['pilot'] = 'Pilot License'
        },
        -- ESX grades 1-18 (must match job_grades table):
        -- 1 kadet | 2 officer | 3 officer2 | 4 officer3 | 5 officer4
        -- 6 sierzant | 7 sierzant2 | 8 sierzant3
        -- 9 porucznik1 | 10 porucznik2 | 11 porucznik3
        -- 12 capitan | 13 capitan2 | 14 capitan3
        -- 15 comendant | 16 deputyboss | 17 astboss | 18 boss
        bossGrades = {15, 16, 17, 18}, -- full MDT access + permissions panel + /mdt:editconfig
    }
}

--- Default MDT permissions applied when a grade has nothing saved in p_mdt_permissions.
--- bossGrades always receive every permission automatically.
Config.DefaultPermissions = {
    minOfficerGrade = 2, -- grade 2+ (OFICER I) gets officer permissions

    cadet = { -- grade 1 (KADET)
        ['dispatch.view'] = true,
        ['dispatch.respond_call'] = true,
        ['bolo.view'] = true,
        ['chat.view'] = true,
        ['chat.send'] = true,
        ['dashboard.units'] = true,
        ['dashboard.incidents'] = true,
        ['dashboard.bolos'] = true,
        ['reports.view'] = true,
        ['warrants.view'] = true,
        ['incidents.view'] = true,
        ['citizens.view'] = true,
        ['vehicles.view'] = true,
        ['bodycam.view'] = true,
    },

    officer = { -- grades 2-14
        ['logs.view'] = true,
        ['bulletin.view'] = true,
        ['bulletin.create'] = true,
        ['bulletin.delete'] = true,
        ['bolo.view'] = true,
        ['bolo.create'] = true,
        ['bolo.edit'] = true,
        ['bolo.delete'] = true,
        ['bolo.change_status'] = true,
        ['chat.view'] = true,
        ['chat.send'] = true,
        ['dashboard.units'] = true,
        ['dashboard.incidents'] = true,
        ['dashboard.bolos'] = true,
        ['dashboard.global_search'] = true,
        ['dispatch.view'] = true,
        ['dispatch.create_call'] = true,
        ['dispatch.delete_call'] = true,
        ['dispatch.respond_call'] = true,
        ['reports.view'] = true,
        ['reports.create'] = true,
        ['reports.edit'] = true,
        ['reports.delete'] = true,
        ['garage.view'] = true,
        ['garage.impound'] = true,
        ['garage.mark_car'] = true,
        ['employees.view'] = true,
        ['employees.view_location'] = true,
        ['applications.view'] = true,
        ['applications.review'] = true,
        ['bodycam.view'] = true,
        ['bodycam.watch'] = true,
        ['judgments.view'] = true,
        ['judgments.issue'] = true,
        ['charges.view'] = true,
        ['charges.create_charge'] = true,
        ['charges.edit_charge'] = true,
        ['charges.delete_charge'] = true,
        ['warrants.view'] = true,
        ['warrants.create'] = true,
        ['warrants.delete'] = true,
        ['incidents.view'] = true,
        ['incidents.create'] = true,
        ['incidents.edit'] = true,
        ['incidents.delete'] = true,
        ['evidences.view'] = true,
        ['evidences.register'] = true,
        ['evidences.remove'] = true,
        ['weapons.view'] = true,
        ['weapons.register'] = true,
        ['properties.view'] = true,
        ['vehicles.view'] = true,
        ['vehicles.add_note'] = true,
        ['vehicles.remove_note'] = true,
        ['vehicles.add_photo'] = true,
        ['vehicles.remove_photo'] = true,
        ['vehicles.change_avatar'] = true,
        ['citizens.view'] = true,
        ['citizens.change_avatar'] = true,
        ['citizens.add_note'] = true,
        ['citizens.remove_note'] = true,
        ['citizens.view_notes'] = true,
        ['citizens.view_vehicles'] = true,
        ['citizens.view_properties'] = true,
        ['citizens.view_licenses'] = true,
        ['citizens.revoke_license'] = true,
        ['citizens.view_judgments'] = true,
        ['citizens.remove_judgment'] = true,
        ['citizens.view_warrants'] = true,
        ['citizens.view_reports'] = true,
        ['citizens.add_licences'] = true,
    },
}

---@class Config.MDT
---@field commandName: string | false [Command name to open MDT, false to disable command]
---@field itemName: string | false [Item name to open MDT, false to disable item usage]
---@field canOpenMDT: function [Function to determine if player can open MDT]
Config.MDT = {
    commandName = 'mdt',
    itemName = 'police_mdt',
    canOpenMDT = function()
        local stateBags = {'isDead', 'isCuffed', 'dead', 'draggedBy'}
        local playerState = LocalPlayer.state
        for _, bag in ipairs(stateBags) do
            if playerState[bag] then
                return false
            end
        end
        if IsPauseMenuActive() then
            return false
        end
        
        return true
    end,
    chargeTypes = {'Felony', 'Misdemeanor', 'Infraction'},
    disabledSections = {
        -- / dispatch / bolos / citizens / vehicles / properties / weapons / evidences 
        -- / incidents / warrants / charges / reports / judgments / bodycam / applications
        -- / employees / garage / permissions / logs
        ['bodycam'] = GetResourceState('p_policejob') == 'missing',
        -- ['logs'] = true,
        -- ['garage'] = true,
        -- ['applications'] = true,
    },
}

---@class Config.Dispatch
---@field requireDuty: boolean [If true, only players on duty can receive dispatch alerts]
---@field alertsNotification: boolean [If true, players will receive notifications for new dispatch alerts]
---@field supervisorRole: boolean [If true, the first unit to accept an alert is assigned as supervisor, others as regular units, supervisor can finish alert with even active units and also change supervisor]
---@field allowJoiningMultipleAlerts: boolean [If true, officers can join multiple active dispatch alerts]
---@field allowDeleteWithActiveUnits: boolean [If true, dispatch alerts can be deleted even if there are active units assigned]
---@field alertsMenuKey: string | false [Keybind to open the alerts menu, false to disable keybind]
---@field keybinds: table<string, string> [Keybinds for dispatch actions]
Config.Dispatch = {
    disableClientExport = false, -- set to true if you dont want sending alerts from client to server
    disableDispatch = false, -- set to true to disable dispatch system if you want to use different [disable also in disabledSections]
    requireDuty = false,
    alertsNotification = true,
    supervisorRole = true,
    allowJoiningMultipleAlerts = true,
    allowDeleteWithActiveUnits = true,
    alertsMenuKey = 'F9',
    keybinds = {
        ['acceptAlert'] = 'Z',
        ['dismissAlert'] = 'O',
        ['viewAlert'] = 'G',
        ['expandAlert'] = 'J'
    },

    -- YOU CAN ADJUST ALL ALERT IN modules/dispatch/client_alerts.lua !
    defaultAlerts = {
        ['shooting'] = true,
        ['carjacking'] = true,
        ['vehicletheft'] = true,
        ['fight'] = true,
        ['speeding'] = true,
        ['explosion'] = true,
    }
}


---@class Config.Evidences
---@field itemsMetadata: Record<metadataKey: string, displayName: string> [Table defining metadata keys and their display names for evidence items]
Config.Evidences = {
    depositType = 'digital', -- physical | digital [physical = player need to register evidence item at some coords, digital = through mdt, will remove instantly item]
    depositPoints = {
        ['police'] = {
            vec3(460.86, -989.10, 24.87),
        },
    },
    -- what metadata will be visible in select menu in register evidence
    itemsMetadata = {
        ['serial'] = 'Serial Number',
        ['fingerprint'] = 'Fingerprint',
        ['dna'] = 'DNA Sample'
    }
}

---@class Config.Garage
---@field canImpoundOccupied: boolean [If true, players can impound vehicles that are occupied]
---@field savePropsOnImpound: boolean [If true, vehicle properties will be saved when impounding]
---@field maxParkDistance: number | false [Maximum distance to park a vehicle from the garage point, false to disable limit]
---@field retrieveOnRestart: boolean [If true, vehicles that were in the garage will be retrieved on server restart]
Config.Garage = {
    canImpoundOccupied = false,
    savePropsOnImpound = true,
    maxParkDistance = 5.0,
    retrieveOnRestart = true
}

---@class Config.Applications
---@field enabled: boolean [If true, applications system is enabled]
---@field points: table<string, {title: string, subtitle: string, coords: vector3[]}> [Table of application points by job name]
Config.Applications = {
    enabled = true,
    points = {
        ['police'] = {
            title = 'Police Department Application',
            subtitle = 'Complete all sections to submit your application to join the police force',
            coords = {
                vec3(441.14, -980.34, 30.91),
            }
        },
    },
    onReview = function(sourceId, applicationData, message)
        -- server side function
    end
}

---@class Config.Logs
---@field enabled boolean [If true, logging in MDT is enabled, false = only discord logs]
---@field queryLimit number [Maximum number of logs to query from the database]
---@field expireTime number [Time in seconds after which logs will be deleted]
Config.Logs = {
    enabled = true,
    queryLimit = 500,
    expireTime = 30 * 24 * 60 * 60 -- time in seconds after which logs will be deleted (30 days)
}