while not Config or not Config.CCTV do
    Citizen.Wait(1)
end

if not Config.CCTV.enabled then
    return
end

CCTV = {
    cameras = {},
    repairTimers = {},
}

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `p_policejob_cctv` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `name` VARCHAR(50) NOT NULL,
            `model` VARCHAR(50) NOT NULL,
            `coords` LONGTEXT NOT NULL,
            `rotation` LONGTEXT NOT NULL,
            `jobs` LONGTEXT NOT NULL,
            `broken` TINYINT(1) DEFAULT 0,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]])

    Citizen.Wait(1000)
    CCTV:LoadCameras()
    local cameraCount = 0
    for _ in pairs(CCTV.cameras) do
        cameraCount = cameraCount + 1
    end
    Bridge.Debug(("[CCTV] Database verified, loaded %d cameras"):format(cameraCount))
end)

function CCTV.LoadCameras(self)
    local rows = MySQL.query.await("SELECT * FROM `p_policejob_cctv`")
    if not rows then
        return
    end

    for _, row in ipairs(rows) do
        local cameraData = {
            id = row.id,
            name = row.name,
            model = row.model,
            coords = json.decode(row.coords),
            rotation = json.decode(row.rotation),
            jobs = json.decode(row.jobs),
            broken = row.broken == 1,
        }
        self.cameras[row.id] = cameraData
        if cameraData.broken then
            self:ScheduleAutoRepair(row.id)
        end
    end
end

function CCTV.GetAllCameras(self)
    return self.cameras
end

function CCTV.CreateCamera(self, cameraData)
    local insertId = MySQL.insert.await(
        "INSERT INTO `p_policejob_cctv` (`name`, `model`, `coords`, `rotation`, `jobs`) VALUES (?, ?, ?, ?, ?)",
        {
            cameraData.name,
            cameraData.model,
            json.encode(cameraData.coords),
            json.encode(cameraData.rotation),
            json.encode(cameraData.jobs),
        }
    )

    if not insertId then
        return nil
    end

    local createdCamera = {
        id = insertId,
        name = cameraData.name,
        model = cameraData.model,
        coords = cameraData.coords,
        rotation = cameraData.rotation,
        jobs = cameraData.jobs,
        broken = false,
    }
    self.cameras[insertId] = createdCamera
    return createdCamera
end

function CCTV.DeleteCamera(self, cameraId)
    MySQL.query.await("DELETE FROM `p_policejob_cctv` WHERE `id` = ?", { cameraId })
    self.cameras[cameraId] = nil
    self.repairTimers[cameraId] = nil
end

function CCTV.SetBroken(self, cameraId, isBroken)
    MySQL.update.await(
        "UPDATE `p_policejob_cctv` SET `broken` = ? WHERE `id` = ?",
        { isBroken and 1 or 0, cameraId }
    )
    local cameraData = self.cameras[cameraId]
    if cameraData then
        cameraData.broken = isBroken
    end
end

function CCTV.Repair(self, cameraId)
    self.repairTimers[cameraId] = nil
    self:SetBroken(cameraId, false)
    TriggerClientEvent("p_policejob/client/cctv/broken", -1, cameraId, false)
end

function CCTV.ScheduleAutoRepair(self, cameraId)
    local autoRepairTime = Config.CCTV.damage and Config.CCTV.damage.autoRepairTime or 0
    if not autoRepairTime or autoRepairTime <= 0 then
        return
    end

    local timerGeneration = (self.repairTimers[cameraId] or 0) + 1
    self.repairTimers[cameraId] = timerGeneration

    SetTimeout(autoRepairTime, function()
        if self.repairTimers[cameraId] ~= timerGeneration then
            return
        end

        local cameraData = self.cameras[cameraId]
        if cameraData and cameraData.broken then
            self:Repair(cameraId)
            Bridge.Debug(("[CCTV] Camera id=%s auto-repaired"):format(cameraId))
        else
            self.repairTimers[cameraId] = nil
        end
    end)
end

