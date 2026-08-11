Incidents = {
    data = {},
}

CreateThread(function()
    while not MySQL or not MySQL.ready do
        Wait(100)
    end

    if Bridge and Bridge.Config and Bridge.Config.Debug then
        lib.print.info("Initialized Incidents Module")
        lib.print.info("Loading incidents from database...")
    end

    local rows = MySQL.query.await("SELECT * FROM p_mdt_incidents")
    local expiredIds = {}

    for _, row in ipairs(rows) do
        if row.expire and row.expire < os.time() then
            expiredIds[#expiredIds + 1] = row.id
        else
            Incidents.data[tostring(row.id)] = {
                id = row.id,
                title = row.title,
                description = row.description,
                tags = json.decode(row.tags),
                status = row.status,
                creator = json.decode(row.creator),
                timestamp = row.timestamp,
                expire = row.expire,
                citizens = json.decode(row.citizens),
                vehicles = json.decode(row.vehicles),
            }
        end
    end

    if Bridge and Bridge.Config and Bridge.Config.Debug then
        lib.print.info(("Loaded %s incidents from database."):format(tostring(#Incidents.data)))
    end

    if #expiredIds > 0 then
        MySQL.prepare("DELETE FROM p_mdt_incidents WHERE id = ?", expiredIds)

        if Bridge and Bridge.Config and Bridge.Config.Debug then
            lib.print.info(("Removed %s expired incidents from database."):format(tostring(#expiredIds)))
        end
    end
end)

lib.callback.register("p_mdt/server/incidents/fetch", function(source)
    return Incidents.data
end)

lib.callback.register("p_mdt/server/incidents/search", function(source, data)
    local results = {}
    local query = data.query:lower()

    for _, incident in pairs(Incidents.data) do
        local titleMatch = incident.title:lower():find(query)
        local descriptionMatch = incident.description:lower():find(query)
        local tagsMatch = table.concat(incident.tags, " "):lower():find(query)

        if titleMatch or descriptionMatch or tagsMatch then
            results[#results + 1] = incident
        end
    end

    return results
end)

function Incidents.new(self, source, data)
    local incident = {
        title = data.title,
        description = data.description,
        tags = data.tags,
        status = "open",
        creator = {
            id = Bridge.Framework.getUniqueId(source),
            name = Bridge.Framework.getPlayerName(source),
        },
        timestamp = os.time(),
        expire = data.expire and (data.expire / 1000) or nil,
        citizens = data.citizens,
        vehicles = data.vehicles or {},
    }

    local insertId = MySQL.insert.await(
        "INSERT INTO p_mdt_incidents (title, description, tags, creator, timestamp, expire, citizens, vehicles) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        {
            incident.title,
            incident.description,
            json.encode(incident.tags),
            json.encode(incident.creator),
            incident.timestamp,
            incident.expire,
            json.encode(incident.citizens),
            json.encode(incident.vehicles),
        }
    )

    if not insertId then
        return false
    end

    incident.id = tostring(insertId)
    Incidents.data[incident.id] = incident

    Logs:new(source, {
        category = "incidents",
        action = "create",
        message = ("Created incident %s with id %s"):format(incident.title, incident.id),
    })

    return incident
end

lib.callback.register("p_mdt/server/incidents/create", function(source, data)
    return Incidents:new(source, data)
end)

function Incidents.edit(self, source, data)
    local incident = Incidents.data[tostring(data.id)]
    if not incident then
        return false
    end

    incident.title = data.title
    incident.description = data.description
    incident.tags = data.tags
    incident.expire = data.expire or nil

    if data.citizens then
        incident.citizens = data.citizens
    end

    if data.vehicles then
        incident.vehicles = data.vehicles
    end

    MySQL.update(
        "UPDATE p_mdt_incidents SET title = ?, description = ?, tags = ?, expire = ?, citizens = ?, vehicles = ? WHERE id = ?",
        {
            data.title,
            data.description,
            json.encode(data.tags),
            data.expire,
            json.encode(incident.citizens),
            json.encode(incident.vehicles),
            data.id,
        }
    )

    Logs:new(source, {
        category = "incidents",
        action = "edit",
        message = ("Edited incident %s with id %s"):format(incident.title, incident.id),
    })

    return true
end

lib.callback.register("p_mdt/server/incidents/edit", function(source, data)
    return Incidents:edit(source, data)
end)

function Incidents.delete(self, source, incidentId)
    local incident = Incidents.data[tostring(incidentId)]
    if not incident then
        return false
    end

    Incidents.data[tostring(incidentId)] = nil
    MySQL.prepare("DELETE FROM p_mdt_incidents WHERE id = ?", { incidentId })
    return true
end

RegisterNetEvent("p_mdt/server/incidents/delete", function(incidentId)
    Incidents:delete(source, incidentId)
end)

function Incidents.getRecents(self)
    local openIncidents = {}

    for _, incident in pairs(Incidents.data) do
        if incident.status == "open" then
            table.insert(openIncidents, incident)
        end
    end

    table.sort(openIncidents, function(left, right)
        return left.timestamp < right.timestamp
    end)

    local recents = {}
    for index = 1, math.min(5, #openIncidents) do
        recents[index] = openIncidents[index]
    end

    return recents
end

function Incidents.close(self, source, incidentId)
    local incident = Incidents.data[tostring(incidentId)]
    if not incident then
        return false
    end

    incident.status = "closed"
    MySQL.update("UPDATE p_mdt_incidents SET status = ? WHERE id = ?", { "closed", incidentId })
    return true
end

RegisterNetEvent("p_mdt/server/incidents/close", function(incidentId)
    Incidents:close(source, incidentId)
end)

function Incidents.getVehicleIncidents(self, plate)
    local matchingIncidents = {}
    local loweredPlate = plate:lower()

    for _, incident in pairs(Incidents.data) do
        for _, vehicle in ipairs(incident.vehicles or {}) do
            if vehicle.plate:lower() == loweredPlate then
                matchingIncidents[#matchingIncidents + 1] = incident
                break
            end
        end
    end

    return matchingIncidents
end
