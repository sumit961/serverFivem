if not Config.Band.Enabled then
    return
end

Band = {
    tableName = "p_policejob_bands",
    playersWithBand = {},
}

GlobalState.playersWithBand = Band.playersWithBand

function Band.initDatabase(self)
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `p_policejob_bands` (
            `identifier` VARCHAR(60) NOT NULL,
            `name` VARCHAR(50) NOT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end

exports("SetPlayerBand", function(sourceId, targetId, state)
    if state then
        Band:attach(sourceId, targetId)
    else
        Band:remove(sourceId, targetId)
    end
end)

exports("HasPlayerBand", function(sourceId)
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    return Band.playersWithBand[identifier] ~= nil
end)

exports("GetPlayersWithBand", function()
    return Band.playersWithBand
end)

function Band.saveToDatabase(self, identifier, name)
    MySQL.insert(
        ("INSERT INTO `%s` (`identifier`, `name`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `name` = VALUES(`name`)"):format(self.tableName),
        { identifier, name }
    )
end

function Band.removeFromDatabase(self, identifier)
    MySQL.query(
        ("DELETE FROM `%s` WHERE `identifier` = ?"):format(self.tableName),
        { identifier }
    )
end

function Band.loadFromDatabase(self)
    local rows = MySQL.query.await(
        ("SELECT `identifier`, `name` FROM `%s`"):format(self.tableName)
    )
    if rows and #rows > 0 then
        for _, row in ipairs(rows) do
            self.playersWithBand[row.identifier] = {
                coords = nil,
                heading = nil,
                online = false,
                name = row.name,
            }
        end
        GlobalState.playersWithBand = self.playersWithBand
    end
end

function Band.attach(self, officerId, targetId)
    local job = Bridge.Framework.getPlayerJob(officerId)
    if not Config.Jobs[job.name] then
        return Bridge.Notify.showNotify(officerId, locale("no_access"), "error")
    end
    local identifier = Bridge.Framework.getUniqueId(targetId)
    if not identifier then
        return Bridge.Notify.showNotify(officerId, locale("player_not_found"), "error")
    end
    if self.playersWithBand[identifier] then
        return Bridge.Notify.showNotify(officerId, locale("this_player_have_band"), "error")
    end
    local targetPed = GetPlayerPed(targetId)
    local coords = GetEntityCoords(targetPed)
    local playerName = Bridge.Framework.getPlayerName(targetId)
    local heading = nil
    if Config.Band.Blip.heading then
        heading = GetEntityHeading(targetPed)
    end
    self.playersWithBand[identifier] = {
        coords = vector3(coords.x, coords.y, coords.z),
        heading = heading,
        online = true,
        name = playerName,
    }
    GlobalState.playersWithBand = self.playersWithBand
    Bridge.Inventory.removeItem(officerId, "tracking_band", 1)
    SetTimeout(2000, function()
        TriggerClientEvent("p_policejob/client/band/SetPlayerBand", targetId, true)
    end)
    self:saveToDatabase(identifier, playerName)
    Bridge.Logs.Send(officerId, "Band", locale("player_set_band_for_player", targetId), Config.Webhooks.band)
    if Config.Band.onAttach_Server then
        Config.Band.onAttach_Server(officerId, targetId)
    end
    Bridge.Debug(("[Band] Player %s attached band to player %s"):format(officerId, targetId))
end

function Band.remove(self, officerId, targetId)
    if not Bridge.Framework.getPlayerById(targetId) then
        return Bridge.Notify.showNotify(officerId, locale("player_not_found"), "error")
    end
    local identifier = Bridge.Framework.getUniqueId(targetId)
    if not self.playersWithBand[identifier] then
        return Bridge.Notify.showNotify(officerId, locale("this_player_dont_has_band"), "error")
    end
    local job = Bridge.Framework.getPlayerJob(officerId)
    local hasJobAccess = false
    if Config.Jobs[job.name] then
        hasJobAccess = tonumber(job.grade) >= Config.Jobs[job.name]
    end
    if hasJobAccess then
        Bridge.Inventory.addItem(officerId, "tracking_band", 1)
    end
    self.playersWithBand[identifier] = nil
    GlobalState.playersWithBand = self.playersWithBand
    SetTimeout(2000, function()
        TriggerClientEvent("p_policejob/client/band/SetPlayerBand", targetId, false)
    end)
    TriggerClientEvent("p_policejob/client/band/RemoveBandBlip", -1, { id = identifier })
    self:removeFromDatabase(identifier)
    Bridge.Logs.Send(officerId, "Band", locale("player_removed_band_from_player", targetId), Config.Webhooks.band)
    if Config.Band.onRemove_Server then
        Config.Band.onRemove_Server(officerId, targetId)
    end
    Bridge.Debug(("[Band] Player %s removed band from player %s"):format(officerId, targetId))
end

function Band.updateCoords(self)
    for identifier, playerData in pairs(self.playersWithBand) do
        local player = Bridge.Framework.getPlayerByUniqueId(identifier)
        if player then
            local sourceId = player.source or (player.PlayerData and player.PlayerData.source)
            if sourceId then
                local ped = GetPlayerPed(sourceId)
                local coords = GetEntityCoords(ped)
                playerData.coords = vector3(coords.x, coords.y, coords.z)
                if Config.Band.Blip.heading then
                    playerData.heading = GetEntityHeading(ped)
                end
                playerData.online = true
            end
        else
            playerData.online = false
        end
    end
    GlobalState.playersWithBand = self.playersWithBand
end

function Band.onPlayerLoaded(self, sourceId)
    Wait(3000)
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier then
        return
    end
    if self.playersWithBand[identifier] then
        self.playersWithBand[identifier].online = true
        GlobalState.playersWithBand = self.playersWithBand
        Wait(2500)
        TriggerClientEvent("p_policejob/client/band/SetPlayerBand", sourceId, true)
        Bridge.Logs.Send(sourceId, "Band", locale("player_joined_with_band"), Config.Webhooks.band)
        Bridge.Debug(("[Band] Player %s joined with active band"):format(sourceId))
    end
end

function Band.onPlayerDropped(self, sourceId)
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if identifier and self.playersWithBand[identifier] then
        self.playersWithBand[identifier].online = false
        GlobalState.playersWithBand = self.playersWithBand
        Bridge.Debug(("[Band] Player %s with band disconnected"):format(sourceId))
    end
end

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    Band:initDatabase()
    SetTimeout(500, function()
        Band:loadFromDatabase()
        SetTimeout(1500, function()
            for _, playerId in pairs(GetPlayers()) do
                local sourceId = tonumber(playerId)
                if sourceId then
                    Band:onPlayerLoaded(sourceId)
                end
                Wait(1)
            end
        end)
    end)
end)

AddEventHandler("p_bridge/server/playerLoaded", function(sourceId)
    Band:onPlayerLoaded(sourceId)
end)

AddEventHandler("playerDropped", function()
    Band:onPlayerDropped(source)
end)

RegisterNetEvent("p_policejob/server/band/SetPlayerBand", function(data)
    local sourceId = source
    if data.state then
        Band:attach(sourceId, data.player)
    else
        Band:remove(sourceId, data.player)
    end
end)

CreateThread(function()
    while true do
        Wait(Config.Band.UpdateCoordsRate)
        Band:updateCoords()
    end
end)