function hasCctvCreatorAccess(playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job then
        return false
    end
    for _, allowedJob in ipairs(Config.CCTV.creatorAccess) do
        if job.name == allowedJob then
            return true
        end
    end
    return false
end

RegisterNetEvent("p_policejob/server/cctv/request", function()
    TriggerClientEvent("p_policejob/client/cctv/load", source, CCTV:GetAllCameras())
end)

RegisterNetEvent("p_policejob/server/cctv/create", function(cameraData)
    local playerId = source
    if not hasCctvCreatorAccess(playerId) then
        return
    end

    local createdCamera = CCTV:CreateCamera(cameraData)
    if createdCamera then
        TriggerClientEvent("p_policejob/client/cctv/add", -1, createdCamera)
        lib.notify(playerId, { title = locale("cctv_created"), type = "success" })
        Bridge.Debug(("[CCTV] Player %s created camera id=%s name=%s"):format(
            playerId, createdCamera.id, createdCamera.name
        ))
    else
        Bridge.Debug(("[CCTV] Player %s create failed"):format(playerId))
    end
end)

RegisterNetEvent("p_policejob/server/cctv/delete", function(cameraId)
    local playerId = source
    if not hasCctvCreatorAccess(playerId) then
        return
    end

    local cameraData = CCTV.cameras[cameraId]
    if not cameraData then
        return
    end

    CCTV:DeleteCamera(cameraId)
    TriggerClientEvent("p_policejob/client/cctv/remove", -1, cameraId)
    lib.notify(playerId, { title = locale("camera_removed", cameraData.name), type = "success" })
    Bridge.Debug(("[CCTV] Player %s deleted camera id=%s"):format(playerId, cameraId))
end)

RegisterNetEvent("p_policejob/server/cctv/damage", function(cameraId)
    local playerId = source
    local cameraData = CCTV.cameras[cameraId]
    if not cameraData or cameraData.broken then
        return
    end

    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 or not cameraData.coords then
        return
    end

    local breakDistance = Config.CCTV.damage and Config.CCTV.damage.breakDistance or 10.0
    local playerCoords = GetEntityCoords(ped)
    local cameraCoords = vec3(cameraData.coords.x, cameraData.coords.y, cameraData.coords.z)
    if #(playerCoords - cameraCoords) > breakDistance then
        Bridge.Debug(("[CCTV] Player %s denied breaking camera id=%s (too far)"):format(playerId, cameraId))
        return
    end

    CCTV:SetBroken(cameraId, true)
    TriggerClientEvent("p_policejob/client/cctv/broken", -1, cameraId, true)
    CCTV:ScheduleAutoRepair(cameraId)
    Bridge.Debug(("[CCTV] Camera id=%s damaged by %s"):format(cameraId, playerId))
end)

lib.addCommand("repaircctv", {
    help = "Repair a broken CCTV camera",
    params = {
        { name = "id", type = "number", help = "Camera ID" },
    },
    restricted = "group.admin",
}, function(source, args)
    local cameraId = args.id
    if not CCTV.cameras[cameraId] then
        return lib.notify(source, { title = locale("cctv_not_found"), type = "error" })
    end
    CCTV:Repair(cameraId)
    lib.notify(source, { title = locale("cctv_repaired"), type = "success" })
end)

lib.addCommand("deletecctv", {
    help = "Delete a CCTV camera",
    params = {
        { name = "id", type = "number", help = "Camera ID" },
    },
    restricted = "group.admin",
}, function(source, args)
    local cameraId = args.id
    local cameraData = CCTV.cameras[cameraId]
    if not cameraData then
        return lib.notify(source, { title = locale("cctv_not_found"), type = "error" })
    end

    CCTV:DeleteCamera(cameraId)
    TriggerClientEvent("p_policejob/client/cctv/remove", -1, cameraId)
    lib.notify(source, { title = locale("camera_removed", cameraData.name), type = "success" })
end)

lib.addCommand("createcctv", {
    help = "Open CCTV camera creator",
    params = {},
    restricted = false,
}, function(source)
    if not hasCctvCreatorAccess(source) then
        return lib.notify(source, { title = locale("camera_no_access"), type = "error" })
    end
    TriggerClientEvent("p_policejob/client/cctv/creator", source)
end)

exports("getCCTVCameras", function()
    return CCTV:GetAllCameras()
end)

exports("repairCCTV", function(cameraId)
    CCTV:Repair(cameraId)
end)
