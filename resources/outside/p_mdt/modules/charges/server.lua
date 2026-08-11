Charges = {
    data = {},
}

CreateThread(function()
    while not MySQL or not MySQL.ready do
        Wait(100)
    end

    local rows = MySQL.query.await("SELECT * FROM p_mdt_charges")

    for _, row in ipairs(rows) do
        Charges.data[row.name] = json.decode(row.charges or "[]")
    end
end)

lib.callback.register("p_mdt/server/charges/fetch", function()
    return Charges.data
end)

RegisterNetEvent("p_mdt/server/charges/createCategory", function(data)
    if not data or not data.name then
        return
    end

    Charges.data[data.name] = {}
    MySQL.insert("INSERT INTO p_mdt_charges (name, charges) VALUES (@name, @charges)", {
        ["@name"] = data.name,
        ["@charges"] = json.encode({}),
    })

    Logs:new(_source, {
        category = "charges",
        action = "create",
        message = ("Created category %s"):format(data.name),
    })
end)

lib.callback.register("p_mdt/server/charges/createCharge", function(playerSource, data)
    if not data or type(data) ~= "table" or not data.category or not data.charge then
        return false
    end

    local categoryCharges = Charges.data[data.category]
    if not categoryCharges then
        return false
    end

    local charge = {
        id = #categoryCharges + 1,
        title = data.charge.title,
        description = data.charge.description or "",
        type = data.charge.type,
        fine = { data.charge.fine[1], data.charge.fine[2] },
        sentence = { data.charge.sentence[1], data.charge.sentence[2] },
    }

    table.insert(categoryCharges, 1, charge)

    MySQL.update("UPDATE p_mdt_charges SET charges = ? WHERE name = ?", {
        json.encode(categoryCharges),
        data.category,
    })

    Logs:new(playerSource, {
        category = "charges",
        action = "create",
        message = ("Created charge %s for category %s"):format(data.charge.title, data.category),
    })

    return Charges.data
end)

RegisterNetEvent("p_mdt/server/charges/deleteCharge", function(data)
    if not data or type(data) ~= "table" or not data.category or not data.id then
        return
    end

    local categoryCharges = Charges.data[data.category]
    if not categoryCharges then
        return
    end

    for index, charge in ipairs(categoryCharges) do
        if charge.id == data.id then
            table.remove(categoryCharges, index)
            break
        end
    end

    MySQL.update("UPDATE p_mdt_charges SET charges = ? WHERE name = ?", {
        json.encode(categoryCharges),
        data.category,
    })
end)

lib.callback.register("p_mdt/server/charges/editCharge", function(playerSource, data)
    if not data or type(data) ~= "table" or not data.category or not data.charge or not data.charge.id then
        return false
    end

    local categoryCharges = Charges.data[data.category]
    if not categoryCharges then
        return false
    end

    for index, charge in ipairs(categoryCharges) do
        if charge.id == data.charge.id then
            categoryCharges[index] = {
                id = charge.id,
                title = data.charge.title,
                description = data.charge.description or "",
                type = data.charge.type,
                fine = { data.charge.fine[1], data.charge.fine[2] },
                sentence = { data.charge.sentence[1], data.charge.sentence[2] },
            }
            break
        end
    end

    MySQL.update("UPDATE p_mdt_charges SET charges = ? WHERE name = ?", {
        json.encode(categoryCharges),
        data.category,
    })

    return Charges.data
end)

RegisterNetEvent("p_mdt/server/charges/deleteCategory", function(data)
    local playerSource = source
    if not data or not data.name then
        return
    end

    if not Charges.data[data.name] then
        return
    end

    Charges.data[data.name] = nil
    MySQL.query("DELETE FROM p_mdt_charges WHERE name = ?", { data.name })

    Logs:new(playerSource, {
        category = "charges",
        action = "delete",
        message = ("Deleted category %s"):format(data.name),
    })
end)
