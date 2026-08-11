Vehicles = {
    profiles = {},
}

CreateThread(function()
    while not MySQL or not MySQL.ready do
        Wait(100)
    end

    local expiredUpdates = {}
    local rows = MySQL.query.await("SELECT * FROM p_mdt_vehicles")

    for _, row in ipairs(rows) do
        row.photos = json.decode(row.photos or "[]") or {}
        row.notes = json.decode(row.notes or "[]") or {}
        local notesChanged = false

        for noteIndex, note in ipairs(row.notes) do
            if note.expire and note.expire < os.time() then
                table.remove(row.notes, noteIndex)
                notesChanged = true
            end
        end

        if notesChanged then
            expiredUpdates[#expiredUpdates + 1] = { row.notes, row.plate }
        end

        Vehicles.profiles[row.plate] = {
            plate = row.plate,
            avatar = row.avatar or nil,
            notes = row.notes,
            photos = row.photos,
        }
    end

    if #expiredUpdates > 0 then
        MySQL.prepare("UPDATE p_mdt_vehicles SET notes = ? WHERE plate = ?", expiredUpdates)
    end
end)

function Vehicles.getVehicleProfile(self, plate)
    local profile = self.profiles[plate]

    if not profile then
        profile = MySQL.single.await("SELECT * FROM p_mdt_vehicles WHERE plate = ?", { plate })
        if profile then
            profile.photos = json.decode(profile.photos or "[]") or {}
            profile.notes = json.decode(profile.notes or "[]") or {}
            self.profiles[plate] = profile
        end
    end

    return profile
end

lib.callback.register("p_mdt/server/vehicles/search", function(source, data)
    return Editable:getVehiclesByQuery(source, data.query, data.type)
end)

lib.callback.register("p_mdt/server/vehicles/getProfile", function(source, data)
    return Editable:getVehicleProfile(source, data.plate)
end)

function Vehicles.saveProfile(self, profile)
    MySQL.update("REPLACE INTO p_mdt_vehicles (plate, notes, photos, avatar) VALUES (?, ?, ?, ?)", {
        profile.plate,
        json.encode(profile.notes),
        json.encode(profile.photos),
        profile.avatar,
    })
end

function Vehicles.ensureProfile(self, plate)
    local profile = self:getVehicleProfile(plate)

    if not profile then
        profile = {
            plate = plate,
            avatar = nil,
            notes = {},
            photos = {},
            tags = {},
        }
    end

    return profile
end

function Vehicles.createNote(self, source, data)
    if not Permissions.hasPerm(source, "vehicles.add_note") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return
    end

    local profile = self:ensureProfile(data.plate)
    local note = {
        id = #profile.notes + 1,
        title = data.title,
        content = data.content,
        timestamp = os.time(),
        isImportant = data.isImportant or false,
        expire = data.expire or nil,
        creator = {
            name = Bridge.Framework.getPlayerName(source),
            id = Bridge.Framework.getUniqueId(source),
        },
    }

    table.insert(profile.notes, 1, note)
    self.profiles[data.plate] = profile
    self:saveProfile(profile)

    Logs:new(source, {
        category = "vehicles",
        action = "created_note",
        message = ("Created note %s for vehicle %s"):format(note.title, data.plate),
    })
end

RegisterNetEvent("p_mdt/server/vehicle/createNote", function(data)
    Vehicles:createNote(source, data)
end)

function Vehicles.changeAvatar(self, source, data)
    if not Permissions.hasPerm(source, "vehicles.change_avatar") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return
    end

    local profile = self:ensureProfile(data.plate)
    profile.avatar = data.avatar
    self.profiles[data.plate] = profile
    self:saveProfile(profile)

    Logs:new(source, {
        category = "vehicles",
        action = "changed_avatar",
        message = ("Changed avatar for vehicle %s"):format(data.plate),
    })
end

RegisterNetEvent("p_mdt/server/vehicle/changeAvatar", function(data)
    Vehicles:changeAvatar(source, data)
end)

function Vehicles.addPhoto(self, source, data)
    if not Permissions.hasPerm(source, "vehicles.add_photo") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return
    end

    local profile = self:ensureProfile(data.plate)
    table.insert(profile.photos, 1, data.url)
    self.profiles[data.plate] = profile
    self:saveProfile(profile)

    Logs:new(source, {
        category = "vehicles",
        action = "added_photo",
        message = ("Added photo for vehicle %s"):format(data.plate),
    })
end

RegisterNetEvent("p_mdt/server/vehicle/addPhoto", function(data)
    Vehicles:addPhoto(source, data)
end)

function Vehicles.deletePhoto(self, source, data)
    if not Permissions.hasPerm(source, "vehicles.delete_photo") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return
    end

    local profile = self:getVehicleProfile(data.plate)
    if not profile then
        Bridge.Notify.showNotify(source, locale("no_data"), "error")
        return
    end

    for photoIndex, photoUrl in pairs(profile.photos) do
        if photoUrl == data.url then
            table.remove(profile.photos, photoIndex)
            break
        end
    end

    self.profiles[data.plate] = profile
    self:saveProfile(profile)

    Logs:new(source, {
        category = "vehicles",
        action = "deleted_photo",
        message = ("Deleted photo for vehicle %s"):format(data.plate),
    })
end

RegisterNetEvent("p_mdt/server/vehicle/deletePhoto", function(data)
    Vehicles:deletePhoto(source, data)
end)

function Vehicles.deleteNote(self, source, data)
    if not Permissions.hasPerm(source, "vehicles.delete_note") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return
    end

    local profile = self:getVehicleProfile(data.plate)
    if not profile then
        Bridge.Notify.showNotify(source, locale("no_data"), "error")
        return
    end

    for noteIndex, note in pairs(profile.notes) do
        if note.id == data.id then
            table.remove(profile.notes, noteIndex)
            break
        end
    end

    self.profiles[data.plate] = profile
    self:saveProfile(profile)

    Logs:new(source, {
        category = "vehicles",
        action = "deleted_note",
        message = ("Deleted note for vehicle %s"):format(data.plate),
    })
end

RegisterNetEvent("p_mdt/server/vehicle/deleteNote", function(data)
    Vehicles:deleteNote(source, data)
end)
