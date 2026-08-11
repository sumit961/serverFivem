while not Config or not Config.Speedcam do
    Citizen.Wait(500)
end

if not Config.Speedcam.enabled then
    return
end

Speedcam = {
    cameras = {},
    dbReady = false,
}

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `p_policejob_speedcams` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `cam_name` VARCHAR(100) NOT NULL UNIQUE,
            `model_name` VARCHAR(100) NOT NULL,
            `coords_x` FLOAT NOT NULL,
            `coords_y` FLOAT NOT NULL,
            `coords_z` FLOAT NOT NULL,
            `heading` FLOAT NOT NULL,
            `speed_limit` INT NOT NULL,
            `cam_distance` INT NOT NULL,
            `fine` INT NOT NULL,
            `fine_multiplier` TINYINT(1) NOT NULL DEFAULT 0,
            `blip_enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `screen_effect` TINYINT(1) NOT NULL DEFAULT 1,
            `light_effect` TINYINT(1) NOT NULL DEFAULT 1,
            `sensors` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    Speedcam.dbReady = true
    Bridge.Debug("[Speedcam] Database table verified")
end)

function Speedcam.loadFromDatabase()
    local rows = MySQL.query.await("SELECT * FROM p_policejob_speedcams")
    if not rows or #rows == 0 then
        return
    end
    for _, row in ipairs(rows) do
        local sensors = json.decode(row.sensors) or {}
        Speedcam.cameras[row.cam_name] = {
            id = row.id,
            camName = row.cam_name,
            modelName = row.model_name,
            coords = {
                x = row.coords_x,
                y = row.coords_y,
                z = row.coords_z,
            },
            heading = row.heading,
            speedLimit = row.speed_limit,
            camDistance = row.cam_distance,
            fine = row.fine,
            fineMultiplier = row.fine_multiplier == 1,
            blipEnabled = row.blip_enabled == 1,
            screenEffect = row.screen_effect == 1,
            lightEffect = row.light_effect == 1,
            sensors = sensors,
        }
    end
end

function Speedcam.syncAllClients()
    local cameraList = {}
    for _, cameraData in pairs(Speedcam.cameras) do
        cameraList[#cameraList + 1] = cameraData
    end
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent("p_policejob/client/speedcam/loadCameras", tonumber(playerId), cameraList)
    end
end

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    while not Speedcam.dbReady do
        Citizen.Wait(50)
    end
    Speedcam:loadFromDatabase()
    Speedcam:syncAllClients()
end)

RegisterNetEvent("p_policejob/server/speedcam/loadCameras", function()
    local playerId = source
    local cameraList = {}
    for _, cameraData in pairs(Speedcam.cameras) do
        cameraList[#cameraList + 1] = cameraData
    end
    TriggerClientEvent("p_policejob/client/speedcam/loadCameras", playerId, cameraList)
end)

RegisterNetEvent("p_policejob/server/speedcam/createSpeedcam", function(data)
    local playerId = source
    local job = Bridge.Framework.getPlayerJob(playerId)
    local minGrade = Config.Jobs[job.name]
    if not minGrade or job.grade < minGrade then
        Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
        return
    end
    if Speedcam.cameras[data.camName] then
        Bridge.Notify.showNotify(playerId, "Camera name already exists", "error")
        return
    end
    local sensorsJson = json.encode(data.sensors)
    MySQL.insert.await(
        "INSERT INTO p_policejob_speedcams (cam_name, model_name, coords_x, coords_y, coords_z, heading, speed_limit, cam_distance, fine, fine_multiplier, blip_enabled, screen_effect, light_effect, sensors) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        {
            data.camName,
            data.modelName,
            data.coords.x,
            data.coords.y,
            data.coords.z,
            data.heading,
            data.speedLimit,
            data.camDistance,
            data.fine,
            data.fineMultiplier and 1 or 0,
            data.blipEnabled and 1 or 0,
            data.screenEffect and 1 or 0,
            data.lightEffect and 1 or 0,
            sensorsJson,
        }
    )
    local cameraData = {
        camName = data.camName,
        modelName = data.modelName,
        coords = data.coords,
        heading = data.heading,
        speedLimit = data.speedLimit,
        camDistance = data.camDistance,
        fine = data.fine,
        fineMultiplier = data.fineMultiplier,
        blipEnabled = data.blipEnabled,
        screenEffect = data.screenEffect,
        lightEffect = data.lightEffect,
        sensors = data.sensors,
    }
    Speedcam.cameras[data.camName] = cameraData
    TriggerClientEvent("p_policejob/client/speedcam/newCamera", -1, cameraData)
    Bridge.Notify.showNotify(playerId, "Speed camera created", "success")
end)

RegisterNetEvent("p_policejob/server/speedcam/playerCaught", function(payload)
    local playerId = source
    local ped = GetPlayerPed(playerId)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then
        return
    end
    local fineAmount = payload.cameraData.fine
    if payload.cameraData.fineMultiplier then
        fineAmount = math.floor((payload.speed / payload.cameraData.speedLimit) * fineAmount)
    end
    if Config.Speedcam.OnSpeedingDetected then
        Config.Speedcam.OnSpeedingDetected(
            playerId,
            fineAmount,
            payload.speed,
            payload.cameraData.speedLimit
        )
    end
    Bridge.Notify.showNotify(
        playerId,
        ("You were speeding! Fine: $%d (%d km/h over limit)"):format(
            fineAmount,
            payload.speed - payload.cameraData.speedLimit
        ),
        "error"
    )
    if payload.cameraData.lightEffect then
        local playerCoords = GetEntityCoords(ped)
        local nearbyPlayers = lib.getNearbyPlayers(playerCoords, 50.0, true)
        for _, nearbyPlayer in ipairs(nearbyPlayers) do
            TriggerClientEvent("p_policejob/client/speedcam/syncLight", nearbyPlayer.id, payload)
        end
    end
    if Config.Webhooks and Config.Webhooks.speedcam then
        Bridge.Logs.Send(
            playerId,
            "Speedcam",
            ("Player caught speeding: $%d fine (%d km/h over)"):format(
                fineAmount,
                payload.speed - payload.cameraData.speedLimit
            ),
            Config.Webhooks.speedcam
        )
    end
end)

RegisterNetEvent("p_policejob/server/speedcam/removeSpeedcam", function(camName)
    local playerId = source
    local job = Bridge.Framework.getPlayerJob(playerId)
    local minGrade = Config.Jobs[job.name]
    if not minGrade or job.grade < minGrade then
        Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
        return
    end
    MySQL.update.await("DELETE FROM p_policejob_speedcams WHERE cam_name = ?", { camName })
    Speedcam.cameras[camName] = nil
    TriggerClientEvent("p_policejob/client/speedcam/removeCamera", -1, camName)
    Bridge.Notify.showNotify(playerId, ('Speed camera "%s" removed'):format(camName), "success")
    if Config.Webhooks and Config.Webhooks.speedcam then
        Bridge.Logs.Send(
            playerId,
            "Speedcam",
            ("Removed speedcam: %s"):format(camName),
            Config.Webhooks.speedcam
        )
    end
end)

RegisterNetEvent("p_policejob/server/speedcam/updateSpeedcam", function(data)
    local playerId = source
    local job = Bridge.Framework.getPlayerJob(playerId)
    local minGrade = Config.Jobs[job.name]
    if not minGrade or job.grade < minGrade then
        Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
        return
    end
    local sensorsJson = json.encode(data.sensors)
    MySQL.update.await(
        "UPDATE p_policejob_speedcams SET model_name = ?, speed_limit = ?, cam_distance = ?, fine = ?, fine_multiplier = ?, blip_enabled = ?, screen_effect = ?, light_effect = ?, sensors = ? WHERE cam_name = ?",
        {
            data.modelName,
            data.speedLimit,
            data.camDistance,
            data.fine,
            data.fineMultiplier and 1 or 0,
            data.blipEnabled and 1 or 0,
            data.screenEffect and 1 or 0,
            data.lightEffect and 1 or 0,
            sensorsJson,
            data.camName,
        }
    )
    Speedcam.cameras[data.camName] = data
    TriggerClientEvent("p_policejob/client/speedcam/removeCamera", -1, data.camName)
    TriggerClientEvent("p_policejob/client/speedcam/newCamera", -1, data)
    Bridge.Notify.showNotify(playerId, "Speed camera updated", "success")
end)

lib.callback.register("p_policejob/server/speedcam/getSpeedcams", function(playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    local minGrade = Config.Jobs[job.name]
    if not minGrade or job.grade < minGrade then
        return {}
    end
    local cameraList = {}
    for _, cameraData in pairs(Speedcam.cameras) do
        cameraList[#cameraList + 1] = cameraData
    end
    return cameraList
end)

AddEventHandler("playerJoining", function()
    local playerId = source
    Citizen.SetTimeout(500, function()
        local cameraList = {}
        for _, cameraData in pairs(Speedcam.cameras) do
            cameraList[#cameraList + 1] = cameraData
        end
        TriggerClientEvent("p_policejob/client/speedcam/loadCameras", playerId, cameraList)
    end)
end)
