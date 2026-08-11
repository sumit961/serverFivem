if not Config.Mugshot.enabled then
    return
end

Mugshot = {
    records = {},
}

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `police_mugshots` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `url` LONGTEXT NOT NULL,
            `suspect` VARCHAR(100) NOT NULL,
            `dob` VARCHAR(20) DEFAULT NULL,
            `officer` VARCHAR(100) NOT NULL,
            `description` TEXT,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    Bridge.Debug("[Mugshot] Database table verified")
end)

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    Wait(2000)
    local success, rows = pcall(MySQL.query.await, "SELECT * FROM police_mugshots")
    if not success then
        lib.print.error("[Mugshot] Failed to fetch mugshots — import the SQL file from INSTALL folder!")
        return
    end
    for index, row in ipairs(rows) do
        Mugshot.records[index] = {
            id = index,
            url = row.url,
            suspect = row.suspect,
            dob = row.dob,
            officer = row.officer,
            description = row.description,
        }
    end
    Bridge.Debug(("[Mugshot] Loaded %d mugshots from database"):format(#Mugshot.records))
end)

lib.callback.register("p_policejob/server/mugshot/getMugshots", function(_, searchQuery)
    if not searchQuery then
        return Mugshot.records
    end
    local query = string.lower(tostring(searchQuery))
    local results = {}
    for _, record in ipairs(Mugshot.records) do
        if tostring(record.id):find(query)
            or record.suspect:lower():find(query)
            or record.officer:lower():find(query)
            or record.description:lower():find(query)
            or record.dob:lower():find(query)
        then
            results[#results + 1] = record
        end
    end
    return results
end)

RegisterNetEvent("p_policejob/server/mugshot/takePhoto", function(photoData)
    local officerId = source
    if not photoData or type(photoData) ~= "table" or not photoData.name or not photoData.playerId or photoData.playerId < 0 then
        return
    end
    local location = Config.DepartmentData.mugshots[photoData.name]
    if not location then
        return
    end
    local job = Bridge.Framework.getPlayerJob(officerId)
    if not Config.Jobs[job.name] then
        return
    end
    local targetId = photoData.playerId
    if not GetPlayerPed(targetId) then
        return Bridge.Notify.showNotify(officerId, locale("player_is_offline"), "error")
    end
    local targetCoords = GetEntityCoords(GetPlayerPed(targetId))
    if #(targetCoords - location.photoCoords) > 3.0 then
        return Bridge.Notify.showNotify(officerId, locale("mugshot_player_is_too_far"), "error")
    end
    local suspectName = Bridge.Framework.getPlayerName(targetId)
    local dob = Bridge.Framework.getPlayerDob(targetId) or ""
    local description = tostring(photoData.info and photoData.info.description or "")
    local photoUrl = lib.callback.await("p_policejob/client/mugshot/takePhoto", targetId, {
        name = photoData.name,
        info = {
            dob = dob,
            description = description,
        },
    })
    if not photoUrl then
        return
    end
    local recordId = #Mugshot.records + 1
    local officerName = Bridge.Framework.getPlayerName(officerId)
    local record = {
        id = recordId,
        url = photoUrl,
        suspect = suspectName,
        dob = dob,
        officer = officerName,
        description = description,
    }
    Mugshot.records[recordId] = record
    MySQL.insert(
        "INSERT INTO police_mugshots (url, suspect, dob, officer, description) VALUES (?, ?, ?, ?, ?)",
        { photoUrl, suspectName, dob, officerName, description }
    )
    Config.Mugshot.SendPhoto({
        url = photoUrl,
        webhook = Config.Webhooks and Config.Webhooks.mugshot or "",
        id = recordId,
        suspect = suspectName,
        dob = dob,
        officer = officerName,
        description = description,
    })
    Bridge.Logs.Send(
        officerId,
        "Mugshot",
        locale("mugshot_taken", suspectName),
        Config.Webhooks and Config.Webhooks.mugshot or ""
    )
end)

RegisterNetEvent("p_policejob/server/mugshot/remove", function(recordId)
    local playerId = source
    if not Mugshot.records[recordId] then
        return Bridge.Notify.showNotify(playerId, locale("mugshot_doesnt_exist", recordId), "error")
    end
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Config.Jobs[job.name] then
        return
    end
    table.remove(Mugshot.records, recordId)
    MySQL.update("DELETE FROM police_mugshots WHERE id = ?", { recordId })
    Config.Mugshot.onPhotoRemoved(playerId, recordId)
    Bridge.Notify.showNotify(playerId, locale("mugshot_removed", recordId), "success")
end)
