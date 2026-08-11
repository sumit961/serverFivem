Weapons = {}

lib.callback.register("p_mdt/server/weapons/search", function(_, data)
    local query = data.query
    if not query or query == "" or query:len() < 1 then
        return {}
    end

    return MySQL.query.await([[
        SELECT * FROM p_mdt_weapons
        WHERE serial LIKE @query OR model LIKE @query 
        OR JSON_UNQUOTE(JSON_EXTRACT(owner, "$.name")) LIKE @query OR JSON_UNQUOTE(JSON_EXTRACT(owner, "$.id")) LIKE @query
    ]], {
        ["@query"] = "%" .. query .. "%",
    })
end)

function Weapons.register(self, playerSource, data)
    local existing = MySQL.single.await("SELECT * FROM p_mdt_weapons WHERE serial = ?", { data.serial })

    if existing and playerSource then
        Bridge.Notify.showNotify(playerSource, locale("weapon_serial_already_registered"), "error")
        return
    end

    local owner = Bridge.Framework.getOfflinePlayerByUniqueId(data.ownerId)
    if not owner then
        owner = Bridge.Framework.getOfflinePlayerByCitizenId(data.ownerId)
    end

    if not owner and playerSource then
        Bridge.Notify.showNotify(playerSource, locale("weapon_owner_not_found"), "error")
        return
    end

    MySQL.insert(
        "INSERT INTO p_mdt_weapons (serial, model, owner, timestamp, note) VALUES (?, ?, ?, ?, ?)",
        {
            data.serial,
            data.model,
            json.encode({
                name = ("%s %s"):format(owner.firstname, owner.lastname),
                id = data.ownerId,
            }),
            os.time(),
            data.note or nil,
        }
    )

    if playerSource then
        Bridge.Notify.showNotify(playerSource, locale("weapon_registered_successfully"), "success")
    end
end

function Weapons.delete(self, playerSource, data)
    local job = Bridge.Framework.getPlayerJob(playerSource)
    if not Config.Departments[job.name] then
        return
    end

    MySQL.update("DELETE FROM p_mdt_weapons WHERE serial = ?", { data.serial })
    Bridge.Notify.showNotify(playerSource, locale("weapon_deleted_successfully"), "success")
end

RegisterNetEvent("p_mdt/server/weapons/register", function(data)
    Weapons:register(source, data)
end)

RegisterNetEvent("p_mdt/server/weapons/delete", function(data)
    Weapons:delete(source, data)
end)

exports("RegisterWeapon", function(playerSource, data)
    Weapons:register(playerSource, data)
end)
