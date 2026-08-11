Citizens = {
    profiles = {},
}

function Citizens.getCitizenProfile(self, identifier)
    local profile = self.profiles[identifier]

    if not profile then
        profile = MySQL.single.await("SELECT * FROM p_mdt_citizens WHERE identifier = ?", { identifier })
        if profile then
            profile.notes = json.decode(profile.notes or "[]") or {}
            self.profiles[identifier] = profile
        end
    end

    return profile
end

CreateThread(function()
    while not Bridge or not Config do
        Wait(100)
    end

    local expiredUpdates = {}
    local rows = MySQL.query.await("SELECT * FROM p_mdt_citizens")

    for _, row in pairs(rows) do
        row.notes = json.decode(row.notes or "[]") or {}
        local notesChanged = false

        for noteIndex, note in ipairs(row.notes) do
            if note.expire and note.expire < os.time() then
                table.remove(row.notes, noteIndex)
                notesChanged = true
            end
        end

        if notesChanged then
            expiredUpdates[#expiredUpdates + 1] = { row.notes, row.identifier }
        end

        Citizens.profiles[row.identifier] = row
    end

    if #expiredUpdates > 0 then
        MySQL.prepare("UPDATE p_mdt_citizens SET notes = ? WHERE identifier = ?", expiredUpdates)
    end
end)

lib.callback.register("p_mdt/server/citizens/search", function(source, data)
    local query = data.query
    if not query or query == "" or query:len() < 1 then
        return {}
    end

    return Editable:getCitizensByQuery(source, query, data.type)
end)

lib.callback.register("p_mdt/server/citizens/getProfile", function(source, data)
    if not data.citizenId then
        return nil
    end

    return Editable:getCitizenProfile(data.citizenId)
end)

function Citizens.createNote(self, source, data)
    local profile = self.profiles[data.identifier]
    local isNewProfile = false

    if not profile then
        profile = {
            identifier = data.identifier,
            avatar = nil,
            notes = {},
        }
        isNewProfile = true
    end

    local note = {
        id = #profile.notes + 1,
        title = data.title,
        content = data.content,
        isImportant = data.isImportant or false,
        creator = {
            name = Bridge.Framework.getPlayerName(source),
            id = Bridge.Framework.getUniqueId(source),
        },
        timestamp = os.time(),
        expire = data.expire or nil,
    }

    table.insert(profile.notes, 1, note)
    self.profiles[data.identifier] = profile

    if isNewProfile then
        MySQL.insert("INSERT INTO p_mdt_citizens (identifier, notes) VALUES (?, ?)", {
            data.identifier,
            json.encode(profile.notes),
        })
    else
        MySQL.update("UPDATE p_mdt_citizens SET notes = ? WHERE identifier = ?", {
            json.encode(profile.notes),
            data.identifier,
        })
    end

    Logs:new(source, {
        category = "citizens",
        action = "created_note",
        message = ("Created note %s for citizen %s"):format(note.title, data.identifier),
    })
end

function Citizens.setCitizenAvatar(self, source, data)
    local profile = self.profiles[data.identifier]
    local isNewProfile = false

    if not profile then
        profile = {
            identifier = data.identifier,
            avatar = data.avatar,
            notes = {},
        }
        isNewProfile = true
    else
        profile.avatar = data.avatar
    end

    self.profiles[data.identifier] = profile

    if isNewProfile then
        MySQL.insert("INSERT INTO p_mdt_citizens (identifier, avatar) VALUES (?, ?)", {
            data.identifier,
            data.avatar,
        })
    else
        MySQL.update("UPDATE p_mdt_citizens SET avatar = ? WHERE identifier = ?", {
            data.avatar,
            data.identifier,
        })
    end

    Logs:new(_source, {
        category = "citizens",
        action = "changed_avatar",
        message = ("Changed avatar for citizen %s"):format(data.identifier),
    })
end

function Citizens.removeJudgment(self, source, data)
    local judgment = MySQL.single.await("SELECT * FROM p_mdt_judgments WHERE id = ?", { data.id })
    if not judgment then
        return
    end

    local targets = json.decode(judgment.targets)

    for targetIndex, targetId in pairs(targets) do
        if targetId == data.identifier then
            table.remove(targets, targetIndex)
            break
        end
    end

    if #targets < 1 then
        MySQL.update("DELETE FROM p_mdt_judgments WHERE id = ?", { data.id })
    else
        MySQL.update("UPDATE p_mdt_judgments SET targets = ? WHERE id = ?", {
            json.encode(targets),
            data.id,
        })
    end

    Logs:new(source, {
        category = "citizens",
        action = "removed_judgment",
        message = ("Removed judgment for citizen %s"):format(data.identifier),
    })
end

function Citizens.deleteNote(self, source, data)
    local profile = self.profiles[data.identifier]
    if not profile then
        return
    end

    for noteIndex, note in pairs(profile.notes) do
        if note.id == data.noteId then
            table.remove(profile.notes, noteIndex)
            break
        end
    end

    MySQL.update("UPDATE p_mdt_citizens SET notes = ? WHERE identifier = ?", {
        json.encode(profile.notes),
        data.identifier,
    })

    Logs:new(source, {
        category = "citizens",
        action = "deleted_note",
        message = ("Deleted note %s for citizen %s"):format(data.noteId, data.identifier),
    })
end

RegisterNetEvent("p_mdt/server/citizens/createNote", function(data)
    Citizens:createNote(source, data)
end)

RegisterNetEvent("p_mdt/server/citizens/deleteNote", function(data)
    Citizens:deleteNote(source, data)
end)

RegisterNetEvent("p_mdt/server/citizens/changeAvatar", function(data)
    Citizens:setCitizenAvatar(source, data)
end)

RegisterNetEvent("p_mdt/server/citizens/deleteLicense", function(data)
    Editable:deleteCitizenLicense(source, data)
end)

RegisterNetEvent("p_mdt/server/citizens/removeJudgment", function(data)
    Citizens:removeJudgment(source, data)
end)

RegisterNetEvent("p_mdt/server/citizens/addLicense", function(data)
    Editable:addCitizenLicense(source, data)
end)
