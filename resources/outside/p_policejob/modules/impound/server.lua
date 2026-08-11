while not Config or not Config.Impound do
    Citizen.Wait(500)
end

if not Config.Impound.Enabled then
    return
end

Impound = {
    records = {},
}

function trimString(value, maxLength)
    if type(value) ~= "string" then
        return ""
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if maxLength and #value > maxLength then
        value = value:sub(1, maxLength)
    end
    return value
end

function normalizePlate(plate)
    if type(plate) ~= "string" then
        return ""
    end
    return plate:gsub("^%s+", ""):gsub("%s+$", "")
end

function validatePhotoUrl(url)
    url = trimString(url, 512)
    if url ~= "" and url:match("^https?://") then
        return url
    end
    return nil
end

function setVehicleImpoundState(plate, impounded)
    local vehicleState = Config.Impound.VehicleState
    local mode = vehicleState and vehicleState.mode or "auto"
    if mode == "none" then
        return
    end
    if mode == "custom" then
        local callback = impounded and vehicleState.onImpound or vehicleState.onRelease
        if type(callback) == "function" then
            local ok, err = pcall(callback, plate)
            if not ok then
                Bridge.Debug(("[Impound] VehicleState.%s failed: %s"):format(
                    impounded and "onImpound" or "onRelease",
                    tostring(err)
                ))
            end
        end
        return
    end
    Bridge.Framework.setVehicleImpounded(plate, impounded)
end

function pushImpoundToMdt(payload)
    local mdtConfig = Config.Impound.MDT
    if not mdtConfig or not mdtConfig.enabled or type(mdtConfig.push) ~= "function" then
        return
    end
    local resourceName = mdtConfig.resource or "p_mdt"
    if GetResourceState(resourceName) ~= "started" then
        return
    end
    local ok, err = pcall(mdtConfig.push, payload)
    if not ok then
        Bridge.Debug(("[Impound] MDT push failed: %s"):format(tostring(err)))
    end
end

