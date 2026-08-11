Properties = {}

function Properties.sort(self, properties)
    for _, property in ipairs(properties) do
        if property.coords then
            local streetHash = GetStreetNameAtCoord(property.coords.x, property.coords.y, property.coords.z)
            property.location = GetStreetNameFromHashKey(streetHash)
            property.address = property.location
        else
            if not property.location then
                property.location = locale("no_data")
            end
            property.address = property.location
        end
    end
    return properties
end

RegisterNUICallback("mdt/properties/fetch", function(_, cb)
    local data = lib.callback.await("p_mdt/server/properties/fetch", false)
    if data then
        data = Properties:sort(data)
    end
    cb(data)
end)

RegisterNUICallback("mdt/properties/mark", function(data, cb)
    Bridge.Notify.showNotify(locale("property_marked_on_map"), "inform")
    SetNewWaypoint(data.coords.x, data.coords.y)
    cb(1)
end)
