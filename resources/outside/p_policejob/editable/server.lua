lib.locale(Bridge?.Config?.Language or 'en')

-- editable server-side utility functions

Editable = {}

--- Validate a player-to-player interaction (server-side)
--- Checks: both exist, not same player, target ped exists, optional max distance
---@param playerId number Source player
---@param targetId number Target player
---@param maxDist? number Maximum allowed distance
---@return boolean
function Editable:canInteract(playerId, targetId, maxDist)
    if not playerId or not targetId then return false end
    if playerId == targetId then return false end
    if not GetPlayerPed(targetId) or GetPlayerPed(targetId) == 0 then return false end

    if maxDist then
        local playerCoords = GetEntityCoords(GetPlayerPed(playerId))
        local targetCoords = GetEntityCoords(GetPlayerPed(targetId))
        if #(playerCoords - targetCoords) > maxDist then return false end
    end

    return true
end

--- Check if a player is dead (server-side)
---@param playerId number
---@return boolean
function Editable:isPlayerDead(playerId)
    if GetResourceState('wasabi_ambulance_v2') == 'started' then
        local isDead = exports['wasabi_ambulance_v2']:isPlayerDead(playerId)
        return isDead
    end
    
    if GetResourceState('osp_ambulance') == 'started' then
        local ambulanceData = exports.osp_ambulance:GetAmbulanceData(playerId)
        if ambulanceData.isDead or ambulanceData.inLastStand then
            return true
        end

        return false
    end

    local state = Player(playerId).state
    if GetResourceState('ars_ambulancejob') == 'started' then
        return state.dead
    end

    
    return state.isDead
end

