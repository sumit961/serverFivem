Bolo = {
    Data = {},
}

CreateThread(function()
    while not MySQL or not MySQL.ready do
        Wait(100)
    end

    local expiredUpdates = {}
    local rows = MySQL.query.await("SELECT * FROM p_mdt_bolo")

    for _, row in pairs(rows) do
        row.target = json.decode(row.target)
        row.tags = json.decode(row.tags)
        row.creator = json.decode(row.creator)
        row.id = tostring(row.id)

        if row.expire then
            local expireTime = tonumber(row.expire) / 1000
            if expireTime < os.time() and row.status ~= "expired" then
                row.status = "expired"
                expiredUpdates[#expiredUpdates + 1] = { row.status, row.id }
            end
        end

        Bolo.Data[row.id] = row
    end

    if #expiredUpdates > 0 then
        MySQL.prepare("UPDATE p_mdt_bolo SET status = ? WHERE id = ?", expiredUpdates)
    end
end)

function Bolo.new(self, playerSource, data)
    local targetType = "citizen"
    local targetObject = Bridge.Framework.getOfflinePlayerByCitizenId(data.target)

    if not targetObject then
        targetType = "vehicle"
        targetObject = Bridge.Framework.getVehicleByPlate(data.target)
    end

    Bridge.Debug(("[BOLO] Target Object: %s"):format(json.encode(targetObject)))

    if not targetObject then
        Bridge.Notify.showNotify(playerSource, locale("bolo_target_not_found"), "error")
        return
    end

    local targetLabel
    if targetType == "vehicle" and targetObject.plate then
        targetLabel = targetObject.plate
    else
        targetLabel = ("%s %s"):format(targetObject.firstname, targetObject.lastname)
    end

    local insertValues = {
        data.title,
        data.description,
        json.encode({
            type = targetType,
            value = data.target,
            label = targetLabel,
        }),
        json.encode(data.tags),
        "active",
        json.encode({
            name = Bridge.Framework.getPlayerName(playerSource),
            id = Bridge.Framework.getUniqueId(playerSource),
        }),
        os.time(),
        data.expire or nil,
    }

    local insertId = MySQL.insert.await(
        "INSERT INTO p_mdt_bolo (title, description, target, tags, status, creator, timestamp, expire) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        insertValues
    )

    if not insertId then
        return nil
    end

    local boloId = tostring(insertId)
    local bolo = {
        id = boloId,
        title = insertValues[1],
        description = insertValues[2],
        target = json.decode(insertValues[3]),
        tags = json.decode(insertValues[4]),
        status = insertValues[5],
        creator = json.decode(insertValues[6]),
        timestamp = insertValues[7],
        expire = insertValues[8] or nil,
    }

    self.Data[boloId] = bolo
    return bolo
end

function Bolo.changeStatus(self, boloId, status)
    boloId = tostring(boloId)
    local bolo = self.Data[boloId]
    if not bolo then
        return false
    end

    bolo.status = status
    MySQL.update("UPDATE p_mdt_bolo SET status = ? WHERE id = ?", { status, boloId })
    return true
end

function Bolo.delete(self, boloId)
    boloId = tostring(boloId)
    if not self.Data[boloId] then
        return false
    end

    self.Data[boloId] = nil
    MySQL.update("DELETE FROM p_mdt_bolo WHERE id = ?", { boloId })
    return true
end

function Bolo.edit(self, boloId, data)
    boloId = tostring(boloId)
    local bolo = self.Data[boloId]
    if not bolo then
        return false
    end

    bolo.title = data.title
    bolo.description = data.description
    bolo.tags = data.tags
    bolo.expire = data.expire or nil

    MySQL.update(
        "UPDATE p_mdt_bolo SET title = ?, description = ?, tags = ?, expire = ? WHERE id = ?",
        {
            data.title,
            data.description,
            json.encode(data.tags),
            data.expire or nil,
            boloId,
        }
    )
    return true
end

RegisterNetEvent("p_mdt/server/bolo/edit", function(data)
    local playerSource = source
    if not Permissions.hasPerm(playerSource, "bolo.edit") then
        Bridge.Notify.showNotify(playerSource, locale("no_permission"), "error")
        return
    end
    Bolo:edit(data.id, data)
end)

function Bolo.getRecents(self)
    local recents = {}
    local activeBolos = {}

    for _, bolo in pairs(self.Data) do
        if bolo.status == "active" then
            activeBolos[#activeBolos + 1] = bolo
        end
    end

    table.sort(activeBolos, function(a, b)
        return a.timestamp > b.timestamp
    end)

    for i = 1, math.min(5, #activeBolos) do
        recents[activeBolos[i].id] = activeBolos[i]
    end

    return recents
end

lib.callback.register("p_mdt/server/bolo/fetch", function()
    return Bolo.Data
end)

lib.callback.register("p_mdt/server/bolo/create", function(playerSource, data)
    if not Permissions.hasPerm(playerSource, "bolo.create") then
        Bridge.Notify.showNotify(playerSource, locale("no_permission"), "error")
        return
    end
    return Bolo:new(playerSource, data)
end)

RegisterNetEvent("p_mdt/server/bolo/changeStatus", function(data)
    local playerSource = source
    if not Permissions.hasPerm(playerSource, "bolo.change_status") then
        Bridge.Notify.showNotify(playerSource, locale("no_permission"), "error")
        return
    end
    Bolo:changeStatus(data.id, data.status)
end)

RegisterNetEvent("p_mdt/server/bolo/delete", function(data)
    local playerSource = source
    if not Permissions.hasPerm(playerSource, "bolo.delete") then
        Bridge.Notify.showNotify(playerSource, locale("no_permission"), "error")
        return
    end
    Bolo:delete(data.id)
end)

function Bolo.getTargetBolo(self, targetValue)
    for _, bolo in pairs(self.Data) do
        if bolo.target.value == targetValue and bolo.status == "active" then
            return bolo
        end
    end
    return nil
end

function Bolo.getTargetBolos(self, targetValue)
    local bolos = {}
    for _, bolo in pairs(self.Data) do
        if bolo.target.value == targetValue then
            bolos[#bolos + 1] = bolo
        end
    end
    return bolos
end
