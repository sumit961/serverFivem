Employees = {}

function Employees.getNearbyPlayers(self, playerId)
    local playerPed = GetPlayerPed(playerId)
    local playerCoords = GetEntityCoords(playerPed)
    local nearbyPlayers = lib.getNearbyPlayers(playerCoords, 10.0, false)
    local options = {}

    for _, player in ipairs(nearbyPlayers) do
        if player.id ~= playerId then
            options[#options + 1] = {
                value = tostring(player.id),
                label = Bridge.Framework.getPlayerName(player.id),
            }
        end
    end

    return options
end

function Employees.updateLicences(self, identifier, licences)
    Base.playersLicences[identifier] = licences

    if Base.playersData[identifier] then
        MySQL.update("UPDATE p_mdt_officers SET licences = ? WHERE identifier = ?", {
            json.encode(licences),
            identifier,
        })
    else
        Base.playersData[identifier] = {}
        MySQL.insert("INSERT INTO p_mdt_officers (identifier, licences) VALUES (?, ?)", {
            identifier,
            json.encode(licences),
        })
    end
end

function Employees.hasLicense(self, identifier, license)
    if not identifier or not license then
        return false
    end

    local row = MySQL.single.await("SELECT licences FROM p_mdt_officers WHERE identifier = ?", { identifier })
    if not row then
        return false
    end

    local licences = {}
    if row.licences then
        licences = json.decode(row.licences) or {}
    end

    for _, value in pairs(licences) do
        if value == license then
            return true
        end
    end

    return false
end

function Employees.getLicences(self, identifier)
    if not identifier then
        return {}
    end

    local row = MySQL.single.await("SELECT licences FROM p_mdt_officers WHERE identifier = ?", { identifier })
    if not row then
        return {}
    end

    local licences = {}
    if row.licences then
        licences = json.decode(row.licences) or {}
    end

    local result = {}
    for _, value in pairs(licences) do
        result[value] = true
    end

    return result
end

exports("hasLicense", function(identifier, license)
    return Employees:hasLicense(identifier, license)
end)

exports("getLicences", function(identifier)
    return Employees:getLicences(identifier)
end)

lib.callback.register("p_mdt/server/employees/fetch", function(source)
    return Editable:fetchEmployees(source)
end)

lib.callback.register("p_mdt/server/employees/getNearbyPlayers", function(source)
    return Employees:getNearbyPlayers(source)
end)

lib.callback.register("p_mdt/server/employees/hire", function(source, data)
    return Editable:hireEmployee(source, data)
end)

lib.callback.register("p_mdt/server/employees/fire", function(source, data)
    return Editable:fireEmployee(source, data)
end)

lib.callback.register("p_mdt/server/employees/update", function(source, data)
    return Editable:updateEmployee(source, data)
end)
