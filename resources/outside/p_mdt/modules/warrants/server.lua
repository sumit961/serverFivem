Warrants = {
    data = {},
}

CreateThread(function()
    while not MySQL or not MySQL.ready do
        Wait(100)
    end

    local expiredIds = {}
    local rows = MySQL.query.await("SELECT * FROM p_mdt_warrants")

    for _, row in ipairs(rows) do
        if row.expire and row.expire < os.time() then
            expiredIds[#expiredIds + 1] = row.id
        else
            local warrantId = tostring(row.id)
            Warrants.data[warrantId] = {
                id = warrantId,
                type = row.type,
                title = row.title,
                content = row.content,
                status = row.status,
                target = json.decode(row.target),
                location = row.location,
                expire = row.expire,
                timestamp = row.timestamp,
                creator = json.decode(row.creator),
            }
        end
    end

    if Bridge and Bridge.Config and Bridge.Config.Debug then
        lib.print.info("Loaded " .. tostring(#Warrants.data) .. " warrants from database.")
    end

    if #expiredIds > 0 then
        MySQL.prepare("DELETE FROM p_mdt_warrants WHERE id = ?", expiredIds)

        if Bridge and Bridge.Config and Bridge.Config.Debug then
            lib.print.info("Registered " .. tostring(#expiredIds) .. " expired warrants.")
        end
    end
end)

lib.callback.register("p_mdt/server/warrants/fetch", function()
    return Warrants.data
end)

lib.callback.register("p_mdt/server/warrants/search", function(_, data)
    local results = {}
    local count = 0
    local query = data.query:lower()

    for _, warrant in pairs(Warrants.data) do
        if warrant.title:lower():find(query)
            or warrant.content:lower():find(query)
            or warrant.target.name:lower():find(query)
        then
            count = count + 1
            results[count] = warrant
        end
    end

    return results
end)

function Warrants.create(self, playerSource, data)
    local target = Bridge.Framework.getOfflinePlayerByCitizenId(data.target)
    if not target then
        Bridge.Notify.showNotify(playerSource, locale("target_not_found"), "error")
        return false
    end

    local warrant = {
        type = data.type,
        title = data.title,
        content = data.description,
        target = {
            id = data.target,
            name = ("%s %s"):format(target.firstname, target.lastname),
        },
        location = data.location or nil,
        expire = data.expirationDate and data.expirationDate / 1000 or nil,
        timestamp = os.time(),
        creator = {
            name = Bridge.Framework.getPlayerName(playerSource),
            id = Bridge.Framework.getUniqueId(playerSource),
        },
    }

    local insertId = MySQL.insert.await(
        "INSERT INTO p_mdt_warrants (type, title, content, target, location, expire, timestamp, creator) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        {
            warrant.type,
            warrant.title,
            warrant.content,
            json.encode(warrant.target),
            warrant.location,
            warrant.expire,
            warrant.timestamp,
            json.encode(warrant.creator),
        }
    )

    if not insertId then
        return
    end

    local warrantId = tostring(insertId)
    local created = {
        id = warrantId,
        type = warrant.type,
        title = warrant.title,
        content = warrant.content,
        status = "active",
        target = warrant.target,
        location = warrant.location,
        expire = warrant.expire,
        timestamp = warrant.timestamp,
        creator = warrant.creator,
    }

    self.data[warrantId] = created

    Bridge.Notify.showNotify(playerSource, locale("warrant_created"), "success")

    Logs:new(playerSource, {
        category = "warrants",
        action = "create",
        message = ("Created warrant %s for target %s"):format(warrant.title, warrant.target.name),
    })

    return created
end

function Warrants.delete(self, playerSource, data)
    local warrant = self.data[tostring(data.id)]
    if not warrant then
        Bridge.Notify.showNotify(playerSource, locale("warrant_not_found"), "error")
        return
    end

    MySQL.update("DELETE FROM p_mdt_warrants WHERE id = ?", { data.id })
    self.data[data.id] = nil

    Bridge.Notify.showNotify(playerSource, locale("warrant_deleted"), "success")

    Logs:new(playerSource, {
        category = "warrants",
        action = "delete",
        message = ("Deleted warrant %s for target %s"):format(warrant.title, warrant.target.name),
    })
end

lib.callback.register("p_mdt/server/warrants/create", function(playerSource, data)
    return Warrants:create(playerSource, data)
end)

RegisterNetEvent("p_mdt/server/warrants/delete", function(data)
    Warrants:delete(source, data)
end)

function Warrants.getCitizenWarrants(self, citizenId)
    local warrants = {}
    local index = 1
    local citizenIdStr = tostring(citizenId)

    for _, warrant in pairs(Warrants.data) do
        if tostring(warrant.target.id) == citizenIdStr then
            warrants[index] = warrant
            index = index + 1
        end
    end

    return warrants
end

function Warrants.getVehicleWarrants(self, plate)
    local warrants = {}
    local index = 1

    for _, warrant in pairs(Warrants.data) do
        if warrant.content:find(plate) then
            warrants[index] = warrant
            index = index + 1
        end
    end

    return warrants
end