--- Get available licenses for wardrobe outfits
--- Modify this function to return licenses from your MDT or other source
---@return table Array of { value = string, label = string }
function Editable:getWardrobeLicenses(playerId)
    if GetResourceState('p_mdt') == 'started' then
        local plyJob = Bridge.Framework.getPlayerJob(playerId)
        if not plyJob or not plyJob.name then
            return {}
        end

        local mdtConfig = exports['p_mdt']:GetConfig()
        local Licenses = mdtConfig and mdtConfig.Departments and mdtConfig.Departments[plyJob.name] and mdtConfig.Departments[plyJob.name].licences or {}
        local formattedLicenses = {}
        for license, label in pairs(Licenses) do
            formattedLicenses[#formattedLicenses + 1] = { value = license, label = label }
        end
        return formattedLicenses
    end
    
    return {
        { value = 'weapon', label = 'Weapon License' },
        { value = 'drive', label = 'Driver License' },
        { value = 'pilot', label = 'Pilot License' },
        { value = 'boat', label = 'Boat License' },
    }
end

--- Usable items
Editable.UsableItems = {
    ['handcuffs'] = function(playerId)
        if Config.Interactions?.Cuffs?.usableItem then
            TriggerClientEvent('p_policejob/useHandcuffs', playerId)
        end
    end,

    ['police_shield'] = function(playerId)
        if Config.Objects?.Shield?.enabled then
            TriggerClientEvent('p_policejob/client/objects/togglePoliceShield', playerId)
        end
    end,

    ['body_cam'] = function(playerId)
        if Config.Bodycam?.Enabled then
            exports[GetCurrentResourceName()]:useBodyCamItem(playerId)
        end
    end,

    ['camera'] = function(playerId)
        if Config.Camera?.Enabled then
            TriggerClientEvent('p_policejob/client/camera/use', playerId)
        end
    end,

    ['breathalyzer'] = function(playerId)
        if Config.Breathalyzer?.Enabled then
            exports[GetCurrentResourceName()]:useBreathalyzerItem(playerId)
        end
    end,
    
    ['drug_test_kit'] = function(playerId)
        if Config.DrugTestKit?.enabled then
            exports[GetCurrentResourceName()]:useDrugTestKitItem(playerId)
        end
    end,
    
    ['tracking_vehicle'] = function(playerId)
        if Config.VehicleTracker?.Enabled then
            TriggerClientEvent('p_policejob:vehicleTracker:useItem', playerId)
        end
    end,

    ['police_diving_suit'] = function(playerId)
        if Config.DivingSuit?.enabled then
            TriggerClientEvent('p_policejob/client/divingsuit/activate', playerId)
            Bridge.Inventory.removeItem(playerId, 'police_diving_suit', 1)
            Bridge.Inventory.addItem(playerId, 'player_clothes', 1)
        end
    end,

    ['player_clothes'] = function(playerId)
        if Config.DivingSuit?.enabled then
            TriggerClientEvent('p_policejob/client/divingsuit/deactivate', playerId)
            Bridge.Inventory.removeItem(playerId, 'player_clothes', 1)
            Bridge.Inventory.addItem(playerId, 'police_diving_suit', 1)
        end
    end,

    ['gps'] = function(playerId)
        if Config.GPS?.enabled then
            TriggerClientEvent('p_policejob/client/gps/toggle', playerId)
        end
    end,

    ['megaphone'] = function(playerId)
        if Config.Megaphone?.enabled then
            TriggerClientEvent('p_policejob/client/megaphone/use', playerId)
        end
    end,

    ['nightvision'] = function(playerId)
        if Config.SmallItems?.NightVision?.enabled then
            TriggerClientEvent('p_policejob/client/smallitems/nightvision/use', playerId)
        end
    end,

    ['thermalvision'] = function(playerId)
        if Config.SmallItems?.ThermalVision?.enabled then
            TriggerClientEvent('p_policejob/client/smallitems/thermalvision/use', playerId)
        end
    end,

    ['battering_ram'] = function(playerId)
        if Config.BatteringRam?.enabled then
            TriggerClientEvent('p_policejob/client/batteringram/use', playerId)
        end
    end,
}

CreateThread(function()
    while not Bridge?.Framework do
        Citizen.Wait(500)
    end

    if Bridge.Framework.registerItem then
        for itemName, callback in pairs(Editable.UsableItems) do
            Bridge.Framework.registerItem(itemName, callback)
        end
        for itemName, itemData in pairs(Config?.Vests or {}) do
            Bridge.Framework.registerItem(itemName, function(playerId)
                TriggerClientEvent('p_policejob/use_vest/' .. itemName, playerId)
            end)
        end
        Bridge.Debug('Registered usable items')
    end
end)

RegisterNetEvent('p_policejob/server/toggleDuty', function()
    local _source = source
    local job = Bridge.Framework.getPlayerJob(_source)
    if not job or not Config.Jobs[job.name] then return end

    local onDuty = Bridge.Framework.CheckJobDuty(_source)
    Bridge.Framework.SetJobDuty(_source, not onDuty)
    lib.notify(_source, { title = locale(onDuty and 'duty_off' or 'duty_on'), type = 'success' })
end)

---@param src number
---@param message string
---@param msgType? string
local function commandReply(src, message, msgType)
    if src == 0 then
        lib.print.info(message)
    else
        lib.notify(src, { title = message, type = msgType or 'inform' })
    end
end

lib.addCommand('callsign', {
    help = 'Set your unit callsign',
    params = {
        { name = 'callsign', type = 'string', help = 'New callsign (e.g. 1A-12)' }
    },
    restricted = false
}, function(src, args)
    local job = Bridge.Framework.getPlayerJob(src)
    if not job or not Config.Jobs[job.name] then
        commandReply(src, 'You are not a police officer', 'error')
        return
    end

    local callsign = args.callsign
    if #callsign < 1 or #callsign > 12 then
        commandReply(src, 'Callsign must be 1-12 characters long', 'error')
        return
    end

    if Bridge.Framework.setPlayerMetadata(src, 'callsign', callsign) then
        commandReply(src, ('Callsign set to %s'):format(callsign), 'success')
    else
        commandReply(src, 'Could not set your callsign', 'error')
    end
end)

lib.addCommand('grantlicense', {
    help = 'Grant a license to a player',
    params = {
        { name = 'target', type = 'playerId', help = 'Target player server ID' },
        { name = 'license', type = 'string', help = 'License name (e.g. weapon, drive)' }
    },
    restricted = 'group.admin'
}, function(src, args)
    if Bridge.Framework.checkPlayerLicense(args.target, args.license) then
        commandReply(src, 'Player already has this license', 'error')
        return
    end

    if Bridge.Framework.addPlayerLicense(args.target, args.license) then
        commandReply(src, ('License %s granted to [%s] %s'):format(args.license, args.target, Bridge.Framework.getPlayerName(args.target) or ''), 'success')
        lib.notify(args.target, { title = ('You received the %s license'):format(args.license), type = 'success' })
    else
        commandReply(src, 'Could not grant the license', 'error')
    end
end)

lib.addCommand('revokelicense', {
    help = 'Revoke a license from a player',
    params = {
        { name = 'target', type = 'playerId', help = 'Target player server ID' },
        { name = 'license', type = 'string', help = 'License name (e.g. weapon, drive)' }
    },
    restricted = 'group.admin'
}, function(src, args)
    if not Bridge.Framework.checkPlayerLicense(args.target, args.license) then
        commandReply(src, 'Player does not have this license', 'error')
        return
    end

    if Bridge.Framework.removePlayerLicense(args.target, args.license) then
        commandReply(src, ('License %s revoked from [%s] %s'):format(args.license, args.target, Bridge.Framework.getPlayerName(args.target) or ''), 'success')
        lib.notify(args.target, { title = ('Your %s license was revoked'):format(args.license), type = 'error' })
    else
        commandReply(src, 'Could not revoke the license', 'error')
    end
end)

lib.addCommand('migrate_police_data', {
    help = 'Migrate p_policejob_v2 database tables to v3',
    params = {},
    restricted = 'group.admin'
}, function(src)
    local ok, rows = pcall(MySQL.query.await, 'SELECT * FROM police_outfits')
    if not ok or not rows then
        commandReply(src, 'v2 table police_outfits was not found in the database', 'error')
        return
    end

    if #rows == 0 then
        commandReply(src, 'No outfits found in police_outfits, nothing to convert', 'inform')
        return
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `p_policejob_outfits` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(64) NOT NULL,
            `job` VARCHAR(50) NOT NULL,
            `grades` JSON NOT NULL,
            `gender` VARCHAR(10) NOT NULL,
            `licenses` JSON DEFAULT NULL,
            `skin` LONGTEXT NOT NULL,
            `created_by` VARCHAR(100) NOT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_job_gender` (`job`, `gender`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    local inserted, skipped = 0, 0
    for i = 1, #rows do
        local outfit = rows[i]
        local requirements = outfit.requirements or 'required_grade'

        local grades = {}
        if requirements ~= 'required_license' then
            for grade in pairs(json.decode(outfit.grade or '{}') or {}) do
                grades[#grades + 1] = tonumber(grade)
            end
            table.sort(grades)
        end

        local licenses = nil
        if (requirements == 'required_license' or requirements == 'required_both') and outfit.license and outfit.license ~= 'none' then
            licenses = {}
            for license in pairs(json.decode(outfit.license) or {}) do
                licenses[#licenses + 1] = license
            end
            table.sort(licenses)
            if #licenses == 0 then licenses = nil end
        end

        local exists = MySQL.scalar.await('SELECT id FROM p_policejob_outfits WHERE name = ? AND job = ? AND gender = ?', { outfit.label, outfit.job, outfit.gender })
        if exists then
            skipped = skipped + 1
        else
            MySQL.insert.await('INSERT INTO p_policejob_outfits (name, job, grades, gender, licenses, skin, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)', {
                outfit.label,
                outfit.job,
                #grades > 0 and json.encode(grades) or '[]',
                outfit.gender,
                licenses and json.encode(licenses) or nil,
                outfit.skin,
                'v2 migration'
            })
            inserted = inserted + 1
        end
    end

    commandReply(src, ('Outfit conversion finished: %s converted, %s skipped (already converted)'):format(inserted, skipped), 'success')
end)