CreateThread(function()
    while not MySQL do
        Wait(50)
    end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `police_impound` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `plate` VARCHAR(20) NOT NULL UNIQUE,
            `owner` VARCHAR(50) NOT NULL,
            `vehicle` LONGTEXT NOT NULL,
            `location` VARCHAR(50) NOT NULL,
            `reason` TEXT NOT NULL,
            `notes` LONGTEXT NULL,
            `photo` TEXT NULL,
            `price` INT NOT NULL DEFAULT 0,
            `duration` INT NOT NULL,
            `officer_name` VARCHAR(100) NOT NULL,
            `officer_id` VARCHAR(50) NOT NULL,
            `impounded_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]])
    function ensureColumn(columnName, alterSql)
        local exists = MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'police_impound' AND COLUMN_NAME = ?
        ]], { columnName })
        if not exists or exists == 0 then
            MySQL.query.await(("ALTER TABLE `police_impound` ADD COLUMN %s"):format(alterSql))
            Bridge.Debug(("[Impound] Added missing column `%s`"):format(columnName))
        end
    end
    ensureColumn("notes", "`notes` LONGTEXT NULL AFTER `reason`")
    ensureColumn("photo", "`photo` TEXT NULL AFTER `notes`")
    Bridge.Debug("[Impound] Database table created or verified")
end)

lib.callback.register("p_policejob/server/impound/checkOwnedVehicle", function(playerId, plate, netId)
    if not plate then
        return false
    end
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job or not Config.Jobs[job.name] or job.grade < Config.Jobs[job.name] then
        return false
    end
    plate = normalizePlate(plate)
    return Bridge.Framework.getOwnedVehicle(plate) ~= nil
end)

RegisterNetEvent("p_policejob/server/impound/removeUnownedVehicle", function(netId)
    local playerId = source
    local unownedConfig = Config.Impound.UnownedVehicles
    if not unownedConfig or not unownedConfig.remove then
        return
    end
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job or not Config.Jobs[job.name] or job.grade < Config.Jobs[job.name] then
        return Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
    end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return Bridge.Notify.showNotify(playerId, locale("impound_vehicle_error"), "error")
    end
    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    if Bridge.Framework.getOwnedVehicle(plate) then
        return
    end
    DeleteEntity(vehicle)
    Bridge.Notify.showNotify(playerId, locale("impound_unowned_removed", plate), "success")
    if Config.Webhooks and Config.Webhooks.impound then
        Bridge.Logs.Send(
            playerId,
            "Impound",
            ("Unowned vehicle %s removed"):format(plate),
            Config.Webhooks.impound
        )
    end
end)

RegisterNetEvent("p_policejob/server/impound/startImpound", function(data)
    if not data or type(data) ~= "table" or not data.netId or not data.reason or not data.location then
        return
    end
    local playerId = source
    local vehicle = NetworkGetEntityFromNetworkId(data.netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return Bridge.Notify.showNotify(playerId, locale("impound_vehicle_error"), "error")
    end
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job or not Config.Jobs[job.name] or job.grade < Config.Jobs[job.name] then
        return Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
    end
    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    local ownedVehicle = Bridge.Framework.getOwnedVehicle(plate)
    if not ownedVehicle then
        DeleteEntity(vehicle)
        return Bridge.Notify.showNotify(playerId, locale("impound_vehicle_not_owned"), "error")
    end
    local now = os.time()
    local price = math.max(0, math.floor(tonumber(data.price) or 0))
    local releaseAt = tonumber(data.releaseAt)
    local duration
    if releaseAt and now < releaseAt then
        duration = math.floor(releaseAt)
    else
        local hours = tonumber(data.time)
        if not hours or hours <= 0 then
            hours = Config.Impound.Time
        end
        duration = now + (hours * 3600)
    end
    local reason = trimString(data.reason, 255)
    local notes = trimString(data.notes, 1000)
    local photo = validatePhotoUrl(data.photo)
    local modelLabel = trimString(data.model, 100)
    local photoConfig = Config.Impound.Photo
    if photoConfig and photoConfig.enabled and photoConfig.required and not photo then
        return Bridge.Notify.showNotify(playerId, locale("impound_photo_required"), "error")
    end
    DeleteEntity(vehicle)
    setVehicleImpoundState(plate, true)
    local officerName = Bridge.Framework.getPlayerName(playerId)
    local officerId = Bridge.Framework.getUniqueId(playerId)
    local record = {
        plate = plate,
        owner = ownedVehicle.owner,
        vehicle = ownedVehicle.props or "{}",
        location = data.location,
        reason = reason,
        notes = notes,
        photo = photo,
        price = price,
        duration = duration,
        officer_name = officerName,
        officer_id = officerId,
    }
    local insertId = MySQL.insert.await([[
        INSERT INTO police_impound (plate, owner, vehicle, location, reason, notes, photo, price, duration, officer_name, officer_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        record.plate,
        record.owner,
        record.vehicle,
        record.location,
        record.reason,
        record.notes,
        record.photo,
        record.price,
        record.duration,
        record.officer_name,
        record.officer_id,
    })
    if insertId then
        Bridge.Notify.showNotify(playerId, locale("impound_success", plate), "success")
        if Config.Impound.OnVehicleImpounded then
            Config.Impound.OnVehicleImpounded(playerId, plate, reason)
        end
        pushImpoundToMdt({
            plate = plate,
            owner = ownedVehicle.owner,
            model = modelLabel,
            officerName = officerName,
            officerId = officerId,
            offence = reason,
            notes = notes,
            price = price,
            impoundedAt = now,
            releaseAt = duration,
            photo = photo,
            location = data.location,
        })
        if Config.Webhooks and Config.Webhooks.impound then
            local notesText = notes ~= "" and ("\n\nNotes: %s"):format(notes) or ""
            local photoText = photo and ("\n\nPhoto: %s"):format(photo) or ""
            Bridge.Logs.Send(
                playerId,
                "Impound",
                ("Vehicle %s (%s) impounded by %s\nOffence: %s\nFine: $%s\nRelease: %s%s%s"):format(
                    plate,
                    modelLabel ~= "" and modelLabel or "Unknown",
                    officerName,
                    reason ~= "" and reason or "N/A",
                    price,
                    os.date("%Y-%m-%d %H:%M", duration),
                    notesText,
                    photoText
                ),
                Config.Webhooks.impound
            )
        end
    else
        Bridge.Notify.showNotify(playerId, locale("impound_failed"), "error")
    end
end)

lib.callback.register("p_policejob/server/impound/getImpoundedVehicles", function(playerId, location)
    if not location then
        return {}
    end
    local ownerId = Bridge.Framework.getUniqueId(playerId)
    local rows = MySQL.query.await(
        "SELECT * FROM police_impound WHERE location = ? AND owner = ? ORDER BY impounded_at DESC",
        { location, ownerId }
    )
    if rows and #rows > 0 then
        local now = os.time()
        for _, row in pairs(rows) do
            row.timeLeft = math.max(0, row.duration - now)
        end
        return rows
    end
    return {}
end)

lib.callback.register("p_policejob/server/impound/payoutVehicle", function(playerId, data)
    if not data or type(data) ~= "table" or not data.plate or not data.location then
        return false
    end
    local ownerId = Bridge.Framework.getUniqueId(playerId)
    local plate = normalizePlate(data.plate)
    local rows = MySQL.query.await(
        "SELECT * FROM police_impound WHERE plate = ? AND location = ? AND owner = ? LIMIT 1",
        { plate, data.location, ownerId }
    )
    if not rows or not rows[1] then
        Bridge.Notify.showNotify(playerId, locale("impound_vehicle_not_found"), "error")
        return false
    end
    local record = rows[1]
    if record.duration > os.time() then
        local bankBalance = Bridge.Framework.getMoney(playerId, "bank")
        if bankBalance < record.price then
            Bridge.Notify.showNotify(playerId, locale("impound_not_enough_money"), "error")
            return false
        end
        if record.price > 0 then
            Bridge.Framework.removeMoney(playerId, "bank", record.price)
        end
    end
    local affected = MySQL.update.await("DELETE FROM police_impound WHERE plate = ?", { plate })
    if affected and affected > 0 then
        setVehicleImpoundState(plate, false)
        Bridge.Notify.showNotify(playerId, locale("impound_buyout_vehicle", plate, record.price), "success")
        if Config.Impound.OnVehiclePayedOut then
            Config.Impound.OnVehiclePayedOut(playerId, plate, record.price)
        end
        if Config.Webhooks and Config.Webhooks.impound then
            Bridge.Logs.Send(
                playerId,
                "Impound",
                ("Vehicle %s paid out and retrieved"):format(plate),
                Config.Webhooks.impound
            )
        end
        return true
    end
    Bridge.Notify.showNotify(playerId, locale("impound_payment_failed"), "error")
    return false
end)

lib.addCommand("removeimpound", {
    help = "Remove a vehicle from impound (admin only)",
    params = {
        { name = "plate", help = "Vehicle plate" },
    },
    restricted = "group.admin",
}, function(playerId, args)
    if not args.plate then
        return Bridge.Notify.showNotify(playerId, "Usage: /removeimpound [plate]", "error")
    end
    local plate = normalizePlate(args.plate)
    MySQL.update.await("DELETE FROM police_impound WHERE plate = ?", { plate })
    setVehicleImpoundState(plate, false)
    Bridge.Notify.showNotify(playerId, ("Vehicle %s removed from impound"):format(plate), "success")
end)
