Evidences = {
    data = {},
}

CreateThread(function()
    while not MySQL or not MySQL.ready do
        if Bridge and Bridge.Config and Bridge.Config.Debug then
            lib.print.info("Waiting for MySQL to be ready...")
        end
        Wait(500)
    end

    local rows = MySQL.query.await("SELECT * FROM p_mdt_evidences")

    for _, row in ipairs(rows) do
        Evidences.data[row.id] = {
            id = row.id,
            type = row.type,
            title = row.title,
            location = row.location,
            description = row.description,
            itemData = row.itemData and json.decode(row.itemData) or nil,
            mediaUrl = row.mediaUrl,
            timestamp = row.timestamp,
            creator = json.decode(row.creator),
            history = json.decode(row.history),
            status = row.status,
        }
    end
end)

lib.callback.register("p_mdt/server/evidences/fetch", function(source, data)
    return Evidences.data
end)

lib.callback.register("p_mdt/server/evidences/search", function(source, data)
    local results = {}
    local query = data.query:lower()

    for _, evidence in pairs(Evidences.data) do
        local titleMatch = evidence.title:lower():find(query)
        local descriptionMatch = evidence.description:lower():find(query)
        local locationMatch = evidence.location:lower():find(query)

        if titleMatch or descriptionMatch or locationMatch then
            table.insert(results, evidence)
        end
    end

    return results
end)

function Evidences.register(self, source, data)
    local itemSlot = nil

    if data.item then
        itemSlot = Bridge.Inventory.getItemSlot(source, tonumber(data.item)) or nil
    end

    local evidence = {
        type = data.type,
        title = data.title,
        description = data.description,
        location = data.location,
        itemData = itemSlot and json.encode(itemSlot) or nil,
        mediaUrl = data.mediaUrl or data.audioUrl or nil,
        creator = {
            id = Bridge.Framework.getUniqueId(source),
            name = Bridge.Framework.getPlayerName(source),
        },
        history = {},
        status = itemSlot and Config.Evidences.depositType == "physical" and "undeposited" or "deposited",
    }

    local insertId = MySQL.insert.await([[
        INSERT INTO p_mdt_evidences (type, title, description, location, itemData, mediaUrl, creator, status, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        evidence.type,
        evidence.title,
        evidence.description,
        evidence.location,
        evidence.itemData,
        evidence.mediaUrl or nil,
        json.encode(evidence.creator),
        evidence.status,
        os.time(),
    })

    if not insertId then
        return false
    end

    evidence.id = insertId
    Evidences.data[insertId] = evidence

    if itemSlot and Config.Evidences.depositType == "digital" then
        Bridge.Inventory.removeItem(source, itemSlot.name, itemSlot.count, itemSlot.metadata, itemSlot.slot)
    end

    Logs:new(source, {
        category = "evidences",
        action = "registered",
        message = ("Registered new evidence %s with id %s"):format(evidence.title, evidence.id),
    })

    return evidence
end

lib.callback.register("p_mdt/server/evidences/register", function(source, data)
    return Evidences:register(source, data)
end)

RegisterNetEvent("p_mdt/server/evidences/deposit", function(evidenceId)
    local source = source
    local evidence = Evidences.data[evidenceId]

    if not evidence or evidence.status == "deposited" then
        return
    end

    if evidence.itemData then
        local itemData = json.decode(evidence.itemData)
        Bridge.Inventory.removeItem(source, itemData.name, itemData.count, itemData.metadata)
    end

    evidence.status = "deposited"

    MySQL.update.await([[
        UPDATE p_mdt_evidences
        SET status = ?, history = ?
        WHERE id = ?
    ]], {
        evidence.status,
        json.encode(evidence.history),
        evidence.id,
    })

    Logs:new(source, {
        category = "evidences",
        action = "deposited",
        message = ("Deposited evidence %s with id %s"):format(evidence.title, evidence.id),
    })
end)

lib.callback.register("p_mdt/server/evidences/update", function(source, data)
    local evidence = Evidences.data[data.id]
    if not evidence then
        return false
    end

    if not Permissions.hasPerm(source, "evidences.register") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return false
    end

    evidence.title = data.title or evidence.title
    evidence.description = data.description or evidence.description

    MySQL.update.await([[
        UPDATE p_mdt_evidences
        SET title = ?, description = ?
        WHERE id = ?
    ]], {
        evidence.title,
        evidence.description,
        evidence.id,
    })

    Logs:new(source, {
        category = "evidences",
        action = "updated",
        message = ("Updated evidence %s with id %s"):format(evidence.title, evidence.id),
    })

    return evidence
end)

RegisterNetEvent("p_mdt/server/evidences/delete", function(evidenceId)
    local source = source
    local evidence = Evidences.data[evidenceId]

    if not evidence then
        return
    end

    if not Permissions.hasPerm(source, "evidences.remove") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return
    end

    local deleted = MySQL.update.await([[
        DELETE FROM p_mdt_evidences
        WHERE id = ?
    ]], { evidence.id })

    if not deleted then
        return
    end

    if evidence.itemData and evidence.status == "deposited" then
        local itemData = json.decode(evidence.itemData)
        Bridge.Inventory.addItem(source, itemData.name, itemData.count, itemData.metadata)
    end

    Evidences.data[evidenceId] = nil

    Logs:new(source, {
        category = "evidences",
        action = "deleted",
        message = ("Deleted evidence %s with id %s"):format(evidence.title, evidence.id),
    })
end)
