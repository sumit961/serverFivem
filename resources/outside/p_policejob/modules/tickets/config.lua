while not Config do Citizen.Wait(1) end

Config.Tickets = {
    enabled = true,

    ---@field command: string [chat command used to open the traffic tickets menu]
    command = 'issueTicket',

    ---@field maxDistance: number [max distance between officer and target player]
    maxDistance = 5.0,

    ---@field maxFine: number [max fine which officer can issue]
    maxFine = 50000,

    ---@field signTimeout: number [seconds shown to the citizen as the signing window (informational; the sign request stays valid until the citizen accepts/refuses or disconnects)]
    signTimeout = 30,

    ---@field points: table [license penalty point system - points are added to the citizen once a ticket is signed or marked as paid]
    points = {
        enabled = true,

        ---@field suspendThreshold: number [citizen's driver license gets suspended when reaching this many points]
        suspendThreshold = 12,

        ---@field resetOnSuspension: boolean [reset the citizen's points back to 0 after the license is suspended]
        resetOnSuspension = true,
    },

    ---@field violations: table [list of violations with fine and points]
    violations = {
        { id = 'speeding_minor',   name = 'Speeding (1-15 over)',       fine = 150,  points = 1, category = 'speeding' },
        { id = 'speeding_moderate', name = 'Speeding (16-30 over)',     fine = 350,  points = 2, category = 'speeding' },
        { id = 'speeding_major',   name = 'Speeding (31+ over)',        fine = 750,  points = 4, category = 'speeding' },
        { id = 'red_light',        name = 'Running Red Light',          fine = 500,  points = 3, category = 'traffic' },
        { id = 'stop_sign',        name = 'Failure to Stop',            fine = 250,  points = 2, category = 'traffic' },
        { id = 'illegal_turn',     name = 'Illegal Turn',               fine = 200,  points = 1, category = 'traffic' },
        { id = 'reckless',         name = 'Reckless Driving',           fine = 1000, points = 5, category = 'dangerous' },
        { id = 'wrong_way',        name = 'Wrong Way Driving',          fine = 600,  points = 3, category = 'dangerous' },
        { id = 'no_license',       name = 'Driving Without License',    fine = 500,  points = 0, category = 'documents' },
        { id = 'no_insurance',     name = 'No Insurance',               fine = 750,  points = 0, category = 'documents' },
        { id = 'expired_reg',      name = 'Expired Registration',       fine = 200,  points = 0, category = 'documents' },
        { id = 'illegal_parking',  name = 'Illegal Parking',            fine = 100,  points = 0, category = 'parking' },
        { id = 'tinted_windows',   name = 'Illegal Window Tint',        fine = 300,  points = 0, category = 'vehicle' },
        { id = 'no_seatbelt',      name = 'No Seatbelt',                fine = 150,  points = 1, category = 'safety' },
        { id = 'phone_driving',    name = 'Using Phone While Driving',  fine = 400,  points = 2, category = 'safety' },
    },

    ---@field categories: table [violation categories for filtering]
    categories = {
        { value = 'all',       label = 'All Violations' },
        { value = 'speeding',  label = 'Speeding' },
        { value = 'traffic',   label = 'Traffic' },
        { value = 'dangerous', label = 'Dangerous Driving' },
        { value = 'documents', label = 'Documents' },
        { value = 'parking',   label = 'Parking' },
        { value = 'vehicle',   label = 'Vehicle' },
        { value = 'safety',    label = 'Safety' },
    },

    ---@field OnPlayerFined: function [called when a player is fined - customize payment logic here]
    ---@param officerId number [the server ID of the officer who issued the ticket]
    ---@param targetId number [the server ID of the player who received the ticket]
    ---@param fineAmount number [the amount of the fine]
    OnPlayerFined = function(officerId, targetId, fineAmount)
        Bridge.Framework.removeMoney(targetId, 'bank', fineAmount)
    end,

    ---@field OnLicenseSuspended: function [called when a citizen reaches the points threshold - customize license removal logic here]
    ---@param targetId number|nil [the server ID of the citizen, nil if they are offline]
    ---@param citizenId string [the unique/citizen ID of the citizen]
    ---@param totalPoints number [the total points the citizen reached]
    OnLicenseSuspended = function(targetId, citizenId, totalPoints)
        local player = Bridge.Framework.getOfflinePlayerByCitizenId(citizenId)
        if not player or not player.identifier then return end

        MySQL.query('DELETE FROM user_licenses WHERE owner = ? AND type IN (?, ?)', { player.identifier, 'drive', 'driver' })
    end,
}
