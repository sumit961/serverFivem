Weapons = {
    cache = {},
}

RegisterNUICallback("mdt/weapons/search", function(data, cb)
    local cached = Weapons.cache[data.query]
    if cached and cached.expire > GetGameTimer() then
        cb(cached.result)
        return
    end

    local results = lib.callback.await("p_mdt/server/weapons/search", false, data)

    for _, weapon in pairs(results) do
        weapon.owner = json.decode(weapon.owner or "{}") or {}
    end

    Weapons.cache[data.query] = {
        result = results,
        expire = GetGameTimer() + 5000,
    }

    cb(results)
end)

RegisterNUICallback("mdt/weapons/register", function(data, cb)
    TriggerServerEvent("p_mdt/server/weapons/register", data)
    cb(1)
end)

RegisterNUICallback("mdt/weapons/delete", function(data, cb)
    TriggerServerEvent("p_mdt/server/weapons/delete", data)
    cb(1)
end)
